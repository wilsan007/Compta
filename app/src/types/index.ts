// All types use snake_case to match Supabase database columns exactly

export type InvoiceStatus = 'draft' | 'sent' | 'viewed' | 'paid' | 'overdue' | 'cancelled'
export type QuoteStatus = 'draft' | 'sent' | 'accepted' | 'rejected' | 'expired'
export type CreditStatus = 'draft' | 'applied'
export type AccountType = 'chequing' | 'savings' | 'credit_card' | 'cash' | 'loan' | 'other'
export type ReportPeriod = 'month' | 'quarter' | 'year' | 'custom'

export interface Customer {
  id: string
  name: string
  email: string
  phone: string
  address: string
  city: string
  postal_code: string
  country: string
  vat_number: string
  contact_name: string
  balance: number
  credit_limit: number
  payment_terms: string
  currency: string
  active: boolean
  created_at: string
  updated_at: string
}

export interface Supplier {
  id: string
  name: string
  email: string
  phone: string
  address: string
  city: string
  postal_code: string
  country: string
  vat_number: string
  contact_name: string
  balance: number
  payment_terms: string
  currency: string
  active: boolean
  created_at: string
  updated_at: string
}

export interface InvoiceLine {
  id: string
  invoice_id: string
  product_id: string | null
  description: string
  quantity: number
  unit_price: number
  vat_rate: number
  total: number
  vat_total: number
  line_order: number
  created_at: string
}

export interface Invoice {
  id: string
  number: string
  customer_id: string | null
  customer_name: string | null
  date: string
  due_date: string
  status: InvoiceStatus
  subtotal: number
  vat_total: number
  total: number
  amount_paid: number
  amount_due: number
  notes: string
  recurring: boolean
  recurring_frequency: string | null
  created_at: string
  updated_at: string
  invoice_lines?: InvoiceLine[]
}

export interface QuoteLine {
  id: string
  quote_id: string
  product_id: string | null
  description: string
  quantity: number
  unit_price: number
  vat_rate: number
  total: number
  vat_total: number
  line_order: number
  created_at: string
}

export interface Quote {
  id: string
  number: string
  customer_id: string | null
  customer_name: string | null
  date: string
  expiry_date: string
  status: QuoteStatus
  subtotal: number
  vat_total: number
  total: number
  notes: string
  created_at: string
  updated_at: string
  quote_lines?: QuoteLine[]
}

export interface CreditNoteLine {
  id: string
  credit_note_id: string
  description: string
  quantity: number
  unit_price: number
  vat_rate: number
  total: number
  vat_total: number
  line_order: number
  created_at: string
}

export interface CreditNote {
  id: string
  number: string
  customer_id: string | null
  customer_name: string | null
  date: string
  status: CreditStatus
  subtotal: number
  vat_total: number
  total: number
  reason: string
  invoice_id: string | null
  created_at: string
  credit_note_lines?: CreditNoteLine[]
}

export interface PurchaseInvoiceLine {
  id: string
  purchase_invoice_id: string
  product_id: string | null
  description: string
  quantity: number
  unit_price: number
  vat_rate: number
  total: number
  vat_total: number
  line_order: number
  created_at: string
}

export interface PurchaseInvoice {
  id: string
  number: string
  supplier_id: string | null
  supplier_name: string | null
  date: string
  due_date: string
  status: InvoiceStatus
  subtotal: number
  vat_total: number
  total: number
  amount_paid: number
  amount_due: number
  notes: string
  created_at: string
  updated_at: string
  purchase_invoice_lines?: PurchaseInvoiceLine[]
}

export interface BankAccount {
  id: string
  name: string
  type: AccountType
  account_number: string
  sort_code: string
  balance: number
  currency: string
  bank_name: string
  last_reconciled: string | null
  connected: boolean
  created_at: string
  updated_at: string
}

export interface BankTransaction {
  id: string
  account_id: string
  date: string
  description: string
  reference: string
  type: 'debit' | 'credit'
  amount: number
  category: string
  reconciled: boolean
  matched: boolean
  invoice_id: string | null
  purchase_invoice_id: string | null
  created_at: string
}

export interface Product {
  id: string
  name: string
  sku: string
  description: string
  type: 'stock' | 'service'
  sale_price: number
  purchase_price: number
  vat_rate: number
  stock_quantity: number
  reorder_level: number
  unit: string
  category: string
  active: boolean
  created_at: string
  updated_at: string
}

export interface JournalLine {
  id: string
  journal_id: string
  account_code: string
  account_name: string
  debit: number
  credit: number
  description: string
  line_order: number
  created_at: string
  account_general?: string | null
  account_tiers?: string | null
  third_party_id?: string | null
  lettrage_code?: string | null
  lettrage_date?: string | null
  piece_number?: string | null
  reference?: string | null
  analytic_section_id?: string | null
  analytic_amount?: number | null
  running_balance?: number | null
  reconciled?: boolean
  line_date?: string | null
}

export interface JournalEntry {
  id: string
  number: string
  date: string
  description: string
  reference: string
  status: 'draft' | 'posted'
  total_debit: number
  total_credit: number
  created_at: string
  updated_at: string
  journal_lines?: JournalLine[]
  journal_code?: string | null
  fiscal_period_id?: string | null
  piece_number?: string | null
  invoice_ref?: string | null
  entry_template_id?: string | null
  status_detail?: 'open' | 'printed' | 'closed' | null
  validated_by?: string | null
  validated_at?: string | null
}

export interface ChartAccount {
  id: string
  code: string
  name: string
  type: 'asset' | 'liability' | 'equity' | 'income' | 'expense'
  balance: number
  vat_rate: string
  description: string
  parent_id: string | null
  created_at: string
}

