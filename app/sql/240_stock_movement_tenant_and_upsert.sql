-- ============================================================
-- 240_stock_movement_tenant_and_upsert.sql — S-08, S-09
--
-- Audit des modules hors comptabilité (doc/audit/AUDIT-MODULES-HORS-COMPTA-2026-09-23.md),
-- § S-08 et S-09, plus un défaut voisin trouvé en montant les scénarios.
--
-- S-08 — LA SOCIÉTÉ EST CELLE DE LA SESSION, PAS CELLE DU MOUVEMENT
--   `increment_stock` et `decrement_stock` lisaient `current_tenant_id()`.
--   Appelées par le déclencheur `update_stock_on_movement`, qui reçoit
--   NEW.tenant_id, elles travaillaient donc sur la société ACTIVE de la session.
--   Mesuré sur base neuve à la 234 (migrations antérieures seules) — scénario T01 de `240_…_tests.sql`) : un
--   mouvement d'entrée de la société A, écrit pendant que la société B est
--   active (cas normal d'un chemin SECURITY DEFINER), laisse le stock de A à
--   100 au lieu de 110 ; en sortie (T02), l'insertion échoue franchement sur
--   « Produit … non trouvé », parce que `decrement_stock` cherche le produit
--   dans la société B.
--
-- S-09 — LA QUANTITÉ DE LA TRANSACTION CONCURRENTE ÉTAIT PERDUE SANS BRUIT
--   `increment_stock` faisait un UPDATE, puis, « si rien trouvé », un
--   `INSERT … ON CONFLICT DO NOTHING`. Entre les deux, une autre transaction
--   peut créer la ligne : l'INSERT tombe alors sur le conflit et JETTE la
--   quantité — le total de l'article est incrémenté, la ligne de dépôt non.
--   L'écriture est remplacée par un seul `INSERT … ON CONFLICT … DO UPDATE`
--   qui additionne, atomiquement.
--
-- Correction de la lecture : la société est un PARAMÈTRE des deux fonctions
--   internes (`_stock_increment`, `_stock_decrement`), que le déclencheur
--   appelle avec `NEW.tenant_id`. Les RPC publiques `increment_stock` et
--   `decrement_stock` gardent leur signature et prennent, elles,
--   `current_tenant_id()` — c'est leur contrat : elles agissent pour l'appelant.
--
-- DÉFAUT VOISIN (T04), de la même famille : `decrement_stock` faisait
--   `GREATEST(quantity - p_qty, 0)` sur la ligne de dépôt. Un article à 200
--   réparti en deux dépôts de 100, sortie de 150 du dépôt 1 : le contrôle
--   global passait, le dépôt tombait à 0 et l'article à 50 — les deux
--   compteurs divergeaient, ce que S-05 reproche précisément à la livraison.
--   La sortie est désormais refusée si le dépôt visé n'a pas la quantité.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Entrée de stock — pour la société du mouvement (S-08/S-09)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION _stock_increment(
  p_tenant_id uuid,
  p_product_id uuid,
  p_qty numeric,
  p_warehouse_id uuid DEFAULT NULL,
  p_unit_cost numeric DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_cost numeric;
BEGIN
  IF p_tenant_id IS NULL THEN
    RAISE EXCEPTION 'Société absente : une entrée de stock ne peut pas être anonyme';
  END IF;

  -- Coût de revient de l'article si l'appelant n'en fournit pas
  IF p_unit_cost IS NULL THEN
    SELECT cost_price INTO v_cost FROM products WHERE id = p_product_id AND tenant_id = p_tenant_id;
    p_unit_cost := COALESCE(v_cost, 0);
  END IF;

  IF p_warehouse_id IS NOT NULL THEN
    -- S-09 : une seule écriture, atomique. La quantité d'une transaction
    -- concurrente qui a créé la ligne entre-temps n'est plus perdue.
    INSERT INTO stock_quantities (tenant_id, product_id, warehouse_id, quantity, unit_cost)
    VALUES (p_tenant_id, p_product_id, p_warehouse_id, p_qty, p_unit_cost)
    ON CONFLICT (product_id, warehouse_id) DO UPDATE
      SET quantity = stock_quantities.quantity + EXCLUDED.quantity,
          updated_at = now();
  END IF;

  UPDATE products
    SET stock_quantity = COALESCE(stock_quantity, 0) + p_qty,
        updated_at = now()
    WHERE id = p_product_id AND tenant_id = p_tenant_id;
END $$;

-- ------------------------------------------------------------
-- 2. Sortie de stock — même société explicite, contrôle par dépôt (T04)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION _stock_decrement(
  p_tenant_id uuid,
  p_product_id uuid,
  p_qty numeric,
  p_warehouse_id uuid DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_current numeric;
  v_wh_qty numeric;
  v_wh_name text;
BEGIN
  IF p_tenant_id IS NULL THEN
    RAISE EXCEPTION 'Société absente : une sortie de stock ne peut pas être anonyme';
  END IF;

  SELECT stock_quantity INTO v_current
  FROM products
  WHERE id = p_product_id AND tenant_id = p_tenant_id
  FOR UPDATE;

  IF v_current IS NULL THEN
    RAISE EXCEPTION 'Produit % non trouvé', p_product_id;
  END IF;

  IF v_current < p_qty THEN
    RAISE EXCEPTION 'Stock insuffisant: disponible=%, demandé=%', v_current, p_qty;
  END IF;

  IF p_warehouse_id IS NOT NULL THEN
    SELECT sq.quantity, w.name INTO v_wh_qty, v_wh_name
    FROM stock_quantities sq
    LEFT JOIN warehouses w ON w.id = sq.warehouse_id
    WHERE sq.product_id = p_product_id
      AND sq.warehouse_id = p_warehouse_id
      AND sq.tenant_id = p_tenant_id
    FOR UPDATE OF sq;

    IF v_wh_qty IS NULL THEN
      -- Stock non localisé : entré avant que les réceptions ne portent un dépôt
      -- (S-01). On rattache le stock de l'article au dépôt utilisé, au coût de
      -- revient — la reprise de la 242 fait la même chose pour le stock
      -- existant, celle-ci couvre ce qui lui échapperait (article dont le stock
      -- a été posé à la main, nouvelle société, données rechargées).
      -- L'alternative — refuser — bloquerait toute livraison d'un stock
      -- antérieur, mesuré en écrivant le scénario T04.
      INSERT INTO stock_quantities (tenant_id, product_id, warehouse_id, quantity, unit_cost)
      VALUES (p_tenant_id, p_product_id, p_warehouse_id, GREATEST(v_current - p_qty, 0),
              COALESCE((SELECT p.cost_price FROM products p
                        WHERE p.id = p_product_id AND p.tenant_id = p_tenant_id), 0))
      ON CONFLICT (product_id, warehouse_id) DO UPDATE
        SET quantity = GREATEST(v_current - p_qty, 0),
            updated_at = now();
    ELSE
      IF v_wh_qty < p_qty THEN
        RAISE EXCEPTION 'Stock insuffisant dans le dépôt % : disponible=%, demandé=%',
          COALESCE(v_wh_name, p_warehouse_id::text), v_wh_qty, p_qty;
      END IF;

      UPDATE stock_quantities
        SET quantity = quantity - p_qty, updated_at = now()
      WHERE product_id = p_product_id
        AND warehouse_id = p_warehouse_id
        AND tenant_id = p_tenant_id;
    END IF;
  END IF;

  UPDATE products
    SET stock_quantity = stock_quantity - p_qty, updated_at = now()
    WHERE id = p_product_id AND tenant_id = p_tenant_id;
END $$;

-- ------------------------------------------------------------
-- 3. Les RPC publiques gardent leur signature : elles agissent pour l'appelant
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION increment_stock(
  p_product_id uuid,
  p_qty numeric,
  p_warehouse_id uuid DEFAULT NULL,
  p_unit_cost numeric DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_tid uuid := current_tenant_id();
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;
  PERFORM _stock_increment(v_tid, p_product_id, p_qty, p_warehouse_id, p_unit_cost);
END $$;

CREATE OR REPLACE FUNCTION decrement_stock(
  p_product_id uuid,
  p_qty numeric,
  p_warehouse_id uuid DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_tid uuid := current_tenant_id();
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;
  PERFORM _stock_decrement(v_tid, p_product_id, p_qty, p_warehouse_id);
END $$;

-- ------------------------------------------------------------
-- 4. Le déclencheur passe la société DU MOUVEMENT (S-08)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_stock_on_movement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.movement_type = 'in' THEN
    PERFORM _stock_increment(NEW.tenant_id, NEW.product_id, NEW.quantity, NEW.warehouse_id, NEW.unit_cost);
  ELSIF NEW.movement_type = 'out' THEN
    PERFORM _stock_decrement(NEW.tenant_id, NEW.product_id, NEW.quantity, NEW.warehouse_id);
  ELSIF NEW.movement_type = 'adjustment' THEN
    -- Pour un ajustement, quantity est la nouvelle valeur absolue
    UPDATE products
      SET stock_quantity = NEW.quantity, updated_at = NOW()
      WHERE id = NEW.product_id AND tenant_id = NEW.tenant_id;
  ELSIF NEW.movement_type = 'initial' THEN
    -- LOT1-02 : 'initial' initialise le stock avec le coût fourni
    PERFORM _stock_increment(NEW.tenant_id, NEW.product_id, NEW.quantity, NEW.warehouse_id, NEW.unit_cost);
  END IF;
  RETURN NEW;
END $$;

-- ------------------------------------------------------------
-- 5. Droits — les fonctions internes ne sont pas des points d'entrée
-- ------------------------------------------------------------
REVOKE ALL ON FUNCTION _stock_increment(uuid, uuid, numeric, uuid, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION _stock_decrement(uuid, uuid, numeric, uuid) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION increment_stock(uuid, numeric, uuid, numeric) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION decrement_stock(uuid, numeric, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION update_stock_on_movement() TO service_role;
