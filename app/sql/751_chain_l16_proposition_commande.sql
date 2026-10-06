-- 751 — chain_l16_proposition_commande
-- Numéro pris le 2026-10-06T09:14:08.632Z par migration-numero.mjs (ligne « plan6 A3 L16 (familles restantes) », branche plan6/a3-moteur).
-- ═══════════════════════════════════════════════════════════════════════════
-- 751 — L16 · le chaînage interne du STOCK/ACHATS : la COMMANDE D'ACHAT issue
--       d'une PROPOSITION (MRP) lui est RATTACHÉE et TRACÉE
-- ═══════════════════════════════════════════════════════════════════════════
-- Le référentiel (§B.3) le dit au module Stock — « besoin (MRP) ↔ **proposition ↔
-- commande** ↔ réception ↔ stock ↔ CUMP ↔ écriture ». Le lot `498` a fermé
-- commande d'achat → réception ; voici l'amont : la **proposition** d'achat que
-- le MRP produit devient une commande.
--
-- CE QUE LA MESURE A TROUVÉ AVANT D'ÉCRIRE (base neuve, 333 migrations) :
--   * `mrp_proposals` EXISTE (le MRP la remplit : `run_mrp`, `proposal_type`
--     `purchase|manufacture|subcontract`, `status` `pending|approved|rejected|
--     converted`, `supplier_id`, `suggested_quantity`, `suggested_date`) ;
--   * elle n'est PAS au registre `chain_document_types` → un lien vers une
--     proposition aurait été REFUSÉ (451). C'est le premier objet de ce fichier ;
--   * aucun contrat d'effet, donc aucun maillon.
--
-- CE QUE CE FICHIER POSE : le type `mrp_proposals` au registre, le contrat
-- d'effet `purchase.proposal.to_order`, et le maillon
-- `chain_l16_proposal_order` — idempotent (rejeu REFUSÉ), réversible, tracé
-- (`link_documents`, type `created_from`, lisible par la Vue Chaîne).
--
-- ⚠️ LA COHÉRENCE EST VÉRIFIÉE, PAS SUPPOSÉE : seule une proposition d'ACHAT
-- (`proposal_type = 'purchase'`) devient une commande d'achat ici (une proposition
-- de fabrication va vers un OF — hors de ce maillon) ; une proposition déjà
-- convertie ou rejetée est refusée ; la commande ne se rattache pas à une
-- proposition d'un AUTRE fournisseur.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Le registre accueille la PROPOSITION (MRP) et la COMMANDE D'ACHAT ───
-- `purchase_orders` est posée par la 498 ; on la réaffirme (upsert) pour que la
-- 751 reste autosuffisante si elle était jouée seule.
INSERT INTO public.chain_document_types (code, table_name, ligne_table, libelle_fr) VALUES
  ('mrp_proposals', 'mrp_proposals', NULL, 'Proposition d''approvisionnement (MRP)'),
  ('purchase_orders', 'purchase_orders', 'purchase_order_lines', 'Commande d''achat')
ON CONFLICT (code) DO UPDATE SET
  table_name  = EXCLUDED.table_name,
  ligne_table = EXCLUDED.ligne_table,
  libelle_fr  = EXCLUDED.libelle_fr;

-- ── 2. Le CONTRAT d'effet (L7) : sans lui, la porte G2 refuse le maillon ───
INSERT INTO public.document_effects
  (tenant_id, document_type, evenement, effet, ecrit_comptable, journal_code,
   touche_stock, touche_paie, reversible, obligatoire, actif, note)
SELECT NULL, 'mrp_proposals', 'converted', 'purchase.proposal.to_order', false, NULL,
       false, false, true, false, true,
       'L16/751 : une proposition d''achat (MRP) est convertie en commande d''achat, et le lien amont→aval est posé. Aucune comptabilité ni stock ici. Réversible : fermer le lien.'
WHERE NOT EXISTS (
  SELECT 1 FROM public.document_effects
  WHERE document_type = 'mrp_proposals' AND evenement = 'converted' AND effet = 'purchase.proposal.to_order'
);

