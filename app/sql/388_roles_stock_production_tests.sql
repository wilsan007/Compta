-- ============================================================
-- 388_roles_stock_production_tests.sql — LOC1-07 (tranche stock/production)
--
--   T01  resolve_stock_account résout par le RÔLE (plus de '310000' en dur) ;
--   T02  le mouvement de stock demande le journal (plus de 'ST' en dur) ;
--   T03  la clôture d'OF demande ses rôles (plus de 601000/355000/713500 en dur) ;
--   T04  société FR : les rôles rendent EXACTEMENT les comptes d'avant ;
--   T05  resolve_variation_account garde '603000' — le choix est DOCUMENTÉ.
--
-- La recette « écritures identiques » est tenue par les suites de stock
-- (`173`, `240`, `241`, `230`) et `102_trigger_tests`, rejouées vertes.
--
-- Vu ROUGE avant la 388 : T01/T02/T03 (numéros en dur). T04/T05 sans objet.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '388', false);
DELETE FROM _audit_results WHERE file = '388';

-- ─────────────────────────────────────────────────────────────
-- T01 / T02 / T03 — les fonctions passent par les rôles
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_stock text; v_mvt text; v_of text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_stock FROM pg_proc p
   JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='resolve_stock_account';
  SELECT pg_get_functiondef(p.oid) INTO v_mvt FROM pg_proc p
   JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='create_journal_on_stock_movement';
  SELECT pg_get_functiondef(p.oid) INTO v_of FROM pg_proc p
   JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='create_stock_on_manufacturing_complete';

  PERFORM _rec('T01', 'resolve_stock_account résout son repli par le RÔLE (plus de 310000 en dur)',
    v_stock LIKE '%resolve_account%' AND v_stock NOT LIKE '%''310000''%',
    format('resolve_account=%s ; 310000 en dur=%s', v_stock LIKE '%resolve_account%', v_stock LIKE '%''310000''%'));

  PERFORM _rec('T02', 'le mouvement de stock demande son journal (plus de ''ST'' en dur)',
    v_mvt LIKE '%resolve_journal%' AND v_mvt NOT LIKE '%''ST'',%',
    format('resolve_journal=%s', v_mvt LIKE '%resolve_journal%'));

  PERFORM _rec('T03', 'la clôture d''OF demande ses rôles (plus de 601000/355000/713500 en dur)',
    v_of LIKE '%resolve_account%' AND v_of NOT LIKE '%''601000''%'
      AND v_of NOT LIKE '%''355000''%' AND v_of NOT LIKE '%''713500''%',
    format('resolve_account=%s ; 601000 en dur=%s ; 355000 en dur=%s ; 713500 en dur=%s',
      v_of LIKE '%resolve_account%', v_of LIKE '%''601000''%', v_of LIKE '%''355000''%', v_of LIKE '%''713500''%'));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'resolve_stock_account résout son repli par le RÔLE (plus de 310000 en dur)', false, SQLERRM);
  PERFORM _rec('T02', 'le mouvement de stock demande son journal (plus de ''ST'' en dur)', false, SQLERRM);
  PERFORM _rec('T03', 'la clôture d''OF demande ses rôles (plus de 601000/355000/713500 en dur)', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T04 — les rôles rendent EXACTEMENT les comptes d'avant (FR)
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE t uuid; a text; b text; c text; d text; j text;
BEGIN
  t := _mk_tenant('RSTK1');
  UPDATE tenants SET legislation_pack_code = 'FR' WHERE id = t;
  PERFORM ensure_standard_journals(t);
  a := resolve_account(t, 'ACHATS_MATIERES');
  b := resolve_account(t, 'STOCK_MATIERES');
  c := resolve_account(t, 'STOCK_PRODUITS_FINIS');
  d := resolve_account(t, 'PRODUCTION_STOCKEE');
  j := resolve_journal(t, 'JOURNAL_STOCK');
  PERFORM _rec('T04', 'société FR : ACHATS_MATIERES=601000, STOCK_MATIERES=310000, PRODUITS_FINIS=355000, PRODUCTION_STOCKEE=713500, JOURNAL_STOCK=ST',
    a='601000' AND b='310000' AND c='355000' AND d='713500' AND j='ST',
    format('601000→%s ; 310000→%s ; 355000→%s ; 713500→%s ; ST→%s', a, b, c, d, j));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'société FR : ACHATS_MATIERES=601000, STOCK_MATIERES=310000, PRODUITS_FINIS=355000, PRODUCTION_STOCKEE=713500, JOURNAL_STOCK=ST', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T05 — le choix documenté : la variation garde 603000
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v FROM pg_proc p
   JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='resolve_variation_account';
  PERFORM _rec('T05', 'resolve_variation_account garde ''603000'' — décision documentée (pas de rôle pour la variation générique)',
    v LIKE '%''603000''%',
    format('603000 présent=%s (attendu : oui, à trancher)', v LIKE '%''603000''%'));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T05', 'resolve_variation_account garde ''603000'' — décision documentée (pas de rôle pour la variation générique)', false, SQLERRM);
END $$;

SELECT _audit_assert('388');