-- ============================================================
-- 117_pricing_and_credit.sql
-- VTE-01 : Grilles tarifaires + VTE-02 : Contrôle d'encours client
-- ============================================================

-- ============================================================
-- VTE-01 : Étendre price_lists avec validité et priorité
-- ============================================================
ALTER TABLE price_lists ADD COLUMN IF NOT EXISTS valid_from date;
ALTER TABLE price_lists ADD COLUMN IF NOT EXISTS valid_to date;
ALTER TABLE price_lists ADD COLUMN IF NOT EXISTS priority int DEFAULT 0;
ALTER TABLE price_lists ADD COLUMN IF NOT EXISTS customer_category_id uuid;
ALTER TABLE price_lists ADD COLUMN IF NOT EXISTS base_price_list_id uuid;
ALTER TABLE price_lists ADD COLUMN IF NOT EXISTS discount_percent numeric;

-- ============================================================
-- VTE-01 : Fonction de résolution de prix
-- ============================================================
CREATE OR REPLACE FUNCTION resolve_price(
  p_product_id uuid,
  p_customer_id uuid,
  p_quantity numeric DEFAULT 1,
  p_date date DEFAULT CURRENT_DATE
)
RETURNS TABLE(
  unit_price numeric,
  discount_percent numeric,
  price_list_id uuid,
  price_list_name text,
  source text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_line record;
  v_base_price numeric;
BEGIN
  -- Chercher la ligne de tarif la plus spécifique
  SELECT pll.unit_price, pll.discount_percent, pll.min_quantity,
         pl.id, pl.name, pl.base_price_list_id, pl.discount_percent AS pl_discount
  INTO v_line
  FROM price_list_lines pll
  JOIN price_lists pl ON pl.id = pll.price_list_id AND pl.tenant_id = pll.tenant_id
  WHERE pll.tenant_id = v_tid
    AND pll.product_id = p_product_id
    AND pl.type = 'sales'
    AND pll.min_quantity <= p_quantity
    AND COALESCE(pl.valid_from, p_date) <= p_date
    AND COALESCE(pl.valid_to, '9999-12-31'::date) >= p_date
    AND (pl.customer_id = p_customer_id OR pl.customer_id IS NULL)
  ORDER BY
    -- Client spécifique avant général
    (pl.customer_id IS NOT NULL) DESC,
    -- Priorité la plus haute d'abord
    pl.priority DESC NULLS LAST,
    -- Quantité minimale la plus haute d'abord
    pll.min_quantity DESC
  LIMIT 1;

  IF v_line.id IS NULL THEN
    RETURN;
  END IF;

  -- Gérer les tarifs en pourcentage d'un autre tarif
  IF v_line.base_price_list_id IS NOT NULL THEN
    SELECT unit_price INTO v_base_price
    FROM price_list_lines
    WHERE tenant_id = v_tid
      AND price_list_id = v_line.base_price_list_id
      AND product_id = p_product_id
      AND min_quantity <= p_quantity
    ORDER BY min_quantity DESC
    LIMIT 1;

    IF v_base_price IS NOT NULL THEN
      RETURN QUERY
      SELECT
        v_base_price * (1 - COALESCE(v_line.pl_discount, 0) / 100),
        COALESCE(v_line.discount_percent, 0),
        v_line.id,
        v_line.name,
        'price_list:' || v_line.name
      ;
      RETURN;
    END IF;
  END IF;

  RETURN QUERY
  SELECT
    v_line.unit_price,
    COALESCE(v_line.discount_percent, 0),
    v_line.id,
    v_line.name,
    'price_list:' || v_line.name
  ;
END;
$$;

-- ============================================================
-- VTE-02 : Trigger de contrôle d'encours client
-- ============================================================
CREATE OR REPLACE FUNCTION check_customer_credit_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_limit numeric;
  v_outstanding numeric;
  v_policy text;
BEGIN
  -- Ne vérifier que lors du passage à 'confirmed'
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status <> 'confirmed' THEN
    RETURN NEW;
  END IF;

  -- Récupérer la limite et la politique
  SELECT COALESCE(credit_limit, 0), COALESCE(credit_policy, 'blocking')
  INTO v_limit, v_policy
  FROM customers
  WHERE id = NEW.customer_id AND tenant_id = NEW.tenant_id;

  -- 0 = pas de plafond
  IF v_limit <= 0 THEN
    RETURN NEW;
  END IF;

  -- Encours = factures non soldées + commandes confirmées non facturées
  SELECT COALESCE(SUM(amount_due), 0)
  INTO v_outstanding
  FROM invoices
  WHERE customer_id = NEW.customer_id
    AND tenant_id = NEW.tenant_id
    AND payment_state IN ('not_paid', 'partial');

  -- Ajouter les commandes confirmées non facturées
  v_outstanding := v_outstanding + COALESCE((
    SELECT SUM(total)
    FROM sales_orders
    WHERE customer_id = NEW.customer_id
      AND tenant_id = NEW.tenant_id
      AND status = 'confirmed'
      AND id <> NEW.id
  ), 0);

  -- Vérifier le dépassement
  IF v_outstanding + NEW.total > v_limit THEN
    IF v_policy = 'blocking' THEN
      RAISE EXCEPTION
        'Encours dépassé : % + % > limite % — validation requise',
        v_outstanding, NEW.total, v_limit;
    ELSIF v_policy = 'warning' THEN
      -- Marquer la commande avec un avertissement mais ne pas bloquer
      NEW.credit_warning := true;
    END IF;
  END IF;

  -- Mettre à jour l'encours utilisé
  UPDATE customers
  SET credit_used = v_outstanding + NEW.total,
    updated_at = now()
  WHERE id = NEW.customer_id AND tenant_id = NEW.tenant_id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS check_credit_limit_trigger ON sales_orders;
CREATE TRIGGER check_credit_limit_trigger
  BEFORE UPDATE ON sales_orders
  FOR EACH ROW
  EXECUTE FUNCTION check_customer_credit_limit();

-- ============================================================
-- VTE-02 : Colonne credit_policy sur customers et credit_warning sur sales_orders
-- ============================================================
ALTER TABLE customers ADD COLUMN IF NOT EXISTS credit_policy text
  DEFAULT 'blocking' CHECK (credit_policy IN ('blocking', 'warning', 'information'));
ALTER TABLE customers ADD COLUMN IF NOT EXISTS credit_warning boolean DEFAULT false;
ALTER TABLE sales_orders ADD COLUMN IF NOT EXISTS credit_warning boolean DEFAULT false;

