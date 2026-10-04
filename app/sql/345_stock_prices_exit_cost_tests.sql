-- ============================================================
-- 345_stock_prices_exit_cost_tests.sql — tâche 2.7 (D6, D7)
--
--   T01  un article à prix de vente ou d'achat négatif est refusé
--   T02  une sortie sans coût porte le coût moyen du dépôt (100 à 10 € +
--        100 à 14 € → 12 €) — elle affichait 0,00 €
--   T03  le mouvement et l'écriture comptable disent le MÊME montant
--   T04  un coût fourni à la sortie est respecté
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '345', false);
DELETE FROM _audit_results WHERE file = '345';

CREATE OR REPLACE FUNCTION _l345_mvt(p_t uuid, p_p uuid, p_wh uuid, p_type text, p_qte numeric, p_cout numeric)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE m uuid;
BEGIN
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type,
    quantity, unit_cost, reference, movement_date, date)
  VALUES (p_t, p_p, p_wh, p_type, p_type, p_qte, p_cout,
          'MV345-' || p_type || '-' || p_qte || '-' || COALESCE(p_cout::text, 'x'), CURRENT_DATE, CURRENT_DATE)
  RETURNING id INTO m;
  RETURN m;
END $$;

-- ── T01 ──────────────────────────────────────────────────────
DO $$
DECLARE
  t uuid := _mk_tenant('P2D6T01', false);
  v_vente boolean := false; v_achat boolean := false;
BEGIN
  PERFORM _as_user();
  BEGIN
    INSERT INTO products (tenant_id, name, sku, type, sale_price) VALUES (t, 'Prix de vente négatif', 'D6-V', 'stock', -10);
  EXCEPTION WHEN check_violation THEN v_vente := true;
  END;
  BEGIN
    INSERT INTO products (tenant_id, name, sku, type, purchase_price) VALUES (t, 'Prix d''achat négatif', 'D6-A', 'stock', -10);
  EXCEPTION WHEN check_violation THEN v_achat := true;
  END;
  PERFORM _rec('T01', 'un article à prix négatif est refusé (vente comme achat)',
    v_vente AND v_achat, format('refus vente=%s achat=%s', v_vente, v_achat));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'T01 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ── T02 + T03 + T04 ──────────────────────────────────────────
DO $$
DECLARE
  t uuid := _mk_tenant('P2D7T02');
  p uuid; wh uuid; m uuid; m2 uuid; c numeric; c2 numeric; v_ecriture numeric;
BEGIN
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-D7', 'Dépôt D7') RETURNING id INTO wh;
  INSERT INTO products (tenant_id, name, sku, type) VALUES (t, 'Article D7', 'D7-A1', 'stock') RETURNING id INTO p;
  PERFORM _l345_mvt(t, p, wh, 'in', 100, 10);
  PERFORM _l345_mvt(t, p, wh, 'in', 100, 14);
  m := _l345_mvt(t, p, wh, 'out', 50, NULL);
  SELECT unit_cost INTO c FROM stock_movements WHERE id = m;
  PERFORM _rec('T02', 'une sortie sans coût porte le coût moyen pondéré du dépôt (12,00 €), au lieu de 0',
    c = 12, format('unit_cost de la sortie=%s (12 attendu)', c));

  SELECT COALESCE(sum(l.debit), 0) INTO v_ecriture
    FROM journal_entries e JOIN journal_lines l ON l.journal_id = e.id
   WHERE e.tenant_id = t AND e.piece_number = 'STK-' || m::text;
  PERFORM _rec('T03', 'le mouvement et le grand livre disent le même montant : 50 × 12 = 600,00 €',
    v_ecriture = 600 AND round(50 * c, 2) = v_ecriture,
    format('écriture=%s, mouvement=%s', v_ecriture, round(50 * c, 2)));

  m2 := _l345_mvt(t, p, wh, 'out', 10, 11.5);
  SELECT unit_cost INTO c2 FROM stock_movements WHERE id = m2;
  PERFORM _rec('T04', 'un coût fourni à la sortie est respecté (11,50 €)',
    c2 = 11.5, format('unit_cost=%s', c2));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'T02 à T04 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

DROP FUNCTION _l345_mvt(uuid, uuid, uuid, text, numeric, numeric);
SELECT _audit_assert('345');
