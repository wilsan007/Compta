-- ============================================================
-- 396_roles_comptes_3_tests.sql — LOC1-10 (comptes en dur, tranche 4)
--
--   T01  les 3 fonctions demandent leurs COMPTES (plus aucun littéral chiffré) ;
--   T02  société FR : les rôles rendent EXACTEMENT les numéros d'avant ;
--   T03  les 8 rôles employés sont au catalogue ET mappés au référentiel PCG ;
--   T04  rejouable : le trigger de clôture POS est posé sur sa table.
--
-- Vu ROUGE avant la 396 : T01 (7 occurrences mesurées).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '396', false);
DELETE FROM _audit_results WHERE file = '396';

-- ─────────────────────────────────────────────────────────────
-- T01 — les 3 fonctions passent par le rôle
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(p.proname, ', ' ORDER BY p.proname) INTO v_bad
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN ('post_pos_session_on_close','post_exchange_gain_loss_on_payment',
                      'propagate_analytic_section')
    AND (p.prosrc NOT LIKE '%resolve_account%'
         OR p.prosrc ~ '''[1-9][0-9]{2,5}''');

  PERFORM _rec('T01', 'les 3 fonctions de la tranche demandent leur compte, sans littéral chiffré',
    v_bad IS NULL, COALESCE('encore en dur : ' || v_bad, 'les 3 fonctions passent par le rôle'));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'les 3 fonctions de la tranche demandent leur compte, sans littéral chiffré', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T02 — société FR : les rôles rendent EXACTEMENT les numéros d'avant
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE t uuid; cp text; vm text; tv text; cl text; ga text; pe text; ps text; am text;
BEGIN
  t := _mk_tenant('RCPT5');
  UPDATE tenants SET legislation_pack_code = 'FR' WHERE id = t;
  PERFORM ensure_standard_journals(t);
  cp := resolve_account(t, 'CAISSE_POS');
  vm := resolve_account(t, 'VENTES_MARCHANDISES');
  tv := resolve_account(t, 'TVA_COLLECTEE');
  cl := resolve_account(t, 'CLIENTS');
  ga := resolve_account(t, 'GAINS_CHANGE');
  pe := resolve_account(t, 'PERTES_CHANGE');
  ps := resolve_account(t, 'PRESTATIONS_SERVICES');
  am := resolve_account(t, 'ACHATS_MARCHANDISES');
  PERFORM _rec('T02',
    'société FR : CAISSE_POS=531000, VENTES_MARCHANDISES=707000, TVA_COLLECTEE=445710, CLIENTS=411000, GAINS_CHANGE=766000, PERTES_CHANGE=666000, PRESTATIONS=706000, ACHATS_MARCHANDISES=607000',
    cp = '531000' AND vm = '707000' AND tv = '445710' AND cl = '411000'
      AND ga = '766000' AND pe = '666000' AND ps = '706000' AND am = '607000',
    format('POS=%s VM=%s TVA=%s CL=%s GAIN=%s PERTE=%s PS=%s ACH=%s', cp, vm, tv, cl, ga, pe, ps, am));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02',
    'société FR : CAISSE_POS=531000, VENTES_MARCHANDISES=707000, TVA_COLLECTEE=445710, CLIENTS=411000, GAINS_CHANGE=766000, PERTES_CHANGE=666000, PRESTATIONS=706000, ACHATS_MARCHANDISES=607000',
    false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T03 — les rôles employés existent VRAIMENT (catalogue + référentiel)
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_cat int; v_pack int;
BEGIN
  SELECT count(*) INTO v_cat FROM account_role_catalog
   WHERE role IN ('CAISSE_POS','VENTES_MARCHANDISES','TVA_COLLECTEE','CLIENTS',
                  'GAINS_CHANGE','PERTES_CHANGE','PRESTATIONS_SERVICES','ACHATS_MARCHANDISES');
  SELECT count(*) INTO v_pack FROM pack_account_roles
   WHERE pack_code = 'PCG'
     AND role IN ('CAISSE_POS','VENTES_MARCHANDISES','TVA_COLLECTEE','CLIENTS',
                  'GAINS_CHANGE','PERTES_CHANGE','PRESTATIONS_SERVICES','ACHATS_MARCHANDISES');
  PERFORM _rec('T03', 'les 8 rôles employés par la tranche sont au catalogue ET mappés au PCG',
    v_cat = 8 AND v_pack = 8, format('catalogue=%s (8) ; pack PCG=%s (8)', v_cat, v_pack));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'les 8 rôles employés par la tranche sont au catalogue ET mappés au PCG', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T04 — rejouable : la clôture est branchée, la variante simple est définie
--
-- ⚠ La clôture réellement DÉCLENCHÉE est la variante `multi` (elle seule est
-- posée sur `pos_sessions`) : la variante simple n'a jamais été branchée. Ce
-- contrôle le DIT au lieu d'exiger un branchement qui n'existe pas — et il
-- vérifie que la fonction que cette migration corrige existe bien.
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_trig int; v_fn int;
BEGIN
  SELECT count(*) INTO v_trig
  FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
  WHERE NOT t.tgisinternal AND c.relname = 'pos_sessions'
    AND t.tgfoid = 'public.post_pos_session_on_close_multi()'::regprocedure;
  SELECT count(*) INTO v_fn
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'post_pos_session_on_close';
  PERFORM _rec('T04', 'rejouable : la clôture multi est branchée sur pos_sessions et la variante simple est définie',
    v_trig >= 1 AND v_fn = 1, format('trigger multi=%s ; fonction simple=%s', v_trig, v_fn));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'rejouable : la clôture multi est branchée sur pos_sessions et la variante simple est définie', false, SQLERRM);
END $$;

SELECT _audit_assert('396');