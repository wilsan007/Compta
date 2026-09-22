-- ============================================================
-- 192_purchases_treasury_tests.sql — lot G du plan correctif (vague V3)
--
-- AUD-G01 : audit par exécution des achats, sur le modèle du lot E :
-- facture fournisseur → écriture AC (401 auxiliaire, 6xx, 4456x multi-taux),
-- avoir fournisseur, règlement, trop-payé, numérotation (AUD-G02).
-- Décision n° 1 du plan (trop-perçu client → 4191) appliquée symétriquement :
-- un trop-payé fournisseur est porté en avance fournisseur (4091).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '192', false);
DELETE FROM _audit_results WHERE file = '192';

-- Facture fournisseur : lignes [{"q":, "p":, "r":, "c":}], en-tête posé comme l'écran, approuvée si demandé
CREATE OR REPLACE FUNCTION _mk_purchase(p_t uuid, p_s uuid, p_date date, p_lines jsonb, p_approve boolean DEFAULT true)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE pi uuid;
BEGIN
  INSERT INTO purchase_invoices (tenant_id, number, supplier_id, supplier_name, date, due_date, status, subtotal, vat_total, total, amount_paid, amount_due, approval_status)
  VALUES (p_t, 'FOURN-' || left(uuid_generate_v4()::text, 8), p_s, 'Fournisseur', p_date, p_date + 30, 'draft', 0, 0, 0, 0, 0, 'pending')
  RETURNING id INTO pi;
  INSERT INTO purchase_invoice_lines (tenant_id, purchase_invoice_id, description, quantity, unit_price, vat_rate, vat_code, total, vat_amount, line_order)
  SELECT p_t, pi, 'Achat', (x->>'q')::numeric, (x->>'p')::numeric, (x->>'r')::numeric, COALESCE(x->>'c', 'FR20'),
         round((x->>'q')::numeric * (x->>'p')::numeric, 2), round((x->>'q')::numeric * (x->>'p')::numeric * (x->>'r')::numeric / 100, 2), o
  FROM jsonb_array_elements(p_lines) WITH ORDINALITY AS a(x, o);
  UPDATE purchase_invoices i SET subtotal = s.ht, vat_total = s.tva, total = s.ht + s.tva, amount_due = s.ht + s.tva
  FROM (SELECT sum(total) ht, sum(vat_amount) tva FROM purchase_invoice_lines WHERE purchase_invoice_id = pi) s
  WHERE i.id = pi;
  IF p_approve THEN UPDATE purchase_invoices SET approval_status = 'approved' WHERE id = pi; END IF;
  RETURN pi;
END $$;

-- A01 — facture fournisseur multi-taux → écriture AC équilibrée, 401 avec auxiliaire
DO $$
DECLARE t uuid := _mk_tenant('A01'); s uuid; pi uuid; e uuid; v record;
BEGIN
  INSERT INTO suppliers (tenant_id, name, account_tiers) VALUES (t, 'Fournisseur A', 'F0001') RETURNING id INTO s;
  PERFORM _as_user();
  BEGIN
    pi := _mk_purchase(t, s, '2026-03-01', '[{"q":1,"p":1000,"r":20},{"q":1,"p":200,"r":5.5,"c":"FR055"}]');
    SELECT transferred_entry_id INTO e FROM purchase_invoices WHERE id = pi;
    SELECT sum(debit) FILTER (WHERE account_code ~ '^6') d6, sum(debit) FILTER (WHERE account_code ~ '^4456') d4456,
           count(DISTINCT account_code) FILTER (WHERE account_code ~ '^4456') n4456,
           sum(credit) FILTER (WHERE account_code ~ '^401') c401, max(account_tiers) FILTER (WHERE account_code ~ '^401') tiers,
           sum(debit) d, sum(credit) c
      INTO v FROM journal_lines WHERE journal_id = e;
    PERFORM _rec('A01', 'facture 1 200 HT (20 % et 5,5 %) → D 6 1 200 + D 4456 211 (2 comptes) = C 401 1 411 (auxiliaire)',
      v.d6 = 1200 AND v.d4456 = 211 AND v.n4456 = 2 AND v.c401 = 1411 AND v.tiers = 'F0001' AND v.d = v.c,
      format('D6=%s D4456=%s (%s comptes) C401=%s tiers=%s D=%s C=%s', v.d6, v.d4456, v.n4456, v.c401, v.tiers, v.d, v.c));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('A01', 'facture 1 200 HT (20 % et 5,5 %) → D 6 1 200 + D 4456 211 (2 comptes) = C 401 1 411 (auxiliaire)', false, SQLERRM); END;
END $$;