export interface User {
  id: string
  auth_id: string | null
  name: string
  email: string
  role: 'admin' | 'accountant' | 'manager' | 'viewer'
  active: boolean
  last_login: string | null
  created_at: string
  updated_at: string
}

export interface BankRule {
  id: string
  name: string
  condition_field: string
  condition_operator: string
  condition_value: string
  action_category: string
  action_account_code: string
  action_vat_rate: number
  priority: number
  active: boolean
  created_at: string
}

export interface Project {
  id: string
  name: string
  description: string
  customer_id: string | null
  status: 'active' | 'completed' | 'on_hold' | 'cancelled'
  budget: number
  actual_cost: number
  start_date: string
  end_date: string
  created_at: string
  updated_at: string
}

export interface VatReturn {
  id: string
  period_start: string
  period_end: string
  status: 'draft' | 'submitted' | 'paid'
  box1_output_vat: number
  box2_input_vat: number
  box3_vat_due: number
  box4_repayment_due: number
  box5_net_vat: number
  total_sales: number
  total_purchases: number
  submitted_date: string | null
  created_at: string
}

export interface CompanySettings {
  id: string
  name: string
  legal_name: string
  vat_number: string
  siret: string
  address: string
  city: string
  postal_code: string
  country: string
  currency: string
  fiscal_year_start: string
  email: string
  phone: string
  website: string
  logo_url: string
  country_code: string | null
  legislation_pack_code: string | null
  created_at: string
  updated_at: string
}

export type TaxCategory = 'standard' | 'intermediate' | 'reduced' | 'super_reduced' | 'zero' | 'exempt'

export interface LegislationPack {
  code: string
  name: string
  country_code: string
  country_name: string
  accounting_standard: string
  currency: string
  currency_decimals: number
  date_format: string
  locale: string
  fiscal_year_start: string
  tax_id_label: string
  tax_id_secondary_label: string | null
  is_default: boolean
  active: boolean
  created_at: string
  updated_at: string
}

export interface TaxRate {
  id: string
  pack_code: string
  name: string
  category: TaxCategory
  rate: number
  account_code: string | null
  is_default: boolean
  effective_from: string
  effective_to: string | null
  created_at: string
}

export interface DashboardStats {
  totalRevenue: number
  outstandingInvoice: number
  outstandingBills: number
  bankBalance: number
  totalDebtors: number
  totalCreditors: number
  invoiceCount: number
  billCount: number
}

// ============ Purchase Credit Notes ============
export interface PurchaseCreditNoteLine {
  id: string
  purchase_credit_id: string
  description: string
  quantity: number
  unit_price: number
  vat_rate: number
  total: number
  vat_total: number
  line_order: number
  created_at: string
}

export interface PurchaseCreditNote {
  id: string
  number: string
  supplier_id: string | null
  supplier_name: string | null
  date: string
  status: 'draft' | 'applied'
  subtotal: number
  vat_total: number
  total: number
  reason: string
  purchase_invoice_id: string | null
  created_at: string
  purchase_credit_lines?: PurchaseCreditNoteLine[]
}

// ============ Fixed Assets ============
export interface FixedAsset {
  id: string
  name: string
  code: string
  category: string
  purchase_date: string
  purchase_value: number
  current_value: number
  depreciation_method: string
  useful_life_years: number
  residual_value: number
  status: 'active' | 'disposed' | 'fully_depreciated'
  created_at: string
  updated_at: string
}

// ============ Employees ============
export interface Employee {
  id: string
  name: string
  email: string
  phone: string
  position: string
  department: string
  salary: number
  hire_date: string
  status: 'active' | 'inactive' | 'on_leave'
  created_at: string
  updated_at: string
}

// ============ Pay Runs ============
export interface PayRun {
  id: string
  number: string
  period_start: string
  period_end: string
  pay_date: string
  status: 'draft' | 'approved' | 'paid'
  gross_total: number
  tax_total: number
  net_total: number
  employee_count: number
  created_at: string
}

// ============ Timesheets ============
export interface Timesheet {
  id: string
  employee_id: string
  date: string
  hours: number
  description: string
  project_id: string | null
  status: 'pending' | 'approved' | 'rejected'
  created_at: string
}

// ============ Currencies ============
export interface Currency {
  id: string
  code: string
  name: string
  symbol: string
  exchange_rate: number
  is_base: boolean
  created_at: string
}

// ============ Journals (codes journaux) ============
export interface Journal {
  id: string
  code: string
  name: string
  type: 'purchase' | 'sale' | 'bank' | 'cash' | 'general' | 'analytic'
  account_counterpart: string | null
  bank_account_id: string | null
  default_entry_template_id: string | null
  status: 'active' | 'inactive'
  locked: boolean
  created_at: string
  updated_at: string
}

// ============ Fiscal Years & Periods ============
export interface FiscalYear {
  id: string
  code: string
  start_date: string
  end_date: string
  status: 'open' | 'closed' | 'locked'
  closed_at: string | null
  closed_by: string | null
  created_at: string
}

export interface FiscalPeriod {
  id: string
  fiscal_year_id: string
  period_number: number
  period_label: string
  start_date: string
  end_date: string
  status: 'open' | 'closed' | 'locked'
  created_at: string
}

// ============ Entry Templates (modèles de saisie) ============
export interface EntryTemplate {
  id: string
  name: string
  journal_code: string | null
  description: string | null
  template_lines: any[] | null
  is_default: boolean
  active: boolean
  created_at: string
}

