-- ============================================================
-- check_forced_rls_writers.sql — G7 : le socle peut-il écrire ?
--
-- LA TROUVAILLE QU'IL REND VISIBLE. `FORCE ROW LEVEL SECURITY` fait que la RLS
-- s'applique AUSSI au PROPRIÉTAIRE de la table. Sur les tables du socle des
-- chaînages (`document_links`, `domain_events`, `document_effects`,
-- `chain_traces`, `chain_regeneration_log`, `chain_settings`), il n'existe
-- qu'UNE politique : la LECTURE. Il n'y a donc AUCUNE politique d'écriture — et
-- l'absence de politique EST le refus.
--
-- CONSÉQUENCE, si le propriétaire de ces tables n'est ni superutilisateur ni
-- `BYPASSRLS` : le socle **ne peut pas écrire**, et `link_documents` ne le peut
-- pas non plus — une fonction `SECURITY DEFINER` s'exécute **en tant que son
-- propriétaire**. Toute la chaîne serait muette, en production, sans une erreur
-- au déploiement.
--
-- EXPÉRIENCE MESURÉE LE 30/09 (base neuve, UNE seule variable : le propriétaire) :
--     * mesure A — propriétaire NON superutilisateur, SANS bypass
--       → `ERROR: new row violates row-level security policy for table
--          "document_links"` (42501) ;
--     * mesure B — MÊME table, MÊME phrase, propriétaire AVEC `BYPASSRLS` → acceptée ;
--     * mesure C — propriétaire superutilisateur → acceptée.
-- Les trois mesures sont reproductibles par le §8 du document de la tranche 3.
--
-- POURQUOI CE CONTRÔLE A QUELQUE CHOSE EN PLUS. La CI ne peut pas voir le défaut :
-- son `postgres` est superutilisateur, donc le RLS y est contourné. Un contrôle
-- qui se contenterait de compter les tables serait donc vert partout. Celui-ci
-- publie d'abord **le verdict de l'environnement** — quel rôle possède ces
-- tables, et ce rôle contourne-t-il la RLS ? — puis il ÉCHOUE si cet
-- environnement est muet. Sur une copie de production, c'est donc **le
-- diagnostic**, exécutable en une commande.
--
-- LA RÈGLE DU PLAFOND (celle de G1). Mesuré sur base neuve, 02/10/2026 :
--     * **314** tables sous `FORCE ROW LEVEL SECURITY` ;
--     * dont **15** sans AUCUNE politique d'écriture — c'est l'exposition : leur
--       propriétaire ne peut pas écrire dès qu'il n'est ni super ni bypass ;
--     * les **six** tables du socle en font partie, et c'est le lien avec L3.
--     * +2 et +2 pour la **413** (L4, invariants) : `chain_invariants` et
--       `chain_invariant_results`. Elles sont volontairement muettes — le
--       registre et le relevé ne s'écrivent que par `audit_chains`
--       (SECURITY DEFINER), jamais par le client : c'est un choix de
--       sécurité assumé, la raison est écrite dans la migration.
--     * +1 et +1 pour la **414** : `chain_invariant_alertes`, même raison
--       (`chain_alertes_lancer`, `service_role`).
-- Ces deux nombres sont DATÉS. S'ils **montent**, c'est une régression. S'ils
-- **baissent**, c'est une amélioration — et elle s'inscrit dans le même commit
-- (la règle du dépôt : un plafond qui ne se met pas à jour ment).
--
-- CE QUE CE CONTRÔLE NE PROUVE PAS. Il ne dit pas que la production est muette :
-- il dit ce que vaut, DANS L'ENVIRONNEMENT OÙ IL TOURNE, le droit d'écrire du
-- propriétaire. La réponse pour la production vient de la copie de production.
-- ============================================================

\set ON_ERROR_STOP on


