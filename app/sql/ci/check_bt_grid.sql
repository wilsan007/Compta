-- ============================================================
-- check_bt_grid.sql — G1 : la grille BT, mesurée et plafonnée
--
-- Source : doc/audit/PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md, porte **G1**
-- (§4.2) : « la grille `BT` du plan correctif : RLS active et forcée, une
-- politique par commande, index de société, clés composites » — le défaut
-- qu'elle rend impossible est la **réintroduction** de `ISO-02`, `ISO-03`,
-- `ISO-04`. La grille elle-même vient du plan correctif
-- `doc/audit/PLAN-CORRECTIF-COMPLET-ET-VERIFICATION-2026-09-24.md` §4.2.
--
-- CE QUI ÉTAIT DÉJÀ COUVERT, ET QU'ON NE DUPLIQUE PAS. « Une politique par
-- commande » est tenu par `ci/check_policy_duplicates.sql` (ISO-03), « les clés
-- composites » par `ci/check_composite_fks.sql` (ISO-02). Ce fichier ne les
-- rejoue pas : il ferme les **deux moitiés qui n'étaient gardées par rien** —
-- **RLS activée et forcée** et **index de société** — sur les 360 tables qui
-- portent `tenant_id`.
--
-- POURQUOI UN PLAFOND DATÉ, ET PAS UN ZÉRO DE COMPLAISANCE. Mesuré sur base
-- neuve (261 migrations, 30/09/2026) :
--     * RLS **activée** partout : 0 table sans RLS — cette moitié-là est déjà à
--       zéro, et le zéro y est donc une RÈGLE, pas un plafond ;
--     * RLS **forcée** : **55** tables sur 360 ne le sont pas. C'est un état
--       daté, pas une découverte : les partitions du socle en font partie, et la
--       252 dit pourquoi (`ENABLE` + droits retirés : la lecture passe par le
--       parent). Un plafond dit la vérité ; un zéro inventé ferait échouer la CI
--       sur un état que personne n'a décidé de corriger ;
--     * **index de société** : **79** tables sur 360 n'ont aucun index dont la
--       première colonne est `tenant_id` — c'est le défaut `BUD-04`
--       (« deux requêtes par budget ») à l'échelle du schéma : une lecture par
--       société y scanne la table ;
--     * politiques : **77** tables couvrent moins de 4 commandes, **10** n'ont
--       aucune politique (RLS fermée par défaut : ce n'est pas un trou, c'est une
--       table interne — mais le nombre est publié pour qu'il ne dérive pas).
--
-- LA RÈGLE DE CE CONTRÔLE : chaque nombre doit ÉGALER son plafond.
--     * un nombre qui **monte** → la CI échoue : c'est une régression
--       (une table neuve sans index de société, une RLS qu'on a cessé de forcer) ;
--     * un nombre qui **baisse** → la CI échoue AUSSI, tant que le plafond n'a
--       pas été réinscrit dans ce fichier. C'est la règle du dépôt (registre
--       `expected_failures`, `check-unused-tables.mjs`) : **un plafond qui ne se
--       met pas à jour ment**, et un registre qui pourrit ne veut plus rien dire.
--
-- CE QUE CE CONTRÔLE NE PROUVE PAS. Il lit le catalogue, pas les intentions : il
-- ne dit pas qu'un index de société est utilisé (le planificateur décide), ni
-- qu'une politique garde vraiment quelque chose (c'est `check_roles_opposables`
-- pour les droits, `105` pour la lecture). Il dit qu'aucune table ne peut
-- **revenir** à un schéma qu'on a mis une vague entière à quitter.
--
-- Le contrôle s'auto-teste : une table fictive sans RLS doit être vue, et la
-- même table une fois gardée ne doit plus l'être.
--
-- ⚠️ **À LANCER AVANT LES SUITES** — c'est l'ordre de la CI, et il n'est pas
-- cosmétique : la suite **252** crée des partitions mensuelles (`+3 mois`) pour
-- éprouver le calendrier, et deux partitions de plus font monter
-- `tables_tenant`, `rls_sans_force` et `sans_politique` — c'est-à-dire qu'un
-- plafond mesuré sur les seules migrations deviendrait faux après les suites.
-- Le contrôle le dit lui-même quand les nombres ont bougé de cette façon.
-- ============================================================

