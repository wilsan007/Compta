-- ============================================================
-- 215_bootstrap_tenant_grants.sql — dérive de production sur les droits
--
-- Trouvé le 23/09 par la répétition sur copie de production (P0-06) : la suite
-- 182 échoue sur S05 en prod alors qu'elle est verte en CI. `bootstrap_tenant`
-- y est exécutable par le rôle **anon**, c'est-à-dire par quiconque détient la
-- clé publique de l'application.
--
-- Pourquoi : la 183 révoque ce droit, mais la production a exécuté la 183
-- AVANT que cette ligne n'y soit ajoutée (le traqueur ne suit que les noms de
-- fichiers — c'est la dérive déjà constatée pour 115 migrations, corrigée par
-- la 188). `CREATE OR REPLACE FUNCTION` conservant les droits existants, les
-- redéfinitions ultérieures (187, 201) ont gardé l'ancien ACL.
--
-- Cette migration ré-applique la révocation. Elle est sans effet sur une base
-- déjà correcte (CI), et idempotente.
--
-- Périmètre volontairement étroit : l'exposition générale des fonctions
-- SECURITY DEFINER au rôle anon (214 sur 272 en CI, 249 sur 274 en prod) est
-- le lot H09 du plan correctif, qui demande un inventaire et un contrôle CI
-- dédiés — à traiter à part, sans quoi on casserait des appels légitimes.
-- ============================================================

DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname IN ('bootstrap_tenant', 'assert_can_provision_tenant')
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', r.sig);
  END LOOP;
END $$;

DO $$
DECLARE v_exposed text;
BEGIN
  SELECT string_agg(p.oid::regprocedure::text, ', ')
  INTO v_exposed
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname IN ('bootstrap_tenant', 'assert_can_provision_tenant')
    AND has_function_privilege('anon', p.oid, 'EXECUTE');

  IF v_exposed IS NOT NULL THEN
    RAISE EXCEPTION 'Droits anon encore accordés après révocation : %', v_exposed;
  END IF;
  RAISE NOTICE 'bootstrap_tenant et assert_can_provision_tenant : anon révoqué, authenticated conservé';
END $$;
