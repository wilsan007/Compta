-- ============================================================
-- 177_manufacturing_cost_tests.sql
--
-- B9 — MRP et coût de revient, rejoués en scénario complet sur la vraie base.
--
-- Scénario : composants C1 (100 @ 10) et C2 (100 @ 20), nomenclature
-- 2 × C1 + 1 × C2 par unité, gamme à 60 €/h avec 30 min de réglage et 12 min
-- par unité, taux de frais généraux 20 %, ordre de fabrication de 5 unités.
--
--   matières  5 × (2×10 + 1×20)        = 200
--   main-d'œuvre (30 + 12×5)/60 × 60   =  90
--   frais généraux 90 × 0,20           =  18
--   total 308, soit 61,60 l'unité
--
-- Avant `176_fix_production_double_entry.sql`, le TEST 4 échoue : les mêmes
-- faits étaient écrits dans le journal OF *et* dans le journal ST, laissant
-- 108 de stock fantôme au compte 310000.
-- ============================================================

\ir ci/ledger_fixture.sql

DO $$
DECLARE
  v_tenant_id uuid := uuid_generate_v4();
  v_auth_id   uuid := uuid_generate_v4();
  v_w uuid; v_c1 uuid; v_c2 uuid; v_pf uuid;
  v_bom uuid; v_rt uuid; v_wc uuid; v_mo uuid;
  v_cost jsonb;
  v_qty numeric; v_unit numeric;
  v_310 numeric; v_355 numeric; v_physique numeric;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_auth_id, 'test@manufacturing.com') ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claim.sub', v_auth_id::text, false);
  INSERT INTO tenants (id, name, plan, status, currency, created_at)
  VALUES (v_tenant_id, 'Test Production', 'trial', 'active', 'EUR', NOW());
  INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status, created_at)
  VALUES (v_tenant_id, v_auth_id, 'test@manufacturing.com', 'Test Admin', 'admin', 'active', NOW());
  INSERT INTO company_settings (tenant_id, name, currency, country, fiscal_year_start, overhead_rate, created_at)
  VALUES (v_tenant_id, 'Test Company', 'EUR', 'France', '2026-01-01', 0.2, NOW()) ON CONFLICT DO NOTHING;
  PERFORM _ledger_fixture(v_tenant_id);  -- plan, journaux, exercice (187)
  PERFORM set_config('app.active_tenant_id', v_tenant_id::text, true);

  IF current_tenant_id() IS DISTINCT FROM v_tenant_id THEN
    RAISE EXCEPTION 'Contexte tenant non établi — le test ne prouverait rien';
  END IF;

  INSERT INTO warehouses (tenant_id, name, code) VALUES (v_tenant_id, 'Atelier Test', 'WPROD') RETURNING id INTO v_w;
  INSERT INTO products (tenant_id, name, sku, type) VALUES (v_tenant_id, 'Composant 1', 'C1-TEST', 'stock') RETURNING id INTO v_c1;
  INSERT INTO products (tenant_id, name, sku, type) VALUES (v_tenant_id, 'Composant 2', 'C2-TEST', 'stock') RETURNING id INTO v_c2;
  INSERT INTO products (tenant_id, name, sku, type) VALUES (v_tenant_id, 'Produit fini', 'PF-TEST', 'stock') RETURNING id INTO v_pf;

  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, type, movement_type, quantity, unit_cost, date)
  VALUES (v_tenant_id, v_c1, v_w, 'in', 'in', 100, 10, CURRENT_DATE),
         (v_tenant_id, v_c2, v_w, 'in', 'in', 100, 20, CURRENT_DATE);

  INSERT INTO boms (tenant_id, code, name, product_id) VALUES (v_tenant_id, 'BOM-TEST', 'Nomenclature', v_pf) RETURNING id INTO v_bom;
  INSERT INTO bom_lines (tenant_id, bom_id, product_id, quantity) VALUES (v_tenant_id, v_bom, v_c1, 2), (v_tenant_id, v_bom, v_c2, 1);

  INSERT INTO work_centers (tenant_id, code, name, cost_per_hour) VALUES (v_tenant_id, 'WC-TEST', 'Poste', 60) RETURNING id INTO v_wc;
  INSERT INTO routings (tenant_id, code, name, product_id) VALUES (v_tenant_id, 'RT-TEST', 'Gamme', v_pf) RETURNING id INTO v_rt;
  INSERT INTO routing_operations (tenant_id, routing_id, sequence, name, work_center_id, setup_time_min, run_time_min)
  VALUES (v_tenant_id, v_rt, 1, 'Assemblage', v_wc, 30, 12);

  INSERT INTO manufacturing_orders (tenant_id, number, quantity, status, product_id, bom_id, routing_id, warehouse_id)
  VALUES (v_tenant_id, 'OF-TEST-1', 5, 'planned', v_pf, v_bom, v_rt, v_w) RETURNING id INTO v_mo;

  -- ============================================================
  -- TEST 1 : décomposition du coût de revient
  -- ============================================================
  v_cost := calculate_manufacturing_cost(v_mo, v_tenant_id);
  IF NOT (v_cost->>'success')::boolean THEN
    RAISE EXCEPTION 'TEST 1 : calcul en échec — %', v_cost->>'error';
  END IF;
  IF (v_cost->>'cost_material')::numeric <> 200 THEN
    RAISE EXCEPTION 'TEST 1 : matières à % au lieu de 200', v_cost->>'cost_material';
  END IF;
  IF (v_cost->>'cost_labor')::numeric <> 90 THEN
    RAISE EXCEPTION 'TEST 1 : main-d''œuvre à % au lieu de 90', v_cost->>'cost_labor';
  END IF;
  IF (v_cost->>'cost_overhead')::numeric <> 18 THEN
    RAISE EXCEPTION 'TEST 1 : frais généraux à % au lieu de 18', v_cost->>'cost_overhead';
  END IF;
  IF round((v_cost->>'unit_cost')::numeric, 2) <> 61.60 THEN
    RAISE EXCEPTION 'TEST 1 : coût unitaire à % au lieu de 61,60', v_cost->>'unit_cost';
  END IF;
  RAISE NOTICE '✅ TEST 1 : coût de revient — matières 200, MO 90, frais 18, total 308, unitaire 61,60';

  -- ============================================================
  -- TEST 2 : clôture de l'OF — composants consommés, produit fini entré
  -- ============================================================
  UPDATE manufacturing_orders SET status = 'completed' WHERE id = v_mo;

  SELECT quantity INTO v_qty FROM stock_quantities WHERE product_id = v_c1 AND warehouse_id = v_w;
  IF v_qty <> 90 THEN RAISE EXCEPTION 'TEST 2 : C1 à % au lieu de 90 (2 × 5 consommés)', v_qty; END IF;
  SELECT quantity INTO v_qty FROM stock_quantities WHERE product_id = v_c2 AND warehouse_id = v_w;
  IF v_qty <> 95 THEN RAISE EXCEPTION 'TEST 2 : C2 à % au lieu de 95 (1 × 5 consommés)', v_qty; END IF;

  SELECT quantity, unit_cost INTO v_qty, v_unit FROM stock_quantities WHERE product_id = v_pf AND warehouse_id = v_w;
  IF v_qty <> 5 THEN RAISE EXCEPTION 'TEST 2 : produit fini à % unités au lieu de 5', v_qty; END IF;
  IF round(v_unit, 2) <> 61.60 THEN
    RAISE EXCEPTION 'TEST 2 : produit fini valorisé % au lieu de 61,60', v_unit;
  END IF;
  RAISE NOTICE '✅ TEST 2 : composants consommés (C1 90, C2 95), 5 produits finis entrés à 61,60';

  -- ============================================================
  -- TEST 3 : l'écriture de production est équilibrée
  -- ============================================================
  SELECT COALESCE(SUM(jl.debit - jl.credit), 0) INTO v_310
  FROM journal_entries je JOIN journal_lines jl ON jl.journal_id = je.id
  WHERE je.tenant_id = v_tenant_id AND je.journal_code = 'OF';
  IF v_310 <> 0 THEN RAISE EXCEPTION 'TEST 3 : écriture de production déséquilibrée (%)', v_310; END IF;

  SELECT COALESCE(SUM(jl.debit - jl.credit), 0) INTO v_355
  FROM journal_lines jl WHERE jl.tenant_id = v_tenant_id AND jl.account_code = '355000';
  IF v_355 <> 308 THEN
    RAISE EXCEPTION 'TEST 3 : produits finis (355000) à % au lieu de 308', v_355;
  END IF;
  RAISE NOTICE '✅ TEST 3 : écriture de production équilibrée, 355000 à 308';

  -- ============================================================
  -- TEST 4 : le compte de stock suit le stock physique
  --   Sans le correctif 176, les mouvements de production étaient
  --   comptabilisés deux fois : 310000 à −92 au lieu de −200 sur l'OF,
  --   soit 108 de stock fantôme.
  -- ============================================================
  SELECT COALESCE(SUM(jl.debit - jl.credit), 0) INTO v_310
  FROM journal_lines jl WHERE jl.tenant_id = v_tenant_id AND jl.account_code = '310000';

  SELECT COALESCE(SUM(sq.quantity * sq.unit_cost), 0) INTO v_physique
  FROM stock_quantities sq WHERE sq.tenant_id = v_tenant_id AND sq.product_id IN (v_c1, v_c2);

  IF round(v_310, 2) <> round(v_physique, 2) THEN
    RAISE EXCEPTION 'TEST 4 : compte 310000 à % alors que les matières en stock valent % (écart %)',
      v_310, v_physique, v_310 - v_physique;
  END IF;
  RAISE NOTICE '✅ TEST 4 : compte 310000 = % = valeur des matières en stock, aucun doublon', v_310;

  -- ============================================================
  -- Nettoyage
  -- ============================================================
  SET session_replication_role = 'replica';
  DELETE FROM stock_valuation_layers WHERE tenant_id = v_tenant_id;
  DELETE FROM journal_lines WHERE tenant_id = v_tenant_id;
  DELETE FROM journal_entries WHERE tenant_id = v_tenant_id;
  DELETE FROM stock_movements WHERE tenant_id = v_tenant_id;
  DELETE FROM stock_quantities WHERE tenant_id = v_tenant_id;
  DELETE FROM manufacturing_orders WHERE tenant_id = v_tenant_id;
  DELETE FROM routing_operations WHERE tenant_id = v_tenant_id;
  DELETE FROM routings WHERE tenant_id = v_tenant_id;
  DELETE FROM work_centers WHERE tenant_id = v_tenant_id;
  DELETE FROM bom_lines WHERE tenant_id = v_tenant_id;
  DELETE FROM boms WHERE tenant_id = v_tenant_id;
  DELETE FROM products WHERE tenant_id = v_tenant_id;
  DELETE FROM warehouses WHERE tenant_id = v_tenant_id;
  DELETE FROM company_settings WHERE tenant_id = v_tenant_id;
  DELETE FROM tenant_users WHERE tenant_id = v_tenant_id;
  DELETE FROM tenants WHERE id = v_tenant_id;
  DELETE FROM auth.users WHERE id = v_auth_id;
  PERFORM set_config('request.jwt.claim.sub', '', false);
  SET session_replication_role = 'origin';

  RAISE NOTICE '';
  RAISE NOTICE '🎉 TESTS DE COÛT DE REVIENT : 4/4 RÉUSSIS';

EXCEPTION WHEN OTHERS THEN
  SET session_replication_role = 'origin';
  RAISE EXCEPTION '❌ ÉCHEC DES TESTS DE COÛT DE REVIENT : %', SQLERRM;
END $$;
