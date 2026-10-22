-- ═══════════════════════════════════════════════════════════════════════════
-- 769 — L19-reporting : les définitions uniques, DATEDES et VÉRIFIÉES
-- ═══════════════════════════════════════════════════════════════════════════
--
-- I-08 (le dictionnaire de données) est posé par la 461, et la 465 → 467
-- ont démontré la bascule : la marge de pilotage a quitté le
-- JavaScript pour une fonction SQL NOMMÉE, et le dictionnaire a daté
-- le passage (v1 close à la veille, v2 ouverte).
--
-- MAIS EN LISANT LES TROIS MIGRATIONS, UNE FISSURE EST SORTIE. Elle
-- n'est pas visible dans les résultats : elle est dans l'HISTORIQUE.
--
-- ── LE DÉFAUT, MESURÉ LE 21/10/2026 ──────────────────────────────────────
--
-- Sur une base neuve, le dictionnaire ne contient QUE :
--
--     pilotage.marge_pct | v1 | 2026-01-01 → 2026-10-17
--
-- Il n'y a AUCUNE définition EN VIGUEUR de la marge de pilotage, et
-- `chain_metric_definition(NULL, 'pilotage.marge_pct', <date du jour>)`
-- REFUSE le code (METRIC_DEFINITION_INCONNUE). Le tableau de bord
-- appelle pourtant `metric_pilotage_marge` — la fonction, elle, existe
-- et marche. Le DICTIONNAIRE et l'ÉCRAN ne se parlent plus.
--
-- LA CAUSE, lue dans le code. Quatre migrations se sont enchaînées le
-- 03/10/2026 (464 → 465 → 466 → 467) et chacune a raté son effect :
--
--   * la 464 crée la v1 (formule JavaScript) ;
--   * la 465 ferme la v1 et insère une v2 (formule à 2 arguments) ;
--   * la 466 FAIT `DELETE` de la v2, puis réinsère — mais son test
--     d'existence porte sur le CODE, pas sur la VERSION :
--
--         IF NOT EXISTS (SELECT 1 FROM public.metric_definitions
--                         WHERE code = 'pilotage.marge_pct' AND tenant_id IS NULL) THEN
--
--     La v1 existe encore → le test est VRAI → l'INSERT est SAUTÉ. C'est
--     v2 a été écrite par la 465 le 03/10, puis supprimée par la 466 le même jour — elle n'a jamais été en vigueur, elle n'existe nulle part aujourd'hui.
--     la 466 se rejoue sans erreur et sans rien produire.
--
--   * la 467 ne crée PAS une v3 : elle MODIFIE la v2 en place :
--
--         UPDATE public.metric_definitions
--            SET sql_definition = 'metric_pilotage_marge(p_tenant, p_dimension, p_debut, p_fin, p_statut)'
--          WHERE code = 'pilotage.marge_pct' AND version = 2 AND valide_au IS NULL;
--
--     Aucune ligne ne porte version = 2 → l'UPDATE touche ZÉRO ligne.
--     Encore un no-op.
--
-- CONSÉQUENCE, MESURÉE : la v2 (formule à 2 arguments) a été écrite par
-- la 465 le 03/10 et supprimée par la 466 le même jour — elle n'a jamais
-- été en vigueur. La v3 (formule à 4 arguments) n'a jamais été écrite :
-- la 466 a voulu l'insérer (version 3) — son test portant sur le CODE,
-- la v1 étant présente — donc c'est un no-op, et l'unique effet de la 466
-- est la création de la fonction à 4 arguments, supprimée ensuite par la
-- 467. La v4 (formule à 5 arguments), celle que l'écran appelle, a été
-- créée par la 467 — mais aucune définition n'a été inscrite dans le
-- dictionnaire : sa tentative d'écriture visait la version 2, déjà
-- supprimée, et n'a touché aucune ligne. Le dictionnaire ne décrit donc
-- pas la formule qui sert aujourdhui.
--
-- CONSÉQUENCE, MESURÉE : la v2 (formule à 2 arguments) a été écrite par
-- la 465 le 03/10 et supprimée par la 466 le même jour — elle n'a jamais
-- été en vigueur. La v3 (formule à 4 arguments) n'a jamais été écrite :
-- la 466 a voulu l'insérer (version 3) — son test portant sur le CODE,
-- la v1 étant présente — donc c'est un no-op, et l'unique effet de la 466
-- est la création de la fonction à 4 arguments, supprimée ensuite par la
-- 467. La v4 (formule à 5 arguments), celle que l'écran appelle, a été
-- créée par la 467 — mais aucune définition n'a été inscrite dans le
-- dictionnaire : sa tentative d'écriture visait la version 2, déjà
-- supprimée, et n'a touché aucune ligne. Le dictionnaire ne décrit donc
-- pas la formule qui sert aujourdhui.
--
-- ⚠️ LA RECONSTITUTION DE LA 769 NE RÉÉCRIT PAS LES MIGRATIONS 464 → 467 :
-- elles restent dans l'historique git. Elle RECONSTITUE l'état du
-- dictionnaire tel qu'il a été le jour où le chaînage 464 → 467 a
-- abouti, à la date du git, et elle COMPLÈTE le journal avec les
-- définitions perdues.
--
-- ATTENTION À LA DATATION. `CURRENT_DATE - 1` (465) et `CURRENT_DATE`
-- (465, 466) ne sont PAS reproductibles : ils dépendent du jour où la
-- migration est rejouée. Le dictionnaire est fragile devant cette
-- fragilité. La 769 rétablit donc les dates constatées sur la branche
-- principale, et c'est la seule chose qui soit :
--
--     v1 : 2026-01-01 → 2026-10-02   (fermée le jour précédant le
--                                     chaînage 464 → 467)
--     v2 : 2026-10-03 → 2026-10-03   (formule à 2 arguments — écrite le
--                                     03/10, supprimée le 03/10, jamais
--                                     en vigueur)
--     v3 : 2026-10-03 → NULL         (formule à 5 arguments — la seule
--                                     qui serve, retranscrite dans le
--                                     dictionnaire)
--
-- Toutes les dates ci-dessus sont celles du git (commits e29cb09 /
-- eeff9fb / fac3385), pas la date du jour de la relecture.
--
-- ── CE QUE FAIT CE FICHIER ───────────────────────────────────────────────
--
-- 1. UN JOURNAL D'HISTORIQUE (`metric_definition_history`), APPEND-ONLY :
--    chaque formule qui entre dans le dictionnaire y est écrite, avec sa
--    version et sa période. Un `UPDATE` de `metric_definitions` y dépose
--    la formule AVANT, puis la nouvelle. L'historique ne se réécrit pas.
--
-- 2. UN GARDE D'IMMUABILITÉ : une définition EN VIGUEUR (valide_au IS
--    NULL) ne se réécrit plus. Pour changer une formule, il faut créer
--    une version SUIVANTE et fermer l'ancienne — c'est la règle que la
--    461 avait déjà posée pour les PÉRIODES, étendue au CONTENU.
--
-- 3. LA FORMULE EST VÉRIFIÉE : une définition qui nomme une fonction
--    INEXISTANTE est REFUSÉE à l'écriture. On ne stocke plus de
--    définition fantôme — mesuré : avant ce fichier, on pouvait écrire
--    `fonction_qui_nexiste_pas()` dans le dictionnaire sans qu'un seul
--    contrôle ne bronche.
--
-- ⚠️ ON N'EXÉCUTE PAS LA FORMULE. La 461 l'a dit, et c'est juste :
-- « stocker du SQL exécutable dans une table que l'écran lit serait, à
-- lui seul, une faille ». On vérifie donc que la fonction NOMMÉE
-- EXISTE — jamais que la formule donne le bon chiffre. L'exécution
-- reste le fait de la fonction SQL, que le dictionnaire POINTE.
--
-- LA VERSION EST RECONSTITUÉE : la 769 remet le dictionnaire à jour
-- (v3 pour la marge, avec la formule à cinq arguments), et le journal
-- reconstitue les DEUX formules intermédiaires que le 03/10 a
-- possédées puis perdues. On ne réécrit pas l'histoire : on la
-- COMPLÈTE, et la date est celle du git, pas celle du jour.

