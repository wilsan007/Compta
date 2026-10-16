-- 707 — rattachement_documents
-- Numéro pris le 2026-10-11T06:02:26.560Z par migration-numero.mjs (ligne « plan6 F (plateforme) », branche plan6/f-plateforme).
--
-- ============================================================
-- F.6 / GED-01 (partie F du plan du 05/10) : LE RATTACHEMENT UNIVERSEL
-- DE DOCUMENTS — et il est enfin VALIDÉ
--
-- Le constat, mesuré le 05/10. `module_documents` (migration 68) porte DEUX
-- colonnes polymorphes — `entity_type`, `entity_id` — qui disent à quelle pièce
-- un document se rattache. Elles sont lues et écrites par la couche d'écrans
-- (`src/lib/queries/documents.ts`), et… **rien ne les valide**. Mesuré :
--   * seul `tenant_id` est posé (`trigger set_tenant_id_module_documents`) :
--     aucune contrainte, aucune clé étrangère (une colonne polymorphe ne peut
--     pas en porter), aucun contrôle d'existence ;
--   * donc un document peut se rattacher à une pièce **qui n'existe pas**, ou à
--     une pièce **d'une autre société** — `entity_id` est un `uuid` nu. C'est le
--     défaut ISO-02 (la clé composite de la 237) que la Partie 5 a fermé pour
--     `document_links` (`451`) — mais `module_documents` n'avait pas eu sa
--     contrepartie.
--
-- Ce que cette migration pose : le contrôle d'existence, avec des refus NOMMÉS.
--   * les deux colonnes, ou aucune (une moitié ne désigne rien) ;
--   * `entity_type` doit être un CODE DU REGISTRE `chain_document_types`
--     (27 pièces : factures, avoirs, BL, écritures, lots de paie, tickets,
--     mouvements de stock…) — c'est le registre que la `450` a posé, et il est
--     lisible par tous (`SELECT USING (true)`) : le réutiliser est le but ;
--   * la pièce doit EXISTER **dans la société du document** (lecture bornée par
--     la RLS du lecteur, plus le filtre `tenant_id` explicite).
--
-- REFUS : `DOCUMENT_LINK_INCOMPLETE`, `DOCUMENT_LINK_TYPE`,
-- `DOCUMENT_LINK_MISSING`.
--
-- Pas de nouvelle table : `document_entity_types` (la coquille identifiée par
-- F.8) aurait recopié `chain_document_types` — un second registre qui aurait pu
-- diverger. Le registre des chaînages EST le registre des pièces.
--
-- ⚠️ LIMITE DITE. Le vocabulaire accepté est celui du REGISTRE (les 27 codes) :
-- une pièce qui n'y figure pas (projet, client, salarié) ne peut pas encore
-- accueillir de document — l'ouvrir demande d'inscrire son code au registre, ce
-- qui est un acte de revue, pas une chaîne libre. Et l'écriture est aujourd'hui
-- ORPHELINE côté écran (`DocumentList`/`DocumentUploader` n'ont aucun appelant) :
-- cette migration rend le rattachement RÉEL, elle ne le rend pas encore visible.
-- Brancher l'écran est le lot suivant.
-- ============================================================

CREATE OR REPLACE FUNCTION validate_module_document_link()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_table  text;
  v_exists boolean;
BEGIN
  -- Un document sans rattachement reste valide (les deux colonnes NULL) :
  -- c'est le cas ordinaire d'un document de module, et il ne change pas.
  IF NEW.entity_type IS NULL AND NEW.entity_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Les deux, ou aucune : une moitié ne désigne rien.
  IF NEW.entity_type IS NULL OR NEW.entity_id IS NULL THEN
    RAISE EXCEPTION 'DOCUMENT_LINK_INCOMPLETE : un rattachement porte le TYPE et l''IDENTIFIANT de la pièce';
  END IF;

  SELECT table_name INTO v_table FROM chain_document_types WHERE code = NEW.entity_type;
  IF v_table IS NULL THEN
    RAISE EXCEPTION 'DOCUMENT_LINK_TYPE : type de pièce inconnu du registre (%)', NEW.entity_type;
  END IF;

  -- Existence DANS LA SOCIÉTÉ : la lecture est bornée par la RLS du lecteur, et
  -- le filtre de société est explicite — les deux gardes, pas une.
  EXECUTE format('SELECT EXISTS (SELECT 1 FROM public.%I WHERE id = $1 AND tenant_id = $2)', v_table)
     USING NEW.entity_id, NEW.tenant_id INTO v_exists;
  IF NOT v_exists THEN
    RAISE EXCEPTION 'DOCUMENT_LINK_MISSING : aucune pièce % (%) dans cette société', NEW.entity_type, NEW.entity_id;
  END IF;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_validate_module_document_link ON module_documents;
CREATE TRIGGER trg_validate_module_document_link
  BEFORE INSERT OR UPDATE OF entity_type, entity_id ON module_documents
  FOR EACH ROW EXECUTE FUNCTION validate_module_document_link();

-- Une fonction de DÉCLENCHEUR n'est pas une fonction de service : personne ne
-- l'appelle directement (PostgREST n'expose pas les `RETURNS trigger`). Sans ce
-- retrait, elle resterait exécutable par `PUBLIC` — donc par un visiteur.
REVOKE ALL ON FUNCTION validate_module_document_link() FROM PUBLIC, anon;

