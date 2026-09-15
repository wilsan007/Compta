-- ============================================================
-- 159_fix_rls_cross_tenant_leaks.sql
--
-- Fuites trouvées par le test générique 105_rls_tests.sql (rôle authenticated,
-- deux tenants, 358 tables). Les politiques PostgreSQL permissives se combinent
-- en OU : une seule politique USING (true) annule toutes les politiques tenant.
--
-- 1. partner_bank_accounts / bank_connections : « allow_all_* » (FOR ALL, true)
--    recréées par 99_sprint7_bank_features.sql après la purge des migrations
--    74/84 (renumérotation 44 → 99) — coordonnées bancaires lisibles et
--    modifiables par tout utilisateur connecté.
-- 2. signup_flows : USING (true).
-- 3. Tables de référence (currencies, legislation_packs, public_holidays,
--    tax_rates) : les lignes globales (tenant_id NULL) sont partagées, mais
--    les lignes propres à un tenant étaient visibles de tous.
-- ============================================================

DROP POLICY IF EXISTS allow_all_partner_bank_accounts ON partner_bank_accounts;
DROP POLICY IF EXISTS allow_all_bank_connections ON bank_connections;

DROP POLICY IF EXISTS signup_flows_self ON signup_flows;
CREATE POLICY signup_flows_self ON signup_flows
  FOR ALL
  USING ((tenant_id IS NOT NULL AND tenant_id = current_tenant_id()) OR (email IS NOT NULL AND email = auth.email()))
  WITH CHECK ((tenant_id IS NULL OR tenant_id = current_tenant_id()) AND (email IS NULL OR email = auth.email()));

-- Référentiels : lignes globales + lignes du tenant courant
DROP POLICY IF EXISTS global_select_currencies ON currencies;
DROP POLICY IF EXISTS select_currencies ON currencies;
CREATE POLICY select_currencies ON currencies
  FOR SELECT USING (tenant_id IS NULL OR tenant_id = current_tenant_id());

DROP POLICY IF EXISTS global_select_legislation_packs ON legislation_packs;
DROP POLICY IF EXISTS select_legislation_packs ON legislation_packs;
CREATE POLICY select_legislation_packs ON legislation_packs
  FOR SELECT USING (tenant_id IS NULL OR tenant_id = current_tenant_id());

DROP POLICY IF EXISTS global_select_public_holidays ON public_holidays;
DROP POLICY IF EXISTS global_select_tax_rates ON tax_rates;
