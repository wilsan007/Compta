-- ============================================================
-- 107_fiscal_year_close.sql
-- ACC-05 : Clôture d'exercice, à-nouveaux, affectation du résultat
--
-- Implémente la procédure de clôture en cinq temps :
-- 1. Contrôles de cohérence
-- 2. Écritures de regroupement (classes 6/7 → 120/129)
-- 3. Calcul du résultat
-- 4. Écriture d'à-nouveaux (classes 1-5 → journal AN)
-- 5. Verrouillage + empreinte NF525
-- ============================================================

-- ============================================================
-- 1. close_fiscal_year — Clôture d'exercice
-- ============================================================
CREATE OR REPLACE FUNCTION close_fiscal_year(
  p_fiscal_year_id uuid,
  p_next_fiscal_year_id uuid DEFAULT NULL,
  p_carry_forward boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tenant_id uuid;
  v_fy RECORD;
  v_next_fy RECORD;
  v_entry_id uuid;
  v_number text;
  v_result numeric;
  v_result_account text;
  v_total_debit numeric;
  v_total_credit numeric;
  v_count int;
  v_open_periods int;
  v_draft_entries int;
  v_an_entry_id uuid;
  v_an_number text;
  v_log_id uuid;
  v_hash text;
BEGIN
  -- Récupérer l'exercice à clôturer
  SELECT * INTO v_fy FROM fiscal_years
  WHERE id = p_fiscal_year_id AND tenant_id = current_tenant_id();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Exercice introuvable ou accès interdit';
  END IF;

  v_tenant_id := v_fy.tenant_id;

  IF v_fy.status IN ('closed', 'locked') THEN
    RAISE EXCEPTION 'Exercice déjà clôturé';
  END IF;

  -- ── Étape 1 : Contrôles de cohérence ──
  -- Vérifier que la balance est équilibrée
  SELECT COALESCE(SUM(jl.debit), 0), COALESCE(SUM(jl.credit), 0)
  INTO v_total_debit, v_total_credit
  FROM journal_lines jl
  JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
  WHERE jl.tenant_id = v_tenant_id
    AND je.status = 'posted'
    AND je.date BETWEEN v_fy.start_date AND v_fy.end_date;

  IF abs(v_total_debit - v_total_credit) > 0.01 THEN
    RAISE EXCEPTION 'Balance déséquilibrée : débit % ≠ crédit %', v_total_debit, v_total_credit;
  END IF;

  -- Vérifier qu'aucune période n'est ouverte
  SELECT count(*) INTO v_open_periods
  FROM fiscal_periods
  WHERE fiscal_year_id = p_fiscal_year_id
    AND tenant_id = v_tenant_id
    AND status = 'open';

  IF v_open_periods > 0 THEN
    RAISE EXCEPTION '% période(s) encore ouverte(s) — clôture impossible', v_open_periods;
  END IF;

  -- Vérifier qu'il n'y a pas d'écritures en brouillon
  SELECT count(*) INTO v_draft_entries
  FROM journal_entries
  WHERE tenant_id = v_tenant_id
    AND date BETWEEN v_fy.start_date AND v_fy.end_date
    AND status = 'draft';

  IF v_draft_entries > 0 THEN
    RAISE EXCEPTION '% écriture(s) en brouillard — validation requise avant clôture', v_draft_entries;
  END IF;

  -- ── Étape 2 : Écritures de regroupement (classes 6/7 → 120/129) ──
  -- Calculer le résultat : produits (classe 7) - charges (classe 6)
  SELECT
    COALESCE(SUM(CASE
      WHEN COALESCE(jl.account_general, jl.account_code) ~ '^7' THEN jl.credit - jl.debit
      WHEN COALESCE(jl.account_general, jl.account_code) ~ '^6' THEN jl.debit - jl.credit
      ELSE 0
    END), 0)
  INTO v_result
  FROM journal_lines jl
  JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
  WHERE jl.tenant_id = v_tenant_id
    AND je.status = 'posted'
    AND je.date BETWEEN v_fy.start_date AND v_fy.end_date
    AND (COALESCE(jl.account_general, jl.account_code) ~ '^6'
      OR COALESCE(jl.account_general, jl.account_code) ~ '^7');

  -- Compte de résultat : 120 (bénéfice) ou 129 (perte)
  v_result_account := CASE WHEN v_result >= 0 THEN '120000' ELSE '129000' END;

  v_number := 'CLOTURE-' || to_char(v_fy.end_date, 'YYYYMMDD');

  -- Écriture de regroupement
  INSERT INTO journal_entries (
    tenant_id, number, date, journal_code, status,
    description, fiscal_period_id, reference
  ) VALUES (
    v_tenant_id, v_number, v_fy.end_date, 'OD', 'draft',
    'Clôture de l''exercice ' || v_fy.code, NULL,
    'CLOTURE-' || v_fy.code
  )
  RETURNING id INTO v_entry_id;

  -- Insérer les lignes de regroupement par compte de classe 6 et 7
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_name, debit, credit, description, line_order)
  SELECT
    v_tenant_id, v_entry_id,
    COALESCE(jl.account_general, jl.account_code),
    COALESCE(jl.account_general, jl.account_code),
    MAX(jl.account_name),
    -- Solde le compte : crédit le solde débiteur, débit le solde créditeur
    GREATEST(0, SUM(jl.debit - jl.credit)),
    GREATEST(0, SUM(jl.credit - jl.debit)),
    'Regroupement ' || COALESCE(jl.account_general, jl.account_code),
    row_number() OVER (ORDER BY COALESCE(jl.account_general, jl.account_code))
  FROM journal_lines jl
  JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
  WHERE jl.tenant_id = v_tenant_id
    AND je.status = 'posted'
    AND je.date BETWEEN v_fy.start_date AND v_fy.end_date
    AND (COALESCE(jl.account_general, jl.account_code) ~ '^6'
      OR COALESCE(jl.account_general, jl.account_code) ~ '^7')
  GROUP BY COALESCE(jl.account_general, jl.account_code);

  -- Ligne de résultat (120 ou 129)
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_name, debit, credit, description, line_order)
  VALUES (
    v_tenant_id, v_entry_id,
    v_result_account, v_result_account,
    CASE WHEN v_result >= 0 THEN 'Résultat de l''exercice (bénéfice)' ELSE 'Résultat de l''exercice (perte)' END,
    CASE WHEN v_result < 0 THEN abs(v_result) ELSE 0 END,
    CASE WHEN v_result >= 0 THEN v_result ELSE 0 END,
    'Résultat ' || v_fy.code,
    9999
  );

  -- Bascule en posted APRÈS les lignes (SOC-01)
  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = v_tenant_id;

  -- ── Étape 3 : Calcul du résultat (déjà fait ci-dessus) ──

  -- ── Étape 4 : Écriture d'à-nouveaux (si exercice suivant fourni) ──
  IF p_carry_forward AND p_next_fiscal_year_id IS NOT NULL THEN
    SELECT * INTO v_next_fy FROM fiscal_years
    WHERE id = p_next_fiscal_year_id AND tenant_id = v_tenant_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Exercice suivant introuvable';
    END IF;

    v_an_number := 'AN-' || to_char(v_next_fy.start_date, 'YYYYMMDD');

    INSERT INTO journal_entries (
      tenant_id, number, date, journal_code, status,
      description, reference
    ) VALUES (
      v_tenant_id, v_an_number, v_next_fy.start_date, 'AN', 'draft',
      'À-nouveaux ' || v_next_fy.code,
      'AN-' || v_fy.code
    )
    RETURNING id INTO v_an_entry_id;

    -- Reporter les soldes des classes 1 à 5 (hors comptes de résultat 120/129)
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_name, debit, credit, description, line_order)
    SELECT
      v_tenant_id, v_an_entry_id,
      COALESCE(jl.account_general, jl.account_code),
      COALESCE(jl.account_general, jl.account_code),
      MAX(jl.account_name),
      GREATEST(0, SUM(jl.debit - jl.credit)),
      GREATEST(0, SUM(jl.credit - jl.debit)),
      'À-nouveaux ' || COALESCE(jl.account_general, jl.account_code),
      row_number() OVER (ORDER BY COALESCE(jl.account_general, jl.account_code))
    FROM journal_lines jl
    JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
    WHERE jl.tenant_id = v_tenant_id
      AND je.status = 'posted'
      AND je.date <= v_fy.end_date
      -- Classes 1 à 5 uniquement (bilan), exclure 6, 7 et le compte de résultat 120/129
      AND COALESCE(jl.account_general, jl.account_code) ~ '^[1-5]'
      AND COALESCE(jl.account_general, jl.account_code) NOT IN ('120000', '129000')
    GROUP BY COALESCE(jl.account_general, jl.account_code)
    HAVING SUM(jl.debit - jl.credit) <> 0 OR SUM(jl.credit - jl.debit) <> 0;

    -- Bascule en posted APRÈS les lignes (SOC-01)
    UPDATE journal_entries SET status = 'posted' WHERE id = v_an_entry_id AND tenant_id = v_tenant_id;
  END IF;

  -- ── Étape 5 : Verrouillage ──
  -- Calculer l'empreinte NF525 (simplifiée — hash des écritures de l'exercice)
  v_hash := md5(
    COALESCE((SELECT string_agg(
      je.id::text || je.number || je.date::text || je.status || COALESCE(jl.account_code, '') || jl.debit::text || jl.credit::text,
      '|' ORDER BY je.date, je.number, jl.line_order
    )
    FROM journal_entries je
    JOIN journal_lines jl ON jl.journal_id = je.id AND jl.tenant_id = je.tenant_id
    WHERE je.tenant_id = v_tenant_id
      AND je.status = 'posted'
      AND je.date BETWEEN v_fy.start_date AND v_fy.end_date
    ), '')
  );

  -- Verrouiller l'exercice
  UPDATE fiscal_years
  SET status = 'closed',
      closed_at = NOW(),
      closed_by = auth.uid()
  WHERE id = p_fiscal_year_id AND tenant_id = v_tenant_id;

  -- Tracer dans carry_forward_log
  INSERT INTO carry_forward_log (
    tenant_id, source_fiscal_year_id, target_fiscal_year_id,
    carry_forward_date, total_debit, total_credit, status, journal_entry_id
  ) VALUES (
    v_tenant_id, p_fiscal_year_id, p_next_fiscal_year_id,
    NOW(), v_result, 0, 'completed', v_entry_id
  )
  RETURNING id INTO v_log_id;

  RETURN jsonb_build_object(
    'success', true,
    'fiscal_year_id', p_fiscal_year_id,
    'result', v_result,
    'result_account', v_result_account,
    'carry_forward_entry_id', v_an_entry_id,
    'close_entry_id', v_entry_id,
    'hash', v_hash,
    'log_id', v_log_id
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$$;

-- ============================================================
-- 2. allocate_result — Affectation du résultat (N-1)
--    120 → 106 (réserves) / 457 (dividendes)
-- ============================================================
CREATE OR REPLACE FUNCTION allocate_result(
  p_fiscal_year_id uuid,
  p_reserves_amount numeric DEFAULT 0,
  p_dividends_amount numeric DEFAULT 0,
  p_description text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tenant_id uuid;
  v_fy RECORD;
  v_entry_id uuid;
  v_number text;
  v_total numeric;
  v_carry_amount numeric;
BEGIN
  SELECT * INTO v_fy FROM fiscal_years
  WHERE id = p_fiscal_year_id AND tenant_id = current_tenant_id();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Exercice introuvable';
  END IF;

  v_tenant_id := v_fy.tenant_id;
  v_total := p_reserves_amount + p_dividends_amount;

  IF v_total <= 0 THEN
    RAISE EXCEPTION 'Le montant total à affecter doit être positif';
  END IF;

  -- Récupérer le solde du compte 120/129
  SELECT COALESCE(SUM(jl.credit - jl.debit), 0)
  INTO v_carry_amount
  FROM journal_lines jl
  JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
  WHERE jl.tenant_id = v_tenant_id
    AND je.status = 'posted'
    AND je.date <= v_fy.end_date
    AND COALESCE(jl.account_general, jl.account_code) IN ('120000', '129000');

  IF abs(v_carry_amount - v_total) > 0.01 THEN
    RAISE EXCEPTION 'Le montant à affecter (%) ne correspond pas au solde du compte de résultat (%)', v_total, v_carry_amount;
  END IF;

  v_number := 'AFFECT-' || to_char(v_fy.end_date, 'YYYYMMDD');

  INSERT INTO journal_entries (
    tenant_id, number, date, journal_code, status,
    description, reference
  ) VALUES (
    v_tenant_id, v_number, v_fy.end_date + interval '1 day', 'OD', 'draft',
    COALESCE(p_description, 'Affectation du résultat ' || v_fy.code),
    'AFFECT-' || v_fy.code
  )
  RETURNING id INTO v_entry_id;

  -- Débiter le compte 120 (ou 129 si perte)
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_name, debit, credit, description, line_order)
  VALUES
    (v_tenant_id, v_entry_id, '120000', '120000', 'Résultat de l''exercice', v_total, 0, 'Solde du résultat', 0);

  -- Créditer les réserves (106) et les dividendes (457)
  IF p_reserves_amount > 0 THEN
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_name, debit, credit, description, line_order)
    VALUES (v_tenant_id, v_entry_id, '106000', '106000', 'Réserves', 0, p_reserves_amount, 'Affectation aux réserves', 1);
  END IF;

  IF p_dividends_amount > 0 THEN
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_name, debit, credit, description, line_order)
    VALUES (v_tenant_id, v_entry_id, '457000', '457000', 'Dividendes à payer', 0, p_dividends_amount, 'Dividendes distribués', 2);
  END IF;

  -- Bascule en posted APRÈS les lignes (SOC-01)
  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = v_tenant_id;

  RETURN jsonb_build_object(
    'success', true,
    'entry_id', v_entry_id,
    'reserves', p_reserves_amount,
    'dividends', p_dividends_amount
  );
