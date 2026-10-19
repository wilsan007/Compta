-- ═══════════════════════════════════════════════════════════════════════════
-- 765_chain_l16_cump_ecriture.sql — L16 · Stock · P10 : les frais accessoires
--       (CUMP) rattachés aux mouvements qu'ils ajustent
-- ═══════════════════════════════════════════════════════════════════════════
-- Le défaut mesuré (lot 762) : `125_stock_advanced.sql` filtre DEUX fois sur
-- `reference_type = 'receipt'` alors que l'écrivain `241` pose
-- `'goods_receipt'`. La répartition des frais accessoires trouvait donc ZÉRO
-- mouvement, distribuait zéro centime et renvoyait `success: true`.
--
-- CE QUE CE FICHIER POSE :
--   1. La 125 est CORRIGÉE EN PLACE (les deux filtres `'receipt'` →
--      `'goods_receipt'`) — la correction vit dans la migration, pas ici.
--   2. `landed_costs` entre au registre `chain_document_types` (le lien le
--      nomme comme aval : sans l'inscription, `link_documents` le refuse, 451).
--   3. Le contrat d'effet `stock.landed_cost.distributed` (porte G2).
--   4. Le maillon : `distribute_landed_cost` (son nom historique est CONSERVÉ —
--      c'est une fonction publique déjà livrée par la 125) est réécrit pour
--      TRACER chaque mouvement ajusté (`link_documents`) et pour être
--      IDEMPOTENT AU REJEU.
--   5. La garde de suppression sur `landed_costs` (le type entre au registre ;
--      la boucle de la 764 ne l'a pas vu — elle tourne AVANT ce fichier).
--
-- SENS DU LIEN (la leçon de `758` et `762`) : `link_documents` FUSIONNE deux
-- liens qui partagent le même `amont` + effet + ligne-amont. Un frais réparti
-- ajuste N MOUVEMENTS : c'est donc CHAQUE MOUVEMENT qui est l'`amont` et les
-- FRAIS qui sont l'`aval` — avec les frais pour amont, N mouvements ne
-- tiendraient qu'UN lien (le dernier écraserait les autres, ils disparaîtraient
-- de la frise).
--
-- REJEU ET CIBLAGE — le contrat de la 658 (plan6 E, appliquée AVANT celle-ci
-- en ordre de numérotation) est le socle : les frais se répartissent SUR LES
-- RÉCEPTIONS CIBLÉES (`landed_cost_receipts`) — jamais sur toutes celles de la
-- société (658 T04 le mesure : une réception voisine non ciblée ne compte
-- pas) ; sans cible, la répartition est REFUSÉE (658 T02). Un frais DÉJÀ
-- réparti est REFUSÉ nommé (658 T03) — un rejeu silencieux masquerait une
-- double répartition en production. La 765 ajoute à ce contrat ce que le
-- sien n'avait pas : la BASE vient des LIGNES DES RÉCEPTIONS CIBLÉES (la
-- 125 lisait les mouvements avec un filtre faux — `'receipt'` au lieu de
-- `'goods_receipt'` — et trouvait zéro mouvement ; la source pièce évite
-- le piège), le LIEN de chaîne vers le MOUVEMENT réel ajusté quand il en
-- existe un (effet `stock.landed_cost.distributed`, contrat déclaré plus
-- bas), le refus du frais ANNULÉ, et la CUMP ajustée AU DÉPÔT de la
-- réception (`stock_quantities` : clé produit × dépôt, sans NULL mesuré). DEUX suites, UN moteur : 658 et 765 vivent sur la même
-- fonction — c'est la règle W5 appliquée à l'envers : le second arrivant
-- ne réécrit pas le contrat du premier, il l'ÉTEND.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Registre : landed_costs ──────────────────────────────────────────────
INSERT INTO public.chain_document_types (code, table_name, ligne_table, libelle_fr) VALUES
  ('landed_costs', 'landed_costs', NULL, 'Frais accessoires d''achat (CUMP)')
ON CONFLICT (code) DO UPDATE SET
  table_name  = EXCLUDED.table_name,
  ligne_table = EXCLUDED.ligne_table,
  libelle_fr  = EXCLUDED.libelle_fr;

-- ── 2. Contrat d'effet (L7) ────────────────────────────────────────────────
INSERT INTO public.document_effects
  (tenant_id, document_type, evenement, effet, ecrit_comptable, journal_code,
   touche_stock, touche_paie, reversible, obligatoire, actif, note)
SELECT NULL, 'landed_costs', 'distributed', 'stock.landed_cost.distributed',
       false, NULL, false, false, true, true, true,
       'P10/765 : la répartition des frais accessoires (CUMP) lie la landed_cost aux mouvements de stock affectés. Lien tracé, réversible (rompre ferme).'
WHERE NOT EXISTS (
  SELECT 1 FROM public.document_effects
   WHERE document_type = 'landed_costs' AND effet = 'stock.landed_cost.distributed');

-- ── 3. LE MAILLON : distribute_landed_cost — le moteur UNIQUE ───────────────
-- Contrat 658 (ciblage des réceptions, refus sans cible, refus du déjà
-- réparti) + apports 765 (filtre goods_receipt, lien de chaîne par mouvement,
-- refus du frais annulé, CUMP au dépôt). Le nom historique est CONSERVÉ —
-- c'est une fonction publique déjà livrée par la 125 et appelée par le front.
CREATE OR REPLACE FUNCTION public.distribute_landed_cost(
  p_landed_cost_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_lc record;
  v_total_base numeric := 0;
  v_line record;
  v_distributed numeric;
  v_n integer := 0;
BEGIN
  SELECT * INTO v_lc FROM landed_costs WHERE id = p_landed_cost_id AND tenant_id = v_tid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Frais accessoire introuvable'; END IF;

  -- REJEU : un frais DÉJÀ réparti est REFUSÉ nommé (contrat 658 T03) — un
  -- rejeu silencieux masquerait une double répartition en production.
  IF v_lc.status = 'distributed' THEN
    RAISE EXCEPTION 'Frais accessoire % déjà réparti — corrigez le total et régénérez (L20), ou annulez : un second partage écraserait le premier.', COALESCE(v_lc.invoice_number, v_lc.id::text)
      USING ERRCODE = 'check_violation';
  END IF;

  -- Un frais ANNULÉ n'est pas réparti (le rejeu ne retombe pas).
  IF v_lc.status = 'cancelled' THEN
    RAISE EXCEPTION 'Frais accessoire annulé : refus de la répartition'
      USING ERRCODE = 'check_violation';
  END IF;

  -- Idempotence de l'état (658) : une répartition antérieure inachevée est
  -- effacée AVANT le partage — jamais deux fois le même frais.
  DELETE FROM landed_cost_lines WHERE landed_cost_id = p_landed_cost_id AND tenant_id = v_tid;

  -- LA BASE : les LIGNES des RÉCEPTIONS CIBLÉES (landed_cost_receipts) —
  -- jamais toutes celles de la société (658 T04). La base vient des lignes
  -- de réception (contrat 658) : c'est la pièce de réception qui dit ce qui
  -- est entré ; la 125 lisait les mouvements avec un filtre faux
  -- (`'receipt'` au lieu de `'goods_receipt'`) et trouvait zéro — autant
  -- prendre la source qui ne dépend pas du filtre. 'weight'/'volume'
  -- tombent sur la valeur (pas de pesée réelle — limite dite, comme avant).
  SELECT COALESCE(SUM(
    CASE v_lc.distribution_method
      WHEN 'quantity' THEN grl.quantity_received
      WHEN 'weight'  THEN grl.quantity_received * COALESCE(p.weight, 0)
      ELSE grl.quantity_received * COALESCE(p.cost_price, p.purchase_price, 0)
    END
  ), 0) INTO v_total_base
  FROM landed_cost_receipts lcr
  JOIN goods_receipt_lines grl
    ON grl.goods_receipt_id = lcr.receipt_id
   AND grl.tenant_id = v_tid
  JOIN products p ON p.id = grl.product_id AND p.tenant_id = v_tid
  WHERE lcr.landed_cost_id = p_landed_cost_id
    AND lcr.tenant_id = v_tid;

  IF v_total_base = 0 THEN
    RAISE EXCEPTION 'Aucune réception à répartir pour ce frais (base nulle) — reliez le frais à ses réceptions (landed_cost_receipts).'
      USING ERRCODE = 'check_violation';
  END IF;

  -- Répartir, LIGNE de RÉCEPTION par LIGNE de RÉCEPTION (chaque entrée
  -- réelle reçoit sa part, au dépôt de sa réception).
  FOR v_line IN
    SELECT grl.product_id, gr.warehouse_id, grl.quantity_received,
           lcr.receipt_id,
           CASE v_lc.distribution_method
             WHEN 'quantity' THEN grl.quantity_received
             WHEN 'weight'  THEN grl.quantity_received * COALESCE(p.weight, 0)
             ELSE grl.quantity_received * COALESCE(p.cost_price, p.purchase_price, 0)
           END AS base,
           COALESCE(p.cost_price, p.purchase_price, 0) AS cout_unitaire
    FROM landed_cost_receipts lcr
    JOIN goods_receipts gr ON gr.id = lcr.receipt_id AND gr.tenant_id = v_tid
    JOIN goods_receipt_lines grl
      ON grl.goods_receipt_id = gr.id
     AND grl.tenant_id = v_tid
    JOIN products p ON p.id = grl.product_id AND p.tenant_id = v_tid
    WHERE lcr.landed_cost_id = p_landed_cost_id
      AND lcr.tenant_id = v_tid
      AND COALESCE(grl.quantity_received, 0) <> 0
  LOOP
    v_distributed := v_lc.total_amount * (v_line.base / v_total_base);

    INSERT INTO landed_cost_lines (
      tenant_id, landed_cost_id, product_id,
      distributed_amount, original_unit_cost, new_unit_cost
    ) VALUES (
      v_tid, p_landed_cost_id, v_line.product_id,
      v_distributed, v_line.cout_unitaire,
      v_line.cout_unitaire + v_distributed / v_line.quantity_received
    );

    -- Ajuster la CUMP DU COUPLE (article, dépôt) de la réception (658).
    UPDATE stock_quantities
    SET unit_cost = COALESCE(unit_cost, 0) + v_distributed / v_line.quantity_received,
        updated_at = now()
    WHERE tenant_id = v_tid
      AND product_id = v_line.product_id
      AND warehouse_id = v_line.warehouse_id;

    -- Lien de chaîne : landed_costs → le MOUVEMENT réel de cette réception,
    -- quand la réception en a produit (765). Une réception sans mouvement —
    -- pièce créée sans transition d'état — ajuste la couche SANS lien : le
    -- lien suit le flux de stock, il n'invente pas de document aval
    -- (`link_documents` refuse un aval introuvable, 451).
    PERFORM (
      SELECT link_documents(
        v_tid,
        'landed_costs', p_landed_cost_id,
        'stock_movements', sm.id,
        'stock.landed_cost.distributed', 'adjusted_by',
        jsonb_build_object('distributed_amount', v_distributed,
                           'product_id', v_line.product_id))
      FROM stock_movements sm
      WHERE sm.tenant_id = v_tid
        AND sm.reference_type = 'goods_receipt'
        AND sm.reference_id = v_line.receipt_id
        AND sm.product_id = v_line.product_id
        AND sm.movement_type = 'in'
      ORDER BY sm.id
      LIMIT 1
    );

    v_n := v_n + 1;
  END LOOP;

  UPDATE landed_costs SET status = 'distributed' WHERE id = p_landed_cost_id;

  RETURN jsonb_build_object('success', true, 'landed_cost_id', p_landed_cost_id,
                            'lignes', v_n, 'base', v_total_base);
END;
$$;

REVOKE ALL ON FUNCTION public.distribute_landed_cost(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.distribute_landed_cost(uuid) TO authenticated;

-- ── 4. Garde de suppression sur landed_costs ────────────────────────────────
-- (764 boucle sur le registre, mais landed_costs n'y était pas à ce moment ;
-- on pose la garde ici pour que la couverture soit immédiate.)
DROP TRIGGER IF EXISTS zz_garde_p5_suppression ON public.landed_costs;
CREATE TRIGGER zz_garde_p5_suppression
  BEFORE DELETE ON public.landed_costs
  FOR EACH ROW
  EXECUTE FUNCTION public.chain_refuser_suppression_liee('landed_costs', 'document');