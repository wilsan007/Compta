-- ============================================================
-- 212_payroll_payment_tests.sql — R-04 (phase 1 du reste-à-faire du 22/09)
--
-- La 191 comptabilise la paie (charges et dettes), pas son paiement : aucune
-- écriture D 421 / C 512 au versement des salaires, ni D 431 / C 512 pour les
-- organismes sociaux, ni D 447 / C 512 pour l'impôt retenu, ni D 425 / C 512
-- pour les acomptes versés aux salariés.
--
-- Bulletin type (repris de la 181) : brut 3 000, cotisations salariales 400,
-- CSG/CRDS 200, impôt 60 → net 2 340 ; charges patronales 1 260 ; acompte 100
-- déduit si demandé (net 2 240).
--
-- Montants attendus pour 2 salariés :
--   net        2 340 × 2 = 4 680 en 421 (un auxiliaire par salarié, lettré)
--   organismes (400 + 200 + 1 260) × 2 = 3 720 en 431
--   impôt       60 × 2 = 120 en 447
--   acompte    100 × 2 = 200 en 425 (si demandé)
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '212', false);
DELETE FROM _audit_results WHERE file = '212';

-- Lot de paie avec p_slips bulletins, statut demandé, acompte éventuel
CREATE OR REPLACE FUNCTION _mk_run212(p_t uuid, p_number text, p_status text DEFAULT 'approved',
  p_slips int DEFAULT 2, p_adv numeric DEFAULT 0)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE r uuid; e uuid; i int;
BEGIN
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status,
    gross_total, tax_total, net_total, employee_count)
  VALUES (p_t, p_number, '2026-03-01', '2026-03-31', '2026-03-31', 'draft',
    3000 * p_slips, (660 + p_adv) * p_slips, (2340 - p_adv) * p_slips, p_slips)
  RETURNING id INTO r;
  FOR i IN 1..p_slips LOOP
    INSERT INTO employees (tenant_id, name, email, status, employee_number)
    VALUES (p_t, 'Salarié ' || i, lower(p_number) || '-' || i || '@audit.test', 'active', p_number || '-S' || i)
    RETURNING id INTO e;
    INSERT INTO pay_slips (tenant_id, number, pay_run_id, employee_id, period_start, period_end,
      gross_salary, total_gross, social_security_employee, income_tax, other_deductions, total_deductions,
      net_salary, employer_contributions, status, calc_inputs)
    VALUES (p_t, p_number || '-BS' || i, r, e, '2026-03-01', '2026-03-31',
      3000, 3000, 400, 60, 200 + p_adv, 660 + p_adv, 2340 - p_adv, 1260, 'draft',
      jsonb_build_object('csgDeductible', 120, 'csgNonDeductible', 60, 'crds', 20,
                         'advanceDeduction', p_adv, 'otherDeductions', 0));
  END LOOP;
  IF p_status <> 'draft' THEN UPDATE pay_runs SET status = p_status WHERE id = r; END IF;
  RETURN r;
END $$;

-- Identifiants des écritures d'un paiement, par périmètre
CREATE OR REPLACE FUNCTION _pay_entry(p_res jsonb, p_scope text)
RETURNS uuid LANGUAGE sql AS $$
  SELECT (e->>'entry_id')::uuid FROM jsonb_array_elements(p_res->'entries') e
  WHERE e->>'scope' = p_scope LIMIT 1
$$;

-- P08 — versement des salaires : D 421 (un auxiliaire par salarié) / C banque, lettré
DO $$
DECLARE t uuid := _mk_tenant('P08'); r uuid; res jsonb; e uuid; v record; n_open int; n_tiers int;
BEGIN
  PERFORM _as_user();
  BEGIN
    r := _mk_run212(t, 'PR8', 'approved', 2);
    res := post_payroll_payment(r, NULL, DATE '2026-03-31', 'net');
    e := _pay_entry(res, 'net');
    SELECT je.journal_code, je.status,
           sum(jl.debit) FILTER (WHERE jl.account_code = '421000') d421,
           sum(jl.credit) FILTER (WHERE jl.account_code = '512000') c512,
           count(DISTINCT jl.account_tiers) FILTER (WHERE jl.account_code = '421000') ntiers,
           sum(jl.debit) d, sum(jl.credit) c
      INTO v FROM journal_entries je JOIN journal_lines jl ON jl.journal_id = je.id
      WHERE je.id = e GROUP BY je.journal_code, je.status;
    SELECT count(*) INTO n_open FROM journal_lines
      WHERE account_code = '421000' AND tenant_id = t AND lettrage_code IS NULL;
    SELECT count(DISTINCT account_tiers) INTO n_tiers FROM journal_lines
      WHERE account_code = '421000' AND tenant_id = t;
    PERFORM _rec('P08', 'nets 2 × 2 340 = 4 680 : D 421 par salarié / C banque, lettrage 421 soldé',
      v.journal_code = 'BQ' AND v.status = 'posted' AND v.d421 = 4680 AND v.c512 = 4680
        AND v.ntiers = 2 AND n_tiers = 2 AND v.d = v.c AND n_open = 0,
      format('journal=%s statut=%s D421=%s C512=%s auxiliaires=%s ouvertes=%s', v.journal_code, v.status, v.d421, v.c512, v.ntiers, n_open));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('P08', 'nets 2 × 2 340 = 4 680 : D 421 par salarié / C banque, lettrage 421 soldé', false, SQLERRM);
  END;
