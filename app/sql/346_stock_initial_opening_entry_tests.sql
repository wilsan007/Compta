-- ============================================================
-- 346_stock_initial_opening_entry_tests.sql — décisions D-QA-3 et D-QA-4
--
--   T01  D-QA-4 : un stock initial de 100 × 12 € passe UNE écriture d'à-nouveau
--        validée — 31x au débit, 890000 au crédit, 1 200 €, au début de l'exercice
--   T02  le stock valorisé et le compte de stock disent le même montant
--   T03  sans exercice, le stock initial est ACCEPTÉ et aucune écriture n'est
--        passée ; il apparaît dans la liste des écritures manquantes
--   T04  un stock initial sans coût ne produit aucune écriture
--   T05  D-QA-3 : la règle de désactivation des articles à prix négatif
-- ============================================================
\ir ci/audit_helpers.sql
\ir ci/ledger_fixture.sql
SELECT set_config('audit.file', '346', false);
DELETE FROM _audit_results WHERE file = '346';

CREATE OR REPLACE FUNCTION _l346_initial(p_t uuid, p_p uuid, p_wh uuid, p_qte numeric, p_cout numeric)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE m uuid;
BEGIN
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type,
    quantity, unit_cost, reference, movement_date, date)
  VALUES (p_t, p_p, p_wh, 'initial', 'initial', p_qte, p_cout, 'Stock initial', DATE '2026-03-15', DATE '2026-03-15')
  RETURNING id INTO m;
  RETURN m;
END $$;

-- ── T01 + T02 + T04 ──────────────────────────────────────────
DO $$
DECLARE
  t uuid := _mk_tenant('P2DQA4T01', false);
  wh uuid; p uuid; p0 uuid; m uuid; m0 uuid;
  n int; v_statut text; v_date date; v_journal text; d_stock numeric; c_890 numeric; v_compte text;
  v_couches numeric; v_solde numeric; n0 int;
BEGIN
  PERFORM _ledger_fixture(t);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-DQA4', 'Dépôt DQA4') RETURNING id INTO wh;
  INSERT INTO products (tenant_id, name, sku, type) VALUES (t, 'Article DQA4', 'DQA4-A', 'stock') RETURNING id INTO p;
  INSERT INTO products (tenant_id, name, sku, type) VALUES (t, 'Article sans coût', 'DQA4-B', 'stock') RETURNING id INTO p0;

  m := _l346_initial(t, p, wh, 100, 12);

  SELECT count(*), max(e.status), max(e.date), max(e.journal_code) INTO n, v_statut, v_date, v_journal
    FROM journal_entries e WHERE e.tenant_id = t AND e.reference = 'STOCK-OPEN-' || m;
  SELECT COALESCE(sum(l.debit) FILTER (WHERE l.account_code LIKE '3%'), 0),
         COALESCE(sum(l.credit) FILTER (WHERE l.account_code = '890000'), 0),
         max(l.account_code) FILTER (WHERE l.debit > 0)
    INTO d_stock, c_890, v_compte
    FROM journal_entries e JOIN journal_lines l ON l.journal_id = e.id
   WHERE e.tenant_id = t AND e.reference = 'STOCK-OPEN-' || m;
  PERFORM _rec('T01', 'un stock initial de 100 × 12 € passe UNE écriture d''à-nouveau validée : compte de stock au débit, 890000 au crédit, 1 200 €, au début de l''exercice',
    n = 1 AND v_statut = 'posted' AND v_journal = 'AN' AND v_date = DATE '2026-01-01'
      AND d_stock = 1200 AND c_890 = 1200,
    format('écritures=%s statut=%s journal=%s date=%s débit %s=%s crédit 890000=%s', n, v_statut, v_journal, v_date, v_compte, d_stock, c_890));

  SELECT COALESCE(sum(remaining_qty * unit_cost), 0) INTO v_couches
    FROM stock_valuation_layers WHERE tenant_id = t AND product_id = p;
  SELECT COALESCE(sum(l.debit - l.credit), 0) INTO v_solde
    FROM journal_entries e JOIN journal_lines l ON l.journal_id = e.id
   WHERE e.tenant_id = t AND e.status = 'posted' AND l.account_code LIKE '3%';
  PERFORM _rec('T02', 'le stock valorisé et le compte de stock disent le même montant (1 200 €) — il était à 0 au grand livre',
    v_couches = 1200 AND v_solde = 1200, format('couches=%s solde des comptes 3x=%s', v_couches, v_solde));

  m0 := _l346_initial(t, p0, wh, 50, 0);
  SELECT count(*) INTO n0 FROM journal_entries e WHERE e.tenant_id = t AND e.reference = 'STOCK-OPEN-' || m0;
  PERFORM _rec('T04', 'un stock initial sans coût ne produit aucune écriture',
    n0 = 0, format('écritures=%s', n0));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'T01/T02/T04 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ── T03 ──────────────────────────────────────────────────────
