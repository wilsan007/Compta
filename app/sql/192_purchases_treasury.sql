-- ============================================================
-- 192_purchases_treasury.sql — lot G du plan correctif du 21/09 (vague V3)
--
-- Défauts prouvés par sql/192_purchases_treasury_tests.sql (AUD-G01) :
--   A02  totaux d'en-tête saisis par l'écran ; facture approuvée modifiable
--   A03  numéro tiré au hasard par l'écran (AUD-G02) ; pas de champ pour la
--        référence du fournisseur
--   A04  avoirs fournisseurs sans écriture ni rattachement
--   A05  décaissement toujours en 512000 / BQ ; facture payée non lettrée ;
--        un décaissement échouait dès que le solde calculé du compte bancaire
--        devenait négatif (contrainte posée à tort par la migration 82)
--   A06  trop-payé fournisseur débité au 401 ; décision n° 1 appliquée
--        symétriquement : avance fournisseur 4091
--   A07  facture fournisseur approuvable sans ligne
--
-- Même mécanique que la 190 pour les ventes ; les outils de la 190
-- (next_legal_document_number, draft_document_number, line_amounts,
-- line_vat_code, treasury_for_payment, next_lettrage_code_for) sont réutilisés.
-- ============================================================

-- Un compte bancaire peut être à découvert
ALTER TABLE bank_accounts DROP CONSTRAINT IF EXISTS bank_accounts_calculated_balance_nonneg;

-- ------------------------------------------------------------
-- 1. Lignes de facture fournisseur : montants calculés, figées après approbation
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION purchase_invoice_line_compute()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE a record;
BEGIN
  IF EXISTS (SELECT 1 FROM purchase_invoices WHERE approval_status = 'approved'
             AND id IN (CASE WHEN TG_OP <> 'INSERT' THEN OLD.purchase_invoice_id END,
                        CASE WHEN TG_OP <> 'DELETE' THEN NEW.purchase_invoice_id END)) THEN
    RAISE EXCEPTION 'Facture fournisseur approuvée : ses lignes ne peuvent plus être modifiées (saisissez un avoir)'
      USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  a := line_amounts(NEW.quantity, NEW.unit_price, NEW.vat_rate);
  NEW.quantity := COALESCE(NEW.quantity, 0);
  NEW.unit_price := COALESCE(NEW.unit_price, 0);
  NEW.vat_rate := COALESCE(NEW.vat_rate, 0);
  NEW.total := a.total;
  NEW.vat_total := a.vat;
  NEW.vat_amount := a.vat;
  NEW.vat_code := line_vat_code(NEW.vat_code, NEW.vat_rate);
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION purchase_invoice_lines_refresh_totals()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE purchase_invoices i SET subtotal = s.ht, vat_total = s.tva, total = s.ht + s.tva
  FROM (SELECT x.id, COALESCE(sum(l.total), 0) ht, COALESCE(sum(l.vat_amount), 0) tva
        FROM (SELECT DISTINCT unnest(ARRAY[CASE WHEN TG_OP <> 'INSERT' THEN OLD.purchase_invoice_id END,
                                           CASE WHEN TG_OP <> 'DELETE' THEN NEW.purchase_invoice_id END]) AS id) x
        LEFT JOIN purchase_invoice_lines l ON l.purchase_invoice_id = x.id
        WHERE x.id IS NOT NULL GROUP BY x.id) s
  WHERE i.id = s.id AND i.approval_status IS DISTINCT FROM 'approved'
    AND (i.subtotal, i.vat_total, i.total) IS DISTINCT FROM (s.ht, s.tva, s.ht + s.tva);
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS tg_line_compute ON purchase_invoice_lines;
CREATE TRIGGER tg_line_compute BEFORE INSERT OR UPDATE OR DELETE ON purchase_invoice_lines
  FOR EACH ROW EXECUTE FUNCTION purchase_invoice_line_compute();
