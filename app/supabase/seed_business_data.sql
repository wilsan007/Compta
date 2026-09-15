-- ============================================
-- Seed data métier pour Onusuite
-- Tenant: a0000000-0000-0000-0000-000000000001
-- Crée: clients, fournisseurs, produits, banques,
--        écritures comptables, factures, employés, projets, tâches
-- ============================================

DO $$
DECLARE
  v_tenant uuid := 'a0000000-0000-0000-0000-000000000001';
  v_cust1 uuid; v_cust2 uuid; v_cust3 uuid; v_cust4 uuid; v_cust5 uuid;
  v_supp1 uuid; v_supp2 uuid; v_supp3 uuid;
  v_prod1 uuid; v_prod2 uuid; v_prod3 uuid; v_prod4 uuid; v_prod5 uuid;
  v_bank1 uuid; v_bank2 uuid;
  v_wh1 uuid;
  v_je1 uuid; v_je2 uuid; v_je3 uuid; v_je4 uuid; v_je5 uuid;
  v_inv1 uuid; v_inv2 uuid; v_inv3 uuid; v_inv4 uuid; v_inv5 uuid;
  v_emp1 uuid; v_emp2 uuid; v_emp3 uuid; v_emp4 uuid; v_emp5 uuid;
  v_proj1 uuid; v_proj2 uuid; v_proj3 uuid;
