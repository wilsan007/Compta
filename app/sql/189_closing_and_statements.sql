-- ============================================================
-- 189_closing_and_statements.sql — lot D du plan correctif du 21/09
-- (doc/audit/PLAN-CORRECTIF-AUDIT-2026-09-21.md, vague V2)
--
-- close_fiscal_year (153) est réécrite, pas rapiécée. Défauts prouvés par
-- sql/179_closing_and_statements_tests.sql :
--
--   AUD-D01  résultat = produits + charges (1 600 au lieu de 400) (D02, D07)
--   AUD-D02  regroupement dans le même sens que les soldes : D 600 ≠ C 2 600 (D03, D07)
--   AUD-D03  exigeait les périodes closes puis écrivait dans une période close (D01)
--   AUD-D04  résultat (120/129) exclu des à-nouveaux : à-nouveaux déséquilibrés (D04)
--   AUD-D05  à-nouveaux cumulés depuis l'origine : double comptage (D06, D08)
--   AUD-D06  clôture impossible à résultat nul (écriture sans ligne) (D06)
--   AUD-D07  surcharge close_fiscal_year(uuid) (89) : ne faisait que marquer l'exercice clos
--   AUD-D08  bilan : comptes hors plan écartés sans bruit, pas de ligne de résultat,
--            jamais équilibré (R04) ; balance et bilan de N+1 recomptaient N (D08)
--
-- Règle de périmètre commune (bilan, balance, à-nouveaux) : les écritures d'un
-- exercice dont les à-nouveaux ont été générés (carry_forward_log « completed »)
-- ne sont plus relues — ce sont ses à-nouveaux qui le représentent dans l'exercice
-- suivant. Un exercice antérieur non reporté est relu tel quel : rien ne se perd
-- et rien n'est compté deux fois.
--
-- Compte de résultat : les écritures du journal CL (regroupement des classes
-- 6 et 7 à la clôture) en sont exclues, sinon un exercice clos afficherait
-- produits et charges à zéro.
-- ============================================================

-- AUD-D07 : la surcharge à un argument marquait l'exercice clos sans écriture
DROP FUNCTION IF EXISTS close_fiscal_year(uuid);

-- ------------------------------------------------------------
-- Périmètre : exercices antérieurs déjà reportés par des à-nouveaux
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION carried_forward_ranges(p_tenant_id uuid, p_before date)
RETURNS TABLE (start_date date, end_date date)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  SELECT fy.start_date, fy.end_date
  FROM fiscal_years fy
  WHERE fy.tenant_id = p_tenant_id
    AND fy.end_date < p_before
    AND EXISTS (SELECT 1 FROM carry_forward_log l
                WHERE l.source_fiscal_year_id = fy.id AND l.status = 'completed'
                  AND l.journal_entry_id IS NOT NULL);
$$;

