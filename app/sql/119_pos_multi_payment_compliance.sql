-- ============================================================
-- 119_pos_multi_payment_compliance.sql
-- POS-02 : Paiements multiples + POS-03 : Conformité loi anti-fraude
-- ============================================================

-- ============================================================
-- POS-02 : Moyens de paiement paramétrables
-- ============================================================
CREATE TABLE IF NOT EXISTS pos_payment_methods (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  name text NOT NULL,
  type text NOT NULL CHECK (type IN ('cash', 'card', 'check', 'voucher', 'transfer', 'other')),
  account_code text NOT NULL,     -- Compte comptable (531, 5112, 5115...)
  opens_cash_drawer boolean DEFAULT false,
  is_active boolean DEFAULT true,
  display_order int DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE pos_payment_methods ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pos_payment_methods_tenant ON pos_payment_methods;
CREATE POLICY pos_payment_methods_tenant ON pos_payment_methods
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- Seed : moyens de paiement standards (sera créé par l'application pour chaque tenant)
-- Désactivé ici car current_tenant_id() retourne NULL sans contexte de session

-- ============================================================
-- POS-02 : Table des paiements (un ticket peut avoir plusieurs paiements)
-- ============================================================
CREATE TABLE IF NOT EXISTS pos_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  ticket_id uuid NOT NULL,
  payment_method_id uuid NOT NULL,
  amount numeric NOT NULL,
  transaction_reference text,     -- Référence de transaction (numéro de carte, chèque...)
  created_at timestamptz DEFAULT now()
);

ALTER TABLE pos_payments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pos_payments_tenant ON pos_payments;
CREATE POLICY pos_payments_tenant ON pos_payments
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

CREATE INDEX IF NOT EXISTS idx_pos_payments_ticket
  ON pos_payments (tenant_id, ticket_id);

ALTER TABLE pos_sessions ADD COLUMN IF NOT EXISTS session_number text;

-- ============================================================
-- POS-02 : Ventiler l'écriture de clôture par moyen de paiement
-- Modifier post_pos_session_on_close pour utiliser pos_payments
-- ============================================================
CREATE OR REPLACE FUNCTION post_pos_session_on_close_multi()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_tid uuid := NEW.tenant_id;
  v_je_id uuid;
  v_line_num int := 1;
  v_total_sales numeric := 0;
  v_total_vat numeric := 0;
  v_ticket record;
  v_payment record;
  v_method_amount numeric;
  v_product record;
  v_je_number text;
  v_session_ref text;
BEGIN
  -- Ne se déclenche qu'à la fermeture
  IF NEW.status <> 'closed' OR OLD.status = 'closed' THEN
    RETURN NEW;
  END IF;

  v_session_ref := COALESCE(NEW.session_number, NEW.id::text);

  -- Calculer le total des ventes et TVA
  SELECT COALESCE(SUM(subtotal), 0), COALESCE(SUM(vat_total), 0)
  INTO v_total_sales, v_total_vat
  FROM pos_tickets
  WHERE session_id = NEW.id AND tenant_id = v_tid AND status = 'completed';

  IF v_total_sales = 0 THEN
    RETURN NEW;
  END IF;

  -- Générer un numéro d'écriture
  v_je_number := 'POS-' || NEW.id;

  -- Créer l'écriture de journal en draft
  INSERT INTO journal_entries (
    tenant_id, journal_code, number, date, description, status, created_at
  ) VALUES (
    v_tid, 'POS', v_je_number, CURRENT_DATE,
    'Clôture caisse session ' || v_session_ref, 'draft', now()
  )
  RETURNING id INTO v_je_id;

  -- POS-02 : Une ligne de débit par moyen de paiement
  FOR v_payment IN
    SELECT ppm.account_code, SUM(pp.amount) AS total
    FROM pos_payments pp
    JOIN pos_payment_methods ppm ON ppm.id = pp.payment_method_id AND ppm.tenant_id = v_tid
    JOIN pos_tickets pt ON pt.id = pp.ticket_id AND pt.tenant_id = v_tid
    WHERE pt.session_id = NEW.id AND pt.status = 'completed' AND pp.tenant_id = v_tid
    GROUP BY ppm.account_code
  LOOP
    INSERT INTO journal_lines (
      tenant_id, journal_id, line_order, account_code,
      debit, credit, created_at
    ) VALUES (
      v_tid, v_je_id, v_line_num, v_payment.account_code,
      v_payment.total, 0, now()
    );
    v_line_num := v_line_num + 1;
  END LOOP;

  -- Crédit des ventes (707000)
  INSERT INTO journal_lines (
    tenant_id, journal_id, line_order, account_code,
    debit, credit, created_at
  ) VALUES (
    v_tid, v_je_id, v_line_num, '707000', 0, v_total_sales, now()
  );
  v_line_num := v_line_num + 1;

  -- Crédit de la TVA (4457100)
  IF v_total_vat > 0 THEN
    INSERT INTO journal_lines (
      tenant_id, journal_id, line_order, account_code,
      debit, credit, created_at
    ) VALUES (
      v_tid, v_je_id, v_line_num, '4457100', 0, v_total_vat, now()
    );
    v_line_num := v_line_num + 1;
  END IF;

  -- Poster l'écriture
  UPDATE journal_entries SET status = 'posted' WHERE id = v_je_id;

  -- Créer les mouvements de stock sortants
  FOR v_product IN
    SELECT ptl.product_id, SUM(ptl.quantity) AS total_qty, pt2.warehouse_id
    FROM pos_ticket_lines ptl
    JOIN pos_tickets pt ON pt.id = ptl.ticket_id AND pt.tenant_id = ptl.tenant_id
    JOIN pos_sessions ps ON ps.id = pt.session_id AND ps.tenant_id = pt.tenant_id
    JOIN pos_terminals pt2 ON pt2.id = ps.terminal_id AND pt2.tenant_id = ps.tenant_id
    WHERE pt.session_id = NEW.id AND pt.status = 'completed' AND ptl.tenant_id = v_tid
    GROUP BY ptl.product_id, pt2.warehouse_id
  LOOP
    INSERT INTO stock_movements (
      tenant_id, product_id, warehouse_id, movement_type,
      quantity, unit_cost, reference, reference_type, movement_date, created_at
    )
    SELECT
      v_tid, v_product.product_id, v_product.warehouse_id, 'out',
      v_product.total_qty,
      COALESCE(sq.unit_cost, 0),
      'POS-' || v_session_ref, 'manual', now(), now()
    FROM stock_quantities sq
    WHERE sq.tenant_id = v_tid AND sq.product_id = v_product.product_id
    LIMIT 1;

    -- Décrémenter le stock
    UPDATE stock_quantities
    SET quantity = quantity - v_product.total_qty, updated_at = now()
    WHERE tenant_id = v_tid AND product_id = v_product.product_id;
  END LOOP;

  RETURN NEW;
END;
$$;

-- Remplacer l'ancien trigger par le nouveau
DROP TRIGGER IF EXISTS post_pos_session_on_close_trigger ON pos_sessions;
DROP TRIGGER IF EXISTS post_pos_session_on_close_multi_trigger ON pos_sessions;
CREATE TRIGGER post_pos_session_on_close_multi_trigger
  AFTER UPDATE ON pos_sessions
  FOR EACH ROW
  EXECUTE FUNCTION post_pos_session_on_close_multi();

-- ============================================================
-- POS-03 : Conformité loi anti-fraude
-- ============================================================

-- Numérotation séquentielle des tickets par terminal
ALTER TABLE pos_tickets ADD COLUMN IF NOT EXISTS sequential_number int;
ALTER TABLE pos_tickets ADD COLUMN IF NOT EXISTS ticket_hash text;
ALTER TABLE pos_tickets ADD COLUMN IF NOT EXISTS previous_hash text;
ALTER TABLE pos_tickets ADD COLUMN IF NOT EXISTS grand_total_daily numeric DEFAULT 0;
ALTER TABLE pos_tickets ADD COLUMN IF NOT EXISTS grand_total_monthly numeric DEFAULT 0;
ALTER TABLE pos_tickets ADD COLUMN IF NOT EXISTS grand_total_yearly numeric DEFAULT 0;
ALTER TABLE pos_tickets ADD COLUMN IF NOT EXISTS grand_total_lifetime numeric DEFAULT 0;

-- Empêcher la suppression de tickets
ALTER TABLE pos_tickets ADD COLUMN IF NOT EXISTS is_voided boolean DEFAULT false;

-- ============================================================
-- POS-03 : Trigger de numérotation séquentielle et chaînage d'empreintes
-- ============================================================
CREATE OR REPLACE FUNCTION assign_pos_ticket_number_and_hash()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_last_number int := 0;
  v_last_hash text;
  v_hash_input text;
  v_grand_daily numeric := 0;
  v_grand_monthly numeric := 0;
  v_grand_yearly numeric := 0;
  v_grand_lifetime numeric := 0;
BEGIN
  -- Numéro séquentiel par terminal
  SELECT COALESCE(MAX(sequential_number), 0) INTO v_last_number
  FROM pos_tickets
  WHERE tenant_id = NEW.tenant_id AND terminal_id = NEW.terminal_id;

  NEW.sequential_number := v_last_number + 1;

  -- Récupérer le hash précédent
  SELECT ticket_hash INTO v_last_hash
  FROM pos_tickets
  WHERE tenant_id = NEW.tenant_id AND terminal_id = NEW.terminal_id
  ORDER BY sequential_number DESC
  LIMIT 1;

  NEW.previous_hash := v_last_hash;

  -- Calculer le hash : SHA256(données + hash précédent)
  v_hash_input := NEW.tenant_id || '|' || NEW.terminal_id || '|' ||
    NEW.sequential_number || '|' || NEW.total || '|' ||
    COALESCE(v_last_hash, '') || '|' || NEW.created_at;

  NEW.ticket_hash := encode(digest(v_hash_input, 'sha256'), 'hex');

  -- Cumuls perpétuels (jamais remis à zéro)
  SELECT COALESCE(SUM(total), 0) INTO v_grand_daily
  FROM pos_tickets
  WHERE tenant_id = NEW.tenant_id AND terminal_id = NEW.terminal_id
    AND DATE(created_at) = DATE(NEW.created_at);

  SELECT COALESCE(SUM(total), 0) INTO v_grand_monthly
  FROM pos_tickets
  WHERE tenant_id = NEW.tenant_id AND terminal_id = NEW.terminal_id
    AND DATE_TRUNC('month', created_at) = DATE_TRUNC('month', NEW.created_at);

  SELECT COALESCE(SUM(total), 0) INTO v_grand_yearly
  FROM pos_tickets
  WHERE tenant_id = NEW.tenant_id AND terminal_id = NEW.terminal_id
    AND DATE_TRUNC('year', created_at) = DATE_TRUNC('year', NEW.created_at);

  SELECT COALESCE(SUM(total), 0) INTO v_grand_lifetime
  FROM pos_tickets
  WHERE tenant_id = NEW.tenant_id AND terminal_id = NEW.terminal_id;

  NEW.grand_total_daily := v_grand_daily + NEW.total;
  NEW.grand_total_monthly := v_grand_monthly + NEW.total;
  NEW.grand_total_yearly := v_grand_yearly + NEW.total;
  NEW.grand_total_lifetime := v_grand_lifetime + NEW.total;

  -- Journaliser dans nf525_event_log via la fonction certifiée avec hash-chaining
  PERFORM log_nf525_event(
    'pos_ticket_created',
    'pos_ticket',
    NEW.id,
    jsonb_build_object(
      'terminal_id', NEW.terminal_id,
      'sequential_number', NEW.sequential_number,
      'total', NEW.total,
      'hash', NEW.ticket_hash,
      'previous_hash', NEW.previous_hash
    ),
    NULL,
    to_char(now(), 'YYYY-MM')
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS assign_pos_ticket_hash_trigger ON pos_tickets;
CREATE TRIGGER assign_pos_ticket_hash_trigger
  BEFORE INSERT ON pos_tickets
  FOR EACH ROW
  EXECUTE FUNCTION assign_pos_ticket_number_and_hash();

-- ============================================================
-- POS-03 : Interdire la suppression de tickets (seul l'avoir est possible)
-- ============================================================
CREATE OR REPLACE FUNCTION prevent_pos_ticket_deletion()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
BEGIN
  -- Au lieu de supprimer, marquer comme annulé
  RAISE EXCEPTION 'Suppression de ticket interdite. Utiliser l''avoir pour annuler un ticket.';
END;
$$;

DROP TRIGGER IF EXISTS prevent_pos_ticket_deletion_trigger ON pos_tickets;
CREATE TRIGGER prevent_pos_ticket_deletion_trigger
  BEFORE DELETE ON pos_tickets
  FOR EACH ROW
  EXECUTE FUNCTION prevent_pos_ticket_deletion();

-- ============================================================
-- POS-03 : Vérification de la chaîne d'empreintes
-- ============================================================
CREATE OR REPLACE FUNCTION verify_pos_ticket_chain(
  p_terminal_id uuid,
  p_date date DEFAULT CURRENT_DATE
)
RETURNS TABLE(
  ticket_id uuid,
  sequential_number int,
  stored_hash text,
  computed_hash text,
  is_valid boolean
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions, pg_temp
AS $$
  WITH chain AS (
    SELECT
      id,
      sequential_number,
      ticket_hash,
      previous_hash,
      total,
      created_at,
      encode(digest(
        current_tenant_id() || '|' || p_terminal_id || '|' || sequential_number || '|' ||
        total || '|' || COALESCE(previous_hash, '') || '|' || created_at,
        'sha256'
      ), 'hex') AS computed_hash
    FROM pos_tickets
    WHERE tenant_id = current_tenant_id() AND terminal_id = p_terminal_id
      AND DATE(created_at) = p_date
  )
  SELECT
    id,
    sequential_number,
    ticket_hash,
    computed_hash,
    computed_hash = ticket_hash
  FROM chain
  ORDER BY sequential_number;
$$;
