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
DECLARE t uuid := _mk_tenant('E04'); c uuid; inv uuid; det text; ok boolean;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client Q') RETURNING id INTO c;
  PERFORM _as_user();
  INSERT INTO invoices (tenant_id, number, customer_id, customer_name, date, due_date, status, subtotal, vat_total, total, amount_paid, amount_due)
  VALUES (t, 'FAC-2026-042', c, 'Client Q', '2026-03-01', '2026-03-31', 'draft', 1000, 200, 1200, 0, 1200) RETURNING id INTO inv;
  INSERT INTO invoice_lines (tenant_id, invoice_id, description, quantity, unit_price, vat_rate, total, vat_total, line_order)
  VALUES (t, inv, 'Prestation', 1, 1000, 20, 1000, 200, 0);
  BEGIN
    UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
    -- comparaison numérique : depuis la 187, les montants sont en numeric(18,2) (« 1200.00 »)
    SELECT format('D=%s C=%s', sum(debit), sum(credit)), sum(debit) = 1200 AND sum(credit) = 1200 INTO det, ok
    FROM journal_lines jl JOIN invoices i ON i.transferred_entry_id = jl.journal_id WHERE i.id = inv;
    PERFORM _rec('E04', 'facture issue d''un devis validable et comptabilisée (1 200 TTC)', ok, det);
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

-- ============================================================
-- Vague V3 — lot E (AUD-E02 à E11), scénarios écrits avant les correctifs
-- ============================================================

-- Facture de test : en-tête + lignes [{"q":, "p":, "r": taux, "c": code TVA}], validée si demandé
CREATE OR REPLACE FUNCTION _mk_invoice(p_t uuid, p_c uuid, p_date date, p_lines jsonb, p_validate boolean DEFAULT true)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE inv uuid;
BEGIN
  INSERT INTO invoices (tenant_id, number, customer_id, customer_name, date, due_date, status, subtotal, vat_total, total, amount_paid, amount_due)
  VALUES (p_t, 'SAISIE-' || left(uuid_generate_v4()::text, 8), p_c, 'Client', p_date, p_date + 30, 'draft', 0, 0, 0, 0, 0)
  RETURNING id INTO inv;
  INSERT INTO invoice_lines (tenant_id, invoice_id, description, quantity, unit_price, vat_rate, vat_code, total, vat_amount, line_order)
  SELECT p_t, inv, 'Ligne', (x->>'q')::numeric, (x->>'p')::numeric, (x->>'r')::numeric, COALESCE(x->>'c', 'FR20'),
         round((x->>'q')::numeric * (x->>'p')::numeric, 2), round((x->>'q')::numeric * (x->>'p')::numeric * (x->>'r')::numeric / 100, 2), o
  FROM jsonb_array_elements(p_lines) WITH ORDINALITY AS a(x, o);
  -- totaux d'en-tête posés comme le fait l'écran (le serveur les recalcule depuis la 190)
  UPDATE invoices i SET subtotal = s.ht, vat_total = s.tva, total = s.ht + s.tva, amount_due = s.ht + s.tva
  FROM (SELECT sum(total) ht, sum(vat_amount) tva FROM invoice_lines WHERE invoice_id = inv) s
  WHERE i.id = inv;
  IF p_validate THEN UPDATE invoices SET validation_status = 'validated' WHERE id = inv; END IF;
  RETURN inv;
END $$;

-- E10 — AUD-E03 : totaux de ligne et d'en-tête calculés par le serveur
DO $$
DECLARE t uuid := _mk_tenant('E10'); c uuid; inv uuid; l record; h record;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client T') RETURNING id INTO c;
  PERFORM _as_user();
  BEGIN
    INSERT INTO invoices (tenant_id, number, customer_id, customer_name, date, due_date, status, subtotal, vat_total, total, amount_paid, amount_due)
    VALUES (t, 'F-E10', c, 'Client T', '2026-03-01', '2026-03-31', 'draft', 999, 0, 999, 0, 999) RETURNING id INTO inv;
    -- total et TVA de ligne faux à la saisie
    INSERT INTO invoice_lines (tenant_id, invoice_id, description, quantity, unit_price, vat_rate, total, vat_amount)
    VALUES (t, inv, 'X', 2, 150, 20, 1, 0);
    SELECT total, vat_amount INTO l FROM invoice_lines WHERE invoice_id = inv;
    SELECT subtotal, vat_total, total, amount_due INTO h FROM invoices WHERE id = inv;
    PERFORM _rec('E10', 'ligne 2 × 150 à 20 % → 300 + 60 ; en-tête 300 / 60 / 360 recalculé',
      l.total = 300 AND l.vat_amount = 60 AND h.subtotal = 300 AND h.vat_total = 60 AND h.total = 360 AND h.amount_due = 360,
      format('ligne %s/%s en-tête %s/%s/%s dû %s', l.total, l.vat_amount, h.subtotal, h.vat_total, h.total, h.amount_due));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('E10', 'ligne 2 × 150 à 20 % → 300 + 60 ; en-tête 300 / 60 / 360 recalculé', false, SQLERRM); END;
