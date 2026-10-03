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
--
-- 04/10/2026 (341, tâche 2.1) : T02, T03 et T05 sortent du registre. Ils
-- attendaient les titres-restaurant et le transport « au brut », ce qui n'est
-- pas leur régime social ; ils sont réécrits sur le régime 2026 sourcé, et
-- T07 à T09 éprouvent les plafonds.
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

  -- T02 — les titres-restaurant (341). 04/10/2026 : assertion RÉÉCRITE. Elle
  -- attendait « 160 € au brut » (verdict précédent : brut = 2660), ce qui n'est
  -- pas leur régime : la part patronale EXONÉRÉE n'entre pas dans le brut, et la
  -- part salariale est une RETENUE sur le net. Décor : 20 titres de 10 €, part
  -- salariale 80 € (40 %) → part patronale 6,00 € par titre = 60 %, sous le
  -- plafond 2026 de 7,32 € [URSSAF-AN-2026] : rien n'est réintégré.
  d  := _lot321('T02', 2500, jsonb_build_array(
    jsonb_build_object('type','meal_vouchers','libelle','titres-restaurant','qte',20,'pu',10,'montant',80)));
  d2 := _lot321('T02bis', 2500, '[]'::jsonb);
  brut := (d->>'total_gross')::numeric;
  ecart := round((d2->>'net_salary')::numeric - (d->>'net_salary')::numeric, 2);
  PERFORM _rec('T02', 'titres-restaurant dans les limites : le brut ne bouge pas (2 500 €), la part salariale (80 €) est retenue sur le net, la part patronale (120 €) est publiée',
    brut = 2500 AND ecart = 80
      AND (d->>'mealVouchers')::numeric = 80
      AND (d->>'mealVouchersEmployerShare')::numeric = 120
      AND (d->>'mealVouchersReintegrated')::numeric = 0,
    format('brut=%s (2500) retenue sur le net=%s (80) part patronale=%s (120) réintégré=%s (0)',
           brut, ecart, d->>'mealVouchersEmployerShare', d->>'mealVouchersReintegrated'));

  -- T03 — la prise en charge du transport (341). 04/10/2026 : assertion RÉÉCRITE
  -- (verdict précédent : brut = 2575). Une prise en charge d'abonnement n'entre
  -- pas dans le brut : elle est versée en plus du net. Décor : abonnement de
  -- 150 €, pris en charge à 50 % (75 €) — sous les 75 % exonérés [URSSAF-TP-2026].
  d := _lot321('T03', 2500, jsonb_build_array(
    jsonb_build_object('type','transport_allowance','libelle','abonnement transports','qte',1,'pu',150,'montant',75)));
  brut := (d->>'total_gross')::numeric;
  ecart := round((d->>'net_salary')::numeric - (d2->>'net_salary')::numeric, 2);
  PERFORM _rec('T03', 'prise en charge du transport dans la limite : le brut ne bouge pas (2 500 €), 75 € sont versés en plus du net',
    brut = 2500 AND ecart = 75 AND (d->>'transportAllowance')::numeric = 75 AND (d->>'transportReintegrated')::numeric = 0,
    format('brut=%s (2500) versé en plus du net=%s (75) réintégré=%s (0)', brut, ecart, d->>'transportReintegrated'));

  -- T04 — une autre déduction est retranchée du net
  d  := _lot321('T04', 2500, jsonb_build_array(
        jsonb_build_object('type','other_deductions','libelle','avance sur prime','montant',120)));
  d2 := _lot321('T04bis', 2500, '[]'::jsonb);
  net_a := (d->>'net_salary')::numeric;
  net_b := (d2->>'net_salary')::numeric;
  ecart := round(net_b - net_a, 2);
  PERFORM _rec('T04', 'une autre déduction de 120 € est retranchée du net à payer',
    ecart = 120, format('avec=%s sans=%s écart=%s (120 attendu)', net_a, net_b, ecart));

  -- T05 — plusieurs éléments (341). 04/10/2026 : assertion RÉÉCRITE (verdict
  -- précédent : brut = 3235, titres et transport comptés au brut). Seule la
  -- prime entre dans le brut ; les titres et le transport restent dans leurs
  -- limites.
  d := _lot321('T05', 2500, jsonb_build_array(
    jsonb_build_object('type','bonus','libelle','prime','montant',500),
    jsonb_build_object('type','meal_vouchers','libelle','titres-restaurant','qte',20,'pu',10,'montant',80),
    jsonb_build_object('type','transport_allowance','libelle','abonnement transports','qte',1,'pu',150,'montant',75),
    jsonb_build_object('type','other_deductions','libelle','avance sur prime','montant',120)));
  brut := (d->>'total_gross')::numeric;
  PERFORM _rec('T05', 'plusieurs éléments : seule la prime entre dans le brut (3 000 €), titres et transport restent hors brut',
    brut = 3000 AND (d->>'mealVouchersReintegrated')::numeric = 0 AND (d->>'transportReintegrated')::numeric = 0,
    format('brut=%s (3000 attendu) réintégré titres=%s transport=%s', brut, d->>'mealVouchersReintegrated', d->>'transportReintegrated'));

  -- T06 — sans élément variable, rien n'est inventé (non-régression)
  d := _lot321('T06', 2500, '[]'::jsonb);
  brut := (d->>'total_gross')::numeric;
  PERFORM _rec('T06', 'sans élément variable, le brut est celui de la fiche (2 500 €)',
    brut = 2500, format('brut=%s (2500 attendu)', brut));

  -- T07 — titres-restaurant AU-DELÀ du plafond (341). 20 titres de 14 €, part
  -- salariale 100 € → part patronale 9,00 € par titre (64 %). Limite la plus
  -- basse : min(7,32 € ; 60 % × 14 = 8,40 €) = 7,32 €. Excédent : 1,68 € × 20 =
  -- 33,60 €, réintégré au brut.
  d := _lot321('T07', 2500, jsonb_build_array(
    jsonb_build_object('type','meal_vouchers','libelle','titres-restaurant','qte',20,'pu',14,'montant',100)));
  brut := (d->>'total_gross')::numeric;
  PERFORM _rec('T07', 'titres-restaurant au-delà du plafond 2026 (7,32 €) : l''excédent de part patronale (33,60 €) entre dans le brut',
    brut = 2533.60 AND (d->>'mealVouchersReintegrated')::numeric = 33.60 AND (d->>'mealVouchersEmployerShare')::numeric = 180,
    format('brut=%s (2533,60) réintégré=%s (33,60) part patronale=%s (180)', brut, d->>'mealVouchersReintegrated', d->>'mealVouchersEmployerShare'));

  -- T08 — transport AU-DELÀ de la part exonérée (341). Abonnement de 100 €,
  -- pris en charge à 90 € : 75 € exonérés, 15 € réintégrés au brut.
  d := _lot321('T08', 2500, jsonb_build_array(
    jsonb_build_object('type','transport_allowance','libelle','abonnement transports','qte',1,'pu',100,'montant',90)));
  brut := (d->>'total_gross')::numeric;
  PERFORM _rec('T08', 'transport au-delà de 75 % du coût de l''abonnement : l''excédent (15 €) entre dans le brut',
    brut = 2515 AND (d->>'transportReintegrated')::numeric = 15,
    format('brut=%s (2515) réintégré=%s (15)', brut, d->>'transportReintegrated'));

  -- T09 — les deux paramètres sont DATÉS et SOURCÉS
  PERFORM _rec('T09', 'les deux paramètres légaux 2026 sont en base, datés du 01/01/2026 et sourcés (7,32 € ; 75 %)',
    (SELECT count(*) FROM payroll_legal_parameters
      WHERE tenant_id IS NULL AND country_code = 'FR' AND valid_from = DATE '2026-01-01'
        AND btrim(COALESCE(source, '')) <> ''
        AND ((code = 'TITRE_RESTAURANT_EXO_MAX' AND value = 7.32)
          OR (code = 'TRANSPORT_PUBLIC_EXO_PCT' AND value = 75))) = 2,
    'paramètres TITRE_RESTAURANT_EXO_MAX et TRANSPORT_PUBLIC_EXO_PCT');
END $$;

DROP FUNCTION _lot321(text, numeric, jsonb);
SELECT _audit_assert('321');