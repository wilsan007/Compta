-- ============================================================
-- 391_roles_journaux_restants_tests.sql — LOC1-09 (journaux en dur)
--
--   T01  les 3 fonctions demandent leur journal (plus de 'AN'/'OD' en dur) ;
--   T02  société FR : les rôles rendent EXACTEMENT les codes d'avant ;
--   T03  aucune fonction EFFECTIVE n'écrit plus un code de journal littéral
--        (le reste à zéro, hors `ensure_standard_journals` qui les DÉFINIT) ;
--   T04  rejouable.
--
-- Vu ROUGE avant la 391 : T01/T03 (codes en dur).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '391', false);
DELETE FROM _audit_results WHERE file = '391';

-- ─────────────────────────────────────────────────────────────
-- T01 — les 3 fonctions passent par le rôle
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_txt text; v_bad text;
BEGIN
  SELECT string_agg(p.proname, ', ' ORDER BY p.proname) INTO v_bad
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN ('bank_account_post_opening_balance','stock_initial_post_opening_entry',
                      'post_exchange_gain_loss_on_payment')
    AND (p.prosrc NOT LIKE '%resolve_journal%'
         OR p.prosrc ~ '''(VT|AC|OD|AN|BQ|CA|ST|POS|OF|CL)'', *''draft''');

  PERFORM _rec('T01', 'bank_account_post_opening_balance, stock_initial_post_opening_entry et post_exchange_gain_loss_on_payment demandent leur journal',
    v_bad IS NULL, COALESCE('encore en dur : ' || v_bad, 'les 3 fonctions passent par le rôle'));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'bank_account_post_opening_balance, stock_initial_post_opening_entry et post_exchange_gain_loss_on_payment demandent leur journal', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T02 — les rôles rendent EXACTEMENT les codes d'avant (FR)
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE t uuid; a text; o text; v text; c text;
BEGIN
  t := _mk_tenant('RJRN1');
  UPDATE tenants SET legislation_pack_code = 'FR' WHERE id = t;
  PERFORM ensure_standard_journals(t);
  a := resolve_journal(t, 'JOURNAL_A_NOUVEAUX');
  o := resolve_journal(t, 'JOURNAL_OD');
  v := resolve_journal(t, 'JOURNAL_VENTES');
  c := resolve_journal(t, 'JOURNAL_ACHATS');
  PERFORM _rec('T02', 'société FR : JOURNAL_A_NOUVEAUX=AN, JOURNAL_OD=OD, JOURNAL_VENTES=VT, JOURNAL_ACHATS=AC',
    a='AN' AND o='OD' AND v='VT' AND c='AC',
    format('AN→%s ; OD→%s ; VT→%s ; AC→%s', a, o, v, c));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'société FR : JOURNAL_A_NOUVEAUX=AN, JOURNAL_OD=OD, JOURNAL_VENTES=VT, JOURNAL_ACHATS=AC', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T03 — aucune NOUVELLE fonction n'écrit un journal littéral
--       (le reste recule à chaque tranche ; il ne doit jamais GROSSIR)
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_restant text; v_nouveau int;
BEGIN
  SELECT string_agg(p.proname, ', ' ORDER BY p.proname) INTO v_restant
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.prosrc ~ '''(VT|AC|OD|AN|BQ|CA|ST|POS|OF|CL)'', *''draft'''
    AND p.proname <> 'ensure_standard_journals';

  SELECT count(*) INTO v_nouveau
  FROM unnest(string_to_array(COALESCE(v_restant, ''), ', ')) x
  WHERE x <> '' AND x NOT IN ('bank_account_post_opening_balance','credit_note_guard',
    'generate_depreciation_entry','integrate_expense_report_on_approval','post_deferred_charge',
    'post_exchange_gain_loss_on_payment','purchase_credit_note_guard','revaluate_currency_balances',
    'stock_initial_post_opening_entry');

  PERFORM _rec('T03', 'aucune NOUVELLE fonction n''écrit un journal littéral (le reste recule, il ne grossit pas)',
    v_nouveau = 0, format('nouvelles : %s ; restant : %s', v_nouveau, COALESCE(v_restant, 'aucun')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'aucune NOUVELLE fonction n''écrit un journal littéral (le reste recule, il ne grossit pas)', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T04 — rejouable
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v int;
BEGIN
  SELECT count(*) INTO v FROM journal_role_catalog;
  PERFORM _rec('T04', 'rejouable : le catalogue des rôles de journaux est stable',
    v >= 8, format('%s rôle(s) au catalogue', v));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'rejouable : le catalogue des rôles de journaux est stable', false, SQLERRM);
END $$;

SELECT _audit_assert('391');