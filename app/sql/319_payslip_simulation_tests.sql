-- ============================================================
-- 319_payslip_simulation_tests.sql — lot C (paie), C2 / rh-005
--
-- Recette /qa du 29/09/2026. Le simulateur de paie (« Simuler ») recalculait
-- tout en TypeScript (`src/lib/payroll.ts`) : c'était un SECOND moteur, avec
-- ses propres taux. Mesuré par la recette : 2 500 € brut donnaient 1 798,53 €
-- au simulateur contre **1 919,53 €** au moteur de la base (bulletin d'or de la
-- 276) — 121,00 € d'écart, et le chômage salarial compté, la CRDS absente, le
-- net imposable confondu avec le net, aucun traitement cadre, et un total
-- patronal différent de la somme des rubriques.
--
-- Doctrine W5 (« un seul moteur par grandeur ») : le simulateur doit APPELER
-- le moteur. `simulate_payslip` est ce moteur en lecture — même calcul, mêmes
-- paramètres, même grille, et **aucune écriture**.
--
-- Mesuré sur la base de recette AVANT la 319 : les 4 scénarios sont ROUGES —
-- `simulate_payslip` n'existe pas (`42883`), donc rien ne peut être comparé au
-- moteur, et le simulateur affiche des nets que le moteur ne produit pas.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '319', false);
DELETE FROM _audit_results WHERE file = '319';

