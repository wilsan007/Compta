-- ============================================================
-- 108_auxiliary_accounts.sql
-- ACC-01 : Comptes auxiliaires sur les écritures automatiques
--
-- Les triggers de comptabilisation ne renseignaient pas account_tiers
-- ni third_party_id ni echeance_date → le grand livre tiers et la
-- balance âgée n'affichaient rien pour le flux automatique.
-- ============================================================

-- ============================================================
-- 1. Ajouter account_tiers et account_collectif sur customers/suppliers
-- ============================================================
ALTER TABLE customers ADD COLUMN IF NOT EXISTS account_tiers text;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS account_collectif text DEFAULT '411000';

ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS account_tiers text;
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS account_collectif text DEFAULT '401000';

-- Index pour la recherche par compte auxiliaire
CREATE INDEX IF NOT EXISTS idx_customers_account_tiers ON customers (tenant_id, account_tiers) WHERE account_tiers IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_suppliers_account_tiers ON suppliers (tenant_id, account_tiers) WHERE account_tiers IS NOT NULL;

-- ============================================================
-- 2. Fonction de génération automatique du compte auxiliaire
-- ============================================================
CREATE OR REPLACE FUNCTION generate_customer_account_tiers()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_prefix text := 'CLI';
  v_seq int;
BEGIN
  IF NEW.account_tiers IS NOT NULL AND NEW.account_tiers != '' THEN
    RETURN NEW;
  END IF;

  -- Générer un code auxiliaire : préfixe + séquence
  SELECT COALESCE(MAX(seq), 0) + 1 INTO v_seq
  FROM (
    SELECT CAST(
      regexp_replace(
        COALESCE(account_tiers, ''),
        '^[A-Z]+',
        ''
      ) AS int
    ) AS seq
    FROM customers
    WHERE tenant_id = NEW.tenant_id
      AND account_tiers ~ '^[A-Z]+[0-9]+$'
  ) s;

  NEW.account_tiers := v_prefix || lpad(v_seq::text, 5, '0');
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION generate_supplier_account_tiers()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_prefix text := 'FOU';
  v_seq int;
BEGIN
  IF NEW.account_tiers IS NOT NULL AND NEW.account_tiers != '' THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(MAX(seq), 0) + 1 INTO v_seq
  FROM (
    SELECT CAST(
      regexp_replace(
        COALESCE(account_tiers, ''),
        '^[A-Z]+',
        ''
      ) AS int
    ) AS seq
    FROM suppliers
    WHERE tenant_id = NEW.tenant_id
      AND account_tiers ~ '^[A-Z]+[0-9]+$'
  ) s;

  NEW.account_tiers := v_prefix || lpad(v_seq::text, 5, '0');
  RETURN NEW;
END;
$$;

-- Triggers de génération automatique
DROP TRIGGER IF EXISTS trg_generate_customer_account_tiers ON customers;
CREATE TRIGGER trg_generate_customer_account_tiers
  BEFORE INSERT ON customers
  FOR EACH ROW EXECUTE FUNCTION generate_customer_account_tiers();

DROP TRIGGER IF EXISTS trg_generate_supplier_account_tiers ON suppliers;
CREATE TRIGGER trg_generate_supplier_account_tiers
  BEFORE INSERT ON suppliers
  FOR EACH ROW EXECUTE FUNCTION generate_supplier_account_tiers();

-- ============================================================
-- 3. Rattrapage : alimenter account_tiers sur les customers/suppliers existants
-- ============================================================
DO $$
DECLARE
  r RECORD;
  v_seq int := 1;
