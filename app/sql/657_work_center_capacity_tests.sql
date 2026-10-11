-- ============================================================
-- 657_work_center_capacity_tests.sql — PRD-07 / E.4
--
-- Mesuré AVANT la 657 : la charge existait (`work_center_load_hours`, 416) mais
-- aucune capacité n'était lue — donc aucune surcharge constatable.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '657', false);
DELETE FROM _audit_results WHERE file = '657';

CREATE OR REPLACE FUNCTION _mk657(p_nom text, OUT t uuid, OUT wc uuid) LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom, false);
  INSERT INTO work_centers (tenant_id, code, name, capacity_hours_per_day, cost_per_hour, active)
  VALUES (t, 'WC-' || p_nom, 'Poste ' || p_nom, 8, 50, true) RETURNING id INTO wc;
END $$;

-- T01 — sans calendrier, la capacité vaut capacity_hours_per_day (8)
DO $$
DECLARE t uuid; wc uuid; c numeric;
BEGIN
  SELECT * INTO t, wc FROM _mk657('VAL657T01');
  c := work_center_capacity(t, wc, CURRENT_DATE);
  PERFORM _rec('T01', 'sans calendrier, la capacité vaut capacity_hours_per_day (8)', c = 8, format('capacité=%s (8 attendu)', c));
END $$;

-- T02 — un jour fermé au calendrier donne une capacité nulle
DO $$
DECLARE t uuid; wc uuid; c numeric;
BEGIN
  SELECT * INTO t, wc FROM _mk657('VAL657T02');
  INSERT INTO work_center_calendars (tenant_id, work_center_id, date, is_closed) VALUES (t, wc, CURRENT_DATE, true);
  c := work_center_capacity(t, wc, CURRENT_DATE);
  PERFORM _rec('T02', 'un jour fermé au calendrier donne une capacité nulle', c = 0, format('capacité=%s (0 attendu)', c));
END $$;

-- T03 — les heures du calendrier priment sur la capacité par défaut
DO $$
DECLARE t uuid; wc uuid; c numeric;
BEGIN
  SELECT * INTO t, wc FROM _mk657('VAL657T03');
  INSERT INTO work_center_calendars (tenant_id, work_center_id, date, available_hours) VALUES (t, wc, CURRENT_DATE, 4);
  c := work_center_capacity(t, wc, CURRENT_DATE);
  PERFORM _rec('T03', 'les heures du calendrier priment sur la capacité par défaut (4)', c = 4, format('capacité=%s (4 attendu)', c));
END $$;

-- T04 — le croisement charge × capacité expose la capacité et la surcharge
DO $$
DECLARE t uuid; wc uuid; n int; cap numeric; ov boolean;
BEGIN
  SELECT * INTO t, wc FROM _mk657('VAL657T04');
  SELECT count(*), max(capacity), bool_or(overload) INTO n, cap, ov
  FROM work_center_capacity_load(CURRENT_DATE, CURRENT_DATE) WHERE work_center_id = wc;
  PERFORM _rec('T04', 'le croisement charge × capacité expose capacité et surcharge', (n = 1 AND cap = 8 AND ov = false), format('lignes=%s, capacité=%s, surcharge=%s', n, cap, ov));
END $$;

SELECT _audit_assert('657');
