-- ============================================================
-- 189_accounting_property_tests.sql — test de propriété du lot D
-- (doc/audit/PLAN-CORRECTIF-AUDIT-2026-09-21.md, conditions 2 et 4 du barème)
--
-- 3 exercices (2023 à 2025, plus 2026 qui reçoit les à-nouveaux), 100 000
-- écritures équilibrées aléatoires (graine fixe : le jeu est reproductible),
-- comptes de toutes les classes, lignes de tiers non lettrées. Invariants :
--   P1  balance de chaque exercice : Σ débits = Σ crédits
--   P2  compte de résultat = Σ classe 7 − Σ classe 6, calculé indépendamment
--   P3  bilan : Σ des soldes = 0 (actif = passif + capitaux propres + résultat)
--   P4  après clôture : classes 6/7 à zéro, à-nouveaux = soldes de clôture compte par compte
--   P5  deux clôtures successives : à-nouveaux N+2 = cumul des soldes hors 6/7, sans double comptage
--   P6  chaque clôture en moins de 30 s
--   P7  numéros définitifs continus : pour chaque journal et exercice, 1..n sans trou
--
-- Nombre d'écritures : variable psql `n` (défaut 100000), p. ex. -v n=5000 en local.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '189', false);
DELETE FROM _audit_results WHERE file = '189';
\if :{?n}
\else
  \set n 100000
\endif
SELECT set_config('audit.n', :'n', false);

DO $$
DECLARE
  t uuid := _mk_tenant('PROP', false);
  n int := current_setting('audit.n')::int;
  fy23 uuid; fy24 uuid; fy25 uuid; fy26 uuid;
  accs text[];
  t0 timestamptz; d_post interval; d_c1 interval; d_c2 interval;
  r1 jsonb; r2 jsonb;
  v_bad int; v_d numeric; v_c numeric; v_is numeric; v_ref numeric; v_bs numeric; v_res numeric;
  v_det text;