BEGIN
  FOR r IN
    SELECT id, tenant_id FROM customers WHERE account_tiers IS NULL OR account_tiers = ''
    ORDER BY created_at
  LOOP
    UPDATE customers SET account_tiers = 'CLI' || lpad(v_seq::text, 5, '0')
    WHERE id = r.id AND tenant_id = r.tenant_id;
    v_seq := v_seq + 1;
  END LOOP;

  v_seq := 1;
  FOR r IN
    SELECT id, tenant_id FROM suppliers WHERE account_tiers IS NULL OR account_tiers = ''
    ORDER BY created_at
  LOOP
    UPDATE suppliers SET account_tiers = 'FOU' || lpad(v_seq::text, 5, '0')
    WHERE id = r.id AND tenant_id = r.tenant_id;
    v_seq := v_seq + 1;
  END LOOP;
END $$;

-- ============================================================
-- 4. Réécrire les triggers de comptabilisation avec account_tiers
-- ============================================================

-- Facture vente
CREATE OR REPLACE FUNCTION create_journal_on_invoice_validate()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_entry_id uuid;
  v_number text;
  v_existing uuid;
  v_collectif text := '411000';
  v_tiers text;
  v_third_party uuid;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status IN ('validated', 'posted') THEN
    SELECT id INTO v_existing FROM journal_entries
      WHERE tenant_id = NEW.tenant_id AND invoice_ref = NEW.number AND journal_code = 'VT' LIMIT 1;
    IF v_existing IS NOT NULL THEN RETURN NEW; END IF;

    -- ACC-01 : récupérer le compte collectif et le compte auxiliaire du client
    SELECT COALESCE(c.account_collectif, '411000'), c.account_tiers, c.id
    INTO v_collectif, v_tiers, v_third_party
    FROM customers c
    WHERE c.id = NEW.customer_id AND c.tenant_id = NEW.tenant_id;

    v_number := 'JE-INV-' || NEW.number;
    INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, invoice_ref, piece_number)
    VALUES (NEW.tenant_id, v_number, NEW.date, 'VT', 'draft', 'Facture vente ' || NEW.number, NEW.number, v_number)
    RETURNING id INTO v_entry_id;

    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      account_tiers, third_party_id, echeance_date,
      debit, credit, description, line_order
    ) VALUES
      (NEW.tenant_id, v_entry_id, v_collectif, v_collectif,
       v_tiers, v_third_party, NEW.due_date,
       NEW.total, 0, 'Client ' || NEW.number, 0),
      (New.tenant_id, v_entry_id, '707000', '707000',
       NULL, NULL, NULL,
       0, NEW.subtotal, 'Ventes ' || NEW.number, 1),
      (New.tenant_id, v_entry_id, '4457000', '4457000',
       NULL, NULL, NULL,
       0, NEW.vat_total, 'TVA collectée ' || NEW.number, 2);

    -- Bascule en 'posted' APRÈS les lignes (SOC-01)
    UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;
    UPDATE invoices SET transferred_entry_id = v_entry_id WHERE id = NEW.id AND tenant_id = NEW.tenant_id;
  END IF;
  RETURN NEW;
END;
$$;

-- Facture achat
CREATE OR REPLACE FUNCTION create_journal_on_purchase_invoice_validate()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_entry_id uuid;
  v_number text;
  v_existing uuid;
  v_collectif text := '401000';
  v_tiers text;
  v_third_party uuid;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status IN ('validated', 'posted', 'approved') THEN
    SELECT id INTO v_existing FROM journal_entries
      WHERE tenant_id = NEW.tenant_id AND invoice_ref = NEW.number AND journal_code = 'AC' LIMIT 1;
    IF v_existing IS NOT NULL THEN RETURN NEW; END IF;

    -- ACC-01 : récupérer le compte collectif et le compte auxiliaire du fournisseur
    SELECT COALESCE(s.account_collectif, '401000'), s.account_tiers, s.id
    INTO v_collectif, v_tiers, v_third_party
    FROM suppliers s
    WHERE s.id = NEW.supplier_id AND s.tenant_id = NEW.tenant_id;

    v_number := 'JE-PI-' || NEW.number;
    INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, invoice_ref, piece_number)
    VALUES (NEW.tenant_id, v_number, NEW.date, 'AC', 'draft', 'Facture achat ' || NEW.number, NEW.number, v_number)
    RETURNING id INTO v_entry_id;

    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      account_tiers, third_party_id, echeance_date,
      debit, credit, description, line_order
    ) VALUES
      (New.tenant_id, v_entry_id, '607000', '607000',
       NULL, NULL, NULL,
       NEW.subtotal, 0, 'Achats ' || NEW.number, 0),
      (New.tenant_id, v_entry_id, '4456000', '4456000',
       NULL, NULL, NULL,
       NEW.vat_total, 0, 'TVA déductible ' || NEW.number, 1),
      (New.tenant_id, v_entry_id, v_collectif, v_collectif,
       v_tiers, v_third_party, NEW.due_date,
       0, NEW.total, 'Fournisseur ' || NEW.number, 2);

    -- Bascule en 'posted' APRÈS les lignes (SOC-01)
    UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;
    UPDATE purchase_invoices SET transferred_entry_id = v_entry_id WHERE id = NEW.id AND tenant_id = NEW.tenant_id;
  END IF;
  RETURN NEW;