// ============ Third Party Accounts (plan tiers unifié) ============
export interface ThirdPartyAccount {
  id: string
  code: string
  account_general_code: string | null
  type: 'customer' | 'supplier' | 'employee' | 'other'
  name: string
  customer_id: string | null
  supplier_id: string | null
  employee_id: string | null
  balance: number
  lettrage_code: string | null
  currency: string
  active: boolean
  created_at: string
  updated_at: string
}

// ============ Analytic Sections ============
export interface AnalyticSection {
  id: string
  code: string
  name: string
  parent_id: string | null
  axis: string | null
  level: number
  active: boolean
  created_at: string
}

// ============ Budgets ============
export interface Budget {
  id: string
  name: string
  fiscal_year_id: string | null
  account_code: string | null
  analytic_section_id: string | null
  period_1: number
  period_2: number
  period_3: number
  period_4: number
  period_5: number
  period_6: number
  period_7: number
  period_8: number
  period_9: number
  period_10: number
  period_11: number
  period_12: number
  created_at: string
}

// ============ Budget Commitments ============
export interface BudgetCommitment {
  id: string
  description: string
  account_code: string
  fiscal_year_id: string | null
  amount: number
  commitment_date: string
  source_type: 'manual' | 'purchase_order' | 'purchase_invoice'
  source_id: string | null
  status: 'active' | 'consumed' | 'cancelled'
  supplier_id: string | null
  notes: string | null
  created_at: string
  updated_at: string
}

export interface BudgetControlResult {
  account_code: string
  budget_total: number
  realized: number
  committed: number
  available: number
  would_exceed: boolean
  overshoot_amount: number
}

// ============ Standard Labels ============
export interface StandardLabel {
  id: string
  label: string
  category: string | null
  created_at: string
}

// ============ Payment Orders ============
export interface PaymentOrder {
  id: string
  number: string
  type: 'sepa_transfer' | 'check' | 'cash' | 'card' | 'other'
  status: 'draft' | 'approved' | 'executed' | 'cancelled'
  bank_account_id: string | null
  third_party_id: string | null
  third_party_name: string | null
  third_party_iban: string | null
  amount: number
  payment_date: string
  reference: string | null
  description: string | null
  remise_number: string | null
  created_at: string
  updated_at: string
}

// ============ Asset Depreciations ============
export interface AssetDepreciation {
  id: string
  asset_id: string
  fiscal_year_code: string | null
  period: number
  depreciation_type: 'depreciation' | 'disposal' | 'dotation'
  amount: number
  cumulative_amount: number
  net_book_value: number
  entry_number: string | null
  created_at: string
}

// ============ Collection Reminders ============
export interface CollectionReminder {
  id: string
  number: string
  customer_id: string | null
  third_party_id: string | null
  invoice_id: string | null
  reminder_level: 1 | 2 | 3
  reminder_date: string
  due_date: string | null
  amount: number
  status: 'draft' | 'sent' | 'paid' | 'cancelled'
  notes: string | null
  created_at: string
}

// ============ Sprint 6: GesCom Types ============

export interface SalesOrder {
  id: string
  number: string
  customer_id: string | null
  order_date: string
  delivery_date: string | null
  status: 'draft' | 'confirmed' | 'delivered' | 'invoiced' | 'cancelled'
  subtotal: number
  vat: number
  total: number
  notes: string | null
  created_at: string
  updated_at: string
}

export interface SalesOrderLine {
  id: string
  sales_order_id: string
  product_id: string | null
  description: string
  quantity: number
  unit_price: number
  vat_rate: number
  line_total: number
}

export interface DeliveryNote {
  id: string
  number: string
  customer_id: string | null
  sales_order_id: string | null
  delivery_date: string
  status: 'pending' | 'delivered' | 'returned' | 'cancelled'
  carrier: string | null
  tracking_number: string | null
  notes: string | null
  created_at: string
}

export interface DeliveryNoteLine {
  id: string
  delivery_note_id: string
  product_id: string | null
  description: string
  quantity: number
}

export interface CustomerPayment {
  id: string
  number: string
  customer_id: string | null
  invoice_id: string | null
  payment_date: string
  amount: number
  method: 'cash' | 'check' | 'transfer' | 'card' | 'direct_debit' | 'other' | null
  bank_account_id: string | null
  reference: string | null
  status: 'recorded' | 'reconciled' | 'cancelled'
  created_at: string
}

export interface PurchaseOrder {
  id: string
  number: string
  supplier_id: string | null
  order_date: string
  expected_date: string | null
  status: 'draft' | 'confirmed' | 'received' | 'cancelled'
  subtotal: number
  vat: number
  total: number
  notes: string | null
  created_at: string
  updated_at: string
}

export interface PurchaseOrderLine {
  id: string
  purchase_order_id: string
  product_id: string | null
  description: string
  quantity: number
  unit_price: number
  vat_rate: number
  line_total: number
}

export interface GoodsReceipt {
  id: string
  number: string
  supplier_id: string | null
  purchase_order_id: string | null
  receipt_date: string
  status: 'pending' | 'received' | 'partial' | 'cancelled'
  notes: string | null
  created_at: string
}

export interface GoodsReceiptLine {
  id: string
  goods_receipt_id: string
  product_id: string | null
  description: string
  quantity_ordered: number
  quantity_received: number
}

export interface SupplierPayment {
  id: string
  number: string
  supplier_id: string | null
  purchase_invoice_id: string | null
  payment_date: string
  amount: number
  method: 'cash' | 'check' | 'transfer' | 'card' | 'direct_debit' | 'other' | null
  bank_account_id: string | null
  reference: string | null
  status: 'recorded' | 'reconciled' | 'cancelled'
  created_at: string
}

