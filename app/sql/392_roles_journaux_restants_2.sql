-- ═══════════════════════════════════════════════════════════════════════════
-- 392 — roles_journaux_restants_2 : journaux en dur, tranche 2 (LOC1-09)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- CE QUE C'EST. Suite de `391` : deux fonctions de plus ne portent plus `'OD'`.
--   - `integrate_expense_report_on_approval` (note de frais → journal OD) ;
--   - `post_deferred_charge` (charges/produits constatés d'avance → journal OD).
--
-- ÉCRITURES IDENTIQUES : le pack PCG rend `JOURNAL_OD → OD`.
--
-- ⚠ RESTE EN DUR, ET POURQUOI : les COMPTES `486000`/`487000` (comptes
-- d'attente CCA/PCA) de `post_deferred_charge` — des comptes, pas des journaux
-- (LOC1-10/11 ; le catalogue fermé ne les nomme pas encore).
--
-- Le RESTE de LOC1-09 est gardé par la suite `391` (T03) :
-- `credit_note_guard`, `generate_depreciation_entry`,
-- `purchase_credit_note_guard`, `revaluate_currency_balances` (tranche 3).
--
-- Numéro pris le 2026-10-11T05:39:56.776Z par migration-numero.mjs
-- (ligne « plan6 C (lot K, Djibouti) », branche plan6/c-localisation).
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- 1. Note de frais approuvée → journal OD
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.integrate_expense_report_on_approval()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_period text;
  v_pay_run_id uuid;
  v_total numeric;
  v_vat numeric;
  v_charge numeric;
  v_rate numeric;
  v_account_charge text;
  v_account_vat text;
  v_account_employee text;
  v_entry uuid;
  v_existing uuid;
  v_date date;
  v_journal text;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'approved' THEN
    -- 3.1 La période : celle de la note de frais quand elle est posée, sinon le
    --     mois de validation. `submitted_at` peut tomber dans le mois suivant.
    v_period := COALESCE(NULLIF(NEW.period, ''), to_char(COALESCE(NEW.submitted_at, now()), 'YYYY-MM'));
    v_total := COALESCE(NEW.total_amount, 0);
    v_vat := COALESCE(NEW.total_vat, 0);

    IF v_total < 0 THEN
      RAISE EXCEPTION 'Note de frais % : total négatif (%)', NEW.number, v_total
        USING ERRCODE = 'check_violation';
    END IF;
    IF v_vat < 0 OR v_vat > v_total THEN
      RAISE EXCEPTION 'Note de frais % : TVA récupérable % incohérente avec le total %',
        NEW.number, v_vat, v_total USING ERRCODE = 'check_violation';
    END IF;
    v_charge := v_total - v_vat;

    -- 3.2 L'élément de paie : le remboursement TTC dû au salarié (RH-07).
    SELECT id INTO v_pay_run_id FROM pay_runs
      WHERE tenant_id = NEW.tenant_id AND to_char(period_start, 'YYYY-MM') = v_period
        AND status IN ('draft', 'processing') ORDER BY created_at DESC LIMIT 1;

    INSERT INTO payroll_variable_elements (tenant_id, employee_id, pay_run_id, period, element_type,
                                           description, quantity, unit_price, amount, source, source_id, integrated)
    VALUES (NEW.tenant_id, NEW.employee_id, v_pay_run_id, v_period, 'expense_reimbursement',
            'Frais ' || NEW.number, NULL, NULL, v_total, 'expense_report', NEW.id, false)
    ON CONFLICT DO NOTHING;

    -- 3.3 L'écriture (RH-08) : un seul passage, portée par sa référence.
    SELECT je.id INTO v_existing FROM journal_entries je
      WHERE je.tenant_id = NEW.tenant_id AND je.reference = 'EXPENSE-' || NEW.number LIMIT 1;

    IF v_existing IS NULL AND v_total > 0 THEN
      v_account_charge := payroll_account(NEW.tenant_id, 'expense_reimbursement');
      v_account_employee := payroll_account(NEW.tenant_id, 'net');

      -- Taux de TVA : celui des lignes quand il est posé, sinon celui qu'implique
      -- le montant de TVA ; le compte vient du paramétrage TVA.
      SELECT max(l.vat_rate) INTO v_rate FROM expense_report_lines l
        WHERE l.expense_report_id = NEW.id AND l.tenant_id = NEW.tenant_id
          AND COALESCE(l.vat_amount, 0) > 0;
      IF v_rate IS NULL AND v_vat > 0 AND v_charge > 0 THEN
        v_rate := round(v_vat / v_charge * 100, 2);
      END IF;

      -- 3.3bis Le compte de TVA : la correspondance CANONIQUE du taux d'abord
      --        (FR20 → 445661), jamais un régime particulier par accident.
      SELECT COALESCE(
        (SELECT m.account_code FROM vat_account_mapping m
          WHERE m.tenant_id IN (NEW.tenant_id, '00000000-0000-0000-0000-000000000000')
            AND m.direction = 'deductible' AND m.rate = v_rate
            AND m.vat_code = vat_code_for_rate(v_rate)
          ORDER BY (m.tenant_id <> '00000000-0000-0000-0000-000000000000') DESC LIMIT 1),
        (SELECT m.account_code FROM vat_account_mapping m
          WHERE m.tenant_id IN (NEW.tenant_id, '00000000-0000-0000-0000-000000000000')
            AND m.direction = 'deductible' AND m.rate = v_rate
          ORDER BY (m.tenant_id <> '00000000-0000-0000-0000-000000000000') DESC,
                   (m.vat_code IN ('AUTOLIQ', 'UE', 'EXO')) ASC, m.vat_code LIMIT 1),
        (SELECT m.account_code FROM vat_account_mapping m
          WHERE m.tenant_id = '00000000-0000-0000-0000-000000000000'
            AND m.direction = 'deductible' AND m.vat_code = vat_code_for_rate(20) LIMIT 1))
      INTO v_account_vat;

      IF v_vat > 0 AND v_account_vat IS NULL THEN
        RAISE EXCEPTION 'Note de frais % : aucune TVA récupérable au paramétrage (vat_account_mapping, direction deductible) — la TVA de % ne peut pas être ventilée',
          NEW.number, v_vat USING ERRCODE = 'check_violation';
      END IF;

      -- LOC1-09 : le journal vient du RÔLE (et il est garanti)
      PERFORM ensure_standard_journals(NEW.tenant_id);
      v_journal := resolve_journal(NEW.tenant_id, 'JOURNAL_OD');

      v_date := COALESCE(NEW.reimbursement_date, (NEW.approved_at)::date, CURRENT_DATE);

      INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, reference, piece_number)
      VALUES (NEW.tenant_id, 'JE-' || NEW.number, v_date, v_journal, 'draft',
              'Note de frais ' || NEW.number, 'EXPENSE-' || NEW.number, NEW.number)
      RETURNING id INTO v_entry;

      INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
      SELECT NEW.tenant_id, v_entry, x.account, x.account,
             CASE WHEN x.side = 'D' THEN x.amount ELSE 0 END,
             CASE WHEN x.side = 'C' THEN x.amount ELSE 0 END,
             'Note de frais ' || NEW.number,
             row_number() OVER (ORDER BY x.side DESC, x.account)
      FROM (VALUES
              (v_account_charge,   'D', v_charge),
              (v_account_vat,      'D', v_vat),
              (v_account_employee, 'C', v_total)
           ) AS x(account, side, amount)
      WHERE x.amount > 0 AND x.account IS NOT NULL;

      UPDATE journal_entries SET status = 'posted' WHERE id = v_entry;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

-- ─────────────────────────────────────────────────────────────
-- 2. Charges/produits constatés d'avance → journal OD
--    (les comptes d'attente 486000/487000 restent : LOC1-10/11)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.post_deferred_charge(p_regularization_id uuid, p_type text DEFAULT NULL::text, p_amount numeric DEFAULT NULL::numeric, p_months integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_tid uuid := current_tenant_id();
  v_reg regularization_entries%ROWTYPE;
  v_type text;
  v_montant numeric;
  v_mois int;
  v_attente text;
  v_compte text;
  v_ref text;
  v_number text;
  v_date date;
  v_part numeric;
  v_je uuid;
  v_initiale uuid;
  v_entries jsonb := '[]'::jsonb;
  i int;
  v_journal text;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  SELECT * INTO v_reg FROM regularization_entries WHERE id = p_regularization_id AND tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Régularisation introuvable : %', p_regularization_id;
  END IF;

  v_type := lower(btrim(COALESCE(NULLIF(p_type, ''), v_reg.type)));
  IF v_type NOT IN ('cca', 'pca') THEN
    RAISE EXCEPTION 'Type de report inconnu : % (attendu cca ou pca)', COALESCE(p_type, v_reg.type)
      USING ERRCODE = 'check_violation';
  END IF;

  v_montant := round(COALESCE(NULLIF(p_amount, 0), NULLIF(v_reg.remaining_amount, 0), v_reg.amount, 0), 2);
  IF v_montant <= 0 THEN
    RAISE EXCEPTION 'Montant à reporter invalide pour la régularisation % : %', v_reg.id, v_montant
      USING ERRCODE = 'check_violation';
  END IF;

  -- Idempotence : un report déjà passé ne se double pas
  v_ref := 'DEFER:' || v_reg.id;
  IF EXISTS (SELECT 1 FROM journal_entries WHERE tenant_id = v_tid AND reference = v_ref || ':0') THEN
    RAISE EXCEPTION 'La régularisation % a déjà été reportée en charge/produit constaté d''avance',
      COALESCE(v_reg.description, v_reg.id::text)
      USING ERRCODE = 'unique_violation';
  END IF;

  v_compte := btrim(v_reg.account_code);
  v_attente := CASE WHEN v_type = 'cca' THEN '486000' ELSE '487000' END;
  IF NOT EXISTS (SELECT 1 FROM chart_accounts WHERE tenant_id = v_tid AND code = v_compte) THEN
    RAISE EXCEPTION 'Compte % absent du plan comptable de la société', v_compte
      USING ERRCODE = 'foreign_key_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM chart_accounts WHERE tenant_id = v_tid AND code = v_attente) THEN
    RAISE EXCEPTION 'Compte d''attente % absent du plan comptable de la société', v_attente
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  v_mois := COALESCE(NULLIF(p_months, 0),
    GREATEST(1, (date_part('year', age(v_reg.end_date, v_reg.start_date)) * 12
               + date_part('month', age(v_reg.end_date, v_reg.start_date)))::int));
  v_mois := LEAST(v_mois, 120);

  -- LOC1-09 : le journal vient du RÔLE (et il est garanti)
  PERFORM ensure_standard_journals(v_tid);
  v_journal := resolve_journal(v_tid, 'JOURNAL_OD');

  -- 1. écriture initiale, à la date de départ de la régularisation
  v_number := 'DEFER-' || left(replace(v_reg.id::text, '-', ''), 8) || '-0';
  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, reference, piece_number)
  VALUES (v_tid, v_number, v_reg.start_date, v_journal, 'draft',
          upper(v_type) || ' ' || v_reg.description || ' (' || v_mois || ' mois)', v_ref || ':0', v_number)
  RETURNING id INTO v_je;
  v_initiale := v_je;

  IF v_type = 'cca' THEN
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_name, debit, credit, description)
    VALUES (v_tid, v_je, v_attente, 'Charges constatées d''avance', v_montant, 0, 'CCA à répartir'),
           (v_tid, v_je, v_compte,  'Charge reportée', 0, v_montant, 'CCA à répartir');
  ELSE
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_name, debit, credit, description)
    VALUES (v_tid, v_je, v_compte,  'Produit reporté', v_montant, 0, 'PCA à répartir'),
           (v_tid, v_je, v_attente, 'Produits constatés d''avance', 0, v_montant, 'PCA à répartir');
  END IF;
  UPDATE journal_entries SET status = 'posted' WHERE id = v_je AND tenant_id = v_tid;

  v_entries := v_entries || jsonb_build_object(
    'entry_id', v_je, 'entry_number', v_number, 'date', v_reg.start_date,
    'amount', v_montant, 'account', v_attente, 'deferred_account', v_attente, 'counterpart', v_compte);

  -- 2. reprises mensuelles, au premier jour de chaque mois suivant ; la
  --    dernière absorbe l'arrondi pour que le total repris soit exact
  FOR i IN 1..v_mois LOOP
    v_date := (date_trunc('month', v_reg.start_date) + make_interval(months => i))::date;
    v_part := CASE WHEN i = v_mois THEN round(v_montant - round(v_montant / v_mois, 2) * (v_mois - 1), 2)
                   ELSE round(v_montant / v_mois, 2) END;
    v_number := 'DEFER-' || left(replace(v_reg.id::text, '-', ''), 8) || '-' || i;

    INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, reference, piece_number)
    VALUES (v_tid, v_number, v_date, v_journal, 'draft',
            'Reprise ' || upper(v_type) || ' ' || i || '/' || v_mois || ' - ' || v_reg.description,
            v_ref || ':1', v_number)
    RETURNING id INTO v_je;

    IF v_type = 'cca' THEN
      INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_name, debit, credit, description)
      VALUES (v_tid, v_je, v_compte,  'Charge reprise', v_part, 0, 'Reprise CCA ' || i),
             (v_tid, v_je, v_attente, 'Charges constatées d''avance', 0, v_part, 'Reprise CCA ' || i);
    ELSE
      INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_name, debit, credit, description)
      VALUES (v_tid, v_je, v_attente, 'Produits constatés d''avance', v_part, 0, 'Reprise PCA ' || i),
             (v_tid, v_je, v_compte,  'Produit repris', 0, v_part, 'Reprise PCA ' || i);
    END IF;
    UPDATE journal_entries SET status = 'posted' WHERE id = v_je AND tenant_id = v_tid;

    v_entries := v_entries || jsonb_build_object(
      'entry_id', v_je, 'entry_number', v_number, 'date', v_date, 'amount', v_part, 'account', v_compte);
  END LOOP;

  UPDATE regularization_entries
  SET used_amount = v_montant, remaining_amount = 0, status = 'posted',
      created_entry_id = v_initiale, updated_at = now()
  WHERE id = v_reg.id AND tenant_id = v_tid;

  RETURN jsonb_build_object(
    'success', true,
    'regularization_id', v_reg.id,
    'type', v_type,
    'total_amount', v_montant,
    'monthly_amount', round(v_montant / v_mois, 2),
    'months', v_mois,
    'entry_id', v_initiale,
    'entries', v_entries
  );
END $function$;
