-- ============================================================
-- 658_landed_cost_receipts_and_fix.sql — STK-08 / E.3 (partie E)
-- Numéro pris le 2026-10-11 par migration-numero.mjs (ligne « plan6 E (opérations) », branche plan6/e-operations).
--
-- Constat (moteur mesuré) : `distribute_landed_cost` (125) répartit sur **toutes**
-- les réceptions de la société (`stock_movements WHERE reference_type='receipt'`),
-- sans lien avec les réceptions concernées ; elle divise par la quantité **sans
-- garde** ; elle met à jour `stock_quantities` de **tous** les dépôts du produit ;
-- elle n'est **pas idempotente** ; et `landed_costs` n'a **aucune** cible.
--
-- Décision : on donne à la dépense de frais ses **réceptions cibles**
-- (`landed_cost_receipts`), puis on réécrit le moteur pour ne répartir que sur
-- elles, avec les gardes et l'idempotence qui manquaient.
--   · méthode `value`    : quantité reçue × coût (cost_price, à défaut purchase_price) ;
--   · méthode `quantity` : quantité reçue ;
--   · méthode `weight`   : quantité reçue × poids de l'article ;
--   · méthode `volume`   : non modélisée (`products` n'a pas de volume) → repli sur `value`.
-- ============================================================

CREATE TABLE IF NOT EXISTS landed_cost_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  landed_cost_id uuid NOT NULL REFERENCES landed_costs(id) ON DELETE CASCADE,
  receipt_id uuid NOT NULL,
  created_at timestamptz DEFAULT now(),
  UNIQUE (landed_cost_id, receipt_id)
);

ALTER TABLE landed_cost_receipts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS landed_cost_receipts_tenant ON landed_cost_receipts;
CREATE POLICY landed_cost_receipts_tenant ON landed_cost_receipts
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- Clé étrangère composite vers la réception ciblée (doctrine 237 : une FK
-- mono-colonne relierait deux sociétés). Posée si la cible le permet.
DO $$ BEGIN
  ALTER TABLE landed_cost_receipts
    ADD CONSTRAINT landed_cost_receipts_receipt_fk
    FOREIGN KEY (receipt_id, tenant_id) REFERENCES goods_receipts(id, tenant_id) ON DELETE CASCADE;
EXCEPTION WHEN others THEN NULL;
END $$;

CREATE OR REPLACE FUNCTION distribute_landed_cost(p_landed_cost_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_lc landed_costs%ROWTYPE;
  v_total_base numeric := 0;
  v_line record;
  v_distributed numeric;
BEGIN
  SELECT * INTO v_lc FROM landed_costs WHERE id = p_landed_cost_id AND tenant_id = v_tid;
  IF v_lc.id IS NULL THEN RAISE EXCEPTION 'Frais accessoire introuvable'; END IF;
  IF v_lc.status = 'distributed' THEN
    RAISE EXCEPTION 'Frais accessoire % déjà réparti', COALESCE(v_lc.invoice_number, v_lc.id::text);
  END IF;

  -- Idempotence : toute répartition antérieure est effacée.
  DELETE FROM landed_cost_lines WHERE landed_cost_id = p_landed_cost_id AND tenant_id = v_tid;

  -- Base : les lignes des réceptions CIBLÉES (jamais toutes celles de la société).
  SELECT COALESCE(SUM(
    CASE v_lc.distribution_method
      WHEN 'quantity' THEN grl.quantity_received
      WHEN 'weight'   THEN grl.quantity_received * COALESCE(p.weight, 0)
      ELSE grl.quantity_received * COALESCE(p.cost_price, p.purchase_price, 0)
    END
  ), 0) INTO v_total_base
  FROM landed_cost_receipts lcr
  JOIN goods_receipt_lines grl ON grl.goods_receipt_id = lcr.receipt_id AND grl.tenant_id = v_tid
  JOIN products p ON p.id = grl.product_id AND p.tenant_id = v_tid
  WHERE lcr.landed_cost_id = p_landed_cost_id AND lcr.tenant_id = v_tid;

  IF v_total_base = 0 THEN
    RAISE EXCEPTION 'Aucune réception à répartir pour ce frais (base nulle)';
  END IF;

  FOR v_line IN
    SELECT grl.product_id, gr.warehouse_id, grl.quantity_received,
           CASE v_lc.distribution_method
             WHEN 'quantity' THEN grl.quantity_received
             WHEN 'weight'   THEN grl.quantity_received * COALESCE(p.weight, 0)
             ELSE grl.quantity_received * COALESCE(p.cost_price, p.purchase_price, 0)
           END AS base,
           COALESCE(p.cost_price, p.purchase_price, 0) AS unit_cost
    FROM landed_cost_receipts lcr
    JOIN goods_receipts gr ON gr.id = lcr.receipt_id AND gr.tenant_id = v_tid
    JOIN goods_receipt_lines grl ON grl.goods_receipt_id = gr.id AND grl.tenant_id = v_tid
    JOIN products p ON p.id = grl.product_id AND p.tenant_id = v_tid
    WHERE lcr.landed_cost_id = p_landed_cost_id AND lcr.tenant_id = v_tid
      AND COALESCE(grl.quantity_received, 0) <> 0
  LOOP
    v_distributed := v_lc.total_amount * (v_line.base / v_total_base);

    INSERT INTO landed_cost_lines (
      tenant_id, landed_cost_id, product_id,
      distributed_amount, original_unit_cost, new_unit_cost
    ) VALUES (
      v_tid, p_landed_cost_id, v_line.product_id,
      v_distributed, v_line.unit_cost,
      v_line.unit_cost + v_distributed / v_line.quantity_received
    );

    -- Le CUMP du couple (article, dépôt) de la réception — et de lui seul.
    UPDATE stock_quantities
    SET unit_cost = COALESCE(unit_cost, 0) + v_distributed / v_line.quantity_received,
        updated_at = now()
    WHERE tenant_id = v_tid AND product_id = v_line.product_id AND warehouse_id = v_line.warehouse_id;
  END LOOP;

  UPDATE landed_costs SET status = 'distributed' WHERE id = p_landed_cost_id AND tenant_id = v_tid;

  RETURN jsonb_build_object('success', true, 'landed_cost_id', p_landed_cost_id, 'base', v_total_base);
END;
$$;

COMMENT ON FUNCTION distribute_landed_cost(uuid) IS
  'STK-08 (658) : répartit une dépense de frais sur SES réceptions ciblées (landed_cost_receipts), ajuste le CUMP du couple (article, dépôt) de chaque réception, efface une répartition antérieure (idempotence) et refuse un second appel.';

REVOKE ALL ON FUNCTION distribute_landed_cost(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION distribute_landed_cost(uuid) TO authenticated;


