-- ============================================================
-- 84_rls_critical_fixes.sql
--
-- Corrections critiques de sécurité RLS :
--   1. Suppression des policies trop permissives sur tenant_users
--   2. Renforcement des policies sur users (rôle admin requis)
--   3. Ajout de policies sur project_members (isolation correcte)
--   4. Ajout de policies sur 13 tables sans policies
--   5. FORCE ROW LEVEL SECURITY sur 62 tables
--   6. Ajout de SET search_path sur les fonctions SECURITY DEFINER
-- ============================================================

-- ============================================================
-- SECTION 1 — Suppression des policies trop permissives sur tenant_users
-- ============================================================
-- Les policies tenant_users_* (sans vérification de rôle) permettent
-- à n'importe quel utilisateur du tenant de modifier tous les tenant_users.
-- On les supprime et on garde uniquement les policies tenant_*_tenant_users
-- qui vérifient current_user_role() = 'admin'.

DROP POLICY IF EXISTS tenant_users_select ON tenant_users;
DROP POLICY IF EXISTS tenant_users_insert ON tenant_users;
DROP POLICY IF EXISTS tenant_users_update ON tenant_users;
DROP POLICY IF EXISTS tenant_users_delete ON tenant_users;

-- Vérifier que les policies avec rôle existent toujours
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'tenant_users' AND policyname = 'tenant_select_tenant_users') THEN
    DROP POLICY IF EXISTS tenant_select_tenant_users ON tenant_users;
    CREATE POLICY tenant_select_tenant_users ON tenant_users
      FOR SELECT USING (tenant_id = current_tenant_id());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'tenant_users' AND policyname = 'tenant_insert_tenant_users') THEN
    DROP POLICY IF EXISTS tenant_insert_tenant_users ON tenant_users;
    CREATE POLICY tenant_insert_tenant_users ON tenant_users
      FOR INSERT WITH CHECK (tenant_id = current_tenant_id() AND current_user_role() = 'admin');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'tenant_users' AND policyname = 'tenant_update_tenant_users') THEN
    DROP POLICY IF EXISTS tenant_update_tenant_users ON tenant_users;
    CREATE POLICY tenant_update_tenant_users ON tenant_users
      FOR UPDATE USING (tenant_id = current_tenant_id() AND current_user_role() = 'admin')
      WITH CHECK (tenant_id = current_tenant_id() AND current_user_role() = 'admin');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'tenant_users' AND policyname = 'tenant_delete_tenant_users') THEN
    DROP POLICY IF EXISTS tenant_delete_tenant_users ON tenant_users;
    CREATE POLICY tenant_delete_tenant_users ON tenant_users
      FOR DELETE USING (tenant_id = current_tenant_id() AND current_user_role() = 'admin');
  END IF;
END;
$$;



-- ============================================================
-- SECTION 2 — Renforcement des policies sur users
-- ============================================================
-- INSERT/UPDATE/DELETE doivent nécessiter le rôle admin.

DROP POLICY IF EXISTS tenant_insert_users ON users;
DROP POLICY IF EXISTS tenant_update_users ON users;
DROP POLICY IF EXISTS tenant_delete_users ON users;

DROP POLICY IF EXISTS tenant_insert_users ON users;
CREATE POLICY tenant_insert_users ON users
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id() AND current_user_role() = 'admin');

DROP POLICY IF EXISTS tenant_update_users ON users;
CREATE POLICY tenant_update_users ON users
  FOR UPDATE USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id() AND current_user_role() = 'admin');

DROP POLICY IF EXISTS tenant_delete_users ON users;
CREATE POLICY tenant_delete_users ON users
  FOR DELETE USING (tenant_id = current_tenant_id() AND current_user_role() = 'admin');



-- ============================================================
-- SECTION 3 — Policies sur project_members (isolation correcte)
-- ============================================================
-- project_members avait 0 policies (RLS activé = tout bloqué).
-- On ajoute des policies avec isolation par current_tenant_id().

DROP POLICY IF EXISTS tenant_select_project_members ON project_members;
DROP POLICY IF EXISTS tenant_insert_project_members ON project_members;
DROP POLICY IF EXISTS tenant_update_project_members ON project_members;
DROP POLICY IF EXISTS tenant_delete_project_members ON project_members;

DROP POLICY IF EXISTS tenant_select_project_members ON project_members;
CREATE POLICY tenant_select_project_members ON project_members
  FOR SELECT USING (tenant_id = current_tenant_id());

DROP POLICY IF EXISTS tenant_insert_project_members ON project_members;
CREATE POLICY tenant_insert_project_members ON project_members
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id());

DROP POLICY IF EXISTS tenant_update_project_members ON project_members;
CREATE POLICY tenant_update_project_members ON project_members
  FOR UPDATE USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

DROP POLICY IF EXISTS tenant_delete_project_members ON project_members;
CREATE POLICY tenant_delete_project_members ON project_members
  FOR DELETE USING (tenant_id = current_tenant_id());



-- ============================================================
-- SECTION 4 — Policies sur les 13 tables sans policies
-- ============================================================

