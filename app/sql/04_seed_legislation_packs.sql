-- ============================================
-- 04_seed_legislation_packs.sql
-- Adds 14 new legislation packs to the existing FR + SYSCOHADA packs.
-- Run AFTER legislation_packs_migration.sql
-- ============================================

-- ============================================
-- UK — United Kingdom (UK GAAP / GBP)
-- ============================================
insert into legislation_packs (code, name, country_code, country_name, accounting_standard, currency, currency_decimals, date_format, locale, fiscal_year_start, tax_id_label, tax_id_secondary_label, is_default, active)
values ('UK', 'United Kingdom — UK GAAP', 'GB', 'United Kingdom', 'UK_GAAP', 'GBP', 2, 'DD/MM/YYYY', 'en-GB', '04-06', 'VAT Reg. No.', 'Companies House No.', false, true)
on conflict (code) do update set
  name = excluded.name, country_code = excluded.country_code, country_name = excluded.country_name,
  accounting_standard = excluded.accounting_standard, currency = excluded.currency,
  tax_id_label = excluded.tax_id_label, tax_id_secondary_label = excluded.tax_id_secondary_label,
  updated_at = now();

insert into tax_rates (pack_code, name, category, rate, is_default, effective_from)
values
  ('UK', 'Standard rate', 'standard', 20.000, true, '2011-01-04'),
  ('UK', 'Reduced rate', 'reduced', 5.000, false, '2011-01-04'),
  ('UK', 'Zero rate', 'zero', 0.000, false, '2011-01-04')
on conflict do nothing;

-- ============================================
-- US — United States (US GAAP / USD)
-- ============================================
insert into legislation_packs (code, name, country_code, country_name, accounting_standard, currency, currency_decimals, date_format, locale, fiscal_year_start, tax_id_label, tax_id_secondary_label, is_default, active)
values ('US', 'United States — US GAAP', 'US', 'United States', 'US_GAAP', 'USD', 2, 'MM/DD/YYYY', 'en-US', '01-01', 'EIN', 'State Tax ID', false, true)
on conflict (code) do update set
  name = excluded.name, country_code = excluded.country_code, country_name = excluded.country_name,
  accounting_standard = excluded.accounting_standard, currency = excluded.currency,
  tax_id_label = excluded.tax_id_label, tax_id_secondary_label = excluded.tax_id_secondary_label,
  updated_at = now();

insert into tax_rates (pack_code, name, category, rate, is_default, effective_from)
values
  ('US', 'No VAT (Sales Tax handled locally)', 'zero', 0.000, true, '1900-01-01')
on conflict do nothing;

-- ============================================
-- MA — Maroc (CGNC / MAD)
-- ============================================
insert into legislation_packs (code, name, country_code, country_name, accounting_standard, currency, currency_decimals, date_format, locale, fiscal_year_start, tax_id_label, tax_id_secondary_label, is_default, active)
values ('MA', 'Maroc — Code Général de Normalisation Comptable', 'MA', 'Maroc', 'CGNC', 'MAD', 2, 'DD/MM/YYYY', 'fr-MA', '01-01', 'N° IF', 'RC', false, true)
on conflict (code) do update set
  name = excluded.name, country_code = excluded.country_code, country_name = excluded.country_name,
  accounting_standard = excluded.accounting_standard, currency = excluded.currency,
  tax_id_label = excluded.tax_id_label, tax_id_secondary_label = excluded.tax_id_secondary_label,
  updated_at = now();

insert into tax_rates (pack_code, name, category, rate, is_default, effective_from)
values
  ('MA', 'TVA normal', 'standard', 20.000, true, '2014-01-01'),
  ('MA', 'TVA réduit', 'reduced', 14.000, false, '2014-01-01'),
  ('MA', 'TVA réduit (eau, électricité)', 'super_reduced', 7.000, false, '2014-01-01'),
  ('MA', 'Exonéré / 0 %', 'zero', 0.000, false, '2014-01-01')
on conflict do nothing;

-- ============================================
-- DZ — Algérie (SCF / DZD)
-- ============================================
insert into legislation_packs (code, name, country_code, country_name, accounting_standard, currency, currency_decimals, date_format, locale, fiscal_year_start, tax_id_label, tax_id_secondary_label, is_default, active)
values ('DZ', 'Algérie — Système Comptable Financier', 'DZ', 'Algérie', 'SCF', 'DZD', 2, 'DD/MM/YYYY', 'ar-DZ', '01-01', 'N° IF', 'RC', false, true)
on conflict (code) do update set
  name = excluded.name, country_code = excluded.country_code, country_name = excluded.country_name,
  accounting_standard = excluded.accounting_standard, currency = excluded.currency,
  tax_id_label = excluded.tax_id_label, tax_id_secondary_label = excluded.tax_id_secondary_label,
  updated_at = now();

