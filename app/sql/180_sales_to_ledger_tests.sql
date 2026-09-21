-- ============================================================
-- 180_sales_to_ledger_tests.sql — AUD-A01, lot E du plan correctif
--
-- Chaîne gestion commerciale → comptabilité, avec les charges utiles
-- exactes qu'envoie le front (sales.ts, InvoicesPage.tsx).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '180', false);
DELETE FROM _audit_results WHERE file = '180';

-- E01 à E03 — création par la RPC de l'écran Factures, puis validation multi-taux
DO $$
DECLARE t uuid := _mk_tenant('E01'); c uuid; inv uuid; r jsonb; e uuid; d numeric; cr numeric; tva numeric; tiers text; n int;
BEGIN
  INSERT INTO customers (tenant_id, name, account_tiers) VALUES (t, 'Client E', 'C0001') RETURNING id INTO c;
  PERFORM _as_user();
  -- charge utile de sales.ts:createInvoice (pas d'id, pas de created_at)
  r := create_invoice_atomic(
    jsonb_build_object('number', 'F-E01', 'customer_id', c, 'customer_name', 'Client E', 'date', '2026-03-01', 'due_date', '2026-03-31',
      'status', 'draft', 'subtotal', 1500, 'vat_total', 227.5, 'total', 1727.5, 'amount_paid', 0, 'amount_due', 1727.5, 'tenant_id', t),
    '[{"description":"A","quantity":1,"unit_price":1000,"vat_rate":20,"total":1000,"vat_code":"FR20","vat_amount":200,"line_order":0},
      {"description":"B","quantity":1,"unit_price":500,"vat_rate":5.5,"total":500,"vat_code":"FR055","vat_amount":27.5,"line_order":1}]');
  PERFORM _rec('E01', 'create_invoice_atomic crée la facture (charge utile du front)', COALESCE((r->>'success')::boolean, false), r::text);

  IF COALESCE((r->>'success')::boolean, false) THEN
    inv := (r->>'invoice_id')::uuid;
  ELSE
    -- la suite du scénario ne doit pas dépendre d'E01
    INSERT INTO invoices (tenant_id, number, customer_id, customer_name, date, due_date, status, subtotal, vat_total, total, amount_paid, amount_due)
    VALUES (t, 'F-E01', c, 'Client E', '2026-03-01', '2026-03-31', 'draft', 1500, 227.5, 1727.5, 0, 1727.5) RETURNING id INTO inv;
    INSERT INTO invoice_lines (tenant_id, invoice_id, description, quantity, unit_price, vat_rate, total, vat_code, vat_amount) VALUES
      (t, inv, 'A', 1, 1000, 20, 1000, 'FR20', 200), (t, inv, 'B', 1, 500, 5.5, 500, 'FR055', 27.5);
  END IF;

  BEGIN
    UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
    SELECT transferred_entry_id INTO e FROM invoices WHERE id = inv;
    SELECT sum(debit), sum(credit), count(*) INTO d, cr, n FROM journal_lines WHERE journal_id = e;
    SELECT sum(credit) INTO tva FROM journal_lines WHERE journal_id = e AND account_code ~ '^445';
    SELECT account_tiers INTO tiers FROM journal_lines WHERE journal_id = e AND debit > 0;
    PERFORM _rec('E02', 'validation → VT : D 411 1 727,5 = C 7xx 1 500 + C 445 227,5',
      d = 1727.5 AND cr = 1727.5 AND tva = 227.5, format('D=%s C=%s TVA=%s lignes=%s', d, cr, tva, n));
    PERFORM _rec('E03', 'la ligne client porte le compte auxiliaire', tiers = 'C0001', 'account_tiers=' || COALESCE(tiers, '∅'));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('E02', 'validation → VT : D 411 1 727,5 = C 7xx 1 500 + C 445 227,5', false, SQLERRM);
    PERFORM _rec('E03', 'la ligne client porte le compte auxiliaire', false, 'validation impossible');
  END;
END $$;

-- E04 — facture issue d'un devis (champs exacts de sales.ts:convertQuoteToInvoice)
DO $$
DECLARE t uuid := _mk_tenant('E04'); c uuid; inv uuid; det text;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client Q') RETURNING id INTO c;
  PERFORM _as_user();
  INSERT INTO invoices (tenant_id, number, customer_id, customer_name, date, due_date, status, subtotal, vat_total, total, amount_paid, amount_due)
  VALUES (t, 'FAC-2026-042', c, 'Client Q', '2026-03-01', '2026-03-31', 'draft', 1000, 200, 1200, 0, 1200) RETURNING id INTO inv;
  INSERT INTO invoice_lines (tenant_id, invoice_id, description, quantity, unit_price, vat_rate, total, vat_total, line_order)
  VALUES (t, inv, 'Prestation', 1, 1000, 20, 1000, 200, 0);
  BEGIN
    UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
    SELECT format('D=%s C=%s', sum(debit), sum(credit)) INTO det
    FROM journal_lines jl JOIN invoices i ON i.transferred_entry_id = jl.journal_id WHERE i.id = inv;
    PERFORM _rec('E04', 'facture issue d''un devis validable et comptabilisée (1 200 TTC)', det = 'D=1200 C=1200', det);
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('E04', 'facture issue d''un devis validable et comptabilisée (1 200 TTC)', false, SQLERRM); END;
END $$;

-- E05 — une facture sans ligne n'est pas validable, et reste en brouillon
DO $$
DECLARE t uuid := _mk_tenant('E05'); c uuid; inv uuid; vs text;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client V') RETURNING id INTO c;
  PERFORM _as_user();
  INSERT INTO invoices (tenant_id, number, customer_id, customer_name, date, due_date, status, subtotal, vat_total, total, amount_paid, amount_due)
  VALUES (t, 'F-VIDE', c, 'Client V', '2026-03-01', '2026-03-01', 'draft', 0, 0, 0, 0, 0) RETURNING id INTO inv;
  BEGIN
    UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
  EXCEPTION WHEN OTHERS THEN NULL; END;
  SELECT validation_status INTO vs FROM invoices WHERE id = inv;
  PERFORM _rec('E05', 'facture sans ligne non validable', vs IS DISTINCT FROM 'validated', 'validation_status=' || COALESCE(vs, '∅'));
END $$;

-- E06 — un avoir client appliqué produit une écriture
DO $$
DECLARE t uuid := _mk_tenant('E06'); c uuid; cn uuid; n0 int; n1 int;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client AV') RETURNING id INTO c;
  PERFORM _as_user();
  SELECT count(*) INTO n0 FROM journal_entries WHERE tenant_id = t;
  BEGIN
    INSERT INTO credit_notes (tenant_id, number, customer_id, customer_name, date, status, subtotal, vat_total, total)
    VALUES (t, 'AV-1', c, 'Client AV', '2026-03-01', 'draft', 100, 20, 120) RETURNING id INTO cn;
    UPDATE credit_notes SET status = 'applied' WHERE id = cn;
    SELECT count(*) INTO n1 FROM journal_entries WHERE tenant_id = t AND status = 'posted';
    PERFORM _rec('E06', 'avoir client appliqué → écriture d''avoir', n1 > n0, format('écritures validées avant=%s après=%s', n0, n1));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('E06', 'avoir client appliqué → écriture d''avoir', false, SQLERRM); END;
END $$;

-- E07 et E08 — encaissement, puis trop-perçu
DO $$
DECLARE t uuid := _mk_tenant('E07'); c uuid; inv uuid; e uuid; tiers text; due numeric;
BEGIN
  INSERT INTO customers (tenant_id, name, account_tiers) VALUES (t, 'Client P', 'C0002') RETURNING id INTO c;
  PERFORM _as_user();
  INSERT INTO invoices (tenant_id, number, customer_id, customer_name, date, due_date, status, subtotal, vat_total, total, amount_paid, amount_due)
  VALUES (t, 'F-P1', c, 'Client P', '2026-03-01', '2026-03-31', 'sent', 100, 20, 120, 0, 120) RETURNING id INTO inv;
  BEGIN
    INSERT INTO customer_payments (tenant_id, number, customer_id, invoice_id, payment_date, amount, method)
    VALUES (t, 'RG-1', c, inv, '2026-03-05', 120, 'transfer');
    SELECT transferred_entry_id INTO e FROM customer_payments WHERE number = 'RG-1' AND tenant_id = t;
    SELECT account_tiers INTO tiers FROM journal_lines WHERE journal_id = e AND credit > 0;
    PERFORM _rec('E07', 'encaissement → écriture BQ avec auxiliaire client', tiers = 'C0002', 'account_tiers=' || COALESCE(tiers, '∅'));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('E07', 'encaissement → écriture BQ avec auxiliaire client', false, SQLERRM); END;
  -- Trop-perçu : refusé, OU porté en avance client (419x) — décision n° 1 du plan
  BEGIN
    INSERT INTO customer_payments (tenant_id, number, customer_id, invoice_id, payment_date, amount, method)
    VALUES (t, 'RG-2', c, inv, '2026-03-06', 500, 'transfer');
    SELECT amount_due INTO due FROM invoices WHERE id = inv;
    PERFORM _rec('E08', 'trop-perçu refusé ou porté en avance client',
      EXISTS (SELECT 1 FROM journal_lines WHERE tenant_id = t AND account_code ~ '^419' AND credit = 500),
      'accepté sans avance client ; amount_due=' || due);
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('E08', 'trop-perçu refusé ou porté en avance client', true, SQLERRM); END;
END $$;

-- E09 — les autres RPC composées partagent le même mécanisme (devis)
DO $$
DECLARE t uuid := _mk_tenant('E09'); c uuid; r jsonb; n int; hdr_tid uuid;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client D') RETURNING id INTO c;
  PERFORM _as_user();
  -- un tenant_id et un id fournis par le client doivent être ignorés
  r := create_quote_atomic(
    jsonb_build_object('id', '00000000-0000-0000-0000-0000000000aa', 'tenant_id', '00000000-0000-0000-0000-0000000000bb',
      'number', 'DEV-E09', 'customer_id', c, 'customer_name', 'Client D', 'date', '2026-03-01', 'expiry_date', '2026-03-31',
      'subtotal', 100, 'vat_total', 20, 'total', 120),
    '[{"description":"Ligne 1","quantity":1,"unit_price":100,"total":100}]');
  SELECT count(*) INTO n FROM quote_lines WHERE quote_id = (r->>'quote_id')::uuid;
  SELECT tenant_id INTO hdr_tid FROM quotes WHERE id = (r->>'quote_id')::uuid;
  PERFORM _rec('E09', 'create_quote_atomic : devis + 1 ligne, id et tenant imposés par le serveur',
    COALESCE((r->>'success')::boolean, false) AND n = 1 AND hdr_tid = t
      AND (r->>'quote_id') <> '00000000-0000-0000-0000-0000000000aa',
    format('%s | lignes=%s tenant=%s', r, n, CASE WHEN hdr_tid = t THEN 'le sien' ELSE COALESCE(hdr_tid::text, '∅') END));
END $$;

SELECT _audit_assert('180');
