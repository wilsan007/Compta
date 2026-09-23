-- ============================================================
-- 229_production_scrap_and_idempotence.sql — la production ment sur deux points
--
-- Mesuré avant la 229, sur base neuve à la 228 (M-08 du reste-à-faire) :
--
--   1. OF de 100 pièces dont 10 rebutées → le stock de produits finis monte de
--      100, `qty_produced` vaut 100 et le coût unitaire 10,00. La colonne
--      `qty_scrapped` existe, aucun code ne la lit : les rebuts entrent en stock
--      comme des pièces bonnes, et le coût unitaire est sous-évalué d'autant
--      (1 000 / 100 au lieu de 1 000 / 90 = 11,11). `qty_produced + qty_scrapped`
--      dépassait la quantité lancée, ce qui est contradictoire quelle que soit
--      la convention retenue.
--
--   2. OF terminé → annulé → terminé (les trois statuts sont permis par la
--      contrainte CHECK) → 4 mouvements de stock au lieu de 2, soit 20 pièces
--      entrées pour 10 produites, tandis que l'écriture comptable, elle, était
--      protégée par un test d'existence. Stock et comptabilité divergeaient
--      silencieusement. L'index unique `uq_stock_movement_source` aurait dû
--      l'interdire, mais il est partiel — `WHERE reference_id IS NOT NULL` — et
--      ce déclencheur est le seul à ne jamais renseigner `reference_id`.
--
-- Correctifs : renseigner `reference_id`, refuser explicitement une seconde
-- clôture, et déduire les rebuts des pièces entrées en stock.
--
-- Hors périmètre, inscrit au registre : annuler un OF terminé ne contrepasse
-- toujours pas les mouvements de stock (M-08 suite).
-- ============================================================

-- ------------------------------------------------------------
-- 1. Le coût unitaire se calcule sur les pièces bonnes
--    Sans rebut (cas de la 177), le résultat est inchangé.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION calculate_manufacturing_cost(p_mo_id uuid, p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_cost_material numeric := 0;
  v_cost_labor numeric := 0;
  v_cost_overhead numeric := 0;
  v_unit_cost numeric;
  v_quantity numeric;
  v_scrapped numeric;
  v_good numeric;
  v_bom_id uuid;
  v_routing_id uuid;
  v_warehouse_id uuid;
  v_overhead_rate numeric := 0;
BEGIN
  SELECT mo.quantity, COALESCE(mo.qty_scrapped, 0), mo.bom_id, mo.routing_id, mo.warehouse_id
  INTO v_quantity, v_scrapped, v_bom_id, v_routing_id, v_warehouse_id
  FROM manufacturing_orders mo
  WHERE mo.id = p_mo_id AND mo.tenant_id = p_tenant_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'OF introuvable');
  END IF;

  -- Les matières sont consommées pour la quantité LANCÉE : un rebut a coûté
  -- sa matière. Seule la répartition sur les pièces bonnes change.
  SELECT COALESCE(sum(bl.quantity * v_quantity
                    * COALESCE(NULLIF(sq.unit_cost, 0), NULLIF(p.cost_price, 0), bl.unit_cost, 0)), 0)
  INTO v_cost_material
  FROM bom_lines bl
  JOIN products p ON p.id = bl.product_id AND p.tenant_id = p_tenant_id
  LEFT JOIN stock_quantities sq
    ON sq.product_id = bl.product_id
   AND sq.warehouse_id = v_warehouse_id
   AND sq.tenant_id = p_tenant_id
  WHERE bl.bom_id = v_bom_id AND bl.tenant_id = p_tenant_id;

  -- Temps en minutes → heures
  SELECT COALESCE(sum((COALESCE(ro.setup_time_min, 0) + COALESCE(ro.run_time_min, 0) * v_quantity) / 60.0
                    * COALESCE(wc.cost_per_hour, 0)), 0)
  INTO v_cost_labor
  FROM routing_operations ro
  JOIN work_centers wc ON wc.id = ro.work_center_id AND wc.tenant_id = p_tenant_id
  WHERE ro.routing_id = v_routing_id AND ro.tenant_id = p_tenant_id;

  SELECT COALESCE(overhead_rate, 0) INTO v_overhead_rate
  FROM company_settings WHERE tenant_id = p_tenant_id LIMIT 1;

  v_cost_overhead := v_cost_labor * v_overhead_rate;

  -- M-08 : le coût total est absorbé par les seules pièces bonnes.
  v_good := GREATEST(v_quantity - v_scrapped, 0);
  v_unit_cost := (v_cost_material + v_cost_labor + v_cost_overhead)
                / NULLIF(v_good, 0);

  UPDATE manufacturing_orders
  SET cost_material = v_cost_material,
      cost_labor = v_cost_labor,
      cost_overhead = v_cost_overhead,
      cost_total = v_cost_material + v_cost_labor + v_cost_overhead,
      unit_cost = COALESCE(v_unit_cost, 0)
  WHERE id = p_mo_id AND tenant_id = p_tenant_id;

  RETURN jsonb_build_object(
    'success', true,
    'cost_material', v_cost_material,
    'cost_labor', v_cost_labor,
    'cost_overhead', v_cost_overhead,
    'cost_total', v_cost_material + v_cost_labor + v_cost_overhead,
    'qty_good', v_good,
    'unit_cost', COALESCE(v_unit_cost, 0)
  );
END;
$$;

-- ------------------------------------------------------------
-- 2. La clôture d'un OF : traçable, idempotente, et consciente des rebuts
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION create_stock_on_manufacturing_complete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_entry_id uuid;
  v_number text;
  v_existing uuid;
  v_cost jsonb;
  v_unit_cost numeric;
  v_cost_material numeric;
  v_cost_labor numeric;
  v_cost_overhead numeric;
  v_cost_total numeric;
  v_ordre int := 0;
  v_component RECORD;
  v_good numeric;
  v_deja int;
