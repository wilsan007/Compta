-- ============================================
-- TENANT ENABLED MODULES MIGRATION
-- ============================================
-- Adds an `enabled_modules` column to the `tenants` table
-- so each tenant can choose which modules (services) to use.
-- The column is a jsonb array of module IDs, e.g.:
--   ["home","accounting","commercial","treasury","system"]
-- ============================================

-- 1. Add enabled_modules column (nullable for backward compatibility)
ALTER TABLE tenants
  ADD COLUMN IF NOT EXISTS enabled_modules jsonb DEFAULT '["home","accounting","commercial","treasury","stock","production","hr","dashboards","reporting","system"]'::jsonb;

-- 2. Backfill existing tenants that have NULL enabled_modules
UPDATE tenants
  SET enabled_modules = '["home","accounting","commercial","treasury","stock","production","hr","dashboards","reporting","system"]'::jsonb
  WHERE enabled_modules IS NULL;

-- 3. Make the column NOT NULL
ALTER TABLE tenants
  ALTER COLUMN enabled_modules SET NOT NULL;

-- 4. Add an index for quick lookups
CREATE INDEX IF NOT EXISTS idx_tenants_enabled_modules ON tenants USING gin (enabled_modules);