BEGIN
  -- Set tenant context for triggers (increment_stock, etc.)
  PERFORM set_config('app.active_tenant_id', v_tenant::text, true);

  -- ============================================
  -- 1. CLIENTS (5)
  -- ============================================
  INSERT INTO customers (tenant_id, name, email, phone, address, city, postal_code, country, siret, vat_number, balance, credit_limit, payment_terms, currency, is_company, active)
  VALUES
    (v_tenant, 'TechCorp SARL', 'contact@techcorp.fr', '01 23 45 67 89', '12 rue de l''Innovation', 'Paris', '75001', 'France', '12345678900012', 'FR12345678901', 15000, 50000, '30 days', 'EUR', true, true)
  RETURNING id INTO v_cust1;

  INSERT INTO customers (tenant_id, name, email, phone, address, city, postal_code, country, siret, vat_number, balance, credit_limit, payment_terms, currency, is_company, active)
  VALUES
    (v_tenant, 'Boulangerie Martin', 'martin@boulang.fr', '02 34 56 78 90', '5 place du Marché', 'Lyon', '69001', 'France', '23456789000023', 'FR23456789023', 3200, 10000, '15 days', 'EUR', true, true)
  RETURNING id INTO v_cust2;

  INSERT INTO customers (tenant_id, name, email, phone, address, city, postal_code, country, siret, vat_number, balance, credit_limit, payment_terms, currency, is_company, active)
  VALUES
    (v_tenant, 'Globex International', 'info@globex.com', '+33 1 98 76 54 32', '88 avenue des Champs', 'Paris', '75008', 'France', '34567890100034', 'FR34567890134', 42000, 100000, '45 days', 'EUR', true, true)
  RETURNING id INTO v_cust3;

  INSERT INTO customers (tenant_id, name, email, phone, address, city, postal_code, country, balance, credit_limit, payment_terms, currency, is_company, active)
  VALUES
    (v_tenant, 'Sophie Durand', 'sophie.durand@email.fr', '06 12 34 56 78', '23 rue Lafayette', 'Marseille', '13001', 'France', 800, 5000, 'Immediate', 'EUR', false, true)
  RETURNING id INTO v_cust4;

  INSERT INTO customers (tenant_id, name, email, phone, address, city, postal_code, country, siret, vat_number, balance, credit_limit, payment_terms, currency, is_company, active)
  VALUES
    (v_tenant, 'Initech Solutions', 'hello@initech.fr', '03 45 67 89 01', '42 boulevard Tech', 'Bordeaux', '33000', 'France', '45678901200045', 'FR45678901245', 8700, 25000, '30 days', 'EUR', true, true)
  RETURNING id INTO v_cust5;

  -- ============================================
  -- 2. FOURNISSEURS (3)
  -- ============================================
  INSERT INTO suppliers (tenant_id, name, email, phone, address, city, postal_code, country, siret, vat_number, balance, payment_terms, currency, is_company, active)
  VALUES
    (v_tenant, 'Fournitures Pro', 'commandes@fournipro.fr', '04 56 78 90 12', '7 zone industrielle', 'Lille', '59000', 'France', '56789012300056', 'FR56789012356', -12500, '30 days', 'EUR', true, true)
  RETURNING id INTO v_supp1;

  INSERT INTO suppliers (tenant_id, name, email, phone, address, city, postal_code, country, siret, vat_number, balance, payment_terms, currency, is_company, active)
  VALUES
    (v_tenant, 'TechDistribution', 'sales@techdist.com', '05 67 89 01 23', '15 rue du Commerce', 'Paris', '75011', 'France', '67890123400067', 'FR67890123467', -8300, '45 days', 'EUR', true, true)
  RETURNING id INTO v_supp2;

  INSERT INTO suppliers (tenant_id, name, email, phone, address, city, postal_code, country, balance, payment_terms, currency, is_company, active)
  VALUES
    (v_tenant, 'Papeterie Centrale', 'contact@papeterie-centre.fr', '01 22 33 44 55', '3 rue des Papetiers', 'Paris', '75003', 'France', -2100, '30 days', 'EUR', true, true)
  RETURNING id INTO v_supp3;

  -- ============================================
  -- 3. PRODUITS & SERVICES (5)
  -- ============================================
  INSERT INTO products (tenant_id, name, sku, description, type, sale_price, purchase_price, cost_price, vat_rate, stock_quantity, reorder_level, unit, category, active)
  VALUES
    (v_tenant, 'Licence Onusuite Standard', 'LIC-STD', 'Licence annuelle module standard', 'service', 2400, 0, 0, 20, 0, 0, 'licence', 'Licences', true)
  RETURNING id INTO v_prod1;

  INSERT INTO products (tenant_id, name, sku, description, type, sale_price, purchase_price, cost_price, vat_rate, stock_quantity, reorder_level, unit, category, active)
  VALUES
    (v_tenant, 'Licence Onusuite Premium', 'LIC-PREM', 'Licence annuelle tous modules', 'service', 4800, 0, 0, 20, 0, 0, 'licence', 'Licences', true)
  RETURNING id INTO v_prod2;

  INSERT INTO products (tenant_id, name, sku, description, type, sale_price, purchase_price, cost_price, vat_rate, stock_quantity, reorder_level, unit, category, active, weight, barcode)
  VALUES
    (v_tenant, 'Ordinateur portable 15"', 'ORD-15', 'PC portable 15" 16GB SSD 512GB', 'stock', 899, 650, 650, 20, 45, 10, 'unité', 'Matériel', true, 2.1, '3760123456789')
  RETURNING id INTO v_prod3;

  INSERT INTO products (tenant_id, name, sku, description, type, sale_price, purchase_price, cost_price, vat_rate, stock_quantity, reorder_level, unit, category, active)
  VALUES
    (v_tenant, 'Souris sans fil', 'SOURIS-WL', 'Souris ergonomique sans fil USB', 'stock', 29.90, 12, 12, 20, 120, 30, 'unité', 'Accessoires', true)
  RETURNING id INTO v_prod4;

  INSERT INTO products (tenant_id, name, sku, description, type, sale_price, purchase_price, cost_price, vat_rate, stock_quantity, reorder_level, unit, category, active)
  VALUES
    (v_tenant, 'Consultation intégration', 'CONS-INT', 'Jour d''intégration et configuration', 'service', 850, 0, 0, 20, 0, 0, 'jour', 'Services', true)
  RETURNING id INTO v_prod5;

  -- ============================================
  -- 4. COMPTES BANCAIRES (2)
  -- ============================================
  INSERT INTO bank_accounts (tenant_id, name, type, account_number, balance, currency, bank_name, connected, statement_balance, calculated_balance)
  VALUES
    (v_tenant, 'Compte courant BNP', 'chequing', 'FR7630006000011234567890189', 45230.50, 'EUR', 'BNP Paribas', true, 45230.50, 45230.50)
  RETURNING id INTO v_bank1;

  INSERT INTO bank_accounts (tenant_id, name, type, account_number, balance, currency, bank_name, connected, statement_balance, calculated_balance)
  VALUES
    (v_tenant, 'Livret épargne', 'savings', 'FR7630006000019876543210987', 12500.00, 'EUR', 'BNP Paribas', false, 12500.00, 12500.00)
  RETURNING id INTO v_bank2;

  -- ============================================
  -- 5. ENTREPÔT
  -- ============================================
  INSERT INTO warehouses (tenant_id, code, name, address, city, postal_code, country, active)
  VALUES
    (v_tenant, 'WH-01', 'Entrepôt principal', '25 zone logistique', 'Lyon', '69007', 'France', true)
  RETURNING id INTO v_wh1;

  -- ============================================
  -- 6. ÉCRITURES COMPTABLES (5)
  -- ============================================
  INSERT INTO journal_entries (tenant_id, number, date, description, status, total_debit, total_credit, journal_code)
  VALUES
    (v_tenant, 'JE-2026-001', '2026-01-15', 'Facture de vente FAC-2026-001 TechCorp', 'posted', 12000, 12000, 'VT')
  RETURNING id INTO v_je1;

  INSERT INTO journal_entries (tenant_id, number, date, description, status, total_debit, total_credit, journal_code)
  VALUES
    (v_tenant, 'JE-2026-002', '2026-01-20', 'Achat fournitures Fournitures Pro', 'posted', 10000, 10000, 'AC')
  RETURNING id INTO v_je2;

  INSERT INTO journal_entries (tenant_id, number, date, description, status, total_debit, total_credit, journal_code)
  VALUES
    (v_tenant, 'JE-2026-003', '2026-02-01', 'Paie janvier 2026', 'posted', 35000, 35000, 'OD')
  RETURNING id INTO v_je3;

  INSERT INTO journal_entries (tenant_id, number, date, description, status, total_debit, total_credit, journal_code)
  VALUES
    (v_tenant, 'JE-2026-004', '2026-02-10', 'Règlement client Globex', 'posted', 42000, 42000, 'BQ')
  RETURNING id INTO v_je4;

  INSERT INTO journal_entries (tenant_id, number, date, description, status, total_debit, total_credit, journal_code)
  VALUES
    (v_tenant, 'JE-2026-005', '2026-02-15', 'Facture de vente FAC-2026-002 Initech', 'draft', 8700, 8700, 'VT')
  RETURNING id INTO v_je5;

  -- Lignes comptables pour chaque écriture
  -- JE-001: Vente (12000 TTC = 10000 HT + 2000 TVA)
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_name, debit, credit, line_order, line_date) VALUES
    (v_tenant, v_je1, '411000', 'Clients', 12000, 0, 1, '2026-01-15'),
    (v_tenant, v_je1, '707000', 'Ventes de marchandises', 0, 10000, 2, '2026-01-15'),
    (v_tenant, v_je1, '445710', 'TVA collectée', 0, 2000, 3, '2026-01-15');

  -- JE-002: Achat (10000 TTC = 8333.33 HT + 1666.67 TVA)
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_name, debit, credit, line_order, line_date) VALUES
    (v_tenant, v_je2, '607000', 'Achats de marchandises', 8333.33, 0, 1, '2026-01-20'),
    (v_tenant, v_je2, '445660', 'TVA déductible', 1666.67, 0, 2, '2026-01-20'),
    (v_tenant, v_je2, '401000', 'Fournisseurs', 0, 10000, 3, '2026-01-20');

  -- JE-003: Paie (35000 brut)
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_name, debit, credit, line_order, line_date) VALUES
    (v_tenant, v_je3, '641000', 'Rémunérations du personnel', 28000, 0, 1, '2026-02-01'),
    (v_tenant, v_je3, '645000', 'Charges sociales', 7000, 0, 2, '2026-02-01'),
    (v_tenant, v_je3, '421000', 'Personnel - rémunérations dues', 0, 22000, 3, '2026-02-01'),
    (v_tenant, v_je3, '431000', 'Sécurité sociale', 0, 9000, 4, '2026-02-01'),
    (v_tenant, v_je3, '437000', 'Autres charges sociales', 0, 4000, 5, '2026-02-01');

  -- JE-004: Règlement client
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_name, debit, credit, line_order, line_date) VALUES
    (v_tenant, v_je4, '512000', 'Banque BNP', 42000, 0, 1, '2026-02-10'),
    (v_tenant, v_je4, '411000', 'Clients', 0, 42000, 2, '2026-02-10');

  -- JE-005: Vente (brouillon)
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_name, debit, credit, line_order, line_date) VALUES
    (v_tenant, v_je5, '411000', 'Clients', 8700, 0, 1, '2026-02-15'),
    (v_tenant, v_je5, '707000', 'Ventes de marchandises', 0, 7250, 2, '2026-02-15'),
    (v_tenant, v_je5, '445710', 'TVA collectée', 0, 1450, 3, '2026-02-15');

  -- ============================================
  -- 7. FACTURES DE VENTE (5)
  -- ============================================
  INSERT INTO invoices (tenant_id, number, customer_id, customer_name, date, due_date, status, subtotal, vat_total, total, amount_paid, amount_due, payment_state, currency_code, validation_status)
  VALUES
    (v_tenant, 'FAC-2026-001', v_cust1, 'TechCorp SARL', '2026-01-15', '2026-02-14', 'paid', 10000, 2000, 12000, 12000, 0, 'paid', 'EUR', 'validated')
  RETURNING id INTO v_inv1;

  INSERT INTO invoices (tenant_id, number, customer_id, customer_name, date, due_date, status, subtotal, vat_total, total, amount_paid, amount_due, payment_state, currency_code, validation_status)
  VALUES
    (v_tenant, 'FAC-2026-002', v_cust5, 'Initech Solutions', '2026-02-15', '2026-03-17', 'sent', 7250, 1450, 8700, 0, 8700, 'not_paid', 'EUR', 'validated')
  RETURNING id INTO v_inv2;

  INSERT INTO invoices (tenant_id, number, customer_id, customer_name, date, due_date, status, subtotal, vat_total, total, amount_paid, amount_due, payment_state, currency_code, validation_status)
  VALUES
    (v_tenant, 'FAC-2026-003', v_cust3, 'Globex International', '2026-02-20', '2026-04-06', 'sent', 35000, 7000, 42000, 15000, 27000, 'partial', 'EUR', 'validated')
  RETURNING id INTO v_inv3;

  INSERT INTO invoices (tenant_id, number, customer_id, customer_name, date, due_date, status, subtotal, vat_total, total, amount_paid, amount_due, payment_state, currency_code, validation_status)
  VALUES
    (v_tenant, 'FAC-2026-004', v_cust2, 'Boulangerie Martin', '2026-03-01', '2026-03-16', 'sent', 2666.67, 533.33, 3200, 0, 3200, 'not_paid', 'EUR', 'validated')
  RETURNING id INTO v_inv4;

  INSERT INTO invoices (tenant_id, number, customer_id, customer_name, date, due_date, status, subtotal, vat_total, total, amount_paid, amount_due, payment_state, currency_code, validation_status)
  VALUES
    (v_tenant, 'FAC-2026-005', v_cust4, 'Sophie Durand', '2026-03-05', '2026-03-05', 'draft', 666.67, 133.33, 800, 0, 800, 'not_paid', 'EUR', 'draft')
  RETURNING id INTO v_inv5;

  -- ============================================
  -- 8. EMPLOYÉS (5)
  -- ============================================
  INSERT INTO employees (tenant_id, name, email, phone, position, department, salary, hire_date, status, contract_type, employee_number)
  VALUES
    (v_tenant, 'Ahmed Benali', 'ahmed.benali@onusuite.com', '06 11 22 33 44', 'CEO', 'Direction', 12000, '2024-01-01', 'active', 'CDI', 'EMP-001')
  RETURNING id INTO v_emp1;

  INSERT INTO employees (tenant_id, name, email, phone, position, department, salary, hire_date, status, contract_type, employee_number)
  VALUES
    (v_tenant, 'Fatima Zahra', 'fatima.zahra@onusuite.com', '06 22 33 44 55', 'Comptable', 'Finance', 5500, '2024-03-15', 'active', 'CDI', 'EMP-002')
  RETURNING id INTO v_emp2;

  INSERT INTO employees (tenant_id, name, email, phone, position, department, salary, hire_date, status, contract_type, employee_number)
  VALUES
    (v_tenant, 'Karim Mansouri', 'karim.mansouri@onusuite.com', '06 33 44 55 66', 'Développeur', 'IT', 6500, '2024-06-01', 'active', 'CDI', 'EMP-003')
  RETURNING id INTO v_emp3;

  INSERT INTO employees (tenant_id, name, email, phone, position, department, salary, hire_date, status, contract_type, employee_number)
  VALUES
    (v_tenant, 'Leila Haddad', 'leila.haddad@onusuite.com', '06 44 55 66 77', 'Responsable commercial', 'Commercial', 6000, '2024-09-01', 'active', 'CDI', 'EMP-004')
  RETURNING id INTO v_emp4;

  INSERT INTO employees (tenant_id, name, email, phone, position, department, salary, hire_date, status, contract_type, employee_number)
  VALUES
    (v_tenant, 'Youssef Amrani', 'youssef.amrani@onusuite.com', '06 55 66 77 88', 'Apprenti développeur', 'IT', 2500, '2025-09-01', 'active', 'Apprentissage', 'EMP-005')
  RETURNING id INTO v_emp5;

  -- ============================================
  -- 9. PROJETS (3)
  -- ============================================
  INSERT INTO projects (tenant_id, name, description, customer_id, status, budget, actual_cost, start_date, end_date, progress, allow_subtasks, allow_recurrent_tasks, allow_milestones, allow_task_dependencies, allow_timesheets, allow_billable)
  VALUES
    (v_tenant, 'Migration ERP TechCorp', 'Migration complète du système ERP de TechCorp vers Onusuite', v_cust1, 'active', 45000, 28000, '2026-01-15', '2026-04-30', 60, true, true, true, true, true, true)
  RETURNING id INTO v_proj1;

  INSERT INTO projects (tenant_id, name, description, customer_id, status, budget, actual_cost, start_date, end_date, progress, allow_subtasks, allow_recurrent_tasks, allow_milestones, allow_task_dependencies, allow_timesheets, allow_billable)
  VALUES
    (v_tenant, 'Intégration API Globex', 'Intégration API e-commerce et synchronisation stock', v_cust3, 'active', 30000, 12000, '2026-02-01', '2026-05-15', 40, true, false, true, true, true, true)
  RETURNING id INTO v_proj2;

  INSERT INTO projects (tenant_id, name, description, status, budget, actual_cost, start_date, end_date, progress, allow_subtasks, allow_recurrent_tasks, allow_milestones, allow_task_dependencies, allow_timesheets, allow_billable)
  VALUES
    (v_tenant, 'Refonte site web interne', 'Refonte du site web et intranet Onusuite', 'active', 15000, 0, '2026-04-01', '2026-06-30', 0, true, true, true, false, true, false)
  RETURNING id INTO v_proj3;

  -- ============================================
  -- 10. TÂCHES (12)
  -- ============================================
  INSERT INTO project_tasks (tenant_id, project_id, title, description, status, priority, assignee, start_date, due_date, effort_estimate_h, effort_spent_h, progress, display_order, task_level, budget) VALUES
    (v_tenant, v_proj1, 'Analyse des besoins', 'Recueil et analyse des besoins TechCorp', 'done', 'high', 'Ahmed Benali', '2026-01-15', '2026-01-25', 20, 22, 100, '1', 1, 3000),
    (v_tenant, v_proj1, 'Configuration modules', 'Configuration des modules comptabilité et commercial', 'in_progress', 'high', 'Fatima Zahra', '2026-01-26', '2026-02-15', 40, 28, 70, '2', 1, 8000),
    (v_tenant, v_proj1, 'Migration données', 'Import des données historiques depuis ancien ERP', 'in_progress', 'critical', 'Karim Mansouri', '2026-02-01', '2026-03-01', 60, 35, 55, '3', 1, 12000),
    (v_tenant, v_proj1, 'Formation utilisateurs', 'Formation des équipes TechCorp sur Onusuite', 'todo', 'medium', 'Leila Haddad', '2026-03-15', '2026-03-30', 16, 0, 0, '4', 1, 4000),
    (v_tenant, v_proj1, 'Go-live et support', 'Mise en production et support post-go-live', 'todo', 'high', 'Ahmed Benali', '2026-04-01', '2026-04-30', 24, 0, 0, '5', 1, 5000);

  INSERT INTO project_tasks (tenant_id, project_id, title, description, status, priority, assignee, start_date, due_date, effort_estimate_h, effort_spent_h, progress, display_order, task_level, budget) VALUES
    (v_tenant, v_proj2, 'Étude API existante', 'Analyse de l''API e-commerce Globex', 'done', 'high', 'Karim Mansouri', '2026-02-01', '2026-02-10', 16, 18, 100, '1', 1, 3000),
    (v_tenant, v_proj2, 'Développement connecteur', 'Développement du connecteur API', 'in_progress', 'critical', 'Karim Mansouri', '2026-02-11', '2026-03-20', 80, 45, 50, '2', 1, 15000),
    (v_tenant, v_proj2, 'Tests d''intégration', 'Tests end-to-end du connecteur', 'todo', 'high', 'Youssef Amrani', '2026-03-21', '2026-04-10', 24, 0, 0, '3', 1, 5000),
    (v_tenant, v_proj2, 'Déploiement production', 'Mise en production du connecteur', 'todo', 'high', 'Karim Mansouri', '2026-04-15', '2026-05-01', 8, 0, 0, '4', 1, 3000);

  INSERT INTO project_tasks (tenant_id, project_id, title, description, status, priority, assignee, start_date, due_date, effort_estimate_h, effort_spent_h, progress, display_order, task_level, budget) VALUES
    (v_tenant, v_proj3, 'Cahier des charges', 'Rédaction du cahier des charges', 'todo', 'medium', 'Leila Haddad', '2026-04-01', '2026-04-15', 12, 0, 0, '1', 1, 2000),
    (v_tenant, v_proj3, 'Maquettes UX/UI', 'Design des maquettes du nouveau site', 'todo', 'medium', 'Leila Haddad', '2026-04-16', '2026-05-15', 40, 0, 0, '2', 1, 5000),
    (v_tenant, v_proj3, 'Développement', 'Développement front-end et back-end', 'todo', 'high', 'Karim Mansouri', '2026-05-16', '2026-06-20', 60, 0, 0, '3', 1, 6000);

  -- ============================================
  -- 11. MOUVEMENTS DE STOCK (3)
  -- ============================================
  BEGIN
    INSERT INTO stock_movements (tenant_id, product_id, type, quantity, reference, date, warehouse_id, unit_cost, movement_type) VALUES
      (v_tenant, v_prod3, 'in', 50, 'BR-2026-001', '2026-01-10', v_wh1, 650, 'in'),
      (v_tenant, v_prod3, 'out', 5, 'FAC-2026-001', '2026-01-15', v_wh1, 650, 'out'),
      (v_tenant, v_prod4, 'in', 200, 'BR-2026-002', '2026-01-12', v_wh1, 12, 'in');
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Stock movements skipped: %', SQLERRM;
  END;

  -- ============================================
  -- RÉCAPITULATIF
  -- ============================================
  RAISE NOTICE '=== SEED DATA INSÉRÉ ===';
  RAISE NOTICE 'Clients: 5 | Fournisseurs: 3 | Produits: 5';
  RAISE NOTICE 'Banques: 2 | Entrepôts: 1';
  RAISE NOTICE 'Écritures comptables: 5 | Lignes: 16';
  RAISE NOTICE 'Factures: 5 | Employés: 5';
  RAISE NOTICE 'Projets: 3 | Tâches: 12';
  RAISE NOTICE 'Mouvements stock: 3';
END$$;
