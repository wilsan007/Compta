-- ============================================================
-- 147_fix_composite_documents_atomic.sql
-- LOT4-11 : Documents composés non atomiques
--
-- Problème : createInvoice insère l'en-tête puis les lignes sans
-- transaction. Si la 2e insertion échoue, la facture reste sans lignes.
--
-- Fix : Créer des RPC atomiques pour les 5 documents :
-- - facture de vente
-- - facture d'achat
-- - devis
-- - commande
-- - bon de livraison
-- ============================================================

-- ============================================================
-- 1. Facture de vente atomique
-- ============================================================
CREATE OR REPLACE FUNCTION create_invoice_atomic(p_invoice jsonb, p_lines jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_id uuid;
  v_line jsonb;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- Insérer l'en-tête
  INSERT INTO invoices SELECT * FROM jsonb_populate_record(
    NULL::invoices, p_invoice || jsonb_build_object('tenant_id', v_tid)
  )
  RETURNING id INTO v_id;

  -- Insérer les lignes
  FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    INSERT INTO invoice_lines SELECT * FROM jsonb_populate_record(
      NULL::invoice_lines,
      v_line || jsonb_build_object('invoice_id', v_id, 'tenant_id', v_tid)
    );
  END LOOP;

  RETURN jsonb_build_object('success', true, 'invoice_id', v_id);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- ============================================================
-- 2. Facture d'achat atomique
-- ============================================================
CREATE OR REPLACE FUNCTION create_purchase_invoice_atomic(p_invoice jsonb, p_lines jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_id uuid;
  v_line jsonb;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  INSERT INTO purchase_invoices SELECT * FROM jsonb_populate_record(
    NULL::purchase_invoices, p_invoice || jsonb_build_object('tenant_id', v_tid)
  )
  RETURNING id INTO v_id;

  FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    INSERT INTO purchase_invoice_lines SELECT * FROM jsonb_populate_record(
      NULL::purchase_invoice_lines,
      v_line || jsonb_build_object('purchase_invoice_id', v_id, 'tenant_id', v_tid)
    );
  END LOOP;

  RETURN jsonb_build_object('success', true, 'purchase_invoice_id', v_id);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- ============================================================
-- 3. Devis atomique
-- ============================================================
CREATE OR REPLACE FUNCTION create_quote_atomic(p_quote jsonb, p_lines jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_id uuid;
  v_line jsonb;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  INSERT INTO quotes SELECT * FROM jsonb_populate_record(
    NULL::quotes, p_quote || jsonb_build_object('tenant_id', v_tid)
  )
  RETURNING id INTO v_id;

  FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    INSERT INTO quote_lines SELECT * FROM jsonb_populate_record(
      NULL::quote_lines,
      v_line || jsonb_build_object('quote_id', v_id, 'tenant_id', v_tid)
    );
  END LOOP;

  RETURN jsonb_build_object('success', true, 'quote_id', v_id);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- ============================================================
-- 4. Commande atomique
-- ============================================================
CREATE OR REPLACE FUNCTION create_sales_order_atomic(p_order jsonb, p_lines jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_id uuid;
  v_line jsonb;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  INSERT INTO sales_orders SELECT * FROM jsonb_populate_record(
    NULL::sales_orders, p_order || jsonb_build_object('tenant_id', v_tid)
  )
  RETURNING id INTO v_id;

  FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    INSERT INTO sales_order_lines SELECT * FROM jsonb_populate_record(
      NULL::sales_order_lines,
      v_line || jsonb_build_object('sales_order_id', v_id, 'tenant_id', v_tid)
    );
  END LOOP;

  RETURN jsonb_build_object('success', true, 'sales_order_id', v_id);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- ============================================================
-- 5. Bon de livraison atomique
-- ============================================================
CREATE OR REPLACE FUNCTION create_delivery_note_atomic(p_note jsonb, p_lines jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_id uuid;
  v_line jsonb;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  INSERT INTO delivery_notes SELECT * FROM jsonb_populate_record(
    NULL::delivery_notes, p_note || jsonb_build_object('tenant_id', v_tid)
  )
  RETURNING id INTO v_id;

  FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    INSERT INTO delivery_note_lines SELECT * FROM jsonb_populate_record(
      NULL::delivery_note_lines,
      v_line || jsonb_build_object('delivery_note_id', v_id, 'tenant_id', v_tid)
    );
  END LOOP;

  RETURN jsonb_build_object('success', true, 'delivery_note_id', v_id);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- Grants
GRANT EXECUTE ON FUNCTION create_invoice_atomic(jsonb, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION create_purchase_invoice_atomic(jsonb, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION create_quote_atomic(jsonb, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION create_sales_order_atomic(jsonb, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION create_delivery_note_atomic(jsonb, jsonb) TO authenticated;
