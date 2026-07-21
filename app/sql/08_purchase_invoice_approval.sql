-- ============================================
-- BON À PAYER — Purchase invoice approval workflow
-- ============================================
-- Adds approval_status, approved_by, approved_at
-- columns to purchase_invoices table
-- ============================================

ALTER TABLE purchase_invoices
  ADD COLUMN IF NOT EXISTS approval_status text DEFAULT 'pending'
  CHECK (approval_status IN ('pending', 'approved', 'rejected'));

ALTER TABLE purchase_invoices
  ADD COLUMN IF NOT EXISTS approved_by uuid;

ALTER TABLE purchase_invoices
  ADD COLUMN IF NOT EXISTS approved_at timestamptz;

-- Index for filtering pending approvals
CREATE INDEX IF NOT EXISTS idx_purchase_invoices_approval
  ON purchase_invoices(approval_status) WHERE approval_status = 'pending';
