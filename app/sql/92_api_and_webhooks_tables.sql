-- ============================================================
-- 92_api_and_webhooks_tables.sql
--
-- Tables de support pour l'API publique et les webhooks sortants
-- ============================================================

-- ============================================================
-- 1. api_keys — Clés API pour l'accès public
-- ============================================================
CREATE TABLE IF NOT EXISTS api_keys (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id uuid NOT NULL,
  name text NOT NULL,                 -- Nom descriptif de la clé
  key_hash text NOT NULL UNIQUE,      -- Hash de la clé API (pas la clé elle-même)
  key_prefix text,                    -- Préfixe visible (ex: "onu_abc123...")
  permissions jsonb DEFAULT '[]'::jsonb,  -- Permissions: ['read:invoices', 'write:invoices', '*']
  rate_limit_per_min integer DEFAULT 100,
  active boolean DEFAULT true,
  expires_at timestamptz,
  last_used_at timestamptz,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz
);

ALTER TABLE api_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE api_keys FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_select_api_keys ON api_keys
  FOR SELECT USING (tenant_id = current_tenant_id() AND current_user_role() = 'admin');
CREATE POLICY tenant_insert_api_keys ON api_keys
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id() AND current_user_role() = 'admin');
CREATE POLICY tenant_update_api_keys ON api_keys
  FOR UPDATE USING (tenant_id = current_tenant_id() AND current_user_role() = 'admin')
  WITH CHECK (tenant_id = current_tenant_id() AND current_user_role() = 'admin');
CREATE POLICY tenant_delete_api_keys ON api_keys
  FOR DELETE USING (tenant_id = current_tenant_id() AND current_user_role() = 'admin');

CREATE INDEX IF NOT EXISTS idx_api_keys_hash ON api_keys(key_hash) WHERE active = true;
CREATE INDEX IF NOT EXISTS idx_api_keys_tenant ON api_keys(tenant_id);


-- ============================================================
-- 2. webhook_endpoints — URLs enregistrées pour les webhooks sortants
-- ============================================================
CREATE TABLE IF NOT EXISTS webhook_endpoints (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id uuid NOT NULL,
  name text NOT NULL,
  url text NOT NULL,
  secret text,                        -- Secret pour signature HMAC
  active_events jsonb DEFAULT '["*"]'::jsonb,  -- Événements déclencheurs
  active boolean DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE webhook_endpoints ENABLE ROW LEVEL SECURITY;
ALTER TABLE webhook_endpoints FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_select_webhook_endpoints ON webhook_endpoints
  FOR SELECT USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_insert_webhook_endpoints ON webhook_endpoints
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_update_webhook_endpoints ON webhook_endpoints
  FOR UPDATE USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_delete_webhook_endpoints ON webhook_endpoints
  FOR DELETE USING (tenant_id = current_tenant_id());

CREATE INDEX IF NOT EXISTS idx_webhook_endpoints_tenant ON webhook_endpoints(tenant_id, active);


-- ============================================================
-- 3. webhook_delivery_logs — Journal de livraison des webhooks
-- ============================================================
CREATE TABLE IF NOT EXISTS webhook_delivery_logs (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id uuid NOT NULL,
  endpoint_id uuid,
  url text NOT NULL,
  event text NOT NULL,
  status text NOT NULL,               -- 'delivered', 'failed', 'retry'
  attempt integer DEFAULT 1,
  response_code integer,
  response_body text,
  error_message text,
  delivered_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE webhook_delivery_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE webhook_delivery_logs FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_select_webhook_logs ON webhook_delivery_logs
  FOR SELECT USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_insert_webhook_logs ON webhook_delivery_logs
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id());

CREATE INDEX IF NOT EXISTS idx_webhook_logs_tenant_date ON webhook_delivery_logs(tenant_id, delivered_at DESC);
CREATE INDEX IF NOT EXISTS idx_webhook_logs_status ON webhook_delivery_logs(status) WHERE status != 'delivered';


-- ============================================================
-- 4. Trigger : notifier les webhooks sur création de facture
-- ============================================================
CREATE OR REPLACE FUNCTION notify_webhook_invoice_created()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- L'Edge Function outgoing-webhooks est appelée via pg_net ou Supabase
  -- Pour simplifier, on enregistre l'événement dans une file d'attente
  INSERT INTO webhook_delivery_logs (tenant_id, url, event, status, attempt)
  SELECT NEW.tenant_id, we.url, 'invoice.created', 'pending', 0
  FROM webhook_endpoints we
  WHERE we.tenant_id = NEW.tenant_id
    AND we.active = true
    AND (we.active_events @> '["invoice.created"]'::jsonb OR we.active_events @> '["*"]'::jsonb);

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS webhook_invoice_created ON invoices;
CREATE TRIGGER webhook_invoice_created
  AFTER INSERT ON invoices
  FOR EACH ROW EXECUTE FUNCTION notify_webhook_invoice_created();


-- ============================================================
-- 5. Trigger : notifier les webhooks sur paiement de facture
-- ============================================================
CREATE OR REPLACE FUNCTION notify_webhook_invoice_paid()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.payment_state = 'paid' AND (OLD.payment_state IS NULL OR OLD.payment_state != 'paid') THEN
    INSERT INTO webhook_delivery_logs (tenant_id, url, event, status, attempt)
    SELECT NEW.tenant_id, we.url, 'invoice.paid', 'pending', 0
    FROM webhook_endpoints we
    WHERE we.tenant_id = NEW.tenant_id
      AND we.active = true
      AND (we.active_events @> '["invoice.paid"]'::jsonb OR we.active_events @> '["*"]'::jsonb);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS webhook_invoice_paid ON invoices;
CREATE TRIGGER webhook_invoice_paid
  AFTER UPDATE ON invoices
  FOR EACH ROW
  WHEN (OLD.payment_state IS DISTINCT FROM NEW.payment_state)
  EXECUTE FUNCTION notify_webhook_invoice_paid();


-- ============================================================
-- RÉCAPITULATIF
-- ============================================================
-- 1. Table api_keys (clés API avec permissions et rate limit)
-- 2. Table webhook_endpoints (URLs + secrets + événements actifs)
-- 3. Table webhook_delivery_logs (journal de livraison)
-- 4. Trigger webhook_invoice_created
-- 5. Trigger webhook_invoice_paid
-- ============================================================
