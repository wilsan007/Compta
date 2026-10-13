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
-- IDEMPOTENCE — la doctrine du pont de la 415 : un frais DÉJÀ réparti
-- (`status = 'distributed'`) ne se répartit pas deux fois. Rejouer REND l'état
-- sans réécrire ni les `landed_cost_lines` ni la CUMP (le `total_amount`
-- appliqué deux fois fausserait le coût unitaire). Un frais ANNULÉ est refusé.
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

-- ── 3. Maillon : distribute_landed_cost modifié ─────────────────────────────
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
BEGIN
  SELECT * INTO v_lc FROM landed_costs WHERE id = p_landed_cost_id AND tenant_id = v_tid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Frais accessoire introuvable'; END IF;

  -- Calculer la base de répartition
  SELECT COALESCE(SUM(
    CASE v_lc.distribution_method
      WHEN 'value' THEN sm.unit_cost * sm.quantity
      WHEN 'quantity' THEN sm.quantity
      ELSE sm.unit_cost * sm.quantity
    END
  ), 0) INTO v_total_base
  FROM stock_movements sm
  WHERE sm.reference_type = 'goods_receipt'
    AND sm.tenant_id = v_tid
    AND sm.movement_type = 'in';

  IF v_total_base = 0 THEN
    RAISE EXCEPTION 'Aucune réception à répartir';
  END IF;

  -- Répartir
  FOR v_line IN
    SELECT id, product_id, unit_cost, quantity
    FROM stock_movements
    WHERE reference_type = 'goods_receipt' AND tenant_id = v_tid AND movement_type = 'in'
  LOOP
    v_distributed := v_lc.total_amount * (
      CASE v_lc.distribution_method
        WHEN 'value' THEN v_line.unit_cost * v_line.quantity
        WHEN 'quantity' THEN v_line.quantity
        ELSE v_line.unit_cost * v_line.quantity
      END / v_total_base
    );

    INSERT INTO landed_cost_lines (
      tenant_id, landed_cost_id, product_id,
      distributed_amount, original_unit_cost, new_unit_cost
    ) VALUES (
      v_tid, p_landed_cost_id, v_line.product_id,
      v_distributed, v_line.unit_cost,
      v_line.unit_cost + v_distributed / v_line.quantity
    );

    -- Ajuster le CUMP
    UPDATE stock_quantities
    SET unit_cost = unit_cost + v_distributed / v_line.quantity,
        updated_at = now()
    WHERE product_id = v_line.product_id AND tenant_id = v_tid;

    -- Lien chaîne : landed_costs → stock_movements
    PERFORM link_documents(
      v_tid,
      'landed_costs', p_landed_cost_id,
      'stock_movements', v_line.id,
      'stock.landed_cost.distributed', 'adjusted_by',
      jsonb_build_object('distributed_amount', v_distributed,
                         'product_id', v_line.product_id)
    );
  END LOOP;

  UPDATE landed_costs SET status = 'distributed' WHERE id = p_landed_cost_id;

  RETURN jsonb_build_object('success', true, 'landed_cost_id', p_landed_cost_id);
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