-- 354 — supplier_payment_requires_approved_invoice
-- Numéro pris le 2026-10-05T05:32:26.389Z par migration-numero.mjs (ligne « partie 2 (défauts métier) », branche claude/pensive-jang-019c66).
--
-- Partie 2 (défauts métier) — un règlement fournisseur ne s'impute qu'à une
-- facture d'achat APPROUVÉE.
--
-- Mesuré le 05/10/2026 sur le chemin de l'écran (base neuve, 328 migrations) :
-- `createSupplierPayment({ purchase_invoice_id: <facture BROUILLON-ACH-…, pending> })`
-- était accepté. La facture passait à `paid`, reste dû 0, sans écriture d'achat
-- (`transferred_entry_id` nul) ; le règlement, lui, était comptabilisé
-- (D 401000 / C 512000). Le 401 était débité sans qu'aucune dette n'ait été
-- constatée, et l'approbation — donc la séparation des tâches de la 271 (M9) —
-- était contournée par le paiement. Le côté vente est gardé depuis longtemps
-- (23514 « validez-la avant de l'envoyer ») ; l'avoir fournisseur aussi (192 :
-- « la facture fournisseur d'origine n'est pas approuvée »). Il manquait le règlement.
--
-- Ce que fait la 354 :
--   1. `tg_supplier_payment_invoice_guard` (BEFORE INSERT OR UPDATE) refuse, en
--      23514, un règlement COMPTÉ (`recorded`, `reconciled`) imputé à une facture
--      qui n'est pas `approved` — à l'insertion, et à l'imputation après coup
--      (changement de facture, de montant, ou retour d'un règlement annulé).
--   2. `purchase_invoices_settled_unapproved()` LISTE les factures déjà dans cet
--      état. Rien n'est supprimé ni réécrit : le remède est une décision de
--      gestion — APPROUVER la facture (la base passe alors l'écriture d'achat et
--      lettre le 401 avec le règlement : suite 354, T07) ou ANNULER le règlement
--      (T08). La migration publie le décompte à l'application.
--
-- Ce qu'elle ne fait PAS (décision de l'utilisateur, 05/10/2026) : le règlement
-- SANS facture (fournisseur seul — acompte, règlement à imputer) reste possible
-- et reste comptabilisé D 401 / C 512 comme avant (T05). Le porter en avance
-- fournisseur (4091) et l'imputer ensuite sur la facture approuvée est un
-- chantier distinct, inscrit au suivi.
--
-- Un règlement hérité garde ses mouvements ordinaires : la garde ne regarde un
-- UPDATE que s'il crée ou agrandit l'imputation (le rapprochement bancaire
-- `recorded` → `reconciled` et l'annulation passent).

CREATE OR REPLACE FUNCTION public.supplier_payment_invoice_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_number text; v_approval text;
BEGIN
  IF NEW.purchase_invoice_id IS NULL OR NEW.status NOT IN ('recorded', 'reconciled') THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE'
     AND OLD.status IN ('recorded', 'reconciled')
     AND NEW.purchase_invoice_id IS NOT DISTINCT FROM OLD.purchase_invoice_id
     AND COALESCE(NEW.amount, 0) <= COALESCE(OLD.amount, 0) THEN
    RETURN NEW;
  END IF;

  SELECT number, approval_status INTO v_number, v_approval
  FROM purchase_invoices
  WHERE id = NEW.purchase_invoice_id AND tenant_id = NEW.tenant_id;
  -- facture introuvable dans la société : la clé composite (237) refuse, avec son message
  IF NOT FOUND THEN RETURN NEW; END IF;

  IF v_approval IS DISTINCT FROM 'approved' THEN
    RAISE EXCEPTION 'La facture fournisseur % n''est pas approuvée : approuvez-la avant de la régler', v_number
      USING ERRCODE = 'check_violation',
            HINT = 'Un acompte versé avant la facture s''enregistre comme un règlement sans facture.';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.supplier_payment_invoice_guard() FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.supplier_payment_invoice_guard() IS
  '354 : un règlement fournisseur compté ne s''impute qu''à une facture d''achat approuvée (23514 sinon).';

-- Nommé après set_tenant_id_supplier_payments : la société est posée quand il s'exécute
DROP TRIGGER IF EXISTS tg_supplier_payment_invoice_guard ON public.supplier_payments;
CREATE TRIGGER tg_supplier_payment_invoice_guard
  BEFORE INSERT OR UPDATE ON public.supplier_payments
  FOR EACH ROW EXECUTE FUNCTION public.supplier_payment_invoice_guard();

-- Les factures déjà réglées sans approbation : listées, jamais réparées d'office.
CREATE OR REPLACE FUNCTION public.purchase_invoices_settled_unapproved()
RETURNS TABLE (
  purchase_invoice_id uuid, number text, supplier_name text, invoice_date date,
  approval_status text, status text, total numeric,
  amount_settled numeric, payments integer, last_payment_date date
)
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT i.id, i.number, i.supplier_name, i.date, i.approval_status, i.status, i.total,
         sum(p.amount), count(*)::integer, max(p.payment_date)
  FROM purchase_invoices i
  JOIN supplier_payments p ON p.purchase_invoice_id = i.id AND p.tenant_id = i.tenant_id
  WHERE i.tenant_id = current_tenant_id()
    AND i.approval_status IS DISTINCT FROM 'approved'
    AND p.status IN ('recorded', 'reconciled')
  GROUP BY i.id
  ORDER BY max(p.payment_date) DESC, i.number
$$;
REVOKE ALL ON FUNCTION public.purchase_invoices_settled_unapproved() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.purchase_invoices_settled_unapproved() TO authenticated, service_role;

COMMENT ON FUNCTION public.purchase_invoices_settled_unapproved() IS
  '354 : factures d''achat de la société courante portant un règlement compté sans être approuvées (état né avant la garde). À approuver, ou règlement à annuler.';

-- Le décompte, publié à l'application (toutes sociétés) — rien n'est modifié.
DO $$
DECLARE r record; n int := 0;
BEGIN
  FOR r IN
    SELECT i.tenant_id, i.number, i.approval_status, sum(p.amount) AS regle, count(*) AS n
    FROM purchase_invoices i
    JOIN supplier_payments p ON p.purchase_invoice_id = i.id AND p.tenant_id = i.tenant_id
    WHERE i.approval_status IS DISTINCT FROM 'approved' AND p.status IN ('recorded', 'reconciled')
    GROUP BY i.id ORDER BY i.tenant_id, i.number
  LOOP
    n := n + 1;
    RAISE NOTICE '354 : société % — facture % (%) réglée sans approbation : % en % règlement(s)',
      r.tenant_id, r.number, r.approval_status, r.regle, r.n;
  END LOOP;
  RAISE NOTICE '354 : % facture(s) d''achat réglée(s) sans approbation — listées, aucune modifiée (purchase_invoices_settled_unapproved()).', n;
END $$;
