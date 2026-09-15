-- ============================================================
-- 137_fix_triggers_constraints.sql
-- LOT1-01 : Brancher les triggers sur validation_status / approval_status
-- LOT2-01/LOT2-02 : subtotal → total sur les lignes de facture
-- LOT1-04 : Élargir delivery_notes_status_check ('shipped')
-- LOT1-05 : Élargir pay_runs_status_check ('closed', 'processing', 'cancelled')
-- LOT4-04 : Index unique pour idempotence des mouvements de stock
-- ============================================================

-- ============================================================
-- LOT1-04 : Élargir delivery_notes_status_check
-- (safe après LOT4-04 trigger fix dans migration 133)
-- ============================================================
ALTER TABLE delivery_notes DROP CONSTRAINT IF EXISTS delivery_notes_status_check;
ALTER TABLE delivery_notes ADD CONSTRAINT delivery_notes_status_check
  CHECK (status = ANY (ARRAY['pending','shipped','delivered','returned','cancelled']));

-- ============================================================
-- LOT1-05 : Élargir pay_runs_status_check
-- ============================================================
ALTER TABLE pay_runs DROP CONSTRAINT IF EXISTS pay_runs_status_check;
ALTER TABLE pay_runs ADD CONSTRAINT pay_runs_status_check
  CHECK (status = ANY (ARRAY['draft','processing','approved','closed','paid','cancelled']));

-- ============================================================
-- LOT4-04 : Index unique pour idempotence des mouvements de stock
-- Garde structurelle : survit à toute modification future de condition de trigger
-- ============================================================
CREATE UNIQUE INDEX IF NOT EXISTS uq_stock_movement_source
  ON stock_movements (tenant_id, reference_type, reference_id, product_id, movement_type)
  WHERE reference_type IS NOT NULL AND reference_id IS NOT NULL;

-- ============================================================
-- LOT2-01/LOT2-02 : Ajouter vat_code/vat_amount à purchase_invoice_lines
-- (existe déjà sur invoice_lines via migration 109)
-- ============================================================
ALTER TABLE purchase_invoice_lines ADD COLUMN IF NOT EXISTS vat_code text DEFAULT 'FR20';
ALTER TABLE purchase_invoice_lines ADD COLUMN IF NOT EXISTS vat_amount numeric DEFAULT 0;

