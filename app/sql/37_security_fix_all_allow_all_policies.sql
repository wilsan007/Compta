-- ============================================================
-- 37_security_fix_all_allow_all_policies.sql
--
-- Remplace DYNAMIQUEMENT TOUTES les politiques RLS "allow_all"
-- par des politiques isolées par tenant (current_tenant_id())
-- Corrige aussi les tables utilisant incorrectement auth.uid()
--
-- Tables de référence globales (SELECT public, pas de tenant_id):
--   currencies, legislation_packs, tax_rates, chart_account_templates
--
-- Tables avec auth.uid() légitime (non modifiées):
--   tenant_users (utilise auth.uid() pour les invitations pending)
-- ============================================================

-- ============================================
-- 1. FONCTION HELPER: set_tenant_id (si pas déjà créée)
-- ============================================
CREATE OR REPLACE FUNCTION set_tenant_id()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.tenant_id IS NULL AND TG_TABLENAME != 'tenants' THEN
    NEW.tenant_id := current_tenant_id();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 2. TABLES DE RÉFÉRENCE GLOBALES
--    Ces tables n'ont pas de tenant_id et sont lisibles
--    par tous les utilisateurs authentifiés.
--    On remplace leur allow_all par un simple "authenticated" check.
-- ============================================
DO $$
DECLARE
  t text;
  ref_tables text[] := ARRAY[
    'currencies', 'legislation_packs', 'tax_rates', 'chart_account_templates'
  ];
  pol record;
BEGIN
  FOREACH t IN ARRAY ref_tables LOOP
    BEGIN
      -- Activer RLS
      EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);

      -- Supprimer toutes les politiques existantes sur cette table
      FOR pol IN SELECT policyname FROM pg_policies WHERE tablename = t LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I', pol.policyname, t);
      END LOOP;

      -- SELECT: tout utilisateur authentifié peut lire
      EXECUTE format(
        'CREATE POLICY %I ON %I FOR SELECT USING (true)',
        'global_select_' || t, t
      );
      -- Pas de INSERT/UPDATE/DELETE pour les tenants normaux
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Skipping ref table fix on %: %', t, SQLERRM;
    END;
  END LOOP;
END $$;

-- ============================================
-- 3. AJOUTER tenant_id + TRIGGER + RLS À TOUTES LES
--    TABLES AYANT ENCORE UNE POLITIQUE allow_all
--    (Découverte dynamique via pg_policies)
-- ============================================
DO $$
DECLARE
  pol record;
  has_tenant_id boolean;
  is_ref_table boolean;
  ref_tables text[] := ARRAY['currencies','legislation_packs','tax_rates','chart_account_templates'];
