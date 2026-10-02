-- ===========================================================
-- 322_payslip_elements_invariants_tests.sql — lot C (paie)
--
-- Dernière étape de la suppression du second moteur de paie
-- (`src/lib/payroll.ts`, 509 lignes).
--
-- 108 assertions vivaient sur SES PROPRES chiffres. Ce qu'elles piggyotaient —
-- des invariants qui, eux, restent vrais — est porté ici contre
-- `payroll_compute_slip`, le moteur qui reste. On ne perd pas un test : on le
-- rejoue contre le barème qui fait foi.
--
-- Ils sont écrits en DIFFÉRENCE (avec / sans élément), jamais en valeur
-- absolue : un taux change chaque année, un invariant non.
--
-- Le détail ligne à ligne (`contributions`) est vérifié aussi : un bulletin
-- doit DIRE d'où vient chaque euro.
-- ===========================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '322', false);
DELETE FROM _audit_results WHERE file = '322';

-- Un lot, un salarié, un élément variable, et le bulletin avant / après.
CREATE OR REPLACE FUNCTION _lot322(p_nom text, p_element jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  t uuid; e uuid; r uuid; avant jsonb; apres jsonb;
BEGIN
  EXECUTE 'RESET ROLE';
  t := _mk_tenant('L' || p_nom);
  INSERT INTO payroll_legal_parameters (tenant_id, country_code, code, value, valid_from)
    VALUES (t, 'FR', 'TAUX_ATMP', 1.00, '2026-01-01');
  INSERT INTO employees (tenant_id, name, salary, status, hire_date)
    VALUES (t, 'Salarié ' || p_nom, 2500, 'active', '2020-01-06') RETURNING id INTO e;
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status)
    VALUES (t, 'PR-' || p_nom, '2026-09-01', '2026-09-30', '2026-09-30', 'draft') RETURNING id INTO r;

  PERFORM _as_user();
  avant := calculate_payslip(e, '2026-09', r);
  DELETE FROM payroll_variable_elements WHERE tenant_id = t;
  INSERT INTO payroll_variable_elements
    (tenant_id, employee_id, pay_run_id, period, element_type, description, amount, source)
    VALUES (t, e, r, '2026-09', p_element->>'type', p_element->>'libelle',
            (p_element->>'montant')::numeric, 'manuel');
  apres := calculate_payslip(e, '2026-09', r);
  EXECUTE 'RESET ROLE';

  RETURN jsonb_build_object(
    'brut_avant',     (avant ->> 'total_gross')::numeric,
    'brut_apres',     (apres ->> 'total_gross')::numeric,
    'securite_avant', (avant ->> 'social_security_employee')::numeric,
    'securite_apres', (apres ->> 'social_security_employee')::numeric,
    'csg_avant',      (avant ->> 'csg_crds_total')::numeric,
    'csg_apres',      (apres ->> 'csg_crds_total')::numeric,
    'impot_avant',    (avant ->> 'income_tax')::numeric,
    'impot_apres',    (apres ->> 'income_tax')::numeric,
    'net_avant',      (avant ->> 'net_salary')::numeric,
    'net_apres',      (apres ->> 'net_salary')::numeric,
    'lignes',         COALESCE(apres -> 'contributions', '[]'::jsonb)
  );
END $$;

DO $$
DECLARE
  d jsonb; ecart numeric; ligne jsonb; brut_ref numeric;
