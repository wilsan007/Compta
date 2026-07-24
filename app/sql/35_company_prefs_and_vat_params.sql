-- Migration: Company preferences and VAT parameters
-- Items #48 and #49 from PLAN-IMPLEMENTATION-FINAL-SAGE100-COMPTA.md

-- Add company preferences fields
ALTER TABLE company_settings ADD COLUMN IF NOT EXISTS saisie_negative boolean DEFAULT false;
ALTER TABLE company_settings ADD COLUMN IF NOT EXISTS multi_currency boolean DEFAULT false;
ALTER TABLE company_settings ADD COLUMN IF NOT EXISTS show_quantities boolean DEFAULT false;

-- Add VAT parameters fields
ALTER TABLE company_settings ADD COLUMN IF NOT EXISTS vat_regime text DEFAULT 'CA3';
ALTER TABLE company_settings ADD COLUMN IF NOT EXISTS vat_periodicity text DEFAULT 'monthly';
