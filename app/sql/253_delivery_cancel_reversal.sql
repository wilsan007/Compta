-- ============================================================
-- 253_delivery_cancel_reversal.sql — le pendant de la 251, côté vente
--
-- La 230 avait mesuré et fermé la moitié du chemin : expédier sort le stock
-- une seule fois, et réexpédier un BL annulé est refusé explicitement. Elle
-- écrivait elle-même ce qui restait : « Hors périmètre, inscrit au registre :
-- annuler un BL expédié ne contrepasse pas la sortie de stock ».
--
-- Mesuré AVANT la 253 (base neuve, 252 migrations, suite 253) :
--   T01 ✅ expédier un BL de 10 : une sortie, article et dépôt à 990
--   T02 ❌ annuler un BL expédié : stock toujours à 990, 0 contrepassation
--   T03 ❌ aucune garde : une seconde annulation contrepasserait deux fois
--   T04 ❌ (la non-régression de la 230) stock non rendu, donc incohérent
--   T05 ❌ annuler un BL livré : rien non plus
--
-- Ce que ce fichier fait : une sortie miroir par entrée d'origine, au même
-- coût, référence `BL-ANN-<numéro>`, `reference_type = 'delivery_note_cancel'`.
-- L'écriture inverse suit au journal **ST** par le déclencheur existant, et
-- l'écriture d'origine reste intacte — contrepassation, jamais réécriture.
-- Une seconde annulation est refusée (`23505`).
-- ============================================================
CREATE OR REPLACE FUNCTION public.reverse_stock_on_delivery_cancel()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_src RECORD;
  v_cout numeric;
  v_n int := 0;
BEGIN
  IF NOT (NEW.status = 'cancelled' AND OLD.status IN ('shipped', 'delivered')) THEN
    RETURN NEW;
  END IF;

  -- Une contrepassation ne s'écrit qu'une fois.
  IF EXISTS (
    SELECT 1 FROM stock_movements sm
    WHERE sm.tenant_id = NEW.tenant_id
      AND sm.reference_type = 'delivery_note_cancel'
      AND sm.reference_id = NEW.id)
  THEN
    RAISE EXCEPTION 'BL % : sa contrepassation de stock est déjà écrite. Annuler deux fois ne remet pas le stock deux fois.', NEW.number
      USING ERRCODE = '23505';
  END IF;

  FOR v_src IN
    SELECT * FROM stock_movements sm
    WHERE sm.tenant_id = NEW.tenant_id
      AND sm.reference_type = 'delivery_note'
      AND sm.reference_id = NEW.id
      AND sm.movement_type = 'out'
    ORDER BY sm.created_at NULLS LAST, sm.id
  LOOP
    -- Le coût de la contrepassation est celui que la comptabilité a sorti : la
    -- sortie d'origine ne porte pas toujours de coût (elle laisse le CUMP du
    -- dépôt le calculer), et recopier 0 ne créerait ni couche ni écriture.
    -- Mesuré avant ce repli : couches 990 au lieu de 1 000, aucune écriture.
    SELECT NULLIF(COALESCE(sq.unit_cost, 0), 0) INTO v_cout
    FROM stock_quantities sq
    WHERE sq.tenant_id = NEW.tenant_id
      AND sq.product_id = v_src.product_id
      AND sq.warehouse_id = v_src.warehouse_id;

    v_cout := COALESCE(NULLIF(COALESCE(v_src.unit_cost, 0), 0), v_cout);
    IF v_cout IS NULL THEN
      SELECT NULLIF(COALESCE(p.cost_price, 0), 0) INTO v_cout
      FROM products p WHERE p.id = v_src.product_id AND p.tenant_id = NEW.tenant_id;
    END IF;
    v_cout := COALESCE(v_cout, 0);

    INSERT INTO stock_movements (
      tenant_id, product_id, warehouse_id, movement_type, type, quantity, unit_cost,
      lot_id, serial_id,
      reference, reference_type, reference_id,
      date, movement_date, notes
    ) VALUES (
      NEW.tenant_id, v_src.product_id, v_src.warehouse_id, 'in', 'in', v_src.quantity, v_cout,
      v_src.lot_id, v_src.serial_id,
      'BL-ANN-' || NEW.number, 'delivery_note_cancel', NEW.id,
      CURRENT_DATE, CURRENT_DATE,
      'Annulation du bon de livraison ' || NEW.number
    );
    v_n := v_n + 1;
  END LOOP;

  RETURN NEW;
END $$;

COMMENT ON FUNCTION public.reverse_stock_on_delivery_cancel() IS
  '253 : annuler un bon de livraison expédié ou livré écrit la sortie de stock miroir, et son écriture au journal ST. L''écriture d''origine reste intacte — contrepassation, jamais réécriture.';

DROP TRIGGER IF EXISTS trg_delivery_cancel_reverse ON delivery_notes;
CREATE TRIGGER trg_delivery_cancel_reverse
  AFTER UPDATE OF status ON delivery_notes
  FOR EACH ROW
  EXECUTE FUNCTION public.reverse_stock_on_delivery_cancel();

-- ─────────────────────────────────────────────────────────────
-- Droits — un déclencheur n'est pas une RPC (leçon de la 228)
-- ─────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.reverse_stock_on_delivery_cancel() FROM PUBLIC, anon, authenticated;
