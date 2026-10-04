-- ============================================================
-- 79_current_tenant_priority.sql
--
-- SEC-03 (durcissement): rend current_tenant_id() déterministe.
-- L'ancienne version utilisait LIMIT 1 sans ORDER BY sur un
-- UNION ALL : PostgreSQL ne garantit pas l'ordre sans ORDER BY.
-- Cette version donne une priorité explicite :
--   prio 1 = en-tête x-tenant-id (fiable derrière le pooler)
--   prio 2 = GUC app.active_tenant_id (session locale)
-- Les deux candidats restent validés contre tenant_users :
-- aucune fuite inter-tenant possible.
-- ============================================================

CREATE OR REPLACE FUNCTION current_tenant_id()
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT c.tid
  FROM (
    -- prio 1 : en-tête x-tenant-id (transmis par PostgREST)
    SELECT 1 AS prio,
           NULLIF(
             current_setting('request.headers', true)::json->>'x-tenant-id',
             ''
           )::uuid AS tid
    UNION ALL
    -- prio 2 : GUC de session (set_config via set_active_tenant)
    SELECT 2 AS prio,
           NULLIF(current_setting('app.active_tenant_id', true), '')::uuid AS tid
  ) c
  WHERE c.tid IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM tenant_users
      WHERE auth_id = auth.uid()
        AND status = 'active'
        AND tenant_id = c.tid
    )
  ORDER BY c.prio
  LIMIT 1
$$;
