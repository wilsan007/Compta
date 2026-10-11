-- 754 — chain_l16_facture_avoir
-- Numéro pris le 2026-10-11T05:36:58.815Z par migration-numero.mjs (ligne « plan6 A3 L16 (familles restantes) », branche plan6/a3-moteur).
-- ═══════════════════════════════════════════════════════════════════════════
-- 754 — L16 · le chaînage interne du COMMERCIAL (tronçon 5) : l'AVOIR qui
--       annule une FACTURE lui est RATTACHÉ et TRACÉ
-- ═══════════════════════════════════════════════════════════════════════════
-- Suite du lot `495` (livraison → facture) : voici facture → avoir
-- (« §B.3 : … facture ↔ avoir ↔ règlement ↔ relance »).
--
-- ⏸️ CE LOT A ÉTÉ **DIFFÉRÉ** une première fois (numéro `498` rendu) : sa SUITE
-- se heurtait aux gardes de validation (`credit_note_guard` 213 impose « un avoir
-- est créé en brouillon PUIS validé » et exige la facture d'origine validée ; or
-- `invoice_guard` 190 refuse de valider une facture SANS ligne). Le harnais a été
-- monté pour le lot `753` (facture fournisseur approuvée) et sert ici : la suite
-- construit **facture validée (avec ligne) → avoir validé**, et le tronçon ferme.
--
-- CE QUE LA MESURE A TROUVÉ AVANT D'ÉCRIRE (base neuve, 333 migrations) :
--   * `credit_notes.invoice_id` EXISTE (clé composite 237) et le trigger `213` le
--     remplit depuis `source_invoice_id` — mais AUCUN lien de chaîne
--     (`document_links`) n'est posé : l'avoir reste invisible pour la frise ;
--   * aucun contrat d'effet, donc aucun maillon.
--
-- CE QUE CE FICHIER POSE : le contrat d'effet `sale.invoice.to_credit_note`, et
-- le maillon `chain_l16_invoice_credit_note` — idempotent (rejeu REFUSÉ),
-- réversible, tracé (`link_documents`, type `reversed_by`, lisible par la Vue
-- Chaîne).
--
-- ⚠️ IL NE RÉÉCRIT PAS `credit_notes.invoice_id` : le trigger `213` l'a déjà posé
-- depuis `source_invoice_id`, et la garde refuse toute modification d'un avoir
-- validé. Le maillon LIT la colonne (cohérence) et pose le LIEN.
--
-- ⚠️ LE STATUT DE LA FACTURE N'EST PAS UN REFUS : un avoir qui la crédite en
-- entier la fait **légitimement** passer à `cancelled` (`refresh_invoice_settlement`)
-- — refuser ce cas bloquerait le geste normal. Le lien est une TRACE : plusieurs
-- avoirs partiels peuvent s'y rattacher, et la garde `213` refuse déjà l'avoir de
-- trop (total > reste à créditer).
--
-- ⚠️ LA COHÉRENCE EST VÉRIFIÉE, PAS SUPPOSÉE : l'avoir n'est pas un BROUILLON
-- (un brouillon n'annule rien), ils visent le MÊME client, et un avoir qui annule
-- DÉJÀ une autre facture est refusé.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Le CONTRAT d'effet (L7) : sans lui, la porte G2 refuse le maillon ───
INSERT INTO public.document_effects
  (tenant_id, document_type, evenement, effet, ecrit_comptable, journal_code,
   touche_stock, touche_paie, reversible, obligatoire, actif, note)
SELECT NULL, 'invoices', 'reversed', 'sale.invoice.to_credit_note', false, NULL,
       false, false, true, false, true,
       'L16/754 : une facture client est annulée par un avoir, et le lien amont→aval est posé. L''écriture de l''avoir est portée par le trigger 213 (sale.credit_note.generated_entry), pas par ce maillon. Réversible : fermer le lien.'
WHERE NOT EXISTS (
  SELECT 1 FROM public.document_effects
  WHERE document_type = 'invoices' AND evenement = 'reversed' AND effet = 'sale.invoice.to_credit_note'
);

-- ── 2. Le MAILLON : `chain_l16_invoice_credit_note` ────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l16_invoice_credit_note(p_invoice_id uuid, p_credit_note_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_f     invoices%ROWTYPE;
  v_a     credit_notes%ROWTYPE;
  v_exist uuid;
BEGIN
  -- 1. La facture, VERROUILLÉE et bornée à la société.
  SELECT * INTO v_f FROM invoices
   WHERE id = p_invoice_id AND tenant_id = current_tenant_id()
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Facture introuvable (ou hors de votre société)' USING ERRCODE = 'no_data_found';
  END IF;

  -- 2. L'avoir, borné à la société.
  SELECT * INTO v_a FROM credit_notes
   WHERE id = p_credit_note_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Avoir introuvable (ou hors de votre société)' USING ERRCODE = 'no_data_found';
  END IF;

  -- 3. LES REFUS EXPLICITES : chaque refus porte sa raison.
  IF v_a.status = 'draft' THEN
    RAISE EXCEPTION 'Avoir % en brouillon : un brouillon n''annule rien', v_a.number
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_a.customer_id IS DISTINCT FROM v_f.customer_id THEN
    RAISE EXCEPTION 'L''avoir % et la facture % ne visent pas le même client',
      v_a.number, v_f.number USING ERRCODE = 'check_violation';
  END IF;
  IF v_a.invoice_id IS NOT NULL AND v_a.invoice_id <> p_invoice_id THEN
    RAISE EXCEPTION 'L''avoir % annule déjà une autre facture', v_a.number
      USING ERRCODE = 'unique_violation';
  END IF;

  -- 4. IDEMPOTENCE : le LIEN actif fait foi pour la frise. Le rejeu est REFUSÉ.
  SELECT l.id INTO v_exist FROM document_links l
   WHERE l.tenant_id  = v_f.tenant_id
     AND l.amont_type = 'invoices'     AND l.amont_id = p_invoice_id
     AND l.aval_type  = 'credit_notes' AND l.aval_id  = p_credit_note_id
     AND l.effet = 'sale.invoice.to_credit_note' AND l.etat = 'actif'
   LIMIT 1;
  IF v_exist IS NOT NULL THEN
    RAISE EXCEPTION 'La facture % est déjà annulée par l''avoir %', v_f.number, v_a.number
      USING ERRCODE = 'unique_violation';
  END IF;

  -- 5. LE LIEN : c'est lui qui rend la chaîne VISIBLE (I-01). Aucune colonne n'est
  --    réécrite : `credit_notes.invoice_id` est déjà posée par le trigger 213, et
  --    la garde refuse de modifier un avoir validé.
  PERFORM link_documents(
    v_f.tenant_id, 'invoices', p_invoice_id, 'credit_notes', p_credit_note_id,
    'sale.invoice.to_credit_note', 'reversed_by');

  RETURN jsonb_build_object(
    'success', true, 'invoice_id', p_invoice_id, 'credit_note_id', p_credit_note_id,
    'invoice_number', v_f.number, 'credit_note_number', v_a.number);
END $fn$;

COMMENT ON FUNCTION public.chain_l16_invoice_credit_note(uuid, uuid) IS
  'L16/754 : chaîne commerciale facture → avoir. Idempotent (rejeu refusé), cohérent (même client, statuts valides), tracé (link_documents, effet sale.invoice.to_credit_note). Ne réécrit pas credit_notes.invoice_id (posée par le trigger 213). SECURITY DEFINER, borné à current_tenant_id().';

-- ── 3. Droits : jamais PUBLIC — la règle de la garde 228 T06 ───────────────
REVOKE ALL ON FUNCTION public.chain_l16_invoice_credit_note(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chain_l16_invoice_credit_note(uuid, uuid) TO authenticated;