END $$;

-- P09 — organismes sociaux et impôt retenu : D 431 / C banque, D 447 / C banque
DO $$
DECLARE t uuid := _mk_tenant('P09'); r uuid; res jsonb; es uuid; v record; v_d431 numeric;
BEGIN
  PERFORM _as_user();
  BEGIN
    r := _mk_run212(t, 'PR9', 'approved', 2);
    res := post_payroll_payment(r, NULL, DATE '2026-03-31', 'social');
    res := post_payroll_payment(r, NULL, DATE '2026-03-31', 'tax');
    es := _pay_entry(res, 'tax');
    SELECT sum(debit) FILTER (WHERE account_code = '447000') d447,
           sum(credit) FILTER (WHERE account_code = '512000') c512
      INTO v FROM journal_lines WHERE journal_id = es;
    SELECT sum(debit) INTO v_d431 FROM journal_lines WHERE account_code = '431000' AND tenant_id = t AND debit > 0;
    PERFORM _rec('P09', 'organismes 3 720 en 431 et impôt 120 en 447, contrepartie banque',
      v_d431 = 3720 AND v.d447 = 120 AND v.c512 = 120,
      format('D431=%s D447=%s C512(impôt)=%s', v_d431, v.d447, v.c512));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('P09', 'organismes 3 720 en 431 et impôt 120 en 447, contrepartie banque', false, SQLERRM);
  END;
END $$;

-- P10 — idempotence : un second appel ne double rien, et le lot passe à « payé »
DO $$
DECLARE t uuid := _mk_tenant('P10'); r uuid; res jsonb; st text; n int;
BEGIN
  PERFORM _as_user();
  BEGIN
    r := _mk_run212(t, 'PR10', 'approved', 2);
    res := post_payroll_payment(r, NULL, DATE '2026-03-31', 'all');
    res := post_payroll_payment(r, NULL, DATE '2026-03-31', 'all');
    SELECT count(*) INTO n FROM journal_entries
      WHERE tenant_id = t AND reference LIKE 'PAYPAY-PR10-%';
    SELECT status INTO st FROM pay_runs WHERE id = r;
    PERFORM _rec('P10', 'deux appels « all » : 3 écritures (net, organismes, impôt), lot payé',
      n = 3 AND st = 'paid' AND jsonb_array_length(res->'already_paid') = 3,
      format('écritures=%s statut=%s déjà payés=%s', n, st, res->>'already_paid'));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('P10', 'deux appels « all » : 3 écritures (net, organismes, impôt), lot payé', false, SQLERRM);
  END;
END $$;

-- P11 — acompte versé à un salarié : D 425 / C banque, acompte marqué déduit
DO $$
DECLARE t uuid := _mk_tenant('P11'); r uuid; res jsonb; e uuid; v record; st text; adv uuid;
BEGIN
  PERFORM _as_user();
  BEGIN
    r := _mk_run212(t, 'PR11', 'approved', 2, 100);
    INSERT INTO salary_advances (tenant_id, employee_id, amount, advance_date, deduction_month, status)
    SELECT t, employee_id, 100, '2026-03-10', '2026-03-01', 'pending'
    FROM pay_slips WHERE pay_run_id = r ORDER BY number LIMIT 1
    RETURNING id INTO adv;
    res := post_payroll_payment(r, NULL, DATE '2026-03-31', 'advances');
    e := _pay_entry(res, 'advances');
    SELECT sum(debit) FILTER (WHERE account_code = '425000') d425,
           sum(credit) FILTER (WHERE account_code = '512000') c512
      INTO v FROM journal_lines WHERE journal_id = e;
    SELECT status INTO st FROM salary_advances WHERE id = adv;
    PERFORM _rec('P11', 'acompte 100 versé à un salarié : D 425 / C banque, acompte marqué déduit',
      v.d425 = 100 AND v.c512 = 100 AND st = 'deducted',
      format('D425=%s C512=%s statut acompte=%s', v.d425, v.c512, st));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('P11', 'acompte 100 versé à un salarié : D 425 / C banque, acompte marqué déduit', false, SQLERRM);
  END;
END $$;

