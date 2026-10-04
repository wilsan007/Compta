-- ============================================================
-- 139_align_stock_movement_types.sql
-- LOT1-02 : Aligner type et movement_type sur stock_movements
-- type (in,out,adjustment) était plus restrictif que movement_type
-- (in,out,transfer,adjustment,initial). L'insertion de 'initial' échouait.
-- ============================================================

-- 1. Élargir la contrainte de type pour aligner sur movement_type
ALTER TABLE stock_movements DROP CONSTRAINT IF EXISTS stock_movements_type_check;
ALTER TABLE stock_movements ADD CONSTRAINT stock_movements_type_check
  CHECK (type = ANY (ARRAY['in','out','transfer','adjustment','initial']));

-- 2. Synchroniser les valeurs existantes (type = movement_type)
UPDATE stock_movements SET type = movement_type
  WHERE type IS DISTINCT FROM movement_type AND movement_type IS NOT NULL;

-- 3. Empêcher la divergence future
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'stock_movements_type_coherence'
  ) THEN
    ALTER TABLE stock_movements ADD CONSTRAINT stock_movements_type_coherence
      CHECK (type = movement_type);
  END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
