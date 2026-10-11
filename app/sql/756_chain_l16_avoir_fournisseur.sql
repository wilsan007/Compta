-- 756 — chain_l16_avoir_fournisseur
-- Numéro pris le 2026-10-11T06:00:53.973Z par migration-numero.mjs (ligne « plan6 A3 L16 (familles restantes) », branche plan6/a3-moteur).
-- ═══════════════════════════════════════════════════════════════════════════
-- 756 — L16 · le chaînage interne des ACHATS : l'AVOIR FOURNISSEUR qui annule
--       une FACTURE FOURNISSEUR lui est RATTACHÉ et TRACÉ
-- ═══════════════════════════════════════════════════════════════════════════
-- Le miroir achats du lot `754` (avoir client), et le dernier tronçon de la
-- famille Achats — « commande ↔ réception ↔ facture ↔ **avoir** ↔ règlement ».
--
-- CE QUE LA MESURE A TROUVÉ AVANT D'ÉCRIRE (base neuve, 333 migrations) :
--   * `purchase_credit_notes.purchase_invoice_id` EXISTE et son trigger (`192`)
--     l'utilise pour valider (« la facture d'origine doit être approuvée ») — mais
--     AUCUN lien de chaîne (`document_links`) n'est posé : l'avoir fournisseur
--     reste invisible pour la frise ;
--   * `purchase_credit_notes` n'est PAS au registre `chain_document_types` : un lien
--     vers un avoir fournisseur aurait été REFUSÉ (451). C'est le premier objet ;
--   * aucun contrat d'effet, donc aucun maillon.
--
-- CE QUE CE FICHIER POSE : le type `purchase_credit_notes` au registre, le contrat
-- d'effet `purchase.invoice.to_credit_note`, et le maillon
-- `chain_l16_supplier_invoice_credit_note` — idempotent (rejeu REFUSÉ), réversible,
-- tracé (`link_documents`, type `reversed_by`).
--
-- ⚠️ IL NE RÉÉCRIT PAS `purchase_credit_notes.purchase_invoice_id` : le trigger
-- `192` refuse de modifier un avoir validé, et la colonne est déjà posée. Le
-- maillon LIT la colonne (cohérence) et pose le LIEN.
--
-- ⚠️ LE STATUT DE LA FACTURE N'EST PAS UN REFUS (même décision qu'au lot `754`) :
-- un avoir qui crédite la facture en entier la fait **légitimement** passer à
-- `cancelled` (`refresh_purchase_invoice_settlement`).
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Le registre accueille l'AVOIR FOURNISSEUR ───────────────────────────
INSERT INTO public.chain_document_types (code, table_name, ligne_table, libelle_fr) VALUES
  ('purchase_credit_notes', 'purchase_credit_notes', 'purchase_credit_lines', 'Avoir fournisseur')
ON CONFLICT (code) DO UPDATE SET
  table_name  = EXCLUDED.table_name,
  ligne_table = EXCLUDED.ligne_table,
  libelle_fr  = EXCLUDED.libelle_fr;

-- ── 2. Le CONTRAT d'effet (L7) : sans lui, la porte G2 refuse le maillon ───
INSERT INTO public.document_effects
  (tenant_id, document_type, evenement, effet, ecrit_comptable, journal_code,
   touche_stock, touche_paie, reversible, obligatoire, actif, note)
SELECT NULL, 'purchase_invoices', 'reversed', 'purchase.invoice.to_credit_note', false, NULL,
       false, false, true, false, true,
       'L16/756 : une facture fournisseur est annulée par un avoir, et le lien amont→aval est posé. L''écriture de l''avoir est portée par le trigger 192, pas par ce maillon. Réversible : fermer le lien.'
WHERE NOT EXISTS (
  SELECT 1 FROM public.document_effects
  WHERE document_type = 'purchase_invoices' AND evenement = 'reversed' AND effet = 'purchase.invoice.to_credit_note'
);

