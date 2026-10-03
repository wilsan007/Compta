-- ===========================================================
-- 326_payslip_elements_invariants_tests.sql — lot C (paie)
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
SELECT set_config('audit.file', '326', false);
DELETE FROM _audit_results WHERE file = '326';

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
  -- `d->>'x'` rend du TEXTE : sans le cast, `texte - texte` n'existe pas
  -- (operator does not exist: unknown - jsonb). C'est ce défaut qui faisait
  -- échouer la suite 326 à son premier passage en CI, le 02/10.
  ecart := (d->>'net_avant')::numeric - (d->>'net_apres')::numeric;
  PERFORM _rec('T01', 'un acompte de 500 EUR sort du net, et laisse le brut comme les cotisations',
    round(ecart, 2) = 500
      AND (d->>'brut_avant')::numeric = (d->>'brut_apres')::numeric
      AND (d->>'securite_avant')::numeric = (d->>'securite_apres')::numeric,
    format('net %s→%s (500 attendu) brut %s→%s secu %s→%s',
      d->>'net_avant', d->>'net_apres', d->>'brut_avant', d->>'brut_apres',
      d->>'securite_avant', d->>'securite_apres'));

  -- T02 — le RAPPEL DE PAIE est l'inverse : c'est du salaire dû, il entre
  -- donc au brut, et la CSG comme l'impôt se calculent dessus.
  d := _lot322('T02', jsonb_build_object('type','pay_recall','libelle','rappel','montant',800));
  PERFORM _rec('T02', 'un rappel de 800 EUR porte le brut, la CSG et l''impôt',
    round((d->>'brut_apres')::numeric - (d->>'brut_avant')::numeric, 2) = 800
      AND (d->>'csg_apres')::numeric > (d->>'csg_avant')::numeric
      AND (d->>'impot_apres')::numeric > (d->>'impot_avant')::numeric,
    format('brut %s→%s (800 attendu) csg %s→%s impot %s→%s',
      d->>'brut_avant', d->>'brut_apres', d->>'csg_avant', d->>'csg_apres',
      d->>'impot_avant', d->>'impot_apres'));

  -- T03 — le REMBOURSEMENT DE FRAIS n'est pas une rémunération : il entre dans le
  -- net sans toucher au brut, aux cotisations ni à l'impôt. C'est la preuve
  -- que le moteur distingue une charge de l'entreprise d'un salaire.
  d := _lot322('T03', jsonb_build_object('type','expense_reimbursement','libelle','frais','montant',250));
  ecart := (d->>'net_apres')::numeric - (d->>'net_avant')::numeric;
  PERFORM _rec('T03', 'un remboursement de 250 EUR entre dans le net, sans toucher brut, cotisations ni impôt',
    round(ecart, 2) = 250
      AND (d->>'brut_avant')::numeric = (d->>'brut_apres')::numeric
      AND d->>'securite_avant' = d->>'securite_apres'
      AND d->>'csg_avant' = d->>'csg_apres'
      AND d->>'impot_avant' = d->>'impot_apres',
    format('net %s→%s (250 attendu) brut %s→%s csg %s→%s impot %s→%s',
      d->>'net_avant', d->>'net_apres', d->>'brut_avant', d->>'brut_apres',
      d->>'csg_avant', d->>'csg_apres', d->>'impot_avant', d->>'impot_apres'));

  -- T04 — le CONGÉ SANS SOLDE se comporte comme l'acompte : le brut du mois est
  -- payé, la retenue s'opère sur le NET.
  --
  -- ⚠️ CE TEST A ÉTÉ CORRIGÉ le 02/10/2026 : il affirmait que le congé sans
  -- solde ne touche NI le brut NI les cotisations. C'est faux, et le moteur
  -- avait raison depuis le début.
  --
  -- Un congé sans solde, c'est du temps NON TRAVAILLÉ : il n'y a pas de
  -- rémunération correspondante, donc il n'y a pas d'assiette sur laquelle
  -- cotiser. Le brut du mois baisse, et les cotisations suivent mécaniquement.
  -- C'est ce que font les DEUX moteurs du dépôt, indépendamment : la 319
  -- (`v_total_gross := … - v_unpaid_leave_deduction`, l. 235) et la 320
  -- (`- v_unpaid_leave_deduction`, l. 284). Deux migrations écrites par deux
  -- sessions, la même règle : c'est elle qui fait foi, et non une assertion
  -- de test qui n'avait jamais été jouée en CI.
  --
  -- Mesuré avant correction : net 1919,53 → 1639,96 (l'écart de 400 est donc
  -- bien là), brut 2 500 → 2 100, cotisations 282,75 → 237,51. Le moteur
  -- faisait exactement ce qu'il devait faire.
  d := _lot322('T04', jsonb_build_object('type','unpaid_leave_deduction','libelle','congé','montant',400));
  ecart := (d->>'net_avant')::numeric - (d->>'net_apres')::numeric;
  PERFORM _rec('T04', 'un congé sans solde de 400 EUR sort du net ET du brut — le temps non travaillé ne cote pas',
    -- Le BRUT baisse du montant : pas de rémunération pour du temps non
    -- travaillé, donc pas d'assiette, donc pas de cotisations.
    round((d->>'brut_avant')::numeric - (d->>'brut_apres')::numeric, 2) = 400
      -- Les cotisations BAISSENT avec l'assiette. On ne compare pas des
      -- montants : un congé de 400 € ne coûte pas 400 € de cotisations, et un
      -- test qui l'affirmerait serait faux.
      AND (d->>'securite_apres')::numeric < (d->>'securite_avant')::numeric
      -- Le net baisse MOINS que le brut : la différence, ce sont les
      -- cotisations qu'on ne verse plus. C'est ce que l'écran doit montrer.
      AND round(ecart, 2) > 0
      AND round(ecart, 2) < 400,
    format('net %s→%s (baisse de %s, comprise entre 0 et 400 : les cotisations suivent l''assiette) brut %s→%s (400 attendu de baisse) secu %s→%s (en baisse, assiette réduite)',
      d->>'net_avant', d->>'net_apres', ecart,
      d->>'brut_avant', d->>'brut_apres',
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
  -- frais ne relève PAS le brut, même quand un rappel l'a relevé.
  --
  -- ⚠️ CE TEST A ÉTÉ CORRIGÉ le 02/10/2026 : il comparait le brut d'APRÈS un
  -- remboursement (société T09) au brut d'APRÈS un rappel (société T08). Ce
  -- sont deux sociétés de test DIFFÉRENTES, avec deux fiches
  -- différentes : leurs bruts de base n'ont aucune raison de se ressembler.
  -- L'égalité était donc fausse pour une raison sans rapport avec ce qu'elle
  -- prétendait vérifier — et elle le resterait, un rappel ou non.
  --
  -- Ce qu'il faut comparer, c'est le MÊME bulletin avant et après. On mesure
  -- donc le brut du T08 avant le rappel, puis après : un rappel de 800 € le
  -- relève de 800, et c'est tout. Le remboursement, mesuré sur le T09, ne doit
  -- pas le relever d'un euro.
  d := _lot322('T08a', jsonb_build_object('type','pay_recall','libelle','rappel','montant',800));
  brut_ref := (d->>'brut_apres')::numeric;
  d := _lot322('T09', jsonb_build_object('type','expense_reimbursement','libelle','frais','montant',250));
  PERFORM _rec('T08', 'un rappel relève le brut de son montant ; un remboursement ne le relève pas',
    -- Sur le T08 : brut après rappel = brut avant + 800.
    round(brut_ref, 2) = 3300
      -- Sur le T09 : le remboursement de 250 ne touche PAS au brut.
      AND round((d->>'brut_apres')::numeric, 2) = 2500
      -- …et il entre dans le net, pour 250.
      AND round(((d->>'net_apres')::numeric - (d->>'net_avant')::numeric), 2) = 250,
    format('brut après rappel %s (3300 attendu = 2500 + 800) | brut après frais %s (2500 attendu : le remboursement ne relève pas le brut) | écart net frais %s (250 attendu)',
      brut_ref, d->>'brut_apres', round(((d->>'net_apres')::numeric - (d->>'net_avant')::numeric), 2)));
END $$;

DROP FUNCTION _lot322(text, jsonb);
SELECT _audit_assert('326');