-- 791 — correctifs_fusion_c_roles
-- Numéro pris le 2026-10-14T10:47:50.638Z par migration-numero.mjs (ligne « plan6 intégration (correctifs de fusion) », branche integration/plan6-b).
-- ═══════════════════════════════════════════════════════════════════════════
-- 791 — Correctifs de la fusion plan6 C (13/10/2026, session d'intégration)
-- ═══════════════════════════════════════════════════════════════════════════
-- ROUGES AVANT, mesurés sur base neuve (batterie du 13/10 : 7 échecs sur 267) :
--
--   1. check_anon_grants + 228 T06 : la 4ᵉ surcharge de `resolve_account`
--      (uuid, text, jsonb, boolean — créée par la 397) hérite des droits
--      PUBLIC par défaut : la 384 avait révoqué la 3-args, la 4-args est née
--      APRES et n'a pas reçu la même posture.
--
--   2. G1 (check_bt_grid) : +2 tables cloisonnées RLS mais NON FORCEES —
--      tenant_account_roles et tenant_journal_roles (rôles par société des
--      packs, 381) : ISO-04 non tenu à la naissance (mesuré : tables_tenant
--      382, moins_de_4 88, rls_sans_force 53).
--
--   3. (cascade — corrigé du même souffle dans 105) crm_scoring_rules porte
--      DEUX CHECKs sur `operator` : le seeder générique y pioche 'equals'
--      (l'un des deux) et l'autre CHECK le refuse — cas particulier ajouté.
--
-- CORRECTIONS :
--   1. resolve_account(uuid, text, jsonb, boolean) : REVOKE PUBLIC/anon +
--      GRANT authenticated/service_role — même posture que la 3-args de la 384
--      (« appelée par le front et par les triggers d'écriture »).
--   2. Les deux tables rôles passent SOUS FORCE ROW LEVEL SECURITY (ISO-04
--      rattrapé). muettes inchangé : elles ont une politique FOR ALL.
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.tenant_account_roles FORCE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_journal_roles FORCE ROW LEVEL SECURITY;

REVOKE ALL ON FUNCTION public.resolve_account(uuid, text, jsonb, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resolve_account(uuid, text, jsonb, boolean) TO authenticated, service_role;

