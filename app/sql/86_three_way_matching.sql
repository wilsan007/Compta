-- ============================================================
-- 86_three_way_matching.sql
--
-- Three-way matching : Bon de commande → Réception → Facture d'achat
--
-- Inspiré de :
--   - Sage Intacct (three-way matching AP automation)
--   - Odoo (PO → receipt → bill matching, purchase approval)
--   - ERPNext (purchase receipt → invoice matching)
--   - SAP (3-way match: PO/GR/IR verification)
--
-- Principe : avant d'approuver une facture d'achat, le système vérifie
-- automatiquement que les quantités et prix correspondent entre :
--   1. Le bon de commande (PO) — ce qui a été commandé
--   2. La réception (Goods Receipt) — ce qui a été reçu
--   3. La facture (Purchase Invoice) — ce qui a été facturé
--
-- Si tout correspond → auto-approve
-- Si écarts → flag pour revue manuelle (statut 'pending_review')
-- ============================================================

-- ============================================================
-- 1. Ajouter les colonnes de liaison sur purchase_invoices
-- ============================================================

-- Lier la facture d'achat au bon de commande
ALTER TABLE purchase_invoices ADD COLUMN IF NOT EXISTS purchase_order_id UUID REFERENCES purchase_orders(id) ON DELETE SET NULL;

-- Lier la facture d'achat à la réception
ALTER TABLE purchase_invoices ADD COLUMN IF NOT EXISTS goods_receipt_id UUID REFERENCES goods_receipts(id) ON DELETE SET NULL;

-- Statut du three-way matching
ALTER TABLE purchase_invoices ADD COLUMN IF NOT EXISTS match_status VARCHAR(20) DEFAULT 'unmatched';
-- Valeurs : unmatched, matched, partial_match, mismatch, pending_review

-- Détails du matching (JSON)
ALTER TABLE purchase_invoices ADD COLUMN IF NOT EXISTS match_details JSONB DEFAULT '{}';

-- ============================================================
-- 2. Ajouter la colonne de liaison sur purchase_invoice_lines
-- ============================================================

-- Lier chaque ligne de facture à la ligne de commande correspondante
ALTER TABLE purchase_invoice_lines ADD COLUMN IF NOT EXISTS purchase_order_line_id UUID REFERENCES purchase_order_lines(id) ON DELETE SET NULL;

-- Quantité reçue (pour comparaison)
ALTER TABLE purchase_invoice_lines ADD COLUMN IF NOT EXISTS quantity_received NUMERIC DEFAULT 0;

