-- ═══════════════════════════════════════════════════════════════════════════
-- 390 — roles_close_fiscal_year : la CLÔTURE d'exercice sur les rôles (LOC1-08)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- CE QUE C'EST. Le cœur de LOC1-08 : `close_fiscal_year` ne porte plus
-- `'120000'`/`'129000'` (compte de résultat) ni les journaux `'CL'`
-- (clôture, créé en `389`) et `'AN'` (à-nouveaux) : elle demande ses **rôles**.
--
-- ÉCRITURES IDENTIQUES. Le pack PCG rend exactement les comptes d'aujourd'hui
-- (`RESULTAT_BENEFICE→120000`, `RESULTAT_PERTE→129000`, `JOURNAL_CLOTURE→CL`,
-- `JOURNAL_A_NOUVEAUX→AN`). Recette du cahier : « balance d'ouverture N+1
-- identique à l'actuelle au centime ».
--
-- ⚠ CE QUI N'EST PAS TOUCHÉ. La SÉLECTION des comptes à solder reste la
-- **classe** (`~ '^[67]'`) — c'est `LOC1-11` (« remplacer la logique par
-- classe »), pas 08. Le cahier y renvoie au gabarit `income_statement`
-- (`LOC1-38`), qui n'est pas encore construit : on ne le simule pas.
--
-- REJOUABLE : `CREATE OR REPLACE`.
--
-- Numéro pris le 2026-10-06T14:54:50.850Z par migration-numero.mjs
-- (ligne « plan6 C (lot K, Djibouti) », branche plan6/c-localisation).
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- 1. Clôture d'exercice → journaux CL et AN, comptes de résultat, sur les rôles
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.close_fiscal_year(p_fiscal_year_id uuid, p_next_fiscal_year_id uuid DEFAULT NULL::uuid, p_carry_forward boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  -- LOC1-08 : journaux et comptes viennent des RÔLES
  v_journal_cl text;
  v_journal_an text;
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
  v_journal_cl := resolve_journal(v_tid, 'JOURNAL_CLOTURE');
  v_journal_an := resolve_journal(v_tid, 'JOURNAL_A_NOUVEAUX');

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
  -- LOC1-08 : le compte de résultat vient du RÔLE
  v_result_account := CASE WHEN v_result >= 0 THEN resolve_account(v_tid, 'RESULTAT_BENEFICE')
                           ELSE resolve_account(v_tid, 'RESULTAT_PERTE') END;

  -- AUD-D06 : rien à solder → pas d'écriture de regroupement, la clôture continue
  IF EXISTS (SELECT 1 FROM _cl_soldes) THEN
    INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, reference)
    VALUES (v_tid, 'CL-' || v_fy.code, v_fy.end_date, v_journal_cl, 'draft',
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
      VALUES (v_tid, 'AN-' || v_next.code, v_next.start_date, v_journal_an, 'draft',
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
END $function$;
