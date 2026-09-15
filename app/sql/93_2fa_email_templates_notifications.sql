-- Migration 93 : 2FA TOTP, Templates Email, Notifications globales
-- Comble les lacunes identifiées vs PayFit, Pennylane, Sage, etc.

BEGIN;

-- ============================================================
-- 1. TABLE : user_totp (2FA TOTP)
-- ============================================================
CREATE TABLE IF NOT EXISTS user_totp (
  id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     uuid NOT NULL,           -- réf. auth.users (Supabase)
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  secret_enc  text NOT NULL,           -- secret TOTP chiffré (AES)
  backup_codes jsonb NOT NULL DEFAULT '[]'::jsonb,  -- codes de récupération hashés
  enabled     boolean NOT NULL DEFAULT false,
  enabled_at  timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_user_totp_user_tenant ON user_totp(user_id, tenant_id);
CREATE INDEX IF NOT EXISTS idx_user_totp_tenant ON user_totp(tenant_id);

ALTER TABLE user_totp ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_totp FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_select_user_totp ON user_totp
  FOR SELECT USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_insert_user_totp ON user_totp
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_update_user_totp ON user_totp
  FOR UPDATE USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_delete_user_totp ON user_totp
  FOR DELETE USING (tenant_id = current_tenant_id());

-- ============================================================
-- 2. TABLE : email_templates (templates personnalisables)
-- ============================================================
CREATE TABLE IF NOT EXISTS email_templates (
  id            uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id     uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  template_key  text NOT NULL,          -- ex: 'invoice.created', 'payslip.ready', 'payment.reminder'
  subject       text NOT NULL,
  body_html     text NOT NULL,
  body_text     text,
  variables     jsonb NOT NULL DEFAULT '[]'::jsonb,  -- liste des variables disponibles
  locale        text NOT NULL DEFAULT 'fr',
  active        boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_email_templates_tenant_key_locale
  ON email_templates(tenant_id, template_key, locale);
CREATE INDEX IF NOT EXISTS idx_email_templates_tenant ON email_templates(tenant_id);

ALTER TABLE email_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE email_templates FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_select_email_templates ON email_templates
  FOR SELECT USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_insert_email_templates ON email_templates
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_update_email_templates ON email_templates
  FOR UPDATE USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_delete_email_templates ON email_templates
  FOR DELETE USING (tenant_id = current_tenant_id());

-- ============================================================
-- 3. TABLE : notifications (centre de notifications global)
-- ============================================================
CREATE TABLE IF NOT EXISTS notifications (
  id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  user_id     uuid,                    -- réf. auth.users (Supabase)
  category    text NOT NULL,             -- 'accounting', 'hr', 'sales', 'system', 'project'
  severity    text NOT NULL DEFAULT 'info',  -- 'info', 'warning', 'error', 'success'
  title       text NOT NULL,
  message     text NOT NULL,
  link        text,                      -- URL de redirection au clic
  metadata    jsonb NOT NULL DEFAULT '{}'::jsonb,
  read_at     timestamptz,               -- NULL = non lu
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notifications_tenant_unread
  ON notifications(tenant_id, user_id, read_at) WHERE read_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_notifications_tenant_date
  ON notifications(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id, read_at);

ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_select_notifications ON notifications
  FOR SELECT USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_insert_notifications ON notifications
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_update_notifications ON notifications
  FOR UPDATE USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_delete_notifications ON notifications
  FOR DELETE USING (tenant_id = current_tenant_id());

-- ============================================================
-- 4. FONCTION : create_notification (SECURITY DEFINER)
-- ============================================================
CREATE OR REPLACE FUNCTION create_notification(
  p_category  text,
  p_title     text,
  p_message   text,
  p_user_id   uuid DEFAULT NULL,
  p_severity  text DEFAULT 'info',
  p_link      text DEFAULT NULL,
  p_metadata  jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id uuid;
  v_tenant uuid := current_tenant_id();
BEGIN
  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  INSERT INTO notifications (tenant_id, user_id, category, severity, title, message, link, metadata)
  VALUES (v_tenant, p_user_id, p_category, p_severity, p_title, p_message, p_link, p_metadata)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION create_notification TO authenticated;

-- ============================================================
-- 5. FONCTION : mark_notification_read
-- ============================================================
CREATE OR REPLACE FUNCTION mark_notification_read(p_notification_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE notifications
  SET read_at = now()
  WHERE id = p_notification_id
    AND tenant_id = current_tenant_id();
END;
$$;

GRANT EXECUTE ON FUNCTION mark_notification_read TO authenticated;

-- ============================================================
-- 6. FONCTION : mark_all_notifications_read
-- ============================================================
CREATE OR REPLACE FUNCTION mark_all_notifications_read(p_user_id uuid DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE notifications
  SET read_at = now()
  WHERE read_at IS NULL
    AND tenant_id = current_tenant_id()
    AND (p_user_id IS NULL OR user_id = p_user_id OR user_id IS NULL);
END;
$$;

GRANT EXECUTE ON FUNCTION mark_all_notifications_read TO authenticated;

-- ============================================================
-- 7. FONCTION : get_unread_notification_count
-- ============================================================
CREATE OR REPLACE FUNCTION get_unread_notification_count(p_user_id uuid DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count integer;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM notifications
  WHERE read_at IS NULL
    AND tenant_id = current_tenant_id()
    AND (p_user_id IS NULL OR user_id = p_user_id OR user_id IS NULL);

  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION get_unread_notification_count TO authenticated;

-- ============================================================
-- 8. TRIGGER : notification automatique sur facture impayée
-- ============================================================
CREATE OR REPLACE FUNCTION notify_invoice_overdue()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.status = 'sent' AND NEW.due_date < now() AND OLD.due_date >= now() THEN
    PERFORM create_notification(
      'sales',
      'Facture en retard de paiement',
      'La facture ' || NEW.number || ' est maintenant en retard de paiement (échéance: ' || NEW.due_date::date || ')',
      NULL, 'warning',
      '/invoices/' || NEW.id
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_invoice_overdue ON invoices;
CREATE TRIGGER trigger_invoice_overdue
  AFTER UPDATE ON invoices
  FOR EACH ROW
  EXECUTE FUNCTION notify_invoice_overdue();

-- ============================================================
-- 9. TRIGGER : notification sur bulletin de paie généré
-- ============================================================
CREATE OR REPLACE FUNCTION notify_payslip_ready()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.status = 'draft' AND (OLD.status IS NULL OR OLD.status <> 'draft') THEN
    PERFORM create_notification(
      'hr',
      'Bulletin de paie disponible',
      'Votre bulletin de paie de ' || to_char(NEW.period_start, 'MM/YYYY') || ' est disponible.',
      NEW.employee_id, 'info',
      '/pay-slips/' || NEW.id
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_payslip_ready ON pay_slips;
CREATE TRIGGER trigger_payslip_ready
  AFTER INSERT OR UPDATE ON pay_slips
  FOR EACH ROW
  EXECUTE FUNCTION notify_payslip_ready();

-- ============================================================
-- 10. TRIGGER : notification sur rapprochement bancaire
-- ============================================================
CREATE OR REPLACE FUNCTION notify_bank_reconciliation_needed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_curr text;
BEGIN
  v_curr := COALESCE(NEW.original_currency, 'EUR');

  IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND NEW.reconciled = false AND OLD.reconciled = true) THEN
    PERFORM create_notification(
      'banking',
      'Transaction bancaire à rapprocher',
      'Une nouvelle transaction bancaire de ' || NEW.amount || ' ' || v_curr || ' nécessite un rapprochement.',
      NULL, 'info',
      '/bank-reconciliation'
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_bank_recon_needed ON bank_transactions;
CREATE TRIGGER trigger_bank_recon_needed
  AFTER INSERT OR UPDATE ON bank_transactions
  FOR EACH ROW
  WHEN (NEW.reconciled = false)
  EXECUTE FUNCTION notify_bank_reconciliation_needed();

-- ============================================================
-- 11. Templates email par défaut (insertion pour tous les tenants existants)
-- ============================================================
INSERT INTO email_templates (tenant_id, template_key, subject, body_html, body_text, variables, locale)
SELECT t.id, 'invoice.created', 'Nouvelle facture {{invoice_number}}',
  '<h1>Facture {{invoice_number}}</h1><p>Montant : {{amount}} {{currency}}</p><p>Échéance : {{due_date}}</p><p>Merci de régler cette facture dans les meilleurs délais.</p>',
  'Facture {{invoice_number}} - Montant : {{amount}} {{currency}} - Échéance : {{due_date}}',
  '["invoice_number","amount","currency","due_date","customer_name"]'::jsonb,
  'fr'
FROM tenants t
WHERE NOT EXISTS (
  SELECT 1 FROM email_templates et
  WHERE et.tenant_id = t.id AND et.template_key = 'invoice.created' AND et.locale = 'fr'
)
ON CONFLICT (tenant_id, template_key, locale) DO NOTHING;

INSERT INTO email_templates (tenant_id, template_key, subject, body_html, body_text, variables, locale)
SELECT t.id, 'payment.reminder', 'Rappel de paiement - Facture {{invoice_number}}',
  '<h1>Rappel de paiement</h1><p>Votre facture {{invoice_number}} d''un montant de {{amount}} {{currency}} est en retard de {{days_overdue}} jours.</p><p>Merci de procéder au règlement dès que possible.</p>',
  'Rappel : Facture {{invoice_number}} - {{amount}} {{currency}} - Retard : {{days_overdue}} jours',
  '["invoice_number","amount","currency","days_overdue","customer_name"]'::jsonb,
  'fr'
FROM tenants t
WHERE NOT EXISTS (
  SELECT 1 FROM email_templates et
  WHERE et.tenant_id = t.id AND et.template_key = 'payment.reminder' AND et.locale = 'fr'
)
ON CONFLICT (tenant_id, template_key, locale) DO NOTHING;

INSERT INTO email_templates (tenant_id, template_key, subject, body_html, body_text, variables, locale)
SELECT t.id, 'payslip.ready', 'Votre bulletin de paie est disponible',
  '<h1>Bulletin de paie</h1><p>Votre bulletin de paie pour la période {{period}} est disponible.</p><p>Net à payer : {{net_salary}}</p>',
  'Bulletin de paie {{period}} - Net : {{net_salary}}',
  '["period","net_salary","employee_name"]'::jsonb,
  'fr'
FROM tenants t
WHERE NOT EXISTS (
  SELECT 1 FROM email_templates et
  WHERE et.tenant_id = t.id AND et.template_key = 'payslip.ready' AND et.locale = 'fr'
)
ON CONFLICT (tenant_id, template_key, locale) DO NOTHING;

COMMIT;
