-- ============================================================
-- 350_distribution_grill_references_tests.sql — tâche 2.13 (G2)
--
--   T01  une grille sur un compte qui n'existe pas (706999) est refusée
--   T02  une ligne vers une section qui n'existe pas (ZZZ99) est refusée
--   T03  une grille correcte s'enregistre, et renommer la section suit
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '350', false);
DELETE FROM _audit_results WHERE file = '350';

DO $$
DECLARE
  t uuid := _mk_tenant('P2G2T01', false);
  g uuid; v_compte boolean := false; v_section boolean := false; v_code text;
BEGIN
  INSERT INTO chart_accounts (tenant_id, code, name, type) VALUES (t, '70699001', 'Prestations (test)', 'income');
  INSERT INTO analytic_sections (tenant_id, code, name, active) VALUES (t, 'PIL01', 'Pilote 01', true);
  PERFORM _as_user();

  BEGIN
    INSERT INTO distribution_grills (tenant_id, name, account_code, active) VALUES (t, 'Grille fantôme', '70699999', true);
  EXCEPTION WHEN foreign_key_violation THEN v_compte := true;
  END;
  PERFORM _rec('T01', 'une grille sur un compte qui n''existe pas est refusée',
    v_compte, format('refus=%s', v_compte));

  INSERT INTO distribution_grills (tenant_id, name, account_code, active) VALUES (t, 'Grille pilote', '70699001', true) RETURNING id INTO g;
  BEGIN
    INSERT INTO distribution_grill_lines (tenant_id, grill_id, section_code, percentage) VALUES (t, g, 'ZZZ99', 100);
  EXCEPTION WHEN foreign_key_violation THEN v_section := true;
  END;
  PERFORM _rec('T02', 'une ligne vers une section qui n''existe pas est refusée',
    v_section, format('refus=%s', v_section));

  INSERT INTO distribution_grill_lines (tenant_id, grill_id, section_code, percentage) VALUES (t, g, 'PIL01', 100);
  EXECUTE 'RESET ROLE';
  UPDATE analytic_sections SET code = 'PIL01-B' WHERE tenant_id = t AND code = 'PIL01';
  SELECT section_code INTO v_code FROM distribution_grill_lines WHERE tenant_id = t AND grill_id = g;
  PERFORM _rec('T03', 'une grille correcte s''enregistre, et renommer la section suit sur la ligne',
    v_code = 'PIL01-B', format('section de la ligne après renommage=%s', v_code));
EXCEPTION WHEN OTHERS THEN
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T01', 'T01 à T03 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

SELECT _audit_assert('350');
