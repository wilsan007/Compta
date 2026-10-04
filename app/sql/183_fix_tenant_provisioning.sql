-- ============================================================
-- 183_fix_tenant_provisioning.sql — lot B du plan correctif du 21/09
--
-- AUD-B01  `currencies_code_unique` (UNIQUE(code) global) faisait échouer
--          bootstrap_tenant pour toute société : les devises de référence
--          (tenant_id NULL) occupent déjà EUR/USD/GBP.
-- AUD-B02  create_tenant_for_current_user avalait l'échec du bootstrap et
--          répondait succès : société sans plan, journaux, exercice ni paramètres.
-- AUD-B03  la devise de la société est créée si elle n'est pas dans les devises
--          par défaut (ex. DJF).
-- AUD-B04  assert_tenant_ready : une inscription n'aboutit que si la société
--          est utilisable.
-- Sécurité bootstrap_tenant et seed_standard_chart étaient SECURITY DEFINER,
--          exécutables par PUBLIC (donc anon) et sans contrôle d'appartenance.
--
-- Preuve : sql/182_signup_provisioning_tests.sql (S02, S04, S05).
-- ============================================================

-- ── AUD-B01 : unicité des devises par société, et parmi les devises de référence ──
ALTER TABLE currencies DROP CONSTRAINT IF EXISTS currencies_code_unique;
CREATE UNIQUE INDEX IF NOT EXISTS currencies_reference_code_key
  ON currencies (code) WHERE tenant_id IS NULL;