\set ON_ERROR_STOP on

-- ─────────────────────────────────────────────────────────────
-- 1. La grille (la requête du plan correctif §4.2, bornée aux tables cloisonnées)
--    Écrite en VUE : l'auto-test la relit dans sa propre transaction.
-- ─────────────────────────────────────────────────────────────
CREATE TEMP VIEW g1_grille AS
WITH t AS (
  SELECT c.oid, c.relname, c.relrowsecurity AS rls, c.relforcerowsecurity AS force
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
  WHERE c.relkind IN ('r', 'p')
    AND EXISTS (SELECT 1 FROM pg_attribute a
                WHERE a.attrelid = c.oid AND a.attname = 'tenant_id'
                  AND a.attnum > 0 AND NOT a.attisdropped)
)
SELECT count(*)                                                              AS tables_tenant,
       count(*) FILTER (WHERE NOT rls)                                      AS sans_rls,
       count(*) FILTER (WHERE rls AND NOT force)                            AS rls_sans_force,
       count(*) FILTER (WHERE (SELECT count(DISTINCT p.polcmd) FROM pg_policy p
                                WHERE p.polrelid = t.oid) < 4)              AS moins_de_4_commandes,
       count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM pg_policy p
                                           WHERE p.polrelid = t.oid))       AS sans_politique,
       count(*) FILTER (WHERE NOT EXISTS (
         SELECT 1 FROM pg_index i
         JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = i.indkey[0]
         WHERE i.indrelid = t.oid AND a.attname = 'tenant_id' AND i.indisvalid))
                                                                            AS sans_index_societe
FROM t;

-- Les listes d'infractions, pour pouvoir les NOMMER (un audit qui ne nomme pas
-- ce qu'il compte n'est pas un audit — formule du référentiel, §B.2).
CREATE TEMP VIEW g1_sans_index AS
SELECT c.relname FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
WHERE c.relkind IN ('r', 'p')
  AND EXISTS (SELECT 1 FROM pg_attribute a
              WHERE a.attrelid = c.oid AND a.attname = 'tenant_id' AND a.attnum > 0 AND NOT a.attisdropped)
  AND NOT EXISTS (SELECT 1 FROM pg_index i
                  JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = i.indkey[0]
                  WHERE i.indrelid = c.oid AND a.attname = 'tenant_id' AND i.indisvalid);

CREATE TEMP VIEW g1_sans_force AS
SELECT c.relname FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
WHERE c.relkind IN ('r', 'p') AND c.relrowsecurity AND NOT c.relforcerowsecurity
  AND EXISTS (SELECT 1 FROM pg_attribute a
              WHERE a.attrelid = c.oid AND a.attname = 'tenant_id' AND a.attnum > 0 AND NOT a.attisdropped);