END $$;

-- E11 — AUD-E03 : une facture validée est figée (lignes et montants)
DO $$
DECLARE t uuid := _mk_tenant('E11'); c uuid; inv uuid; ok_l boolean := false; ok_h boolean := false; tot numeric;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client F') RETURNING id INTO c;
  PERFORM _as_user();
  BEGIN
    inv := _mk_invoice(t, c, '2026-03-01', '[{"q":1,"p":100,"r":20}]');
    BEGIN UPDATE invoice_lines SET unit_price = 1 WHERE invoice_id = inv; EXCEPTION WHEN OTHERS THEN ok_l := true; END;
    BEGIN UPDATE invoices SET total = 1 WHERE id = inv; EXCEPTION WHEN OTHERS THEN ok_h := true; END;
    SELECT total INTO tot FROM invoices WHERE id = inv;
    PERFORM _rec('E11', 'facture validée : lignes et montants non modifiables', ok_l AND ok_h AND tot = 120,
      format('ligne refusée=%s en-tête refusé=%s total=%s', ok_l, ok_h, tot));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('E11', 'facture validée : lignes et montants non modifiables', false, SQLERRM); END;
END $$;

-- E12 — AUD-E04 : numéro définitif à la validation, continu, par exercice
DO $$
DECLARE t uuid := _mk_tenant('E12'); c uuid; a uuid; b uuid; v uuid; d uuid; n27 uuid; na text; nb text; nd text; n27s text; draft_no text;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client N') RETURNING id INTO c;
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status) VALUES (t, '2027', '2027-01-01', '2027-12-31', 'open');
  PERFORM _as_user();
  BEGIN
    a := _mk_invoice(t, c, '2026-03-01', '[{"q":1,"p":100,"r":20}]', false);
    b := _mk_invoice(t, c, '2026-03-02', '[{"q":1,"p":100,"r":20}]', false);
    SELECT number INTO draft_no FROM invoices WHERE id = a;
    UPDATE invoices SET validation_status = 'validated' WHERE id = b;
    UPDATE invoices SET validation_status = 'validated' WHERE id = a;
    -- une validation refusée (facture sans ligne) ne consomme pas de numéro
    INSERT INTO invoices (tenant_id, number, customer_id, customer_name, date, due_date, status)
    VALUES (t, 'VIDE', c, 'Client N', '2026-03-03', '2026-03-03', 'draft') RETURNING id INTO v;
    BEGIN UPDATE invoices SET validation_status = 'validated' WHERE id = v; EXCEPTION WHEN OTHERS THEN NULL; END;
    d := _mk_invoice(t, c, '2026-03-04', '[{"q":1,"p":100,"r":20}]');
    n27 := _mk_invoice(t, c, '2027-02-01', '[{"q":1,"p":100,"r":20}]');
    SELECT number INTO nb FROM invoices WHERE id = b;
    SELECT number INTO na FROM invoices WHERE id = a;
    SELECT number INTO nd FROM invoices WHERE id = d;
    SELECT number INTO n27s FROM invoices WHERE id = n27;
    PERFORM _rec('E12', 'numéros FAC-2026-000001/2/3 dans l''ordre de validation, FAC-2027-000001, brouillon provisoire',
      nb = 'FAC-2026-000001' AND na = 'FAC-2026-000002' AND nd = 'FAC-2026-000003' AND n27s = 'FAC-2027-000001'
        AND draft_no NOT LIKE 'FAC-%',
      format('b=%s a=%s d=%s 2027=%s brouillon=%s', nb, na, nd, n27s, draft_no));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('E12', 'numéros FAC-2026-000001/2/3 dans l''ordre de validation, FAC-2027-000001, brouillon provisoire', false, SQLERRM); END;
END $$;