insert into tax_rates (pack_code, name, category, rate, is_default, effective_from)
values
  ('DZ', 'TVA normal', 'standard', 19.000, true, '2010-01-01'),
  ('DZ', 'TVA réduit', 'reduced', 9.000, false, '2010-01-01'),
  ('DZ', 'Exonéré / 0 %', 'zero', 0.000, false, '2010-01-01')
on conflict do nothing;

-- ============================================
-- TN — Tunisie (NCT / TND)
-- ============================================
insert into legislation_packs (code, name, country_code, country_name, accounting_standard, currency, currency_decimals, date_format, locale, fiscal_year_start, tax_id_label, tax_id_secondary_label, is_default, active)
values ('TN', 'Tunisie — Normes Comptables Tunisiennes', 'TN', 'Tunisie', 'NCT', 'TND', 3, 'DD/MM/YYYY', 'ar-TN', '01-01', 'Matricule fiscale', 'RC', false, true)
on conflict (code) do update set
  name = excluded.name, country_code = excluded.country_code, country_name = excluded.country_name,
  accounting_standard = excluded.accounting_standard, currency = excluded.currency,
  tax_id_label = excluded.tax_id_label, tax_id_secondary_label = excluded.tax_id_secondary_label,
  updated_at = now();

insert into tax_rates (pack_code, name, category, rate, is_default, effective_from)
values
  ('TN', 'TVA normal', 'standard', 19.000, true, '2018-01-01'),
  ('TN', 'TVA réduit', 'reduced', 13.000, false, '2018-01-01'),
  ('TN', 'TVA réduit (produits de première nécessité)', 'super_reduced', 7.000, false, '2018-01-01'),
  ('TN', 'Exonéré / 0 %', 'zero', 0.000, false, '2018-01-01')
on conflict do nothing;

-- ============================================
-- SN — Sénégal (SYSCOHADA / XOF)
-- ============================================
insert into legislation_packs (code, name, country_code, country_name, accounting_standard, currency, currency_decimals, date_format, locale, fiscal_year_start, tax_id_label, tax_id_secondary_label, is_default, active)
values ('SN', 'Sénégal — SYSCOHADA révisé', 'SN', 'Sénégal', 'SYSCOHADA', 'XOF', 0, 'DD/MM/YYYY', 'fr-SN', '01-01', 'N° IFU', 'RCCM', false, true)
on conflict (code) do update set
  name = excluded.name, country_code = excluded.country_code, country_name = excluded.country_name,
  accounting_standard = excluded.accounting_standard, currency = excluded.currency,
  tax_id_label = excluded.tax_id_label, tax_id_secondary_label = excluded.tax_id_secondary_label,
  updated_at = now();

insert into tax_rates (pack_code, name, category, rate, is_default, effective_from)
values
  ('SN', 'TVA standard', 'standard', 18.000, true, '2000-01-01'),
  ('SN', 'TVA réduite', 'reduced', 10.000, false, '2000-01-01'),
  ('SN', 'Exonéré / 0 %', 'zero', 0.000, false, '2000-01-01')
on conflict do nothing;

-- ============================================
-- CI — Côte d'Ivoire (SYSCOHADA / XOF)
-- ============================================
insert into legislation_packs (code, name, country_code, country_name, accounting_standard, currency, currency_decimals, date_format, locale, fiscal_year_start, tax_id_label, tax_id_secondary_label, is_default, active)
values ('CI', 'Côte d''Ivoire — SYSCOHADA révisé', 'CI', 'Côte d''Ivoire', 'SYSCOHADA', 'XOF', 0, 'DD/MM/YYYY', 'fr-CI', '01-01', 'N° IFU', 'RCCM', false, true)
on conflict (code) do update set
  name = excluded.name, country_code = excluded.country_code, country_name = excluded.country_name,
  accounting_standard = excluded.accounting_standard, currency = excluded.currency,
  tax_id_label = excluded.tax_id_label, tax_id_secondary_label = excluded.tax_id_secondary_label,
  updated_at = now();

insert into tax_rates (pack_code, name, category, rate, is_default, effective_from)
values
  ('CI', 'TVA standard', 'standard', 18.000, true, '2000-01-01'),
  ('CI', 'TVA réduite', 'reduced', 9.000, false, '2000-01-01'),
  ('CI', 'Exonéré / 0 %', 'zero', 0.000, false, '2000-01-01')
