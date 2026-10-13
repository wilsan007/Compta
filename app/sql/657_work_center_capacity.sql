-- ============================================================
-- 657_work_center_capacity.sql — PRD-07 / E.4 (partie E)
-- Numéro pris le 2026-10-06 par migration-numero.mjs (ligne « plan6 E (opérations) », branche plan6/e-operations).
--
-- Constat : la **charge** existe déjà — `work_center_load_hours` (`416`, L17) lit
-- les créneaux planifiés et retire les heures des opérateurs absents. Mais la
-- **capacité** n'était lue par personne : ni `work_centers.capacity_hours_per_day`,
-- ni `work_center_calendars` (jours fermés, heures réellement disponibles). Sans
-- elle, aucune **surcharge** ne peut être constatée (critère PRD-07).
--
-- Décision : deux fonctions.
--   · `work_center_capacity(société, poste, jour)` — la capacité RÉELLE du jour :
--     `0` si le poste est fermé ou férié, sinon les heures du calendrier, sinon
--     `capacity_hours_per_day`. `0` si le poste ou le jour est inconnu : on ne
--     renvoie jamais une capacité inventée (même doctrine que `work_center_load_hours`).
--   · `work_center_capacity_load(début, fin)` — le croisement charge × capacité par
--     poste et par jour, avec le drapeau **surcharge** — c'est la donnée du graphe.
-- ============================================================

CREATE OR REPLACE FUNCTION work_center_capacity(
  p_tenant uuid,
  p_work_center uuid,
  p_day date
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_cal record;
  v_cap numeric;
BEGIN
  IF p_tenant IS NULL OR p_work_center IS NULL OR p_day IS NULL THEN
    RETURN 0;
  END IF;

  SELECT * INTO v_cal FROM work_center_calendars c
  WHERE c.tenant_id = p_tenant AND c.work_center_id = p_work_center AND c.date = p_day
  LIMIT 1;
  IF FOUND THEN
    IF COALESCE(v_cal.is_closed, false) OR COALESCE(v_cal.is_holiday, false) THEN
      RETURN 0;
    END IF;
    RETURN COALESCE(v_cal.available_hours, 0);
  END IF;

  SELECT COALESCE(wc.capacity_hours_per_day, 0) INTO v_cap FROM work_centers wc
  WHERE wc.id = p_work_center AND wc.tenant_id = p_tenant;
  RETURN COALESCE(v_cap, 0);
END $fn$;

CREATE OR REPLACE FUNCTION work_center_capacity_load(p_from date, p_to date)
RETURNS TABLE(
  work_center_id uuid,
  work_center_code text,
  work_center_name text,
  day date,
  capacity numeric,
  load numeric,
  overload boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT
    wc.id,
    wc.code,
    wc.name,
    d.day::date,
    work_center_capacity(wc.tenant_id, wc.id, d.day::date) AS capacity,
    work_center_load_hours(wc.tenant_id, wc.id, d.day::date) AS load,
    work_center_load_hours(wc.tenant_id, wc.id, d.day::date)
      > work_center_capacity(wc.tenant_id, wc.id, d.day::date) AS overload
  FROM work_centers wc
  CROSS JOIN generate_series(p_from, p_to, interval '1 day') AS d(day)
  WHERE wc.tenant_id = current_tenant_id()
    AND COALESCE(wc.active, true)
  ORDER BY wc.name, d.day;
$$;

COMMENT ON FUNCTION work_center_capacity(uuid, uuid, date) IS
  'PRD-07 (657) : la capacité RÉELLE d''un centre de charge pour un jour — 0 si fermé/férié, sinon les heures du calendrier, sinon capacity_hours_per_day.';
COMMENT ON FUNCTION work_center_capacity_load(date, date) IS
  'PRD-07 (657) : charge × capacité par poste et par jour, avec le drapeau surcharge (donnée du graphe charge/capacité).';

REVOKE ALL ON FUNCTION work_center_capacity(uuid, uuid, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION work_center_capacity_load(date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION work_center_capacity(uuid, uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION work_center_capacity_load(date, date) TO authenticated;