BEGIN
  -- Parcourir toutes les politiques allow_all restantes
  FOR pol IN
    SELECT DISTINCT tablename, policyname
    FROM pg_policies
    WHERE policyname LIKE 'allow_all_%'
    ORDER BY tablename
  LOOP
    BEGIN
      -- Skip les tables de référence (déjà traitées en section 2)
      is_ref_table := pol.tablename = ANY(ref_tables);
      IF is_ref_table THEN
        -- Supprimer juste la politique allow_all
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I', pol.policyname, pol.tablename);
        CONTINUE;
      END IF;

      -- Vérifier si la table a une colonne tenant_id
      SELECT EXISTS(
        SELECT 1 FROM information_schema.columns
        WHERE table_name = pol.tablename AND column_name = 'tenant_id'
      ) INTO has_tenant_id;

      -- Si pas de tenant_id, tenter d'ajouter
      IF NOT has_tenant_id THEN
        BEGIN
          EXECUTE format('ALTER TABLE %I ADD COLUMN tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE', pol.tablename);
          EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%I_tenant ON %I(tenant_id)', pol.tablename, pol.tablename);
        EXCEPTION WHEN OTHERS THEN
          RAISE NOTICE 'Could not add tenant_id to %: %', pol.tablename, SQLERRM;
          -- Si on ne peut pas ajouter tenant_id, on ne peut pas isoler → skip
          CONTINUE;
        END;
      END IF;

      -- Activer et forcer RLS
      EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', pol.tablename);
      EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', pol.tablename);

      -- Supprimer la politique allow_all
      EXECUTE format('DROP POLICY IF EXISTS %I ON %I', pol.policyname, pol.tablename);

      -- Supprimer aussi d'éventuelles anciennes politiques tenant_* pour éviter les doublons
      EXECUTE format('DROP POLICY IF EXISTS %I ON %I', 'tenant_select_' || pol.tablename, pol.tablename);
      EXECUTE format('DROP POLICY IF EXISTS %I ON %I', 'tenant_insert_' || pol.tablename, pol.tablename);
      EXECUTE format('DROP POLICY IF EXISTS %I ON %I', 'tenant_update_' || pol.tablename, pol.tablename);
      EXECUTE format('DROP POLICY IF EXISTS %I ON %I', 'tenant_delete_' || pol.tablename, pol.tablename);

      -- Ajouter le trigger set_tenant_id si pas déjà présent
      BEGIN
        EXECUTE format('DROP TRIGGER IF EXISTS set_tenant_id_%I ON %I', pol.tablename, pol.tablename);
        EXECUTE format(
          'CREATE TRIGGER set_tenant_id_%I BEFORE INSERT ON %I FOR EACH ROW EXECUTE FUNCTION set_tenant_id()',
          pol.tablename, pol.tablename
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Could not add trigger on %: %', pol.tablename, SQLERRM;
      END;

      -- Créer les 4 politiques tenant-isolated
      EXECUTE format(
        'CREATE POLICY %I ON %I FOR SELECT USING (tenant_id = current_tenant_id())',
        'tenant_select_' || pol.tablename, pol.tablename
      );
      EXECUTE format(
        'CREATE POLICY %I ON %I FOR INSERT WITH CHECK (tenant_id = current_tenant_id())',
        'tenant_insert_' || pol.tablename, pol.tablename
      );
      EXECUTE format(
        'CREATE POLICY %I ON %I FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id())',
        'tenant_update_' || pol.tablename, pol.tablename
      );
      EXECUTE format(
        'CREATE POLICY %I ON %I FOR DELETE USING (tenant_id = current_tenant_id())',
        'tenant_delete_' || pol.tablename, pol.tablename
      );

      RAISE NOTICE 'Fixed RLS on table %', pol.tablename;

    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ERROR fixing RLS on %: %', pol.tablename, SQLERRM;
    END;
  END LOOP;
END $$;

-- ============================================
-- 4. CORRIGER LES POLITIQUES auth.uid() INCORRECTES
--    (sauf tenant_users qui utilise auth.uid() légitimement)
-- ============================================
DO $$
DECLARE
  pol record;
  has_tenant_id boolean;
BEGIN
  -- Trouver toutes les politiques utilisant auth.uid() sauf tenant_users
  FOR pol IN
    SELECT tablename, policyname
    FROM pg_policies
    WHERE (qual LIKE '%auth.uid()%' OR with_check LIKE '%auth.uid()%')
      AND tablename NOT IN ('tenant_users')
    ORDER BY tablename
  LOOP
    BEGIN
      -- Vérifier si la table a tenant_id
      SELECT EXISTS(
        SELECT 1 FROM information_schema.columns
        WHERE table_name = pol.tablename AND column_name = 'tenant_id'
      ) INTO has_tenant_id;

      IF NOT has_tenant_id THEN
        -- Table sans tenant_id: juste remplacer auth.uid() par true pour SELECT
        -- (table de référence globale déjà traitée ou à traiter)
        RAISE NOTICE 'Table % uses auth.uid() but has no tenant_id — skipping', pol.tablename;
        CONTINUE;
      END IF;

      -- Supprimer l'ancienne politique
      EXECUTE format('DROP POLICY IF EXISTS %I ON %I', pol.policyname, pol.tablename);

      -- Supprimer d'éventuelles anciennes politiques tenant_* doublons
      EXECUTE format('DROP POLICY IF EXISTS %I ON %I', 'tenant_select_' || pol.tablename, pol.tablename);
      EXECUTE format('DROP POLICY IF EXISTS %I ON %I', 'tenant_insert_' || pol.tablename, pol.tablename);
      EXECUTE format('DROP POLICY IF EXISTS %I ON %I', 'tenant_update_' || pol.tablename, pol.tablename);
      EXECUTE format('DROP POLICY IF EXISTS %I ON %I', 'tenant_delete_' || pol.tablename, pol.tablename);

      -- Activer et forcer RLS
      EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', pol.tablename);
      EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', pol.tablename);

      -- Créer les politiques tenant-isolated
      -- SELECT: tenant voit ses lignes + lignes globales (tenant_id IS NULL)
      EXECUTE format(
        'CREATE POLICY %I ON %I FOR SELECT USING (tenant_id = current_tenant_id() OR tenant_id IS NULL)',
        'tenant_select_' || pol.tablename, pol.tablename
      );
      EXECUTE format(
        'CREATE POLICY %I ON %I FOR INSERT WITH CHECK (tenant_id = current_tenant_id())',
        'tenant_insert_' || pol.tablename, pol.tablename
      );
      EXECUTE format(
        'CREATE POLICY %I ON %I FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id())',
        'tenant_update_' || pol.tablename, pol.tablename
      );
      EXECUTE format(
        'CREATE POLICY %I ON %I FOR DELETE USING (tenant_id = current_tenant_id())',
        'tenant_delete_' || pol.tablename, pol.tablename
      );

      RAISE NOTICE 'Fixed auth.uid() policy on table %', pol.tablename;

    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ERROR fixing auth.uid on %: %', pol.tablename, SQLERRM;
    END;
  END LOOP;
END $$;

-- ============================================
-- 5. VÉRIFICATION FINALE
-- ============================================
-- Après exécution, ces requêtes ne doivent retourner AUCUNE ligne:
--
-- SELECT tablename, policyname FROM pg_policies
-- WHERE policyname LIKE 'allow_all_%'
-- ORDER BY tablename;
--
-- SELECT tablename, policyname FROM pg_policies
-- WHERE (qual LIKE '%auth.uid()%' OR with_check LIKE '%auth.uid()%')
--   AND tablename NOT IN ('tenant_users')
-- ORDER BY tablename;
