-- ============================================================
-- 705_recrutement_tests.sql — F.7 / RH-03 :
--   UN POSTE PORTE SES CANDIDATURES, ET LE MODÈLE TIENT TOUT SEUL
--
--   T01  RLS FORCÉE sur les deux tables (grille BT)
--   T02  un poste et sa candidature : statuts par défaut (draft / received)
--   T03  refus : un statut hors vocabulaire (le CHECK tient, pas l'écran)
--   T04  refus : une candidature vers le poste d'une AUTRE société
--        (clé composite : le défaut ISO-02 ne peut pas revenir)
--   T05  supprimer un poste emporte ses candidatures (ON DELETE CASCADE)
--   T06  le visiteur (`anon`) n'a AUCUN droit sur les deux tables
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '705', false);
DELETE FROM _audit_results WHERE file = '705';

-- T01 — la RLS est FORCÉE sur les deux tables
DO $$
DECLARE v boolean;
BEGIN
  SELECT bool_and(relforcerowsecurity) INTO v
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
   WHERE c.relname IN ('job_postings', 'job_applications');
  PERFORM _rec('T01', 'RLS FORCÉE sur `job_postings` et `job_applications`',
    v IS TRUE, format('relforcerowsecurity = %s pour les deux', COALESCE(v::text, 'NULL')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'RLS forcée sur les deux tables', false, SQLERRM);
END $$;

-- T06 — le visiteur n'a aucun droit (testable hors RLS)
DO $$
DECLARE privs text;
BEGIN
  SELECT string_agg(DISTINCT privilege_type, ',') INTO privs
    FROM information_schema.role_table_grants
   WHERE grantee = 'anon' AND table_name IN ('job_postings', 'job_applications');
  PERFORM _rec('T06', 'le visiteur (`anon`) n''a AUCUN droit sur les tables de recrutement',
    privs IS NULL, format('droits d''anon = %s', COALESCE(privs, 'aucun')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T06', 'anon sans droits', false, SQLERRM);
END $$;

-- T02 → T05 : un décor partagé (un poste, une candidature, une seconde société)
DO $$
DECLARE
  ta uuid; tb uuid; pa uuid; pb uuid; ap uuid; v_status text; v_app_status text;
  n int; ok boolean;
BEGIN
  ta := _mk_tenant('F705A');
  INSERT INTO job_postings (tenant_id, title) VALUES (ta, 'Développeur')
    RETURNING id, status INTO pa, v_status;
  INSERT INTO job_applications (tenant_id, posting_id, candidate_name)
    VALUES (ta, pa, 'Alice Candidat') RETURNING id, status INTO ap, v_app_status;

  -- T02 — statuts par défaut
  PERFORM _rec('T02', 'un poste naît `draft` et une candidature `received` (les statuts par défaut tiennent)',
    v_status = 'draft' AND v_app_status = 'received',
    format('poste=%s candidature=%s', v_status, v_app_status));

  -- T03 — un statut hors vocabulaire est refusé par le CHECK
  ok := false;
  BEGIN
    INSERT INTO job_postings (tenant_id, title, status) VALUES (ta, 'Poste bidon', 'published');
  EXCEPTION WHEN OTHERS THEN ok := SQLSTATE = '23514'; END;   -- check_violation
  PERFORM _rec('T03', 'refus : un statut de poste hors vocabulaire (CHECK, pas l''écran)', ok,
    format('check_violation 23514 obtenue = %s', ok));

  -- T04 — une candidature ne peut pas viser le poste d'une AUTRE société
  tb := _mk_tenant('F705B');
  INSERT INTO job_postings (tenant_id, title) VALUES (tb, 'Poste B') RETURNING id INTO pb;
  ok := false;
  BEGIN
    INSERT INTO job_applications (tenant_id, posting_id, candidate_name)
      VALUES (ta, pb, 'Bob');   -- société A, poste de B
  EXCEPTION WHEN OTHERS THEN ok := SQLSTATE = '23503'; END;   -- foreign_key_violation
  PERFORM _rec('T04', 'refus : une candidature vers le poste d''une autre société (clé composite, ISO-02)', ok,
    format('foreign_key_violation 23503 obtenue = %s', ok));

  -- T05 — supprimer le poste emporte ses candidatures
  DELETE FROM job_postings WHERE id = pa;
  SELECT count(*) INTO n FROM job_applications WHERE posting_id = pa;
  PERFORM _rec('T05', 'supprimer un poste emporte ses candidatures (ON DELETE CASCADE)', n = 0,
    format('candidatures restantes = %s (attendu 0)', n));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'statuts par défaut', false, SQLERRM);
  PERFORM _rec('T03', 'refus statut hors vocabulaire', false, SQLERRM);
  PERFORM _rec('T04', 'refus candidature inter-société', false, SQLERRM);
  PERFORM _rec('T05', 'cascade de suppression', false, SQLERRM);
END $$;

-- Garde-fou anti-faux-vert : la suite EXIGE ses 6 verdicts
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM _audit_results WHERE file = '705';
  IF n <> 6 THEN
    RAISE EXCEPTION '[705] % verdict(s) enregistré(s) au lieu de 6 — un scénario n''a pas été joué', n;
  END IF;
END $$;

SELECT _audit_assert('705');