export interface Warehouse {
  id: string
  code: string
  name: string
  address: string | null
  city: string | null
  postal_code: string | null
  country: string
  active: boolean
  created_at: string
}

export interface StockQuantity {
  id: string
  product_id: string
  warehouse_id: string
  quantity: number
  reserved_quantity: number
  min_quantity: number
  max_quantity: number
  reorder_point: number
  unit_cost: number
  created_at: string
  updated_at: string
}

export interface StockMovement {
  id: string
  product_id: string
  warehouse_id: string | null
  movement_type: 'in' | 'out' | 'transfer' | 'adjustment' | 'initial'
  quantity: number
  unit_cost: number
  reference: string | null
  reference_type: 'delivery_note' | 'goods_receipt' | 'inventory' | 'transfer' | 'manual' | null
  reference_id: string | null
  movement_date: string
  notes: string | null
  created_at: string
}

export interface PriceList {
  id: string
  name: string
  code: string | null
  type: 'sales' | 'purchase'
  currency: string
  valid_from: string | null
  valid_to: string | null
  active: boolean
  is_default: boolean
  created_at: string
}

export interface PriceListLine {
  id: string
  price_list_id: string
  product_id: string
  unit_price: number
  min_quantity: number
  discount_percent: number
}

export interface BOM {
  id: string
  code: string
  name: string
  product_id: string | null
  quantity: number
  unit: string
  active: boolean
  bom_type: 'standard' | 'amalgam'
  routing_id: string | null
  created_at: string
}

export interface BOMLine {
  id: string
  bom_id: string
  product_id: string
  quantity: number
  unit_cost: number
  position: number
}

export interface ManufacturingOrder {
  id: string
  number: string
  bom_id: string | null
  product_id: string | null
  quantity: number
  status: 'planned' | 'in_progress' | 'completed' | 'cancelled'
  start_date: string | null
  end_date: string | null
  warehouse_id: string | null
  notes: string | null
  origin: 'manual' | 'mrp' | 'sub_level'
  parent_mo_id: string | null
  routing_id: string | null
  lot_number: string | null
  expiry_date: string | null
  custom_expiry_date: string | null
  expiry_type: 'DLUO' | 'DDM' | 'DLC' | null
  label_enabled: boolean
  additional_text: string | null
  created_at: string
}

// ============ Sprint 7: Paie & RH Types ============

export interface PaySlip {
  id: string
  number: string
  pay_run_id: string | null
  employee_id: string
  period_start: string
  period_end: string
  gross_salary: number
  overtime_pay: number
  bonus: number
  total_gross: number
  social_security_employee: number
  income_tax: number
  other_deductions: number
  total_deductions: number
  net_salary: number
  employer_contributions: number
  status: 'draft' | 'approved' | 'paid' | 'cancelled'
  payment_date: string | null
  created_at: string
}

export interface PayrollAccountingEntry {
  id: string
  number: string
  pay_run_id: string | null
  period_date: string
  gross_total: number
  employer_contributions_total: number
  employee_deductions_total: number
  net_total: number
  journal_entry_id: string | null
  status: 'draft' | 'transferred' | 'cancelled'
  created_at: string
}

export interface LeaveRequest {
  id: string
  employee_id: string
  leave_type: 'annual' | 'sick' | 'maternity' | 'paternity' | 'unpaid' | 'other'
  start_date: string
  end_date: string
  days: number
  status: 'pending' | 'approved' | 'rejected' | 'cancelled'
  reason: string | null
  approved_by: string | null
  approved_at: string | null
  created_at: string
}

export interface Contract {
  id: string
  number: string
  employee_id: string
  contract_type: 'cdi' | 'cdd' | 'apprentissage' | 'stage' | 'interim' | 'freelance'
  start_date: string
  end_date: string | null
  position: string | null
  department: string | null
  monthly_salary: number
  hourly_rate: number
  weekly_hours: number
  trial_period_days: number
  status: 'active' | 'ended' | 'suspended' | 'terminated'
  notes: string | null
  created_at: string
}

export interface LegalDeclaration {
  id: string
  number: string
  declaration_type: 'dsn' | 'urssaf' | 'dgt' | 'ifrs' | 'other'
  period_month: number
  period_year: number
  due_date: string
  submission_date: string | null
  amount: number
  status: 'pending' | 'submitted' | 'late' | 'cancelled'
  notes: string | null
  created_at: string
}

export interface AuditLog {
  id: string
  user_id: string | null
  action: 'create' | 'update' | 'delete' | 'login' | 'logout' | 'transfer' | 'validate' | 'close' | 'export'
  entity_type: string
  entity_id: string | null
  entity_number: string | null
  description: string | null
  metadata: Record<string, any> | null
  ip_address: string | null
  created_at: string
}

// ============ Production Module: Gamme & Machine ============

export interface Routing {
  id: string
  code: string
  name: string
  description: string | null
  product_id: string | null
  version: number
  active: boolean
  created_at: string
  updated_at: string
}

export interface RoutingOperation {
  id: string
  routing_id: string
  sequence: number
  name: string
  description: string | null
  work_center_id: string | null
  machine_id: string | null
  tooling_id: string | null
  setup_time_min: number
  run_time_min: number
  is_subcontracted: boolean
  supplier_id: string | null
  st_unit: string | null
  st_quantity: number
  created_at: string
}

export interface WorkCenter {
  id: string
  code: string
  name: string
  capacity_hours_per_day: number
  cost_per_hour: number
  active: boolean
  created_at: string
}