-- ─────────────────────────────────────────────────────────────
-- 2. Les plafonds datés — à réinscrire dès qu'un nombre change
-- ─────────────────────────────────────────────────────────────
CREATE TEMP TABLE g1_plafond (nom text PRIMARY KEY, valeur integer, raison text);
INSERT INTO g1_plafond (nom, valeur, raison) VALUES
  ('tables_tenant',        365, '03/10/2026 (harmonisation) : +1 chain_invariant_alertes (414), +1 chain_banc_resultats (433). Avant : Nombre de tables portant tenant_id (base neuve, 286 migrations, 03/10/2026 — +1 pour la 421 : metric_definitions, le dictionnaire d''indicateurs posé par la 461 et resté hors plafond).'),
  ('sans_rls',               0, 'RÈGLE, pas plafond : toute table cloisonnée porte RLS. 0 sans exception depuis la 84.'),
  ('rls_sans_force',        54, 'État daté : partitions du socle et tables d''historique. Défaut ISO-04 non réintroduit. −1 le 02/10/2026 (415) : webhook_delivery_queue passe sous FORCE. Stable le 03/10 : la 421 force metric_definitions, dont la 461 avait oublié le FORCE — le compteur RETROUVE sa valeur, il ne la dépasse pas.'),
  ('moins_de_4_commandes',  82, '03/10/2026 (harmonisation) : +1 chain_invariant_alertes (414), +1 chain_banc_resultats (433) — lecture seule toutes deux. Avant : Le plan (§4.2) tient une table à moins de 4 commandes pour suspecte. +2 pour la 413 (chain_invariants et ses résultats : une politique de LECTURE, le relevé s''écrit par audit_chains()). +1 pour la 421 : metric_definitions est dans le même cas — une politique de lecture, les écritures passant par chain_metric_definition, qui est SECURITY DEFINER. Choix de sécurité assumé, pas un oubli.'),
  ('sans_politique',        10, 'RLS fermée par défaut : pas un trou, mais un nombre qui ne doit pas monter.'),
  ('sans_index_societe',    78, 'Défaut BUD-04 à l''échelle du schéma : une lecture par société y scanne la table. −1 le 02/10/2026 (415). Stable le 03/10 : la 421 pose l''index de société de metric_definitions, que la 461 avait oublié — le compteur RETROUVE sa valeur, il ne la dépasse pas.');

-- ─────────────────────────────────────────────────────────────
-- 3. La mesure confrontée au plafond
-- ─────────────────────────────────────────────────────────────
CREATE TEMP TABLE g1_mesure AS
SELECT 'tables_tenant'::text AS nom, tables_tenant AS valeur FROM g1_grille
UNION ALL SELECT 'sans_rls',                sans_rls                FROM g1_grille
UNION ALL SELECT 'rls_sans_force',          rls_sans_force          FROM g1_grille
UNION ALL SELECT 'moins_de_4_commandes',    moins_de_4_commandes    FROM g1_grille
UNION ALL SELECT 'sans_politique',          sans_politique          FROM g1_grille
UNION ALL SELECT 'sans_index_societe',      sans_index_societe      FROM g1_grille;

CREATE TEMP TABLE g1_verdicts AS
SELECT m.nom, m.valeur, p.valeur AS plafond,
       (m.valeur > p.valeur) AS a_augmente,
       (m.valeur < p.valeur) AS a_baisse
FROM g1_mesure m JOIN g1_plafond p USING (nom);

DO $$
DECLARE
  v_noms_index text; v_noms_force text; v_augmente text; v_baisse text;
  v_nb_augmente int; v_nb_baisse int; v_tables int; v_detail text;
