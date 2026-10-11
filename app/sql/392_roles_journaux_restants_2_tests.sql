-- ============================================================
-- 392_roles_journaux_restants_2_tests.sql — LOC1-09 (tranche 2)
--
--   T01  les 2 fonctions demandent leur journal (plus de 'OD' en dur) ;
--   T02  le RESTE est FIGÉ : exactement 4 fonctions (tranche 3) ;
--   T03  société FR : JOURNAL_OD = OD (écritures identiques) ;
--   T04  rejouable.
--
-- Vu ROUGE avant la 392 : T01/T02 (codes en dur).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '392', false);
DELETE FROM _audit_results WHERE file = '392';

-- ─────────────────────────────────────────────────────────────
-- T01 — les 2 fonctions passent par le rôle
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(p.proname, ', ' ORDER BY p.proname) INTO v_bad
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN ('integrate_expense_report_on_approval','post_deferred_charge')
    AND (p.prosrc NOT LIKE '%resolve_journal%'
         OR p.prosrc ~ '''(VT|AC|OD|AN|BQ|CA|ST|POS|OF|CL)'', *''draft''');

  PERFORM _rec('T01', 'integrate_expense_report_on_approval et post_deferred_charge demandent leur journal',
    v_bad IS NULL, COALESCE('encore en dur : ' || v_bad, 'les 2 fonctions passent par le rôle'));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'integrate_expense_report_on_approval et post_deferred_charge demandent leur journal', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T02 — le reste est FIGÉ (4 fonctions pour la tranche 3)
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_restant text;
BEGIN
  SELECT string_agg(p.proname, ', ' ORDER BY p.proname) INTO v_restant
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.prosrc ~ '''(VT|AC|OD|AN|BQ|CA|ST|POS|OF|CL)'', *''draft'''
    AND p.proname <> 'ensure_standard_journals';

  PERFORM _rec('T02', 'le reste des journaux en dur est FIGÉ (4 fonctions : tranche 3)',
    v_restant = 'credit_note_guard, generate_depreciation_entry, purchase_credit_note_guard, revaluate_currency_balances',
    format('restant : %s', COALESCE(v_restant, 'aucun')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'le reste des journaux en dur est FIGÉ (4 fonctions : tranche 3)', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T03 — société FR : JOURNAL_OD = OD (écritures identiques)
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE t uuid; o text;
BEGIN
  t := _mk_tenant('RJRN2');
  UPDATE tenants SET legislation_pack_code = 'FR' WHERE id = t;
  PERFORM ensure_standard_journals(t);
  o := resolve_journal(t, 'JOURNAL_OD');
  PERFORM _rec('T03', 'société FR : resolve_journal(''JOURNAL_OD'') = OD', o = 'OD',
    format('OD→%s', COALESCE(o, 'NULL')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'société FR : resolve_journal(''JOURNAL_OD'') = OD', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T04 — rejouable
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v int;
BEGIN
  SELECT count(*) INTO v FROM journal_role_catalog WHERE role = 'JOURNAL_OD';
  PERFORM _rec('T04', 'rejouable : JOURNAL_OD est au catalogue, une seule fois', v = 1,
    format('%s occurrence(s)', v));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'rejouable : JOURNAL_OD est au catalogue, une seule fois', false, SQLERRM);
END $$;

SELECT _audit_assert('392');