-- A02 — totaux recalculés par le serveur ; facture approuvée figée
DO $$
DECLARE t uuid := _mk_tenant('A02'); s uuid; pi uuid; h record; ok_l boolean := false; ok_h boolean := false; tot numeric;
BEGIN
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Fournisseur B') RETURNING id INTO s;
  PERFORM _as_user();
  BEGIN
    INSERT INTO purchase_invoices (tenant_id, number, supplier_id, supplier_name, date, due_date, status, subtotal, vat_total, total, approval_status)
    VALUES (t, 'F-A02', s, 'Fournisseur B', '2026-03-01', '2026-03-31', 'draft', 999, 0, 999, 'pending') RETURNING id INTO pi;
    INSERT INTO purchase_invoice_lines (tenant_id, purchase_invoice_id, description, quantity, unit_price, vat_rate, total, vat_amount)
    VALUES (t, pi, 'X', 2, 150, 20, 1, 0);
    SELECT subtotal, vat_total, total INTO h FROM purchase_invoices WHERE id = pi;
    UPDATE purchase_invoices SET approval_status = 'approved' WHERE id = pi;
    BEGIN UPDATE purchase_invoice_lines SET unit_price = 1 WHERE purchase_invoice_id = pi; EXCEPTION WHEN OTHERS THEN ok_l := true; END;
    BEGIN UPDATE purchase_invoices SET total = 1 WHERE id = pi; EXCEPTION WHEN OTHERS THEN ok_h := true; END;
    SELECT total INTO tot FROM purchase_invoices WHERE id = pi;
    PERFORM _rec('A02', 'en-tête recalculé 300 / 60 / 360 ; approuvée : lignes et montants figés',
      h.subtotal = 300 AND h.vat_total = 60 AND h.total = 360 AND ok_l AND ok_h AND tot = 360,
      format('en-tête %s/%s/%s ; ligne refusée=%s en-tête refusé=%s total=%s', h.subtotal, h.vat_total, h.total, ok_l, ok_h, tot));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('A02', 'en-tête recalculé 300 / 60 / 360 ; approuvée : lignes et montants figés', false, SQLERRM); END;
END $$;

-- A03 — AUD-G02 : numéro interne ACH-<exercice>-n à l'approbation ; la référence du fournisseur est conservée
DO $$
DECLARE t uuid := _mk_tenant('A03'); s uuid; a uuid; b uuid; na text; nb text; ra text; draft_no text;
BEGIN
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Fournisseur C') RETURNING id INTO s;
  PERFORM _as_user();
  BEGIN
    a := _mk_purchase(t, s, '2026-03-01', '[{"q":1,"p":100,"r":20}]', false);
    b := _mk_purchase(t, s, '2026-03-02', '[{"q":1,"p":100,"r":20}]', false);
    EXECUTE 'UPDATE purchase_invoices SET supplier_reference = ''FA-778'' WHERE id = $1' USING a;
    SELECT number INTO draft_no FROM purchase_invoices WHERE id = a;
    UPDATE purchase_invoices SET approval_status = 'approved' WHERE id = b;
    UPDATE purchase_invoices SET approval_status = 'approved' WHERE id = a;
    SELECT number INTO na FROM purchase_invoices WHERE id = a;
    SELECT number INTO nb FROM purchase_invoices WHERE id = b;
    EXECUTE 'SELECT supplier_reference FROM purchase_invoices WHERE id = $1' INTO ra USING a;
    PERFORM _rec('A03', 'ACH-2026-000001 puis 000002 dans l''ordre d''approbation, référence fournisseur FA-778 conservée',
      nb = 'ACH-2026-000001' AND na = 'ACH-2026-000002' AND ra = 'FA-778' AND draft_no NOT LIKE 'ACH-%',
      format('b=%s a=%s réf=%s brouillon=%s', nb, na, ra, draft_no));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('A03', 'ACH-2026-000001 puis 000002 dans l''ordre d''approbation, référence fournisseur FA-778 conservée', false, SQLERRM); END;
END $$;

-- A04 — avoir fournisseur appliqué → écriture inverse, facture soldée et lettrée
DO $$
DECLARE t uuid := _mk_tenant('A04'); s uuid; pi uuid; cn uuid; e uuid; v record; due numeric; codes int; lettre int;
BEGIN
  INSERT INTO suppliers (tenant_id, name, account_tiers) VALUES (t, 'Fournisseur D', 'F0004') RETURNING id INTO s;
  PERFORM _as_user();
  BEGIN
    pi := _mk_purchase(t, s, '2026-03-01', '[{"q":1,"p":500,"r":20}]');
    INSERT INTO purchase_credit_notes (tenant_id, number, supplier_id, supplier_name, date, status, subtotal, vat_total, total, purchase_invoice_id, reason)
    VALUES (t, 'AVF-SAISIE', s, 'Fournisseur D', '2026-03-10', 'draft', 500, 100, 600, pi, 'Retour') RETURNING id INTO cn;
    UPDATE purchase_credit_notes SET status = 'applied' WHERE id = cn;
    EXECUTE 'SELECT transferred_entry_id FROM purchase_credit_notes WHERE id = $1' INTO e USING cn;
    SELECT sum(debit) FILTER (WHERE account_code ~ '^401') d401, max(account_tiers) FILTER (WHERE account_code ~ '^401') tiers,
           sum(credit) FILTER (WHERE account_code ~ '^6') c6, sum(credit) FILTER (WHERE account_code ~ '^4456') c4456
      INTO v FROM journal_lines WHERE journal_id = e;
    SELECT amount_due INTO due FROM purchase_invoices WHERE id = pi;
    SELECT count(DISTINCT lettrage_code), count(*) FILTER (WHERE lettrage_code IS NOT NULL) INTO codes, lettre
    FROM journal_lines WHERE tenant_id = t AND account_code ~ '^401';
    PERFORM _rec('A04', 'avoir fournisseur : D 401 600 (auxiliaire) = C 6 500 + C 4456 100, facture soldée et lettrée',
      v.d401 = 600 AND v.tiers = 'F0004' AND v.c6 = 500 AND v.c4456 = 100 AND due = 0 AND codes = 1 AND lettre = 2,
      format('D401=%s tiers=%s C6=%s C4456=%s dû=%s lettrage=%s code(s)/%s ligne(s)', v.d401, v.tiers, v.c6, v.c4456, due, codes, lettre));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('A04', 'avoir fournisseur : D 401 600 (auxiliaire) = C 6 500 + C 4456 100, facture soldée et lettrée', false, SQLERRM); END;
