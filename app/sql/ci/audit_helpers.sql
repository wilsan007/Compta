-- ============================================================
-- ci/audit_helpers.sql — outillage des tests d'audit (AUD-A01/A02)
--
-- Inclus par les fichiers 178 à 182 via `\ir ci/audit_helpers.sql`.
--
-- Chaque scénario enregistre son verdict dans `_audit_results` au lieu de
-- s'arrêter au premier échec. En fin de fichier, `_audit_assert('<nnn>')`
-- confronte les verdicts au registre `ci/expected_failures.sql` :
--   - un échec hors registre    → la CI échoue (régression ou défaut nouveau) ;
--   - un succès inscrit au registre → la CI échoue aussi : le défaut est corrigé,
--     il faut le retirer du registre dans le même commit ;
--   - aucun verdict enregistré  → la CI échoue (un test qui ne vérifie rien).
--
-- Les scénarios s'exécutent sous le rôle `authenticated` (sans BYPASSRLS)
-- dès que le contexte est posé (`_as_user()`), comme un utilisateur réel.
-- ============================================================

CREATE TABLE IF NOT EXISTS _audit_results (
  id      serial PRIMARY KEY,
  file    text NOT NULL,
  test_id text NOT NULL,
  label   text NOT NULL,
  ok      boolean NOT NULL,
  detail  text
);
GRANT SELECT, INSERT ON _audit_results TO authenticated, service_role;
GRANT USAGE ON SEQUENCE _audit_results_id_seq TO authenticated, service_role;

CREATE TABLE IF NOT EXISTS _audit_expected (test_id text PRIMARY KEY, reason text NOT NULL);
TRUNCATE _audit_expected;
\ir expected_failures.sql

-- Verdict d'un scénario
CREATE OR REPLACE FUNCTION _rec(p_id text, p_label text, p_ok boolean, p_detail text)
RETURNS void LANGUAGE sql AS $$
  INSERT INTO _audit_results (file, test_id, label, ok, detail)
  VALUES (current_setting('audit.file'), p_id, p_label, COALESCE(p_ok, false), p_detail)
$$;

-- Société de test isolée, contexte posé comme PostgREST le ferait.
-- S'exécute en superutilisateur (écrit dans auth.users) : appeler AVANT _as_user().
-- Comme une société réelle depuis la 183, elle reçoit le plan comptable standard ;
-- p_fy crée l'exercice 2026 (sans périodes). Un scénario qui pose ses propres
-- exercices passe p_fy = false.
DROP FUNCTION IF EXISTS _mk_tenant(text);
CREATE OR REPLACE FUNCTION _mk_tenant(p_name text, p_fy boolean DEFAULT true) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE t uuid := uuid_generate_v4(); a uuid := uuid_generate_v4();
BEGIN
  INSERT INTO auth.users (id, email) VALUES (a, lower(p_name) || '-' || a || '@audit.test');
  PERFORM set_config('request.jwt.claim.sub', a::text, false);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated', 'email', lower(p_name) || '@audit.test')::text, false);
  INSERT INTO tenants (id, name, plan, status, currency, created_at) VALUES (t, p_name, 'trial', 'active', 'EUR', now());
  INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status, created_at)
    VALUES (t, a, lower(p_name) || '@audit.test', 'Admin', 'admin', 'active', now());
  INSERT INTO company_settings (tenant_id, name, currency, country, fiscal_year_start, created_at)
    VALUES (t, p_name, 'EUR', 'France', '2025-01-01', now()) ON CONFLICT DO NOTHING;
  INSERT INTO journals (tenant_id, code, name, type, status, next_number) VALUES
    (t, 'OD', 'Opérations diverses', 'general', 'active', 1),
    (t, 'VT', 'Ventes', 'sale', 'active', 1),
    (t, 'AC', 'Achats', 'purchase', 'active', 1),
    (t, 'BQ', 'Banque', 'bank', 'active', 1)
  ON CONFLICT DO NOTHING;
  PERFORM seed_standard_chart_unchecked(t);
  IF p_fy THEN
    INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status) VALUES (t, '2026', '2026-01-01', '2026-12-31', 'open');
  END IF;
  PERFORM set_config('app.active_tenant_id', t::text, false);
  IF current_tenant_id() IS DISTINCT FROM t THEN
    RAISE EXCEPTION 'Contexte tenant non établi — le test ne prouverait rien';
  END IF;
  RETURN t;