-- E13 — AUD-E04 : 1 000 validations → 1 000 numéros consécutifs distincts
DO $$
DECLARE t uuid := _mk_tenant('E13'); c uuid; n int; nd int; mx int;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client M') RETURNING id INTO c;
  PERFORM _as_user();
  BEGIN
    FOR i IN 1..1000 LOOP
      PERFORM _mk_invoice(t, c, DATE '2026-01-01' + (i % 300), '[{"q":1,"p":10,"r":20}]');
    END LOOP;
    SELECT count(*), count(DISTINCT number), max(substring(number FROM '(\d+)$')::int)
      INTO n, nd, mx FROM invoices WHERE tenant_id = t AND number LIKE 'FAC-2026-%';
    PERFORM _rec('E13', '1 000 validations → FAC-2026-000001 à 001000 sans trou ni doublon', n = 1000 AND nd = 1000 AND mx = 1000,
      format('numéros=%s distincts=%s max=%s', n, nd, mx));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('E13', '1 000 validations → FAC-2026-000001 à 001000 sans trou ni doublon', false, SQLERRM); END;
END $$;

-- E14 — AUD-E05 : conversion devis → facture par le serveur
DO $$
DECLARE t uuid := _mk_tenant('E14'); c uuid; q uuid; r jsonb; inv uuid; h record; d numeric; cr numeric; qs text;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client DV') RETURNING id INTO c;
  PERFORM _as_user();
  BEGIN
    INSERT INTO quotes (tenant_id, number, customer_id, customer_name, date, expiry_date, status, subtotal, vat_total, total)
    VALUES (t, 'DEV-E14', c, 'Client DV', '2026-03-01', '2026-03-31', 'sent', 1500, 227.5, 1727.5) RETURNING id INTO q;
    INSERT INTO quote_lines (tenant_id, quote_id, description, quantity, unit_price, vat_rate, total, vat_total, line_order) VALUES
      (t, q, 'A', 1, 1000, 20, 1000, 200, 0), (t, q, 'B', 1, 500, 5.5, 500, 27.5, 1);
    r := convert_quote_to_invoice(q);
    inv := (r->>'invoice_id')::uuid;
    SELECT subtotal, vat_total, total, quote_id INTO h FROM invoices WHERE id = inv;
    SELECT transformation_status INTO qs FROM quotes WHERE id = q;
    UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
    SELECT sum(jl.debit), sum(jl.credit) INTO d, cr FROM journal_lines jl JOIN invoices i ON i.transferred_entry_id = jl.journal_id WHERE i.id = inv;
    PERFORM _rec('E14', 'convert_quote_to_invoice : facture 1 500 + 227,5 liée au devis, validée et équilibrée',
      h.subtotal = 1500 AND h.vat_total = 227.5 AND h.total = 1727.5 AND h.quote_id = q AND qs = 'transformed' AND d = 1727.5 AND cr = 1727.5,
      format('%s | en-tête %s/%s/%s devis=%s D=%s C=%s', r, h.subtotal, h.vat_total, h.total, qs, d, cr));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('E14', 'convert_quote_to_invoice : facture 1 500 + 227,5 liée au devis, validée et équilibrée', false, SQLERRM); END;
END $$;

