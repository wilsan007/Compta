-- ============================================
-- Compta App - Additional Schema (New Tables)
-- Run this after supabase-schema.sql
-- ============================================

-- Purchase Credit Notes
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

-- Fixed Assets
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

-- Employees
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

-- Pay Runs
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

-- Timesheets
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

-- Stock Movements
create table if not exists stock_movements (
  id uuid primary key default uuid_generate_v4(),
  product_id uuid references products(id) on delete cascade,
  type text not null check (type in ('in', 'out', 'adjustment')),
  quantity numeric(15,2) not null default 0,
  reference text,
  date date not null default current_date,
  created_at timestamptz default now()
);

-- Currencies
create table if not exists currencies (
  id uuid primary key default uuid_generate_v4(),
  code text not null unique,
  name text not null,
  symbol text,
  exchange_rate numeric(10,4) default 1.0,
  is_base boolean default false,
  created_at timestamptz default now()
);

-- Indexes
create index if not exists idx_purchase_credit_lines_purchase_credit_id on purchase_credit_lines(purchase_credit_id);
create index if not exists idx_fixed_assets_status on fixed_assets(status);
create index if not exists idx_employees_status on employees(status);
create index if not exists idx_pay_runs_status on pay_runs(status);
create index if not exists idx_timesheets_employee_id on timesheets(employee_id);
create index if not exists idx_timesheets_status on timesheets(status);
create index if not exists idx_stock_movements_product_id on stock_movements(product_id);

-- RLS
alter table purchase_credit_notes enable row level security;
alter table purchase_credit_lines enable row level security;
alter table fixed_assets enable row level security;
alter table employees enable row level security;
alter table pay_runs enable row level security;
alter table timesheets enable row level security;
alter table stock_movements enable row level security;
alter table currencies enable row level security;

DO $$ BEGIN
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
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_stock_movements') THEN
    CREATE POLICY "allow_all_stock_movements" ON stock_movements FOR ALL USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_currencies') THEN
    CREATE POLICY "allow_all_currencies" ON currencies FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