END;
$$;

-- ============================================================
-- 3. get_balance_sheet_structured — Bilan structuré en rubriques
--    avec colonnes brut / amortissements / net
-- ============================================================
CREATE OR REPLACE FUNCTION get_balance_sheet_structured(
  p_fiscal_year_id uuid,
  p_date_to date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_tenant_id uuid := current_tenant_id();
  v_end_date date;
  v_assets jsonb;
  v_liabilities jsonb;
  v_equity jsonb;
  v_amortissements jsonb;
BEGIN
  SELECT end_date INTO v_end_date FROM fiscal_years
  WHERE id = p_fiscal_year_id AND tenant_id = v_tenant_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Exercice introuvable');
  END IF;

  v_end_date := LEAST(v_end_date, COALESCE(p_date_to, v_end_date));

  -- Actif brut (comptes commençant par 2, 3, 4 débit, 5 débit)
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'account_code', code, 'account_name', name,
    'brut', brut, 'amortissements', amort, 'net', brut - amort
  )), '[]'::jsonb) INTO v_assets
  FROM (
    SELECT
      COALESCE(jl.account_general, jl.account_code) AS code,
      MAX(jl.account_name) AS name,
      SUM(jl.debit) AS brut,
      -- Amortissements : comptes 28 et 29 (crédit = dépréciation)
      COALESCE((
        SELECT SUM(jl2.credit - jl2.debit)
        FROM journal_lines jl2
        JOIN journal_entries je2 ON je2.id = jl2.journal_id AND je2.tenant_id = jl2.tenant_id
        WHERE jl2.tenant_id = v_tenant_id
          AND je2.status = 'posted'
          AND je2.date <= v_end_date
          AND COALESCE(jl2.account_general, jl2.account_code) ~ '^2[89]'
          AND substr(COALESCE(jl2.account_general, jl2.account_code), 2, 2) = substr(COALESCE(jl.account_general, jl.account_code), 2, 2)
      ), 0) AS amort
    FROM journal_lines jl
    JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
    WHERE jl.tenant_id = v_tenant_id
      AND je.status = 'posted'
      AND je.date <= v_end_date
      AND (COALESCE(jl.account_general, jl.account_code) ~ '^2[0-4]'
        OR COALESCE(jl.account_general, jl.account_code) ~ '^3'
        OR COALESCE(jl.account_general, jl.account_code) ~ '^4[0-9][0-9][0-9]')  -- 40, 41, 42, 43, 44, 45, 46, 47, 48
      AND COALESCE(jl.account_general, jl.account_code) !~ '^2[89]'
    GROUP BY COALESCE(jl.account_general, jl.account_code)
    HAVING SUM(jl.debit) > 0
  ) actif;

  -- Passif (comptes 1, 4 crédit, 5 crédit)
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'account_code', code, 'account_name', name, 'amount', amount
  )), '[]'::jsonb) INTO v_liabilities
  FROM (
    SELECT
      COALESCE(jl.account_general, jl.account_code) AS code,
      MAX(jl.account_name) AS name,
      SUM(jl.credit - jl.debit) AS amount
    FROM journal_lines jl
    JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
    WHERE jl.tenant_id = v_tenant_id
      AND je.status = 'posted'
      AND je.date <= v_end_date
      AND (COALESCE(jl.account_general, jl.account_code) ~ '^1'
        OR COALESCE(jl.account_general, jl.account_code) ~ '^4[0-9][0-9][0-9]'
        OR COALESCE(jl.account_general, jl.account_code) ~ '^5')
    GROUP BY COALESCE(jl.account_general, jl.account_code)
    HAVING SUM(jl.credit - jl.debit) > 0
  ) passif;

  -- Capitaux propres (classe 1)
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'account_code', code, 'account_name', name, 'amount', amount
  )), '[]'::jsonb) INTO v_equity
  FROM (
    SELECT
      COALESCE(jl.account_general, jl.account_code) AS code,
      MAX(jl.account_name) AS name,
      SUM(jl.credit - jl.debit) AS amount
    FROM journal_lines jl
    JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
    WHERE jl.tenant_id = v_tenant_id
      AND je.status = 'posted'
      AND je.date <= v_end_date
      AND COALESCE(jl.account_general, jl.account_code) ~ '^1'
    GROUP BY COALESCE(jl.account_general, jl.account_code)
    HAVING SUM(jl.credit - jl.debit) <> 0
  ) capitaux;

  RETURN jsonb_build_object(
    'assets', v_assets,
    'liabilities', v_liabilities,
    'equity', v_equity,
    'date', v_end_date
  );
END;
$$;