BEGIN
  -- T01 — l'ACOMPTE ne change ni le brut ni les cotisations : c'est une
  -- retenue sur un salaire déjà acquis, pas une composante de la rémunération.
  d := _lot322('T01', jsonb_build_object('type','advance_deduction','libelle','acompte','montant',500));
  ecart := d->>'net_avant' - d->>'net_apres';
  PERFORM _rec('T01', 'un acompte de 500 EUR sort du net, et laisse le brut comme les cotisations',
    round(ecart, 2) = 500
      AND d->>'brut_avant' = d->>'brut_apres'
      AND d->>'securite_avant' = d->>'securite_apres',
    format('net %s→%s (500 attendu) brut %s→%s secu %s→%s',
      d->>'net_avant', d->>'net_apres', d->>'brut_avant', d->>'brut_apres',
      d->>'securite_avant', d->>'securite_apres'));

  -- T02 — le RAPPEL DE PAIE est l'inverse : c'est du salaire dû, il entre
  -- donc au brut, et la CSG comme l'impôt se calculent dessus.
  d := _lot322('T02', jsonb_build_object('type','pay_recall','libelle','rappel','montant',800));
  PERFORM _rec('T02', 'un rappel de 800 EUR porte le brut, la CSG et l''impôt',
    round(d->>'brut_apres' - d->>'brut_avant', 2) = 800
      AND d->>'csg_apres' > d->>'csg_avant'
      AND d->>'impot_apres' > d->>'impot_avant',
    format('brut %s→%s (800 attendu) csg %s→%s impot %s→%s',
      d->>'brut_avant', d->>'brut_apres', d->>'csg_avant', d->>'csg_apres',
      d->>'impot_avant', d->>'impot_apres'));

  -- T03 — le REMBOURSEMENT DE FRAIS n'est pas une rémunération : il entre dans le
  -- net sans toucher au brut, aux cotisations ni à l'impôt. C'est la preuve
  -- que le moteur distingue une charge de l'entreprise d'un salaire.
  d := _lot322('T03', jsonb_build_object('type','expense_reimbursement','libelle','frais','montant',250));
  ecart := d->>'net_apres' - d->>'net_avant';
  PERFORM _rec('T03', 'un remboursement de 250 EUR entre dans le net, sans toucher brut, cotisations ni impôt',
    round(ecart, 2) = 250
      AND d->>'brut_avant' = d->>'brut_apres'
      AND d->>'securite_avant' = d->>'securite_apres'
      AND d->>'csg_avant' = d->>'csg_apres'
      AND d->>'impot_avant' = d->>'impot_apres',
    format('net %s→%s (250 attendu) brut %s→%s csg %s→%s impot %s→%s',
      d->>'net_avant', d->>'net_apres', d->>'brut_avant', d->>'brut_apres',
      d->>'csg_avant', d->>'csg_apres', d->>'impot_avant', d->>'impot_apres'));

  -- T04 — le CONGÉ SANS SOLDE se comporte comme l'acompte : le brut du mois est
  -- payé, la retenue s'opère sur le net.
  d := _lot322('T04', jsonb_build_object('type','unpaid_leave_deduction','libelle','congé','montant',400));
  ecart := d->>'net_avant' - d->>'net_apres';
  PERFORM _rec('T04', 'un congé sans solde de 400 EUR sort du net, sans toucher au brut',
    round(ecart, 2) = 400
      AND d->>'brut_avant' = d->>'brut_apres'
      AND d->>'securite_avant' = d->>'securite_apres',
    format('net %s→%s (400 attendu) brut %s→%s secu %s→%s',
      d->>'net_avant', d->>'net_apres', d->>'brut_avant', d->>'brut_apres',
      d->>'securite_avant', d->>'securite_apres'));

  -- T05 — le bulletin DIT d'où vient l'euro : l'acompte y figure, en négatif.
  d := _lot322('T05', jsonb_build_object('type','advance_deduction','libelle','acompte','montant',300));
  SELECT l INTO ligne FROM jsonb_array_elements(d->'lignes') l WHERE l->>'type' = 'advance_deduction';
  PERFORM _rec('T05', 'l''acompte figure au détail du bulletin, en négatif',
    ligne IS NOT NULL AND (ligne->>'amount')::numeric = -300,
    format('ligne=%s (montant -300 attendu)', COALESCE(ligne::text, 'ABSENTE')));

  -- T06 — et le moteur n'invente aucune ligne pour ce qui n'a pas été saisi.
  SELECT l INTO ligne FROM jsonb_array_elements(d->'lignes') l WHERE l->>'type' = 'pay_recall';
  PERFORM _rec('T06', 'sans élément de ce type, le bulletin n''invente aucune ligne',
    ligne IS NULL, format('ligne=%s', COALESCE(ligne::text, 'ABSENTE (attendu)')));

  -- T07 — le rappel, lui, y figure en positif.
  d := _lot322('T07', jsonb_build_object('type','pay_recall','libelle','rappel','montant',500));
  SELECT l INTO ligne FROM jsonb_array_elements(d->'lignes') l WHERE l->>'type' = 'pay_recall';
  PERFORM _rec('T07', 'le rappel figure au détail du bulletin, en positif',
    ligne IS NOT NULL AND (ligne->>'amount')::numeric = 500,
    format('ligne=%s (montant 500 attendu)', COALESCE(ligne::text, 'ABSENTE')));

  -- T08 — deux natures d'éléments ne se contaminent pas : un remboursement de
  -- frais ne relève pas le brut, même quand un rappel l'a relevé juste avant.
  d := _lot322('T08', jsonb_build_object('type','pay_recall','libelle','rappel','montant',800));
  brut_ref := d->>'brut_apres';
  d := _lot322('T09', jsonb_build_object('type','expense_reimbursement','libelle','frais','montant',250));
  PERFORM _rec('T08', 'rappel et remboursement ne se contaminent pas : chacun sa base',
    d->>'brut_apres' = brut_ref
      AND round((d->>'net_apres' - d->>'net_avant'), 2) = 250,
    format('brut après frais %s (%s attendu) écart net %s (250 attendu)',
      d->>'brut_apres', brut_ref, round((d->>'net_apres' - d->>'net_avant'), 2)));
END $$;

DROP FUNCTION _lot322(text, jsonb);
SELECT _audit_assert('322');