-- ------------------------------------------------------------
-- Affectation du résultat (décision n° 3 : écran d'affectation obligatoire)
--   L'exercice mémorise son résultat à la clôture ; l'affectation (réserves,
--   report à nouveau, dividendes) est une écriture distincte, passée dans
--   l'exercice suivant, et elle est exigée avant de clôturer cet exercice suivant.
-- ------------------------------------------------------------
ALTER TABLE fiscal_years ADD COLUMN IF NOT EXISTS closing_result numeric(18,2);
ALTER TABLE fiscal_years ADD COLUMN IF NOT EXISTS result_allocated_at timestamptz;
ALTER TABLE fiscal_years ADD COLUMN IF NOT EXISTS result_allocation_entry_id uuid REFERENCES journal_entries(id) ON DELETE RESTRICT;
COMMENT ON COLUMN fiscal_years.closing_result IS 'Résultat déterminé par close_fiscal_year (bénéfice > 0, perte < 0). NULL : exercice clos avant la 189.';
COMMENT ON COLUMN fiscal_years.result_allocated_at IS 'Date de l''affectation du résultat (allocate_result) ; exigée avant de clôturer l''exercice suivant.';

-- ------------------------------------------------------------
-- Clôture d'exercice
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS close_fiscal_year(uuid, uuid, boolean);
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
  v_tid uuid := current_tenant_id();
  v_fy fiscal_years%ROWTYPE;
  v_next fiscal_years%ROWTYPE;
  v_prev_open text;
  v_prev_unallocated text;
  v_drafts int;
  v_d numeric;
  v_c numeric;
  v_result numeric := 0;
  v_result_account text;
  v_cl_id uuid;
  v_an_id uuid;
  v_an_d numeric := 0;
  v_an_c numeric := 0;
  v_an_lines int := 0;
  v_hash text;
  v_log_id uuid;
  v_closed_by uuid;
BEGIN
  SELECT * INTO v_fy FROM fiscal_years WHERE id = p_fiscal_year_id AND tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Exercice introuvable ou accès interdit';
  END IF;
  IF v_fy.status IN ('closed', 'locked') THEN
    RAISE EXCEPTION 'Exercice % déjà clôturé', v_fy.code;
  END IF;

  -- ── 1. Contrôles ──
  SELECT string_agg(code, ', ' ORDER BY start_date) INTO v_prev_open
  FROM fiscal_years WHERE tenant_id = v_tid AND end_date < v_fy.start_date AND status = 'open';
  IF v_prev_open IS NOT NULL THEN
    RAISE EXCEPTION 'Clôturez d''abord l''exercice antérieur : %', v_prev_open;
  END IF;

  -- Décision n° 3 : le résultat d'un exercice clos est affecté avant de clôturer le suivant
  SELECT string_agg(code, ', ' ORDER BY start_date) INTO v_prev_unallocated
  FROM fiscal_years
  WHERE tenant_id = v_tid AND end_date < v_fy.start_date
    AND closing_result IS NOT NULL AND closing_result <> 0 AND result_allocated_at IS NULL;
  IF v_prev_unallocated IS NOT NULL THEN
    RAISE EXCEPTION 'Affectez d''abord le résultat de l''exercice % (réserves, report à nouveau, dividendes)', v_prev_unallocated;
  END IF;

  SELECT count(*) INTO v_drafts FROM journal_entries
  WHERE tenant_id = v_tid AND date BETWEEN v_fy.start_date AND v_fy.end_date AND status = 'draft';
  IF v_drafts > 0 THEN
    RAISE EXCEPTION '% écriture(s) en brouillard dans l''exercice % : à valider ou supprimer avant clôture', v_drafts, v_fy.code;
  END IF;

  IF p_carry_forward THEN
    IF p_next_fiscal_year_id IS NOT NULL THEN
      SELECT * INTO v_next FROM fiscal_years WHERE id = p_next_fiscal_year_id AND tenant_id = v_tid;
    ELSE
      SELECT * INTO v_next FROM fiscal_years WHERE tenant_id = v_tid AND start_date = v_fy.end_date + 1;
    END IF;
    IF v_next.id IS NULL THEN
      RAISE EXCEPTION 'Créez l''exercice suivant avant de clôturer % : il reçoit les à-nouveaux', v_fy.code;
    END IF;
    IF v_next.start_date <= v_fy.end_date THEN
      RAISE EXCEPTION 'L''exercice % ne suit pas l''exercice %', v_next.code, v_fy.code;
    END IF;
    IF v_next.status <> 'open' THEN
      RAISE EXCEPTION 'L''exercice % qui reçoit les à-nouveaux n''est pas ouvert', v_next.code;
    END IF;
  END IF;

  SELECT COALESCE(sum(jl.debit), 0), COALESCE(sum(jl.credit), 0) INTO v_d, v_c
  FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id
  WHERE je.tenant_id = v_tid AND je.status = 'posted'
    AND je.date BETWEEN v_fy.start_date AND v_fy.end_date;
  IF v_d <> v_c THEN
    RAISE EXCEPTION 'Balance de l''exercice % déséquilibrée : débit % ≠ crédit %', v_fy.code, v_d, v_c;
  END IF;

  PERFORM ensure_standard_journals(v_tid);

  -- ── 2. Écritures de clôture, sous le drapeau que journal_entry_guard reconnaît
  --       pour le seul journal CL de cet exercice (AUD-D03) ──
  PERFORM set_config('app.closing_in_progress', v_fy.id::text, true);

  -- AUD-D01 : résultat = Σ(crédit − débit) des classes 6 et 7, en un seul signe
  DROP TABLE IF EXISTS _cl_soldes;
  CREATE TEMP TABLE _cl_soldes ON COMMIT DROP AS
  SELECT COALESCE(jl.account_general, jl.account_code) AS account,
         max(jl.account_name) AS account_name,
         sum(jl.debit - jl.credit) AS solde
  FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id
  WHERE je.tenant_id = v_tid AND je.status = 'posted'
    AND je.date BETWEEN v_fy.start_date AND v_fy.end_date
    AND COALESCE(jl.account_general, jl.account_code) ~ '^[67]'
  GROUP BY 1
  HAVING sum(jl.debit - jl.credit) <> 0;

  SELECT COALESCE(-sum(solde), 0) INTO v_result FROM _cl_soldes;
  v_result_account := CASE WHEN v_result >= 0 THEN '120000' ELSE '129000' END;

  -- AUD-D06 : rien à solder → pas d'écriture de regroupement, la clôture continue
  IF EXISTS (SELECT 1 FROM _cl_soldes) THEN
    INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, reference)
    VALUES (v_tid, 'CL-' || v_fy.code, v_fy.end_date, 'CL', 'draft',
            'Clôture de l''exercice ' || v_fy.code, 'CLOTURE-' || v_fy.code)
    RETURNING id INTO v_cl_id;

    -- AUD-D02 : chaque compte est soldé en sens inverse de son solde
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_name,
                               debit, credit, description, line_order)
    SELECT v_tid, v_cl_id, account, account, account_name,
           GREATEST(-solde, 0), GREATEST(solde, 0),
           'Solde ' || account || ' — clôture ' || v_fy.code,
           row_number() OVER (ORDER BY account)::int
    FROM _cl_soldes;

    IF v_result <> 0 THEN
      INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_name,
                                 debit, credit, description, line_order)
      VALUES (v_tid, v_cl_id, v_result_account, v_result_account,
              CASE WHEN v_result > 0 THEN 'Résultat de l''exercice (bénéfice)' ELSE 'Résultat de l''exercice (perte)' END,
              GREATEST(-v_result, 0), GREATEST(v_result, 0),
              'Résultat ' || v_fy.code, 99999);
    END IF;

    UPDATE journal_entries SET status = 'posted' WHERE id = v_cl_id;
  END IF;

  -- ── 3. À-nouveaux (AUD-D04, D05) : tous les comptes hors classes 6 et 7, résultat
  --       compris, sur le périmètre de l'exercice (qui contient ses propres à-nouveaux
  --       d'ouverture ; les exercices antérieurs déjà reportés ne sont pas relus) ──
  IF p_carry_forward THEN
    DROP TABLE IF EXISTS _an_lignes;
    CREATE TEMP TABLE _an_lignes ON COMMIT DROP AS
    WITH perimetre AS (
      SELECT jl.*, COALESCE(jl.account_general, jl.account_code) AS account
      FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id
      WHERE je.tenant_id = v_tid AND je.status = 'posted' AND je.date <= v_fy.end_date
        AND NOT EXISTS (SELECT 1 FROM carried_forward_ranges(v_tid, v_fy.start_date) r
                        WHERE je.date BETWEEN r.start_date AND r.end_date)
        AND COALESCE(jl.account_general, jl.account_code) !~ '^[67]'
    ),
    -- Tiers non lettrés : reportés ligne à ligne pour rester lettrables
    detail AS (
      SELECT account, account_name, account_tiers, third_party_id, lettrage_code,
             reference, piece_number, debit - credit AS solde, 1 AS rang
      FROM perimetre
      WHERE account_tiers IS NOT NULL AND lettrage_code IS NULL AND debit <> credit
    ),
    groupe AS (
      SELECT account, max(account_name) AS account_name, NULL::text AS account_tiers,
             NULL::uuid AS third_party_id, NULL::text AS lettrage_code,
             NULL::text AS reference, NULL::text AS piece_number,
             sum(debit - credit) AS solde, 2 AS rang
      FROM perimetre
      WHERE NOT (account_tiers IS NOT NULL AND lettrage_code IS NULL AND debit <> credit)
      GROUP BY account
      HAVING sum(debit - credit) <> 0
    )
    SELECT * FROM detail UNION ALL SELECT * FROM groupe;

    SELECT count(*), COALESCE(sum(GREATEST(solde, 0)), 0), COALESCE(sum(GREATEST(-solde, 0)), 0)
      INTO v_an_lines, v_an_d, v_an_c FROM _an_lignes;

    IF v_an_lines > 0 THEN
      INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, reference)
      VALUES (v_tid, 'AN-' || v_next.code, v_next.start_date, 'AN', 'draft',
              'À-nouveaux ' || v_next.code || ' (clôture ' || v_fy.code || ')', 'AN-' || v_fy.code)
      RETURNING id INTO v_an_id;

      INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_name,
                                 account_tiers, third_party_id, lettrage_code, reference, piece_number,
                                 debit, credit, description, line_order)
      SELECT v_tid, v_an_id, account, account, account_name,
             account_tiers, third_party_id, lettrage_code, reference, piece_number,
             GREATEST(solde, 0), GREATEST(-solde, 0),
             'À-nouveau ' || account || COALESCE(' ' || account_tiers, ''),
             row_number() OVER (ORDER BY rang, account, account_tiers)::int
      FROM _an_lignes;

      UPDATE journal_entries SET status = 'posted' WHERE id = v_an_id;
    END IF;
  END IF;

  PERFORM set_config('app.closing_in_progress', '', true);

  -- ── 4. Verrouillage et empreinte ──
  v_hash := md5(COALESCE((
    SELECT string_agg(je.id::text || COALESCE(je.posting_number, je.number) || je.date::text
                      || jl.account_code || jl.debit::text || jl.credit::text,
                      '|' ORDER BY je.date, je.journal_code, je.posting_seq, jl.line_order, jl.id)
    FROM journal_entries je JOIN journal_lines jl ON jl.journal_id = je.id
    WHERE je.tenant_id = v_tid AND je.status = 'posted'
      AND je.date BETWEEN v_fy.start_date AND v_fy.end_date), ''));

  SELECT id INTO v_closed_by FROM users WHERE auth_id = auth.uid() LIMIT 1;

  UPDATE fiscal_periods SET status = 'closed'
  WHERE tenant_id = v_tid AND fiscal_year_id = v_fy.id AND status = 'open';
  UPDATE fiscal_years SET status = 'closed', closed_at = now(), closed_by = v_closed_by,
         closing_result = v_result
  WHERE id = v_fy.id;

  IF v_an_id IS NOT NULL THEN
    INSERT INTO carry_forward_log (tenant_id, source_fiscal_year_id, target_fiscal_year_id,
                                   carry_forward_date, total_debit, total_credit, entry_count,
                                   status, journal_entry_id)
    VALUES (v_tid, v_fy.id, v_next.id, v_next.start_date, v_an_d, v_an_c, v_an_lines, 'completed', v_an_id)
    RETURNING id INTO v_log_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'fiscal_year_id', v_fy.id,
    'result', v_result,
    'result_account', v_result_account,
    'close_entry_id', v_cl_id,
    'carry_forward_entry_id', v_an_id,
    'carry_forward_lines', v_an_lines,
    'carry_forward_total', v_an_d,
    'next_fiscal_year_id', v_next.id,
    'hash', v_hash,
    'log_id', v_log_id
  );
