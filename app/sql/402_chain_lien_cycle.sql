-- ============================================================
-- 312_chain_lien_cycle.sql — le CYCLE DE VIE DU LIEN
--
-- Source : doc/audit/PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md (socle §3.2,
-- M-02 idempotence structurelle, M-03 réversibilité conditionnée au lien) et
-- VAGUE-L1-2026-09-29.md §6.2 (« le socle n'a pas de notion de tour »), §6.5
-- point 1 (« le cycle de vie du lien : c'est le prérequis pour poser
-- `chain_avant` partout sans casser les flux d'annulation / reprise »).
--
-- LE DÉFAUT MESURÉ, ET IL EST NÉ D'UN ROUGE. La clé d'idempotence du socle
-- (252) est `(société, amont_type, amont_id, effet, amont_ligne_id)`. Elle ne
-- distingue pas deux faits opposés :
--   * « le même effet REJOUÉ » — il ne doit rien produire de plus ;
--   * « le même effet LÉGITIMEMENT REPRODUIT après annulation » — il DOIT être
--     produit, sinon l'annulation laisse un trou.
-- Mesuré : la première version de la 311 appelait `chain_avant` en tête de
-- boucle du maillon des réservations, et la suite 230 (T04) — qui existait
-- depuis la vague des livraisons — a rougi : une commande ANNULÉE puis
-- RECONFIRMÉE ne réservait plus rien (`réservé = 0` au lieu de 10). Conclusion
-- écrite dans la 311 : `chain_avant` n'est posé QUE sur les maillons à sens
-- unique. C'est cette limitation que ce fichier lève.
--
-- LA RÉPONSE : le lien a un CYCLE DE VIE, et l'unicité ne porte que sur lui.
--   * un lien naît `actif` ;
--   * il se ferme par un ACTE EXPLICITE du métier : `remplace` (l'effet va être
--     reproduit — reconfirmation, resynchronisation) ou `rompu` (l'effet est
--     retiré — annulation, extourne) ;
--   * l'index unique `uq_document_links_effet` devient **PARTIEL** (`WHERE etat
--     = 'actif'`) : un lien fermé ne bloque donc plus le tour suivant, et il
--     n'est jamais réécrit — il RESTE, avec sa date, son motif et son auteur ;
--   * `tour` compte les rounds du couple (document, effet, ligne) : le premier
--     vaut 1, un lien produit après fermeture vaut 2, etc.
-- C'est la phrase de la 311, tenue : « **un lien remplacé, pas réécrit** ».
--
-- CE QUE CE FICHIER DÉCIDE, ET POURQUOI
--   * **la fermeture n'est jamais automatique.** Le socle ne connaît pas les
--     états métier (un `status` peut légitimement revenir — `pending → shipped →
--     returned → shipped` mesuré sur la 311, ou `cancelled → confirmed` sur la
--     230). Fermer un lien sur une transition devinée ferait disparaître en
--     silence l'effet d'une réexpédition : c'est exactement le trou qu'on
--     ferme. C'est donc le MAILLON qui ferme, en nommant son motif ;
--   * **la fermeture ciblée REFUSE quand il n'y a rien à fermer** (message
--     nominatif), parce que son appelant affirme savoir qu'un lien existe —
--     même doctrine que `chain_regenerate` (« aucun lien » = refus). La
--     fermeture GLOBALE d'un document, elle, RAPPORTE le nombre fermé : zéro
--     effet tracé y est un état légitime, pas une affirmation fausse ;
--   * **`chain_deja_fait` et `chain_integrity_ok` ne regardent que l'ACTIF.**
--     Un lien fermé n'est plus « déjà fait » (le maillon peut reproduire son
--     effet) et n'est plus « intact » (M-03 : une annulation refuse au lieu de
--     laisser une pièce orpheline) ;
--   * **une fermeture n'écrit PAS dans `chain_traces`.** Une trace mesure
--     l'exécution d'un maillon (durée, lignes écrites, résultat) ; fermer un
--     lien n'est pas produire un effet. Le journal du cycle de vie est
--     `domain_events` (`chain.link_superseded`, `chain.link_broken`) et le
--     registre `document_links` lui-même — les tableaux de bord du lot L5 s'y
--     lisent sans ajouter de valeur au vocabulaire de `chain_traces.resultat`.
--
-- CE QUE CE FICHIER NE FAIT PAS
--   * il **ne ferme aucun lien des 310 et 311** : leurs maillons restent sur la
--     doctrine du sens unique — c'est le travail de L3 (les 62 maillons) ;
--   * il **ne pose pas `chain_avant` partout** : il lève le verrou qui
--     l'empêchait (le tour), il ne réécrit pas les 62 maillons ;
--   * il **ne change pas la trace d'un refus** : la limite transactionnelle
--     (une trace `refuse` ne survit pas au rollback de l'opération refusée) est
--     une propriété de PostgreSQL, dite au §5 de la 252.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. Les colonnes du cycle de vie (additives, et rejouables)
-- ─────────────────────────────────────────────────────────────
-- `DEFAULT` constant : PostgreSQL 11+ ajoute la colonne sans réécrire la table
-- (mesuré : aucune réécriture sur `document_links`).
ALTER TABLE document_links ADD COLUMN IF NOT EXISTS etat      text NOT NULL DEFAULT 'actif';
ALTER TABLE document_links ADD COLUMN IF NOT EXISTS tour      integer NOT NULL DEFAULT 1;
ALTER TABLE document_links ADD COLUMN IF NOT EXISTS ferme_le  timestamptz;
ALTER TABLE document_links ADD COLUMN IF NOT EXISTS ferme_par uuid;
ALTER TABLE document_links ADD COLUMN IF NOT EXISTS motif     text;

COMMENT ON COLUMN document_links.etat IS
  '312 : cycle de vie du lien — actif, remplace (l''effet va être reproduit) ou rompu (l''effet est retiré). Un lien fermé n''est jamais réécrit : il reste, avec sa date, son motif et son auteur.';
COMMENT ON COLUMN document_links.tour IS
  '312 : le round du couple (document, effet, ligne). 1 à la première production, +1 après chaque fermeture. C''est la « notion de tour » qui manquait au socle (trouvaille de la 311, mesurée par la suite 230 T04).';
COMMENT ON COLUMN document_links.ferme_le IS
  '312 : instant de la fermeture — NULL tant que le lien est actif. Renseigné avec `motif` et `ferme_par` : une fermeture muette est interdite par la contrainte.';
COMMENT ON COLUMN document_links.ferme_par IS
  '312 : auteur de la fermeture (auth.uid() quand il existe — une reprise d''historique peut n''en avoir aucun, la contrainte l''admet).';
COMMENT ON COLUMN document_links.motif IS
  '312 : pourquoi le lien a été fermé (reconfirmation, annulation, extourne…). Obligatoire dès que `etat` n''est plus `actif` : c''est ce qui rend l''historique lisible, et pas seulement présent.';

-- ─────────────────────────────────────────────────────────────
-- 2. Les gardes structurelles : une fermeture est datée, motivée et signée
--    Ajoutées par bloc conditionnel — `ADD CONSTRAINT` n'a pas de
--    `IF NOT EXISTS`, et une migration se rejoue (doctrine du dépôt).
-- ─────────────────────────────────────────────────────────────
DO $bloc$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'document_links_etat_check') THEN
    ALTER TABLE document_links ADD CONSTRAINT document_links_etat_check
      CHECK (etat IN ('actif', 'remplace', 'rompu'));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'document_links_tour_check') THEN
    ALTER TABLE document_links ADD CONSTRAINT document_links_tour_check
      CHECK (tour >= 1);
  END IF;

  -- La garde qui compte : un lien ACTIF est ouvert et muet ; un lien FERMÉ est
  -- daté ET motivé. Les deux moitiés sont dans la même contrainte, donc aucune
  -- des deux ne peut être oubliée — un lien fermé « sans raison » est refusé
  -- par la base, pas par la revue.
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'document_links_fermeture_check') THEN
    ALTER TABLE document_links ADD CONSTRAINT document_links_fermeture_check
      CHECK (
        (etat = 'actif'  AND ferme_le IS NULL AND ferme_par IS NULL AND motif IS NULL)
        OR
        (etat <> 'actif' AND ferme_le IS NOT NULL AND btrim(COALESCE(motif, '')) <> '')
      );
  END IF;
END $bloc$;

-- ─────────────────────────────────────────────────────────────
-- 3. L'index d'idempotence devient PARTIEL — la bascule du fichier
--    Avant : unique sur `(société, amont_type, amont_id, effet, ligne)`, tous
--    états confondus — un lien fermé interdisait le tour suivant.
--    Après : unique sur les mêmes colonnes **WHERE etat = 'actif'**. `ON
--    CONFLICT` retrouve un index partiel dès que la clause porte le même
--    prédicat (c'est ce que fait `link_documents` au §5), et PostgreSQL refuse
--    deux liens actifs sur la même clé — l'idempotence structurelle de M-02 est
--    donc intacte, elle porte simplement sur ce qui vit.
--    Le nom est conservé : c'est le même index, sa portée a changé.
-- ─────────────────────────────────────────────────────────────
DROP INDEX IF EXISTS uq_document_links_effet;
CREATE UNIQUE INDEX IF NOT EXISTS uq_document_links_effet
  ON document_links (tenant_id, amont_type, amont_id, effet,
                     COALESCE(amont_ligne_id, '00000000-0000-0000-0000-000000000000'::uuid))
  WHERE etat = 'actif';

-- La lecture de l'historique : « tous les tours de ce couple », dans l'ordre.
CREATE INDEX IF NOT EXISTS ix_document_links_cycle
  ON document_links (tenant_id, amont_type, amont_id, effet, tour);

-- ─────────────────────────────────────────────────────────────
-- 4. Les lectures du cycle : quel lien est ACTIF, quel tour en est au combien
-- ─────────────────────────────────────────────────────────────
-- a) Le lien actif d'un couple (document, effet, ligne) — NULL s'il n'y en a pas.
CREATE OR REPLACE FUNCTION public.chain_lien_actif(
  p_tenant      uuid,
  p_amont_type  text,
  p_amont_id    uuid,
  p_effet       text,
  p_amont_ligne uuid DEFAULT NULL
) RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
  SELECT dl.id FROM document_links dl
  WHERE dl.tenant_id = p_tenant
    AND dl.amont_type = p_amont_type
    AND dl.amont_id = p_amont_id
    AND dl.effet = p_effet
    AND dl.amont_ligne_id IS NOT DISTINCT FROM p_amont_ligne
    AND dl.etat = 'actif'
  LIMIT 1
$fn$;

-- b) Le tour courant : 0 si l'effet n'a jamais été produit, sinon le plus haut
--    tour atteint (toutes états confondus — un lien fermé compte, c'est lui qui
--    a fait monter le compteur). La production suivante vaut `chain_lien_tour + 1`.
CREATE OR REPLACE FUNCTION public.chain_lien_tour(
  p_tenant      uuid,
  p_amont_type  text,
  p_amont_id    uuid,
  p_effet       text,
  p_amont_ligne uuid DEFAULT NULL
) RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
  SELECT COALESCE(max(dl.tour), 0)::integer FROM document_links dl
  WHERE dl.tenant_id = p_tenant
    AND dl.amont_type = p_amont_type
    AND dl.amont_id = p_amont_id
    AND dl.effet = p_effet
    AND dl.amont_ligne_id IS NOT DISTINCT FROM p_amont_ligne
$fn$;

-- c) `chain_deja_fait` ne regarde plus que l'ACTIF. C'est le cœur de la levée de
--    la limitation : après une fermeture, l'effet n'est plus « déjà fait », donc
--    `chain_avant` rend vrai et le maillon peut légitimement le reproduire.
CREATE OR REPLACE FUNCTION public.chain_deja_fait(
  p_tenant      uuid,
  p_amont_type  text,
  p_amont_id    uuid,
  p_effet       text,
  p_amont_ligne uuid DEFAULT NULL
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
  SELECT EXISTS (
    SELECT 1 FROM document_links dl
    WHERE dl.tenant_id = p_tenant
      AND dl.amont_type = p_amont_type
      AND dl.amont_id = p_amont_id
      AND dl.effet = p_effet
      AND dl.amont_ligne_id IS NOT DISTINCT FROM p_amont_ligne
      AND dl.etat = 'actif')
$fn$;

-- d) `chain_integrity_ok` : intact veut dire ACTIF (M-03). Un lien fermé — rompu
--    par une annulation, remplacé par un tour suivant — ne l'est plus : c'est ce
--    qui fait qu'une annulation REFUSE au lieu de laisser une pièce orpheline.
CREATE OR REPLACE FUNCTION public.chain_integrity_ok(
  p_tenant     uuid,
  p_amont_type text,
  p_amont_id   uuid,
  p_aval_type  text,
  p_aval_id    uuid
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
  SELECT EXISTS (
    SELECT 1 FROM document_links dl
    WHERE dl.tenant_id = p_tenant
      AND dl.amont_type = p_amont_type
      AND dl.amont_id = p_amont_id
      AND dl.aval_type = p_aval_type
      AND dl.aval_id = p_aval_id
      AND dl.etat = 'actif')
$fn$;

COMMENT ON FUNCTION public.chain_lien_actif(uuid, text, uuid, text, uuid) IS
  '312 : le lien ACTIF d''un couple (document, effet, ligne) — NULL s''il n''y en a pas. Ce que `chain_deja_fait` et `chain_integrity_ok` interrogent depuis la 312.';
COMMENT ON FUNCTION public.chain_lien_tour(uuid, text, uuid, text, uuid) IS
  '312 : le tour courant d''un couple (document, effet, ligne) : 0 si l''effet n''a jamais été produit, sinon le plus haut tour atteint. La production suivante vaut ce nombre + 1.';
COMMENT ON FUNCTION public.chain_deja_fait(uuid, text, uuid, text, uuid) IS
  '252, précisé par la 312 : le lien ACTIF existe-t-il déjà ? Un lien fermé (remplacé, rompu) ne compte pas — c''est ce qui permet de reproduire un effet après une annulation.';
COMMENT ON FUNCTION public.chain_integrity_ok(uuid, text, uuid, text, uuid) IS
  '252, précisé par la 312 : le lien amont ↔ aval est-il intact, c''est-à-dire ACTIF ? M-03 : si le lien est fermé, l''annulation refuse au lieu de laisser une pièce orpheline.';

-- ─────────────────────────────────────────────────────────────
-- 5. `link_documents` : le tour, et l'arbitre qui ne regarde que l'actif
--    Deux changements, et deux seulement :
--      * l'arbitre de `ON CONFLICT` porte le prédicat de l'index partiel
--        (`WHERE etat = 'actif'`) : le rejeu d'un effet ACTIF fusionne le
--        payload comme avant (la 252 T02 est inchangée) ;
--      * `tour` est calculé pour le couple : si aucun lien n'existe, 1 ; si des
--        liens existent mais sont tous fermés, le tour suivant. Le lien fermé
--        n'est PAS réécrit — il reste, et un nouveau lien naît à côté de lui.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.link_documents(
  p_tenant      uuid,
  p_amont_type  text,
  p_amont_id    uuid,
  p_aval_type   text,
  p_aval_id     uuid,
  p_effet       text,
  p_link_type   text,
  p_payload     jsonb DEFAULT '{}'::jsonb,
  p_amont_ligne uuid DEFAULT NULL,
  p_aval_ligne  uuid DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_id   uuid;
  v_tour integer;
BEGIN
  IF p_tenant IS NULL THEN
    RAISE EXCEPTION 'Chaînage refusé : aucune société — un lien sans société n''existe pas (cloisonnement fermé).'
      USING ERRCODE = '23514';
  END IF;
  IF p_amont_id IS NULL OR p_aval_id IS NULL THEN
    RAISE EXCEPTION 'Chaînage refusé : le lien % → % est incomplet (identifiant amont ou aval absent).',
      p_amont_type, p_aval_type USING ERRCODE = '23514';
  END IF;
  IF COALESCE(btrim(p_effet), '') = '' THEN
    RAISE EXCEPTION 'Chaînage refusé : maillon sans nom (effet vide). Un lien sans effet n''est pas idempotent.'
      USING ERRCODE = '23514';
  END IF;

  -- Le tour suivant du couple (tous états confondus : un lien fermé a fait
  -- monter le compteur). Lu sous la même clé que l'index partiel.
  SELECT COALESCE(max(dl.tour), 0) + 1 INTO v_tour
  FROM document_links dl
  WHERE dl.tenant_id = p_tenant
    AND dl.amont_type = p_amont_type
    AND dl.amont_id = p_amont_id
    AND dl.effet = p_effet
    AND dl.amont_ligne_id IS NOT DISTINCT FROM p_amont_ligne;

  INSERT INTO document_links (tenant_id, amont_type, amont_id, amont_ligne_id,
                              aval_type, aval_id, aval_ligne_id,
                              link_type, effet, payload, created_by, tour)
  VALUES (p_tenant, p_amont_type, p_amont_id, p_amont_ligne,
          p_aval_type, p_aval_id, p_aval_ligne,
          p_link_type, p_effet, COALESCE(p_payload, '{}'::jsonb), auth.uid(), v_tour)
  ON CONFLICT (tenant_id, amont_type, amont_id, effet,
               COALESCE(amont_ligne_id, '00000000-0000-0000-0000-000000000000'::uuid))
    WHERE etat = 'actif'
  DO UPDATE SET payload       = document_links.payload || EXCLUDED.payload,
                link_type     = EXCLUDED.link_type,
                aval_type     = EXCLUDED.aval_type,
                aval_id       = EXCLUDED.aval_id,
                aval_ligne_id = EXCLUDED.aval_ligne_id
  RETURNING id INTO v_id;

  RETURN v_id;
END $fn$;

COMMENT ON FUNCTION public.link_documents(uuid, text, uuid, text, uuid, text, text, jsonb, uuid, uuid) IS
  '252, étendu par la 312 : déclare un lien amont → aval pour un effet donné. Idempotent sur le lien ACTIF (index partiel + ON CONFLICT, payload fusionné au rejeu) ; après fermeture, un NOUVEAU lien naît au tour suivant au lieu de réécrire l''ancien. Rend l''identifiant du lien.';

-- ─────────────────────────────────────────────────────────────
-- 6. La fermeture : un acte explicite, daté, motivé, signé et journalisé
--    Un seul cœur, quatre portes :
--      * `chain_lien_fermer`    — le cœur, ciblé sur un couple (document, effet,
--                                 ligne). REFUSE s'il n'y a aucun lien actif ;
--      * `chain_lien_remplacer` — l'effet va être reproduit (reconfirmation) ;
--      * `chain_lien_rompre`    — l'effet est retiré (annulation, extourne) ;
--      * `chain_liens_fermer`   — TOUS les effets d'un document en un acte
--                                 (annulation globale). RAPPORTE, ne refuse pas.
--    Le journal : `chain.link_superseded` ou `chain.link_broken`, un événement
--    par lien fermé, portant l'effet, le tour, le motif et l'identifiant du lien.
-- ─────────────────────────────────────────────────────────────

-- a) Le cœur : fermer le lien ACTIF d'un couple.
CREATE OR REPLACE FUNCTION public.chain_lien_fermer(
  p_tenant      uuid,
  p_amont_type  text,
  p_amont_id    uuid,
  p_effet       text,
  p_amont_ligne uuid,
  p_etat        text,
  p_motif       text
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_id   uuid;
  v_tour integer;
  v_n    integer;
BEGIN
  IF p_tenant IS NULL THEN
    RAISE EXCEPTION 'Fermeture de lien refusée : aucune société (cloisonnement fermé).'
      USING ERRCODE = '23514';
  END IF;
  IF p_etat NOT IN ('remplace', 'rompu') THEN
    RAISE EXCEPTION 'Fermeture de lien refusée : « % » n''est pas un état de fermeture (remplace, rompu).', p_etat
      USING ERRCODE = '22023';
  END IF;
  IF COALESCE(btrim(p_motif), '') = '' THEN
    RAISE EXCEPTION 'Fermeture de lien refusée pour « % » : aucun motif — une fermeture muette rend l''historique illisible.', p_effet
      USING ERRCODE = '23514';
  END IF;

  -- La fermeture EST la clause de course : `WHERE etat = 'actif'` rend l'acte
  -- atomique. Deux appelants simultanés n'en ferment qu'un — le second n'a plus
  -- rien à fermer, et l'apprend par le refus explicite ci-dessous.
  UPDATE document_links
     SET etat      = p_etat,
         ferme_le  = now(),
         ferme_par = auth.uid(),
         motif     = btrim(p_motif)
   WHERE tenant_id = p_tenant
     AND amont_type = p_amont_type
     AND amont_id = p_amont_id
     AND effet = p_effet
     AND amont_ligne_id IS NOT DISTINCT FROM p_amont_ligne
     AND etat = 'actif'
  RETURNING id, tour INTO v_id, v_tour;

  GET DIAGNOSTICS v_n = ROW_COUNT;

  IF v_n = 0 THEN
    RAISE EXCEPTION 'Fermeture de lien refusée : aucun lien ACTIF « % » pour % (%) — il n''y a rien à fermer. Un lien déjà fermé se relit (document_links.etat) ; un effet jamais produit ne se ferme pas.',
      p_effet, p_amont_type, p_amont_id USING ERRCODE = '23514';
  END IF;

  PERFORM emit_domain_event(
    p_tenant,
    CASE p_etat WHEN 'rompu' THEN 'chain.link_broken' ELSE 'chain.link_superseded' END,
    p_amont_type, p_amont_id,
    jsonb_build_object('effet', p_effet, 'lien_id', v_id, 'tour', v_tour,
                       'etat', p_etat, 'motif', btrim(p_motif),
                       'amont_ligne_id', p_amont_ligne),
    NULL);

  RETURN v_n;
END $fn$;

-- b) L'effet va être REPRODUIT (reconfirmation, resynchronisation).
CREATE OR REPLACE FUNCTION public.chain_lien_remplacer(
  p_tenant      uuid,
  p_amont_type  text,
  p_amont_id    uuid,
  p_effet       text,
  p_motif       text,
  p_amont_ligne uuid DEFAULT NULL
) RETURNS integer
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
  SELECT chain_lien_fermer(p_tenant, p_amont_type, p_amont_id, p_effet, p_amont_ligne, 'remplace', p_motif)
$fn$;

-- c) L'effet est RETIRÉ (annulation, extourne).
CREATE OR REPLACE FUNCTION public.chain_lien_rompre(
  p_tenant      uuid,
  p_amont_type  text,
  p_amont_id    uuid,
  p_effet       text,
  p_motif       text,
  p_amont_ligne uuid DEFAULT NULL
) RETURNS integer
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
  SELECT chain_lien_fermer(p_tenant, p_amont_type, p_amont_id, p_effet, p_amont_ligne, 'rompu', p_motif)
$fn$;

-- d) TOUS les effets actifs d'un document, en un acte (annulation globale).
--    Rapporte le nombre fermé : zéro effet tracé n'y est pas une affirmation
--    fausse (contrairement au ciblé) — un document dont rien n'a été tracé se
--    ferme « pour rien », et c'est légitime.
CREATE OR REPLACE FUNCTION public.chain_liens_fermer(
  p_tenant     uuid,
  p_amont_type text,
  p_amont_id   uuid,
  p_etat       text,
  p_motif      text
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  r   record;
  v_n integer := 0;
BEGIN
  IF p_tenant IS NULL THEN
    RAISE EXCEPTION 'Fermeture de liens refusée : aucune société (cloisonnement fermé).'
      USING ERRCODE = '23514';
  END IF;
  IF p_etat NOT IN ('remplace', 'rompu') THEN
    RAISE EXCEPTION 'Fermeture de liens refusée : « % » n''est pas un état de fermeture (remplace, rompu).', p_etat
      USING ERRCODE = '22023';
  END IF;
  IF COALESCE(btrim(p_motif), '') = '' THEN
    RAISE EXCEPTION 'Fermeture de liens refusée pour % (%) : aucun motif — une fermeture muette rend l''historique illisible.',
      p_amont_type, p_amont_id USING ERRCODE = '23514';
  END IF;

  FOR r IN
    SELECT dl.id, dl.effet, dl.tour, dl.amont_ligne_id
    FROM document_links dl
    WHERE dl.tenant_id = p_tenant
      AND dl.amont_type = p_amont_type
      AND dl.amont_id = p_amont_id
      AND dl.etat = 'actif'
    ORDER BY dl.tour, dl.effet
    FOR UPDATE
  LOOP
    UPDATE document_links
       SET etat = p_etat, ferme_le = now(), ferme_par = auth.uid(), motif = btrim(p_motif)
     WHERE id = r.id;
    v_n := v_n + 1;

    PERFORM emit_domain_event(
      p_tenant,
      CASE p_etat WHEN 'rompu' THEN 'chain.link_broken' ELSE 'chain.link_superseded' END,
      p_amont_type, p_amont_id,
      jsonb_build_object('effet', r.effet, 'lien_id', r.id, 'tour', r.tour,
                         'etat', p_etat, 'motif', btrim(p_motif),
                         'amont_ligne_id', r.amont_ligne_id, 'fermeture_globale', true),
      NULL);
  END LOOP;

  RETURN v_n;
END $fn$;


COMMENT ON FUNCTION public.chain_lien_fermer(uuid, text, uuid, text, uuid, text, text) IS
  '312 : ferme le lien ACTIF d''un couple (document, effet, ligne) — état `remplace` ou `rompu`, motif obligatoire, journalisé. REFUSE s''il n''y a aucun lien actif : son appelant affirme savoir qu''un lien existe (même doctrine que chain_regenerate).';
COMMENT ON FUNCTION public.chain_lien_remplacer(uuid, text, uuid, text, text, uuid) IS
  '312 : ferme le lien actif en `remplace` — l''effet va être reproduit (reconfirmation d''une commande annulée, resynchronisation). Le tour suivant naîtra au prochain link_documents.';
COMMENT ON FUNCTION public.chain_lien_rompre(uuid, text, uuid, text, text, uuid) IS
  '312 : ferme le lien actif en `rompu` — l''effet est retiré (annulation, extourne). M-03 : le lien n''est plus « intact », donc l''annulation peut refuser au lieu de laisser une pièce orpheline.';
COMMENT ON FUNCTION public.chain_liens_fermer(uuid, text, uuid, text, text) IS
  '312 : ferme TOUS les liens actifs d''un document en un acte (annulation globale) et RAPPORTE le nombre fermé — zéro y est légitime. Un événement par lien fermé.';

-- ─────────────────────────────────────────────────────────────
-- 7. Droits : le cycle de vie n'est pas non plus une API
--    Même règle que la 252 (§14) : ces fonctions s'appellent depuis les maillons
--    (déclencheurs et fonctions SECURITY DEFINER, propriétaires des tables),
--    jamais depuis PostgREST. `check_anon_grants.sql` est le garde-fou du jour où
--    une migration l'oubliera.
-- ─────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.chain_lien_actif(uuid, text, uuid, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.chain_lien_tour(uuid, text, uuid, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.chain_lien_fermer(uuid, text, uuid, text, uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.chain_lien_remplacer(uuid, text, uuid, text, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.chain_lien_rompre(uuid, text, uuid, text, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.chain_liens_fermer(uuid, text, uuid, text, text) FROM PUBLIC, anon, authenticated;

-- ─────────────────────────────────────────────────────────────
-- 8. Le geste que les maillons ajouteront (L3), écrit ici pour être opposable
--
--    Annulation d'un document dont les effets ont été tracés :
--      PERFORM chain_liens_fermer(NEW.tenant_id, 'sales_orders', NEW.id, 'rompu',
--        format('Commande %s du %s annulée : les effets tracés sont retirés (règle sale.order.cancelled).',
--               NEW.number, to_char(NEW.date, 'DD/MM/YYYY')));
--      -- la garde M-03 reste celle du métier :
--      IF NOT chain_integrity_ok(...) THEN RAISE EXCEPTION '…' ; END IF ;
--
--    Reconformation (même effet reproduit) :
--      PERFORM chain_lien_remplacer(NEW.tenant_id, 'sales_orders', NEW.id,
--        'sale.order.reserved', 'Commande reconfirmée : la réservation est reproduite.');
--      -- puis le maillon reprend son cours (ou son propre appel de chain_avant).
--
--    Ce que ce geste apporte, et c'est la mesure qui l'a exigée : `chain_avant`
--    peut désormais être posé SUR LES MAILLONS QUI SE REPRODUISENT — le tour a
--    fermé le lien précédent, donc `chain_deja_fait` rend faux et l'effet est
--    reproduit au lieu de disparaître en silence (le rouge de la suite 230 T04).
-- ─────────────────────────────────────────────────────────────
