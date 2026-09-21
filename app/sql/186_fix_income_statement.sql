-- ============================================================
-- 186_fix_income_statement.sql — AUD-D07 du plan correctif du 21/09
--
-- 1. get_income_statement filtrait `chart_accounts.type IN ('expense','revenue')`.
--    La contrainte de chart_accounts n'admet que 'income' : aucun produit ne
--    pouvait apparaître. Mesuré : bénéfice de 400 affiché comme perte de 600.
--    Les comptes absents du plan étaient en outre écartés sans bruit.
-- 2. generate_profit_loss (écran SIG) filtrait sur journal_entries.fiscal_period_id,
--    que rien ne renseigne : résultat toujours vide. Il comptait aussi les brouillards.
-- 3. Nouvelle get_income_statement_monthly pour la tendance de l'écran des états
--    financiers, qui affichait jusqu'ici des chiffres écrits en dur.
--
-- Règle commune : exercice borné par ses dates, écritures validées seulement,
-- classes 6 et 7 par préfixe du compte (le rôle de compte par pack viendra avec
-- `resolve_account`, lot K), plan comptable consulté pour le libellé uniquement.
--
-- Preuve : sql/179_closing_and_statements_tests.sql (R02, R05, R06).
-- ============================================================

CREATE OR REPLACE FUNCTION get_income_statement(p_fiscal_year_id uuid, p_date_from date DEFAULT NULL, p_date_to date DEFAULT NULL)
RETURNS TABLE(account_code text, account_name text, account_type text, debit numeric, credit numeric, balance numeric)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  WITH bornes AS (
    SELECT start_date, end_date FROM fiscal_years
    WHERE id = p_fiscal_year_id AND tenant_id = current_tenant_id()
  ),
  mouvements AS (
    SELECT
      COALESCE(jl.account_general, jl.account_code) AS code,
      SUM(jl.debit) AS debit,
      SUM(jl.credit) AS credit
    FROM journal_lines jl
    JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
    CROSS JOIN bornes b
    WHERE jl.tenant_id = current_tenant_id()
      AND je.status = 'posted'
      AND je.date >= GREATEST(b.start_date, COALESCE(p_date_from, b.start_date))
      AND je.date <= LEAST(b.end_date, COALESCE(p_date_to, b.end_date))
      AND COALESCE(jl.account_general, jl.account_code) ~ '^[67]'
    GROUP BY 1
  )
  SELECT
    m.code,
    COALESCE(ca.name, (SELECT max(jl.account_name) FROM journal_lines jl
                        WHERE jl.tenant_id = current_tenant_id() AND COALESCE(jl.account_general, jl.account_code) = m.code),
             m.code),
    CASE WHEN m.code ~ '^7' THEN 'income' ELSE 'expense' END,
    m.debit,
    m.credit,
    m.debit - m.credit
  FROM mouvements m
  LEFT JOIN chart_accounts ca ON ca.code = m.code AND ca.tenant_id = current_tenant_id()
  ORDER BY m.code;
$$;

CREATE OR REPLACE FUNCTION get_income_statement_monthly(p_fiscal_year_id uuid)
RETURNS TABLE(month date, revenue numeric, expense numeric, result numeric)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  WITH bornes AS (
    SELECT start_date, end_date FROM fiscal_years
    WHERE id = p_fiscal_year_id AND tenant_id = current_tenant_id()
  ),
  mois AS (
    SELECT generate_series(date_trunc('month', b.start_date), date_trunc('month', b.end_date), interval '1 month')::date AS month
    FROM bornes b
  ),
  mouvements AS (
    SELECT
      date_trunc('month', je.date)::date AS month,
      SUM(CASE WHEN COALESCE(jl.account_general, jl.account_code) ~ '^7' THEN jl.credit - jl.debit ELSE 0 END) AS revenue,
      SUM(CASE WHEN COALESCE(jl.account_general, jl.account_code) ~ '^6' THEN jl.debit - jl.credit ELSE 0 END) AS expense
    FROM journal_lines jl
    JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
    CROSS JOIN bornes b
    WHERE jl.tenant_id = current_tenant_id()
      AND je.status = 'posted'
      AND je.date BETWEEN b.start_date AND b.end_date
      AND COALESCE(jl.account_general, jl.account_code) ~ '^[67]'
    GROUP BY 1
  )
  SELECT mo.month,
         COALESCE(mv.revenue, 0),
         COALESCE(mv.expense, 0),
         COALESCE(mv.revenue, 0) - COALESCE(mv.expense, 0)
  FROM mois mo
  LEFT JOIN mouvements mv ON mv.month = mo.month
  ORDER BY mo.month;
$$;

CREATE OR REPLACE FUNCTION generate_profit_loss(p_fiscal_year_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_revenues jsonb;
  v_expenses jsonb;
  v_total_revenue numeric := 0;
  v_total_expense numeric := 0;
BEGIN
  SELECT
    COALESCE(jsonb_agg(jsonb_build_object('account_code', account_code, 'account_name', account_name, 'amount', -balance)
      ORDER BY account_code) FILTER (WHERE account_type = 'income'), '[]'::jsonb),
    COALESCE(jsonb_agg(jsonb_build_object('account_code', account_code, 'account_name', account_name, 'amount', balance)
      ORDER BY account_code) FILTER (WHERE account_type = 'expense'), '[]'::jsonb),
    COALESCE(SUM(-balance) FILTER (WHERE account_type = 'income'), 0),
    COALESCE(SUM(balance) FILTER (WHERE account_type = 'expense'), 0)
  INTO v_revenues, v_expenses, v_total_revenue, v_total_expense
  FROM get_income_statement(p_fiscal_year_id, NULL, NULL);

  RETURN jsonb_build_object(
    'revenues', v_revenues, 'expenses', v_expenses,
    'total_revenue', round(v_total_revenue, 2),
    'total_expense', round(v_total_expense, 2),
    'result', round(v_total_revenue - v_total_expense, 2)
  );
END;
$$;

REVOKE ALL ON FUNCTION get_income_statement(uuid, date, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION get_income_statement_monthly(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION generate_profit_loss(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_income_statement(uuid, date, date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION get_income_statement_monthly(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION generate_profit_loss(uuid) TO authenticated, service_role;
