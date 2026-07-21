-- ============================================
-- THIRD PARTY STATISTICAL FIELDS
-- ============================================
-- Adds legal and statistical fields to
-- customers and suppliers tables
-- ============================================

ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS legal_form text,
  ADD COLUMN IF NOT EXISTS ape_code text,
  ADD COLUMN IF NOT EXISTS naf_code text,
  ADD COLUMN IF NOT EXISTS employee_count_range text,
  ADD COLUMN IF NOT EXISTS revenue_range text,
  ADD COLUMN IF NOT EXISTS payment_delay_avg int,
  ADD COLUMN IF NOT EXISTS siret text;

ALTER TABLE suppliers
  ADD COLUMN IF NOT EXISTS legal_form text,
  ADD COLUMN IF NOT EXISTS ape_code text,
  ADD COLUMN IF NOT EXISTS naf_code text,
  ADD COLUMN IF NOT EXISTS employee_count_range text,
  ADD COLUMN IF NOT EXISTS revenue_range text,
  ADD COLUMN IF NOT EXISTS payment_delay_avg int,
  ADD COLUMN IF NOT EXISTS siret text;
