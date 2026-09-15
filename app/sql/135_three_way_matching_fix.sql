-- ============================================================
-- Migration 132 : Correction du three-way matching
--   TRG-01a : LIMIT 1 appareille la première ligne au lieu de consommer les reliquats
--   TRG-01b : v_price_variance et v_quantity_variance non réinitialisés
-- Idempotent — CREATE OR REPLACE
-- ============================================================

CREATE OR REPLACE FUNCTION check_three_way_match()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := NEW.tenant_id;
  v_po_id uuid;
  v_gr_id uuid;
  v_has_receipt boolean := false;
  v_tolerance float := 0.01;  -- 1% de tolérance
  v_match_status text := 'matched';
  v_line_status text;
  v_total_invoiced numeric := 0;
  v_total_ordered numeric := 0;
  v_total_received numeric := 0;
  v_price_variance float := 0;
  v_quantity_variance float := 0;
  v_inv_line RECORD;
  v_po_line RECORD;
  v_gr_line RECORD;
  v_line_result jsonb;
  v_results jsonb := '[]'::jsonb;
  v_po_matched_qty_map jsonb := '{}'::jsonb;  -- TRG-01a : tracker les quantités déjà matchées
  v_gr_matched_qty_map jsonb := '{}'::jsonb;  -- TRG-01a : tracker les quantités déjà reçues
  v_po_remaining numeric;
  v_gr_remaining numeric;
  v_po_line_key text;
  v_gr_line_key text;
