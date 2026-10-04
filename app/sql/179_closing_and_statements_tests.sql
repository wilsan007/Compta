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
DECLARE t uuid := _mk_tenant('D01', false); fy uuid; fy2 uuid; r jsonb; an_d numeric; an_c numeric; an_120 numeric; s67 numeric; st text;
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
DECLARE t uuid := _mk_tenant('D06', false); fy uuid; fy2 uuid; fy3 uuid; r1 jsonb; r2 jsonb; an_512 numeric;
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
DECLARE t uuid := _mk_tenant('D07', false); fy uuid; fy2 uuid; r jsonb;
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

-- D08 — états d'un exercice clos et de l'exercice suivant, sans double comptage
DO $$
DECLARE t uuid := _mk_tenant('D08', false); fy uuid; fy2 uuid; r jsonb;
  is_rev numeric; is_exp numeric; bs_all numeric; bs_512 numeric; bs_res numeric; tb_d numeric; tb_c numeric; tb_512 numeric;
BEGIN
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status) VALUES (t, '2025', '2025-01-01', '2025-12-31', 'open') RETURNING id INTO fy;
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status) VALUES (t, '2026', '2026-01-01', '2026-12-31', 'open') RETURNING id INTO fy2;
  PERFORM _as_user();
  PERFORM _entry(t, 'CAP', DATE '2025-01-02', '[{"a":"512000","d":10000},{"a":"101000","c":10000}]');
  PERFORM _entry(t, 'VTE', DATE '2025-05-10', '[{"a":"411000","d":1000,"t":"C001"},{"a":"706000","c":1000}]', true, 'VT');
  PERFORM _entry(t, 'ACH', DATE '2025-06-10', '[{"a":"601000","d":600},{"a":"401000","c":600,"t":"F001"}]', true, 'AC');
  r := close_fiscal_year(fy, fy2, true);

  SELECT COALESCE(sum(credit - debit) FILTER (WHERE account_code ~ '^7'), 0), COALESCE(sum(debit - credit) FILTER (WHERE account_code ~ '^6'), 0)
    INTO is_rev, is_exp FROM get_income_statement(fy, NULL, NULL);
  SELECT COALESCE(sum(balance), 0), COALESCE(sum(balance) FILTER (WHERE account_code = '512000'), 0),
         COALESCE(sum(balance) FILTER (WHERE account_code IN ('120000', '129000')), 0)
    INTO bs_all, bs_512, bs_res FROM get_balance_sheet(fy2, NULL);
  SELECT sum(closing_debit), sum(closing_credit), COALESCE(sum(closing_debit) FILTER (WHERE account_code = '512000'), 0)
    INTO tb_d, tb_c, tb_512 FROM get_trial_balance(fy2, NULL, NULL, NULL);
  PERFORM _rec('D08', 'exercice clos : compte de résultat intact ; N+1 : bilan et balance sans double comptage',
    COALESCE((r->>'success')::boolean, false) AND is_rev = 1000 AND is_exp = 600
      AND bs_all = 0 AND bs_512 = 10000 AND bs_res = -400 AND tb_d = tb_c AND tb_512 = 10000,
    format('clôture=%s | CR 2025 : produits=%s charges=%s | bilan 2026 : Σ=%s 512=%s résultat=%s | balance 2026 : D=%s C=%s 512=%s',
      COALESCE(r->>'error', r->>'success'), is_rev, is_exp, bs_all, bs_512, bs_res, tb_d, tb_c, tb_512));
END $$;

-- D09 — clôture refusée proprement sans exercice suivant, ou si l'antérieur est ouvert
DO $$
DECLARE t uuid := _mk_tenant('D09', false); fy1 uuid; fy2 uuid; r1 jsonb; r2 jsonb; st1 text; st2 text;
BEGIN
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status) VALUES (t, '2025', '2025-01-01', '2025-12-31', 'open') RETURNING id INTO fy1;
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status) VALUES (t, '2026', '2026-01-01', '2026-12-31', 'open') RETURNING id INTO fy2;
  PERFORM _as_user();
  PERFORM _entry(t, 'CAP', DATE '2025-01-02', '[{"a":"512000","d":100},{"a":"101000","c":100}]');
  r1 := close_fiscal_year(fy2, NULL, true);   -- 2025 encore ouvert, et pas de 2027
  r2 := close_fiscal_year(fy1, NULL, true);   -- l'exercice suivant est retrouvé par sa date
  SELECT status INTO st1 FROM fiscal_years WHERE id = fy1;
  SELECT status INTO st2 FROM fiscal_years WHERE id = fy2;
  PERFORM _rec('D09', 'clôture de 2026 refusée (2025 ouvert) ; 2025 clôturé vers 2026 retrouvé par sa date',
    NOT COALESCE((r1->>'success')::boolean, true) AND COALESCE(r1->>'error', '') ~ 'antérieur'
      AND COALESCE((r2->>'success')::boolean, false) AND st1 = 'closed' AND st2 = 'open',
    format('2026 : %s | 2025 : %s | statuts %s/%s', COALESCE(r1->>'error', r1->>'success'), COALESCE(r2->>'error', r2->>'success'), st1, st2));
