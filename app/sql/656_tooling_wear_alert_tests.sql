-- ============================================================
-- 656_tooling_wear_alert_tests.sql — PRD-11 / E.4
--
-- Mesuré AVANT la 656 : aucune fonction n'alertait à l'approche de la fin de vie
-- d'un outillage, alors que les compteurs sont en base.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '656', false);
DELETE FROM _audit_results WHERE file = '656';

CREATE OR REPLACE FUNCTION _mk656(p_nom text, OUT t uuid) LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom, false);
END $$;

CREATE OR REPLACE FUNCTION _tool656(p_t uuid, p_code text, p_max int, p_cur int) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid;
BEGIN
  INSERT INTO toolings (tenant_id, code, name, max_pieces, current_counter)
  VALUES (p_t, p_code, 'Outil ' || p_code, p_max, p_cur) RETURNING id INTO v;
  RETURN v;
END $$;

-- T01 — 95 % de la durée de vie déclenche l'alerte
DO $$
DECLARE t uuid; v uuid; n int; r numeric;
BEGIN
  SELECT * INTO t FROM _mk656('VAL656T01');
  v := _tool656(t, 'T01', 1000, 950);
  SELECT count(*), max(wear_ratio) INTO n, r FROM tooling_wear_alert() WHERE tooling_id = v;
  PERFORM _rec('T01', 'un outillage à 95 % de sa durée de vie déclenche l''alerte', (n = 1 AND r = 0.9500), format('lignes=%s, ratio=%s (0.95 attendu)', n, r));
END $$;

-- T02 — 90 % ne déclenche rien
DO $$
DECLARE t uuid; v uuid; n int;
BEGIN
  SELECT * INTO t FROM _mk656('VAL656T02');
  v := _tool656(t, 'T02', 1000, 900);
  SELECT count(*) INTO n FROM tooling_wear_alert() WHERE tooling_id = v;
  PERFORM _rec('T02', 'un outillage à 90 % ne déclenche pas d''alerte', n = 0, format('lignes=%s (0 attendu)', n));
END $$;

-- T03 — une durée de vie nulle (max 0) ne divise pas par zéro et n'alerte pas
DO $$
DECLARE t uuid; v uuid; n int;
BEGIN
  SELECT * INTO t FROM _mk656('VAL656T03');
  v := _tool656(t, 'T03', 0, 10);
  SELECT count(*) INTO n FROM tooling_wear_alert() WHERE tooling_id = v;
  PERFORM _rec('T03', 'un outillage sans durée de vie (max 0) n''alerte pas', n = 0, format('lignes=%s (0 attendu)', n));
END $$;

SELECT _audit_assert('656');
