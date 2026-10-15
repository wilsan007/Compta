-- ============================================================
-- 661_mo_operations_shop_floor.sql — PRD-06 / E.5 (partie E)
-- Numéro pris le 2026-10-11 par migration-numero.mjs (ligne « plan6 E (opérations) », branche plan6/e-operations).
--
-- `mo_operations` était une **coquille** : la table existait depuis la 126, rien
-- ne l'écrivait ni ne la lisait. C'est pourtant la seule table du domaine qui
-- sache dire **où le temps est passé** et **où sont les rebuts**, opération par
-- opération (`planned_time_minutes`, `actual_time_minutes`, `quantity_produced`,
-- `quantity_scrapped`, `scrap_reason`).
--
-- On la branche :
--   · `record_mo_operation` — l'atelier déclare une opération (temps réel,
--     quantités produites, rebuts, motif). Rejouer la même opération **met à
--     jour** la ligne au lieu d'en créer une seconde (index unique) ;
--   · `mo_operations_summary` — le récapitulatif d'un OF : nombre d'opérations,
--     minutes prévues / réelles, produites, rebutées et **taux de rebut**.
--
-- Aucun impact sur le stock : la matière reste consommée par les mouvements
-- (`reference_type = 'production'`), cette table ne fait que **déclarer**.
-- ============================================================

-- Une opération = une ligne par OF. L'index unique est ce qui rend la
-- déclaration **rejouable** (on corrige un temps, on ne le double pas).
CREATE UNIQUE INDEX IF NOT EXISTS mo_operations_mo_name_key
  ON public.mo_operations (tenant_id, manufacturing_order_id, lower(operation_name));

CREATE OR REPLACE FUNCTION public.record_mo_operation(
  p_mo_id uuid,
  p_operation_name text,
  p_planned_minutes int DEFAULT NULL,
  p_actual_minutes int DEFAULT 0,
  p_produced numeric DEFAULT 0,
  p_scrapped numeric DEFAULT 0,
  p_scrap_reason text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tenant uuid := current_tenant_id();
  v_status text;
  v_name text := btrim(COALESCE(p_operation_name, ''));
  v_id uuid;
BEGIN
  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'Tenant introuvable';
  END IF;
  IF v_name = '' THEN
    RAISE EXCEPTION 'Le nom de l''opération est obligatoire';
  END IF;
  IF COALESCE(p_actual_minutes, 0) < 0
     OR COALESCE(p_produced, 0) < 0
     OR COALESCE(p_scrapped, 0) < 0 THEN
    RAISE EXCEPTION 'Temps et quantités doivent être positifs';
  END IF;

  SELECT status INTO v_status
  FROM public.manufacturing_orders
  WHERE id = p_mo_id AND tenant_id = v_tenant;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'OF introuvable';
  END IF;
  IF v_status = 'cancelled' THEN
    RAISE EXCEPTION 'OF annulé : la déclaration est fermée';
  END IF;

  INSERT INTO public.mo_operations (
    tenant_id, manufacturing_order_id, operation_name,
    planned_time_minutes, actual_time_minutes,
    quantity_produced, quantity_scrapped, scrap_reason, status, completed_at
  )
  VALUES (
    v_tenant, p_mo_id, v_name,
    p_planned_minutes, COALESCE(p_actual_minutes, 0),
    COALESCE(p_produced, 0), COALESCE(p_scrapped, 0), p_scrap_reason,
    CASE WHEN COALESCE(p_produced, 0) > 0 THEN 'completed' ELSE 'in_progress' END,
    CASE WHEN COALESCE(p_produced, 0) > 0 THEN now() ELSE NULL END
  )
  ON CONFLICT (tenant_id, manufacturing_order_id, (lower(operation_name)))
  DO UPDATE SET
    actual_time_minutes  = EXCLUDED.actual_time_minutes,
    planned_time_minutes = COALESCE(EXCLUDED.planned_time_minutes, public.mo_operations.planned_time_minutes),
    quantity_produced    = EXCLUDED.quantity_produced,
    quantity_scrapped    = EXCLUDED.quantity_scrapped,
    scrap_reason         = EXCLUDED.scrap_reason,
    status               = EXCLUDED.status,
    completed_at         = EXCLUDED.completed_at
  RETURNING id INTO v_id;

  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION public.mo_operations_summary(p_mo_id uuid)
RETURNS TABLE (
  nb_operations bigint,
  planned_minutes bigint,
  actual_minutes bigint,
  produced numeric,
  scrapped numeric,
  scrap_rate numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT count(*)::bigint,
         COALESCE(sum(o.planned_time_minutes), 0)::bigint,
         COALESCE(sum(o.actual_time_minutes), 0)::bigint,
         COALESCE(sum(o.quantity_produced), 0),
         COALESCE(sum(o.quantity_scrapped), 0),
         CASE WHEN COALESCE(sum(o.quantity_produced), 0) + COALESCE(sum(o.quantity_scrapped), 0) > 0
              THEN round(COALESCE(sum(o.quantity_scrapped), 0) * 100
                   / (COALESCE(sum(o.quantity_produced), 0) + COALESCE(sum(o.quantity_scrapped), 0)), 2)
              ELSE 0 END
  FROM public.mo_operations o
  WHERE o.manufacturing_order_id = p_mo_id
    AND o.tenant_id = current_tenant_id();
$$;

COMMENT ON FUNCTION public.record_mo_operation(uuid, text, int, int, numeric, numeric, text) IS
  'PRD-06 (661) : déclaration d''atelier — temps réel, quantités produites, rebuts. Rejouable par nom d''opération.';
COMMENT ON FUNCTION public.mo_operations_summary(uuid) IS
  'PRD-06 (661) : récapitulatif d''un OF — minutes prévues/réelles, produites, rebutées, taux de rebut.';

REVOKE ALL ON FUNCTION public.record_mo_operation(uuid, text, int, int, numeric, numeric, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.mo_operations_summary(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_mo_operation(uuid, text, int, int, numeric, numeric, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mo_operations_summary(uuid) TO authenticated;

