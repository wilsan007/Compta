-- ============================================================
-- 166_permission_tests.sql
--
-- has_permission() garde la validation des écritures
-- (enforce_journal_entry_permissions, 154:211). Les deux défauts corrigés par la
-- 163 ne se voyaient qu'à l'exécution : la fonction compile, et les tests
-- unitaires mockent Supabase.
--
-- Rejoué par la CI (job db-integration). Exclu du rejeu des migrations par le
-- suffixe `_tests.sql`.
-- ============================================================

DO $$
DECLARE
  v_tenant uuid := uuid_generate_v4();
  v_admin uuid := uuid_generate_v4();
  v_compta uuid := uuid_generate_v4();
  v_viewer uuid := uuid_generate_v4();
  v_revoque uuid := uuid_generate_v4();
  v_role uuid := uuid_generate_v4();

BEGIN
  INSERT INTO auth.users (id) VALUES (v_admin), (v_compta), (v_viewer), (v_revoque);
  INSERT INTO tenants (id, name) VALUES (v_tenant, 'Tests permissions');
  INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status) VALUES
    (v_tenant, v_admin,   'a@test', 'Admin',     'admin',      'active'),
    (v_tenant, v_compta,  'c@test', 'Comptable', 'accountant', 'active'),
    (v_tenant, v_viewer,  'v@test', 'Lecteur',   'viewer',     'active'),
    (v_tenant, v_revoque, 'r@test', 'Révoqué',   'admin',      'revoked');
  PERFORM set_config('request.headers', json_build_object('x-tenant-id', v_tenant)::text, true);

  -- 1. l'administrateur peut valider
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  IF NOT has_permission('journal_entry.post') THEN
    RAISE EXCEPTION '1. un admin doit pouvoir valider une écriture';
  END IF;

  -- 2. le comptable aussi — c'est son métier. Avant la 165 il était bloqué,
  --    parce que role_permissions est vide tant qu'aucun écran ne l'alimente.
  PERFORM set_config('request.jwt.claim.sub', v_compta::text, true);
  IF NOT has_permission('journal_entry.post') THEN
    RAISE EXCEPTION '2. un comptable doit pouvoir valider une écriture';
  END IF;

  -- 3. le lecteur, non
  PERFORM set_config('request.jwt.claim.sub', v_viewer::text, true);
  IF has_permission('journal_entry.post') THEN
    RAISE EXCEPTION '3. un lecteur ne doit pas pouvoir valider une écriture';
  END IF;

  -- 4. un utilisateur révoqué ne garde aucun droit, fût-il admin
  PERFORM set_config('request.jwt.claim.sub', v_revoque::text, true);
  IF has_permission('journal_entry.post') THEN
    RAISE EXCEPTION '4. un utilisateur révoqué ne doit garder aucun droit';
  END IF;

  -- 5. une permission accordée à UN rôle ne doit pas fuiter vers les autres.
  --    Avant la 165, la jointure `OR tu.custom_role_id IS NULL` la donnait à tous.
  INSERT INTO tenant_roles (id, tenant_id, name, is_system, is_active)
    VALUES (v_role, v_tenant, 'Rôle restreint', false, true);
  INSERT INTO role_permissions (tenant_id, role_id, permission)
    VALUES (v_tenant, v_role, 'secret.action');
  PERFORM set_config('request.jwt.claim.sub', v_viewer::text, true);
  IF has_permission('secret.action') THEN
    RAISE EXCEPTION '5. une permission d''un autre rôle ne doit pas fuiter';
  END IF;

  -- 6. … mais l'utilisateur qui porte ce rôle l'obtient
  UPDATE tenant_users SET custom_role_id = v_role
    WHERE tenant_id = v_tenant AND auth_id = v_viewer;
  IF NOT has_permission('secret.action') THEN
    RAISE EXCEPTION '6. le porteur du rôle doit obtenir la permission';
  END IF;

  -- nettoyage
  DELETE FROM role_permissions WHERE tenant_id = v_tenant;
  DELETE FROM tenant_users WHERE tenant_id = v_tenant;  -- custom_role_id référence tenant_roles
  DELETE FROM tenant_roles WHERE tenant_id = v_tenant;
  DELETE FROM tenants WHERE id = v_tenant;
  DELETE FROM auth.users WHERE id IN (v_admin, v_compta, v_viewer, v_revoque);
  PERFORM set_config('request.jwt.claim.sub', '', false);

  RAISE NOTICE '✅ has_permission : 6 scénarios sur 6';
END $$;
