-- ============================================================
-- 311_pay_run_slip_generation_tests.sql — recette /qa du 29/09/2026
--
--   rh-006 🔴 « Générer les bulletins » ne génère aucun bulletin : l'écran crée
--            le lot (POST pay_runs) et s'arrête ; `pay_slips` reste à 0 et le
--            lot affiche 0 salarié / 0,00 €. Aucun écran ne produisait de
--            bulletin — la paie entière était intestable.
--   rh-006 🔴 « Valider la préparation » n'émettait aucune requête : un lot VIDE
--            s'approuvait, et `approved` est le feu vert de l'écriture de paie.
--
-- Ce fichier tient la fermeture : un lot se génère par UN appel, le verdict est
-- nommé par salarié, le lot porte les totaux de ses bulletins, un lot vide ne
-- s'approuve pas, et rien de tout cela ne franchit une frontière de société.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '311', false);
DELETE FROM _audit_results WHERE file = '311';

-- T01 — un lot neuf pour 3 salariés actifs produit 3 bulletins, et le lot porte
--       exactement les totaux de ses bulletins (275 tient l'agrégat).
DO $$
DECLARE
  t uuid; r uuid; res jsonb;
  n int; nb int; brut numeric; net numeric; s_brut numeric; s_net numeric;
BEGIN
  t := _mk_tenant('QA311A');
  INSERT INTO employees (tenant_id, name, employee_number, base_salary, hire_date, status, contract_type, payroll_category)
  VALUES (t, 'Salarié A QA311', 'QA311-A', 1823.03, '2026-01-01', 'active', 'cdi', 'non_cadre'),
         (t, 'Salarié B QA311', 'QA311-B', 2500.00, '2026-01-01', 'active', 'cdi', 'non_cadre'),
         (t, 'Salarié C QA311', 'QA311-C', 4500.00, '2026-01-01', 'active', 'cdi', 'cadre');
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status)
  VALUES (t, 'PR-QA311-A', '2026-02-01', '2026-02-28', '2026-02-28', 'draft') RETURNING id INTO r;

  PERFORM _as_user();
  res := generate_pay_run_slips(r);
  EXECUTE 'RESET ROLE';

  SELECT count(*) INTO n FROM pay_slips
  WHERE tenant_id = t AND pay_run_id = r AND status IS DISTINCT FROM 'cancelled';
  SELECT gross_total, net_total, employee_count INTO brut, net, nb FROM pay_runs WHERE id = r;
  SELECT COALESCE(sum(COALESCE(NULLIF(total_gross, 0), gross_salary)), 0),
         COALESCE(sum(net_salary), 0)
    INTO s_brut, s_net
  FROM pay_slips
  WHERE tenant_id = t AND pay_run_id = r AND status IS DISTINCT FROM 'cancelled';

  PERFORM _rec('T01', 'un lot de 3 salariés produit 3 bulletins, et le lot porte leurs totaux',
    COALESCE((res ->> 'generes')::int, 0) = 3
      AND n = 3 AND nb = 3
      AND round(brut, 2) = round(s_brut, 2)
      AND round(net, 2) = round(s_net, 2)
      AND brut > 0 AND net > 0,
    format('verdict=%s bulletins, en base=%s, lot brut=%s / %s salarié(s), somme des bulletins=%s net=%s',
           res ->> 'generes', n, brut, nb, s_brut, net));
END $$;

-- T02 — un lot SANS bulletin ne s'approuve pas (le « Valider » placebo rendait
--       cet état possible, et l'écriture de paie s'en servait).
DO $$
DECLARE t uuid; r uuid; err text := 'accepté'; st text;
BEGIN
  t := _mk_tenant('QA311B');
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status)
  VALUES (t, 'PR-QA311-B', '2026-02-01', '2026-02-28', '2026-02-28', 'draft') RETURNING id INTO r;

  PERFORM _as_user();
  BEGIN
    UPDATE pay_runs SET status = 'approved' WHERE id = r;
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  EXECUTE 'RESET ROLE';

  SELECT status INTO st FROM pay_runs WHERE id = r;
  PERFORM _rec('T02', 'un lot vide ne s''approuve pas',
    err <> 'accepté' AND st <> 'approved',
    format('approbation : %s ; statut en base : %s', err, st));
END $$;

-- T03 — le garde-fou n'est pas un mur : un lot AVEC bulletins s'approuve
DO $$
DECLARE t uuid; r uuid; res jsonb; st text; err text := '—';
BEGIN
  t := _mk_tenant('QA311C');
  INSERT INTO employees (tenant_id, name, employee_number, base_salary, hire_date, status, contract_type)
  VALUES (t, 'Salarié T03', 'QA311-T03', 2500.00, '2026-01-01', 'active', 'cdi');
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status)
  VALUES (t, 'PR-QA311-C', '2026-02-01', '2026-02-28', '2026-02-28', 'draft') RETURNING id INTO r;

  PERFORM _as_user();
  res := generate_pay_run_slips(r);
  BEGIN
    UPDATE pay_runs SET status = 'approved' WHERE id = r;
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  EXECUTE 'RESET ROLE';

  SELECT status INTO st FROM pay_runs WHERE id = r;
  PERFORM _rec('T03', 'un lot qui porte ses bulletins s''approuve',
    COALESCE((res ->> 'generes')::int, 0) = 1 AND st = 'approved',
    format('%s bulletin(s) généré(s), statut=%s, erreur=%s', res ->> 'generes', st, err));
END $$;

