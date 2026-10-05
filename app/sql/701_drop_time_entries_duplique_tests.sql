-- ============================================================
-- 701_drop_time_entries_duplique_tests.sql — F.8 :
--   UNE SEULE TABLE DE TEMPS, ET C'EST `timesheets`
--
-- La décision « brancher ou supprimer » de `time_entries` (heritée de la 164,
-- qui l'avait laissée ouverte) est rendue : SUPPRIMER, parce qu'elle double
-- `timesheets` (la table vivante) et n'est lue par rien. Cette suite mesure les
-- deux moitiés de la décision :
--
--   T01  la table est PARTIE (to_regclass NULL) — l'effet de la 701
--   T02  le modèle de temps VIVANT est intact : `timesheets` ET
--        `project_time_entries` existent (non-régression : on n'a rien emporté
--        de ce qui est réellement lu)
--   T03  les deux tables que F.7 doit BRANCHER sont intactes :
--        `collective_agreements` et `collective_classifications`
--   T04  `platform_admins` n'a pas été touchée — c'est un FAUX POSITIF de la
--        liste des coquilles (elle est lue par `is_platform_admin()`)
--
-- NB : T01 suppose la base de CI (neuve, donc `time_entries` vide → supprimée).
-- Sur une base qui porterait des lignes, la 701 CONSERVE la table et le dit :
-- T01 serait alors rouge, et c'est exact — la décision n'est pas appliquée.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '701', false);
DELETE FROM _audit_results WHERE file = '701';

-- T01 — la table est partie
DO $$
DECLARE v_exists boolean;
BEGIN
  v_exists := to_regclass('public.time_entries') IS NOT NULL;
  PERFORM _rec('T01', 'F.8 : `time_entries` est SUPPRIMÉE (le leurre est retiré)',
    NOT v_exists,
    format('to_regclass(time_entries) = %s', COALESCE(to_regclass('public.time_entries')::text, 'NULL')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'F.8 : `time_entries` est supprimée', false, SQLERRM);
END $$;

-- T02 — les DEUX tables de temps réellement lues existent encore
DO $$
BEGIN
  PERFORM _rec('T02', 'non-régression : `timesheets` (paie W9, écrans RH) et `project_time_entries` (projets) sont intactes',
    to_regclass('public.timesheets') IS NOT NULL
      AND to_regclass('public.project_time_entries') IS NOT NULL,
    format('timesheets=%s project_time_entries=%s',
      to_regclass('public.timesheets') IS NOT NULL,
      to_regclass('public.project_time_entries') IS NOT NULL));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'non-régression : les tables de temps vivantes sont intactes', false, SQLERRM);
END $$;

-- T03 — les deux tables à BRANCHER par F.7 (conventions collectives) sont là
DO $$
BEGIN
  PERFORM _rec('T03', 'F.7 : `collective_agreements` et `collective_classifications` sont intactes (à brancher, pas à supprimer)',
    to_regclass('public.collective_agreements') IS NOT NULL
      AND to_regclass('public.collective_classifications') IS NOT NULL,
    format('collective_agreements=%s collective_classifications=%s',
      to_regclass('public.collective_agreements') IS NOT NULL,
      to_regclass('public.collective_classifications') IS NOT NULL));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'F.7 : les tables de conventions collectives sont intactes', false, SQLERRM);
END $$;

-- T04 — platform_admins intacte : ce n'est pas une coquille (lue par du SQL)
DO $$
BEGIN
  PERFORM _rec('T04', '`platform_admins` n''a pas été touchée — FAUX POSITIF de la liste des coquilles (lue par is_platform_admin())',
    to_regclass('public.platform_admins') IS NOT NULL,
    format('platform_admins existe = %s', to_regclass('public.platform_admins') IS NOT NULL));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'platform_admins intacte', false, SQLERRM);
END $$;

-- Le verdict : la suite peut échouer (G5, check-test-suites)
SELECT _audit_assert('701');
