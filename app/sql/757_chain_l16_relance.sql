-- 757 — chain_l16_relance
-- Numéro pris le 2026-10-11T06:28:20.954Z par migration-numero.mjs (ligne « plan6 A3 L16 (familles restantes) », branche plan6/a3-moteur).
-- ═══════════════════════════════════════════════════════════════════════════
-- 757 — L16 · le chaînage interne du COMMERCIAL : la RELANCE d'une FACTURE lui
--       est RATTACHÉE et TRACÉE
-- ═══════════════════════════════════════════════════════════════════════════
-- La famille Commercial va « devis ↔ commande ↔ livraison ↔ facture ↔ avoir ↔
-- règlement ↔ **relance** ». Les lots `493` → `497`, `754` ont fermé le reste ;
-- voici la relance.
--
-- CE QUE LA MESURE A TROUVÉ AVANT D'ÉCRIRE (base neuve, 333 migrations) :
--   * `collection_reminders` EXISTE (la relance, réparée par W6/`258` : statuts,
--     idempotence, lien de paiement) et `collection_reminders.invoice_id` EXISTE —
--     mais **AUCUN lien de chaîne** (`document_links`) n'est posé (`258` n'en
--     appelle aucun) : la relance d'une facture est invisible pour la frise ;
--   * `collection_reminders` n'est PAS au registre `chain_document_types` : un lien
--     vers une relance aurait été REFUSÉ (451). C'est le premier objet ;
--   * aucun contrat d'effet, donc aucun maillon.
--
-- CE QUE CE FICHIER POSE : le type `collection_reminders` au registre, le contrat
-- d'effet `sale.invoice.to_reminder`, et le maillon `chain_l16_invoice_reminder` —
-- idempotent (rejeu REFUSÉ), réversible, tracé (`link_documents`, type
-- `created_from`, lisible par la Vue Chaîne).
--
-- ⚠️ LA COHÉRENCE EST VÉRIFIÉE, PAS SUPPOSÉE : une relance en BROUILLON ou
-- ANNULÉE n'est pas tracée (elle n'est pas partie) ; la relance et la facture
-- visent le MÊME client ; une relance déjà rattachée à une AUTRE facture est
-- refusée. Chaque refus dit sa raison.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Le registre accueille la RELANCE ────────────────────────────────────
INSERT INTO public.chain_document_types (code, table_name, ligne_table, libelle_fr) VALUES
  ('collection_reminders', 'collection_reminders', NULL, 'Relance de paiement')
ON CONFLICT (code) DO UPDATE SET
  table_name  = EXCLUDED.table_name,
  ligne_table = EXCLUDED.ligne_table,
  libelle_fr  = EXCLUDED.libelle_fr;

-- ── 2. Le CONTRAT d'effet (L7) : sans lui, la porte G2 refuse le maillon ───
INSERT INTO public.document_effects
  (tenant_id, document_type, evenement, effet, ecrit_comptable, journal_code,
   touche_stock, touche_paie, reversible, obligatoire, actif, note)
SELECT NULL, 'invoices', 'reminded', 'sale.invoice.to_reminder', false, NULL,
       false, false, true, false, true,
       'L16/757 : une facture client est relancée, et le lien amont→aval vers la relance est posé. Aucune comptabilité ici (une relance ne s''écrit pas). Réversible : fermer le lien.'
WHERE NOT EXISTS (
  SELECT 1 FROM public.document_effects
  WHERE document_type = 'invoices' AND evenement = 'reminded' AND effet = 'sale.invoice.to_reminder'
);

-- ── 3. Le MAILLON : `chain_l16_invoice_reminder` ───────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l16_invoice_reminder(p_invoice_id uuid, p_reminder_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_f     invoices%ROWTYPE;
  v_r     collection_reminders%ROWTYPE;
  v_exist uuid;
BEGIN
  -- 1. La facture, VERROUILLÉE et bornée à la société.
  SELECT * INTO v_f FROM invoices
   WHERE id = p_invoice_id AND tenant_id = current_tenant_id()
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Facture introuvable (ou hors de votre société)' USING ERRCODE = 'no_data_found';
  END IF;

  -- 2. La relance, bornée à la société.
  SELECT * INTO v_r FROM collection_reminders
   WHERE id = p_reminder_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Relance introuvable (ou hors de votre société)' USING ERRCODE = 'no_data_found';
  END IF;

  -- 3. LES REFUS EXPLICITES : chaque refus porte sa raison.
  IF v_r.status = 'draft' THEN
    RAISE EXCEPTION 'Relance % en brouillon : elle n''est pas partie, rien à tracer', v_r.number
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_r.status = 'cancelled' THEN
    RAISE EXCEPTION 'Relance % annulée : rattachement impossible', v_r.number
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_r.customer_id IS NOT NULL AND v_r.customer_id IS DISTINCT FROM v_f.customer_id THEN
    RAISE EXCEPTION 'La relance % et la facture % ne visent pas le même client',
      v_r.number, v_f.number USING ERRCODE = 'check_violation';
  END IF;
  IF v_r.invoice_id IS NOT NULL AND v_r.invoice_id <> p_invoice_id THEN
    RAISE EXCEPTION 'La relance % porte déjà une autre facture', v_r.number
      USING ERRCODE = 'unique_violation';
  END IF;

  -- 4. IDEMPOTENCE : le LIEN actif fait foi pour la frise.
  SELECT l.id INTO v_exist FROM document_links l
   WHERE l.tenant_id  = v_f.tenant_id
     AND l.amont_type = 'invoices'             AND l.amont_id = p_invoice_id
     AND l.aval_type  = 'collection_reminders' AND l.aval_id  = p_reminder_id
     AND l.effet = 'sale.invoice.to_reminder' AND l.etat = 'actif'
   LIMIT 1;
  IF v_exist IS NOT NULL THEN
    RAISE EXCEPTION 'La facture % est déjà relancée par la relance %', v_f.number, v_r.number
      USING ERRCODE = 'unique_violation';
  END IF;

  -- 5. Le rattachement STOCKÉ, seulement s'il manque (la relance peut déjà
  --    porter sa facture).
  UPDATE collection_reminders SET invoice_id = p_invoice_id
   WHERE id = p_reminder_id AND invoice_id IS NULL;

  -- 6. LE LIEN : c'est lui qui rend la chaîne VISIBLE (I-01).
  PERFORM link_documents(
    v_f.tenant_id, 'invoices', p_invoice_id, 'collection_reminders', p_reminder_id,
    'sale.invoice.to_reminder', 'created_from');

  RETURN jsonb_build_object(
    'success', true, 'invoice_id', p_invoice_id, 'reminder_id', p_reminder_id,
    'invoice_number', v_f.number, 'reminder_number', v_r.number, 'level', v_r.reminder_level);
END $fn$;

COMMENT ON FUNCTION public.chain_l16_invoice_reminder(uuid, uuid) IS
  'L16/757 : chaîne commerciale facture → relance. Idempotent (rejeu refusé), cohérent (même client, statuts valides), ÉCRIT collection_reminders.invoice_id si vide, tracé (link_documents, effet sale.invoice.to_reminder). SECURITY DEFINER, borné à current_tenant_id().';

-- ── 4. Droits : jamais PUBLIC — la règle de la garde 228 T06 ───────────────
REVOKE ALL ON FUNCTION public.chain_l16_invoice_reminder(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chain_l16_invoice_reminder(uuid, uuid) TO authenticated;