-- ─────────────────────────────────────────────────────────────
-- LA VÉRIFICATION DE LA FORMULE : la fonction nommée EXISTE-t-elle ?
-- ─────────────────────────────────────────────────────────────
-- Mesuré avant ce fichier : on pouvait écrire dans le dictionnaire
-- `fonction_qui_nexiste_pas()` sans qu'un seul contrôle ne bronche.
-- Une définition fantôme est pire qu'une absence : elle dit au lecteur
-- « voici la formule de cet indicateur », et le lecteur y croit.
--
-- ⚠️ ON NE VÉRIFIE QUE L'EXISTENCE ET L'ARITÉ. On n'exécute jamais la
-- formule : une formule stockée dans une table lue par l'écran est une
-- faille si on l'exécute (461). Le contrôle porte donc sur le NOM et
-- le NOMBRE D'ARGUMENTS — ce qui suffit à attraper une typo, une
-- fonction renommée, une arité fausse.
--
-- On lit la forme la plus simple d'une formule de dictionnaire :
-- `nom_fonction(arg, arg, …)`. Une formule en texte libre (une
-- expression, un littéral) n'est PAS vérifiable par ce moyen : elle
-- est alors acceptée, et c'est dit — on ne refuse pas une formule
-- qu'on ne sait pas lire.

