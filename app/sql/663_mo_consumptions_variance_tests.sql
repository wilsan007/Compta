-- ============================================================
-- 663_mo_consumptions_variance_tests.sql — PRD-06 / E.5
--
-- Mesuré AVANT la 663 : le prévu (`manufacturing_requirements`) et le réel
-- (mouvements de production) existaient, mais **rien ne les confrontait** —
-- l'écart de matière ne se lisait nulle part. Après : il est figé et lisible.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '663', false);
DELETE FROM _audit_results WHERE file = '663';

-- PF = 2 × C1 + 3 × C2 (nomenclature pour 1 PF)
CREATE OR REPLACE FUNCTION _mk663(p_nom text, OUT t uuid, OUT wh uuid, OUT c1 uuid, OUT c2 uuid, OUT mo uuid)
LANGUAGE plpgsql AS $$
DECLARE pf uuid; b uuid;
BEGIN
  t := _mk_tenant(p_nom, false);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt') RETURNING id INTO wh;
  INSERT INTO products (tenant_id, name, sku, type, cost_price) VALUES (t, 'PF ' || p_nom, 'PF-' || p_nom, 'stock', 0) RETURNING id INTO pf;
  INSERT INTO products (tenant_id, name, sku, type, cost_price) VALUES (t, 'C1 ' || p_nom, 'C1-' || p_nom, 'stock', 5) RETURNING id INTO c1;
  INSERT INTO products (tenant_id, name, sku, type, cost_price) VALUES (t, 'C2 ' || p_nom, 'C2-' || p_nom, 'stock', 10) RETURNING id INTO c2;
  INSERT INTO boms (tenant_id, code, name, product_id, quantity) VALUES (t, 'B-' || p_nom, 'Nomenclature', pf, 1) RETURNING id INTO b;
  INSERT INTO bom_lines (tenant_id, bom_id, product_id, quantity, unit_cost) VALUES (t, b, c1, 2, 5), (t, b, c2, 3, 10);
  INSERT INTO manufacturing_orders (tenant_id, number, bom_id, product_id, quantity, status, warehouse_id)
    VALUES (t, 'OF-' || p_nom, b, pf, 10, 'planned', wh) RETURNING id INTO mo;
END $$;

-- Du stock, puis une sortie de production rattachée à l'OF (le « réel »).
-- Le moteur de stock (`240`) lit d'abord `products.stock_quantity` : c'est cette
-- colonne qu'on approvisionne, le localisé se crée ensuite tout seul.
CREATE OR REPLACE FUNCTION _out663(p_t uuid, p_wh uuid, p_mo uuid, p_produit uuid, p_qte numeric)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  UPDATE products SET stock_quantity = COALESCE(stock_quantity, 0) + 1000
  WHERE id = p_produit AND tenant_id = p_t;
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type,
                               quantity, unit_cost, reference, movement_date, date,
                               reference_type, reference_id)
  VALUES (p_t, p_produit, p_wh, 'out', 'out', p_qte, 1, 'CONS', CURRENT_DATE, CURRENT_DATE,
          'production', p_mo);
END $$;

-- T01 — le prévu vient de la nomenclature : 10 PF = 20 C1 + 30 C2
DO $$
DECLARE t uuid; wh uuid; c1 uuid; c2 uuid; mo uuid; n int; q1 numeric; q2 numeric;
BEGIN
  SELECT * INTO t, wh, c1, c2, mo FROM _mk663('VAL663T01');
  PERFORM _out663(t, wh, mo, c1, 22);
  PERFORM _out663(t, wh, mo, c2, 28);
  n := refresh_mo_consumptions(mo);
  SELECT theoretical_quantity INTO q1 FROM mo_consumptions WHERE manufacturing_order_id = mo AND product_id = c1;
  SELECT theoretical_quantity INTO q2 FROM mo_consumptions WHERE manufacturing_order_id = mo AND product_id = c2;
  PERFORM _rec('T01', 'le prévu vient de la nomenclature : 10 PF = 20 C1 + 30 C2',
    (n = 2 AND q1 = 20 AND q2 = 30), format('lignes=%s, C1=%s (20), C2=%s (30)', n, q1, q2));
END $$;

-- T02 — le réel vient des mouvements : 22 C1 et 28 C2 → écarts +2 et −2
DO $$
DECLARE t uuid; wh uuid; c1 uuid; c2 uuid; mo uuid; e1 numeric; e2 numeric; p1 numeric; p2 numeric;
BEGIN
  SELECT * INTO t, wh, c1, c2, mo FROM _mk663('VAL663T02');
  PERFORM _out663(t, wh, mo, c1, 22);
  PERFORM _out663(t, wh, mo, c2, 28);
  PERFORM refresh_mo_consumptions(mo);
  SELECT variance_quantity, variance_percent INTO e1, p1 FROM mo_consumption_variance(mo) WHERE product_id = c1;
  SELECT variance_quantity, variance_percent INTO e2, p2 FROM mo_consumption_variance(mo) WHERE product_id = c2;
  PERFORM _rec('T02', 'écart = réel − prévu : +2 sur C1 (+10 %) et −2 sur C2 (−6,67 %)',
    (e1 = 2 AND p1 = 10 AND e2 = -2 AND p2 = -6.67),
    format('C1 : %s (%s %%), C2 : %s (%s %%) (+2/10, -2/-6.67)', e1, p1, e2, p2));
END $$;

-- T03 — rejouer le rafraîchissement met à jour, ça ne double pas
DO $$
DECLARE t uuid; wh uuid; c1 uuid; c2 uuid; mo uuid; n bigint; r int; e1 numeric; e2 numeric;
BEGIN
  SELECT * INTO t, wh, c1, c2, mo FROM _mk663('VAL663T03');
  PERFORM _out663(t, wh, mo, c1, 22);
  PERFORM _out663(t, wh, mo, c2, 28);
  PERFORM refresh_mo_consumptions(mo);
  -- Le moteur de stock n'admet qu'une sortie par (OF, article) : rejouer le
  -- rafraîchissement est donc la seule façon de recalculer — et il doit rester
  -- deux lignes, avec les mêmes écarts.
  r := refresh_mo_consumptions(mo);
  SELECT count(*) INTO n FROM mo_consumptions WHERE manufacturing_order_id = mo;
  SELECT variance_quantity INTO e1 FROM mo_consumptions WHERE manufacturing_order_id = mo AND product_id = c1;
  SELECT variance_quantity INTO e2 FROM mo_consumptions WHERE manufacturing_order_id = mo AND product_id = c2;
  PERFORM _rec('T03', 'rejouer le rafraîchissement laisse 2 lignes, sans doublon ni dérive',
    (r = 2 AND n = 2 AND e1 = 2 AND e2 = -2),
    format('lignes écrites=%s, lignes en base=%s, écarts=%s/%s (2/2/+2/-2)', r, n, e1, e2));
END $$;

-- T04 — un OF inconnu est refusé
DO $$
DECLARE t uuid; wh uuid; c1 uuid; c2 uuid; mo uuid; v_ok boolean := false; v_msg text;
BEGIN
  SELECT * INTO t, wh, c1, c2, mo FROM _mk663('VAL663T04');
  BEGIN
    PERFORM refresh_mo_consumptions('00000000-0000-0000-0000-000000000000'::uuid);
  EXCEPTION WHEN OTHERS THEN
    v_ok := (SQLERRM LIKE '%introuvable%'); v_msg := SQLERRM;
  END;
  PERFORM _rec('T04', 'un OF inconnu est refusé', v_ok, COALESCE(v_msg, 'aucune erreur levée'));
END $$;

SELECT _audit_assert('663');
