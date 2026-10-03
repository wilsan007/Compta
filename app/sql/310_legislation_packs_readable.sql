-- ============================================================
-- 310_legislation_packs_readable.sql — recette /qa du 29/09/2026 (QA-01)
--
-- Mesuré à l'écran, sur base neuve (258 migrations) : l'inscription s'arrête à
-- l'étape « législation », la liste des pays est VIDE, et une société réelle ne
-- lit pas son propre pack (`getLegislationPack(code)` → 406).
--
-- Cause : la migration 24 a rangé le référentiel `legislation_packs` sous la
-- société technique `…0001` (colonne `tenant_id` NOT NULL), mais la politique de
-- lecture ne montre que `tenant_id IS NULL OR tenant_id = current_tenant_id()`.
-- La 272 avait fait le même constat pour `tax_rates` (« aucune société réelle ne
-- pouvait porter un taux rattaché à son pack »), sans rouvrir la lecture.
--
-- Correctif : le référentiel (les lignes de la société technique) est LISIBLE,
-- par les mêmes rôles qu'avant (la politique reste sans clause TO : la page
-- d'inscription le lit, cf. ci/check_anon_grants.sql). Rien d'autre ne change :
--   * aucune politique d'écriture n'est ajoutée — le référentiel reste en
--     lecture seule pour `authenticated` ;
--   * un pack propre à une société réelle reste réservé à cette société.
-- Preuve : 310_legislation_packs_readable_tests.sql (T01, T02 rouges avant).
-- ============================================================

DROP POLICY IF EXISTS "select_legislation_packs" ON legislation_packs;
CREATE POLICY "select_legislation_packs" ON legislation_packs
  FOR SELECT
  USING (
    tenant_id IS NULL
    OR tenant_id = '00000000-0000-0000-0000-000000000001'::uuid
    OR tenant_id = current_tenant_id()
  );
