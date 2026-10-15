-- ============================================================
-- 656_tooling_wear_alert.sql — PRD-11 / E.4 (partie E)
-- Numéro pris le 2026-10-06 par migration-numero.mjs (ligne « plan6 E (opérations) », branche plan6/e-operations).
--
-- Constat : `toolings` porte `max_pieces`, `initial_counter` et `current_counter`
-- (l'usure d'outillage est modélisée, c'est un point fort) — mais **aucune
-- fonction n'alerte** à l'approche de la fin de vie (critère PRD-11 : « un
-- outillage atteignant 95 % de sa durée de vie déclenche une alerte »).
--
-- Décision : une fonction de lecture `tooling_wear_alert()` — les outillages à
-- 95 % ou plus de leur durée de vie. L'incrémentation automatique du compteur à
-- la production et le blocage du lancement d'OF restent à faire (PRD-06/PRD-11).
-- ============================================================

CREATE OR REPLACE FUNCTION tooling_wear_alert()
RETURNS TABLE(
  tooling_id uuid,
  tooling_code text,
  tooling_name text,
  machine_name text,
  current_counter int,
  max_pieces int,
  wear_ratio numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT
    t.id AS tooling_id,
    t.code AS tooling_code,
    t.name AS tooling_name,
    m.name AS machine_name,
    COALESCE(t.current_counter, 0) AS current_counter,
    t.max_pieces,
    ROUND(COALESCE(t.current_counter, 0)::numeric / t.max_pieces, 4) AS wear_ratio
  FROM toolings t
  LEFT JOIN machines m ON m.id = t.machine_id AND m.tenant_id = t.tenant_id
  WHERE t.tenant_id = current_tenant_id()
    AND COALESCE(t.max_pieces, 0) > 0
    AND COALESCE(t.current_counter, 0) >= 0.95 * t.max_pieces
  ORDER BY (COALESCE(t.current_counter, 0)::numeric / t.max_pieces) DESC;
$$;

COMMENT ON FUNCTION tooling_wear_alert() IS
  'PRD-11 (656) : les outillages à 95 % ou plus de leur durée de vie (current_counter / max_pieces).';

REVOKE ALL ON FUNCTION tooling_wear_alert() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION tooling_wear_alert() TO authenticated;

