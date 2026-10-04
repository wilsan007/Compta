-- ============================================================
-- 461_metric_definitions_tests.sql — I-08, l'explicabilité : le
--   dictionnaire de données unique.
--
-- I-08 du référentiel (D.4) : « sur n'importe quel montant, un bouton
-- qui déroule la chaîne des documents et écritures qui produit ce
-- montant ». Sa condition technique n'est pas l'écran : « un
-- indicateur est une requête NOMMÉE et DATÉE, jamais un calcul recopié
-- dans un écran ».
--
-- MESURÉ LE 02/10/2026, avant correction : **5 fichiers** de
-- `src/lib/queries/` calculent une marge projet, **8** un suivi
-- budgétaire — chacun avec SA version (définitions concurrentes,
-- BUD-01 / PROJ-02). Un ERP qui dit « voici d'où vient ce chiffre »
-- doit d'abord savoir de QUEL chiffre il parle.
--
--   T01  STRUCTURE : RLS active, lecture pour `authenticated`, aucun
--        droit d'écriture ;
--   T02  RÉSOLUTION : la définition EN VIGUEUR à une date ;
--   T03  DATATION : une version récente ne s'applique PAS à une date
--        antérieure — une définition est datée, pas « la dernière » ;
--   T04  CHEVAUCHEMENT : deux définitions concurrentes de la même
--        période sont REFUSÉES — le remède structurel ;
--   T05  INCONNU : un indicateur inconnu est refusé, jamais deviné ;
--   T06  TENANT : la société prime sur le standard.
--
-- Vu ROUGE sur le code d'avant : la table n'existe pas, T01→T06 rouges.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '461', false);
DELETE FROM _audit_results WHERE file = '461';
-- Rejouabilité : le dictionnaire garde ses lignes d'une exécution à l'autre.
-- On repart donc de zéro sur les deux codes que cette suite utilise — sinon
-- le second passage buterait sur la version 2 déjà posée. C'est mesuré.
DELETE FROM metric_definitions WHERE code IN ('projet.marge', 'budget.realise');

DROP FUNCTION IF EXISTS _i8_standard();
CREATE OR REPLACE FUNCTION _i8_standard() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO metric_definitions (tenant_id, code, version, libelle, unite, sql_definition, valide_du, valide_au)
  VALUES
    (NULL, 'projet.marge', 1, 'Marge projet', '%', 'SELECT 1::numeric', DATE '2026-01-01', DATE '2026-06-30'),
    (NULL, 'budget.realise', 1, 'Réalisé budgétaire', 'EUR', 'SELECT 1::numeric', DATE '2026-01-01', NULL);
END $$;

-- ── T01 — structure
DO $$
DECLARE v_rls boolean; v_lecture boolean; v_ecriture boolean;
BEGIN
  SELECT c.relrowsecurity INTO v_rls FROM pg_class c
   WHERE c.oid = 'public.metric_definitions'::regclass;
  SELECT has_table_privilege('authenticated', 'public.metric_definitions', 'SELECT') INTO v_lecture;
  SELECT has_table_privilege('authenticated', 'public.metric_definitions', 'INSERT')
      OR has_table_privilege('authenticated', 'public.metric_definitions', 'UPDATE')
      OR has_table_privilege('authenticated', 'public.metric_definitions', 'DELETE') INTO v_ecriture;
  PERFORM _rec('T01', 'STRUCTURE : RLS active, lisible par authenticated, AUCUN droit d''écriture',
    COALESCE(v_rls, false) AND COALESCE(v_lecture, false) AND NOT COALESCE(v_ecriture, true),
    format('RLS=%s, SELECT=%s, écriture=%s',
           COALESCE(v_rls::text, 'table absente'), v_lecture, v_ecriture));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'T01 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ── T02 — résolution
DO $$
DECLARE v_libelle text; v_version int;
BEGIN
  PERFORM _i8_standard();
  SELECT libelle, version INTO v_libelle, v_version
    FROM chain_metric_definition(NULL, 'projet.marge', DATE '2026-06-30');
  PERFORM _rec('T02', 'RÉSOLUTION : la définition EN VIGUEUR à une date est rendue',
    v_libelle = 'Marge projet' AND v_version = 1,
    format('« %s » (version %s)', v_libelle, v_version));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'T02 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ── T03 — datation
