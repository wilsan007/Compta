-- ============================================
-- TVA TELE-DECLARATION (EDI-TVA)
-- ============================================
-- Tracks EDI-TVA submissions and
-- acknowledgment receipts
-- ============================================

ALTER TABLE vat_returns
  ADD COLUMN IF NOT EXISTS edi_tva_id text,
  ADD COLUMN IF NOT EXISTS edi_status text DEFAULT 'not_submitted'
  CHECK (edi_status IN ('not_submitted', 'preparing', 'submitted', 'acknowledged', 'rejected')),
  ADD COLUMN IF NOT EXISTS edi_submitted_at timestamptz,
  ADD COLUMN IF NOT EXISTS edi_acknowledgment text,
  ADD COLUMN IF NOT EXISTS edi_acknowledged_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_vat_returns_edi_status ON vat_returns(edi_status) WHERE edi_status != 'not_submitted';