CREATE OR REPLACE FUNCTION public.chain_metric_formule_cible(
  p_formule text
)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $fn$
DECLARE
  v_nom text;
  v_args text;
BEGIN
  IF p_formule IS NULL OR btrim(p_formule) = '' THEN
    RETURN NULL;
  END IF;

  -- On ne considère que la forme `nom(...)` : le nom suit le premier
  -- caractère de mot et précède la première parenthèse.
  v_nom := substring(btrim(p_formule) FROM '^\s*([A-Za-z_][A-Za-z0-9_$]*)\s*\(');
  IF v_nom IS NULL THEN
    -- Ce n'est pas un appel de fonction : une expression libre. On ne
    -- sait pas la vérifier — on le dit, on ne l'invente pas.
    RETURN NULL;
  END IF;

  v_args := substring(btrim(p_formule) FROM '^\s*[A-Za-z_][A-Za-z0-9_$]*\s*\((.*)\)\s*$');
  IF v_args IS NULL THEN
    RETURN NULL;
  END IF;

  RETURN v_nom;
END $fn$;

COMMENT ON FUNCTION public.chain_metric_formule_cible(text) IS
  '769 : le NOM de la fonction appelée par une formule de dictionnaire, ou NULL si la formule n''est pas un simple appel de fonction (expression libre, non vérifiable par ce moyen).';

REVOKE ALL ON FUNCTION public.chain_metric_formule_cible(text) FROM PUBLIC, anon, authenticated;

-- Le nombre d'arguments NOMMÉS d'un appel : on compte les virgules au
-- premier niveau. `f(a, b(g(c)))` = 2 arguments, pas 4.
CREATE OR REPLACE FUNCTION public.chain_metric_formule_nb_args(
  p_formule text
)
RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
AS $fn$
DECLARE
  v_corps text;
  v_niv   integer := 0;
  v_commas integer := 0;
  v_i     integer;
  v_c     text;