END;
$$;

-- Ensure backward compatibility columns
ALTER TABLE customer_payments ADD COLUMN IF NOT EXISTS invoice_number text;
ALTER TABLE supplier_payments ADD COLUMN IF NOT EXISTS invoice_number text;

-- Encaissement client
CREATE OR REPLACE FUNCTION create_journal_on_customer_payment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_entry_id uuid;
  v_number text;
  v_collectif text := '411000';
  v_tiers text;
  v_third_party uuid;
BEGIN
  -- ACC-01 : récupérer les infos du client directement ou via la facture
  IF NEW.customer_id IS NOT NULL THEN
    SELECT account_collectif, account_tiers, id
    INTO v_collectif, v_tiers, v_third_party
    FROM customers
    WHERE id = NEW.customer_id AND tenant_id = NEW.tenant_id;
  ELSIF NEW.invoice_id IS NOT NULL THEN
    SELECT c.account_collectif, c.account_tiers, c.id
    INTO v_collectif, v_tiers, v_third_party
    FROM customers c
    JOIN invoices i ON i.customer_id = c.id AND i.tenant_id = c.tenant_id
    WHERE i.id = NEW.invoice_id AND i.tenant_id = NEW.tenant_id;
  END IF;

  v_number := 'JE-CP-' || NEW.number;
  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, piece_number)
  VALUES (NEW.tenant_id, v_number, NEW.payment_date, 'BQ', 'draft', 'Encaissement ' || NEW.number, v_number)
  RETURNING id INTO v_entry_id;

  INSERT INTO journal_lines (
    tenant_id, journal_id, account_code, account_general,
    account_tiers, third_party_id,
    debit, credit, description, line_order
  ) VALUES
    (New.tenant_id, v_entry_id, '512000', '512000',
     NULL, NULL,
     NEW.amount, 0, 'Banque ' || NEW.number, 0),
    (New.tenant_id, v_entry_id, v_collectif, v_collectif,
     v_tiers, v_third_party,
     0, NEW.amount, 'Client ' || NEW.number, 1);

  -- Bascule en 'posted' APRÈS les lignes (SOC-01)
  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;
  UPDATE customer_payments SET transferred_entry_id = v_entry_id WHERE id = NEW.id AND tenant_id = NEW.tenant_id;
  RETURN NEW;
END;
$$;

-- Décaissement fournisseur
CREATE OR REPLACE FUNCTION create_journal_on_supplier_payment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_entry_id uuid;
  v_number text;
  v_collectif text := '401000';
  v_tiers text;
  v_third_party uuid;