export interface Machine {
  id: string
  code: string
  name: string
  work_center_id: string | null
  capacity_per_hour: number
  status: 'active' | 'maintenance' | 'inactive'
  purchase_date: string | null
  notes: string | null
  created_at: string
}

export interface Tooling {
  id: string
  code: string
  name: string
  machine_id: string | null
  max_pieces: number
  initial_counter: number
  current_counter: number
  status: 'active' | 'worn' | 'inactive'
  notes: string | null
  created_at: string
}

// ============ Production Module: OF Enhancements ============

export interface OFLabel {
  id: string
  manufacturing_order_id: string
  label_number: string
  product_id: string | null
  planned_quantity: number
  actual_quantity: number
  is_complete: boolean
  is_declared: boolean
  created_at: string
}

export interface OFLot {
  id: string
  manufacturing_order_id: string
  lot_number: string
  product_id: string | null
  quantity: number
  production_date: string | null
  expiry_date: string | null
  custom_expiry_date: string | null
  expiry_type: 'DLUO' | 'DDM' | 'DLC' | null
  created_at: string
}

export interface OFConsumption {
  id: string
  manufacturing_order_id: string
  product_id: string
  quantity: number
  unit: string
  consumption_date: string
  is_deferred: boolean
  notes: string | null
  created_at: string
}

// ============ Production Module: Sous-traitance ============

export interface STOrder {
  id: string
  number: string
  supplier_id: string
  manufacturing_order_id: string | null
  routing_operation_id: string | null
  product_id: string | null
  quantity: number
  unit: string
  unit_price: number
  total_price: number
  status: 'draft' | 'sent' | 'in_progress' | 'received' | 'cancelled'
  order_date: string
  expected_date: string | null
  notes: string | null
  created_at: string
}

export interface STShipment {
  id: string
  number: string
  st_order_id: string
  shipment_date: string
  warehouse_id: string | null
  status: 'pending' | 'shipped' | 'returned'
  notes: string | null
  created_at: string
}

export interface STShipmentLine {
  id: string
  st_shipment_id: string
  product_id: string
  quantity: number
  unit: string
  created_at: string
}

export interface STReceipt {
  id: string
  number: string
  st_order_id: string
  receipt_date: string
  warehouse_id: string | null
  quantity_received: number
  quantity_returned: number
  status: 'pending' | 'received' | 'partial' | 'cancelled'
  notes: string | null
  created_at: string
}

export interface STReceiptLine {
  id: string
  st_receipt_id: string
  product_id: string
  quantity: number
  unit: string
  line_type: 'received' | 'returned'
  created_at: string
}

// ============ Production Module: CBN/MRP ============

export interface MRPRun {
  id: string
  run_number: string
  run_date: string
  status: 'running' | 'completed' | 'cancelled'
  parameters: Record<string, any> | null
  summary: Record<string, any> | null
  created_at: string
}

export interface MRPProposal {
  id: string
  mrp_run_id: string
  product_id: string
  proposal_type: 'purchase' | 'manufacture' | 'subcontract'
  gross_need: number
  stock_available: number
  open_orders: number
  net_need: number
  suggested_quantity: number
  suggested_date: string | null
  bom_id: string | null
  supplier_id: string | null
  status: 'pending' | 'approved' | 'rejected' | 'converted'
  notes: string | null
  created_at: string
}

export interface MRPPendingDoc {
  id: string
  doc_type: 'purchase_order' | 'manufacturing_order' | 'subcontract_order'
  doc_id: string | null
  product_id: string | null
  quantity: number
  status: 'pending' | 'processed' | 'cancelled'
  created_at: string
}

// ============ Production Module: Prévisions ============

export interface ProductionForecast {
  id: string
  forecast_number: string
  period: string
  start_date: string
  end_date: string
  product_id: string | null
  forecasted_quantity: number
  actual_quantity: number
  reliability_rate: number
  source: 'manual' | 'invoice_import'
  notes: string | null
  created_at: string
}

// ============ Production Module: Planification ============

export interface PlanningSlot {
  id: string
  manufacturing_order_id: string
  routing_operation_id: string | null
  machine_id: string | null
  work_center_id: string | null
  planned_start: string | null
  planned_end: string | null
  setup_time: number
  run_time: number
  status: 'planned' | 'scheduled' | 'in_progress' | 'completed'
  material_available: boolean
  material_check_date: string | null
  created_at: string
}

// ============ Production Module: Complémentaires ============

export interface ProductEquivalence {
  id: string
  product_id: string
  equivalent_product_id: string
  conversion_ratio: number
  created_at: string
}

export interface Workflow {
  id: string
  name: string
  description: string | null
  workflow_type: 'mrp' | 'forecast' | 'planning' | 'custom'
  schedule: string | null
  last_run: string | null
  status: 'active' | 'inactive'
  created_at: string
}

export interface OFDocumentAccess {
  id: string
  user_id: string
  document_type: string
  can_view: boolean
  can_print: boolean
  can_export: boolean
  created_at: string
}

export interface RecurringEntryLine {
  account_code: string
  description: string
  debit: number
  credit: number
}

export interface RecurringEntry {
  id: string
  tenant_id: string
  name: string
  description: string | null
  journal_id: string
  journal_code: string | null
  frequency: 'weekly' | 'monthly' | 'quarterly' | 'yearly'
  day_of_month: number
  start_date: string
  end_date: string | null
  next_generation_date: string
  last_generation_date: string | null
  lines: RecurringEntryLine[]
  status: 'active' | 'paused' | 'expired'
  total_debit: number
  total_credit: number
  created_at: string
  updated_at: string
}

