-- ============================================================
-- 241_receipt_stock_and_ledger.sql — S-01, S-02, S-03, S-04, S-10, S-11
--
-- Audit des modules hors comptabilité (23/09), § Achats → stock et § Stock.
-- Mesuré sur base neuve à la 234 (migrations antérieures seules), en exécutant un scénario chiffré (T01 → T07 de
-- `241_receipt_stock_and_ledger_tests.sql`) :
--
--   S-04  `goods_receipts` n'a pas de colonne `warehouse_id` : « column
--         "warehouse_id" of relation "goods_receipts" does not exist ». La
--         réception ne peut pas dire OÙ elle entre.
--   S-01  Le mouvement d'entrée ne porte pas de dépôt : le stock par dépôt
--         reste à 0, l'article seul monte. Deux compteurs, deux vérités.
--   S-02  Il ne porte pas de coût : aucune couche de valorisation n'est créée
--         (0 couche, valeur 0 pour une réception de 10 à 7 qui vaut 70).
--   S-03  Sans coût, l'écriture est sortie par la première porte de
--         `create_journal_on_stock_movement` — « IF v_unit_cost IS NULL THEN
--         RETURN NEW » — et le journal des stocks reste vide.
--   S-10  Les comptes du mouvement sont littéralement « 310000 » et « 603000 ».
--         `resolve_stock_account` et `resolve_variation_account` existent
--         depuis la 125 et ne sont appelés par personne ; `products.
--         stock_account_code` (mesuré : resolve_stock_account rend 310000 pour
--         un article configuré 603200) et `product_categories.*_account_code`
--         sont ignorés.
--   S-11  `check_tracking_on_stock_movement` se contente d'écrire une ligne
--         dans `tracking_warnings` (décision LOT4-14) : un article suivi en lot
--         entre en stock sans lot. La traçabilité est décorative.
--
-- CORRECTIFS
--   1. `goods_receipts.warehouse_id` (S-04), avec `resolve_default_warehouse`
--      en repli : une société qui n'en nomme pas a un dépôt, celui qu'utilisent
--      déjà `reserve_stock_on_sales_order_confirm` et la production.
--   2. Le mouvement d'entrée porte le dépôt ET le coût : prix de la ligne de
--      commande, sinon prix d'achat de l'article, sinon coût de revient (S-01,
--      S-02). Le coût non connu reste 0 : la couche et l'écriture ne naissent
--      alors pas — on ne valorise pas ce qu'on ne sait pas valoriser.
--   3. L'écriture naît donc d'elle-même, par le déclencheur existant (S-03).
--      Le journal `ST` est créé s'il manque, sinon la contrainte de clé
--      étrangère de `journal_entries` ferait échouer la réception elle-même.
--   4. Les comptes sont résolus : article → famille d'articles → 310000/603000
--      (S-10), et les deux résolveurs lisent enfin `products`.
--   5. Le lot et le numéro de série de la ligne de réception suivent le
--      mouvement, et un article suivi qui bouge sans lot est REFUSÉ (S-11).
-- ============================================================

