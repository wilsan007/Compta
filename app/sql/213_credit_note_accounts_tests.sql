-- ============================================================
-- 213_credit_note_accounts_tests.sql — R-05 (phase 1 du reste-à-faire du 22/09)
--
-- Un avoir rattaché à une facture dont les lignes n'ont pas d'article (ou qui
-- n'a aucune ligne : remise commerciale) était imputé au compte par défaut —
-- 709000 en client, 609000 en fournisseur — au lieu de **contre-passer les
-- comptes de l'écriture d'origine**, au prorata. L'avoir annulait donc une
-- vente 706000 en 709000 : le chiffre d'affaires n'était pas corrigé.
--
-- E23 — client : facture 600 en 706000 + 400 en 707000, avoir de 500 sans
--       article → 300 en 706000 et 200 en 707000 (et non 500 en 709000).
-- A10 — fournisseur : facture 300 en 606000 + 700 en 607000, avoir de 400 sans
--       article → 120 en 606000 et 280 en 607000.
-- E23b / A10b — non-régression : un avoir sans facture reste en 709000 / 609000.
-- E23c — avoir dont la somme du prorata tombe juste au centime : la dernière
--        ligne absorbe l'arrondi, le total contre-passé est exact.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '213', false);
DELETE FROM _audit_results WHERE file = '213';

-- Facture client validée : deux lignes d'articles de comptes de vente différents
CREATE OR REPLACE FUNCTION _mk_sale213(t uuid, c uuid, p1 uuid, a1 numeric, p2 uuid, a2 numeric)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE inv uuid;
BEGIN
  INSERT INTO invoices (tenant_id, customer_id, customer_name, date, due_date, status)
  VALUES (t, c, 'Client', '2026-03-01', '2026-03-31', 'draft') RETURNING id INTO inv;
  INSERT INTO invoice_lines (tenant_id, invoice_id, product_id, description, quantity, unit_price, vat_rate, line_order)
  VALUES (t, inv, p1, 'Ligne 1', 1, a1, 0, 0), (t, inv, p2, 'Ligne 2', 1, a2, 0, 1);
  UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
  RETURN inv;
END $$;

-- Avoir client rattaché (ou non) à une facture, sans ligne d'article
CREATE OR REPLACE FUNCTION _mk_cn213(t uuid, c uuid, inv uuid, amount numeric)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE cn uuid;
BEGIN
  INSERT INTO credit_notes (tenant_id, customer_id, invoice_id, date, subtotal, vat_total, total)
  VALUES (t, c, inv, '2026-04-01', amount, 0, amount) RETURNING id INTO cn;
  UPDATE credit_notes SET status = 'validated' WHERE id = cn;
  RETURN cn;
END $$;

-- Facture fournisseur approuvée, deux lignes de comptes de charge différents
CREATE OR REPLACE FUNCTION _mk_purch213(t uuid, s uuid, p1 uuid, a1 numeric, p2 uuid, a2 numeric)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE inv uuid;
BEGIN
  INSERT INTO purchase_invoices (tenant_id, supplier_id, supplier_name, number, date, due_date, status)
  VALUES (t, s, 'Fournisseur', 'FA-213', '2026-03-01', '2026-03-31', 'draft') RETURNING id INTO inv;
  INSERT INTO purchase_invoice_lines (tenant_id, purchase_invoice_id, product_id, description, quantity, unit_price, vat_rate, line_order)
  VALUES (t, inv, p1, 'Ligne 1', 1, a1, 0, 0), (t, inv, p2, 'Ligne 2', 1, a2, 0, 1);
  UPDATE purchase_invoices SET approval_status = 'approved' WHERE id = inv;
  RETURN inv;
END $$;

-- Avoir fournisseur rattaché (ou non) à une facture, sans ligne d'article
CREATE OR REPLACE FUNCTION _mk_pcn213(t uuid, s uuid, inv uuid, amount numeric)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE cn uuid;
BEGIN
  INSERT INTO purchase_credit_notes (tenant_id, supplier_id, purchase_invoice_id, date, subtotal, vat_total, total)
  VALUES (t, s, inv, '2026-04-01', amount, 0, amount) RETURNING id INTO cn;
  UPDATE purchase_credit_notes SET status = 'validated' WHERE id = cn;
  RETURN cn;
END $$;

-- E23 — avoir client 500 sur facture 600 (706000) + 400 (707000) : contrepassation au prorata
DO $$
DECLARE t uuid := _mk_tenant('E23'); c uuid; pa uuid; pb uuid; inv uuid; cn uuid; e uuid; r record;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client E23') RETURNING id INTO c;
  INSERT INTO products (tenant_id, name, sku, type, sale_account_code)
  VALUES (t, 'Prestation A', 'SKU-E23A', 'service', '706000') RETURNING id INTO pa;
  INSERT INTO products (tenant_id, name, sku, type)
  VALUES (t, 'Marchandise B', 'SKU-E23B', 'stock') RETURNING id INTO pb;
  PERFORM _as_user();
  BEGIN
    inv := _mk_sale213(t, c, pa, 600::numeric, pb, 400::numeric);
    cn := _mk_cn213(t, c, inv, 500::numeric);
    SELECT transferred_entry_id INTO e FROM credit_notes WHERE id = cn;
    SELECT COALESCE(sum(jl.debit) FILTER (WHERE jl.account_code = '706000'), 0) AS d706,
           COALESCE(sum(jl.debit) FILTER (WHERE jl.account_code = '707000'), 0) AS d707,
           COALESCE(sum(jl.debit) FILTER (WHERE jl.account_code = '709000'), 0) AS d709,
           COALESCE(sum(jl.credit) FILTER (WHERE jl.account_code = '411000'), 0) AS c411
      INTO r FROM journal_lines jl WHERE jl.journal_id = e;
    PERFORM _rec('E23', 'avoir 500 sans article sur facture 600/706000 + 400/707000 : 300 en 706000 et 200 en 707000, pas 709000',
      r.d706 = 300 AND r.d707 = 200 AND r.d709 = 0 AND r.c411 = 500,
      format('D706000=%s D707000=%s D709000=%s C411000=%s', r.d706, r.d707, r.d709, r.c411));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('E23', 'avoir 500 sans article sur facture 600/706000 + 400/707000 : 300 en 706000 et 200 en 707000, pas 709000', false, SQLERRM);
  END;
END $$;

-- E23b — non-régression : un avoir sans facture d'origine reste une remise en 709000
DO $$
DECLARE t uuid := _mk_tenant('E23B'); c uuid; cn uuid; e uuid; r record;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client E23b') RETURNING id INTO c;
  PERFORM _as_user();
  BEGIN
    cn := _mk_cn213(t, c, NULL, 150::numeric);
    SELECT transferred_entry_id INTO e FROM credit_notes WHERE id = cn;
    SELECT COALESCE(sum(jl.debit) FILTER (WHERE jl.account_code = '709000'), 0) AS d709,
           COALESCE(sum(jl.debit) FILTER (WHERE jl.account_code LIKE '7%' AND jl.account_code <> '709000'), 0) AS autres
      INTO r FROM journal_lines jl WHERE jl.journal_id = e;
    PERFORM _rec('E23b', 'avoir sans facture d''origine : remise commerciale en 709000 (aucun autre compte de produit)',
      r.d709 = 150 AND r.autres = 0, format('D709000=%s autres 7xx=%s', r.d709, r.autres));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('E23b', 'avoir sans facture d''origine : remise commerciale en 709000 (aucun autre compte de produit)', false, SQLERRM);
  END;
END $$;

-- E23c — prorata qui tombe au centime : la somme contre-passée est exacte au centime
DO $$
DECLARE t uuid := _mk_tenant('E23C'); c uuid; pa uuid; pb uuid; inv uuid; cn uuid; e uuid; d numeric; n int;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client E23c') RETURNING id INTO c;
  INSERT INTO products (tenant_id, name, sku, type, sale_account_code)
  VALUES (t, 'P1', 'SKU-E23C1', 'service', '706000') RETURNING id INTO pa;
  INSERT INTO products (tenant_id, name, sku, type, sale_account_code)
  VALUES (t, 'P2', 'SKU-E23C2', 'service', '707000') RETURNING id INTO pb;
  PERFORM _as_user();
  BEGIN
    inv := _mk_sale213(t, c, pa, 100::numeric, pb, 200::numeric);   -- 100 / 200
    cn := _mk_cn213(t, c, inv, 100.01);           -- tiers : 33.336… et 66.673…
    SELECT transferred_entry_id INTO e FROM credit_notes WHERE id = cn;
    SELECT COALESCE(sum(jl.debit) FILTER (WHERE jl.account_code IN ('706000', '707000')), 0) AS s,
           count(*) FILTER (WHERE jl.account_code IN ('706000', '707000')) AS cpt
      INTO d, n FROM journal_lines jl WHERE jl.journal_id = e;
    PERFORM _rec('E23c', 'prorata 100/200 sur 100,01 : total contre-passé exact au centime (dernière ligne ajustée)',
      d = 100.01 AND n = 2, format('total=%s lignes=%s', d, n));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('E23c', 'prorata 100/200 sur 100,01 : total contre-passé exact au centime (dernière ligne ajustée)', false, SQLERRM);
  END;
END $$;

-- E23d — avoir avec des lignes sans article rattaché à une facture : même contrepassation
DO $$
DECLARE t uuid := _mk_tenant('E23D'); c uuid; pa uuid; pb uuid; inv uuid; cn uuid; e uuid; r record;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client E23d') RETURNING id INTO c;
  INSERT INTO products (tenant_id, name, sku, type, sale_account_code)
  VALUES (t, 'Prestation A', 'SKU-E23D1', 'service', '706000') RETURNING id INTO pa;
  INSERT INTO products (tenant_id, name, sku, type)
  VALUES (t, 'Marchandise B', 'SKU-E23D2', 'stock') RETURNING id INTO pb;
  PERFORM _as_user();
  BEGIN
    inv := _mk_sale213(t, c, pa, 600::numeric, pb, 400::numeric);
    INSERT INTO credit_notes (tenant_id, customer_id, invoice_id, date, subtotal, vat_total, total)
    VALUES (t, c, inv, '2026-04-01', 400, 0, 400) RETURNING id INTO cn;
    -- une ligne, mais sans article : l'écran laisse l'article vide
    INSERT INTO credit_note_lines (tenant_id, credit_note_id, product_id, description, quantity, unit_price, vat_rate)
    VALUES (t, cn, NULL, 'Geste commercial', 1, 400, 0);
    UPDATE credit_notes SET status = 'validated' WHERE id = cn;
    SELECT transferred_entry_id INTO e FROM credit_notes WHERE id = cn;
    SELECT COALESCE(sum(jl.debit) FILTER (WHERE jl.account_code = '706000'), 0) AS d706,
           COALESCE(sum(jl.debit) FILTER (WHERE jl.account_code = '707000'), 0) AS d707,
           COALESCE(sum(jl.debit) FILTER (WHERE jl.account_code = '709000'), 0) AS d709
      INTO r FROM journal_lines jl WHERE jl.journal_id = e;
    PERFORM _rec('E23d', 'avoir de 400 avec ligne sans article : 240 en 706000 et 160 en 707000 (prorata de la facture)',
      r.d706 = 240 AND r.d707 = 160 AND r.d709 = 0, format('D706000=%s D707000=%s D709000=%s', r.d706, r.d707, r.d709));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('E23d', 'avoir de 400 avec ligne sans article : 240 en 706000 et 160 en 707000 (prorata de la facture)', false, SQLERRM);
  END;
END $$;

-- A10 — avoir fournisseur 400 sur facture 300 (606000) + 700 (607000)
DO $$
DECLARE t uuid := _mk_tenant('A10'); s uuid; pc uuid; pd uuid; inv uuid; cn uuid; e uuid; r record;
BEGIN
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Fournisseur A10') RETURNING id INTO s;
  INSERT INTO products (tenant_id, name, sku, type, purchase_account_code)
  VALUES (t, 'Composant C', 'SKU-A10C', 'stock', '606000') RETURNING id INTO pc;
  INSERT INTO products (tenant_id, name, sku, type)
  VALUES (t, 'Composant D', 'SKU-A10D', 'stock') RETURNING id INTO pd;
  PERFORM _as_user();
  BEGIN
    inv := _mk_purch213(t, s, pc, 300::numeric, pd, 700::numeric);
    cn := _mk_pcn213(t, s, inv, 400::numeric);
    SELECT transferred_entry_id INTO e FROM purchase_credit_notes WHERE id = cn;
    SELECT COALESCE(sum(jl.credit) FILTER (WHERE jl.account_code = '606000'), 0) AS c606,
           COALESCE(sum(jl.credit) FILTER (WHERE jl.account_code = '607000'), 0) AS c607,
           COALESCE(sum(jl.credit) FILTER (WHERE jl.account_code = '609000'), 0) AS c609,
           COALESCE(sum(jl.debit) FILTER (WHERE jl.account_code = '401000'), 0) AS d401
      INTO r FROM journal_lines jl WHERE jl.journal_id = e;
    PERFORM _rec('A10', 'avoir fournisseur 400 sans article : 120 en 606000 et 280 en 607000, pas 609000',
      r.c606 = 120 AND r.c607 = 280 AND r.c609 = 0 AND r.d401 = 400,
      format('C606000=%s C607000=%s C609000=%s D401000=%s', r.c606, r.c607, r.c609, r.d401));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('A10', 'avoir fournisseur 400 sans article : 120 en 606000 et 280 en 607000, pas 609000', false, SQLERRM);
  END;
END $$;

-- A10b — non-régression : avoir fournisseur sans facture d'origine reste en 609000
DO $$
DECLARE t uuid := _mk_tenant('A10B'); s uuid; cn uuid; e uuid; r record;
BEGIN
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Fournisseur A10b') RETURNING id INTO s;
  PERFORM _as_user();
  BEGIN
    cn := _mk_pcn213(t, s, NULL, 90::numeric);
    SELECT transferred_entry_id INTO e FROM purchase_credit_notes WHERE id = cn;
    SELECT COALESCE(sum(jl.credit) FILTER (WHERE jl.account_code = '609000'), 0) AS c609,
           COALESCE(sum(jl.credit) FILTER (WHERE jl.account_code LIKE '6%' AND jl.account_code <> '609000'), 0) AS autres
      INTO r FROM journal_lines jl WHERE jl.journal_id = e;
    PERFORM _rec('A10b', 'avoir fournisseur sans facture d''origine : remise en 609000 (aucun autre compte de charge)',
      r.c609 = 90 AND r.autres = 0, format('C609000=%s autres 6xx=%s', r.c609, r.autres));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('A10b', 'avoir fournisseur sans facture d''origine : remise en 609000 (aucun autre compte de charge)', false, SQLERRM);
  END;
END $$;

DROP FUNCTION _mk_sale213(uuid, uuid, uuid, numeric, uuid, numeric);
DROP FUNCTION _mk_cn213(uuid, uuid, uuid, numeric);
DROP FUNCTION _mk_purch213(uuid, uuid, uuid, numeric, uuid, numeric);
DROP FUNCTION _mk_pcn213(uuid, uuid, uuid, numeric);

SELECT _audit_assert('213');