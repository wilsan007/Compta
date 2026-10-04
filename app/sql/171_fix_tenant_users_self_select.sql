-- ============================================================
-- 171_fix_tenant_users_self_select.sql
-- Blocage à froid : un membre actif ne pouvait jamais lire sa
-- propre ligne tenant_users au premier chargement (session fraîche,
-- pas encore d'en-tête x-tenant-id ni de GUC app.active_tenant_id),
-- car la policy SELECT exigeait current_tenant_id() — que l'on ne
-- peut justement pas connaître avant d'avoir lu tenant_users.
-- Résultat : redirection vers /onboarding pour tout utilisateur
-- existant sur navigateur nouveau ou session nettoyée.
-- Correction : autoriser la lecture de ses propres lignes.
-- ============================================================

DROP POLICY IF EXISTS tenant_select_tenant_users ON tenant_users;

CREATE POLICY tenant_select_tenant_users ON tenant_users
  FOR SELECT USING (
    tenant_id = current_tenant_id()
    OR auth_id = auth.uid()
  );
