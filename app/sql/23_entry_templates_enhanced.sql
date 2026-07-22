-- ============================================================
-- 23_entry_templates_enhanced.sql
-- Enhance entry_templates to match Sage 100 modèle de saisie
-- Adds: counterpart_account, payment_terms to header
-- template_lines is a jsonb column already — no schema change needed
-- This migration just ensures the table exists and adds helpful indexes
-- ============================================================

-- Ensure entry_templates table exists (for fresh installs)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'entry_templates') THEN
    CREATE TABLE entry_templates (
      id uuid primary key default uuid_generate_v4(),
      tenant_id uuid,
      name text not null,
      journal_code text,
      description text,
      template_lines jsonb default '[]'::jsonb,
      is_default boolean default false,
      active boolean default true,
      created_at timestamptz default now()
    );
    alter table entry_templates enable row level security;
    CREATE POLICY "allow_all_entry_templates" ON entry_templates FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- Add counterpart_account column (compte de contrepartie du journal)
DO $$ BEGIN
  ALTER TABLE entry_templates ADD COLUMN IF NOT EXISTS counterpart_account text;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'counterpart_account: %', SQLERRM;
END $$;

-- Add payment_terms column (conditions de règlement par défaut)
DO $$ BEGIN
  ALTER TABLE entry_templates ADD COLUMN IF NOT EXISTS payment_terms text;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'payment_terms: %', SQLERRM;
END $$;

-- Index for faster lookups
CREATE INDEX IF NOT EXISTS idx_entry_templates_journal ON entry_templates(journal_code);
CREATE INDEX IF NOT EXISTS idx_entry_templates_default ON entry_templates(is_default) WHERE is_default = true;
CREATE INDEX IF NOT EXISTS idx_entry_templates_tenant ON entry_templates(tenant_id);