-- ─────────────────────────────────────────────────────────────
-- 1. La mesure — les tables sous FORCE, et celles que leur propriétaire ne
--    pourra pas écrire.
-- ─────────────────────────────────────────────────────────────
CREATE TEMP VIEW g7_exposition AS
SELECT c.relname                       AS table_name,
       pg_get_userbyid(c.relowner)     AS proprietaire,
       r.rolsuper                      AS super,
       r.rolbypassrls                  AS bypass,
       (r.rolsuper OR r.rolbypassrls)  AS environnement_ecrit,
       (SELECT count(*) FROM pg_policies p
         WHERE p.schemaname = 'public' AND p.tablename = c.relname
           AND p.cmd IN ('INSERT', 'UPDATE', 'DELETE', 'ALL')) AS politiques_ecriture
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_roles r ON r.rolname = pg_get_userbyid(c.relowner)
 WHERE n.nspname = 'public'
   AND c.relkind = 'r'
   AND c.relforcerowsecurity;

CREATE TEMP TABLE g7_mesure AS
SELECT (SELECT count(*) FROM g7_exposition) AS tables_forcees,
       (SELECT count(*) FROM g7_exposition WHERE politiques_ecriture = 0) AS muettes,
       (SELECT count(*) FROM g7_exposition
         WHERE politiques_ecriture = 0 AND NOT environnement_ecrit) AS muettes_ici;

-- Plafond DATÉ (une ligne à mettre à jour, jamais à relever sans la mesurer)
-- Mesuré le 02/10/2026 sur base neuve (273 migrations) : 314 tables sous FORCE
-- RLS, dont 15 sans AUCUNE politique d'écriture. Le +1/+1 vient de la 414
-- (`chain_invariant_alertes`), qui est volontairement MUETTE — elle ne s'écrit
-- que par `chain_alertes_lancer` (SECURITY DEFINER, rôle `service_role`), jamais
-- par le client. C'est la même raison que les deux tables de la 413.
CREATE TEMP TABLE g7_plafond (nom text PRIMARY KEY, plafond int);
INSERT INTO g7_plafond VALUES
  ('tables_forcees', 314),
  ('muettes',         15);

DO $$
DECLARE
  v_tables int; v_muettes int; v_muettes_ici int;
  v_proprietaires text; v_verdict text; v_detail text;
BEGIN
  SELECT tables_forcees, muettes, muettes_ici
    INTO v_tables, v_muettes, v_muettes_ici
    FROM g7_mesure;

  SELECT string_agg(DISTINCT format('%s (super=%s, bypass=%s)', proprietaire, super, bypass), ', ')
    INTO v_proprietaires FROM g7_exposition;

  IF v_muettes_ici = 0 THEN
    v_verdict := 'OK — le propriétaire du socle écrit (superutilisateur ou BYPASSRLS)';
  ELSE
    v_verdict := 'MUET — ' || v_muettes_ici || ' table(s) que leur propriétaire ne peut PAS écrire';
  END IF;

  RAISE NOTICE 'check_forced_rls_writers : % table(s) sous FORCE RLS, dont % sans AUCUNE politique d''écriture. Propriétaire(s) : %.',
    v_tables, v_muettes, v_proprietaires;
  RAISE NOTICE 'Environnement : %', v_verdict;

  IF v_tables <> (SELECT plafond FROM g7_plafond WHERE nom = 'tables_forcees') THEN
    RAISE EXCEPTION 'check_forced_rls_writers : les tables sous FORCE RLS sont % (plafond daté : %). À la hausse c''est une exposition neuve ; à la baisse c''est une amélioration, à inscrire ici dans le même commit.',
      v_tables, (SELECT plafond FROM g7_plafond WHERE nom = 'tables_forcees');
  END IF;

  IF v_muettes <> (SELECT plafond FROM g7_plafond WHERE nom = 'muettes') THEN
    RAISE EXCEPTION 'check_forced_rls_writers : % table(s) sous FORCE RLS n''ont AUCUNE politique d''écriture (plafond daté : %). Si le nombre a baissé, la table a été corrigée : mettre le plafond à jour ici. S''il a monté, une table vient d''être condamnée à ne pas pouvoir écrire.',
      v_muettes, (SELECT plafond FROM g7_plafond WHERE nom = 'muettes');
  END IF;

  IF v_muettes_ici > 0 THEN
    SELECT string_agg(format('%s (propriétaire %s)', table_name, proprietaire), ', ' ORDER BY table_name)
      INTO v_detail FROM g7_exposition WHERE politiques_ecriture = 0 AND NOT environnement_ecrit;
    RAISE EXCEPTION 'check_forced_rls_writers : LE SOCLE EST MUET DANS CET ENVIRONNEMENT — % table(s) sous FORCE RLS sans politique d''écriture, et leur propriétaire n''est ni superutilisateur ni BYPASSRLS : %. Trois issues, à trancher sur la copie de production : `NO FORCE ROW LEVEL SECURITY` sur ces tables (le propriétaire écrit, `authenticated` reste filtré — c''est l''intention écrite dans l''en-tête de la 252), une politique d''écriture pour le propriétaire, ou `BYPASSRLS` accordé au rôle.',
      v_muettes_ici, v_detail;
  END IF;

  RAISE NOTICE 'check_forced_rls_writers : OK — la RLS forcée et le droit d''écrire de son propriétaire sont cohérents ici.';
