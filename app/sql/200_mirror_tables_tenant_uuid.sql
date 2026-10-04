-- ============================================================
-- 200_mirror_tables_tenant_uuid.sql
-- mirror_servers / mirror_verification_details : tenant_id text → uuid.
--
-- Constat en prod (21/09/2026) : tenant_id était de type text, valeur par défaut
-- 'default', et les politiques d'INSERT valaient WITH CHECK (true) — n'importe quel
-- client, même anonyme, pouvait écrire. Un ancien démon miroir (clé anon, sans
-- compte, config tenantId = "default") écrivait ainsi toutes les 5 minutes :
-- 87 424 lignes 'default' au 21/09.
--
-- Attribution : un seul serveur miroir existe (1a79dbfd-…, MacBook de l'éditeur,
-- enregistré le 17/07/2026). Ses premières lignes (17-19/07) portaient la société
-- 00000000-0000-0000-0000-000000000001 « Entreprise par défaut » : toutes les
-- lignes 'default' de ce serveur lui sont rattachées. Une ligne 'default' qu'on ne
-- peut rattacher à aucune société existante est supprimée (compteurs techniques
-- de vérification, pas de donnée métier).
--
-- Sur une base déjà en uuid (CI), seules les politiques sont réappliquées.
-- ============================================================

DO $$
DECLARE
  v_default constant uuid := '00000000-0000-0000-0000-000000000001';
  v_has_default boolean := EXISTS (SELECT 1 FROM tenants WHERE id = v_default);
  p record;
BEGIN
  IF (SELECT data_type FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'mirror_servers' AND column_name = 'tenant_id') <> 'text' THEN
    RETURN;
  END IF;

  -- Les politiques lisent tenant_id : à retirer avant le changement de type
  FOR p IN SELECT policyname, tablename FROM pg_policies
           WHERE schemaname = 'public' AND tablename IN ('mirror_servers', 'mirror_verification_details')
  LOOP
    EXECUTE format('DROP POLICY %I ON public.%I', p.policyname, p.tablename);
  END LOOP;

  -- 1. Serveurs : 'default' ou identifiant inconnu → société par défaut si elle existe
  UPDATE mirror_servers SET tenant_id = v_default::text
  WHERE v_has_default
    AND (tenant_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
         OR NOT EXISTS (SELECT 1 FROM tenants t WHERE t.id::text = mirror_servers.tenant_id));
  DELETE FROM mirror_servers
  WHERE NOT EXISTS (SELECT 1 FROM tenants t WHERE t.id::text = mirror_servers.tenant_id);

  -- 2. Détails : société de leur serveur
  UPDATE mirror_verification_details d SET tenant_id = s.tenant_id
  FROM mirror_servers s
  WHERE s.id = d.mirror_server_id AND d.tenant_id IS DISTINCT FROM s.tenant_id;
  DELETE FROM mirror_verification_details d
  WHERE NOT EXISTS (SELECT 1 FROM tenants t WHERE t.id::text = d.tenant_id);

  -- 3. Type, défaut, contraintes
  ALTER TABLE mirror_servers ALTER COLUMN tenant_id DROP DEFAULT;
  ALTER TABLE mirror_verification_details ALTER COLUMN tenant_id DROP DEFAULT;
  ALTER TABLE mirror_servers ALTER COLUMN tenant_id TYPE uuid USING tenant_id::uuid;
  ALTER TABLE mirror_verification_details ALTER COLUMN tenant_id TYPE uuid USING tenant_id::uuid;
  ALTER TABLE mirror_servers ALTER COLUMN tenant_id SET NOT NULL;
  ALTER TABLE mirror_verification_details ALTER COLUMN tenant_id SET NOT NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE mirror_servers ADD CONSTRAINT mirror_servers_tenant_id_fkey
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE mirror_verification_details ADD CONSTRAINT mirror_verification_details_tenant_id_fkey
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE mirror_servers ENABLE ROW LEVEL SECURITY;
ALTER TABLE mirror_verification_details ENABLE ROW LEVEL SECURITY;