-- E15 — AUD-E07 : avoir sur facture → écriture inverse, numéro AV, lettrage avec la facture
DO $$
DECLARE t uuid := _mk_tenant('E15'); c uuid; inv uuid; cn uuid; e uuid; d7 numeric; dt numeric; c411 numeric; tiers text; num text; due numeric; codes int; lettre int;
BEGIN
  INSERT INTO customers (tenant_id, name, account_tiers) VALUES (t, 'Client AV', 'C0015') RETURNING id INTO c;
  PERFORM _as_user();
  BEGIN
    inv := _mk_invoice(t, c, '2026-03-01', '[{"q":1,"p":1000,"r":20}]');
    INSERT INTO credit_notes (tenant_id, number, customer_id, customer_name, date, status, subtotal, vat_total, total, invoice_id, reason)
    VALUES (t, 'AV-SAISIE', c, 'Client AV', '2026-03-10', 'draft', 0, 0, 0, inv, 'Retour') RETURNING id INTO cn;
    INSERT INTO credit_note_lines (tenant_id, credit_note_id, description, quantity, unit_price, vat_rate, total, vat_total)
    VALUES (t, cn, 'Retour', 1, 1000, 20, 1000, 200);
    UPDATE credit_notes SET status = 'validated' WHERE id = cn;
    SELECT transferred_entry_id, number INTO e, num FROM credit_notes WHERE id = cn;
    SELECT sum(debit) FILTER (WHERE account_code ~ '^7'), sum(debit) FILTER (WHERE account_code ~ '^445'),
           sum(credit) FILTER (WHERE account_code ~ '^411'), max(account_tiers) FILTER (WHERE account_code ~ '^411')
      INTO d7, dt, c411, tiers FROM journal_lines WHERE journal_id = e;
    SELECT amount_due INTO due FROM invoices WHERE id = inv;
    SELECT count(DISTINCT lettrage_code), count(*) FILTER (WHERE lettrage_code IS NOT NULL) INTO codes, lettre
    FROM journal_lines WHERE tenant_id = t AND account_code ~ '^411';
    PERFORM _rec('E15', 'avoir validé : D 7xx 1 000 + D 445 200 = C 411 1 200 (auxiliaire), AV-2026-000001, facture soldée et lettrée',
      d7 = 1000 AND dt = 200 AND c411 = 1200 AND tiers = 'C0015' AND num = 'AV-2026-000001' AND due = 0 AND codes = 1 AND lettre = 2,
      format('D7=%s D445=%s C411=%s tiers=%s n°=%s dû=%s lettrage=%s code(s)/%s ligne(s)', d7, dt, c411, tiers, num, due, codes, lettre));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('E15', 'avoir validé : D 7xx 1 000 + D 445 200 = C 411 1 200 (auxiliaire), AV-2026-000001, facture soldée et lettrée', false, SQLERRM); END;
END $$;

