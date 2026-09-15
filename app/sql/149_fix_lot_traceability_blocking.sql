-- ============================================================
-- 149_fix_lot_traceability_blocking.sql
-- LOT4-14 : Traçabilité lot bloquante (latente)
--
-- Problème : check_tracking_on_sm lève une exception si lot_id est nul
-- pour un produit avec tracking='lot'. Aucun trigger automatisé ne
-- renseigne lot_id, et les tables de lignes ne portent pas la colonne.
--
-- Fix (étape 1) : Dégrader en avertissement tracé au lieu de bloquer.
-- Fix (étape 2) : Ajouter lot_id/serial_id aux tables de lignes.
-- ============================================================

-- ============================================================
-- Étape 2 : Ajouter lot_id et serial_id aux tables de lignes
-- ============================================================
ALTER TABLE delivery_note_lines ADD COLUMN IF NOT EXISTS lot_id uuid;
ALTER TABLE delivery_note_lines ADD COLUMN IF NOT EXISTS serial_id uuid;

ALTER TABLE goods_receipt_lines ADD COLUMN IF NOT EXISTS lot_id uuid;
ALTER TABLE goods_receipt_lines ADD COLUMN IF NOT EXISTS serial_id uuid;

ALTER TABLE bom_lines ADD COLUMN IF NOT EXISTS lot_id uuid;

-- Table des avertissements de traçabilité
CREATE TABLE IF NOT EXISTS tracking_warnings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  product_id uuid NOT NULL,
  movement_id uuid,
  warning_type text NOT NULL CHECK (warning_type IN ('missing_lot', 'missing_serial')),
  message text,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE tracking_warnings ENABLE ROW LEVEL SECURITY;
CREATE POLICY tracking_warnings_tenant ON tracking_warnings
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- ============================================================
-- Étape 1 : Dégrader le contrôle en avertissement tracé
-- ============================================================
CREATE OR REPLACE FUNCTION check_tracking_on_stock_movement()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tracking text;
BEGIN
  SELECT tracking INTO v_tracking
  FROM products
  WHERE id = NEW.product_id AND tenant_id = NEW.tenant_id;

  -- LOT4-14 : Dégrader en avertissement au lieu de bloquer
  IF v_tracking = 'lot' AND NEW.lot_id IS NULL THEN
    INSERT INTO tracking_warnings (tenant_id, product_id, movement_id, warning_type, message)
    VALUES (NEW.tenant_id, NEW.product_id, NEW.id, 'missing_lot',
      'Lot obligatoire non renseigné pour le produit ' || NEW.product_id);
    -- Ne pas bloquer : RETURN NEW au lieu de RAISE EXCEPTION
  ELSIF v_tracking = 'serial' AND NEW.serial_id IS NULL THEN
    INSERT INTO tracking_warnings (tenant_id, product_id, movement_id, warning_type, message)
    VALUES (NEW.tenant_id, NEW.product_id, NEW.id, 'missing_serial',
      'Numéro de série obligatoire non renseigné pour le produit ' || NEW.product_id);
  END IF;

  RETURN NEW;
END;
$$;
