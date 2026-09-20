-- ============================================================
-- 169_fix_payment_reconciled_status.sql
--
-- Corrige trois comparaisons impossibles trouvées par le garde-fou B3
-- élargi (sql/ci/check_trigger_reachability.sql) le 18/09/2026.
--
-- 1) customer_payments.status et supplier_payments.status n'acceptent que
--    'recorded' | 'reconciled' | 'cancelled' (contraintes CHECK). Or les deux
--    triggers de mise à jour des factures comptaient les paiements
--    `status IN ('recorded', 'validated')`. 'validated' n'existe pas et
--    'reconciled' manquait : dès que le rapprochement bancaire passe un
--    paiement à 'reconciled' (auto_match_bank_transactions,
--    sql/152_fix_broken_rpc_functions.sql:1435), le paiement cesse d'être
--    compté.
--
--    Reproduit sur base réelle avant correction, côté client :
--      encaissement 1000 -> amount_paid=1000, payment_state='paid', solde=0
--      rapprochement   -> amount_paid=0,    payment_state='not_paid', solde=1000
--    Autrement dit : rapprocher un encaissement « dé-payait » la facture et
--    regonflait le solde du client.
--
-- 2) update_invoice_on_supplier_payment sortait tôt (`NOT IN (...)`) au lieu de
--    raisonner en variation. En corrigeant seulement la liste de statuts, le
--    trigger se serait mis à décrémenter une seconde fois le solde fournisseur
--    lors du rapprochement. La fonction est donc alignée sur son homologue
--    client : on n'applique que la variation réelle du montant compté.
--
--    Au passage, les deux branches de la fonction appliquaient des signes
--    opposés au solde fournisseur (+ NEW.amount si aucune facture liée,
--    - NEW.amount sinon). Aucune autre fonction n'écrit suppliers.balance :
--    la convention retenue est celle des clients — un règlement diminue le
--    solde dû.
--
-- 3) purchase_invoices.approval_status n'accepte que
--    'pending' | 'approved' | 'rejected'. Le statut fantôme 'submitted' est
--    retiré du trigger three_way_match_on_invoice, de sa clause WHEN et de
--    la RPC run_three_way_match.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Encaissements clients
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_invoice_on_customer_payment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_invoice RECORD;
  v_total_paid numeric;
  v_invoice_total numeric;
  v_old_counted numeric := 0;
  v_new_counted numeric := 0;
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.status IN ('recorded', 'reconciled') THEN
    v_old_counted := COALESCE(OLD.amount, 0);
  END IF;
  IF NEW.status IN ('recorded', 'reconciled') THEN
    v_new_counted := COALESCE(NEW.amount, 0);
  END IF;

  -- Facture liée : recalcul complet depuis les paiements enregistrés
  IF NEW.invoice_id IS NOT NULL THEN
    SELECT * INTO v_invoice FROM invoices WHERE id = NEW.invoice_id AND tenant_id = NEW.tenant_id;
    IF FOUND THEN
      SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
      FROM customer_payments
      WHERE invoice_id = NEW.invoice_id
        AND tenant_id = NEW.tenant_id
        AND status IN ('recorded', 'reconciled');

      v_invoice_total := COALESCE(v_invoice.total, 0);

      UPDATE invoices
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
      WHERE id = NEW.invoice_id AND tenant_id = NEW.tenant_id
        AND (amount_paid IS DISTINCT FROM v_total_paid
             OR amount_due IS DISTINCT FROM GREATEST(v_invoice_total - v_total_paid, 0));
    END IF;
  END IF;

  -- Solde client : n'appliquer que la variation réelle du montant compté
  IF TG_OP = 'UPDATE' AND OLD.customer_id IS DISTINCT FROM NEW.customer_id THEN
    IF OLD.customer_id IS NOT NULL AND v_old_counted <> 0 THEN
      UPDATE customers
        SET balance = COALESCE(balance, 0) + v_old_counted,
            credit_used = COALESCE(credit_used, 0) + v_old_counted,
            updated_at = NOW()
      WHERE id = OLD.customer_id AND tenant_id = OLD.tenant_id;
    END IF;
    v_old_counted := 0;
  END IF;

  IF NEW.customer_id IS NOT NULL AND v_new_counted - v_old_counted <> 0 THEN
    UPDATE customers
      SET balance = GREATEST(COALESCE(balance, 0) - (v_new_counted - v_old_counted), 0),
          credit_used = GREATEST(COALESCE(credit_used, 0) - (v_new_counted - v_old_counted), 0),
          updated_at = NOW()
    WHERE id = NEW.customer_id AND tenant_id = NEW.tenant_id;
  END IF;

  RETURN NEW;