BEGIN
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status) VALUES (t, '2023', '2023-01-01', '2023-12-31', 'open') RETURNING id INTO fy23;
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status) VALUES (t, '2024', '2024-01-01', '2024-12-31', 'open') RETURNING id INTO fy24;
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status) VALUES (t, '2025', '2025-01-01', '2025-12-31', 'open') RETURNING id INTO fy25;
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status) VALUES (t, '2026', '2026-01-01', '2026-12-31', 'open') RETURNING id INTO fy26;
  -- 2024 découpé en périodes mensuelles : la clôture doit aussi fonctionner ainsi
  INSERT INTO fiscal_periods (tenant_id, fiscal_year_id, period_number, period_label, start_date, end_date, status)
  SELECT t, fy24, m, '2024-' || lpad(m::text, 2, '0'), make_date(2024, m, 1),
         (make_date(2024, m, 1) + interval '1 month - 1 day')::date, 'open'
  FROM generate_series(1, 12) m;

  SELECT array_agg(code ORDER BY code) INTO accs FROM chart_accounts
  WHERE tenant_id = t AND code IN ('101000', '164000', '215400', '218300', '401000', '411000', '421000',
    '431000', '445660', '445710', '512000', '530000', '601000', '606000', '613000', '641000', '645000',
    '661000', '706000', '707000', '758000', '766000');
  IF array_length(accs, 1) < 15 THEN
    RAISE EXCEPTION 'Plan de test incomplet : %', accs;
  END IF;

  PERFORM setseed(0.4242);
  -- Écritures en brouillard, puis 2 lignes chacune, puis validation en une instruction
  CREATE TEMP TABLE _gen ON COMMIT DROP AS
  SELECT i,
         (DATE '2023-01-01' + floor(random() * 1095)::int) AS d,
         (ARRAY['OD', 'VT', 'AC', 'BQ'])[1 + floor(random() * 4)::int] AS j,
         accs[1 + floor(random() * array_length(accs, 1))::int] AS a_d,
         accs[1 + floor(random() * array_length(accs, 1))::int] AS a_c,
         round((0.01 + random() * 9999)::numeric, 2) AS amt
  FROM generate_series(1, n) i;
  UPDATE _gen SET d = LEAST(d, DATE '2025-12-31');

  ALTER TABLE _gen ADD COLUMN id uuid DEFAULT uuid_generate_v4();
  INSERT INTO journal_entries (id, tenant_id, number, date, journal_code, status, description)
  SELECT id, t, 'P' || i, d, j, 'draft', 'propriété ' || i FROM _gen;
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_tiers, debit, credit, description)
  SELECT t, id, a_d, a_d, CASE WHEN a_d IN ('401000', '411000') THEN 'T' || (i % 50) END, amt, 0, 'd'
  FROM _gen
  UNION ALL
  SELECT t, id, a_c, a_c, CASE WHEN a_c IN ('401000', '411000') THEN 'T' || (i % 50) END, 0, amt, 'c'
  FROM _gen;

  t0 := clock_timestamp();
  UPDATE journal_entries SET status = 'posted' WHERE tenant_id = t AND status = 'draft';
  d_post := clock_timestamp() - t0;
  RAISE NOTICE 'Validation de % écritures : %', n, d_post;

  PERFORM _as_user();

  -- P7 — numéros définitifs continus par journal et exercice
  SELECT count(*) INTO v_bad FROM (
    SELECT journal_code, fiscal_year_id, count(*) AS c, max(posting_seq) AS mx, min(posting_seq) AS mn,
           count(DISTINCT posting_seq) AS dc
    FROM journal_entries WHERE tenant_id = t AND status = 'posted'
    GROUP BY 1, 2) s
  WHERE NOT (mn = 1 AND mx = c AND dc = c);
  PERFORM _rec('P7', 'numéros définitifs 1..n sans trou ni doublon, par journal et par exercice', v_bad = 0,
    v_bad || ' série(s) non continue(s)');

  -- P1, P2, P3 — avant toute clôture, pour chaque exercice
  v_det := '';
  v_bad := 0;
  DECLARE fy record; BEGIN
    FOR fy IN SELECT id, code, start_date, end_date FROM fiscal_years WHERE tenant_id = t AND code IN ('2023', '2024', '2025') ORDER BY code LOOP
      SELECT sum(closing_debit), sum(closing_credit) INTO v_d, v_c FROM get_trial_balance(fy.id, NULL, NULL, NULL);
      SELECT COALESCE(sum(credit - debit), 0) INTO v_is FROM get_income_statement(fy.id, NULL, NULL);
      SELECT COALESCE(sum(jl.credit - jl.debit), 0) INTO v_ref
      FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id
      WHERE je.tenant_id = t AND je.status = 'posted' AND je.date BETWEEN fy.start_date AND fy.end_date
        AND jl.account_code ~ '^[67]';
      SELECT COALESCE(sum(balance), 0) INTO v_bs FROM get_balance_sheet(fy.id, NULL);
      IF v_d <> v_c OR v_is <> v_ref OR v_bs <> 0 THEN v_bad := v_bad + 1; END IF;
      v_det := v_det || format('%s: balance %s/%s, CR %s (attendu %s), Σbilan %s ; ', fy.code, v_d, v_c, v_is, v_ref, v_bs);
    END LOOP;
  END;
  PERFORM _rec('P1', 'avant clôture : balance, compte de résultat et bilan justes sur les 3 exercices', v_bad = 0, v_det);

  -- Clôture 2023 → 2024
  t0 := clock_timestamp();
  r1 := close_fiscal_year(fy23, fy24, true);
  d_c1 := clock_timestamp() - t0;

  -- P4 — classes 6/7 soldées en 2023 ; à-nouveaux 2024 = soldes de clôture 2023, compte par compte
  SELECT count(*) INTO v_bad FROM (
    SELECT jl.account_code FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id
    WHERE je.tenant_id = t AND je.status = 'posted' AND je.date BETWEEN '2023-01-01' AND '2023-12-31'
    GROUP BY jl.account_code
    HAVING jl.account_code ~ '^[67]' AND sum(jl.debit - jl.credit) <> 0) x;
  SELECT count(*) INTO v_res FROM (
    SELECT account, sum(s) FROM (
      SELECT jl.account_code AS account, jl.debit - jl.credit AS s
      FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id
      WHERE je.tenant_id = t AND je.status = 'posted' AND je.date BETWEEN '2023-01-01' AND '2023-12-31'
        AND jl.account_code !~ '^[67]'
      UNION ALL
      SELECT jl.account_code, -(jl.debit - jl.credit)
      FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id
      WHERE je.tenant_id = t AND je.status = 'posted' AND je.journal_code = 'AN' AND je.date = '2024-01-01'
    ) u GROUP BY account HAVING sum(s) <> 0) y;
  PERFORM _rec('P4', 'clôture 2023 : classes 6/7 soldées, à-nouveaux 2024 = soldes de clôture compte par compte',
    COALESCE((r1->>'success')::boolean, false) AND v_bad = 0 AND v_res = 0,
    format('clôture=%s ; comptes 6/7 non soldés=%s ; comptes dont l''à-nouveau diffère=%s ; résultat=%s',
      COALESCE(r1->>'error', r1->>'success'), v_bad, v_res, r1->>'result'));

  -- Clôture 2024 → 2025 (périodes closes au préalable, comme dans l'écran)
  UPDATE fiscal_periods SET status = 'closed' WHERE fiscal_year_id = fy24;
  t0 := clock_timestamp();
  r2 := close_fiscal_year(fy24, fy25, true);
  d_c2 := clock_timestamp() - t0;

  -- P5 — à-nouveaux 2025 = cumul 2023-2024 hors classes 6/7 et hors à-nouveaux (sinon double comptage)
  SELECT count(*) INTO v_res FROM (
    SELECT account, sum(s) FROM (
      SELECT jl.account_code AS account, jl.debit - jl.credit AS s
      FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id
      WHERE je.tenant_id = t AND je.status = 'posted' AND je.date BETWEEN '2023-01-01' AND '2024-12-31'
        AND je.journal_code <> 'AN' AND jl.account_code !~ '^[67]'
      UNION ALL
      SELECT jl.account_code, -(jl.debit - jl.credit)
      FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id
      WHERE je.tenant_id = t AND je.status = 'posted' AND je.journal_code = 'AN' AND je.date = '2025-01-01'
    ) u GROUP BY account HAVING sum(s) <> 0) y;
  SELECT COALESCE(sum(balance), 0) INTO v_bs FROM get_balance_sheet(fy25, NULL);
  SELECT sum(closing_debit), sum(closing_credit) INTO v_d, v_c FROM get_trial_balance(fy25, NULL, NULL, NULL);
  PERFORM _rec('P5', 'deux clôtures : à-nouveaux 2025 = cumul 2023-2024, bilan et balance 2025 équilibrés',
    COALESCE((r2->>'success')::boolean, false) AND v_res = 0 AND v_bs = 0 AND v_d = v_c,
    format('clôture=%s ; comptes en écart=%s ; Σbilan 2025=%s ; balance 2025 %s/%s',
      COALESCE(r2->>'error', r2->>'success'), v_res, v_bs, v_d, v_c));

  -- P2 — le compte de résultat d'un exercice clos reste lisible (écritures CL exclues)
  SELECT COALESCE(sum(credit - debit), 0) INTO v_is FROM get_income_statement(fy23, NULL, NULL);
  SELECT COALESCE(sum(jl.credit - jl.debit), 0) INTO v_ref
  FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id
  WHERE je.tenant_id = t AND je.status = 'posted' AND je.journal_code <> 'CL'
    AND je.date BETWEEN '2023-01-01' AND '2023-12-31' AND jl.account_code ~ '^[67]';
  PERFORM _rec('P2', 'compte de résultat 2023 après clôture = Σ7 − Σ6 = résultat de clôture',
    v_is = v_ref AND v_is = (r1->>'result')::numeric, format('CR=%s attendu=%s clôture=%s', v_is, v_ref, r1->>'result'));

  -- P3 — bilan d'un exercice clos : plus de ligne RESULTAT, résultat dans 120/129, Σ = 0
  SELECT COALESCE(sum(balance), 0), count(*) FILTER (WHERE account_code = 'RESULTAT') INTO v_bs, v_bad
  FROM get_balance_sheet(fy23, NULL);
  PERFORM _rec('P3', 'bilan 2023 clos : équilibré, résultat porté par 120/129', v_bs = 0 AND v_bad = 0,
    format('Σ=%s lignes RESULTAT=%s', v_bs, v_bad));

  RAISE NOTICE 'Durées : validation %, clôture 2023 %, clôture 2024 %', d_post, d_c1, d_c2;
  PERFORM _rec('P6', 'chaque clôture en moins de 30 s', d_c1 < interval '30 seconds' AND d_c2 < interval '30 seconds',
    format('%s écritures ; clôture 2023 %s ; clôture 2024 %s', n, d_c1, d_c2));
END $$;

SELECT _audit_assert('189');
