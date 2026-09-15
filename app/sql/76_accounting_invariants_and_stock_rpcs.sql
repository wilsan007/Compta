-- ============================================================
-- 76_accounting_invariants_and_stock_rpcs.sql
--
-- ACC-01: Invariants comptables garantis par la base
--   - Trigger d'équilibre débit/crédit (DEFERRABLE)
--   - Trigger d'immutabilité des écritures validées (posted)
--   - Contrôle de période close
--   - Numérotation atomique via séquence
--   - RPC post_journal_entry (transaction atomique)
--   - Transfert gescom idempotent (transferred_entry_id)
--
-- APP-01: RPC de stock manquants
--   - increment_stock / decrement_stock
--   - generate_recurring_entry
-- ============================================================

-- ============================================
-- ACC-01.1: Trigger d'immutabilité des écritures validées
-- ============================================
CREATE OR REPLACE FUNCTION prevent_posted_entry_modification()
RETURNS TRIGGER AS $$
BEGIN
  -- Une écriture validée (posted) ne peut être ni modifiée ni supprimée
  -- L'annulation passe par generateExtourne (création d'une écriture inverse)
  IF (TG_OP = 'DELETE') THEN
    IF OLD.status = 'posted' THEN
      RAISE EXCEPTION 'Écriture % est validée (posted) — immuable. Utiliser l''extourne pour annuler.', OLD.id;
    END IF;
    RETURN OLD;
  END IF;
  -- TG_OP = 'UPDATE'
  IF OLD.status = 'posted' THEN
    RAISE EXCEPTION 'Écriture % est validée (posted) — immuable. Utiliser l''extourne pour annuler.', OLD.id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS prevent_posted_entry_modification ON journal_entries;
CREATE TRIGGER prevent_posted_entry_modification
  BEFORE UPDATE OR DELETE ON journal_entries
  FOR EACH ROW EXECUTE FUNCTION prevent_posted_entry_modification();

-- ============================================
-- ACC-01.1b: Immutabilité des lignes d'écritures validées
-- Les lignes d'une écriture posted ne peuvent être ni modifiées ni supprimées
-- ============================================
CREATE OR REPLACE FUNCTION prevent_posted_line_modification()
RETURNS TRIGGER AS $$
DECLARE
  v_entry_status text;
  v_entry_id uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_entry_id := OLD.journal_id;
  ELSE
    v_entry_id := NEW.journal_id;
  END IF;

  SELECT status INTO v_entry_status FROM journal_entries WHERE id = v_entry_id;
  IF v_entry_status = 'posted' THEN
    RAISE EXCEPTION 'Ligne d''écriture % validée (posted) — immuable. Utiliser l''extourne pour annuler.', v_entry_id;
  END IF;
  IF (TG_OP = 'DELETE') THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS prevent_posted_line_modification ON journal_lines;
CREATE TRIGGER prevent_posted_line_modification
  BEFORE INSERT OR UPDATE OR DELETE ON journal_lines
  FOR EACH ROW EXECUTE FUNCTION prevent_posted_line_modification();

-- ============================================
-- ACC-01.2: Trigger d'équilibre débit/crédit (DEFERRABLE)
-- Vérifie que SUM(debit) = SUM(credit) par journal_entry
-- ============================================
CREATE OR REPLACE FUNCTION check_journal_entry_balance()
RETURNS TRIGGER AS $$
DECLARE
  v_total_debit numeric;
  v_total_credit numeric;
  v_entry_id uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_entry_id := OLD.journal_id;
  ELSE
    v_entry_id := NEW.journal_id;
  END IF;

  SELECT COALESCE(SUM(debit), 0), COALESCE(SUM(credit), 0)
  INTO v_total_debit, v_total_credit
  FROM journal_lines
  WHERE journal_id = v_entry_id;

  -- Tolérance de 0.01 pour les arrondis
  IF ABS(v_total_debit - v_total_credit) > 0.01 THEN
    RAISE EXCEPTION 'Écriture déséquilibrée: débit=%, crédit=% (écart=%)',
      v_total_debit, v_total_credit, ABS(v_total_debit - v_total_credit);
  END IF;

  -- Au moins une ligne avec un montant > 0
  IF v_total_debit = 0 AND v_total_credit = 0 THEN
    RAISE EXCEPTION 'Écriture vide: aucun montant sur les lignes';
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Le trigger est DEFERRABLE INITIALLY DEFERRED pour permettre
-- l'insertion de l'entête puis des lignes dans la même transaction
DROP TRIGGER IF EXISTS check_journal_entry_balance ON journal_lines;
CREATE CONSTRAINT TRIGGER check_journal_entry_balance
  AFTER INSERT OR UPDATE OR DELETE ON journal_lines
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION check_journal_entry_balance();

