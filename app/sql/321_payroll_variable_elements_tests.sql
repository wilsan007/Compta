-- ============================================================
-- 321_payroll_variable_elements_tests.sql — lot C (paie)
--
-- Chorégraphie de la suppression du second moteur (`src/lib/payroll.ts`) :
-- ses 108 assertions portaient sur ses propres chiffres — dont plusieurs faux,
-- c'est le défaut rh-005. Avant de les effacer, la COUVERTURE qu'elles
-- apportaient est portée sur le moteur qui reste. C'est la doctrine W5 (« un
-- seul moteur par grandeur ») appliquée dans l'autre sens : on ne perd pas un
-- test, on le rejoue contre le moteur réel.
--
-- Inventaire mesuré des types d'éléments variables :
--
--   type                     | testé contre le moteur SQL   | Covered
--   --------------------------|------------------------------|---------
--   overtime                  | 243, 264, 265, 266          | ✓
--   advance_deduction         | 243                          | ✓
--   pay_recall                | 243                          | ✓
--   expense_reimbursement     | 243                          | ✓
--   unpaid_leave_deduction    | 265, 266                     | ✓
--   lateness_deduction        | 264                          | ✓
--   timesheet_hours           | 265, 266                     | ✓
--   **bonus**                 | **AUCUN**                    | 321
--   **meal_vouchers**         | **AUCUN**                    | 321
--   **transport_allowance**   | **AUCUN**                    | 321
--   **other_deductions**      | **AUCUN**                    | 321
--
-- Ces quatre-là n'étaient couverts que par le second moteur, qu'aucun écran
-- n'appelait. Cette suite les rejoue contre `calculate_payslip`.
--
-- Mesuré AVANT la 321 : 5 rouges / 1 vert (le vert est la non-régression).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '321', false);
DELETE FROM _audit_results WHERE file = '321';

-- Un lot de paie, un salarié, et autant d'éléments variables que voulu.
CREATE OR REPLACE FUNCTION _lot321(p_nom text, p_salaire numeric, p_elements jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  t uuid; e uuid; r uuid; res jsonb; el jsonb;
BEGIN
  EXECUTE 'RESET ROLE';
  t := _mk_tenant(p_nom);
  INSERT INTO payroll_legal_parameters (tenant_id, country_code, code, value, valid_from)
    VALUES (t, 'FR', 'TAUX_ATMP', 1.00, '2026-01-01');
  INSERT INTO employees (tenant_id, name, salary, status, hire_date)
    VALUES (t, 'Salarié ' || p_nom, p_salaire, 'active', '2020-01-06') RETURNING id INTO e;
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status)
    VALUES (t, 'PR-' || p_nom, '2026-09-01', '2026-09-30', '2026-09-30', 'draft') RETURNING id INTO r;
  FOR el IN SELECT * FROM jsonb_array_elements(p_elements) LOOP
    INSERT INTO payroll_variable_elements
      (tenant_id, employee_id, pay_run_id, period, element_type, description, quantity, unit_price, amount, source)
    VALUES (t, e, r, '2026-09', el->>'type', el->>'libelle',
            (el->>'qte')::numeric, (el->>'pu')::numeric, (el->>'montant')::numeric, 'manuel');
  END LOOP;
  PERFORM _as_user();
  res := calculate_payslip(e, '2026-09', r);
  EXECUTE 'RESET ROLE';
  RETURN res || jsonb_build_object('run_id', r, 'employee_id', e);
END $$;
DO $$
DECLARE d jsonb; d2 jsonb; brut numeric; net_a numeric; net_b numeric; ecart numeric;
BEGIN
  -- T01 — la prime entre dans le brut
  d := _lot321('T01', 2500, jsonb_build_array(
    jsonb_build_object('type','bonus','libelle','prime de résultat','montant',500)));
  brut := (d->>'total_gross')::numeric;
  PERFORM _rec('T01', 'une prime de 500 € porte le brut à 3 000 €',
    brut = 3000, format('brut=%s (3000 attendu) bonus=%s', brut, COALESCE(d->>'bonus','—')));

  -- T02 — les titres-restaurant
  d := _lot321('T02', 2500, jsonb_build_array(
    jsonb_build_object('type','meal_vouchers','libelle','titres-restaurant','montant',160)));
  brut := (d->>'total_gross')::numeric;
  PERFORM _rec('T02', 'les titres-restaurant sont repris par le moteur (160 € au brut)',
    brut = 2660 AND COALESCE((d->>'mealVouchers')::numeric, -1) = 160,
    format('brut=%s (2660 attendu) titres=%s', brut, COALESCE(d->>'mealVouchers','—')));

  -- T03 — l'indemnité de transport
  d := _lot321('T03', 2500, jsonb_build_array(
    jsonb_build_object('type','transport_allowance','libelle','transport','montant',75)));
  brut := (d->>'total_gross')::numeric;
  PERFORM _rec('T03', 'l''indemnité de transport est reprise par le moteur (75 € au brut)',
    brut = 2575 AND COALESCE((d->>'transportAllowance')::numeric, -1) = 75,
    format('brut=%s (2575 attendu) transport=%s', brut, COALESCE(d->>'transportAllowance','—')));

  -- T04 — une autre déduction est retranchée du net
  d  := _lot321('T04', 2500, jsonb_build_array(
        jsonb_build_object('type','other_deductions','libelle','avance sur prime','montant',120)));
  d2 := _lot321('T04bis', 2500, '[]'::jsonb);
  net_a := (d->>'net_salary')::numeric;
  net_b := (d2->>'net_salary')::numeric;
  ecart := round(net_b - net_a, 2);
  PERFORM _rec('T04', 'une autre déduction de 120 € est retranchée du net à payer',
    ecart = 120, format('avec=%s sans=%s écart=%s (120 attendu)', net_a, net_b, ecart));

  -- T05 — plusieurs éléments s'additionnent
  d := _lot321('T05', 2500, jsonb_build_array(
    jsonb_build_object('type','bonus','libelle','prime','montant',500),
    jsonb_build_object('type','meal_vouchers','libelle','titres-restaurant','montant',160),
    jsonb_build_object('type','transport_allowance','libelle','transport','montant',75),
    jsonb_build_object('type','other_deductions','libelle','avance sur prime','montant',120)));
  brut := (d->>'total_gross')::numeric;
  PERFORM _rec('T05', 'plusieurs éléments variables s''additionnent (brut 3 235 €)',
    brut = 3235, format('brut=%s (3235 attendu)', brut));

  -- T06 — sans élément variable, rien n'est inventé (non-régression)
  d := _lot321('T06', 2500, '[]'::jsonb);
  brut := (d->>'total_gross')::numeric;
  PERFORM _rec('T06', 'sans élément variable, le brut est celui de la fiche (2 500 €)',
    brut = 2500, format('brut=%s (2500 attendu)', brut));
END $$;

DROP FUNCTION _lot321(text, numeric, jsonb);
SELECT _audit_assert('321');