-- ============================================================
-- Phase 4 — Paie & RH 100%
-- Tables: payroll components, templates, advances, DSN, DPAE,
--         hardship, career history, CPF, archives, legal watch
-- ============================================================

-- 1. Payroll components (rubriques de paie)
create table if not exists payroll_components (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  code text not null,
  name text not null,
  type text not null check (type in ('gross','deduction','contribution','tax','net','benefit','information')),
  calculation_type text default 'fixed' check (calculation_type in ('fixed','percentage','formula','bracket')),
  default_value numeric(15,2) default 0,
  rate_employer numeric(5,2) default 0,
  rate_employee numeric(5,2) default 0,
  ceiling_amount numeric(15,2),
  ceiling_basis text,
  tax_deductible boolean default false,
  display_order int default 100,
  active boolean default true,
  created_at timestamptz default now()
);
create index if not exists idx_payroll_components_code on payroll_components(code);
create index if not exists idx_payroll_components_type on payroll_components(type);
alter table payroll_components enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_payroll_components') THEN
    CREATE POLICY "allow_all_payroll_components" ON payroll_components FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 2. Payroll component rates (taux par législation)
create table if not exists payroll_component_rates (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  component_id uuid not null references payroll_components(id) on delete cascade,
  legislation_pack text,
  rate_employer numeric(5,2) default 0,
  rate_employee numeric(5,2) default 0,
  ceiling_amount numeric(15,2),
  effective_date date not null default current_date,
  end_date date,
  created_at timestamptz default now()
);
create index if not exists idx_payroll_rates_component on payroll_component_rates(component_id);
alter table payroll_component_rates enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_payroll_component_rates') THEN
    CREATE POLICY "allow_all_payroll_component_rates" ON payroll_component_rates FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 3. Payroll templates (modèles de bulletins)
create table if not exists payroll_templates (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  name text not null,
  category text default 'standard' check (category in ('standard','cadre','non_cadre','apprenti','stagiaire','interim')),
  component_ids jsonb default '[]'::jsonb,
  description text,
  active boolean default true,
  created_at timestamptz default now()
);
create index if not exists idx_payroll_templates_name on payroll_templates(name);
alter table payroll_templates enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_payroll_templates') THEN
    CREATE POLICY "allow_all_payroll_templates" ON payroll_templates FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 4. Salary advances (acomptes)
create table if not exists salary_advances (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  employee_id uuid not null references employees(id) on delete cascade,
  amount numeric(15,2) not null default 0,
  advance_date date not null default current_date,
  deduction_month date,
  status text default 'pending' check (status in ('pending','deducted','cancelled')),
  notes text,
  created_at timestamptz default now()
);
create index if not exists idx_salary_advances_employee on salary_advances(employee_id);
create index if not exists idx_salary_advances_status on salary_advances(status);
alter table salary_advances enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_salary_advances') THEN
    CREATE POLICY "allow_all_salary_advances" ON salary_advances FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 5. Pay recalls (rappels rétroactifs)
create table if not exists pay_recalls (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  employee_id uuid not null references employees(id) on delete cascade,
  reference_period text not null,
  recall_amount numeric(15,2) not null default 0,
  reason text,
  status text default 'pending' check (status in ('pending','processed','cancelled')),
  processed_pay_run_id uuid,
  created_at timestamptz default now()
);
create index if not exists idx_pay_recalls_employee on pay_recalls(employee_id);
alter table pay_recalls enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_pay_recalls') THEN
    CREATE POLICY "allow_all_pay_recalls" ON pay_recalls FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 6. DSN declarations
create table if not exists dsn_declarations (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  period text not null,
  type text default 'mensuelle' check (type in ('mensuelle','arret','reprise','fin_contrat')),
  status text default 'draft' check (status in ('draft','generated','transmitted','accepted','rejected')),
  file_url text,
  generated_at timestamptz,
  transmitted_at timestamptz,
  response_code text,
  response_message text,
  created_at timestamptz default now()
);
create index if not exists idx_dsn_period on dsn_declarations(period);
create index if not exists idx_dsn_status on dsn_declarations(status);
alter table dsn_declarations enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_dsn_declarations') THEN
    CREATE POLICY "allow_all_dsn_declarations" ON dsn_declarations FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 7. DPAE (déclaration préalable embauche)
create table if not exists dpae_records (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  employee_id uuid not null references employees(id) on delete cascade,
  hire_date date not null,
  contract_type text,
  position text,
  status text default 'pending' check (status in ('pending','transmitted','accepted','rejected')),
  transmitted_at timestamptz,
  response_code text,
  created_at timestamptz default now()
);
create index if not exists idx_dpae_employee on dpae_records(employee_id);
create index if not exists idx_dpae_status on dpae_records(status);
alter table dpae_records enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_dpae_records') THEN
    CREATE POLICY "allow_all_dpae_records" ON dpae_records FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 8. Work hardship (pénibilité)
