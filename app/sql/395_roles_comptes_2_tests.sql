-- ============================================================
-- 395_roles_comptes_2_tests.sql — LOC1-10 (comptes en dur, tranche 3 : avoirs)
--
--   T01  les deux triggers d'avoir demandent leurs COMPTES (plus aucun littéral) ;
--   T02  société FR : les rôles rendent EXACTEMENT les numéros d'avant ;
--   T03  les 8 rôles employés sont AU CATALOGUE et mappés au référentiel PCG
--        (un rôle mal orthographié ne casserait qu'à l'exécution) ;
--   T04  rejouable : les deux triggers d'avoir existent, sur leurs tables.
--
-- Vu ROUGE avant la 395 : T01 (6 occurrences mesurées, 9 corrigées).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '395', false);
DELETE FROM _audit_results WHERE file = '395';

-- ─────────────────────────────────────────────────────────────
-- T01 — les deux fonctions passent par le rôle
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(p.proname, ', ' ORDER BY p.proname) INTO v_bad
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN ('credit_note_guard','purchase_credit_note_guard')
    AND (p.prosrc NOT LIKE '%resolve_account%'
         OR p.prosrc ~ '''[1-9][0-9]{2,5}''');

  PERFORM _rec('T01', 'les deux avoirs demandent leur compte, sans littéral chiffré',
    v_bad IS NULL, COALESCE('encore en dur : ' || v_bad, 'les deux avoirs passent par le rôle'));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'les deux avoirs demandent leur compte, sans littéral chiffré', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T02 — société FR : les rôles rendent EXACTEMENT les numéros d'avant
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE t uuid; cl text; ps text; vm text; ra text; tc text; fo text; ro text; td text;
BEGIN
  t := _mk_tenant('RCPT3');
  UPDATE tenants SET legislation_pack_code = 'FR' WHERE id = t;
  PERFORM ensure_standard_journals(t);
  cl := resolve_account(t, 'CLIENTS');
  ps := resolve_account(t, 'PRESTATIONS_SERVICES');
  vm := resolve_account(t, 'VENTES_MARCHANDISES');
  ra := resolve_account(t, 'RRR_ACCORDES');
  tc := resolve_account(t, 'TVA_COLLECTEE');
  fo := resolve_account(t, 'FOURNISSEURS');
  ro := resolve_account(t, 'RRR_OBTENUS');
  td := resolve_account(t, 'TVA_DEDUCTIBLE_BIENS_SERVICES');
  PERFORM _rec('T02',
    'société FR : CLIENTS=411000, PRESTATIONS=706000, VENTES_MARCHANDISES=707000, RRR_ACCORDES=709000, TVA_COLLECTEE=445710, FOURNISSEURS=401000, RRR_OBTENUS=609000, TVA_DEDUCTIBLE=445660',
    cl = '411000' AND ps = '706000' AND vm = '707000' AND ra = '709000' AND tc = '445710'
      AND fo = '401000' AND ro = '609000' AND td = '445660',
    format('CL=%s PS=%s VM=%s RRRa=%s TVAc=%s FO=%s RRRo=%s TVAd=%s',
           cl, ps, vm, ra, tc, fo, ro, td));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02',
    'société FR : CLIENTS=411000, PRESTATIONS=706000, VENTES_MARCHANDISES=707000, RRR_ACCORDES=709000, TVA_COLLECTEE=445710, FOURNISSEURS=401000, RRR_OBTENUS=609000, TVA_DEDUCTIBLE=445660',
    false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T03 — les rôles employés existent VRAIMENT (catalogue + référentiel)
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_cat int; v_pack int;
BEGIN
  SELECT count(*) INTO v_cat FROM account_role_catalog
   WHERE role IN ('CLIENTS','PRESTATIONS_SERVICES','VENTES_MARCHANDISES','RRR_ACCORDES',
                  'TVA_COLLECTEE','FOURNISSEURS','RRR_OBTENUS','TVA_DEDUCTIBLE_BIENS_SERVICES');
  SELECT count(*) INTO v_pack FROM pack_account_roles
   WHERE pack_code = 'PCG'
     AND role IN ('CLIENTS','PRESTATIONS_SERVICES','VENTES_MARCHANDISES','RRR_ACCORDES',
                  'TVA_COLLECTEE','FOURNISSEURS','RRR_OBTENUS','TVA_DEDUCTIBLE_BIENS_SERVICES');
  PERFORM _rec('T03', 'les 8 rôles employés par les avoirs sont au catalogue ET mappés au PCG',
    v_cat = 8 AND v_pack = 8, format('catalogue=%s (8) ; pack PCG=%s (8)', v_cat, v_pack));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'les 8 rôles employés par les avoirs sont au catalogue ET mappés au PCG', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T04 — rejouable : les deux triggers sont là, un par table
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v int;
BEGIN
  SELECT count(*) INTO v
  FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
  WHERE NOT t.tgisinternal
    AND t.tgfoid IN ('public.credit_note_guard()'::regprocedure,
                     'public.purchase_credit_note_guard()'::regprocedure)
    AND c.relname IN ('credit_notes','purchase_credit_notes');
  PERFORM _rec('T04', 'rejouable : les deux triggers d''avoir sont posés, un par table', v = 2,
    format('%s trigger(s)', v));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'rejouable : les deux triggers d''avoir sont posés, un par table', false, SQLERRM);
END $$;

SELECT _audit_assert('395');