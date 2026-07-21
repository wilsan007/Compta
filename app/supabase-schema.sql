-- ============================================
-- Compta App - Database Schema
-- Inspired by Sage Accounting structure
-- ============================================

-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- ============================================
-- COMPANY SETTINGS
-- ============================================
create table if not exists company_settings (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  legal_name text,
  vat_number text,
  siret text,
  address text,
  city text,
  postal_code text,
  country text default 'France',
  currency text default 'EUR',
  fiscal_year_start text default '01-01',
  email text,
  phone text,
  website text,
  logo_url text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ============================================
-- USERS
-- ============================================
create table if not exists users (
  id uuid primary key default uuid_generate_v4(),
  auth_id uuid references auth.users(id) on delete cascade,
  name text not null,
  email text not null unique,
  role text not null default 'viewer' check (role in ('admin', 'accountant', 'manager', 'viewer')),
  active boolean default true,
  last_login timestamptz,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ============================================
-- CHART OF ACCOUNTS
-- ============================================
create table if not exists chart_accounts (
  id uuid primary key default uuid_generate_v4(),
  code text not null unique,
  name text not null,
  type text not null check (type in ('asset', 'liability', 'equity', 'income', 'expense')),
  balance numeric(15,2) default 0,
  vat_rate text,
  description text,
  parent_id uuid references chart_accounts(id),
  created_at timestamptz default now()
);

-- ============================================
-- CUSTOMERS
-- ============================================
create table if not exists customers (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  email text,
  phone text,
  address text,
  city text,
  postal_code text,
  country text default 'France',
  vat_number text,
  contact_name text,
  balance numeric(15,2) default 0,
  credit_limit numeric(15,2) default 0,
  payment_terms text default '30 days',
  currency text default 'EUR',
  active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ============================================
-- SUPPLIERS
-- ============================================
create table if not exists suppliers (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  email text,
  phone text,
  address text,
  city text,
  postal_code text,
  country text default 'France',
  vat_number text,
  contact_name text,
  balance numeric(15,2) default 0,
  payment_terms text default '30 days',
  currency text default 'EUR',
  active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ============================================
-- PRODUCTS & SERVICES
-- ============================================
create table if not exists products (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  sku text unique,
  description text,
  type text not null check (type in ('stock', 'service')),
  sale_price numeric(15,2) default 0,
  purchase_price numeric(15,2) default 0,
  vat_rate numeric(5,2) default 20.0,
  stock_quantity numeric(15,2) default 0,
  reorder_level numeric(15,2) default 0,
  unit text default 'unité',
  category text,
  active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ============================================
-- INVOICES (Sales)
-- ============================================
create table if not exists invoices (
  id uuid primary key default uuid_generate_v4(),
  number text not null unique,
  customer_id uuid references customers(id) on delete set null,
  customer_name text,
  date date not null default current_date,
  due_date date not null,
  status text not null default 'draft' check (status in ('draft', 'sent', 'viewed', 'paid', 'overdue', 'cancelled')),
  subtotal numeric(15,2) default 0,
  vat_total numeric(15,2) default 0,
  total numeric(15,2) default 0,
  amount_paid numeric(15,2) default 0,
  amount_due numeric(15,2) default 0,
  notes text,
  recurring boolean default false,
  recurring_frequency text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ============================================
-- INVOICE LINES
-- ============================================
create table if not exists invoice_lines (
  id uuid primary key default uuid_generate_v4(),
  invoice_id uuid references invoices(id) on delete cascade,
  product_id uuid references products(id) on delete set null,
  description text not null,
  quantity numeric(15,2) default 1,
  unit_price numeric(15,2) default 0,
  vat_rate numeric(5,2) default 20.0,
  total numeric(15,2) default 0,
  vat_total numeric(15,2) default 0,
  line_order int default 0,
  created_at timestamptz default now()
);

-- ============================================
-- QUOTES & ESTIMATES
-- ============================================
create table if not exists quotes (
  id uuid primary key default uuid_generate_v4(),
  number text not null unique,
  customer_id uuid references customers(id) on delete set null,
  customer_name text,
  date date not null default current_date,
  expiry_date date not null,
  status text not null default 'draft' check (status in ('draft', 'sent', 'accepted', 'rejected', 'expired')),
  subtotal numeric(15,2) default 0,
  vat_total numeric(15,2) default 0,
  total numeric(15,2) default 0,
  notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists quote_lines (
  id uuid primary key default uuid_generate_v4(),
  quote_id uuid references quotes(id) on delete cascade,
  product_id uuid references products(id) on delete set null,
  description text not null,
  quantity numeric(15,2) default 1,
  unit_price numeric(15,2) default 0,
  vat_rate numeric(5,2) default 20.0,
  total numeric(15,2) default 0,
  vat_total numeric(15,2) default 0,
  line_order int default 0,
  created_at timestamptz default now()
);

-- ============================================
-- CREDIT NOTES (Sales)
-- ============================================
create table if not exists credit_notes (
  id uuid primary key default uuid_generate_v4(),
  number text not null unique,
  customer_id uuid references customers(id) on delete set null,
  customer_name text,
  date date not null default current_date,
  status text not null default 'draft' check (status in ('draft', 'applied')),
  subtotal numeric(15,2) default 0,
  vat_total numeric(15,2) default 0,
  total numeric(15,2) default 0,
  reason text,
  invoice_id uuid references invoices(id) on delete set null,
  created_at timestamptz default now()
);

create table if not exists credit_note_lines (
  id uuid primary key default uuid_generate_v4(),
  credit_note_id uuid references credit_notes(id) on delete cascade,
  description text not null,
  quantity numeric(15,2) default 1,
  unit_price numeric(15,2) default 0,
  vat_rate numeric(5,2) default 20.0,
  total numeric(15,2) default 0,
  vat_total numeric(15,2) default 0,
  line_order int default 0,
  created_at timestamptz default now()
);

-- ============================================
-- PURCHASE INVOICES (Bills)
-- ============================================
create table if not exists purchase_invoices (
  id uuid primary key default uuid_generate_v4(),
  number text not null unique,
  supplier_id uuid references suppliers(id) on delete set null,
  supplier_name text,
  date date not null default current_date,
  due_date date not null,
  status text not null default 'draft' check (status in ('draft', 'sent', 'viewed', 'paid', 'overdue', 'cancelled')),
  subtotal numeric(15,2) default 0,
  vat_total numeric(15,2) default 0,
  total numeric(15,2) default 0,
  amount_paid numeric(15,2) default 0,
  amount_due numeric(15,2) default 0,
  notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists purchase_invoice_lines (
  id uuid primary key default uuid_generate_v4(),
  purchase_invoice_id uuid references purchase_invoices(id) on delete cascade,
  product_id uuid references products(id) on delete set null,
  description text not null,
  quantity numeric(15,2) default 1,
  unit_price numeric(15,2) default 0,
  vat_rate numeric(5,2) default 20.0,
  total numeric(15,2) default 0,
  vat_total numeric(15,2) default 0,
  line_order int default 0,
  created_at timestamptz default now()
);

-- ============================================
-- BANK ACCOUNTS
-- ============================================
create table if not exists bank_accounts (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  type text not null check (type in ('chequing', 'savings', 'credit_card', 'cash', 'loan', 'other')),
  account_number text,
  sort_code text,
  balance numeric(15,2) default 0,
  currency text default 'EUR',
  bank_name text,
  last_reconciled date,
  connected boolean default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ============================================
-- BANK TRANSACTIONS
-- ============================================
create table if not exists bank_transactions (
  id uuid primary key default uuid_generate_v4(),
  account_id uuid references bank_accounts(id) on delete cascade,
  date date not null default current_date,
  description text not null,
  reference text,
  type text not null check (type in ('debit', 'credit')),
  amount numeric(15,2) not null default 0,
  category text,
  reconciled boolean default false,
  matched boolean default false,
  invoice_id uuid references invoices(id) on delete set null,
  purchase_invoice_id uuid references purchase_invoices(id) on delete set null,
  created_at timestamptz default now()
);

-- ============================================
-- BANK RULES
-- ============================================
create table if not exists bank_rules (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  condition_field text not null,
  condition_operator text not null,
  condition_value text not null,
  action_category text not null,
  action_account_code text,
  action_vat_rate numeric(5,2),
  priority int default 0,
  active boolean default true,
  created_at timestamptz default now()
);

-- ============================================
-- JOURNAL ENTRIES
-- ============================================
create table if not exists journal_entries (
  id uuid primary key default uuid_generate_v4(),
  number text not null unique,
  date date not null default current_date,
  description text not null,
  reference text,
  status text not null default 'draft' check (status in ('draft', 'posted')),
  total_debit numeric(15,2) default 0,
  total_credit numeric(15,2) default 0,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists journal_lines (
  id uuid primary key default uuid_generate_v4(),
  journal_id uuid references journal_entries(id) on delete cascade,
  account_code text not null,
  account_name text,
  debit numeric(15,2) default 0,
  credit numeric(15,2) default 0,
  description text,
  line_order int default 0,
  created_at timestamptz default now()
);

-- ============================================
-- VAT RETURNS
-- ============================================
create table if not exists vat_returns (
  id uuid primary key default uuid_generate_v4(),
  period_start date not null,
  period_end date not null,
  status text not null default 'draft' check (status in ('draft', 'submitted', 'paid')),
  box1_output_vat numeric(15,2) default 0,
  box2_input_vat numeric(15,2) default 0,
  box3_vat_due numeric(15,2) default 0,
  box4_repayment_due numeric(15,2) default 0,
  box5_net_vat numeric(15,2) default 0,
  total_sales numeric(15,2) default 0,
  total_purchases numeric(15,2) default 0,
  submitted_date date,
  created_at timestamptz default now()
);

-- ============================================
-- PROJECTS
-- ============================================
create table if not exists projects (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  description text,
  customer_id uuid references customers(id) on delete set null,
  status text not null default 'active' check (status in ('active', 'completed', 'on_hold', 'cancelled')),
  budget numeric(15,2) default 0,
  actual_cost numeric(15,2) default 0,
  start_date date,
  end_date date,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ============================================
-- JOURNALS (codes journaux — référentiel central)
-- ============================================
create table if not exists journals (
  id uuid primary key default uuid_generate_v4(),
  code text not null unique,
  name text not null,
  type text not null check (type in ('purchase', 'sale', 'bank', 'cash', 'general', 'analytic')),
  account_counterpart text,
  bank_account_id uuid references bank_accounts(id) on delete set null,
  default_entry_template_id uuid,
  status text default 'active' check (status in ('active', 'inactive')),
  locked boolean default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ============================================
-- FISCAL YEARS & PERIODS
-- ============================================
create table if not exists fiscal_years (
  id uuid primary key default uuid_generate_v4(),
  code text not null unique,
  start_date date not null,
  end_date date not null,
  status text default 'open' check (status in ('open', 'closed', 'locked')),
  closed_at timestamptz,
  closed_by uuid references users(id),
  created_at timestamptz default now()
);

create table if not exists fiscal_periods (
  id uuid primary key default uuid_generate_v4(),
  fiscal_year_id uuid references fiscal_years(id) on delete cascade,
  period_number int not null,
  period_label text not null,
  start_date date not null,
  end_date date not null,
  status text default 'open' check (status in ('open', 'closed', 'locked')),
  created_at timestamptz default now()
);

-- ============================================
-- ENTRY TEMPLATES (modèles de saisie)
-- ============================================
create table if not exists entry_templates (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  journal_code text references journals(code),
  description text,
  template_lines jsonb,
  is_default boolean default false,
  active boolean default true,
  created_at timestamptz default now()
);

-- ============================================
-- THIRD PARTY ACCOUNTS (plan tiers unifié)
-- ============================================
create table if not exists third_party_accounts (
  id uuid primary key default uuid_generate_v4(),
  code text not null unique,
  account_general_code text,
  type text not null check (type in ('customer', 'supplier', 'employee', 'other')),
  name text not null,
  customer_id uuid references customers(id) on delete set null,
  supplier_id uuid references suppliers(id) on delete set null,
  employee_id uuid references users(id) on delete set null,
  balance numeric(15,2) default 0,
  lettrage_code text,
  currency text default 'EUR',
  active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ============================================
-- ANALYTIC SECTIONS (plan analytique)
-- ============================================
create table if not exists analytic_sections (
  id uuid primary key default uuid_generate_v4(),
  code text not null unique,
  name text not null,
  parent_id uuid references analytic_sections(id),
  axis text,
  level int default 1,
  active boolean default true,
  created_at timestamptz default now()
);

-- ============================================
-- BUDGETS
-- ============================================
create table if not exists budgets (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  fiscal_year_id uuid references fiscal_years(id) on delete cascade,
  account_code text,
  analytic_section_id uuid references analytic_sections(id) on delete set null,
  period_1 numeric(15,2) default 0,
  period_2 numeric(15,2) default 0,
  period_3 numeric(15,2) default 0,
  period_4 numeric(15,2) default 0,
  period_5 numeric(15,2) default 0,
  period_6 numeric(15,2) default 0,
  period_7 numeric(15,2) default 0,
  period_8 numeric(15,2) default 0,
  period_9 numeric(15,2) default 0,
  period_10 numeric(15,2) default 0,
  period_11 numeric(15,2) default 0,
  period_12 numeric(15,2) default 0,
  created_at timestamptz default now()
);

-- ============================================
-- STANDARD LABELS (bibliothèque de libellés)
-- ============================================
create table if not exists standard_labels (
  id uuid primary key default uuid_generate_v4(),
  label text not null unique,
  category text,
  created_at timestamptz default now()
);

-- ============================================
-- MIGRATION: journal_entries — add Sage 100 columns
-- ============================================
alter table journal_entries add column if not exists journal_code text;
alter table journal_entries add column if not exists fiscal_period_id uuid;
alter table journal_entries add column if not exists piece_number text;
alter table journal_entries add column if not exists invoice_ref text;
alter table journal_entries add column if not exists entry_template_id uuid;
alter table journal_entries add column if not exists status_detail text default 'open';
alter table journal_entries add column if not exists validated_by uuid;
alter table journal_entries add column if not exists validated_at timestamptz;

-- ============================================
-- MIGRATION: journal_lines — add Sage 100 columns
-- ============================================
alter table journal_lines add column if not exists account_general text;
alter table journal_lines add column if not exists account_tiers text;
alter table journal_lines add column if not exists third_party_id uuid;
alter table journal_lines add column if not exists lettrage_code text;
alter table journal_lines add column if not exists lettrage_date date;
alter table journal_lines add column if not exists piece_number text;
alter table journal_lines add column if not exists reference text;
alter table journal_lines add column if not exists analytic_section_id uuid;
alter table journal_lines add column if not exists analytic_amount numeric(15,2);
alter table journal_lines add column if not exists running_balance numeric(15,2);
alter table journal_lines add column if not exists reconciled boolean default false;
alter table journal_lines add column if not exists line_date date;

-- ============================================
-- PURCHASE CREDIT NOTES (Avoirs fournisseurs)
-- ============================================
create table if not exists purchase_credit_notes (
  id uuid primary key default uuid_generate_v4(),
  number text not null unique,
  supplier_id uuid references suppliers(id) on delete set null,
  supplier_name text,
  date date not null default current_date,
  status text not null default 'draft' check (status in ('draft', 'applied')),
  subtotal numeric(15,2) default 0,
  vat_total numeric(15,2) default 0,
  total numeric(15,2) default 0,
  reason text,
  purchase_invoice_id uuid references purchase_invoices(id) on delete set null,
  created_at timestamptz default now()
);

create table if not exists purchase_credit_lines (
  id uuid primary key default uuid_generate_v4(),
  purchase_credit_id uuid references purchase_credit_notes(id) on delete cascade,
  description text not null,
  quantity numeric(15,2) default 1,
  unit_price numeric(15,2) default 0,
  vat_rate numeric(5,2) default 20.0,
  total numeric(15,2) default 0,
  vat_total numeric(15,2) default 0,
  line_order int default 0,
  created_at timestamptz default now()
);

-- ============================================
-- FIXED ASSETS (Immobilisations)
-- ============================================
create table if not exists fixed_assets (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  code text unique,
  category text,
  purchase_date date not null default current_date,
  purchase_value numeric(15,2) default 0,
  current_value numeric(15,2) default 0,
  depreciation_method text default 'straight_line',
  useful_life_years int default 5,
  residual_value numeric(15,2) default 0,
  status text not null default 'active' check (status in ('active', 'disposed', 'fully_depreciated')),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ============================================
-- EMPLOYEES (Employés)
-- ============================================
create table if not exists employees (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  email text,
  phone text,
  position text,
  department text,
  salary numeric(15,2) default 0,
  hire_date date default current_date,
  status text not null default 'active' check (status in ('active', 'inactive', 'on_leave')),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ============================================
-- PAY RUNS (Campagnes de paie)
-- ============================================
create table if not exists pay_runs (
  id uuid primary key default uuid_generate_v4(),
  number text not null unique,
  period_start date not null,
  period_end date not null,
  pay_date date not null,
  status text not null default 'draft' check (status in ('draft', 'approved', 'paid')),
  gross_total numeric(15,2) default 0,
  tax_total numeric(15,2) default 0,
  net_total numeric(15,2) default 0,
  employee_count int default 0,
  created_at timestamptz default now()
);

-- ============================================
-- TIMESHEETS (Feuilles de temps)
-- ============================================
create table if not exists timesheets (
  id uuid primary key default uuid_generate_v4(),
  employee_id uuid references employees(id) on delete cascade,
  date date not null default current_date,
  hours numeric(5,2) default 0,
  description text,
  project_id uuid references projects(id) on delete set null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  created_at timestamptz default now()
);

-- ============================================
-- CURRENCIES (Devises)
-- ============================================
create table if not exists currencies (
  id uuid primary key default uuid_generate_v4(),
  code text not null unique,
  name text not null,
  symbol text,
  exchange_rate numeric(10,4) default 1.0,
  is_base boolean default false,
  created_at timestamptz default now()
);

-- ============================================
-- INDEXES
-- ============================================
create index if not exists idx_invoices_customer_id on invoices(customer_id);
create index if not exists idx_invoices_status on invoices(status);
create index if not exists idx_invoices_date on invoices(date);
create index if not exists idx_purchase_invoices_supplier_id on purchase_invoices(supplier_id);
create index if not exists idx_purchase_invoices_status on purchase_invoices(status);
create index if not exists idx_bank_transactions_account_id on bank_transactions(account_id);
create index if not exists idx_bank_transactions_date on bank_transactions(date);
create index if not exists idx_bank_transactions_reconciled on bank_transactions(reconciled);
create index if not exists idx_journal_entries_date on journal_entries(date);
create index if not exists idx_journal_entries_status on journal_entries(status);
create index if not exists idx_invoice_lines_invoice_id on invoice_lines(invoice_id);
create index if not exists idx_quote_lines_quote_id on quote_lines(quote_id);
create index if not exists idx_credit_note_lines_credit_note_id on credit_note_lines(credit_note_id);
create index if not exists idx_purchase_invoice_lines_purchase_invoice_id on purchase_invoice_lines(purchase_invoice_id);
create index if not exists idx_journal_lines_journal_id on journal_lines(journal_id);
create index if not exists idx_journal_entries_journal_code on journal_entries(journal_code);
create index if not exists idx_journal_entries_period on journal_entries(fiscal_period_id);
create index if not exists idx_journal_entries_piece on journal_entries(piece_number);
create index if not exists idx_journal_lines_account_general on journal_lines(account_general);
create index if not exists idx_journal_lines_account_tiers on journal_lines(account_tiers);
create index if not exists idx_journal_lines_lettrage on journal_lines(lettrage_code);
create index if not exists idx_journal_lines_analytic on journal_lines(analytic_section_id);
create index if not exists idx_journals_code on journals(code);
create index if not exists idx_fiscal_periods_year on fiscal_periods(fiscal_year_id);
create index if not exists idx_third_party_code on third_party_accounts(code);
create index if not exists idx_third_party_type on third_party_accounts(type);
create index if not exists idx_purchase_credit_lines_purchase_credit_id on purchase_credit_lines(purchase_credit_id);
create index if not exists idx_fixed_assets_status on fixed_assets(status);
create index if not exists idx_employees_status on employees(status);
create index if not exists idx_pay_runs_status on pay_runs(status);
create index if not exists idx_timesheets_employee_id on timesheets(employee_id);
create index if not exists idx_timesheets_status on timesheets(status);

-- ============================================
-- UPDATED_AT TRIGGERS
-- ============================================
create or replace function update_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'customers_updated_at') THEN
    CREATE TRIGGER customers_updated_at BEFORE UPDATE ON customers FOR EACH ROW EXECUTE FUNCTION update_updated_at();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'suppliers_updated_at') THEN
    CREATE TRIGGER suppliers_updated_at BEFORE UPDATE ON suppliers FOR EACH ROW EXECUTE FUNCTION update_updated_at();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'products_updated_at') THEN
    CREATE TRIGGER products_updated_at BEFORE UPDATE ON products FOR EACH ROW EXECUTE FUNCTION update_updated_at();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'invoices_updated_at') THEN
    CREATE TRIGGER invoices_updated_at BEFORE UPDATE ON invoices FOR EACH ROW EXECUTE FUNCTION update_updated_at();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'purchase_invoices_updated_at') THEN
    CREATE TRIGGER purchase_invoices_updated_at BEFORE UPDATE ON purchase_invoices FOR EACH ROW EXECUTE FUNCTION update_updated_at();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'bank_accounts_updated_at') THEN
    CREATE TRIGGER bank_accounts_updated_at BEFORE UPDATE ON bank_accounts FOR EACH ROW EXECUTE FUNCTION update_updated_at();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'journal_entries_updated_at') THEN
    CREATE TRIGGER journal_entries_updated_at BEFORE UPDATE ON journal_entries FOR EACH ROW EXECUTE FUNCTION update_updated_at();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'projects_updated_at') THEN
    CREATE TRIGGER projects_updated_at BEFORE UPDATE ON projects FOR EACH ROW EXECUTE FUNCTION update_updated_at();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'company_settings_updated_at') THEN
    CREATE TRIGGER company_settings_updated_at BEFORE UPDATE ON company_settings FOR EACH ROW EXECUTE FUNCTION update_updated_at();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'users_updated_at') THEN
    CREATE TRIGGER users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION update_updated_at();
  END IF;
END $$;

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================
alter table company_settings enable row level security;
alter table users enable row level security;
alter table chart_accounts enable row level security;
alter table customers enable row level security;
alter table suppliers enable row level security;
alter table products enable row level security;
alter table invoices enable row level security;
alter table invoice_lines enable row level security;
alter table quotes enable row level security;
alter table quote_lines enable row level security;
alter table credit_notes enable row level security;
alter table credit_note_lines enable row level security;
alter table purchase_invoices enable row level security;
alter table purchase_invoice_lines enable row level security;
alter table bank_accounts enable row level security;
alter table bank_transactions enable row level security;
alter table bank_rules enable row level security;
alter table journal_entries enable row level security;
alter table journal_lines enable row level security;
alter table vat_returns enable row level security;
alter table projects enable row level security;
alter table journals enable row level security;
alter table fiscal_years enable row level security;
alter table fiscal_periods enable row level security;
alter table entry_templates enable row level security;
alter table third_party_accounts enable row level security;
alter table analytic_sections enable row level security;
alter table budgets enable row level security;
alter table standard_labels enable row level security;
alter table purchase_credit_notes enable row level security;
alter table purchase_credit_lines enable row level security;
alter table fixed_assets enable row level security;
alter table employees enable row level security;
alter table pay_runs enable row level security;
alter table timesheets enable row level security;
alter table currencies enable row level security;

-- Permissive policies for development (adjust for production)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_company_settings') THEN
    CREATE POLICY "allow_all_company_settings" ON company_settings FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_users') THEN
    CREATE POLICY "allow_all_users" ON users FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_chart_accounts') THEN
    CREATE POLICY "allow_all_chart_accounts" ON chart_accounts FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_customers') THEN
    CREATE POLICY "allow_all_customers" ON customers FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_suppliers') THEN
    CREATE POLICY "allow_all_suppliers" ON suppliers FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_products') THEN
    CREATE POLICY "allow_all_products" ON products FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_invoices') THEN
    CREATE POLICY "allow_all_invoices" ON invoices FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_invoice_lines') THEN
    CREATE POLICY "allow_all_invoice_lines" ON invoice_lines FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_quotes') THEN
    CREATE POLICY "allow_all_quotes" ON quotes FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_quote_lines') THEN
    CREATE POLICY "allow_all_quote_lines" ON quote_lines FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_credit_notes') THEN
    CREATE POLICY "allow_all_credit_notes" ON credit_notes FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_credit_note_lines') THEN
    CREATE POLICY "allow_all_credit_note_lines" ON credit_note_lines FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_purchase_invoices') THEN
    CREATE POLICY "allow_all_purchase_invoices" ON purchase_invoices FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_purchase_invoice_lines') THEN
    CREATE POLICY "allow_all_purchase_invoice_lines" ON purchase_invoice_lines FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_bank_accounts') THEN
    CREATE POLICY "allow_all_bank_accounts" ON bank_accounts FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_bank_transactions') THEN
    CREATE POLICY "allow_all_bank_transactions" ON bank_transactions FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_bank_rules') THEN
    CREATE POLICY "allow_all_bank_rules" ON bank_rules FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_journal_entries') THEN
    CREATE POLICY "allow_all_journal_entries" ON journal_entries FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_journal_lines') THEN
    CREATE POLICY "allow_all_journal_lines" ON journal_lines FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_vat_returns') THEN
    CREATE POLICY "allow_all_vat_returns" ON vat_returns FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_projects') THEN
    CREATE POLICY "allow_all_projects" ON projects FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_journals') THEN
    CREATE POLICY "allow_all_journals" ON journals FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_fiscal_years') THEN
    CREATE POLICY "allow_all_fiscal_years" ON fiscal_years FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_fiscal_periods') THEN
    CREATE POLICY "allow_all_fiscal_periods" ON fiscal_periods FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_entry_templates') THEN
    CREATE POLICY "allow_all_entry_templates" ON entry_templates FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_third_party_accounts') THEN
    CREATE POLICY "allow_all_third_party_accounts" ON third_party_accounts FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_analytic_sections') THEN
    CREATE POLICY "allow_all_analytic_sections" ON analytic_sections FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_budgets') THEN
    CREATE POLICY "allow_all_budgets" ON budgets FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_standard_labels') THEN
    CREATE POLICY "allow_all_standard_labels" ON standard_labels FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_purchase_credit_notes') THEN
    CREATE POLICY "allow_all_purchase_credit_notes" ON purchase_credit_notes FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_purchase_credit_lines') THEN
    CREATE POLICY "allow_all_purchase_credit_lines" ON purchase_credit_lines FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_fixed_assets') THEN
    CREATE POLICY "allow_all_fixed_assets" ON fixed_assets FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_employees') THEN
    CREATE POLICY "allow_all_employees" ON employees FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_pay_runs') THEN
    CREATE POLICY "allow_all_pay_runs" ON pay_runs FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_timesheets') THEN
    CREATE POLICY "allow_all_timesheets" ON timesheets FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_currencies') THEN
    CREATE POLICY "allow_all_currencies" ON currencies FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- ============================================
-- PAYMENT ORDERS (ordres de paiement — SEPA, chèques, remises)
-- ============================================
create table if not exists payment_orders (
  id uuid primary key default uuid_generate_v4(),
  number text not null unique,
  type text not null check (type in ('sepa_transfer', 'check', 'cash', 'card', 'other')),
  status text not null default 'draft' check (status in ('draft', 'approved', 'executed', 'cancelled')),
  bank_account_id uuid references bank_accounts(id) on delete set null,
  third_party_id uuid references third_party_accounts(id) on delete set null,
  third_party_name text,
  third_party_iban text,
  amount numeric(15,2) not null default 0,
  payment_date date not null default current_date,
  reference text,
  description text,
  remise_number text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ============================================
-- ASSET DEPRECIATIONS (table des amortissements par immobilisation)
-- ============================================
create table if not exists asset_depreciations (
  id uuid primary key default uuid_generate_v4(),
  asset_id uuid not null references fixed_assets(id) on delete cascade,
  fiscal_year_code text,
  period int not null check (period >= 1 and period <= 12),
  depreciation_type text not null check (depreciation_type in ('depreciation', 'disposal', 'dotation')),
  amount numeric(15,2) not null default 0,
  cumulative_amount numeric(15,2) not null default 0,
  net_book_value numeric(15,2) not null default 0,
  entry_number text,
  created_at timestamptz default now()
);

-- ============================================
-- COLLECTION REMINDERS (relances de recouvrement)
-- ============================================
create table if not exists collection_reminders (
  id uuid primary key default uuid_generate_v4(),
  number text not null unique,
  customer_id uuid references customers(id) on delete set null,
  third_party_id uuid references third_party_accounts(id) on delete set null,
  invoice_id uuid references invoices(id) on delete set null,
  reminder_level int not null default 1 check (reminder_level in (1, 2, 3)),
  reminder_date date not null default current_date,
  due_date date,
  amount numeric(15,2) not null default 0,
  status text not null default 'sent' check (status in ('draft', 'sent', 'paid', 'cancelled')),
  notes text,
  created_at timestamptz default now()
);

-- Indexes for Sprint 5
create index if not exists idx_payment_orders_bank on payment_orders(bank_account_id);
create index if not exists idx_payment_orders_status on payment_orders(status);
create index if not exists idx_payment_orders_date on payment_orders(payment_date);
create index if not exists idx_asset_depreciations_asset on asset_depreciations(asset_id);
create index if not exists idx_collection_reminders_customer on collection_reminders(customer_id);
create index if not exists idx_collection_reminders_status on collection_reminders(status);

-- RLS for Sprint 5 tables
alter table payment_orders enable row level security;
alter table asset_depreciations enable row level security;
alter table collection_reminders enable row level security;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_payment_orders') THEN
    CREATE POLICY "allow_all_payment_orders" ON payment_orders FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_asset_depreciations') THEN
    CREATE POLICY "allow_all_asset_depreciations" ON asset_depreciations FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_collection_reminders') THEN
    CREATE POLICY "allow_all_collection_reminders" ON collection_reminders FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- ============================================
-- SPRINT 6: GESTION COMMERCIALE (GesCom)
-- ============================================

-- Sales Orders (commandes clients)
create table if not exists sales_orders (
  id uuid primary key default uuid_generate_v4(),
  number text not null unique,
  customer_id uuid references customers(id) on delete set null,
  order_date date not null default current_date,
  delivery_date date,
  status text not null default 'draft' check (status in ('draft','confirmed','delivered','invoiced','cancelled')),
  subtotal numeric(15,2) default 0,
  vat numeric(15,2) default 0,
  total numeric(15,2) default 0,
  notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists sales_order_lines (
  id uuid primary key default uuid_generate_v4(),
  sales_order_id uuid references sales_orders(id) on delete cascade,
  product_id uuid references products(id) on delete set null,
  description text not null,
  quantity numeric(15,2) not null default 1,
  unit_price numeric(15,2) not null default 0,
  vat_rate numeric(5,2) default 0,
  line_total numeric(15,2) default 0
);

-- Delivery Notes (bons de livraison)
create table if not exists delivery_notes (
  id uuid primary key default uuid_generate_v4(),
  number text not null unique,
  customer_id uuid references customers(id) on delete set null,
  sales_order_id uuid references sales_orders(id) on delete set null,
  delivery_date date not null default current_date,
  status text not null default 'pending' check (status in ('pending','delivered','returned','cancelled')),
  carrier text,
  tracking_number text,
  notes text,
  created_at timestamptz default now()
);

create table if not exists delivery_note_lines (
  id uuid primary key default uuid_generate_v4(),
  delivery_note_id uuid references delivery_notes(id) on delete cascade,
  product_id uuid references products(id) on delete set null,
  description text not null,
  quantity numeric(15,2) not null default 1
);

-- Customer Payments (règlements clients)
create table if not exists customer_payments (
  id uuid primary key default uuid_generate_v4(),
  number text not null unique,
  customer_id uuid references customers(id) on delete set null,
  invoice_id uuid references invoices(id) on delete set null,
  payment_date date not null default current_date,
  amount numeric(15,2) not null default 0,
  method text check (method in ('cash','check','transfer','card','direct_debit','other')),
  bank_account_id uuid references bank_accounts(id) on delete set null,
  reference text,
  status text not null default 'recorded' check (status in ('recorded','reconciled','cancelled')),
  created_at timestamptz default now()
);

-- Purchase Orders (commandes fournisseurs)
create table if not exists purchase_orders (
  id uuid primary key default uuid_generate_v4(),
  number text not null unique,
  supplier_id uuid references suppliers(id) on delete set null,
  order_date date not null default current_date,
  expected_date date,
  status text not null default 'draft' check (status in ('draft','confirmed','received','cancelled')),
  subtotal numeric(15,2) default 0,
  vat numeric(15,2) default 0,
  total numeric(15,2) default 0,
  notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists purchase_order_lines (
  id uuid primary key default uuid_generate_v4(),
  purchase_order_id uuid references purchase_orders(id) on delete cascade,
  product_id uuid references products(id) on delete set null,
  description text not null,
  quantity numeric(15,2) not null default 1,
  unit_price numeric(15,2) not null default 0,
  vat_rate numeric(5,2) default 0,
  line_total numeric(15,2) default 0
);

-- Goods Receipts (réceptions marchandises)
create table if not exists goods_receipts (
  id uuid primary key default uuid_generate_v4(),
  number text not null unique,
  supplier_id uuid references suppliers(id) on delete set null,
  purchase_order_id uuid references purchase_orders(id) on delete set null,
  receipt_date date not null default current_date,
  status text not null default 'pending' check (status in ('pending','received','partial','cancelled')),
  notes text,
  created_at timestamptz default now()
);

create table if not exists goods_receipt_lines (
  id uuid primary key default uuid_generate_v4(),
  goods_receipt_id uuid references goods_receipts(id) on delete cascade,
  product_id uuid references products(id) on delete set null,
  description text not null,
  quantity_ordered numeric(15,2) default 0,
  quantity_received numeric(15,2) default 0
);

-- Supplier Payments (règlements fournisseurs)
create table if not exists supplier_payments (
  id uuid primary key default uuid_generate_v4(),
  number text not null unique,
  supplier_id uuid references suppliers(id) on delete set null,
  purchase_invoice_id uuid references purchase_invoices(id) on delete set null,
  payment_date date not null default current_date,
  amount numeric(15,2) not null default 0,
  method text check (method in ('cash','check','transfer','card','direct_debit','other')),
  bank_account_id uuid references bank_accounts(id) on delete set null,
  reference text,
  status text not null default 'recorded' check (status in ('recorded','reconciled','cancelled')),
  created_at timestamptz default now()
);

-- Warehouses (dépôts)
create table if not exists warehouses (
  id uuid primary key default uuid_generate_v4(),
  code text not null unique,
  name text not null,
  address text,
  city text,
  postal_code text,
  country text default 'France',
  active boolean default true,
  created_at timestamptz default now()
);

-- Stock Quantities (quantités en stock par dépôt)
create table if not exists stock_quantities (
  id uuid primary key default uuid_generate_v4(),
  product_id uuid not null references products(id) on delete cascade,
  warehouse_id uuid not null references warehouses(id) on delete cascade,
  quantity numeric(15,2) not null default 0,
  reserved_quantity numeric(15,2) not null default 0,
  min_quantity numeric(15,2) default 0,
  max_quantity numeric(15,2) default 0,
  reorder_point numeric(15,2) default 0,
  unit_cost numeric(15,2) default 0,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique(product_id, warehouse_id)
);

-- Stock Movements (mouvements de stock)
create table if not exists stock_movements (
  id uuid primary key default uuid_generate_v4(),
  product_id uuid not null references products(id) on delete cascade,
  warehouse_id uuid references warehouses(id) on delete set null,
  movement_type text not null check (movement_type in ('in','out','transfer','adjustment','initial')),
  quantity numeric(15,2) not null default 0,
  unit_cost numeric(15,2) default 0,
  reference text,
  reference_type text check (reference_type in ('delivery_note','goods_receipt','inventory','transfer','manual')),
  reference_id uuid,
  movement_date date not null default current_date,
  notes text,
  created_at timestamptz default now()
);

-- MIGRATION: stock_movements — add Sprint 6 columns if table existed from additions file
alter table stock_movements add column if not exists warehouse_id uuid;
alter table stock_movements add column if not exists movement_type text;
alter table stock_movements add column if not exists unit_cost numeric(15,2) default 0;
alter table stock_movements add column if not exists reference_type text;
alter table stock_movements add column if not exists reference_id uuid;
alter table stock_movements add column if not exists movement_date date default current_date;
alter table stock_movements add column if not exists notes text;
-- Migrate old 'type' column data to 'movement_type' if needed
update stock_movements set movement_type = type where movement_type is null and type is not null;
-- Add check constraint only if not already present
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'stock_movements_movement_type_check') THEN
    ALTER TABLE stock_movements ADD CONSTRAINT stock_movements_movement_type_check
      CHECK (movement_type IN ('in','out','transfer','adjustment','initial'));
  END IF;
END $$;

-- Price Lists (listes de prix)
create table if not exists price_lists (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  code text unique,
  type text not null default 'sales' check (type in ('sales','purchase')),
  currency text default 'EUR',
  valid_from date,
  valid_to date,
  active boolean default true,
  is_default boolean default false,
  created_at timestamptz default now()
);

create table if not exists price_list_lines (
  id uuid primary key default uuid_generate_v4(),
  price_list_id uuid references price_lists(id) on delete cascade,
  product_id uuid references products(id) on delete cascade,
  unit_price numeric(15,2) not null default 0,
  min_quantity numeric(15,2) default 1,
  discount_percent numeric(5,2) default 0
);

-- BOMs (nomenclatures)
create table if not exists boms (
  id uuid primary key default uuid_generate_v4(),
  code text not null unique,
  name text not null,
  product_id uuid references products(id) on delete set null,
  quantity numeric(15,2) default 1,
  unit text default 'unit',
  active boolean default true,
  created_at timestamptz default now()
);

create table if not exists bom_lines (
  id uuid primary key default uuid_generate_v4(),
  bom_id uuid references boms(id) on delete cascade,
  product_id uuid not null references products(id) on delete cascade,
  quantity numeric(15,2) not null default 1,
  unit_cost numeric(15,2) default 0,
  position int default 1
);

-- Manufacturing Orders (ordres de fabrication)
create table if not exists manufacturing_orders (
  id uuid primary key default uuid_generate_v4(),
  number text not null unique,
  bom_id uuid references boms(id) on delete set null,
  product_id uuid references products(id) on delete set null,
  quantity numeric(15,2) not null default 1,
  status text not null default 'planned' check (status in ('planned','in_progress','completed','cancelled')),
  start_date date,
  end_date date,
  warehouse_id uuid references warehouses(id) on delete set null,
  notes text,
  created_at timestamptz default now()
);

-- Indexes for Sprint 6
create index if not exists idx_sales_orders_customer on sales_orders(customer_id);
create index if not exists idx_sales_orders_status on sales_orders(status);
create index if not exists idx_sales_order_lines_order on sales_order_lines(sales_order_id);
create index if not exists idx_delivery_notes_customer on delivery_notes(customer_id);
create index if not exists idx_delivery_note_lines_dn on delivery_note_lines(delivery_note_id);
create index if not exists idx_customer_payments_customer on customer_payments(customer_id);
create index if not exists idx_customer_payments_invoice on customer_payments(invoice_id);
create index if not exists idx_purchase_orders_supplier on purchase_orders(supplier_id);
create index if not exists idx_purchase_order_lines_order on purchase_order_lines(purchase_order_id);
create index if not exists idx_goods_receipts_supplier on goods_receipts(supplier_id);
create index if not exists idx_goods_receipt_lines_gr on goods_receipt_lines(goods_receipt_id);
create index if not exists idx_supplier_payments_supplier on supplier_payments(supplier_id);
create index if not exists idx_stock_quantities_product on stock_quantities(product_id);
create index if not exists idx_stock_quantities_warehouse on stock_quantities(warehouse_id);
create index if not exists idx_stock_movements_product on stock_movements(product_id);
create index if not exists idx_stock_movements_warehouse on stock_movements(warehouse_id);
create index if not exists idx_stock_movements_date on stock_movements(movement_date);
create index if not exists idx_price_list_lines_list on price_list_lines(price_list_id);
create index if not exists idx_bom_lines_bom on bom_lines(bom_id);
create index if not exists idx_manufacturing_orders_bom on manufacturing_orders(bom_id);
create index if not exists idx_manufacturing_orders_status on manufacturing_orders(status);

-- RLS for Sprint 6 tables
alter table sales_orders enable row level security;
alter table sales_order_lines enable row level security;
alter table delivery_notes enable row level security;
alter table delivery_note_lines enable row level security;
alter table customer_payments enable row level security;
alter table purchase_orders enable row level security;
alter table purchase_order_lines enable row level security;
alter table goods_receipts enable row level security;
alter table goods_receipt_lines enable row level security;
alter table supplier_payments enable row level security;
alter table warehouses enable row level security;
alter table stock_quantities enable row level security;
alter table stock_movements enable row level security;
alter table price_lists enable row level security;
alter table price_list_lines enable row level security;
alter table boms enable row level security;
alter table bom_lines enable row level security;
alter table manufacturing_orders enable row level security;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_sales_orders') THEN
    CREATE POLICY "allow_all_sales_orders" ON sales_orders FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_sales_order_lines') THEN
    CREATE POLICY "allow_all_sales_order_lines" ON sales_order_lines FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_delivery_notes') THEN
    CREATE POLICY "allow_all_delivery_notes" ON delivery_notes FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_delivery_note_lines') THEN
    CREATE POLICY "allow_all_delivery_note_lines" ON delivery_note_lines FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_customer_payments') THEN
    CREATE POLICY "allow_all_customer_payments" ON customer_payments FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_purchase_orders') THEN
    CREATE POLICY "allow_all_purchase_orders" ON purchase_orders FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_purchase_order_lines') THEN
    CREATE POLICY "allow_all_purchase_order_lines" ON purchase_order_lines FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_goods_receipts') THEN
    CREATE POLICY "allow_all_goods_receipts" ON goods_receipts FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_goods_receipt_lines') THEN
    CREATE POLICY "allow_all_goods_receipt_lines" ON goods_receipt_lines FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_supplier_payments') THEN
    CREATE POLICY "allow_all_supplier_payments" ON supplier_payments FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_warehouses') THEN
    CREATE POLICY "allow_all_warehouses" ON warehouses FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_stock_quantities') THEN
    CREATE POLICY "allow_all_stock_quantities" ON stock_quantities FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_stock_movements') THEN
    CREATE POLICY "allow_all_stock_movements" ON stock_movements FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_price_lists') THEN
    CREATE POLICY "allow_all_price_lists" ON price_lists FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_price_list_lines') THEN
    CREATE POLICY "allow_all_price_list_lines" ON price_list_lines FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_boms') THEN
    CREATE POLICY "allow_all_boms" ON boms FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_bom_lines') THEN
    CREATE POLICY "allow_all_bom_lines" ON bom_lines FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_manufacturing_orders') THEN
    CREATE POLICY "allow_all_manufacturing_orders" ON manufacturing_orders FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- ============================================
-- SPRINT 7: PAIE & RH
-- ============================================

-- Pay Slips (bulletins de paie)
create table if not exists pay_slips (
  id uuid primary key default uuid_generate_v4(),
  number text not null unique,
  pay_run_id uuid references pay_runs(id) on delete cascade,
  employee_id uuid not null references employees(id) on delete cascade,
  period_start date not null,
  period_end date not null,
  gross_salary numeric(15,2) default 0,
  overtime_pay numeric(15,2) default 0,
  bonus numeric(15,2) default 0,
  total_gross numeric(15,2) default 0,
  social_security_employee numeric(15,2) default 0,
  income_tax numeric(15,2) default 0,
  other_deductions numeric(15,2) default 0,
  total_deductions numeric(15,2) default 0,
  net_salary numeric(15,2) default 0,
  employer_contributions numeric(15,2) default 0,
  status text not null default 'draft' check (status in ('draft','approved','paid','cancelled')),
  payment_date date,
  created_at timestamptz default now()
);

-- Payroll Accounting Entries (OD de paie)
create table if not exists payroll_accounting_entries (
  id uuid primary key default uuid_generate_v4(),
  number text not null unique,
  pay_run_id uuid references pay_runs(id) on delete set null,
  period_date date not null,
  gross_total numeric(15,2) default 0,
  employer_contributions_total numeric(15,2) default 0,
  employee_deductions_total numeric(15,2) default 0,
  net_total numeric(15,2) default 0,
  journal_entry_id uuid references journal_entries(id) on delete set null,
  status text not null default 'draft' check (status in ('draft','transferred','cancelled')),
  created_at timestamptz default now()
);

-- Leave Requests (demandes de congés)
create table if not exists leave_requests (
  id uuid primary key default uuid_generate_v4(),
  employee_id uuid not null references employees(id) on delete cascade,
  leave_type text not null check (leave_type in ('annual','sick','maternity','paternity','unpaid','other')),
  start_date date not null,
  end_date date not null,
  days numeric(5,1) default 0,
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  reason text,
  approved_by uuid references employees(id) on delete set null,
  approved_at timestamptz,
  created_at timestamptz default now()
);

-- Contracts (contrats de travail)
create table if not exists contracts (
  id uuid primary key default uuid_generate_v4(),
  number text not null unique,
  employee_id uuid not null references employees(id) on delete cascade,
  contract_type text not null check (contract_type in ('cdi','cdd','apprentissage','stage','interim','freelance')),
  start_date date not null,
  end_date date,
  position text,
  department text,
  monthly_salary numeric(15,2) default 0,
  hourly_rate numeric(15,2) default 0,
  weekly_hours numeric(5,1) default 35,
  trial_period_days int default 0,
  status text not null default 'active' check (status in ('active','ended','suspended','terminated')),
  notes text,
  created_at timestamptz default now()
);

-- Legal Declarations (déclarations sociales/fiscales)
create table if not exists legal_declarations (
  id uuid primary key default uuid_generate_v4(),
  number text not null unique,
  declaration_type text not null check (declaration_type in ('dsn','urssaf','dgt','ifrs','other')),
  period_month int not null check (period_month >= 1 and period_month <= 12),
  period_year int not null,
  due_date date not null,
  submission_date date,
  amount numeric(15,2) default 0,
  status text not null default 'pending' check (status in ('pending','submitted','late','cancelled')),
  notes text,
  created_at timestamptz default now()
);

-- Indexes for Sprint 7
create index if not exists idx_pay_slips_pay_run on pay_slips(pay_run_id);
create index if not exists idx_pay_slips_employee on pay_slips(employee_id);
create index if not exists idx_pay_slips_status on pay_slips(status);
create index if not exists idx_payroll_acct_pay_run on payroll_accounting_entries(pay_run_id);
create index if not exists idx_payroll_acct_status on payroll_accounting_entries(status);
create index if not exists idx_leave_requests_employee on leave_requests(employee_id);
create index if not exists idx_leave_requests_status on leave_requests(status);
create index if not exists idx_contracts_employee on contracts(employee_id);
create index if not exists idx_contracts_status on contracts(status);
create index if not exists idx_legal_declarations_type on legal_declarations(declaration_type);
create index if not exists idx_legal_declarations_status on legal_declarations(status);

-- RLS for Sprint 7
alter table pay_slips enable row level security;
alter table payroll_accounting_entries enable row level security;
alter table leave_requests enable row level security;
alter table contracts enable row level security;
alter table legal_declarations enable row level security;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_pay_slips') THEN
    CREATE POLICY "allow_all_pay_slips" ON pay_slips FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_payroll_accounting_entries') THEN
    CREATE POLICY "allow_all_payroll_accounting_entries" ON payroll_accounting_entries FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_leave_requests') THEN
    CREATE POLICY "allow_all_leave_requests" ON leave_requests FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_contracts') THEN
    CREATE POLICY "allow_all_contracts" ON contracts FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_legal_declarations') THEN
    CREATE POLICY "allow_all_legal_declarations" ON legal_declarations FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- ============================================
-- SPRINT 8: AUDIT LOG (Journal d'audit)
-- ============================================
create table if not exists audit_log (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references users(id) on delete set null,
  action text not null check (action in ('create', 'update', 'delete', 'login', 'logout', 'transfer', 'validate', 'close', 'export')),
  entity_type text not null,
  entity_id uuid,
  entity_number text,
  description text,
  metadata jsonb,
  ip_address text,
  created_at timestamptz default now()
);

create index if not exists idx_audit_log_user_id on audit_log(user_id);
create index if not exists idx_audit_log_entity_type on audit_log(entity_type);
create index if not exists idx_audit_log_action on audit_log(action);
create index if not exists idx_audit_log_created_at on audit_log(created_at);

alter table audit_log enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_audit_log') THEN
    CREATE POLICY "allow_all_audit_log" ON audit_log FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- ============================================
-- BUDGET COMMITMENTS (Engagements budgétaires)
-- ============================================
create table if not exists budget_commitments (
  id uuid primary key default uuid_generate_v4(),
  description text not null,
  account_code text not null,
  fiscal_year_id uuid references fiscal_years(id) on delete cascade,
  amount numeric(15,2) not null default 0,
  commitment_date date not null default current_date,
  source_type text default 'manual' check (source_type in ('manual', 'purchase_order', 'purchase_invoice')),
  source_id uuid,
  status text not null default 'active' check (status in ('active', 'consumed', 'cancelled')),
  supplier_id uuid references suppliers(id) on delete set null,
  notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create index if not exists idx_budget_commitments_account on budget_commitments(account_code);
create index if not exists idx_budget_commitments_fiscal_year on budget_commitments(fiscal_year_id);
create index if not exists idx_budget_commitments_status on budget_commitments(status);

alter table budget_commitments enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_budget_commitments') THEN
    CREATE POLICY "allow_all_budget_commitments" ON budget_commitments FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- ============================================
-- PRODUCTION MODULE — Sprint 1: Gamme + Machine + Outillage
-- ============================================

-- Routings (gammes opératoires)
create table if not exists routings (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  code text not null,
  name text not null,
  description text,
  product_id uuid references products(id) on delete set null,
  version int default 1,
  active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists idx_routings_code on routings(code);
create index if not exists idx_routings_product on routings(product_id);
alter table routings enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_routings') THEN
    CREATE POLICY "allow_all_routings" ON routings FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- Work Centers (centres de charge)
create table if not exists work_centers (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  code text not null,
  name text not null,
  capacity_hours_per_day numeric(5,1) default 8,
  cost_per_hour numeric(15,2) default 0,
  active boolean default true,
  created_at timestamptz default now()
);
create index if not exists idx_work_centers_code on work_centers(code);
alter table work_centers enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_work_centers') THEN
    CREATE POLICY "allow_all_work_centers" ON work_centers FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- Machines
create table if not exists machines (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  code text not null,
  name text not null,
  work_center_id uuid references work_centers(id) on delete set null,
  capacity_per_hour numeric(15,2) default 0,
  status text default 'active' check (status in ('active','maintenance','inactive')),
  purchase_date date,
  notes text,
  created_at timestamptz default now()
);
create index if not exists idx_machines_code on machines(code);
create index if not exists idx_machines_work_center on machines(work_center_id);
alter table machines enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_machines') THEN
    CREATE POLICY "allow_all_machines" ON machines FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- Toolings (outillages)
create table if not exists toolings (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  code text not null,
  name text not null,
  machine_id uuid references machines(id) on delete set null,
  max_pieces int default 0,
  initial_counter int default 0,
  current_counter int default 0,
  status text default 'active' check (status in ('active','worn','inactive')),
  notes text,
  created_at timestamptz default now()
);
create index if not exists idx_toolings_code on toolings(code);
create index if not exists idx_toolings_machine on toolings(machine_id);
alter table toolings enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_toolings') THEN
    CREATE POLICY "allow_all_toolings" ON toolings FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- Routing Operations (opérations d'une gamme)
create table if not exists routing_operations (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  routing_id uuid not null references routings(id) on delete cascade,
  sequence int not null default 10,
  name text not null,
  description text,
  work_center_id uuid references work_centers(id) on delete set null,
  machine_id uuid references machines(id) on delete set null,
  tooling_id uuid references toolings(id) on delete set null,
  setup_time_min int default 0,
  run_time_min int default 0,
  is_subcontracted boolean default false,
  supplier_id uuid references suppliers(id) on delete set null,
  st_unit text,
  st_quantity numeric(15,2) default 1,
  created_at timestamptz default now()
);
create index if not exists idx_routing_operations_routing on routing_operations(routing_id);
create index if not exists idx_routing_operations_sequence on routing_operations(sequence);
alter table routing_operations enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_routing_operations') THEN
    CREATE POLICY "allow_all_routing_operations" ON routing_operations FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- ALTER existing tables to add routing_id
alter table boms add column if not exists routing_id uuid references routings(id) on delete set null;
alter table manufacturing_orders add column if not exists routing_id uuid references routings(id) on delete set null;

-- ============================================
-- PRODUCTION MODULE — Sprint 4: OF Enhancements
-- ============================================

-- OF Labels (étiquettes cartons)
create table if not exists of_labels (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  manufacturing_order_id uuid not null references manufacturing_orders(id) on delete cascade,
  label_number text not null unique,
  product_id uuid references products(id) on delete set null,
  planned_quantity numeric(15,2) default 0,
  actual_quantity numeric(15,2) default 0,
  is_complete boolean default false,
  is_declared boolean default false,
  created_at timestamptz default now()
);
create index if not exists idx_of_labels_mo on of_labels(manufacturing_order_id);
alter table of_labels enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_of_labels') THEN
    CREATE POLICY "allow_all_of_labels" ON of_labels FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- OF Lots (lots d'OF avec péremption)
create table if not exists of_lots (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  manufacturing_order_id uuid not null references manufacturing_orders(id) on delete cascade,
  lot_number text not null,
  product_id uuid references products(id) on delete set null,
  quantity numeric(15,2) default 0,
  production_date date,
  expiry_date date,
  custom_expiry_date date,
  expiry_type text check (expiry_type in ('DLUO','DDM','DLC')),
  created_at timestamptz default now()
);
create index if not exists idx_of_lots_mo on of_lots(manufacturing_order_id);
alter table of_lots enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_of_lots') THEN
    CREATE POLICY "allow_all_of_lots" ON of_lots FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- OF Consumptions (consommation différée)
create table if not exists of_consumptions (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  manufacturing_order_id uuid not null references manufacturing_orders(id) on delete cascade,
  product_id uuid not null references products(id) on delete cascade,
  quantity numeric(15,2) not null default 0,
  unit text default 'unit',
  consumption_date date not null default current_date,
  is_deferred boolean default false,
  notes text,
  created_at timestamptz default now()
);
create index if not exists idx_of_consumptions_mo on of_consumptions(manufacturing_order_id);
alter table of_consumptions enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_of_consumptions') THEN
    CREATE POLICY "allow_all_of_consumptions" ON of_consumptions FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- ALTER manufacturing_orders to add Sprint 4 columns
ALTER TABLE manufacturing_orders ADD COLUMN IF NOT EXISTS origin text default 'manual' check (origin in ('manual','mrp','sub_level'));
ALTER TABLE manufacturing_orders ADD COLUMN IF NOT EXISTS parent_mo_id uuid references manufacturing_orders(id) on delete set null;
ALTER TABLE manufacturing_orders ADD COLUMN IF NOT EXISTS lot_number text;
ALTER TABLE manufacturing_orders ADD COLUMN IF NOT EXISTS expiry_date date;
ALTER TABLE manufacturing_orders ADD COLUMN IF NOT EXISTS custom_expiry_date date;
ALTER TABLE manufacturing_orders ADD COLUMN IF NOT EXISTS expiry_type text check (expiry_type in ('DLUO','DDM','DLC'));
ALTER TABLE manufacturing_orders ADD COLUMN IF NOT EXISTS label_enabled boolean default false;
ALTER TABLE manufacturing_orders ADD COLUMN IF NOT EXISTS additional_text text;

-- ============================================
-- PRODUCTION MODULE — Sprint 3: Amalgam
-- ============================================
ALTER TABLE boms ADD COLUMN IF NOT EXISTS bom_type text default 'standard' check (bom_type in ('standard','amalgam'));

ALTER TABLE products ADD COLUMN IF NOT EXISTS is_amalgam boolean default false;
ALTER TABLE products ADD COLUMN IF NOT EXISTS units_per_carton int;
ALTER TABLE products ADD COLUMN IF NOT EXISTS st_unit text;
ALTER TABLE products ADD COLUMN IF NOT EXISTS purchase_unit text;
ALTER TABLE products ADD COLUMN IF NOT EXISTS st_multiple numeric(15,2) default 1;
ALTER TABLE products ADD COLUMN IF NOT EXISTS shelf_life_days int;
ALTER TABLE products ADD COLUMN IF NOT EXISTS exclude_from_mrp boolean default false;

-- ============================================
-- PRODUCTION MODULE — Sprint 2: Sous-traitance
-- ============================================

-- Subcontracting Orders (commandes de sous-traitance)
create table if not exists st_orders (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  number text not null unique,
  supplier_id uuid not null references suppliers(id) on delete restrict,
  manufacturing_order_id uuid references manufacturing_orders(id) on delete set null,
  routing_operation_id uuid references routing_operations(id) on delete set null,
  product_id uuid references products(id) on delete set null,
  quantity numeric(15,2) not null default 0,
  unit text default 'unit',
  unit_price numeric(15,2) default 0,
  total_price numeric(15,2) default 0,
  status text default 'draft' check (status in ('draft','sent','in_progress','received','cancelled')),
  order_date date not null default current_date,
  expected_date date,
  notes text,
  created_at timestamptz default now()
);
create index if not exists idx_st_orders_supplier on st_orders(supplier_id);
create index if not exists idx_st_orders_mo on st_orders(manufacturing_order_id);
create index if not exists idx_st_orders_status on st_orders(status);
alter table st_orders enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_st_orders') THEN
    CREATE POLICY "allow_all_st_orders" ON st_orders FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- Subcontracting Shipments (expéditions vers sous-traitant)
create table if not exists st_shipments (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  number text not null unique,
  st_order_id uuid not null references st_orders(id) on delete cascade,
  shipment_date date not null default current_date,
  warehouse_id uuid references warehouses(id) on delete set null,
  status text default 'pending' check (status in ('pending','shipped','returned')),
  notes text,
  created_at timestamptz default now()
);
create index if not exists idx_st_shipments_order on st_shipments(st_order_id);
alter table st_shipments enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_st_shipments') THEN
    CREATE POLICY "allow_all_st_shipments" ON st_shipments FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- Subcontracting Shipment Lines (matières expédiées)
create table if not exists st_shipment_lines (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  st_shipment_id uuid not null references st_shipments(id) on delete cascade,
  product_id uuid not null references products(id) on delete cascade,
  quantity numeric(15,2) not null default 0,
  unit text default 'unit',
  created_at timestamptz default now()
);
create index if not exists idx_st_shipment_lines_shipment on st_shipment_lines(st_shipment_id);
alter table st_shipment_lines enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_st_shipment_lines') THEN
    CREATE POLICY "allow_all_st_shipment_lines" ON st_shipment_lines FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- Subcontracting Receipts (réceptions de sous-traitance)
create table if not exists st_receipts (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  number text not null unique,
  st_order_id uuid not null references st_orders(id) on delete cascade,
  receipt_date date not null default current_date,
  warehouse_id uuid references warehouses(id) on delete set null,
  quantity_received numeric(15,2) default 0,
  quantity_returned numeric(15,2) default 0,
  status text default 'pending' check (status in ('pending','received','partial','cancelled')),
  notes text,
  created_at timestamptz default now()
);
create index if not exists idx_st_receipts_order on st_receipts(st_order_id);
alter table st_receipts enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_st_receipts') THEN
    CREATE POLICY "allow_all_st_receipts" ON st_receipts FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- Subcontracting Receipt Lines (produits reçus + matières retournées)
create table if not exists st_receipt_lines (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  st_receipt_id uuid not null references st_receipts(id) on delete cascade,
  product_id uuid not null references products(id) on delete cascade,
  quantity numeric(15,2) not null default 0,
  unit text default 'unit',
  line_type text default 'received' check (line_type in ('received','returned')),
  created_at timestamptz default now()
);
create index if not exists idx_st_receipt_lines_receipt on st_receipt_lines(st_receipt_id);
alter table st_receipt_lines enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_st_receipt_lines') THEN
    CREATE POLICY "allow_all_st_receipt_lines" ON st_receipt_lines FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- ============================================
-- PRODUCTION MODULE — Sprint 5: CBN/MRP
-- ============================================

-- MRP Runs (lancements de calcul des besoins nets)
create table if not exists mrp_runs (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  run_number text not null unique,
  run_date timestamptz default now(),
  status text default 'completed' check (status in ('running','completed','cancelled')),
  parameters jsonb,
  summary jsonb,
  created_at timestamptz default now()
);
create index if not exists idx_mrp_runs_date on mrp_runs(run_date);
alter table mrp_runs enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_mrp_runs') THEN
    CREATE POLICY "allow_all_mrp_runs" ON mrp_runs FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- MRP Proposals (propositions d'approvisionnement/fabrication)
create table if not exists mrp_proposals (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  mrp_run_id uuid not null references mrp_runs(id) on delete cascade,
  product_id uuid not null references products(id) on delete cascade,
  proposal_type text check (proposal_type in ('purchase','manufacture','subcontract')),
  gross_need numeric(15,2) not null default 0,
  stock_available numeric(15,2) default 0,
  open_orders numeric(15,2) default 0,
  net_need numeric(15,2) not null default 0,
  suggested_quantity numeric(15,2) default 0,
  suggested_date date,
  bom_id uuid references boms(id) on delete set null,
  supplier_id uuid references suppliers(id) on delete set null,
  status text default 'pending' check (status in ('pending','approved','rejected','converted')),
  notes text,
  created_at timestamptz default now()
);
create index if not exists idx_mrp_proposals_run on mrp_proposals(mrp_run_id);
create index if not exists idx_mrp_proposals_product on mrp_proposals(product_id);
create index if not exists idx_mrp_proposals_status on mrp_proposals(status);
alter table mrp_proposals enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_mrp_proposals') THEN
    CREATE POLICY "allow_all_mrp_proposals" ON mrp_proposals FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- MRP Pending Documents (documents en attente de traitement)
create table if not exists mrp_pending_docs (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  doc_type text not null check (doc_type in ('purchase_order','manufacturing_order','subcontract_order')),
  doc_id uuid,
  product_id uuid references products(id) on delete set null,
  quantity numeric(15,2) default 0,
  status text default 'pending' check (status in ('pending','processed','cancelled')),
  created_at timestamptz default now()
);
create index if not exists idx_mrp_pending_status on mrp_pending_docs(status);
alter table mrp_pending_docs enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_mrp_pending_docs') THEN
    CREATE POLICY "allow_all_mrp_pending_docs" ON mrp_pending_docs FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- ============================================
-- PRODUCTION MODULE — Sprint 6: Prévisions
-- ============================================
create table if not exists production_forecasts (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  forecast_number text not null unique,
  period text not null,
  start_date date not null,
  end_date date not null,
  product_id uuid references products(id) on delete set null,
  forecasted_quantity numeric(15,3) not null default 0,
  actual_quantity numeric(15,3) default 0,
  reliability_rate numeric(5,2) default 0,
  source text default 'manual' check (source in ('manual','invoice_import')),
  notes text,
  created_at timestamptz default now()
);
create index if not exists idx_forecasts_period on production_forecasts(period);
create index if not exists idx_forecasts_product on production_forecasts(product_id);
alter table production_forecasts enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_production_forecasts') THEN
    CREATE POLICY "allow_all_production_forecasts" ON production_forecasts FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- ============================================
-- PRODUCTION MODULE — Sprint 7: Planification
-- ============================================
create table if not exists planning_slots (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  manufacturing_order_id uuid not null references manufacturing_orders(id) on delete cascade,
  routing_operation_id uuid references routing_operations(id) on delete set null,
  machine_id uuid references machines(id) on delete set null,
  work_center_id uuid references work_centers(id) on delete set null,
  planned_start timestamptz,
  planned_end timestamptz,
  setup_time numeric(15,2) default 0,
  run_time numeric(15,2) default 0,
  status text default 'planned' check (status in ('planned','scheduled','in_progress','completed')),
  material_available boolean default true,
  material_check_date timestamptz,
  created_at timestamptz default now()
);
create index if not exists idx_planning_mo on planning_slots(manufacturing_order_id);
create index if not exists idx_planning_machine on planning_slots(machine_id);
create index if not exists idx_planning_dates on planning_slots(planned_start, planned_end);
alter table planning_slots enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_planning_slots') THEN
    CREATE POLICY "allow_all_planning_slots" ON planning_slots FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- ============================================
-- PRODUCTION MODULE — Sprint 9: Complémentaires
-- ============================================

-- Product Equivalences (cas d'emploi: affichage des équivalences)
create table if not exists product_equivalences (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  product_id uuid not null references products(id) on delete cascade,
  equivalent_product_id uuid not null references products(id) on delete cascade,
  conversion_ratio numeric(15,4) default 1,
  created_at timestamptz default now()
);
create index if not exists idx_equiv_product on product_equivalences(product_id);
alter table product_equivalences enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_product_equivalences') THEN
    CREATE POLICY "allow_all_product_equivalences" ON product_equivalences FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- Workflows (tâches automatisées: MRP, prévisions, etc.)
create table if not exists workflows (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  name text not null,
  description text,
  workflow_type text check (workflow_type in ('mrp','forecast','planning','custom')),
  schedule text,
  last_run timestamptz,
  status text default 'active' check (status in ('active','inactive')),
  created_at timestamptz default now()
);
alter table workflows enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_workflows') THEN
    CREATE POLICY "allow_all_workflows" ON workflows FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- OF Document Access (droits d'accès aux éditions du dossier de fabrication)
create table if not exists of_document_access (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  user_id uuid not null references users(id) on delete cascade,
  document_type text not null,
  can_view boolean default true,
  can_print boolean default false,
  can_export boolean default false,
  created_at timestamptz default now()
);
create index if not exists idx_of_doc_access_user on of_document_access(user_id);
alter table of_document_access enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_of_document_access') THEN
    CREATE POLICY "allow_all_of_document_access" ON of_document_access FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