EXCEPTION WHEN OTHERS THEN
  -- Toute la clôture est annulée : pas d'état partiel (D05)
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END $$;

REVOKE ALL ON FUNCTION close_fiscal_year(uuid, uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION close_fiscal_year(uuid, uuid, boolean) TO authenticated, service_role;

-- ------------------------------------------------------------
-- Bilan (AUD-D08)
--   a) aucun compte écarté : un compte absent du plan sort en « unclassified » ;
--   b) tant que les classes 6/7 ne sont pas soldées, une ligne RESULTAT porte le
--      résultat en cours : Σ des soldes = 0, actif = passif + capitaux propres + résultat ;
--   c) périmètre commun : un exercice reporté n'est pas recompté.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_balance_sheet(p_fiscal_year_id uuid, p_date_to date DEFAULT NULL)
RETURNS TABLE(account_code text, account_name text, account_type text, debit numeric, credit numeric, balance numeric)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH bornes AS (
    SELECT tenant_id, start_date, LEAST(end_date, COALESCE(p_date_to, end_date)) AS date_to
    FROM fiscal_years
    WHERE id = p_fiscal_year_id AND tenant_id = current_tenant_id()
  ),
  -- Écritures d'abord (index par société et date), lignes ensuite par journal_id :
  -- le plan ne dépend pas de l'estimation du nombre de lignes de la société
  ecritures AS MATERIALIZED (
    SELECT je.id
    FROM journal_entries je CROSS JOIN bornes b
    WHERE je.tenant_id = b.tenant_id AND je.status = 'posted' AND je.date <= b.date_to
      AND NOT EXISTS (SELECT 1 FROM carried_forward_ranges(b.tenant_id, b.start_date) r
                      WHERE je.date BETWEEN r.start_date AND r.end_date)
  ),
  perimetre AS (
    SELECT COALESCE(jl.account_general, jl.account_code) AS code, jl.account_name, jl.debit, jl.credit
    FROM ecritures e
    -- Lignes lues écriture par écriture (index journal_id) ; OFFSET 0 empêche le
    -- planificateur d'aplatir la sous-requête et de revenir à une boucle sur toute la société
    CROSS JOIN LATERAL (SELECT jl0.* FROM journal_lines jl0 WHERE jl0.journal_id = e.id OFFSET 0) jl
  ),
  comptes AS (
    SELECT p.code, max(p.account_name) AS account_name, sum(p.debit) AS debit, sum(p.credit) AS credit
    FROM perimetre p WHERE p.code !~ '^[67]'
    GROUP BY p.code
  ),
  resultat AS (
    SELECT sum(p.debit) AS debit, sum(p.credit) AS credit
    FROM perimetre p WHERE p.code ~ '^[67]'
  )
  SELECT c.code,
         COALESCE(ca.name, c.account_name, c.code),
         COALESCE(ca.type, 'unclassified'),
         c.debit, c.credit, c.debit - c.credit
  FROM comptes c
  LEFT JOIN chart_accounts ca ON ca.tenant_id = current_tenant_id() AND ca.code = c.code
  UNION ALL
  SELECT 'RESULTAT', 'Résultat de l''exercice (non clôturé)', 'equity',
         r.debit, r.credit, r.debit - r.credit
  FROM resultat r
  WHERE COALESCE(r.debit, 0) <> COALESCE(r.credit, 0)
  ORDER BY 1;
