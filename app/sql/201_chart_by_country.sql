-- ============================================================
-- 201_chart_by_country.sql — plan comptable par pays
--
-- Décision du 21/09/2026 :
--   - une société ne reçoit plus automatiquement le PCG français ;
--   - France : PCG (pack FR) ;
--   - Djibouti : plan de Djibouti (pack DJ) dès qu'il est publié ; en attendant,
--     PCG français à titre PROVISOIRE (tenants.chart_provisional = true) ;
--   - tout autre pays : inscription refusée (PAYS_NON_DISPONIBLE) tant qu'aucun
--     plan n'est publié pour lui ;
--   - le plan d'un pays est téléversé par un administrateur de la plateforme
--     (écran « Plans comptables », CSV) puis publié ; la publication bascule
--     automatiquement les sociétés du pays qui sont au plan provisoire ET n'ont
--     aucune écriture validée. Les autres sont listées (transposition manuelle).
--
-- Depuis la 187, une écriture sur un compte absent du plan est refusée : un plan
-- n'est publiable que s'il contient les comptes imputés par les écritures
-- automatiques (chart_required_accounts), par le paramétrage TVA global
-- (vat_account_mapping) et par le paramétrage de paie global s'il existe.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Données
-- ------------------------------------------------------------
-- Pack Djibouti : créé à la main en prod, absent des migrations (repris à l'identique)
-- tenant_id : même rattachement que les autres packs globaux (celui du pack FR)
INSERT INTO legislation_packs (code, name, country_code, country_name, accounting_standard, currency, currency_decimals, date_format, locale, fiscal_year_start, tax_id_label, tax_id_secondary_label, is_default, active, tenant_id)
SELECT 'DJ', 'Djibouti — Plan Comptable', 'DJ', 'Djibouti', 'PCG', 'DJF', 0, 'DD/MM/YYYY', 'fr-DJ', '01-01', 'N° NIF', 'RCCM', false, true,
       (SELECT tenant_id FROM legislation_packs WHERE code = 'FR')
ON CONFLICT (code) DO NOTHING;

ALTER TABLE tenants ADD COLUMN IF NOT EXISTS chart_pack_code text REFERENCES legislation_packs(code);
ALTER TABLE tenants ADD COLUMN IF NOT EXISTS chart_provisional boolean NOT NULL DEFAULT false;

-- État de publication du plan de chaque pack (le pack FR est le PCG historique,
-- semé par seed_standard_chart_unchecked et non par chart_account_templates)
CREATE TABLE IF NOT EXISTS chart_pack_status (
  pack_code     text PRIMARY KEY REFERENCES legislation_packs(code) ON DELETE CASCADE,
  status        text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published')),
  account_count int  NOT NULL DEFAULT 0,
  uploaded_by   uuid,
  uploaded_at   timestamptz,
  published_by  uuid,
  published_at  timestamptz,
  source        text NOT NULL DEFAULT 'chart_account_templates'
);
INSERT INTO chart_pack_status (pack_code, status, source, published_at)
VALUES ('FR', 'published', 'seed_standard_chart', now())
ON CONFLICT (pack_code) DO NOTHING;

-- Plan provisoire d'un pays tant que le sien n'est pas publié (exception Djibouti)
CREATE TABLE IF NOT EXISTS chart_provisional_fallbacks (
  country_code  text PRIMARY KEY,
  fallback_pack text NOT NULL REFERENCES legislation_packs(code)
);
INSERT INTO chart_provisional_fallbacks VALUES ('DJ', 'FR') ON CONFLICT DO NOTHING;

-- Comptes qu'un plan de pays doit contenir pour être publiable
CREATE TABLE IF NOT EXISTS chart_required_accounts (
  code   text NOT NULL,
  source text NOT NULL,
  reason text NOT NULL,
  PRIMARY KEY (code, source)
);
INSERT INTO chart_required_accounts (code, source, reason) VALUES
  -- 187 : écritures automatiques (ventes, achats, règlements, paie, stock, production, change)
  ('411000', '187', 'collectif clients'), ('401000', '187', 'collectif fournisseurs'),
  ('707000', '187', 'ventes de marchandises'), ('607000', '187', 'achats de marchandises'),
  ('601000', '187', 'achats de matières premières'), ('445710', '187', 'TVA collectée (repli)'),
  ('445660', '187', 'TVA déductible (repli)'), ('512000', '187', 'banque'),
  ('530000', '187', 'caisse'), ('531000', '187', 'caisse (siège)'),
  ('421000', '187', 'rémunérations dues'), ('431000', '187', 'sécurité sociale'),
  ('641000', '187', 'rémunérations du personnel'), ('645000', '187', 'charges sociales'),
  ('310000', '187', 'stocks de matières'), ('355000', '187', 'stocks de produits finis'),
  ('713500', '187', 'variation des stocks de produits'), ('654000', '187', 'créances irrécouvrables'),
  ('665000', '187', 'escomptes accordés'), ('666000', '187', 'pertes de change'),
  ('766000', '187', 'gains de change'),
  -- clôture de l'exercice
  ('120000', 'clôture', 'résultat de l''exercice (bénéfice)'),
  ('129000', 'clôture', 'résultat de l''exercice (perte)'),
  -- lots E/F/G (migrations 190-192, session V3)
  ('707000', 'lot E/F/G', 'ventes'), ('709000', 'lot E/F/G', 'rabais accordés'),
  ('419100', 'lot E/F/G', 'avances clients'), ('409100', 'lot E/F/G', 'avances fournisseurs'),
  ('609000', 'lot E/F/G', 'rabais obtenus'), ('530000', 'lot E/F/G', 'caisse'),
  ('625100', 'lot E/F/G', 'frais de déplacement'), ('641400', 'lot E/F/G', 'indemnités'),
  ('647800', 'lot E/F/G', 'autres charges sociales'), ('425000', 'lot E/F/G', 'avances au personnel'),
  ('427000', 'lot E/F/G', 'oppositions sur salaires'), ('447000', 'lot E/F/G', 'autres impôts'),
  ('445710', 'lot E/F/G', 'TVA collectée (repli avoirs)'), ('445660', 'lot E/F/G', 'TVA déductible (repli achats)'),
  ('411000', 'lot E/F/G', 'collectif clients'), ('401000', 'lot E/F/G', 'collectif fournisseurs'),
  ('512000', 'lot E/F/G', 'banque par défaut')
ON CONFLICT DO NOTHING;

-- Administrateurs de la plateforme (éditeur) : seuls habilités à publier un plan
CREATE TABLE IF NOT EXISTS platform_admins (
  auth_id    uuid PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Journal des bascules de plan
CREATE TABLE IF NOT EXISTS chart_pack_switch_log (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  from_pack   text,
  to_pack     text NOT NULL,
  switched    boolean NOT NULL,
  detail      jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE chart_pack_status ENABLE ROW LEVEL SECURITY;
ALTER TABLE chart_provisional_fallbacks ENABLE ROW LEVEL SECURITY;
ALTER TABLE chart_required_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE platform_admins ENABLE ROW LEVEL SECURITY;
ALTER TABLE chart_pack_switch_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS select_chart_pack_status ON chart_pack_status;
CREATE POLICY select_chart_pack_status ON chart_pack_status FOR SELECT USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS select_chart_required_accounts ON chart_required_accounts;
CREATE POLICY select_chart_required_accounts ON chart_required_accounts FOR SELECT USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS select_chart_pack_switch_log ON chart_pack_switch_log;
CREATE POLICY select_chart_pack_switch_log ON chart_pack_switch_log FOR SELECT USING (tenant_id = current_tenant_id());
-- platform_admins, chart_provisional_fallbacks : lus seulement par les fonctions

-- Les modèles de plan ne sont modifiables que par les fonctions ci-dessous
REVOKE INSERT, UPDATE, DELETE ON chart_account_templates FROM anon, authenticated;

-- ------------------------------------------------------------
-- 2. Résolution pays → plan
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION is_platform_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT EXISTS (SELECT 1 FROM platform_admins WHERE auth_id = auth.uid());
$$;

-- Code ISO du pays : code explicite, sinon nom du pays (legislation_packs.country_name)
CREATE OR REPLACE FUNCTION normalize_country_code(p_country text, p_code text DEFAULT NULL)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT COALESCE(
    (SELECT lp.country_code FROM legislation_packs lp
      WHERE lower(lp.country_name) = lower(btrim(p_country)) ORDER BY lp.is_default DESC, lp.code LIMIT 1),
    CASE WHEN p_code ~ '^[A-Za-z]{2}$' THEN upper(p_code) END
  );
$$;

-- Plan attribué à une société du pays : son plan publié, sinon le plan provisoire
-- prévu pour ce pays, sinon rien (pays non disponible)
CREATE OR REPLACE FUNCTION chart_pack_for_country(p_country_code text)
RETURNS TABLE (pack_code text, provisional boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT pack_code, provisional FROM (
    SELECT s.pack_code, false AS provisional, 1 AS prio
    FROM chart_pack_status s JOIN legislation_packs lp ON lp.code = s.pack_code
    WHERE s.status = 'published' AND lp.country_code = upper(p_country_code)
    UNION ALL
    SELECT f.fallback_pack, true, 2 FROM chart_provisional_fallbacks f
    WHERE f.country_code = upper(p_country_code)
  ) c ORDER BY prio, pack_code LIMIT 1;
$$;

-- Pays proposés à l'inscription (les autres sont « Bientôt disponible »)
CREATE OR REPLACE FUNCTION available_signup_countries()
RETURNS TABLE (country_code text, country_name text, pack_code text, provisional boolean, currency text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT DISTINCT ON (lp.country_code) lp.country_code, lp.country_name, c.pack_code, c.provisional, lp.currency
  FROM legislation_packs lp
  CROSS JOIN LATERAL chart_pack_for_country(lp.country_code) c
  WHERE c.pack_code IS NOT NULL
  ORDER BY lp.country_code, lp.is_default DESC, lp.code;
$$;

-- Comptes obligatoires absents d'un plan téléversé
CREATE OR REPLACE FUNCTION chart_pack_missing_required(p_pack text)
RETURNS text[] LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_missing text[];
  v_payroll text[] := '{}';
  v_payroll_table text;
BEGIN
  -- Table du lot F (191) : absente tant que cette migration n'est pas passée
  SELECT c.relname INTO v_payroll_table FROM pg_class c WHERE c.oid = to_regclass('public.payroll_account_mapping');
  -- Paramétrage de paie global (payroll_account_mapping, lot F) s'il existe
  IF v_payroll_table IS NOT NULL
     AND EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = 'payroll_account_mapping' AND column_name = 'account_code')
     AND EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = 'payroll_account_mapping' AND column_name = 'tenant_id') THEN
    EXECUTE format('SELECT COALESCE(array_agg(DISTINCT account_code), ''{}'') FROM public.%I
                    WHERE tenant_id IS NULL AND account_code IS NOT NULL', v_payroll_table) INTO v_payroll;
  END IF;

  SELECT array_agg(code ORDER BY code) INTO v_missing FROM (
    SELECT code FROM chart_required_accounts
    UNION SELECT account_code FROM vat_account_mapping
          WHERE tenant_id = '00000000-0000-0000-0000-000000000000' AND account_code IS NOT NULL
    UNION SELECT unnest(v_payroll)
  ) r
  WHERE NOT EXISTS (SELECT 1 FROM chart_account_templates t WHERE t.pack_code = p_pack AND t.code = r.code);
  RETURN COALESCE(v_missing, '{}');
END $$;

-- ------------------------------------------------------------
-- 3. Téléversement (brouillon) et publication
-- ------------------------------------------------------------
-- p_rows : [{"code":"411000","name":"Clients","type":"asset","parent_code":"41","vat_rate":null}, …]
CREATE OR REPLACE FUNCTION upload_chart_pack(p_pack text, p_rows jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_errors jsonb;
  v_count int;
BEGIN
  IF NOT is_platform_admin() THEN
    RAISE EXCEPTION 'ACCES_REFUSE: réservé aux administrateurs de la plateforme' USING ERRCODE = '42501';
  END IF;
  IF p_pack = 'FR' THEN
    RAISE EXCEPTION 'PACK_PROTEGE: le PCG français (pack FR) n''est pas remplaçable par téléversement';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM legislation_packs WHERE code = p_pack) THEN
    RAISE EXCEPTION 'PACK_INCONNU: %', p_pack;
  END IF;
  IF EXISTS (SELECT 1 FROM chart_pack_status WHERE pack_code = p_pack AND status = 'published') THEN
    RAISE EXCEPTION 'PACK_PUBLIE: le plan % est publié, il ne peut plus être remplacé', p_pack;
  END IF;
  IF jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
    RAISE EXCEPTION 'FICHIER_VIDE: aucune ligne de compte';
  END IF;

  -- Contrôle ligne par ligne (numéro de ligne = position dans le fichier, en-tête exclu)
  SELECT jsonb_agg(e ORDER BY (e->>'line')::int) INTO v_errors FROM (
    SELECT jsonb_build_object('line', n + 1, 'code', r->>'code', 'error', err) AS e
    FROM jsonb_array_elements(p_rows) WITH ORDINALITY x(r, n)
    CROSS JOIN LATERAL (VALUES
      (CASE WHEN COALESCE(btrim(r->>'code'), '') !~ '^[0-9A-Za-z]{1,20}$' THEN 'code de compte invalide' END),
      (CASE WHEN COALESCE(btrim(r->>'name'), '') = '' THEN 'libellé manquant' END),
      (CASE WHEN COALESCE(r->>'type', '') NOT IN ('asset', 'liability', 'equity', 'income', 'expense')
            THEN 'type invalide (asset, liability, equity, income, expense)' END)
    ) v(err)
    WHERE err IS NOT NULL
    UNION ALL
    SELECT jsonb_build_object('line', min(n) + 1, 'code', btrim(r->>'code'), 'error', 'code en double')
    FROM jsonb_array_elements(p_rows) WITH ORDINALITY x(r, n)
    GROUP BY btrim(r->>'code') HAVING count(*) > 1
  ) errs;

  IF v_errors IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'errors', v_errors);
  END IF;

  DELETE FROM chart_account_templates WHERE pack_code = p_pack;
  INSERT INTO chart_account_templates (pack_code, code, name, type, vat_rate, parent_code, sort_order)
  SELECT p_pack, btrim(r->>'code'), btrim(r->>'name'), r->>'type', NULLIF(btrim(r->>'vat_rate'), ''),
         NULLIF(btrim(r->>'parent_code'), ''), n::int
  FROM jsonb_array_elements(p_rows) WITH ORDINALITY x(r, n);
  GET DIAGNOSTICS v_count = ROW_COUNT;

  INSERT INTO chart_pack_status (pack_code, status, account_count, uploaded_by, uploaded_at)
  VALUES (p_pack, 'draft', v_count, auth.uid(), now())
  ON CONFLICT (pack_code) DO UPDATE
    SET status = 'draft', account_count = EXCLUDED.account_count,
        uploaded_by = EXCLUDED.uploaded_by, uploaded_at = EXCLUDED.uploaded_at;

  RETURN jsonb_build_object('success', true, 'pack', p_pack, 'accounts', v_count,
    'missing_required', to_jsonb(chart_pack_missing_required(p_pack)));
END $$;

-- Remplace le plan d'une société par celui d'un pack publié (sans écriture validée)
CREATE OR REPLACE FUNCTION apply_chart_pack(p_tenant uuid, p_pack text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_from text;
  v_acc record;
  v_deleted int := 0;
  v_closed text[] := '{}';
  v_upserted int;
BEGIN
  SELECT chart_pack_code INTO v_from FROM tenants WHERE id = p_tenant FOR UPDATE;

  IF EXISTS (SELECT 1 FROM journal_entries WHERE tenant_id = p_tenant AND status = 'posted') THEN
    INSERT INTO chart_pack_switch_log (tenant_id, from_pack, to_pack, switched, detail)
    VALUES (p_tenant, v_from, p_pack, false, jsonb_build_object('reason', 'ecritures_validees'));
    RETURN jsonb_build_object('tenant_id', p_tenant, 'switched', false, 'reason', 'ecritures_validees');
  END IF;

  -- Comptes du nouveau plan : ajoutés, ou repris (libellé, type) et rouverts
  INSERT INTO chart_accounts (tenant_id, code, name, type, vat_rate, deprecated)
  SELECT p_tenant, t.code, t.name, t.type, t.vat_rate, false
  FROM chart_account_templates t WHERE t.pack_code = p_pack
  ON CONFLICT (tenant_id, code) DO UPDATE
    SET name = EXCLUDED.name, type = EXCLUDED.type, vat_rate = EXCLUDED.vat_rate, deprecated = false;
  GET DIAGNOSTICS v_upserted = ROW_COUNT;

  -- Comptes de l'ancien plan absents du nouveau : supprimés s'ils ne servent à rien,
  -- sinon fermés (un brouillon qui les utilise sera refusé à la validation)
  FOR v_acc IN
    SELECT ca.id, ca.code FROM chart_accounts ca
    WHERE ca.tenant_id = p_tenant
      AND NOT EXISTS (SELECT 1 FROM chart_account_templates t WHERE t.pack_code = p_pack AND t.code = ca.code)
    ORDER BY ca.code DESC
  LOOP
    IF EXISTS (SELECT 1 FROM journal_lines jl WHERE jl.tenant_id = p_tenant
               AND v_acc.code IN (jl.account_code, jl.account_general, jl.account_tiers)) THEN
      UPDATE chart_accounts SET deprecated = true WHERE id = v_acc.id;
      v_closed := v_closed || v_acc.code;
    ELSE
      BEGIN
        DELETE FROM chart_accounts WHERE id = v_acc.id;
        v_deleted := v_deleted + 1;
      EXCEPTION WHEN foreign_key_violation THEN
        UPDATE chart_accounts SET deprecated = true WHERE id = v_acc.id;
        v_closed := v_closed || v_acc.code;
      END;
    END IF;
  END LOOP;

  UPDATE tenants SET chart_pack_code = p_pack, chart_provisional = false WHERE id = p_tenant;

  INSERT INTO chart_pack_switch_log (tenant_id, from_pack, to_pack, switched, detail)
  VALUES (p_tenant, v_from, p_pack, true,
          jsonb_build_object('accounts', v_upserted, 'deleted', v_deleted, 'closed', to_jsonb(v_closed)));
  RETURN jsonb_build_object('tenant_id', p_tenant, 'switched', true, 'accounts', v_upserted,
                            'deleted', v_deleted, 'closed', to_jsonb(v_closed));
END $$;

CREATE OR REPLACE FUNCTION publish_chart_pack(p_pack text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_status record;
  v_country text;
  v_missing text[];
  v_t record;
  v_results jsonb := '[]'::jsonb;
BEGIN
  IF NOT is_platform_admin() THEN
    RAISE EXCEPTION 'ACCES_REFUSE: réservé aux administrateurs de la plateforme' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_status FROM chart_pack_status WHERE pack_code = p_pack FOR UPDATE;
  IF NOT FOUND OR v_status.account_count = 0 THEN
    RAISE EXCEPTION 'PACK_VIDE: aucun plan téléversé pour %', p_pack;
  END IF;
  IF v_status.status = 'published' THEN
    RAISE EXCEPTION 'PACK_PUBLIE: le plan % est déjà publié', p_pack;
  END IF;

  v_missing := chart_pack_missing_required(p_pack);
  IF cardinality(v_missing) > 0 THEN
    RAISE EXCEPTION 'COMPTES_MANQUANTS: le plan % ne contient pas les comptes imputés par les écritures automatiques : %',
      p_pack, array_to_string(v_missing, ', ');
  END IF;

  UPDATE chart_pack_status SET status = 'published', published_by = auth.uid(), published_at = now()
  WHERE pack_code = p_pack;

  -- Bascule automatique des sociétés du pays restées au plan provisoire
  SELECT country_code INTO v_country FROM legislation_packs WHERE code = p_pack;
  FOR v_t IN
    SELECT id FROM tenants WHERE country_code = v_country AND chart_provisional ORDER BY created_at
  LOOP
    v_results := v_results || apply_chart_pack(v_t.id, p_pack);
  END LOOP;

  RETURN jsonb_build_object('success', true, 'pack', p_pack, 'country', v_country, 'tenants', v_results);
END $$;

-- ------------------------------------------------------------
-- 4. Inscription et mise en service
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_tenant_for_current_user(p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_tenant uuid;
  v_auth_id uuid := auth.uid();
  v_email text;
  v_user_name text;
  v_enabled_modules jsonb;
  v_claims jsonb;
  v_country_code text;
  v_chart record;
  v_lp record;
BEGIN
  IF v_auth_id IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;

  -- Pays → plan comptable (201) : pas de PCG français par défaut
  v_country_code := normalize_country_code(p_data ->> 'country', NULL);
  IF v_country_code IS NULL AND p_data ->> 'legislation_pack_code' IS NOT NULL THEN
    SELECT country_code INTO v_country_code FROM legislation_packs WHERE code = p_data ->> 'legislation_pack_code';
  END IF;
  SELECT * INTO v_chart FROM chart_pack_for_country(v_country_code);
  IF v_chart.pack_code IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'PAYS_NON_DISPONIBLE',
      'message', format('Le pays %s n''est pas encore disponible : aucun plan comptable publié.',
                        COALESCE(p_data ->> 'country', v_country_code, '(non renseigné)')));
  END IF;
  SELECT * INTO v_lp FROM legislation_packs WHERE country_code = v_country_code
  ORDER BY (code = p_data ->> 'legislation_pack_code') DESC, is_default DESC, code LIMIT 1;

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
    chart_pack_code, chart_provisional,
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
    COALESCE(p_data ->> 'country', v_lp.country_name),
    COALESCE(p_data ->> 'currency', v_lp.currency),
    COALESCE(p_data ->> 'email', v_email),
    p_data ->> 'phone',
    v_lp.code,
    v_country_code,
    v_chart.pack_code,
    v_chart.provisional,
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
    'chart_pack_code', v_chart.pack_code,
    'chart_provisional', v_chart.provisional,
    'tenant', (SELECT to_jsonb(t) FROM tenants t WHERE t.id = v_tenant)
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.bootstrap_tenant(p_tenant_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_tenant record;
  v_pack text;
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

  -- 1. CHART OF ACCOUNTS — plan du pack attribué à la société (201)
  IF NOT EXISTS (SELECT 1 FROM chart_accounts WHERE tenant_id = p_tenant_id) THEN
    v_pack := v_tenant.chart_pack_code;
    IF v_pack IS NULL THEN
      SELECT pack_code INTO v_pack FROM chart_pack_for_country(v_tenant.country_code);
    END IF;
    IF v_pack IS NULL THEN
      RAISE EXCEPTION 'PAYS_NON_DISPONIBLE: aucun plan comptable pour le pays %', COALESCE(v_tenant.country_code, v_tenant.country);
    END IF;

    IF v_pack = 'FR' THEN
      PERFORM seed_standard_chart_unchecked(p_tenant_id);
    ELSE
      IF NOT EXISTS (SELECT 1 FROM chart_pack_status WHERE pack_code = v_pack AND status = 'published') THEN
        RAISE EXCEPTION 'PACK_NON_PUBLIE: le plan % n''est pas publié', v_pack;
      END IF;
      INSERT INTO chart_accounts (tenant_id, code, name, type, vat_rate, deprecated)
      SELECT p_tenant_id, t.code, t.name, t.type, t.vat_rate, false
      FROM chart_account_templates t WHERE t.pack_code = v_pack
      ON CONFLICT (tenant_id, code) DO NOTHING;
      PERFORM seed_vat_accounts(p_tenant_id);
    END IF;
    UPDATE tenants SET chart_pack_code = v_pack WHERE id = p_tenant_id AND chart_pack_code IS NULL;
  END IF;

  -- 2. STANDARD JOURNALS (AUD-C09 : y compris CL, ST, OF, POS des écritures automatiques)
  PERFORM ensure_standard_journals(p_tenant_id);

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
  -- Un exercice existant qui couvre déjà l'année (autre code) suffit : pas de chevauchement
  IF NOT EXISTS (SELECT 1 FROM fiscal_years WHERE tenant_id = p_tenant_id
                 AND daterange(start_date, end_date, '[]') && daterange(make_date(v_year, 1, 1), make_date(v_year, 12, 31), '[]')) THEN
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

  -- 5. COMPANY SETTINGS (201 : plus de pays « France » par défaut)
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
      COALESCE(v_tenant.country,
               (SELECT country_name FROM legislation_packs WHERE code = v_tenant.legislation_pack_code)),
      COALESCE(v_tenant.currency,
               (SELECT currency FROM legislation_packs WHERE code = v_tenant.legislation_pack_code)),
      '01-01',
      p_tenant_id
    );
  END IF;
END;
$function$;

-- ------------------------------------------------------------
-- 4 bis. Comptes encore ouverts au moment de la validation
--    journal_line_account_guard (187) ne contrôle une ligne qu'à sa saisie : un
--    brouillon dont un compte a été fermé depuis (bascule de plan, clôture manuelle
--    d'un compte) se validait quand même. Le contrôle est refait à la validation.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION journal_entry_accounts_open_on_post()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_bad text;
  -- Pendant close_fiscal_year (drapeau posé par la 189), un compte fermé ou de
  -- regroupement qui porte encore un solde doit pouvoir être soldé et reporté :
  -- seul « absent du plan » reste bloquant, comme dans journal_line_account_guard.
  v_closing boolean := COALESCE(current_setting('app.closing_in_progress', true), '') <> '';
BEGIN
  IF NEW.status = 'posted' AND OLD.status IS DISTINCT FROM 'posted' THEN
    SELECT string_agg(DISTINCT format('%s (%s)', c.code,
             CASE WHEN ca.id IS NULL THEN 'absent du plan'
                  WHEN ca.deprecated THEN 'fermé'
                  ELSE 'compte de regroupement' END), ', ')
    INTO v_bad
    FROM journal_lines jl
    CROSS JOIN LATERAL (VALUES (jl.account_code), (NULLIF(jl.account_general, jl.account_code))) c(code)
    LEFT JOIN chart_accounts ca ON ca.tenant_id = jl.tenant_id AND ca.code = c.code
    WHERE jl.journal_id = NEW.id AND c.code IS NOT NULL
      AND (jl.debit <> 0 OR jl.credit <> 0)
      AND (ca.id IS NULL
           OR (NOT v_closing AND (ca.deprecated
               OR EXISTS (SELECT 1 FROM chart_accounts ch WHERE ch.parent_id = ca.id))));
    IF v_bad IS NOT NULL THEN
      RAISE EXCEPTION 'Validation impossible : compte(s) non imputable(s) : %', v_bad
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS tg_journal_entry_accounts_open_on_post ON journal_entries;
CREATE TRIGGER tg_journal_entry_accounts_open_on_post
  BEFORE UPDATE OF status ON journal_entries
  FOR EACH ROW EXECUTE FUNCTION journal_entry_accounts_open_on_post();

-- ------------------------------------------------------------
-- 5. Droits
-- ------------------------------------------------------------
REVOKE ALL ON FUNCTION apply_chart_pack(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION upload_chart_pack(text, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION publish_chart_pack(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION chart_pack_missing_required(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION available_signup_countries() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION upload_chart_pack(text, jsonb), publish_chart_pack(text),
  chart_pack_missing_required(text), available_signup_countries(), is_platform_admin()
  TO authenticated;

-- ------------------------------------------------------------
-- 6. Sociétés existantes
-- ------------------------------------------------------------
-- Code pays déduit du nom du pays quand il le contredit (ex. société « Djibouti »
-- enregistrée avec country_code FR)
UPDATE tenants t SET country_code = n.cc
FROM (SELECT id, normalize_country_code(country, NULL) AS cc FROM tenants) n
WHERE n.id = t.id AND n.cc IS NOT NULL AND t.country_code IS DISTINCT FROM n.cc;

-- Toutes les sociétés existantes ont reçu le PCG (seed_standard_chart) ; celles d'un
-- pays à plan provisoire le gardent à titre provisoire jusqu'à la publication du leur
UPDATE tenants t SET chart_pack_code = 'FR',
       chart_provisional = EXISTS (SELECT 1 FROM chart_provisional_fallbacks f WHERE f.country_code = t.country_code)
WHERE t.chart_pack_code IS NULL;