DO $$
DECLARE
  t uuid := _mk_tenant('P2DQA4T03', false);
  wh uuid; p uuid; m uuid; n int; q numeric; n_manquant int;
BEGIN
  -- pas de _ledger_fixture : la société n'a AUCUN exercice
  DELETE FROM fiscal_years WHERE tenant_id = t;
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-DQA4B', 'Dépôt DQA4B') RETURNING id INTO wh;
  INSERT INTO products (tenant_id, name, sku, type) VALUES (t, 'Article sans exercice', 'DQA4-C', 'stock') RETURNING id INTO p;
  m := _l346_initial(t, p, wh, 10, 5);
  SELECT count(*) INTO n FROM journal_entries e WHERE e.tenant_id = t AND e.reference = 'STOCK-OPEN-' || m;
  SELECT COALESCE(sum(quantity), 0) INTO q FROM stock_quantities WHERE tenant_id = t AND product_id = p;
  PERFORM _as_user();
  SELECT count(*) INTO n_manquant FROM stock_initial_missing_entries() x WHERE x.movement_id = m;
  PERFORM _rec('T03', 'sans exercice : le stock initial est accepté (10 unités), aucune écriture n''est passée, et il figure dans la liste des écritures manquantes',
    n = 0 AND q = 10 AND n_manquant = 1, format('écritures=%s stock=%s listé manquant=%s', n, q, n_manquant));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'T03 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ── T05 ──────────────────────────────────────────────────────
-- La désactivation s'est jouée à la migration, sur les données présentes. On
-- en éprouve ici la CONSÉQUENCE opposable : un article à prix négatif ne peut
-- ni être créé, ni être modifié sans corriger son prix.
DO $$
DECLARE
  t uuid := _mk_tenant('P2DQA3T05', false);
  p uuid; v_refus_creation boolean := false; v_refus_modif boolean := false; n_actifs_negatifs int;
BEGIN
  PERFORM _as_user();
  BEGIN
    INSERT INTO products (tenant_id, name, sku, type, sale_price) VALUES (t, 'Négatif', 'DQA3-N', 'stock', -1);
  EXCEPTION WHEN check_violation THEN v_refus_creation := true;
  END;
  INSERT INTO products (tenant_id, name, sku, type, sale_price) VALUES (t, 'Correct', 'DQA3-OK', 'stock', 10) RETURNING id INTO p;
  BEGIN
    UPDATE products SET sale_price = -5 WHERE id = p;
  EXCEPTION WHEN check_violation THEN v_refus_modif := true;
  END;
  EXECUTE 'RESET ROLE';
  SELECT count(*) INTO n_actifs_negatifs FROM products
   WHERE COALESCE(active, true)
     AND (COALESCE(sale_price, 0) < 0 OR COALESCE(purchase_price, 0) < 0 OR COALESCE(cost_price, 0) < 0);
  PERFORM _rec('T05', 'articles à prix négatif : ni création, ni modification vers un prix négatif, et plus aucun article ACTIF à prix négatif dans la base',
    v_refus_creation AND v_refus_modif AND n_actifs_negatifs = 0,
    format('refus création=%s refus modification=%s actifs à prix négatif=%s', v_refus_creation, v_refus_modif, n_actifs_negatifs));
EXCEPTION WHEN OTHERS THEN
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T05', 'T05 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

DROP FUNCTION _l346_initial(uuid, uuid, uuid, numeric, numeric);
SELECT _audit_assert('346');