-- 4. Politiques du dépôt (cloisonnement par société, plus d'INSERT ouvert)
DROP POLICY IF EXISTS tenant_delete_mirror_servers ON public.mirror_servers;
CREATE POLICY tenant_delete_mirror_servers ON public.mirror_servers AS PERMISSIVE FOR DELETE TO public USING ((tenant_id = public.current_tenant_id()));
DROP POLICY IF EXISTS tenant_insert_mirror_servers ON public.mirror_servers;
CREATE POLICY tenant_insert_mirror_servers ON public.mirror_servers AS PERMISSIVE FOR INSERT TO public WITH CHECK ((tenant_id = public.current_tenant_id()));
DROP POLICY IF EXISTS tenant_isolated_mirror_servers ON public.mirror_servers;
CREATE POLICY tenant_isolated_mirror_servers ON public.mirror_servers AS PERMISSIVE FOR ALL TO public USING ((tenant_id = public.current_tenant_id())) WITH CHECK ((tenant_id = public.current_tenant_id()));
DROP POLICY IF EXISTS tenant_select_mirror_servers ON public.mirror_servers;
CREATE POLICY tenant_select_mirror_servers ON public.mirror_servers AS PERMISSIVE FOR SELECT TO public USING ((tenant_id = public.current_tenant_id()));
DROP POLICY IF EXISTS tenant_update_mirror_servers ON public.mirror_servers;
CREATE POLICY tenant_update_mirror_servers ON public.mirror_servers AS PERMISSIVE FOR UPDATE TO public USING ((tenant_id = public.current_tenant_id())) WITH CHECK ((tenant_id = public.current_tenant_id()));
DROP POLICY IF EXISTS tenant_delete_mirror_verification ON public.mirror_verification_details;
CREATE POLICY tenant_delete_mirror_verification ON public.mirror_verification_details AS PERMISSIVE FOR DELETE TO public USING ((EXISTS ( SELECT 1
   FROM public.mirror_servers ms
  WHERE ((ms.id = mirror_verification_details.mirror_server_id) AND (ms.tenant_id = public.current_tenant_id())))));
DROP POLICY IF EXISTS tenant_delete_mirror_verification_details ON public.mirror_verification_details;
CREATE POLICY tenant_delete_mirror_verification_details ON public.mirror_verification_details AS PERMISSIVE FOR DELETE TO public USING (((tenant_id = public.current_tenant_id()) AND public.can_perform('mirror_verification_details'::text, 'delete'::text)));
DROP POLICY IF EXISTS tenant_insert_mirror_verification ON public.mirror_verification_details;
CREATE POLICY tenant_insert_mirror_verification ON public.mirror_verification_details AS PERMISSIVE FOR INSERT TO public WITH CHECK ((EXISTS ( SELECT 1
   FROM public.mirror_servers ms
  WHERE ((ms.id = mirror_verification_details.mirror_server_id) AND (ms.tenant_id = public.current_tenant_id())))));
DROP POLICY IF EXISTS tenant_insert_mirror_verification_details ON public.mirror_verification_details;
CREATE POLICY tenant_insert_mirror_verification_details ON public.mirror_verification_details AS PERMISSIVE FOR INSERT TO public WITH CHECK (((tenant_id = public.current_tenant_id()) AND public.can_perform('mirror_verification_details'::text, 'insert'::text)));
DROP POLICY IF EXISTS tenant_isolated_mirror_verification ON public.mirror_verification_details;
CREATE POLICY tenant_isolated_mirror_verification ON public.mirror_verification_details AS PERMISSIVE FOR ALL TO public USING ((tenant_id = public.current_tenant_id())) WITH CHECK ((tenant_id = public.current_tenant_id()));
DROP POLICY IF EXISTS tenant_select_mirror_verification ON public.mirror_verification_details;
CREATE POLICY tenant_select_mirror_verification ON public.mirror_verification_details AS PERMISSIVE FOR SELECT TO public USING ((EXISTS ( SELECT 1
   FROM public.mirror_servers ms
  WHERE ((ms.id = mirror_verification_details.mirror_server_id) AND (ms.tenant_id = public.current_tenant_id())))));
DROP POLICY IF EXISTS tenant_select_mirror_verification_details ON public.mirror_verification_details;
CREATE POLICY tenant_select_mirror_verification_details ON public.mirror_verification_details AS PERMISSIVE FOR SELECT TO public USING ((tenant_id = public.current_tenant_id()));
DROP POLICY IF EXISTS tenant_update_mirror_verification ON public.mirror_verification_details;
CREATE POLICY tenant_update_mirror_verification ON public.mirror_verification_details AS PERMISSIVE FOR UPDATE TO public USING ((EXISTS ( SELECT 1
   FROM public.mirror_servers ms
  WHERE ((ms.id = mirror_verification_details.mirror_server_id) AND (ms.tenant_id = public.current_tenant_id())))));
DROP POLICY IF EXISTS tenant_update_mirror_verification_details ON public.mirror_verification_details;
CREATE POLICY tenant_update_mirror_verification_details ON public.mirror_verification_details AS PERMISSIVE FOR UPDATE TO public USING (((tenant_id = public.current_tenant_id()) AND public.can_perform('mirror_verification_details'::text, 'update'::text))) WITH CHECK ((tenant_id = public.current_tenant_id()));
