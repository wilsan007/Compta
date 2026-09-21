-- ============================================================
-- 179_closing_and_statements_tests.sql — AUD-A01, lot D du plan correctif
--
-- Clôture d'exercice (RPC appelée par FiscalYearClosurePage) et états
-- financiers (balance, compte de résultat, bilan), sur des chiffres connus :
--   capital 10 000 (512/101), vente 1 000 (411/706), achat 600 (601/401)
--   → bénéfice attendu 400.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '179', false);
DELETE FROM _audit_results WHERE file = '179';

-- D01 à D05 — clôture d'un exercice découpé en périodes, bénéfice 400
DO $$
DECLARE t uuid := _mk_tenant('D01'); fy uuid; fy2 uuid; r jsonb; an_d numeric; an_c numeric; an_120 numeric; s67 numeric; st text;
BEGIN
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status) VALUES (t, '2025', '2025-01-01', '2025-12-31', 'open') RETURNING id INTO fy;
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status) VALUES (t, '2026', '2026-01-01', '2026-12-31', 'open') RETURNING id INTO fy2;
  INSERT INTO fiscal_periods (tenant_id, fiscal_year_id, period_number, period_label, start_date, end_date, status)
    VALUES (t, fy, 1, '2025', '2025-01-01', '2025-12-31', 'open');
  PERFORM _as_user();
  PERFORM _entry(t, 'CAP', DATE '2025-01-02', '[{"a":"512000","d":10000},{"a":"101000","c":10000}]');
  PERFORM _entry(t, 'VTE', DATE '2025-05-10', '[{"a":"411000","d":1000,"t":"C001"},{"a":"706000","c":1000}]', true, 'VT');
  PERFORM _entry(t, 'ACH', DATE '2025-06-10', '[{"a":"601000","d":600},{"a":"401000","c":600,"t":"F001"}]', true, 'AC');
  UPDATE fiscal_periods SET status = 'closed' WHERE fiscal_year_id = fy;

  r := close_fiscal_year(fy, fy2, true);
  PERFORM _rec('D01', 'clôture d''un exercice à périodes closes aboutit', COALESCE((r->>'success')::boolean, false), r::text);
  PERFORM _rec('D02', 'résultat = produits − charges = 400', COALESCE((r->>'result')::numeric, -1) = 400, 'result=' || COALESCE(r->>'result', '∅'));

  SELECT COALESCE(sum(jl.debit - jl.credit), 0) INTO s67
  FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id
  WHERE jl.tenant_id = t AND je.status = 'posted' AND je.date <= '2025-12-31'
    AND COALESCE(jl.account_general, jl.account_code) ~ '^[67]';
  PERFORM _rec('D03', 'classes 6 et 7 soldées par la clôture', COALESCE((r->>'success')::boolean, false) AND s67 = 0, 'solde net 6+7 = ' || s67);

  SELECT COALESCE(sum(jl.debit), 0), COALESCE(sum(jl.credit), 0),
         COALESCE(sum(jl.credit - jl.debit) FILTER (WHERE COALESCE(jl.account_general, jl.account_code) IN ('120000', '129000')), 0)
    INTO an_d, an_c, an_120
  FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id
  WHERE jl.tenant_id = t AND je.status = 'posted' AND je.date = '2026-01-01';
  PERFORM _rec('D04', 'à-nouveaux 2026 équilibrés (11 000) et résultat 400 reporté',
    an_d = an_c AND an_d = 11000 AND an_120 = 400, format('AN D=%s C=%s résultat reporté=%s', an_d, an_c, an_120));

  SELECT status INTO st FROM fiscal_years WHERE id = fy;
  PERFORM _rec('D05', 'pas d''état partiel : exercice clos seulement si la clôture réussit',
    ((r->>'success')::boolean AND st = 'closed') OR (NOT (r->>'success')::boolean AND st = 'open'),
    format('success=%s statut=%s', r->>'success', st));
END $$;