export interface RegularizationEntry {
  id: string
  tenant_id: string
  type: 'CCA' | 'PCA' | 'PRC' | 'CRC'
  fiscal_year_id: string | null
  account_code: string
  third_party_code: string | null
  description: string
  invoice_number: string | null
  invoice_date: string | null
  invoice_amount: number
  start_date: string
  end_date: string
  amount: number
  used_amount: number
  remaining_amount: number
  status: 'pending' | 'regularized' | 'extourned'
  journal_id: string | null
  journal_code: string | null
  created_entry_id: string | null
  extourne_entry_id: string | null
  created_at: string
  updated_at: string
}

export interface CurrencyRevaluation {
  id: string
  tenant_id: string
  fiscal_year_id: string | null
  period_date: string
  account_code: string
  third_party_code: string | null
  currency: string
  original_rate: number
  new_rate: number
  original_amount: number
  original_amount_eur: number
  revalued_amount_eur: number
  gain_loss: number
  type: 'receivable' | 'payable'
  status: 'pending' | 'posted'
  entry_id: string | null
  created_at: string
  updated_at: string
}

export interface AnalyticPlan {
  id: string
  tenant_id: string
  code: string
  name: string
  description: string | null
  is_default: boolean
  active: boolean
  created_at: string
  updated_at: string
}

export interface DistributionGrillLine {
  id: string
  grill_id: string
  section_code: string
  percentage: number
  created_at: string
}

export interface DistributionGrill {
  id: string
  tenant_id: string
  name: string
  description: string | null
  account_code: string
  journal_code: string | null
  active: boolean
  lines: DistributionGrillLine[]
  created_at: string
  updated_at: string
}

export interface BankReconciliationRule {
  id: string
  tenant_id: string
  name: string
  afb_code: string
  description: string | null
  match_pattern: string | null
  counterpart_account: string | null
  journal_code: string | null
  priority: number
  active: boolean
  created_at: string
  updated_at: string
}

export interface BankStatementImport {
  id: string
  tenant_id: string
  bank_account_id: string
  filename: string
  format: string
  file_size: number | null
  status: 'pending' | 'processing' | 'completed' | 'failed'
  imported_count: number
  error_message: string | null
  imported_at: string
}

export interface TvsDeclaration {
  id: string
  tenant_id: string
  fiscal_year: number
  vehicle_registration: string
  vehicle_type: string | null
  co2_emissions: number | null
  first_registration_date: string | null
  amount_co2: number
  amount_age: number
  amount_total: number
  status: 'draft' | 'filed' | 'paid'
  filed_at: string | null
  created_at: string
  updated_at: string
}

export interface FiscalBackup {
  id: string
  tenant_id: string
  fiscal_year_id: string | null
  backup_type: 'manual' | 'automatic'
  status: 'pending' | 'completed' | 'failed'
  file_url: string | null
  file_size: number | null
  created_by: string | null
  created_at: string
}

// ============ Phase 2: GesCom ============

export interface ProductAttribute {
  id: string
  tenant_id: string | null
  name: string
  type: 'select' | 'text' | 'number' | 'color'
  options: any[]
  created_at: string
}

export interface ProductVariant {
  id: string
  tenant_id: string | null
  product_id: string
  sku: string
  attributes: Record<string, any>
  price_override: number | null
  barcode: string | null
  active: boolean
  created_at: string
}

export interface ProductSerialNumber {
  id: string
  tenant_id: string | null
  product_id: string
  serial_number: string
  status: 'in_stock' | 'sold' | 'returned' | 'warranty'
  warranty_expiry: string | null
  notes: string | null
  created_at: string
}

export interface ProductBatch {
  id: string
  tenant_id: string | null
  product_id: string
  batch_number: string
  quantity: number
  expiry_date: string | null
  status: 'active' | 'expired' | 'quarantine'
  created_at: string
}

export interface WarehouseLocation {
  id: string
  tenant_id: string | null
  warehouse_id: string
  zone: string | null
  aisle: string | null
  shelf: string | null
  code: string
  description: string | null
  created_at: string
}

export interface QualityCheck {
  id: string
  tenant_id: string | null
  product_id: string
  reference_type: 'goods_receipt' | 'delivery_note' | 'production' | 'manual'
  reference_id: string | null
  status: 'pending' | 'passed' | 'failed' | 'partial'
  checked_by: string | null
  checked_at: string | null
  notes: string | null
  created_at: string
}

export interface PickList {
  id: string
  tenant_id: string | null
  number: string
  reference_type: 'sales_order' | 'delivery_note' | 'production'
  reference_id: string | null
  warehouse_id: string | null
  status: 'draft' | 'in_progress' | 'completed' | 'cancelled'
  picked_by: string | null
  picked_at: string | null
  created_at: string
}

export interface PickListLine {
  id: string
  tenant_id: string | null
  pick_list_id: string
  product_id: string
  location_id: string | null
  quantity_to_pick: number
  quantity_picked: number
  barcode: string | null
  created_at: string
}

export interface SalesRepresentative {
  id: string
  tenant_id: string | null
  name: string
  email: string | null
  phone: string | null
  commission_rate: number
  territory: string | null
  active: boolean
  created_at: string
}

export interface Prospect {
  id: string
  tenant_id: string | null
  name: string
  email: string | null
  phone: string | null
  address: string | null
  city: string | null
  postal_code: string | null
  country: string | null
  contact_name: string | null
  source: string | null
  status: 'new' | 'contacted' | 'qualified' | 'converted' | 'lost'
  assigned_rep_id: string | null
  notes: string | null
  converted_customer_id: string | null
  created_at: string
  updated_at: string
}

