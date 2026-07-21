-- ============================================================
-- Phase 5 — Immobilisations 100%
-- Tables: depreciation plans, families, revaluation, split,
--         leasing, batch disposal, free fields, documents
-- ============================================================

-- 1. Asset depreciation plans (plans multiples)
create table if not exists asset_depreciation_plans (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  asset_id uuid not null references fixed_assets(id) on delete cascade,
  plan_type text not null check (plan_type in ('economic','fiscal','derogatory','exceptional')),
  depreciation_method text default 'linear' check (depreciation_method in ('linear','degressive','variable','manual')),
  duration_months int not null,
  residual_value numeric(15,2) default 0,
  annual_rate numeric(5,2),
  start_date date not null,
  end_date date,
  accumulated_depreciation numeric(15,2) default 0,
  current_net_value numeric(15,2) default 0,
  active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists idx_asset_dep_plans_asset on asset_depreciation_plans(asset_id);
create index if not exists idx_asset_dep_plans_type on asset_depreciation_plans(plan_type);
alter table asset_depreciation_plans enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_asset_depreciation_plans') THEN
    CREATE POLICY "allow_all_asset_depreciation_plans" ON asset_depreciation_plans FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 2. Asset families
create table if not exists asset_families (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  code text not null,
  name text not null,
  parent_id uuid references asset_families(id) on delete set null,
  default_account text,
  default_depreciation_account text,
  default_duration_months int,
  default_method text default 'linear' check (default_method in ('linear','degressive','variable','manual')),
  depreciation_rate numeric(5,2),
  description text,
  created_at timestamptz default now()
);
create index if not exists idx_asset_families_code on asset_families(code);
create index if not exists idx_asset_families_parent on asset_families(parent_id);
alter table asset_families enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_asset_families') THEN
    CREATE POLICY "allow_all_asset_families" ON asset_families FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 3. Asset revaluations
create table if not exists asset_revaluations (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  asset_id uuid not null references fixed_assets(id) on delete cascade,
  revaluation_date date not null,
  old_value numeric(15,2) not null default 0,
  new_value numeric(15,2) not null default 0,
  difference numeric(15,2) default 0,
  reason text,
  journal_entry_id uuid,
  created_at timestamptz default now()
);
create index if not exists idx_asset_revaluations_asset on asset_revaluations(asset_id);
alter table asset_revaluations enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_asset_revaluations') THEN
    CREATE POLICY "allow_all_asset_revaluations" ON asset_revaluations FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 4. Asset documents
create table if not exists asset_documents (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  asset_id uuid not null references fixed_assets(id) on delete cascade,
  document_type text check (document_type in ('invoice','contract','photo','other')),
  file_url text not null,
  file_name text,
  description text,
  created_at timestamptz default now()
);
create index if not exists idx_asset_documents_asset on asset_documents(asset_id);
alter table asset_documents enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_asset_documents') THEN
    CREATE POLICY "allow_all_asset_documents" ON asset_documents FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 5. Asset free fields (64 champs libres + 10 statistiques)
create table if not exists asset_free_fields (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  asset_id uuid not null references fixed_assets(id) on delete cascade,
  field_key text not null,
  field_value text,
  field_type text default 'text' check (field_type in ('text','number','date','boolean','select')),
  field_category text default 'free' check (field_category in ('free','statistical')),
  created_at timestamptz default now()
);
create index if not exists idx_asset_free_fields_asset on asset_free_fields(asset_id);
create index if not exists idx_asset_free_fields_key on asset_free_fields(field_key);
alter table asset_free_fields enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_asset_free_fields') THEN
    CREATE POLICY "allow_all_asset_free_fields" ON asset_free_fields FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 6. Batch disposals (cessions en rafale)
create table if not exists asset_batch_disposals (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  batch_number text not null,
  disposal_date date not null default current_date,
  total_assets int default 0,
  total_proceeds numeric(15,2) default 0,
  total_gain_loss numeric(15,2) default 0,
  status text default 'draft' check (status in ('draft','processed','cancelled')),
  journal_entry_id uuid,
  notes text,
  created_at timestamptz default now()
);
create index if not exists idx_asset_batch_disposals_number on asset_batch_disposals(batch_number);
alter table asset_batch_disposals enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_asset_batch_disposals') THEN
    CREATE POLICY "allow_all_asset_batch_disposals" ON asset_batch_disposals FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 7. Batch disposal lines
create table if not exists asset_batch_disposal_lines (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  batch_id uuid not null references asset_batch_disposals(id) on delete cascade,
  asset_id uuid not null references fixed_assets(id) on delete restrict,
  disposal_type text check (disposal_type in ('sale','scrapping','donation','transfer')),
  proceeds numeric(15,2) default 0,
  net_book_value numeric(15,2) default 0,
  gain_loss numeric(15,2) default 0,
  created_at timestamptz default now()
);
create index if not exists idx_batch_disposal_lines_batch on asset_batch_disposal_lines(batch_id);
alter table asset_batch_disposal_lines enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_asset_batch_disposal_lines') THEN
    CREATE POLICY "allow_all_asset_batch_disposal_lines" ON asset_batch_disposal_lines FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 8. Asset splits (fractionnement)
create table if not exists asset_splits (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  original_asset_id uuid not null references fixed_assets(id) on delete restrict,
  split_date date not null default current_date,
  reason text,
  created_at timestamptz default now()
);
create index if not exists idx_asset_splits_original on asset_splits(original_asset_id);
alter table asset_splits enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_asset_splits') THEN
    CREATE POLICY "allow_all_asset_splits" ON asset_splits FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 9. Asset split components
create table if not exists asset_split_components (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  split_id uuid not null references asset_splits(id) on delete cascade,
  new_asset_id uuid not null references fixed_assets(id) on delete cascade,
  allocated_value numeric(15,2) not null default 0,
  allocated_percentage numeric(5,2) default 0,
  created_at timestamptz default now()
);
create index if not exists idx_asset_split_components_split on asset_split_components(split_id);
alter table asset_split_components enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_asset_split_components') THEN
    CREATE POLICY "allow_all_asset_split_components" ON asset_split_components FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 10. Add columns to fixed_assets
alter table fixed_assets add column if not exists asset_type text default 'owned' check (asset_type in ('owned','leased','leasing'));
alter table fixed_assets add column if not exists parent_asset_id uuid references fixed_assets(id) on delete set null;
alter table fixed_assets add column if not exists family_id uuid references asset_families(id) on delete set null;
alter table fixed_assets add column if not exists asset_number text;
alter table fixed_assets add column if not exists lease_start_date date;
alter table fixed_assets add column if not exists lease_end_date date;
alter table fixed_assets add column if not exists lease_monthly_payment numeric(15,2) default 0;
alter table fixed_assets add column if not exists purchase_entry_id uuid;
