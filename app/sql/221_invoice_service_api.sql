-- ============================================================
-- 221_invoice_service_api.sql — R-12 : une facture créée par l'API a des lignes
--
-- Constat, vérifié dans le code : `public-api` (POST /v1/invoices) insérait
-- l'EN-TÊTE SEUL. Depuis la 190, une facture sans ligne n'est **ni validable ni
-- approuvable** (« Facture sans ligne : rien à valider ») : tout ce qu'une
-- intégration créait par l'API était donc une pièce inutilisable, et l'appelant
-- ne l'apprenait qu'en essayant de la valider dans l'interface.
--
-- Vérification de la seconde moitié du constat : `ocr-invoice-import` ne crée
-- AUCUNE facture — elle renvoie les données extraites (dont `items`) et
-- n'enregistre rien. Il n'y avait donc rien à corriger de ce côté ; la
-- documentation du contrat suffit.
--
-- Pourquoi une fonction dédiée plutôt que les RPC existantes : l'API publique
-- s'authentifie par clé (service_role), donc `current_tenant_id()` y vaut NULL
-- et `create_invoice_atomic` (147, réécrite par la 184) lève « Aucun tenant
-- actif ». La société est donc passée explicitement, et la fonction n'est
-- ouverte qu'à `service_role` — un jeton utilisateur ne peut pas l'appeler pour
-- une autre société que la sienne.
--
-- Deux garanties que l'API n'avait pas :
--   1. au moins une ligne est exigée — sinon refus explicite, aucune pièce
--      laissée derrière ;
--   2. les totaux sont recalculés DEPUIS les lignes par les triggers de la 190
--      (invoice_line_compute, invoice_guard) : un appelant ne peut pas annoncer
--      un total qui ne correspond pas à ses lignes.
--
-- Preuve : sql/221_invoice_api_tests.sql (V01 à V04), vu rouge avant.
-- ============================================================

CREATE OR REPLACE FUNCTION create_invoice_service(p_tenant uuid, p_invoice jsonb, p_lines jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id uuid;
  v_line jsonb;
  v_order int := 0;
  v_head record;
BEGIN
  IF p_tenant IS NULL OR NOT EXISTS (SELECT 1 FROM tenants WHERE id = p_tenant) THEN
    RAISE EXCEPTION 'Société inconnue' USING ERRCODE = 'no_data_found';
  END IF;

  -- 1. Une facture sans ligne n'est ni validable ni approuvable : on refuse à la
  --    porte plutôt que de laisser une pièce inutilisable.
  IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) = 0 THEN
    RAISE EXCEPTION 'Au moins une ligne est requise : une facture sans ligne n''est ni validable ni approuvable'
      USING ERRCODE = 'check_violation';
  END IF;

  -- En-tête : la société vient du paramètre, jamais de la charge utile
  v_id := insert_row_from_jsonb('invoices',
    (COALESCE(p_invoice, '{}'::jsonb) - 'lines' - 'invoice_lines')
      || jsonb_build_object('tenant_id', p_tenant));

  -- Lignes : montants calculés par le trigger invoice_line_compute (190)
  FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    PERFORM insert_row_from_jsonb('invoice_lines',
      (v_line - 'id' - 'created_at' - 'updated_at')
        || jsonb_build_object('invoice_id', v_id, 'tenant_id', p_tenant)
        || jsonb_build_object('line_order', COALESCE((v_line ->> 'line_order')::int, v_order)));
    v_order := v_order + 1;
  END LOOP;

  -- 2. Totaux recalculés depuis les lignes : le no-op déclenche invoice_guard,
  --    qui recalcule subtotal, vat_total, total et reste dû (190).
  UPDATE invoices SET updated_at = now() WHERE id = v_id;

  SELECT number, subtotal, vat_total, total, amount_due INTO v_head
  FROM invoices WHERE id = v_id;

  RETURN jsonb_build_object(
    'success', true,
    'invoice_id', v_id,
    'number', v_head.number,
    'subtotal', v_head.subtotal,
    'vat_total', v_head.vat_total,
    'total', v_head.total,
    'amount_due', v_head.amount_due,
    'lines', jsonb_array_length(p_lines));
END $$;
REVOKE ALL ON FUNCTION create_invoice_service(uuid, jsonb, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION create_invoice_service(uuid, jsonb, jsonb) TO service_role;

COMMENT ON FUNCTION create_invoice_service(uuid, jsonb, jsonb) IS
  'Création d''une facture de vente AVEC ses lignes, pour l''API publique '
  '(service_role). La société est explicite ; au moins une ligne est exigée et les '
  'totaux sont recalculés depuis les lignes (R-12, 221).';