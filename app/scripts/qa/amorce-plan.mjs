// ============================================================
// qa/amorce-plan.mjs — le jeu de données d'amorçage, écrit dans le vocabulaire
// de la BASE : noms de colonnes et valeurs d'énumération RÉELS, relevés sur le
// schéma le 29/09/2026 (les deviner avait produit 41 refus d'un coup).
//
// Les valeurs `@nom.champ` sont résolues avec les lignes réellement insérées.
// ============================================================
export const PLAN = [
  // ── Référentiels ────────────────────────────────────────────────
  { module: 'commercial', table: 'customers', rows: [
    { __as: 'client1', name: 'Boulangerie Martin', email: 'compta@martin.test', city: 'Lyon', postal_code: '69003', country: 'France', payment_terms: '30 jours' },
    { __as: 'client2', name: 'Atelier Duval', email: 'facture@duval.test', city: 'Nantes', postal_code: '44000', country: 'France', payment_terms: '30 jours' },
    { __as: 'client3', name: 'Hôtel des Alpes', email: 'achats@alpes.test', city: 'Grenoble', postal_code: '38000', country: 'France', payment_terms: '45 jours' },
  ] },
  { module: 'commercial', table: 'suppliers', rows: [
    { __as: 'four1', name: 'Papeterie Centrale', email: 'ventes@papeterie.test', city: 'Paris', postal_code: '75011', country: 'France', payment_terms: '30 jours' },
    { __as: 'four2', name: 'InfoMatériel SARL', email: 'contact@infomat.test', city: 'Lille', postal_code: '59000', country: 'France', payment_terms: '30 jours' },
  ] },
  { module: 'stock', table: 'products', rows: [
    { __as: 'prod1', name: 'Ramette A4 80g', sku: 'A4-80-500', type: 'stock', sale_price: 6.5, purchase_price: 3.2, vat_rate: 20, unit: 'ramette' },
    { __as: 'prod2', name: 'Clavier mécanique', sku: 'KB-MEC-01', type: 'stock', sale_price: 89, purchase_price: 52, vat_rate: 20, unit: 'pièce' },
    { __as: 'prod3', name: 'Écran 27 pouces', sku: 'SC-27-IPS', type: 'stock', sale_price: 249, purchase_price: 165, vat_rate: 20, unit: 'pièce' },
    { __as: 'prod4', name: 'Chaise de bureau', sku: 'CHR-ERG-02', type: 'stock', sale_price: 189, purchase_price: 110, vat_rate: 20, unit: 'pièce' },
    { __as: 'prod5', name: 'Maintenance annuelle', sku: 'SVC-MAINT', type: 'service', sale_price: 480, purchase_price: 0, vat_rate: 20, unit: 'forfait' },
  ] },
  { module: 'stock', table: 'warehouses', rows: [{ __as: 'depot1', code: 'DEP-01', name: 'Dépôt principal', city: 'Lyon', country: 'France', active: true }] },
  { module: 'treasury', table: 'bank_accounts', rows: [
    { __as: 'compte1', name: 'Compte courant pro', type: 'chequing', account_number: 'FR7630006000011234567890189', bank_name: 'Banque de la Recette', currency: 'EUR', balance: 12000 },
  ] },
  { module: 'hr', table: 'employees', rows: [
    { __as: 'sal1', name: 'Camille Bernard', email: 'camille.bernard@qa.local', position: 'Comptable', department: 'Comptabilité', hire_date: '2024-03-01', salary: 2600, status: 'active' },
    { __as: 'sal2', name: 'Yanis Moreau', email: 'yanis.moreau@qa.local', position: 'Magasinier', department: 'Logistique', hire_date: '2025-01-15', salary: 2100, status: 'active' },
  ] },
  { module: 'projectManagement', table: 'projects', rows: [
    { __as: 'proj1', customer_id: '@client1.id', name: 'Refonte du site client', status: 'active', budget: 24000, start_date: '2026-01-05', allow_timesheets: true, allow_billable: true },
    { __as: 'proj2', customer_id: '@client2.id', name: 'Déploiement ERP', status: 'active', budget: 48000, start_date: '2026-02-01', allow_timesheets: true, allow_billable: false },
  ] },
  { module: 'projectManagement', table: 'project_tasks', rows: [
    { __as: 'tache1', project_id: '@proj1.id', title: 'Cadrage', status: 'done', effort_estimate_h: 20, effort_spent_h: 18, progress: 100 },
    { __as: 'tache2', project_id: '@proj1.id', title: 'Intégration', status: 'in_progress', effort_estimate_h: 80, effort_spent_h: 28, progress: 35 },
  ] },
  { module: 'projectManagement', table: 'project_time_entries', rows: [
    { project_id: '@proj1.id', task_id: '@tache1.id', employee_id: '@sal1.id', start_time: '2026-03-02T09:00:00Z', end_time: '2026-03-02T15:00:00Z', duration_seconds: 21600, description: 'Atelier de cadrage', is_billable: true, hourly_rate: 75 },
    { project_id: '@proj1.id', task_id: '@tache2.id', employee_id: '@sal1.id', start_time: '2026-03-09T09:00:00Z', end_time: '2026-03-09T16:30:00Z', duration_seconds: 27000, description: 'Développement', is_billable: true, hourly_rate: 75 },
  ] },
  // ── Ventes ──────────────────────────────────────────────────────
  { module: 'commercial', table: 'quotes', rows: [
    { __as: 'devis1', number: 'DV-2026-0001', customer_id: '@client1.id', customer_name: 'Boulangerie Martin', date: '2026-03-01', expiry_date: '2026-04-01', status: 'sent', validation_status: 'draft', subtotal: 955, vat_total: 191, total: 1146 },
  ] },
  { module: 'commercial', table: 'quote_lines', rows: [
    { quote_id: '@devis1.id', product_id: '@prod2.id', description: 'Clavier mécanique', quantity: 10, unit_price: 89, vat_rate: 20, total: 890, vat_total: 178, line_order: 1 },
    { quote_id: '@devis1.id', product_id: '@prod1.id', description: 'Ramette A4', quantity: 10, unit_price: 6.5, vat_rate: 20, total: 65, vat_total: 13, line_order: 2 },
  ] },
  { module: 'commercial', table: 'sales_orders', rows: [
    { __as: 'commande1', number: 'CM-2026-0001', customer_id: '@client2.id', order_date: '2026-03-05', status: 'confirmed', validation_status: 'draft', subtotal: 890, vat: 178, total: 1068 },
  ] },
  { module: 'commercial', table: 'sales_order_lines', rows: [
    { sales_order_id: '@commande1.id', product_id: '@prod2.id', description: 'Clavier mécanique', quantity: 10, unit_price: 89, vat_rate: 20, line_total: 890 },
  ] },
  { module: 'commercial', table: 'delivery_notes', rows: [
    { __as: 'bl1', number: 'BL-2026-0001', customer_id: '@client2.id', sales_order_id: '@commande1.id', delivery_date: '2026-03-07', status: 'delivered', validation_status: 'validated' },
  ] },
  { module: 'commercial', table: 'delivery_note_lines', rows: [
    { delivery_note_id: '@bl1.id', product_id: '@prod2.id', description: 'Clavier mécanique', quantity: 10 },
  ] },
  { module: 'commercial', table: 'invoices', rows: [
    { __as: 'fact1', number: 'FA-2026-0001', customer_id: '@client1.id', customer_name: 'Boulangerie Martin', date: '2026-03-10', due_date: '2026-04-09', status: 'sent', validation_status: 'draft', subtotal: 1079, vat_total: 215.8, total: 1294.8, amount_paid: 0, amount_due: 1294.8 },
    { __as: 'fact2', number: 'FA-2026-0002', customer_id: '@client3.id', customer_name: 'Hôtel des Alpes', date: '2026-03-15', due_date: '2026-04-14', status: 'draft', validation_status: 'draft', subtotal: 2490, vat_total: 498, total: 2988, amount_paid: 0, amount_due: 2988 },
  ] },
  { module: 'commercial', table: 'invoice_lines', rows: [
    { invoice_id: '@fact1.id', product_id: '@prod2.id', description: 'Clavier mécanique', quantity: 10, unit_price: 89, vat_rate: 20, total: 890, vat_total: 178, line_order: 1 },
    { invoice_id: '@fact1.id', product_id: '@prod4.id', description: 'Chaise de bureau', quantity: 1, unit_price: 189, vat_rate: 20, total: 189, vat_total: 37.8, line_order: 2 },
    { invoice_id: '@fact2.id', product_id: '@prod3.id', description: 'Écran 27 pouces', quantity: 10, unit_price: 249, vat_rate: 20, total: 2490, vat_total: 498, line_order: 1 },
  ] },
  { module: 'commercial', table: 'customer_payments', rows: [
    { number: 'RG-2026-0001', customer_id: '@client1.id', invoice_id: '@fact1.id', payment_date: '2026-03-20', amount: 1294.8, method: 'transfer', bank_account_id: '@compte1.id', reference: 'FA-2026-0001', status: 'recorded' },
  ] },
  // ── Achats et stock ─────────────────────────────────────────────
  { module: 'stock', table: 'purchase_orders', rows: [
    { __as: 'cdf1', number: 'CF-2026-0001', supplier_id: '@four1.id', order_date: '2026-03-02', status: 'confirmed', subtotal: 640, vat: 128, total: 768 },
  ] },
  { module: 'stock', table: 'purchase_order_lines', rows: [
    { purchase_order_id: '@cdf1.id', product_id: '@prod1.id', description: 'Ramette A4 80g', quantity: 200, unit_price: 3.2, vat_rate: 20, line_total: 640, line_order: 1 },
  ] },
  { module: 'stock', table: 'goods_receipts', rows: [
    { __as: 'recep1', number: 'RE-2026-0001', supplier_id: '@four1.id', purchase_order_id: '@cdf1.id', receipt_date: '2026-03-04', status: 'received' },
  ] },
  { module: 'stock', table: 'goods_receipt_lines', rows: [
    { goods_receipt_id: '@recep1.id', product_id: '@prod1.id', description: 'Ramette A4 80g', quantity_ordered: 200, quantity_received: 200 },
  ] },
  { module: 'stock', table: 'stock_movements', rows: [
    { product_id: '@prod1.id', type: 'in', movement_type: 'in', quantity: 200, reference: 'RE-2026-0001', date: '2026-03-04' },
    { product_id: '@prod3.id', type: 'in', movement_type: 'in', quantity: 15, reference: 'RE-2026-0002', date: '2026-03-06' },
    { product_id: '@prod3.id', type: 'out', movement_type: 'out', quantity: 10, reference: 'FA-2026-0002', date: '2026-03-15' },
  ] },
  { module: 'stock', table: 'purchase_invoices', rows: [
    { __as: 'factf1', number: 'FF-2026-0001', supplier_id: '@four1.id', supplier_name: 'Papeterie Centrale', date: '2026-03-04', due_date: '2026-04-03', status: 'draft', approval_status: 'pending', subtotal: 640, vat_total: 128, total: 768, amount_paid: 0, amount_due: 768 },
  ] },
  { module: 'stock', table: 'purchase_invoice_lines', rows: [
    { purchase_invoice_id: '@factf1.id', product_id: '@prod1.id', description: 'Ramette A4 80g', quantity: 200, unit_price: 3.2, vat_rate: 20, total: 640, vat_total: 128, line_order: 1 },
  ] },
  { module: 'stock', table: 'supplier_payments', rows: [
    { number: 'RF-2026-0001', supplier_id: '@four1.id', purchase_invoice_id: '@factf1.id', payment_date: '2026-03-25', amount: 768, method: 'transfer', bank_account_id: '@compte1.id', reference: 'FF-2026-0001', status: 'recorded' },
  ] },
  // ── Production ──────────────────────────────────────────────────
  { module: 'production', table: 'boms', rows: [
    { __as: 'nomen1', code: 'NOM-CHAISE', name: 'Chaise ergonomique — nomenclature', product_id: '@prod4.id', quantity: 1, unit: 'pièce', bom_type: 'standard', active: true },
  ] },
  { module: 'production', table: 'bom_lines', rows: [
    { bom_id: '@nomen1.id', product_id: '@prod1.id', quantity: 1, unit_cost: 3.2, position: 1 },
  ] },
  { module: 'production', table: 'manufacturing_orders', rows: [
    { number: 'OF-2026-0001', bom_id: '@nomen1.id', product_id: '@prod4.id', quantity: 10, status: 'planned', start_date: '2026-03-18', warehouse_id: '@depot1.id' },
  ] },
  // ── Comptabilité ────────────────────────────────────────────────
  { module: 'accounting', table: 'journal_entries', rows: [
    { __as: 'ecr1', number: 'VE-2026-0001', date: '2026-03-10', journal_code: 'VT', reference: 'FA-2026-0001', description: 'Facture de vente FA-2026-0001', status: 'draft', total_debit: 1294.8, total_credit: 1294.8 },
    { __as: 'ecr2', number: 'AC-2026-0001', date: '2026-03-04', journal_code: 'AC', reference: 'FF-2026-0001', description: 'Facture d achat FF-2026-0001', status: 'draft', total_debit: 768, total_credit: 768 },
  ] },
  { module: 'accounting', table: 'journal_lines', rows: [
    { journal_id: '@ecr1.id', account_code: '411000', account_name: 'Clients', debit: 1294.8, credit: 0, description: 'FA-2026-0001', line_order: 1 },
    { journal_id: '@ecr1.id', account_code: '707000', account_name: 'Ventes', debit: 0, credit: 1079, description: 'FA-2026-0001', line_order: 2 },
    { journal_id: '@ecr1.id', account_code: '445710', account_name: 'TVA collectée', debit: 0, credit: 215.8, description: 'FA-2026-0001', line_order: 3 },
    { journal_id: '@ecr2.id', account_code: '607000', account_name: 'Achats', debit: 640, credit: 0, description: 'FF-2026-0001', line_order: 1 },
    { journal_id: '@ecr2.id', account_code: '445660', account_name: 'TVA déductible', debit: 128, credit: 0, description: 'FF-2026-0001', line_order: 2 },
    { journal_id: '@ecr2.id', account_code: '401000', account_name: 'Fournisseurs', debit: 0, credit: 768, description: 'FF-2026-0001', line_order: 3 },
  ] },
  { module: 'accounting', table: 'fixed_assets', rows: [
    { name: 'Véhicule utilitaire', code: 'IMM-001', category: 'Véhicules', asset_type: 'owned', purchase_date: '2026-01-10', purchase_value: 24000, current_value: 24000, useful_life_years: 5, depreciation_method: 'linear', residual_value: 0, status: 'active' },
  ] },
  { module: 'accounting', table: 'analytic_sections', rows: [
    { code: 'LOT-A', name: 'Chantier Alpes', axis: 'chantier', active: true },
  ] },
  // ── Paie et RH ──────────────────────────────────────────────────
  { module: 'hr', table: 'contracts', rows: [
    { number: 'CT-2026-0001', employee_id: '@sal1.id', contract_type: 'cdi', start_date: '2024-03-01', position: 'Comptable', department: 'Comptabilité', monthly_salary: 2600, weekly_hours: 35, status: 'active' },
    { number: 'CT-2026-0002', employee_id: '@sal2.id', contract_type: 'cdi', start_date: '2025-01-15', position: 'Magasinier', department: 'Logistique', monthly_salary: 2100, weekly_hours: 35, status: 'active' },
  ] },
  { module: 'hr', table: 'pay_runs', rows: [
    { __as: 'lot1', number: 'PAIE-2026-03', period_start: '2026-03-01', period_end: '2026-03-31', pay_date: '2026-03-31', status: 'draft', gross_total: 4700, tax_total: 578.5, net_total: 3721, employee_count: 2 },
  ] },
  { module: 'hr', table: 'pay_slips', rows: [
    { number: 'BP-2026-03-001', pay_run_id: '@lot1.id', employee_id: '@sal1.id', period_start: '2026-03-01', period_end: '2026-03-31', gross_salary: 2600, total_gross: 2600, social_security_employee: 578.5, total_deductions: 578.5, net_salary: 2021.5, employer_contributions: 1160, status: 'draft' },
    { number: 'BP-2026-03-002', pay_run_id: '@lot1.id', employee_id: '@sal2.id', period_start: '2026-03-01', period_end: '2026-03-31', gross_salary: 2100, total_gross: 2100, social_security_employee: 467.25, total_deductions: 467.25, net_salary: 1632.75, employer_contributions: 897, status: 'draft' },
  ] },
  { module: 'hr', table: 'leave_requests', rows: [
    { employee_id: '@sal1.id', leave_type: 'annual', start_date: '2026-04-06', end_date: '2026-04-10', days: 5, status: 'pending', reason: 'Congés de printemps' },
  ] },
  { module: 'hr', table: 'expense_reports', rows: [
    { __as: 'ndf1', employee_id: '@sal1.id', number: 'NDF-2026-0001', period: '2026-03', total_amount: 214.5, status: 'submitted' },
  ] },
  { module: 'hr', table: 'expense_report_lines', rows: [
    { expense_report_id: '@ndf1.id', date: '2026-03-12', category: 'transport', amount: 128.5, description: 'Train Lyon-Paris', vat_rate: 10, vat_amount: 11.68 },
    { expense_report_id: '@ndf1.id', date: '2026-03-13', category: 'meal', amount: 86, description: 'Repas client', vat_rate: 20, vat_amount: 14.33 },
  ] },
  { module: 'hr', table: 'timesheets', rows: [
    { employee_id: '@sal1.id', date: '2026-03-16', hours: 7, project_id: '@proj1.id', status: 'approved', description: 'Recette client' },
    { employee_id: '@sal1.id', date: '2026-03-17', hours: 8, project_id: '@proj2.id', status: 'pending', description: 'Paramétrage ERP' },
  ] },
  // ── Caisse et trésorerie ────────────────────────────────────────
  { module: 'commercial', table: 'pos_terminals', rows: [
    { __as: 'caisse1', name: 'Caisse comptoir', warehouse_id: '@depot1.id', location: 'Boutique Lyon', active: true },
  ] },
  { module: 'commercial', table: 'pos_sessions', rows: [
    { __as: 'session1', terminal_id: '@caisse1.id', user_email: 'qa-patron@qa.local', session_number: 'CS-2026-0001', opening_amount: 150, status: 'open', opened_at: '2026-03-20T08:00:00Z' },
  ] },
  { module: 'commercial', table: 'pos_tickets', rows: [
    { __as: 'ticket1', number: 'TCK-0001', session_id: '@session1.id', terminal_id: '@caisse1.id', date: '2026-03-20T09:15:00Z', subtotal: 24.5, vat_total: 4.9, total: 24.5, payment_method: 'cash', amount_paid: 25, change_given: 0.5, status: 'completed' },
  ] },
  { module: 'commercial', table: 'pos_ticket_lines', rows: [
    { ticket_id: '@ticket1.id', product_id: '@prod1.id', description: 'Ramette A4', quantity: 2, unit_price: 6.5, vat_rate: 20, line_total: 13 },
    { ticket_id: '@ticket1.id', product_id: '@prod2.id', description: 'Clavier', quantity: 1, unit_price: 11.5, vat_rate: 20, line_total: 11.5 },
  ] },
  { module: 'treasury', table: 'bank_transactions', rows: [
    { account_id: '@compte1.id', date: '2026-03-20', amount: 1294.8, type: 'credit', description: 'Virement Boulangerie Martin', reference: 'FA-2026-0001', reconciled: false },
    { account_id: '@compte1.id', date: '2026-03-25', amount: 768, type: 'debit', description: 'Prélèvement Papeterie Centrale', reference: 'FF-2026-0001', reconciled: false },
  ] },
]