$$;

-- ------------------------------------------------------------
-- Balance générale : même périmètre ; à-nouveaux = antérieur non reporté
-- + écritures du journal AN datées du premier jour de l'exercice
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_trial_balance(p_fiscal_year_id uuid, p_date_from date DEFAULT NULL, p_date_to date DEFAULT NULL, p_journal_code text DEFAULT NULL)
RETURNS TABLE(account_code text, account_name text, opening_debit numeric, opening_credit numeric, period_debit numeric, period_credit numeric, closing_debit numeric, closing_credit numeric)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH bornes AS (
    SELECT tenant_id, start_date, end_date,
           GREATEST(start_date, COALESCE(p_date_from, start_date)) AS p_from,
           LEAST(end_date, COALESCE(p_date_to, end_date)) AS p_to
    FROM fiscal_years
    WHERE id = p_fiscal_year_id AND tenant_id = current_tenant_id()
  ),
  ecritures AS MATERIALIZED (
    SELECT je.id,
           (je.date < b.start_date OR (je.journal_code = 'AN' AND je.date = b.start_date)) AS ouverture,
           (je.date BETWEEN b.p_from AND b.p_to) AS dans_periode
    FROM journal_entries je CROSS JOIN bornes b
    WHERE je.tenant_id = b.tenant_id AND je.status = 'posted' AND je.date <= b.p_to
      AND (p_journal_code IS NULL OR je.journal_code = p_journal_code)
      AND NOT EXISTS (SELECT 1 FROM carried_forward_ranges(b.tenant_id, b.start_date) r
                      WHERE je.date BETWEEN r.start_date AND r.end_date)
  ),
  lignes AS (
    SELECT COALESCE(jl.account_general, jl.account_code) AS code, jl.account_name, jl.debit, jl.credit,
           e.ouverture, e.dans_periode
    FROM ecritures e
    -- Lignes lues écriture par écriture (index journal_id) ; OFFSET 0 empêche le
    -- planificateur d'aplatir la sous-requête et de revenir à une boucle sur toute la société
    CROSS JOIN LATERAL (SELECT jl0.* FROM journal_lines jl0 WHERE jl0.journal_id = e.id OFFSET 0) jl
  ),
  mouvements AS (
    SELECT code, max(account_name) AS account_name,
           sum(CASE WHEN ouverture THEN debit ELSE 0 END) AS o_d,
           sum(CASE WHEN ouverture THEN credit ELSE 0 END) AS o_c,
           sum(CASE WHEN NOT ouverture AND dans_periode THEN debit ELSE 0 END) AS p_d,
           sum(CASE WHEN NOT ouverture AND dans_periode THEN credit ELSE 0 END) AS p_c
    FROM lignes
    WHERE ouverture OR dans_periode
    GROUP BY code
  )
  SELECT m.code, COALESCE(ca.name, m.account_name, m.code),
         m.o_d, m.o_c, m.p_d, m.p_c,
         GREATEST(m.o_d + m.p_d - m.o_c - m.p_c, 0),
         GREATEST(m.o_c + m.p_c - m.o_d - m.p_d, 0)
  FROM mouvements m
  LEFT JOIN chart_accounts ca ON ca.tenant_id = current_tenant_id() AND ca.code = m.code
  ORDER BY m.code;
