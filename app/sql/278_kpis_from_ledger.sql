-- ============================================================
-- 278_kpis_from_ledger.sql — vague X6 / M5 : une seule vérité pour les tableaux de bord
-- (audit fonctionnel exécuté du 28/09/2026)
--
-- LES DÉFAUTS, mesurés par le chemin de l'écran (s9) :
--   les trois tableaux de bord (accueil, financier, trésorerie) calculaient chacun
--   leurs chiffres à leur façon : CA = TTC des factures PAYÉES (financier) ou
--   comptes 70 (accueil), charges = TTC des achats payés, encours clients = somme
--   de `customers.balance` (que rien ne tient), encours = factures au statut
--   « sent/overdue »… alors qu'une facture VALIDÉE restait au statut « draft » :
--   elle n'apparaissait dans aucun encours.
--
-- LE CORRECTIF
--   1. `get_kpis(p_from, p_to)` lit le GRAND LIVRE (écritures validées de la
--      société) : CA = 70x (crédit − débit) et charges = 6x (débit − crédit) sur
--      la période ; encours clients = 411x, fournisseurs = 401x, trésorerie = 5x,
--      en solde cumulé au `p_to` (à-nouveaux compris). Les trois tableaux l'appellent.
--   2. Une facture validée n'est plus un brouillon : sa validation la fait passer
--      à « émise » (`sent`) ; les factures déjà validées sont rattrapées.
--
-- Suite : `278_kpis_from_ledger_tests.sql`.
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_kpis(p_from date, p_to date)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'public', 'pg_temp'
AS $$
  WITH l AS (
    SELECT coalesce(jl.account_general, jl.account_code) AS acc, jl.debit, jl.credit, je.date
    FROM journal_lines jl
    JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
    WHERE je.tenant_id = current_tenant_id() AND je.status = 'posted' AND je.date <= p_to
  )
  SELECT jsonb_build_object(
    'from', p_from, 'to', p_to,
    'revenue',     round(coalesce(sum(credit - debit) FILTER (WHERE acc LIKE '70%' AND date >= p_from), 0), 2),
    'expenses',    round(coalesce(sum(debit - credit) FILTER (WHERE acc LIKE '6%'  AND date >= p_from), 0), 2),
    'receivables', round(coalesce(sum(debit - credit) FILTER (WHERE acc LIKE '411%'), 0), 2),
    'payables',    round(coalesce(sum(credit - debit) FILTER (WHERE acc LIKE '401%'), 0), 2),
    'cash',        round(coalesce(sum(debit - credit) FILTER (WHERE acc LIKE '5%'), 0), 2),
    'draft_entries', (SELECT count(*) FROM journal_entries WHERE tenant_id = current_tenant_id() AND status = 'draft'),
    'posted_entries', (SELECT count(*) FROM journal_entries WHERE tenant_id = current_tenant_id() AND status = 'posted')
  )
  FROM l
$$;
COMMENT ON FUNCTION public.get_kpis(date, date) IS
  'X6/M5 (278) : indicateurs des tableaux de bord lus au grand livre (écritures validées) — CA 70x et charges 6x sur la période, encours 411x/401x et trésorerie 5x cumulés au p_to.';
REVOKE EXECUTE ON FUNCTION public.get_kpis(date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_kpis(date, date) TO authenticated, service_role;

-- Une facture validée est émise
CREATE OR REPLACE FUNCTION public.invoice_status_on_validate()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF NEW.validation_status = 'validated' AND OLD.validation_status IS DISTINCT FROM 'validated'
     AND NEW.status = 'draft' THEN
    NEW.status := 'sent';
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.invoice_status_on_validate() FROM PUBLIC, anon, authenticated;

-- après `tg_invoice_guard` (ordre des noms) : la validation est déjà acceptée
DROP TRIGGER IF EXISTS tg_invoice_status_on_validate ON public.invoices;
CREATE TRIGGER tg_invoice_status_on_validate
  BEFORE UPDATE OF validation_status ON public.invoices
  FOR EACH ROW EXECUTE FUNCTION public.invoice_status_on_validate();

-- Rattrapage, société par société : la modification est journalisée NF-525 au nom
-- d'un administrateur de la société (le journal exige un membre de la société)
DO $$
DECLARE r record; n int := 0; m int; v_admin uuid;
BEGIN
  FOR r IN SELECT DISTINCT tenant_id FROM invoices WHERE validation_status = 'validated' AND status = 'draft' LOOP
    SELECT auth_id INTO v_admin FROM tenant_users
    WHERE tenant_id = r.tenant_id AND status = 'active' AND role = 'admin' ORDER BY created_at LIMIT 1;
    IF v_admin IS NULL THEN
      RAISE NOTICE '[X6/M5] société % sans administrateur actif : factures laissées en brouillon', r.tenant_id;
      CONTINUE;
    END IF;
    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    PERFORM set_config('app.active_tenant_id', r.tenant_id::text, true);
    UPDATE invoices SET status = 'sent'
    WHERE tenant_id = r.tenant_id AND validation_status = 'validated' AND status = 'draft';
    GET DIAGNOSTICS m = ROW_COUNT;
    n := n + m;
  END LOOP;
  PERFORM set_config('app.active_tenant_id', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
  RAISE NOTICE '[X6/M5] % facture(s) validée(s) sorties du statut brouillon', n;
END $$;
