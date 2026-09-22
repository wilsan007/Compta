// All types use snake_case to match Supabase database columns exactly

export type InvoiceStatus = 'draft' | 'sent' | 'viewed' | 'paid' | 'overdue' | 'cancelled'
export type QuoteStatus = 'draft' | 'sent' | 'accepted' | 'rejected' | 'expired'
export type CreditStatus = 'draft' | 'validated' | 'applied'
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
  currency_code?: string
  active: boolean
  created_at: string
  updated_at: string
  parent_id?: string | null
  is_company?: boolean
  sales_rep_id?: string | null
  bank_account_id?: string | null
  price_list_id?: string | null
  email_settings?: Record<string, any> | null
  credit_used?: number
  credit_blocked?: boolean
  account_tiers?: string | null
  account_collectif?: string | null
}

export interface CustomerContact {
  id: string
  customer_id: string
  name: string
  role: 'billing' | 'delivery' | 'technical' | 'sales' | 'other' | null
  email: string | null
  phone: string | null
  mobile: string | null
  is_default: boolean
  active: boolean
  notes: string | null
  created_at: string
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
  currency_code?: string
  active: boolean
  created_at: string
  updated_at: string
  parent_id?: string | null
  is_company?: boolean
  sales_rep_id?: string | null
  bank_account_id?: string | null
  price_list_id?: string | null
  email_settings?: Record<string, any> | null
  account_tiers?: string | null
  account_collectif?: string | null
}

export interface SupplierContact {
  id: string
  supplier_id: string
  name: string
  role: 'billing' | 'delivery' | 'technical' | 'sales' | 'other' | null
  email: string | null
  phone: string | null
  mobile: string | null
  is_default: boolean
  active: boolean
  notes: string | null
  created_at: string
}

export interface PurchaseRequest {
  id: string
  number: string
  requester: string | null
  department: string | null
  status: 'draft' | 'submitted' | 'approved' | 'rejected' | 'converted'
  priority: 'low' | 'normal' | 'high' | 'urgent'
  expected_date: string | null
  notes: string | null
  approved_by: string | null
  approved_at: string | null
  created_at: string
  purchase_request_lines?: PurchaseRequestLine[]
}

export interface PurchaseRequestLine {
  id: string
  purchase_request_id: string
  product_id: string | null
  description: string
  quantity: number
  unit: string | null
  estimated_price: number | null
  preferred_supplier_id: string | null
  notes: string | null
}

export interface SupplierPriceList {
  id: string
  supplier_id: string
  name: string
  valid_from: string
  valid_to: string | null
  currency_code: string
  min_quantity: number
  discount_percent: number
  active: boolean
  supplier_price_list_lines?: SupplierPriceListLine[]
}

export interface SupplierPriceListLine {
  id: string
  price_list_id: string
  product_id: string
  supplier_ref: string | null
  unit_price: number
  min_quantity: number
  discount_percent: number
  lead_time_days: number | null
}

export interface SupplierDeliverySchedule {
  id: string
  supplier_id: string
  product_id: string
  warehouse_id: string | null
  frequency: 'weekly' | 'biweekly' | 'monthly'
  monday_qty: number
  tuesday_qty: number
  wednesday_qty: number
  thursday_qty: number
  friday_qty: number
  saturday_qty: number
  sunday_qty: number
  start_date: string
  end_date: string | null
  active: boolean
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
  delivery_note_line_id?: string | null
  sales_order_line_id?: string | null
  vat_code?: string | null
  vat_amount?: number
  /** Ligne de déduction d'acompte (montant négatif) : facture d'acompte déduite */
  advance_invoice_id?: string | null
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
  fiscal_position_id?: string | null
  payment_state?: 'not_paid' | 'in_payment' | 'paid' | 'partial'
  currency_code?: string
  exchange_rate?: number
  amount_untaxed_currency?: number | null
  amount_tax_currency?: number | null
  amount_total_currency?: number | null
  delivery_note_id?: string | null
  sales_order_id?: string | null
  quote_id?: string | null
  is_advance_invoice?: boolean
  advance_amount?: number | null
  invoice_type?: 'standard' | 'advance' | 'balance' | 'proforma'
  parent_invoice_id?: string | null
  validation_status?: 'draft' | 'pending' | 'validated' | 'rejected' | null
  /** Écriture de vente passée à la validation */
  transferred_entry_id?: string | null
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
  transformed_to_order_id?: string | null
  transformation_status?: 'pending' | 'transformed' | 'partial'
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
  currency_code?: string
  exchange_rate?: number
  amount_untaxed_currency?: number | null
  amount_tax_currency?: number | null
  amount_total_currency?: number | null
  source_invoice_id?: string | null
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
  vat_code?: string | null
  vat_amount?: number
}

export interface PurchaseInvoice {
  id: string
  number: string
  supplier_reference?: string | null
  approval_status?: 'pending' | 'approved' | 'rejected'
  transferred_entry_id?: string | null
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
  fiscal_position_id?: string | null
  payment_state?: 'not_paid' | 'in_payment' | 'paid' | 'partial'
  currency_code?: string
  exchange_rate?: number
  amount_untaxed_currency?: number | null
  amount_tax_currency?: number | null
  amount_total_currency?: number | null
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
  statement_balance?: number | null
  statement_balance_date?: string | null
  calculated_balance?: number | null
  reconciliation_diff?: number | null
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
  matched_line_id: string | null
  invoice_id: string | null
  purchase_invoice_id: string | null
  created_at: string
  original_currency?: string | null
  original_amount?: number | null
  exchange_rate?: number | null
  exchange_gain_loss?: number | null
  source?: string | null
}

export interface BankConnection {
  id: string
  tenant_id: string | null
  provider: string
  provider_connection_id: string | null
  bank_account_id: string | null
  status: string
  last_sync_at: string | null
  sync_frequency: string
  next_sync_at: string | null
  error_message: string | null
  metadata: Record<string, any> | null
  created_at: string
}

export interface PartnerBankAccount {
  id: string
  tenant_id: string | null
  partner_type: 'customer' | 'supplier'
  partner_id: string
  account_number: string
  bank_name: string | null
  bic: string | null
  bank_code: string | null
  sort_code: string | null
  account_key: string | null
  currency_code: string
  is_default: boolean
  active: boolean
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
  barcode?: string | null
  weight?: number | null
  photo_url?: string | null
  supplier_ref?: string | null
  criticality_level?: 'normal' | 'critical' | 'essential' | null
  cost_price?: number | null
  sale_account_code?: string | null
  purchase_account_code?: string | null
  stock_account_code?: string | null
  category_id?: string | null
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
  vat_code?: string | null
  vat_amount?: number | null
  echeance_date?: string | null
  quantity?: number | null
  marking_code?: string | null
  marked_bap?: boolean
  marked_bap_date?: string | null
  analytic_distribution?: Record<string, Record<string, number>> | null
  amount_residual?: number | null
  tax_tag_ids?: string[] | null
  product_id?: string | null
  product_uom?: string | null
}

export interface AnalyticDistributionLine {
  id: string
  tenant_id: string | null
  journal_line_id: string | null
  plan_id: string | null
  section_id: string | null
  percentage: number
  amount: number | null
  created_at: string
}

