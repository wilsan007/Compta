-- ============================================================
-- 393_roles_journaux_restants_3_tests.sql — LOC1-09 (tranche 3, la dernière)
--
--   T01  les 4 fonctions demandent leur journal (plus de 'VT'/'AC'/'OD' en dur) ;
--   T02  le reste est VIDE : plus AUCUNE fonction effective n'écrit un code de
--        journal littéral (hors `ensure_standard_journals`, qui les DÉFINIT) ;
--   T03  société FR : les rôles rendent EXACTEMENT les codes d'avant ;
--   T04  rejouable.
--
-- Vu ROUGE avant la 393 : T01 (codes en dur) et T02 (reste = les 4 fonctions).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '393', false);
DELETE FROM _audit_results WHERE file = '393';

-- ─────────────────────────────────────────────────────────────
-- T01 — les 4 fonctions passent par le rôle
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(p.proname, ', ' ORDER BY p.proname) INTO v_bad
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN ('credit_note_guard','generate_depreciation_entry',
                      'purchase_credit_note_guard','revaluate_currency_balances')
    AND (p.prosrc NOT LIKE '%resolve_journal%'
         OR p.prosrc ~ '''(VT|AC|OD|AN|BQ|CA|ST|POS|OF|CL)'', *''draft''');

  PERFORM _rec('T01', 'les 4 fonctions de la tranche 3 demandent leur journal',
    v_bad IS NULL, COALESCE('encore en dur : ' || v_bad, 'les 4 fonctions passent par le rôle'));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'les 4 fonctions de la tranche 3 demandent leur journal', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T02 — LOC1-09 est TERMINÉ : plus aucun journal littéral
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_restant text;
BEGIN
  SELECT string_agg(p.proname, ', ' ORDER BY p.proname) INTO v_restant
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.prosrc ~ '''(VT|AC|OD|AN|BQ|CA|ST|POS|OF|CL)'', *''draft'''
    AND p.proname <> 'ensure_standard_journals'
    -- Fixtures de suites (préfixe `_`, convention du dépôt : `_i8_piece`,
    -- `_vc_entry`) : hors du garde, qui ne parle que de la PRODUCTION.
    AND p.proname !~ '^_';

  PERFORM _rec('T02', 'LOC1-09 terminé : plus aucune fonction n''écrit un journal littéral',
    v_restant IS NULL, format('restant : %s', COALESCE(v_restant, 'aucun')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'LOC1-09 terminé : plus aucune fonction n''écrit un journal littéral', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T03 — société FR : les rôles rendent EXACTEMENT les codes d'avant
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE t uuid; v text; a text; o text;
BEGIN
  t := _mk_tenant('RJRN3');
  UPDATE tenants SET legislation_pack_code = 'FR' WHERE id = t;
  PERFORM ensure_standard_journals(t);
  v := resolve_journal(t, 'JOURNAL_VENTES');
  a := resolve_journal(t, 'JOURNAL_ACHATS');
  o := resolve_journal(t, 'JOURNAL_OD');
  PERFORM _rec('T03', 'société FR : JOURNAL_VENTES=VT, JOURNAL_ACHATS=AC, JOURNAL_OD=OD',
    v = 'VT' AND a = 'AC' AND o = 'OD',
    format('VT→%s ; AC→%s ; OD→%s', v, a, o));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'société FR : JOURNAL_VENTES=VT, JOURNAL_ACHATS=AC, JOURNAL_OD=OD', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T04 — rejouable
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v int;
BEGIN
  SELECT count(*) INTO v FROM journal_role_catalog WHERE role IN ('JOURNAL_VENTES','JOURNAL_ACHATS','JOURNAL_OD');
  PERFORM _rec('T04', 'rejouable : les 3 rôles de la tranche sont au catalogue, une seule fois', v = 3,
    format('%s occurrence(s)', v));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'rejouable : les 3 rôles de la tranche sont au catalogue, une seule fois', false, SQLERRM);
END $$;

SELECT _audit_assert('393');