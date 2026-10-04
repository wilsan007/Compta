-- ============================================================
-- 184_fix_composite_documents_null_id.sql — AUD-E01 du plan correctif du 21/09
--
-- Les cinq RPC de 147 inséraient `SELECT * FROM jsonb_populate_record(NULL::t, …)`.
-- Toute colonne absente du JSON devient NULL EXPLICITE, et un NULL explicite
-- n'est pas remplacé par la valeur par défaut : `id` (uuid_generate_v4()) était
-- inséré à NULL → « null value in column "id" violates not-null constraint ».
-- Le front n'envoie jamais d'id : l'écran « Nouvelle facture » échouait toujours.
--
-- Correctif : n'insérer que les colonnes présentes (et non nulles) dans le JSON ;
-- les autres prennent leur valeur par défaut. `id`, `created_at`, `updated_at`
-- et `tenant_id` ne sont jamais pris du client.
--
-- Preuve : sql/180_sales_to_ledger_tests.sql (E01).
-- ============================================================

CREATE OR REPLACE FUNCTION insert_row_from_jsonb(p_table regclass, p_row jsonb)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row jsonb := jsonb_strip_nulls(COALESCE(p_row, '{}'::jsonb));
  v_cols text;
  v_id uuid;
BEGIN
  SELECT string_agg(quote_ident(a.attname), ', ' ORDER BY a.attnum)
  INTO v_cols
  FROM pg_attribute a
  WHERE a.attrelid = p_table
    AND a.attnum > 0
    AND NOT a.attisdropped
    AND a.attgenerated = ''
    AND a.attname NOT IN ('id', 'created_at', 'updated_at')
    AND v_row ? a.attname;

  IF v_cols IS NULL THEN
    RAISE EXCEPTION 'Aucune colonne reconnue pour %', p_table;
  END IF;

  EXECUTE format(
    'INSERT INTO %s (%s) SELECT %s FROM jsonb_populate_record(NULL::%s, $1) RETURNING id',
    p_table, v_cols, v_cols, p_table
  ) USING v_row INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION insert_row_from_jsonb(regclass, jsonb) FROM PUBLIC, anon, authenticated;

-- Document composé : en-tête + lignes, en une transaction
CREATE OR REPLACE FUNCTION create_composite_document(
  p_header_table regclass, p_lines_table regclass, p_parent_column text,
  p_header jsonb, p_lines jsonb
)
RETURNS uuid
LANGUAGE plpgsql
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

  v_id := insert_row_from_jsonb(p_header_table, p_header || jsonb_build_object('tenant_id', v_tid));

  FOR v_line IN SELECT * FROM jsonb_array_elements(COALESCE(p_lines, '[]'::jsonb)) LOOP
    PERFORM insert_row_from_jsonb(p_lines_table,
      v_line || jsonb_build_object(p_parent_column, v_id, 'tenant_id', v_tid));
  END LOOP;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION create_composite_document(regclass, regclass, text, jsonb, jsonb) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION create_invoice_atomic(p_invoice jsonb, p_lines jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  RETURN jsonb_build_object('success', true, 'invoice_id',
    create_composite_document('invoices', 'invoice_lines', 'invoice_id', p_invoice, p_lines));
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

CREATE OR REPLACE FUNCTION create_purchase_invoice_atomic(p_invoice jsonb, p_lines jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  RETURN jsonb_build_object('success', true, 'purchase_invoice_id',
    create_composite_document('purchase_invoices', 'purchase_invoice_lines', 'purchase_invoice_id', p_invoice, p_lines));
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

CREATE OR REPLACE FUNCTION create_quote_atomic(p_quote jsonb, p_lines jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  RETURN jsonb_build_object('success', true, 'quote_id',
    create_composite_document('quotes', 'quote_lines', 'quote_id', p_quote, p_lines));
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

CREATE OR REPLACE FUNCTION create_sales_order_atomic(p_order jsonb, p_lines jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  RETURN jsonb_build_object('success', true, 'sales_order_id',
    create_composite_document('sales_orders', 'sales_order_lines', 'sales_order_id', p_order, p_lines));
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

CREATE OR REPLACE FUNCTION create_delivery_note_atomic(p_note jsonb, p_lines jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  RETURN jsonb_build_object('success', true, 'delivery_note_id',
    create_composite_document('delivery_notes', 'delivery_note_lines', 'delivery_note_id', p_note, p_lines));
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

REVOKE ALL ON FUNCTION create_invoice_atomic(jsonb, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION create_purchase_invoice_atomic(jsonb, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION create_quote_atomic(jsonb, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION create_sales_order_atomic(jsonb, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION create_delivery_note_atomic(jsonb, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION create_invoice_atomic(jsonb, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION create_purchase_invoice_atomic(jsonb, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION create_quote_atomic(jsonb, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION create_sales_order_atomic(jsonb, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION create_delivery_note_atomic(jsonb, jsonb) TO authenticated;
