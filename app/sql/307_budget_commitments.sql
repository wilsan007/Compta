-- ============================================================
-- 307_budget_commitments.sql — W7 (M-04) : les engagements se créent et se soldent
--
-- BUD-03 🟠 : `budget_commitments` prévoyait `status = 'consumed'` et
-- `source_type IN ('purchase_order','purchase_invoice')`, mais **rien** ne
-- créait d'engagement depuis une commande et **rien** ne le soldait à la
-- facturation. Mesuré avant ce fichier : confirmer une commande de 1 000 crée
-- **0** engagement ; annuler la commande n'annule rien ; l'approbation de la
-- facture liée ne consomme rien. Un engagement resté `active` est donc déduit
-- une première fois du disponible comme engagement, puis une seconde comme
-- réalisé — le disponible est faux.
--
-- CE QUI EST POSÉ.
--   • `uniq_budget_commitment_source` : un engagement par (société, source,
--     compte) — confirmer deux fois ne duplique pas.
--   • `sync_commitments_on_purchase_order()` : confirmer une commande **crée**
--     un engagement par compte de charge (compte d'achat de l'article, sinon de
--     sa catégorie, sinon `607000`, et à défaut le total d'en-tête) ; l'annuler
--     l'annule.
--   • `consume_commitment_on_purchase_invoice()` : approuver une facture **liée
--     à la commande** consomme l'engagement — le réalisé prend le relais.
-- ============================================================

CREATE UNIQUE INDEX IF NOT EXISTS uniq_budget_commitment_source
  ON public.budget_commitments (tenant_id, source_type, source_id, account_code)
  WHERE source_id IS NOT NULL;

-- ------------------------------------------------------------
-- 1. La commande d'achat : crée son engagement, l'annule si elle est annulée
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_commitments_on_purchase_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_fy uuid;
  v_ligne RECORD;
  v_nb int := 0;
BEGIN
  -- Annulation : l'engagement encore actif part avec elle.
  IF NEW.status = 'cancelled' AND OLD.status IS DISTINCT FROM 'cancelled' THEN
    UPDATE public.budget_commitments
    SET status = 'cancelled', updated_at = now()
    WHERE tenant_id = NEW.tenant_id AND source_type = 'purchase_order'
      AND source_id = NEW.id AND status = 'active';
    RETURN NEW;
  END IF;

  IF NOT (NEW.status = 'confirmed' AND OLD.status IS DISTINCT FROM 'confirmed') THEN
    RETURN NEW;
  END IF;

  -- L'exercice qui contient la date de la commande
  SELECT id INTO v_fy FROM public.fiscal_years
  WHERE tenant_id = NEW.tenant_id
    AND COALESCE(NEW.order_date, CURRENT_DATE) BETWEEN start_date AND end_date
  LIMIT 1;

  -- Un engagement par compte de charge (compte de l'article, sinon de sa
  -- catégorie, sinon 607000) — c'est le compte que le budget suit.
  FOR v_ligne IN
    SELECT COALESCE(p.purchase_account_code, pc.purchase_account_code, '607000') AS compte,
           COALESCE(SUM(pol.line_total), 0) AS montant
    FROM public.purchase_order_lines pol
    LEFT JOIN public.products p ON p.id = pol.product_id AND p.tenant_id = NEW.tenant_id
    LEFT JOIN public.product_categories pc ON pc.id = p.category_id AND pc.tenant_id = NEW.tenant_id
    WHERE pol.purchase_order_id = NEW.id AND pol.tenant_id = NEW.tenant_id
    GROUP BY 1
  LOOP
    v_nb := v_nb + 1;
    INSERT INTO public.budget_commitments (
      tenant_id, description, account_code, fiscal_year_id, amount, commitment_date,
      source_type, source_id, status, supplier_id
    ) VALUES (
      NEW.tenant_id, 'Commande ' || NEW.number, v_ligne.compte, v_fy, v_ligne.montant,
      COALESCE(NEW.order_date, CURRENT_DATE), 'purchase_order', NEW.id, 'active', NEW.supplier_id
    )
    ON CONFLICT (tenant_id, source_type, source_id, account_code) WHERE source_id IS NOT NULL
    DO NOTHING;
  END LOOP;

  -- Commande sans ligne : le total d'en-tête sur le compte de charge par défaut
  IF v_nb = 0 AND COALESCE(NEW.subtotal, 0) > 0 THEN
    INSERT INTO public.budget_commitments (
      tenant_id, description, account_code, fiscal_year_id, amount, commitment_date,
      source_type, source_id, status, supplier_id
    ) VALUES (
      NEW.tenant_id, 'Commande ' || NEW.number, '607000', v_fy, NEW.subtotal,
      COALESCE(NEW.order_date, CURRENT_DATE), 'purchase_order', NEW.id, 'active', NEW.supplier_id
    )
    ON CONFLICT (tenant_id, source_type, source_id, account_code) WHERE source_id IS NOT NULL
    DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.sync_commitments_on_purchase_order() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS sync_commitments_on_purchase_order ON public.purchase_orders;
CREATE TRIGGER sync_commitments_on_purchase_order
  AFTER UPDATE OF status
  ON public.purchase_orders
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_commitments_on_purchase_order();

-- ------------------------------------------------------------
-- 2. La facture d'achat approuvée consomme l'engagement de sa commande
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.consume_commitment_on_purchase_invoice()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF NOT (NEW.approval_status = 'approved' AND OLD.approval_status IS DISTINCT FROM 'approved') THEN
    RETURN NEW;
  END IF;
  IF NEW.purchase_order_id IS NULL THEN RETURN NEW; END IF;

  UPDATE public.budget_commitments
  SET status = 'consumed', updated_at = now()
  WHERE tenant_id = NEW.tenant_id AND source_type = 'purchase_order'
    AND source_id = NEW.purchase_order_id AND status = 'active';

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.consume_commitment_on_purchase_invoice() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS consume_commitment_on_purchase_invoice ON public.purchase_invoices;
CREATE TRIGGER consume_commitment_on_purchase_invoice
  AFTER UPDATE OF approval_status
  ON public.purchase_invoices
  FOR EACH ROW
  EXECUTE FUNCTION public.consume_commitment_on_purchase_invoice();

