-- ============================================================
-- 710_crm_scoring_rules_tests.sql — F.5 / CRM-02 :
--   UN SCORE QUI DIT D'OÙ IL VIENT, ET QUI NE SE TROMPE PAS
--
--   T01  RLS FORCÉE sur `crm_scoring_rules`
--   T02  le moteur additionne les règles qui matchent (contre-épreuve : 20 + 30)
--   T03  une règle INACTIVE ne compte pas
--   T04  `equals` ne matche pas une autre valeur
--   T05  `greater_than` compare en NOMBRE — un fait non numérique ne matche pas
--   T06  des points NÉGATIFS se déduisent
--   T07  isolation : les règles d'une AUTRE société ne comptent pas
--   T08  le nom d'une règle est UNIQUE par société
--   T09  opérateur hors vocabulaire, et comparaison sans valeur (CHECK)
--   T10  `anon` n'a aucun droit, ni sur la table, ni sur la fonction
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '710', false);
DELETE FROM _audit_results WHERE file = '710';

DO $$
DECLARE v boolean;
BEGIN
  SELECT relforcerowsecurity INTO v FROM pg_class WHERE relname = 'crm_scoring_rules';
  PERFORM _rec('T01', 'RLS FORCÉE sur `crm_scoring_rules`',
    v IS TRUE, format('relforcerowsecurity = %s', COALESCE(v::text, 'NULL')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'RLS forcée', false, SQLERRM);
END $$;

DO $$
DECLARE privs text; fn boolean;
BEGIN
  SELECT string_agg(DISTINCT privilege_type, ',') INTO privs
    FROM information_schema.role_table_grants
   WHERE grantee = 'anon' AND table_name = 'crm_scoring_rules';
  fn := has_function_privilege('anon', 'public.crm_lead_score(jsonb)', 'EXECUTE');
  PERFORM _rec('T10', '`anon` n''a aucun droit — ni sur la table, ni sur la fonction de score',
    privs IS NULL AND fn IS FALSE,
    format('droits d''anon = %s ; EXECUTE anon = %s', COALESCE(privs, 'aucun'), fn));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T10', 'anon sans droits', false, SQLERRM);
END $$;

-- T02 → T09 : un décor partagé (cinq règles dans A, une dans B)
DO $$
DECLARE
  ta uuid := _mk_tenant('F710A');
  tb uuid; v jsonb; v_bad jsonb; v_ok jsonb; ok boolean;
BEGIN
  INSERT INTO crm_scoring_rules (tenant_id, name, field, operator, value, points, position) VALUES
    (ta, 'Recommandation', 'source',  'equals',       'referral',  20, 1),
    (ta, 'Grand compte',   'revenue', 'greater_than', '1000000',   30, 2),
    (ta, 'Hors cible',     'sector',  'equals',       'autre',    -15, 3),
    (ta, 'A un telephone', 'phone',   'is_set',       NULL,         5, 4),
    (ta, 'Desactivee',     'source',  'equals',       'referral', 999, 5);
  UPDATE crm_scoring_rules SET is_active = false WHERE tenant_id = ta AND name = 'Desactivee';

  -- T02 — 20 (recommandation) + 30 (CA > 1 M€)
  v := crm_lead_score('{"source":"referral","revenue":"1500000","sector":"sante"}'::jsonb);
  PERFORM _rec('T02', 'le moteur additionne les règles qui matchent (20 + 30 = 50) et les NOMME',
    (v ->> 'score')::int = 50
      AND (v -> 'matched_rules') ? 'Recommandation'
      AND (v -> 'matched_rules') ? 'Grand compte',
    format('score=%s règles=%s', v ->> 'score', v -> 'matched_rules'));

  -- T03 — la règle désactivée ne compte pas (ni +999, ni dans les raisons)
  PERFORM _rec('T03', 'une règle INACTIVE ne compte pas',
    NOT ((v -> 'matched_rules') ? 'Desactivee'),
    format('« Desactivee » présente = %s', (v -> 'matched_rules') ? 'Desactivee'));

  -- T04 — `equals` ne matche pas une autre valeur
  v := crm_lead_score('{"source":"cold"}'::jsonb);
  PERFORM _rec('T04', '`equals` ne matche pas une autre valeur',
    (v ->> 'score')::int = 0 AND NOT ((v -> 'matched_rules') ? 'Recommandation'),
    format('score=%s (attendu 0)', v ->> 'score'));

  -- T05 — `greater_than` compare en NOMBRE ; un fait non numérique ne matche pas
  v_bad := crm_lead_score('{"revenue":"beaucoup"}'::jsonb);
  v_ok  := crm_lead_score('{"revenue":"2000000"}'::jsonb);
  PERFORM _rec('T05', '`greater_than` compare en NOMBRE (non numérique : 0 ; 2 M€ : 30)',
    (v_bad ->> 'score')::int = 0 AND (v_ok ->> 'score')::int = 30,
    format('non numérique=%s ; 2 000 000=%s', v_bad ->> 'score', v_ok ->> 'score'));

  -- T06 — des points négatifs se déduisent
  v := crm_lead_score('{"sector":"autre"}'::jsonb);
  PERFORM _rec('T06', 'des points NÉGATIFS se déduisent (-15)',
    (v ->> 'score')::int = -15, format('score=%s (attendu -15)', v ->> 'score'));

  -- T07 — isolation : la règle d'une AUTRE société ne compte pas
  tb := _mk_tenant('F710B');
  INSERT INTO crm_scoring_rules (tenant_id, name, field, operator, value, points)
    VALUES (tb, 'Regle B', 'x', 'equals', 'y', 1000);
  PERFORM set_config('app.active_tenant_id', ta::text, false);   -- on revient dans la société A
  v := crm_lead_score('{"x":"y"}'::jsonb);
  PERFORM _rec('T07', 'isolation : la règle d''une AUTRE société ne compte pas',
    (v ->> 'score')::int = 0, format('score=%s (attendu 0)', v ->> 'score'));

  -- T08 — le nom d'une règle est unique par société
  ok := false;
  BEGIN
    INSERT INTO crm_scoring_rules (tenant_id, name, field, operator, value, points)
      VALUES (ta, 'Grand compte', 'z', 'equals', '1', 1);
  EXCEPTION WHEN OTHERS THEN ok := SQLSTATE = '23505'; END;
  PERFORM _rec('T08', 'le nom d''une règle est UNIQUE par société', ok,
    format('unique_violation 23505 obtenue = %s', ok));

  -- T09 — opérateur hors vocabulaire, et comparaison SANS valeur
  ok := false;
  BEGIN
    INSERT INTO crm_scoring_rules (tenant_id, name, field, operator, value, points)
      VALUES (ta, 'Bad1', 'x', 'pigeon_voyageur', 'y', 1);
  EXCEPTION WHEN OTHERS THEN ok := SQLSTATE = '23514'; END;
  BEGIN
    INSERT INTO crm_scoring_rules (tenant_id, name, field, operator, value, points)
      VALUES (ta, 'Bad2', 'x', 'greater_than', NULL, 1);
  EXCEPTION WHEN OTHERS THEN ok := ok AND SQLSTATE = '23514'; END;
  PERFORM _rec('T09', 'refus : un opérateur hors vocabulaire, et une comparaison SANS valeur (CHECK)', ok,
    format('les deux check_violation 23514 obtenues = %s', ok));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'addition des règles', false, SQLERRM);
  PERFORM _rec('T03', 'règle inactive', false, SQLERRM);
  PERFORM _rec('T04', 'equals', false, SQLERRM);
  PERFORM _rec('T05', 'greater_than numérique', false, SQLERRM);
  PERFORM _rec('T06', 'points négatifs', false, SQLERRM);
  PERFORM _rec('T07', 'isolation des règles', false, SQLERRM);
  PERFORM _rec('T08', 'nom unique', false, SQLERRM);
  PERFORM _rec('T09', 'opérateur et valeur contraints', false, SQLERRM);
END $$;

-- Garde-fou anti-faux-vert : la suite EXIGE ses 10 verdicts
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM _audit_results WHERE file = '710';
  IF n <> 10 THEN
    RAISE EXCEPTION '[710] % verdict(s) enregistré(s) au lieu de 10 — un scénario n''a pas été joué', n;
  END IF;
END $$;

SELECT _audit_assert('710');