-- ── 3. Le MAILLON : `chain_l16_supplier_invoice_credit_note` ───────────────
CREATE OR REPLACE FUNCTION public.chain_l16_supplier_invoice_credit_note(p_invoice_id uuid, p_credit_note_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_f     purchase_invoices%ROWTYPE;
  v_a     purchase_credit_notes%ROWTYPE;
  v_exist uuid;
BEGIN
  -- 1. La facture fournisseur, VERROUILLÉE et bornée à la société.
  SELECT * INTO v_f FROM purchase_invoices
   WHERE id = p_invoice_id AND tenant_id = current_tenant_id()
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Facture fournisseur introuvable (ou hors de votre société)' USING ERRCODE = 'no_data_found';
  END IF;

  -- 2. L'avoir fournisseur, borné à la société.
  SELECT * INTO v_a FROM purchase_credit_notes
   WHERE id = p_credit_note_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Avoir fournisseur introuvable (ou hors de votre société)' USING ERRCODE = 'no_data_found';
  END IF;

  -- 3. LES REFUS EXPLICITES : chaque refus porte sa raison.
  IF v_a.status = 'draft' THEN
    RAISE EXCEPTION 'Avoir fournisseur % en brouillon : un brouillon n''annule rien', v_a.number
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_a.supplier_id IS NOT NULL AND v_a.supplier_id IS DISTINCT FROM v_f.supplier_id THEN
    RAISE EXCEPTION 'L''avoir % et la facture % ne visent pas le même fournisseur',
      v_a.number, v_f.number USING ERRCODE = 'check_violation';
  END IF;
  IF v_a.purchase_invoice_id IS NOT NULL AND v_a.purchase_invoice_id <> p_invoice_id THEN
    RAISE EXCEPTION 'L''avoir % annule déjà une autre facture', v_a.number
      USING ERRCODE = 'unique_violation';
  END IF;

  -- 4. IDEMPOTENCE : le LIEN actif fait foi pour la frise. Le rejeu est REFUSÉ.
  SELECT l.id INTO v_exist FROM document_links l
   WHERE l.tenant_id  = v_f.tenant_id
     AND l.amont_type = 'purchase_invoices'      AND l.amont_id = p_invoice_id
     AND l.aval_type  = 'purchase_credit_notes'  AND l.aval_id  = p_credit_note_id
     AND l.effet = 'purchase.invoice.to_credit_note' AND l.etat = 'actif'
   LIMIT 1;
  IF v_exist IS NOT NULL THEN
    RAISE EXCEPTION 'La facture % est déjà annulée par l''avoir %', v_f.number, v_a.number
      USING ERRCODE = 'unique_violation';
  END IF;

  -- 5. LE LIEN : c'est lui qui rend la chaîne VISIBLE (I-01). Aucune colonne n'est
  --    réécrite : `purchase_credit_notes.purchase_invoice_id` est déjà posée, et la
  --    garde 192 refuse de modifier un avoir validé.
  PERFORM link_documents(
    v_f.tenant_id, 'purchase_invoices', p_invoice_id, 'purchase_credit_notes', p_credit_note_id,
    'purchase.invoice.to_credit_note', 'reversed_by');

  RETURN jsonb_build_object(
    'success', true, 'invoice_id', p_invoice_id, 'credit_note_id', p_credit_note_id,
    'invoice_number', v_f.number, 'credit_note_number', v_a.number);
END $fn$;

COMMENT ON FUNCTION public.chain_l16_supplier_invoice_credit_note(uuid, uuid) IS
  'L16/756 : chaîne achats facture fournisseur → avoir. Idempotent (rejeu refusé), cohérent (même fournisseur, statuts valides), tracé (link_documents, effet purchase.invoice.to_credit_note). Ne réécrit pas purchase_invoice_id (posée par le trigger 192). SECURITY DEFINER, borné à current_tenant_id().';

-- ── 4. Droits : jamais PUBLIC — la règle de la garde 228 T06 ───────────────
REVOKE ALL ON FUNCTION public.chain_l16_supplier_invoice_credit_note(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chain_l16_supplier_invoice_credit_note(uuid, uuid) TO authenticated;