export interface JournalEntry {
  ifrs_mode?: boolean
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
  /** AUD-C08 — renseigné par le serveur depuis la date */
  fiscal_year_id?: string | null
  /** AUD-C11 — numéro définitif attribué à la validation (EcritureNum du FEC) */
  posting_number?: string | null
  posting_seq?: number | null
  piece_number?: string | null
  invoice_ref?: string | null
  entry_template_id?: string | null
  status_detail?: 'open' | 'printed' | 'closed' | null
  validated_by?: string | null
  validated_at?: string | null
  currency_code?: string
  functional_currency?: string
  exchange_rate?: number
  exchange_rate_date?: string | null
}

export type ChartAccountType =
  | 'asset_receivable'
  | 'asset_cash'
  | 'asset_current'
  | 'asset_non_current'
  | 'asset_prepayments'
  | 'asset_fixed'
  | 'liability_payable'
  | 'liability_credit_card'
  | 'liability_current'
  | 'liability_non_current'
  | 'equity'
  | 'equity_unaffected'
  | 'income'
  | 'income_other'
  | 'expense'
  | 'expense_other'
  | 'expense_depreciation'
  | 'expense_direct_cost'
  | 'off_balance'

export interface ChartAccount {
  id: string
  code: string
  name: string
  type: 'asset' | 'liability' | 'equity' | 'income' | 'expense'
  account_type?: ChartAccountType
  balance: number
  vat_rate: string
  description: string
  parent_id: string | null
  created_at: string
  racine?: string | null
  classe?: string | null
  nature?: string | null
  code_taxe_default?: string | null
  saisie_analytic?: boolean
  saisie_echeance?: boolean
  saisie_tiers?: boolean
  debit_n1?: number
  credit_n1?: number
  current_debit?: number
  current_credit?: number
  current_balance?: number
  currency_code?: string | null
  reconcile?: boolean
  deprecated?: boolean
}

export interface User {
  id: string
  auth_id: string | null
  name: string
  email: string
  role: 'admin' | 'accountant' | 'manager' | 'viewer' | 'auditor'
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
  manager_id: string | null
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
  vat_method?: string | null
  accounting_standard?: string | null
  gdpr_enabled?: boolean
  gdpr_retention_years?: number
  gdpr_anonymize_after?: boolean
  saisie_negative?: boolean
  multi_currency?: boolean
  show_quantities?: boolean
  vat_regime?: string | null
  vat_periodicity?: string | null
  iban?: string | null
  bic?: string | null
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
  account_collectee?: string | null
  account_deductible?: string | null
  type?: string | null
  mode?: string | null
  tenant_id?: string | null
  amount_type?: 'percent' | 'fixed' | 'group' | 'division'
  type_tax_use?: 'sale' | 'purchase' | 'none'
  sequence?: number
  parent_tax_id?: string | null
  tax_exigibility?: 'on_invoice' | 'on_payment'
  cash_basis_transition_account?: string | null
  price_include?: boolean
  include_base_amount?: boolean
  is_base_affected?: boolean
  analytic?: boolean
  fixed_amount?: number | null
}

export interface TaxGroup {
  id: string
  tenant_id: string | null
  name: string
  country_code?: string | null
  created_at: string
}

export interface TaxRepartitionLine {
  id: string
  tenant_id: string | null
  tax_id: string
  document_type: 'invoice' | 'refund'
  repartition_type: 'base' | 'tax'
  factor: number
  account_code?: string | null
  tag_ids?: string[] | null
  created_at: string
}

export interface TaxCashBasisEntry {
  id: string
  tenant_id: string | null
  tax_id: string | null
  payment_id: string | null
  journal_entry_id: string | null
  base_amount: number
  tax_amount: number
  transition_date: string | null
  status: 'pending' | 'posted'
  created_at: string
}

export interface FiscalPosition {
  id: string
  tenant_id: string | null
  name: string
  country_code?: string | null
  country_group_id?: string | null
  zip_from?: string | null
  zip_to?: string | null
  auto_apply: boolean
  active: boolean
  created_at: string
}

export interface FiscalPositionMapping {
  id: string
  tenant_id: string | null
  fiscal_position_id: string
  source_tax_id?: string | null
  target_tax_id?: string | null
  source_account_code?: string | null
  target_account_code?: string | null
  created_at: string
}

export interface AccountTag {
  id: string
  tenant_id: string | null
  name: string
  applicability: string
  color?: string | null
  country_code?: string | null
  created_at: string
}

export interface AccountTagMapping {
  id: string
  tenant_id: string | null
  tag_id: string
  entity_type: string
  entity_id: string
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
  status: 'draft' | 'validated' | 'applied'
  supplier_reference?: string | null
  subtotal: number
  vat_total: number
  total: number
  reason: string
  purchase_invoice_id: string | null
  created_at: string
  purchase_credit_lines?: PurchaseCreditNoteLine[]
  currency_code?: string
  exchange_rate?: number
  amount_untaxed_currency?: number | null
  amount_tax_currency?: number | null
  amount_total_currency?: number | null
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
  account_asset_code?: string | null
  account_depreciation_code?: string | null
  account_expense_depreciation_code?: string | null
  journal_id?: string | null
  partner_id?: string | null
  currency_code?: string
  derogatory_depreciation?: boolean
  subvention_amount?: number | null
  subvention_account?: string | null
}

// ============ Sprint 6: Partner Contacts (#62) ============
export interface PartnerContact {
  id: string
  tenant_id: string | null
  partner_type: 'customer' | 'supplier'
  partner_id: string
  contact_type: 'primary' | 'invoice' | 'delivery' | 'other'
  name: string
  email: string | null
  phone: string | null
  mobile: string | null
  function: string | null
  address: string | null
  postal_code: string | null
  city: string | null
  country: string | null
  is_default: boolean
  active: boolean
  created_at: string
}

// ============ Sprint 6: Partner Categories (#64) ============
export interface PartnerCategory {
  id: string
  tenant_id: string | null
  name: string
  color: string | null
  parent_id: string | null
  created_at: string
}

// ============ Sprint 6: Partner Bank Accounts (#80) ============
export interface PartnerBankAccount {
  id: string
  tenant_id: string | null
  partner_type: 'customer' | 'supplier'
  partner_id: string
  account_number: string
  bank_name: string | null
  bic: string | null
  bank_code: string | null
  sort_code: string | null
  account_key: string | null
  currency_code: string
  is_default: boolean
  active: boolean
  created_at: string
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
  employee_number?: string | null
  social_security_number?: string | null
  birth_date?: string | null
  /** G16 : 'F' | 'M' | null. DSN et indicateurs d'égalité de la BDES uniquement. */
  gender?: 'F' | 'M' | null
  address?: string | null
  city?: string | null
  postal_code?: string | null
  contract_type?: 'CDI' | 'CDD' | 'Apprentissage' | 'Stage' | 'Interim' | null
  contract_end_date?: string | null
  withholding_tax_rate?: number | null
  withholding_rate_source?: string | null
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
  // R-04 : statuts réellement utilisés (contrainte élargie par la 212)
  status: 'draft' | 'processing' | 'approved' | 'closed' | 'paid' | 'cancelled'
  gross_total: number
  tax_total: number
  net_total: number
  employer_contributions_total?: number
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
  last_rate_date?: string | null
  decimal_places?: number
  rounding?: number
  active?: boolean
  position?: 'before' | 'after'
}