-- ============================================================
-- LOT1-01 + LOT2-01 : Réécrire create_journal_on_invoice_validate
-- - Surveiller validation_status = 'validated' au lieu de status IN ('validated','posted')
-- - il.subtotal → il.total (subtotal n'existe pas sur invoice_lines)
-- ============================================================
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
  v_compte_tva text;
  v_ordre int := 2;
  v_vat RECORD;
  v_ligne RECORD;
  v_defaut_vente text := '707000';
BEGIN
  IF NEW.validation_status IS DISTINCT FROM OLD.validation_status
     AND NEW.validation_status = 'validated' THEN
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

    -- Ligne client (débit)
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      account_tiers, third_party_id, echeance_date,
      debit, credit, description, line_order
    ) VALUES (
      NEW.tenant_id, v_entry_id, v_collectif, v_collectif,
      v_tiers, v_third_party, NEW.due_date,
      NEW.total, 0, 'Client ' || NEW.number, 0
    );

    -- ACC-03 : boucle sur les lignes de facture regroupées par compte de produit
    -- LOT2-01 : il.subtotal → il.total (subtotal n'existe pas sur invoice_lines)
    FOR v_ligne IN
      SELECT
        COALESCE(p.sale_account_code, pc.sale_account_code, v_defaut_vente) AS compte,
        SUM(il.total) AS montant
      FROM invoice_lines il
      LEFT JOIN products p ON p.id = il.product_id AND p.tenant_id = NEW.tenant_id
      LEFT JOIN product_categories pc ON pc.id = p.category_id AND pc.tenant_id = NEW.tenant_id
      WHERE il.invoice_id = NEW.id AND il.tenant_id = NEW.tenant_id
      GROUP BY 1
    LOOP
      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        debit, credit, description, line_order
      ) VALUES (
        New.tenant_id, v_entry_id, v_ligne.compte, v_ligne.compte,
        0, v_ligne.montant, 'Ventes ' || v_ligne.compte || ' — ' || NEW.number,
        v_ordre
      );
      v_ordre := v_ordre + 1;
    END LOOP;

    -- Fallback si pas de lignes détaillées
    IF v_ordre = 2 AND NEW.subtotal > 0 THEN
      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        debit, credit, description, line_order
      ) VALUES (
        New.tenant_id, v_entry_id, v_defaut_vente, v_defaut_vente,
        0, NEW.subtotal, 'Ventes ' || NEW.number, 1
      );
      v_ordre := 3;
    END IF;

    -- ACC-02 : boucle sur les taux de TVA
    FOR v_vat IN
      SELECT il.vat_code,
             SUM(il.total) AS base_ht,
             SUM(il.vat_amount) AS montant_tva
      FROM invoice_lines il
      WHERE il.invoice_id = NEW.id AND il.tenant_id = NEW.tenant_id
      GROUP BY il.vat_code
    LOOP
      SELECT account_code INTO v_compte_tva
      FROM vat_account_mapping
      WHERE tenant_id IN (NEW.tenant_id, '00000000-0000-0000-0000-000000000000')
        AND vat_code = v_vat.vat_code
        AND direction = 'collected'
      ORDER BY tenant_id DESC
      LIMIT 1;

      v_compte_tva := COALESCE(v_compte_tva, '4457000');

      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        vat_code, vat_amount,
        debit, credit, description, line_order
      ) VALUES (
        New.tenant_id, v_entry_id, v_compte_tva, v_compte_tva,
        v_vat.vat_code, v_vat.montant_tva,
        0, v_vat.montant_tva,
        'TVA collectée ' || v_vat.vat_code || ' — ' || NEW.number,
        v_ordre
      );
      v_ordre := v_ordre + 1;
    END LOOP;

    -- Fallback TVA
    IF v_ordre = 2 AND NEW.vat_total > 0 THEN
      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        vat_code, vat_amount,
        debit, credit, description, line_order
      ) VALUES (
        New.tenant_id, v_entry_id, '4457000', '4457000',
        'FR20', NEW.vat_total,
        0, NEW.vat_total, 'TVA collectée ' || NEW.number, 2
      );
    END IF;

    -- Bascule en 'posted' APRÈS les lignes (SOC-01)
    UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;
    UPDATE invoices SET transferred_entry_id = v_entry_id WHERE id = NEW.id AND tenant_id = NEW.tenant_id;
  END IF;
  RETURN NEW;
END;
$$;

