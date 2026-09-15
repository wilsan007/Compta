-- ============================================================
-- 74_rls_generic_tenant_isolation.sql
--
-- SEC-02: Corrige les 129+ tables créées après la migration 37
-- qui sont restées en accès libre (USING (true) / WITH CHECK (true)).
--
-- Approche dynamique : parcourt pg_policies pour trouver TOUTES
-- les politiques allow_all ou USING(true) restantes, et les
-- remplace par des politiques isolées par tenant.
--
-- Tables de référence globales (sans tenant_id, SELECT public) :
--   currencies, legislation_packs, tax_rates, chart_account_templates
-- ============================================================

-- ============================================
-- 1. S'assurer que set_tenant_id() existe
-- ============================================
CREATE OR REPLACE FUNCTION set_tenant_id()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.tenant_id IS NULL AND TG_TABLE_NAME != 'tenants' THEN
    NEW.tenant_id := current_tenant_id();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 2. TABLES DE RÉFÉRENCE GLOBALES
--    SELECT public pour les utilisateurs authentifiés
-- ============================================
DO $$
DECLARE
  t text;
  ref_tables text[] := ARRAY[
    'currencies', 'legislation_packs', 'tax_rates', 'chart_account_templates',
    'banks', 'public_holidays'
  ];
  pol record;
BEGIN
  FOREACH t IN ARRAY ref_tables LOOP
    BEGIN
      EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
      FOR pol IN SELECT policyname AS polname FROM pg_policies WHERE tablename = t LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I', pol.polname, t);
      END LOOP;
      EXECUTE format(
        'CREATE POLICY %I ON %I FOR SELECT USING (auth.uid() IS NOT NULL)',
        'global_select_' || t, t
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Skipping ref table %: %', t, SQLERRM;
    END;
  END LOOP;
END $$;

-- ============================================
-- 3. CORRIGER TOUTES LES TABLES AVEC allow_all OU USING(true)
--    qui ont une colonne tenant_id
-- ============================================
DO $$
DECLARE
  pol record;
  pol2 record;
  has_tenant_id boolean;
  ref_tables text[] := ARRAY[
    'currencies','legislation_packs','tax_rates','chart_account_templates',
    'banks','public_holidays'
  ];
BEGIN
  -- Parcourir toutes les politiques avec USING (true) ou WITH CHECK (true)
  -- ou nommées allow_all_*
  FOR pol IN
    SELECT DISTINCT tablename AS tbl, policyname AS polname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND (
        policyname LIKE 'allow_all%'
        OR qual = 'true'
        OR with_check = 'true'
        OR qual = '(true)'
        OR with_check = '(true)'
      )
      AND tablename != ANY(ref_tables)
      AND tablename NOT IN ('tenant_users')
    ORDER BY tablename
  LOOP
    BEGIN
      -- Vérifier si la table a une colonne tenant_id
      SELECT EXISTS(
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = pol.tbl
          AND column_name = 'tenant_id'
      ) INTO has_tenant_id;

      IF NOT has_tenant_id THEN
        -- Tenter d'ajouter tenant_id
        BEGIN
          EXECUTE format(
            'ALTER TABLE %I ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE',
            pol.tbl
          );
          EXECUTE format(
            'CREATE INDEX IF NOT EXISTS idx_%I_tenant ON %I(tenant_id)',
            pol.tbl, pol.tbl
          );
          has_tenant_id := true;
        EXCEPTION WHEN OTHERS THEN
          RAISE NOTICE 'Could not add tenant_id to %: %', pol.tbl, SQLERRM;
          -- Table sans tenant_id et impossible d'ajouter → skip
          CONTINUE;
        END;
      END IF;

      -- Activer et forcer RLS
      EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', pol.tbl);
      EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', pol.tbl);

      -- Supprimer toutes les politiques existantes sur cette table
      FOR pol2 IN SELECT policyname AS polname FROM pg_policies WHERE tablename = pol.tbl LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I', pol2.polname, pol.tbl);
      END LOOP;

      -- Ajouter le trigger set_tenant_id si pas déjà présent
      BEGIN
        EXECUTE format('DROP TRIGGER IF EXISTS set_tenant_id_%I ON %I', pol.tbl, pol.tbl);
        EXECUTE format(
          'CREATE TRIGGER set_tenant_id_%I BEFORE INSERT ON %I FOR EACH ROW EXECUTE FUNCTION set_tenant_id()',
          pol.tbl, pol.tbl
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Could not add trigger on %: %', pol.tbl, SQLERRM;
      END;

      -- Créer les 4 politiques tenant-isolated
      EXECUTE format(
        'CREATE POLICY %I ON %I FOR SELECT USING (tenant_id = current_tenant_id())',
        'tenant_select_' || pol.tbl, pol.tbl
      );
      EXECUTE format(
        'CREATE POLICY %I ON %I FOR INSERT WITH CHECK (tenant_id = current_tenant_id())',
        'tenant_insert_' || pol.tbl, pol.tbl
      );
      EXECUTE format(
        'CREATE POLICY %I ON %I FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id())',
        'tenant_update_' || pol.tbl, pol.tbl
      );
      EXECUTE format(
        'CREATE POLICY %I ON %I FOR DELETE USING (tenant_id = current_tenant_id())',
        'tenant_delete_' || pol.tbl, pol.tbl
      );

      RAISE NOTICE 'Fixed RLS on table %', pol.tbl;

    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ERROR fixing RLS on %: %', pol.tbl, SQLERRM;
    END;
  END LOOP;
END $$;

-- ============================================
-- 4. TABLES ENFANTS SANS tenant_id (lignes de documents)
--    Politique par jointure sur le parent
-- ============================================
DO $$
DECLARE
  child record;
  parent_table text;
  join_col text;
  pol record;
BEGIN
  -- Tables enfants connues (ligne → parent)
  FOR child IN
    SELECT * FROM (VALUES
      ('invoice_lines', 'invoices', 'invoice_id'),
      ('quote_lines', 'quotes', 'quote_id'),
      ('credit_note_lines', 'credit_notes', 'credit_note_id'),
      ('purchase_invoice_lines', 'purchase_invoices', 'purchase_invoice_id'),
      ('purchase_order_lines', 'purchase_orders', 'purchase_order_id'),
      ('purchase_credit_lines', 'purchase_credit_notes', 'purchase_credit_note_id'),
      ('sales_order_lines', 'sales_orders', 'sales_order_id'),
      ('delivery_note_lines', 'delivery_notes', 'delivery_note_id'),
      ('goods_receipt_lines', 'goods_receipts', 'goods_receipt_id'),
      ('pick_list_lines', 'pick_lists', 'pick_list_id'),
      ('pos_ticket_lines', 'pos_tickets', 'pos_ticket_id'),
      ('service_ticket_messages', 'service_tickets', 'ticket_id'),
      ('expense_report_lines', 'expense_reports', 'expense_report_id'),
      ('purchase_request_lines', 'purchase_requests', 'purchase_request_id'),
      ('distribution_grill_lines', 'distribution_grills', 'grill_id'),
      ('asset_batch_disposal_lines', 'asset_batch_disposals', 'batch_disposal_id'),
      ('asset_split_components', 'asset_splits', 'split_id'),
      ('crm_campaign_recipients', 'crm_campaigns', 'campaign_id'),
      ('document_distribution_logs', 'employee_documents', 'document_id')
    ) AS t(child_table, parent_table, join_col)
  LOOP
    BEGIN
      -- Vérifier que les deux tables existent
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = child.child_table
      ) OR NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = child.parent_table
      ) THEN
        CONTINUE;
      END IF;

      -- Vérifier que la colonne de jointure existe
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = child.child_table AND column_name = child.join_col
      ) THEN
        CONTINUE;
      END IF;

      -- Activer RLS
      EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', child.child_table);
      EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', child.child_table);

      -- Supprimer les politiques existantes
      FOR pol IN SELECT policyname AS polname FROM pg_policies WHERE tablename = child.child_table LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I', pol.polname, child.child_table);
      END LOOP;

      -- SELECT : la ligne est visible si son parent appartient au tenant
      EXECUTE format(
        'CREATE POLICY %I ON %I FOR SELECT USING (
           EXISTS (SELECT 1 FROM %I p WHERE p.id = %I.%I AND p.tenant_id = current_tenant_id())
         )',
        'tenant_select_' || child.child_table, child.child_table,
        child.parent_table, child.child_table, child.join_col
      );

      -- INSERT : le parent doit appartenir au tenant
      EXECUTE format(
        'CREATE POLICY %I ON %I FOR INSERT WITH CHECK (
           EXISTS (SELECT 1 FROM %I p WHERE p.id = %I.%I AND p.tenant_id = current_tenant_id())
         )',
        'tenant_insert_' || child.child_table, child.child_table,
        child.parent_table, child.child_table, child.join_col
      );

      -- UPDATE
      EXECUTE format(
        'CREATE POLICY %I ON %I FOR UPDATE USING (
           EXISTS (SELECT 1 FROM %I p WHERE p.id = %I.%I AND p.tenant_id = current_tenant_id())
         ) WITH CHECK (
           EXISTS (SELECT 1 FROM %I p WHERE p.id = %I.%I AND p.tenant_id = current_tenant_id())
         )',
        'tenant_update_' || child.child_table, child.child_table,
        child.parent_table, child.child_table, child.join_col,
        child.parent_table, child.child_table, child.join_col
      );

      -- DELETE
      EXECUTE format(
        'CREATE POLICY %I ON %I FOR DELETE USING (
           EXISTS (SELECT 1 FROM %I p WHERE p.id = %I.%I AND p.tenant_id = current_tenant_id())
         )',
        'tenant_delete_' || child.child_table, child.child_table,
        child.parent_table, child.child_table, child.join_col
      );

      RAISE NOTICE 'Fixed child table %', child.child_table;

    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ERROR fixing child table %: %', child.child_table, SQLERRM;
    END;
  END LOOP;
