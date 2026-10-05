-- 494 — chain_l16_commande_livraison
-- Numéro pris le 2026-10-05T20:42:52.353Z par migration-numero.mjs (ligne « plan6 A3 (moteur L16-L24) », branche plan6/a3-moteur).
-- ═══════════════════════════════════════════════════════════════════════════
-- 494 — L16 · le chaînage interne du COMMERCIAL (tronçon 2) : la LIVRAISON
--       issue d'une COMMANDE est RATTACHÉE à elle et TRACÉE
-- ═══════════════════════════════════════════════════════════════════════════
-- Le référentiel (§B.3) le dit au module Commercial — « devis ↔ commande ↔
-- livraison ↔ facture ↔ avoir ↔ règlement ↔ relance ». Le tronçon
-- devis → commande est fermé par la `493` ; voici le suivant : commande →
-- livraison.
--
-- CE QUE LA MESURE A TROUVÉ AVANT D'ÉCRIRE (base neuve, 333 migrations) :
--   * `delivery_notes.sales_order_id` et `delivery_note_lines.sales_order_line_id`
--     EXISTENT — le schéma portait le rattachement ; PERSONNE ne l'écrivait ;
--   * aucun contrat d'effet, donc aucun maillon : la porte G2 refuse un effet
--     appelé sans contrat ;
--   * l'écran crée le bon de livraison (`create_delivery_note_atomic`, 147/184)
--     sans vérifier qu'il correspond à une commande, ni le relier, ni le tracer.
--
-- CE QUE CE FICHIER POSE : le contrat d'effet `sale.order.to_delivery`, et le
-- maillon `chain_l16_order_deliver` — idempotent (une commande ne se rattache
-- qu'UNE fois à un bon de livraison donné ; le rejeu est REFUSÉ), réversible
-- (le lien peut être fermé) et tracé (`link_documents`, donc lisible par la
-- Vue Chaîne, I-01).
--
-- ⚠️ LA COHÉRENCE EST VÉRIFIÉE, PAS SUPPOSÉE. Un bon de livraison ne se
-- rattache à une commande que si elles visent le MÊME client ; une livraison
-- annulée ou retournée ne se rattache pas ; une commande en brouillon ou
-- annulée n'en reçoit pas. Chaque refus porte sa raison.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Le CONTRAT d'effet (L7) : sans lui, la porte G2 refuse le maillon ───
-- La sortie de stock est déjà portée par le bon (`sale.delivery.stock_out`) :
-- ce maillon-ci ne touche ni le stock ni la comptabilité, il RATTACHE et TRACE.
INSERT INTO public.document_effects
  (tenant_id, document_type, evenement, effet, ecrit_comptable, journal_code,
   touche_stock, touche_paie, reversible, obligatoire, actif, note)
SELECT NULL, 'sales_orders', 'delivered', 'sale.order.to_delivery', false, NULL,
       false, false, true, false, true,
       'L16/494 : une commande client reçoit un bon de livraison qui la solde, et le lien amont→aval est posé. Aucune comptabilité ni sortie de stock ici (la sortie de stock est l''effet sale.delivery.stock_out, déjà porté par le bon). Réversible : fermer le lien.'
WHERE NOT EXISTS (
  SELECT 1 FROM public.document_effects
  WHERE document_type = 'sales_orders' AND evenement = 'delivered' AND effet = 'sale.order.to_delivery'
);

-- ── 2. Le MAILLON : `chain_l16_order_deliver` ──────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l16_order_deliver(p_order_id uuid, p_delivery_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_o     sales_orders%ROWTYPE;
  v_d     delivery_notes%ROWTYPE;
  v_exist uuid;
BEGIN
  -- 1. La commande, VERROUILLÉE et bornée à la société : deux appels
  --    simultanés ne posent pas deux liens pour le même couple.
  SELECT * INTO v_o FROM sales_orders
   WHERE id = p_order_id AND tenant_id = current_tenant_id()
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Commande introuvable (ou hors de votre société)' USING ERRCODE = 'no_data_found';
  END IF;

  -- 2. La livraison, bornée à la société.
  SELECT * INTO v_d FROM delivery_notes
   WHERE id = p_delivery_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bon de livraison introuvable (ou hors de votre société)' USING ERRCODE = 'no_data_found';
  END IF;

  -- 3. LES REFUS EXPLICITES : chaque refus porte sa raison — le contraire d'un
  --    état muet, qui est exactement le défaut que le référentiel mesure.
  IF v_o.status = 'cancelled' THEN
    RAISE EXCEPTION 'Commande % annulée : aucune livraison ne s''y rattache', v_o.number
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_o.status = 'draft' THEN
    RAISE EXCEPTION 'Commande % non confirmée (statut %) : la livraison ne suit qu''une commande confirmée',
      v_o.number, v_o.status USING ERRCODE = 'check_violation';
  END IF;
  IF v_d.status IN ('cancelled', 'returned') THEN
    RAISE EXCEPTION 'Bon de livraison % % : rattachement impossible', v_d.number, v_d.status
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_d.customer_id IS DISTINCT FROM v_o.customer_id THEN
    RAISE EXCEPTION 'Le bon de livraison % et la commande % ne visent pas le même client',
      v_d.number, v_o.number USING ERRCODE = 'check_violation';
  END IF;
  IF v_d.sales_order_id IS NOT NULL AND v_d.sales_order_id <> p_order_id THEN
    RAISE EXCEPTION 'Le bon de livraison % est déjà rattaché à une autre commande', v_d.number
      USING ERRCODE = 'unique_violation';
  END IF;

  -- 4. IDEMPOTENCE : deux lectures, parce que deux réalités le disent — la
  --    colonne que le schéma portait, ET le LIEN actif (celui qui fait foi pour
  --    la frise). Le rejeu est REFUSÉ, jamais silencieux.
  SELECT l.id INTO v_exist FROM document_links l
   WHERE l.tenant_id  = v_o.tenant_id
     AND l.amont_type = 'sales_orders'   AND l.amont_id = p_order_id
     AND l.aval_type  = 'delivery_notes' AND l.aval_id  = p_delivery_id
     AND l.effet = 'sale.order.to_delivery' AND l.etat = 'actif'
   LIMIT 1;
  IF v_exist IS NOT NULL THEN
    RAISE EXCEPTION 'La commande % est déjà rattachée au bon de livraison %', v_o.number, v_d.number
      USING ERRCODE = 'unique_violation';
  END IF;

  -- 5. Le rattachement STOCKÉ (la colonne que personne n'écrivait).
  UPDATE delivery_notes SET sales_order_id = p_order_id WHERE id = p_delivery_id;

  -- 6. LE LIEN : c'est lui qui rend la chaîne VISIBLE (I-01). Le nom de l'effet
  --    est celui du contrat du §1 — G2 les compare.
  PERFORM link_documents(
    v_o.tenant_id, 'sales_orders', p_order_id, 'delivery_notes', p_delivery_id,
    'sale.order.to_delivery', 'delivered_by');

  RETURN jsonb_build_object(
    'success', true, 'order_id', p_order_id, 'delivery_id', p_delivery_id,
    'order_number', v_o.number, 'delivery_number', v_d.number);
END $fn$;

COMMENT ON FUNCTION public.chain_l16_order_deliver(uuid, uuid) IS
  'L16/494 : chaîne commerciale commande → livraison. Idempotent (rejeu refusé), cohérent (même client, statuts valides), tracé (link_documents, effet sale.order.to_delivery). SECURITY DEFINER, borné à current_tenant_id().';

-- ── 3. Droits : jamais PUBLIC — la règle de la garde 228 T06 ───────────────
REVOKE ALL ON FUNCTION public.chain_l16_order_deliver(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chain_l16_order_deliver(uuid, uuid) TO authenticated;
