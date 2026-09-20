-- ============================================================
-- 176_fix_production_double_entry.sql
--
-- La production était comptabilisée deux fois.
--
-- À la clôture d'un ordre de fabrication, `create_stock_on_manufacturing_complete`
-- fait deux choses : il insère les mouvements de stock (entrée du produit fini,
-- sorties des composants) **et** il écrit lui-même l'écriture de production
-- dans le journal OF — 601000/310000 pour les matières, 355000/713550 pour le
-- produit fini.
--
-- Mais ces mouvements de stock portent un `unit_cost`, donc
-- `create_journal_on_stock_movement` les comptabilise **à son tour** dans le
-- journal ST. Les mêmes faits sont enregistrés deux fois, dans deux journaux.
--
-- Mesuré sur un OF de 5 unités (matières 200, MO 90, frais 18, total 308) :
--
--   journal OF   310000  C 200      601000  D 200
--                355000  D 308      713550  C 308     ← correct
--   journal ST   310000  D 308 C 200
--                603000  D 200 C 308                  ← doublon
--
--   compte 310000 : −92 au lieu de −200, soit **+108 de stock fantôme**
--   compte 603000 : −108 de variation fantôme
--   produit fini valorisé deux fois, en 355000 et dans 310000
--
-- Ce défaut est antérieur à `172_fix_stock_exit_accounting.sql` : vérifié en
-- rejouant le scénario avec la version précédente de la fonction, à l'identique.
-- La 172 ne l'a ni créé ni aggravé — les mouvements de production portaient
-- déjà un `unit_cost` non nul et passaient donc l'ancienne garde.
--
-- Correctif : le journal de stock ignore les mouvements issus de la production,
-- que `reference_type = 'production'` identifie sans ambiguïté. Les autres
-- origines — livraisons, réceptions, ajustements — restent comptabilisées par
-- lui, puisque personne d'autre ne le fait.
-- ============================================================

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

  -- La production écrit sa propre écriture (journal OF) dans
  -- `create_stock_on_manufacturing_complete` : la comptabiliser ici aussi
  -- enregistrerait les mêmes faits deux fois.
  IF NEW.reference_type = 'production' THEN
    RETURN NEW;
  END IF;

  SELECT * INTO v_product FROM products WHERE id = NEW.product_id AND tenant_id = NEW.tenant_id;

  v_unit_cost := NULLIF(COALESCE(NEW.unit_cost, 0), 0);

  IF v_unit_cost IS NULL AND NEW.movement_type = 'out' THEN
    IF NEW.warehouse_id IS NOT NULL THEN
      SELECT NULLIF(COALESCE(sq.unit_cost, 0), 0) INTO v_unit_cost
      FROM stock_quantities sq
      WHERE sq.product_id = NEW.product_id
        AND sq.warehouse_id = NEW.warehouse_id
        AND sq.tenant_id = NEW.tenant_id;
    ELSE
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

  IF v_unit_cost IS NULL THEN
    RETURN NEW;
  END IF;

  v_amount := NEW.quantity * v_unit_cost;
  IF v_amount = 0 THEN RETURN NEW; END IF;

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

  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id;

  RETURN NEW;
END;
$function$;
