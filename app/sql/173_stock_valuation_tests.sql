-- ============================================================
-- 173_stock_valuation_tests.sql
--
-- B8 — valeurs métier du stock, rejouées en scénarios complets sur la vraie base.
--
-- Ce que `src/__tests__/e2e-business-scenarios.test.ts` appelait « parcours bout
-- en bout » se limitait à vérifier que les tables et les fonctions existent :
-- aucune valeur n'était calculée ni comparée. Les tests ci-dessous font le
-- parcours et vérifient les montants.
--
-- Corrigé par `172_fix_stock_exit_accounting.sql` : avant, le TEST 2 échoue
-- (compte 310000 à 2 400 pour un stock valorisé 1 800).
-- ============================================================

DO $$
DECLARE
  v_tenant_id uuid := uuid_generate_v4();
  v_auth_id   uuid := uuid_generate_v4();
  v_product   uuid;
  v_warehouse uuid;
  v_customer  uuid;
  v_dn        uuid;
  v_qty       numeric;
  v_cump      numeric;
  v_stock_310 numeric;
  v_var_603   numeric;
  v_layers    numeric;
  v_n         int;
BEGIN
  -- ---------- contexte tenant ----------
  INSERT INTO auth.users (id, email) VALUES (v_auth_id, 'test@stock-valuation.com') ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claim.sub', v_auth_id::text, false);

  INSERT INTO tenants (id, name, plan, status, currency, created_at)
  VALUES (v_tenant_id, 'Test Valorisation Stock', 'trial', 'active', 'EUR', NOW());
  INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status, created_at)
  VALUES (v_tenant_id, v_auth_id, 'test@stock-valuation.com', 'Test Admin', 'admin', 'active', NOW());
  INSERT INTO company_settings (tenant_id, name, currency, country, fiscal_year_start, created_at)
  VALUES (v_tenant_id, 'Test Company', 'EUR', 'France', '2026-01-01', NOW()) ON CONFLICT DO NOTHING;
  PERFORM set_config('app.active_tenant_id', v_tenant_id::text, true);

  IF current_tenant_id() IS DISTINCT FROM v_tenant_id THEN
    RAISE EXCEPTION 'Contexte tenant non établi — le test ne prouverait rien';
  END IF;

  INSERT INTO warehouses (tenant_id, name, code) VALUES (v_tenant_id, 'Dépôt Test', 'WTEST')
  RETURNING id INTO v_warehouse;
  INSERT INTO products (tenant_id, name, sku, type, cost_price, stock_quantity)
  VALUES (v_tenant_id, 'Article Valorisation', 'SKU-VAL-TEST', 'stock', 0, 0)
  RETURNING id INTO v_product;

  -- ============================================================
  -- TEST 1 : coût unitaire moyen pondéré
  --   100 @ 10 puis 100 @ 14 → CUMP 12 ; une sortie ne change pas le CUMP
  -- ============================================================
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, type, movement_type, quantity, unit_cost, date)
  VALUES (v_tenant_id, v_product, v_warehouse, 'in', 'in', 100, 10, CURRENT_DATE);

  SELECT quantity, unit_cost INTO v_qty, v_cump
  FROM stock_quantities WHERE product_id = v_product AND warehouse_id = v_warehouse;
  IF v_qty <> 100 OR v_cump <> 10 THEN
    RAISE EXCEPTION 'TEST 1a : après 100 @ 10, attendu 100 u. à 10, obtenu % u. à %', v_qty, v_cump;
  END IF;

  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, type, movement_type, quantity, unit_cost, date)
  VALUES (v_tenant_id, v_product, v_warehouse, 'in', 'in', 100, 14, CURRENT_DATE);

  SELECT quantity, unit_cost INTO v_qty, v_cump
  FROM stock_quantities WHERE product_id = v_product AND warehouse_id = v_warehouse;
  IF v_qty <> 200 OR round(v_cump, 4) <> 12 THEN
    RAISE EXCEPTION 'TEST 1b : après 100 @ 14, attendu 200 u. à 12, obtenu % u. à %', v_qty, v_cump;
  END IF;

  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, type, movement_type, quantity, date)
  VALUES (v_tenant_id, v_product, v_warehouse, 'out', 'out', 50, CURRENT_DATE);

  SELECT quantity, unit_cost INTO v_qty, v_cump
  FROM stock_quantities WHERE product_id = v_product AND warehouse_id = v_warehouse;
  IF v_qty <> 150 OR round(v_cump, 4) <> 12 THEN
    RAISE EXCEPTION 'TEST 1c : après sortie de 50, attendu 150 u. à 12, obtenu % u. à %', v_qty, v_cump;
  END IF;
  RAISE NOTICE '✅ TEST 1 : CUMP — 100@10 puis 100@14 = 12 ; la sortie ne le modifie pas';

  -- ============================================================
  -- TEST 2 : le compte de stock suit la valorisation réelle
  --   entrées 1 000 + 1 400, sortie 50 @ 12 = 600 → 310000 doit valoir 1 800
  -- ============================================================
  SELECT COALESCE(SUM(jl.debit - jl.credit), 0) INTO v_stock_310
  FROM journal_lines jl WHERE jl.tenant_id = v_tenant_id AND jl.account_code = '310000';

  SELECT COALESCE(SUM(jl.debit - jl.credit), 0) INTO v_var_603
  FROM journal_lines jl WHERE jl.tenant_id = v_tenant_id AND jl.account_code = '603000';

  IF v_stock_310 <> 1800 THEN
    RAISE EXCEPTION 'TEST 2 : compte 310000 à % alors que le stock vaut 150 × 12 = 1 800. La sortie n''a pas été comptabilisée.', v_stock_310;
  END IF;
  IF v_stock_310 + v_var_603 <> 0 THEN
    RAISE EXCEPTION 'TEST 2 : 310000 (%) et 603000 (%) ne se compensent pas', v_stock_310, v_var_603;
  END IF;
  RAISE NOTICE '✅ TEST 2 : compte 310000 = 1 800 = valorisation du stock, contrepartie 603000 équilibrée';

  -- ============================================================
  -- TEST 3 : couches de valorisation consommées dans l'ordre FIFO
  --   sortie de 50 sur 100@10 + 100@14 → reste 50@10 et 100@14 = 1 900
  -- ============================================================
  SELECT COALESCE(SUM(remaining_qty * unit_cost), 0) INTO v_layers
  FROM stock_valuation_layers WHERE tenant_id = v_tenant_id;

  IF v_layers <> 1900 THEN
    RAISE EXCEPTION 'TEST 3 : couches à % au lieu de 1 900 (FIFO : reste 50 @ 10 et 100 @ 14)', v_layers;
  END IF;

  SELECT remaining_qty INTO v_qty
  FROM stock_valuation_layers WHERE tenant_id = v_tenant_id AND unit_cost = 10;
  IF v_qty <> 50 THEN
    RAISE EXCEPTION 'TEST 3 : la couche la plus ancienne (10) garde % au lieu de 50 — consommation non FIFO', v_qty;
  END IF;
  RAISE NOTICE '✅ TEST 3 : couches FIFO — la plus ancienne consommée en premier, reste 1 900';

  -- ============================================================
  -- TEST 4 : parcours bon de livraison → sortie de stock → écriture
  -- ============================================================
  INSERT INTO customers (name, tenant_id, balance, credit_used)
  VALUES ('Client Livraison', v_tenant_id, 0, 0) RETURNING id INTO v_customer;

  INSERT INTO delivery_notes (tenant_id, number, customer_id, delivery_date, status)
  VALUES (v_tenant_id, 'BL-VAL-1', v_customer, CURRENT_DATE, 'pending') RETURNING id INTO v_dn;

  INSERT INTO delivery_note_lines (tenant_id, delivery_note_id, product_id, description, quantity)
  VALUES (v_tenant_id, v_dn, v_product, 'Article Valorisation', 30);

  -- STK-01 : la sortie se déclenche au passage à 'shipped', pas à 'delivered'
  UPDATE delivery_notes SET status = 'shipped' WHERE id = v_dn;

  SELECT count(*) INTO v_n
  FROM stock_movements WHERE tenant_id = v_tenant_id AND reference_id = v_dn AND movement_type = 'out';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'TEST 4 : le bon de livraison n''a pas produit de sortie de stock (% mouvement(s))', v_n;
  END IF;

  SELECT quantity INTO v_qty FROM stock_quantities WHERE product_id = v_product AND warehouse_id = v_warehouse;

  SELECT COALESCE(SUM(jl.debit - jl.credit), 0) INTO v_stock_310
  FROM journal_lines jl WHERE jl.tenant_id = v_tenant_id AND jl.account_code = '310000';

  -- La sortie du BL n'a pas d'entrepôt : elle décrémente products.stock_quantity
  -- mais pas stock_quantities. Le compte, lui, doit avoir bougé de 30 × 12 = 360.
  IF v_stock_310 <> 1440 THEN
    RAISE EXCEPTION 'TEST 4 : après livraison de 30 @ 12, compte 310000 à % au lieu de 1 440', v_stock_310;
  END IF;
  RAISE NOTICE '✅ TEST 4 : livraison de 30 → sortie de stock comptabilisée 360, compte 310000 à 1 440';

  -- ============================================================
  -- Nettoyage (triggers désactivés : les écritures validées sont immuables)
  -- ============================================================
  SET session_replication_role = 'replica';

  DELETE FROM stock_valuation_layers WHERE tenant_id = v_tenant_id;
  DELETE FROM journal_lines WHERE tenant_id = v_tenant_id;
  DELETE FROM journal_entries WHERE tenant_id = v_tenant_id;
  DELETE FROM stock_movements WHERE tenant_id = v_tenant_id;
  DELETE FROM stock_quantities WHERE tenant_id = v_tenant_id;
  DELETE FROM delivery_note_lines WHERE tenant_id = v_tenant_id;
  DELETE FROM delivery_notes WHERE tenant_id = v_tenant_id;
  DELETE FROM customers WHERE tenant_id = v_tenant_id;
  DELETE FROM products WHERE tenant_id = v_tenant_id;
  DELETE FROM warehouses WHERE tenant_id = v_tenant_id;
  DELETE FROM company_settings WHERE tenant_id = v_tenant_id;
  DELETE FROM tenant_users WHERE tenant_id = v_tenant_id;
  DELETE FROM tenants WHERE id = v_tenant_id;
  DELETE FROM auth.users WHERE id = v_auth_id;
  PERFORM set_config('request.jwt.claim.sub', '', false);

  SET session_replication_role = 'origin';

  RAISE NOTICE '';
  RAISE NOTICE '🎉 TESTS DE VALORISATION DU STOCK : 4/4 RÉUSSIS';

EXCEPTION WHEN OTHERS THEN
  SET session_replication_role = 'origin';
  RAISE EXCEPTION '❌ ÉCHEC DES TESTS DE VALORISATION : %', SQLERRM;
END $$;
