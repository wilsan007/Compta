-- ============================================
-- PHASES 1.17-1.22: RGPD, IAS-IFRS, SOLDE PROGRESSIF,
-- JOURNAL ACCESS CONTROL, 10 FISCAL YEARS, FISCAL BACKUP
-- ============================================

-- Phase 1.17: RGPD — personal data retention settings
ALTER TABLE company_settings
  ADD COLUMN IF NOT EXISTS gdpr_enabled boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS gdpr_retention_years int DEFAULT 10,
  ADD COLUMN IF NOT EXISTS gdpr_anonymize_after boolean DEFAULT true;

-- Phase 1.18: IAS-IFRS — accounting standard options
ALTER TABLE company_settings
  ADD COLUMN IF NOT EXISTS accounting_standard text DEFAULT 'french_pcga'
  CHECK (accounting_standard IN ('french_pcga', 'ias_ifrs', 'french_pcg'));

-- Phase 1.20: Journal access control
ALTER TABLE journals
  ADD COLUMN IF NOT EXISTS access_level text DEFAULT 'all'
  CHECK (access_level IN ('all', 'restricted', 'admin_only'));

-- Phase 1.21: Allow up to 10 fiscal years (no schema change needed,
-- just ensure the fiscal_years table can hold multiple years)
-- Already supported by existing schema.

-- Phase 1.22: Fiscal backup tracking
CREATE TABLE IF NOT EXISTS fiscal_backups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  fiscal_year_id uuid,
  backup_type text NOT NULL DEFAULT 'manual',
  status text NOT NULL DEFAULT 'pending',
  file_url text,
  file_size bigint,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_fiscal_backups_tenant ON fiscal_backups(tenant_id);
CREATE INDEX IF NOT EXISTS idx_fiscal_backups_fiscal_year ON fiscal_backups(fiscal_year_id);

ALTER TABLE fiscal_backups ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_fiscal_backups') THEN
    CREATE POLICY "allow_all_fiscal_backups" ON fiscal_backups FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