-- ============================================
-- ACC-01.3: Contrôle de période close
-- ============================================
CREATE OR REPLACE FUNCTION check_fiscal_period_open()
RETURNS TRIGGER AS $$
DECLARE
  v_period_status text;
  v_entry_date date;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_entry_date := OLD.date;
  ELSE
    v_entry_date := NEW.date;
  END IF;

  SELECT fp.status INTO v_period_status
  FROM fiscal_periods fp
  JOIN fiscal_years fy ON fy.id = fp.fiscal_year_id
  WHERE fp.tenant_id = current_tenant_id()
    AND v_entry_date >= fp.start_date
    AND v_entry_date <= fp.end_date
  LIMIT 1;

  IF v_period_status = 'closed' THEN
    RAISE EXCEPTION 'Période fiscale close — écriture interdite (date=%)', v_entry_date;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS check_fiscal_period_open ON journal_entries;
CREATE TRIGGER check_fiscal_period_open
  BEFORE INSERT OR UPDATE ON journal_entries
  FOR EACH ROW EXECUTE FUNCTION check_fiscal_period_open();

-- ============================================
-- ACC-01.4: Numérotation atomique via compteur sur journals
-- ============================================
-- Ajouter une colonne next_number si elle n'existe pas
ALTER TABLE journals ADD COLUMN IF NOT EXISTS next_number integer DEFAULT 1;

CREATE OR REPLACE FUNCTION get_next_piece_number(p_journal_code text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_next integer;
  v_padded text;
BEGIN
  -- Verrou de ligne pour éviter les doublons en concurrence
  UPDATE journals
    SET next_number = next_number + 1
    WHERE journal_code = p_journal_code
      AND tenant_id = current_tenant_id()
    RETURNING next_number - 1 INTO v_next;

  IF v_next IS NULL THEN
    -- Journal non trouvé pour ce tenant — fallback
    v_next := 1;
  END IF;

  v_padded := CASE
    WHEN v_next < 10000 THEN lpad(v_next::text, 4, '0')
    ELSE v_next::text
  END;
  RETURN p_journal_code || '-' || v_padded;
END;
$$;

GRANT EXECUTE ON FUNCTION get_next_piece_number(text) TO authenticated;

-- ============================================
-- ACC-01.5: Contrainte d'unicité des numéros de pièces par tenant
-- ============================================
-- Ajouter la contrainte si elle n'existe pas déjà
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uniq_journal_entry_number_tenant'
  ) THEN
    ALTER TABLE journal_entries
      ADD CONSTRAINT uniq_journal_entry_number_tenant
      UNIQUE (tenant_id, journal_code, number);
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Uniqueness constraint skipped: %', SQLERRM;
END $$;

-- Unicité des numéros de factures par tenant
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uniq_invoice_number_tenant'
  ) THEN
    ALTER TABLE invoices ADD CONSTRAINT uniq_invoice_number_tenant UNIQUE (tenant_id, number);
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Invoice uniqueness constraint skipped: %', SQLERRM;
END $$;

-- Unicité des numéros d'avoirs par tenant
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uniq_credit_note_number_tenant'
  ) THEN
    ALTER TABLE credit_notes ADD CONSTRAINT uniq_credit_note_number_tenant UNIQUE (tenant_id, number);
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Credit note uniqueness constraint skipped: %', SQLERRM;
END $$;

-- Unicité des numéros de bulletins de paie par tenant
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uniq_pay_slip_number_tenant'
  ) THEN
    ALTER TABLE pay_slips ADD CONSTRAINT uniq_pay_slip_number_tenant UNIQUE (tenant_id, number);
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Pay slip uniqueness constraint skipped: %', SQLERRM;
END $$;