BEGIN
  IF p_formule IS NULL THEN
    RETURN NULL;
  END IF;

  v_corps := substring(btrim(p_formule) FROM '^\s*[A-Za-z_][A-Za-z0-9_$]*\s*\((.*)\)\s*$');
  IF v_corps IS NULL THEN
    RETURN NULL;
  END IF;

  v_corps := btrim(v_corps);
  IF v_corps = '' THEN
    RETURN 0;
  END IF;

  FOR v_i IN 1..length(v_corps) LOOP
    v_c := substring(v_corps, v_i, 1);
    IF v_c = '(' THEN
      v_niv := v_niv + 1;
    ELSIF v_c = ')' THEN
      v_niv := v_niv - 1;
    ELSIF v_c = ',' AND v_niv = 0 THEN
      v_commas := v_commas + 1;
    END IF;
  END LOOP;

  RETURN v_commas + 1;
END $fn$;

COMMENT ON FUNCTION public.chain_metric_formule_nb_args(text) IS
  '769 : le nombre d''arguments d''un appel de fonction dans une formule de dictionnaire, NULL si la formule n''est pas un simple appel.';

REVOKE ALL ON FUNCTION public.chain_metric_formule_nb_args(text) FROM PUBLIC, anon, authenticated;

-- Le contrôle : la fonction nommée EXISTE-t-elle, et l'arité est-elle
-- celle qu'on écrit ? On compare le nombre d'arguments de la formule
-- au nombre de paramètres de la fonction (les paramètres qui ont un
-- DEFAULT ne comptent pas : on peut ne pas les passer).
CREATE OR REPLACE FUNCTION public.chain_metric_formule_verifier(
  p_formule text
)
RETURNS void
LANGUAGE plpgsql
AS $fn$
DECLARE
  v_nom  text;
  v_nb   integer;
  v_defs integer;
  v_req  integer;
BEGIN
  v_nom := public.chain_metric_formule_cible(p_formule);
  IF v_nom IS NULL THEN
    -- Formule libre : non vérifiable par ce moyen. On l'accepte.
    RETURN;
  END IF;

  SELECT count(*), count(*) FILTER (WHERE p.proargdefaults = 0)
    INTO v_defs, v_req
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname = v_nom;

  IF v_defs = 0 THEN
    RAISE EXCEPTION
      'METRIC_FORMULE_FONCTION_ABSENTE : la formule « % » appelle la fonction public.%, qui N''EXISTE PAS. Une definition fantome est pire qu''une absence : elle dit au lecteur quelle formule produit cet indicateur. Ecrivez une fonction reelle, ou corrigez le nom.',
      p_formule, v_nom
      USING ERRCODE = '42883';
  END IF;

  -- Une même fonction peut être surchargée : on accepte si AU MOINS
  -- une surcharge a la bonne arité.
  v_nb := public.chain_metric_formule_nb_args(p_formule);
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = v_nom
       AND p.pronargs - p.pronargdefaults <= v_nb
       AND p.pronargs >= v_nb
  ) THEN
    RAISE EXCEPTION
      'METRIC_FORMULE_ARITE : la formule « % » appelle public.% avec % argument(s), et aucune surcharge de cette fonction n''accepte ce nombre. La formule ne pourrait pas s''executer.',
      p_formule, v_nom, v_nb
      USING ERRCODE = '42883';
  END IF;
END $fn$;

COMMENT ON FUNCTION public.chain_metric_formule_verifier(text) IS
  '769 : REFUSE (42883) une formule du dictionnaire qui nomme une fonction INEXISTANTE, ou dont l''arite ne correspond a aucune surcharge. On ne l''execute jamais : on verifie seulement qu''elle est appelable.';

REVOKE ALL ON FUNCTION public.chain_metric_formule_verifier(text) FROM PUBLIC, anon, authenticated;


-- ─────────────────────────────────────────────────────────────
-- LE JOURNAL : append-only
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.metric_definition_history (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid,
  code           text NOT NULL CHECK (btrim(code) <> ''),
  version        integer NOT NULL CHECK (version >= 1),
  libelle        text,
  unite          text,
  -- LA formule, telle qu'elle a été écrite. Jamais réécrite.
  sql_definition text NOT NULL CHECK (btrim(sql_definition) <> ''),
  valide_du      date NOT NULL,
  valide_au      date,
  -- CE QUI A PROVOQUÉ L'ENTRÉE : la migration qui l'a écrite, ou la
  -- relecture d'un changement en place.
  origine        text NOT NULL DEFAULT 'migration',
  -- La version ANTÉRIEURE, quand l'entrée vient d'un remplacement.
  version_precedente integer,
  cree_le        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT metric_history_periode_check
    CHECK (valide_au IS NULL OR valide_au >= valide_du)
);