create table if not exists work_hardship (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  employee_id uuid not null references employees(id) on delete cascade,
  exposure_type text not null,
  exposure_level text check (exposure_level in ('low','medium','high')),
  start_date date,
  end_date date,
  points int default 0,
  notes text,
  created_at timestamptz default now()
);
create index if not exists idx_work_hardship_employee on work_hardship(employee_id);
alter table work_hardship enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_work_hardship') THEN
    CREATE POLICY "allow_all_work_hardship" ON work_hardship FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 9. Career history
create table if not exists career_history (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  employee_id uuid not null references employees(id) on delete cascade,
  position text,
  department text,
  salary numeric(15,2),
  start_date date not null,
  end_date date,
  change_type text check (change_type in ('hire','promotion','transfer','salary_change','departure')),
  notes text,
  created_at timestamptz default now()
);
create index if not exists idx_career_history_employee on career_history(employee_id);
create index if not exists idx_career_history_dates on career_history(start_date, end_date);
alter table career_history enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_career_history') THEN
    CREATE POLICY "allow_all_career_history" ON career_history FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 10. CPF account (compte personnel de formation)
create table if not exists cpf_accounts (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  employee_id uuid not null references employees(id) on delete cascade,
  balance_hours numeric(10,2) default 0,
  balance_amount numeric(15,2) default 0,
  history jsonb default '[]'::jsonb,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists idx_cpf_employee on cpf_accounts(employee_id);
alter table cpf_accounts enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_cpf_accounts') THEN
    CREATE POLICY "allow_all_cpf_accounts" ON cpf_accounts FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 11. Payroll archives (archivage chiffré)
create table if not exists payroll_archives (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  employee_id uuid references employees(id) on delete set null,
  period text not null,
  archive_type text check (archive_type in ('payslip','dsn','dpae','contract','other')),
  file_url text not null,
  file_encrypted boolean default true,
  retention_until date,
  created_at timestamptz default now()
);
create index if not exists idx_payroll_archives_employee on payroll_archives(employee_id);
create index if not exists idx_payroll_archives_period on payroll_archives(period);
alter table payroll_archives enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_payroll_archives') THEN
    CREATE POLICY "allow_all_payroll_archives" ON payroll_archives FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 12. Legal watch (veille juridique)
create table if not exists legal_watch (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  title text not null,
  category text,
  source text,
  summary text,
  content_url text,
  published_date date,
  relevance text check (relevance in ('info','important','critical')),
  read boolean default false,
  created_at timestamptz default now()
);
create index if not exists idx_legal_watch_date on legal_watch(published_date);
alter table legal_watch enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_legal_watch') THEN
    CREATE POLICY "allow_all_legal_watch" ON legal_watch FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 13. Employee documents (coffre-fort)
create table if not exists employee_documents (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  employee_id uuid not null references employees(id) on delete cascade,
  document_type text not null check (document_type in ('payslip','contract','dpae','dsn','certificate','other')),
  file_url text not null,
  file_name text,
  distributed_at timestamptz,
  acknowledged_at timestamptz,
  created_at timestamptz default now()
);
create index if not exists idx_employee_documents_employee on employee_documents(employee_id);
alter table employee_documents enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_employee_documents') THEN
    CREATE POLICY "allow_all_employee_documents" ON employee_documents FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 14. Expense reports (notes de frais)
create table if not exists expense_reports (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  employee_id uuid not null references employees(id) on delete cascade,
  number text not null,
  period text,
  total_amount numeric(15,2) default 0,
  total_vat numeric(15,2) default 0,
  status text default 'draft' check (status in ('draft','submitted','approved','rejected','reimbursed')),
  submitted_at timestamptz,
  approved_by text,
  approved_at timestamptz,
  notes text,
  created_at timestamptz default now()
);
create index if not exists idx_expense_reports_employee on expense_reports(employee_id);
create index if not exists idx_expense_reports_status on expense_reports(status);
alter table expense_reports enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_expense_reports') THEN
    CREATE POLICY "allow_all_expense_reports" ON expense_reports FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 15. Expense report lines
create table if not exists expense_report_lines (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  expense_report_id uuid not null references expense_reports(id) on delete cascade,
  date date not null,
  description text not null,
  category text,
  amount numeric(15,2) not null default 0,
  vat_rate numeric(5,2) default 0,
  vat_amount numeric(15,2) default 0,
  receipt_url text,
  created_at timestamptz default now()
);
create index if not exists idx_expense_lines_report on expense_report_lines(expense_report_id);
alter table expense_report_lines enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_expense_report_lines') THEN
    CREATE POLICY "allow_all_expense_report_lines" ON expense_report_lines FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 16. Interviews (entretiens & objectifs)
create table if not exists interviews (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  employee_id uuid not null references employees(id) on delete cascade,
  type text default 'annual' check (type in ('annual','mid_year','professional','exit','other')),
  scheduled_date date,
  conducted_at timestamptz,
  conducted_by text,
  objectives text,
  feedback text,
  rating int check (rating between 1 and 5),
  status text default 'scheduled' check (status in ('scheduled','conducted','cancelled')),
  created_at timestamptz default now()
);
create index if not exists idx_interviews_employee on interviews(employee_id);
alter table interviews enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_interviews') THEN
    CREATE POLICY "allow_all_interviews" ON interviews FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