END $$;

-- ============================================
-- 5. RÉVOQUER LES GRANTS DU RÔLE anon
--    sur toutes les tables métier
-- ============================================
DO $$
DECLARE
  t record;
  ref_tables text[] := ARRAY[
    'currencies','legislation_packs','tax_rates','chart_account_templates',
    'banks','public_holidays'
  ];
BEGIN
  FOR t IN
    SELECT table_name FROM information_schema.tables
    WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
  LOOP
    BEGIN
      IF t.table_name != ANY(ref_tables) THEN
        EXECUTE format('REVOKE ALL ON %I FROM anon', t.table_name);
      END IF;
    EXCEPTION WHEN OTHERS THEN
      -- anon role may not exist in all environments
      RAISE NOTICE 'Could not revoke anon on %: %', t.table_name, SQLERRM;
    END;
  END LOOP;
END $$;

-- ============================================
-- 6. VÉRIFICATION FINALE
--    Après exécution, ces requêtes ne doivent retourner AUCUNE ligne:
-- ============================================
-- SELECT tablename, policyname, qual, with_check
-- FROM pg_policies
-- WHERE schemaname = 'public'
--   AND (qual = 'true' OR with_check = 'true'
--        OR qual = '(true)' OR with_check = '(true)'
--        OR policyname LIKE 'allow_all%')
--   AND tablename NOT IN ('tenant_users')
-- ORDER BY tablename;