-- ============================================================
-- LOT1-01 + LOT2-02 : Réécrire create_journal_on_purchase_invoice_validate
-- - Surveiller approval_status = 'approved' au lieu de status IN ('validated','posted','approved')
-- - pil.subtotal → pil.total (subtotal n'existe pas sur purchase_invoice_lines)
-- ============================================================
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
  v_compte_tva text;
  v_ordre int := 0;
  v_vat RECORD;
  v_ligne RECORD;
  v_defaut_achat text := '607000';
BEGIN
  IF NEW.approval_status IS DISTINCT FROM OLD.approval_status
     AND NEW.approval_status = 'approved' THEN
    SELECT id INTO v_existing FROM journal_entries
      WHERE tenant_id = NEW.tenant_id AND invoice_ref = NEW.number AND journal_code = 'AC' LIMIT 1;
    IF v_existing IS NOT NULL THEN RETURN NEW; END IF;

    -- ACC-01
    SELECT COALESCE(s.account_collectif, '401000'), s.account_tiers, s.id
    INTO v_collectif, v_tiers, v_third_party
    FROM suppliers s
    WHERE s.id = NEW.supplier_id AND s.tenant_id = NEW.tenant_id;

    v_number := 'JE-PI-' || NEW.number;
    INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, invoice_ref, piece_number)
    VALUES (NEW.tenant_id, v_number, NEW.date, 'AC', 'draft', 'Facture achat ' || NEW.number, NEW.number, v_number)
    RETURNING id INTO v_entry_id;

    -- ACC-03 : boucle sur les lignes d'achat regroupées par compte de charge
    -- LOT2-02 : pil.subtotal → pil.total (subtotal n'existe pas sur purchase_invoice_lines)
    FOR v_ligne IN
      SELECT
        COALESCE(p.purchase_account_code, pc.purchase_account_code, v_defaut_achat) AS compte,
        SUM(pil.total) AS montant
      FROM purchase_invoice_lines pil
      LEFT JOIN products p ON p.id = pil.product_id AND p.tenant_id = NEW.tenant_id
      LEFT JOIN product_categories pc ON pc.id = p.category_id AND pc.tenant_id = NEW.tenant_id
      WHERE pil.purchase_invoice_id = NEW.id AND pil.tenant_id = NEW.tenant_id
      GROUP BY 1
    LOOP
      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        debit, credit, description, line_order
      ) VALUES (
        New.tenant_id, v_entry_id, v_ligne.compte, v_ligne.compte,
        v_ligne.montant, 0, 'Achats ' || v_ligne.compte || ' — ' || NEW.number,
        v_ordre
      );
      v_ordre := v_ordre + 1;
    END LOOP;

    -- Fallback si pas de lignes détaillées
    IF v_ordre = 0 AND NEW.subtotal > 0 THEN
      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        debit, credit, description, line_order
      ) VALUES (
        New.tenant_id, v_entry_id, v_defaut_achat, v_defaut_achat,
        NEW.subtotal, 0, 'Achats ' || NEW.number, 0
      );
      v_ordre := 1;
    END IF;

    -- ACC-02 : boucle sur les taux de TVA déductibles
    FOR v_vat IN
      SELECT pil.vat_code,
             SUM(pil.total) AS base_ht,
             SUM(pil.vat_amount) AS montant_tva
      FROM purchase_invoice_lines pil
      WHERE pil.purchase_invoice_id = NEW.id AND pil.tenant_id = NEW.tenant_id
      GROUP BY pil.vat_code
    LOOP
      SELECT account_code INTO v_compte_tva
      FROM vat_account_mapping
      WHERE tenant_id IN (NEW.tenant_id, '00000000-0000-0000-0000-000000000000')
        AND vat_code = v_vat.vat_code
        AND direction = 'deductible'
      ORDER BY tenant_id DESC
      LIMIT 1;

      v_compte_tva := COALESCE(v_compte_tva, '4456000');

      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        vat_code, vat_amount,
        debit, credit, description, line_order
      ) VALUES (
        New.tenant_id, v_entry_id, v_compte_tva, v_compte_tva,
        v_vat.vat_code, v_vat.montant_tva,
        v_vat.montant_tva, 0, 'TVA déductible ' || v_vat.vat_code || ' — ' || NEW.number,
        v_ordre
      );
      v_ordre := v_ordre + 1;
    END LOOP;

    -- Fallback TVA
    IF v_ordre <= 1 AND NEW.vat_total > 0 THEN
      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        vat_code, vat_amount,
        debit, credit, description, line_order
      ) VALUES (
        New.tenant_id, v_entry_id, '4456000', '4456000',
        'FR20', NEW.vat_total,
        NEW.vat_total, 0, 'TVA déductible ' || NEW.number, v_ordre
      );
      v_ordre := v_ordre + 1;
    END IF;

    -- Ligne fournisseur (crédit)
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      account_tiers, third_party_id, echeance_date,
      debit, credit, description, line_order
    ) VALUES (
      New.tenant_id, v_entry_id, v_collectif, v_collectif,
      v_tiers, v_third_party, NEW.due_date,
      0, NEW.total, 'Fournisseur ' || NEW.number, 99
    );

    -- Bascule en 'posted' APRÈS les lignes (SOC-01)
    UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;
    UPDATE purchase_invoices SET transferred_entry_id = v_entry_id WHERE id = NEW.id AND tenant_id = NEW.tenant_id;
  END IF;
  RETURN NEW;
END;
$$;
