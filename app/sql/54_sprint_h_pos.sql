-- Sprint H: POS / Saisie de Caisse
-- Tables: pos_terminals, pos_sessions, pos_tickets, pos_ticket_lines

-- pos_terminals (caisses)
CREATE TABLE IF NOT EXISTS pos_terminals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  warehouse_id uuid REFERENCES warehouses(id) ON DELETE SET NULL,
  location text,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE pos_terminals ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_pos_terminals') THEN
    DROP POLICY IF EXISTS "allow_all_pos_terminals" ON pos_terminals;
    CREATE POLICY "allow_all_pos_terminals" ON pos_terminals FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- pos_sessions (sessions de caisse)
CREATE TABLE IF NOT EXISTS pos_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  terminal_id uuid NOT NULL REFERENCES pos_terminals(id) ON DELETE CASCADE,
  user_email text NOT NULL,
  opening_amount numeric(15,2) DEFAULT 0,
  closing_amount numeric(15,2),
  expected_amount numeric(15,2),
  difference numeric(15,2),
  status text DEFAULT 'open',
  opened_at timestamptz DEFAULT now(),
  closed_at timestamptz,
  notes text
);
CREATE INDEX IF NOT EXISTS idx_ps_terminal ON pos_sessions(terminal_id);
CREATE INDEX IF NOT EXISTS idx_ps_status ON pos_sessions(status);
ALTER TABLE pos_sessions ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_pos_sessions') THEN
    DROP POLICY IF EXISTS "allow_all_pos_sessions" ON pos_sessions;
    CREATE POLICY "allow_all_pos_sessions" ON pos_sessions FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- pos_tickets (tickets de caisse)
CREATE TABLE IF NOT EXISTS pos_tickets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  number text NOT NULL,
  session_id uuid NOT NULL REFERENCES pos_sessions(id) ON DELETE CASCADE,
  terminal_id uuid NOT NULL REFERENCES pos_terminals(id) ON DELETE CASCADE,
  customer_id uuid REFERENCES customers(id) ON DELETE SET NULL,
  date timestamptz DEFAULT now(),
  subtotal numeric(15,2) DEFAULT 0,
  vat_total numeric(15,2) DEFAULT 0,
  total numeric(15,2) DEFAULT 0,
  payment_method text,
  amount_paid numeric(15,2) DEFAULT 0,
  change_given numeric(15,2) DEFAULT 0,
  status text DEFAULT 'completed',
  invoice_id uuid,
  notes text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pt_session ON pos_tickets(session_id);
CREATE INDEX IF NOT EXISTS idx_pt_date ON pos_tickets(date);
ALTER TABLE pos_tickets ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_pos_tickets') THEN
    DROP POLICY IF EXISTS "allow_all_pos_tickets" ON pos_tickets;
    CREATE POLICY "allow_all_pos_tickets" ON pos_tickets FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- pos_ticket_lines
CREATE TABLE IF NOT EXISTS pos_ticket_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  ticket_id uuid NOT NULL REFERENCES pos_tickets(id) ON DELETE CASCADE,
  product_id uuid REFERENCES products(id) ON DELETE SET NULL,
  description text NOT NULL,
  quantity numeric(15,2) NOT NULL DEFAULT 1,
  unit_price numeric(15,2) NOT NULL,
  vat_rate numeric(5,2) DEFAULT 0,
  line_total numeric(15,2) NOT NULL,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ptl_ticket ON pos_ticket_lines(ticket_id);
ALTER TABLE pos_ticket_lines ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_pos_ticket_lines') THEN
    DROP POLICY IF EXISTS "allow_all_pos_ticket_lines" ON pos_ticket_lines;
    CREATE POLICY "allow_all_pos_ticket_lines" ON pos_ticket_lines FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
