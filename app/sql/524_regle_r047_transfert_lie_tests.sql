-- ============================================================
-- 524_regle_r047_transfert_lie_tests.sql — partie B, lot Stock, R-047
--
--   T01  les DEUX jambes d'un transfert (même référence) sont LIÉES ;
--   T02  un transfert SANS contrepartie ne pose aucun lien (trace « sans_effet »).
-- \ir ci/audit_helpers.sql.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '524', false);
DELETE FROM _audit_results WHERE file = '524';

CREATE OR REPLACE FUNCTION _b524(p_nom text, OUT t uuid, OUT w1 uuid, OUT w2 uuid, OUT p uuid)
LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W1-' || p_nom, 'Dépôt 1') RETURNING id INTO w1;
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W2-' || p_nom, 'Dépôt 2') RETURNING id INTO w2;
  INSERT INTO products (tenant_id, name, sku, type) VALUES (t, 'Art ' || p_nom, 'A-' || p_nom, 'stock') RETURNING id INTO p;
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type, quantity, unit_cost, reference, movement_date, date)
    VALUES (t, p, w1, 'in', 'in', 100, 5, 'INIT', CURRENT_DATE, CURRENT_DATE);
END $$;

DO $$
DECLARE x record; m1 uuid; m2 uuid; nl int; nt int;
BEGIN
  x := _b524('T01');
  PERFORM _as_user();
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type, quantity, unit_cost, reference, reference_type, movement_date, date)
    VALUES (x.t, x.p, x.w1, 'transfer', 'transfer', 10, 5, 'TRF-T01', 'transfer', CURRENT_DATE, CURRENT_DATE) RETURNING id INTO m1;
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type, quantity, unit_cost, reference, reference_type, movement_date, date)
    VALUES (x.t, x.p, x.w2, 'transfer', 'transfer', 10, 5, 'TRF-T01', 'transfer', CURRENT_DATE, CURRENT_DATE) RETURNING id INTO m2;

  SELECT count(*) INTO nl FROM document_links dl
  WHERE dl.tenant_id = x.t AND dl.effet = 'stock.transfer.linked'
    AND dl.amont_type = 'stock_movements' AND dl.aval_type = 'stock_movements';
  PERFORM _rec('T01a', 'les deux jambes du transfert sont LIÉES (1 lien)', nl = 1, format('liens=%s (1 attendu)', nl));

  SELECT count(*) INTO nt FROM chain_traces ct
  WHERE ct.tenant_id = x.t AND ct.effet = 'stock.transfer.linked' AND ct.resultat = 'applique';
  PERFORM _rec('T01b', 'le lien est tracé « applique »', nt = 1, format('traces=%s (1 attendue)', nt));
END $$;

DO $$
DECLARE x record; m uuid; nl int; nt int;
BEGIN
  x := _b524('T02');
  PERFORM _as_user();
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type, quantity, unit_cost, reference, movement_date, date)
    VALUES (x.t, x.p, x.w1, 'transfer', 'transfer', 3, 5, NULL, CURRENT_DATE, CURRENT_DATE) RETURNING id INTO m;
  SELECT count(*) INTO nl FROM document_links dl
  WHERE dl.tenant_id = x.t AND dl.effet = 'stock.transfer.linked';
  SELECT count(*) INTO nt FROM chain_traces ct
  WHERE ct.tenant_id = x.t AND ct.effet = 'stock.transfer.linked' AND ct.amont_id = m AND ct.resultat = 'sans_effet';
  PERFORM _rec('T02', 'un transfert sans contrepartie ne pose aucun lien (trace « sans_effet »)',
    nl = 0 AND nt = 1, format('liens=%s trace sans_effet=%s (0 / 1 attendus)', nl, nt));
END $$;

SELECT _audit_assert('524');