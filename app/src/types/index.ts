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
  created_at: string
  updated_at: string
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
