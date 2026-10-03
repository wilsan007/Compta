-- 422 — l20_retour_arriere
-- Numéro pris le 2026-10-03T17:50:11.256Z par migration-numero.mjs (ligne « L16-L24 », branche partie-5-integrite-chainages).
-- ═══════════════════════════════════════════════════════════════════════
-- 422 — L20, TRANCHE 1 : LE RETOUR EN ARRIÈRE DES RÉGÉNÉRATIONS
-- ═══════════════════════════════════════════════════════════════════════
--
-- LE LOT. M-04 (plan, phase F) : « tout effet paramétrique se régénère ;
-- on ne corrige jamais une ligne à la main », et la régénération se fait
-- « avec HISTORIQUE et POSSIBILITÉ DE REVENIR À LA VERSION PRÉCÉDENTE ».
-- Cette 422 livre la seconde moitié de la phrase. La première — la
-- régénération en cascade elle-même — est la suite du lot (tranche 2).
--
-- CE QUI EXISTAIT, MESURÉ SUR LA BASE DU JOUR.
--
--   * `chain_regeneration_log` : posée par la 252 (le socle a anticipé
--     L20), 9 colonnes dont `avant` et `apres`. Deux lignes au total —
--     celles de sa propre suite T13.
--   * `chain_regenerate(tenant, effet, amont_type, amont_id, cause,
--     apres)` : photographie les payloads des liens, écrit la ligne,
--     émet `chain.regenerated`, rend l'id. **Il ne régénère rien.**
--   * **ZÉRO** fonction de retour arrière : ni rollback, ni revert, ni
--     annulation. Le `avant` que la 252 écrit depuis trois semaines
--     n'était donc une donnée que PERSONNE ne pouvait atteindre.
--
-- LE DÉFAUT : on peut régénérer et l'historique s'écrit, mais on ne peut
-- pas revenir. Or c'est la moitié qui PROTÈGE : sans retour possible, une
-- régénération est un aller simple — une décision irréversible habillée
-- en édition. Et rien ne dit à l'utilisateur qu'il vient de se fermer
-- une porte.
--
-- ⚠️ LE CONFLIT EST LE CŒUR DU LOT.
-- `chain_regenerate` reçoit `apres` DE L'APPELLANT : la suite 252 T13
-- passe `{"prix": 12}` pendant que le lien vivant porte encore
-- `{"prix": 10}`. `apres` est donc une DÉCLARATION, pas un constat — on
-- ne peut pas s'en servir pour détecter que l'état a bougé depuis, et on
-- ne le changera pas ici : ce contrat appartient au socle, dont la suite
-- le fige, et la 422 n'est pas son lot.
-- Le rollback exige alors que l'appelant DÉCLARE l'état vivant attendu
-- (`p_attendu`) et REFUSE si le réel ne colle pas. C'est de la concurrence
-- optimiste, et c'est la seule honnête quand le journal ne sait pas dire
-- la vérité. Refuser ici est le comportement CORRECT : l'alternative —
-- écraser sans vérifier — détruirait un travail plus récent sous couvert
--
-- ⚠️ UN CHOIX DE FUITE, ASSUMÉ ET ÉCRIT.
-- L'id du journal est un `bigserial` GLOBAL, pas par société. Deux
-- messages distincts (« inconnu » / « appartient à une autre société »)
-- révèlent donc l'existence d'une ligne dans une autre société. C'est
-- mesuré et assumé : la numération est déjà globale et séquentielle, donc
-- l'existence se déduit déjà des trous dans la séquence. Le masquer ne
-- donnerait aucune protection réelle, et coûterait le diagnostic exact
-- que l'utilisateur a besoin pour comprendre son refus. Si un jour le
-- Cloisonnement exige ce silence, c'est une séquence PAR SOCIÉTÉ qu'il
-- faudra — pas un message.
--
-- LE ROLLBACK NE « RÉPARE » RIEN (T07). Un lien `rompu` garde son état :
-- revenir en arrière n'est pas réparer une chaîne rompue, c'est en remettre
-- une à son état antérieur. Confondre les deux ajouterait une cinquième
-- transition au cycle du lien (312) sans raison.
-- ═══════════════════════════════════════════════════════════════════════
-- d'un retour arrière, et personne ne verrait jamais l'alerte.