-- ── 3. Le MAILLON : `chain_l16_proposal_order` ─────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l16_proposal_order(p_proposal_id uuid, p_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_p     mrp_proposals%ROWTYPE;
  v_o     purchase_orders%ROWTYPE;
  v_exist uuid;
BEGIN
  -- 1. La proposition, VERROUILLÉE et bornée à la société.
  SELECT * INTO v_p FROM mrp_proposals
   WHERE id = p_proposal_id AND tenant_id = current_tenant_id()
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Proposition introuvable (ou hors de votre société)' USING ERRCODE = 'no_data_found';
  END IF;

  -- 2. La commande d'achat, bornée à la société.
  SELECT * INTO v_o FROM purchase_orders
   WHERE id = p_order_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Commande d''achat introuvable (ou hors de votre société)' USING ERRCODE = 'no_data_found';
  END IF;

  -- 3. LES REFUS EXPLICITES : chaque refus porte sa raison.
  IF v_p.status = 'rejected' THEN
    RAISE EXCEPTION 'Proposition % rejetée : aucune commande ne s''y rattache', v_p.id
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_p.status = 'converted' THEN
    RAISE EXCEPTION 'Proposition % déjà convertie en commande', v_p.id
      USING ERRCODE = 'unique_violation';
  END IF;
  IF v_p.proposal_type <> 'purchase' THEN
    RAISE EXCEPTION 'Proposition % de type % : une proposition de fabrication va vers un OF, pas une commande d''achat',
      v_p.id, v_p.proposal_type USING ERRCODE = 'check_violation';
  END IF;
  IF v_o.status = 'cancelled' THEN
    RAISE EXCEPTION 'Commande d''achat % annulée : rattachement impossible', v_o.number
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_p.supplier_id IS NOT NULL AND v_o.supplier_id IS DISTINCT FROM v_p.supplier_id THEN
    RAISE EXCEPTION 'La commande % et la proposition % ne visent pas le même fournisseur',
      v_o.number, v_p.id USING ERRCODE = 'check_violation';
  END IF;

  -- 4. IDEMPOTENCE : le LIEN actif fait foi pour la frise.
  SELECT l.id INTO v_exist FROM document_links l
   WHERE l.tenant_id = v_p.tenant_id AND l.amont_type = 'mrp_proposals' AND l.amont_id = p_proposal_id
     AND l.aval_type = 'purchase_orders' AND l.aval_id = p_order_id
     AND l.effet = 'purchase.proposal.to_order' AND l.etat = 'actif'
   LIMIT 1;
  IF v_exist IS NOT NULL THEN
    RAISE EXCEPTION 'La proposition % est déjà rattachée à la commande %', v_p.id, v_o.number
      USING ERRCODE = 'unique_violation';
  END IF;

  -- 5. La proposition DIT ce qu'elle est devenue (le statut que personne ne posait).
  UPDATE mrp_proposals SET status = 'converted' WHERE id = p_proposal_id;

  -- 6. LE LIEN : c'est lui qui rend la chaîne VISIBLE (I-01).
  PERFORM link_documents(
    v_p.tenant_id, 'mrp_proposals', p_proposal_id, 'purchase_orders', p_order_id,
    'purchase.proposal.to_order', 'created_from');

  RETURN jsonb_build_object(
    'success', true, 'proposal_id', p_proposal_id, 'order_id', p_order_id,
    'order_number', v_o.number, 'suggested_quantity', v_p.suggested_quantity);
END $fn$;

COMMENT ON FUNCTION public.chain_l16_proposal_order(uuid, uuid) IS
  'L16/751 : chaîne stock/achats proposition (MRP) → commande d''achat. Idempotent (rejeu refusé), cohérent (type purchase, même fournisseur, statuts valides), marque la proposition converted, tracé (link_documents, effet purchase.proposal.to_order). SECURITY DEFINER, borné à current_tenant_id().';

-- ── 4. Droits : jamais PUBLIC — la règle de la garde 228 T06 ───────────────
REVOKE ALL ON FUNCTION public.chain_l16_proposal_order(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chain_l16_proposal_order(uuid, uuid) TO authenticated;