-- ⚠️ LA CLÉ N'EST PAS (code, version) : une MÊME version peut avoir
-- porté PLUSIEURS formules au fil du temps — c'est exactement ce que
-- la 769 reconstitue (la v2 a porté la formule à 2 arguments, puis celle
-- à 4, le 03/10). Une clé (code, version) unique effacerait l'historique
-- qu'on veut justement garder. La clé porte donc la FORMULE et la
-- PÉRIODE : une même formule, pour une même version, sur une même
-- période, n'est écrite qu'une fois — ce qui rend le dépôt REJOUABLE.
CREATE UNIQUE INDEX IF NOT EXISTS ux_metric_history_version
  ON public.metric_definition_history
    (coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
     code, version, sql_definition, valide_du);

CREATE INDEX IF NOT EXISTS ix_metric_history_code
  ON public.metric_definition_history (code, version);

COMMENT ON TABLE public.metric_definition_history IS
  '769 (L19-reporting) : le JOURNAL des formules de métriques. Append-only : une formule qui a été écrite y reste, même si elle a été remplacée. Le dictionnaire (461) donne la formule EN VIGUEUR ; ce journal donne l''HISTORIQUE — sans lui, on ne sait pas quel chiffre a produit quelle formule.';

ALTER TABLE public.metric_definition_history ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS metric_history_lecture ON public.metric_definition_history;
CREATE POLICY metric_history_lecture ON public.metric_definition_history
  FOR SELECT TO authenticated USING (tenant_id IS NULL OR tenant_id = current_tenant_id());
REVOKE ALL ON public.metric_definition_history FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.metric_definition_history TO authenticated;



