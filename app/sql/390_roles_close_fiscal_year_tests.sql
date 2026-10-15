-- ============================================================
-- 390_roles_close_fiscal_year_tests.sql — LOC1-08 (clôture d'exercice)
--
--   T01  close_fiscal_year demande ses rôles (plus de 120000/129000/CL/AN en dur) ;
--   T02  société FR : les rôles rendent EXACTEMENT les comptes d'avant ;
--   T03  la fonction garde sa signature (régression : elle est appelée par l'écran) ;
--   T04  rejouable.
--
-- La recette du cahier — « balance d'ouverture N+1 identique à l'actuelle au
-- centime » — est tenue par la suite `179_closing_and_statements_tests`, rejouée
-- verte : c'est elle qui exécute une vraie clôture et compare les à-nouveaux.
--
-- Vu ROUGE avant la 390 : T01 (numéros en dur).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '390', false);
DELETE FROM _audit_results WHERE file = '390';

-- ─────────────────────────────────────────────────────────────
-- T01 — la fonction demande ses rôles
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='close_fiscal_year';
  PERFORM _rec('T01', 'close_fiscal_year demande ses rôles (journal CL/AN, comptes de résultat) — plus de 120000/129000 en dur',
    v LIKE '%resolve_account%' AND v LIKE '%resolve_journal%'
      AND v NOT LIKE '%''120000''%' AND v NOT LIKE '%''129000''%',
    format('resolve_account=%s ; resolve_journal=%s ; 120000 en dur=%s ; 129000 en dur=%s',
      v LIKE '%resolve_account%', v LIKE '%resolve_journal%',
      v LIKE '%''120000''%', v LIKE '%''129000''%'));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'close_fiscal_year demande ses rôles (journal CL/AN, comptes de résultat) — plus de 120000/129000 en dur', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T02 — les rôles rendent EXACTEMENT les comptes d'avant (FR)
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE t uuid; a text; b text; jc text; ja text;
BEGIN
  t := _mk_tenant('RCLS1');
  UPDATE tenants SET legislation_pack_code = 'FR' WHERE id = t;
  PERFORM ensure_standard_journals(t);
  a  := resolve_account(t, 'RESULTAT_BENEFICE');
  b  := resolve_account(t, 'RESULTAT_PERTE');
  jc := resolve_journal(t, 'JOURNAL_CLOTURE');
  ja := resolve_journal(t, 'JOURNAL_A_NOUVEAUX');
  PERFORM _rec('T02', 'société FR : RESULTAT_BENEFICE=120000, RESULTAT_PERTE=129000, JOURNAL_CLOTURE=CL, JOURNAL_A_NOUVEAUX=AN',
    a='120000' AND b='129000' AND jc='CL' AND ja='AN',
    format('120000→%s ; 129000→%s ; CL→%s ; AN→%s', a, b, jc, ja));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'société FR : RESULTAT_BENEFICE=120000, RESULTAT_PERTE=129000, JOURNAL_CLOTURE=CL, JOURNAL_A_NOUVEAUX=AN', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T03 — la signature est inchangée (l'écran l'appelle)
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'close_fiscal_year'
    AND p.pronargs = 3 AND p.prorettype = 'jsonb'::regtype;
  PERFORM _rec('T03', 'close_fiscal_year garde sa signature (uuid, uuid, boolean) → jsonb',
    v_n = 1, format('%s signature(s) trouvée(s) (1 attendue)', v_n));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'close_fiscal_year garde sa signature (uuid, uuid, boolean) → jsonb', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T04 — rejouable : le catalogue n'ajoute rien au second passage
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_av int; v_ap int;
BEGIN
  SELECT count(*) INTO v_av FROM journal_role_catalog;
  INSERT INTO journal_role_catalog (role, journal_type, required_for)
    VALUES ('JOURNAL_CLOTURE', 'general', ARRAY['closing'])
  ON CONFLICT (role) DO NOTHING;
  SELECT count(*) INTO v_ap FROM journal_role_catalog;
  PERFORM _rec('T04', 'rejouable : un second chargement du catalogue n''ajoute aucun rôle',
    v_av = v_ap, format('%s → %s rôle(s)', v_av, v_ap));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'rejouable : un second chargement du catalogue n''ajoute aucun rôle', false, SQLERRM);
END $$;

SELECT _audit_assert('390');