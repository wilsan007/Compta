-- ============================================================
-- 270_anon_and_global_rows_write_closed.sql — vague X1-urgent
-- Audit fonctionnel exécuté du 28/09/2026 : C1, C2 (+ `banks`, même classe)
--
-- LE DÉFAUT. Trois tables SANS société — des référentiels partagés par toutes
-- les sociétés — portaient une politique d'écriture qui ne vérifiait rien :
--   * webhook_event_catalog  : ALL USING (true) WITH CHECK (true)            (C1)
--   * payroll_legal_parameters : ALL USING (tenant_id IS NULL OR …)         (C2)
--     → un anonyme mettait le SMIC horaire à 1 € pour TOUT LE MONDE ;
--   * banks : écriture pour `current_user_role() = 'admin'` — l'admin de
--     n'importe quelle société réécrivait le référentiel des autres.
-- Et la cause racine : `anon` détenait INSERT/UPDATE/DELETE/TRUNCATE sur 72
-- tables (privilèges par défaut de l'image Supabase). La RLS arrêtait la
-- plupart des lignes — pas celles des trois politiques ci-dessus, et jamais
-- TRUNCATE, que la RLS ne regarde pas.
--
-- LA RÈGLE POSÉE.
--   1. Un visiteur non connecté ne détient AUCUN droit d'écriture ni TRUNCATE
--      sur `public` — maintenant et pour les tables à venir (privilèges par
--      défaut). Il garde SELECT : les référentiels de l'inscription (devises,
--      pays, taux) restent lisibles.
--   2. Une ligne GLOBALE (sans société) ne s'écrit que par `service_role`
--      (migrations, fonctions d'administration). Aucune politique d'écriture
--      ne peut plus l'atteindre — `ci/check_global_rows_writable.sql` y veille.
--   3. Une société garde son paramètre légal propre (surcharge du global),
--      sous `can_perform('payroll_legal_parameters', …)` : un lecteur ne le
--      pose plus.
--   4. TRUNCATE est retiré à `authenticated` aussi : aucun écran ne vide une
--      table, et c'est le seul verbe que la RLS ne filtre jamais.
--
-- Tests : 270_anon_and_global_rows_write_closed_tests.sql (T01–T08, 6 rouges
-- avant). PRODUCTION : après déploiement, relire les valeurs globales
-- (voir doc/audit/VAGUE-X1U-X0-X1-X7-2026-09-28.md) — elles ont pu être
-- altérées avant la fermeture.
-- ============================================================

BEGIN;

-- ── 1. webhook_event_catalog (C1) ────────────────────────────
DROP POLICY IF EXISTS webhook_event_catalog_all ON webhook_event_catalog;
DROP POLICY IF EXISTS webhook_event_catalog_select ON webhook_event_catalog;
CREATE POLICY webhook_event_catalog_select ON webhook_event_catalog
  FOR SELECT TO authenticated USING (true);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON webhook_event_catalog FROM anon, authenticated;

-- ── 2. payroll_legal_parameters (C2) ─────────────────────────
DROP POLICY IF EXISTS payroll_legal_params_all ON payroll_legal_parameters;
DROP POLICY IF EXISTS payroll_legal_params_insert ON payroll_legal_parameters;
DROP POLICY IF EXISTS payroll_legal_params_update ON payroll_legal_parameters;
DROP POLICY IF EXISTS payroll_legal_params_delete ON payroll_legal_parameters;
-- La lecture (payroll_legal_params_select) reste : globaux + ceux de la société.
CREATE POLICY payroll_legal_params_insert ON payroll_legal_parameters
  FOR INSERT TO authenticated
  WITH CHECK (tenant_id = current_tenant_id()
              AND can_perform('payroll_legal_parameters', 'insert'));
CREATE POLICY payroll_legal_params_update ON payroll_legal_parameters
  FOR UPDATE TO authenticated
  USING (tenant_id = current_tenant_id()
         AND can_perform('payroll_legal_parameters', 'update'))
  WITH CHECK (tenant_id = current_tenant_id()
              AND can_perform('payroll_legal_parameters', 'update'));
CREATE POLICY payroll_legal_params_delete ON payroll_legal_parameters
  FOR DELETE TO authenticated
  USING (tenant_id = current_tenant_id()
         AND can_perform('payroll_legal_parameters', 'delete'));

-- ── 3. banks : référentiel global ────────────────────────────
DROP POLICY IF EXISTS tenant_insert_banks ON banks;
DROP POLICY IF EXISTS tenant_update_banks ON banks;
DROP POLICY IF EXISTS tenant_delete_banks ON banks;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON banks FROM anon, authenticated;

-- ── 4. Cause racine : les droits d'écriture de `anon` ────────
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON ALL TABLES IN SCHEMA public FROM anon;
REVOKE TRUNCATE ON ALL TABLES IN SCHEMA public FROM authenticated;
REVOKE USAGE, UPDATE ON ALL SEQUENCES IN SCHEMA public FROM anon;

-- Pour les tables à venir : les privilèges par défaut du propriétaire courant
-- et, quand il existe, de `supabase_admin` (celui de l'image Supabase).
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLES FROM anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE TRUNCATE ON TABLES FROM authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE USAGE, UPDATE ON SEQUENCES FROM anon;
DO $$
DECLARE r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['postgres', 'supabase_admin'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) AND r <> current_user THEN
      BEGIN
        EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public
          REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLES FROM anon', r);
        EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public
          REVOKE TRUNCATE ON TABLES FROM authenticated', r);
      EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE '270 : privilèges par défaut de % non modifiables par % — le contrôle CI veille', r, current_user;
      END;
    END IF;
  END LOOP;
END $$;

COMMIT;
