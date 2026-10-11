-- Numéro pris le 2026-10-11T09:30:27.583Z par migration-numero.mjs (ligne « plan6 A3 L16 (familles restantes) », branche plan6/a3-moteur).

-- ═══════════════════════════════════════════════════════════════════════════
-- 762 — L16 · le chaînage interne du STOCK : la RÉCEPTION et les MOUVEMENTS DE
--       STOCK qu'elle produit
-- ═══════════════════════════════════════════════════════════════════════════
-- Le référentiel (§B.3), premier membre de la famille Stock :
-- « **réception → stock** → CUMP → écriture ». Le lot `761` a posé le lot ; voici
-- l'entrée en stock.
--
-- CE QUE LA MESURE A TROUVÉ AVANT D'ÉCRIRE (base neuve) :
--   * l'écrivain existe : `create_stock_on_goods_receipt` (`241`, déclencheur
--     AFTER UPDATE `status = 'received'`) insère les mouvements en posant
--     `reference = 'BR-' || number`, **`reference_type = 'goods_receipt'`**,
--     `reference_id = NEW.id`. L'annulation (`251`) écrit une sortie miroir en
--     `reference_type = 'goods_receipt_cancel'` ;
--   * `133`, `141` et `251` LISENT tous `'goods_receipt'` — mais **aucun lien de
--     chaîne** n'est posé : les mouvements d'une réception sont **invisibles pour
--     la frise** (I-01), et un mouvement se réclamant d'une réception qui n'est
--     pas la sienne passerait sans bruit ;
--   * `goods_receipts` et `stock_movements` sont **déjà au registre** : ce fichier
--     ne le suppose pas, il l'EXIGE (voir §1) ;
--   * la contrainte `uq_stock_movement_source (tenant_id, reference_type,
--     reference_id, product_id, movement_type)` borne le couple : une réception
--     produit **au plus un mouvement par produit** — c'est ce qui donne son sens
--     à « N mouvements depuis une réception » (N produits), et c'est ce que T04
--     mesure ;
--   * aucun contrat d'effet, donc aucun maillon.
--
-- ⚠️ DÉFAUT MESURÉ, TRANSMIS (hors de ce lot — il n'est PAS corrigé ici) :
--   `125_stock_advanced.sql` (le CUMP / les frais accessoires) filtre DEUX fois
--   sur `reference_type = 'receipt'` — **une valeur que PERSONNE n'écrit**.
--   L'écrivain dit `'goods_receipt'`. Le couple « réception ↔ valorisation » est
--   donc **vide** : `calculate_landed_cost_distribution` lève toujours « Aucune
--   réception à répartir ». C'est le lot **CUMP → écriture** qui le corrigera
--   (migration `_fix_`, avec sa mesure) ; le taire ici aurait été le défaut.
--
-- ⚠️ LA COHÉRENCE EST VÉRIFIÉE, PAS SUPPOSÉE : une réception qui n'a pas reçu
--   (`pending`, `cancelled`) est refusée — sa sortie de stock n'existe pas ; un
--   mouvement dont `reference_type`/`reference_id` ne désignent pas CETTE
--   réception est refusé. Chaque refus dit sa raison.
--
-- SENS DU LIEN (la leçon de `758`) : `link_documents` FUSIONNE deux liens qui
-- partagent le même `amont` + effet : pour lire N MOUVEMENTS depuis UNE
-- réception, la réception est l'`aval` et chaque mouvement un `amont`. Une
-- réception produit plusieurs mouvements (un par ligne reçue) : c'est
-- exactement le cas.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Le registre : EXIGÉ, pas supposé ────────────────────────────────────
-- Sans ces deux types au registre, `link_documents` refuse le lien (451) — et le
-- maillon échouerait à l'exécution au lieu de le dire au déploiement.
DO $$
BEGIN
  IF (SELECT count(*) FROM public.chain_document_types
       WHERE code IN ('goods_receipts', 'stock_movements')) <> 2 THEN
    RAISE EXCEPTION '762 : le registre n''accueille pas goods_receipts ET stock_movements — le lien serait refusé (451)'
      USING ERRCODE = 'check_violation';
  END IF;
END $$;

-- ── 2. Le CONTRAT d'effet (L7) : sans lui, la porte G2 refuse le maillon ───
INSERT INTO public.document_effects
  (tenant_id, document_type, evenement, effet, ecrit_comptable, journal_code,
   touche_stock, touche_paie, reversible, obligatoire, actif, note)
SELECT NULL, 'stock_movements', 'receipt_recorded', 'stock.receipt.movement_recorded', false, NULL,
       true, false, true, false, true,
       'L16/762 : une réception « reçue » produit ses mouvements de stock (un par ligne), et le lien amont→aval est posé. Écrit par create_stock_on_goods_receipt (241). Réversible : rompre le lien.'
WHERE NOT EXISTS (
  SELECT 1 FROM public.document_effects
  WHERE document_type = 'stock_movements' AND evenement = 'receipt_recorded'
    AND effet = 'stock.receipt.movement_recorded'
);

-- ── 3. Le MAILLON : `chain_l16_receipt_movement` ───────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l16_receipt_movement(p_receipt_id uuid, p_movement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_r     goods_receipts%ROWTYPE;
  v_m     stock_movements%ROWTYPE;
  v_exist uuid;
BEGIN
  -- 1. La réception, bornée à la société.
  SELECT * INTO v_r FROM goods_receipts
   WHERE id = p_receipt_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Réception introuvable (ou hors de votre société)' USING ERRCODE = 'no_data_found';
  END IF;

  -- 2. Le mouvement, borné à la société.
  SELECT * INTO v_m FROM stock_movements
   WHERE id = p_movement_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Mouvement de stock introuvable (ou hors de votre société)' USING ERRCODE = 'no_data_found';
  END IF;

  -- 3. LES REFUS EXPLICITES : chaque refus porte sa raison.
  IF v_r.status NOT IN ('received', 'partial') THEN
    RAISE EXCEPTION 'Réception % au statut « % » : elle n''a pas reçu, sa sortie de stock n''existe pas', v_r.number, v_r.status
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_m.reference_type IS DISTINCT FROM 'goods_receipt'
     OR v_m.reference_id IS DISTINCT FROM p_receipt_id THEN
    RAISE EXCEPTION 'Le mouvement % n''a pas été produit par la réception % (reference_type = %, reference_id = %)',
      p_movement_id, v_r.number, COALESCE(v_m.reference_type, '(vide)'), COALESCE(v_m.reference_id::text, '(vide)')
      USING ERRCODE = 'check_violation';
  END IF;

  -- 4. IDEMPOTENCE : le LIEN actif fait foi pour la frise.
  SELECT l.id INTO v_exist FROM document_links l
   WHERE l.tenant_id  = v_r.tenant_id
     AND l.amont_type = 'stock_movements' AND l.amont_id = p_movement_id
     AND l.aval_type  = 'goods_receipts'   AND l.aval_id  = p_receipt_id
     AND l.effet = 'stock.receipt.movement_recorded' AND l.etat = 'actif'
   LIMIT 1;
  IF v_exist IS NOT NULL THEN
    RAISE EXCEPTION 'La réception % est déjà rattachée au mouvement %', v_r.number, p_movement_id
      USING ERRCODE = 'unique_violation';
  END IF;

  -- 5. LE LIEN : c'est lui qui rend la chaîne VISIBLE (I-01). Aucune colonne n'est
  --    réécrite : `reference_type`/`reference_id` sont posées par l'entrée en
  --    stock (241) — elles sont ici LUES pour refuser, pas pour être écrasées.
  PERFORM link_documents(
    v_r.tenant_id, 'stock_movements', p_movement_id, 'goods_receipts', p_receipt_id,
    'stock.receipt.movement_recorded', 'created_from');

  RETURN jsonb_build_object(
    'success', true, 'receipt_id', p_receipt_id, 'receipt_number', v_r.number,
    'movement_id', p_movement_id, 'product_id', v_m.product_id);
END $fn$;

COMMENT ON FUNCTION public.chain_l16_receipt_movement(uuid, uuid) IS
  'L16/762 : chaîne de stock réception → ses mouvements de stock. Idempotent (rejeu refusé), refuse une réception qui n''a pas reçu (pending/cancelled) et un mouvement qui ne désigne pas cette réception (reference_type/reference_id), tracé (link_documents, effet stock.receipt.movement_recorded). Ne réécrit rien : les colonnes de 241 sont lues pour vérifier. SECURITY DEFINER, borné à current_tenant_id().';

-- ── 4. Droits : jamais PUBLIC — la règle de la garde 228 T06 ───────────────
REVOKE ALL ON FUNCTION public.chain_l16_receipt_movement(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chain_l16_receipt_movement(uuid, uuid) TO authenticated;