-- E16 — AUD-E07 : un avoir sans facture ni client n'est pas validable
-- (témoin : le même avoir rattaché au client l'est — sans lui, le test passerait
-- tant que le statut « validated » n'existe pas)
DO $$
DECLARE t uuid := _mk_tenant('E16'); c uuid; cn uuid; cw uuid; st text; stw text;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client O') RETURNING id INTO c;
  PERFORM _as_user();
  BEGIN
    INSERT INTO credit_notes (tenant_id, number, customer_name, date, status, subtotal, vat_total, total)
    VALUES (t, 'AV-ORPHELIN', 'Inconnu', '2026-03-10', 'draft', 100, 20, 120) RETURNING id INTO cn;
    INSERT INTO credit_notes (tenant_id, number, customer_id, customer_name, date, status, subtotal, vat_total, total)
    VALUES (t, 'AV-TEMOIN', c, 'Client O', '2026-03-10', 'draft', 100, 20, 120) RETURNING id INTO cw;
    BEGIN UPDATE credit_notes SET status = 'validated' WHERE id = cn; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN UPDATE credit_notes SET status = 'validated' WHERE id = cw; EXCEPTION WHEN OTHERS THEN NULL; END;
    SELECT status INTO st FROM credit_notes WHERE id = cn;
    SELECT status INTO stw FROM credit_notes WHERE id = cw;
    PERFORM _rec('E16', 'avoir sans facture ni client refusé (témoin rattaché au client : validé)', st = 'draft' AND stw = 'validated',
      format('orphelin=%s témoin=%s', st, stw));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('E16', 'avoir sans facture ni client refusé (témoin rattaché au client : validé)', false, SQLERRM); END;
END $$;

-- E17 — AUD-E08 : trop-perçu porté en avance client 4191, avec auxiliaire
DO $$
DECLARE t uuid := _mk_tenant('E17'); c uuid; inv uuid; e uuid; d512 numeric; c411 numeric; c419 numeric; tiers text; st text; due numeric;
BEGIN
  INSERT INTO customers (tenant_id, name, account_tiers) VALUES (t, 'Client TP', 'C0017') RETURNING id INTO c;
  PERFORM _as_user();
  BEGIN
    inv := _mk_invoice(t, c, '2026-03-01', '[{"q":1,"p":100,"r":20}]');
    INSERT INTO customer_payments (tenant_id, number, customer_id, invoice_id, payment_date, amount, method)
    VALUES (t, 'RG-E17', c, inv, '2026-03-05', 200, 'transfer');
    SELECT transferred_entry_id INTO e FROM customer_payments WHERE tenant_id = t AND number = 'RG-E17';
    SELECT sum(debit), sum(credit) FILTER (WHERE account_code ~ '^411'), sum(credit) FILTER (WHERE account_code = '419100'),
           max(account_tiers) FILTER (WHERE account_code = '419100')
      INTO d512, c411, c419, tiers FROM journal_lines WHERE journal_id = e;
    SELECT status, amount_due INTO st, due FROM invoices WHERE id = inv;
    PERFORM _rec('E17', 'paiement 200 sur 120 dû : D 512 200 = C 411 120 + C 4191 80 (auxiliaire), facture payée',
      d512 = 200 AND c411 = 120 AND c419 = 80 AND tiers = 'C0017' AND st = 'paid' AND due = 0,
      format('D=%s C411=%s C4191=%s tiers=%s statut=%s dû=%s', d512, c411, c419, tiers, st, due));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('E17', 'paiement 200 sur 120 dû : D 512 200 = C 411 120 + C 4191 80 (auxiliaire), facture payée', false, SQLERRM); END;
END $$;

-- E18 — AUD-E09 : compte et journal de trésorerie selon le compte bancaire ou le mode
DO $$
DECLARE t uuid := _mk_tenant('E18'); c uuid; b1 uuid; b2 uuid; acc2 text; jr2 text; e uuid; cash_acc text; cash_j text; bk_acc text; bk_j text; in_plan boolean;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client TR') RETURNING id INTO c;
  PERFORM ensure_standard_journals(t);
  PERFORM _as_user();
  BEGIN
    INSERT INTO customer_payments (tenant_id, number, customer_id, payment_date, amount, method)
    VALUES (t, 'RG-ESP', c, '2026-03-05', 50, 'cash');
    SELECT transferred_entry_id INTO e FROM customer_payments WHERE tenant_id = t AND number = 'RG-ESP';
    SELECT jl.account_code, je.journal_code INTO cash_acc, cash_j FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id WHERE jl.journal_id = e AND jl.debit > 0;

    INSERT INTO bank_accounts (tenant_id, name, type) VALUES (t, 'Banque principale', 'chequing') RETURNING id INTO b1;
    INSERT INTO bank_accounts (tenant_id, name, type) VALUES (t, 'Seconde banque', 'chequing') RETURNING id INTO b2;
    EXECUTE 'SELECT account_code, journal_code FROM bank_accounts WHERE id = $1' INTO acc2, jr2 USING b2;
    INSERT INTO customer_payments (tenant_id, number, customer_id, payment_date, amount, method, bank_account_id)
    VALUES (t, 'RG-BQ2', c, '2026-03-06', 70, 'transfer', b2);
    SELECT transferred_entry_id INTO e FROM customer_payments WHERE tenant_id = t AND number = 'RG-BQ2';
    SELECT jl.account_code, je.journal_code INTO bk_acc, bk_j FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id WHERE jl.journal_id = e AND jl.debit > 0;
    in_plan := EXISTS (SELECT 1 FROM chart_accounts WHERE tenant_id = t AND code = acc2);
    PERFORM _rec('E18', 'espèces → 530 / CA ; 2e compte bancaire → son propre compte 512x et son journal',
      cash_acc = '530000' AND cash_j = 'CA' AND bk_acc = acc2 AND bk_j = jr2 AND acc2 <> '512000' AND jr2 <> 'BQ' AND in_plan,
      format('espèces %s/%s ; banque 2 %s/%s (attendu %s/%s, au plan=%s)', cash_acc, cash_j, bk_acc, bk_j, acc2, jr2, in_plan));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('E18', 'espèces → 530 / CA ; 2e compte bancaire → son propre compte 512x et son journal', false, SQLERRM); END;
END $$;

-- E19 — AUD-E10 : lettrage automatique facture ↔ règlements quand la facture est soldée
DO $$
DECLARE t uuid := _mk_tenant('E19'); c uuid; inv uuid; after1 int; codes int; lettre int; d numeric; cr numeric;
BEGIN
  INSERT INTO customers (tenant_id, name, account_tiers) VALUES (t, 'Client L', 'C0019') RETURNING id INTO c;
  PERFORM _as_user();
  BEGIN
    inv := _mk_invoice(t, c, '2026-03-01', '[{"q":1,"p":100,"r":20}]');
    INSERT INTO customer_payments (tenant_id, number, customer_id, invoice_id, payment_date, amount, method)
    VALUES (t, 'RG-L1', c, inv, '2026-03-05', 50, 'transfer');
    SELECT count(*) INTO after1 FROM journal_lines WHERE tenant_id = t AND account_code ~ '^411' AND lettrage_code IS NOT NULL;
    INSERT INTO customer_payments (tenant_id, number, customer_id, invoice_id, payment_date, amount, method)
    VALUES (t, 'RG-L2', c, inv, '2026-03-06', 70, 'transfer');
    SELECT count(DISTINCT lettrage_code), count(*) FILTER (WHERE lettrage_code IS NOT NULL),
           sum(debit) FILTER (WHERE lettrage_code IS NOT NULL), sum(credit) FILTER (WHERE lettrage_code IS NOT NULL)
      INTO codes, lettre, d, cr FROM journal_lines WHERE tenant_id = t AND account_code ~ '^411';
    PERFORM _rec('E19', 'acompte partiel non lettré ; au solde, facture + 2 règlements lettrés ensemble (120 = 120)',
      after1 = 0 AND codes = 1 AND lettre = 3 AND d = 120 AND cr = 120,
      format('après 1er=%s ; code(s)=%s lignes=%s D=%s C=%s', after1, codes, lettre, d, cr));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('E19', 'acompte partiel non lettré ; au solde, facture + 2 règlements lettrés ensemble (120 = 120)', false, SQLERRM); END;
END $$;

-- E20 — AUD-E11 : l'écriture de vente porte le numéro de journal VT et le numéro de facture définitif
DO $$
DECLARE t uuid := _mk_tenant('E20'); c uuid; inv uuid; pn text; ref text; num text;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client J') RETURNING id INTO c;
  PERFORM _as_user();
  BEGIN
    inv := _mk_invoice(t, c, '2026-03-01', '[{"q":1,"p":100,"r":20}]');
    SELECT je.posting_number, je.invoice_ref, i.number INTO pn, ref, num
    FROM invoices i JOIN journal_entries je ON je.id = i.transferred_entry_id WHERE i.id = inv;
    PERFORM _rec('E20', 'écriture VT-2026-000001, invoice_ref = FAC-2026-000001',
      pn = 'VT-2026-000001' AND ref = num AND num = 'FAC-2026-000001', format('écriture=%s ref=%s facture=%s', pn, ref, num));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('E20', 'écriture VT-2026-000001, invoice_ref = FAC-2026-000001', false, SQLERRM); END;
END $$;

-- E21 — une facture ne s'envoie qu'une fois validée (sinon le client reçoit un
-- document au numéro provisoire, sans écriture) ; témoin : validée, elle s'envoie
DO $$
DECLARE t uuid := _mk_tenant('E21'); c uuid; d uuid; v uuid; sd text; sv text;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client S') RETURNING id INTO c;
  PERFORM _as_user();
  BEGIN
    d := _mk_invoice(t, c, '2026-03-01', '[{"q":1,"p":100,"r":20}]', false);
    v := _mk_invoice(t, c, '2026-03-01', '[{"q":1,"p":100,"r":20}]');
    BEGIN UPDATE invoices SET status = 'sent' WHERE id = d; EXCEPTION WHEN OTHERS THEN NULL; END;
    UPDATE invoices SET status = 'sent' WHERE id = v;
    SELECT status INTO sd FROM invoices WHERE id = d;
    SELECT status INTO sv FROM invoices WHERE id = v;
    PERFORM _rec('E21', 'brouillon non envoyable ; facture validée envoyée', sd = 'draft' AND sv = 'sent',
      format('brouillon=%s validée=%s', sd, sv));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('E21', 'brouillon non envoyable ; facture validée envoyée', false, SQLERRM); END;
END $$;

-- E22 — le payé d'une facture ne se saisit pas à la main : seul un règlement
-- (écriture de trésorerie) le fait évoluer
DO $$
DECLARE t uuid := _mk_tenant('E22'); c uuid; v uuid; r record;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client MP') RETURNING id INTO c;
  PERFORM _as_user();
  BEGIN
    v := _mk_invoice(t, c, '2026-03-01', '[{"q":1,"p":100,"r":20}]');
    BEGIN UPDATE invoices SET status = 'paid', amount_paid = 120, amount_due = 0 WHERE id = v; EXCEPTION WHEN OTHERS THEN NULL; END;
    SELECT status, amount_paid, amount_due INTO r FROM invoices WHERE id = v;
    PERFORM _rec('E22', '« payée » sans règlement refusé : payé 0, reste 120', r.amount_paid = 0 AND r.amount_due = 120 AND r.status <> 'paid',
      format('statut=%s payé=%s reste=%s', r.status, r.amount_paid, r.amount_due));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('E22', '« payée » sans règlement refusé : payé 0, reste 120', false, SQLERRM); END;
END $$;

SELECT _audit_assert('180');
