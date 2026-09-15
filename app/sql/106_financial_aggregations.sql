-- ============================================================
-- 106_financial_aggregations.sql
-- SOC-04 : Agrégations financières côté serveur
--
-- Remplace les select(*) + Map JS par des RPC PostgreSQL paramétrés
-- par exercice fiscal. Évite la truncation silencieuse de PostgREST
-- et l'effondrement sur les gros dossiers.
-- ============================================================

-- ============================================================
-- Index de couverture indispensables
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_jl_tenant_account_journal
  ON journal_lines (tenant_id, account_general, journal_id)
  INCLUDE (debit, credit, account_code, account_name);

CREATE INDEX IF NOT EXISTS idx_je_tenant_date_status
  ON journal_entries (tenant_id, date, status)
  INCLUDE (journal_code);

CREATE INDEX IF NOT EXISTS idx_jl_tenant_journal_posted
  ON journal_lines (tenant_id, journal_id)
  INCLUDE (account_general, account_code, account_name, debit, credit);

-- ============================================================
-- 1. get_trial_balance — Balance générale par exercice
-- ============================================================
CREATE OR REPLACE FUNCTION get_trial_balance(
  p_fiscal_year_id uuid,
  p_date_from date DEFAULT NULL,
  p_date_to   date DEFAULT NULL,
  p_journal_code text DEFAULT NULL
)
RETURNS TABLE(
  account_code text,
  account_name text,
  opening_debit numeric,
  opening_credit numeric,
  period_debit numeric,
  period_credit numeric,
  closing_debit numeric,
  closing_credit numeric
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  WITH bornes AS (
    SELECT start_date, end_date FROM fiscal_years
    WHERE id = p_fiscal_year_id AND tenant_id = current_tenant_id()
  ),
  mouvements AS (
    SELECT
      COALESCE(jl.account_general, jl.account_code) AS code,
      jl.account_name,
      -- à-nouveaux : tout ce qui précède l'ouverture de l'exercice
      SUM(CASE WHEN je.date < b.start_date THEN jl.debit  ELSE 0 END) AS o_d,
      SUM(CASE WHEN je.date < b.start_date THEN jl.credit ELSE 0 END) AS o_c,
      -- mouvements de la période demandée, bornée par l'exercice
      SUM(CASE WHEN je.date >= GREATEST(b.start_date, COALESCE(p_date_from, b.start_date))
                AND je.date <= LEAST(b.end_date, COALESCE(p_date_to, b.end_date))
               THEN jl.debit ELSE 0 END) AS p_d,
      SUM(CASE WHEN je.date >= GREATEST(b.start_date, COALESCE(p_date_from, b.start_date))
                AND je.date <= LEAST(b.end_date, COALESCE(p_date_to, b.end_date))
               THEN jl.credit ELSE 0 END) AS p_c
    FROM journal_lines jl
    JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
    CROSS JOIN bornes b
    WHERE jl.tenant_id = current_tenant_id()
      AND je.status = 'posted'
      AND je.date <= b.end_date
      AND (p_journal_code IS NULL OR je.journal_code = p_journal_code)
    GROUP BY 1, 2
  )
  SELECT code AS account_code, account_name,
         o_d AS opening_debit, o_c AS opening_credit,
         p_d AS period_debit, p_c AS period_credit,
         GREATEST(o_d + p_d - o_c - p_c, 0) AS closing_debit,
         GREATEST(o_c + p_c - o_d - p_d, 0) AS closing_credit
  FROM mouvements
  ORDER BY code;
$$;

-- ============================================================
-- 2. get_general_ledger — Grand livre paginé par exercice
-- ============================================================
CREATE OR REPLACE FUNCTION get_general_ledger(
  p_fiscal_year_id uuid,
  p_account_code text DEFAULT NULL,
  p_date_from date DEFAULT NULL,
  p_date_to   date DEFAULT NULL,
  p_journal_code text DEFAULT NULL,
  p_limit int DEFAULT 1000,
  p_offset int DEFAULT 0
)
RETURNS TABLE(
  line_id uuid,
  entry_id uuid,
  entry_number text,
  entry_date date,
  entry_description text,
  entry_reference text,
  account_code text,
  account_name text,
  debit numeric,
  credit numeric,
  line_description text,
  line_order int,
  created_at timestamptz,
  total_count bigint
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  WITH bornes AS (
    SELECT start_date, end_date FROM fiscal_years
    WHERE id = p_fiscal_year_id AND tenant_id = current_tenant_id()
  ),
  filtered AS (
    SELECT
      jl.id AS line_id,
      je.id AS entry_id,
      je.number AS entry_number,
      je.date AS entry_date,
      je.description AS entry_description,
      je.reference AS entry_reference,
      COALESCE(jl.account_general, jl.account_code) AS account_code,
      jl.account_name,
      jl.debit,
      jl.credit,
      jl.description AS line_description,
      jl.line_order,
      jl.created_at
    FROM journal_lines jl
    JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
    CROSS JOIN bornes b
    WHERE jl.tenant_id = current_tenant_id()
      AND je.status = 'posted'
      AND je.date >= GREATEST(b.start_date, COALESCE(p_date_from, b.start_date))
      AND je.date <= LEAST(b.end_date, COALESCE(p_date_to, b.end_date))
      AND (p_account_code IS NULL OR COALESCE(jl.account_general, jl.account_code) = p_account_code)
      AND (p_journal_code IS NULL OR je.journal_code = p_journal_code)
  ),
  cnt AS (SELECT count(*) AS total_count FROM filtered)
  SELECT
    f.line_id, f.entry_id, f.entry_number, f.entry_date, f.entry_description,
    f.entry_reference, f.account_code, f.account_name, f.debit, f.credit,
    f.line_description, f.line_order, f.created_at,
    cnt.total_count
  FROM filtered f
  CROSS JOIN cnt
  ORDER BY f.entry_date DESC, f.entry_number, f.line_order
  LIMIT GREATEST(1, LEAST(p_limit, 10000))
  OFFSET GREATEST(0, p_offset);
$$;

-- ============================================================
-- 3. get_balance_sheet — Bilan par exercice (comptes de classe 1-5)
-- ============================================================
CREATE OR REPLACE FUNCTION get_balance_sheet(
  p_fiscal_year_id uuid,
  p_date_to date DEFAULT NULL
)
RETURNS TABLE(
  account_code text,
  account_name text,
  account_type text,
  debit numeric,
  credit numeric,
  balance numeric
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  WITH bornes AS (
    SELECT start_date, end_date FROM fiscal_years
    WHERE id = p_fiscal_year_id AND tenant_id = current_tenant_id()
  ),
  mouvements AS (
    SELECT
      COALESCE(jl.account_general, jl.account_code) AS code,
      MAX(jl.account_name) AS account_name,
      ca.type AS account_type,
      SUM(jl.debit) AS debit,
      SUM(jl.credit) AS credit
    FROM journal_lines jl
    JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
    CROSS JOIN bornes b
    LEFT JOIN chart_accounts ca ON ca.code = COALESCE(jl.account_general, jl.account_code)
      AND ca.tenant_id = jl.tenant_id
    WHERE jl.tenant_id = current_tenant_id()
      AND je.status = 'posted'
      AND je.date <= LEAST(b.end_date, COALESCE(p_date_to, b.end_date))
      -- Bilan : classes 1 à 5 (capitaux, immobilisations, stocks, tiers, financiers)
      AND ca.type IN ('asset', 'liability', 'equity')
    GROUP BY 1, ca.type
  )
  SELECT
    code AS account_code,
    account_name,
    COALESCE(account_type, 'unknown') AS account_type,
    debit,
    credit,
    debit - credit AS balance
  FROM mouvements
  ORDER BY code;
$$;

-- ============================================================
-- 4. get_income_statement — Compte de résultat par exercice (classes 6-7)
-- ============================================================
CREATE OR REPLACE FUNCTION get_income_statement(
  p_fiscal_year_id uuid,
  p_date_from date DEFAULT NULL,
  p_date_to   date DEFAULT NULL
)
RETURNS TABLE(
  account_code text,
  account_name text,
  account_type text,
  debit numeric,
  credit numeric,
  balance numeric
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  WITH bornes AS (
    SELECT start_date, end_date FROM fiscal_years
    WHERE id = p_fiscal_year_id AND tenant_id = current_tenant_id()
  ),
  mouvements AS (
    SELECT
      COALESCE(jl.account_general, jl.account_code) AS code,
      MAX(jl.account_name) AS account_name,
      ca.type AS account_type,
      SUM(jl.debit) AS debit,
      SUM(jl.credit) AS credit
    FROM journal_lines jl
    JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
    CROSS JOIN bornes b
    LEFT JOIN chart_accounts ca ON ca.code = COALESCE(jl.account_general, jl.account_code)
      AND ca.tenant_id = jl.tenant_id
    WHERE jl.tenant_id = current_tenant_id()
      AND je.status = 'posted'
      AND je.date >= GREATEST(b.start_date, COALESCE(p_date_from, b.start_date))
      AND je.date <= LEAST(b.end_date, COALESCE(p_date_to, b.end_date))
      -- Compte de résultat : classes 6 et 7 (charges, produits)
      AND ca.type IN ('expense', 'revenue')
    GROUP BY 1, ca.type
  )
  SELECT
    code AS account_code,
    account_name,
    COALESCE(account_type, 'unknown') AS account_type,
    debit,
    credit,
    debit - credit AS balance
  FROM mouvements
  ORDER BY code;
$$;

-- ============================================================
-- 5. get_fiscal_years — Liste des exercices du tenant courant
--    (utilitaire pour que le frontend choisisse l'exercice)
-- ============================================================
CREATE OR REPLACE FUNCTION get_fiscal_years()
RETURNS TABLE(
  id uuid,
  name text,
  start_date date,
  end_date date,
  status text,
  is_closed boolean
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT id, code AS name, start_date, end_date, status,
    (status IN ('closed', 'locked')) AS is_closed
  FROM fiscal_years
  WHERE tenant_id = current_tenant_id()
  ORDER BY start_date DESC;
$$;
