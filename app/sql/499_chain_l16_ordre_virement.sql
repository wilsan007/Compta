-- 499 — chain_l16_ordre_virement
-- Numéro pris le 2026-10-06T06:24:57.649Z par migration-numero.mjs (ligne « plan6 A3 (moteur L16-L24) », branche plan6/a3-moteur).
-- ═══════════════════════════════════════════════════════════════════════════
-- 499 — L16 · le chaînage interne de la TRÉSORERIE : le VIREMENT exécuté par un
--       ORDRE DE PAIEMENT lui est RATTACHÉ et TRACÉ
-- ═══════════════════════════════════════════════════════════════════════════
-- Le référentiel (§B.3) le dit au module Trésorerie — « prévision ↔ échéancier ↔
-- **ordre de paiement ↔ virement** ↔ relevé ↔ rapprochement ». L'ordre de
-- paiement EST saisi (l'écran `PaymentOrdersPage` écrit `payment_orders`, le
-- tableau de bord lit `status IN ('draft','approved')` comme engagements à
-- venir) — mais rien ne le relie au VIREMENT qu'il produit.
--
-- CE QUE LA MESURE A TROUVÉ AVANT D'ÉCRIRE (base neuve, 333 migrations) :
--   * `payment_orders` (type `sepa_transfer`…, statut `draft|approved|executed|
--     cancelled`) n'est PAS au registre `chain_document_types` : un lien vers un
--     ordre de paiement aurait été REFUSÉ par la garde d'existence (451) ;
--   * aucun contrat d'effet, donc aucun maillon ;
--   * le « virement » est un RÈGLEMENT enregistré — `supplier_payments` (achat)
--     ou `customer_payments` (vente) — deux tables déjà au registre.
--
-- CE QUE CE FICHIER POSE : le type `payment_orders` au registre, le contrat
-- d'effet `treasury.order.to_payment`, et le maillon `chain_l16_order_payment` —
-- il RETROUVE le règlement dans `supplier_payments` **ou** `customer_payments`
-- (le type du tiers décide), vérifie la COHÉRENCE (même compte bancaire, montant
-- du virement ≤ montant de l'ordre), marque l'ordre `executed`, et TRACE le lien
-- (`link_documents`, type `paid_by`, lisible par la Vue Chaîne).
--
-- ⚠️ LA COHÉRENCE EST VÉRIFIÉE, PAS SUPPOSÉE : un ordre annulé ou déjà exécuté
-- est refusé ; un règlement d'un autre compte bancaire est refusé ; un règlement
-- introuvable est refusé. Chaque refus porte sa raison.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Le registre des types de documents accueille les ORDRES DE PAIEMENT ──
INSERT INTO public.chain_document_types (code, table_name, ligne_table, libelle_fr) VALUES
  ('payment_orders', 'payment_orders', NULL, 'Ordre de paiement')
ON CONFLICT (code) DO UPDATE SET
  table_name  = EXCLUDED.table_name,
  ligne_table = EXCLUDED.ligne_table,
  libelle_fr  = EXCLUDED.libelle_fr;

-- ── 2. Le CONTRAT d'effet (L7) : sans lui, la porte G2 refuse le maillon ───
INSERT INTO public.document_effects
  (tenant_id, document_type, evenement, effet, ecrit_comptable, journal_code,
   touche_stock, touche_paie, reversible, obligatoire, actif, note)
SELECT NULL, 'payment_orders', 'executed', 'treasury.order.to_payment', false, NULL,
       false, false, true, false, true,
       'L16/499 : un ordre de paiement exécuté produit le virement (le règlement) et le lien amont→aval est posé. L''écriture comptable est portée par le règlement (purchase.payment.generated_entry / sale.payment.generated_entry), pas par ce maillon. Réversible : fermer le lien.'
WHERE NOT EXISTS (
  SELECT 1 FROM public.document_effects
  WHERE document_type = 'payment_orders' AND evenement = 'executed' AND effet = 'treasury.order.to_payment'
);

-- ── 3. Le MAILLON : `chain_l16_order_payment` ──────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l16_order_payment(p_order_id uuid, p_payment_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_o      payment_orders%ROWTYPE;
  v_kind   text;
  v_aval   text;
  v_amount numeric;
  v_bank   uuid;
  v_num    text;
  v_exist  uuid;
BEGIN
  -- 1. L'ordre de paiement, VERROUILLÉ et borné à la société.
  SELECT * INTO v_o FROM payment_orders
   WHERE id = p_order_id AND tenant_id = current_tenant_id()
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ordre de paiement introuvable (ou hors de votre société)' USING ERRCODE = 'no_data_found';
  END IF;

  -- 2. Le virement : un règlement enregistré, côté ACHAT ou VENTE. On le
  --    retrouve ; le TYPE DU TIERS décide de la table (aval).
  SELECT 'purchase', 'supplier_payments', sp.amount, sp.bank_account_id, sp.number
    INTO v_kind, v_aval, v_amount, v_bank, v_num
    FROM supplier_payments sp
   WHERE sp.id = p_payment_id AND sp.tenant_id = current_tenant_id();
  IF NOT FOUND THEN
    SELECT 'sale', 'customer_payments', cp.amount, cp.bank_account_id, cp.number
      INTO v_kind, v_aval, v_amount, v_bank, v_num
      FROM customer_payments cp
     WHERE cp.id = p_payment_id AND cp.tenant_id = current_tenant_id();
  END IF;
  IF v_aval IS NULL THEN
    RAISE EXCEPTION 'Virement introuvable (ou hors de votre société) : ni règlement fournisseur, ni règlement client'
      USING ERRCODE = 'no_data_found';
  END IF;

  -- 3. LES REFUS EXPLICITES : chaque refus porte sa raison.
  IF v_o.status = 'cancelled' THEN
    RAISE EXCEPTION 'Ordre de paiement % annulé : aucun virement ne s''y rattache', v_o.number
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_o.status = 'executed' THEN
    RAISE EXCEPTION 'Ordre de paiement % déjà exécuté', v_o.number
      USING ERRCODE = 'unique_violation';
  END IF;
  IF v_o.bank_account_id IS NOT NULL AND v_bank IS NOT NULL AND v_bank <> v_o.bank_account_id THEN
    RAISE EXCEPTION 'Le virement % porte un autre compte bancaire que l''ordre %', v_num, v_o.number
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_amount > COALESCE(v_o.amount, 0) THEN
    RAISE EXCEPTION 'Le virement % (%) dépasse le montant de l''ordre % (%)',
      v_num, v_amount, v_o.number, v_o.amount USING ERRCODE = 'check_violation';
  END IF;

  -- 4. IDEMPOTENCE : le LIEN actif fait foi pour la frise.
  SELECT l.id INTO v_exist FROM document_links l
   WHERE l.tenant_id = v_o.tenant_id AND l.amont_type = 'payment_orders' AND l.amont_id = p_order_id
     AND l.aval_id = p_payment_id AND l.effet = 'treasury.order.to_payment' AND l.etat = 'actif'
   LIMIT 1;
  IF v_exist IS NOT NULL THEN
    RAISE EXCEPTION 'L''ordre % est déjà rattaché à son virement', v_o.number USING ERRCODE = 'unique_violation';
  END IF;

  -- 5. L'ordre DIT qu'il est exécuté (le statut que personne ne posait).
  UPDATE payment_orders SET status = 'executed', updated_at = now() WHERE id = p_order_id;

  -- 6. LE LIEN : c'est lui qui rend la chaîne VISIBLE (I-01).
  PERFORM link_documents(
    v_o.tenant_id, 'payment_orders', p_order_id, v_aval, p_payment_id,
    'treasury.order.to_payment', 'paid_by');

  RETURN jsonb_build_object(
    'success', true, 'order_id', p_order_id, 'payment_id', p_payment_id,
    'kind', v_kind, 'order_number', v_o.number, 'payment_number', v_num);
END $fn$;

COMMENT ON FUNCTION public.chain_l16_order_payment(uuid, uuid) IS
  'L16/499 : chaîne trésorerie ordre de paiement → virement (règlement). Idempotent (rejeu refusé), cohérent (compte bancaire, montant), marque l''ordre exécuté, tracé (link_documents, effet treasury.order.to_payment). SECURITY DEFINER, borné à current_tenant_id().';

-- ── 4. Droits : jamais PUBLIC — la règle de la garde 228 T06 ───────────────
REVOKE ALL ON FUNCTION public.chain_l16_order_payment(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chain_l16_order_payment(uuid, uuid) TO authenticated;
