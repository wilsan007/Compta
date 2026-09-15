-- ============================================================
-- 77_financial_aggregations_and_pagination.sql
--
-- ACC-02: Agrégations SQL pour rapports financiers + pagination
--   - Vue balance_sheet (bilan agrégé)
--   - Vue trial_balance (balance générale)
--   - Vue general_ledger (grand livre agrégé)
--   - Vue vat_summary (récapitulatif TVA)
--   - Fonction fec_export (export FEC paginé)
--   - Compteur exact pour pagination
-- ============================================================

-- ============================================
-- ACC-02.1: Vue balance_sheet (bilan agrégé)
-- SEC-04: security_invoker pour respecter RLS
-- ============================================
CREATE OR REPLACE VIEW balance_sheet WITH (security_invoker = true) AS
SELECT
  je.tenant_id,
  je.date,
  ja.code,
  ja.name,
  ja.type,
  COALESCE(SUM(jl.debit), 0) AS total_debit,
  COALESCE(SUM(jl.credit), 0) AS total_credit,
  COALESCE(SUM(jl.debit), 0) - COALESCE(SUM(jl.credit), 0) AS solde
FROM journal_entries je
JOIN journal_lines jl ON jl.journal_id = je.id AND jl.tenant_id = je.tenant_id
JOIN chart_accounts ja ON ja.code = jl.account_code AND ja.tenant_id = je.tenant_id
WHERE je.status IN ('posted', 'draft')
GROUP BY je.tenant_id, je.date, ja.code, ja.name, ja.type;

-- ============================================
-- ACC-02.2: Vue trial_balance (balance générale)
-- SEC-04: security_invoker pour respecter RLS
-- ============================================
CREATE OR REPLACE VIEW trial_balance WITH (security_invoker = true) AS
SELECT
  je.tenant_id,
  ja.code,
  ja.name,
  ja.type,
  COALESCE(SUM(jl.debit), 0) AS total_debit,
  COALESCE(SUM(jl.credit), 0) AS total_credit,
  COALESCE(SUM(jl.debit), 0) - COALESCE(SUM(jl.credit), 0) AS solde_debit,
  COALESCE(SUM(jl.credit), 0) - COALESCE(SUM(jl.debit), 0) AS solde_credit
FROM journal_entries je
JOIN journal_lines jl ON jl.journal_id = je.id AND jl.tenant_id = je.tenant_id
JOIN chart_accounts ja ON ja.code = jl.account_code AND ja.tenant_id = je.tenant_id
WHERE je.status IN ('posted', 'draft')
GROUP BY je.tenant_id, ja.code, ja.name, ja.type;

-- ============================================
-- ACC-02.3: Vue general_ledger (grand livre agrégé)
-- SEC-04: security_invoker pour respecter RLS
-- ============================================
CREATE OR REPLACE VIEW general_ledger WITH (security_invoker = true) AS
SELECT
  je.tenant_id,
  je.id AS entry_id,
  je.number AS entry_number,
  je.date,
  je.journal_code,
  je.status,
  je.description,
  jl.account_code,
  jl.description AS line_description,
  jl.debit,
  jl.credit,
  jl.line_order
FROM journal_entries je
JOIN journal_lines jl ON jl.journal_id = je.id AND jl.tenant_id = je.tenant_id
WHERE je.status IN ('posted', 'draft');

-- ============================================
-- ACC-02.4: Vue vat_summary (récapitulatif TVA)
-- SEC-04: security_invoker pour respecter RLS
-- ============================================
CREATE OR REPLACE VIEW vat_summary WITH (security_invoker = true) AS
SELECT
  i.tenant_id,
  i.id AS invoice_id,
  i.number AS invoice_number,
  i.date,
  il.vat_rate,
  SUM(il.quantity * il.unit_price) AS ht_amount,
  SUM(il.quantity * il.unit_price * (il.vat_rate / 100)) AS vat_amount,
  SUM(il.quantity * il.unit_price * (1 + il.vat_rate / 100)) AS ttc_amount
FROM invoices i
JOIN invoice_lines il ON il.invoice_id = i.id AND il.tenant_id = i.tenant_id
WHERE i.status != 'cancelled'
GROUP BY i.tenant_id, i.id, i.number, i.date, il.vat_rate;

-- ============================================
-- ACC-02.5: Fonction fec_export (export FEC paginé)
-- SEC-04: Dériver tenant du contexte, ne pas truster p_tenant_id
-- ============================================
CREATE OR REPLACE FUNCTION fec_export(p_start_date date, p_end_date date, p_offset integer DEFAULT 0, p_limit integer DEFAULT 1000)
RETURNS TABLE (
  journal_code text,
  entry_number text,
  entry_date date,
  account_code text,
  account_label text,
  description text,
  debit numeric,
  credit numeric,
  piece_number text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  RETURN QUERY
  SELECT
    je.journal_code::text,
    je.number::text,
    je.date,
    jl.account_code::text,
    COALESCE(ja.name, '')::text,
    COALESCE(jl.description, '')::text,
    jl.debit,
    jl.credit,
    COALESCE(je.piece_number, je.number)::text
  FROM journal_entries je
  JOIN journal_lines jl ON jl.journal_id = je.id AND jl.tenant_id = je.tenant_id
  LEFT JOIN chart_accounts ja ON ja.code = jl.account_code AND ja.tenant_id = je.tenant_id
  WHERE je.tenant_id = v_tid
    AND je.status = 'posted'
    AND je.date >= p_start_date
    AND je.date <= p_end_date
  ORDER BY je.date, je.journal_code, je.number, jl.line_order
  OFFSET p_offset
  LIMIT p_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION fec_export(date, date, integer, integer) TO authenticated;

-- ============================================
-- ACC-02.6: Fonction get_journal_entry_count
-- SEC-04: Dériver tenant du contexte, ne pas truster p_tenant_id
-- ============================================
CREATE OR REPLACE FUNCTION get_journal_entry_count(p_start_date date DEFAULT NULL, p_end_date date DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count integer;
  v_tid uuid := current_tenant_id();
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM journal_entries je
  WHERE je.tenant_id = v_tid
    AND je.status IN ('posted', 'draft')
    AND (p_start_date IS NULL OR je.date >= p_start_date)
    AND (p_end_date IS NULL OR je.date <= p_end_date);
  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION get_journal_entry_count(date, date) TO authenticated;