BEGIN
  -- Récupérer le PO et la réception liés
  SELECT purchase_order_id INTO v_po_id
  FROM purchase_invoices
  WHERE id = NEW.id AND tenant_id = v_tid;

  IF v_po_id IS NULL THEN
    -- Pas de PO lié — pas de three-way matching
    NEW.match_status := 'no_po';
    NEW.match_details := jsonb_build_object('reason', 'Aucun bon de commande lié');
    RETURN NEW;
  END IF;

  -- Vérifier s'il y a une réception
  SELECT id INTO v_gr_id
  FROM goods_receipts
  WHERE reference_type = 'purchase_order' AND reference_id = v_po_id AND tenant_id = v_tid
  LIMIT 1;
  v_has_receipt := v_gr_id IS NOT NULL;

  -- Parcourir les lignes de facture
  FOR v_inv_line IN
    SELECT * FROM purchase_invoice_lines
    WHERE purchase_invoice_id = NEW.id AND tenant_id = v_tid
    ORDER BY line_order
  LOOP
    -- TRG-01b : Réinitialiser les variables à chaque itération
    v_line_status := 'matched';
    v_price_variance := 0;
    v_quantity_variance := 0;

    v_total_invoiced := v_total_invoiced + COALESCE(v_inv_line.quantity, 0) * COALESCE(v_inv_line.unit_price, 0);

    -- Trouver la ligne du PO correspondante
    IF v_inv_line.purchase_order_line_id IS NOT NULL THEN
      SELECT * INTO v_po_line
      FROM purchase_order_lines
      WHERE id = v_inv_line.purchase_order_line_id AND tenant_id = v_tid;
    ELSE
      -- TRG-01a : Matching par product_id en consommant les reliquats
      -- Au lieu de LIMIT 1 qui prend toujours la première ligne,
      -- on cherche la ligne avec du reliquat non encore matché
      v_po_line_key := v_inv_line.product_id::text;
      v_po_remaining := COALESCE((v_po_matched_qty_map ->> v_po_line_key)::numeric, 0);

      SELECT * INTO v_po_line
      FROM purchase_order_lines
      WHERE purchase_order_id = v_po_id
        AND tenant_id = v_tid
        AND product_id = v_inv_line.product_id
        AND quantity > v_po_remaining  -- TRG-01a : ligne avec reliquat disponible
      ORDER BY line_order
      LIMIT 1;
    END IF;

    IF FOUND THEN
      -- TRG-01a : Tracker la quantité matchée
      v_po_line_key := v_po_line.id::text;
      v_po_matched_qty_map := jsonb_set(
        v_po_matched_qty_map,
        ARRAY[v_po_line.product_id::text],
        to_jsonb(COALESCE((v_po_matched_qty_map ->> v_po_line.product_id::text)::numeric, 0) + v_inv_line.quantity)
      );

      v_total_ordered := v_total_ordered + COALESCE(v_po_line.quantity, 0) * COALESCE(v_po_line.unit_price, 0);

      -- Vérifier le prix (tolérance 1%)
      IF v_po_line.unit_price > 0 THEN
        v_price_variance := ABS(v_inv_line.unit_price - v_po_line.unit_price) / v_po_line.unit_price;
        IF v_price_variance > v_tolerance THEN
          v_line_status := 'price_mismatch';
          v_match_status := 'mismatch';
        END IF;
      END IF;

      -- Vérifier la quantité si on a une réception
      IF v_has_receipt THEN
        -- TRG-01a : Matching par product_id en consommant les reliquats de réception
        v_gr_line_key := v_inv_line.product_id::text;
        v_gr_remaining := COALESCE((v_gr_matched_qty_map ->> v_gr_line_key)::numeric, 0);

        SELECT * INTO v_gr_line
        FROM goods_receipt_lines
        WHERE goods_receipt_id = v_gr_id
          AND tenant_id = v_tid
          AND product_id = v_inv_line.product_id
          AND quantity_received > v_gr_remaining  -- TRG-01a : ligne avec reliquat
        ORDER BY line_order
        LIMIT 1;

        IF FOUND THEN
          -- TRG-01a : Tracker la quantité reçue matchée
          v_gr_matched_qty_map := jsonb_set(
            v_gr_matched_qty_map,
            ARRAY[v_inv_line.product_id::text],
            to_jsonb(COALESCE((v_gr_matched_qty_map ->> v_gr_line_key)::numeric, 0) + v_gr_line.quantity_received)
          );

          v_total_received := v_total_received + COALESCE(v_gr_line.quantity_received, 0) * COALESCE(v_po_line.unit_price, 0);

          -- Quantité facturée ne doit pas dépasser quantité reçue
          IF v_inv_line.quantity > v_gr_line.quantity_received THEN
            v_quantity_variance := v_inv_line.quantity - v_gr_line.quantity_received;
            v_line_status := 'quantity_exceeds_received';
            v_match_status := 'mismatch';
          END IF;

          v_line_result := jsonb_build_object(
            'invoice_line_id', v_inv_line.id,
            'product_id', v_inv_line.product_id,
            'po_quantity', v_po_line.quantity,
            'po_unit_price', v_po_line.unit_price,
            'received_quantity', v_gr_line.quantity_received,
            'invoiced_quantity', v_inv_line.quantity,
            'invoice_unit_price', v_inv_line.unit_price,
            'price_variance', v_price_variance,
            'quantity_variance', v_quantity_variance,
            'status', v_line_status
          );
        ELSE
          -- Pas de ligne de réception pour ce produit
          v_line_status := 'no_receipt_line';
          IF v_match_status = 'matched' THEN v_match_status := 'partial_match'; END IF;

          v_line_result := jsonb_build_object(
            'invoice_line_id', v_inv_line.id,
            'product_id', v_inv_line.product_id,
            'po_quantity', v_po_line.quantity,
            'po_unit_price', v_po_line.unit_price,
            'received_quantity', 0,
            'invoiced_quantity', v_inv_line.quantity,
            'status', v_line_status
          );
        END IF;
      ELSE
        -- Pas de réception — two-way matching seulement
        v_line_result := jsonb_build_object(
          'invoice_line_id', v_inv_line.id,
          'product_id', v_inv_line.product_id,
          'po_quantity', v_po_line.quantity,
          'po_unit_price', v_po_line.unit_price,
          'invoiced_quantity', v_inv_line.quantity,
          'invoice_unit_price', v_inv_line.unit_price,
          'price_variance', v_price_variance,
          'status', v_line_status
        );
      END IF;
    ELSE
      -- Pas de ligne de PO pour ce produit
      v_line_status := 'no_po_line';
      v_match_status := 'mismatch';

      v_line_result := jsonb_build_object(
        'invoice_line_id', v_inv_line.id,
        'product_id', v_inv_line.product_id,
        'status', v_line_status
      );
    END IF;

    v_results := v_results || jsonb_build_array(v_line_result);
  END LOOP;

  -- Calculer les totaux
  NEW.match_status := v_match_status;
  NEW.match_details := jsonb_build_object(
    'lines', v_results,
    'total_invoiced', v_total_invoiced,
    'total_ordered', v_total_ordered,
    'total_received', v_total_received,
    'has_receipt', v_has_receipt
  );

  RETURN NEW;
END;
$$;
