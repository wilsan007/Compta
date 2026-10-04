-- ============================================================
-- 344_production_bom_article_of_number_tests.sql — tâche 2.5 (D10, D11)
--
--   T01  une nomenclature ACTIVE sans article est refusée ; inactive, admise
--   T02  le coût proposé d'un composant est son coût moyen pondéré : stocks
--        détenus (10 à 40 € + 30 à 48 € → 46 €), à défaut le prix de revient
--   T03  le numéro d'OF est attribué par la base, et un OF REFUSÉ ne consomme
--        pas de numéro : les deux OF acceptés se suivent
--   T04  un numéro fourni (reprise, import) est respecté
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '344', false);
DELETE FROM _audit_results WHERE file = '344';

CREATE OR REPLACE FUNCTION _l344_article(p_t uuid, p_nom text, p_cout numeric)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid;
BEGIN
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
  VALUES (p_t, p_nom, left(replace(p_nom, ' ', '-'), 20) || '-' || left(uuid_generate_v4()::text, 4), 'stock', p_cout)
  RETURNING id INTO v;
  RETURN v;
END $$;

-- ── T01 ──────────────────────────────────────────────────────
DO $$
DECLARE
  t uuid := _mk_tenant('P2D10T01', false);
  v_refus boolean := false; v_inactive boolean := false;
BEGIN
  PERFORM _as_user();
  BEGIN
    INSERT INTO boms (tenant_id, code, name, product_id, quantity, active)
    VALUES (t, 'B-SANS', 'Nomenclature sans article', NULL, 1, true);
  EXCEPTION WHEN check_violation THEN v_refus := true;
  END;
  INSERT INTO boms (tenant_id, code, name, product_id, quantity, active)
  VALUES (t, 'B-BROUILLON', 'Nomenclature en préparation', NULL, 1, false);
  v_inactive := true;
  PERFORM _rec('T01', 'une nomenclature active sans article est refusée ; une nomenclature inactive (en préparation) est admise',
    v_refus AND v_inactive, format('refus de l''active=%s, inactive admise=%s', v_refus, v_inactive));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'T01 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ── T02 ──────────────────────────────────────────────────────
DO $$
DECLARE
  t uuid := _mk_tenant('P2D10T02', false);
  a uuid; b uuid; w1 uuid; w2 uuid; c_stock numeric; c_fiche numeric;
BEGIN
  a := _l344_article(t, 'Composant en stock', 99);
  b := _l344_article(t, 'Composant sans stock', 44);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W1-D10', 'Dépôt 1') RETURNING id INTO w1;
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W2-D10', 'Dépôt 2') RETURNING id INTO w2;
  INSERT INTO stock_quantities (tenant_id, product_id, warehouse_id, quantity, reserved_quantity, unit_cost)
  VALUES (t, a, w1, 10, 0, 40), (t, a, w2, 30, 0, 48);
  PERFORM _as_user();
  c_stock := product_current_cump(a);
  c_fiche := product_current_cump(b);
  PERFORM _rec('T02', 'coût proposé d''un composant : le coût moyen pondéré des stocks détenus (46,00 €, et non les 99 € de la fiche) ; sans stock, le prix de revient (44,00 €)',
    c_stock = 46 AND c_fiche = 44, format('avec stock=%s (46) sans stock=%s (44)', c_stock, c_fiche));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'T02 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ── T03 + T04 ────────────────────────────────────────────────
DO $$
DECLARE
  t uuid := _mk_tenant('P2D11T03', false);
  pf uuid; bom uuid; n1 text; n2 text; n3 text; v_refus boolean := false;
BEGIN
  pf := _l344_article(t, 'Produit fini D11', 100);
  INSERT INTO boms (tenant_id, code, name, product_id, quantity)
  VALUES (t, 'B-D11', 'Nomenclature D11', pf, 1) RETURNING id INTO bom;
  PERFORM _as_user();

  INSERT INTO manufacturing_orders (tenant_id, number, bom_id, quantity, status)
  VALUES (t, '', bom, 5, 'planned') RETURNING number INTO n1;

  -- un OF sans nomenclature ni article : refusé par la garde de l'article
  BEGIN
    INSERT INTO manufacturing_orders (tenant_id, number, bom_id, product_id, quantity, status)
    VALUES (t, '', NULL, NULL, 5, 'planned');
  EXCEPTION WHEN OTHERS THEN v_refus := true;
  END;

  INSERT INTO manufacturing_orders (tenant_id, number, bom_id, quantity, status)
  VALUES (t, '', bom, 5, 'planned') RETURNING number INTO n2;

  PERFORM _rec('T03', 'le numéro d''OF est attribué par la base, et un OF refusé ne consomme pas de numéro : les deux OF acceptés se suivent',
    n1 ~ '^OF-[0-9]{4}-[0-9]{6}$' AND v_refus
      AND right(n2, 6)::int = right(n1, 6)::int + 1,
    format('1er=%s, refus=%s, 2e=%s', n1, v_refus, n2));

  INSERT INTO manufacturing_orders (tenant_id, number, bom_id, quantity, status)
  VALUES (t, 'OF-REPRISE-42', bom, 1, 'planned') RETURNING number INTO n3;
  PERFORM _rec('T04', 'un numéro fourni (reprise, import) est respecté',
    n3 = 'OF-REPRISE-42', format('numéro=%s', n3));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'T03/T04 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

DROP FUNCTION _l344_article(uuid, text, numeric);
SELECT _audit_assert('344');