END $$;

-- D10 — affectation du résultat obligatoire avant de clôturer l'exercice suivant (décision n° 3)
DO $$
DECLARE t uuid := _mk_tenant('D10', false); fy25 uuid; fy26 uuid; fy27 uuid;
  r_close25 jsonb; r_early jsonb; r_bad jsonb; r_ok jsonb; r_twice jsonb; r_close26 jsonb; s120 numeric; st26 text;
BEGIN
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status) VALUES (t, '2025', '2025-01-01', '2025-12-31', 'open') RETURNING id INTO fy25;
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status) VALUES (t, '2026', '2026-01-01', '2026-12-31', 'open') RETURNING id INTO fy26;
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status) VALUES (t, '2027', '2027-01-01', '2027-12-31', 'open') RETURNING id INTO fy27;
  PERFORM _as_user();
  PERFORM _entry(t, 'CAP', DATE '2025-01-02', '[{"a":"512000","d":10000},{"a":"101000","c":10000}]');
  PERFORM _entry(t, 'VTE', DATE '2025-05-10', '[{"a":"512000","d":1000},{"a":"706000","c":1000}]');
  PERFORM _entry(t, 'ACH', DATE '2025-06-10', '[{"a":"601000","d":600},{"a":"512000","c":600}]');
  r_close25 := close_fiscal_year(fy25, fy26, true);
  BEGIN
    r_early := close_fiscal_year(fy26, fy27, true);   -- résultat 2025 non affecté
    r_bad := allocate_result(fy25, '[{"account":"106100","amount":20},{"account":"110000","amount":300}]'::jsonb, NULL, NULL);  -- 320 ≠ 400
    r_ok := allocate_result(fy25, '[{"account":"106100","amount":20},{"account":"110000","amount":380}]'::jsonb, NULL, NULL);
    r_twice := allocate_result(fy25, '[{"account":"110000","amount":400}]'::jsonb, NULL, NULL);
    SELECT COALESCE(sum(jl.debit - jl.credit), 0) INTO s120
    FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id
    WHERE je.tenant_id = t AND je.status = 'posted' AND je.date >= '2026-01-01' AND jl.account_code = '120000';
    r_close26 := close_fiscal_year(fy26, fy27, true);
    SELECT status INTO st26 FROM fiscal_years WHERE id = fy26;
    PERFORM _rec('D10', 'clôture 2026 refusée tant que le résultat 2025 n''est pas affecté ; affectation exacte, une seule fois',
      COALESCE((r_close25->>'success')::boolean, false)
        AND NOT COALESCE((r_early->>'success')::boolean, true) AND COALESCE(r_early->>'error', '') ~ 'Affectez'
        AND NOT COALESCE((r_bad->>'success')::boolean, true)
        AND COALESCE((r_ok->>'success')::boolean, false)
        AND NOT COALESCE((r_twice->>'success')::boolean, true)
        AND s120 = 0 AND COALESCE((r_close26->>'success')::boolean, false) AND st26 = 'closed',
      format('clôture 2025=%s | 2026 avant affectation=%s | affectation 320=%s | affectation 400=%s | 2e affectation=%s | 120 en 2026=%s | clôture 2026=%s',
        r_close25->>'success', COALESCE(r_early->>'error', r_early->>'success'), COALESCE(r_bad->>'error', r_bad->>'success'),
        COALESCE(r_ok->>'error', r_ok->>'success'), COALESCE(r_twice->>'error', r_twice->>'success'), s120,
        COALESCE(r_close26->>'error', r_close26->>'success')));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('D10', 'clôture 2026 refusée tant que le résultat 2025 n''est pas affecté ; affectation exacte, une seule fois', false, SQLERRM);
  END;
END $$;