END;
$function$;

-- ------------------------------------------------------------
-- 2. Règlements fournisseurs — même logique de variation
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_invoice_on_supplier_payment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_invoice RECORD;
  v_total_paid numeric;
  v_invoice_total numeric;
  v_old_counted numeric := 0;
  v_new_counted numeric := 0;
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.status IN ('recorded', 'reconciled') THEN
    v_old_counted := COALESCE(OLD.amount, 0);
  END IF;
  IF NEW.status IN ('recorded', 'reconciled') THEN
    v_new_counted := COALESCE(NEW.amount, 0);
  END IF;

  -- LOT2-04 : purchase_invoice_id (colonne dédiée), reference en repli
  IF NEW.purchase_invoice_id IS NULL THEN
    IF NEW.reference IS NOT NULL THEN
      SELECT * INTO v_invoice
      FROM purchase_invoices
      WHERE number = NEW.reference
        AND tenant_id = NEW.tenant_id
      LIMIT 1;
    END IF;
  ELSE
    SELECT * INTO v_invoice
    FROM purchase_invoices
    WHERE id = NEW.purchase_invoice_id
      AND tenant_id = NEW.tenant_id
    LIMIT 1;
  END IF;

  IF v_invoice.id IS NOT NULL THEN
    SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
    FROM supplier_payments
    WHERE purchase_invoice_id = v_invoice.id
      AND tenant_id = NEW.tenant_id
      AND status IN ('recorded', 'reconciled');

    v_invoice_total := COALESCE(v_invoice.total, 0);

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
    WHERE id = v_invoice.id AND tenant_id = NEW.tenant_id
      AND (amount_paid IS DISTINCT FROM v_total_paid
           OR amount_due IS DISTINCT FROM GREATEST(v_invoice_total - v_total_paid, 0));
  END IF;

  -- Solde fournisseur : n'appliquer que la variation réelle du montant compté
  IF TG_OP = 'UPDATE' AND OLD.supplier_id IS DISTINCT FROM NEW.supplier_id THEN
    IF OLD.supplier_id IS NOT NULL AND v_old_counted <> 0 THEN
      UPDATE suppliers
        SET balance = COALESCE(balance, 0) + v_old_counted,
            updated_at = NOW()
      WHERE id = OLD.supplier_id AND tenant_id = OLD.tenant_id;
    END IF;
    v_old_counted := 0;
  END IF;

  IF NEW.supplier_id IS NOT NULL AND v_new_counted - v_old_counted <> 0 THEN
    UPDATE suppliers
      SET balance = GREATEST(COALESCE(balance, 0) - (v_new_counted - v_old_counted), 0),
          updated_at = NOW()
    WHERE id = NEW.supplier_id AND tenant_id = NEW.tenant_id;
  END IF;

  RETURN NEW;
END;
$function$;

-- ------------------------------------------------------------
-- 3. Statut fantôme 'submitted' sur purchase_invoices.approval_status
-- ------------------------------------------------------------
DO $$
DECLARE
  v_src text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO v_src
  FROM pg_proc WHERE proname = 'perform_three_way_match'
    AND pronamespace = 'public'::regnamespace;

  IF v_src IS NULL THEN
    RAISE NOTICE 'perform_three_way_match absente — rien à corriger';
  ELSIF position('''submitted''' in v_src) = 0 THEN
    RAISE NOTICE 'perform_three_way_match : ''submitted'' déjà retiré';
  ELSE
    EXECUTE replace(v_src, '''pending'', ''submitted''', '''pending''');
    RAISE NOTICE 'perform_three_way_match : statut fantôme ''submitted'' retiré';
  END IF;
END;
$$;

DROP TRIGGER IF EXISTS three_way_match_on_invoice ON public.purchase_invoices;
CREATE TRIGGER three_way_match_on_invoice
  BEFORE UPDATE OF approval_status ON public.purchase_invoices
  FOR EACH ROW
  WHEN (NEW.approval_status = 'pending')
  EXECUTE FUNCTION perform_three_way_match();

DO $$
DECLARE
  v_src text;
  r RECORD;
BEGIN
  FOR r IN
    SELECT oid FROM pg_proc
    WHERE proname = 'run_three_way_match'
      AND pronamespace = 'public'::regnamespace
  LOOP
    v_src := pg_get_functiondef(r.oid);
    IF position('''submitted''' in v_src) > 0 THEN
      EXECUTE replace(v_src, '''pending'', ''submitted''', '''pending''');
      RAISE NOTICE 'run_three_way_match : statut fantôme ''submitted'' retiré';
    END IF;
  END LOOP;
END;
$$;