DO $$
DECLARE v_version int;
BEGIN
  INSERT INTO metric_definitions (tenant_id, code, version, libelle, unite, sql_definition, valide_du)
  VALUES (NULL, 'projet.marge', 2, 'Marge projet (nouvelle formule)', '%',
          'SELECT 2::numeric', DATE '2026-07-01');
  SELECT version INTO v_version FROM chain_metric_definition(NULL, 'projet.marge', DATE '2026-06-15');
  PERFORM _rec('T03', 'DATATION : une version récente ne s''applique PAS à une date antérieure',
    v_version = 1, format('au 15/06 : version %s (1 attendue)', v_version));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'T03 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ── T04 — chevauchement refusé
DO $$
DECLARE v_refus text;
BEGIN
  BEGIN
    -- Une variante qui chevauche la version 1 : deux réponses au même
    -- « quelle est la marge ? », sur la même période. Doit être refusé.
    INSERT INTO metric_definitions (tenant_id, code, version, libelle, unite, sql_definition, valide_du, valide_au)
    VALUES (NULL, 'projet.marge', 3, 'Marge (variante concurrente)', '%',
            'SELECT 3::numeric', DATE '2026-01-01', DATE '2026-12-31');
    v_refus := 'accepté';
  EXCEPTION WHEN others THEN
    -- On exige le MARQUEUR DU GARDE, pas un refus quelconque : sinon le
    -- scénario est vert dès que la table n'existe pas — un faux vert,
    -- la faute que la doctrine du dépôt interdit (mesuré à la première
    -- exécution).
    v_refus := SQLERRM;
  END;
  PERFORM _rec('T04', 'CHEVAUCHEMENT : deux définitions concurrentes de la même période sont REFUSÉES',
    coalesce(v_refus, '') LIKE '%CHEVAUCHEMENT%',
    format('refus : %s', left(coalesce(v_refus, 'aucun'), 70)));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'T04 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ── T05 — indicateur inconnu
DO $$
DECLARE v_refus text;
BEGIN
  BEGIN
    PERFORM chain_metric_definition(NULL, 'indicateur.qui.nexiste.pas', DATE '2026-06-30');
    v_refus := 'accepté';
  EXCEPTION WHEN others THEN
    -- Idem T04 : c'est le MARQUEUR qui compte, sinon l'absence de la
    -- table suffirait à verdir le scénario.
    v_refus := SQLERRM;
  END;
  PERFORM _rec('T05', 'INCONNU : un indicateur inconnu est refusé, jamais deviné',
    coalesce(v_refus, '') LIKE '%METRIC_DEFINITION_INCONNUE%',
    format('refus : %s', left(coalesce(v_refus, 'aucun'), 70)));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T05', 'T05 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ── T06 — la définition de la société prime
DO $$
DECLARE t uuid := _mk_tenant('metriques'); v_libelle text;
BEGIN
  INSERT INTO metric_definitions (tenant_id, code, version, libelle, unite, sql_definition, valide_du)
  VALUES (t, 'projet.marge', 1, 'Marge projet (conventions de la société)', '%',
          'SELECT 9::numeric', DATE '2026-01-01');
  SELECT libelle INTO v_libelle FROM chain_metric_definition(t, 'projet.marge', DATE '2026-06-30');
  PERFORM _rec('T06', 'TENANT : la définition de la société prime sur le standard',
    v_libelle = 'Marge projet (conventions de la société)',
    format('résolu : « %s »', v_libelle));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T06', 'T06 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- NETTOYAGE. Un test qui écrit dans le dictionnaire — une table de
-- PRODUCTION — doit rendre l'état qu'il a trouvé. On l'avait mesuré :
-- la suite 461 laissait `projet.marge` v1 et v2 derrière elle, et la
-- migration 463 (les définitions réelles) se faisait alors REFUSER par
-- le garde anti-chevauchement. Un test qui pollue une table partagée
-- casse le travail suivant — c'est un défaut, pas un détail.
DELETE FROM metric_definitions WHERE code IN ('projet.marge', 'budget.realise');

SELECT _audit_assert('461');