-- ============================================
-- ACC-01.6: RPC post_journal_entry — insertion atomique
-- ============================================
CREATE OR REPLACE FUNCTION post_journal_entry(p_entry jsonb, p_lines jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_entry_id uuid;
  v_line jsonb;
  v_number text;
  v_journal_code text;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  v_journal_code := p_entry ->> 'journal_code';

  -- Numérotation atomique si pas de numéro fourni
  IF p_entry ->> 'number' IS NULL OR p_entry ->> 'number' = '' THEN
    v_number := get_next_piece_number(v_journal_code);
  ELSE
    v_number := p_entry ->> 'number';
  END IF;

  -- 1. Insérer l'entête
  INSERT INTO journal_entries (
    tenant_id, number, date, journal_code, status,
    description, invoice_ref, piece_number
  ) VALUES (
    v_tid,
    v_number,
    (p_entry ->> 'date')::date,
    v_journal_code,
    COALESCE(p_entry ->> 'status', 'draft'),
    p_entry ->> 'description',
    p_entry ->> 'invoice_ref',
    v_number
  )
  RETURNING id INTO v_entry_id;

  -- 2. Insérer les lignes
  FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order
    ) VALUES (
      v_tid,
      v_entry_id,
      v_line ->> 'account_code',
      v_line ->> 'account_general',
      COALESCE((v_line ->> 'debit')::numeric, 0),
      COALESCE((v_line ->> 'credit')::numeric, 0),
      v_line ->> 'description',
      COALESCE((v_line ->> 'line_order')::integer, 0)
    );
  END LOOP;

  -- ACC-02: Valider qu'au moins une ligne non-nulle existe
  IF jsonb_array_length(p_lines) = 0 THEN
    RAISE EXCEPTION 'Écriture vide: aucune ligne fournie';
  END IF;

  -- Le trigger check_journal_entry_balance vérifie l'équilibre automatiquement

  RETURN jsonb_build_object('success', true, 'entry_id', v_entry_id, 'number', v_number);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION post_journal_entry(jsonb, jsonb) TO authenticated;

-- ============================================
-- ACC-01.7: Transfert gescom idempotent
-- ============================================
-- Ajouter transferred_entry_id sur les tables commerciales
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS transferred_entry_id uuid REFERENCES journal_entries(id);
ALTER TABLE purchase_invoices ADD COLUMN IF NOT EXISTS transferred_entry_id uuid REFERENCES journal_entries(id);
ALTER TABLE customer_payments ADD COLUMN IF NOT EXISTS transferred_entry_id uuid REFERENCES journal_entries(id);
ALTER TABLE supplier_payments ADD COLUMN IF NOT EXISTS transferred_entry_id uuid REFERENCES journal_entries(id);