export interface ExchangeRate {
  id: string
  tenant_id: string | null
  base_currency: string
  quote_currency: string
  rate: number
  rate_date: string
  source: string
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
  numbering_mode?: string | null
  account_attente?: string | null
  is_analytic?: boolean
  analytic_plan_id?: string | null
  currency_code?: string
  sequence?: number
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
  /** Résultat déterminé à la clôture (bénéfice > 0, perte < 0) ; null avant clôture */
  closing_result?: number | null
  /** Décision n° 3 : l'affectation est exigée avant de clôturer l'exercice suivant */
  result_allocated_at?: string | null
  result_allocation_entry_id?: string | null
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
export type TemplateAmountType = 'input' | 'fixed' | 'percent' | 'balance' | 'calc_vat'

export interface TemplateLine {
  account_general: string
  account_tiers: string
  label: string
  debit_pct: number
  credit_pct: number
  amount_type: TemplateAmountType
  fixed_amount: number | null
  vat_code: string | null
  analytic_section: string | null
}

export interface EntryTemplate {
  id: string
  name: string
  journal_code: string | null
  description: string | null
  template_lines: TemplateLine[] | null
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
  payment_term_id?: string | null
  default_bank_account_id?: string | null
  credit_limit?: number
  siret?: string | null
  vat_intra?: string | null
  iban?: string | null
  bic?: string | null
  address?: string | null
  postal_code?: string | null
  city?: string | null
  country?: string | null
  bank_code?: string | null
  branch_code?: string | null
  bank_account_number?: string | null
  bank_key?: string | null
  echeance_model?: string | null
  payment_condition?: string | null
  payment_mode?: string | null
  encours_autorise?: number | null
  relance_niveau?: string | null
  relance_model?: string | null
  delai_paiement?: string | null
  escompte?: number | null
  contact_name?: string | null
  zone_geo?: string | null
  categorie?: string | null
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
  plan_id?: string | null
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

// ============ Sprint A: Commercial Transformations ============

export interface DocumentCharge {
  id: string
  tenant_id: string | null
  document_type: 'quote' | 'sales_order' | 'delivery_note' | 'invoice' | 'credit_note' | 'purchase_order' | 'purchase_invoice'
  document_id: string
  charge_type: 'shipping' | 'handling' | 'insurance' | 'packaging' | 'other'
  label: string
  amount: number
  vat_rate: number
  vat_amount: number
  total_amount: number
  supplier_id: string | null
  created_at: string
}

export interface DocumentTransformation {
  id: string
  tenant_id: string | null
  source_type: 'quote' | 'sales_order' | 'delivery_note' | 'invoice'
  source_id: string
  target_type: 'sales_order' | 'delivery_note' | 'invoice' | 'credit_note'
  target_id: string
  transformation_type: 'full' | 'partial'
  transformed_by: string | null
  transformed_at: string
  notes: string | null
}

// ============ Sprint D: Catalog Extended ============

export interface ProductGrid {
  id: string
  tenant_id: string | null
  product_id: string
  name: string
  axis: 'size' | 'color' | 'material' | 'style'
  values: string[]
  active: boolean
  created_at: string
}

export interface ProductGridCombination {
  id: string
  tenant_id: string | null
  product_id: string
  combination: Record<string, string>
  sku: string | null
  barcode: string | null
  price_override: number | null
  stock_quantity: number
  active: boolean
  created_at: string
}

export interface ProductPackaging {
  id: string
  tenant_id: string | null
  product_id: string
  name: string
  quantity: number
  unit: 'box' | 'pallet' | 'pack' | 'case' | null
  barcode: string | null
  weight: number | null
  active: boolean
  created_at: string
}

export interface ProductLink {
  id: string
  tenant_id: string | null
  product_id: string
  linked_product_id: string
  link_type: 'accessory' | 'complement' | 'substitute' | 'bundle' | 'cross_sell'
  quantity: number
  created_at: string
}

export interface Promotion {
  id: string
  tenant_id: string | null
  name: string
  description: string | null
  promo_type: 'percentage' | 'fixed_amount' | 'buy_x_get_y' | 'free_shipping'
  value: number | null
  product_id: string | null
  category: string | null
  customer_id: string | null
  start_date: string
  end_date: string
  min_quantity: number
  free_product_id: string | null
  free_product_qty: number
  active: boolean
  created_at: string
}

// ============ Sprint E: Stock Advanced ============

export interface WarehouseUser {
  id: string
  tenant_id: string | null
  warehouse_id: string
  user_email: string
  role: 'manager' | 'operator' | 'viewer'
  active: boolean
  created_at: string
}

export interface StockAlert {
  id: string
  tenant_id: string | null
  product_id: string
  warehouse_id: string | null
  alert_type: 'low_stock' | 'out_of_stock' | 'overstock' | 'expiry'
  threshold: number | null
  current_value: number | null
  status: 'active' | 'acknowledged' | 'resolved'
  triggered_at: string
  resolved_at: string | null
  created_at: string
}

// ============ Sprint F: CRM Sales ============

export interface CrmOpportunity {
  id: string
  tenant_id: string | null
  number: string
  customer_id: string | null
  prospect_id: string | null
  title: string
  description: string | null
  stage: 'new' | 'qualified' | 'proposition' | 'negotiation' | 'won' | 'lost'
  probability: number
  expected_amount: number
  expected_close_date: string | null
  actual_amount: number | null
  actual_close_date: string | null
  sales_rep_id: string | null
  source: string | null
  lost_reason: string | null
  tags: string[] | null
  created_at: string
  updated_at: string
}

export interface CrmActivity {
  id: string
  tenant_id: string | null
  opportunity_id: string | null
  customer_id: string | null
  activity_type: 'call' | 'meeting' | 'email' | 'task' | 'visit'
  subject: string
  description: string | null
  scheduled_date: string | null
  completed_date: string | null
  duration_minutes: number | null
  status: 'planned' | 'done' | 'cancelled' | 'postponed'
  assigned_to: string | null
  created_at: string
}

export interface CrmCampaign {
  id: string
  tenant_id: string | null
  name: string
  description: string | null
  campaign_type: 'email' | 'sms' | 'social' | 'event' | 'print'
  status: 'draft' | 'scheduled' | 'running' | 'completed' | 'cancelled'
  start_date: string | null
  end_date: string | null
  budget: number
  actual_cost: number
  target_audience: string | null
  segment_criteria: Record<string, any> | null
  sent_count: number
  open_count: number
  click_count: number
  response_count: number
  conversion_count: number
  created_at: string
}

export interface CrmCampaignRecipient {
  id: string
  tenant_id: string | null
  campaign_id: string
  customer_id: string | null
  prospect_id: string | null
  email: string | null
  phone: string | null
  sent: boolean
  sent_at: string | null
  opened: boolean
  opened_at: string | null
  clicked: boolean
  responded: boolean
  created_at: string
}

export interface CrmTerritory {
  id: string
  tenant_id: string | null
  name: string
  code: string | null
  parent_id: string | null
  sales_rep_id: string | null
  regions: string[] | null
  active: boolean
  created_at: string
}

export interface CrmForecast {
  id: string
  tenant_id: string | null
  period: string
  sales_rep_id: string | null
  target_amount: number
  committed_amount: number
  best_case_amount: number
  pipeline_amount: number
  closed_amount: number
  notes: string | null
  created_at: string
}

// ============ Sprint G: CRM Service ============

export interface ServiceTicket {
  id: string
  tenant_id: string | null
  number: string
  customer_id: string
  contact_id: string | null
  subject: string
  description: string | null
  category: 'technical' | 'billing' | 'delivery' | 'product' | 'other' | null
  priority: 'low' | 'normal' | 'high' | 'urgent'
  status: 'open' | 'in_progress' | 'waiting_customer' | 'resolved' | 'closed'
  assigned_to: string | null
  sla_due_date: string | null
  first_response_at: string | null
  resolved_at: string | null
  closed_at: string | null
  satisfaction_rating: number | null
  satisfaction_comment: string | null
  tags: string[] | null
  created_at: string
  updated_at: string
}

export interface ServiceTicketMessage {
  id: string
  tenant_id: string | null
  ticket_id: string
  author: string
  author_type: 'agent' | 'customer' | 'system'
  message: string
  attachments: { filename: string; url: string; size: number }[] | null
  is_internal: boolean
  created_at: string
}

export interface ServiceContract {
  id: string
  tenant_id: string | null
  number: string
  customer_id: string
  name: string
  contract_type: 'support' | 'maintenance' | 'warranty' | 'sla' | null
  start_date: string
  end_date: string | null
  status: 'active' | 'expired' | 'terminated' | 'draft'
  sla_response_hours: number | null
  sla_resolution_hours: number | null
  coverage: 'business_hours' | '24_7' | null
  max_tickets: number | null
  used_tickets: number
  amount: number | null
  notes: string | null
  created_at: string
}

export interface KnowledgeBaseArticle {
  id: string
  tenant_id: string | null
  title: string
  category: 'faq' | 'guide' | 'troubleshooting' | 'policy' | null
  content: string
  tags: string[] | null
  author: string | null
  status: 'draft' | 'published' | 'archived'
  views: number
  helpful_count: number
  not_helpful_count: number
  is_public: boolean
  created_at: string
  updated_at: string
}

// ============ Sprint J: Pilotage ============

export interface SavedFilter {
  id: string
  tenant_id: string | null
  user_email: string
  page_name: string
  filter_name: string
  filter_criteria: Record<string, any>
  is_default: boolean
  created_at: string
}

// ============ Sprint H: POS ============

export interface PosTerminal {
  id: string
  tenant_id: string | null
  name: string
  warehouse_id: string | null
  location: string | null
  active: boolean
  created_at: string
}

export interface PosSession {
  id: string
  tenant_id: string | null
  terminal_id: string
  user_email: string
  opening_amount: number
  closing_amount: number | null
  expected_amount: number | null
  difference: number | null
  status: 'open' | 'closed'
  opened_at: string
  closed_at: string | null
  notes: string | null
}

// ============ Sprint I: Dématérialisation ============

export interface ElectronicSignature {
  id: string
  tenant_id: string | null
  document_type: string
  document_id: string
  signer_name: string
  signer_email: string | null
  signature_hash: string | null
  signature_data: string | null
  ip_address: string | null
  signed_at: string
  created_at: string
}

export interface DocumentShare {
  id: string
  tenant_id: string | null
  document_type: string
  document_id: string
  shared_with_email: string
  share_token: string
  share_url: string | null
  expires_at: string | null
  viewed: boolean
  viewed_at: string | null
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
  quote_id?: string | null
  fully_delivered?: boolean
  delivery_status?: 'pending' | 'partial' | 'delivered'
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
  delivered_quantity?: number
  remaining_quantity?: number
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
  fully_invoiced?: boolean
  invoice_status?: 'pending' | 'partial' | 'invoiced'
}

export interface DeliveryNoteLine {
  id: string
  delivery_note_id: string
  product_id: string | null
  description: string
  quantity: number
  invoiced_quantity?: number
  remaining_quantity?: number
  sales_order_line_id?: string | null
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
  currency_code?: string
  exchange_rate?: number
  amount_currency?: number | null
  exchange_gain_loss?: number
  journal_entry_id?: string | null
  journal_posted?: boolean
  bank_transaction_id?: string | null
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
  currency_code?: string
  exchange_rate?: number
  amount_currency?: number | null
  exchange_gain_loss?: number
  journal_entry_id?: string | null
  journal_posted?: boolean
  bank_transaction_id?: string | null
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
  document_type: 'payslip' | 'contract' | 'dpae' | 'dsn' | 'certificate' | 'work_certificate' | 'settlement_receipt' | 'pole_emploi_attestation' | 'medical_cert' | 'other'
  title: string
  file_url: string
  file_name: string | null
  file_size: number | null
  mime_type: string | null
  period: string | null
  uploaded_by: string | null
  visible_to_employee: boolean
  requires_acknowledgment: boolean
  acknowledged: boolean
  acknowledged_at: string | null
  distributed_at: string | null
  e_signed: boolean
  e_signed_at: string | null
  e_signature_hash: string | null
  archived: boolean
  archive_date: string | null
  retention_years: number
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
  total_ttc: number
  status: 'draft' | 'submitted' | 'approved' | 'rejected' | 'reimbursed'
  submitted_at: string | null
  approved_by: string | null
  approved_at: string | null
  manager_id: string | null
  manager_comment: string | null
  reimbursement_date: string | null
  notes: string | null
  created_at: string
}

export interface ExpenseReportLine {
  id: string
  tenant_id: string | null
  expense_report_id: string
  category_id: string | null
  date: string
  description: string
  category: string | null
  amount: number
  amount_ht: number
  amount_ttc: number
  vat_rate: number
  vat_amount: number
  receipt_url: string | null
  ocr_data: any
  ocr_processed: boolean
  ceiling_exceeded: boolean
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

// ============ Phase 6: Accounting Features ============

export interface AutoLabelRule {
  id: string
  tenant_id: string | null
  name: string
  description: string | null
  journal_code: string | null
  account_code: string | null
  account_prefix: string | null
  label_pattern: string
  priority: number
  active: boolean
  created_at: string
  updated_at: string
}

export interface ExtourneLog {
  id: string
  tenant_id: string | null
  original_entry_id: string
  extourne_entry_id: string
  extourne_date: string
  reason: string | null
  journal_code: string | null
  total_debit: number
  total_credit: number
  status: string
  created_at: string
}

export interface CarryForwardLog {
  id: string
  tenant_id: string | null
  source_fiscal_year_id: string
  target_fiscal_year_id: string
  carry_forward_date: string
  total_debit: number
  total_credit: number
  entry_count: number
  status: string
  journal_entry_id: string | null
  created_at: string
}

export interface LettrageDifference {
  id: string
  tenant_id: string | null
  third_party_code: string
  lettrage_code: string
  line_id_1: string
  line_id_2: string
  debit_amount: number
  credit_amount: number
  difference: number
  difference_account: string | null
  generated_entry_id: string | null
  status: string
  created_at: string
}

export interface AccountingControlRun {
  id: string
  tenant_id: string | null
  control_type: string
  fiscal_year_id: string | null
  period_id: string | null
  run_date: string
  status: string
  total_checks: number
  errors_found: number
  warnings_found: number
  details: any[]
  created_at: string
}

export interface CashControlSession {
  id: string
  tenant_id: string | null
  session_number: string
  journal_code: string
  session_date: string
  theoretical_balance: number
  counted_balance: number
  difference: number
  status: string
  counted_by: string | null
  validated_by: string | null
  validated_at: string | null
  notes: string | null
  details: any[]
  created_at: string
  updated_at: string
}

export interface FECAttestation {
  id: string
  tenant_id: string | null
  fiscal_year_id: string
  attestation_number: string
  attestation_date: string
  fec_type: string
  entry_count: number
  total_debit: number
  total_credit: number
  file_name: string | null
  file_content: string | null
  status: string
  generated_by: string | null
  created_at: string
}

export interface TierRIB {
  id: string
  tenant_id: string | null
  third_party_account_id: string
  rib_label: string
  iban: string
  bic: string | null
  bank_name: string | null
  bank_code: string | null
  branch_code: string | null
  account_number: string | null
  key: string | null
  is_default: boolean
  active: boolean
  created_at: string
  updated_at: string
}

export interface IFRSAdjustment {
  id: string
  tenant_id: string | null
  fiscal_year_id: string | null
  adjustment_type: string
  account_code: string
  counter_account_code: string
  description: string
  amount: number
  adjustment_date: string
  ifrs_standard: string | null
  journal_entry_id: string | null
  status: string
  created_at: string
  updated_at: string
}

export interface TaxPayment {
  id: string
  tenant_id: string | null
  payment_number: string
  tax_type: string
  period_label: string
  period_start: string
  period_end: string
  amount: number
  payment_date: string
  payment_method: string
  bank_account_id: string | null
  status: string
  confirmation_number: string | null
  journal_entry_id: string | null
  created_at: string
  updated_at: string
}

export interface CustomReportTemplate {
  id: string
  tenant_id: string | null
  name: string
  description: string | null
  report_type: string
  category: string
  columns: any[]
  filters: Record<string, any>
  group_by: string | null
  sort_by: string | null
  sort_order: string
  page_orientation: string
  page_size: string
  header_text: string | null
  footer_text: string | null
  show_logo: boolean
  show_date: boolean
  show_page_numbers: boolean
  active: boolean
  created_at: string
  updated_at: string
}

export interface DeferredPrintingJob {
  id: string
  tenant_id: string | null
  job_name: string
  report_type: string
  parameters: Record<string, any>
  scheduled_date: string
  status: string
  output_format: string
  output_data: string | null
  generated_at: string | null
  generated_by: string | null
  error_message: string | null
  created_at: string
}

export interface JournalAccessRight {
  id: string
  tenant_id: string | null
  user_id: string
  journal_code: string
  can_view: boolean
  can_create: boolean
  can_edit: boolean
  can_delete: boolean
  can_close: boolean
  created_at: string
  updated_at: string
}

export interface VATOnCollection {
  id: string
  tenant_id: string | null
  fiscal_year_id: string | null
  period_label: string
  period_start: string
  period_end: string
  vat_base: number
  vat_rate: number
  vat_amount: number
  collected_amount: number
  uncollected_amount: number
  vat_collected: number
  vat_uncollected: number
  status: string
  journal_entry_id: string | null
  created_at: string
  updated_at: string
}

// ============ Phase 7A: Payment Terms & Marking Types ============

export interface PaymentTerm {
  id: string
  tenant_id: string | null
  code: string
  name: string
  type: 'fixed' | 'end_of_month' | 'split'
  days_1: number
  days_2: number | null
  pct_1: number
  pct_2: number | null
  end_of_month: boolean
  description: string | null
  active: boolean
  created_at: string
  updated_at: string
}

export interface MarkingType {
  id: string
  tenant_id: string | null
  code: string
  label: string
  color: string
  active: boolean
  created_at: string
  updated_at: string
}

export interface BatchEntrySession {
  id: string
  tenant_id: string | null
  session_name: string
  journal_code: string
  session_date: string
  entry_count: number
  total_debit: number
  total_credit: number
  status: string
  validated_at: string | null
  validated_by: string | null
  created_at: string
  updated_at: string
}

// ============ Phase 7B: Reminder Levels, Promises, Disputes ============

export interface ReminderLevel {
  id: string
  tenant_id: string | null
  level: number
  name: string
  template: string | null
  days_after_due: number
  penalty_rate: number
  active: boolean
  created_at: string
  updated_at: string
}

export interface PaymentPromise {
  id: string
  tenant_id: string | null
  third_party_code: string
  amount: number
  promised_date: string
  reminder_level: number
  status: 'pending' | 'kept' | 'broken' | 'cancelled'
  notes: string | null
  created_by: string | null
  created_at: string
  updated_at: string
}

export interface Dispute {
  id: string
  tenant_id: string | null
  third_party_code: string
  invoice_ref: string | null
  amount: number
  reason: string
  status: 'open' | 'under_review' | 'resolved' | 'rejected'
  resolution: string | null
  opened_date: string
  resolved_date: string | null
  created_by: string | null
  created_at: string
  updated_at: string
}

export interface JustificatifSolde {
  id: string
  tenant_id: string | null
  account_code: string
  third_party_code: string | null
  fiscal_period_id: string | null
  opening_balance: number
  total_debit: number
  total_credit: number
  closing_balance: number
  generated_at: string
  generated_by: string | null
}

export interface EtatRapprochement {
  id: string
  tenant_id: string | null
  bank_account_id: string | null
  account_code: string
  period_start: string
  period_end: string
  bank_balance: number
  book_balance: number
  difference: number
  reconciled_items: number
  unreconciled_items: number
  generated_at: string
  generated_by: string | null
}

// ============ Phase 7C: Revision Cycles, Reporting Plans, Stat Fields, Dashboard Widgets, Fusion, Compaction, RGPD ============

export interface RevisionCycle {
  id: string
  tenant_id: string | null
  name: string
  frequency: 'monthly' | 'quarterly' | 'annual' | 'custom'
  start_month: number
  account_class: string | null
  active: boolean
  last_run: string | null
  next_run: string | null
  created_at: string
  updated_at: string
}

export interface ReportingPlan {
  id: string
  tenant_id: string | null
  name: string
  report_type: 'balance' | 'pnl' | 'cashflow' | 'vat' | 'custom'
  schedule: 'manual' | 'monthly' | 'quarterly' | 'annual'
  format: 'pdf' | 'excel' | 'csv'
  recipients: string | null
  parameters: Record<string, any>
  last_generated: string | null
  active: boolean
  created_at: string
  updated_at: string
}

export interface StatField {
  id: string
  tenant_id: string | null
  entity_type: 'customer' | 'supplier' | 'product' | 'account' | 'journal'
  entity_id: string
  field_name: string
  field_value: string | null
  field_type: 'text' | 'number' | 'date' | 'boolean'
  created_at: string
  updated_at: string
}

export interface DashboardWidget {
  id: string
  tenant_id: string | null
  user_id: string
  widget_type: 'chart' | 'table' | 'kpi' | 'alert' | 'custom'
  title: string
  config: Record<string, any>
  position: number
  size: 'small' | 'medium' | 'large' | 'full'
  visible: boolean
  created_at: string
  updated_at: string
}

export interface FusionLog {
  id: string
  tenant_id: string | null
  source_account_code: string
  target_account_code: string
  lines_moved: number
  fused_by: string | null
  fused_at: string
}

export interface CompactionLog {
  id: string
  tenant_id: string | null
  fiscal_year_id: string | null
  entries_compacted: number
  lines_compacted: number
  status: 'pending' | 'in_progress' | 'completed' | 'failed'
  compacted_by: string | null
  compacted_at: string
  details: Record<string, any> | null
}

export interface RGPDRequest {
  id: string
  tenant_id: string | null
  request_type: 'export' | 'delete' | 'anonymize' | 'access'
  entity_type: 'customer' | 'supplier' | 'employee' | 'all'
  entity_id: string | null
  status: 'pending' | 'processing' | 'completed' | 'rejected'
  requested_by: string | null
  processed_by: string | null
  requested_at: string
  processed_at: string | null
  notes: string | null
}

export interface GridTemplate {
  id: string
  tenant_id: string | null
  code: string
  name: string
  description: string | null
  journal_code: string | null
  columns_config: any[]
  default_account: string | null
  is_active: boolean
  created_at: string
  updated_at: string
}

export interface PaymentTemplateCompta {
  id: string
  tenant_id: string | null
  code: string
  name: string
  description: string | null
  payment_method: string
  day_count: number
  end_of_month: boolean
  is_active: boolean
  created_at: string
  updated_at: string
}

export interface StandardLabel {
  id: string
  tenant_id: string | null
  code: string
  label: string
  category: string
  is_active: boolean
  created_at: string
  updated_at: string
}

export interface AnalyticJournalCode {
  id: string
  tenant_id: string | null
  code: string
  name: string
  description: string | null
  type: string
  is_active: boolean
  created_at: string
  updated_at: string
}

export interface ReimputationLog {
  id: string
  tenant_id: string | null
  original_entry_id: string | null
  original_line_id: string | null
  reimputed_entry_id: string | null
  reimputed_line_id: string | null
  from_account: string
  to_account: string
  amount: number
  reason: string | null
  status: string
  created_at: string
}

export interface Bank {
  id: string
  name: string
  swift_code: string | null
  country: string | null
  logo_url: string | null
  is_active: boolean
  created_at: string
}

export interface BankStatementTemplate {
  id: string
  tenant_id: string | null
  bank_id: string | null
  bank_name: string
  account_number_pattern: string | null
  date_pattern: string
  amount_pattern: string
  description_pattern: string | null
  reference_pattern: string | null
  debit_indicator: string | null
  credit_indicator: string | null
  period_pattern: string | null
  balance_pattern: string | null
  currency_pattern: string | null
  skip_lines_pattern: string | null
  sample_text: string | null
  is_active: boolean
  validation_status: 'pending' | 'validated' | 'rejected'
  consecutive_successes: number
  validation_count: number
  last_validated_at: string | null
  last_correction_notes: string | null
  created_at: string
  updated_at: string
}

// ============ Tax Grids (Payroll & Corporate) ============

export interface PayrollTaxGrid {
  id: string
  tenant_id: string | null
  country_code: string
  grid_type: 'its' | 'employer_contribution' | 'employee_contribution' | 'income_tax' | 'other_deduction' | 'other_income' | 'composite'
  name: string
  description: string | null
  effective_from: string
  effective_to: string | null
  status: 'draft' | 'active' | 'archived'
  source: 'platform' | 'imported' | 'manual' | 'api'
  file_url: string | null
  is_default: boolean
  created_at: string
  updated_at: string
}

export interface PayrollTaxGridLine {
  id: string
  grid_id: string
  line_type: 'bracket' | 'flat' | 'percentage' | 'fixed_amount'
  category: 'social_security' | 'health' | 'retirement' | 'unemployment' | 'csg_crds' | 'its' | 'income_tax' | 'other_deduction' | 'other_income' | 'other_tax' | 'employer_charge' | 'employee_charge'
  label: string
  base_type: 'gross' | 'taxable_gross' | 'net' | 'total_gross' | 'custom'
  min_amount: number
  max_amount: number | null
  rate_employee: number
  rate_employer: number
  cap_amount: number | null
  fixed_amount: number
  sort_order: number
  created_at: string
}

export interface CorporateTaxGrid {
  id: string
  tenant_id: string | null
  country_code: string
  tax_type: 'corporate_income_tax' | 'minimum_tax' | 'turnover_tax' | 'withholding_tax' | 'property_tax' | 'other_corporate_tax'
  name: string
  description: string | null
  effective_from: string
  effective_to: string | null
  status: 'draft' | 'active' | 'archived'
  source: 'platform' | 'imported' | 'manual' | 'api'
  file_url: string | null
  is_default: boolean
  created_at: string
  updated_at: string
}

export interface CorporateTaxGridLine {
  id: string
  grid_id: string
  line_type: 'bracket' | 'flat' | 'percentage' | 'fixed_amount'
  label: string
  base_type: 'profit' | 'turnover' | 'property_value' | 'custom'
  min_amount: number
  max_amount: number | null
  rate: number
  cap_amount: number | null
  fixed_amount: number
  sort_order: number
  created_at: string
}

// ============ Sprint 8: Exchange Gain/Loss (#9) ============
export interface ExchangeGainLossEntry {
  id: string
  tenant_id: string | null
  payment_id: string | null
  invoice_id: string | null
  type: 'gain' | 'loss'
  amount: number
  exchange_rate_original: number | null
  exchange_rate_payment: number | null
  account_gain_code: string | null
  account_loss_code: string | null
  journal_entry_id: string | null
  created_at: string
}

// ============ Sprint 8: Check Books (#82) ============
export interface CheckBook {
  id: string
  tenant_id: string | null
  bank_account_id: string | null
  journal_id: string | null
  name: string
  first_check_number: string
  last_check_number: string
  next_check_number: string
  status: 'active' | 'exhausted' | 'cancelled'
  issued_count: number
  created_at: string
}

export interface Check {
  id: string
  tenant_id: string | null
  check_book_id: string | null
  check_number: string
  amount: number
  payee: string
  issue_date: string
  due_date: string | null
  status: 'draft' | 'issued' | 'cashed' | 'cancelled' | 'lost'
  journal_entry_id: string | null
  payment_id: string | null
  notes: string | null
  created_at: string
}

// ============ Sprint H: POS ============

export interface PosTerminal {
  id: string
  tenant_id: string | null
  name: string
  warehouse_id: string | null
  location: string | null
  active: boolean
  created_at: string
}

export interface PosSession {
  id: string
  tenant_id: string | null
  terminal_id: string
  user_email: string
  opening_amount: number
  closing_amount: number | null
  expected_amount: number | null
  difference: number | null
  status: 'open' | 'closed'
  opened_at: string
  closed_at: string | null
  notes: string | null
}

export interface PosTicket {
  id: string
  tenant_id: string | null
  number: string
  session_id: string
  terminal_id: string
  customer_id: string | null
  date: string
  subtotal: number
  vat_total: number
  total: number
  payment_method: 'cash' | 'card' | 'check' | 'transfer' | 'mixed' | null
  amount_paid: number
  change_given: number
  status: 'completed' | 'cancelled' | 'refunded'
  invoice_id: string | null
  notes: string | null
  created_at: string
  pos_ticket_lines?: PosTicketLine[]
}

export interface PosTicketLine {
  id: string
  tenant_id: string | null
  ticket_id: string
  product_id: string | null
  description: string
  quantity: number
  unit_price: number
  vat_rate: number
  line_total: number
  created_at: string
}

// ============ Sprint I: Dématérialisation (types étendus) ============

export interface OnlinePayment {
  id: string
  tenant_id: string | null
  invoice_id: string | null
  customer_id: string | null
  payment_provider: 'stripe' | 'paypal' | 'paystack' | 'other' | null
  provider_transaction_id: string | null
  amount: number
  currency_code: string
  status: 'pending' | 'completed' | 'failed' | 'refunded'
  payment_url: string | null
  paid_at: string | null
  created_at: string
}

export interface DocumentShare {
  id: string
  tenant_id: string | null
  document_type: string
  document_id: string
  shared_with_email: string
  share_token: string
  share_url: string | null
  expires_at: string | null
  viewed: boolean
  viewed_at: string | null
  created_at: string
}

// ============ Sprint B: Leaves & Absences ============
export interface LeaveBalance {
  id: string
  tenant_id: string | null
  employee_id: string
  leave_type: string
  year: number
  acquired: number
  taken: number
  pending: number
  remaining: number
  carry_over: number
  provision: number
  provision_calculated_at: string | null
  created_at: string
  updated_at: string
}

export interface PublicHoliday {
  id: string
  tenant_id: string | null
  name: string
  holiday_date: string
  region: string
  country: string
  is_working_day: boolean
  created_at: string
}

export interface LeaveRule {
  id: string
  tenant_id: string | null
  leave_type: string
  label: string
  accrual_rate: number
  max_carry_over: number
  carry_over_expiry_months: number
  requires_justification: boolean
  requires_manager_approval: boolean
  min_notice_days: number
  max_consecutive_days: number
  color: string
  count_method: 'working_days' | 'working_days_excl_saturday' | 'calendar_days'
  affects_pay: boolean
  deduction_rate: number
  active: boolean
  created_at: string
}

export interface ApprovalWorkflow {
  id: string
  tenant_id: string | null
  name: string
  entity_type: 'leave_request' | 'expense_report' | 'timesheet'
  steps: { role: string; order: number }[]
  active: boolean
  created_at: string
}

export interface LeaveProvision {
  id: string
  tenant_id: string | null
  employee_id: string
  period: string
  cp_remaining_days: number
  rtt_remaining_days: number
  recovery_remaining_days: number
  daily_rate: number
  cp_provision: number
  rtt_provision: number
  recovery_provision: number
  total_provision: number
  accounting_entry_id: string | null
  status: 'draft' | 'calculated' | 'posted'
  created_at: string
}

export interface StaffRequirement {
  id: string
  tenant_id: string | null
  department: string
  min_staff: number
  days_of_week: string[]
  start_date: string | null
  end_date: string | null
  active: boolean
  created_at: string
}

// ============ Sprint C: Payroll Advanced ============
export interface MealVoucherConfig {
  id: string
  tenant_id: string | null
  voucher_value: number
  employer_share: number
  employee_share: number
  eligible_days: string[]
  max_per_month: number
  active: boolean
  created_at: string
}

export interface PayrollVariableElement {
  id: string
  tenant_id: string | null
  employee_id: string
  pay_run_id: string | null
  period: string
  element_type: 'overtime' | 'bonus' | 'commission' | 'absence' | 'meal_voucher' | 'transport' | 'other'
  description: string | null
  quantity: number | null
  unit_price: number | null
  amount: number
  source: 'manual' | 'timesheet' | 'leave_request' | 'expense_report' | 'import'
  source_id: string | null
  integrated: boolean
  created_at: string
}

export interface SepaPaymentOrder {
  id: string
  tenant_id: string | null
  pay_run_id: string | null
  number: string
  execution_date: string
  total_amount: number
  currency: string
  employee_count: number
  file_url: string | null
  file_generated_at: string | null
  status: 'draft' | 'generated' | 'transmitted' | 'processed' | 'rejected'
  transmitted_at: string | null
  processed_at: string | null
  notes: string | null
  created_at: string
}

export interface PaySlipClarified {
  id: string
  tenant_id: string | null
  pay_slip_id: string
  employee_id: string
  period: string
  gross_salary: number
  social_charges_employee: number
  social_charges_employer: number
  income_tax: number
  net_before_tax: number
  net_after_tax: number
  total_deductions: number
  lines: any[]
  created_at: string
}

// ============ Sprint D: Admin & Arrêts ============

export interface WorkStoppage {
  id: string
  tenant_id: string | null
  employee_id: string
  stoppage_type: 'maladie' | 'accident_travail' | 'maladie_professionnelle' | 'maternite' | 'paternite' | 'accident_vie_privee'
  start_date: string
  end_date: string | null
  expected_end_date: string | null
  reprise_date: string | null
  reprise_type: 'plein_temps' | 'mi_temps_therapeutique' | 'temps_partiel' | null
  days_count: number | null
  working_days_count: number | null
  subrogation: boolean
  net_guarantee: boolean
  ijss_net_amount: number
  ijss_brut_amount: number
  ijss_daily_rate: number
  ijss_days_count: number
  ijss_care_days: number
  pas_days_count: number
  employer_maintenance_amount: number
  employer_maintenance_rate: number
  bpij_number: string | null
  bpij_imported_at: string | null
  regularization_amount: number
  regularization_type: 'positive' | 'negative' | null
  medical_certificate_url: string | null
  notes: string | null
  status: 'active' | 'closed' | 'regularized'
  created_at: string
  updated_at: string
}

export interface IjssHistory {
  id: string
  tenant_id: string | null
  work_stoppage_id: string
  employee_id: string
  period: string
  ijss_net_received: number
  ijss_brut_calculated: number
  days_paid: number
  pas_amount: number
  pas_rate: number
  integrated_in_payslip: boolean
  payslip_id: string | null
  created_at: string
}

export interface WorkHardshipRecord {
  id: string
  tenant_id: string | null
  employee_id: string
  exposure_type: string
  exposure_level: 'low' | 'medium' | 'high'
  exposure_start: string | null
  exposure_end: string | null
  duration_months: number | null
  points: number
  declaration_status: 'pending' | 'declared' | 'rejected'
  declared_at: string | null
  notes: string | null
  created_at: string
}

export interface CpfTransaction {
  id: string
  tenant_id: string | null
  employee_id: string
  transaction_type: 'acquisition' | 'usage' | 'adjustment' | 'expiry'
  hours: number
  amount: number
  training_label: string | null
  training_start_date: string | null
  training_end_date: string | null
  training_provider: string | null
  notes: string | null
  created_at: string
}

export interface MedicalExam {
  id: string
  tenant_id: string | null
  employee_id: string
  exam_type: 'initial' | 'periodic' | 'reprise' | 'post_hazard' | 'pre_employment'
  scheduled_date: string
  completed_date: string | null
  result: 'apt' | 'apt_with_restrictions' | 'unapt' | 'pending' | null
  restrictions: string | null
  next_exam_date: string | null
  occupational_doctor: string | null
  notes: string | null
  created_at: string
}

export interface ExpenseCategory {
  id: string
  tenant_id: string | null
  code: string
  label: string
  account_code: string | null
  vat_rate: number
  max_amount: number | null
  max_monthly: number | null
  requires_receipt: boolean
  active: boolean
  created_at: string
}

export interface InterviewCampaign {
  id: string
  tenant_id: string | null
  name: string
  campaign_type: 'annual' | 'mid_year' | 'professional' | 'exit' | 'other'
  start_date: string
  end_date: string | null
  reminder_days: number
  status: 'draft' | 'active' | 'closed'
  form_template: any
  created_at: string
}

export interface EmployeeObjective {
  id: string
  tenant_id: string | null
  employee_id: string
  campaign_id: string | null
  title: string
  description: string | null
  target_value: number | null
  current_value: number
  unit: 'percent' | 'count' | 'currency' | 'days' | null
  period: string | null
  frequency: 'annual' | 'quarterly' | 'monthly'
  status: 'active' | 'achieved' | 'missed' | 'cancelled'
  created_at: string
  updated_at: string
}

// ============ Sprint E: Sortie & Entretiens ============

export interface EmployeeExitProcess {
  id: string
  tenant_id: string | null
  employee_id: string
  exit_date: string
  exit_reason: 'resignation' | 'dismissal' | 'end_cdd' | 'retirement' | 'mutual_agreement' | 'probation_fail'
  step: number
  status: 'in_progress' | 'completed' | 'cancelled'
  cp_indemnity: number
  rtt_indemnity: number
  recovery_indemnity: number
  bonus_amount: number
  advance_deduction: number
  overtime_amount: number
  total_gross: number
  total_net: number
  work_certificate_url: string | null
  settlement_receipt_url: string | null
  pole_emploi_attestation_url: string | null
  dsn_exit_url: string | null
  documents_generated: boolean
  dsn_exit_generated: boolean
  dsn_exit_transmitted: boolean
  exit_payslip_id: string | null
  notes: string | null
  created_at: string
  completed_at: string | null
}

// ============ Sprint F: Social Declarations ============
export interface SocialDeclaration {
  id: string
  tenant_id: string | null
  number: string
  declaration_type: 'dsn' | 'dads_u' | 'ducs' | 'aed' | 'dpae' | 'dts_msa' | 'cibtp' | 'conges_payes_btp' | 'cice' | 'refus_cdi' | 'ct2025' | 'pasrau' | 'other'
  subtype: string | null
  period_month: number | null
  period_year: number | null
  period: string | null
  due_date: string | null
  status: 'draft' | 'generated' | 'transmitted' | 'accepted' | 'rejected' | 'regularized'
  file_url: string | null
  file_format: string | null
  generated_at: string | null
  transmitted_at: string | null
  response_code: string | null
  response_message: string | null
  anomalies: any[]
  amount: number | null
  employee_count: number | null
  details: Record<string, any>
  notes: string | null
  created_at: string
}

export interface CiceConfig {
  id: string
  tenant_id: string | null
  year: number
  smic_threshold: number
  rate: number
  eligible_salary_cap: number | null
  active: boolean
  created_at: string
}

export interface PasRate {
  id: string
  tenant_id: string | null
  employee_id: string
  rate: number
  effective_date: string
  expiry_date: string | null
  source: 'import' | 'manual' | 'api'
  created_at: string
}

export interface AtRate {
  id: string
  tenant_id: string | null
  employee_id: string
  rate: number
  bonus_malus_rate: number
  effective_date: string
  expiry_date: string | null
  risk_category: string | null
  created_at: string
}

export interface BdesIndicator {
  id: string
  tenant_id: string | null
  year: number
  category: string
  indicator_name: string
  indicator_value: number | null
  indicator_unit: string | null
  breakdown: Record<string, any>
  target_value: number | null
  previous_year_value: number | null
  notes: string | null
  created_at: string
}

export interface HonorariumRecord {
  id: string
  tenant_id: string | null
  employee_id: string | null
  recipient_name: string
  recipient_type: 'employee' | 'external' | 'intern'
  period: string | null
  amount: number
  description: string | null
  accounting_entry_id: string | null
  status: 'pending' | 'paid' | 'accounted'
  created_at: string
}

// ============ Sprint G: Dématérialisation RH ============
export interface DocumentDistributionLog {
  id: string
  tenant_id: string | null
  batch_id: string | null
  employee_document_id: string
  employee_id: string
  document_type: string
  period: string | null
  distributed_at: string | null
  acknowledged_at: string | null
  status: 'distributed' | 'acknowledged' | 'bounced' | 'failed'
  created_at: string
}

export interface RhRequest {
  id: string
  tenant_id: string | null
  employee_id: string
  request_type: 'document_copy' | 'certificate' | 'leave_info' | 'salary_change' | 'address_change' | 'other'
  subject: string
  description: string | null
  status: 'pending' | 'in_progress' | 'resolved' | 'rejected'
  assigned_to: string | null
  response: string | null
  resolved_at: string | null
  created_at: string
}

export interface RhKnowledgeBaseArticle {
  id: string
  tenant_id: string | null
  title: string
  content: string
  category: string | null
  tags: string[]
  author_id: string | null
  published: boolean
  views: number
  created_at: string
  updated_at: string
}

// ============ Sprint H: Pilotage RH ============

export interface RhDashboardConfig {
  id: string
  tenant_id: string | null
  user_email: string
  dashboard_type: 'hr_admin' | 'manager' | 'employee'
  widgets: { widget: string; position: number; size: 'small' | 'medium' | 'large' }[]
  filters: Record<string, any>
  created_at: string
  updated_at: string
}

export interface RhReport {
  id: string
  tenant_id: string | null
  name: string
  report_type: 'effectifs' | 'remuneration' | 'absenteeism' | 'turnover' | 'training' | 'costs' | 'custom'
  parameters: Record<string, any>
  chart_type: string | null
  data: any
  data_calculated_at: string | null
  created_by: string | null
  shared: boolean
  created_at: string
}

export interface EmployeeActivityLog {
  id: string
  tenant_id: string | null
  employee_id: string
  activity_type: 'leave_request' | 'leave_approved' | 'leave_rejected' | 'expense_submitted' | 'expense_approved' | 'document_received' | 'document_signed' | 'interview_scheduled' | 'objective_updated' | 'contract_change' | 'salary_change'
  description: string | null
  metadata: Record<string, any>
  created_at: string
}