END $$;



-- ─────────────────────────────────────────────────────────────
-- 2. L'auto-test — la sonde doit VOIR, et le mécanisme doit être réel.
--    Tout est annulé (ROLLBACK) : le contrôle ne laisse rien derrière lui.
-- ─────────────────────────────────────────────────────────────
BEGIN;

CREATE TABLE public.zz_g7_fixture (
  id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  libelle text
);

DO $$
DECLARE
  v_orig text := current_user;
  v_avant int; v_apres int; v_etat text; v_message text;
BEGIN
  -- (1) Une table non gardée n'est pas dans l'exposition
  SELECT count(*) INTO v_avant FROM g7_exposition WHERE table_name = 'zz_g7_fixture';

  -- (2) FORCE + une politique de LECTURE seule : elle y entre
  ALTER TABLE public.zz_g7_fixture ENABLE ROW LEVEL SECURITY;
  ALTER TABLE public.zz_g7_fixture FORCE ROW LEVEL SECURITY;
  CREATE POLICY zz_g7_fixture_select ON public.zz_g7_fixture FOR SELECT USING (true);

  SELECT count(*) INTO v_apres FROM g7_exposition
   WHERE table_name = 'zz_g7_fixture' AND politiques_ecriture = 0;

  IF v_avant <> 0 OR v_apres <> 1 THEN
    RAISE EXCEPTION 'AUTO-TEST G7 : la sonde ne voit pas une table FORCE RLS sans politique d''écriture (avant=%, après=%) — le contrôle ne prouve rien.', v_avant, v_apres;
  END IF;

  -- (3) Le MÉCANISME : un propriétaire non superutilisateur, sans bypass, est refusé
  CREATE ROLE zz_g7_owner NOLOGIN;
  GRANT USAGE, CREATE ON SCHEMA public TO zz_g7_owner;
  ALTER TABLE public.zz_g7_fixture OWNER TO zz_g7_owner;

  PERFORM set_config('role', 'zz_g7_owner', true);
  BEGIN
    INSERT INTO public.zz_g7_fixture (libelle) VALUES ('refus attendu');
    v_etat := 'AUCUN REFUS';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_etat = RETURNED_SQLSTATE, v_message = MESSAGE_TEXT;
  END;
  PERFORM set_config('role', v_orig, true);

  IF v_etat <> '42501' THEN
    RAISE EXCEPTION 'AUTO-TEST G7 : un propriétaire ni superutilisateur ni BYPASSRLS a pu écrire sur une table FORCE RLS sans politique (état=%) — le mécanisme mesuré le 30/09 ne se reproduit plus, ce contrôle ne protège plus rien.', v_etat;
  END IF;

  -- (4) Une politique d'écriture la sort de l'exposition
  CREATE POLICY zz_g7_fixture_insert ON public.zz_g7_fixture FOR INSERT WITH CHECK (true);

  SELECT count(*) INTO v_apres FROM g7_exposition
   WHERE table_name = 'zz_g7_fixture' AND politiques_ecriture = 0;

  IF v_apres <> 0 THEN
    RAISE EXCEPTION 'AUTO-TEST G7 : une table dotée d''une politique d''écriture est encore comptée comme muette — le contrôle compte mal.';
  END IF;

  RAISE NOTICE 'Auto-test : OK (la table FORCE RLS sans écriture est vue, son propriétaire est refusé en 42501 — « % » —, et la politique d''écriture la sort de l''exposition)', v_message;
END $$;

ROLLBACK;