-- ------------------------------------------------------------
-- 1. La réception sait où elle entre (S-04)
-- ------------------------------------------------------------
ALTER TABLE goods_receipts ADD COLUMN IF NOT EXISTS warehouse_id uuid
  REFERENCES warehouses(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_goods_receipts_warehouse ON goods_receipts(warehouse_id);
COMMENT ON COLUMN goods_receipts.warehouse_id IS
  'Dépôt dans lequel la réception entre. NULL = repli sur le dépôt de la société (resolve_default_warehouse).';

-- ------------------------------------------------------------
-- 2. Dépôt par défaut d'une société
--    Même règle que le repli de `reserve_stock_on_sales_order_confirm` :
--    le premier dépôt actif, dans un ordre stable (création, puis code).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION resolve_default_warehouse(p_tenant_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT w.id
  FROM warehouses w
  WHERE w.tenant_id = p_tenant_id
    AND COALESCE(w.active, true)
  ORDER BY w.created_at NULLS LAST, w.code
  LIMIT 1;
$$;

-- ------------------------------------------------------------
-- 3. Les comptes d'un article : l'article d'abord, puis sa famille (S-10)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION resolve_stock_account(p_product_id uuid)
RETURNS text
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(
    NULLIF(btrim(p.stock_account_code), ''),
    NULLIF(btrim(pc.stock_account_code), ''),
    '310000'  -- Fallback par défaut
  )
  FROM products p
  LEFT JOIN product_categories pc ON pc.id = p.category_id AND pc.tenant_id = p.tenant_id
  WHERE p.id = p_product_id;
$$;

CREATE OR REPLACE FUNCTION resolve_variation_account(p_product_id uuid)
RETURNS text
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(
    NULLIF(btrim(pc.variation_account_code), ''),
    '603000'  -- Fallback par défaut
  )
  FROM products p
  LEFT JOIN product_categories pc ON pc.id = p.category_id AND pc.tenant_id = p.tenant_id
  WHERE p.id = p_product_id;
$$;

-- ------------------------------------------------------------
-- 4. La réception nourrit le stock, son dépôt et sa valorisation (S-01 → S-03)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION create_stock_on_goods_receipt()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_line RECORD;
  v_warehouse uuid;
  v_unit_cost numeric;
BEGIN
  -- Ne réagir qu'au passage à 'received'
  IF NEW.status <> 'received' THEN
    RETURN NEW;
  END IF;

  IF OLD.status = 'received' THEN
    RETURN NEW;
  END IF;

  -- S-04 : le dépôt de la réception, sinon le dépôt de la société
  v_warehouse := COALESCE(NEW.warehouse_id, resolve_default_warehouse(NEW.tenant_id));

  FOR v_line IN
    SELECT * FROM goods_receipt_lines
    WHERE goods_receipt_id = NEW.id
      AND tenant_id = NEW.tenant_id
      AND quantity_received > 0
  LOOP
    -- S-02 : coût de la ligne de commande, sinon prix d'achat de l'article,
    -- sinon coût de revient. Sans aucun des trois : 0, et pas d'écriture.
    v_unit_cost := NULL;

    IF NEW.purchase_order_id IS NOT NULL THEN
      SELECT NULLIF(pol.unit_price, 0) INTO v_unit_cost
      FROM purchase_order_lines pol
      WHERE pol.purchase_order_id = NEW.purchase_order_id
        AND pol.tenant_id = NEW.tenant_id
        AND pol.product_id = v_line.product_id
      ORDER BY pol.line_order NULLS LAST, pol.id
      LIMIT 1;
    END IF;

    IF v_unit_cost IS NULL THEN
      SELECT NULLIF(COALESCE(p.purchase_price, 0), 0) INTO v_unit_cost
      FROM products p
      WHERE p.id = v_line.product_id AND p.tenant_id = NEW.tenant_id;
    END IF;

    IF v_unit_cost IS NULL THEN
      SELECT NULLIF(COALESCE(p.cost_price, 0), 0) INTO v_unit_cost
      FROM products p
      WHERE p.id = v_line.product_id AND p.tenant_id = NEW.tenant_id;
    END IF;

    v_unit_cost := COALESCE(v_unit_cost, 0);

    INSERT INTO stock_movements (
      tenant_id, product_id, warehouse_id, movement_type, type, quantity, unit_cost,
      lot_id, serial_id,
      reference, reference_type, reference_id,
      date, movement_date, notes
    ) VALUES (
      NEW.tenant_id, v_line.product_id, v_warehouse, 'in', 'in', v_line.quantity_received, v_unit_cost,
      v_line.lot_id, v_line.serial_id,
      'BR-' || NEW.number, 'goods_receipt', NEW.id,
      NEW.receipt_date, NEW.receipt_date,
      'Réception automatique - BR ' || NEW.number
    );
  END LOOP;

  RETURN NEW;
END $$;

-- ------------------------------------------------------------
-- 5. La traçabilité refuse au lieu d'avertir (S-11)
--    Décision inversée par rapport à LOT4-14 : un avertissement que personne
--    ne lit laisse entrer et sortir un article suivi sans lot, ce qui rend la
--    traçabilité fausse plutôt qu'absente. Le lot (ou le numéro de série) de
--    la ligne de réception suit désormais le mouvement : les chemins existants
--    qui le renseignent continuent de fonctionner.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION check_tracking_on_stock_movement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tracking text;
  v_name text;
BEGIN
  SELECT tracking, name INTO v_tracking, v_name
  FROM products
  WHERE id = NEW.product_id AND tenant_id = NEW.tenant_id;

  IF v_tracking = 'lot' AND NEW.lot_id IS NULL THEN
    RAISE EXCEPTION 'Article % suivi en lot : le lot est obligatoire sur un mouvement de stock', COALESCE(v_name, NEW.product_id::text)
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_tracking = 'serial' AND NEW.serial_id IS NULL THEN
    RAISE EXCEPTION 'Article % suivi en numéro de série : le numéro est obligatoire sur un mouvement de stock', COALESCE(v_name, NEW.product_id::text)
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END $$;

-- ------------------------------------------------------------
-- 6. Les comptes de l'écriture de stock sont résolus, pas codés en dur (S-10)
--    Le reste du corps est inchangé (187/172/176) : coût de sortie pris au
--    CUMP du dépôt, idempotence par `piece_number`, production hors de ce
--    déclencheur.
-- ------------------------------------------------------------
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
  v_unit_cost numeric;
  v_product RECORD;
  v_stock_account text;
  v_variation_account text;
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

  -- Le journal des stocks fait partie des journaux standard : sans lui, la clé
  -- étrangère (tenant_id, journal_code) ferait échouer le mouvement lui-même.
  IF NOT EXISTS (SELECT 1 FROM journals WHERE tenant_id = NEW.tenant_id AND code = 'ST') THEN
    PERFORM ensure_standard_journals(NEW.tenant_id);
  END IF;

  -- S-10 : article, puis famille d'articles, puis le plan standard
  v_stock_account := COALESCE(resolve_stock_account(NEW.product_id), '310000');
  v_variation_account := COALESCE(resolve_variation_account(NEW.product_id), '603000');

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
END $$;

-- ------------------------------------------------------------
-- 7. Droits — le résolveur de dépôt est interne, les résolveurs de comptes
--    restent ceux du registre de ci/check_tenant_guard.sql (lecture seule)
-- ------------------------------------------------------------
REVOKE ALL ON FUNCTION resolve_default_warehouse(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION create_stock_on_goods_receipt() TO service_role;
GRANT EXECUTE ON FUNCTION create_journal_on_stock_movement() TO service_role;
GRANT EXECUTE ON FUNCTION check_tracking_on_stock_movement() TO service_role;
