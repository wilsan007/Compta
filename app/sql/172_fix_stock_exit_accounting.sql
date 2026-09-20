-- ============================================================
-- 172_fix_stock_exit_accounting.sql
--
-- Les sorties de stock ne produisaient AUCUNE écriture comptable.
--
-- `create_journal_on_stock_movement` commençait par :
--     IF NEW.unit_cost IS NULL OR NEW.unit_cost <= 0 THEN RETURN NEW; END IF;
-- Or une sortie n'a pas de coût unitaire propre : c'est la valeur du stock
-- détenu qui la valorise. `create_stock_out_on_delivery` insère d'ailleurs ses
-- mouvements sans `unit_cost`. La branche `movement_type = 'out'` de la fonction
-- était donc inatteignable en pratique : le compte 310000 n'était jamais crédité.
--
-- Effet mesuré avant correctif : entrées 100 @ 10 puis 100 @ 14, sortie de 50.
--   stock réel        150 unités, CUMP 12  → valorisation 1 800
--   compte 310000     2 400 (les deux entrées, aucune sortie)
-- L'écart grandit à chaque livraison : actif surévalué, charges sous-évaluées.
--
-- Correctif : une sortie sans `unit_cost` est valorisée au CUMP du stock au
-- moment du mouvement. Les ajustements sont laissés strictement inchangés : leur
-- `quantity` est une quantité absolue, pas une variation, donc les valoriser
-- produirait une écriture fausse — défaut distinct, signalé, non traité ici. L'ordre des triggers AFTER de
-- `stock_movements` est alphabétique — `create_journal_stock_movement` s'exécute
-- avant `update_stock_on_movement` et `update_cump` — donc `stock_quantities`
-- porte encore le CUMP d'avant la sortie, qui est exactement la valeur à sortir.
-- Une sortie sans entrepôt — c'est le cas de `create_stock_out_on_delivery` —
-- est valorisée au CUMP pondéré de toutes les lignes de stock du produit.
-- Repli : `products.cost_price`. Si les deux sont nuls, aucune écriture (rien à
-- comptabiliser), comportement inchangé.
--
-- Au passage : `consume_valuation_layers_on_exit` triait les couches sur
-- `CASE WHEN v_method = 'lifo' … CASE WHEN v_method = 'fifo' …` alors que
-- `v_method` vaut `'cump'` : les deux CASE valaient NULL et **l'ordre de
-- consommation était indéfini**. Repli explicite en FIFO — et `created_at` ne
-- suffit pas à départager : il vaut `NOW()`, figé sur toute la transaction, donc
-- deux couches créées dans la même transaction sont à égalité et l'ordre
-- retombait au hasard du plan. Une colonne `seq` monotone tranche.
-- ============================================================

-- Ordinal d'insertion : `created_at` vaut NOW(), figé par transaction, donc
-- inutilisable pour départager deux couches créées ensemble.
ALTER TABLE public.stock_valuation_layers ADD COLUMN IF NOT EXISTS seq bigserial;

CREATE OR REPLACE FUNCTION public.create_journal_on_stock_movement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_entry_id uuid;
  v_number text;
  v_amount numeric;
  v_unit_cost numeric;
  v_product RECORD;
  v_stock_account text := '310000';
  v_variation_account text := '603000';
  v_existing uuid;