on conflict do nothing;

-- ============================================
-- CM — Cameroun (SYSCOHADA / XAF)
-- ============================================
insert into legislation_packs (code, name, country_code, country_name, accounting_standard, currency, currency_decimals, date_format, locale, fiscal_year_start, tax_id_label, tax_id_secondary_label, is_default, active)
values ('CM', 'Cameroun — SYSCOHADA révisé', 'CM', 'Cameroun', 'SYSCOHADA', 'XAF', 0, 'DD/MM/YYYY', 'fr-CM', '01-01', 'N° IFU', 'RCCM', false, true)
on conflict (code) do update set
  name = excluded.name, country_code = excluded.country_code, country_name = excluded.country_name,
  accounting_standard = excluded.accounting_standard, currency = excluded.currency,
  tax_id_label = excluded.tax_id_label, tax_id_secondary_label = excluded.tax_id_secondary_label,
  updated_at = now();

insert into tax_rates (pack_code, name, category, rate, is_default, effective_from)
values
  ('CM', 'TVA standard', 'standard', 19.250, true, '2000-01-01'),
  ('CM', 'TVA réduite', 'reduced', 9.700, false, '2000-01-01'),
  ('CM', 'Exonéré / 0 %', 'zero', 0.000, false, '2000-01-01')
on conflict do nothing;

-- ============================================
-- DE — Allemagne (HGB / EUR)
-- ============================================
insert into legislation_packs (code, name, country_code, country_name, accounting_standard, currency, currency_decimals, date_format, locale, fiscal_year_start, tax_id_label, tax_id_secondary_label, is_default, active)
values ('DE', 'Deutschland — HGB', 'DE', 'Deutschland', 'HGB', 'EUR', 2, 'DD.MM.YYYY', 'de-DE', '01-01', 'USt-IdNr.', 'HRB', false, true)
on conflict (code) do update set
  name = excluded.name, country_code = excluded.country_code, country_name = excluded.country_name,
  accounting_standard = excluded.accounting_standard, currency = excluded.currency,
  tax_id_label = excluded.tax_id_label, tax_id_secondary_label = excluded.tax_id_secondary_label,
  updated_at = now();

insert into tax_rates (pack_code, name, category, rate, is_default, effective_from)
values
  ('DE', 'Regelsteuersatz', 'standard', 19.000, true, '2007-01-01'),
  ('DE', 'Ermäßigter Steuersatz', 'reduced', 7.000, false, '2007-01-01'),
  ('DE', 'Steuerfrei / 0 %', 'zero', 0.000, false, '2007-01-01')
on conflict do nothing;

-- ============================================
-- ES — España (PGC / EUR)
-- ============================================
insert into legislation_packs (code, name, country_code, country_name, accounting_standard, currency, currency_decimals, date_format, locale, fiscal_year_start, tax_id_label, tax_id_secondary_label, is_default, active)
values ('ES', 'España — Plan General Contable', 'ES', 'España', 'PGC', 'EUR', 2, 'DD/MM/YYYY', 'es-ES', '01-01', 'NIF', 'CIF', false, true)
on conflict (code) do update set
  name = excluded.name, country_code = excluded.country_code, country_name = excluded.country_name,
  accounting_standard = excluded.accounting_standard, currency = excluded.currency,
  tax_id_label = excluded.tax_id_label, tax_id_secondary_label = excluded.tax_id_secondary_label,
  updated_at = now();

insert into tax_rates (pack_code, name, category, rate, is_default, effective_from)
values
  ('ES', 'Tipo general', 'standard', 21.000, true, '2012-09-01'),
  ('ES', 'Tipo reducido', 'reduced', 10.000, false, '2012-09-01'),
  ('ES', 'Tipo superreducido', 'super_reduced', 4.000, false, '2012-09-01'),
  ('ES', 'Exento / 0 %', 'zero', 0.000, false, '2012-09-01')
on conflict do nothing;

-- ============================================
-- IT — Italia (OIC / EUR)
-- ============================================
insert into legislation_packs (code, name, country_code, country_name, accounting_standard, currency, currency_decimals, date_format, locale, fiscal_year_start, tax_id_label, tax_id_secondary_label, is_default, active)
values ('IT', 'Italia — Organismo Italiano di Contabilità', 'IT', 'Italia', 'OIC', 'EUR', 2, 'DD/MM/YYYY', 'it-IT', '01-01', 'Partita IVA', 'Codice Fiscale', false, true)
on conflict (code) do update set
  name = excluded.name, country_code = excluded.country_code, country_name = excluded.country_name,
  accounting_standard = excluded.accounting_standard, currency = excluded.currency,
  tax_id_label = excluded.tax_id_label, tax_id_secondary_label = excluded.tax_id_secondary_label,
  updated_at = now();