END $$;

-- A05 — règlement fournisseur par un 2e compte bancaire : son compte et son journal ; facture soldée → lettrage
DO $$
DECLARE t uuid := _mk_tenant('A05'); s uuid; pi uuid; b1 uuid; b2 uuid; acc2 text; jr2 text; e uuid; cr_acc text; jc text; codes int; lettre int; st text;
BEGIN
  INSERT INTO suppliers (tenant_id, name, account_tiers) VALUES (t, 'Fournisseur E', 'F0005') RETURNING id INTO s;
  PERFORM _as_user();
  BEGIN
    pi := _mk_purchase(t, s, '2026-03-01', '[{"q":1,"p":100,"r":20}]');
    INSERT INTO bank_accounts (tenant_id, name, type) VALUES (t, 'Banque 1', 'chequing') RETURNING id INTO b1;
    INSERT INTO bank_accounts (tenant_id, name, type) VALUES (t, 'Banque 2', 'chequing') RETURNING id INTO b2;
    SELECT account_code, journal_code INTO acc2, jr2 FROM bank_accounts WHERE id = b2;
    INSERT INTO supplier_payments (tenant_id, number, supplier_id, purchase_invoice_id, payment_date, amount, method, bank_account_id)
    VALUES (t, 'DEC-1', s, pi, '2026-03-05', 120, 'transfer', b2);
    SELECT transferred_entry_id INTO e FROM supplier_payments WHERE tenant_id = t AND number = 'DEC-1';
    SELECT jl.account_code, je.journal_code INTO cr_acc, jc FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id
    WHERE jl.journal_id = e AND jl.credit > 0;
    SELECT status INTO st FROM purchase_invoices WHERE id = pi;
    SELECT count(DISTINCT lettrage_code), count(*) FILTER (WHERE lettrage_code IS NOT NULL) INTO codes, lettre
    FROM journal_lines WHERE tenant_id = t AND account_code ~ '^401';
    PERFORM _rec('A05', 'décaissement sur la banque 2 : C compte/journal propres ; facture payée, 401 lettré',
      cr_acc = acc2 AND jc = jr2 AND acc2 <> '512000' AND st = 'paid' AND codes = 1 AND lettre = 2,
      format('C %s/%s (attendu %s/%s) statut=%s lettrage=%s code(s)/%s ligne(s)', cr_acc, jc, acc2, jr2, st, codes, lettre));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('A05', 'décaissement sur la banque 2 : C compte/journal propres ; facture payée, 401 lettré', false, SQLERRM); END;
END $$;

-- A06 — trop-payé fournisseur porté en avance fournisseur 4091
DO $$
DECLARE t uuid := _mk_tenant('A06'); s uuid; pi uuid; e uuid; v record;
BEGIN
  INSERT INTO suppliers (tenant_id, name, account_tiers) VALUES (t, 'Fournisseur F', 'F0006') RETURNING id INTO s;
  PERFORM _as_user();
  BEGIN
    pi := _mk_purchase(t, s, '2026-03-01', '[{"q":1,"p":100,"r":20}]');
    INSERT INTO supplier_payments (tenant_id, number, supplier_id, purchase_invoice_id, payment_date, amount, method)
    VALUES (t, 'DEC-2', s, pi, '2026-03-05', 200, 'transfer');
    SELECT transferred_entry_id INTO e FROM supplier_payments WHERE tenant_id = t AND number = 'DEC-2';
    SELECT sum(debit) FILTER (WHERE account_code ~ '^401') d401, sum(debit) FILTER (WHERE account_code = '409100') d4091,
           max(account_tiers) FILTER (WHERE account_code = '409100') tiers, sum(credit) c
      INTO v FROM journal_lines WHERE journal_id = e;
    PERFORM _rec('A06', 'paiement 200 sur 120 dû : D 401 120 + D 4091 80 (auxiliaire) = C 512 200',
      v.d401 = 120 AND v.d4091 = 80 AND v.tiers = 'F0006' AND v.c = 200,
      format('D401=%s D4091=%s tiers=%s C=%s', v.d401, v.d4091, v.tiers, v.c));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('A06', 'paiement 200 sur 120 dû : D 401 120 + D 4091 80 (auxiliaire) = C 512 200', false, SQLERRM); END;