-- ============================================================
-- 3. Table : three_way_matches (historique des vérifications)
-- ============================================================
CREATE TABLE IF NOT EXISTS three_way_matches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  purchase_order_id UUID REFERENCES purchase_orders(id) ON DELETE SET NULL,
  goods_receipt_id UUID REFERENCES goods_receipts(id) ON DELETE SET NULL,
  purchase_invoice_id UUID REFERENCES purchase_invoices(id) ON DELETE CASCADE,
  match_status VARCHAR(20) NOT NULL DEFAULT 'pending',
  -- matched, partial_match, mismatch, pending_review
  total_ordered NUMERIC DEFAULT 0,
  total_received NUMERIC DEFAULT 0,
  total_invoiced NUMERIC DEFAULT 0,
  price_variance NUMERIC DEFAULT 0,
  quantity_variance NUMERIC DEFAULT 0,
  line_results JSONB DEFAULT '[]',
  -- Détail par ligne : [{line_id, po_qty, received_qty, invoiced_qty, po_price, invoice_price, status}]
  checked_at TIMESTAMPTZ DEFAULT NOW(),
  checked_by VARCHAR(200),
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_three_way_match_tenant ON three_way_matches(tenant_id);
CREATE INDEX IF NOT EXISTS idx_three_way_match_po ON three_way_matches(purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_three_way_match_gr ON three_way_matches(goods_receipt_id);
CREATE INDEX IF NOT EXISTS idx_three_way_match_pi ON three_way_matches(purchase_invoice_id);
CREATE INDEX IF NOT EXISTS idx_three_way_match_status ON three_way_matches(match_status);

-- RLS
ALTER TABLE three_way_matches ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY tenant_select_three_way_matches ON three_way_matches FOR SELECT USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'select policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_insert_three_way_matches ON three_way_matches FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'insert policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_update_three_way_matches ON three_way_matches FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'update policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_delete_three_way_matches ON three_way_matches FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'delete policy: %', SQLERRM; END $$;


-- ============================================================
-- 4. Fonction : vérifier le three-way matching
-- ============================================================
-- Vérifie que les quantités et prix correspondent entre PO, réception et facture.
-- Inspiré de : Sage Intacct (AP three-way match), Odoo (purchase bill matching)
--
-- Règles :
--   - Quantité facturée ≤ Quantité reçue (on ne paie que ce qu'on a reçu)
--   - Prix unitaire facturé = Prix unitaire commandé (tolérance 1%)
--   - Si écarts < tolérance → matched
--   - Si écarts ≥ tolérance → mismatch (flag pour revue)
--   - Si pas de réception → pending_review (on ne peut pas vérifier)
CREATE OR REPLACE FUNCTION perform_three_way_match()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_po_id uuid;
  v_gr_id uuid;
  v_po RECORD;
  v_po_line RECORD;
  v_gr_line RECORD;
  v_inv_line RECORD;
  v_total_ordered numeric := 0;
  v_total_received numeric := 0;
  v_total_invoiced numeric := 0;
  v_price_variance numeric := 0;
  v_quantity_variance numeric := 0;
  v_line_results jsonb := '[]'::jsonb;
  v_line_result jsonb;
  v_match_status varchar := 'matched';
  v_has_receipt boolean := false;
  v_tolerance numeric := 0.01;  -- 1% de tolérance
  v_line_status varchar;
BEGIN
  -- Se déclenche quand approval_status passe à 'pending' ou 'submitted'
  IF NEW.approval_status IS NOT DISTINCT FROM OLD.approval_status THEN RETURN NEW; END IF;
  IF NEW.approval_status NOT IN ('pending', 'submitted') THEN RETURN NEW; END IF;

  v_po_id := NEW.purchase_order_id;
  v_gr_id := NEW.goods_receipt_id;

  -- Si pas de PO lié, on ne peut pas faire le matching
  IF v_po_id IS NULL THEN
    NEW.match_status := 'pending_review';
    NEW.match_details := jsonb_build_object('reason', 'no_purchase_order_linked');
    RETURN NEW;
  END IF;

  -- Vérifier si une réception existe
  v_has_receipt := v_gr_id IS NOT NULL;

  -- Récupérer le PO
  SELECT * INTO v_po FROM purchase_orders WHERE id = v_po_id AND tenant_id = NEW.tenant_id;
  IF NOT FOUND THEN
    NEW.match_status := 'pending_review';
    NEW.match_details := jsonb_build_object('reason', 'purchase_order_not_found');
    RETURN NEW;
  END IF;

  -- Parcourir les lignes de la facture et comparer avec les lignes du PO
  FOR v_inv_line IN
    SELECT * FROM purchase_invoice_lines
    WHERE purchase_invoice_id = NEW.id AND tenant_id = NEW.tenant_id
    ORDER BY line_order
  LOOP
    v_line_status := 'matched';
    v_price_variance := 0;
    v_quantity_variance := 0;
    v_total_invoiced := v_total_invoiced + COALESCE(v_inv_line.quantity, 0) * COALESCE(v_inv_line.unit_price, 0);

    -- Trouver la ligne du PO correspondante
    IF v_inv_line.purchase_order_line_id IS NOT NULL THEN
      SELECT * INTO v_po_line
      FROM purchase_order_lines
      WHERE id = v_inv_line.purchase_order_line_id AND tenant_id = NEW.tenant_id;
    ELSE
      -- Matching par product_id si pas de lien explicite
      SELECT * INTO v_po_line
      FROM purchase_order_lines
      WHERE purchase_order_id = v_po_id
        AND tenant_id = NEW.tenant_id
        AND product_id = v_inv_line.product_id
      LIMIT 1;
    END IF;

    IF FOUND THEN
      v_total_ordered := v_total_ordered + COALESCE(v_po_line.quantity, 0) * COALESCE(v_po_line.unit_price, 0);

      -- Vérifier le prix (tolérance 1%)
      IF v_po_line.unit_price > 0 THEN
        v_price_variance := ABS(v_inv_line.unit_price - v_po_line.unit_price) / v_po_line.unit_price;
        IF v_price_variance > v_tolerance THEN
          v_line_status := 'price_mismatch';
          v_match_status := 'mismatch';
        END IF;
      END IF;

      -- Vérifier la quantité si on a une réception
      IF v_has_receipt THEN
        -- Trouver la ligne de réception correspondante
        SELECT * INTO v_gr_line
        FROM goods_receipt_lines
        WHERE goods_receipt_id = v_gr_id
          AND tenant_id = NEW.tenant_id
          AND product_id = v_inv_line.product_id
        LIMIT 1;

        IF FOUND THEN
          v_total_received := v_total_received + COALESCE(v_gr_line.quantity_received, 0) * COALESCE(v_po_line.unit_price, 0);

          -- Quantité facturée ne doit pas dépasser quantité reçue
          IF v_inv_line.quantity > v_gr_line.quantity_received THEN
            v_quantity_variance := v_inv_line.quantity - v_gr_line.quantity_received;
            v_line_status := 'quantity_exceeds_received';
            v_match_status := 'mismatch';
          END IF;

          v_line_result := jsonb_build_object(
            'invoice_line_id', v_inv_line.id,
            'product_id', v_inv_line.product_id,
            'po_quantity', v_po_line.quantity,
            'po_unit_price', v_po_line.unit_price,
            'received_quantity', v_gr_line.quantity_received,
            'invoiced_quantity', v_inv_line.quantity,
            'invoice_unit_price', v_inv_line.unit_price,
            'price_variance', v_price_variance,
            'quantity_variance', v_quantity_variance,
            'status', v_line_status
          );
        ELSE
          -- Pas de ligne de réception pour ce produit
          v_line_status := 'no_receipt_line';
          IF v_match_status = 'matched' THEN v_match_status := 'partial_match'; END IF;

          v_line_result := jsonb_build_object(
            'invoice_line_id', v_inv_line.id,
            'product_id', v_inv_line.product_id,
            'po_quantity', v_po_line.quantity,
            'po_unit_price', v_po_line.unit_price,
            'received_quantity', 0,
            'invoiced_quantity', v_inv_line.quantity,
            'invoice_unit_price', v_inv_line.unit_price,
            'status', v_line_status
          );
        END IF;
      ELSE
        -- Pas de réception → on ne peut pas vérifier les quantités
        v_line_status := 'no_receipt';
        IF v_match_status = 'matched' THEN v_match_status := 'pending_review'; END IF;

        v_line_result := jsonb_build_object(
          'invoice_line_id', v_inv_line.id,
          'product_id', v_inv_line.product_id,
          'po_quantity', v_po_line.quantity,
          'po_unit_price', v_po_line.unit_price,
          'received_quantity', null,
          'invoiced_quantity', v_inv_line.quantity,
          'invoice_unit_price', v_inv_line.unit_price,
          'status', v_line_status
        );
      END IF;
    ELSE
      -- Ligne de facture sans ligne de PO correspondante
      v_line_status := 'no_po_line';
      v_match_status := 'mismatch';

      v_line_result := jsonb_build_object(
        'invoice_line_id', v_inv_line.id,
        'product_id', v_inv_line.product_id,
        'po_quantity', null,
        'po_unit_price', null,
        'received_quantity', null,
        'invoiced_quantity', v_inv_line.quantity,
        'invoice_unit_price', v_inv_line.unit_price,
        'status', v_line_status
      );
    END IF;

    v_line_results := v_line_results || jsonb_build_array(v_line_result);
  END LOOP;

  -- Mettre à jour la facture avec les résultats du matching
  NEW.match_status := v_match_status;
  NEW.match_details := jsonb_build_object(
    'total_ordered', v_total_ordered,
    'total_received', v_total_received,
    'total_invoiced', v_total_invoiced,
    'price_variance', v_price_variance,
    'quantity_variance', v_quantity_variance,
    'has_receipt', v_has_receipt,
    'line_results', v_line_results,
    'checked_at', now()
  );

  -- Si tout correspond → auto-approuver
  IF v_match_status = 'matched' THEN
    NEW.approval_status := 'approved';
    NEW.approved_at := now();
  END IF;

  -- Enregistrer le résultat dans three_way_matches
  INSERT INTO three_way_matches (
    tenant_id, purchase_order_id, goods_receipt_id, purchase_invoice_id,
    match_status, total_ordered, total_received, total_invoiced,
    price_variance, quantity_variance, line_results, checked_at
  ) VALUES (
    NEW.tenant_id, v_po_id, v_gr_id, NEW.id,
    v_match_status, v_total_ordered, v_total_received, v_total_invoiced,
    v_price_variance, v_quantity_variance, v_line_results, now()
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS three_way_match_on_invoice ON purchase_invoices;
CREATE TRIGGER three_way_match_on_invoice
  BEFORE UPDATE OF approval_status
  ON purchase_invoices
  FOR EACH ROW
  WHEN (NEW.approval_status IN ('pending', 'submitted'))
  EXECUTE FUNCTION perform_three_way_match();


-- ============================================================
-- 5. Fonction : vérifier le three-way matching manuellement
-- ============================================================
-- Permet de relancer la vérification manuellement sur une facture existante.
CREATE OR REPLACE FUNCTION run_three_way_match(p_invoice_id uuid)
RETURNS table(
  match_status varchar,
  total_ordered numeric,
  total_received numeric,
  total_invoiced numeric,
  price_variance numeric,
  quantity_variance numeric,
  line_results jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice RECORD;
  v_match RECORD;
BEGIN
  SELECT * INTO v_invoice FROM purchase_invoices WHERE id = p_invoice_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Purchase invoice not found'; END IF;

  -- Mettre à jour le approval_status pour déclencher le trigger
  UPDATE purchase_invoices
    SET approval_status = 'pending'
  WHERE id = p_invoice_id AND approval_status NOT IN ('pending', 'submitted');

  -- Récupérer le résultat
  SELECT match_status,
    (match_details->>'total_ordered')::numeric,
    (match_details->>'total_received')::numeric,
    (match_details->>'total_invoiced')::numeric,
    (match_details->>'price_variance')::numeric,
    (match_details->>'quantity_variance')::numeric,
    match_details->'line_results'
  INTO v_match
  FROM purchase_invoices WHERE id = p_invoice_id;

  RETURN QUERY SELECT v_match.match_status, v_match.total_ordered, v_match.total_received,
    v_match.total_invoiced, v_match.price_variance, v_match.quantity_variance, v_match.line_results;
END;
$$;


-- ============================================================
-- 6. Trigger : auto-lier la facture au PO et à la réception
-- ============================================================
-- Quand une facture d'achat est créée avec un supplier_id, on cherche
-- automatiquement le PO et la réception correspondants.
CREATE OR REPLACE FUNCTION auto_link_invoice_to_po_and_receipt()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_po_id uuid;
  v_gr_id uuid;
BEGIN
  -- Seulement si pas déjà lié
  IF NEW.purchase_order_id IS NOT NULL THEN RETURN NEW; END IF;

  -- Chercher le PO le plus récent pour ce fournisseur
  SELECT id INTO v_po_id
  FROM purchase_orders
  WHERE supplier_id = NEW.supplier_id
    AND tenant_id = NEW.tenant_id
    AND status IN ('confirmed', 'received', 'partial')
  ORDER BY order_date DESC
  LIMIT 1;

  IF v_po_id IS NOT NULL THEN
    NEW.purchase_order_id := v_po_id;

    -- Chercher la réception liée à ce PO
    SELECT id INTO v_gr_id
    FROM goods_receipts
    WHERE purchase_order_id = v_po_id
      AND tenant_id = NEW.tenant_id
      AND status = 'received'
    ORDER BY receipt_date DESC
    LIMIT 1;

    IF v_gr_id IS NOT NULL THEN
      NEW.goods_receipt_id := v_gr_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS auto_link_invoice_po ON purchase_invoices;
CREATE TRIGGER auto_link_invoice_po
  BEFORE INSERT
  ON purchase_invoices
  FOR EACH ROW
  WHEN (NEW.purchase_order_id IS NULL AND NEW.supplier_id IS NOT NULL)
  EXECUTE FUNCTION auto_link_invoice_to_po_and_receipt();


-- ============================================================
-- 7. Trigger : auto-lier les lignes de facture aux lignes de PO
-- ============================================================
CREATE OR REPLACE FUNCTION auto_link_invoice_line_to_po_line()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_po_line_id uuid;
  v_po_id uuid;
  v_qty_received numeric;
BEGIN
  -- Récupérer le PO lié à la facture
  SELECT purchase_order_id INTO v_po_id
  FROM purchase_invoices
  WHERE id = NEW.purchase_invoice_id AND tenant_id = NEW.tenant_id;

  IF v_po_id IS NULL THEN RETURN NEW; END IF;

  -- Chercher la ligne du PO correspondant au même produit
  SELECT id INTO v_po_line_id
  FROM purchase_order_lines
  WHERE purchase_order_id = v_po_id
    AND tenant_id = NEW.tenant_id
    AND product_id = NEW.product_id
  LIMIT 1;

  IF v_po_line_id IS NOT NULL THEN
    NEW.purchase_order_line_id := v_po_line_id;
  END IF;

  -- Récupérer la quantité reçue si une réception est liée
  SELECT COALESCE(SUM(grl.quantity_received), 0)
  INTO v_qty_received
  FROM goods_receipts gr
  JOIN goods_receipt_lines grl ON grl.goods_receipt_id = gr.id
  WHERE gr.purchase_order_id = v_po_id
    AND gr.tenant_id = NEW.tenant_id
    AND gr.status = 'received'
    AND grl.product_id = NEW.product_id;

  NEW.quantity_received := v_qty_received;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS auto_link_invoice_line ON purchase_invoice_lines;
CREATE TRIGGER auto_link_invoice_line
  BEFORE INSERT
  ON purchase_invoice_lines
  FOR EACH ROW
  WHEN (NEW.purchase_order_line_id IS NULL)
  EXECUTE FUNCTION auto_link_invoice_line_to_po_line();


-- ============================================================
-- RÉCAPITULATIF
-- ============================================================
-- Triggers créés :
--   1. three_way_match_on_invoice  ON purchase_invoices BEFORE UPDATE(approval_status)
--   2. auto_link_invoice_po         ON purchase_invoices BEFORE INSERT
--   3. auto_link_invoice_line       ON purchase_invoice_lines BEFORE INSERT
--
-- Fonctions créées :
--   perform_three_way_match()       — vérification automatique PO/GR/Invoice
--   run_three_way_match(uuid)       — vérification manuelle sur une facture
--   auto_link_invoice_to_po_and_receipt() — liaison auto facture→PO→réception
--   auto_link_invoice_line_to_po_line()   — liaison auto ligne facture→ligne PO
--
-- Colonnes ajoutées :
--   purchase_invoices.purchase_order_id, goods_receipt_id, match_status, match_details
--   purchase_invoice_lines.purchase_order_line_id, quantity_received
--
-- Table créée :
--   three_way_matches — historique des vérifications de matching
--
-- Total : 3 triggers + 4 fonctions + 6 colonnes + 1 table
-- ============================================================
