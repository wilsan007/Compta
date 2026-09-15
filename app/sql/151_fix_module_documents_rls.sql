-- ============================================================
-- 151_fix_module_documents_rls.sql
-- LOT1-07 : RLS module_documents jamais posée
--
-- Problème : La migration 68 crée les politiques RLS en utilisant
-- des fonctions (has_module_access, current_tenant_user_id,
-- current_module_role) qui ne sont définies que dans la migration 69.
-- Les politiques échouent silencieusement.
--
-- Fix : Réappliquer les 8 politiques maintenant que les fonctions
-- existent.
-- ============================================================

-- ============================================================
-- 1. RLS sur module_documents
-- ============================================================
ALTER TABLE module_documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS module_documents_select ON module_documents;
DROP POLICY IF EXISTS module_documents_insert ON module_documents;
DROP POLICY IF EXISTS module_documents_update ON module_documents;
DROP POLICY IF EXISTS module_documents_delete ON module_documents;

CREATE POLICY module_documents_select ON module_documents
  FOR SELECT USING (
    tenant_id = current_tenant_id()
    AND (
      current_user_role() = 'admin'
      OR has_module_access(module)
    )
  );

CREATE POLICY module_documents_insert ON module_documents
  FOR INSERT WITH CHECK (
    tenant_id = current_tenant_id()
    AND uploaded_by = current_tenant_user_id()
    AND (
      current_user_role() = 'admin'
      OR (
        has_module_access(module)
        AND current_module_role(module) NOT IN ('guest')
      )
    )
  );

CREATE POLICY module_documents_update ON module_documents
  FOR UPDATE USING (
    tenant_id = current_tenant_id()
    AND (
      current_user_role() = 'admin'
      OR (
        has_module_access(module)
        AND current_module_role(module) IN (
          'project_director', 'project_manager',
          'hr_director', 'hr_manager',
          'sales_director', 'sales_rep',
          'accountant', 'treasurer',
          'warehouse_manager', 'production_manager'
        )
      )
    )
  );

CREATE POLICY module_documents_delete ON module_documents
  FOR DELETE USING (
    tenant_id = current_tenant_id()
    AND (
      current_user_role() = 'admin'
      OR (
        has_module_access(module)
        AND current_module_role(module) IN (
          'project_director', 'hr_director', 'sales_director',
          'accountant', 'treasurer', 'warehouse_manager', 'production_manager'
        )
      )
    )
  );

-- ============================================================
-- 2. RLS sur module_document_access_log
-- ============================================================
ALTER TABLE module_document_access_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS doc_access_log_select ON module_document_access_log;
DROP POLICY IF EXISTS doc_access_log_insert ON module_document_access_log;

CREATE POLICY doc_access_log_select ON module_document_access_log
  FOR SELECT USING (
    tenant_id = current_tenant_id()
    AND (
      current_user_role() = 'admin'
      OR user_id = current_tenant_user_id()
    )
  );

CREATE POLICY doc_access_log_insert ON module_document_access_log
  FOR INSERT WITH CHECK (
    tenant_id = current_tenant_id()
    AND user_id = current_tenant_user_id()
  );

-- ============================================================
-- 3. RLS sur module_document_shares
-- ============================================================
ALTER TABLE module_document_shares ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS doc_shares_select ON module_document_shares;
DROP POLICY IF EXISTS doc_shares_insert ON module_document_shares;
DROP POLICY IF EXISTS doc_shares_update ON module_document_shares;
DROP POLICY IF EXISTS doc_shares_delete ON module_document_shares;

CREATE POLICY doc_shares_select ON module_document_shares
  FOR SELECT USING (
    tenant_id = current_tenant_id()
    AND (
      current_user_role() = 'admin'
      OR created_by = current_tenant_user_id()
    )
  );

CREATE POLICY doc_shares_insert ON module_document_shares
  FOR INSERT WITH CHECK (
    tenant_id = current_tenant_id()
    AND created_by = current_tenant_user_id()
  );

CREATE POLICY doc_shares_update ON module_document_shares
  FOR UPDATE USING (
    tenant_id = current_tenant_id()
    AND created_by = current_tenant_user_id()
  );

CREATE POLICY doc_shares_delete ON module_document_shares
  FOR DELETE USING (
    tenant_id = current_tenant_id()
    AND (
      current_user_role() = 'admin'
      OR created_by = current_tenant_user_id()
    )
  );