END $$;

-- A07 — une facture fournisseur sans ligne n'est pas approuvable (témoin : avec ligne, elle l'est)
DO $$
DECLARE t uuid := _mk_tenant('A07'); s uuid; pi uuid; w uuid; st text; stw text;
BEGIN
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Fournisseur G') RETURNING id INTO s;
  PERFORM _as_user();
  BEGIN
    INSERT INTO purchase_invoices (tenant_id, number, supplier_id, supplier_name, date, due_date, status, subtotal, vat_total, total, approval_status)
    VALUES (t, 'F-VIDE', s, 'Fournisseur G', '2026-03-01', '2026-03-31', 'draft', 100, 20, 120, 'pending') RETURNING id INTO pi;
    BEGIN UPDATE purchase_invoices SET approval_status = 'approved' WHERE id = pi; EXCEPTION WHEN OTHERS THEN NULL; END;
    w := _mk_purchase(t, s, '2026-03-01', '[{"q":1,"p":100,"r":20}]');
    SELECT approval_status INTO st FROM purchase_invoices WHERE id = pi;
    SELECT approval_status INTO stw FROM purchase_invoices WHERE id = w;
    PERFORM _rec('A07', 'facture fournisseur sans ligne non approuvable (témoin avec ligne : approuvée)', st = 'pending' AND stw = 'approved',
      format('sans ligne=%s témoin=%s', st, stw));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('A07', 'facture fournisseur sans ligne non approuvable (témoin avec ligne : approuvée)', false, SQLERRM); END;
END $$;

-- A08 — avoir fournisseur avec lignes à deux taux : totaux recalculés, TVA par taux, numéro AVF
DO $$
DECLARE t uuid := _mk_tenant('A08'); s uuid; cn uuid; e uuid; v record; num text; h record;
BEGIN
  INSERT INTO suppliers (tenant_id, name, account_tiers) VALUES (t, 'Fournisseur H', 'F0008') RETURNING id INTO s;
  PERFORM _as_user();
  BEGIN
    INSERT INTO purchase_credit_notes (tenant_id, number, supplier_id, supplier_name, date, status, subtotal, vat_total, total)
    VALUES (t, 'AVF-REF-9', s, 'Fournisseur H', '2026-03-10', 'draft', 0, 0, 0) RETURNING id INTO cn;
    INSERT INTO purchase_credit_lines (tenant_id, purchase_credit_id, description, quantity, unit_price, vat_rate, total, vat_total)
    VALUES (t, cn, 'Remise A', 1, 100, 20, 0, 0), (t, cn, 'Remise B', 1, 100, 5.5, 0, 0);
    SELECT subtotal, vat_total, total INTO h FROM purchase_credit_notes WHERE id = cn;
    UPDATE purchase_credit_notes SET status = 'validated' WHERE id = cn;
    EXECUTE 'SELECT transferred_entry_id, number FROM purchase_credit_notes WHERE id = $1' INTO e, num USING cn;
    SELECT sum(debit) FILTER (WHERE account_code ~ '^401') d401, sum(credit) FILTER (WHERE account_code ~ '^6') c6,
           count(DISTINCT account_code) FILTER (WHERE account_code ~ '^4456') n4456, sum(credit) FILTER (WHERE account_code ~ '^4456') c4456
      INTO v FROM journal_lines WHERE journal_id = e;
    PERFORM _rec('A08', 'avoir 200 HT (20 % + 5,5 %) : en-tête 200/25,5/225,5, D 401 225,5 = C 6 200 + C 4456 25,5 (2 comptes), AVF-2026-000001',
      h.subtotal = 200 AND h.vat_total = 25.5 AND h.total = 225.5 AND v.d401 = 225.5 AND v.c6 = 200 AND v.c4456 = 25.5 AND v.n4456 = 2
        AND num = 'AVF-2026-000001',
      format('en-tête %s/%s/%s D401=%s C6=%s C4456=%s (%s comptes) n°=%s', h.subtotal, h.vat_total, h.total, v.d401, v.c6, v.c4456, v.n4456, num));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('A08', 'avoir 200 HT (20 % + 5,5 %) : en-tête 200/25,5/225,5, D 401 225,5 = C 6 200 + C 4456 25,5 (2 comptes), AVF-2026-000001', false, SQLERRM); END;
END $$;