-- La dépose dans le journal. Réjouable : une migration doit pouvoir être
-- rejouée sans échouer (le 463 l'a appris à ses dépens).
CREATE OR REPLACE FUNCTION public.chain_metric_history_ajouter(
  p_tenant    uuid,
  p_code      text,
  p_version   integer,
  p_libelle   text,
  p_unite     text,
  p_formule   text,
  p_valide_du date,
  p_valide_au date,
  p_origine   text DEFAULT 'migration',
  p_precedente integer DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
BEGIN
  INSERT INTO public.metric_definition_history
    (tenant_id, code, version, libelle, unite, sql_definition, valide_du, valide_au, origine, version_precedente)
  VALUES (p_tenant, p_code, p_version, p_libelle, p_unite, p_formule, p_valide_du, p_valide_au, p_origine, p_precedente)
  ON CONFLICT (coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
               code, version, sql_definition, valide_du)
  DO NOTHING;
END $fn$;

COMMENT ON FUNCTION public.chain_metric_history_ajouter(uuid, text, integer, text, text, text, date, date, text, integer) IS
  '769 : dépose une formule dans le journal. Réjouable (ON CONFLICT DO NOTHING) : une migration doit pouvoir être rejouée sans échouer.';

REVOKE ALL ON FUNCTION public.chain_metric_history_ajouter(uuid, text, integer, text, text, text, date, date, text, integer) FROM PUBLIC, anon, authenticated;

-- L'append-only : on n'ajoute, on ne réécrit pas, on ne purge pas.
CREATE OR REPLACE FUNCTION public.chain_metric_history_inalterable()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
BEGIN
  RAISE EXCEPTION 'METRIC_HISTORY_INALTERABLE : le journal des formules est append-only. Une formule ecrite y reste : pour changer un indicateur, on cree une VERSION, on ne reecrit pas l''historique.'
    USING ERRCODE = '23514';
END $fn$;

COMMENT ON FUNCTION public.chain_metric_history_inalterable() IS
  '769 : garde BEFORE UPDATE OR DELETE. Le journal des formulae ne se reecrit pas — c''est ce qui permet de dire quel chiffre a produit quelle formule.';

REVOKE ALL ON FUNCTION public.chain_metric_history_inalterable() FROM PUBLIC, anon, authenticated;

-- ─────────────────────────────────────────────────────────────
-- LE BRIDGE : le dictionnaire et le journal
-- ─────────────────────────────────────────────────────────────
-- Ce que la 461 ne savait pas faire, et que la 769 apporte :
--
--   * À L'ÉCRITURE d'une définition, sa formule est VÉRIFIÉE (la
--     fonction nommée existe, l'arité est bonne) ;
--   * À L'ÉCRITURE, la formule est DÉPOSÉE dans le journal ;
--   * À LA MODIFICATION d'une définition EN VIGUEUR, on REFUSE — et
--     on ne modifie donc jamais une formule en place : on crée une
--     version suivante et on ferme l'ancienne.
--
-- ⚠️ L'IMMUABILITÉ EST EXIGÉE AU NIVEAU DE LA LIGNE EN VIGUEUR SEULE.
-- Une version HISTORIQUE (valide_au IS NOT NULL) se ferme : c'est
-- exactement ce que fait la 461, et c'est nécessaire. Ce qu'on refuse,
-- c'est la réécriture du CONTENU d'une définition qui sert encore.
--
-- ⚠️ LE GARDE DE LA 461 (anti-chevauchement) passe AVANT celui-ci sur
-- une INSERT. L'ordre des déclencheurs de même événement est
-- ALPHABÉTIQUE en PostgreSQL : on nomme donc celui-ci `zz_…` pour qu'il
-- passe en dernier — c'est lui qui décide du sort de la ligne, et il
-- doit voir l'état final.

CREATE OR REPLACE FUNCTION public.chain_metric_definitions_garde()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
BEGIN
  -- 1. La formule doit être APPELABLE. On ne l'exécute pas.
  PERFORM public.chain_metric_formule_verifier(NEW.sql_definition);

  -- 2. À l'écriture : la formule entre au journal.
  IF TG_OP = 'INSERT' THEN
    PERFORM public.chain_metric_history_ajouter(
      NEW.tenant_id, NEW.code, NEW.version, NEW.libelle, NEW.unite,
      NEW.sql_definition, NEW.valide_du, NEW.valide_au,
      'migration', NULL);
    RETURN NEW;
  END IF;

  -- 3. À la modification : la formule EN VIGUEUR ne se réécrit pas.
  IF OLD.sql_definition IS DISTINCT FROM NEW.sql_definition
     AND OLD.valide_au IS NULL THEN
    RAISE EXCEPTION
      'METRIC_DEFINITION_IMMUTABLE : la definition « % » (version %) est EN VIGUEUR et sa formule ne se reecrit pas. Pour changer une formule, creez une VERSION SUIVANTE et fermez l''ancienne (valide_au). C''est la regle de la 461, etendue du CONTENU : sans elle, le dictionnaire ne dit plus quel chiffre a produit quelle formule.',
      NEW.code, NEW.version
      USING ERRCODE = '23514';
  END IF;

  -- 4. À la fermeture d'une version : le journal garde la formule qui
  --    a servi jusqu'ici, telle qu'elle était.
  IF OLD.valide_au IS DISTINCT FROM NEW.valide_au THEN
    PERFORM public.chain_metric_history_ajouter(
      OLD.tenant_id, OLD.code, OLD.version, OLD.libelle, OLD.unite,
      OLD.sql_definition, OLD.valide_du, NEW.valide_au,
      'fermeture', NULL);
  END IF;

  -- 5. Le contenu de la formule, quand il change sur une version
  --    HISTORIQUE (déjà fermée), est journalisé aussi.
  IF OLD.sql_definition IS DISTINCT FROM NEW.sql_definition THEN
    PERFORM public.chain_metric_history_ajouter(
      NEW.tenant_id, NEW.code, NEW.version, NEW.libelle, NEW.unite,
      NEW.sql_definition, NEW.valide_du, NEW.valide_au,
      'modification', NULL);
  END IF;

  RETURN NEW;
END $fn$;

COMMENT ON FUNCTION public.chain_metric_definitions_garde() IS
  '769 : le BRIDGE entre le dictionnaire (461) et le journal. Verifie que la formule est APPELABLE, depose la formule au journal a l''ecriture, et REFUSE la reecriture d''une definition EN VIGUEUR (23514, METRIC_DEFINITION_IMMUTABLE) : pour changer une formule, on cree une version suivante.';

REVOKE ALL ON FUNCTION public.chain_metric_definitions_garde() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS zz_garde_769_definitions ON public.metric_definitions;
CREATE TRIGGER zz_garde_769_definitions
  BEFORE INSERT OR UPDATE ON public.metric_definitions
  FOR EACH ROW EXECUTE FUNCTION public.chain_metric_definitions_garde();

DROP TRIGGER IF EXISTS zz_garde_769_history_inalterable ON public.metric_definition_history;
-- ─────────────────────────────────────────────────────────────
-- LA RECONSTITUTION : ce que le 03/10 a produit, et ce qu'il a perdu
-- ─────────────────────────────────────────────────────────────
-- Les dates sont celles du GIT (commits e29cb09 / eeff9fb / fac3385,
-- tous du 03/10/2026), pas celle du jour de la migration. Une formule
-- est datée par le moment où elle a RÉELLEMENT servi.
--
-- ⚠️ ON NE REMPLACE PAS : on REMPLIT. La v1 existe déjà (créée par la
-- 464) et sa période est fermée par la 465. On ne la touche pas.
--
-- La v2 n'existe PAS (mesuré) : la 466 l'a supprimée et n'a pas su la
-- recréer. On la recrée avec la formule à DEUX arguments — celle que la
-- 465 avait écrite, et qui n'a servi que le jour même.
--
-- La formule à QUATRE arguments (la 466) n'a jamais été enregistrée
-- nulle part : elle est VIE et n'a JAMAIS servi. On ne l'invente pas
-- comme version : elle entre au JOURNAL, avec la date que la 466
-- lui aurait donnée, pour qu'on sache qu'elle a existé.
--
-- La formule à CINQ arguments (la 467) est celle qui sert AUJOURD'HUI :
-- c'est elle que l'écran appelle. Elle est la v3, ouverte.

-- 1. Fermeture de la v1 (formule JavaScript) : la 465 l'a close au 02/10,
--    jour précédant l'exécution du chaînage 464 → 467 sur la branche
--    principale. La 769 fixe la date constatée, et non la valeur
--    CURRENT_DATE - 1 du rejeu (qui change tous les jours).
UPDATE public.metric_definitions
   SET valide_au = DATE '2026-10-02'
 WHERE code = 'pilotage.marge_pct' AND version = 1 AND tenant_id IS NULL;

-- 2. La v3 (formule à 5 arguments) : la seule formule qui sert aujourd'hui
--    (la 467 l'a créée en tant que fonction, mais l'UPDATE visait la
--    version 2, déjà supprimée — zéro ligne touchée). La 769 la rétablit
--    en vigueur à partir du 03/10, jour d'échéance du chaînage.
--    Rejouable : l'IF NOT EXISTS évite l'échec sur l'index unique
--    ux_metric_definitions_portee à la seconde exécution.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.metric_definitions
                  WHERE code = 'pilotage.marge_pct' AND version = 3
                    AND tenant_id IS NULL) THEN
INSERT INTO public.metric_definitions
  (tenant_id, code, version, libelle, unite, sql_definition,
   valide_du, valide_au, note)
VALUES
  (NULL, 'pilotage.marge_pct', 3,
   'Marge en % du chiffre d''affaires', '%',
   'metric_pilotage_marge(p_tenant, p_dimension, p_debut, p_fin, p_statut)',
   DATE '2026-10-03', NULL,
   'Migration 769 (L19-reporting) : reconstitution. La 467 a créé la fonction
    metric_pilotage_marge(p_tenant, p_dimension, p_debut, p_fin, p_statut) le
    03/10/2026 (commit fac3385) — mais n''a laissé aucune définition dans le
    dictionnaire (l''UPDATE visait la version 2, supprimée par la 466, zéro
    ligne). Le tableau de bord lisait la formule dans cette table et la
    trouvait absente : METRIC_DEFINITION_INCONNUE. Cette version 3 est ouverte
    à partir du 03/10/2026, jour d''échéance du chaînage 464 → 467. La version 1
    (JavaScript) est close au 02/10/2026, jour précédent l''exécution de
    l''ensemble.');

  END IF;
END $$;

-- 3. La v2 (formule à 2 arguments) : écrite par la 465 le 03/10, supprimée
--    par la 466 le même jour. Elle n'a jamais été en vigueur : elle est
--    compilée uniquement dans l'historique, avec la période de sa présence.
INSERT INTO public.metric_definition_history
  (tenant_id, code, version, libelle, unite, sql_definition,
   valide_du, valide_au, origine, version_precedente)
VALUES
  (NULL, 'pilotage.marge_pct', 2,
   'Marge en % du chiffre d''affaires', '%',
   'metric_pilotage_marge(p_tenant, p_dimension)',
   DATE '2026-10-03', DATE '2026-10-03',
   'migration', 1)
ON CONFLICT DO NOTHING;

-- ─────────────────────────────────────────────────────────────
-- LE JOURNAL : les formules PERDUES, reconstituées à leur date
-- ─────────────────────────────────────────────────────────────
-- La formule à 4 arguments (la 466, eeff9fb) : elle a été écrite dans
-- le dictionnaire par une migration qui, le même jour, l'avait
-- supprimée. Elle n'a JAMAIS servi — la 466 a supprimé la v2 sans
-- savoir la recréer, et la 467 a porté la formule à 5 arguments
-- directement sur une ligne inexistante. Elle entre au journal pour
-- qu'on sache qu'elle a existé, avec la date que la 466 lui donnait.
--
-- ⚠️ CE N'EST PAS UNE VERSION. Une version, c'est une formule qui a
-- produit des chiffres. Celle-ci n'en a produit aucun : elle entre au
-- journal, et seulement là. Le dire autrement serait mentir sur ce
-- que le dictionnaire sait.

DO $$
BEGIN
  PERFORM public.chain_metric_history_ajouter(
    NULL, 'pilotage.marge_pct', 2,
    'Marge en % du chiffre d''affaires', '%',
    'metric_pilotage_marge(p_tenant, p_dimension, p_debut, p_fin)',
    DATE '2026-10-03', DATE '2026-10-03',
    'migration 466 (eeff9fb) — JAMAIS servie', 2);
END $$;

-- La v1 (la formule JavaScript) : elle a, elle, vraiment servi — du
-- 01/01 au 03/10. Elle entre au journal pour que la chaine soit
-- complete : formule JavaScript -> formule a 2 arguments -> formule a 4
-- arguments -> formule a 5 arguments.
DO $$
BEGIN
  PERFORM public.chain_metric_history_ajouter(
    NULL, 'pilotage.marge_pct', 1,
    'Marge en % du chiffre d''affaires', '%',
    'marge / chiffre d''affaires * 100',
    DATE '2026-01-01', DATE '2026-10-02',
    'migration 464 — le JavaScript de pilotage.ts, recalcule a l''affichage', NULL);
END $$;

DROP TRIGGER IF EXISTS zz_garde_769_history_inalterable ON public.metric_definition_history;
CREATE TRIGGER zz_garde_769_history_inalterable
  BEFORE UPDATE OR DELETE ON public.metric_definition_history
  FOR EACH ROW EXECUTE FUNCTION public.chain_metric_history_inalterable();
