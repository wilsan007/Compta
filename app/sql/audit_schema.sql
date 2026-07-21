-- ============================================
-- AUDIT: Vérifier ce qui existe dans la DB
-- Exécuter manuellement et partager le résultat
-- ============================================

-- 1. TOUTES les tables existantes (triées par nom)
SELECT 
  schemaname as schema,
  tablename as table_name
FROM pg_tables 
WHERE schemaname = 'public'
ORDER BY tablename;

-- 2. Vérifier spécifiquement les tables Phase 1
SELECT 
  v.name as table_name,
  CASE WHEN t.tablename IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END as status
FROM (VALUES 
  ('recurring_entries'),
  ('regularization_entries'),
  ('currency_revaluations'),
  ('collection_reminders'),
  ('analytic_plans'),
  ('distribution_grills'),
  ('bank_reconciliation_rules'),
  ('bank_statement_imports'),
  ('edi_tva_declarations'),
  ('tvs_declarations'),
  ('fiscal_backups'),
  ('fiscal_years'),
  ('company_settings'),
  ('vat_returns'),
  ('journals'),
  ('customers'),
  ('tenants')
) AS v(name)
LEFT JOIN pg_tables t ON t.tablename = v.name AND t.schemaname = 'public'
ORDER BY v.name;

-- 3. Colonnes de company_settings
SELECT 
  column_name, 
  data_type, 
  is_nullable,
  column_default
FROM information_schema.columns 
WHERE table_name = 'company_settings' AND table_schema = 'public'
ORDER BY ordinal_position;

-- 4. Colonnes de vat_returns
SELECT 
  column_name, 
  data_type, 
  is_nullable,
  column_default
FROM information_schema.columns 
WHERE table_name = 'vat_returns' AND table_schema = 'public'
ORDER BY ordinal_position;

-- 5. Colonnes de journals
SELECT 
  column_name, 
  data_type, 
  is_nullable,
  column_default
FROM information_schema.columns 
WHERE table_name = 'journals' AND table_schema = 'public'
ORDER BY ordinal_position;

-- 6. Colonnes de collection_reminders
SELECT 
  column_name, 
  data_type, 
  is_nullable,
  column_default
FROM information_schema.columns 
WHERE table_name = 'collection_reminders' AND table_schema = 'public'
ORDER BY ordinal_position;

-- 7. Toutes les colonnes des tables Phase 1 qui existent
SELECT 
  c.table_name,
  c.column_name, 
  c.data_type, 
  c.is_nullable,
  c.column_default
FROM information_schema.columns c
JOIN pg_tables t ON t.tablename = c.table_name AND t.schemaname = 'public'
WHERE c.table_schema = 'public'
  AND c.table_name IN (
    'recurring_entries','regularization_entries','currency_revaluations',
    'collection_reminders','analytic_plans','distribution_grills',
    'bank_reconciliation_rules','bank_statement_imports',
    'tvs_declarations','fiscal_backups','fiscal_years'
  )
ORDER BY c.table_name, c.ordinal_position;