BEGIN
  IF NOT (NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'completed') THEN
    RETURN NEW;
  END IF;

  -- M-08 défaut 2 : une seconde clôture doublait le stock sans doubler
  -- l'écriture. On refuse explicitement plutôt que de laisser l'index unique
  -- lever une erreur de contrainte illisible — ou, pire, ne rien lever.
  SELECT count(*) INTO v_deja
  FROM stock_movements
  WHERE tenant_id = NEW.tenant_id AND reference_type = 'production' AND reference_id = NEW.id;

  IF v_deja > 0 THEN
    RAISE EXCEPTION 'OF % déjà clôturé : ses mouvements de stock existent. Contrepasser avant de reclôturer.', NEW.number
      USING ERRCODE = '23505';
  END IF;

  -- M-08 défaut 1 : les rebuts n'entrent pas en stock comme des pièces bonnes.
  v_good := GREATEST(NEW.quantity - COALESCE(NEW.qty_scrapped, 0), 0);

  v_cost := calculate_manufacturing_cost(NEW.id, NEW.tenant_id);
  IF (v_cost->>'success')::boolean THEN
    v_cost_material := (v_cost->>'cost_material')::numeric;
    v_cost_labor := (v_cost->>'cost_labor')::numeric;
    v_cost_overhead := (v_cost->>'cost_overhead')::numeric;
    v_cost_total := (v_cost->>'cost_total')::numeric;
    v_unit_cost := (v_cost->>'unit_cost')::numeric;
  ELSE
    v_unit_cost := 0;
    v_cost_total := 0;
  END IF;

  -- Entrée du produit fini : les pièces bonnes seulement
  IF v_good > 0 THEN
    INSERT INTO stock_movements (
      tenant_id, product_id, warehouse_id, movement_type,
      quantity, unit_cost, reference, movement_date, reference_type, reference_id
    ) VALUES (
      NEW.tenant_id, NEW.product_id, NEW.warehouse_id, 'in',
      v_good, v_unit_cost, NEW.number, CURRENT_DATE, 'production', NEW.id
    );
  END IF;

  -- Sortie des composants : pour la quantité LANCÉE, rebuts compris
  FOR v_component IN
    SELECT bl.product_id, sum(bl.quantity) * NEW.quantity AS qty,
           max(COALESCE(NULLIF(sq.unit_cost, 0), NULLIF(p.cost_price, 0), bl.unit_cost, 0)) AS comp_cost
    FROM bom_lines bl
    JOIN products p ON p.id = bl.product_id AND p.tenant_id = NEW.tenant_id
    LEFT JOIN stock_quantities sq
      ON sq.product_id = bl.product_id
     AND sq.warehouse_id = NEW.warehouse_id
     AND sq.tenant_id = NEW.tenant_id
    WHERE bl.bom_id = NEW.bom_id AND bl.tenant_id = NEW.tenant_id
    GROUP BY bl.product_id
  LOOP
    INSERT INTO stock_movements (
      tenant_id, product_id, warehouse_id, movement_type,
      quantity, unit_cost, reference, movement_date, reference_type, reference_id
    ) VALUES (
      NEW.tenant_id, v_component.product_id, NEW.warehouse_id, 'out',
      v_component.qty, v_component.comp_cost, NEW.number, CURRENT_DATE, 'production', NEW.id
    );
  END LOOP;

  -- Écriture comptable de production
  v_number := 'JE-OF-' || NEW.number;
  SELECT id INTO v_existing FROM journal_entries
    WHERE tenant_id = NEW.tenant_id AND reference = v_number LIMIT 1;

  IF v_existing IS NULL AND COALESCE(v_cost_total, 0) > 0 THEN
    INSERT INTO journal_entries (
      tenant_id, number, date, journal_code, status, description, reference
    ) VALUES (
      NEW.tenant_id, v_number, CURRENT_DATE, 'OF', 'draft',
      'Production OF ' || NEW.number, v_number
    )
    RETURNING id INTO v_entry_id;

    IF v_cost_material > 0 THEN
      INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
      VALUES (NEW.tenant_id, v_entry_id, '601000', '601000', v_cost_material, 0, 'Consommation matières — ' || NEW.number, v_ordre);
      v_ordre := v_ordre + 1;

      INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
      VALUES (NEW.tenant_id, v_entry_id, '310000', '310000', 0, v_cost_material, 'Sortie stock matières — ' || NEW.number, v_ordre);
      v_ordre := v_ordre + 1;
    END IF;

    -- Main-d'œuvre et frais généraux : déjà constatés en charges (paie, factures) ;
    -- ils sont absorbés dans la valeur du produit fini via 355 / 713, sans nouvelle charge.
    -- Le coût des rebuts reste absorbé par les pièces bonnes : l'écriture ne
    -- change pas, seul le coût unitaire monte.
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
    VALUES (NEW.tenant_id, v_entry_id, '355000', '355000', v_cost_total, 0, 'Entrée produit fini — ' || NEW.number, v_ordre);
    v_ordre := v_ordre + 1;

    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
    VALUES (NEW.tenant_id, v_entry_id, '713500', '713500', 0, v_cost_total, 'Production stockée — ' || NEW.number, v_ordre);

    -- Bascule en 'posted' APRÈS les lignes (SOC-01)
    UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;
  END IF;

  UPDATE manufacturing_orders
  SET qty_produced = v_good
  WHERE id = NEW.id AND tenant_id = NEW.tenant_id;

  RETURN NEW;
END;
$$;