DROP TRIGGER IF EXISTS tg_line_refresh_totals ON purchase_invoice_lines;
CREATE TRIGGER tg_line_refresh_totals AFTER INSERT OR UPDATE OR DELETE ON purchase_invoice_lines
  FOR EACH ROW EXECUTE FUNCTION purchase_invoice_lines_refresh_totals();

-- ------------------------------------------------------------
-- 2. Facture fournisseur : référence du fournisseur, numéro interne, gel (A02, A03, A07)
-- ------------------------------------------------------------
ALTER TABLE purchase_invoices ADD COLUMN IF NOT EXISTS supplier_reference text;
COMMENT ON COLUMN purchase_invoices.supplier_reference IS 'Numéro de la facture chez le fournisseur (pièce reçue)';
COMMENT ON COLUMN purchase_invoices.number IS
  'AUD-G02 — numéro interne : provisoire en brouillon, ACH-<exercice>-n attribué à l''approbation';
UPDATE purchase_invoices SET supplier_reference = number WHERE supplier_reference IS NULL;

CREATE OR REPLACE FUNCTION purchase_invoice_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_n int; v_ht numeric; v_tva numeric;
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.approval_status := COALESCE(NEW.approval_status, 'pending');
    IF NEW.approval_status = 'approved' THEN
      RAISE EXCEPTION 'Une facture fournisseur est saisie puis approuvée (l''approbation attribue son numéro et son écriture)'
        USING ERRCODE = 'check_violation';
    END IF;
    -- Un numéro saisi par un ancien écran est la référence du fournisseur
    NEW.supplier_reference := COALESCE(NEW.supplier_reference, NEW.number);
    NEW.number := draft_document_number('ACH', NEW.id);
    NEW.amount_paid := 0;
    NEW.amount_due := COALESCE(NEW.total, 0);
    RETURN NEW;
  END IF;

  -- Le payé ne se saisit pas : il résulte des règlements et avoirs (refresh_purchase_invoice_settlement)
  IF current_setting('app.settlement_in_progress', true) IS DISTINCT FROM 'on'
     AND (NEW.amount_paid IS DISTINCT FROM OLD.amount_paid
          OR NEW.payment_state IS DISTINCT FROM OLD.payment_state
          OR (NEW.status = 'paid' AND OLD.status IS DISTINCT FROM 'paid')
          OR (OLD.approval_status = 'approved' AND NEW.amount_due IS DISTINCT FROM OLD.amount_due)) THEN
    RAISE EXCEPTION 'Facture fournisseur % : le montant payé résulte des règlements — enregistrez un décaissement', OLD.number
      USING ERRCODE = 'check_violation';
  END IF;

  IF OLD.approval_status = 'approved' THEN
    IF NEW.approval_status IS DISTINCT FROM 'approved'
       OR (NEW.number, NEW.date, NEW.supplier_id, NEW.subtotal, NEW.vat_total, NEW.total,
           NEW.currency_code, NEW.exchange_rate, NEW.tenant_id)
          IS DISTINCT FROM
          (OLD.number, OLD.date, OLD.supplier_id, OLD.subtotal, OLD.vat_total, OLD.total,
           OLD.currency_code, OLD.exchange_rate, OLD.tenant_id) THEN
      RAISE EXCEPTION 'Facture fournisseur % approuvée : numéro, date, fournisseur et montants ne sont plus modifiables (saisissez un avoir)', OLD.number
        USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;

  NEW.number := OLD.number;
  SELECT count(*), COALESCE(sum(total), 0), COALESCE(sum(vat_amount), 0) INTO v_n, v_ht, v_tva
  FROM purchase_invoice_lines WHERE purchase_invoice_id = NEW.id;
  IF v_n > 0 THEN
    NEW.subtotal := v_ht; NEW.vat_total := v_tva; NEW.total := v_ht + v_tva;
  END IF;
  NEW.amount_due := GREATEST(COALESCE(NEW.total, 0) - COALESCE(NEW.amount_paid, 0), 0);

  IF NEW.approval_status = 'approved' THEN
    IF v_n = 0 THEN
      RAISE EXCEPTION 'Facture fournisseur sans ligne : rien à approuver' USING ERRCODE = 'check_violation';
    END IF;
    NEW.number := next_legal_document_number(NEW.tenant_id, 'ACH', NEW.date);
    NEW.approved_at := COALESCE(NEW.approved_at, now());
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS tg_purchase_invoice_guard ON purchase_invoices;
CREATE TRIGGER tg_purchase_invoice_guard
  BEFORE INSERT OR UPDATE ON purchase_invoices
  FOR EACH ROW EXECUTE FUNCTION purchase_invoice_guard();

