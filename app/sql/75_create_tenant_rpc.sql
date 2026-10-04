-- ============================================================
-- 75_create_tenant_rpc.sql
--
-- DB-01: RPC atomique pour créer un tenant + admin + employé.
-- Remplace les 3 inserts client non atomiques de createTenantForUser.
--
-- Le RPC est SECURITY DEFINER pour pouvoir insérer dans tenants
-- et tenant_users sans que le client ait besoin de droits directs.
-- ============================================================

CREATE OR REPLACE FUNCTION create_tenant_for_current_user(p_data jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tenant uuid;
  v_auth_id uuid := auth.uid();
  v_email text;
  v_name text;
  v_user_name text;
  v_enabled_modules text;
BEGIN
  -- Vérifier que l'utilisateur est authentifié
  IF v_auth_id IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;

  -- Extraire l'email depuis les métadonnées d'auth
  v_email := (
    SELECT COALESCE(
      (auth.jwt() ->> 'email'),
      (auth.jwt() -> 'user_metadata' ->> 'email')
    )
  );

  -- Nom d'affichage depuis les métadonnées
  v_user_name := COALESCE(
    (auth.jwt() -> 'user_metadata' ->> 'name'),
    (auth.jwt() -> 'user_metadata' ->> 'full_name'),
    v_email
  );

  -- Vérifier que l'utilisateur n'a pas déjà un tenant (optionnel: autoriser plusieurs)
  -- On autorise plusieurs tenants pour les cabinets comptables.

  -- Modules activés par défaut
  -- ACC-02: Utiliser jsonb au lieu de text[] pour éviter "malformed array literal"
  v_enabled_modules := COALESCE(
    (p_data ->> 'enabled_modules'),
    '["home","accounting","commercial","treasury","stock","production","hr","dashboards","reporting","system"]'
  );

  -- 1. Créer le tenant
  INSERT INTO tenants (
    name, legal_name, siren, vat_number,
    address, city, postal_code, country, currency,
    email, phone, legislation_pack_code, country_code,
    enabled_modules, status, plan, trial_ends_at
  ) VALUES (
    p_data ->> 'name',
    COALESCE(p_data ->> 'legal_name', p_data ->> 'name'),
    p_data ->> 'siren',
    p_data ->> 'vat_number',
    p_data ->> 'address',
    p_data ->> 'city',
    p_data ->> 'postal_code',
    COALESCE(p_data ->> 'country', 'France'),
    COALESCE(p_data ->> 'currency', 'EUR'),
    COALESCE(p_data ->> 'email', v_email),
    p_data ->> 'phone',
    p_data ->> 'legislation_pack_code',
    p_data ->> 'legislation_pack_code',
    v_enabled_modules,
    'active',
    'trial',
    (NOW() + INTERVAL '30 days')::timestamptz
  )
  RETURNING id INTO v_tenant;

  -- 2. Créer le tenant_users (admin)
  INSERT INTO tenant_users (
    tenant_id, auth_id, email, name, role, permissions, status, accepted_at
  ) VALUES (
    v_tenant,
    v_auth_id,
    v_email,
    v_user_name,
    'admin',
    '{}'::jsonb,
    'active',
    NOW()
  );

  -- 3. Créer un employé (best-effort, non fatal)
  BEGIN
    INSERT INTO employees (
      tenant_id, name, email, position, department, hire_date, status
    ) VALUES (
      v_tenant,
      v_user_name,
      v_email,
      'Admin',
      'Direction',
      CURRENT_DATE,
      'active'
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Employee creation skipped: %', SQLERRM;
  END;

  -- 4. Bootstrap les données de référence (plan comptable, journaux, etc.)
  BEGIN
    PERFORM bootstrap_tenant(v_tenant);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'bootstrap_tenant skipped: %', SQLERRM;
  END;

  -- Retourner le tenant créé
  RETURN jsonb_build_object(
    'success', true,
    'tenant_id', v_tenant
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$$;

-- Grant execute au rôle authentifié
GRANT EXECUTE ON FUNCTION create_tenant_for_current_user(jsonb) TO authenticated;
