-- 498 — chain_l16_reception_commande
-- Numéro pris le 2026-10-06T05:46:37.975Z par migration-numero.mjs (ligne « plan6 A3 (moteur L16-L24) », branche plan6/a3-moteur).
-- ═══════════════════════════════════════════════════════════════════════════
-- 498 — L16 · le chaînage interne des ACHATS : la RÉCEPTION issue d'une
--       COMMANDE D'ACHAT lui est RATTACHÉE et TRACÉE
-- ═══════════════════════════════════════════════════════════════════════════
-- Le miroir achats du tronçon `494` (ventes). La famille Stock du référentiel
-- (§B.3) va « besoin (MRP) ↔ proposition ↔ **commande ↔ réception** ↔ stock ».
--
-- CE QUE LA MESURE A TROUVÉ AVANT D'ÉCRIRE (base neuve, 333 migrations) :
--   * `goods_receipts.purchase_order_id` EXISTE — le schéma portait le
--     rattachement ; PERSONNE ne l'écrivait ;
--   * `purchase_orders` n'est PAS au registre `chain_document_types` : un lien
--     vers une commande d'achat aurait été REFUSÉ par la garde d'existence (451).
--     C'est le premier objet de ce fichier ;
--   * aucun contrat d'effet, donc aucun maillon.
--
-- CE QUE CE FICHIER POSE : le type `purchase_orders` au registre, le contrat
-- d'effet `purchase.order.to_receipt`, et le maillon `chain_l16_receipt_order` —
-- idempotent (rejeu REFUSÉ), réversible, tracé (`link_documents`, type
-- `delivered_by`, lisible par la Vue Chaîne).
--
-- ⚠️ LA COHÉRENCE EST VÉRIFIÉE, PAS SUPPOSÉE : la réception et la commande
-- visent le MÊME fournisseur ; une commande en brouillon ou annulée n'en reçoit
-- pas ; une réception annulée ne se rattache pas ; une réception déjà rattachée à
-- une AUTRE commande est refusée.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Le registre des types de documents accueille les COMMANDES D'ACHAT ──
-- Le geste est celui de la 450/493 : un upsert, donc rejouable.
INSERT INTO public.chain_document_types (code, table_name, ligne_table, libelle_fr) VALUES
  ('purchase_orders', 'purchase_orders', 'purchase_order_lines', 'Commande d''achat')
ON CONFLICT (code) DO UPDATE SET
  table_name  = EXCLUDED.table_name,
  ligne_table = EXCLUDED.ligne_table,
  libelle_fr  = EXCLUDED.libelle_fr;

-- ── 2. Le CONTRAT d'effet (L7) : sans lui, la porte G2 refuse le maillon ───
INSERT INTO public.document_effects
  (tenant_id, document_type, evenement, effet, ecrit_comptable, journal_code,
   touche_stock, touche_paie, reversible, obligatoire, actif, note)
SELECT NULL, 'purchase_orders', 'received', 'purchase.order.to_receipt', false, NULL,
       false, false, true, false, true,
       'L16/498 : une commande d''achat reçoit une réception qui la solde, et le lien amont→aval est posé. L''entrée de stock est portée par la réception (purchase.receipt.stock_in), pas par ce maillon. Réversible : fermer le lien.'
WHERE NOT EXISTS (
  SELECT 1 FROM public.document_effects
  WHERE document_type = 'purchase_orders' AND evenement = 'received' AND effet = 'purchase.order.to_receipt'
);

-- ── 3. Le MAILLON : `chain_l16_receipt_order` ──────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l16_receipt_order(p_order_id uuid, p_receipt_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_o     purchase_orders%ROWTYPE;
  v_r     goods_receipts%ROWTYPE;
  v_exist uuid;
BEGIN
  -- 1. La commande d'achat, VERROUILLÉE et bornée à la société.
  SELECT * INTO v_o FROM purchase_orders
   WHERE id = p_order_id AND tenant_id = current_tenant_id()
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Commande d''achat introuvable (ou hors de votre société)' USING ERRCODE = 'no_data_found';
  END IF;

  -- 2. La réception, bornée à la société.
  SELECT * INTO v_r FROM goods_receipts
   WHERE id = p_receipt_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Réception introuvable (ou hors de votre société)' USING ERRCODE = 'no_data_found';
  END IF;

  -- 3. LES REFUS EXPLICITES : chaque refus porte sa raison.
  IF v_o.status = 'cancelled' THEN
    RAISE EXCEPTION 'Commande d''achat % annulée : aucune réception ne s''y rattache', v_o.number
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_o.status = 'draft' THEN
    RAISE EXCEPTION 'Commande d''achat % non confirmée (statut %) : la réception ne suit qu''une commande confirmée',
      v_o.number, v_o.status USING ERRCODE = 'check_violation';
  END IF;
  IF v_r.status = 'cancelled' THEN
    RAISE EXCEPTION 'Réception % annulée : rattachement impossible', v_r.number
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_r.supplier_id IS DISTINCT FROM v_o.supplier_id THEN
    RAISE EXCEPTION 'La réception % et la commande % ne visent pas le même fournisseur',
      v_r.number, v_o.number USING ERRCODE = 'check_violation';
  END IF;
  IF v_r.purchase_order_id IS NOT NULL AND v_r.purchase_order_id <> p_order_id THEN
    RAISE EXCEPTION 'La réception % est déjà rattachée à une autre commande', v_r.number
      USING ERRCODE = 'unique_violation';
  END IF;

  -- 4. IDEMPOTENCE : deux lectures — la colonne que le schéma portait, ET le
  --    LIEN actif. Le rejeu est REFUSÉ, jamais silencieux.
  SELECT l.id INTO v_exist FROM document_links l
   WHERE l.tenant_id  = v_o.tenant_id
     AND l.amont_type = 'purchase_orders' AND l.amont_id = p_order_id
     AND l.aval_type  = 'goods_receipts'  AND l.aval_id  = p_receipt_id
     AND l.effet = 'purchase.order.to_receipt' AND l.etat = 'actif'
   LIMIT 1;
  IF v_exist IS NOT NULL THEN
    RAISE EXCEPTION 'La commande % est déjà rattachée à la réception %', v_o.number, v_r.number
      USING ERRCODE = 'unique_violation';
  END IF;

  -- 5. Le rattachement STOCKÉ (la colonne que personne n'écrivait).
  UPDATE goods_receipts SET purchase_order_id = p_order_id WHERE id = p_receipt_id;

  -- 6. LE LIEN : c'est lui qui rend la chaîne VISIBLE (I-01).
  PERFORM link_documents(
    v_o.tenant_id, 'purchase_orders', p_order_id, 'goods_receipts', p_receipt_id,
    'purchase.order.to_receipt', 'delivered_by');

  RETURN jsonb_build_object(
    'success', true, 'order_id', p_order_id, 'receipt_id', p_receipt_id,
    'order_number', v_o.number, 'receipt_number', v_r.number);
END $fn$;

COMMENT ON FUNCTION public.chain_l16_receipt_order(uuid, uuid) IS
  'L16/498 : chaîne achats commande d''achat → réception. Idempotent (rejeu refusé), cohérent (même fournisseur, statuts valides), tracé (link_documents, effet purchase.order.to_receipt). SECURITY DEFINER, borné à current_tenant_id().';

-- ── 4. Droits : jamais PUBLIC — la règle de la garde 228 T06 ───────────────
REVOKE ALL ON FUNCTION public.chain_l16_receipt_order(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chain_l16_receipt_order(uuid, uuid) TO authenticated;
