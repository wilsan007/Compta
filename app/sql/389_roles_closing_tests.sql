-- ============================================================
-- 389_roles_closing_tests.sql — LOC1-08 (tranche clôture/affectation/écarts)
--
--   T01  JOURNAL_CLOTURE est au catalogue et mappé (CL) dans le pack PCG ;
--   T02  allocate_result demande ses rôles (plus de 120000/129000/OD en dur) ;
--   T03  generate_residual_entry demande ses rôles (plus de 665000/666000/766000/654000/OD) ;
--   T04  société FR : les rôles rendent EXACTEMENT les comptes d'avant ;
--   T05  rejouable.
--
-- Recette du cahier : « balance d'ouverture N+1 identique à l'actuelle au
-- centime » — tenue par construction (cf. T04) et par les suites `179`/`175`.
--
-- Vu ROUGE avant la 389 : T01 (rôle absent), T02/T03 (numéros en dur).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '389', false);
DELETE FROM _audit_results WHERE file = '389';

-- ─────────────────────────────────────────────────────────────
-- T01 — le rôle de journal de clôture
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_cat int; v_pack int;
BEGIN
  SELECT count(*) INTO v_cat FROM journal_role_catalog WHERE role = 'JOURNAL_CLOTURE';
  SELECT count(*) INTO v_pack FROM pack_journal_roles WHERE pack_code = 'PCG' AND role = 'JOURNAL_CLOTURE';
  PERFORM _rec('T01', 'JOURNAL_CLOTURE est au catalogue et mappé → CL dans le pack PCG',
    v_cat = 1 AND v_pack = 1, format('catalogue=%s ; pack=%s', v_cat, v_pack));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'JOURNAL_CLOTURE est au catalogue et mappé → CL dans le pack PCG', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T02 / T03 — les fonctions passent par les rôles
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_al text; v_re text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_al FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='allocate_result';
  SELECT pg_get_functiondef(p.oid) INTO v_re FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='generate_residual_entry';

  PERFORM _rec('T02', 'allocate_result demande ses rôles (plus de 120000/129000 en dur)',
    v_al LIKE '%resolve_account%' AND v_al LIKE '%resolve_journal%'
      AND v_al NOT LIKE '%''120000''%' AND v_al NOT LIKE '%''129000''%',
    format('resolve_account=%s ; resolve_journal=%s ; 120000 en dur=%s ; 129000 en dur=%s',
      v_al LIKE '%resolve_account%', v_al LIKE '%resolve_journal%',
      v_al LIKE '%''120000''%', v_al LIKE '%''129000''%'));

  PERFORM _rec('T03', 'generate_residual_entry demande ses rôles (plus de 665000/666000/766000/654000)',
    v_re LIKE '%resolve_account%' AND v_re LIKE '%resolve_journal%'
      AND v_re NOT LIKE '%''665000''%' AND v_re NOT LIKE '%''666000''%'
      AND v_re NOT LIKE '%''766000''%' AND v_re NOT LIKE '%''654000''%',
    format('resolve_account=%s ; resolve_journal=%s', v_re LIKE '%resolve_account%', v_re LIKE '%resolve_journal%'));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'allocate_result demande ses rôles (plus de 120000/129000 en dur)', false, SQLERRM);
  PERFORM _rec('T03', 'generate_residual_entry demande ses rôles (plus de 665000/666000/766000/654000)', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T04 — les rôles rendent EXACTEMENT les comptes d'avant (FR)
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE t uuid; a text; b text; c text; d text; e text; f text; j text;
BEGIN
  t := _mk_tenant('RCLO1');
  UPDATE tenants SET legislation_pack_code = 'FR' WHERE id = t;
  PERFORM ensure_standard_journals(t);
  a := resolve_account(t, 'RESULTAT_BENEFICE');
  b := resolve_account(t, 'RESULTAT_PERTE');
  c := resolve_account(t, 'ESCOMPTES_ACCORDES');
  d := resolve_account(t, 'PERTES_CHANGE');
  e := resolve_account(t, 'GAINS_CHANGE');
  f := resolve_account(t, 'PERTES_CREANCES_IRRECOUVRABLES');
  j := resolve_journal(t, 'JOURNAL_CLOTURE');
  PERFORM _rec('T04', 'société FR : 120000/129000/665000/666000/766000/654000 et JOURNAL_CLOTURE=CL',
    a='120000' AND b='129000' AND c='665000' AND d='666000' AND e='766000' AND f='654000' AND j='CL',
    format('120000→%s ; 129000→%s ; 665000→%s ; 666000→%s ; 766000→%s ; 654000→%s ; CL→%s',
      a, b, c, d, e, f, j));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'société FR : 120000/129000/665000/666000/766000/654000 et JOURNAL_CLOTURE=CL', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T05 — rejouable
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_av int; v_ap int;
BEGIN
  SELECT count(*) INTO v_av FROM journal_role_catalog;
  INSERT INTO journal_role_catalog (role, journal_type, required_for)
    VALUES ('JOURNAL_CLOTURE', 'general', ARRAY['closing'])
  ON CONFLICT (role) DO NOTHING;
  SELECT count(*) INTO v_ap FROM journal_role_catalog;
  PERFORM _rec('T05', 'rejouable : un second chargement n''ajoute aucun rôle',
    v_av = v_ap, format('%s → %s rôle(s)', v_av, v_ap));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T05', 'rejouable : un second chargement n''ajoute aucun rôle', false, SQLERRM);
END $$;

SELECT _audit_assert('389');