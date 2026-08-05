-- ============================================
-- 68_module_documents_storage_rls.sql
-- Document Management System: RLS policies + Storage buckets
-- ============================================
-- Prerequisites:
--   - Tables module_documents, module_document_access_log, module_document_shares already created
--   - Functions current_tenant_id(), current_user_role(), current_user_permissions() exist
--   - Run 69_module_access_management.sql FIRST for module_roles, guest_permissions,
--     and helper functions (current_module_role, has_module_access, etc.)
-- ============================================

-- ============================================
-- 1. MODULE ACCESS (see 69_module_access_management.sql)
-- ============================================
-- module_roles and guest_permissions columns, helper functions, and indexes
-- are defined in 69_module_access_management.sql to keep access management
-- independent from the document system.

-- ============================================
-- 3. RLS ON module_documents
-- ============================================
ALTER TABLE module_documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS module_documents_select ON module_documents;
DROP POLICY IF EXISTS module_documents_insert ON module_documents;
DROP POLICY IF EXISTS module_documents_update ON module_documents;
DROP POLICY IF EXISTS module_documents_delete ON module_documents;

-- SELECT: same tenant + has module access
CREATE POLICY module_documents_select ON module_documents
  FOR SELECT USING (
    tenant_id = current_tenant_id()
    AND (
      current_user_role() = 'admin'
      OR has_module_access(module)
    )
  );

-- INSERT: same tenant + non-guest role in module
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

-- UPDATE: admin or director/manager in the module
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

-- DELETE: admin or director in the module
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

-- ============================================
-- 4. RLS ON module_document_access_log
-- ============================================
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

-- ============================================
-- 5. RLS ON module_document_shares
-- ============================================
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

-- ============================================
-- 6. STORAGE BUCKETS
-- ============================================
-- Insert buckets into storage.buckets (Supabase internal table)
-- These are idempotent — safe to run multiple times

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  ('project-docs', 'project-docs', false, 52428800, ARRAY[
    'application/pdf', 'image/png', 'image/jpeg', 'image/webp',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'application/msword', 'application/vnd.ms-excel',
    'text/plain', 'text/csv', 'application/zip'
  ])
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  ('accounting-docs', 'accounting-docs', false, 52428800, ARRAY[
    'application/pdf', 'image/png', 'image/jpeg', 'image/webp',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.ms-excel', 'text/csv', 'application/zip'
  ])
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  ('hr-docs', 'hr-docs', false, 52428800, ARRAY[
    'application/pdf', 'image/png', 'image/jpeg', 'image/webp',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/msword', 'text/plain', 'application/zip'
  ])
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  ('commercial-docs', 'commercial-docs', false, 52428800, ARRAY[
    'application/pdf', 'image/png', 'image/jpeg', 'image/webp',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/msword', 'application/vnd.ms-excel', 'text/csv', 'application/zip'
  ])
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  ('general-docs', 'general-docs', false, 52428800, ARRAY[
    'application/pdf', 'image/png', 'image/jpeg', 'image/webp',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'application/msword', 'application/vnd.ms-excel',
    'text/plain', 'text/csv', 'application/zip'
  ])
ON CONFLICT (id) DO NOTHING;

-- ============================================
-- 7. STORAGE RLS POLICIES
-- ============================================
-- Path convention: {tenant_id}/{entity_id}/{filename}
-- We use (storage.foldername(name))[1] to extract the tenant_id from the path

-- ---- project-docs ----
DROP POLICY IF EXISTS project_docs_upload ON storage.objects;
DROP POLICY IF EXISTS project_docs_download ON storage.objects;
DROP POLICY IF EXISTS project_docs_delete ON storage.objects;

CREATE POLICY project_docs_upload ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'project-docs'
    AND (storage.foldername(name))[1] = current_tenant_id()::text
    AND (
      current_user_role() = 'admin'
      OR (
        has_module_access('projectManagement')
        AND current_module_role('projectManagement') NOT IN ('guest')
      )
    )
  );

CREATE POLICY project_docs_download ON storage.objects
  FOR SELECT USING (
    bucket_id = 'project-docs'
    AND (storage.foldername(name))[1] = current_tenant_id()::text
    AND (
      current_user_role() = 'admin'
      OR has_module_access('projectManagement')
    )
  );

CREATE POLICY project_docs_delete ON storage.objects
  FOR DELETE USING (
    bucket_id = 'project-docs'
    AND (storage.foldername(name))[1] = current_tenant_id()::text
    AND (
      current_user_role() = 'admin'
      OR current_module_role('projectManagement') IN ('project_director', 'project_manager')
    )
  );

-- ---- accounting-docs ----
DROP POLICY IF EXISTS accounting_docs_upload ON storage.objects;
DROP POLICY IF EXISTS accounting_docs_download ON storage.objects;
DROP POLICY IF EXISTS accounting_docs_delete ON storage.objects;

CREATE POLICY accounting_docs_upload ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'accounting-docs'
    AND (storage.foldername(name))[1] = current_tenant_id()::text
    AND (
      current_user_role() = 'admin'
      OR current_module_role('accounting') IN ('accountant', 'custom')
    )
  );

CREATE POLICY accounting_docs_download ON storage.objects
  FOR SELECT USING (
    bucket_id = 'accounting-docs'
    AND (storage.foldername(name))[1] = current_tenant_id()::text
    AND (
      current_user_role() = 'admin'
      OR has_module_access('accounting')
    )
  );

