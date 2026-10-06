-- 497 — chain_l16_facture_reglement
-- Numéro pris le 2026-10-05T21:09:59.658Z par migration-numero.mjs (ligne « plan6 A3 (moteur L16-L24) », branche plan6/a3-moteur).
-- ═══════════════════════════════════════════════════════════════════════════
-- 497 — L16 · le chaînage interne du COMMERCIAL (tronçon 4) : le RÈGLEMENT
--       d'une FACTURE lui est RATTACHÉ et TRACÉ
-- ═══════════════════════════════════════════════════════════════════════════
-- Suite du tronçon `495` : après livraison → facture, voici facture → règlement
-- (« §B.3 : … facture ↔ avoir ↔ règlement ↔ relance »).
--
-- CE QUE LA MESURE A TROUVÉ AVANT D'ÉCRIRE (base neuve, 333 migrations) :
--   * `customer_payments.invoice_id` et `customer_payments.invoice_number`
--     EXISTENT — le schéma portait le rattachement ; PERSONNE ne l'écrivait ;
--   * aucun contrat d'effet pour ce maillon, donc aucun maillon ;
--   * l'écran enregistre l'encaissement sans le relier à sa facture.
--
-- CE QUE CE FICHIER POSE : le contrat d'effet `sale.invoice.to_payment`, et le
-- maillon `chain_l16_invoice_payment` — idempotent (une facture ne se rattache
-- qu'UNE fois à un règlement donné ; le rejeu est REFUSÉ), réversible (le lien
-- peut être fermé) et tracé (`link_documents`, type `paid_by`, lisible par la
-- Vue Chaîne).
--
-- ⚠️ LA COHÉRENCE EST VÉRIFIÉE, PAS SUPPOSÉE : le règlement et la facture
-- visent le MÊME client ; ni la facture ni le règlement ne sont annulés ; un
-- règlement déjà affecté à une AUTRE facture est refusé. Chaque refus dit sa raison.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Le CONTRAT d'effet (L7) : sans lui, la porte G2 refuse le maillon ───
INSERT INTO public.document_effects
  (tenant_id, document_type, evenement, effet, ecrit_comptable, journal_code,
   touche_stock, touche_paie, reversible, obligatoire, actif, note)
SELECT NULL, 'invoices', 'paid', 'sale.invoice.to_payment', false, NULL,
       false, false, true, false, true,
       'L16/497 : une facture client est réglée, et le lien amont→aval vers l''encaissement est posé. L''écriture comptable est portée par le règlement (sale.payment.generated_entry), pas par ce maillon. Réversible : fermer le lien.'
WHERE NOT EXISTS (
  SELECT 1 FROM public.document_effects
  WHERE document_type = 'invoices' AND evenement = 'paid' AND effet = 'sale.invoice.to_payment'
);

-- ── 2. Le MAILLON : `chain_l16_invoice_payment` ────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l16_invoice_payment(p_invoice_id uuid, p_payment_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_f     invoices%ROWTYPE;
  v_p     customer_payments%ROWTYPE;
  v_exist uuid;
BEGIN
  -- 1. La facture, VERROUILLÉE et bornée à la société.
  SELECT * INTO v_f FROM invoices
   WHERE id = p_invoice_id AND tenant_id = current_tenant_id()
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Facture introuvable (ou hors de votre société)' USING ERRCODE = 'no_data_found';
  END IF;

  -- 2. Le règlement, borné à la société.
  SELECT * INTO v_p FROM customer_payments
   WHERE id = p_payment_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Règlement introuvable (ou hors de votre société)' USING ERRCODE = 'no_data_found';
  END IF;

  -- 3. LES REFUS EXPLICITES : chaque refus porte sa raison.
  IF v_f.status = 'cancelled' THEN
    RAISE EXCEPTION 'Facture % annulée : aucun règlement ne s''y rattache', v_f.number
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_p.status = 'cancelled' THEN
    RAISE EXCEPTION 'Règlement % annulé : rattachement impossible', v_p.number
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_p.customer_id IS DISTINCT FROM v_f.customer_id THEN
    RAISE EXCEPTION 'Le règlement % et la facture % ne visent pas le même client',
      v_p.number, v_f.number USING ERRCODE = 'check_violation';
  END IF;
  IF v_p.invoice_id IS NOT NULL AND v_p.invoice_id <> p_invoice_id THEN
    RAISE EXCEPTION 'Le règlement % est déjà affecté à une autre facture', v_p.number
      USING ERRCODE = 'unique_violation';
  END IF;

  -- 4. IDEMPOTENCE : deux lectures — la colonne que le schéma portait, ET le
  --    LIEN actif. Le rejeu est REFUSÉ, jamais silencieux.
  SELECT l.id INTO v_exist FROM document_links l
   WHERE l.tenant_id  = v_f.tenant_id
     AND l.amont_type = 'invoices'          AND l.amont_id = p_invoice_id
     AND l.aval_type  = 'customer_payments' AND l.aval_id  = p_payment_id
     AND l.effet = 'sale.invoice.to_payment' AND l.etat = 'actif'
   LIMIT 1;
  IF v_exist IS NOT NULL THEN
    RAISE EXCEPTION 'La facture % est déjà réglée par le règlement %', v_f.number, v_p.number
      USING ERRCODE = 'unique_violation';
  END IF;

  -- 5. Le rattachement STOCKÉ (la colonne que personne n'écrivait).
  UPDATE customer_payments SET invoice_id = p_invoice_id WHERE id = p_payment_id;

  -- 6. LE LIEN : c'est lui qui rend la chaîne VISIBLE (I-01).
  PERFORM link_documents(
    v_f.tenant_id, 'invoices', p_invoice_id, 'customer_payments', p_payment_id,
    'sale.invoice.to_payment', 'paid_by');

  RETURN jsonb_build_object(
    'success', true, 'invoice_id', p_invoice_id, 'payment_id', p_payment_id,
    'invoice_number', v_f.number, 'payment_number', v_p.number);
END $fn$;

COMMENT ON FUNCTION public.chain_l16_invoice_payment(uuid, uuid) IS
  'L16/497 : chaîne commerciale facture → règlement. Idempotent (rejeu refusé), cohérent (même client, statuts valides), tracé (link_documents, effet sale.invoice.to_payment). SECURITY DEFINER, borné à current_tenant_id().';

-- ── 3. Droits : jamais PUBLIC — la règle de la garde 228 T06 ───────────────
REVOKE ALL ON FUNCTION public.chain_l16_invoice_payment(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chain_l16_invoice_payment(uuid, uuid) TO authenticated;
