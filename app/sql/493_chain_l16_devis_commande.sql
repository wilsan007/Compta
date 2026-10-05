-- ═══════════════════════════════════════════════════════════════════════════
-- 493 — L16 · le chaînage interne du COMMERCIAL : le devis accepté devient une
--       COMMANDE, et le maillon est TRACÉ
-- ═══════════════════════════════════════════════════════════════════════════
-- Numéro pris le 2026-10-05T20:17:00.173Z par migration-numero.mjs
-- (ligne « plan6 A3 (moteur L16-L24) », branche plan6/a3-moteur).
--
-- Le référentiel (§B.3) le dit au module Commercial — « devis ↔ commande ↔
-- livraison ↔ facture ↔ avoir ↔ règlement ↔ relance » — et mesure le premier
-- tronçon manquant : « devis → commande non chaîné (R-001) ». Le §D.2 en fait
-- un écart de niveau 1, celui qui disqualifie en démonstration : « un devis
-- accepté devient commande À LA MAIN, sans trace », quand SAP, NetSuite et
-- ERPNext répondent « chaîne documentée, prix gelé, engagement créé ».
--
-- CE QUE LA MESURE A TROUVÉ AVANT D'ÉCRIRE (base neuve, 333 migrations) :
--   * `convert_quote_to_invoice` EXISTE et est testé (190, réécrit en 317) —
--     le devis sait produire une FACTURE ; il ne sait pas produire une COMMANDE ;
--   * le schéma PORTE DÉJÀ le chaînon : `quotes.transformed_to_order_id` et
--     `sales_orders.quote_id` existent, et `quotes.validation_status` admet
--     'transformed' — deux colonnes que PERSONNE n'écrivait ;
--   * `quotes` n'était PAS au registre `chain_document_types` (27 types, sans
--     les devis) : un lien quotes → sales_orders aurait été REFUSÉ par la garde
--     d'existence (451). C'est le premier objet de ce fichier ;
--   * aucun maillon ne se nommait pour cet effet : à déclarer aussi — la porte
--     G2 refuse un effet appelé sans contrat.
--
-- CE QUE CE FICHIER POSE : le type 'quotes' au registre, le contrat d'effet
-- `sale.quote.to_order`, et le maillon `convert_quote_to_order` — idempotent (un
-- devis ne produit qu'UNE commande ; la 2e tentative est REFUSÉE), réversible
-- (le lien peut être fermé) et tracé (`link_documents`, donc lisible par la
-- Vue Chaîne, I-01).
--
-- ⚠️ LE PRIX EST GELÉ, ET C'EST TOUT L'INTÉRÊT. Les totaux de la commande sont
-- la SOMME DES LIGNES DU DEVIS — jamais une relecture de tarif, jamais un
-- recalcul. Ce qui a été accepté est ce qui est commandé.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Le registre des types de documents accueille les DEVIS ──────────────
-- Le geste est celui de la 450 pour les 27 types : un upsert, donc rejouable.
INSERT INTO public.chain_document_types (code, table_name, ligne_table, libelle_fr) VALUES
  ('quotes', 'quotes', 'quote_lines', 'Devis')
ON CONFLICT (code) DO UPDATE SET
  table_name  = EXCLUDED.table_name,
  ligne_table = EXCLUDED.ligne_table,
  libelle_fr  = EXCLUDED.libelle_fr;

-- ── 2. Le CONTRAT d'effet (L7) : sans lui, la porte G2 refuse le maillon ───
-- Un contrat dit ce qu'un effet EST, y compris quand il n'écrit AUCUNE
-- comptabilité. Ici : créer la commande ne touche ni le stock (la réservation
-- naît de la CONFIRMATION de la commande, pas de sa création) ni la paie.
-- Écrit sans ON CONFLICT ciblé : l'insertion est gardée par NOT EXISTS, donc
-- rejouable même si la clé (document, événement, effet) n'a pas d'unicité.
INSERT INTO public.document_effects
  (tenant_id, document_type, evenement, effet, ecrit_comptable, journal_code,
   touche_stock, touche_paie, reversible, obligatoire, actif, note)
SELECT NULL, 'quotes', 'accepted', 'sale.quote.to_order', false, NULL,
       false, false, true, true, true,
       'L16/493 : le devis accepté produit une COMMANDE client (brouillon) et un lien amont→aval. Écrit d''après les lignes ACCEPTÉES (prix gelé). Réversible : annuler le devis ferme le lien.'
WHERE NOT EXISTS (
  SELECT 1 FROM public.document_effects
  WHERE document_type = 'quotes' AND evenement = 'accepted' AND effet = 'sale.quote.to_order'
);

-- ── 3. Le MAILLON : `convert_quote_to_order` ───────────────────────────────
-- Le nom dit le geste, et le geste est borné : UN devis → UNE commande.
CREATE OR REPLACE FUNCTION public.convert_quote_to_order(p_quote_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_q      quotes%ROWTYPE;
  v_order  uuid;
  v_num    text;
  v_ht     numeric;
  v_tva    numeric;
  v_exist  uuid;
  v_lignes int;
BEGIN
  -- 1. Le devis, VERROUILLÉ et borné à la société : deux appels simultanés ne
  --    produisent pas deux commandes — le second attend, puis voit le lien.
  SELECT * INTO v_q FROM quotes
   WHERE id = p_quote_id AND tenant_id = current_tenant_id()
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Devis introuvable (ou hors de votre société)' USING ERRCODE = 'no_data_found';
  END IF;

  -- 2. IDEMPOTENCE : deux lectures, parce que deux réalités le disent — la
  --    colonne que le schéma portait, ET le LIEN actif (celui qui fait foi pour
  --    la frise). Le rejeu est REFUSÉ, jamais silencieux.
  IF v_q.transformed_to_order_id IS NOT NULL THEN
    RAISE EXCEPTION 'Devis % déjà transformé en commande', v_q.number USING ERRCODE = 'unique_violation';
  END IF;
  SELECT l.aval_id INTO v_exist FROM document_links l
   WHERE l.tenant_id  = v_q.tenant_id
     AND l.amont_type = 'quotes'       AND l.amont_id = p_quote_id
     AND l.aval_type  = 'sales_orders' AND l.etat = 'actif'
   LIMIT 1;
  IF v_exist IS NOT NULL THEN
    RAISE EXCEPTION 'Devis % déjà transformé en commande', v_q.number USING ERRCODE = 'unique_violation';
  END IF;

  -- 3. Les REFUS EXPLICITES : chaque refus porte sa raison — le contraire d'un
  --    état muet, qui est exactement le défaut que le référentiel mesure.
  IF v_q.status IN ('rejected', 'expired') THEN
    RAISE EXCEPTION 'Devis % % : conversion impossible', v_q.number,
      CASE v_q.status WHEN 'rejected' THEN 'refusé' ELSE 'expiré' END
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_q.status <> 'accepted' THEN
    RAISE EXCEPTION 'Devis % non accepté (statut %) : la commande ne naît que d''un devis accepté',
      v_q.number, v_q.status USING ERRCODE = 'check_violation';
  END IF;

  SELECT count(*) INTO v_lignes FROM quote_lines
   WHERE quote_id = p_quote_id AND tenant_id = v_q.tenant_id;
  IF v_lignes = 0 THEN
    RAISE EXCEPTION 'Devis % sans ligne : une commande vide ne s''engage sur rien', v_q.number
      USING ERRCODE = 'check_violation';
  END IF;

  -- 4. LE PRIX GELÉ : les totaux sont la SOMME DES LIGNES DU DEVIS. Aucun tarif
  --    n'est relu, aucun montant n'est recalculé.
  SELECT COALESCE(sum(l.quantity * l.unit_price), 0),
         COALESCE(sum(l.vat_total), 0)
    INTO v_ht, v_tva
    FROM quote_lines l
   WHERE l.quote_id = p_quote_id AND l.tenant_id = v_q.tenant_id;

  v_num := get_next_document_number('BC');

  -- 5. La commande, en brouillon. C'est la CONFIRMATION qui réserve le stock,
  --    pas la création : ce maillon n'ajoute donc aucun effet d'aval.
  INSERT INTO sales_orders
    (tenant_id, number, customer_id, order_date, delivery_date, status,
     subtotal, vat, total, notes, quote_id)
  VALUES
    (v_q.tenant_id, v_num, v_q.customer_id,
     COALESCE(v_q.date, CURRENT_DATE),
     COALESCE(v_q.expiry_date, COALESCE(v_q.date, CURRENT_DATE) + 30),
     'draft', v_ht, v_tva, v_ht + v_tva,
     'Issue du devis ' || v_q.number, p_quote_id)
  RETURNING id INTO v_order;

  INSERT INTO sales_order_lines
    (tenant_id, sales_order_id, product_id, description, quantity,
     unit_price, vat_rate, line_total, delivered_quantity)
  SELECT v_q.tenant_id, v_order, l.product_id, l.description, l.quantity,
         l.unit_price, l.vat_rate, l.quantity * l.unit_price, 0
    FROM quote_lines l
   WHERE l.quote_id = p_quote_id AND l.tenant_id = v_q.tenant_id
   ORDER BY l.line_order, l.created_at;

  -- 6. Le devis DIT ce qu'il est devenu (les deux colonnes que personne
  --    n'écrivait) ; il reste 'accepted' : il n'a pas été annulé.
  UPDATE quotes
     SET transformed_to_order_id = v_order,
         transformation_status   = 'transformed',
         validation_status       = 'transformed',
         updated_at              = now()
   WHERE id = p_quote_id;

  -- 7. LE LIEN : c'est lui qui rend la chaîne VISIBLE (I-01). Le nom de l'effet
  --    est celui du contrat du §2 — G2 les compare.
  PERFORM link_documents(
    v_q.tenant_id, 'quotes', p_quote_id, 'sales_orders', v_order,
    'sale.quote.to_order', 'created_from');

  RETURN jsonb_build_object(
    'success', true, 'order_id', v_order, 'number', v_num,
    'subtotal', v_ht, 'vat', v_tva, 'total', v_ht + v_tva, 'lines', v_lignes);
END $fn$;

COMMENT ON FUNCTION public.convert_quote_to_order(uuid) IS
  'L16/493 : chaîne commerciale devis → commande. Idempotent (rejeu refusé), prix gelé (somme des lignes acceptées), tracé (link_documents, effet sale.quote.to_order). SECURITY DEFINER, borné à current_tenant_id().';

-- ── 4. Droits : jamais PUBLIC — la règle de la garde 228 T06 ───────────────
REVOKE ALL ON FUNCTION public.convert_quote_to_order(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.convert_quote_to_order(uuid) TO authenticated;

