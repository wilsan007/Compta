-- ============================================================
-- 112_manufacturing_costing.sql
-- PRD-01 : Valoriser les ordres de fabrication
--
-- Le trigger de fin d'OF insérait le mouvement de production
-- sans unit_cost → le produit fini entrait à zéro au stock et
-- au bilan, amputant le résultat de toute la valeur ajoutée.
-- ============================================================

-- ============================================================
-- 1. Ajouter les colonnes de coût sur manufacturing_orders
-- ============================================================
ALTER TABLE manufacturing_orders ADD COLUMN IF NOT EXISTS cost_material numeric DEFAULT 0;
ALTER TABLE manufacturing_orders ADD COLUMN IF NOT EXISTS cost_labor numeric DEFAULT 0;
ALTER TABLE manufacturing_orders ADD COLUMN IF NOT EXISTS cost_overhead numeric DEFAULT 0;
ALTER TABLE manufacturing_orders ADD COLUMN IF NOT EXISTS cost_total numeric DEFAULT 0;
ALTER TABLE manufacturing_orders ADD COLUMN IF NOT EXISTS unit_cost numeric DEFAULT 0;
ALTER TABLE manufacturing_orders ADD COLUMN IF NOT EXISTS qty_produced numeric DEFAULT 0;
ALTER TABLE manufacturing_orders ADD COLUMN IF NOT EXISTS qty_scrapped numeric DEFAULT 0;

-- Ajouter overhead_rate sur company_settings si absent
ALTER TABLE company_settings ADD COLUMN IF NOT EXISTS overhead_rate numeric DEFAULT 0;

-- ============================================================
-- 2. Fonction de calcul du coût de production
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_manufacturing_cost(
  p_mo_id uuid,
  p_tenant_id uuid
)
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
  v_bom_id uuid;
  v_routing_id uuid;
  v_warehouse_id uuid;
  v_overhead_rate numeric := 0;
BEGIN
  -- Récupérer les infos de l'OF
  SELECT mo.quantity, mo.bom_id, mo.routing_id, mo.warehouse_id
  INTO v_quantity, v_bom_id, v_routing_id, v_warehouse_id
  FROM manufacturing_orders mo
  WHERE mo.id = p_mo_id AND mo.tenant_id = p_tenant_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'OF introuvable');
  END IF;

  -- 1. Coût matières : quantité de nomenclature × CUMP courant du composant
  SELECT COALESCE(sum(bl.quantity * v_quantity
                    * COALESCE(sq.unit_cost, p.cost_price, 0)), 0)
  INTO v_cost_material
  FROM bom_lines bl
  JOIN products p ON p.id = bl.product_id AND p.tenant_id = p_tenant_id
  LEFT JOIN stock_quantities sq
    ON sq.product_id = bl.product_id
   AND sq.warehouse_id = v_warehouse_id
   AND sq.tenant_id = p_tenant_id
  WHERE bl.bom_id = v_bom_id AND bl.tenant_id = p_tenant_id;

  -- 2. Main-d'œuvre : temps de gamme × coût horaire du poste
  SELECT COALESCE(sum((ro.setup_time + ro.run_time * v_quantity) / 60.0
                    * COALESCE(wc.cost_per_hour, 0)), 0)
  INTO v_cost_labor
  FROM routing_operations ro
  JOIN work_centers wc ON wc.id = ro.work_center_id AND wc.tenant_id = p_tenant_id
  WHERE ro.routing_id = v_routing_id AND ro.tenant_id = p_tenant_id;

  -- 3. Frais généraux : taux d'imputation sur la main-d'œuvre
  SELECT COALESCE(overhead_rate, 0) INTO v_overhead_rate
  FROM company_settings WHERE tenant_id = p_tenant_id LIMIT 1;

  v_cost_overhead := v_cost_labor * v_overhead_rate;

  -- Coût unitaire
  v_unit_cost := (v_cost_material + v_cost_labor + v_cost_overhead)
                / NULLIF(v_quantity, 0);

  -- Mettre à jour l'OF
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
    'unit_cost', COALESCE(v_unit_cost, 0)
  );
END;
$$;

-- ============================================================
-- 3. Trigger : calculer le coût avant le mouvement de production
--    et générer l'écriture comptable de production
-- ============================================================
CREATE OR REPLACE FUNCTION create_stock_on_manufacturing_complete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
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
  v_component_cost numeric;
