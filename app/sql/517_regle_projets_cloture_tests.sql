-- ============================================================
-- 517_regle_projets_cloture_tests.sql — partie B, lot Projets, R-040, R-041, R-042
--
--   T01  projet COMPLÉTÉ → `projects.completed` + trace ;
--   T02  projet ANNULÉ → `projects.cancelled` ;
--   T03  projet EN ATTENTE → `projects.on_hold` ;
--   T04  IDEMPOTENCE — un rejeu n'émet pas un second événement.
-- \ir ci/audit_helpers.sql.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '517', false);
DELETE FROM _audit_results WHERE file = '517';

CREATE OR REPLACE FUNCTION _b517(p_nom text, OUT t uuid, OUT pr uuid)
LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO projects (tenant_id, name, status) VALUES (t, 'Projet ' || p_nom, 'active') RETURNING id INTO pr;
END $$;

DO $$
DECLARE x record; ne int; nt int;
BEGIN
  x := _b517('T01');
  PERFORM _as_user();
  UPDATE projects SET status = 'completed' WHERE id = x.pr;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'projects.completed' AND de.aggregate_id = x.pr;
  SELECT count(*) INTO nt FROM chain_traces ct
  WHERE ct.tenant_id = x.t AND ct.effet = 'project.completed' AND ct.amont_id = x.pr AND ct.resultat = 'applique';
  PERFORM _rec('T01', 'un projet complété émet projects.completed + trace',
    ne = 1 AND nt = 1, format('événements=%s trace=%s (1 / 1 attendus)', ne, nt));
END $$;

DO $$
DECLARE x record; ne int;
BEGIN
  x := _b517('T02');
  PERFORM _as_user();
  UPDATE projects SET status = 'cancelled' WHERE id = x.pr;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'projects.cancelled' AND de.aggregate_id = x.pr;
  PERFORM _rec('T02', 'un projet annulé émet projects.cancelled', ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

DO $$
DECLARE x record; ne int;
BEGIN
  x := _b517('T03');
  PERFORM _as_user();
  UPDATE projects SET status = 'on_hold' WHERE id = x.pr;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'projects.on_hold' AND de.aggregate_id = x.pr;
  PERFORM _rec('T03', 'un projet en attente émet projects.on_hold', ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

DO $$
DECLARE x record; ne int;
BEGIN
  x := _b517('T04');
  PERFORM _as_user();
  UPDATE projects SET status = 'completed' WHERE id = x.pr;
  UPDATE projects SET status = 'active'    WHERE id = x.pr;
  UPDATE projects SET status = 'completed' WHERE id = x.pr;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'projects.completed' AND de.aggregate_id = x.pr;
  PERFORM _rec('T04', 'un rejeu de « complété » n''émet pas un second événement',
    ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

SELECT _audit_assert('517');