-- P12 — l'acompte est intégré au sein du lot : le passage à « processing » ne doit pas échouer
DO $$
DECLARE t uuid := _mk_tenant('P12'); r uuid; ok boolean := false; msg text; n int;
BEGIN
  PERFORM _as_user();
  BEGIN
    r := _mk_run212(t, 'PR12', 'draft', 1);
    INSERT INTO salary_advances (tenant_id, employee_id, amount, advance_date, deduction_month, status)
    SELECT t, employee_id, 100, '2026-03-10', '2026-03-01', 'pending'
    FROM pay_slips WHERE pay_run_id = r LIMIT 1;
    BEGIN
      UPDATE pay_runs SET status = 'processing' WHERE id = r;
    EXCEPTION WHEN OTHERS THEN ok := true; msg := SQLERRM; END;
    SELECT count(*) INTO n FROM payroll_variable_elements
      WHERE tenant_id = t AND pay_run_id = r AND element_type = 'advance_deduction';
    PERFORM _rec('P12', 'intégration d''un acompte au passage à « processing » : acceptée, élément créé',
      NOT ok AND n = 1, format('erreur=%s (%s) éléments=%s', ok, COALESCE(msg, '—'), n));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('P12', 'intégration d''un acompte au passage à « processing » : acceptée, élément créé', false, SQLERRM);
  END;
END $$;

-- P13 — le compte bancaire choisi porte le crédit, et son journal est utilisé
DO $$
DECLARE t uuid := _mk_tenant('P13'); r uuid; res jsonb; e uuid; b uuid; v record;
BEGIN
  PERFORM _as_user();
  BEGIN
    INSERT INTO bank_accounts (tenant_id, name, type, bank_name) VALUES (t, 'Compte courant', 'chequing', 'Banque')
    RETURNING id INTO b;
    r := _mk_run212(t, 'PR13', 'approved', 1);
    res := post_payroll_payment(r, b, DATE '2026-04-02', 'net');
    e := _pay_entry(res, 'net');
    SELECT je.journal_code, je.date, max(jl.account_code) FILTER (WHERE jl.credit > 0) AS cpt
      INTO v FROM journal_entries je JOIN journal_lines jl ON jl.journal_id = je.id
      WHERE je.id = e GROUP BY je.journal_code, je.date;
    PERFORM _rec('P13', 'compte bancaire choisi : 512000 crédité au journal BQ, à la date demandée',
      v.cpt = '512000' AND v.journal_code = 'BQ' AND v.date = DATE '2026-04-02',
      format('compte crédité=%s journal=%s date=%s', v.cpt, v.journal_code, v.date));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('P13', 'compte bancaire choisi : 512000 crédité au journal BQ, à la date demandée', false, SQLERRM);
  END;
END $$;

-- P14 — un lot non approuvé ne se paie pas
DO $$
DECLARE t uuid := _mk_tenant('P14'); r uuid; refus boolean := false; msg text; n int;
BEGIN
  PERFORM _as_user();
  BEGIN
    r := _mk_run212(t, 'PR14', 'draft', 1);
    BEGIN
      PERFORM post_payroll_payment(r, NULL, CURRENT_DATE, 'all');
    EXCEPTION WHEN OTHERS THEN refus := true; msg := SQLERRM; END;
    SELECT count(*) INTO n FROM journal_entries WHERE tenant_id = t;
    PERFORM _rec('P14', 'lot en brouillon : paiement refusé, aucune écriture',
      refus AND n = 0 AND msg ILIKE '%brouillon%', format('refus=%s écritures=%s | %s', refus, n, msg));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('P14', 'lot en brouillon : paiement refusé, aucune écriture', false, SQLERRM);
  END;
END $$;

-- P15 — le lot ne passe à « payé » que lorsque tout est versé
DO $$
DECLARE t uuid := _mk_tenant('P15'); r uuid; res jsonb; st text; reste jsonb;
BEGIN
  PERFORM _as_user();
  BEGIN
    r := _mk_run212(t, 'PR15', 'approved', 2, 100);
    res := post_payroll_payment(r, NULL, DATE '2026-03-31', 'net');
    SELECT status INTO st FROM pay_runs WHERE id = r;
    PERFORM _rec('P15', 'nets versés seuls : le lot reste « approved » et annonce 3 périmètres restants',
      st = 'approved' AND jsonb_array_length(res->'remaining') = 3,
      format('statut=%s restants=%s', st, res->>'remaining'));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('P15', 'nets versés seuls : le lot reste « approved » et annonce 3 périmètres restants', false, SQLERRM);
  END;
END $$;

DO $$
DECLARE t uuid := _mk_tenant('P16'); r uuid; refus boolean := false; msg text;
BEGIN
  PERFORM _as_user();
  BEGIN
    r := _mk_run212(t, 'PR16', 'approved', 1);
    BEGIN
      PERFORM post_payroll_payment(r, NULL, CURRENT_DATE, 'inconnu');
    EXCEPTION WHEN OTHERS THEN refus := true; msg := SQLERRM; END;
    PERFORM _rec('P16', 'périmètre inconnu refusé (net, social, tax, advances, all)',
      refus AND msg ILIKE '%périmètre%', COALESCE(msg, 'accepté'));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('P16', 'périmètre inconnu refusé (net, social, tax, advances, all)', false, SQLERRM);
  END;
END $$;

DROP FUNCTION _mk_run212(uuid, text, text, integer, numeric);
DROP FUNCTION _pay_entry(jsonb, text);

SELECT _audit_assert('212');