END $$;

-- Passe sous le rôle d'un utilisateur connecté jusqu'à la fin de la transaction
CREATE OR REPLACE FUNCTION _as_user() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('role', 'authenticated', true);
END $$;

-- Écriture brouillon + lignes, puis validation si demandé.
-- p_lines : [{"a": compte, "d": débit, "c": crédit, "t": auxiliaire}]
CREATE OR REPLACE FUNCTION _entry(p_t uuid, p_num text, p_date date, p_lines jsonb,
  p_post boolean DEFAULT true, p_journal text DEFAULT 'OD')
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE e uuid;
BEGIN
  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description)
  VALUES (p_t, p_num, p_date, p_journal, 'draft', p_num) RETURNING id INTO e;
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_tiers, debit, credit, description)
  SELECT p_t, e, x->>'a', x->>'a', x->>'t', COALESCE((x->>'d')::numeric, 0), COALESCE((x->>'c')::numeric, 0), p_num
  FROM jsonb_array_elements(p_lines) x;
  IF p_post THEN UPDATE journal_entries SET status = 'posted' WHERE id = e; END IF;
  RETURN e;
END $$;

-- Confronte les verdicts d'un fichier au registre des échecs attendus
CREATE OR REPLACE FUNCTION _audit_assert(p_file text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  v_total int; v_ok int; v_expected_red int;
  v_regressions text; v_fixed text; r record;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE ok) INTO v_total, v_ok
  FROM _audit_results WHERE file = p_file;

  FOR r IN SELECT test_id, ok, label, detail FROM _audit_results WHERE file = p_file ORDER BY id LOOP
    RAISE NOTICE '% % — % | %',
      CASE WHEN r.ok THEN '✅' WHEN EXISTS (SELECT 1 FROM _audit_expected e WHERE e.test_id = r.test_id) THEN '🟠' ELSE '❌' END,
      r.test_id, r.label, left(COALESCE(r.detail, ''), 200);
  END LOOP;

  IF v_total = 0 THEN
    RAISE EXCEPTION '[%] aucun verdict enregistré — le fichier ne vérifie rien', p_file;
  END IF;

  SELECT string_agg(ar.test_id || ' (' || ar.label || ')', ', ') INTO v_regressions
  FROM _audit_results ar
  WHERE ar.file = p_file AND NOT ar.ok
    AND NOT EXISTS (SELECT 1 FROM _audit_expected e WHERE e.test_id = ar.test_id);

  SELECT string_agg(ar.test_id, ', ') INTO v_fixed
  FROM _audit_results ar
  WHERE ar.file = p_file AND ar.ok
    AND EXISTS (SELECT 1 FROM _audit_expected e WHERE e.test_id = ar.test_id);

  SELECT count(*) INTO v_expected_red FROM _audit_results ar
  WHERE ar.file = p_file AND NOT ar.ok AND EXISTS (SELECT 1 FROM _audit_expected e WHERE e.test_id = ar.test_id);

  RAISE NOTICE '[%] % scénario(s) : % vert(s), % rouge(s) attendu(s) au registre', p_file, v_total, v_ok, v_expected_red;

  IF v_regressions IS NOT NULL THEN
    RAISE EXCEPTION '[%] échec(s) hors registre : %', p_file, v_regressions;
  END IF;
  IF v_fixed IS NOT NULL THEN
    RAISE EXCEPTION '[%] corrigé(s) mais encore au registre — retirer de ci/expected_failures.sql : %', p_file, v_fixed;
  END IF;
END $$;
