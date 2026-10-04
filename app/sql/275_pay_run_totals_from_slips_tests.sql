-- ============================================================
-- 275_pay_run_totals_from_slips_tests.sql — vague X3 / C5, C7
-- (audit fonctionnel exécuté du 28/09/2026)
--
-- MESURÉ AVANT, par le chemin de l'écran :
--   C5  le formulaire de lot envoyait `employer_contributions_total` (colonne
--       absente) : AUCUN lot ne se créait (W06) ;
--   C7  les totaux du lot étaient calculés par l'ÉCRAN avec un barème marocain
--       (CNSS 4,48 % plafonnée à 6 000, AMO 2,26 %, IR marocain) : sur deux
--       salariés à 2 500 et 4 000, le lot affichait un net de 5 938,86 pour
--       4 199,13 de nets aux bulletins (H05).
--
--   T01 un lot créé avec des totaux les voit remis à zéro (la base les tient)
--   T02 deux bulletins → brut, net, retenues et effectif du lot = leurs sommes
--   T03 un bulletin annulé ou supprimé sort des totaux
--   T04 un appel direct ne réécrit pas les totaux d'un lot
--   T05 aucune des 13 tables de paie qui portent de l'argent n'a de politique
--       d'écriture sans `can_perform` ; un lecteur n'écrit pas le pont paie →
--       grand livre (M8, masqué jusqu'à ce qu'un lot puisse être comptabilisé)
--
-- T01–T05 sont ROUGES avant la 275.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '275', false);
DELETE FROM _audit_results WHERE file = '275';

DO $$
DECLARE t uuid; e1 uuid; e2 uuid; r uuid; s1 uuid; s2 uuid; x record; y record; z record; w record;
BEGIN
  t := _mk_tenant('X3C7');
  INSERT INTO employees (tenant_id, name, salary, status) VALUES (t, 'Salarié 1', 2500, 'active') RETURNING id INTO e1;
  INSERT INTO employees (tenant_id, name, salary, status) VALUES (t, 'Salarié 2', 4000, 'active') RETURNING id INTO e2;
  PERFORM _as_user();
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status, gross_total, tax_total, net_total, employee_count)
  VALUES (t, 'PAY-X3', '2026-09-01', '2026-09-30', '2026-09-30', 'draft', 6500, 561.14, 5938.86, 2) RETURNING id INTO r;
  EXECUTE 'RESET ROLE';
  SELECT gross_total, net_total, tax_total, employee_count INTO x FROM pay_runs WHERE id = r;
  PERFORM _rec('T01', 'un lot créé avec des totaux les voit remis à zéro (la base les tient)',
    x.gross_total = 0 AND x.net_total = 0 AND x.tax_total = 0 AND x.employee_count = 0,
    format('brut=%s net=%s retenues=%s effectif=%s', x.gross_total, x.net_total, x.tax_total, x.employee_count));

  INSERT INTO pay_slips (tenant_id, number, employee_id, pay_run_id, period_start, period_end, gross_salary, net_salary, status)
  VALUES (t, 'BUL-1', e1, r, '2026-09-01', '2026-09-30', 2500, 1950.10, 'draft') RETURNING id INTO s1;
  INSERT INTO pay_slips (tenant_id, number, employee_id, pay_run_id, period_start, period_end, gross_salary, net_salary, status)
  VALUES (t, 'BUL-2', e2, r, '2026-09-01', '2026-09-30', 4000, 3110.25, 'draft') RETURNING id INTO s2;
  SELECT gross_total, net_total, tax_total, employee_count INTO y FROM pay_runs WHERE id = r;
  PERFORM _rec('T02', 'deux bulletins : brut, net, retenues et effectif du lot = leurs sommes',
    y.gross_total = 6500 AND y.net_total = 5060.35 AND y.tax_total = 1439.65 AND y.employee_count = 2,
    format('brut=%s net=%s retenues=%s effectif=%s', y.gross_total, y.net_total, y.tax_total, y.employee_count));

  UPDATE pay_slips SET status = 'cancelled' WHERE id = s2;
  SELECT net_total, employee_count INTO z FROM pay_runs WHERE id = r;
  DELETE FROM pay_slips WHERE id = s1;
  SELECT net_total, employee_count INTO w FROM pay_runs WHERE id = r;
  PERFORM _rec('T03', 'un bulletin annulé puis un bulletin supprimé sortent des totaux',
    z.net_total = 1950.10 AND z.employee_count = 1 AND w.net_total = 0 AND w.employee_count = 0,
    format('après annulation : net=%s effectif=%s | après suppression : net=%s effectif=%s', z.net_total, z.employee_count, w.net_total, w.employee_count));

  INSERT INTO pay_slips (tenant_id, number, employee_id, pay_run_id, period_start, period_end, gross_salary, net_salary, status)
  VALUES (t, 'BUL-3', e1, r, '2026-09-01', '2026-09-30', 2500, 1950.10, 'draft');
  PERFORM _as_user();
  UPDATE pay_runs SET net_total = 1, gross_total = 1, employee_count = 99 WHERE id = r;
  EXECUTE 'RESET ROLE';
  SELECT gross_total, net_total, employee_count INTO x FROM pay_runs WHERE id = r;
  PERFORM _rec('T04', 'un appel direct ne réécrit pas les totaux d''un lot',
    x.gross_total = 2500 AND x.net_total = 1950.10 AND x.employee_count = 1,
    format('brut=%s net=%s effectif=%s', x.gross_total, x.net_total, x.employee_count));
END $$;

-- T05 — les tables de paie sous le rôle
DO $$
DECLARE t uuid; lec uuid; n int; ecrit text := 'refusé';
BEGIN
  t := _mk_tenant('X3M8');
  INSERT INTO auth.users (id, email) VALUES (uuid_generate_v4(), 'x3m8-lec@audit.test') RETURNING id INTO lec;
  INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status) VALUES (t, lec, 'x3m8-lec@audit.test', 'Lecteur', 'viewer', 'active');
  SELECT count(*) INTO n FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
  WHERE c.relname IN ('payroll_accounting_entries','payroll_account_mapping','payroll_components','payroll_component_rates',
                      'payroll_templates','payroll_tax_grids','payroll_tax_grid_lines','payroll_variable_elements',
                      'pay_recalls','salary_advances','sepa_payment_orders','dsn_declarations','payroll_archives')
    AND p.polcmd IN ('a','w','d','*') AND p.polpermissive
    AND coalesce(pg_get_expr(p.polqual, p.polrelid), '') || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') NOT LIKE '%can_perform%';
  PERFORM set_config('request.jwt.claim.sub', lec::text, false);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', lec, 'role', 'authenticated')::text, false);
  PERFORM _as_user();
  BEGIN
    INSERT INTO payroll_accounting_entries (tenant_id, number, period_date) VALUES (t, 'PAE-LEC', '2026-09-30');
    ecrit := 'ÉCRIT';
  EXCEPTION WHEN insufficient_privilege THEN ecrit := 'refusé';
    WHEN OTHERS THEN ecrit := 'autre : ' || SQLERRM;
  END;
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T05', 'tables de paie : 0 politique d''écriture sans can_perform ; un lecteur n''écrit pas le pont paie → grand livre',
    n = 0 AND ecrit = 'refusé', format('politiques non gardées : %s | lecteur sur payroll_accounting_entries : %s', n, ecrit));
END $$;

SELECT _audit_assert('275');
