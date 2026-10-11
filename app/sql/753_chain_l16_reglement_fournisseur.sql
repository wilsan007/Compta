-- 753 — chain_l16_reglement_fournisseur
-- Numéro pris le 2026-10-11T05:20:03.523Z par migration-numero.mjs (ligne « plan6 A3 L16 (familles restantes) », branche plan6/a3-moteur).
-- ═══════════════════════════════════════════════════════════════════════════
-- 753 — L16 · le chaînage interne des ACHATS : le RÈGLEMENT d'une FACTURE
--       FOURNISSEUR lui est RATTACHÉ et TRACÉ
-- ═══════════════════════════════════════════════════════════════════════════
-- Le miroir fournisseur du lot `497` (facture client → règlement). La famille
-- Achats va « commande ↔ réception ↔ **facture ↔ règlement** ».
--
-- CE QUE LA MESURE A TROUVÉ AVANT D'ÉCRIRE (base neuve, 333 migrations) :
--   * `supplier_payments.purchase_invoice_id` et `invoice_number` EXISTENT — le
--     schéma portait le rattachement ; PERSONNE ne l'écrivait ;
--   * aucun contrat d'effet pour ce maillon, donc aucun maillon ;
--   * l'écran enregistre le paiement fournisseur sans le relier à sa facture.
--
-- CE QUE CE FICHIER POSE : le contrat d'effet `purchase.invoice.to_payment`, et
-- le maillon `chain_l16_supplier_invoice_payment` — idempotent (rejeu REFUSÉ),
-- réversible, tracé (`link_documents`, type `paid_by`, lisible par la Vue Chaîne).
--
-- ⚠️ LA COHÉRENCE EST VÉRIFIÉE, PAS SUPPOSÉE : le règlement et la facture visent
-- le MÊME fournisseur ; ni la facture ni le règlement ne sont annulés ; un
-- règlement déjà affecté à une AUTRE facture est refusé. Chaque refus dit sa raison.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Le CONTRAT d'effet (L7) : sans lui, la porte G2 refuse le maillon ───
INSERT INTO public.document_effects
  (tenant_id, document_type, evenement, effet, ecrit_comptable, journal_code,
   touche_stock, touche_paie, reversible, obligatoire, actif, note)
SELECT NULL, 'purchase_invoices', 'paid', 'purchase.invoice.to_payment', false, NULL,
       false, false, true, false, true,
       'L16/753 : une facture fournisseur est réglée, et le lien amont→aval vers le paiement est posé. L''écriture comptable est portée par le règlement (purchase.payment.generated_entry), pas par ce maillon. Réversible : fermer le lien.'
WHERE NOT EXISTS (
  SELECT 1 FROM public.document_effects
  WHERE document_type = 'purchase_invoices' AND evenement = 'paid' AND effet = 'purchase.invoice.to_payment'
);

-- ── 2. Le MAILLON : `chain_l16_supplier_invoice_payment` ───────────────────
CREATE OR REPLACE FUNCTION public.chain_l16_supplier_invoice_payment(p_invoice_id uuid, p_payment_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_f     purchase_invoices%ROWTYPE;
  v_p     supplier_payments%ROWTYPE;
  v_exist uuid;
BEGIN
  -- 1. La facture fournisseur, VERROUILLÉE et bornée à la société.
  SELECT * INTO v_f FROM purchase_invoices
   WHERE id = p_invoice_id AND tenant_id = current_tenant_id()
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Facture fournisseur introuvable (ou hors de votre société)' USING ERRCODE = 'no_data_found';
  END IF;

  -- 2. Le règlement, borné à la société.
  SELECT * INTO v_p FROM supplier_payments
   WHERE id = p_payment_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Règlement fournisseur introuvable (ou hors de votre société)' USING ERRCODE = 'no_data_found';
  END IF;

  -- 3. LES REFUS EXPLICITES : chaque refus porte sa raison.
  IF v_f.status = 'cancelled' THEN
    RAISE EXCEPTION 'Facture fournisseur % annulée : aucun règlement ne s''y rattache', v_f.number
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_p.status = 'cancelled' THEN
    RAISE EXCEPTION 'Règlement % annulé : rattachement impossible', v_p.number
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_p.supplier_id IS DISTINCT FROM v_f.supplier_id THEN
    RAISE EXCEPTION 'Le règlement % et la facture % ne visent pas le même fournisseur',
      v_p.number, v_f.number USING ERRCODE = 'check_violation';
  END IF;
  IF v_p.purchase_invoice_id IS NOT NULL AND v_p.purchase_invoice_id <> p_invoice_id THEN
    RAISE EXCEPTION 'Le règlement % est déjà affecté à une autre facture', v_p.number
      USING ERRCODE = 'unique_violation';
  END IF;

  -- 4. IDEMPOTENCE : deux lectures — la colonne que le schéma portait, ET le
  --    LIEN actif. Le rejeu est REFUSÉ, jamais silencieux.
  SELECT l.id INTO v_exist FROM document_links l
   WHERE l.tenant_id  = v_f.tenant_id
     AND l.amont_type = 'purchase_invoices'  AND l.amont_id = p_invoice_id
     AND l.aval_type  = 'supplier_payments'  AND l.aval_id  = p_payment_id
     AND l.effet = 'purchase.invoice.to_payment' AND l.etat = 'actif'
   LIMIT 1;
  IF v_exist IS NOT NULL THEN
    RAISE EXCEPTION 'La facture % est déjà réglée par le règlement %', v_f.number, v_p.number
      USING ERRCODE = 'unique_violation';
  END IF;

  -- 5. Le rattachement STOCKÉ (la colonne que personne n'écrivait).
  UPDATE supplier_payments SET purchase_invoice_id = p_invoice_id WHERE id = p_payment_id;

  -- 6. LE LIEN : c'est lui qui rend la chaîne VISIBLE (I-01).
  PERFORM link_documents(
    v_f.tenant_id, 'purchase_invoices', p_invoice_id, 'supplier_payments', p_payment_id,
    'purchase.invoice.to_payment', 'paid_by');

  RETURN jsonb_build_object(
    'success', true, 'invoice_id', p_invoice_id, 'payment_id', p_payment_id,
    'invoice_number', v_f.number, 'payment_number', v_p.number);
END $fn$;

COMMENT ON FUNCTION public.chain_l16_supplier_invoice_payment(uuid, uuid) IS
  'L16/753 : chaîne achats facture fournisseur → règlement. Idempotent (rejeu refusé), cohérent (même fournisseur, statuts valides), tracé (link_documents, effet purchase.invoice.to_payment). SECURITY DEFINER, borné à current_tenant_id().';

-- ── 3. Droits : jamais PUBLIC — la règle de la garde 228 T06 ───────────────
REVOKE ALL ON FUNCTION public.chain_l16_supplier_invoice_payment(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chain_l16_supplier_invoice_payment(uuid, uuid) TO authenticated;
