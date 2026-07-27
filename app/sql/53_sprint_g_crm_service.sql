-- ============================================================
-- Sprint G: CRM Service Client
-- File: 53_sprint_g_crm_service.sql
-- ============================================================

-- Service Tickets
CREATE TABLE IF NOT EXISTS service_tickets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  number text NOT NULL,
  customer_id uuid NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  contact_id uuid REFERENCES customer_contacts(id) ON DELETE SET NULL,
  subject text NOT NULL,
  description text,
  category text,
  priority text DEFAULT 'normal',
  status text DEFAULT 'open',
  assigned_to text,
  sla_due_date timestamptz,
  first_response_at timestamptz,
  resolved_at timestamptz,
  closed_at timestamptz,
  satisfaction_rating integer,
  satisfaction_comment text,
  tags text[],
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tk_customer ON service_tickets(customer_id);
CREATE INDEX IF NOT EXISTS idx_tk_status ON service_tickets(status);
CREATE INDEX IF NOT EXISTS idx_tk_assigned ON service_tickets(assigned_to);
ALTER TABLE service_tickets ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_service_tickets') THEN
    CREATE POLICY "allow_all_service_tickets" ON service_tickets FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- Service Ticket Messages
CREATE TABLE IF NOT EXISTS service_ticket_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  ticket_id uuid NOT NULL REFERENCES service_tickets(id) ON DELETE CASCADE,
  author text NOT NULL,
  author_type text NOT NULL,
  message text NOT NULL,
  attachments jsonb,
  is_internal boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tm_ticket ON service_ticket_messages(ticket_id);
ALTER TABLE service_ticket_messages ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_service_ticket_messages') THEN
    CREATE POLICY "allow_all_service_ticket_messages" ON service_ticket_messages FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- Service Contracts
CREATE TABLE IF NOT EXISTS service_contracts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  number text NOT NULL,
  customer_id uuid NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  name text NOT NULL,
  contract_type text,
  start_date date NOT NULL,
  end_date date,
  status text DEFAULT 'active',
  sla_response_hours integer,
  sla_resolution_hours integer,
  coverage text,
  max_tickets integer,
  used_tickets integer DEFAULT 0,
  amount numeric(15,2),
  notes text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sc_customer ON service_contracts(customer_id);
ALTER TABLE service_contracts ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_service_contracts') THEN
    CREATE POLICY "allow_all_service_contracts" ON service_contracts FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- Knowledge Base Articles
CREATE TABLE IF NOT EXISTS knowledge_base_articles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  title text NOT NULL,
  category text,
  content text NOT NULL,
  tags text[],
  author text,
  status text DEFAULT 'draft',
  views integer DEFAULT 0,
  helpful_count integer DEFAULT 0,
  not_helpful_count integer DEFAULT 0,
  is_public boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_kb_category ON knowledge_base_articles(category);
CREATE INDEX IF NOT EXISTS idx_kb_status ON knowledge_base_articles(status);
ALTER TABLE knowledge_base_articles ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_kb_articles') THEN
    CREATE POLICY "allow_all_kb_articles" ON knowledge_base_articles FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
