-- ============================================================
-- 110_product_accounts.sql
-- ACC-03 : Comptes de produit et de charge par article
--
-- Remplace la ligne unique 707000/607000 par une boucle sur les
-- lignes de facture regroupées par compte de produit/charge.
-- ============================================================

-- ============================================================
-- 1. Ajouter les colonnes de comptes sur products
-- ============================================================
ALTER TABLE products ADD COLUMN IF NOT EXISTS sale_account_code text;
ALTER TABLE products ADD COLUMN IF NOT EXISTS purchase_account_code text;
ALTER TABLE products ADD COLUMN IF NOT EXISTS stock_account_code text;
ALTER TABLE products ADD COLUMN IF NOT EXISTS category_id uuid;

-- ============================================================
-- 2. Créer product_categories si elle n'existe pas
-- ============================================================
CREATE TABLE IF NOT EXISTS product_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  name text NOT NULL,
  parent_id uuid REFERENCES product_categories(id),
  sale_account_code text,
  purchase_account_code text,
  stock_account_code text,
  created_at timestamptz DEFAULT NOW(),
  updated_at timestamptz DEFAULT NOW()
);

ALTER TABLE product_categories ENABLE ROW LEVEL SECURITY;
CREATE POLICY product_categories_tenant_select ON product_categories
  FOR SELECT USING (tenant_id = current_tenant_id());
CREATE POLICY product_categories_tenant_all ON product_categories
  FOR ALL USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());

-- Lier products.category_id à product_categories
DO $$ BEGIN
  ALTER TABLE products ADD CONSTRAINT products_category_fk
    FOREIGN KEY (category_id) REFERENCES product_categories(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================
-- 3. Réécrire le trigger de facture vente avec comptes par article
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
    -- Cascade : produit → catégorie → défaut (707000)
    FOR v_ligne IN
      SELECT
        COALESCE(p.sale_account_code, pc.sale_account_code, v_defaut_vente) AS compte,
        SUM(il.subtotal) AS montant
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
             SUM(il.subtotal) AS base_ht,
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
-- 4. Réécrire le trigger de facture achat avec comptes par article
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
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status IN ('validated', 'posted', 'approved') THEN
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
    FOR v_ligne IN
      SELECT
        COALESCE(p.purchase_account_code, pc.purchase_account_code, v_defaut_achat) AS compte,
        SUM(pil.subtotal) AS montant
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
             SUM(pil.subtotal) AS base_ht,
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
