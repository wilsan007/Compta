-- ============================================================
-- 136_fix_stock_quantity_reserved.sql
-- LOT1-03 : Fusionner les colonnes de réservation
-- reserved_quantity (schéma d'origine) est la colonne canonique.
-- quantity_reserved (migration 118) est un doublon à supprimer.
-- ============================================================

-- 1. Copier les valeurs de quantity_reserved vers reserved_quantity
--    (seulement si quantity_reserved existe et a des valeurs non nulles)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'stock_quantities' AND column_name = 'quantity_reserved'
  ) THEN
    EXECUTE $q$
      UPDATE stock_quantities
      SET reserved_quantity = COALESCE(quantity_reserved, 0)
      WHERE COALESCE(quantity_reserved, 0) <> COALESCE(reserved_quantity, 0)
    $q$;
  END IF;
END $$;

-- 2. Supprimer la colonne générée quantity_available (dépend de quantity_reserved)
--    et la recréer avec reserved_quantity
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'stock_quantities' AND column_name = 'quantity_available'
  ) THEN
    ALTER TABLE stock_quantities DROP COLUMN quantity_available;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'stock_quantities' AND column_name = 'quantity_available'
  ) THEN
    ALTER TABLE stock_quantities
      ADD COLUMN quantity_available numeric GENERATED ALWAYS AS (quantity - reserved_quantity) STORED;
  END IF;
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

-- 3. Supprimer la colonne doublon quantity_reserved
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'stock_quantities' AND column_name = 'quantity_reserved'
  ) THEN
    ALTER TABLE stock_quantities DROP COLUMN quantity_reserved;
  END IF;
END $$;
