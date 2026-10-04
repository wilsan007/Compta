-- ════════════════════════════════════════════════════════════════════════════
-- 347 — Partie 2, tâche 2.10 (F1, cpt-001) : les soldes du plan comptable se
--       lisent au grand livre
-- ════════════════════════════════════════════════════════════════════════════
--
-- LE DÉFAUT, MESURÉ (suite 347). L'écran du plan comptable affichait les
-- colonnes `chart_accounts.balance`, `current_debit` et `current_credit`, que
-- rien ne tient à jour : un compte 512000 portant 10 000 € d'à-nouveau s'y
-- lisait à 0,00. Et comme l'écran masque par défaut les comptes à solde nul, le
-- plan s'ouvrait VIDE (« 0 sur 713 », F3).
--
-- CE QUE FAIT CE FICHIER. Une lecture, `chart_account_balances()` : pour la
-- société de l'appelant, le débit, le crédit et le solde de chaque compte, sur
-- les seules écritures VALIDÉES. Même doctrine que la banque (277) et les
-- tableaux de bord (278) : le grand livre est la seule vérité. Une ligne saisie
-- sur un sous-compte de tiers est rattachée à son compte général.
--
-- CE QU'IL NE FAIT PAS. Les trois colonnes de `chart_accounts` ne sont ni
-- supprimées ni recalculées : plus aucun écran ne doit les lire. Les soldes
-- ne sont pas cumulés sur les comptes parents.
-- ════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.chart_account_balances()
RETURNS TABLE (code text, debit numeric, credit numeric, balance numeric)
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $fn$
  SELECT COALESCE(ca.code, NULLIF(jl.account_general, ''), jl.account_code) AS code,
         COALESCE(sum(jl.debit), 0)::numeric,
         COALESCE(sum(jl.credit), 0)::numeric,
         (COALESCE(sum(jl.debit), 0) - COALESCE(sum(jl.credit), 0))::numeric
  FROM journal_lines jl
  JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
  LEFT JOIN chart_accounts ca ON ca.tenant_id = jl.tenant_id AND ca.code = jl.account_code
  WHERE jl.tenant_id = current_tenant_id()
    AND je.status = 'posted'
  GROUP BY 1
$fn$;

COMMENT ON FUNCTION public.chart_account_balances() IS
  '347 (F1) — débit, crédit et solde de chaque compte de la société de l''appelant, sur les écritures VALIDÉES. Lecture seule, sous les droits de l''appelant. Remplace la lecture de chart_accounts.balance / current_debit / current_credit, jamais tenues.';

REVOKE ALL ON FUNCTION public.chart_account_balances() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chart_account_balances() TO authenticated, service_role;
