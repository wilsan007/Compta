-- ============================================================
-- 661_mo_operations_shop_floor_tests.sql — PRD-06 / E.5
--
-- Mesuré AVANT la 661 : `mo_operations` ne recevait rien et ne servait à rien.
-- Après : l'atelier déclare ses opérations (temps réel, quantités, rebuts) et
-- le récapitulatif de l'OF les additionne — sans jamais toucher au stock.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '661', false);
DELETE FROM _audit_results WHERE file = '661';

CREATE OR REPLACE FUNCTION _mk661(p_nom text, OUT t uuid, OUT wh uuid, OUT p uuid, OUT mo uuid) LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom, false);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt ' || p_nom) RETURNING id INTO wh;
  INSERT INTO products (tenant_id, name, sku, type, cost_price) VALUES (t, 'PF ' || p_nom, 'PF-' || p_nom, 'stock', 10) RETURNING id INTO p;
  INSERT INTO manufacturing_orders (tenant_id, number, product_id, quantity, status, warehouse_id)
    VALUES (t, 'OF-' || p_nom, p, 100, 'planned', wh) RETURNING id INTO mo;
END $$;

-- T01 — deux opérations déclarées : le récapitulatif les additionne
DO $$
DECLARE t uuid; wh uuid; p uuid; mo uuid; r record;
BEGIN
  SELECT * INTO t, wh, p, mo FROM _mk661('VAL661T01');
  PERFORM record_mo_operation(mo, 'Coupe', 30, 32, 60, 0, NULL);
  PERFORM record_mo_operation(mo, 'Assemblage', 45, 50, 55, 5, 'bavure');
  SELECT * INTO r FROM mo_operations_summary(mo);
  PERFORM _rec('T01', 'deux opérations : minutes réelles, produites, rebuts et taux de rebut',
    (r.nb_operations = 2 AND r.planned_minutes = 75 AND r.actual_minutes = 82
     AND r.produced = 115 AND r.scrapped = 5 AND r.scrap_rate = 4.17),
    format('nb=%s, prévu=%s, réel=%s, produites=%s, rebuts=%s, taux=%s (2/75/82/115/5/4.17)',
           r.nb_operations, r.planned_minutes, r.actual_minutes, r.produced, r.scrapped, r.scrap_rate));
END $$;

-- T02 — rejouer une opération la corrige, elle ne la double pas
DO $$
DECLARE t uuid; wh uuid; p uuid; mo uuid; r record;
BEGIN
  SELECT * INTO t, wh, p, mo FROM _mk661('VAL661T02');
  PERFORM record_mo_operation(mo, 'Coupe', 30, 32, 60, 0, NULL);
  PERFORM record_mo_operation(mo, 'Coupe', 30, 40, 60, 0, NULL);
  SELECT * INTO r FROM mo_operations_summary(mo);
  PERFORM _rec('T02', 'rejouer « Coupe » corrige le temps réel au lieu de créer une 2e ligne',
    (r.nb_operations = 1 AND r.actual_minutes = 40),
    format('nb=%s, réel=%s (1/40)', r.nb_operations, r.actual_minutes));
END $$;

-- T03 — un OF annulé refuse la déclaration
DO $$
DECLARE t uuid; wh uuid; p uuid; mo uuid; v_ok boolean := false; v_msg text;
BEGIN
  SELECT * INTO t, wh, p, mo FROM _mk661('VAL661T03');
  UPDATE manufacturing_orders SET status = 'cancelled' WHERE id = mo;
  BEGIN
    PERFORM record_mo_operation(mo, 'Coupe', 30, 32, 60, 0, NULL);
  EXCEPTION WHEN OTHERS THEN
    v_ok := (SQLERRM LIKE '%annulé%'); v_msg := SQLERRM;
  END;
  PERFORM _rec('T03', 'un OF annulé refuse la déclaration', v_ok, COALESCE(v_msg, 'aucune erreur levée'));
END $$;

SELECT _audit_assert('661');
