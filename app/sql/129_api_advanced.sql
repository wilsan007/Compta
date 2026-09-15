-- ============================================================
-- 129_api_advanced.sql
-- API-01 : Idempotence, journal des appels, portée des clés
-- API-02 : Catalogue d'événements webhooks
-- ============================================================

-- ============================================================
-- API-01 : Idempotence
-- ============================================================
CREATE TABLE IF NOT EXISTS idempotency_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  idempotency_key text NOT NULL,
  response jsonb NOT NULL,
  status int NOT NULL,
  expires_at timestamptz NOT NULL,
  created_at timestamptz DEFAULT now(),
  UNIQUE (tenant_id, idempotency_key)
);

ALTER TABLE idempotency_records ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS idempotency_records_tenant ON idempotency_records;
CREATE POLICY idempotency_records_tenant ON idempotency_records
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- Index pour la recherche rapide
CREATE INDEX IF NOT EXISTS idx_idempotency_lookup
  ON idempotency_records (tenant_id, idempotency_key);

-- Nettoyage automatique des enregistrements expirés
CREATE OR REPLACE FUNCTION cleanup_expired_idempotency()
RETURNS int
LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  WITH deleted AS (
    DELETE FROM idempotency_records WHERE expires_at < now() RETURNING 1
  )
  SELECT COUNT(*) FROM deleted;
$$;

-- ============================================================
-- API-01 : Journal des appels API
-- ============================================================
CREATE TABLE IF NOT EXISTS api_call_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  api_key_id uuid,
  tenant_id uuid NOT NULL,
  method text NOT NULL,
  path text NOT NULL,
  status int NOT NULL,
  idempotency_key text,
  ip_address text,
  user_agent text,
  duration_ms int,
  called_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE api_call_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS api_call_logs_tenant ON api_call_logs;
CREATE POLICY api_call_logs_tenant ON api_call_logs
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

CREATE INDEX IF NOT EXISTS idx_api_call_logs_tenant_date
  ON api_call_logs (tenant_id, called_at DESC);
CREATE INDEX IF NOT EXISTS idx_api_call_logs_key
  ON api_call_logs (api_key_id, called_at DESC);

-- ============================================================
-- API-01 : Portée des clés (permissions)
-- ============================================================
ALTER TABLE api_keys ADD COLUMN IF NOT EXISTS scope text[] DEFAULT ARRAY['read'];
-- Valeurs possibles : 'read', 'write', 'invoices', 'customers', 'suppliers', 'products', 'accounting', 'payroll', 'hr'

-- ============================================================
-- API-02 : Catalogue d'événements webhooks
-- ============================================================
CREATE TABLE IF NOT EXISTS webhook_event_catalog (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_name text NOT NULL UNIQUE,
  description text NOT NULL,
  payload_schema jsonb,
  category text,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE webhook_event_catalog ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS webhook_event_catalog_all ON webhook_event_catalog;
CREATE POLICY webhook_event_catalog_all ON webhook_event_catalog
  FOR ALL USING (true) WITH CHECK (true);

-- Catalogue des événements disponibles
INSERT INTO webhook_event_catalog (event_name, description, category, payload_schema) VALUES
  ('invoice.created', 'Facture créée', 'sales', '{"invoice_id": "uuid", "number": "text", "customer_id": "uuid", "total": "numeric"}'),
  ('invoice.paid', 'Facture payée', 'sales', '{"invoice_id": "uuid", "number": "text", "amount_paid": "numeric"}'),
  ('invoice.overdue', 'Facture en retard', 'sales', '{"invoice_id": "uuid", "number": "text", "days_overdue": "int"}'),
  ('customer.created', 'Client créé', 'crm', '{"customer_id": "uuid", "name": "text"}'),
  ('customer.updated', 'Client modifié', 'crm', '{"customer_id": "uuid", "changes": "jsonb"}'),
  ('supplier.created', 'Fournisseur créé', 'purchases', '{"supplier_id": "uuid", "name": "text"}'),
  ('journal_entry.posted', 'Écriture comptable validée', 'accounting', '{"entry_id": "uuid", "number": "text", "total_debit": "numeric"}'),
  ('payslip.created', 'Bulletin de paie créé', 'hr', '{"payslip_id": "uuid", "employee_id": "uuid", "period": "text"}'),
  ('payslip.validated', 'Bulletin de paie validé', 'hr', '{"payslip_id": "uuid", "net_salary": "numeric"}'),
  ('vat_return.submitted', 'Déclaration TVA soumise', 'tax', '{"return_id": "uuid", "period": "text", "amount": "numeric"}'),
  ('dsn.transmitted', 'DSN transmise', 'hr', '{"dsn_id": "uuid", "period": "text"}'),
  ('payment.received', 'Règlement reçu', 'banking', '{"payment_id": "uuid", "amount": "numeric", "invoice_id": "uuid"}'),
  ('stock.low', 'Stock sous seuil', 'stock', '{"product_id": "uuid", "warehouse_id": "uuid", "quantity": "numeric", "threshold": "numeric"}'),
  ('manufacturing_order.completed', 'OF terminé', 'production', '{"mo_id": "uuid", "quantity_produced": "numeric"}'),
  ('purchase_order.confirmed', 'Commande achat confirmée', 'purchases', '{"po_id": "uuid", "supplier_id": "uuid", "total": "numeric"}')
ON CONFLICT (event_name) DO UPDATE SET
  description = EXCLUDED.description,
  payload_schema = EXCLUDED.payload_schema,
  category = EXCLUDED.category;

-- ============================================================
-- API-02 : File d'attente des webhooks (pour réessais)
-- ============================================================
CREATE TABLE IF NOT EXISTS webhook_delivery_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  endpoint_id uuid NOT NULL REFERENCES webhook_endpoints(id) ON DELETE CASCADE,
  event_name text NOT NULL,
  payload jsonb NOT NULL,
  signature text,
  attempts int DEFAULT 0,
  max_attempts int DEFAULT 5,
  next_attempt_at timestamptz DEFAULT now(),
  last_attempt_at timestamptz,
  last_response_status int,
  last_response_body text,
  status text DEFAULT 'pending' CHECK (status IN ('pending', 'delivered', 'failed', 'disabled')),
  created_at timestamptz DEFAULT now()
);

ALTER TABLE webhook_delivery_queue ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS webhook_delivery_queue_tenant ON webhook_delivery_queue;
CREATE POLICY webhook_delivery_queue_tenant ON webhook_delivery_queue
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

CREATE INDEX IF NOT EXISTS idx_webhook_queue_pending
  ON webhook_delivery_queue (next_attempt_at)
  WHERE status = 'pending';

-- Vue des webhooks en échec
CREATE OR REPLACE VIEW v_webhook_failures AS
SELECT
  q.tenant_id,
  q.id,
  q.event_name,
  q.endpoint_id,
  e.url,
  q.attempts,
  q.last_response_status,
  q.last_response_body,
  q.created_at,
  q.last_attempt_at
FROM webhook_delivery_queue q
JOIN webhook_endpoints e ON e.id = q.endpoint_id
WHERE q.tenant_id = current_tenant_id()
  AND q.status = 'failed'
ORDER BY q.last_attempt_at DESC;