-- Calcul réel, puis simulation, pour le même salarié et la même période.
-- p_reel = false : on ne fait QUE la simulation (pour prouver qu'elle n'écrit
-- rien — sinon le calcul réel de l'apparié aurait déjà écrit un bulletin).
CREATE OR REPLACE FUNCTION _pair319(p_t uuid, p_name text, p_salary numeric, p_cadre boolean,
                                     p_period text, p_simulated numeric DEFAULT NULL,
                                     p_reel boolean DEFAULT true)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE e uuid; reel jsonb; simu jsonb;
BEGIN
  EXECUTE 'RESET ROLE';
  INSERT INTO employees (tenant_id, name, salary, status) VALUES (p_t, p_name, p_salary, 'active') RETURNING id INTO e;
  IF p_cadre THEN
    BEGIN EXECUTE 'UPDATE employees SET payroll_category = ''cadre'' WHERE id = $1' USING e;
    EXCEPTION WHEN undefined_column THEN NULL; END;
  END IF;
  PERFORM _as_user();
  reel := CASE WHEN p_reel THEN calculate_payslip(e, p_period, NULL)
               ELSE jsonb_build_object('success', true, 'skipped', true) END;
  -- Avant la 319, `simulate_payslip` n'existe pas : le scénario s'inscrit alors
  -- en rouge avec un motif, au lieu de faire tomber le fichier entier.
  BEGIN
    simu := simulate_payslip(e, COALESCE(p_simulated, p_salary), p_period);
  EXCEPTION WHEN undefined_function THEN
    simu := jsonb_build_object('success', false, 'error', 'simulate_payslip n''existe pas');
  END;
  EXECUTE 'RESET ROLE';
  RETURN jsonb_build_object('reel', reel, 'simu', simu, 'employee_id', e);
END $$;

-- Les trois bulletins d'or de la 276, rejoués par le simulateur.
DO $$
DECLARE t uuid; p jsonb;
BEGIN
  t := _mk_tenant('C2');
  INSERT INTO payroll_legal_parameters (tenant_id, country_code, code, value, valid_from)
    VALUES (t, 'FR', 'TAUX_ATMP', 1.00, '2026-01-01');

  -- T01 : les trois bulletins d'or — le simulateur rend les mêmes nets, au centime
  p := _pair319(t, 'Salarié SMIC', 1867.02, false, '2026-09');
  PERFORM _rec('T01', 'le simulateur rend le bulletin d''or SMIC (1 867,02 €) : net 1 477,93',
    (p#>'{simu,net_salary}')::numeric = 1477.93 AND (p#>'{simu,success}')::boolean,
    format('simulé net=%s (1477,93 attendu) erreur=%s', p#>'{simu,net_salary}', coalesce(p#>>'{simu,error}', '—')));

  p := _pair319(t, 'Salarié 2 500', 2500, false, '2026-09');
  PERFORM _rec('T02', 'le simulateur rend le bulletin d''or 2 500 € : net 1 919,53',
    (p#>'{simu,net_salary}')::numeric = 1919.53 AND (p#>'{simu,success}')::boolean,
    format('simulé net=%s (1919,53 attendu) erreur=%s', p#>'{simu,net_salary}', coalesce(p#>>'{simu,error}', '—')));

  p := _pair319(t, 'Cadre 4 500', 4500, true, '2026-09');
  PERFORM _rec('T03', 'le simulateur rend le bulletin d''or 4 500 € cadre : net 3 121,70',
    (p#>'{simu,net_salary}')::numeric = 3121.70 AND (p#>'{simu,success}')::boolean,
    format('simulé net=%s (3121,70 attendu) erreur=%s', p#>'{simu,net_salary}', coalesce(p#>>'{simu,error}', '—')));

  -- T04 : simulation et calcul réel, même centime, sur toutes les grandeurs
  p := _pair319(t, 'Salarié 2 500 (comparaison)', 2500, false, '2026-09');
  PERFORM _rec('T04', 'sur toutes les grandeurs, la simulation est identique au calcul réel au centime',
    (p#>'{simu,total_gross}')::numeric = (p#>'{reel,total_gross}')::numeric
    AND (p#>'{simu,social_security_employee}')::numeric = (p#>'{reel,social_security_employee}')::numeric
    AND (p#>'{simu,net_taxable}')::numeric = (p#>'{reel,net_taxable}')::numeric
    AND (p#>'{simu,income_tax}')::numeric = (p#>'{reel,income_tax}')::numeric
    AND (p#>'{simu,net_salary}')::numeric = (p#>'{reel,net_salary}')::numeric
    AND (p#>'{simu,employer_contributions}')::numeric = (p#>'{reel,employer_contributions}')::numeric
    AND (p#>'{simu,reduction_generale}')::numeric = (p#>'{reel,reduction_generale}')::numeric,
    format('réel net=%s / simulé net=%s | réel brut=%s / simulé brut=%s',
      p#>'{reel,net_salary}', p#>'{simu,net_salary}', p#>'{reel,total_gross}', p#>'{simu,total_gross}'));
END $$;

-- T05 : une simulation n'écrit rien (elle n'est pas un bulletin)
DO $$
DECLARE t uuid; e uuid; n_slips int; n_clar int; p jsonb;
BEGIN
  t := _mk_tenant('C2bis');
  INSERT INTO payroll_legal_parameters (tenant_id, country_code, code, value, valid_from)
    VALUES (t, 'FR', 'TAUX_ATMP', 1.00, '2026-01-01');
  -- T05 : la simulation SEULE, le calcul réel n'est pas fait (sinon c'est lui
  -- qui aurait écrit un bulletin, et le scénario ne prouverait plus rien).
  p := _pair319(t, 'Salarié simulé', 2000, false, '2026-09', 2500, false);
  e := (p->>'employee_id')::uuid;

  SELECT count(*) INTO n_slips FROM pay_slips WHERE tenant_id = t AND employee_id = e;
  SELECT count(*) INTO n_clar FROM pay_slip_clarified WHERE tenant_id = t AND employee_id = e;
  PERFORM _rec('T05', 'simuler n''écrit aucun bulletin',
    n_slips = 0 AND n_clar = 0,
    format('pay_slips=%s pay_slip_clarified=%s (0 attendu)', n_slips, n_clar));

  -- T06 : la simulation part du salaire SIMULÉ, pas de celui de la fiche
  PERFORM _rec('T06', 'simuler 2 500 € pour un salarié Paid 2 000 € rend le net des 2 500 €',
    (p#>'{simu,net_salary}')::numeric = 1919.53 AND (p#>'{simu,gross_salary}')::numeric = 2500,
    format('net=%s brut=%s (1919,53 / 2500 attendus)', p#>'{simu,net_salary}', p#>'{simu,gross_salary}'));
END $$;

DROP FUNCTION _pair319(uuid, text, numeric, boolean, text, numeric, boolean);
SELECT _audit_assert('319');
