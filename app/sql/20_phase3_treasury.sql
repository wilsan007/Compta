-- ============================================================
-- Phase 3 — Trésorerie 100%
-- Tables: MCF, treasury transfers, credit lines, investments,
--         value dates, treasury recurring, consolidated treasury
-- ============================================================

-- 1. Future accounting movements (MCF - Mouvements Comptables Futurs)
create table if not exists future_accounting_movements (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  description text not null,
  account_code text not null,
  third_party_id uuid,
  amount numeric(15,2) not null default 0,
  movement_type text not null check (movement_type in ('debit','credit')),
  expected_date date not null,
  source_type text check (source_type in ('invoice','purchase_invoice','payroll','loan','manual','recurring')),
  source_id uuid,
  incorporated boolean default false,
  incorporated_entry_id uuid,
  created_at timestamptz default now()
);
create index if not exists idx_mcf_expected_date on future_accounting_movements(expected_date);
create index if not exists idx_mcf_account on future_accounting_movements(account_code);
create index if not exists idx_mcf_incorporated on future_accounting_movements(incorporated);
alter table future_accounting_movements enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_future_accounting_movements') THEN
    CREATE POLICY "allow_all_future_accounting_movements" ON future_accounting_movements FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 2. Treasury transfers
create table if not exists treasury_transfers (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  number text not null,
  from_account_id uuid not null references bank_accounts(id) on delete restrict,
  to_account_id uuid not null references bank_accounts(id) on delete restrict,
  amount numeric(15,2) not null default 0,
  transfer_date date not null default current_date,
  value_date date,
  status text default 'draft' check (status in ('draft','executed','cancelled')),
  journal_entry_id uuid,
  notes text,
  created_at timestamptz default now()
);
create index if not exists idx_treasury_transfers_number on treasury_transfers(number);
create index if not exists idx_treasury_transfers_status on treasury_transfers(status);
alter table treasury_transfers enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_treasury_transfers') THEN
    CREATE POLICY "allow_all_treasury_transfers" ON treasury_transfers FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 3. Credit lines (financements)
create table if not exists credit_lines (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  bank_account_id uuid references bank_accounts(id) on delete set null,
  name text not null,
  type text default 'credit_line' check (type in ('credit_line','loan','overdraft')),
  limit_amount numeric(15,2) not null default 0,
  used_amount numeric(15,2) default 0,
  interest_rate numeric(5,2) default 0,
  start_date date,
  end_date date,
  monthly_payment numeric(15,2) default 0,
  status text default 'active' check (status in ('active','closed','suspended')),
  notes text,
  created_at timestamptz default now()
);
create index if not exists idx_credit_lines_name on credit_lines(name);
create index if not exists idx_credit_lines_status on credit_lines(status);
alter table credit_lines enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_credit_lines') THEN
    CREATE POLICY "allow_all_credit_lines" ON credit_lines FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 4. Investments (placements / OPCVM)
create table if not exists investments (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  name text not null,
  type text default 'opcv' check (type in ('opcv','bond','stock','term_deposit','other')),
  institution text,
  initial_amount numeric(15,2) not null default 0,
  current_value numeric(15,2) default 0,
  acquisition_date date,
  maturity_date date,
  interest_rate numeric(5,2) default 0,
  status text default 'active' check (status in ('active','matured','sold')),
  notes text,
  created_at timestamptz default now()
);
create index if not exists idx_investments_name on investments(name);
create index if not exists idx_investments_status on investments(status);
alter table investments enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_investments') THEN
    CREATE POLICY "allow_all_investments" ON investments FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 5. Value date tracking (conditions de valeur)
create table if not exists value_date_tracking (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  bank_account_id uuid not null references bank_accounts(id) on delete cascade,
  transaction_id uuid,
  operation_date date not null,
  value_date date not null,
  amount numeric(15,2) not null default 0,
  transaction_type text check (transaction_type in ('debit','credit')),
  notes text,
  created_at timestamptz default now()
);
create index if not exists idx_value_dates_account on value_date_tracking(bank_account_id);
create index if not exists idx_value_dates_value_date on value_date_tracking(value_date);
alter table value_date_tracking enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_value_date_tracking') THEN
    CREATE POLICY "allow_all_value_date_tracking" ON value_date_tracking FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 6. Treasury recurring (abonnements trésorerie)
create table if not exists treasury_recurring (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  description text not null,
  bank_account_id uuid references bank_accounts(id) on delete set null,
  amount numeric(15,2) not null default 0,
  type text not null check (type in ('incoming','outgoing')),
  frequency text default 'monthly' check (frequency in ('weekly','monthly','quarterly','yearly')),
  next_date date not null default current_date,
  end_date date,
  active boolean default true,
  created_at timestamptz default now()
);
create index if not exists idx_treasury_recurring_next on treasury_recurring(next_date);
alter table treasury_recurring enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_treasury_recurring') THEN
    CREATE POLICY "allow_all_treasury_recurring" ON treasury_recurring FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 7. Consolidated treasury (multi-sociétés)
create table if not exists consolidated_treasury (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  consolidation_date date not null default current_date,
  total_assets numeric(15,2) default 0,
  total_liabilities numeric(15,2) default 0,
  net_position numeric(15,2) default 0,
  details jsonb default '[]'::jsonb,
  created_at timestamptz default now()
);
create index if not exists idx_consolidated_treasury_date on consolidated_treasury(consolidation_date);
alter table consolidated_treasury enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_consolidated_treasury') THEN
    CREATE POLICY "allow_all_consolidated_treasury" ON consolidated_treasury FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 8. Add planned/realized/variance columns to treasury forecast
-- (treasury_forecast table already exists, we add columns via alter)
DO $$ BEGIN
  BEGIN
    ALTER TABLE treasury_forecast ADD COLUMN IF NOT EXISTS planned_amount numeric(15,2) default 0;
    ALTER TABLE treasury_forecast ADD COLUMN IF NOT EXISTS realized_amount numeric(15,2) default 0;
    ALTER TABLE treasury_forecast ADD COLUMN IF NOT EXISTS variance numeric(15,2) default 0;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
END $$;