-- D06 — deux clôtures successives, sans double comptage
DO $$
DECLARE t uuid := _mk_tenant('D06'); fy uuid; fy2 uuid; fy3 uuid; r1 jsonb; r2 jsonb; an_512 numeric;
BEGIN
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status) VALUES (t, '2024', '2024-01-01', '2024-12-31', 'open') RETURNING id INTO fy;
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status) VALUES (t, '2025', '2025-01-01', '2025-12-31', 'open') RETURNING id INTO fy2;
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status) VALUES (t, '2026', '2026-01-01', '2026-12-31', 'open') RETURNING id INTO fy3;
  PERFORM _as_user();
  PERFORM _entry(t, 'CAP', DATE '2024-01-02', '[{"a":"512000","d":5000},{"a":"101000","c":5000}]');
  r1 := close_fiscal_year(fy, fy2, true);
  r2 := close_fiscal_year(fy2, fy3, true);
  SELECT COALESCE(sum(jl.debit - jl.credit), 0) INTO an_512
  FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id
  WHERE jl.tenant_id = t AND je.status = 'posted' AND je.date = '2026-01-01' AND jl.account_code = '512000';
  PERFORM _rec('D06', 'deux clôtures successives : banque reportée une seule fois (5 000)',
    COALESCE((r1->>'success')::boolean, false) AND COALESCE((r2->>'success')::boolean, false) AND an_512 = 5000,
    format('r1=%s | r2=%s | 512 au 01/01/2026 = %s', COALESCE(r1->>'error', r1->>'success'), COALESCE(r2->>'error', r2->>'success'), an_512));
END $$;

-- D07 — clôture d'un exercice sans périodes, bénéfice 400
DO $$
DECLARE t uuid := _mk_tenant('D07'); fy uuid; fy2 uuid; r jsonb;
BEGIN
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status) VALUES (t, '2025', '2025-01-01', '2025-12-31', 'open') RETURNING id INTO fy;
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status) VALUES (t, '2026', '2026-01-01', '2026-12-31', 'open') RETURNING id INTO fy2;
  PERFORM _as_user();
  PERFORM _entry(t, 'CAP', DATE '2025-01-02', '[{"a":"512000","d":10000},{"a":"101000","c":10000}]');
  PERFORM _entry(t, 'VTE', DATE '2025-05-10', '[{"a":"411000","d":1000,"t":"C001"},{"a":"706000","c":1000}]', true, 'VT');
  PERFORM _entry(t, 'ACH', DATE '2025-06-10', '[{"a":"601000","d":600},{"a":"401000","c":600,"t":"F001"}]', true, 'AC');
  r := close_fiscal_year(fy, fy2, true);
  PERFORM _rec('D07', 'clôture sans périodes, bénéfice 400',
    COALESCE((r->>'success')::boolean, false) AND COALESCE((r->>'result')::numeric, -1) = 400, r::text);
END $$;

-- R01 à R04 — états financiers d'un exercice ouvert
DO $$
DECLARE t uuid := _mk_tenant('R01'); fy uuid; c uuid; inv uuid;
  tb_d numeric; tb_c numeric; tb_n int; is_rev numeric; is_exp numeric;
  bs_a numeric; bs_all numeric; bs_codes text;