-- G05 — AUD-G05 (C14 du suivi) : un ajustement d'inventaire est une VARIATION de stock
-- 10 u. à 10 en stock ; inventaire à 7 (baisse de 3), puis à 12 (hausse de 5, au CUMP 10)
DO $$
DECLARE t uuid := _mk_tenant('G05'); w uuid; p uuid; q1 numeric; wq1 numeric; s1 numeric; q2 numeric; wq2 numeric; s2 numeric;
BEGIN
  PERFORM ensure_standard_journals(t);
  INSERT INTO warehouses (tenant_id, name, code) VALUES (t, 'Dépôt', 'W1') RETURNING id INTO w;
  INSERT INTO products (tenant_id, name, sku, type, cost_price, stock_quantity) VALUES (t, 'Article', 'SKU-G05', 'stock', 0, 0) RETURNING id INTO p;
  PERFORM _as_user();
  BEGIN
    INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, type, movement_type, quantity, unit_cost, date)
    VALUES (t, p, w, 'in', 'in', 10, 10, '2026-03-01');
    INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, type, movement_type, quantity, date)
    VALUES (t, p, w, 'adjustment', 'adjustment', 7, '2026-03-10');
    SELECT stock_quantity INTO q1 FROM products WHERE id = p;
    SELECT sum(quantity) INTO wq1 FROM stock_quantities WHERE product_id = p AND warehouse_id = w;
    SELECT COALESCE(sum(debit - credit), 0) INTO s1 FROM journal_lines WHERE tenant_id = t AND account_code = '310000';
    INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, type, movement_type, quantity, date)
    VALUES (t, p, w, 'adjustment', 'adjustment', 12, '2026-03-20');
    SELECT stock_quantity INTO q2 FROM products WHERE id = p;
    SELECT sum(quantity) INTO wq2 FROM stock_quantities WHERE product_id = p AND warehouse_id = w;
    SELECT COALESCE(sum(debit - credit), 0) INTO s2 FROM journal_lines WHERE tenant_id = t AND account_code = '310000';
    PERFORM _rec('G05', 'inventaire à 7 puis 12 : stock 7 → 12 (article et dépôt), compte 310000 à 70 puis 120',
      q1 = 7 AND wq1 = 7 AND s1 = 70 AND q2 = 12 AND wq2 = 12 AND s2 = 120,
      format('après baisse : article=%s dépôt=%s 310=%s ; après hausse : article=%s dépôt=%s 310=%s', q1, wq1, s1, q2, wq2, s2));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('G05', 'inventaire à 7 puis 12 : stock 7 → 12 (article et dépôt), compte 310000 à 70 puis 120', false, SQLERRM); END;
END $$;

-- G09 — AUD-G09 : point de vente → écriture de clôture, sortie de stock unique, chaîne NF525
-- 10 u. à 5 au dépôt de la caisse (et 10 u. dans un autre dépôt, qui ne doit pas bouger) ;
-- deux tickets de 1 u. à 10 HT (TVA 20 %) payés en espèces ; clôture de la session.
DO $$
DECLARE t uuid := _mk_tenant('G09'); w uuid; w2 uuid; p uuid; term uuid; sess uuid; pm uuid; k1 uuid; k2 uuid;
  v record; wq numeric; wq2 numeric; s310 numeric; chain_ok boolean; n_out int;
