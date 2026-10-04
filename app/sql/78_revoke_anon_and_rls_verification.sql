-- ============================================================
-- 78_revoke_anon_and_rls_verification.sql
--
-- SEC-02: Révoquer les grants du rôle anon sur toutes les tables
-- métier, et ne réautoriser que les tables de référence publiques.
--
-- Tables publiques (anon peut SELECT) :
--   currencies, legislation_packs, tax_rates, chart_account_templates
-- ============================================================

-- ============================================
-- 1. Révoquer tous les grants du rôle anon
-- ============================================
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM anon;

-- ============================================
-- 2. Réautoriser SELECT sur les tables de référence publiques
-- ============================================
GRANT SELECT ON currencies TO anon;
GRANT SELECT ON legislation_packs TO anon;
GRANT SELECT ON tax_rates TO anon;
GRANT SELECT ON chart_account_templates TO anon;
GRANT SELECT ON banks TO anon;

-- ============================================
-- 3. Vérification : aucune politique USING(true) ne doit rester
-- ============================================
-- Cette requête doit renvoyer 0 ligne après exécution.
-- À exécuter en CI pour vérifier SEC-02.
CREATE OR REPLACE VIEW rls_audit AS
SELECT tablename, policyname, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND (qual = 'true' OR with_check = 'true' OR qual = '(true)' OR with_check = '(true)')
ORDER BY tablename;

GRANT SELECT ON rls_audit TO authenticated;
