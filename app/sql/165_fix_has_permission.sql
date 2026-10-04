-- ============================================================
-- 165_fix_has_permission.sql
--
-- Trouvé le 18/09 en branchant le contrôle des droits (bloc E1 du suivi).
-- `has_permission` (120_admin_onboarding_roles.sql:97) est fausse dans les DEUX
-- sens, et elle garde la validation des écritures
-- (`enforce_journal_entry_permissions`, 154:211).
--
-- 1. La jointure portait `(rp.role_id = tu.custom_role_id OR tu.custom_role_id
--    IS NULL)`. Aucun écran ne renseigne `custom_role_id` : la condition est
--    donc toujours vraie et la jointure ramène TOUTES les permissions du tenant.
--    Dès qu'un rôle quelconque reçoit une permission, tout le monde l'obtient.
-- 2. Symétriquement, tant que `role_permissions` est vide — c'est le cas
--    aujourd'hui, aucun écran n'y écrit — seul `admin` obtient quoi que ce soit.
--    Un `accountant` ne peut donc PAS valider une écriture comptable, ce qui est
--    précisément son métier.
-- 3. Le statut n'était pas regardé : un utilisateur `revoked` gardait ses droits.
--
-- La version ci-dessous : admin, OU une permission explicitement accordée au
-- rôle personnalisé de l'utilisateur, OU le socle du rôle métier. Le socle
-- reprend la matrice de `src/lib/queries/misc.ts` (hasPermission), seule source
-- de droits côté interface.
-- ============================================================

CREATE OR REPLACE FUNCTION has_permission(p_permission text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM tenant_users tu
    WHERE tu.tenant_id = current_tenant_id()
      AND tu.auth_id = auth.uid()
      AND tu.status = 'active'
      AND (
        tu.role = 'admin'
        OR EXISTS (
          SELECT 1 FROM role_permissions rp
          WHERE rp.tenant_id = tu.tenant_id
            AND rp.role_id = tu.custom_role_id
            AND rp.permission = p_permission
        )
        OR (tu.role = 'accountant' AND p_permission IN (
              'journal_entry.post', 'journal_entry.create', 'journal_entry.update'))
      )
  );
$$;

COMMENT ON FUNCTION has_permission(text) IS
  'Permission au format objet.action pour l''utilisateur courant. Admin, rôle '
  'personnalisé, ou socle du rôle métier. Voir 165_fix_has_permission.sql.';