CREATE OR REPLACE FUNCTION public.chain_regeneration_rollback(
  p_tenant          uuid,
  p_regeneration_id bigint,
  p_attendu         jsonb
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_reg    chain_regeneration_log%ROWTYPE;
  v_vivant jsonb;
  v_retour bigint;
  v_rames  integer;
BEGIN
  -- 1. LE CLOISONNEMENT D'ABORD, comme `chain_regenerate` : un retour
  --    sans société n'est pas un retour, c'est une absence de garantie.
  IF p_tenant IS NULL THEN
    RAISE EXCEPTION 'Retour arrière refusé : aucune société (cloisonnement fermé).'
      USING ERRCODE = '23514';
  END IF;

  -- 1b. ⚠️ LA GARDE QUE LA PORTE G4 A EXIGÉE — ET ELLE A EU RAISON.
  -- Cette fonction est SECURITY DEFINER, exposée à `authenticated`, et
  -- `p_tenant` vient du client. Sans ce contrôle, un utilisateur connecté
  -- passerait l'identifiant d'une AUTRE société et ramènerait l'état de
  -- sa régénération : c'est-à-dire écrire chez un autre. La porte l'a
  -- refusée au premier essai (« sans garde de société ») — exactement
  -- pour ce qu'elle est faite.
  --
  -- Un contexte NUL (service_role, pg_cron, une migration) passe : il n'y
  -- a personne à cloisonner. C'est le même contrat que `emit_domain_event`
  -- et `chain_regenerate`, et il est dit ici pour qu'on ne le découvre
  -- pas enproduction.
  IF current_tenant_id() IS NOT NULL
     AND current_tenant_id() IS DISTINCT FROM p_tenant THEN
    RAISE EXCEPTION 'Retour arrière refusé : votre contexte connecté n''appartient pas à la société visée.'
      USING ERRCODE = '23514';
  END IF;

  -- 2. LE JOURNAL DEMANDÉ. On distingue « inconnu » de « autre société »
  --    pour que le refus soit actionnable (cf. la note de fuite plus haut).
  SELECT * INTO v_reg FROM chain_regeneration_log WHERE id = p_regeneration_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Retour arrière refusé : regeneration #% inconnue.', p_regeneration_id
      USING ERRCODE = '23514';
  END IF;
  IF v_reg.tenant_id IS DISTINCT FROM p_tenant THEN
    RAISE EXCEPTION 'Retour arrière refusé : la regeneration #% appartient à une autre société.',
      p_regeneration_id USING ERRCODE = '23514';
  END IF;

  -- 3. L'ÉTAT VIVANT, relu dans le MÊME ordre que la 252 l'a photographié
  --    (created_at, id) : sans cet ordre, rappeler une liste de payloads
  --    n'aurait pas de sens et pourrait les échanger entre liens.
  SELECT COALESCE(jsonb_agg(dl.payload ORDER BY dl.created_at, dl.id), '[]'::jsonb)
    INTO v_vivant
    FROM document_links dl
   WHERE dl.tenant_id = p_tenant
     AND dl.amont_type = v_reg.amont_type
     AND dl.amont_id = v_reg.amont_id
     AND dl.effet = v_reg.effet;

  IF jsonb_array_length(v_vivant) = 0 THEN
    RAISE EXCEPTION 'Retour arrière refusé : aucun lien « % » sur % (%) — il n''y a plus rien à ramener.',
      v_reg.effet, v_reg.amont_type, v_reg.amont_id USING ERRCODE = '23514';
  END IF;

  -- 4. LE CONFLIT. L'appelant déclare ce qu'il croit trouver ; si le réel
  --    diffère, quelqu'un a travaillé depuis, et revenir détruirait son
  --    travail. On refuse, on ne préempte pas.
  IF p_attendu IS NULL THEN
    RAISE EXCEPTION 'Retour arrière refusé : aucun état attendu déclaré — sans lui, le retour ne peut pas détecter un conflit.'
      USING ERRCODE = '23514';
  END IF;
  IF v_vivant IS DISTINCT FROM p_attendu THEN
    RAISE EXCEPTION 'Retour arrière REFUSÉ : CONFLIT sur « % » de % (%). L''état attendu par l''appelant n''est plus celui en place — revenez après avoir relu, ou régénérez de nouveau.',
      v_reg.effet, v_reg.amont_type, v_reg.amont_id USING ERRCODE = '23514';
  END IF;

  -- 5. DÉJÀ REVENU. Le lien est déjà dans l'état visé : le retour ne
  --    ferait rien, et se journaliserait quand même comme s'il avait agi.
  --    Un rejeu de script deviendrait une seconde régénération — donc
  --    l'idempotence est ici un REFUS, pas un no-op silencieux.
  IF v_vivant IS NOT DISTINCT FROM v_reg.avant THEN
    RAISE EXCEPTION 'Retour arrière refusé : l''effet « % » de % (%) est DÉJÀ dans l''état antérieur — rien à ramener.',
      v_reg.effet, v_reg.amont_type, v_reg.amont_id USING ERRCODE = '23514';
  END IF;

  -- 6. LA RESTAURATION, position par position. `etat` n'est PAS touché :
  --    un lien rompu le reste (T07) — revenir n'est pas réparer.
  WITH ordonne AS (
    SELECT dl.id, dl.payload, dl.etat,
           row_number() OVER (ORDER BY dl.created_at, dl.id) AS rang
      FROM document_links dl
     WHERE dl.tenant_id = p_tenant
       AND dl.amont_type = v_reg.amont_type
       AND dl.amont_id = v_reg.amont_id
       AND dl.effet = v_reg.effet
  ),
  instantane AS (
    SELECT snapshot.rang, snapshot.p
      FROM jsonb_array_elements(v_reg.avant) WITH ORDINALITY AS snapshot(p, rang)
  )
  UPDATE document_links dl
     SET payload = i.p
    FROM ordonne o
    JOIN instantane i ON i.rang = o.rang
   WHERE dl.id = o.id
     AND dl.payload IS DISTINCT FROM i.p;

  GET DIAGNOSTICS v_rames = ROW_COUNT;

  -- Si l'instantané et le vivant n'ont pas la même longueur, il y en a
  -- qui n'ont pas reçu leur part : le dire vaut mieux que de laisser
  -- un lien commander un état qu'il n'a pas eu.
  IF jsonb_array_length(v_reg.avant) <> jsonb_array_length(v_vivant) THEN
    RAISE EXCEPTION 'Retour arrière refusé : l''instantané compte % lien(s) et il y en a % en place — remise impossible.',
      jsonb_array_length(v_reg.avant), jsonb_array_length(v_vivant)
      USING ERRCODE = '23514';
  END IF;

  -- 7. LE RETOUR SE JOURNALISE LUI-MÊME — et il emporte dans `avant`
  --    l'état qu'il vient de REMPLACER : le retour est donc lui-même
  --    réversible, et l'historique se relit dans les deux sens.
  INSERT INTO chain_regeneration_log
    (tenant_id, effet, amont_type, amont_id, cause, avant, apres, created_by)
  VALUES (p_tenant, v_reg.effet, v_reg.amont_type, v_reg.amont_id,
          format('retour arrière de la regeneration #%s — %s',
                 p_regeneration_id, v_reg.cause),
          v_vivant, v_reg.avant, auth.uid())
  RETURNING id INTO v_retour;

  PERFORM emit_domain_event(p_tenant, 'chain.regeneration_reverted',
    v_reg.amont_type, v_reg.amont_id,
    jsonb_build_object('effet', v_reg.effet,
                       'regeneration_id', p_regeneration_id,
                       'retour_id', v_retour,
                       'liens_ramenes', v_rames,
                       'cause', v_reg.cause), NULL);

  RETURN v_retour;
END $fn$;

COMMENT ON FUNCTION public.chain_regeneration_rollback(uuid, bigint, jsonb) IS
  'Retour arriere d une regeneration : restaure les payloads « avant » dans '
  'document_links, pour un effet d un document. p_attendu est l etat VIVANT que '
  'l appelant croit trouver (concurrence optimiste) : si le reel ne colle pas, '
  'REFUS PAR CONFLIT — revenir n a pas le droit d ecraser un travail plus recent. '
  'Refuse aussi si l etat vise est deja en place, ou sans societe. Journalise son '
  'propre retour (donc reversible lui-meme) et emet chain.regeneration_reverted. '
  'Ne touche PAS au cycle du lien : un lien rompu le reste.';

REVOKE ALL ON FUNCTION public.chain_regeneration_rollback(uuid, bigint, jsonb)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chain_regeneration_rollback(uuid, bigint, jsonb)
  TO authenticated, service_role;