-- ------------------------------------------------------------
-- 3. Règlement d'une facture fournisseur : reste dû, statut, lettrage
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION refresh_purchase_invoice_settlement(p_invoice uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_inv purchase_invoices%ROWTYPE;
  v_paid numeric; v_credits numeric; v_due numeric;
  v_account text; v_lines uuid[]; v_d numeric; v_c numeric; v_open int; v_code text;
BEGIN
  SELECT * INTO v_inv FROM purchase_invoices WHERE id = p_invoice;
  IF NOT FOUND THEN RETURN; END IF;

  SELECT COALESCE(sum(amount), 0) INTO v_paid FROM supplier_payments
  WHERE purchase_invoice_id = p_invoice AND tenant_id = v_inv.tenant_id AND status IN ('recorded', 'reconciled');
  SELECT COALESCE(sum(total), 0) INTO v_credits FROM purchase_credit_notes
  WHERE purchase_invoice_id = p_invoice AND tenant_id = v_inv.tenant_id AND status IN ('validated', 'applied');
  v_due := GREATEST(COALESCE(v_inv.total, 0) - v_paid - v_credits, 0);

  PERFORM set_config('app.settlement_in_progress', 'on', true);
  UPDATE purchase_invoices SET
    amount_paid = LEAST(v_paid, GREATEST(COALESCE(total, 0) - v_credits, 0)),
    amount_due = v_due,
    payment_state = CASE WHEN v_due = 0 AND COALESCE(total, 0) > 0 THEN 'paid'
                         WHEN v_paid + v_credits > 0 THEN 'partial' ELSE 'not_paid' END,
    status = CASE WHEN v_due = 0 AND COALESCE(total, 0) > 0 AND v_paid > 0 THEN 'paid'
                  WHEN v_due = 0 AND COALESCE(total, 0) > 0 AND v_credits > 0 THEN 'cancelled'
                  WHEN status IN ('paid', 'cancelled') AND v_due > 0 THEN 'sent'
                  ELSE status END,
    updated_at = now()
  WHERE id = p_invoice;
  PERFORM set_config('app.settlement_in_progress', 'off', true);

  IF v_due > 0 OR v_inv.approval_status IS DISTINCT FROM 'approved' OR v_inv.transferred_entry_id IS NULL THEN
    RETURN;
  END IF;
  -- ligne fournisseur : la seule au crédit de l'écriture d'achat
  SELECT account_code INTO v_account FROM journal_lines
  WHERE journal_id = v_inv.transferred_entry_id AND credit > 0 ORDER BY line_order DESC LIMIT 1;

  SELECT array_agg(jl.id), COALESCE(sum(jl.debit), 0), COALESCE(sum(jl.credit), 0),
         count(*) FILTER (WHERE jl.lettrage_code IS NULL)
    INTO v_lines, v_d, v_c, v_open
  FROM journal_lines jl
  WHERE jl.tenant_id = v_inv.tenant_id AND jl.account_code = v_account
    AND jl.journal_id IN (
      SELECT v_inv.transferred_entry_id
      UNION ALL SELECT transferred_entry_id FROM supplier_payments
        WHERE purchase_invoice_id = p_invoice AND tenant_id = v_inv.tenant_id AND status IN ('recorded', 'reconciled')
      UNION ALL SELECT transferred_entry_id FROM purchase_credit_notes
        WHERE purchase_invoice_id = p_invoice AND tenant_id = v_inv.tenant_id AND status IN ('validated', 'applied'));

  IF v_open = COALESCE(array_length(v_lines, 1), 0) AND v_open > 1 AND v_d = v_c THEN
    v_code := next_lettrage_code_for(v_inv.tenant_id);
    UPDATE journal_lines SET lettrage_code = v_code, lettrage_date = CURRENT_DATE WHERE id = ANY(v_lines);
  END IF;
END $$;
REVOKE ALL ON FUNCTION refresh_purchase_invoice_settlement(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION purchase_invoice_after_approve()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM refresh_purchase_invoice_settlement(NEW.id);
  RETURN NULL;
END $$;

-- Nommé après create_journal_purchase_invoice : l'écriture existe quand il s'exécute
DROP TRIGGER IF EXISTS tg_purchase_invoice_after_approve ON purchase_invoices;
CREATE TRIGGER tg_purchase_invoice_after_approve
  AFTER UPDATE OF approval_status ON purchase_invoices
  FOR EACH ROW
  WHEN (NEW.approval_status = 'approved' AND OLD.approval_status IS DISTINCT FROM 'approved')
  EXECUTE FUNCTION purchase_invoice_after_approve();

-- ------------------------------------------------------------
-- 4. Avoirs fournisseurs (A04)
-- ------------------------------------------------------------
ALTER TABLE purchase_credit_notes DROP CONSTRAINT IF EXISTS purchase_credit_notes_status_check;
ALTER TABLE purchase_credit_notes ADD CONSTRAINT purchase_credit_notes_status_check
  CHECK (status IN ('draft', 'validated', 'applied'));
ALTER TABLE purchase_credit_notes ADD COLUMN IF NOT EXISTS transferred_entry_id uuid REFERENCES journal_entries(id);
ALTER TABLE purchase_credit_notes ADD COLUMN IF NOT EXISTS supplier_reference text;
ALTER TABLE purchase_credit_notes ADD COLUMN IF NOT EXISTS validated_at timestamptz;
UPDATE purchase_credit_notes SET supplier_reference = number WHERE supplier_reference IS NULL;

ALTER TABLE purchase_credit_lines ADD COLUMN IF NOT EXISTS product_id uuid REFERENCES products(id) ON DELETE SET NULL;
ALTER TABLE purchase_credit_lines ADD COLUMN IF NOT EXISTS vat_code text;
ALTER TABLE purchase_credit_lines ADD COLUMN IF NOT EXISTS vat_amount numeric NOT NULL DEFAULT 0;
UPDATE purchase_credit_lines SET vat_code = vat_code_for_rate(vat_rate), vat_amount = COALESCE(vat_total, 0) WHERE vat_code IS NULL;

CREATE OR REPLACE FUNCTION purchase_credit_line_compute()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE a record;
BEGIN
  IF EXISTS (SELECT 1 FROM purchase_credit_notes WHERE status IN ('validated', 'applied')
             AND id IN (CASE WHEN TG_OP <> 'INSERT' THEN OLD.purchase_credit_id END,
                        CASE WHEN TG_OP <> 'DELETE' THEN NEW.purchase_credit_id END)) THEN
    RAISE EXCEPTION 'Avoir fournisseur validé : ses lignes ne peuvent plus être modifiées'
      USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  a := line_amounts(NEW.quantity, NEW.unit_price, NEW.vat_rate);
  NEW.quantity := COALESCE(NEW.quantity, 0);
  NEW.unit_price := COALESCE(NEW.unit_price, 0);
  NEW.vat_rate := COALESCE(NEW.vat_rate, 0);
  NEW.total := a.total;
  NEW.vat_total := a.vat;
  NEW.vat_amount := a.vat;
  NEW.vat_code := line_vat_code(NEW.vat_code, NEW.vat_rate);
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION purchase_credit_lines_refresh_totals()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE purchase_credit_notes c SET subtotal = s.ht, vat_total = s.tva, total = s.ht + s.tva
  FROM (SELECT x.id, COALESCE(sum(l.total), 0) ht, COALESCE(sum(l.vat_amount), 0) tva
        FROM (SELECT DISTINCT unnest(ARRAY[CASE WHEN TG_OP <> 'INSERT' THEN OLD.purchase_credit_id END,
                                           CASE WHEN TG_OP <> 'DELETE' THEN NEW.purchase_credit_id END]) AS id) x
        LEFT JOIN purchase_credit_lines l ON l.purchase_credit_id = x.id
        WHERE x.id IS NOT NULL GROUP BY x.id) s
  WHERE c.id = s.id AND c.status = 'draft'
    AND (c.subtotal, c.vat_total, c.total) IS DISTINCT FROM (s.ht, s.tva, s.ht + s.tva);
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS tg_line_compute ON purchase_credit_lines;
CREATE TRIGGER tg_line_compute BEFORE INSERT OR UPDATE OR DELETE ON purchase_credit_lines
  FOR EACH ROW EXECUTE FUNCTION purchase_credit_line_compute();
DROP TRIGGER IF EXISTS tg_line_refresh_totals ON purchase_credit_lines;
CREATE TRIGGER tg_line_refresh_totals AFTER INSERT OR UPDATE OR DELETE ON purchase_credit_lines
  FOR EACH ROW EXECUTE FUNCTION purchase_credit_lines_refresh_totals();

CREATE OR REPLACE FUNCTION purchase_credit_note_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_inv purchase_invoices%ROWTYPE; v_other numeric;
  v_collectif text; v_tiers text; v_entry uuid;
  v_n int; v_ht numeric; v_tva numeric; v_ordre int := 1; r record; v_vat_acc text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.status := COALESCE(NEW.status, 'draft');
    IF NEW.status <> 'draft' THEN
      RAISE EXCEPTION 'Un avoir fournisseur est saisi en brouillon puis validé' USING ERRCODE = 'check_violation';
    END IF;
    NEW.supplier_reference := COALESCE(NEW.supplier_reference, NEW.number);
    NEW.number := draft_document_number('AVF', NEW.id);
    NEW.transferred_entry_id := NULL;
    RETURN NEW;
  END IF;

  IF OLD.status IN ('validated', 'applied') THEN
    IF NEW.status = 'draft'
       OR (NEW.number, NEW.date, NEW.supplier_id, NEW.purchase_invoice_id, NEW.subtotal, NEW.vat_total, NEW.total, NEW.tenant_id)
          IS DISTINCT FROM
          (OLD.number, OLD.date, OLD.supplier_id, OLD.purchase_invoice_id, OLD.subtotal, OLD.vat_total, OLD.total, OLD.tenant_id) THEN
      RAISE EXCEPTION 'Avoir fournisseur % validé : il n''est plus modifiable', OLD.number USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;

  NEW.number := OLD.number;
  SELECT count(*), COALESCE(sum(total), 0), COALESCE(sum(vat_amount), 0) INTO v_n, v_ht, v_tva
  FROM purchase_credit_lines WHERE purchase_credit_id = NEW.id;
  IF v_n > 0 THEN
    NEW.subtotal := v_ht; NEW.vat_total := v_tva; NEW.total := v_ht + v_tva;
  END IF;
  IF NEW.status = 'draft' THEN RETURN NEW; END IF;

  IF NEW.purchase_invoice_id IS NOT NULL THEN
    SELECT * INTO v_inv FROM purchase_invoices WHERE id = NEW.purchase_invoice_id AND tenant_id = NEW.tenant_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Facture fournisseur d''origine introuvable' USING ERRCODE = 'foreign_key_violation';
    END IF;
    IF v_inv.approval_status IS DISTINCT FROM 'approved' THEN
      RAISE EXCEPTION 'La facture fournisseur d''origine % n''est pas approuvée', v_inv.number USING ERRCODE = 'check_violation';
    END IF;
    NEW.supplier_id := COALESCE(NEW.supplier_id, v_inv.supplier_id);
    IF NEW.supplier_id IS DISTINCT FROM v_inv.supplier_id THEN
      RAISE EXCEPTION 'L''avoir et la facture % concernent deux fournisseurs différents', v_inv.number USING ERRCODE = 'check_violation';
    END IF;
    SELECT COALESCE(sum(total), 0) INTO v_other FROM purchase_credit_notes
    WHERE purchase_invoice_id = NEW.purchase_invoice_id AND id <> NEW.id AND status IN ('validated', 'applied');
    IF NEW.total > COALESCE(v_inv.total, 0) - v_other THEN
      RAISE EXCEPTION 'Avoir de % supérieur au montant restant à créditer sur la facture % (%)',
        NEW.total, v_inv.number, COALESCE(v_inv.total, 0) - v_other USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  IF NEW.supplier_id IS NULL THEN
    RAISE EXCEPTION 'Un avoir fournisseur doit être rattaché à une facture ou à un fournisseur' USING ERRCODE = 'check_violation';
  END IF;
  IF COALESCE(NEW.total, 0) <= 0 OR NEW.total <> COALESCE(NEW.subtotal, 0) + COALESCE(NEW.vat_total, 0) THEN
    RAISE EXCEPTION 'Avoir fournisseur incohérent : HT % + TVA % ≠ TTC %', NEW.subtotal, NEW.vat_total, NEW.total
      USING ERRCODE = 'check_violation';
  END IF;

  NEW.number := next_legal_document_number(NEW.tenant_id, 'AVF', NEW.date);
  NEW.validated_at := now();

  SELECT COALESCE(account_collectif, '401000'), account_tiers INTO v_collectif, v_tiers
  FROM suppliers WHERE id = NEW.supplier_id AND tenant_id = NEW.tenant_id;
  v_collectif := COALESCE(v_collectif, '401000');

  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, piece_number)
  VALUES (NEW.tenant_id, 'JE-' || NEW.number, NEW.date, 'AC', 'draft', 'Avoir fournisseur ' || NEW.number, NEW.number)
  RETURNING id INTO v_entry;
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_tiers, third_party_id,
                             debit, credit, description, line_order)
  VALUES (NEW.tenant_id, v_entry, v_collectif, v_collectif, v_tiers, NEW.supplier_id, NEW.total, 0, 'Fournisseur ' || NEW.number, 0);
  IF v_n > 0 THEN
    FOR r IN
      SELECT COALESCE(p.purchase_account_code, pc.purchase_account_code, '609000') AS compte, sum(l.total) AS montant
      FROM purchase_credit_lines l
      LEFT JOIN products p ON p.id = l.product_id AND p.tenant_id = NEW.tenant_id
      LEFT JOIN product_categories pc ON pc.id = p.category_id AND pc.tenant_id = NEW.tenant_id
      WHERE l.purchase_credit_id = NEW.id GROUP BY 1
    LOOP
      INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
      VALUES (NEW.tenant_id, v_entry, r.compte, r.compte, 0, r.montant, 'Avoir obtenu ' || NEW.number, v_ordre);
      v_ordre := v_ordre + 1;
    END LOOP;
    FOR r IN SELECT vat_code, sum(vat_amount) AS tva FROM purchase_credit_lines WHERE purchase_credit_id = NEW.id GROUP BY 1 LOOP
      SELECT account_code INTO v_vat_acc FROM vat_account_mapping
      WHERE tenant_id IN (NEW.tenant_id, '00000000-0000-0000-0000-000000000000')
        AND vat_code = r.vat_code AND direction = 'deductible'
      ORDER BY tenant_id DESC LIMIT 1;
      v_vat_acc := COALESCE(v_vat_acc, '445660');
      INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, vat_code, vat_amount,
                                 debit, credit, description, line_order)
      VALUES (NEW.tenant_id, v_entry, v_vat_acc, v_vat_acc, r.vat_code, r.tva, 0, r.tva,
              'TVA déductible ' || r.vat_code || ' — ' || NEW.number, v_ordre);
      v_ordre := v_ordre + 1;
    END LOOP;
  ELSE
    -- Avoir global sans ligne (remise obtenue)
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
    VALUES (NEW.tenant_id, v_entry, '609000', '609000', 0, NEW.subtotal, 'Avoir obtenu ' || NEW.number, 1),
           (NEW.tenant_id, v_entry, '445660', '445660', 0, NEW.vat_total, 'TVA déductible — ' || NEW.number, 2);
  END IF;
  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry;
  NEW.transferred_entry_id := v_entry;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS tg_purchase_credit_note_guard ON purchase_credit_notes;