-- D11 — une perte s'affecte au débit (report à nouveau débiteur 119), le 129 est soldé
DO $$
DECLARE t uuid := _mk_tenant('D11', false); fy25 uuid; fy26 uuid; r_close jsonb; r_div jsonb; r_ok jsonb; s129 numeric; s119 numeric;
BEGIN
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status) VALUES (t, '2025', '2025-01-01', '2025-12-31', 'open') RETURNING id INTO fy25;
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status) VALUES (t, '2026', '2026-01-01', '2026-12-31', 'open') RETURNING id INTO fy26;
  PERFORM _as_user();
  PERFORM _entry(t, 'CAP', DATE '2025-01-02', '[{"a":"512000","d":10000},{"a":"101000","c":10000}]');
  PERFORM _entry(t, 'ACH', DATE '2025-06-10', '[{"a":"601000","d":250},{"a":"512000","c":250}]');
  r_close := close_fiscal_year(fy25, fy26, true);
  BEGIN
    r_div := allocate_result(fy25, '[{"account":"457000","amount":250}]'::jsonb, NULL, NULL);   -- pas de dividende sur une perte
    r_ok := allocate_result(fy25, '[{"account":"119000","amount":250}]'::jsonb, NULL, NULL);
    SELECT COALESCE(sum(jl.debit - jl.credit) FILTER (WHERE jl.account_code = '129000'), 0),
           COALESCE(sum(jl.debit - jl.credit) FILTER (WHERE jl.account_code = '119000'), 0)
      INTO s129, s119
    FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id
    WHERE je.tenant_id = t AND je.status = 'posted' AND je.date >= '2026-01-01';
    PERFORM _rec('D11', 'perte 250 : dividende refusé, affectée en 119 (débit), 129 soldé',
      COALESCE((r_close->>'success')::boolean, false) AND (r_close->>'result')::numeric = -250
        AND NOT COALESCE((r_div->>'success')::boolean, true) AND COALESCE((r_ok->>'success')::boolean, false)
        AND s129 = 0 AND s119 = 250,
      format('clôture=%s résultat=%s | dividende=%s | affectation=%s | 129=%s 119=%s', r_close->>'success', r_close->>'result',
        COALESCE(r_div->>'error', r_div->>'success'), COALESCE(r_ok->>'error', r_ok->>'success'), s129, s119));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('D11', 'perte 250 : dividende refusé, affectée en 119 (débit), 129 soldé', false, SQLERRM);
  END;
END $$;

-- R01 à R04 — états financiers d'un exercice ouvert
DO $$
DECLARE t uuid := _mk_tenant('R01', false); fy uuid; c uuid; inv uuid;
  tb_d numeric; tb_c numeric; tb_n int; is_rev numeric; is_exp numeric;
  bs_a numeric; bs_all numeric; bs_codes text;
BEGIN
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status) VALUES (t, '2026', '2026-01-01', '2026-12-31', 'open') RETURNING id INTO fy;
  PERFORM _as_user();
  -- plan saisi avec les types que la base accepte
  INSERT INTO chart_accounts (tenant_id, code, name, type) VALUES
    (t, '101000', 'Capital', 'equity'), (t, '512000', 'Banque', 'asset'), (t, '411000', 'Clients', 'asset'),
    (t, '401000', 'Fournisseurs', 'liability'), (t, '445710', 'TVA collectée', 'liability'),
    (t, '601000', 'Achats', 'expense'), (t, '706000', 'Prestations', 'income'), (t, '707000', 'Ventes', 'income')
  ON CONFLICT (tenant_id, code) DO NOTHING;
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

-- R08 — un compte absent du plan (donnée historique antérieure à la 187) n'est pas
-- écarté du bilan : il sort en « unclassified » et le bilan reste équilibré (AUD-D08 a)
DO $$
DECLARE t uuid := _mk_tenant('R08'); fy uuid; e uuid; n int; bs_all numeric; typ text;
BEGIN
  SELECT id INTO fy FROM fiscal_years WHERE tenant_id = t;
  -- Écriture historique, antérieure à la 187 : posée triggers neutralisés (mode
  -- réplication), comme une reprise de données. Ne dépend d'aucun trigger nommé :
  -- les contrôles ajoutés depuis (à la saisie ou à la validation) n'y changent rien.
  PERFORM set_config('session_replication_role', 'replica', true);
  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, total_debit, total_credit)
  VALUES (t, 'HIST', DATE '2026-02-01', 'OD', 'posted', 'reprise historique', 300, 300) RETURNING id INTO e;
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description) VALUES
    (t, e, '512000', '512000', 300, 0, 'HIST'), (t, e, 'ZZ9999', 'ZZ9999', 0, 300, 'HIST');
  PERFORM set_config('session_replication_role', 'origin', true);
  PERFORM _as_user();
  SELECT count(*) FILTER (WHERE account_code = 'ZZ9999'), COALESCE(sum(balance), 0),
         max(account_type) FILTER (WHERE account_code = 'ZZ9999')
    INTO n, bs_all, typ FROM get_balance_sheet(fy, NULL);
  PERFORM _rec('R08', 'compte hors plan présent au bilan (non classé), bilan équilibré',
    n = 1 AND typ = 'unclassified' AND bs_all = 0, format('ZZ9999 lignes=%s type=%s Σ=%s', n, COALESCE(typ, '∅'), bs_all));
END $$;

SELECT _audit_assert('179');
