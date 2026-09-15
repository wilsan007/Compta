-- ============================================================
-- 87_stock_valuation_to_gl.sql
--
-- Fonctions de stock manquantes + valorisation → écritures comptables.
--
-- Inspiré de :
--   - Odoo (stock move → accounting entry, anglo-saxon accounting)
--   - ERPNext (stock ledger → GL entry, stock valuation)
--   - Sage Intacct (inventory valuation → GL posting)
--
-- Contenu :
--   A. Fonctions de stock (increment_stock, decrement_stock) — depuis le schéma de production
--   B. Trigger update_stock_on_movement — met à jour products.stock_quantity
--   C. Trigger create_journal_on_stock_movement — valorisation → écriture comptable
-- ============================================================

-- ============================================================
-- SECTION A — Fonctions de stock (depuis le schéma de production)
-- ============================================================

-- A1. increment_stock : augmente le stock d'un produit
DROP FUNCTION IF EXISTS increment_stock(uuid, numeric, uuid) CASCADE;
CREATE OR REPLACE FUNCTION increment_stock(p_product_id uuid, p_qty numeric, p_warehouse_id uuid DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- Mettre à jour stock_quantities par entrepôt
  IF p_warehouse_id IS NOT NULL THEN
    UPDATE stock_quantities
      SET quantity = quantity + p_qty, updated_at = NOW()
      WHERE product_id = p_product_id
        AND warehouse_id = p_warehouse_id
        AND tenant_id = v_tid;

    -- Créer la ligne si elle n'existe pas avec unit_cost initialisé depuis le prix de revient du produit
    IF NOT FOUND THEN
      INSERT INTO stock_quantities (tenant_id, product_id, warehouse_id, quantity, unit_cost)
      SELECT v_tid, p_product_id, p_warehouse_id, p_qty, COALESCE(p.cost_price, 0)
      FROM products p
      WHERE p.id = p_product_id AND p.tenant_id = v_tid
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;

  -- Mettre à jour le stock total sur products
  UPDATE products
    SET stock_quantity = COALESCE(stock_quantity, 0) + p_qty,
        updated_at = NOW()
    WHERE id = p_product_id AND tenant_id = v_tid;
END;
$$;

-- A2. decrement_stock : diminue le stock d'un produit (avec vérification)
DROP FUNCTION IF EXISTS decrement_stock(uuid, numeric, uuid) CASCADE;
CREATE OR REPLACE FUNCTION decrement_stock(p_product_id uuid, p_qty numeric, p_warehouse_id uuid DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_current numeric;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- Vérifier le stock disponible (avec verrou FOR UPDATE)
  SELECT stock_quantity INTO v_current
  FROM products
  WHERE id = p_product_id AND tenant_id = v_tid
  FOR UPDATE;

  IF v_current IS NULL THEN
    RAISE EXCEPTION 'Produit % non trouvé', p_product_id;
  END IF;

  IF v_current < p_qty THEN
    RAISE EXCEPTION 'Stock insuffisant: disponible=%, demandé=%', v_current, p_qty;
  END IF;

  -- Mettre à jour stock_quantities par entrepôt
  IF p_warehouse_id IS NOT NULL THEN
    UPDATE stock_quantities
      SET quantity = GREATEST(quantity - p_qty, 0), updated_at = NOW()
      WHERE product_id = p_product_id
        AND warehouse_id = p_warehouse_id
        AND tenant_id = v_tid;
  END IF;

  -- Mettre à jour le stock total
  UPDATE products
    SET stock_quantity = stock_quantity - p_qty,
        updated_at = NOW()
    WHERE id = p_product_id AND tenant_id = v_tid;
END;
$$;


-- ============================================================
-- SECTION B — Trigger : mettre à jour le stock après un mouvement
-- ============================================================
-- Inspiré de : Odoo (stock move → update quantity on hand),
--              ERPNext (stock entry → stock ledger update)
DROP FUNCTION IF EXISTS update_stock_on_movement() CASCADE;
CREATE OR REPLACE FUNCTION update_stock_on_movement()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.movement_type = 'in' THEN
    PERFORM increment_stock(NEW.product_id, NEW.quantity, NEW.warehouse_id);
  ELSIF NEW.movement_type = 'out' THEN
    PERFORM decrement_stock(NEW.product_id, NEW.quantity, NEW.warehouse_id);
  ELSIF NEW.movement_type = 'adjustment' THEN
    -- Pour un ajustement, quantity est la nouvelle valeur absolue
    UPDATE products
      SET stock_quantity = NEW.quantity, updated_at = NOW()
      WHERE id = NEW.product_id AND tenant_id = NEW.tenant_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS update_stock_on_movement ON stock_movements;
CREATE TRIGGER update_stock_on_movement
  AFTER INSERT ON stock_movements
  FOR EACH ROW
  EXECUTE FUNCTION update_stock_on_movement();


-- ============================================================
-- SECTION C — Trigger : valorisation du stock → écriture comptable
-- ============================================================
-- Inspiré de : Odoo (anglo-saxon stock accounting: stock move → journal entry),
--              ERPNext (stock entry → GL entry with valuation)
--
-- Quand un mouvement de stock a un unit_cost > 0, on génère une écriture :
--   - movement_type = 'in'  → Débit 310000 (stock) / Crédit 603000 (variation de stock)
--   - movement_type = 'out' → Débit 603000 (variation de stock) / Crédit 310000 (stock)
--   - movement_type = 'adjustment' → Débit/Crédit 310000 / 603000 selon le sens
--
-- Les comptes par défaut peuvent être surchargés par une table de mapping
-- product_category → account. Pour l'instant on utilise les comptes standards.
DROP FUNCTION IF EXISTS create_journal_on_stock_movement() CASCADE;
CREATE OR REPLACE FUNCTION create_journal_on_stock_movement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_entry_id uuid;
  v_number text;
  v_amount numeric;
  v_product RECORD;
  v_stock_account text := '310000';
  v_variation_account text := '603000';
  v_existing uuid;
BEGIN
  -- Ne générer une écriture que si unit_cost est renseigné et > 0
  IF NEW.unit_cost IS NULL OR NEW.unit_cost <= 0 THEN
    RETURN NEW;
  END IF;

  -- Ne pas générer pour les transferts internes
  IF NEW.movement_type NOT IN ('in', 'out', 'adjustment') THEN
    RETURN NEW;
  END IF;

  v_amount := NEW.quantity * NEW.unit_cost;
  IF v_amount = 0 THEN RETURN NEW; END IF;

  -- Récupérer le produit pour d'éventuels comptes spécifiques
  SELECT * INTO v_product FROM products WHERE id = NEW.product_id AND tenant_id = NEW.tenant_id;

  -- Éviter les doublons : vérifier qu'une écriture n'existe pas déjà pour ce mouvement
  SELECT id INTO v_existing
  FROM journal_entries
  WHERE tenant_id = NEW.tenant_id
    AND piece_number = 'STK-' || NEW.id::text
  LIMIT 1;

  IF v_existing IS NOT NULL THEN RETURN NEW; END IF;

  v_number := 'JE-STK-' || to_char(NOW(), 'YYYYMMDDHH24MISS') || '-' || substr(NEW.id::text, 1, 8);

  -- Insérer l'entête
  INSERT INTO journal_entries (
    tenant_id, number, date, journal_code, status,
    description, piece_number, reference
  ) VALUES (
    NEW.tenant_id, v_number, COALESCE(NEW.movement_date, NEW.date, CURRENT_DATE),
    'ST', 'posted',
    'Mouvement de stock ' || COALESCE(NEW.reference, NEW.id::text),
    'STK-' || NEW.id::text,
    NEW.reference
  )
  RETURNING id INTO v_entry_id;

  -- Insérer les lignes selon le type de mouvement
  IF NEW.movement_type = 'in' THEN
    -- Entrée en stock : Débit 310 (stock) / Crédit 603 (variation)
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order, product_id, quantity
    ) VALUES
      (NEW.tenant_id, v_entry_id, v_stock_account, v_stock_account,
       v_amount, 0, 'Entrée en stock - ' || COALESCE(v_product.name, 'Produit'), 0,
       NEW.product_id, NEW.quantity),
      (NEW.tenant_id, v_entry_id, v_variation_account, v_variation_account,
       0, v_amount, 'Variation de stock (entrée) - ' || COALESCE(v_product.name, 'Produit'), 1,
       NEW.product_id, NEW.quantity);

  ELSIF NEW.movement_type = 'out' THEN
    -- Sortie de stock : Débit 603 (variation) / Crédit 310 (stock)
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order, product_id, quantity
    ) VALUES
      (NEW.tenant_id, v_entry_id, v_variation_account, v_variation_account,
       v_amount, 0, 'Variation de stock (sortie) - ' || COALESCE(v_product.name, 'Produit'), 0,
       NEW.product_id, NEW.quantity),
      (NEW.tenant_id, v_entry_id, v_stock_account, v_stock_account,
       0, v_amount, 'Sortie de stock - ' || COALESCE(v_product.name, 'Produit'), 1,
       NEW.product_id, NEW.quantity);

  ELSIF NEW.movement_type = 'adjustment' THEN
    -- Ajustement : Débit ou Crédit selon le sens de la variation
    -- Si quantity augmente → Débit 310 / Crédit 603
    -- Si quantity diminue → Débit 603 / Crédit 310
    -- (Pour un ajustement, on suppose que unit_cost représente la valeur unitaire)
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order, product_id, quantity
    ) VALUES
      (NEW.tenant_id, v_entry_id, v_stock_account, v_stock_account,
       v_amount, 0, 'Ajustement de stock (entrée) - ' || COALESCE(v_product.name, 'Produit'), 0,
       NEW.product_id, NEW.quantity),
      (NEW.tenant_id, v_entry_id, v_variation_account, v_variation_account,
       0, v_amount, 'Variation de stock (ajustement) - ' || COALESCE(v_product.name, 'Produit'), 1,
       NEW.product_id, NEW.quantity);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS create_journal_stock_movement ON stock_movements;