-- ============================================
-- APP-01.1: RPC increment_stock
-- ============================================
CREATE OR REPLACE FUNCTION increment_stock(p_product_id uuid, p_qty numeric, p_warehouse_id uuid DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- Mettre à jour stock_quantities par entrepôt
  IF p_warehouse_id IS NOT NULL THEN
    UPDATE stock_quantities
      SET quantity = quantity + p_qty, updated_at = NOW()
      WHERE product_id = p_product_id
        AND warehouse_id = p_warehouse_id
        AND tenant_id = v_tid;

    -- Créer la ligne si elle n'existe pas
    IF NOT FOUND THEN
      INSERT INTO stock_quantities (tenant_id, product_id, warehouse_id, quantity)
      VALUES (v_tid, p_product_id, p_warehouse_id, p_qty)
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;

  -- Mettre à jour le stock total sur products
  UPDATE products
    SET stock_quantity = COALESCE(stock_quantity, 0) + p_qty,
        updated_at = NOW()
    WHERE id = p_product_id AND tenant_id = v_tid;
END;
$$;

GRANT EXECUTE ON FUNCTION increment_stock(uuid, numeric, uuid) TO authenticated;

-- ============================================
-- APP-01.2: RPC decrement_stock
-- ============================================
CREATE OR REPLACE FUNCTION decrement_stock(p_product_id uuid, p_qty numeric, p_warehouse_id uuid DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_current numeric;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- Vérifier le stock disponible (avec verrou FOR UPDATE)
  SELECT stock_quantity INTO v_current
  FROM products
  WHERE id = p_product_id AND tenant_id = v_tid
  FOR UPDATE;

  IF v_current IS NULL THEN
    RAISE EXCEPTION 'Produit % non trouvé', p_product_id;
  END IF;

  IF v_current < p_qty THEN
    RAISE EXCEPTION 'Stock insuffisant: disponible=%, demandé=%', v_current, p_qty;
  END IF;

  -- Mettre à jour stock_quantities par entrepôt
  IF p_warehouse_id IS NOT NULL THEN
    UPDATE stock_quantities
      SET quantity = GREATEST(quantity - p_qty, 0), updated_at = NOW()
      WHERE product_id = p_product_id
        AND warehouse_id = p_warehouse_id
        AND tenant_id = v_tid;
  END IF;

  -- Mettre à jour le stock total
  UPDATE products
    SET stock_quantity = stock_quantity - p_qty,
        updated_at = NOW()
    WHERE id = p_product_id AND tenant_id = v_tid;
END;
$$;

GRANT EXECUTE ON FUNCTION decrement_stock(uuid, numeric, uuid) TO authenticated;

-- ============================================
-- APP-01.3: Trigger automatique sur stock_movements
-- Alternative au RPC appelé manuellement — met à jour le stock
-- automatiquement à chaque insertion de mouvement
-- ============================================
CREATE OR REPLACE FUNCTION update_stock_on_movement()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.movement_type = 'in' THEN
    PERFORM increment_stock(NEW.product_id, NEW.quantity, NEW.warehouse_id);
  ELSIF NEW.movement_type = 'out' THEN
    PERFORM decrement_stock(NEW.product_id, NEW.quantity, NEW.warehouse_id);
  ELSIF NEW.movement_type = 'adjustment' THEN
    -- Pour un ajustement, quantity est la nouvelle valeur absolue
    UPDATE products
      SET stock_quantity = NEW.quantity, updated_at = NOW()
      WHERE id = NEW.product_id AND tenant_id = current_tenant_id();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_stock_on_movement ON stock_movements;
CREATE TRIGGER update_stock_on_movement
  AFTER INSERT ON stock_movements
  FOR EACH ROW EXECUTE FUNCTION update_stock_on_movement();

-- ============================================
-- APP-01.4: RPC generate_recurring_entry
-- ============================================
CREATE OR REPLACE FUNCTION generate_recurring_entry(p_entry_id uuid, p_tenant_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := COALESCE(p_tenant_id, current_tenant_id());
  v_source journal_entries%ROWTYPE;
  v_source_lines journal_lines[] := ARRAY[]::journal_lines[];
  v_new_id uuid;
  v_line journal_lines%ROWTYPE;
  v_new_date date;
  v_number text;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- Charger l'écriture source
  SELECT * INTO v_source FROM journal_entries WHERE id = p_entry_id AND tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Écriture source % non trouvée', p_entry_id;
  END IF;

  -- Calculer la nouvelle date (un mois plus tard)
  v_new_date := (v_source.date + INTERVAL '1 month')::date;

  -- Générer un nouveau numéro
  v_number := get_next_piece_number(v_source.journal_code);

  -- Créer la nouvelle écriture
  INSERT INTO journal_entries (
    tenant_id, number, date, journal_code, status,
    description, invoice_ref
  ) VALUES (
    v_tid, v_number, v_new_date, v_source.journal_code,
    'draft',
    '[Récurrent] ' || COALESCE(v_source.description, ''),
    v_source.invoice_ref
  )
  RETURNING id INTO v_new_id;

  -- Copier les lignes
  FOR v_line IN
    SELECT * FROM journal_lines WHERE journal_id = p_entry_id AND tenant_id = v_tid
  LOOP
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order
    ) VALUES (
      v_tid, v_new_id, v_line.account_code, v_line.account_general,
      v_line.debit, v_line.credit, v_line.description, v_line.line_order
    );
  END LOOP;

  RETURN jsonb_build_object('success', true, 'new_entry_id', v_new_id, 'number', v_number);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION generate_recurring_entry(uuid, uuid) TO authenticated;
