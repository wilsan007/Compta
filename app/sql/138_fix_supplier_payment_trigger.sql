-- ============================================================
-- 138_fix_supplier_payment_trigger.sql
-- LOT2-04 : Le trigger update_invoice_on_supplier_payment utilisait
-- NEW.reference pour retrouver la facture d'achat, ce qui est fragile.
-- supplier_payments a une colonne dédiée purchase_invoice_id.
-- ============================================================

CREATE OR REPLACE FUNCTION update_invoice_on_supplier_payment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_invoice RECORD;
  v_total_paid numeric;
  v_invoice_total numeric;
BEGIN
  IF NEW.status NOT IN ('recorded', 'validated') THEN
    RETURN NEW;
  END IF;

  -- LOT2-04 : utiliser purchase_invoice_id (colonne dédiée) au lieu de reference
  IF NEW.purchase_invoice_id IS NULL THEN
    -- Fallback : si pas de purchase_invoice_id, essayer via reference
    IF NEW.reference IS NULL THEN
      RETURN NEW;
    END IF;
    SELECT * INTO v_invoice
    FROM purchase_invoices
    WHERE number = NEW.reference
      AND tenant_id = NEW.tenant_id
    LIMIT 1;
  ELSE
    SELECT * INTO v_invoice
    FROM purchase_invoices
    WHERE id = NEW.purchase_invoice_id
      AND tenant_id = NEW.tenant_id
    LIMIT 1;
  END IF;

  IF NOT FOUND THEN
    -- Pas de facture trouvée, juste mettre à jour le solde fournisseur
    IF NEW.supplier_id IS NOT NULL THEN
      UPDATE suppliers
        SET balance = COALESCE(balance, 0) + NEW.amount,
            updated_at = NOW()
      WHERE id = NEW.supplier_id AND tenant_id = NEW.tenant_id;
    END IF;
    RETURN NEW;
  END IF;

  -- Calculer le total payé pour cette facture
  SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
  FROM supplier_payments
  WHERE purchase_invoice_id = v_invoice.id
    AND tenant_id = NEW.tenant_id
    AND status IN ('recorded', 'validated');

  v_invoice_total := COALESCE(v_invoice.total, 0);

  -- Mettre à jour la facture d'achat
  UPDATE purchase_invoices
    SET amount_paid = v_total_paid,
        amount_due = GREATEST(v_invoice_total - v_total_paid, 0),
        payment_state = CASE
          WHEN v_total_paid >= v_invoice_total AND v_invoice_total > 0 THEN 'paid'
          WHEN v_total_paid > 0 THEN 'partial'
          ELSE 'not_paid'
        END,
        status = CASE
          WHEN v_total_paid >= v_invoice_total AND v_invoice_total > 0 THEN 'paid'
          ELSE status
        END,
        updated_at = NOW()
  WHERE id = v_invoice.id AND tenant_id = NEW.tenant_id;

  -- Mettre à jour le solde fournisseur
  IF NEW.supplier_id IS NOT NULL THEN
    UPDATE suppliers
      SET balance = GREATEST(COALESCE(balance, 0) - NEW.amount, 0),
          updated_at = NOW()
    WHERE id = NEW.supplier_id AND tenant_id = NEW.tenant_id;
  END IF;

  RETURN NEW;
END;
$$;