BEGIN
  -- Ne traiter que la transition vers 'completed'
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'completed' THEN

    -- Calculer le coût de production
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

    -- Mouvement d'entrée du produit fini AVEC unit_cost
    INSERT INTO stock_movements (
      tenant_id, product_id, warehouse_id, movement_type,
      quantity, unit_cost, reference, movement_date, reference_type
    ) VALUES (
      NEW.tenant_id, NEW.product_id, NEW.warehouse_id, 'in',
      NEW.quantity, v_unit_cost, NEW.number, CURRENT_DATE, 'production'
    );

    -- Sortie des composants du stock avec leur CUMP courant
    FOR v_component IN
      SELECT bl.product_id, bl.quantity * NEW.quantity AS qty,
             COALESCE(sq.unit_cost, p.cost_price, 0) AS comp_cost
      FROM bom_lines bl
      JOIN products p ON p.id = bl.product_id AND p.tenant_id = NEW.tenant_id
      LEFT JOIN stock_quantities sq
        ON sq.product_id = bl.product_id
       AND sq.warehouse_id = NEW.warehouse_id
       AND sq.tenant_id = NEW.tenant_id
      WHERE bl.bom_id = NEW.bom_id AND bl.tenant_id = NEW.tenant_id
    LOOP
      v_component_cost := v_component.qty * v_component.comp_cost;

      INSERT INTO stock_movements (
        tenant_id, product_id, warehouse_id, movement_type,
        quantity, unit_cost, reference, movement_date, reference_type
      ) VALUES (
        NEW.tenant_id, v_component.product_id, NEW.warehouse_id, 'out',
        v_component.qty, v_component.comp_cost, NEW.number, CURRENT_DATE, 'production'
      );
    END LOOP;

    -- Écriture comptable de production
    v_number := 'JE-OF-' || NEW.number;
    SELECT id INTO v_existing FROM journal_entries
      WHERE tenant_id = NEW.tenant_id AND reference = v_number LIMIT 1;

    IF v_existing IS NULL THEN
      INSERT INTO journal_entries (
        tenant_id, number, date, journal_code, status,
        description, reference
      ) VALUES (
        NEW.tenant_id, v_number, CURRENT_DATE, 'OF', 'draft',
        'Production OF ' || NEW.number, v_number
      )
      RETURNING id INTO v_entry_id;

      -- Sortie des matières (débit 601, crédit 31x)
      IF v_cost_material > 0 THEN
        INSERT INTO journal_lines (
          tenant_id, journal_id, account_code, account_general,
          debit, credit, description, line_order
        ) VALUES (
          NEW.tenant_id, v_entry_id, '601000', '601000',
          v_cost_material, 0, 'Consommation matières — ' || NEW.number, v_ordre
        );
        v_ordre := v_ordre + 1;

        INSERT INTO journal_lines (
          tenant_id, journal_id, account_code, account_general,
          debit, credit, description, line_order
        ) VALUES (
          NEW.tenant_id, v_entry_id, '310000', '310000',
          0, v_cost_material, 'Sortie stock matières — ' || NEW.number, v_ordre
        );
        v_ordre := v_ordre + 1;
      END IF;

      -- Main-d'œuvre imputée (débit 641, crédit 71355)
      IF v_cost_labor > 0 THEN
        INSERT INTO journal_lines (
          tenant_id, journal_id, account_code, account_general,
          debit, credit, description, line_order
        ) VALUES (
          NEW.tenant_id, v_entry_id, '641000', '641000',
          v_cost_labor, 0, 'Main-d''œuvre directe — ' || NEW.number, v_ordre
        );
        v_ordre := v_ordre + 1;
      END IF;

      -- Frais généraux (débit 613, crédit 71355)
      IF v_cost_overhead > 0 THEN
        INSERT INTO journal_lines (
          tenant_id, journal_id, account_code, account_general,
          debit, credit, description, line_order
        ) VALUES (
          NEW.tenant_id, v_entry_id, '613000', '613000',
          v_cost_overhead, 0, 'Frais généraux — ' || NEW.number, v_ordre
        );
        v_ordre := v_ordre + 1;
      END IF;

      -- Entrée du produit fini (débit 355, crédit 71355 production stockée)
      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        debit, credit, description, line_order
      ) VALUES (
        NEW.tenant_id, v_entry_id, '355000', '355000',
        v_cost_total, 0, 'Entrée produit fini — ' || NEW.number, v_ordre
      );
      v_ordre := v_ordre + 1;

      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        debit, credit, description, line_order
      ) VALUES (
        NEW.tenant_id, v_entry_id, '713550', '713550',
        0, v_cost_total, 'Production stockée — ' || NEW.number, v_ordre
      );

      -- Bascule en 'posted' APRÈS les lignes (SOC-01)
      UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;
    END IF;

    -- Mettre à jour les quantités produites
    UPDATE manufacturing_orders
    SET qty_produced = NEW.quantity
    WHERE id = NEW.id AND tenant_id = NEW.tenant_id;
  END IF;

  RETURN NEW;
END;
$$;