insert into tax_rates (pack_code, name, category, rate, is_default, effective_from)
values
  ('IT', 'Aliquota ordinaria', 'standard', 22.000, true, '2013-10-01'),
  ('IT', 'Aliquota ridotta', 'reduced', 10.000, false, '2013-10-01'),
  ('IT', 'Aliquota super ridotta', 'super_reduced', 4.000, false, '2013-10-01'),
  ('IT', 'Esente / 0 %', 'zero', 0.000, false, '2013-10-01')
on conflict do nothing;

-- ============================================
-- SA — Saudi Arabia (SOCPA / SAR)
-- ============================================
insert into legislation_packs (code, name, country_code, country_name, accounting_standard, currency, currency_decimals, date_format, locale, fiscal_year_start, tax_id_label, tax_id_secondary_label, is_default, active)
values ('SA', 'المملكة العربية السعودية — SOCPA', 'SA', 'المملكة العربية السعودية', 'SOCPA', 'SAR', 2, 'DD/MM/YYYY', 'ar-SA', '01-01', 'VAT Reg. No.', 'CR No.', false, true)
on conflict (code) do update set
  name = excluded.name, country_code = excluded.country_code, country_name = excluded.country_name,
  accounting_standard = excluded.accounting_standard, currency = excluded.currency,
  tax_id_label = excluded.tax_id_label, tax_id_secondary_label = excluded.tax_id_secondary_label,
  updated_at = now();

insert into tax_rates (pack_code, name, category, rate, is_default, effective_from)
values
  ('SA', 'Standard rate', 'standard', 15.000, true, '2020-07-01'),
  ('SA', 'Zero rate', 'zero', 0.000, false, '2018-01-01')
on conflict do nothing;

-- ============================================
-- AE — United Arab Emirates (IFRS / AED)
-- ============================================
insert into legislation_packs (code, name, country_code, country_name, accounting_standard, currency, currency_decimals, date_format, locale, fiscal_year_start, tax_id_label, tax_id_secondary_label, is_default, active)
values ('AE', 'United Arab Emirates — IFRS', 'AE', 'United Arab Emirates', 'IFRS', 'AED', 2, 'DD/MM/YYYY', 'ar-AE', '01-01', 'TRN', 'Trade License No.', false, true)
on conflict (code) do update set
  name = excluded.name, country_code = excluded.country_code, country_name = excluded.country_name,
  accounting_standard = excluded.accounting_standard, currency = excluded.currency,
  tax_id_label = excluded.tax_id_label, tax_id_secondary_label = excluded.tax_id_secondary_label,
  updated_at = now();

insert into tax_rates (pack_code, name, category, rate, is_default, effective_from)
values
  ('AE', 'Standard rate', 'standard', 5.000, true, '2018-01-01'),
  ('AE', 'Zero rate', 'zero', 0.000, false, '2018-01-01')
on conflict do nothing;

-- ============================================
-- EG — Egypt (EAS / EGP)
-- ============================================
insert into legislation_packs (code, name, country_code, country_name, accounting_standard, currency, currency_decimals, date_format, locale, fiscal_year_start, tax_id_label, tax_id_secondary_label, is_default, active)
values ('EG', 'مصر — Egyptian Accounting Standards', 'EG', 'مصر', 'EAS', 'EGP', 2, 'DD/MM/YYYY', 'ar-EG', '01-01', 'Tax Reg. No.', 'Commercial Reg. No.', false, true)
on conflict (code) do update set
  name = excluded.name, country_code = excluded.country_code, country_name = excluded.country_name,
  accounting_standard = excluded.accounting_standard, currency = excluded.currency,
  tax_id_label = excluded.tax_id_label, tax_id_secondary_label = excluded.tax_id_secondary_label,
  updated_at = now();

insert into tax_rates (pack_code, name, category, rate, is_default, effective_from)
values
  ('EG', 'Standard rate', 'standard', 14.000, true, '2020-07-01'),
  ('EG', 'Zero rate', 'zero', 0.000, false, '2000-01-01')
on conflict do nothing;

-- ============================================
-- DONE — 16 packs total (FR + SYSCOHADA + 14 new)
-- ============================================
