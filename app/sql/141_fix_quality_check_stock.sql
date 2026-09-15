-- ============================================================
-- 141_fix_quality_check_stock.sql
-- LOT4-05 : Double entrée réception + contrôle qualité
--
-- Problème : create_stock_in_on_quality_pass (133) crée un mouvement 'in'
-- au passage du QC, même si la réception a déjà créé un mouvement 'in'.
-- Le check d'idempotence (COUNT = 0) est fragile.
--
-- Fix : La réception crée l'entrée. Le QC ne crée plus de mouvement
-- en cas de succès. En cas d'échec, il crée un mouvement 'out' (rebut).
-- ============================================================

CREATE OR REPLACE FUNCTION create_stock_in_on_quality_pass()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_gr_line RECORD;
BEGIN
  -- LOT4-05 : Le QC ne crée plus de mouvement en cas de succès.
  -- La réception (create_stock_on_goods_receipt) a déjà créé l'entrée.
  -- En cas d'échec, on crée un mouvement 'out' vers le rebut.
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'failed' THEN
    IF NEW.reference_type = 'goods_receipt' AND NEW.reference_id IS NOT NULL THEN
      FOR v_gr_line IN
        SELECT * FROM goods_receipt_lines
        WHERE goods_receipt_id = NEW.reference_id
          AND tenant_id = NEW.tenant_id
          AND product_id = NEW.product_id
          AND quantity_received > 0
      LOOP
        INSERT INTO stock_movements (
          tenant_id, product_id, movement_type, type, quantity,
          reference, reference_type, reference_id,
          date, movement_date, notes
        ) VALUES (
          NEW.tenant_id, NEW.product_id, 'out', 'out', v_gr_line.quantity_received,
          'QC-REJECT-' || COALESCE(NEW.checked_by, 'auto'),
          'quality_check', NEW.id,
          CURRENT_DATE, CURRENT_DATE, 'Rebut après contrôle qualité échoué'
        );
      END LOOP;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
