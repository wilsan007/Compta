-- 755 — chain_l16_reception_facturefournisseur
-- Numéro pris le 2026-10-11T05:51:39.024Z par migration-numero.mjs (ligne « plan6 A3 L16 (familles restantes) », branche plan6/a3-moteur).
-- ═══════════════════════════════════════════════════════════════════════════
-- 755 — L16 · le chaînage interne des ACHATS : la FACTURE FOURNISSEUR d'une
--       RÉCEPTION lui est RATTACHÉE et TRACÉE
-- ═══════════════════════════════════════════════════════════════════════════
-- La famille Achats va « commande ↔ réception ↔ **facture ↔ règlement** ». Le lot
-- `498` a fermé commande → réception, le lot `753` facture → règlement. Voici
-- réception → facture fournisseur.
--
-- CE QUE LA MESURE A TROUVÉ AVANT D'ÉCRIRE (base neuve, 333 migrations) :
--   * `purchase_invoices.goods_receipt_id` EXISTE, et il est **LU par le
--     rapprochement trois points** (`check_three_way_match`, 135 puis 148, qui le
--     lit pour confronter facture, commande et réception) — mais **PERSONNE ne
--     l'écrit** : mesuré, aucun `INSERT`/`UPDATE` de `app/sql` ne le pose. Le
--     rapprochement tourne donc à vide ;
--   * aucun contrat d'effet `purchase.receipt.to_invoice`, donc aucun maillon.
--
-- CE QUE CE FICHIER POSE : le contrat d'effet `purchase.receipt.to_invoice`, et le
-- maillon `chain_l16_receipt_supplier_invoice` — idempotent (rejeu REFUSÉ),
-- réversible, tracé (`link_documents`, type `invoiced_by`, lisible par la Vue
-- Chaîne). Il ÉCRIT `goods_receipt_id`, ce qui **donne au rapprochement trois
-- points la réception qu'il cherchait**.
--
-- ⚠️ LA COHÉRENCE EST VÉRIFIÉE, PAS SUPPOSÉE : la réception et la facture visent
-- le MÊME fournisseur ; ni l'une ni l'autre n'est annulée ; une facture déjà
-- rattachée à une AUTRE réception est refusée.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Le CONTRAT d'effet (L7) : sans lui, la porte G2 refuse le maillon ───
INSERT INTO public.document_effects
  (tenant_id, document_type, evenement, effet, ecrit_comptable, journal_code,
   touche_stock, touche_paie, reversible, obligatoire, actif, note)
SELECT NULL, 'goods_receipts', 'invoiced', 'purchase.receipt.to_invoice', false, NULL,
       false, false, true, false, true,
       'L16/755 : une réception est facturée par une facture fournisseur, et le lien amont→aval est posé. L''écriture comptable est portée par la facture (purchase.invoice.generated_entry) ; l''entrée de stock est déjà portée par la réception (purchase.receipt.stock_in). Réversible : fermer le lien.'
WHERE NOT EXISTS (
  SELECT 1 FROM public.document_effects
  WHERE document_type = 'goods_receipts' AND evenement = 'invoiced' AND effet = 'purchase.receipt.to_invoice'
);

-- ── 2. Le MAILLON : `chain_l16_receipt_supplier_invoice` ───────────────────
CREATE OR REPLACE FUNCTION public.chain_l16_receipt_supplier_invoice(p_receipt_id uuid, p_invoice_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_r     goods_receipts%ROWTYPE;
  v_f     purchase_invoices%ROWTYPE;
  v_exist uuid;
BEGIN
  -- 1. La réception, VERROUILLÉE et bornée à la société.
  SELECT * INTO v_r FROM goods_receipts
   WHERE id = p_receipt_id AND tenant_id = current_tenant_id()
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Réception introuvable (ou hors de votre société)' USING ERRCODE = 'no_data_found';
  END IF;

  -- 2. La facture fournisseur, bornée à la société.
  SELECT * INTO v_f FROM purchase_invoices
   WHERE id = p_invoice_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Facture fournisseur introuvable (ou hors de votre société)' USING ERRCODE = 'no_data_found';
  END IF;

  -- 3. LES REFUS EXPLICITES : chaque refus porte sa raison.
  IF v_r.status = 'cancelled' THEN
    RAISE EXCEPTION 'Réception % annulée : aucune facture ne s''y rattache', v_r.number
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_f.status = 'cancelled' THEN
    RAISE EXCEPTION 'Facture fournisseur % annulée : rattachement impossible', v_f.number
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_f.supplier_id IS DISTINCT FROM v_r.supplier_id THEN
    RAISE EXCEPTION 'La facture % et la réception % ne visent pas le même fournisseur',
      v_f.number, v_r.number USING ERRCODE = 'check_violation';
  END IF;
  IF v_f.goods_receipt_id IS NOT NULL AND v_f.goods_receipt_id <> p_receipt_id THEN
    RAISE EXCEPTION 'La facture % est déjà rattachée à une autre réception', v_f.number
      USING ERRCODE = 'unique_violation';
  END IF;

  -- 4. IDEMPOTENCE : deux lectures — la colonne que le schéma portait, ET le LIEN
  --    actif. Le rejeu est REFUSÉ, jamais silencieux.
  SELECT l.id INTO v_exist FROM document_links l
   WHERE l.tenant_id  = v_r.tenant_id
     AND l.amont_type = 'goods_receipts'    AND l.amont_id = p_receipt_id
     AND l.aval_type  = 'purchase_invoices' AND l.aval_id  = p_invoice_id
     AND l.effet = 'purchase.receipt.to_invoice' AND l.etat = 'actif'
   LIMIT 1;
  IF v_exist IS NOT NULL THEN
    RAISE EXCEPTION 'La réception % est déjà facturée par la facture %', v_r.number, v_f.number
      USING ERRCODE = 'unique_violation';
  END IF;

  -- 5. Le rattachement STOCKÉ (la colonne que le rapprochement trois points LIT
  --    sans que personne ne l'écrive).
  UPDATE purchase_invoices SET goods_receipt_id = p_receipt_id WHERE id = p_invoice_id;

  -- 6. LE LIEN : c'est lui qui rend la chaîne VISIBLE (I-01).
  PERFORM link_documents(
    v_r.tenant_id, 'goods_receipts', p_receipt_id, 'purchase_invoices', p_invoice_id,
    'purchase.receipt.to_invoice', 'invoiced_by');

  RETURN jsonb_build_object(
    'success', true, 'receipt_id', p_receipt_id, 'invoice_id', p_invoice_id,
    'receipt_number', v_r.number, 'invoice_number', v_f.number);
END $fn$;

COMMENT ON FUNCTION public.chain_l16_receipt_supplier_invoice(uuid, uuid) IS
  'L16/755 : chaîne achats réception → facture fournisseur. Idempotent (rejeu refusé), cohérent (même fournisseur, statuts valides), ÉCRIT purchase_invoices.goods_receipt_id (lue par le rapprochement trois points), tracé (link_documents, effet purchase.receipt.to_invoice). SECURITY DEFINER, borné à current_tenant_id().';

-- ── 3. Droits : jamais PUBLIC — la règle de la garde 228 T06 ───────────────
REVOKE ALL ON FUNCTION public.chain_l16_receipt_supplier_invoice(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chain_l16_receipt_supplier_invoice(uuid, uuid) TO authenticated;
