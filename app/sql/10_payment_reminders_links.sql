-- ============================================
-- PAYMENT REMINDERS WITH ONLINE PAYMENT LINKS
-- ============================================
-- Extends collection_reminders table with
-- online payment link generation
-- ============================================

ALTER TABLE collection_reminders
  ADD COLUMN IF NOT EXISTS payment_link_token text UNIQUE;
ALTER TABLE collection_reminders
  ADD COLUMN IF NOT EXISTS payment_link_url text;
ALTER TABLE collection_reminders
  ADD COLUMN IF NOT EXISTS payment_link_expires_at timestamptz;
ALTER TABLE collection_reminders
  ADD COLUMN IF NOT EXISTS payment_status text DEFAULT 'unpaid'
  CHECK (payment_status IN ('unpaid', 'pending', 'paid', 'expired'));

CREATE INDEX IF NOT EXISTS idx_collection_reminders_link_token
  ON collection_reminders(payment_link_token) WHERE payment_link_token IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_collection_reminders_payment_status
  ON collection_reminders(payment_status);
