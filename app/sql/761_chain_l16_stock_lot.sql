-- 761 — chain_l16_stock_lot
-- Numéro pris le 2026-10-11T08:45:42.611Z par migration-numero.mjs (ligne « plan6 A3 L16 (familles restantes) », branche plan6/a3-moteur).
-- ═══════════════════════════════════════════════════════════════════════════
-- 761 — L16 · le chaînage interne du STOCK : le MOUVEMENT DE STOCK et son LOT
--       (traçabilité des lots)
-- ═══════════════════════════════════════════════════════════════════════════
-- Le référentiel (§B.3) : « réception → stock → CUMP → écriture ; **lot ↔
-- traçabilité ↔ rappel** ». Voici le second membre : le lot.
--
-- CE QUE LA MESURE A TROUVÉ AVANT D'ÉCRIRE (base neuve) :
--   * `stock_movements.lot_id` EXISTE et est posée par les écrivains de stock
--     (`121_subcontracting_and_import.sql`, `122_import_generic.sql`, `113`,
--     `119`) — mais **AUCUNE clé étrangère** ne la relie (`pg_constraint` sur
--     `stock_movements` : seules `tenant_id`, `warehouse_id`, `product_id` sont
--     contraintes) et **AUCUN lien de chaîne** n'est posé : le lot d'un
--     mouvement est **invisible pour la frise**. Un lot orphelin passerait ;
--   * `product_batches` n'est PAS au registre `chain_document_types` : un lien
--     vers un lot aurait été REFUSÉ (451). C'est le premier objet ;
--   * aucun contrat d'effet, donc aucun maillon.
--
-- CE QUE CE FICHIER POSE : le type `product_batches` au registre, le contrat
-- d'effet `stock.movement.lot_traced`, et le maillon `chain_l16_stock_lot` —
-- idempotent (rejeu REFUSÉ), réversible, tracé (`link_documents`, type
-- `created_from` : le mouvement EST CRÉÉ À PARTIR du lot qu'il trace).
--
-- SENS DU LIEN (la leçon de `758`) : `link_documents` FUSIONNE deux liens qui
-- partagent le même `amont` + effet : pour lire N MOUVEMENTS depuis UN lot, le
-- lot doit être l'`aval` et chaque mouvement un `amont`. C'est le sens posé ici
-- (mouvement → lot), et c'est ce qui fait répondre la frise « lot → ses
-- mouvements », qui est la question de la traçabilité.
--
-- ⚠️ LA COHÉRENCE EST VÉRIFIÉE, PAS SUPPOSÉE : un mouvement **sans produit** est
-- refusé (on ne saurait pas à quel produit rattacher le lot) ; un lot qui **ne
-- porte pas le produit du mouvement** est refusé ; un mouvement qui **porte déjà
-- un AUTRE lot** est refusé (un mouvement ne trace qu'un lot — on ne réécrit pas
-- une trace). Chaque refus dit sa raison.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Le registre accueille le LOT ────────────────────────────────────────
INSERT INTO public.chain_document_types (code, table_name, ligne_table, libelle_fr) VALUES
  ('product_batches', 'product_batches', NULL, 'Lot (traçabilité)')
ON CONFLICT (code) DO UPDATE SET
  table_name  = EXCLUDED.table_name,
  ligne_table = EXCLUDED.ligne_table,
  libelle_fr  = EXCLUDED.libelle_fr;

-- ── 2. Le CONTRAT d'effet (L7) : sans lui, la porte G2 refuse le maillon ───
INSERT INTO public.document_effects
  (tenant_id, document_type, evenement, effet, ecrit_comptable, journal_code,
   touche_stock, touche_paie, reversible, obligatoire, actif, note)
SELECT NULL, 'stock_movements', 'lot_traced', 'stock.movement.lot_traced', false, NULL,
       true, false, true, false, true,
       'L16/761 : un mouvement de stock trace le lot qu''il consomme ou qu''il produit, et le lien amont→aval est posé. Écrit par les écrivains de stock (121, 122). Réversible : rompre le lien.'
WHERE NOT EXISTS (
  SELECT 1 FROM public.document_effects
  WHERE document_type = 'stock_movements' AND evenement = 'lot_traced' AND effet = 'stock.movement.lot_traced'
);


-- ── 3. Le MAILLON : `chain_l16_stock_lot` ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l16_stock_lot(p_movement_id uuid, p_batch_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_m     stock_movements%ROWTYPE;
  v_b     product_batches%ROWTYPE;
  v_exist uuid;
BEGIN
  -- 1. Le mouvement, borné à la société.
  SELECT * INTO v_m FROM stock_movements
   WHERE id = p_movement_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Mouvement de stock introuvable (ou hors de votre société)' USING ERRCODE = 'no_data_found';
  END IF;

  -- 2. Le lot, borné à la société.
  SELECT * INTO v_b FROM product_batches
   WHERE id = p_batch_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Lot introuvable (ou hors de votre société)' USING ERRCODE = 'no_data_found';
  END IF;

  -- 3. LES REFUS EXPLICITES : chaque refus porte sa raison.
  IF v_m.product_id IS NULL THEN
    RAISE EXCEPTION 'Mouvement % : aucun produit — impossible de le rattacher à un lot', v_m.id
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_b.product_id IS DISTINCT FROM v_m.product_id THEN
    RAISE EXCEPTION 'Le lot % ne porte pas le produit du mouvement : la traçabilité serait fausse', v_b.batch_number
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_m.lot_id IS NOT NULL AND v_m.lot_id <> p_batch_id THEN
    RAISE EXCEPTION 'Le mouvement % porte déjà un AUTRE lot : une trace ne se réécrit pas', v_m.id
      USING ERRCODE = 'check_violation';
  END IF;

  -- 4. IDEMPOTENCE : le LIEN actif fait foi pour la frise.
  SELECT l.id INTO v_exist FROM document_links l
   WHERE l.tenant_id  = v_m.tenant_id
     AND l.amont_type = 'stock_movements'  AND l.amont_id = p_movement_id
     AND l.aval_type  = 'product_batches'  AND l.aval_id  = p_batch_id
     AND l.effet = 'stock.movement.lot_traced' AND l.etat = 'actif'
   LIMIT 1;
  IF v_exist IS NOT NULL THEN
    RAISE EXCEPTION 'Le mouvement % trace déjà le lot %', p_movement_id, v_b.batch_number
      USING ERRCODE = 'unique_violation';
  END IF;

  -- 5. La COLONNE (si elle était vide) puis le LIEN : c'est le lien qui rend la
  --    chaîne VISIBLE (I-01). On ne réécrit jamais `lot_id` : il est lu pour
  --    refuser, pas pour être écrasé.
  IF v_m.lot_id IS NULL THEN
    UPDATE stock_movements SET lot_id = p_batch_id
     WHERE id = p_movement_id AND tenant_id = v_m.tenant_id;
  END IF;

  PERFORM link_documents(
    v_m.tenant_id, 'stock_movements', p_movement_id, 'product_batches', p_batch_id,
    'stock.movement.lot_traced', 'created_from');

  RETURN jsonb_build_object(
    'success', true, 'movement_id', p_movement_id, 'batch_id', p_batch_id,
    'batch_number', v_b.batch_number);
END $fn$;

COMMENT ON FUNCTION public.chain_l16_stock_lot(uuid, uuid) IS
  'L16/761 : chaîne de stock mouvement → son lot (traçabilité). Idempotent (rejeu refusé), refuse un mouvement sans produit, un lot d''un autre produit et un mouvement portant déjà un autre lot, tracé (link_documents, effet stock.movement.lot_traced). Ne réécrit pas lot_id : il le pose s''il est vide, sinon il le vérifie. SECURITY DEFINER, borné à current_tenant_id().';

-- ── 4. Droits : jamais PUBLIC — la règle de la garde 228 T06 ───────────────
REVOKE ALL ON FUNCTION public.chain_l16_stock_lot(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chain_l16_stock_lot(uuid, uuid) TO authenticated;