BEGIN
  PERFORM ensure_standard_journals(t);
  INSERT INTO warehouses (tenant_id, name, code) VALUES (t, 'Magasin', 'MAG') RETURNING id INTO w;
  INSERT INTO warehouses (tenant_id, name, code) VALUES (t, 'Réserve', 'RES') RETURNING id INTO w2;
  INSERT INTO products (tenant_id, name, sku, type, cost_price, stock_quantity) VALUES (t, 'Article POS', 'SKU-G09', 'stock', 0, 0) RETURNING id INTO p;
  PERFORM _as_user();
  BEGIN
    INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, type, movement_type, quantity, unit_cost, date)
    VALUES (t, p, w, 'in', 'in', 10, 5, '2026-03-01'), (t, p, w2, 'in', 'in', 10, 5, '2026-03-01');
    INSERT INTO pos_terminals (tenant_id, name, warehouse_id) VALUES (t, 'Caisse 1', w) RETURNING id INTO term;
    INSERT INTO pos_payment_methods (tenant_id, name, type, account_code) VALUES (t, 'Espèces', 'cash', '530000') RETURNING id INTO pm;
    INSERT INTO pos_sessions (tenant_id, terminal_id, user_email, opening_amount, status) VALUES (t, term, 'caisse@audit.test', 0, 'open') RETURNING id INTO sess;
    INSERT INTO pos_tickets (tenant_id, number, session_id, terminal_id, subtotal, vat_total, total, payment_method, amount_paid, status)
    VALUES (t, 'T1', sess, term, 10, 2, 12, 'cash', 12, 'completed') RETURNING id INTO k1;
    INSERT INTO pos_ticket_lines (tenant_id, ticket_id, product_id, description, quantity, unit_price, vat_rate, line_total)
    VALUES (t, k1, p, 'Article POS', 1, 10, 20, 10);
    INSERT INTO pos_payments (tenant_id, ticket_id, payment_method_id, amount) VALUES (t, k1, pm, 12);
    INSERT INTO pos_tickets (tenant_id, number, session_id, terminal_id, subtotal, vat_total, total, payment_method, amount_paid, status)
    VALUES (t, 'T2', sess, term, 10, 2, 12, 'cash', 12, 'completed') RETURNING id INTO k2;
    INSERT INTO pos_ticket_lines (tenant_id, ticket_id, product_id, description, quantity, unit_price, vat_rate, line_total)
    VALUES (t, k2, p, 'Article POS', 1, 10, 20, 10);
    INSERT INTO pos_payments (tenant_id, ticket_id, payment_method_id, amount) VALUES (t, k2, pm, 12);
    SELECT (SELECT previous_hash FROM pos_tickets WHERE id = k2) = (SELECT ticket_hash FROM pos_tickets WHERE id = k1)
           AND (SELECT ticket_hash FROM pos_tickets WHERE id = k1) IS NOT NULL INTO chain_ok;

    UPDATE pos_sessions SET status = 'closed', closing_amount = 24 WHERE id = sess;

    SELECT max(je.status) st, sum(jl.debit) FILTER (WHERE jl.account_code = '530000') d530,
           sum(jl.credit) FILTER (WHERE jl.account_code ~ '^70') c70, sum(jl.credit) FILTER (WHERE jl.account_code ~ '^4457') c4457
      INTO v FROM journal_entries je JOIN journal_lines jl ON jl.journal_id = je.id
     WHERE je.tenant_id = t AND je.journal_code = 'POS';
    SELECT sum(quantity) INTO wq FROM stock_quantities WHERE product_id = p AND warehouse_id = w;
    SELECT sum(quantity) INTO wq2 FROM stock_quantities WHERE product_id = p AND warehouse_id = w2;
    SELECT count(*) INTO n_out FROM stock_movements WHERE tenant_id = t AND reference_type = 'pos_session';
    SELECT COALESCE(sum(debit - credit), 0) INTO s310 FROM journal_lines WHERE tenant_id = t AND account_code = '310000';
    PERFORM _rec('G09', 'clôture POS : D 530 24 = C 707 20 + C 4457 4 ; magasin 10 → 8, réserve 10 intacte, 310 = 90 ; tickets chaînés',
      v.st = 'posted' AND v.d530 = 24 AND v.c70 = 20 AND v.c4457 = 4 AND wq = 8 AND wq2 = 10 AND n_out = 1 AND s310 = 90 AND chain_ok,
      format('écriture %s D530=%s C70=%s C4457=%s ; magasin=%s réserve=%s mouvements=%s 310=%s chaîne=%s',
             v.st, v.d530, v.c70, v.c4457, wq, wq2, n_out, s310, chain_ok));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('G09', 'clôture POS : D 530 24 = C 707 20 + C 4457 4 ; magasin 10 → 8, réserve 10 intacte, 310 = 90 ; tickets chaînés', false, SQLERRM); END;
END $$;

-- G10 — AUD-G10 : tout compte écrit par une écriture automatique existe dans le plan
-- semé à l'inscription. Comptes cherchés : littéraux des fonctions qui insèrent dans
-- journal_lines, comptes de paie par défaut, comptes de TVA partagés.
DO $$
DECLARE t uuid := _mk_tenant('G10'); n_lit int; missing text;
BEGIN
  WITH used AS (
    SELECT DISTINCT m[1] AS code, p.proname AS src
    FROM pg_proc p, regexp_matches(p.prosrc, '''([1-7][0-9]{5,6})''', 'g') m
    WHERE p.pronamespace = 'public'::regnamespace AND p.prosrc ~* 'insert into (public\.)?journal_lines'
      AND p.proname NOT LIKE '\_%'
    UNION SELECT account_code, 'payroll_account_mapping' FROM payroll_account_mapping WHERE tenant_id IS NULL
    UNION SELECT account_code, 'vat_account_mapping' FROM vat_account_mapping
      WHERE tenant_id = '00000000-0000-0000-0000-000000000000'
  )
  SELECT count(DISTINCT code),
         string_agg(DISTINCT code || ' (' || src || ')', ', ') FILTER (WHERE NOT EXISTS (
           SELECT 1 FROM chart_accounts c WHERE c.tenant_id = t AND c.code = used.code))
    INTO n_lit, missing
  FROM used;
  PERFORM _rec('G10', 'comptes des écritures automatiques présents au plan semé (témoin : au moins 15 comptes trouvés)',
    n_lit >= 15 AND missing IS NULL, format('%s comptes examinés ; absents : %s', n_lit, COALESCE(missing, 'aucun')));
END $$;

