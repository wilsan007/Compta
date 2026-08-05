-- ============================================
-- SEED DATA FOR LANDING PAGE SCREENSHOTS
-- Modules: Commercial (sales orders), Projects, Production
-- Run after seed_demo_data.sql
-- ============================================

DO $$
DECLARE
  v_tenant_id uuid;
  v_customer_1 uuid;
  v_customer_2 uuid;
  v_customer_3 uuid;
  v_product_1 uuid;
  v_product_2 uuid;
  v_product_3 uuid;
  v_warehouse_1 uuid;
  v_project_1 uuid;
  v_project_2 uuid;
  v_project_3 uuid;
  v_employee_1 uuid;
  v_employee_2 uuid;
  v_employee_3 uuid;
  v_bom_1 uuid;
  v_so_1 uuid;
  v_so_2 uuid;
  v_mo_1 uuid;
  v_mo_2 uuid;
  v_mo_3 uuid;
BEGIN
  -- Use "entreprise test" tenant (user: test@demo.dj)
  SELECT id INTO v_tenant_id FROM tenants WHERE id = 'cea61d0c-4b2b-4c37-a6df-2c0d18b2f809' LIMIT 1;
  IF v_tenant_id IS NULL THEN
    -- Fallback: use the most recent tenant
    SELECT id INTO v_tenant_id FROM tenants ORDER BY created_at DESC LIMIT 1;
  END IF;
  IF v_tenant_id IS NULL THEN
    RAISE NOTICE 'No tenant found. Run seed_demo_data.sql first.';
    RETURN;
  END IF;

  -- Enable production + stock + projectManagement modules on this tenant (needed for screenshots)
  UPDATE tenants 
  SET enabled_modules = enabled_modules || '["projectManagement","production","stock"]'::jsonb
  WHERE id = v_tenant_id;

  -- Get existing seeded data (or create if missing)
  SELECT id INTO v_customer_1 FROM customers WHERE tenant_id = v_tenant_id ORDER BY name LIMIT 1 OFFSET 0;
  SELECT id INTO v_customer_2 FROM customers WHERE tenant_id = v_tenant_id ORDER BY name LIMIT 1 OFFSET 1;
  SELECT id INTO v_customer_3 FROM customers WHERE tenant_id = v_tenant_id ORDER BY name LIMIT 1 OFFSET 2;
  SELECT id INTO v_warehouse_1 FROM warehouses WHERE tenant_id = v_tenant_id ORDER BY name LIMIT 1;

  -- Get or create employees
  SELECT id INTO v_employee_1 FROM employees WHERE tenant_id = v_tenant_id ORDER BY name LIMIT 1 OFFSET 0;
  SELECT id INTO v_employee_2 FROM employees WHERE tenant_id = v_tenant_id ORDER BY name LIMIT 1 OFFSET 1;
  SELECT id INTO v_employee_3 FROM employees WHERE tenant_id = v_tenant_id ORDER BY name LIMIT 1 OFFSET 2;

  -- Ensure products exist (create if missing)
  SELECT id INTO v_product_1 FROM products WHERE tenant_id = v_tenant_id AND sku = 'SRV-001' LIMIT 1;
  IF v_product_1 IS NULL THEN
    INSERT INTO products (id, name, sku, description, type, sale_price, purchase_price, vat_rate, stock_quantity, unit, category, active, tenant_id)
    VALUES (gen_random_uuid(), 'Consultation comptable', 'SRV-001', 'Prestation comptable horaire', 'service', 120.00, 0, 19.0, 0, 'heure', 'Services', true, v_tenant_id)
    RETURNING id INTO v_product_1;
  END IF;

  SELECT id INTO v_product_2 FROM products WHERE tenant_id = v_tenant_id AND sku = 'PROD-ERP' LIMIT 1;
  IF v_product_2 IS NULL THEN
    INSERT INTO products (id, name, sku, description, type, sale_price, purchase_price, vat_rate, stock_quantity, unit, category, active, tenant_id)
    VALUES (gen_random_uuid(), 'Logiciel ERP licence annuelle', 'PROD-ERP', 'Licence annuelle ERP', 'stock', 2400.00, 800.00, 19.0, 50, 'licence', 'Logiciels', true, v_tenant_id)
    RETURNING id INTO v_product_2;
  END IF;

  SELECT id INTO v_product_3 FROM products WHERE tenant_id = v_tenant_id AND sku = 'SRV-FORM' LIMIT 1;
  IF v_product_3 IS NULL THEN
    INSERT INTO products (id, name, sku, description, type, sale_price, purchase_price, vat_rate, stock_quantity, unit, category, active, tenant_id)
    VALUES (gen_random_uuid(), 'Formation utilisateurs', 'SRV-FORM', 'Formation 1 jour', 'service', 800.00, 0, 19.0, 0, 'jour', 'Formations', true, v_tenant_id)
    RETURNING id INTO v_product_3;
  END IF;

  RAISE NOTICE 'Products ready: %, %, %', v_product_1, v_product_2, v_product_3;

  RAISE NOTICE 'Seeding landing page screenshot data for tenant: %', v_tenant_id;

  -- ============================================
  -- 1. COMMERCIAL: Sales Orders
  -- ============================================
  -- Delete by number first (unique constraint is global, not per-tenant)
  DELETE FROM sales_order_lines WHERE sales_order_id IN (SELECT id FROM sales_orders WHERE number LIKE 'CMD-2026-%');
  DELETE FROM sales_orders WHERE number LIKE 'CMD-2026-%';
  DELETE FROM sales_order_lines WHERE tenant_id = v_tenant_id;
  DELETE FROM sales_orders WHERE tenant_id = v_tenant_id;

  -- Sales Order 1: Confirmed
  INSERT INTO sales_orders (id, tenant_id, number, customer_id, order_date, delivery_date, status, subtotal, vat, total, notes, created_at, updated_at)
  VALUES (
    gen_random_uuid(), v_tenant_id, 'CMD-2026-001',
    v_customer_1, '2026-01-15', '2026-02-15', 'confirmed',
    1250000, 237500, 1487500, 'Commande ferme - livraison prévue février',
    NOW(), NOW()
  ) RETURNING id INTO v_so_1;

  INSERT INTO sales_order_lines (id, sales_order_id, tenant_id, product_id, description, quantity, unit_price, vat_rate, line_total)
  VALUES
    (gen_random_uuid(), v_so_1, v_tenant_id, v_product_1, 'Licence Onusuite Comptabilité - 5 postes', 5, 150000, 19, 750000),
    (gen_random_uuid(), v_so_1, v_tenant_id, v_product_2, 'Module Commercial - 3 postes', 3, 100000, 19, 300000),
    (gen_random_uuid(), v_so_1, v_tenant_id, v_product_3, 'Formation utilisateurs (2 jours)', 1, 200000, 19, 200000);

  -- Sales Order 2: Delivered
  INSERT INTO sales_orders (id, tenant_id, number, customer_id, order_date, delivery_date, status, subtotal, vat, total, notes, created_at, updated_at)
  VALUES (
    gen_random_uuid(), v_tenant_id, 'CMD-2026-002',
    v_customer_2, '2026-01-10', '2026-01-25', 'delivered',
    450000, 85500, 535500, 'Livré - facture à émettre',
    NOW(), NOW()
  ) RETURNING id INTO v_so_2;

  INSERT INTO sales_order_lines (id, sales_order_id, tenant_id, product_id, description, quantity, unit_price, vat_rate, line_total)
  VALUES
    (gen_random_uuid(), v_so_2, v_tenant_id, v_product_1, 'Onusuite RH/Paie - 10 postes', 10, 35000, 19, 350000),
    (gen_random_uuid(), v_so_2, v_tenant_id, v_product_3, 'Audit installation', 1, 100000, 19, 100000);

  -- Sales Order 3: Draft
  INSERT INTO sales_orders (id, tenant_id, number, customer_id, order_date, status, subtotal, vat, total, notes, created_at, updated_at)
  VALUES (
    gen_random_uuid(), v_tenant_id, 'CMD-2026-003',
    v_customer_3, '2026-01-20', 'draft',
    875000, 166250, 1041250, 'En attente validation client',
    NOW(), NOW()
  );

  -- Sales Order 4: Invoiced
  INSERT INTO sales_orders (id, tenant_id, number, customer_id, order_date, delivery_date, status, subtotal, vat, total, created_at, updated_at)
  VALUES (
    gen_random_uuid(), v_tenant_id, 'CMD-2026-004',
    v_customer_1, '2026-01-05', '2026-01-20', 'invoiced',
    600000, 114000, 714000, NOW(), NOW()
  );

  RAISE NOTICE 'Sales orders seeded.';

  -- ============================================
  -- 2. PROJECTS: Projects + Tasks
  -- ============================================
  -- Cleanup existing data (use subqueries to be resilient to missing tenant_id columns)
  DELETE FROM project_task_assignees WHERE task_id IN (SELECT id FROM project_tasks WHERE tenant_id = v_tenant_id);
  DELETE FROM task_comments WHERE task_id IN (SELECT id FROM project_tasks WHERE tenant_id = v_tenant_id);
  DELETE FROM task_actions WHERE task_id IN (SELECT id FROM project_tasks WHERE tenant_id = v_tenant_id);
  DELETE FROM project_task_tags WHERE task_id IN (SELECT id FROM project_tasks WHERE tenant_id = v_tenant_id);
  DELETE FROM project_task_dependencies WHERE task_id IN (SELECT id FROM project_tasks WHERE tenant_id = v_tenant_id);
  DELETE FROM project_tasks WHERE tenant_id = v_tenant_id;
  DELETE FROM project_stages WHERE tenant_id = v_tenant_id;
  DELETE FROM project_tags WHERE tenant_id = v_tenant_id;
  DELETE FROM projects WHERE tenant_id = v_tenant_id;

  -- Project 1: Implementation Onusuite (color: indigo #6366f1)
  INSERT INTO projects (id, tenant_id, name, description, customer_id, status, budget, actual_cost, start_date, end_date, manager_id, color, created_at, updated_at)
  VALUES (
    gen_random_uuid(), v_tenant_id, 'Implémentation Onusuite - Société ABC',
    'Déploiement complet Onusuite (Comptabilité + Commercial + RH) pour Société ABC. Formation des utilisateurs et paramétrage fiscal.',
    v_customer_1, 'active', 2500000, 1450000, '2026-01-01', '2026-03-31', v_employee_1, '#6366f1',
    NOW(), NOW()
  ) RETURNING id INTO v_project_1;

  -- Project 2: Migration Sage 100 (color: emerald #10b981)
  INSERT INTO projects (id, tenant_id, name, description, customer_id, status, budget, actual_cost, start_date, end_date, manager_id, color, created_at, updated_at)
  VALUES (
    gen_random_uuid(), v_tenant_id, 'Migration Sage 100 → Onusuite',
    'Reprise des données comptables et commerciales depuis Sage 100. Migration des journaux, comptes, tiers et stocks.',
    v_customer_2, 'active', 1800000, 920000, '2026-01-15', '2026-04-15', v_employee_2, '#10b981',
    NOW(), NOW()
  ) RETURNING id INTO v_project_2;

  -- Project 3: Audit fiscal (color: amber #f59e0b)
  INSERT INTO projects (id, tenant_id, name, description, customer_id, status, budget, actual_cost, start_date, end_date, manager_id, color, created_at, updated_at)
  VALUES (
    gen_random_uuid(), v_tenant_id, 'Audit fiscal 2025 - Groupe XYZ',
    'Audit de conformité fiscale : TVA, retenues à la source, taxe sur salaires. Production du rapport d''audit.',
    v_customer_3, 'completed', 850000, 780000, '2025-10-01', '2025-12-31', v_employee_1, '#f59e0b',
    NOW(), NOW()
  ) RETURNING id INTO v_project_3;

  -- Project stages (columns: name, sequence, fold, case_default)
  INSERT INTO project_stages (id, tenant_id, name, sequence, fold, case_default)
  VALUES
    (gen_random_uuid(), v_tenant_id, 'À faire', 0, false, true),
    (gen_random_uuid(), v_tenant_id, 'En cours', 1, false, false),
    (gen_random_uuid(), v_tenant_id, 'En revue', 2, false, false),
    (gen_random_uuid(), v_tenant_id, 'Terminé', 3, false, false);

  -- Project tags (color is INTEGER index, not hex string)
  INSERT INTO project_tags (id, tenant_id, name, color)
  VALUES
    (gen_random_uuid(), v_tenant_id, 'Urgent', 0),
    (gen_random_uuid(), v_tenant_id, 'Comptabilité', 1),
    (gen_random_uuid(), v_tenant_id, 'Commercial', 2),
    (gen_random_uuid(), v_tenant_id, 'RH', 3),
    (gen_random_uuid(), v_tenant_id, 'Formation', 4);

  -- Tasks for Project 1 (color: 1 = indigo, same as project color #6366f1)
  INSERT INTO project_tasks (id, tenant_id, project_id, title, description, status, priority, start_date, due_date, effort_estimate_h, effort_spent_h, progress, display_order, color, created_at, updated_at)
  VALUES
    (gen_random_uuid(), v_tenant_id, v_project_1, 'Paramétrage plan comptable', 'Configuration du plan comptable SYCEBN et des journaux', 'completed', 'high', '2026-01-02', '2026-01-08', 16, 14, 100, '0', 1, NOW(), NOW()),
    (gen_random_uuid(), v_tenant_id, v_project_1, 'Migration données tiers', 'Import des clients et fournisseurs depuis Sage', 'completed', 'high', '2026-01-05', '2026-01-12', 20, 18, 100, '1', 1, NOW(), NOW()),
    (gen_random_uuid(), v_tenant_id, v_project_1, 'Configuration TVA', 'Paramétrage des taux de TVA et des déclarations', 'in_progress', 'high', '2026-01-10', '2026-01-20', 12, 8, 65, '2', 1, NOW(), NOW()),
    (gen_random_uuid(), v_tenant_id, v_project_1, 'Formation utilisateurs comptabilité', 'Formation des 8 utilisateurs sur le module Comptabilité', 'todo', 'medium', '2026-02-01', '2026-02-15', 24, 0, 0, '3', 1, NOW(), NOW()),
    (gen_random_uuid(), v_tenant_id, v_project_1, 'Paramétrage module Commercial', 'Configuration des devis, factures et bons de livraison', 'todo', 'medium', '2026-02-10', '2026-02-25', 16, 0, 0, '4', 1, NOW(), NOW()),
    (gen_random_uuid(), v_tenant_id, v_project_1, 'Tests et validation', 'Tests de bout en bout et validation avec le client', 'todo', 'high', '2026-03-01', '2026-03-15', 32, 0, 0, '5', 1, NOW(), NOW()),
    (gen_random_uuid(), v_tenant_id, v_project_1, 'Go-live et support', 'Mise en production et support post-démarrage', 'todo', 'high', '2026-03-20', '2026-03-31', 16, 0, 0, '6', 1, NOW(), NOW());

  -- Tasks for Project 2 (color: 2 = emerald, same as project color #10b981)
  INSERT INTO project_tasks (id, tenant_id, project_id, title, description, status, priority, start_date, due_date, effort_estimate_h, effort_spent_h, progress, display_order, color, created_at, updated_at)
  VALUES
    (gen_random_uuid(), v_tenant_id, v_project_2, 'Extraction données Sage', 'Export des écritures, comptes et tiers depuis Sage 100', 'completed', 'high', '2026-01-15', '2026-01-22', 16, 15, 100, '0', 2, NOW(), NOW()),
    (gen_random_uuid(), v_tenant_id, v_project_2, 'Transformation et mapping', 'Mapping des comptes Sage vers plan SYCEBN', 'in_progress', 'high', '2026-01-23', '2026-02-05', 24, 12, 50, '1', 2, NOW(), NOW()),
    (gen_random_uuid(), v_tenant_id, v_project_2, 'Import écritures 2024-2025', 'Import des écritures comptables historiques', 'todo', 'high', '2026-02-06', '2026-02-20', 20, 0, 0, '2', 2, NOW(), NOW()),
    (gen_random_uuid(), v_tenant_id, v_project_2, 'Réconciliation soldes', 'Vérification des soldes après migration', 'todo', 'medium', '2026-02-20', '2026-03-01', 12, 0, 0, '3', 2, NOW(), NOW()),
    (gen_random_uuid(), v_tenant_id, v_project_2, 'Formation équipe', 'Formation de l''équipe comptable (5 personnes)', 'todo', 'low', '2026-03-15', '2026-03-25', 16, 0, 0, '4', 2, NOW(), NOW());

  -- Tasks for Project 3 (color: 3 = amber, same as project color #f59e0b)
  INSERT INTO project_tasks (id, tenant_id, project_id, title, description, status, priority, start_date, due_date, effort_estimate_h, effort_spent_h, progress, display_order, color, created_at, updated_at)
  VALUES
    (gen_random_uuid(), v_tenant_id, v_project_3, 'Collecte documents fiscaux', 'Collecte des déclarations TVA et charges sociales 2025', 'completed', 'high', '2025-10-01', '2025-10-15', 16, 16, 100, '0', 3, NOW(), NOW()),
    (gen_random_uuid(), v_tenant_id, v_project_3, 'Analyse TVA', 'Vérification des déclarations TVA et reversements', 'completed', 'high', '2025-10-16', '2025-11-10', 32, 30, 100, '1', 3, NOW(), NOW()),
    (gen_random_uuid(), v_tenant_id, v_project_3, 'Analyse retenues à la source', 'Contrôle des retenues à la source sur prestations', 'completed', 'medium', '2025-11-01', '2025-11-20', 20, 18, 100, '2', 3, NOW(), NOW()),
    (gen_random_uuid(), v_tenant_id, v_project_3, 'Rapport d''audit', 'Rédaction et présentation du rapport d''audit fiscal', 'completed', 'high', '2025-11-20', '2025-12-31', 24, 22, 100, '3', 3, NOW(), NOW());

  RAISE NOTICE 'Projects and tasks seeded.';

  -- ============================================
  -- 3. PRODUCTION: BOMs + Manufacturing Orders
  -- ============================================
  -- Delete by code/number first (unique constraints are global)
  DELETE FROM bom_lines WHERE bom_id IN (SELECT id FROM boms WHERE code = 'BOM-001');
  DELETE FROM boms WHERE code = 'BOM-001';
  DELETE FROM manufacturing_orders WHERE number LIKE 'OF-2026-%';
  -- Also cleanup by tenant
  DELETE FROM manufacturing_orders WHERE tenant_id = v_tenant_id;
  DELETE FROM bom_lines WHERE tenant_id = v_tenant_id;
  DELETE FROM boms WHERE tenant_id = v_tenant_id;

  -- BOM for product 1
  INSERT INTO boms (id, tenant_id, code, name, product_id, quantity, unit, active, bom_type, created_at)
  VALUES (
    gen_random_uuid(), v_tenant_id, 'BOM-001', 'BOM - Licence Onusuite Complete', v_product_1, 1, 'unité', true, 'standard', NOW()
  ) RETURNING id INTO v_bom_1;

  INSERT INTO bom_lines (id, tenant_id, bom_id, product_id, quantity, unit_cost, position)
  VALUES
    (gen_random_uuid(), v_tenant_id, v_bom_1, COALESCE(v_product_2, v_product_1), 1, 50000, 1),
    (gen_random_uuid(), v_tenant_id, v_bom_1, COALESCE(v_product_3, v_product_1), 2, 25000, 2);

  -- Manufacturing Order 1: In progress
  INSERT INTO manufacturing_orders (id, tenant_id, number, bom_id, product_id, quantity, status, start_date, end_date, warehouse_id, notes, origin, created_at)
  VALUES (
    gen_random_uuid(), v_tenant_id, 'OF-2026-001',
    v_bom_1, v_product_1, 10, 'in_progress',
    '2026-01-10', '2026-02-10', v_warehouse_1,
    'Production de 10 licences Onusuite complètes pour stock',
    'manual', NOW()
  ) RETURNING id INTO v_mo_1;

  -- Manufacturing Order 2: Planned
  INSERT INTO manufacturing_orders (id, tenant_id, number, bom_id, product_id, quantity, status, start_date, end_date, warehouse_id, notes, origin, created_at)
  VALUES (
    gen_random_uuid(), v_tenant_id, 'OF-2026-002',
    v_bom_1, v_product_1, 5, 'planned',
    '2026-02-15', '2026-03-01', v_warehouse_1,
    'Production planifiée pour commande CMD-2026-003',
    'mrp', NOW()
  ) RETURNING id INTO v_mo_2;

  -- Manufacturing Order 3: Completed
  INSERT INTO manufacturing_orders (id, tenant_id, number, bom_id, product_id, quantity, status, start_date, end_date, warehouse_id, notes, origin, created_at)
  VALUES (
    gen_random_uuid(), v_tenant_id, 'OF-2026-003',
    v_bom_1, v_product_1, 8, 'completed',
    '2025-12-15', '2026-01-05', v_warehouse_1,
    'Production terminée - entrée en stock effectuée',
    'manual', NOW()
  ) RETURNING id INTO v_mo_3;

  RAISE NOTICE 'Manufacturing orders seeded.';

  RAISE NOTICE '=== Landing page screenshot seed data complete ===';
  RAISE NOTICE 'Modules seeded: Commercial (4 sales orders), Projects (3 projects + 16 tasks), Production (1 BOM + 3 MOs)';
  RAISE NOTICE 'Comptabilité already seeded by seed_demo_data.sql';

END $$;
