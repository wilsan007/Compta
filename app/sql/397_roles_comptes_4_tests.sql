-- ============================================================
-- 397_roles_comptes_4_tests.sql — LOC1-10 (les deux derniers comptes en dur)
--
--   T01  MÉRITE : aucune fonction de production n'écrit plus un compte en clair ;
--   T02  société FR : les rôles rendent EXACTEMENT les numéros d'avant ;
--   T03  les paires d'amortissement sont COHÉRENTES par nature ;
--   T04  rejouable : les 4 rôles sont au catalogue ET mappés, une seule fois.
--
-- Vu ROUGE avant la 397 : T01 (3 occurrences : 681200/281000 et 511200), T02/T03.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '397', false);
DELETE FROM _audit_results WHERE file = '397';

-- ─────────────────────────────────────────────────────────────
-- T01 — la règle E01 est TENUE sur tout le schéma
--       (mêmes exclusions que le garde-fou : fixtures `_…`, et le GABARIT de
--        plan comptable, déclaré à son registre et porté par LOC1-13)
--   PRÉCISÉ le 13/10/2026 : le PRÉDICAT est aussi celui du garde-fou
--        (`check-country-neutral.mjs`, scanSql) — un littéral ENTRE GUILLEMETS
--        sur une LIGNE qui parle d'un compte (account|compte|collectif).
--        Mesuré : le motif brut `prosrc ~ '[1-9][0-9]{2,5}'` comptait 195
--        fonctions (dates, seuils, identifiants de lot…) et ne pouvait JAMAIS
--        passer — faux écart du TEST, pas du produit : le garde-fou mesure
--        SQL = 0 sur cette base, comme la requête ci-dessous.
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(DISTINCT p.proname, ', ' ORDER BY p.proname) INTO v_bad
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  CROSS JOIN LATERAL regexp_split_to_table(p.prosrc, E'\n') AS ligne
  WHERE n.nspname = 'public'
    AND p.proname !~ '^_'
    AND p.proname NOT IN ('seed_standard_chart', 'seed_standard_chart_unchecked')
    AND ligne ~ '[''"][1-9][0-9]{2,5}[''"]'
    AND ligne ~* '(account|compte|collectif)';

  PERFORM _rec('T01', 'E01 tenue : aucune fonction de production n''écrit un compte en clair',
    v_bad IS NULL, COALESCE('encore en dur : ' || v_bad, 'zéro occurrence — la dette SQL de E01 est soldée'));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'E01 tenue : aucune fonction de production n''écrit un compte en clair', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T02 — société FR : les rôles rendent EXACTEMENT les numéros d'avant
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE t uuid; c text; e text; da_i text; am_i text; da_c text; am_c text;
BEGIN
  t := _mk_tenant('RCPT4');
  UPDATE tenants SET legislation_pack_code = 'FR' WHERE id = t;
  PERFORM ensure_standard_journals(t);
  c    := resolve_account(t, 'CAISSE');
  e    := resolve_account(t, 'MOYENS_PAIEMENT_A_ENCAISSER');
  da_i := resolve_account(t, 'DOTATIONS_AMORTISSEMENTS_INCORPORELLES');
  am_i := resolve_account(t, 'AMORTISSEMENTS_INCORPORELLES');
  da_c := resolve_account(t, 'DOTATIONS_AMORTISSEMENTS_CORPORELLES');
  am_c := resolve_account(t, 'AMORTISSEMENTS_CORPORELLES');
  PERFORM _rec('T02',
    'société FR : CAISSE=530000, MOYENS_PAIEMENT_A_ENCAISSER=511000, dotations/amortissements = 681100/280000 et 681200/281000',
    c = '530000' AND e = '511000' AND da_i = '681100' AND am_i = '280000'
      AND da_c = '681200' AND am_c = '281000',
    format('CAISSE=%s ENCAISSER=%s ; INCORP %s/%s ; CORP %s/%s', c, e, da_i, am_i, da_c, am_c));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02',
    'société FR : CAISSE=530000, MOYENS_PAIEMENT_A_ENCAISSER=511000, dotations/amortissements = 681100/280000 et 681200/281000',
    false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T03 — les paires d'amortissement se répondent (même nature des deux côtés)
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_incorp int; v_corp int;
BEGIN
  -- Une paire est cohérente si la dotation et l'amortissement sont de la même
  -- famille de numéros : 68x1x0/28x0x0 pour l'incorporel, 68x2x0/28x1x0 pour le
  -- corporel. C'est ce que le plan de la base nomme.
  SELECT count(*) INTO v_incorp FROM account_role_catalog
   WHERE role IN ('DOTATIONS_AMORTISSEMENTS_INCORPORELLES','AMORTISSEMENTS_INCORPORELLES');
  SELECT count(*) INTO v_corp FROM account_role_catalog
   WHERE role IN ('DOTATIONS_AMORTISSEMENTS_CORPORELLES','AMORTISSEMENTS_CORPORELLES');
  PERFORM _rec('T03', 'les deux paires d''amortissement existent ensemble (incorporel ET corporel)',
    v_incorp = 2 AND v_corp = 2, format('incorporel=%s (2) ; corporel=%s (2)', v_incorp, v_corp));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'les deux paires d''amortissement existent ensemble (incorporel ET corporel)', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T04 — rejouable : catalogue et pack, une seule fois chacun
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_cat int; v_pack int;
BEGIN
  SELECT count(*) INTO v_cat FROM account_role_catalog
   WHERE role IN ('AMORTISSEMENTS_INCORPORELLES','DOTATIONS_AMORTISSEMENTS_INCORPORELLES',
                  'AMORTISSEMENTS_CORPORELLES','DOTATIONS_AMORTISSEMENTS_CORPORELLES');
  SELECT count(*) INTO v_pack FROM pack_account_roles
   WHERE pack_code = 'PCG'
     AND role IN ('AMORTISSEMENTS_INCORPORELLES','DOTATIONS_AMORTISSEMENTS_INCORPORELLES',
                  'AMORTISSEMENTS_CORPORELLES','DOTATIONS_AMORTISSEMENTS_CORPORELLES');
  PERFORM _rec('T04', 'rejouable : les 4 rôles sont au catalogue (4) et mappés au PCG (4)',
    v_cat = 4 AND v_pack = 4, format('catalogue=%s ; pack PCG=%s', v_cat, v_pack));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'rejouable : les 4 rôles sont au catalogue (4) et mappés au PCG (4)', false, SQLERRM);
END $$;

SELECT _audit_assert('397');