-- Sprint E: Sortie du Salarié, Notes de Frais & Entretiens
-- Tables: employee_exit_processes

-- ============ employee_exit_processes (Suivi des sorties) ============
CREATE TABLE IF NOT EXISTS employee_exit_processes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  exit_date date NOT NULL,
  exit_reason text NOT NULL,
  step int DEFAULT 1,
  status text DEFAULT 'in_progress' CHECK (status IN ('in_progress', 'completed', 'cancelled')),

  -- Solde de tout compte
  cp_indemnity decimal(15,2) DEFAULT 0,
  rtt_indemnity decimal(15,2) DEFAULT 0,
  recovery_indemnity decimal(15,2) DEFAULT 0,
  bonus_amount decimal(15,2) DEFAULT 0,
  advance_deduction decimal(15,2) DEFAULT 0,
  overtime_amount decimal(15,2) DEFAULT 0,
  total_gross decimal(15,2) DEFAULT 0,
  total_net decimal(15,2) DEFAULT 0,

  -- Documents
  work_certificate_url text,
  settlement_receipt_url text,
  pole_emploi_attestation_url text,
  dsn_exit_url text,
  documents_generated boolean DEFAULT false,

  -- DSN
  dsn_exit_generated boolean DEFAULT false,
  dsn_exit_transmitted boolean DEFAULT false,

  -- Bulletin de sortie
  exit_payslip_id uuid,

  notes text,
  created_at timestamptz DEFAULT now(),
  completed_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_exit_processes_employee ON employee_exit_processes(employee_id);
CREATE INDEX IF NOT EXISTS idx_exit_processes_status ON employee_exit_processes(status);
ALTER TABLE employee_exit_processes ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_employee_exit_processes') THEN
    CREATE POLICY "allow_all_employee_exit_processes" ON employee_exit_processes FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