CREATE POLICY accounting_docs_delete ON storage.objects
  FOR DELETE USING (
    bucket_id = 'accounting-docs'
    AND (storage.foldername(name))[1] = current_tenant_id()::text
    AND (
      current_user_role() = 'admin'
      OR current_module_role('accounting') = 'accountant'
    )
  );

-- ---- hr-docs ----
DROP POLICY IF EXISTS hr_docs_upload ON storage.objects;
DROP POLICY IF EXISTS hr_docs_download ON storage.objects;
DROP POLICY IF EXISTS hr_docs_delete ON storage.objects;

CREATE POLICY hr_docs_upload ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'hr-docs'
    AND (storage.foldername(name))[1] = current_tenant_id()::text
    AND (
      current_user_role() = 'admin'
      OR (
        has_module_access('hr')
        AND current_module_role('hr') NOT IN ('guest')
      )
    )
  );

CREATE POLICY hr_docs_download ON storage.objects
  FOR SELECT USING (
    bucket_id = 'hr-docs'
    AND (storage.foldername(name))[1] = current_tenant_id()::text
    AND (
      current_user_role() = 'admin'
      OR has_module_access('hr')
    )
  );

CREATE POLICY hr_docs_delete ON storage.objects
  FOR DELETE USING (
    bucket_id = 'hr-docs'
    AND (storage.foldername(name))[1] = current_tenant_id()::text
    AND (
      current_user_role() = 'admin'
      OR current_module_role('hr') IN ('hr_director', 'hr_manager')
    )
  );

-- ---- commercial-docs ----
DROP POLICY IF EXISTS commercial_docs_upload ON storage.objects;
DROP POLICY IF EXISTS commercial_docs_download ON storage.objects;
DROP POLICY IF EXISTS commercial_docs_delete ON storage.objects;

CREATE POLICY commercial_docs_upload ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'commercial-docs'
    AND (storage.foldername(name))[1] = current_tenant_id()::text
    AND (
      current_user_role() = 'admin'
      OR (
        has_module_access('commercial')
        AND current_module_role('commercial') NOT IN ('guest')
      )
    )
  );

CREATE POLICY commercial_docs_download ON storage.objects
  FOR SELECT USING (
    bucket_id = 'commercial-docs'
    AND (storage.foldername(name))[1] = current_tenant_id()::text
    AND (
      current_user_role() = 'admin'
      OR has_module_access('commercial')
    )
  );

CREATE POLICY commercial_docs_delete ON storage.objects
  FOR DELETE USING (
    bucket_id = 'commercial-docs'
    AND (storage.foldername(name))[1] = current_tenant_id()::text
    AND (
      current_user_role() = 'admin'
      OR current_module_role('commercial') IN ('sales_director')
    )
  );

-- ---- general-docs ----
DROP POLICY IF EXISTS general_docs_upload ON storage.objects;
DROP POLICY IF EXISTS general_docs_download ON storage.objects;
DROP POLICY IF EXISTS general_docs_delete ON storage.objects;

CREATE POLICY general_docs_upload ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'general-docs'
    AND (storage.foldername(name))[1] = current_tenant_id()::text
    AND current_user_role() = 'admin'
  );

CREATE POLICY general_docs_download ON storage.objects
  FOR SELECT USING (
    bucket_id = 'general-docs'
    AND (storage.foldername(name))[1] = current_tenant_id()::text
    AND current_user_role() = 'admin'
  );

CREATE POLICY general_docs_delete ON storage.objects
  FOR DELETE USING (
    bucket_id = 'general-docs'
    AND (storage.foldername(name))[1] = current_tenant_id()::text
    AND current_user_role() = 'admin'
  );

-- ============================================
-- 8. INDEXES
-- ============================================
CREATE INDEX IF NOT EXISTS idx_module_documents_tenant ON module_documents(tenant_id);
CREATE INDEX IF NOT EXISTS idx_module_documents_module ON module_documents(module);
CREATE INDEX IF NOT EXISTS idx_module_documents_entity ON module_documents(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_module_documents_status ON module_documents(status);
CREATE INDEX IF NOT EXISTS idx_module_documents_confidentiality ON module_documents(confidentiality);
CREATE INDEX IF NOT EXISTS idx_module_documents_uploaded_by ON module_documents(uploaded_by);
CREATE INDEX IF NOT EXISTS idx_module_documents_expires ON module_documents(expires_at);
CREATE INDEX IF NOT EXISTS idx_module_documents_created ON module_documents(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_doc_access_log_tenant ON module_document_access_log(tenant_id);
CREATE INDEX IF NOT EXISTS idx_doc_access_log_doc ON module_document_access_log(document_id);
CREATE INDEX IF NOT EXISTS idx_doc_access_log_user ON module_document_access_log(user_id);

CREATE INDEX IF NOT EXISTS idx_doc_shares_tenant ON module_document_shares(tenant_id);
CREATE INDEX IF NOT EXISTS idx_doc_shares_doc ON module_document_shares(document_id);
CREATE INDEX IF NOT EXISTS idx_doc_shares_token ON module_document_shares(share_token);

-- Indexes for module_roles and guest_permissions are in 69_module_access_management.sql

-- ============================================
-- 9. HELPER: increment_download_count
-- ============================================
CREATE OR REPLACE FUNCTION increment_download_count(doc_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE module_documents
  SET download_count = download_count + 1
  WHERE id = doc_id AND tenant_id = current_tenant_id();
END;
$$;

GRANT EXECUTE ON FUNCTION increment_download_count(uuid) TO authenticated;
