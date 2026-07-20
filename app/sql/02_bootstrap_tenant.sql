-- ============================================
-- BOOTSTRAP TENANT REFERENCE DATA
-- Run this in Supabase Dashboard > SQL Editor
-- ============================================
-- Creates the reference data every new company needs so the app is
-- immediately usable after signup:
--   - Chart of accounts (copied from a clean template tenant, if present)
--   - Standard journals (VT, AC, BQ, CA, OD, AN)
--   - Default currency (EUR)
--   - Current fiscal year + 12 monthly periods
--   - A company_settings row (from the tenant record)
--
-- It is idempotent-ish: it only seeds what is missing, so calling it twice
-- will not create duplicates.
--
-- PREREQUISITES:
--   - multi_tenant_migration.sql (tenant_id columns) must be run
--   - 01_fix_tenant_unique_constraints.sql must be run (per-tenant uniqueness)
-- ============================================

CREATE OR REPLACE FUNCTION bootstrap_tenant(p_tenant_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_template_tenant uuid := '00000000-0000-0000-0000-000000000001';
  v_tenant record;
  v_year int := EXTRACT(YEAR FROM CURRENT_DATE)::int;
  v_fy_id uuid;
  v_month int;
  v_period_start date;
  v_period_end date;
  v_labels text[] := ARRAY['Janvier','Fevrier','Mars','Avril','Mai','Juin','Juillet','Aout','Septembre','Octobre','Novembre','Decembre'];
BEGIN
  SELECT * INTO v_tenant FROM tenants WHERE id = p_tenant_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tenant % not found', p_tenant_id;
  END IF;

  -- --------------------------------------------
  -- 1. CHART OF ACCOUNTS (copy from template if this tenant has none)
  -- --------------------------------------------
  IF NOT EXISTS (SELECT 1 FROM chart_accounts WHERE tenant_id = p_tenant_id) THEN
    INSERT INTO chart_accounts (code, name, type, balance, vat_rate, description, tenant_id)
    SELECT code, name, type, 0, vat_rate, description, p_tenant_id
    FROM chart_accounts
    WHERE tenant_id = v_template_tenant
    ON CONFLICT (tenant_id, code) DO NOTHING;
  END IF;

  -- --------------------------------------------
  -- 2. STANDARD JOURNALS
  -- --------------------------------------------
  INSERT INTO journals (code, name, type, account_counterpart, status, locked, tenant_id)
  VALUES
    ('VT', 'Journal des ventes',        'sale',     '411000', 'active', false, p_tenant_id),
    ('AC', 'Journal des achats',        'purchase', '401000', 'active', false, p_tenant_id),
    ('BQ', 'Journal de banque',         'bank',     '512000', 'active', false, p_tenant_id),
    ('CA', 'Journal de caisse',         'cash',     '530000', 'active', false, p_tenant_id),
    ('OD', 'Operations diverses',       'general',  NULL,     'active', false, p_tenant_id),
    ('AN', 'A-nouveaux',                'general',  NULL,     'active', false, p_tenant_id)
  ON CONFLICT (tenant_id, code) DO NOTHING;

  -- --------------------------------------------
  -- 3. DEFAULT CURRENCIES
  -- --------------------------------------------
  INSERT INTO currencies (code, name, symbol, exchange_rate, tenant_id)
  VALUES
    ('EUR', 'Euro',            '€', 1.0,    p_tenant_id),
    ('USD', 'Dollar US',       '$', 1.08,   p_tenant_id),
    ('GBP', 'Livre Sterling',  '£', 0.85,   p_tenant_id)
  ON CONFLICT (tenant_id, code) DO NOTHING;

  -- --------------------------------------------
  -- 4. FISCAL YEAR + 12 MONTHLY PERIODS (current year)
  -- --------------------------------------------
  IF NOT EXISTS (SELECT 1 FROM fiscal_years WHERE tenant_id = p_tenant_id AND code = 'FY' || v_year) THEN
    INSERT INTO fiscal_years (code, start_date, end_date, status, tenant_id)
    VALUES ('FY' || v_year, make_date(v_year, 1, 1), make_date(v_year, 12, 31), 'open', p_tenant_id)
    RETURNING id INTO v_fy_id;

    FOR v_month IN 1 .. 12 LOOP
      v_period_start := make_date(v_year, v_month, 1);
      v_period_end := (v_period_start + INTERVAL '1 month - 1 day')::date;
      INSERT INTO fiscal_periods (fiscal_year_id, period_number, period_label, start_date, end_date, status, tenant_id)
      VALUES (v_fy_id, v_month, v_labels[v_month] || ' ' || v_year, v_period_start, v_period_end, 'open', p_tenant_id);
    END LOOP;
  END IF;

  -- --------------------------------------------
  -- 5. COMPANY SETTINGS (from the tenant record)
  -- --------------------------------------------
  IF NOT EXISTS (SELECT 1 FROM company_settings WHERE tenant_id = p_tenant_id) THEN
    INSERT INTO company_settings (name, legal_name, vat_number, siret, address, city, postal_code, country, currency, fiscal_year_start, tenant_id)
    VALUES (
      v_tenant.name,
      COALESCE(v_tenant.legal_name, v_tenant.name),
      v_tenant.vat_number,
      v_tenant.siret,
      v_tenant.address,
      v_tenant.city,
      v_tenant.postal_code,
      COALESCE(v_tenant.country, 'France'),
      COALESCE(v_tenant.currency, 'EUR'),
      '01-01',
      p_tenant_id
    );
  END IF;

END;
$$;

-- Allow authenticated users to call it (RLS still applies to the tables it writes,
-- but SECURITY DEFINER runs as the function owner so seeding works during onboarding).
GRANT EXECUTE ON FUNCTION bootstrap_tenant(uuid) TO authenticated;

-- ============================================
-- DONE
-- ============================================
-- Call from the app right after creating a tenant:
--   await supabase.rpc('bootstrap_tenant', { p_tenant_id: tenant.id })
-- ============================================
