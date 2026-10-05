-- 701 — drop_time_entries_duplique
-- Numéro pris le 2026-10-05T20:15:51.055Z par migration-numero.mjs (ligne « plan6 F (plateforme) », branche plan6/f-plateforme).
--
-- ============================================================
-- F.8 (partie F du plan du 05/10) — « tables coquilles : brancher ou supprimer »
--
-- LE RECOMPTAGE, MESURÉ LE 05/10 (base complète, `app/sql` + schéma) :
-- le suivi annonce « 37 tables coquilles », dont « les 25 autres » pour F. Ce
-- chiffre est PÉRIMÉ, pour deux raisons qui tiennent chacune en une ligne :
--
--   1. `164_drop_unused_vague3_tables.sql` (18/09) a DÉJÀ supprimé 22 des tables
--      que le suivi compte encore. `suivi-chantiers.mjs::coquilles()` lit les
--      `CREATE TABLE` des fichiers de migration et ne REGARDE PAS les `DROP`
--      ultérieurs : une table retirée reste comptée comme coquille.
--   2. `platform_admins` n'est PAS une coquille : elle est LUE par une fonction
--      SQL (`is_platform_admin()`, migration 201, `WHERE auth_id = auth.uid()`).
--      Le même calcul ne regarde que les références du FRONT (`src/` + Edge) :
--      une table lue par du SQL pur passe donc pour une coquille.
--
-- Vérifié en base le 05/10 : sur les 24 tables listées pour F, CINQ existent
-- encore —
--   * `collective_agreements`, `collective_classifications` → à BRANCHER par
--     F.7 (PAY-08, conventions collectives) : conservées ici ;
--   * `platform_admins` → brancher (lue par `is_platform_admin()`, lot K / C) :
--     hors périmètre F, laissée intacte ;
--   * `time_entries` → SUPPRIMER : c'est l'objet de cette migration.
--
-- POURQUOI `time_entries` ET PAS UNE AUTRE. La 164 l'avait explicitement
-- CONSERVÉE : « cible des 16 fonctions de `queries/projectManagementSprint1.ts`,
-- encore sans écran. Son sort dépend de la décision « brancher ou supprimer »
-- en cours sur ce sprint ». C'est cette décision. Elle est rendue sur des faits
-- mesurés le 05/10 :
--   * la 127 la crée (bloc « RH-01 : gestion des temps et activités ») et
--     PERSONNE ne la lit : aucune occurrence en dehors du type généré
--     (`database-generated.ts`) dans tout `src/` ; aucune fonction, vue,
--     politique ni déclencheur en SQL ne la nomme ; aucune suite ne l'écrit ;
--   * les 16 fonctions de sprint1 ne la nomment plus (elles visent
--     `project_time_entries`) — l'argument de la 164 n'est plus vrai ;
--   * surtout, elle DOUBLE une table VIVANTE : `timesheets` (baseline, lue par
--     la paie W9, les écrans RH, `useProjects`…). Deux modèles de temps, un
--     seul branché : `time_entries` est le leurre que F.8 doit retirer.
--
-- GARDE-FOU (le même que la 164, pour ne rien détruire) : la table n'est
-- supprimée que si elle est VIDE et qu'aucune table ne la référence. Sur une
-- base qui porte des données, elle est CONSERVÉE et la migration le dit. Elle
-- est donc rejouable et sans effet sur une base déjà nettoyée.
--
-- Pas d'autre table touchée. `npm run db:types` accompagne cette migration (le
-- type `time_entries` disparaît) — même commit.
-- ============================================================

DO $$
DECLARE
  t text := 'time_entries';
  n bigint;
  dependantes text;
BEGIN
  IF to_regclass('public.' || t) IS NULL THEN
    RAISE NOTICE 'F.8 : % déjà absente — rien à faire (migration rejouable)', t;
    RETURN;
  END IF;

  EXECUTE format('SELECT count(*) FROM public.%I', t) INTO n;
  IF n > 0 THEN
    RAISE NOTICE 'F.8 : % CONSERVÉE — % ligne(s) présente(s) : la décision de suppression ne détruit pas de données.', t, n;
    RETURN;
  END IF;

  SELECT string_agg(DISTINCT k.conrelid::regclass::text, ', ')
    INTO dependantes
    FROM pg_constraint k
   WHERE k.contype = 'f'
     AND k.confrelid = ('public.' || t)::regclass
     AND k.conrelid <> ('public.' || t)::regclass;

  IF dependantes IS NOT NULL THEN
    RAISE NOTICE 'F.8 : % CONSERVÉE — référencée par %', t, dependantes;
    RETURN;
  END IF;

  EXECUTE format('DROP TABLE public.%I', t);
  RAISE NOTICE 'F.8 : % supprimée (vide, non référencée) — le modèle de temps vivant reste `timesheets`.', t;
END $$;

