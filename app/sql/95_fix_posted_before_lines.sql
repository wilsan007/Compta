-- ============================================================
-- 95_fix_posted_before_lines.sql
-- SOC-01 : Corrige le motif « écriture validée avant ses lignes »
--
-- Cinq triggers inséraient l'en-tête directement en 'posted' puis
-- ajoutaient les lignes — ce qui déclenchait prevent_posted_line_modification
-- (BEFORE INSERT sur journal_lines) et faisait échouer toute l'opération.
--
-- Correctif : insérer en 'draft', ajouter les lignes, puis basculer en 'posted'.
-- Le trigger prevent_posted_entry_modification (BEFORE UPDATE sur journal_entries)
-- teste OLD.status = 'posted' — or OLD.status = 'draft' ici, donc le passage est autorisé.
-- ============================================================

-- ============================================================
-- 1. create_journal_on_invoice_validate (facture vente)
-- ============================================================
CREATE OR REPLACE FUNCTION create_journal_on_invoice_validate()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_entry_id uuid; v_number text; v_existing uuid;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status IN ('validated', 'posted') THEN
    SELECT id INTO v_existing FROM journal_entries
      WHERE tenant_id = NEW.tenant_id AND invoice_ref = NEW.number AND journal_code = 'VT' LIMIT 1;
    IF v_existing IS NOT NULL THEN RETURN NEW; END IF;
    v_number := 'JE-INV-' || NEW.number;
    INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, invoice_ref, piece_number)
    VALUES (NEW.tenant_id, v_number, NEW.date, 'VT', 'draft', 'Facture vente ' || NEW.number, NEW.number, v_number)
    RETURNING id INTO v_entry_id;
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order) VALUES
      (NEW.tenant_id, v_entry_id, '411000', '411000', NEW.total, 0, 'Client ' || NEW.number, 0),
      (NEW.tenant_id, v_entry_id, '707000', '707000', 0, NEW.subtotal, 'Ventes ' || NEW.number, 1),
      (New.tenant_id, v_entry_id, '4457000', '4457000', 0, NEW.vat_total, 'TVA collectée ' || NEW.number, 2);
    -- Bascule en 'posted' APRÈS les lignes
    UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;
    UPDATE invoices SET transferred_entry_id = v_entry_id WHERE id = NEW.id AND tenant_id = NEW.tenant_id;
  END IF;
  RETURN NEW;
END;
$$;

-- ============================================================
-- 2. create_journal_on_purchase_invoice_validate (facture achat)
-- ============================================================
CREATE OR REPLACE FUNCTION create_journal_on_purchase_invoice_validate()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_entry_id uuid; v_number text; v_existing uuid;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status IN ('validated', 'posted', 'approved') THEN
    SELECT id INTO v_existing FROM journal_entries
      WHERE tenant_id = NEW.tenant_id AND invoice_ref = NEW.number AND journal_code = 'AC' LIMIT 1;
    IF v_existing IS NOT NULL THEN RETURN NEW; END IF;
    v_number := 'JE-PI-' || NEW.number;
    INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, invoice_ref, piece_number)
    VALUES (NEW.tenant_id, v_number, NEW.date, 'AC', 'draft', 'Facture achat ' || NEW.number, NEW.number, v_number)
    RETURNING id INTO v_entry_id;
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order) VALUES
      (NEW.tenant_id, v_entry_id, '607000', '607000', NEW.subtotal, 0, 'Achats ' || NEW.number, 0),
      (NEW.tenant_id, v_entry_id, '4456000', '4456000', NEW.vat_total, 0, 'TVA déductible ' || NEW.number, 1),
      (NEW.tenant_id, v_entry_id, '401000', '401000', 0, NEW.total, 'Fournisseur ' || NEW.number, 2);
    -- Bascule en 'posted' APRÈS les lignes
    UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;
    UPDATE purchase_invoices SET transferred_entry_id = v_entry_id WHERE id = NEW.id AND tenant_id = NEW.tenant_id;
  END IF;
  RETURN NEW;
END;
$$;

-- ============================================================
-- 3. create_journal_on_customer_payment (encaissement)
-- ============================================================
CREATE OR REPLACE FUNCTION create_journal_on_customer_payment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_entry_id uuid; v_number text;
BEGIN
  v_number := 'JE-CP-' || NEW.number;
  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, piece_number)
  VALUES (NEW.tenant_id, v_number, NEW.payment_date, 'BQ', 'draft', 'Encaissement ' || NEW.number, v_number)
  RETURNING id INTO v_entry_id;
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order) VALUES
    (NEW.tenant_id, v_entry_id, '512000', '512000', NEW.amount, 0, 'Banque ' || NEW.number, 0),
    (NEW.tenant_id, v_entry_id, '411000', '411000', 0, NEW.amount, 'Client ' || NEW.number, 1);
  -- Bascule en 'posted' APRÈS les lignes
  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;
  UPDATE customer_payments SET transferred_entry_id = v_entry_id WHERE id = NEW.id AND tenant_id = NEW.tenant_id;
  RETURN NEW;