CREATE TRIGGER tg_purchase_credit_note_guard
  BEFORE INSERT OR UPDATE ON purchase_credit_notes
  FOR EACH ROW EXECUTE FUNCTION purchase_credit_note_guard();

CREATE OR REPLACE FUNCTION purchase_credit_note_after_validate()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.purchase_invoice_id IS NOT NULL THEN PERFORM refresh_purchase_invoice_settlement(NEW.purchase_invoice_id); END IF;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS tg_purchase_credit_note_after_validate ON purchase_credit_notes;
CREATE TRIGGER tg_purchase_credit_note_after_validate
  AFTER UPDATE OF status ON purchase_credit_notes
  FOR EACH ROW
  WHEN (OLD.status = 'draft' AND NEW.status IN ('validated', 'applied'))
  EXECUTE FUNCTION purchase_credit_note_after_validate();

-- ------------------------------------------------------------
-- 5. Décaissements : trésorerie, avance fournisseur, lettrage (A05, A06)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_journal_on_supplier_payment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_entry_id uuid; v_number text;
  v_collectif text; v_tiers text; v_third_party uuid;
  v_tr record; v_remaining numeric; v_excess numeric := 0;
BEGIN
  IF NEW.supplier_id IS NOT NULL THEN
    SELECT account_collectif, account_tiers, id INTO v_collectif, v_tiers, v_third_party
    FROM suppliers WHERE id = NEW.supplier_id AND tenant_id = NEW.tenant_id;
  ELSIF NEW.purchase_invoice_id IS NOT NULL THEN
    SELECT s.account_collectif, s.account_tiers, s.id INTO v_collectif, v_tiers, v_third_party
    FROM suppliers s JOIN purchase_invoices pi ON pi.supplier_id = s.id AND pi.tenant_id = s.tenant_id
    WHERE pi.id = NEW.purchase_invoice_id AND pi.tenant_id = NEW.tenant_id;
  END IF;
  v_collectif := COALESCE(v_collectif, '401000');

  -- Trop-payé : avance fournisseur (décision n° 1 appliquée aux achats)
  IF NEW.purchase_invoice_id IS NOT NULL THEN
    SELECT COALESCE(i.total, 0)
           - COALESCE((SELECT sum(amount) FROM supplier_payments p
                       WHERE p.purchase_invoice_id = i.id AND p.id <> NEW.id AND p.status IN ('recorded', 'reconciled')), 0)
           - COALESCE((SELECT sum(total) FROM purchase_credit_notes c
                       WHERE c.purchase_invoice_id = i.id AND c.status IN ('validated', 'applied')), 0)
      INTO v_remaining
    FROM purchase_invoices i WHERE i.id = NEW.purchase_invoice_id AND i.tenant_id = NEW.tenant_id;
    v_excess := GREATEST(NEW.amount - GREATEST(COALESCE(v_remaining, NEW.amount), 0), 0);
  END IF;

  SELECT * INTO v_tr FROM treasury_for_payment(NEW.tenant_id, NEW.bank_account_id, NEW.method);

  v_number := 'JE-SP-' || NEW.number;
  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, piece_number)
  VALUES (NEW.tenant_id, v_number, NEW.payment_date, v_tr.journal_code, 'draft', 'Décaissement ' || NEW.number, v_number)
  RETURNING id INTO v_entry_id;

  IF NEW.amount - v_excess > 0 THEN
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_tiers, third_party_id,
                               debit, credit, description, line_order)
    VALUES (NEW.tenant_id, v_entry_id, v_collectif, v_collectif, v_tiers, v_third_party,
            NEW.amount - v_excess, 0, 'Fournisseur ' || NEW.number, 0);
  END IF;
  IF v_excess > 0 THEN
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_tiers, third_party_id,
                               debit, credit, description, line_order)
    VALUES (NEW.tenant_id, v_entry_id, '409100', '409100', v_tiers, v_third_party,
            v_excess, 0, 'Avance fournisseur (trop-payé) ' || NEW.number, 1);
  END IF;
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_tiers, third_party_id,
                             debit, credit, description, line_order)
  VALUES (NEW.tenant_id, v_entry_id, v_tr.account_code, v_tr.account_code, NULL, NULL,
          0, NEW.amount, 'Trésorerie ' || NEW.number, 2);

  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;
  UPDATE supplier_payments SET transferred_entry_id = v_entry_id WHERE id = NEW.id AND tenant_id = NEW.tenant_id;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_invoice_on_supplier_payment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_invoice_id uuid;
  v_old_counted numeric := 0;
  v_new_counted numeric := 0;
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.status IN ('recorded', 'reconciled') THEN
    v_old_counted := COALESCE(OLD.amount, 0);
  END IF;
  IF NEW.status IN ('recorded', 'reconciled') THEN
    v_new_counted := COALESCE(NEW.amount, 0);
  END IF;

  -- LOT2-04 : purchase_invoice_id (colonne dédiée), référence en repli
  v_invoice_id := NEW.purchase_invoice_id;
  IF v_invoice_id IS NULL AND NEW.reference IS NOT NULL THEN
    SELECT id INTO v_invoice_id FROM purchase_invoices
    WHERE tenant_id = NEW.tenant_id AND (number = NEW.reference OR supplier_reference = NEW.reference) LIMIT 1;
  END IF;
  IF v_invoice_id IS NOT NULL THEN
    PERFORM refresh_purchase_invoice_settlement(v_invoice_id);
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.purchase_invoice_id IS NOT NULL AND OLD.purchase_invoice_id IS DISTINCT FROM NEW.purchase_invoice_id THEN
    PERFORM refresh_purchase_invoice_settlement(OLD.purchase_invoice_id);
  END IF;

  -- Solde fournisseur : n'appliquer que la variation réelle du montant compté
  IF TG_OP = 'UPDATE' AND OLD.supplier_id IS DISTINCT FROM NEW.supplier_id THEN
    IF OLD.supplier_id IS NOT NULL AND v_old_counted <> 0 THEN
      UPDATE suppliers SET balance = COALESCE(balance, 0) + v_old_counted, updated_at = NOW()
      WHERE id = OLD.supplier_id AND tenant_id = OLD.tenant_id;
    END IF;
    v_old_counted := 0;
  END IF;
  IF NEW.supplier_id IS NOT NULL AND v_new_counted - v_old_counted <> 0 THEN
    UPDATE suppliers
      SET balance = GREATEST(COALESCE(balance, 0) - (v_new_counted - v_old_counted), 0), updated_at = NOW()
    WHERE id = NEW.supplier_id AND tenant_id = NEW.tenant_id;
  END IF;

  RETURN NEW;
END;
$$;

-- ------------------------------------------------------------
-- 6. Pièces d'achat validées : pas de suppression
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION purchase_document_delete_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF (TG_TABLE_NAME = 'purchase_invoices' AND to_jsonb(OLD)->>'approval_status' = 'approved')
     OR (TG_TABLE_NAME = 'purchase_credit_notes' AND to_jsonb(OLD)->>'status' IN ('validated', 'applied')) THEN
    RAISE EXCEPTION 'Pièce d''achat % validée : suppression interdite (saisissez un avoir)', OLD.number
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN OLD;
END $$;

DROP TRIGGER IF EXISTS tg_purchase_invoice_delete_guard ON purchase_invoices;
CREATE TRIGGER tg_purchase_invoice_delete_guard BEFORE DELETE ON purchase_invoices
  FOR EACH ROW EXECUTE FUNCTION purchase_document_delete_guard();
DROP TRIGGER IF EXISTS tg_purchase_credit_note_delete_guard ON purchase_credit_notes;
CREATE TRIGGER tg_purchase_credit_note_delete_guard BEFORE DELETE ON purchase_credit_notes
  FOR EACH ROW EXECUTE FUNCTION purchase_document_delete_guard();