BEGIN
  -- Ne pas générer pour les transferts internes ni les entrées initiales
  IF NEW.movement_type NOT IN ('in', 'out', 'adjustment') THEN
    RETURN NEW;
  END IF;

  SELECT * INTO v_product FROM products WHERE id = NEW.product_id AND tenant_id = NEW.tenant_id;

  -- Valorisation du mouvement
  v_unit_cost := NULLIF(COALESCE(NEW.unit_cost, 0), 0);

  IF v_unit_cost IS NULL AND NEW.movement_type = 'out' THEN
    -- Sortie : au CUMP détenu. Ce trigger s'exécute avant `update_stock_on_movement`
    -- (ordre alphabétique des triggers AFTER), donc la ligne porte encore le coût
    -- d'avant le mouvement.
    IF NEW.warehouse_id IS NOT NULL THEN
      SELECT NULLIF(COALESCE(sq.unit_cost, 0), 0) INTO v_unit_cost
      FROM stock_quantities sq
      WHERE sq.product_id = NEW.product_id
        AND sq.warehouse_id = NEW.warehouse_id
        AND sq.tenant_id = NEW.tenant_id;
    ELSE
      -- Sortie sans entrepôt (`create_stock_out_on_delivery` n'en renseigne pas) :
      -- CUMP pondéré sur toutes les lignes de stock du produit.
      SELECT NULLIF(SUM(sq.quantity * COALESCE(sq.unit_cost, 0)) / NULLIF(SUM(sq.quantity), 0), 0)
      INTO v_unit_cost
      FROM stock_quantities sq
      WHERE sq.product_id = NEW.product_id
        AND sq.tenant_id = NEW.tenant_id;
    END IF;

    IF v_unit_cost IS NULL THEN
      v_unit_cost := NULLIF(COALESCE(v_product.cost_price, 0), 0);
    END IF;
  END IF;

  -- Rien de valorisable : rien à comptabiliser
  IF v_unit_cost IS NULL THEN
    RETURN NEW;
  END IF;

  v_amount := NEW.quantity * v_unit_cost;
  IF v_amount = 0 THEN RETURN NEW; END IF;

  -- Éviter les doublons
  SELECT id INTO v_existing
  FROM journal_entries
  WHERE tenant_id = NEW.tenant_id
    AND piece_number = 'STK-' || NEW.id::text
  LIMIT 1;

  IF v_existing IS NOT NULL THEN RETURN NEW; END IF;

  v_number := 'JE-STK-' || to_char(NOW(), 'YYYYMMDDHH24MISS') || '-' || substr(NEW.id::text, 1, 8);

  INSERT INTO journal_entries (
    tenant_id, number, date, journal_code, status,
    description, piece_number, reference
  ) VALUES (
    NEW.tenant_id, v_number, COALESCE(NEW.movement_date, NEW.date, CURRENT_DATE),
    'ST', 'draft',
    'Mouvement de stock ' || COALESCE(NEW.reference, NEW.id::text),
    'STK-' || NEW.id::text,
    NEW.reference
  )
  RETURNING id INTO v_entry_id;

  IF NEW.movement_type IN ('in', 'adjustment') THEN
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
  END IF;

  -- Bascule en 'posted' APRÈS les lignes (SOC-01)
  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id;

  RETURN NEW;
END;
$function$;

-- ------------------------------------------------------------
-- Ordre de consommation des couches : déterministe
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.consume_valuation_layers_on_exit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_remaining_to_consume numeric := abs(NEW.quantity);
  v_layer RECORD;
  v_consumed numeric;
  v_method text := 'cump';  -- par défaut ; sera paramétrable
BEGIN
  IF NEW.movement_type NOT IN ('out') THEN
    RETURN NEW;
  END IF;

  -- LIFO si demandé, FIFO dans tous les autres cas (y compris 'cump').
  -- Avant : les deux CASE valaient NULL quand v_method = 'cump' et l'ordre de
  -- consommation était laissé au hasard du plan d'exécution.
  FOR v_layer IN
    SELECT * FROM stock_valuation_layers
    WHERE tenant_id = NEW.tenant_id
      AND product_id = NEW.product_id
      AND COALESCE(warehouse_id, NEW.warehouse_id) = NEW.warehouse_id
      AND remaining_qty > 0
    ORDER BY
      CASE WHEN v_method = 'lifo' THEN seq END DESC NULLS LAST,
      created_at ASC,
      seq ASC
    FOR UPDATE
  LOOP
    EXIT WHEN v_remaining_to_consume <= 0;
    v_consumed := LEAST(v_remaining_to_consume, v_layer.remaining_qty);
    UPDATE stock_valuation_layers
    SET remaining_qty = remaining_qty - v_consumed,
        value = (remaining_qty - v_consumed) * unit_cost
    WHERE id = v_layer.id;
    v_remaining_to_consume := v_remaining_to_consume - v_consumed;
  END LOOP;

  RETURN NEW;
END;
$function$;
