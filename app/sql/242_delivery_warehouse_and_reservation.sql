-- ============================================================
-- 242_delivery_warehouse_and_reservation.sql — S-05, S-06, S-07
--
-- Audit des modules hors comptabilité (23/09), § Ventes → stock.
-- Mesuré sur base neuve à la 234 (migrations antérieures seules), scénarios T01 → T06 de
-- `242_delivery_warehouse_and_reservation_tests.sql` :
--
--   S-05  La sortie de livraison ne portait pas de dépôt : article 94, dépôt
--         100 — le stock du dépôt ne bougeait jamais d'une livraison.
--   S-06  Les couches de valorisation restaient intactes (100 restants, valeur
--         500 après une sortie de 6) : le stock vendu restait au bilan.
--   S-07  La réservation restait `active` avec `reserved_quantity = 6` après la
--         livraison (T03) et 10 après une livraison partielle de 4 (T04). Le
--         déclencheur `release_stock_on_delivery` écoute `sales_orders.status =
--         'delivered'` ; l'écran, lui, pose `delivery_status` (misc.ts:2483) —
--         la branche n'était donc jamais atteinte dans le parcours réel.
--
-- CORRECTIFS
--   1. La sortie porte le dépôt de la réservation de la commande, à défaut le
--      dépôt qui peut servir la ligne, à défaut celui de la société : le stock
--      du dépôt et le stock de l'article bougent ensemble (S-05).
--   2. Comme le mouvement porte son dépôt, `consume_valuation_layers_on_exit`
--      — inchangé — trouve les couches et les consomme (S-06).
--   3. L'expédition du bon de livraison libère la réservation de la commande,
--      proportionnellement à ce qui est expédié (S-07). La quantité restante
--      est laissée sur la réservation : une commande livrée en deux fois libère
--      4 puis 6, pas 4 puis rien.
--      `release_stock_on_delivery` (230, sur `sales_orders.status`) est
--      conservé : il couvre le passage à « livrée » de la commande et ne
--      trouve plus rien à libérer quand le bon est passé.
--   4. `reserve_stock_on_sales_order_confirm` se rabat, lui aussi, sur le dépôt
--      de la société quand l'article n'a pas encore de ligne de dépôt — sinon
--      la réservation naissait sans dépôt et la sortie ne pouvait pas la suivre.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Le dépôt d'une sortie de livraison
--    Ordre : la réservation de la commande, puis le dépôt qui peut servir la
--    ligne (assez de disponible d'abord, assez de quantité ensuite), puis le
--    dépôt de la société.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION resolve_delivery_warehouse(
  p_tenant_id uuid,
  p_so_id uuid,
  p_product_id uuid,
  p_qty numeric DEFAULT 0
) RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_wh uuid;
BEGIN
  IF p_so_id IS NOT NULL THEN
    SELECT r.warehouse_id INTO v_wh
    FROM stock_reservations r
    WHERE r.tenant_id = p_tenant_id
      AND r.reference_id = p_so_id
      AND r.reference_type = 'sales_order'
      AND r.product_id = p_product_id
      AND r.status = 'active'
      AND r.warehouse_id IS NOT NULL
    ORDER BY r.created_at
    LIMIT 1;
  END IF;

  IF v_wh IS NULL THEN
    SELECT sq.warehouse_id INTO v_wh
    FROM stock_quantities sq
    WHERE sq.tenant_id = p_tenant_id
      AND sq.product_id = p_product_id
      AND sq.warehouse_id IS NOT NULL
    ORDER BY (sq.quantity >= p_qty) DESC,
             (COALESCE(sq.quantity, 0) - COALESCE(sq.reserved_quantity, 0)) DESC,
             sq.quantity DESC,
             sq.warehouse_id
    LIMIT 1;
  END IF;

  IF v_wh IS NULL THEN
    v_wh := resolve_default_warehouse(p_tenant_id);
  END IF;

  RETURN v_wh;
END $$;

-- ------------------------------------------------------------
-- 2. Libération de la réservation, à hauteur de ce qui est expédié
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION _release_sales_order_reservation(
  p_tenant_id uuid,
  p_so_id uuid,
  p_product_id uuid,
  p_qty numeric
) RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_restant numeric := p_qty;
  v_prend numeric;
  r RECORD;
BEGIN
  IF p_so_id IS NULL OR COALESCE(p_qty, 0) <= 0 THEN
    RETURN 0;
  END IF;

  FOR r IN
    SELECT * FROM stock_reservations
    WHERE tenant_id = p_tenant_id
      AND reference_id = p_so_id
      AND reference_type = 'sales_order'
      AND product_id = p_product_id
      AND status = 'active'
    ORDER BY created_at, id
    FOR UPDATE
  LOOP
    EXIT WHEN v_restant <= 0;

    v_prend := LEAST(v_restant, r.quantity);

    UPDATE stock_quantities
      SET reserved_quantity = GREATEST(0, COALESCE(reserved_quantity, 0) - v_prend),
          updated_at = now()
    WHERE tenant_id = p_tenant_id
      AND product_id = p_product_id
      AND (r.warehouse_id IS NULL OR warehouse_id = r.warehouse_id);

    UPDATE stock_reservations
      SET quantity = r.quantity - v_prend,
          status = CASE WHEN r.quantity - v_prend <= 0 THEN 'consumed' ELSE status END,
          updated_at = now()
    WHERE id = r.id;

    v_restant := v_restant - v_prend;
  END LOOP;

  RETURN p_qty - v_restant;
END $$;

-- ------------------------------------------------------------
-- 3. La sortie de livraison : dépôt, lot, et libération de la réservation
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION create_stock_out_on_delivery()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_line RECORD;
  v_deja int;
  v_wh uuid;
  v_libere numeric;
BEGIN
  -- STK-01 : Déclencher uniquement au passage de draft/confirmed → shipped
  -- (pas sur shipped → delivered, qui ne doit pas re-décrémenter le stock)
  IF OLD.status NOT IN ('shipped', 'delivered') AND NEW.status = 'shipped' THEN

    -- M-06 : un BL annulé puis réexpédié retombait sur l'index unique. Le stock
    -- était sauf, le message était un code d'erreur PostgreSQL.
    SELECT count(*) INTO v_deja
    FROM stock_movements
    WHERE tenant_id = NEW.tenant_id AND reference_type = 'delivery_note' AND reference_id = NEW.id;

    IF v_deja > 0 THEN
      RAISE EXCEPTION 'BL % déjà expédié : sa sortie de stock existe. Contrepasser avant de réexpédier.', NEW.number
        USING ERRCODE = '23505';
    END IF;

    FOR v_line IN
      SELECT * FROM delivery_note_lines
      WHERE delivery_note_id = NEW.id AND tenant_id = NEW.tenant_id AND quantity > 0
    LOOP
      -- S-05 : le dépôt de la sortie — réservation de la commande, dépôt qui
      -- peut servir la ligne, dépôt de la société
      v_wh := resolve_delivery_warehouse(NEW.tenant_id, NEW.sales_order_id, v_line.product_id, v_line.quantity);

      INSERT INTO stock_movements (
        tenant_id, product_id, warehouse_id, movement_type, type, quantity,
        lot_id, serial_id,
        reference, reference_type, reference_id, date, movement_date, notes
      ) VALUES (
        NEW.tenant_id, v_line.product_id, v_wh, 'out', 'out', v_line.quantity,
        v_line.lot_id, v_line.serial_id,
        'BL-' || NEW.number, 'delivery_note', NEW.id, NEW.delivery_date, NEW.delivery_date, v_line.description
      );

      -- S-07 : la marchandise est partie, la réservation de la commande l'est
      -- aussi, à hauteur de la ligne livrée
      v_libere := _release_sales_order_reservation(NEW.tenant_id, NEW.sales_order_id, v_line.product_id, v_line.quantity);
    END LOOP;
  END IF;
  RETURN NEW;
END $$;

-- ------------------------------------------------------------
-- 4. Une réservation porte toujours un dépôt quand la société en a un
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION reserve_stock_on_sales_order_confirm()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_line RECORD;
  v_warehouse_id UUID;
  v_tid UUID := NEW.tenant_id;
BEGIN
  IF NEW.status = 'confirmed' AND OLD.status IS DISTINCT FROM 'confirmed' THEN
    FOR v_line IN SELECT * FROM sales_order_lines WHERE sales_order_id = NEW.id AND tenant_id = v_tid AND quantity > 0 LOOP
      -- STK-02 : la ligne de commande ne porte pas de dépôt : choisir celui qui a le plus de disponible
      SELECT sq.warehouse_id INTO v_warehouse_id
      FROM stock_quantities sq
      WHERE sq.tenant_id = v_tid AND sq.product_id = v_line.product_id
      ORDER BY (COALESCE(sq.quantity, 0) - COALESCE(sq.reserved_quantity, 0)) DESC, sq.warehouse_id
      LIMIT 1;

      -- S-05/S-07 : un article sans ligne de dépôt (stock d'avant la 241) ne
      -- doit pas produire une réservation sans dépôt, que la sortie ne pourrait
      -- pas suivre
      IF v_warehouse_id IS NULL THEN
        v_warehouse_id := resolve_default_warehouse(v_tid);
      END IF;

      -- Créer la réservation avec warehouse_id
      INSERT INTO stock_reservations (
        tenant_id, product_id, warehouse_id, quantity,
        reserved_by, reference_id, reference_type, status
      ) VALUES (
        v_tid, v_line.product_id, v_warehouse_id, v_line.quantity,
        'sales_order', NEW.id, 'sales_order', 'active'
      );

      -- STK-02 : Mettre à jour la quantité réservée uniquement pour le dépôt concerné
      IF v_warehouse_id IS NOT NULL THEN
        UPDATE stock_quantities
        SET reserved_quantity = reserved_quantity + v_line.quantity,
          updated_at = now()
        WHERE tenant_id = v_tid
          AND product_id = v_line.product_id
          AND warehouse_id = v_warehouse_id;
      END IF;
    END LOOP;
  END IF;

  RETURN NEW;
END $$;

-- ------------------------------------------------------------
-- 5. Reprise — le stock que personne n'avait rangé dans un dépôt
--    Jusqu'ici, une réception n'écrivait pas de ligne de dépôt (S-01) : les
--    sociétés existantes ont donc un stock d'article sans stock de dépôt. La
--    sortie de livraison s'impute désormais au dépôt et vérifie qu'il a la
--    quantité : sans cette reprise, une livraison d'un stock antérieur serait
--    refusée (« Stock insuffisant dans le dépôt … », mesuré en écrivant le
--    scénario T04 de `240_…_tests.sql`). On range ce stock dans le dépôt de la
--    société, à son coût de revient — la même valeur que celle qu'utilisait
--    déjà l'écriture de sortie.
--    Hors périmètre, inscrit au registre : ce stock n'a ni couche de
--    valorisation ni écriture d'entrée (les réceptions d'avant la 241 n'en
--    produisaient pas). Le CUMP porté par `stock_quantities` tient les
--    écritures justes ; les couches, elles, ne couvrent que le stock reçu
--    depuis la 241.
-- ------------------------------------------------------------
INSERT INTO stock_quantities (tenant_id, product_id, warehouse_id, quantity, unit_cost)
SELECT p.tenant_id,
       p.id,
       resolve_default_warehouse(p.tenant_id),
       p.stock_quantity,
       COALESCE(p.cost_price, 0)
FROM products p
WHERE COALESCE(p.stock_quantity, 0) > 0
  AND resolve_default_warehouse(p.tenant_id) IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM stock_quantities sq WHERE sq.product_id = p.id)
ON CONFLICT (product_id, warehouse_id) DO NOTHING;

-- ------------------------------------------------------------
-- 6. Droits — les deux fonctions internes ne sont pas des points d'entrée
-- ------------------------------------------------------------
REVOKE ALL ON FUNCTION resolve_delivery_warehouse(uuid, uuid, uuid, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION _release_sales_order_reservation(uuid, uuid, uuid, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION create_stock_out_on_delivery() TO service_role;
GRANT EXECUTE ON FUNCTION reserve_stock_on_sales_order_confirm() TO service_role;