-- ── Contrôle d'appartenance commun aux fonctions de mise en service ──
-- Autorisé : un administrateur actif de la société, ou un contexte serveur sans
-- utilisateur (service_role, job, migration). Refusé : tout autre utilisateur.
CREATE OR REPLACE FUNCTION assert_can_provision_tenant(p_tenant_id uuid)
RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_role text := auth.role();
BEGIN
  IF v_uid IS NULL THEN
    IF COALESCE(v_role, 'service_role') IN ('service_role') THEN
      RETURN;
    END IF;
    RAISE EXCEPTION 'Mise en service refusée : utilisateur non authentifié';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM tenant_users
    WHERE tenant_id = p_tenant_id AND auth_id = v_uid
      AND status = 'active' AND role = 'admin'
  ) THEN
    RAISE EXCEPTION 'Mise en service refusée : vous n''êtes pas administrateur de cette société';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION assert_can_provision_tenant(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION assert_can_provision_tenant(uuid) TO authenticated, service_role;

-- ── AUD-B04 : une société est-elle utilisable ? ──
CREATE OR REPLACE FUNCTION assert_tenant_ready(p_tenant_id uuid)
RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_missing text[] := ARRAY[]::text[];
  v_journal text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM chart_accounts WHERE tenant_id = p_tenant_id) THEN
    v_missing := array_append(v_missing, 'plan comptable');
  END IF;
  FOREACH v_journal IN ARRAY ARRAY['VT', 'AC', 'BQ', 'OD', 'AN'] LOOP
    IF NOT EXISTS (SELECT 1 FROM journals WHERE tenant_id = p_tenant_id AND code = v_journal) THEN
      v_missing := array_append(v_missing, ('journal ' || v_journal));
    END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM fiscal_years WHERE tenant_id = p_tenant_id AND status = 'open') THEN
    v_missing := array_append(v_missing, 'exercice ouvert');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM company_settings WHERE tenant_id = p_tenant_id) THEN
    v_missing := array_append(v_missing, 'paramètres société');
  END IF;

  IF array_length(v_missing, 1) > 0 THEN
    RAISE EXCEPTION 'Société % incomplète après mise en service : %', p_tenant_id, array_to_string(v_missing, ', ');
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION assert_tenant_ready(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION assert_tenant_ready(uuid) TO authenticated, service_role;

-- ── seed_standard_chart : même contrôle, et plus d'accès direct depuis le client ──
-- Le corps (plan de référence) est inchangé ; on l'enveloppe dans un contrôle.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'seed_standard_chart_unchecked') THEN
    ALTER FUNCTION seed_standard_chart(uuid) RENAME TO seed_standard_chart_unchecked;
  END IF;
END $$;
REVOKE ALL ON FUNCTION seed_standard_chart_unchecked(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION seed_standard_chart(p_tenant_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  PERFORM assert_can_provision_tenant(p_tenant_id);
  PERFORM seed_standard_chart_unchecked(p_tenant_id);
END;
$$;

REVOKE ALL ON FUNCTION seed_standard_chart(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION seed_standard_chart(uuid) TO authenticated, service_role;

-- ── bootstrap_tenant : contrôle d'appartenance + devise de la société ──
CREATE OR REPLACE FUNCTION bootstrap_tenant(p_tenant_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_tenant record;
  v_year int := EXTRACT(YEAR FROM CURRENT_DATE)::int;
  v_fy_id uuid;
  v_period_start date;
  v_period_end date;
  v_labels text[] := ARRAY['Janvier','Fevrier','Mars','Avril','Mai','Juin','Juillet','Aout','Septembre','Octobre','Novembre','Decembre'];
BEGIN
  PERFORM assert_can_provision_tenant(p_tenant_id);

  SELECT * INTO v_tenant FROM tenants WHERE id = p_tenant_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tenant % not found', p_tenant_id;
  END IF;

  -- 1. CHART OF ACCOUNTS
  IF NOT EXISTS (SELECT 1 FROM chart_accounts WHERE tenant_id = p_tenant_id) THEN
    PERFORM seed_standard_chart_unchecked(p_tenant_id);
  END IF;

  -- 2. STANDARD JOURNALS
  INSERT INTO journals (code, name, type, account_counterpart, status, locked, tenant_id)
  VALUES
    ('VT', 'Journal des ventes',        'sale',     '411000', 'active', false, p_tenant_id),
    ('AC', 'Journal des achats',        'purchase', '401000', 'active', false, p_tenant_id),
    ('BQ', 'Journal de banque',         'bank',     '512000', 'active', false, p_tenant_id),
    ('CA', 'Journal de caisse',         'cash',     '530000', 'active', false, p_tenant_id),
    ('OD', 'Operations diverses',       'general',  NULL,     'active', false, p_tenant_id),
    ('AN', 'A-nouveaux',                'general',  NULL,     'active', false, p_tenant_id)
  ON CONFLICT (tenant_id, code) DO NOTHING;

  -- 3. CURRENCIES — devises par défaut + devise de la société (AUD-B03)
  INSERT INTO currencies (code, name, symbol, exchange_rate, tenant_id)
  VALUES
    ('EUR', 'Euro',            '€', 1.0,    p_tenant_id),
    ('USD', 'Dollar US',       '$', 1.08,   p_tenant_id),
    ('GBP', 'Livre Sterling',  '£', 0.85,   p_tenant_id)
  ON CONFLICT (tenant_id, code) DO NOTHING;

  IF v_tenant.currency IS NOT NULL THEN
    INSERT INTO currencies (code, name, symbol, exchange_rate, tenant_id)
    SELECT v_tenant.currency, COALESCE(ref.name, v_tenant.currency), COALESCE(ref.symbol, v_tenant.currency),
           COALESCE(ref.exchange_rate, 1.0), p_tenant_id
    FROM (SELECT 1) one
    LEFT JOIN currencies ref ON ref.tenant_id IS NULL AND ref.code = v_tenant.currency
    ON CONFLICT (tenant_id, code) DO NOTHING;
  END IF;

  -- 4. FISCAL YEAR + 12 MONTHLY PERIODS (current year)
  IF NOT EXISTS (SELECT 1 FROM fiscal_years WHERE tenant_id = p_tenant_id AND code = 'FY' || v_year) THEN
    INSERT INTO fiscal_years (code, start_date, end_date, status, tenant_id)
    VALUES ('FY' || v_year, make_date(v_year, 1, 1), make_date(v_year, 12, 31), 'open', p_tenant_id)
    RETURNING id INTO v_fy_id;

    FOR v_month IN 1 .. 12 LOOP
      v_period_start := make_date(v_year, v_month, 1);
      v_period_end := (v_period_start + INTERVAL '1 month - 1 day')::date;
      INSERT INTO fiscal_periods (fiscal_year_id, period_number, period_label, start_date, end_date, status, tenant_id)
      VALUES (v_fy_id, v_month, v_labels[v_month] || ' ' || v_year, v_period_start, v_period_end, 'open', p_tenant_id);
    END LOOP;
  END IF;

  -- 5. COMPANY SETTINGS
  IF NOT EXISTS (SELECT 1 FROM company_settings WHERE tenant_id = p_tenant_id) THEN
    INSERT INTO company_settings (name, legal_name, vat_number, siret, address, city, postal_code, country, currency, fiscal_year_start, tenant_id)
    VALUES (
      v_tenant.name,
      COALESCE(v_tenant.legal_name, v_tenant.name),
      v_tenant.vat_number,
      v_tenant.siret,
      v_tenant.address,
      v_tenant.city,
      v_tenant.postal_code,
      COALESCE(v_tenant.country, 'France'),
      COALESCE(v_tenant.currency, 'EUR'),
      '01-01',
      p_tenant_id
    );
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION bootstrap_tenant(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bootstrap_tenant(uuid) TO authenticated, service_role;

-- ── AUD-B02 : l'inscription échoue si la mise en service échoue ──
-- Corps repris de 158 ; seuls changent : le bootstrap n'est plus avalé, la société
-- est contrôlée, et la société créée est renvoyée (le client ne peut pas la relire
-- tant qu'elle n'est pas son tenant actif : la RLS de `tenants` l'en empêche).
CREATE OR REPLACE FUNCTION create_tenant_for_current_user(p_data jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tenant uuid;
  v_auth_id uuid := auth.uid();
  v_email text;
  v_user_name text;
  v_enabled_modules jsonb;
  v_claims jsonb;
BEGIN
  IF v_auth_id IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;

  BEGIN
    v_claims := COALESCE(current_setting('request.jwt.claims', true)::jsonb, '{}'::jsonb);
  EXCEPTION WHEN OTHERS THEN
    v_claims := '{}'::jsonb;
  END;

  v_email := COALESCE(
    v_claims ->> 'email',
    v_claims -> 'user_metadata' ->> 'email'
  );

  v_user_name := COALESCE(
    v_claims -> 'user_metadata' ->> 'name',
    v_claims -> 'user_metadata' ->> 'full_name',
    v_email
  );

  v_enabled_modules := COALESCE(
    NULLIF(p_data -> 'enabled_modules', 'null'::jsonb),
    '["home","accounting","commercial","treasury","stock","production","hr","dashboards","reporting","system"]'::jsonb
  );

  INSERT INTO tenants (
    name, legal_name, siren, siret, vat_number,
    address, city, postal_code, country, currency,
    email, phone, legislation_pack_code, country_code,
    enabled_modules, status, plan, trial_ends_at
  ) VALUES (
    p_data ->> 'name',
    COALESCE(p_data ->> 'legal_name', p_data ->> 'name'),
    p_data ->> 'siren',
    p_data ->> 'siret',
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
    COALESCE(p_data ->> 'plan', 'trial'),
    COALESCE((p_data ->> 'trial_ends_at')::timestamptz, (NOW() + INTERVAL '30 days')::timestamptz)
  )
  RETURNING id INTO v_tenant;

  INSERT INTO tenant_users (
    tenant_id, auth_id, email, name, role, permissions, status, accepted_at
  ) VALUES (
    v_tenant, v_auth_id, v_email, v_user_name, 'admin', '{}'::jsonb, 'active', NOW()
  );

  -- La fiche salarié de l'administrateur reste facultative
  BEGIN
    INSERT INTO employees (tenant_id, name, email, position, department, hire_date, status)
    VALUES (v_tenant, v_user_name, v_email, 'Admin', 'Direction', CURRENT_DATE, 'active');
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Employee creation skipped: %', SQLERRM;
  END;

  -- AUD-B02 : plus de rattrapage silencieux — un échec annule toute l'inscription
  PERFORM bootstrap_tenant(v_tenant);
  PERFORM assert_tenant_ready(v_tenant);

  RETURN jsonb_build_object(
    'success', true,
    'tenant_id', v_tenant,
    'tenant', (SELECT to_jsonb(t) FROM tenants t WHERE t.id = v_tenant)
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$$;

REVOKE ALL ON FUNCTION create_tenant_for_current_user(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION create_tenant_for_current_user(jsonb) TO authenticated;
