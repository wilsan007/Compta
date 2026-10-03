-- ============================================================
-- 313_customer_balances_from_ledger.sql — recette /qa du 29/09/2026
-- (lot A, A3 : ven-017 🟠 / ven-018 🟠)
--
-- LE DÉFAUT, mesuré à l'écran : le « Solde dû » de la liste des clients et le
-- « Crédit utilisé » du contrôle crédit affichent 0,00 € partout, alors que le
-- 411 porte 532,20. Cause : ces deux écrans lisent `customers.balance` et
-- `customers.credit_used`, deux colonnes dénormalisées que **rien ne tient** —
-- aucune écriture, aucun déclencheur ne les met à jour. La valeur est donc
-- toujours celle du `DEFAULT 0`.
--
-- LE CORRECTIF (même doctrine que la 277 pour les comptes bancaires et la 278
-- pour les indicateurs : « le grand livre est la seule vérité »)
--   1. Une vue `customer_balances` (security_invoker, donc la RLS de la société
--      s'applique) rend, pour CHAQUE client, son solde du compte 411 :
--      somme des débits − crédits des écritures **validées**, par compte
--      auxiliaire (`journal_lines.account_tiers`). Un client sans mouvement est
--      présent, à 0,00 €.
--   2. Les écrans lisent la vue : liste des clients (affichage et export),
--      contrôle crédit, fiche client 360. Les colonnes `customers.balance` et
--      `customers.credit_used` ne sont plus lues ni affichées — comme
--      `bank_accounts.balance` depuis la 277.
--
-- CE QUE CETTE MIGRATION NE FAIT PAS — et le dit :
--   * elle ne supprime pas les deux colonnes : leur retrait touche le type
--     généré et les clients de l'API ; elles restent, documentées comme non
--     tenues et non lues.
--   * elle ne calcule AUCUN solde en dehors du grand livre : pas de somme de
--     `invoices.amount_due` en doublon, pas de reprise des colonnes mortes.
--   * les avoirs et règlements sont déjà des écritures (411 au crédit) : rien
--     de spécial à faire, c'est le grand livre qui les porte.
--   * le solde n'est pas lettré par facture : c'est un solde de compte, pas un
--     reste dû par pièce (le lettrage a ses propres écrans).
--
-- Preuve : `313_customer_balances_from_ledger_tests.sql` (T01 à T05, T01 vu
-- rouge avant).
-- ============================================================

CREATE OR REPLACE VIEW public.customer_balances
WITH (security_invoker = true) AS
SELECT
  c.tenant_id,
  c.id                                       AS customer_id,
  c.name,
  c.account_tiers,
  COALESCE(s.balance, 0)::numeric(14, 2)     AS balance,
  COALESCE(s.mouvements, 0)                  AS lines_count
FROM customers c
LEFT JOIN (
  SELECT jl.tenant_id,
         jl.account_tiers,
         sum(jl.debit - jl.credit) AS balance,
         count(*)                  AS mouvements
  FROM journal_lines jl
  JOIN journal_entries je
    ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
  WHERE je.status = 'posted'
    AND COALESCE(jl.account_general, jl.account_code) LIKE '411%'
  GROUP BY jl.tenant_id, jl.account_tiers
) s
  ON s.tenant_id = c.tenant_id
 AND s.account_tiers = c.account_tiers;

-- Le MÊME défaut frappe la liste des fournisseurs (`suppliers.balance`, jamais
-- tenue non plus) : la vue jumelle lit le 401. « Partout » dans le constat de
-- ven-017, c'est bien les deux listes.
CREATE OR REPLACE VIEW public.supplier_balances
WITH (security_invoker = true) AS
SELECT
  s.tenant_id,
  s.id                                       AS supplier_id,
  s.name,
  s.account_tiers,
  COALESCE(a.balance, 0)::numeric(14, 2)     AS balance,
  COALESCE(a.mouvements, 0)                  AS lines_count
FROM suppliers s
LEFT JOIN (
  SELECT jl.tenant_id,
         jl.account_tiers,
         sum(jl.debit - jl.credit) AS balance,
         count(*)                  AS mouvements
  FROM journal_lines jl
  JOIN journal_entries je
    ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
  WHERE je.status = 'posted'
    AND COALESCE(jl.account_general, jl.account_code) LIKE '401%'
  GROUP BY jl.tenant_id, jl.account_tiers
) a
  ON a.tenant_id = s.tenant_id
 AND a.account_tiers = s.account_tiers;

COMMENT ON VIEW public.supplier_balances IS
  'A3 (313) : solde du compte 401 par fournisseur, lu au grand livre (écritures validées uniquement). '
  'Remplace la lecture de suppliers.balance, que rien ne tenait.';
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.supplier_balances FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.supplier_balances TO authenticated, service_role;

COMMENT ON COLUMN public.suppliers.balance IS
  'A3 (313) : NI TENUE NI LUE — le solde du fournisseur se lit dans la vue supplier_balances (grand livre).';

COMMENT ON VIEW public.customer_balances IS
  'A3 (313) : solde du compte 411 par client, lu au grand livre (écritures validées uniquement). '
  'Remplace la lecture de customers.balance / customers.credit_used, que rien ne tenait.';

-- Une vue se lit : aucun rôle applicatif n''y écrit (les colonnes dénormalisées
-- de `customers` ne sont pas touchées pour autant).
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.customer_balances FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.customer_balances TO authenticated, service_role;

COMMENT ON COLUMN public.customers.balance IS
  'A3 (313) : NI TENUE NI LUE — le solde du client se lit dans la vue customer_balances (grand livre). '
  'Colonne conservée pour le type généré ; ne pas la réafficher.';
COMMENT ON COLUMN public.customers.credit_used IS
  'A3 (313) : NI TENUE NI LUE — l''encours utilisé se lit dans la vue customer_balances (grand livre).';
