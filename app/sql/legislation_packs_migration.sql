-- ============================================
-- LEGISLATION PACKS MIGRATION
-- Run this in Supabase Dashboard > SQL Editor
-- ============================================
-- Goal: make the app adapt to each country's legislation.
--
-- Design principles:
--  1. Legislation is a GLOBAL, SHARED reference (not per-tenant). All tenants
--     read the same packs. A tenant only *points* to a pack.
--  2. Legislation is VERSIONED BY EFFECTIVE DATE. When a country changes a VAT
--     rate, we INSERT a new tax_rates row with a new effective_from and close
--     the old one (effective_to). We NEVER mutate historical rates, so past
--     documents stay correct.
--  3. Documents already snapshot the applied rate (invoice_lines.vat_rate), so
--     changing legislation never rewrites history.
-- ============================================

create extension if not exists "uuid-ossp";

-- ============================================
-- 1. LEGISLATION PACKS (global reference)
-- ============================================
-- One row per country / accounting standard.
create table if not exists legislation_packs (
  code text primary key,                       -- e.g. 'FR', 'SYSCOHADA', 'FR-2024'
  name text not null,                           -- human label
  country_code text not null,                   -- ISO-3166 alpha-2, e.g. 'FR', 'CI'
  country_name text not null,
  accounting_standard text not null,            -- 'PCG', 'SYSCOHADA', 'IFRS', 'US_GAAP'
  currency text not null default 'EUR',
  currency_decimals int not null default 2,
  date_format text not null default 'DD/MM/YYYY',
  locale text not null default 'fr-FR',
  fiscal_year_start text not null default '01-01', -- MM-DD
  tax_id_label text not null default 'N° TVA',  -- label for primary fiscal id
  tax_id_secondary_label text,                  -- e.g. 'SIRET', 'RCCM', 'EIN'
  is_default boolean not null default false,    -- fallback pack for new tenants
  active boolean not null default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table legislation_packs enable row level security;
-- Reference data: readable by any authenticated user; writes via service role only.
do $$ begin
  if not exists (select 1 from pg_policies where policyname = 'legislation_packs_read') then
    create policy "legislation_packs_read" on legislation_packs for select using (true);
  end if;
end $$;

-- ============================================
-- 2. TAX RATES (global reference, versioned by date)
-- ============================================
create table if not exists tax_rates (
  id uuid primary key default uuid_generate_v4(),
  pack_code text not null references legislation_packs(code) on delete cascade,
  name text not null,                           -- 'Taux normal', 'Taux réduit', ...
  category text not null check (category in ('standard', 'intermediate', 'reduced', 'super_reduced', 'zero', 'exempt')),
  rate numeric(6,3) not null,                   -- percentage, e.g. 20.000
  account_code text,                            -- default VAT collection account
  is_default boolean not null default false,    -- default rate for its pack
  effective_from date not null default '1900-01-01',
  effective_to date,                            -- null = still in force
  created_at timestamptz default now()
);

create index if not exists idx_tax_rates_pack on tax_rates(pack_code);
create index if not exists idx_tax_rates_effective on tax_rates(pack_code, effective_from, effective_to);

alter table tax_rates enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where policyname = 'tax_rates_read') then
    create policy "tax_rates_read" on tax_rates for select using (true);
  end if;
end $$;

-- ============================================
-- 3. CHART OF ACCOUNTS TEMPLATES (global reference)
-- ============================================
-- Default plan comptable per accounting standard, copied into a tenant on setup.
create table if not exists chart_account_templates (
  id uuid primary key default uuid_generate_v4(),
  pack_code text not null references legislation_packs(code) on delete cascade,
  code text not null,
  name text not null,
  type text not null check (type in ('asset', 'liability', 'equity', 'income', 'expense')),
  vat_rate text,
  parent_code text,
  sort_order int default 0,
  created_at timestamptz default now(),
  unique (pack_code, code)
);

create index if not exists idx_chart_templates_pack on chart_account_templates(pack_code);