export interface ProductSubstitute {
  id: string
  tenant_id: string | null
  product_id: string
  substitute_id: string
  priority: number
  created_at: string
}

export interface DeliverySchedule {
  id: string
  tenant_id: string | null
  customer_id: string | null
  product_id: string
  frequency: 'daily' | 'weekly' | 'monthly'
  quantity: number
  start_date: string
  end_date: string | null
  active: boolean
  created_at: string
}

export interface RecurringInvoiceTemplate {
  id: string
  tenant_id: string | null
  name: string
  customer_id: string | null
  frequency: 'weekly' | 'monthly' | 'quarterly' | 'yearly'
  next_date: string
  lines: any[]
  active: boolean
  created_at: string
}

export interface DocumentTemplate {
  id: string
  tenant_id: string | null
  name: string
  document_type: 'invoice' | 'quote' | 'delivery_note' | 'credit_note' | 'purchase_order' | 'statement'
  logo_url: string | null
  primary_color: string
  secondary_color: string
  template_config: Record<string, any>
  is_default: boolean
  created_at: string
}

// ============ Phase 3: Treasury ============

export interface FutureAccountingMovement {
  id: string
  tenant_id: string | null
  description: string
  account_code: string
  third_party_id: string | null
  amount: number
  movement_type: 'debit' | 'credit'
  expected_date: string
  source_type: 'invoice' | 'purchase_invoice' | 'payroll' | 'loan' | 'manual' | 'recurring' | null
  source_id: string | null
  incorporated: boolean
  incorporated_entry_id: string | null
  created_at: string
}

export interface TreasuryTransfer {
  id: string
  tenant_id: string | null
  number: string
  from_account_id: string
  to_account_id: string
  amount: number
  transfer_date: string
  value_date: string | null
  status: 'draft' | 'executed' | 'cancelled'
  journal_entry_id: string | null
  notes: string | null
  created_at: string
}

export interface CreditLine {
  id: string
  tenant_id: string | null
  bank_account_id: string | null
  name: string
  type: 'credit_line' | 'loan' | 'overdraft'
  limit_amount: number
  used_amount: number
  interest_rate: number
  start_date: string | null
  end_date: string | null
  monthly_payment: number
  status: 'active' | 'closed' | 'suspended'
  notes: string | null
  created_at: string
}

export interface Investment {
  id: string
  tenant_id: string | null
  name: string
  type: 'opcv' | 'bond' | 'stock' | 'term_deposit' | 'other'
  institution: string | null
  initial_amount: number
  current_value: number
  acquisition_date: string | null
  maturity_date: string | null
  interest_rate: number
  status: 'active' | 'matured' | 'sold'
  notes: string | null
  created_at: string
}

export interface ValueDateTracking {
  id: string
  tenant_id: string | null
  bank_account_id: string
  transaction_id: string | null
  operation_date: string
  value_date: string
  amount: number
  transaction_type: 'debit' | 'credit' | null
  notes: string | null
  created_at: string
}

export interface TreasuryRecurring {
  id: string
  tenant_id: string | null
  description: string
  bank_account_id: string | null
  amount: number
  type: 'incoming' | 'outgoing'
  frequency: 'weekly' | 'monthly' | 'quarterly' | 'yearly'
  next_date: string
  end_date: string | null
  active: boolean
  created_at: string
}

export interface ConsolidatedTreasury {
  id: string
  tenant_id: string | null
  consolidation_date: string
  total_assets: number
  total_liabilities: number
  net_position: number
  details: any[]
  created_at: string
}

// ============ Phase 4: Payroll & HR ============

export interface PayrollComponent {
  id: string
  tenant_id: string | null
  code: string
  name: string
  type: 'gross' | 'deduction' | 'contribution' | 'tax' | 'net' | 'benefit' | 'information'
  calculation_type: 'fixed' | 'percentage' | 'formula' | 'bracket'
  default_value: number
  rate_employer: number
  rate_employee: number
  ceiling_amount: number | null
  ceiling_basis: string | null
  tax_deductible: boolean
  display_order: number
  active: boolean
  created_at: string
}

export interface PayrollComponentRate {
  id: string
  tenant_id: string | null
  component_id: string
  legislation_pack: string | null
  rate_employer: number
  rate_employee: number
  ceiling_amount: number | null
  effective_date: string
  end_date: string | null
  created_at: string
}

export interface PayrollTemplate {
  id: string
  tenant_id: string | null
  name: string
  category: 'standard' | 'cadre' | 'non_cadre' | 'apprenti' | 'stagiaire' | 'interim'
  component_ids: any[]
  description: string | null
  active: boolean
  created_at: string
}

export interface SalaryAdvance {
  id: string
  tenant_id: string | null
  employee_id: string
  amount: number
  advance_date: string
  deduction_month: string | null
  status: 'pending' | 'deducted' | 'cancelled'
  notes: string | null
  created_at: string
}

export interface PayRecall {
  id: string
  tenant_id: string | null
  employee_id: string
  reference_period: string
  recall_amount: number
  reason: string | null
  status: 'pending' | 'processed' | 'cancelled'
  processed_pay_run_id: string | null
  created_at: string
}

export interface DsnDeclaration {
  id: string
  tenant_id: string | null
  period: string
  type: 'mensuelle' | 'arret' | 'reprise' | 'fin_contrat'
  status: 'draft' | 'generated' | 'transmitted' | 'accepted' | 'rejected'
  file_url: string | null
  generated_at: string | null
  transmitted_at: string | null
  response_code: string | null
  response_message: string | null
  created_at: string
}