END;
$$;

-- ============================================================
-- 4. create_journal_on_supplier_payment (décaissement)
-- ============================================================
CREATE OR REPLACE FUNCTION create_journal_on_supplier_payment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_entry_id uuid; v_number text;
BEGIN
  v_number := 'JE-SP-' || NEW.number;
  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, piece_number)
  VALUES (NEW.tenant_id, v_number, NEW.payment_date, 'BQ', 'draft', 'Décaissement ' || NEW.number, v_number)
  RETURNING id INTO v_entry_id;
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order) VALUES
    (NEW.tenant_id, v_entry_id, '401000', '401000', NEW.amount, 0, 'Fournisseur ' || NEW.number, 0),
    (NEW.tenant_id, v_entry_id, '512000', '512000', 0, NEW.amount, 'Banque ' || NEW.number, 1);
  -- Bascule en 'posted' APRÈS les lignes
  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;
  UPDATE supplier_payments SET transferred_entry_id = v_entry_id WHERE id = NEW.id AND tenant_id = NEW.tenant_id;
  RETURN NEW;
END;
$$;

-- ============================================================
-- 5. create_journal_on_stock_movement (mouvement de stock)
-- ============================================================
CREATE OR REPLACE FUNCTION create_journal_on_stock_movement()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_entry_id uuid;
  v_number text;
  v_existing uuid;
  v_amount numeric;
  v_stock_account text := '310000';
  v_variation_account text := '603000';
  v_product RECORD;
BEGIN
  -- Ne traiter que les types de mouvement qui ont un impact comptable
  IF NEW.movement_type NOT IN ('in', 'out', 'adjustment', 'initial') THEN
    RETURN NEW;
  END IF;

  -- Éviter les doublons
  SELECT id INTO v_existing FROM journal_entries
    WHERE tenant_id = NEW.tenant_id AND piece_number = 'STK-' || NEW.id::text
  LIMIT 1;
  IF v_existing IS NOT NULL THEN RETURN NEW; END IF;

  -- Récupérer le produit
  SELECT * INTO v_product FROM products WHERE id = NEW.product_id AND tenant_id = NEW.tenant_id;

  -- Calculer le montant
  v_amount := COALESCE(NEW.unit_cost, 0) * COALESCE(NEW.quantity, 0);
  IF v_amount = 0 THEN RETURN NEW; END IF;

  v_number := 'JE-STK-' || to_char(NOW(), 'YYYYMMDDHH24MISS') || '-' || substr(NEW.id::text, 1, 8);

  -- Insérer l'entête en 'draft'
  INSERT INTO journal_entries (
    tenant_id, number, date, journal_code, status,
    description, piece_number, reference
  ) VALUES (
    NEW.tenant_id, v_number, COALESCE(NEW.movement_date, NEW.date, CURRENT_DATE),
    'ST', 'draft',
    'Mouvement de stock ' || COALESCE(NEW.reference, NEW.id::text),
    'STK-' || NEW.id::text,
    NEW.reference
  )
  RETURNING id INTO v_entry_id;

  -- Insérer les lignes selon le type de mouvement
  IF NEW.movement_type IN ('in', 'initial') THEN
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order, product_id, quantity
    ) VALUES
      (NEW.tenant_id, v_entry_id, v_stock_account, v_stock_account,
       v_amount, 0, 'Entrée en stock - ' || COALESCE(v_product.name, 'Produit'), 0,
       NEW.product_id, NEW.quantity),
      (NEW.tenant_id, v_entry_id, v_variation_account, v_variation_account,
       0, v_amount, 'Variation de stock (entrée) - ' || COALESCE(v_product.name, 'Produit'), 1,
       NEW.product_id, NEW.quantity);

  ELSIF NEW.movement_type = 'out' THEN
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order, product_id, quantity
    ) VALUES
      (NEW.tenant_id, v_entry_id, v_variation_account, v_variation_account,
       v_amount, 0, 'Variation de stock (sortie) - ' || COALESCE(v_product.name, 'Produit'), 0,
       NEW.product_id, NEW.quantity),
      (NEW.tenant_id, v_entry_id, v_stock_account, v_stock_account,
       0, v_amount, 'Sortie de stock - ' || COALESCE(v_product.name, 'Produit'), 1,
       NEW.product_id, NEW.quantity);

  ELSIF NEW.movement_type = 'adjustment' THEN
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order, product_id, quantity
    ) VALUES
      (NEW.tenant_id, v_entry_id, v_stock_account, v_stock_account,
       v_amount, 0, 'Ajustement de stock (entrée) - ' || COALESCE(v_product.name, 'Produit'), 0,
       NEW.product_id, NEW.quantity),
      (NEW.tenant_id, v_entry_id, v_variation_account, v_variation_account,
       0, v_amount, 'Variation de stock (ajustement) - ' || COALESCE(v_product.name, 'Produit'), 1,
       NEW.product_id, NEW.quantity);
  END IF;

  -- Bascule en 'posted' APRÈS les lignes
  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;

  RETURN NEW;
END;
$$;
