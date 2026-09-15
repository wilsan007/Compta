-- ============================================================
-- 155_fix_post_journal_entry_missing_fields.sql
--
-- ACC-01.7 : post_journal_entry (migration 76) n'insérait que les colonnes
-- tenant_id, journal_id, account_code, account_general, debit, credit,
-- description, line_order. Depuis que le frontend a été branché sur ce RPC
-- (au lieu d'un insert JS direct qui transmettait l'objet ligne complet),
-- les champs suivants étaient silencieusement perdus :
--   account_name, account_tiers, third_party_id, lettrage_code,
--   lettrage_date, piece_number, reference, analytic_section_id,
--   analytic_amount, line_date, vat_code, vat_amount, echeance_date,
--   quantity, marking_code, tax_tag_ids, analytic_distribution,
--   product_id, product_uom.
-- Cela cassait le lettrage, le suivi tiers, l'analytique et la TVA sur
-- les écritures créées via créateJournalEntry/import Sage/transfert gescom.
-- ============================================================

CREATE OR REPLACE FUNCTION post_journal_entry(p_entry jsonb, p_lines jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_entry_id uuid;
  v_number text;
  v_journal_code text;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  v_journal_code := p_entry ->> 'journal_code';

  -- Numérotation atomique si pas de numéro fourni
  IF p_entry ->> 'number' IS NULL OR p_entry ->> 'number' = '' THEN
    v_number := get_next_piece_number(v_journal_code);
  ELSE
    v_number := p_entry ->> 'number';
  END IF;

  -- 1. Insérer l'entête
  INSERT INTO journal_entries (
    tenant_id, number, date, journal_code, status,
    description, invoice_ref, piece_number
  ) VALUES (
    v_tid,
    v_number,
    (p_entry ->> 'date')::date,
    v_journal_code,
    COALESCE(p_entry ->> 'status', 'draft'),
    p_entry ->> 'description',
    p_entry ->> 'invoice_ref',
    v_number
  )
  RETURNING id INTO v_entry_id;

  -- 2. Insérer toutes les lignes en un seul INSERT (le trigger statement-level
  --    check_journal_entry_balance_ins se déclenche une seule fois après
  --    l'insertion de toutes les lignes, ce qui permet la vérification
  --    d'équilibre sur l'écriture complète).
  INSERT INTO journal_lines (
    tenant_id, journal_id, account_code, account_name, account_general,
    account_tiers, third_party_id, debit, credit, description, line_order,
    lettrage_code, lettrage_date, piece_number, reference,
    analytic_section_id, analytic_amount, analytic_distribution,
    line_date, vat_code, vat_amount, echeance_date, quantity,
    marking_code, tax_tag_ids, product_id, product_uom
  )
  SELECT
    v_tid,
    v_entry_id,
    l ->> 'account_code',
    l ->> 'account_name',
    l ->> 'account_general',
    l ->> 'account_tiers',
    NULLIF(l ->> 'third_party_id', '')::uuid,
    COALESCE((l ->> 'debit')::numeric, 0),
    COALESCE((l ->> 'credit')::numeric, 0),
    l ->> 'description',
    COALESCE((l ->> 'line_order')::integer, 0),
    l ->> 'lettrage_code',
    NULLIF(l ->> 'lettrage_date', '')::date,
    COALESCE(l ->> 'piece_number', v_number),
    l ->> 'reference',
    NULLIF(l ->> 'analytic_section_id', '')::uuid,
    NULLIF(l ->> 'analytic_amount', '')::numeric,
    l -> 'analytic_distribution',
    COALESCE(NULLIF(l ->> 'line_date', '')::date, (p_entry ->> 'date')::date),
    l ->> 'vat_code',
    COALESCE((l ->> 'vat_amount')::numeric, 0),
    NULLIF(l ->> 'echeance_date', '')::date,
    NULLIF(l ->> 'quantity', '')::numeric,
    l ->> 'marking_code',
    CASE WHEN l ? 'tax_tag_ids' THEN
      ARRAY(SELECT jsonb_array_elements_text(l -> 'tax_tag_ids'))
    ELSE '{}'::text[] END,
    NULLIF(l ->> 'product_id', '')::uuid,
    l ->> 'product_uom'
  FROM jsonb_array_elements(p_lines) AS t(l);

  -- ACC-02: Valider qu'au moins une ligne non-nulle existe
  IF jsonb_array_length(p_lines) = 0 THEN
    RAISE EXCEPTION 'Écriture vide: aucune ligne fournie';
  END IF;

  -- Le trigger check_journal_entry_balance vérifie l'équilibre automatiquement

  RETURN jsonb_build_object('success', true, 'entry_id', v_entry_id, 'number', v_number);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION post_journal_entry(jsonb, jsonb) TO authenticated;