BEGIN
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status) VALUES (t, '2026', '2026-01-01', '2026-12-31', 'open') RETURNING id INTO fy;
  PERFORM _as_user();
  -- plan saisi avec les types que la base accepte
  INSERT INTO chart_accounts (tenant_id, code, name, type) VALUES
    (t, '101000', 'Capital', 'equity'), (t, '512000', 'Banque', 'asset'), (t, '411000', 'Clients', 'asset'),
    (t, '401000', 'Fournisseurs', 'liability'), (t, '445710', 'TVA collectée', 'liability'),
    (t, '601000', 'Achats', 'expense'), (t, '706000', 'Prestations', 'income'), (t, '707000', 'Ventes', 'income');
  PERFORM _entry(t, 'CAP', DATE '2026-01-02', '[{"a":"512000","d":10000},{"a":"101000","c":10000}]');
  PERFORM _entry(t, 'ACH', DATE '2026-02-10', '[{"a":"601000","d":600},{"a":"401000","c":600}]', true, 'AC');
  -- vente par la vraie chaîne : facture validée → trigger comptable
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client R') RETURNING id INTO c;
  INSERT INTO invoices (tenant_id, number, customer_id, customer_name, date, due_date, status, subtotal, vat_total, total, amount_paid, amount_due)
  VALUES (t, 'F-R1', c, 'Client R', '2026-03-01', '2026-03-31', 'draft', 1000, 200, 1200, 0, 1200) RETURNING id INTO inv;
  INSERT INTO invoice_lines (tenant_id, invoice_id, description, quantity, unit_price, vat_rate, total, vat_code, vat_amount)
  VALUES (t, inv, 'X', 1, 1000, 20, 1000, 'FR20', 200);
  UPDATE invoices SET validation_status = 'validated' WHERE id = inv;

  SELECT sum(closing_debit), sum(closing_credit), count(*) INTO tb_d, tb_c, tb_n FROM get_trial_balance(fy, NULL, NULL, NULL);
  PERFORM _rec('R01', 'balance générale équilibrée, 7 comptes mouvementés', tb_d = tb_c AND tb_n = 7, format('D=%s C=%s comptes=%s', tb_d, tb_c, tb_n));

  SELECT COALESCE(sum(credit - debit) FILTER (WHERE account_code ~ '^7'), 0), COALESCE(sum(debit - credit) FILTER (WHERE account_code ~ '^6'), 0)
    INTO is_rev, is_exp FROM get_income_statement(fy, NULL, NULL);
  PERFORM _rec('R02', 'compte de résultat : produits 1 000, charges 600', is_rev = 1000 AND is_exp = 600,
    format('produits=%s charges=%s', is_rev, is_exp));

  SELECT COALESCE(sum(balance) FILTER (WHERE account_type = 'asset'), 0), COALESCE(sum(balance), 0), string_agg(account_code, ',' ORDER BY account_code)
    INTO bs_a, bs_all, bs_codes FROM get_balance_sheet(fy, NULL);
  PERFORM _rec('R03', 'bilan : actif 11 200 (512 + 411)', bs_a = 11200, format('actif=%s comptes=%s', bs_a, bs_codes));
  -- Actif = passif + capitaux propres + résultat ⇔ la somme des soldes de toutes les
  -- lignes du bilan est nulle (la ligne de résultat et les comptes hors plan comprises).
  PERFORM _rec('R04', 'bilan équilibré (résultat et comptes hors plan compris)', bs_all = 0,
    format('Σ soldes du bilan = %s (doit valoir 0) ; comptes=%s', bs_all, bs_codes));

  -- R05 — le compte de résultat de l'écran SIG (generate_profit_loss) donne le même résultat
  DECLARE pl jsonb; m_rev numeric; m_exp numeric; m_n int; BEGIN
    pl := generate_profit_loss(fy);
    PERFORM _rec('R05', 'generate_profit_loss : produits 1 000, charges 600, résultat 400',
      (pl->>'total_revenue')::numeric = 1000 AND (pl->>'total_expense')::numeric = 600 AND (pl->>'result')::numeric = 400,
      format('produits=%s charges=%s résultat=%s', pl->>'total_revenue', pl->>'total_expense', pl->>'result'));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('R05', 'generate_profit_loss : produits 1 000, charges 600, résultat 400', false, SQLERRM); END;

  -- R06 — la tendance mensuelle couvre les 12 mois et totalise comme le compte de résultat
  DECLARE m_rev numeric; m_exp numeric; m_n int; m_mar numeric; BEGIN
    SELECT sum(revenue), sum(expense), count(*), sum(revenue) FILTER (WHERE month = '2026-03-01')
      INTO m_rev, m_exp, m_n, m_mar FROM get_income_statement_monthly(fy);
    PERFORM _rec('R06', 'tendance mensuelle : 12 mois, 1 000 de produits (tous en mars), 600 de charges',
      m_n = 12 AND m_rev = 1000 AND m_exp = 600 AND m_mar = 1000,
      format('mois=%s produits=%s charges=%s dont mars=%s', m_n, m_rev, m_exp, m_mar));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('R06', 'tendance mensuelle : 12 mois, 1 000 de produits, 600 de charges', false, SQLERRM); END;

  -- R07 — une écriture en brouillard ne compte pas dans le résultat
  PERFORM _entry(t, 'BROUILLARD', DATE '2026-04-01', '[{"a":"411000","d":5000},{"a":"706000","c":5000}]', false);
  SELECT COALESCE(sum(credit - debit) FILTER (WHERE account_code ~ '^7'), 0) INTO is_rev FROM get_income_statement(fy, NULL, NULL);
  PERFORM _rec('R07', 'une écriture en brouillard n''entre pas dans le compte de résultat', is_rev = 1000,
    'produits après brouillard de 5 000 = ' || is_rev);
END $$;

SELECT _audit_assert('179');