-- G06 — AUD-G06 : reçu d'une ligne de commande (colonne calculée lue par le MRP)
-- deux lignes du même article (10 et 5) ; réceptions 4 puis 8 → 4, puis 12 reçus, chaque ligne plafonnée à sa quantité
DO $$
DECLARE t uuid := _mk_tenant('G06'); s uuid; p uuid; po uuid; l1 uuid; l2 uuid; g uuid; r1a numeric; r2a numeric; r1b numeric; r2b numeric; st text;
BEGIN
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Fournisseur MRP') RETURNING id INTO s;
  INSERT INTO products (tenant_id, name, sku, type) VALUES (t, 'Composant', 'SKU-G06', 'stock') RETURNING id INTO p;
  PERFORM _as_user();
  BEGIN
    INSERT INTO purchase_orders (tenant_id, number, supplier_id, status) VALUES (t, 'CF-1', s, 'confirmed') RETURNING id INTO po;
    INSERT INTO purchase_order_lines (tenant_id, purchase_order_id, product_id, description, quantity, unit_price) VALUES (t, po, p, 'L1', 10, 1) RETURNING id INTO l1;
    INSERT INTO purchase_order_lines (tenant_id, purchase_order_id, product_id, description, quantity, unit_price) VALUES (t, po, p, 'L2', 5, 1) RETURNING id INTO l2;
    INSERT INTO goods_receipts (tenant_id, number, supplier_id, purchase_order_id, status) VALUES (t, 'BR-1', s, po, 'pending') RETURNING id INTO g;
    INSERT INTO goods_receipt_lines (tenant_id, goods_receipt_id, product_id, description, quantity_ordered, quantity_received) VALUES (t, g, p, 'Composant', 15, 4);
    UPDATE goods_receipts SET status = 'partial' WHERE id = g;
    EXECUTE 'SELECT quantity_received(l) FROM purchase_order_lines l WHERE id = $1' INTO r1a USING l1;
    EXECUTE 'SELECT quantity_received(l) FROM purchase_order_lines l WHERE id = $1' INTO r2a USING l2;
    INSERT INTO goods_receipts (tenant_id, number, supplier_id, purchase_order_id, status) VALUES (t, 'BR-2', s, po, 'pending') RETURNING id INTO g;
    INSERT INTO goods_receipt_lines (tenant_id, goods_receipt_id, product_id, description, quantity_ordered, quantity_received) VALUES (t, g, p, 'Composant', 11, 8);
    UPDATE goods_receipts SET status = 'received' WHERE id = g;
    EXECUTE 'SELECT quantity_received(l) FROM purchase_order_lines l WHERE id = $1' INTO r1b USING l1;
    EXECUTE 'SELECT quantity_received(l) FROM purchase_order_lines l WHERE id = $1' INTO r2b USING l2;
    SELECT status INTO st FROM purchase_orders WHERE id = po;
    PERFORM _rec('G06', 'reçu 4 puis 12 sur 15 commandés (lignes plafonnées), réception partielle validée, commande « partial »',
      r1a + r2a = 4 AND r1b + r2b = 12 AND r1b <= 10 AND r2b <= 5 AND st = 'partial',
      format('L1=%s puis %s ; L2=%s puis %s ; commande=%s', r1a, r1b, r2a, r2b, st));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('G06', 'reçu 4 puis 12 sur 15 commandés (lignes plafonnées), réception partielle validée, commande « partial »', false, SQLERRM); END;
END $$;

-- G04 — AUD-G04 : relevé importé → pointage automatique → écart → état de rapprochement
-- Comptabilité : encaissement 120 (05/03), décaissement 50 (06/03) sur la banque.
-- Relevé : +120 (06/03), −50 (07/03), −3 de frais (08/03, pas encore comptabilisés).
-- Attendu au 31/03 : relevé 67, compte 512 70, un seul écart (frais −3), état équilibré.
DO $$
DECLARE t uuid := _mk_tenant('G04'); c uuid; sp uuid; b uuid; acc text; st record; n_match int; n_rec int;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client R') RETURNING id INTO c;
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Fournisseur R') RETURNING id INTO sp;
  PERFORM _as_user();
  BEGIN
    INSERT INTO bank_accounts (tenant_id, name, type) VALUES (t, 'Banque R', 'chequing') RETURNING id INTO b;
    SELECT account_code INTO acc FROM bank_accounts WHERE id = b;
    INSERT INTO customer_payments (tenant_id, number, customer_id, payment_date, amount, method, bank_account_id)
    VALUES (t, 'RG-R1', c, '2026-03-05', 120, 'transfer', b);
    INSERT INTO supplier_payments (tenant_id, number, supplier_id, payment_date, amount, method, bank_account_id)
    VALUES (t, 'DEC-R1', sp, '2026-03-06', 50, 'transfer', b);
    -- lignes du relevé, telles que l'import les enregistre
    INSERT INTO bank_transactions (tenant_id, account_id, bank_account_id, date, description, type, amount, source) VALUES
      (t, b, b, '2026-03-06', 'VIR CLIENT R', 'credit', 120, 'import'),
      (t, b, b, '2026-03-07', 'VIR FOURNISSEUR R', 'debit', 50, 'import'),
      (t, b, b, '2026-03-08', 'FRAIS TENUE DE COMPTE', 'debit', 3, 'import');
    SELECT count(*) FILTER (WHERE matched) INTO n_match FROM bank_transactions WHERE tenant_id = t AND source = 'import';
    SELECT count(*) INTO n_rec FROM journal_lines WHERE tenant_id = t AND account_code = acc AND reconciled;
    SELECT * INTO st FROM get_bank_reconciliation_state(b, '2026-03-31');
    PERFORM _rec('G04', 'relevé 67 / compte 512 70 : 2 lignes pointées, écart unique −3 (frais), état équilibré',
      n_match = 2 AND n_rec = 2 AND st.statement_balance = 67 AND st.accounting_balance = 70
        AND st.unmatched_debits = 3 AND st.unmatched_credits = 0
        AND st.ledger_unmatched_debits = 0 AND st.ledger_unmatched_credits = 0 AND st.is_balanced,
      format('pointées relevé=%s écritures=%s ; relevé=%s compte=%s ; écarts relevé D%s/C%s, compta D%s/C%s ; équilibré=%s',
             n_match, n_rec, st.statement_balance, st.accounting_balance, st.unmatched_debits, st.unmatched_credits,
             st.ledger_unmatched_debits, st.ledger_unmatched_credits, st.is_balanced));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('G04', 'relevé 67 / compte 512 70 : 2 lignes pointées, écart unique −3 (frais), état équilibré', false, SQLERRM); END;