export interface DpaeRecord {
  id: string
  tenant_id: string | null
  employee_id: string
  hire_date: string
  contract_type: string | null
  position: string | null
  status: 'pending' | 'transmitted' | 'accepted' | 'rejected'
  transmitted_at: string | null
  response_code: string | null
  created_at: string
}

export interface WorkHardship {
  id: string
  tenant_id: string | null
  employee_id: string
  exposure_type: string
  exposure_level: 'low' | 'medium' | 'high' | null
  start_date: string | null
  end_date: string | null
  points: number
  notes: string | null
  created_at: string
}

export interface CareerHistory {
  id: string
  tenant_id: string | null
  employee_id: string
  position: string | null
  department: string | null
  salary: number | null
  start_date: string
  end_date: string | null
  change_type: 'hire' | 'promotion' | 'transfer' | 'salary_change' | 'departure' | null
  notes: string | null
  created_at: string
}

export interface CpfAccount {
  id: string
  tenant_id: string | null
  employee_id: string
  balance_hours: number
  balance_amount: number
  history: any[]
  created_at: string
  updated_at: string
}

export interface PayrollArchive {
  id: string
  tenant_id: string | null
  employee_id: string | null
  period: string
  archive_type: 'payslip' | 'dsn' | 'dpae' | 'contract' | 'other'
  file_url: string
  file_encrypted: boolean
  retention_until: string | null
  created_at: string
}

export interface LegalWatch {
  id: string
  tenant_id: string | null
  title: string
  category: string | null
  source: string | null
  summary: string | null
  content_url: string | null
  published_date: string | null
  relevance: 'info' | 'important' | 'critical' | null
  read: boolean
  created_at: string
}

export interface EmployeeDocument {
  id: string
  tenant_id: string | null
  employee_id: string
  document_type: 'payslip' | 'contract' | 'dpae' | 'dsn' | 'certificate' | 'other'
  file_url: string
  file_name: string | null
  distributed_at: string | null
  acknowledged_at: string | null
  created_at: string
}

export interface ExpenseReport {
  id: string
  tenant_id: string | null
  employee_id: string
  number: string
  period: string | null
  total_amount: number
  total_vat: number
  status: 'draft' | 'submitted' | 'approved' | 'rejected' | 'reimbursed'
  submitted_at: string | null
  approved_by: string | null
  approved_at: string | null
  notes: string | null
  created_at: string
}

export interface ExpenseReportLine {
  id: string
  tenant_id: string | null
  expense_report_id: string
  date: string
  description: string
  category: string | null
  amount: number
  vat_rate: number
  vat_amount: number
  receipt_url: string | null
  created_at: string
}

export interface Interview {
  id: string
  tenant_id: string | null
  employee_id: string
  type: 'annual' | 'mid_year' | 'professional' | 'exit' | 'other'
  scheduled_date: string | null
  conducted_at: string | null
  conducted_by: string | null
  objectives: string | null
  feedback: string | null
  rating: number | null
  status: 'scheduled' | 'conducted' | 'cancelled'
  created_at: string
}

// ============ Phase 5: Fixed Assets ============

export interface AssetDepreciationPlan {
  id: string
  tenant_id: string | null
  asset_id: string
  plan_type: 'economic' | 'fiscal' | 'derogatory' | 'exceptional'
  depreciation_method: 'linear' | 'degressive' | 'variable' | 'manual'
  duration_months: number
  residual_value: number
  annual_rate: number | null
  start_date: string
  end_date: string | null
  accumulated_depreciation: number
  current_net_value: number
  active: boolean
  created_at: string
  updated_at: string
}

export interface AssetFamily {
  id: string
  tenant_id: string | null
  code: string
  name: string
  parent_id: string | null
  default_account: string | null
  default_depreciation_account: string | null
  default_duration_months: number | null
  default_method: 'linear' | 'degressive' | 'variable' | 'manual'
  depreciation_rate: number | null
  description: string | null
  created_at: string
}

export interface AssetRevaluation {
  id: string
  tenant_id: string | null
  asset_id: string
  revaluation_date: string
  old_value: number
  new_value: number
  difference: number
  reason: string | null
  journal_entry_id: string | null
  created_at: string
}

export interface AssetDocument {
  id: string
  tenant_id: string | null
  asset_id: string
  document_type: 'invoice' | 'contract' | 'photo' | 'other' | null
  file_url: string
  file_name: string | null
  description: string | null
  created_at: string
}

export interface AssetFreeField {
  id: string
  tenant_id: string | null
  asset_id: string
  field_key: string
  field_value: string | null
  field_type: 'text' | 'number' | 'date' | 'boolean' | 'select'
  field_category: 'free' | 'statistical'
  created_at: string
}

export interface AssetBatchDisposal {
  id: string
  tenant_id: string | null
  batch_number: string
  disposal_date: string
  total_assets: number
  total_proceeds: number
  total_gain_loss: number
  status: 'draft' | 'processed' | 'cancelled'
  journal_entry_id: string | null
  notes: string | null
  created_at: string
}

export interface AssetBatchDisposalLine {
  id: string
  tenant_id: string | null
  batch_id: string
  asset_id: string
  disposal_type: 'sale' | 'scrapping' | 'donation' | 'transfer' | null
  proceeds: number
  net_book_value: number
  gain_loss: number
  created_at: string
}

export interface AssetSplit {
  id: string
  tenant_id: string | null
  original_asset_id: string
  split_date: string
  reason: string | null
  created_at: string
}

export interface AssetSplitComponent {
  id: string
  tenant_id: string | null
  split_id: string
  new_asset_id: string
  allocated_value: number
  allocated_percentage: number
  created_at: string
}