$$;

-- ------------------------------------------------------------
-- Compte de résultat : hors écritures de clôture (journal CL)
--   SECURITY DEFINER, comme le bilan et la balance : les écritures sont filtrées
--   explicitement sur current_tenant_id() et les lignes ne sont lues qu'à travers
--   elles. Sous RLS, le filtre société de journal_lines rendait l'index par
--   société éligible pour chaque écriture : 27 s par appel mesurées juste après
--   un chargement, statistiques pas encore à jour.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_income_statement(p_fiscal_year_id uuid, p_date_from date DEFAULT NULL, p_date_to date DEFAULT NULL)
RETURNS TABLE(account_code text, account_name text, account_type text, debit numeric, credit numeric, balance numeric)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH bornes AS (
    SELECT start_date, end_date FROM fiscal_years
    WHERE id = p_fiscal_year_id AND tenant_id = current_tenant_id()
  ),
  -- Écritures d'abord, lignes par journal_id : mesuré sur 40 000 écritures, 17,7 s
  -- (boucle imbriquée sur l'estimation « 1 ligne ») → 0,9 s
  ecritures AS MATERIALIZED (
    SELECT je.id
    FROM journal_entries je CROSS JOIN bornes b
    WHERE je.tenant_id = current_tenant_id()
      AND je.status = 'posted'
      AND je.journal_code <> 'CL'
      AND je.date >= GREATEST(b.start_date, COALESCE(p_date_from, b.start_date))
      AND je.date <= LEAST(b.end_date, COALESCE(p_date_to, b.end_date))
  ),
  mouvements AS (
    SELECT
      COALESCE(jl.account_general, jl.account_code) AS code,
      max(jl.account_name) AS line_name,
      SUM(jl.debit) AS debit,
      SUM(jl.credit) AS credit
    FROM ecritures e
    -- Lignes lues écriture par écriture (index journal_id) ; OFFSET 0 empêche le
    -- planificateur d'aplatir la sous-requête et de revenir à une boucle sur toute la société
    CROSS JOIN LATERAL (SELECT jl0.* FROM journal_lines jl0 WHERE jl0.journal_id = e.id OFFSET 0) jl
    WHERE COALESCE(jl.account_general, jl.account_code) ~ '^[67]'
    GROUP BY 1
  )
  SELECT
    m.code,
    COALESCE(ca.name, m.line_name, m.code),
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
LANGUAGE sql STABLE SECURITY DEFINER
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
  ecritures AS MATERIALIZED (
    SELECT je.id, je.date
    FROM journal_entries je CROSS JOIN bornes b
    WHERE je.tenant_id = current_tenant_id()
      AND je.status = 'posted'
      AND je.journal_code <> 'CL'
      AND je.date BETWEEN b.start_date AND b.end_date
  ),
  mouvements AS (
    SELECT
      date_trunc('month', e.date)::date AS month,
      SUM(CASE WHEN COALESCE(jl.account_general, jl.account_code) ~ '^7' THEN jl.credit - jl.debit ELSE 0 END) AS revenue,
      SUM(CASE WHEN COALESCE(jl.account_general, jl.account_code) ~ '^6' THEN jl.debit - jl.credit ELSE 0 END) AS expense
    FROM ecritures e
    -- Lignes lues écriture par écriture (index journal_id) ; OFFSET 0 empêche le
    -- planificateur d'aplatir la sous-requête et de revenir à une boucle sur toute la société
    CROSS JOIN LATERAL (SELECT jl0.* FROM journal_lines jl0 WHERE jl0.journal_id = e.id OFFSET 0) jl
    WHERE COALESCE(jl.account_general, jl.account_code) ~ '^[67]'
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

-- ------------------------------------------------------------
-- Compte imputable (187) : pendant la clôture, un compte fermé ou devenu compte de
-- regroupement qui porte encore un solde doit pouvoir être soldé et reporté.
-- L'existence au plan reste exigée.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION journal_line_account_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_code text;
  v_acc record;
  v_closing boolean := COALESCE(current_setting('app.closing_in_progress', true), '') <> '';
BEGIN
  -- AUD-C03 : une ligne sans montant n'a aucune valeur comptable : elle n'est pas enregistrée.
  IF TG_OP = 'INSERT' AND NEW.debit = 0 AND NEW.credit = 0 THEN
    RETURN NULL;
  END IF;
  FOREACH v_code IN ARRAY ARRAY[NEW.account_code, NULLIF(NEW.account_general, NEW.account_code)] LOOP
    CONTINUE WHEN v_code IS NULL;
    SELECT id, deprecated INTO v_acc FROM chart_accounts
    WHERE tenant_id = NEW.tenant_id AND code = v_code;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Compte % absent du plan comptable de la société', v_code
        USING ERRCODE = 'foreign_key_violation';
    END IF;
    CONTINUE WHEN v_closing;
    IF v_acc.deprecated THEN
      RAISE EXCEPTION 'Compte % fermé (déprécié) : imputation interdite', v_code
        USING ERRCODE = 'check_violation';
    END IF;
    IF EXISTS (SELECT 1 FROM chart_accounts WHERE parent_id = v_acc.id) THEN
      RAISE EXCEPTION 'Compte % : compte de regroupement, imputer un de ses sous-comptes', v_code
        USING ERRCODE = 'check_violation';
    END IF;
  END LOOP;
  RETURN NEW;
END $$;

-- ------------------------------------------------------------
-- Validation des écritures en temps constant (test de propriété, 21/09)
--   log_nf525_event lit le dernier maillon de la chaîne par
--   « WHERE tenant_id = … ORDER BY id DESC LIMIT 1 » : sans index sur
--   (tenant_id, id), chaque validation relisait une part croissante du
--   journal NF525. Mesuré sur base neuve : 30 000 validations en 50,6 s
--   (45 s dans log_nf525_event), 100 000 en 18 min ; 6,8 s avec l'index.
-- ------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_nf525_tenant_id_desc ON nf525_event_log (tenant_id, id DESC);

-- ------------------------------------------------------------
-- allocate_result : écriture d'affectation du résultat d'un exercice clos
--   p_allocation : [{"account": "106100", "amount": 20}, {"account": "110000", "amount": 380}]
--   Bénéfice : D 120000 / C réserves (106…), report à nouveau (110…), dividendes (457…),
--              compte de l'exploitant (108…).
--   Perte    : C 129000 / D report à nouveau débiteur (119…), imputation sur réserves
--              (106…) ou sur report créditeur (110…), compte de l'exploitant (108…).
--   La somme est égale au résultat au centime ; une seule affectation par exercice ;
--   l'écriture est datée dans l'exercice suivant (par défaut son premier jour).
-- Remplace allocate_result(uuid, numeric, numeric, text), qui débitait toujours 120000
-- (même pour une perte) et n'était appelée par aucun écran.
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS allocate_result(uuid, numeric, numeric, text);

CREATE OR REPLACE FUNCTION allocate_result(
  p_fiscal_year_id uuid,
  p_allocation jsonb,
  p_date date DEFAULT NULL,
  p_description text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_fy fiscal_years%ROWTYPE;
  v_next fiscal_years%ROWTYPE;
  v_date date;
  v_profit boolean;
  v_total numeric(18,2);
  v_sum numeric(18,2);
  v_bad text;
  v_result_account text;
  v_entry_id uuid;
BEGIN
  SELECT * INTO v_fy FROM fiscal_years WHERE id = p_fiscal_year_id AND tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Exercice introuvable ou accès interdit';
  END IF;
  IF v_fy.status NOT IN ('closed', 'locked') OR v_fy.closing_result IS NULL THEN
    RAISE EXCEPTION 'L''exercice % n''est pas clôturé : son résultat n''est pas encore déterminé', v_fy.code;
  END IF;
  IF v_fy.result_allocated_at IS NOT NULL THEN
    RAISE EXCEPTION 'Le résultat de l''exercice % est déjà affecté', v_fy.code;
  END IF;
  IF v_fy.closing_result = 0 THEN
    RAISE EXCEPTION 'Résultat nul : rien à affecter pour l''exercice %', v_fy.code;
  END IF;

  SELECT * INTO v_next FROM fiscal_years
  WHERE tenant_id = v_tid AND start_date = v_fy.end_date + 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'L''exercice qui suit % est introuvable : l''affectation y est passée', v_fy.code;
  END IF;
  v_date := COALESCE(p_date, v_next.start_date);
  IF v_date NOT BETWEEN v_next.start_date AND v_next.end_date THEN
    RAISE EXCEPTION 'La date d''affectation doit appartenir à l''exercice % (du % au %)',
      v_next.code, v_next.start_date, v_next.end_date;
  END IF;

  v_profit := v_fy.closing_result > 0;
  v_total := abs(v_fy.closing_result);
  v_result_account := CASE WHEN v_profit THEN '120000' ELSE '129000' END;

  IF jsonb_typeof(p_allocation) IS DISTINCT FROM 'array' OR jsonb_array_length(p_allocation) = 0 THEN
    RAISE EXCEPTION 'Répartition vide : indiquez au moins un compte et un montant';
  END IF;

  SELECT string_agg(COALESCE(x->>'account', '(vide)'), ', ') INTO v_bad
  FROM jsonb_array_elements(p_allocation) x
  WHERE COALESCE(x->>'account', '') !~ CASE WHEN v_profit THEN '^(106|108|110|457)' ELSE '^(106|108|110|119)' END
     OR COALESCE((x->>'amount')::numeric, 0) <= 0
     OR (x->>'amount')::numeric <> round((x->>'amount')::numeric, 2);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'Ligne(s) d''affectation invalide(s) : % — %', v_bad,
      CASE WHEN v_profit
        THEN 'un bénéfice s''affecte en réserves (106), report à nouveau (110), dividendes (457) ou compte de l''exploitant (108), montant positif au centime'
        ELSE 'une perte s''affecte en report à nouveau débiteur (119), sur les réserves (106), le report créditeur (110) ou le compte de l''exploitant (108), montant positif au centime' END;
  END IF;

  SELECT sum((x->>'amount')::numeric) INTO v_sum FROM jsonb_array_elements(p_allocation) x;
  IF v_sum <> v_total THEN
    RAISE EXCEPTION 'La répartition (%) doit être égale au résultat de l''exercice % (%)', v_sum, v_fy.code, v_total;
  END IF;

  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, reference)
  VALUES (v_tid, 'AFF-' || v_fy.code, v_date, 'OD', 'draft',
          COALESCE(NULLIF(p_description, ''), 'Affectation du résultat de l''exercice ' || v_fy.code),
          'AFFECTATION-' || v_fy.code)
  RETURNING id INTO v_entry_id;

  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
  VALUES (v_tid, v_entry_id, v_result_account, v_result_account,
          CASE WHEN v_profit THEN v_total ELSE 0 END, CASE WHEN v_profit THEN 0 ELSE v_total END,
          'Résultat ' || v_fy.code, 0);

  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
  SELECT v_tid, v_entry_id, x->>'account', x->>'account',
         CASE WHEN v_profit THEN 0 ELSE (x->>'amount')::numeric END,
         CASE WHEN v_profit THEN (x->>'amount')::numeric ELSE 0 END,
         'Affectation du résultat ' || v_fy.code, ord::int
  FROM jsonb_array_elements(p_allocation) WITH ORDINALITY AS a(x, ord);

  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id;

  UPDATE fiscal_years SET result_allocated_at = now(), result_allocation_entry_id = v_entry_id
  WHERE id = v_fy.id;

  RETURN jsonb_build_object('success', true, 'entry_id', v_entry_id, 'fiscal_year_id', v_fy.id,
                            'result', v_fy.closing_result, 'date', v_date);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END $$;

REVOKE ALL ON FUNCTION allocate_result(uuid, jsonb, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION allocate_result(uuid, jsonb, date, text) TO authenticated, service_role;