-- module_documents
DROP POLICY IF EXISTS tenant_select_module_documents ON module_documents;
CREATE POLICY tenant_select_module_documents ON module_documents
  FOR SELECT USING (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS tenant_insert_module_documents ON module_documents;
CREATE POLICY tenant_insert_module_documents ON module_documents
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS tenant_update_module_documents ON module_documents;
CREATE POLICY tenant_update_module_documents ON module_documents
  FOR UPDATE USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS tenant_delete_module_documents ON module_documents;
CREATE POLICY tenant_delete_module_documents ON module_documents
  FOR DELETE USING (tenant_id = current_tenant_id());

-- module_document_shares
DROP POLICY IF EXISTS tenant_select_module_doc_shares ON module_document_shares;
CREATE POLICY tenant_select_module_doc_shares ON module_document_shares
  FOR SELECT USING (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS tenant_insert_module_doc_shares ON module_document_shares;
CREATE POLICY tenant_insert_module_doc_shares ON module_document_shares
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS tenant_update_module_doc_shares ON module_document_shares;
CREATE POLICY tenant_update_module_doc_shares ON module_document_shares
  FOR UPDATE USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS tenant_delete_module_doc_shares ON module_document_shares;
CREATE POLICY tenant_delete_module_doc_shares ON module_document_shares
  FOR DELETE USING (tenant_id = current_tenant_id());

-- module_document_access_log
DROP POLICY IF EXISTS tenant_select_module_doc_access ON module_document_access_log;
CREATE POLICY tenant_select_module_doc_access ON module_document_access_log
  FOR SELECT USING (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS tenant_insert_module_doc_access ON module_document_access_log;
CREATE POLICY tenant_insert_module_doc_access ON module_document_access_log
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id());

-- notification_email_queue
DROP POLICY IF EXISTS tenant_select_notif_email_queue ON notification_email_queue;
CREATE POLICY tenant_select_notif_email_queue ON notification_email_queue
  FOR SELECT USING (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS tenant_insert_notif_email_queue ON notification_email_queue;
CREATE POLICY tenant_insert_notif_email_queue ON notification_email_queue
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS tenant_update_notif_email_queue ON notification_email_queue;
CREATE POLICY tenant_update_notif_email_queue ON notification_email_queue
  FOR UPDATE USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS tenant_delete_notif_email_queue ON notification_email_queue;
CREATE POLICY tenant_delete_notif_email_queue ON notification_email_queue
  FOR DELETE USING (tenant_id = current_tenant_id());

-- notification_preferences
DROP POLICY IF EXISTS tenant_select_notif_prefs ON notification_preferences;
CREATE POLICY tenant_select_notif_prefs ON notification_preferences
  FOR SELECT USING (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS tenant_insert_notif_prefs ON notification_preferences;
CREATE POLICY tenant_insert_notif_prefs ON notification_preferences
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS tenant_update_notif_prefs ON notification_preferences;
CREATE POLICY tenant_update_notif_prefs ON notification_preferences
  FOR UPDATE USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS tenant_delete_notif_prefs ON notification_preferences;
CREATE POLICY tenant_delete_notif_prefs ON notification_preferences
  FOR DELETE USING (tenant_id = current_tenant_id());

-- payment_promises
DROP POLICY IF EXISTS tenant_select_payment_promises ON payment_promises;
CREATE POLICY tenant_select_payment_promises ON payment_promises
  FOR SELECT USING (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS tenant_insert_payment_promises ON payment_promises;
CREATE POLICY tenant_insert_payment_promises ON payment_promises
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS tenant_update_payment_promises ON payment_promises;
CREATE POLICY tenant_update_payment_promises ON payment_promises
  FOR UPDATE USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS tenant_delete_payment_promises ON payment_promises;
CREATE POLICY tenant_delete_payment_promises ON payment_promises
  FOR DELETE USING (tenant_id = current_tenant_id());

-- payment_terms
DROP POLICY IF EXISTS tenant_select_payment_terms ON payment_terms;
CREATE POLICY tenant_select_payment_terms ON payment_terms
  FOR SELECT USING (tenant_id = current_tenant_id() OR tenant_id IS NULL);
DROP POLICY IF EXISTS tenant_insert_payment_terms ON payment_terms;
CREATE POLICY tenant_insert_payment_terms ON payment_terms
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS tenant_update_payment_terms ON payment_terms;
CREATE POLICY tenant_update_payment_terms ON payment_terms
  FOR UPDATE USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS tenant_delete_payment_terms ON payment_terms;
CREATE POLICY tenant_delete_payment_terms ON payment_terms
  FOR DELETE USING (tenant_id = current_tenant_id());

-- banks (table de référence globale, lecture pour tous les authentifiés)
DROP POLICY IF EXISTS tenant_select_banks ON banks;
CREATE POLICY tenant_select_banks ON banks
  FOR SELECT USING (true);
DROP POLICY IF EXISTS tenant_insert_banks ON banks;
CREATE POLICY tenant_insert_banks ON banks
  FOR INSERT WITH CHECK (current_user_role() = 'admin');
DROP POLICY IF EXISTS tenant_update_banks ON banks;
CREATE POLICY tenant_update_banks ON banks
  FOR UPDATE USING (current_user_role() = 'admin')
  WITH CHECK (current_user_role() = 'admin');
DROP POLICY IF EXISTS tenant_delete_banks ON banks;
CREATE POLICY tenant_delete_banks ON banks
  FOR DELETE USING (current_user_role() = 'admin');

-- chart_account_templates (table globale, lecture pour tous)
DROP POLICY IF EXISTS select_chart_account_templates ON chart_account_templates;
CREATE POLICY select_chart_account_templates ON chart_account_templates
  FOR SELECT USING (true);

-- currencies (table globale, lecture pour tous)
DROP POLICY IF EXISTS select_currencies ON currencies;
CREATE POLICY select_currencies ON currencies
  FOR SELECT USING (true);

-- legislation_packs (table globale, lecture pour tous)
DROP POLICY IF EXISTS select_legislation_packs ON legislation_packs;
CREATE POLICY select_legislation_packs ON legislation_packs
  FOR SELECT USING (true);

-- public_holidays (lecture pour le tenant ou global)
DROP POLICY IF EXISTS tenant_select_public_holidays ON public_holidays;
CREATE POLICY tenant_select_public_holidays ON public_holidays
  FOR SELECT USING (tenant_id = current_tenant_id() OR tenant_id IS NULL);
DROP POLICY IF EXISTS tenant_insert_public_holidays ON public_holidays;
CREATE POLICY tenant_insert_public_holidays ON public_holidays
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS tenant_update_public_holidays ON public_holidays;
CREATE POLICY tenant_update_public_holidays ON public_holidays
  FOR UPDATE USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS tenant_delete_public_holidays ON public_holidays;
CREATE POLICY tenant_delete_public_holidays ON public_holidays
  FOR DELETE USING (tenant_id = current_tenant_id());

-- tax_rates (lecture pour le tenant ou global)
DROP POLICY IF EXISTS tenant_select_tax_rates ON tax_rates;
CREATE POLICY tenant_select_tax_rates ON tax_rates
  FOR SELECT USING (tenant_id = current_tenant_id() OR tenant_id IS NULL);
DROP POLICY IF EXISTS tenant_insert_tax_rates ON tax_rates;
CREATE POLICY tenant_insert_tax_rates ON tax_rates
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS tenant_update_tax_rates ON tax_rates;
CREATE POLICY tenant_update_tax_rates ON tax_rates
  FOR UPDATE USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS tenant_delete_tax_rates ON tax_rates;
CREATE POLICY tenant_delete_tax_rates ON tax_rates
  FOR DELETE USING (tenant_id = current_tenant_id());

-- v_tenant_id (vue technique - SELECT uniquement pour authentifiés)
DROP POLICY IF EXISTS select_v_tenant_id ON v_tenant_id;
CREATE POLICY select_v_tenant_id ON v_tenant_id
  FOR SELECT USING (true);



-- ============================================================
-- SECTION 5 — FORCE ROW LEVEL SECURITY sur toutes les tables
-- ============================================================
-- Sans FORCE, le propriétaire des tables (postgres) ignore le RLS.
-- On l'active sur toutes les tables qui ont RLS activé.

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relrowsecurity = true
      AND c.relforcerowsecurity = false
      AND c.relkind = 'r'
      AND c.relname NOT LIKE 'pg_%'
      AND c.relname NOT IN ('sql_migrations_tracker')
    ORDER BY c.relname
  LOOP
    BEGIN
      EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', r.relname);
      RAISE NOTICE 'Forced RLS on %', r.relname;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'SKIP FORCE RLS on %: %', r.relname, SQLERRM;
    END;
  END LOOP;
END;
$$;


-- ============================================================
-- SECTION 6 — SET search_path sur fonctions SECURITY DEFINER
-- ============================================================
-- Protège contre les attaques par search_path hijacking.

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid, p.proname, n.nspname as schema_name
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef = true
      AND NOT pg_get_functiondef(p.oid) ILIKE '%SET search_path%'
    ORDER BY p.proname
  LOOP
    BEGIN
      EXECUTE format('ALTER FUNCTION %I.%I SET search_path = public, auth', r.schema_name, r.proname);
      RAISE NOTICE 'Added search_path to %', r.proname;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'SKIP search_path on %: %', r.proname, SQLERRM;
    END;
  END LOOP;
END;
$$;

-- ============================================================
-- RÉCAPITULATIF
-- ============================================================
-- Section 1 : Suppression de 4 policies permissives sur tenant_users
-- Section 2 : Renforcement de 3 policies sur users (rôle admin)
-- Section 3 : Ajout de 4 policies sur project_members
-- Section 4 : Ajout de ~40 policies sur 13 tables sans policies
-- Section 5 : FORCE ROW LEVEL SECURITY sur ~62 tables
-- Section 6 : SET search_path sur fonctions SECURITY DEFINER
-- ============================================================