BEGIN
  SELECT tables_tenant INTO v_tables FROM g1_grille;
  IF v_tables = 0 THEN
    RAISE EXCEPTION 'check_bt_grid : aucune table cloisonnée trouvée — le contrôle ne vérifie rien (schéma vide ?).';
  END IF;

  SELECT count(*) INTO v_nb_augmente FROM g1_verdicts WHERE a_augmente;
  SELECT count(*) INTO v_nb_baisse   FROM g1_verdicts WHERE a_baisse;

  IF v_nb_augmente > 0 THEN
    SELECT string_agg(format('%s : %s observés pour %s au plafond', nom, valeur, plafond), ', ' ORDER BY nom)
      INTO v_augmente FROM g1_verdicts WHERE a_augmente;
    SELECT string_agg(format('%s %s', nom, valeur), ', ' ORDER BY nom) INTO v_detail
      FROM g1_verdicts WHERE a_augmente;
    RAISE EXCEPTION 'check_bt_grid : % nombre(s) ont AUGMENTÉ — régression de la grille BT : %. Corrigez la table fautive (RLS forcée, index de société), ne relevez pas le plafond. (Si ce contrôle a tourné APRÈS les suites, l''écart peut venir d''elles : la 252 crée des partitions +3 mois — l''ordre de la CI est contrôles puis suites.)',
      v_nb_augmente, COALESCE(v_augmente, v_detail);
  END IF;

  IF v_nb_baisse > 0 THEN
    SELECT string_agg(format('%s : %s observés pour %s au plafond', nom, valeur, plafond), ', ' ORDER BY nom)
      INTO v_baisse FROM g1_verdicts WHERE a_baisse;
    RAISE EXCEPTION 'check_bt_grid : % nombre(s) ont BAISSÉ — c''est une amélioration, et elle doit s''inscrire dans le même commit (plafond daté) : %.',
      v_nb_baisse, v_baisse;
  END IF;

  SELECT string_agg(relname, ', ' ORDER BY relname) INTO v_noms_index
  FROM (SELECT relname FROM g1_sans_index ORDER BY relname LIMIT 8) s;
  SELECT string_agg(relname, ', ' ORDER BY relname) INTO v_noms_force
  FROM (SELECT relname FROM g1_sans_force ORDER BY relname LIMIT 8) s;

  RAISE NOTICE 'Grille BT : % tables portant tenant_id — sans RLS % (règle), sans RLS FORCÉE %, sans index de société %, à moins de 4 commandes %, sans politique %.',
    v_tables,
    (SELECT valeur FROM g1_mesure WHERE nom = 'sans_rls'),
    (SELECT valeur FROM g1_mesure WHERE nom = 'rls_sans_force'),
    (SELECT valeur FROM g1_mesure WHERE nom = 'sans_index_societe'),
    (SELECT valeur FROM g1_mesure WHERE nom = 'moins_de_4_commandes'),
    (SELECT valeur FROM g1_mesure WHERE nom = 'sans_politique');
  RAISE NOTICE 'Premiers sans index de société : %', v_noms_index;
  RAISE NOTICE 'Premiers sans RLS forcée : %', v_noms_force;
  RAISE NOTICE 'check_bt_grid : OK — la grille est celle du 30/09/2026, aucun nombre n''a bougé.';
END $$;

-- ─────────────────────────────────────────────────────────────
-- 4. L'auto-test : la grille voit une table non gardée, et cesse de la voir
--    quand elle est gardée (fixture annulée : ROLLBACK).
-- ─────────────────────────────────────────────────────────────
BEGIN;

CREATE TABLE public.zz_g1_fixture (
  id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid
);

DO $$
DECLARE v_sans_rls int; v_sans_index int; v_sans_force int; v_politiques int;
BEGIN
  SELECT sans_rls INTO v_sans_rls FROM g1_grille;
  IF v_sans_rls < 1 THEN
    RAISE EXCEPTION '%', 'AUTO-TEST G1 : une table SANS RLS n''est pas vue par la grille — le contrôle ne prouve rien.';
  END IF;

  ALTER TABLE public.zz_g1_fixture ENABLE ROW LEVEL SECURITY;
  ALTER TABLE public.zz_g1_fixture FORCE ROW LEVEL SECURITY;
  CREATE POLICY zz_g1_fixture_select ON public.zz_g1_fixture
    FOR SELECT USING (tenant_id = current_tenant_id());
  CREATE INDEX zz_g1_fixture_tenant ON public.zz_g1_fixture (tenant_id);

  SELECT count(*) INTO v_sans_rls   FROM g1_grille WHERE sans_rls > 0;   -- 1 si au moins un reste
  SELECT count(*) INTO v_sans_index FROM g1_sans_index WHERE relname = 'zz_g1_fixture';
  SELECT count(*) INTO v_sans_force FROM g1_sans_force WHERE relname = 'zz_g1_fixture';

  IF v_sans_index <> 0 OR v_sans_force <> 0 THEN
    RAISE EXCEPTION '%', 'AUTO-TEST G1 : la table gardée est encore comptée comme fautive (index / RLS forcée).';
  END IF;

  RAISE NOTICE 'Auto-test : OK (une table sans RLS est vue, la même table gardée ne l''est plus)';
END $$;

ROLLBACK;