CREATE TRIGGER create_journal_stock_movement
  AFTER INSERT ON stock_movements
  FOR EACH ROW
  EXECUTE FUNCTION create_journal_on_stock_movement();


-- ============================================================
-- SECTION D — Fonction : calculer la valorisation du stock à une date
-- ============================================================
-- Inspiré de : Odoo (stock valuation report),
--              ERPNext (stock balance valuation)
-- Permet de calculer la valeur du stock à une date donnée.
DROP FUNCTION IF EXISTS get_stock_valuation(uuid, date) CASCADE;
CREATE OR REPLACE FUNCTION get_stock_valuation(p_tenant_id uuid, p_date date DEFAULT CURRENT_DATE)
RETURNS TABLE(
  product_id uuid,
  product_name text,
  quantity numeric,
  unit_cost numeric,
  total_value numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.id,
    p.name,
    COALESCE(p.stock_quantity, 0) as quantity,
    COALESCE(
      (SELECT unit_cost
       FROM stock_movements sm
       WHERE sm.product_id = p.id
         AND sm.tenant_id = p_tenant_id
         AND sm.movement_date <= p_date
       ORDER BY sm.movement_date DESC, sm.created_at DESC
       LIMIT 1),
      p.cost_price
    ) as unit_cost,
    COALESCE(p.stock_quantity, 0) * COALESCE(
      (SELECT unit_cost
       FROM stock_movements sm
       WHERE sm.product_id = p.id
         AND sm.tenant_id = p_tenant_id
         AND sm.movement_date <= p_date
       ORDER BY sm.movement_date DESC, sm.created_at DESC
       LIMIT 1),
      p.cost_price
    ) as total_value
  FROM products p
  WHERE p.tenant_id = p_tenant_id
    AND COALESCE(p.stock_quantity, 0) != 0
  ORDER BY total_value DESC;
END;
$$;


-- ============================================================
-- RÉCAPITULATIF
-- ============================================================
-- Fonctions créées :
--   increment_stock(product_id, qty, warehouse_id)  — augmente le stock
--   decrement_stock(product_id, qty, warehouse_id)  — diminue le stock (avec vérif)
--   update_stock_on_movement()                      — trigger met à jour stock
--   create_journal_on_stock_movement()              — trigger valorisation → GL
--   get_stock_valuation(tenant_id, date)            — valorisation à une date
--
-- Triggers créés :
--   update_stock_on_movement     ON stock_movements AFTER INSERT
--   create_journal_stock_movement ON stock_movements AFTER INSERT
--
-- Comptes utilisés (PCG français) :
--   310000 — Stocks de matières premières
--   603000 — Variation des stocks
--
-- Total : 5 fonctions + 2 triggers
-- ============================================================