-- T04 — isolation : le lot d'une AUTRE société ne se génère pas
DO $$
DECLARE tb uuid; ta uuid; rb uuid; err text := 'accepté'; errcode text := '—';
BEGIN
  tb := _mk_tenant('QA311D');                 -- société B : son lot
  INSERT INTO employees (tenant_id, name, employee_number, base_salary, hire_date, status, contract_type)
  VALUES (tb, 'Salarié de B', 'QA311-B1', 2500.00, '2026-01-01', 'active', 'cdi');
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status)
  VALUES (tb, 'PR-QA311-D', '2026-02-01', '2026-02-28', '2026-02-28', 'draft') RETURNING id INTO rb;

  ta := _mk_tenant('QA311E');                 -- le contexte bascule sur A
  PERFORM _as_user();
  BEGIN
    PERFORM generate_pay_run_slips(rb);
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; errcode := SQLSTATE;
  END;
  EXECUTE 'RESET ROLE';

  PERFORM _rec('T04', 'la société A ne génère pas les bulletins du lot de la société B',
    err <> 'accepté' AND errcode = '23503',
    format('%s (sqlstate %s)', left(err, 120), errcode));
END $$;

-- T05 — seuls les salariés ACTIFS reçoivent un bulletin (un salarié parti ne
--       produit pas de paie en silence).
DO $$
DECLARE t uuid; r uuid; res jsonb; n int;
BEGIN
  t := _mk_tenant('QA311F');
  INSERT INTO employees (tenant_id, name, employee_number, base_salary, hire_date, status, contract_type)
  VALUES (t, 'Actif 1 QA311', 'QA311-F1', 2000.00, '2026-01-01', 'active', 'cdi'),
         (t, 'Actif 2 QA311', 'QA311-F2', 2600.00, '2026-01-01', 'active', 'cdi'),
         (t, 'Parti QA311', 'QA311-F3', 3000.00, '2020-01-01', 'inactive', 'cdi');
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status)
  VALUES (t, 'PR-QA311-F', '2026-02-01', '2026-02-28', '2026-02-28', 'draft') RETURNING id INTO r;

  PERFORM _as_user();
  res := generate_pay_run_slips(r);
  EXECUTE 'RESET ROLE';

  SELECT count(*) INTO n FROM pay_slips WHERE tenant_id = t AND pay_run_id = r;
  PERFORM _rec('T05', 'les salariés inactifs ne reçoivent pas de bulletin',
    n = 2 AND COALESCE((res ->> 'total')::int, 0) = 2,
    format('%s bulletin(s) en base, %s salarié(s) examiné(s) (2 attendus)', n, res ->> 'total'));
END $$;

-- T06 — le droit est opposable : un `viewer` ne génère pas de bulletin (la
--       garde est dans la fonction, pas seulement dans la politique RLS).
DO $$
DECLARE t uuid; r uuid; err text := 'accepté'; errcode text := '—'; n int;
BEGIN
  t := _mk_tenant('QA311G');
  INSERT INTO employees (tenant_id, name, employee_number, base_salary, hire_date, status, contract_type)
  VALUES (t, 'Salarié T06', 'QA311-G1', 2500.00, '2026-01-01', 'active', 'cdi');
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status)
  VALUES (t, 'PR-QA311-G', '2026-02-01', '2026-02-28', '2026-02-28', 'draft') RETURNING id INTO r;
  UPDATE tenant_users SET role = 'viewer' WHERE tenant_id = t;

  PERFORM _as_user();
  BEGIN
    PERFORM generate_pay_run_slips(r);
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; errcode := SQLSTATE;
  END;
  EXECUTE 'RESET ROLE';

  SELECT count(*) INTO n FROM pay_slips WHERE tenant_id = t AND pay_run_id = r;
  PERFORM _rec('T06', 'un lecteur ne génère pas les bulletins de paie',
    err <> 'accepté' AND errcode = '42501' AND n = 0,
    format('%s (sqlstate %s), %s bulletin(s) créé(s)', left(err, 110), errcode, n));
END $$;

-- T07 — le salarié « Admin » de l'inscription (sans salaire) ne reçoit pas de
--       bulletin à 0,00 € (défaut trouvé par le banc écran, X0).
DO $$
DECLARE t uuid; r uuid; res jsonb; n int; msg text;
BEGIN
  t := _mk_tenant('QA311H');
  INSERT INTO employees (tenant_id, name, employee_number, base_salary, hire_date, status, contract_type)
  VALUES (t, 'Admin', 'QA311-H0', NULL, '2026-01-01', 'active', 'cdi'),
         (t, 'Salarié payé', 'QA311-H1', 2500.00, '2026-01-01', 'active', 'cdi');
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status)
  VALUES (t, 'PR-QA311-H', '2026-02-01', '2026-02-28', '2026-02-28', 'draft') RETURNING id INTO r;

  PERFORM _as_user();
  res := generate_pay_run_slips(r);
  EXECUTE 'RESET ROLE';

  SELECT count(*) INTO n FROM pay_slips WHERE tenant_id = t AND pay_run_id = r;
  SELECT e ->> 'message' INTO msg FROM jsonb_array_elements(res -> 'echecs') e;
  PERFORM _rec('T07', 'un salarié sans salaire ne reçoit pas de bulletin à 0,00 €',
    n = 1 AND COALESCE((res ->> 'generes')::int, 0) = 1 AND msg = 'salaire non renseigné — aucun bulletin',
    format('%s bulletin(s) en base, %s généré(s), refus : %s', n, res ->> 'generes', msg));
END $$;

SELECT _audit_assert('311');