END $$;

-- A09 — le payé d'une facture fournisseur ne se saisit pas à la main (bouton « Marquer
-- payée » de l'écran : ni décaissement ni écriture) ; seul un règlement le fait évoluer
DO $$
DECLARE t uuid := _mk_tenant('A09'); s uuid; pi uuid; r record;
BEGIN
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Fournisseur MP') RETURNING id INTO s;
  PERFORM _as_user();
  BEGIN
    pi := _mk_purchase(t, s, '2026-03-01', '[{"q":1,"p":100,"r":20}]');
    BEGIN UPDATE purchase_invoices SET status = 'paid', amount_paid = 120, amount_due = 0 WHERE id = pi; EXCEPTION WHEN OTHERS THEN NULL; END;
    SELECT status, amount_paid, amount_due INTO r FROM purchase_invoices WHERE id = pi;
    PERFORM _rec('A09', '« payée » sans décaissement refusé : payé 0, reste 120', r.amount_paid = 0 AND r.amount_due = 120 AND r.status <> 'paid',
      format('statut=%s payé=%s reste=%s', r.status, r.amount_paid, r.amount_due));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('A09', '« payée » sans décaissement refusé : payé 0, reste 120', false, SQLERRM); END;
END $$;

-- G11 — une ligne de relevé qui reconnaît une facture (même montant, n° de facture en
-- référence) enregistre un vrai règlement : écriture 512/411, facture payée une seule
-- fois, lettrage, ligne de relevé pointée. Avant : amount_paid augmenté sans écriture.
DO $$
DECLARE t uuid := _mk_tenant('G11'); c uuid; inv uuid; b uuid; num text; r record; n_pay int; lettre int; pointee boolean;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client Relevé') RETURNING id INTO c;
  PERFORM _as_user();
  BEGIN
    INSERT INTO invoices (tenant_id, number, customer_id, customer_name, date, due_date, status)
    VALUES (t, 'X', c, 'Client Relevé', '2026-03-01', '2026-03-31', 'draft') RETURNING id INTO inv;
    INSERT INTO invoice_lines (tenant_id, invoice_id, description, quantity, unit_price, vat_rate) VALUES (t, inv, 'P', 1, 100, 20);
    UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
    SELECT number INTO num FROM invoices WHERE id = inv;
    INSERT INTO bank_accounts (tenant_id, name, type) VALUES (t, 'Banque relevé', 'chequing') RETURNING id INTO b;
    INSERT INTO bank_transactions (tenant_id, account_id, bank_account_id, date, description, reference, type, amount, source)
    VALUES (t, b, b, '2026-03-10', 'VIR CLIENT RELEVE ' || num, num, 'credit', 120, 'import');
    SELECT status, amount_paid, amount_due INTO r FROM invoices WHERE id = inv;
    SELECT count(*) INTO n_pay FROM customer_payments WHERE tenant_id = t AND invoice_id = inv;
    SELECT count(*) FILTER (WHERE lettrage_code IS NOT NULL) INTO lettre FROM journal_lines WHERE tenant_id = t AND account_code = '411000';
    SELECT reconciled_entry_id IS NOT NULL INTO pointee FROM bank_transactions WHERE tenant_id = t AND source = 'import';
    PERFORM _rec('G11', 'relevé reconnu → 1 règlement, facture payée 120 (pas 240), 411 lettré, ligne pointée',
      n_pay = 1 AND r.status = 'paid' AND r.amount_paid = 120 AND r.amount_due = 0 AND lettre = 2 AND pointee,
      format('règlements=%s statut=%s payé=%s reste=%s lettrées=%s pointée=%s', n_pay, r.status, r.amount_paid, r.amount_due, lettre, pointee));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('G11', 'relevé reconnu → 1 règlement, facture payée 120 (pas 240), 411 lettré, ligne pointée', false, SQLERRM); END;
END $$;

SELECT _audit_assert('192');
