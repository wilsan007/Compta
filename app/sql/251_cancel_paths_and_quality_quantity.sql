-- ============================================================
-- 251_cancel_paths_and_quality_quantity.sql — S-12, S-13
--
-- Audit des modules hors comptabilité (23/09), § S-08 à S-13.
--
--   S-12 🟡 Une réception passée à « received » entre en stock (241 : mouvement,
--           dépôt, couche, écriture). Son ANNULATION ne fait rien : le stock,
--           la couche et l'écriture restent. Mesuré : réception de 10 à 7 puis
--           `status = 'cancelled'` → article 110, dépôt 110, couches 110,
--           0 contrepassation. Le stock affiché ne correspond plus aux
--           marchandises présentes. (Le côté livraison, lui, est mesuré par la
--           suite 230 : un BL réexpédié est refusé explicitement.)
--   S-13 🟠 `quality_checks` n'a pas de colonne quantité : un contrôle en échec
--           rebute `quantity_received`, la TOTALITÉ de la ligne reçue. Mesuré :
--           10 rebutés pour 3 contrôlés. Et le mouvement de rebut ne porte pas
--           de dépôt : l'article baisse, le dépôt non (mesuré : 100 / 110).
--
-- CORRECTIFS
--   1. `quality_checks` gagne `quantity_checked` et `quantity_rejected`, avec
--      leur cohérence (positives, rebut ≤ contrôlé) et un refus de contrôler
--      plus que ce qui est entré.
--   2. Le rebut ne porte plus que la quantité contrôlée (ou rebutée si elle est
--      donnée), il porte le dépôt de la réception et le lot de sa ligne — et il
--      ne s'écrit pas deux fois pour un même contrôle.
--      `failed` sans quantité = tout le reçu (le comportement d'avant, dit) ;
--      `partial` sans quantité rebutée = rien.
--   3. Une réception ne rentre pas deux fois en stock (le statut ne se rejoue
--      pas), et une annulation contrepasse : une sortie miroir par entrée, au
--      même coût, plus l'écriture inverse au journal ST. L'écriture d'origine
--      reste intacte — c'est la doctrine comptable du dépôt (« utiliser
--      l'extourne pour annuler »), pas une réécriture.
--
-- LIMITES DITES
--   * Le coût de la sortie de contrepassation est celui de l'entrée d'origine
--     (7 × 10 = 70) : la contrepassation est le miroir exact de l'écriture.
--     La consommation des couches reste FIFO (`consume_valuation_layers_on_exit`),
--     donc la valeur des couches peut différer du CUMP affiché — coexistence
--     des deux méthodes, antérieure à cette vague et non refermée ici.
--   * Annuler un BL **expédié** ne contrepasse toujours pas sa sortie de stock :
--     c'est le pendant du point 3, mesuré par la suite 230 et inscrit comme
--     reste à faire (le chemin existe, l'écriture doit être écrite).
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. Le contrôle qualité dit COMBIEN il a contrôlé (S-13)
-- ─────────────────────────────────────────────────────────────
ALTER TABLE quality_checks ADD COLUMN IF NOT EXISTS quantity_checked numeric;
ALTER TABLE quality_checks ADD COLUMN IF NOT EXISTS quantity_rejected numeric;

COMMENT ON COLUMN quality_checks.quantity_checked IS
  '251 : quantité réellement contrôlée. NULL = tout ce qui est entré (comportement d''avant la 251, conservé).';
COMMENT ON COLUMN quality_checks.quantity_rejected IS
  '251 : quantité rebutée. Si NULL : tout le contrôlé sur un échec, rien sur un contrôle partiel.';

ALTER TABLE quality_checks DROP CONSTRAINT IF EXISTS quality_checks_quantities_check;
ALTER TABLE quality_checks ADD CONSTRAINT quality_checks_quantities_check
  CHECK (COALESCE(quantity_checked, 0) >= 0
         AND COALESCE(quantity_rejected, 0) >= 0
         AND (quantity_rejected IS NULL OR quantity_checked IS NULL
              OR quantity_rejected <= quantity_checked));

-- Un contrôle ne peut pas porter sur plus de marchandises qu'il n'en est entré.
CREATE OR REPLACE FUNCTION public.validate_quality_check_quantities()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_recu numeric;
BEGIN
  IF NEW.quantity_checked IS NOT NULL
     AND NEW.reference_type = 'goods_receipt'
     AND NEW.reference_id IS NOT NULL THEN
    SELECT COALESCE(SUM(grl.quantity_received), 0) INTO v_recu
    FROM goods_receipt_lines grl
    WHERE grl.goods_receipt_id = NEW.reference_id
      AND grl.tenant_id = NEW.tenant_id
      AND (NEW.product_id IS NULL OR grl.product_id = NEW.product_id);

    IF NEW.quantity_checked > v_recu THEN
      RAISE EXCEPTION 'Contrôle qualité : % contrôlé(s) pour % reçu(s) sur l''article. Un contrôle ne porte pas sur des marchandises qui ne sont pas entrées.',
        NEW.quantity_checked, v_recu
        USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END $$;

COMMENT ON FUNCTION public.validate_quality_check_quantities() IS
  '251 (S-13) : refuse un contrôle portant sur plus que la quantité reçue de la réception.';

DROP TRIGGER IF EXISTS validate_quality_check_quantities_trg ON quality_checks;
CREATE TRIGGER validate_quality_check_quantities_trg
  BEFORE INSERT OR UPDATE ON quality_checks
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_quality_check_quantities();

-- ─────────────────────────────────────────────────────────────
-- 2. Le rebut ne porte que ce qui a été contrôlé, au bon dépôt (S-13)
-- ─────────────────────────────────────────────────────────────
-- 141 (STK-01b) avait déjà posé la bonne règle : la réception fait entrer, le
-- contrôle ne fait que rebuter. Ce qui change ici : COMBIEN il rebute, et OÙ.
CREATE OR REPLACE FUNCTION create_stock_in_on_quality_pass()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_gr_line RECORD;
  v_deja int;
  v_warehouse uuid;
  v_qte numeric;
BEGIN
  -- Le contrôle réussi n'entre pas (la réception l'a fait). L'échec et le
  -- partiel rebutent.
  IF NOT (NEW.status IS DISTINCT FROM OLD.status AND NEW.status IN ('failed', 'partial')) THEN
    RETURN NEW;
  END IF;

  IF NEW.reference_type <> 'goods_receipt' OR NEW.reference_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Idempotence : un contrôle qui passerait de « partiel » à « échoué » ne
  -- rebute pas deux fois.
  SELECT count(*) INTO v_deja
  FROM stock_movements
  WHERE tenant_id = NEW.tenant_id AND reference_type = 'quality_check' AND reference_id = NEW.id;

  IF v_deja > 0 THEN
    RETURN NEW;
  END IF;

  -- Le dépôt : celui de l'entrée de la réception, sinon le dépôt de la société.
  -- Sans lui, le rebut baissait l'article et pas le dépôt (mesuré : 100 / 110).
  SELECT sm.warehouse_id INTO v_warehouse
  FROM stock_movements sm
  WHERE sm.tenant_id = NEW.tenant_id
    AND sm.reference_type = 'goods_receipt'
    AND sm.reference_id = NEW.reference_id
    AND sm.movement_type = 'in'
    AND (NEW.product_id IS NULL OR sm.product_id = NEW.product_id)
  ORDER BY sm.created_at NULLS LAST, sm.id
  LIMIT 1;

  v_warehouse := COALESCE(v_warehouse, resolve_default_warehouse(NEW.tenant_id));

  FOR v_gr_line IN
    SELECT * FROM goods_receipt_lines
    WHERE goods_receipt_id = NEW.reference_id
      AND tenant_id = NEW.tenant_id
      AND (NEW.product_id IS NULL OR product_id = NEW.product_id)
      AND quantity_received > 0
  LOOP
    -- La quantité rebutée : nommée si elle l'est ; sinon le contrôlé sur un
    -- échec (le comportement d'avant la 251 quand rien n'est nommé) ; rien sur
    -- un contrôle partiel dont le rebut n'est pas nommé.
    v_qte := CASE
      WHEN NEW.status = 'partial' THEN COALESCE(NEW.quantity_rejected, 0)
      ELSE COALESCE(NEW.quantity_rejected, NEW.quantity_checked, v_gr_line.quantity_received)
    END;
    v_qte := LEAST(COALESCE(v_qte, 0), v_gr_line.quantity_received);

    IF v_qte > 0 THEN
      INSERT INTO stock_movements (
        tenant_id, product_id, warehouse_id, movement_type, type, quantity,
        lot_id, serial_id,
        reference, reference_type, reference_id,
        date, movement_date, notes
      ) VALUES (
        NEW.tenant_id, v_gr_line.product_id, v_warehouse, 'out', 'out', v_qte,
        v_gr_line.lot_id, v_gr_line.serial_id,
        'QC-REJECT-' || COALESCE(NEW.checked_by, 'auto'),
        'quality_check', NEW.id,
        CURRENT_DATE, CURRENT_DATE,
        'Rebut après contrôle : ' || v_qte || ' sur ' || v_gr_line.quantity_received || ' reçu(s)'
      );
    END IF;
  END LOOP;

  RETURN NEW;
END $$;

COMMENT ON FUNCTION create_stock_in_on_quality_pass() IS
  '251 (S-13) : sur échec ou contrôle partiel, rebute la quantité contrôlée (ou rebutée) au dépôt de la réception, jamais la totalité de la ligne reçue. La réception (241) reste la seule à faire entrer.';



-- ─────────────────────────────────────────────────────────────
-- 3. Une réception ne rentre pas deux fois (S-12)
-- ─────────────────────────────────────────────────────────────
-- Le statut « received » est atteignable depuis « cancelled » : le déclencheur
-- de la 241 (create_stock_on_goods_receipt, AFTER UPDATE) ne regarde que
-- OLD.status = 'received' et recréait une entrée — sans erreur. Un garde
-- BEFORE, juste avant lui, refuse la réédition pour ce qu'elle est.
CREATE OR REPLACE FUNCTION public.prevent_goods_receipt_double_entry()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.status = 'received' AND OLD.status IS DISTINCT FROM 'received'
     AND EXISTS (
       SELECT 1 FROM stock_movements sm
       WHERE sm.tenant_id = NEW.tenant_id
         AND sm.reference_type = 'goods_receipt'
         AND sm.reference_id = NEW.id)
  THEN
    RAISE EXCEPTION 'BR % est déjà entrée en stock : sa réception est comptabilisée. Elle ne se rejoue pas — annuler la réception (statut « cancelled ») écrit la contrepassation.', NEW.number
      USING ERRCODE = '23505';
  END IF;
  RETURN NEW;
END $$;

COMMENT ON FUNCTION public.prevent_goods_receipt_double_entry() IS
  '251 (S-12) : une réception déjà entrée en stock ne peut pas être « reçue » une seconde fois.';

DROP TRIGGER IF EXISTS prevent_goods_receipt_double_entry_trg ON goods_receipts;
CREATE TRIGGER prevent_goods_receipt_double_entry_trg
  BEFORE UPDATE ON goods_receipts
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_goods_receipt_double_entry();


-- ─────────────────────────────────────────────────────────────
-- 4. Annuler une réception remet le stock et contrepasse l'écriture (S-12)
-- ─────────────────────────────────────────────────────────────
-- Une sortie miroir par entrée d'origine, au même coût : l'écriture d'origine
-- reste intacte, la contrepassation est exacte. Couche de valorisation et CUMP
-- suivent par les déclencheurs existants du stock.
CREATE OR REPLACE FUNCTION public.reverse_stock_on_goods_receipt_cancel()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_src RECORD;
  v_n int := 0;
BEGIN
  IF NOT (NEW.status = 'cancelled' AND OLD.status IN ('received', 'partial')) THEN
    RETURN NEW;
  END IF;

  -- Une contrepassation ne s'écrit qu'une fois.
  IF EXISTS (
    SELECT 1 FROM stock_movements sm
    WHERE sm.tenant_id = NEW.tenant_id
      AND sm.reference_type = 'goods_receipt_cancel'
      AND sm.reference_id = NEW.id)
  THEN
    RAISE EXCEPTION 'BR % : sa contrepassation de stock est déjà écrite. Annuler deux fois ne remet pas le stock deux fois.', NEW.number
      USING ERRCODE = '23505';
  END IF;

  FOR v_src IN
    SELECT * FROM stock_movements sm
    WHERE sm.tenant_id = NEW.tenant_id
      AND sm.reference_type = 'goods_receipt'
      AND sm.reference_id = NEW.id
      AND sm.movement_type = 'in'
    ORDER BY sm.created_at NULLS LAST, sm.id
  LOOP
    INSERT INTO stock_movements (
      tenant_id, product_id, warehouse_id, movement_type, type, quantity, unit_cost,
      lot_id, serial_id,
      reference, reference_type, reference_id,
      date, movement_date, notes
    ) VALUES (
      NEW.tenant_id, v_src.product_id, v_src.warehouse_id, 'out', 'out', v_src.quantity, v_src.unit_cost,
      v_src.lot_id, v_src.serial_id,
      'BR-ANN-' || NEW.number, 'goods_receipt_cancel', NEW.id,
      CURRENT_DATE, CURRENT_DATE,
      'Annulation de la réception BR ' || NEW.number
    );
    v_n := v_n + 1;
  END LOOP;

  RETURN NEW;
END $$;

COMMENT ON FUNCTION public.reverse_stock_on_goods_receipt_cancel() IS
  '251 (S-12) : annuler une réception reçue écrit la sortie de stock miroir, et son écriture au journal ST. L''écriture d''origine reste intacte — contrepassation, jamais réécriture.';

DROP TRIGGER IF EXISTS trg_goods_receipt_cancel_reverse ON goods_receipts;
CREATE TRIGGER trg_goods_receipt_cancel_reverse
  AFTER UPDATE OF status ON goods_receipts
  FOR EACH ROW
  EXECUTE FUNCTION public.reverse_stock_on_goods_receipt_cancel();

-- ─────────────────────────────────────────────────────────────
-- 5. Droits — un déclencheur n'est pas une RPC (leçon de la 228)
-- ─────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.validate_quality_check_quantities() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.prevent_goods_receipt_double_entry() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.reverse_stock_on_goods_receipt_cancel() FROM PUBLIC, anon, authenticated;