alter table chart_account_templates enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where policyname = 'chart_templates_read') then
    create policy "chart_templates_read" on chart_account_templates for select using (true);
  end if;
end $$;

-- ============================================
-- 4. LINK TENANTS TO A LEGISLATION PACK
-- ============================================
-- The tenant *points* to a pack; it does not copy its rates.
alter table company_settings
  add column if not exists country_code text,
  add column if not exists legislation_pack_code text references legislation_packs(code);

alter table tenants
  add column if not exists country_code text,
  add column if not exists legislation_pack_code text references legislation_packs(code);

-- ============================================
-- 5. SEED: FRANCE (PCG / EUR)
-- ============================================
insert into legislation_packs (code, name, country_code, country_name, accounting_standard, currency, currency_decimals, date_format, locale, fiscal_year_start, tax_id_label, tax_id_secondary_label, is_default, active)
values ('FR', 'France — Plan Comptable Général', 'FR', 'France', 'PCG', 'EUR', 2, 'DD/MM/YYYY', 'fr-FR', '01-01', 'N° TVA intracom.', 'SIRET', true, true)
on conflict (code) do update set
  name = excluded.name, country_code = excluded.country_code, country_name = excluded.country_name,
  accounting_standard = excluded.accounting_standard, currency = excluded.currency,
  tax_id_label = excluded.tax_id_label, tax_id_secondary_label = excluded.tax_id_secondary_label,
  is_default = excluded.is_default, updated_at = now();

-- France VAT rates (current, in force since 2014-01-01)
insert into tax_rates (pack_code, name, category, rate, account_code, is_default, effective_from)
values
  ('FR', 'Taux normal', 'standard', 20.000, '44571', true, '2014-01-01'),
  ('FR', 'Taux intermédiaire', 'intermediate', 10.000, '44571', false, '2014-01-01'),
  ('FR', 'Taux réduit', 'reduced', 5.500, '44571', false, '2014-01-01'),
  ('FR', 'Taux particulier', 'super_reduced', 2.100, '44571', false, '2014-01-01'),
  ('FR', 'Exonéré / 0 %', 'zero', 0.000, null, false, '2014-01-01')
on conflict do nothing;

-- ============================================
-- 6. SEED: SYSCOHADA (OHADA / XOF) — test second country
-- ============================================
insert into legislation_packs (code, name, country_code, country_name, accounting_standard, currency, currency_decimals, date_format, locale, fiscal_year_start, tax_id_label, tax_id_secondary_label, is_default, active)
values ('SYSCOHADA', 'OHADA — SYSCOHADA révisé', 'CI', 'Zone OHADA', 'SYSCOHADA', 'XOF', 0, 'DD/MM/YYYY', 'fr-FR', '01-01', 'N° IFU', 'RCCM', false, true)
on conflict (code) do update set
  name = excluded.name, currency = excluded.currency, currency_decimals = excluded.currency_decimals,
  tax_id_label = excluded.tax_id_label, tax_id_secondary_label = excluded.tax_id_secondary_label,
  updated_at = now();

insert into tax_rates (pack_code, name, category, rate, is_default, effective_from)
values
  ('SYSCOHADA', 'TVA standard', 'standard', 18.000, true, '2000-01-01'),
  ('SYSCOHADA', 'TVA réduite', 'reduced', 9.000, false, '2000-01-01'),
  ('SYSCOHADA', 'Exonéré / 0 %', 'zero', 0.000, false, '2000-01-01')
on conflict do nothing;

-- ============================================
-- 7. BACKFILL EXISTING TENANTS -> FRANCE
-- ============================================
update company_settings
  set legislation_pack_code = 'FR', country_code = 'FR'
  where legislation_pack_code is null;

update tenants
  set legislation_pack_code = 'FR', country_code = 'FR'
  where legislation_pack_code is null;

-- ============================================
-- DONE
-- ============================================
-- To add a new country: insert a legislation_packs row + its tax_rates.
-- To update a VAT rate: INSERT a new tax_rates row with effective_from = law date
--   and set effective_to on the previous row. Never edit historical rates.
-- ============================================