BEGIN
  -- ACC-01 : récupérer les infos du fournisseur directement ou via la facture d'achat
  IF NEW.supplier_id IS NOT NULL THEN
    SELECT account_collectif, account_tiers, id
    INTO v_collectif, v_tiers, v_third_party
    FROM suppliers
    WHERE id = NEW.supplier_id AND tenant_id = NEW.tenant_id;
  ELSIF NEW.purchase_invoice_id IS NOT NULL THEN
    SELECT s.account_collectif, s.account_tiers, s.id
    INTO v_collectif, v_tiers, v_third_party
    FROM suppliers s
    JOIN purchase_invoices pi ON pi.supplier_id = s.id AND pi.tenant_id = s.tenant_id
    WHERE pi.id = NEW.purchase_invoice_id AND pi.tenant_id = NEW.tenant_id;
  END IF;

  v_number := 'JE-SP-' || NEW.number;
  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, piece_number)
  VALUES (NEW.tenant_id, v_number, NEW.payment_date, 'BQ', 'draft', 'Décaissement ' || NEW.number, v_number)
  RETURNING id INTO v_entry_id;

  INSERT INTO journal_lines (
    tenant_id, journal_id, account_code, account_general,
    account_tiers, third_party_id,
    debit, credit, description, line_order
  ) VALUES
    (New.tenant_id, v_entry_id, v_collectif, v_collectif,
     v_tiers, v_third_party,
     NEW.amount, 0, 'Fournisseur ' || NEW.number, 0),
    (New.tenant_id, v_entry_id, '512000', '512000',
     NULL, NULL,
     0, NEW.amount, 'Banque ' || NEW.number, 1);

  -- Bascule en 'posted' APRÈS les lignes (SOC-01)
  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;
  UPDATE supplier_payments SET transferred_entry_id = v_entry_id WHERE id = NEW.id AND tenant_id = NEW.tenant_id;
  RETURN NEW;
END;
$$;

-- ============================================================
-- 5. Rattrapage : alimenter account_tiers sur les journal_lines existantes
--    par jointure sur invoice_ref
-- ============================================================
DO $$
BEGIN
  -- Lignes clients (411000) : joindre sur invoices → customers
  UPDATE journal_lines jl
  SET account_tiers = c.account_tiers,
      third_party_id = c.id
  FROM journal_entries je
  JOIN invoices i ON i.number = je.invoice_ref AND i.tenant_id = je.tenant_id
  JOIN customers c ON c.id = i.customer_id AND c.tenant_id = i.tenant_id
  WHERE jl.journal_id = je.id
    AND jl.tenant_id = je.tenant_id
    AND jl.account_code = '411000'
    AND jl.account_tiers IS NULL;

  -- Lignes fournisseurs (401000) : joindre sur purchase_invoices → suppliers
  UPDATE journal_lines jl
  SET account_tiers = s.account_tiers,
      third_party_id = s.id
  FROM journal_entries je
  JOIN purchase_invoices pi ON pi.number = je.invoice_ref AND pi.tenant_id = je.tenant_id
  JOIN suppliers s ON s.id = pi.supplier_id AND s.tenant_id = pi.tenant_id
  WHERE jl.journal_id = je.id
    AND jl.tenant_id = je.tenant_id
    AND jl.account_code = '401000'
    AND jl.account_tiers IS NULL;

  -- Echeance : joindre sur invoices pour récupérer due_date
  UPDATE journal_lines jl
  SET echeance_date = i.due_date
  FROM journal_entries je
  JOIN invoices i ON i.number = je.invoice_ref AND i.tenant_id = je.tenant_id
  WHERE jl.journal_id = je.id
    AND jl.tenant_id = je.tenant_id
    AND jl.account_code = '411000'
    AND jl.echeance_date IS NULL;

  -- Echeance : joindre sur purchase_invoices
  UPDATE journal_lines jl
  SET echeance_date = pi.due_date
  FROM journal_entries je
  JOIN purchase_invoices pi ON pi.number = je.invoice_ref AND pi.tenant_id = je.tenant_id
  WHERE jl.journal_id = je.id
    AND jl.tenant_id = je.tenant_id
    AND jl.account_code = '401000'
    AND jl.echeance_date IS NULL;
END $$;
