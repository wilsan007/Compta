-- ============================================================
-- 148_fix_three_way_matching_limit1.sql
-- LOT4-12 : Rapprochement 3 voies en LIMIT 1
--
-- Problème : LIMIT 1 sans consommer les reliquats → double facturation
-- non détectée. Deux lignes de facture de 10 contre une commande de 10
-- passent en 'matched'.
--
-- Fix : Utiliser des tables temporaires qui suivent les quantités
-- restantes et les consomment dans la boucle.
-- ============================================================

CREATE OR REPLACE FUNCTION perform_three_way_match()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_po_id uuid;
  v_gr_id uuid;
  v_po RECORD;
  v_po_line RECORD;
  v_gr_line RECORD;
  v_inv_line RECORD;
  v_total_ordered numeric := 0;
  v_total_received numeric := 0;
  v_total_invoiced numeric := 0;
  v_price_variance numeric := 0;
  v_quantity_variance numeric := 0;
  v_line_results jsonb := '[]'::jsonb;
  v_line_result jsonb;
  v_match_status varchar := 'matched';
  v_has_receipt boolean := false;
  v_tolerance numeric := 0.01;
  v_line_status varchar;
  v_qty_to_consume numeric;
  v_qty_consumed numeric;
BEGIN
  IF NEW.approval_status IS NOT DISTINCT FROM OLD.approval_status THEN RETURN NEW; END IF;
  IF NEW.approval_status NOT IN ('pending', 'submitted') THEN RETURN NEW; END IF;

  v_po_id := NEW.purchase_order_id;
  v_gr_id := NEW.goods_receipt_id;

  IF v_po_id IS NULL THEN
    NEW.match_status := 'pending_review';
    NEW.match_details := jsonb_build_object('reason', 'no_purchase_order_linked');
    RETURN NEW;
  END IF;

  v_has_receipt := v_gr_id IS NOT NULL;

  SELECT * INTO v_po FROM purchase_orders WHERE id = v_po_id AND tenant_id = NEW.tenant_id;
  IF NOT FOUND THEN
    NEW.match_status := 'pending_review';
    NEW.match_details := jsonb_build_object('reason', 'purchase_order_not_found');
    RETURN NEW;
  END IF;

  -- LOT4-12 : Tables temporaires avec quantités restantes
  DROP TABLE IF EXISTS _po_remaining;
  CREATE TEMP TABLE _po_remaining AS
  SELECT id, product_id, quantity AS qty_left, unit_price
  FROM purchase_order_lines
  WHERE purchase_order_id = v_po_id AND tenant_id = NEW.tenant_id;

  DROP TABLE IF EXISTS _gr_remaining;
  CREATE TEMP TABLE _gr_remaining AS
  SELECT id, product_id, quantity_received AS qty_left
  FROM goods_receipt_lines
  WHERE goods_receipt_id = v_gr_id AND tenant_id = NEW.tenant_id;

  FOR v_inv_line IN
    SELECT * FROM purchase_invoice_lines
    WHERE purchase_invoice_id = NEW.id AND tenant_id = NEW.tenant_id
    ORDER BY line_order
  LOOP
    -- LOT4-13 : Réinitialiser les variables d'écart
    v_line_status := 'matched';
    v_price_variance := 0;
    v_quantity_variance := 0;
    v_total_invoiced := v_total_invoiced + COALESCE(v_inv_line.quantity, 0) * COALESCE(v_inv_line.unit_price, 0);

    -- LOT4-12 : Trouver la ligne du PO et consommer la quantité
    IF v_inv_line.purchase_order_line_id IS NOT NULL THEN
      SELECT * INTO v_po_line FROM _po_remaining
      WHERE id = v_inv_line.purchase_order_line_id AND qty_left > 0
      LIMIT 1;
    ELSE
      SELECT * INTO v_po_line FROM _po_remaining
      WHERE product_id = v_inv_line.product_id AND qty_left > 0
      ORDER BY id LIMIT 1;
    END IF;

    IF FOUND THEN
      v_total_ordered := v_total_ordered + COALESCE(v_po_line.quantity, 0) * COALESCE(v_po_line.unit_price, 0);

      -- LOT4-12 : Consommer la quantité
      v_qty_to_consume := LEAST(v_po_line.qty_left, COALESCE(v_inv_line.quantity, 0));
      UPDATE _po_remaining SET qty_left = qty_left - v_qty_to_consume WHERE id = v_po_line.id;

      -- Vérifier le prix
      IF v_po_line.unit_price > 0 THEN
        v_price_variance := ABS(v_inv_line.unit_price - v_po_line.unit_price) / v_po_line.unit_price;
        IF v_price_variance > v_tolerance THEN
          v_line_status := 'price_mismatch';
          v_match_status := 'mismatch';
        END IF;
      END IF;

      -- Vérifier la quantité si réception
      IF v_has_receipt THEN
        -- LOT4-12 : Trouver la ligne de réception et consommer
        SELECT * INTO v_gr_line FROM _gr_remaining
        WHERE product_id = v_inv_line.product_id AND qty_left > 0
        ORDER BY id LIMIT 1;

        IF FOUND THEN
          v_total_received := v_total_received + COALESCE(v_gr_line.qty_left, 0) * COALESCE(v_po_line.unit_price, 0);

          -- Consommer la quantité reçue
          v_qty_consumed := LEAST(v_gr_line.qty_left, v_qty_to_consume);
          UPDATE _gr_remaining SET qty_left = qty_left - v_qty_consumed WHERE id = v_gr_line.id;

          -- Quantité facturée ne doit pas dépasser quantité reçue
          IF v_inv_line.quantity > v_gr_line.qty_left THEN
            v_quantity_variance := v_inv_line.quantity - v_gr_line.qty_left;
            v_line_status := 'quantity_exceeds_received';
            v_match_status := 'mismatch';
          END IF;

          v_line_result := jsonb_build_object(
            'invoice_line_id', v_inv_line.id,
            'product_id', v_inv_line.product_id,
            'po_quantity', v_po_line.quantity,
            'po_unit_price', v_po_line.unit_price,
            'received_quantity', v_gr_line.qty_left,
            'invoiced_quantity', v_inv_line.quantity,
            'invoice_unit_price', v_inv_line.unit_price,
            'price_variance', v_price_variance,
            'quantity_variance', v_quantity_variance,
            'status', v_line_status
          );
        ELSE
          v_line_status := 'no_receipt_line';
          IF v_match_status = 'matched' THEN v_match_status := 'partial_match'; END IF;

          v_line_result := jsonb_build_object(
            'invoice_line_id', v_inv_line.id,
            'product_id', v_inv_line.product_id,
            'po_quantity', v_po_line.quantity,
            'po_unit_price', v_po_line.unit_price,
            'received_quantity', 0,
            'invoiced_quantity', v_inv_line.quantity,
            'invoice_unit_price', v_inv_line.unit_price,
            'status', v_line_status
          );
        END IF;
      ELSE
        v_line_status := 'no_receipt';
        IF v_match_status = 'matched' THEN v_match_status := 'pending_review'; END IF;

        v_line_result := jsonb_build_object(
          'invoice_line_id', v_inv_line.id,
          'product_id', v_inv_line.product_id,
          'po_quantity', v_po_line.quantity,
          'po_unit_price', v_po_line.unit_price,
          'received_quantity', null,
          'invoiced_quantity', v_inv_line.quantity,
          'invoice_unit_price', v_inv_line.unit_price,
          'status', v_line_status
        );
      END IF;
    ELSE
      -- LOT4-12 : Pas de ligne de PO disponible (quantité épuisée)
      v_line_status := 'no_po_line_or_exhausted';
      v_match_status := 'mismatch';

      v_line_result := jsonb_build_object(
        'invoice_line_id', v_inv_line.id,
        'product_id', v_inv_line.product_id,
        'po_quantity', 0,
        'po_unit_price', 0,
        'received_quantity', 0,
        'invoiced_quantity', v_inv_line.quantity,
        'invoice_unit_price', v_inv_line.unit_price,
        'status', v_line_status,
        'reason', 'po_quantity_exhausted'
      );
    END IF;

    v_line_results := v_line_results || jsonb_build_array(v_line_result);
  END LOOP;

  NEW.match_status := v_match_status;
  NEW.match_details := jsonb_build_object(
    'total_ordered', v_total_ordered,
    'total_received', v_total_received,
    'total_invoiced', v_total_invoiced,
    'line_results', v_line_results
  );

  DROP TABLE IF EXISTS _po_remaining;
  DROP TABLE IF EXISTS _gr_remaining;

  RETURN NEW;
END;
$$;
