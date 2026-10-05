-- 495 — chain_l16_livraison_facture
-- Numéro pris le 2026-10-05T20:48:17.125Z par migration-numero.mjs (ligne « plan6 A3 (moteur L16-L24) », branche plan6/a3-moteur).
-- ═══════════════════════════════════════════════════════════════════════════
-- 495 — L16 · le chaînage interne du COMMERCIAL (tronçon 3) : la FACTURE
--       d'un bon de livraison lui est RATTACHÉE et TRACÉE
-- ═══════════════════════════════════════════════════════════════════════════
-- Suite du tronçon `494` : après devis → commande → livraison, voici
-- livraison → facture (« §B.3 : livraison ↔ facture »).
--
-- CE QUE LA MESURE A TROUVÉ AVANT D'ÉCRIRE (base neuve, 333 migrations) :
--   * `invoices.delivery_note_id` et `invoice_lines.delivery_note_line_id`
--     EXISTENT — le schéma portait le rattachement ; PERSONNE ne l'écrivait ;
--   * aucun contrat d'effet pour ce maillon, donc aucun maillon ;
--   * l'écran crée la facture sans jamais la relier au bon qu'elle facture.
--
-- CE QUE CE FICHIER POSE : le contrat d'effet `sale.delivery.to_invoice`, et le
-- maillon `chain_l16_delivery_invoice` — idempotent (un bon ne se rattache
-- qu'UNE fois ; le rejeu est REFUSÉ), réversible (le lien peut être fermé) et
-- tracé (`link_documents`, type `invoiced_by`, donc lisible par la Vue Chaîne).
--
-- ⚠️ LA COHÉRENCE EST VÉRIFIÉE, PAS SUPPOSÉE : la facture et le bon visent le
-- MÊME client ; ni la facture ni le bon ne sont annulés ; un bon déjà facturé
-- par une AUTRE facture est refusé. Chaque refus porte sa raison.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Le CONTRAT d'effet (L7) : sans lui, la porte G2 refuse le maillon ───
INSERT INTO public.document_effects
  (tenant_id, document_type, evenement, effet, ecrit_comptable, journal_code,
   touche_stock, touche_paie, reversible, obligatoire, actif, note)
SELECT NULL, 'delivery_notes', 'invoiced', 'sale.delivery.to_invoice', false, NULL,
       false, false, true, false, true,
       'L16/495 : un bon de livraison est facturé, et le lien amont→aval vers la facture est posé. L''écriture comptable est portée par la facture (sale.invoice.generated_entry), pas par ce maillon. Réversible : fermer le lien.'
WHERE NOT EXISTS (
  SELECT 1 FROM public.document_effects
  WHERE document_type = 'delivery_notes' AND evenement = 'invoiced' AND effet = 'sale.delivery.to_invoice'
);

-- ── 2. Le MAILLON : `chain_l16_delivery_invoice` ───────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l16_delivery_invoice(p_delivery_id uuid, p_invoice_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_d     delivery_notes%ROWTYPE;
  v_f     invoices%ROWTYPE;
  v_exist uuid;
BEGIN
  -- 1. Le bon de livraison, VERROUILLÉ et borné à la société.
  SELECT * INTO v_d FROM delivery_notes
   WHERE id = p_delivery_id AND tenant_id = current_tenant_id()
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bon de livraison introuvable (ou hors de votre société)' USING ERRCODE = 'no_data_found';
  END IF;

  -- 2. La facture, bornée à la société.
  SELECT * INTO v_f FROM invoices
   WHERE id = p_invoice_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Facture introuvable (ou hors de votre société)' USING ERRCODE = 'no_data_found';
  END IF;

  -- 3. LES REFUS EXPLICITES : chaque refus porte sa raison.
  IF v_d.status IN ('cancelled', 'returned') THEN
    RAISE EXCEPTION 'Bon de livraison % % : facturation impossible', v_d.number, v_d.status
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_f.status = 'cancelled' THEN
    RAISE EXCEPTION 'Facture % annulée : rattachement impossible', v_f.number
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_f.customer_id IS DISTINCT FROM v_d.customer_id THEN
    RAISE EXCEPTION 'La facture % et le bon de livraison % ne visent pas le même client',
      v_f.number, v_d.number USING ERRCODE = 'check_violation';
  END IF;
  IF v_f.delivery_note_id IS NOT NULL AND v_f.delivery_note_id <> p_delivery_id THEN
    RAISE EXCEPTION 'La facture % est déjà rattachée à un autre bon de livraison', v_f.number
      USING ERRCODE = 'unique_violation';
  END IF;

  -- 4. IDEMPOTENCE : deux lectures — la colonne que le schéma portait, ET le
  --    LIEN actif. Le rejeu est REFUSÉ, jamais silencieux.
  SELECT l.id INTO v_exist FROM document_links l
   WHERE l.tenant_id  = v_d.tenant_id
     AND l.amont_type = 'delivery_notes' AND l.amont_id = p_delivery_id
     AND l.aval_type  = 'invoices'       AND l.aval_id  = p_invoice_id
     AND l.effet = 'sale.delivery.to_invoice' AND l.etat = 'actif'
   LIMIT 1;
  IF v_exist IS NOT NULL THEN
    RAISE EXCEPTION 'Le bon % est déjà facturé par la facture %', v_d.number, v_f.number
      USING ERRCODE = 'unique_violation';
  END IF;

  -- 5. Le rattachement STOCKÉ (la colonne que personne n'écrivait).
  UPDATE invoices SET delivery_note_id = p_delivery_id WHERE id = p_invoice_id;

  -- 6. LE LIEN : c'est lui qui rend la chaîne VISIBLE (I-01).
  PERFORM link_documents(
    v_d.tenant_id, 'delivery_notes', p_delivery_id, 'invoices', p_invoice_id,
    'sale.delivery.to_invoice', 'invoiced_by');

  RETURN jsonb_build_object(
    'success', true, 'delivery_id', p_delivery_id, 'invoice_id', p_invoice_id,
    'delivery_number', v_d.number, 'invoice_number', v_f.number);
END $fn$;

COMMENT ON FUNCTION public.chain_l16_delivery_invoice(uuid, uuid) IS
  'L16/495 : chaîne commerciale livraison → facture. Idempotent (rejeu refusé), cohérent (même client, statuts valides), tracé (link_documents, effet sale.delivery.to_invoice). SECURITY DEFINER, borné à current_tenant_id().';

-- ── 3. Droits : jamais PUBLIC — la règle de la garde 228 T06 ───────────────
REVOKE ALL ON FUNCTION public.chain_l16_delivery_invoice(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chain_l16_delivery_invoice(uuid, uuid) TO authenticated;
