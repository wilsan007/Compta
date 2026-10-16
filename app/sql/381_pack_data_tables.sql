-- ═══════════════════════════════════════════════════════════════════════════
-- 381 — pack_data_tables : les TABLES DE DONNÉES d'un pack (LOT 1-A, LOC1-02)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- CE QUE C'EST. La `380` a posé le MOULE (`legislation_packs` : niveau, parent,
-- statut, formats). La `381` pose la FARINE : les dix tables qui portent le
-- CONTENU d'un pack — sources légales, rôles de comptes et de journaux,
-- capacités, jours fériés, identifiants légaux, règles de documents, gabarits
-- d'états et leurs lignes, autres taxes. Cahier §5, tâche LOC1-02.
--
-- TOUTES GLOBALES, SANS `tenant_id`. Un pack est un référentiel de plateforme,
-- rangé sous la société technique `…0001` (comme `legislation_packs`) : ces
-- tables ne portent pas de société, donc elles sont EXEMPTÉES de la porte
-- ISO-02 (`ci/check_composite_fks.sql`), qui ne vise que les enfants portant un
-- `tenant_id`. Lecture : tout utilisateur connecté. Écriture : `service_role`
-- seul (aucune politique d'écriture — même patron que `chart_pack_status`, 201).
--
-- Les rôles (`pack_account_roles.role`, `pack_journal_roles.role`) seront
-- raccrochés au catalogue fermé en `383` (LOC1-04) : la clé étrangère ne peut
-- pas précéder le catalogue.
--
-- REJOUABLE : `CREATE TABLE IF NOT EXISTS`, `DROP POLICY IF EXISTS` + `CREATE`,
-- `ADD COLUMN IF NOT EXISTS`, `DROP CONSTRAINT IF EXISTS` + `ADD`.
--
-- Numéro pris le 2026-10-05T18:57:06.325Z par migration-numero.mjs
-- (ligne « plan6 C (lot K, Djibouti) », branche plan6/c-localisation).
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- 1. Sources légales — le texte fondateur de chaque valeur
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pack_sources (
  pack_code      text NOT NULL REFERENCES legislation_packs(code) ON DELETE CASCADE,
  source_id      text NOT NULL,                -- 'SRC-DJ-01'…
  title          text NOT NULL,
  issuer         text,
  reference      text,                         -- n° de loi / décret
  article        text,
  published_on   date,
  effective_from date,
  url            text,
  file_sha256    text,
  PRIMARY KEY (pack_code, source_id),
  CONSTRAINT pack_sources_source_id_check CHECK (source_id ~ '^[A-Za-z0-9_.-]+$')
);

-- ─────────────────────────────────────────────────────────────
-- 2. Rôles de comptes et de journaux portés par le pack
--    (clé étrangère vers le catalogue fermé en 383 / LOC1-04)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pack_account_roles (
  pack_code    text NOT NULL REFERENCES legislation_packs(code) ON DELETE CASCADE,
  role         text NOT NULL,
  account_code text NOT NULL,
  source_id    text,
  PRIMARY KEY (pack_code, role)
);

CREATE TABLE IF NOT EXISTS pack_journal_roles (
  pack_code    text NOT NULL REFERENCES legislation_packs(code) ON DELETE CASCADE,
  role         text NOT NULL,
  journal_code text NOT NULL,
  journal_name text,
  journal_type text,
  source_id    text,
  PRIMARY KEY (pack_code, role)
);

-- ─────────────────────────────────────────────────────────────
-- 3. Capacités du pack — ce que le pays sait faire (LOC1-41/42)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pack_capabilities (
  pack_code  text NOT NULL REFERENCES legislation_packs(code) ON DELETE CASCADE,
  capability text NOT NULL,
  enabled    boolean NOT NULL DEFAULT true,
  config     jsonb   NOT NULL DEFAULT '{}'::jsonb,
  PRIMARY KEY (pack_code, capability),
  CONSTRAINT pack_capabilities_config_check CHECK (jsonb_typeof(config) = 'object')
);

-- ─────────────────────────────────────────────────────────────
-- 4. Jours fériés (fixes et variables) — remplace public_holidays.country
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pack_holidays (
  pack_code    text NOT NULL REFERENCES legislation_packs(code) ON DELETE CASCADE,
  holiday_date date NOT NULL,                  -- date VARIABLE : l'occurrence connue
  label        text NOT NULL,
  label_ar     text,
  is_variable  boolean NOT NULL DEFAULT false, -- Pâques, Aïd… : recalculée
  source_id    text,
  PRIMARY KEY (pack_code, holiday_date)
);

-- ─────────────────────────────────────────────────────────────
-- 5. Identifiants légaux (SIRET, NIF, RCCM…) — fin de siret / vat_number en dur
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pack_legal_identifiers (
  pack_code          text NOT NULL REFERENCES legislation_packs(code) ON DELETE CASCADE,
  identifier_type    text NOT NULL,
  label              text NOT NULL,
  label_ar           text,
  regex              text,
  checksum_algo      text,
  required_for       text[] NOT NULL DEFAULT '{}',   -- company, customer_b2b, supplier
  printed_on_invoice boolean NOT NULL DEFAULT true,
  PRIMARY KEY (pack_code, identifier_type)
);

-- ─────────────────────────────────────────────────────────────
-- 6. Règles de documents — mentions obligatoires, numérotation
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pack_document_rules (
  pack_code          text NOT NULL REFERENCES legislation_packs(code) ON DELETE CASCADE,
  document_type      text NOT NULL,            -- invoice, credit_note, quote, payslip…
  mandatory_mentions  jsonb NOT NULL DEFAULT '[]'::jsonb,
  numbering_pattern   text,                     -- '{type}-{year}-{seq}'
  numbering_reset     text NOT NULL DEFAULT 'never',
  gapless             boolean NOT NULL DEFAULT true,
  source_id           text,
  PRIMARY KEY (pack_code, document_type),
  CONSTRAINT pack_document_rules_reset_check  CHECK (numbering_reset IN ('never','yearly')),
  CONSTRAINT pack_document_rules_mentions_check CHECK (jsonb_typeof(mandatory_mentions) = 'array')
);

-- ─────────────────────────────────────────────────────────────
-- 7. Gabarits d'états et leurs lignes — remplace la logique `LIKE '6%'`
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pack_statement_templates (
  pack_code     text NOT NULL REFERENCES legislation_packs(code) ON DELETE CASCADE,
  template_code text NOT NULL,
  name          text NOT NULL,
  kind          text NOT NULL,
  periodicity   text,
  PRIMARY KEY (pack_code, template_code),
  CONSTRAINT pack_statement_templates_kind_check CHECK (kind IN
    ('balance_sheet','income_statement','cash_flow','notes','tax_return','vat_return','social_return'))
);

CREATE TABLE IF NOT EXISTS pack_statement_lines (
  pack_code     text NOT NULL REFERENCES legislation_packs(code) ON DELETE CASCADE,
  template_code text NOT NULL,
  line_code     text NOT NULL,
  label         text NOT NULL,
  label_ar      text,
  parent_line   text,
  sort_order    integer NOT NULL DEFAULT 0,
  sign          text NOT NULL DEFAULT 'net',
  account_ranges text[] NOT NULL DEFAULT '{}',
  formula       text,
  box_code      text,
  PRIMARY KEY (pack_code, template_code, line_code),
  CONSTRAINT pack_statement_lines_sign_check CHECK (sign IN ('debit','credit','net')),
  FOREIGN KEY (pack_code, template_code)
    REFERENCES pack_statement_templates (pack_code, template_code) ON DELETE CASCADE
);

-- ─────────────────────────────────────────────────────────────
-- 8. Autres impôts et taxes — retenues, timbre, taxes parafiscales
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pack_other_taxes (
  id             bigserial PRIMARY KEY,
  pack_code      text NOT NULL REFERENCES legislation_packs(code) ON DELETE CASCADE,
  tax_code       text NOT NULL,
  kind           text NOT NULL,
  rate           numeric,
  fixed_amount   numeric,
  base           text,
  account_role   text,
  effective_from date,
  effective_to   date,
  source_id      text,
  UNIQUE (pack_code, tax_code, effective_from),
  CONSTRAINT pack_other_taxes_kind_check CHECK (kind IN ('withholding','stamp','business_license','parafiscal'))
);

-- ─────────────────────────────────────────────────────────────
-- 9. RLS : lecture par tout utilisateur connecté, écriture par `service_role`
--    seul (aucune politique d'écriture). Même patron que `chart_pack_status` (201).
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'pack_sources','pack_account_roles','pack_journal_roles','pack_capabilities',
    'pack_holidays','pack_legal_identifiers','pack_document_rules',
    'pack_statement_templates','pack_statement_lines','pack_other_taxes'] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', 'select_' || t, t);
    EXECUTE format('CREATE POLICY %I ON %I FOR SELECT USING (auth.uid() IS NOT NULL)', 'select_' || t, t);
  END LOOP;
END $$;

-- ─────────────────────────────────────────────────────────────
-- 10. Les tables existantes reçoivent `source_id` (traçabilité d'une valeur)
-- ─────────────────────────────────────────────────────────────
ALTER TABLE tax_rates               ADD COLUMN IF NOT EXISTS source_id text;
ALTER TABLE chart_account_templates ADD COLUMN IF NOT EXISTS source_id text;
ALTER TABLE payroll_tax_grids       ADD COLUMN IF NOT EXISTS source_id text;
ALTER TABLE payroll_tax_grid_lines  ADD COLUMN IF NOT EXISTS source_id text;
ALTER TABLE payroll_legal_parameters ADD COLUMN IF NOT EXISTS source_id text;
ALTER TABLE corporate_tax_grids     ADD COLUMN IF NOT EXISTS source_id text;
ALTER TABLE corporate_tax_grid_lines ADD COLUMN IF NOT EXISTS source_id text;

-- ─────────────────────────────────────────────────────────────
-- 11. Grilles et paramètres pointent leur PACK, par une clé COMPOSITE
--     (ISO-02 : ces tables portent `tenant_id`). Leurs lignes globales ont
--     `tenant_id` NULL : la clé n'est pas contrôlée pour elles, comme
--     `company_settings_legislation_pack_code_fkey`.
-- ─────────────────────────────────────────────────────────────
ALTER TABLE payroll_tax_grids        ADD COLUMN IF NOT EXISTS pack_code text;
ALTER TABLE payroll_legal_parameters ADD COLUMN IF NOT EXISTS pack_code text;
ALTER TABLE corporate_tax_grids      ADD COLUMN IF NOT EXISTS pack_code text;

ALTER TABLE payroll_tax_grids DROP CONSTRAINT IF EXISTS payroll_tax_grids_pack_code_fkey;
ALTER TABLE payroll_tax_grids ADD CONSTRAINT payroll_tax_grids_pack_code_fkey
  FOREIGN KEY (tenant_id, pack_code) REFERENCES legislation_packs (tenant_id, code);

ALTER TABLE payroll_legal_parameters DROP CONSTRAINT IF EXISTS payroll_legal_parameters_pack_code_fkey;
ALTER TABLE payroll_legal_parameters ADD CONSTRAINT payroll_legal_parameters_pack_code_fkey
  FOREIGN KEY (tenant_id, pack_code) REFERENCES legislation_packs (tenant_id, code);

ALTER TABLE corporate_tax_grids DROP CONSTRAINT IF EXISTS corporate_tax_grids_pack_code_fkey;
ALTER TABLE corporate_tax_grids ADD CONSTRAINT corporate_tax_grids_pack_code_fkey
  FOREIGN KEY (tenant_id, pack_code) REFERENCES legislation_packs (tenant_id, code);
