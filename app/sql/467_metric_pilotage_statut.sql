-- ═══════════════════════════════════════════════════════════════════════════
-- 467 — I-08 : la marge de pilotage filtre sur le STATUT des factures
-- ═══════════════════════════════════════════════════════════════════════════
--
-- EN LISANT `getMarginAnalysis` EN ENTIER avant de le branchement, une
-- DEUXIÈME différence de sens est sortie, plus grave que la période :
--
--   `.eq('invoice.status', 'paid')`  — l'écran ne compte QUE les factures
--   PAYÉES. La fonction SQL ne filtrait rien : elle prenait aussi les
--   brouillons, les impayées, les avoirs.
--
-- Brancher les deux sans cela aurait changé les chiffres en silence, et
-- dans le sens le plus Trompeur : une marge calculée sur du non-payé
-- ressemble à une marge calculée normalement. C'est le genre d'erreur
-- qu'aucun test de fumée ne voit.
--
-- On n'a donc toujours PAS branché les écrans. On commence par aligner
-- la fonction, pour qu'elle dise exactement la même chose que l'écran.
--
-- LE FILTRE EST UN PARAMÈTRE, pas une constante : l'écran ne regarde
-- que les payées aujourd'hui, mais une vue « encréance » aura besoin du
-- même calcul sur les autres statuts. On ne fige pas ce qui est un choix
-- d'écran dans une définition de métrique.
-- ═══════════════════════════════════════════════════════════════════════════

-- Surcharges précédentes (465 à 2 arguments, 466 à 4) retirées : sinon
-- PostgreSQL ne sait plus laquelle choisir. Jamais livrées.
DROP FUNCTION IF EXISTS public.metric_pilotage_marge(uuid, text);
DROP FUNCTION IF EXISTS public.metric_pilotage_marge(uuid, text, date, date);

CREATE OR REPLACE FUNCTION public.metric_pilotage_marge(
  p_tenant    uuid,
  p_dimension text DEFAULT 'product',
  p_debut     date DEFAULT NULL,
  p_fin       date DEFAULT NULL,
  p_statut    text DEFAULT 'paid'
)
RETURNS TABLE (
  cle              text,
  chiffre_affaires numeric,
  cout             numeric,
  marge            numeric,
  marge_pct        numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
  SELECT
    CASE p_dimension
      WHEN 'customer' THEN coalesce(c.name, 'No customer')
      WHEN 'category' THEN coalesce(pr.category, 'No category')
      ELSE coalesce(pr.name, 'No product')
    END,
    sum(coalesce(l.total, 0))::numeric,
    sum(coalesce(l.quantity, 0) * coalesce(pr.cost_price, 0))::numeric,
    (sum(coalesce(l.total, 0)) - sum(coalesce(l.quantity, 0) * coalesce(pr.cost_price, 0)))::numeric,
    CASE WHEN sum(coalesce(l.total, 0)) > 0
         THEN (sum(coalesce(l.total, 0)) - sum(coalesce(l.quantity, 0) * coalesce(pr.cost_price, 0)))
              / sum(coalesce(l.total, 0)) * 100
         ELSE 0 END::numeric
  FROM public.invoice_lines l
  JOIN public.invoices  i  ON i.id  = l.invoice_id  AND i.tenant_id  = l.tenant_id
  LEFT JOIN public.customers c ON c.id  = i.customer_id AND c.tenant_id  = i.tenant_id
  LEFT JOIN public.products pr ON pr.id = l.product_id  AND pr.tenant_id = l.tenant_id
 WHERE l.tenant_id = p_tenant
   AND (p_debut IS NULL OR i.date >= p_debut)
   AND (p_fin   IS NULL OR i.date <= p_fin)
   -- LE STATUT : ce que l'écranfiltrait déjà (`.eq('invoice.status','paid')`)
   -- et que la 466 avait laissé passer. NULL = pas de filtre (usage interne).
   AND (p_statut IS NULL OR i.status = p_statut)
 GROUP BY 1
 ORDER BY 1;
$fn$;

COMMENT ON FUNCTION public.metric_pilotage_marge(uuid, text, date, date, text) IS
  '467 (I-08) : marge de pilotage — formule de pilotage.ts, sur une fenêtre de dates et pour un statut de facture. Alignée sur l''écran : sans p_statut, elle compterait les brouillons et les impayées, ce que l''écran ne fait jamais.';

REVOKE ALL ON FUNCTION public.metric_pilotage_marge(uuid, text, date, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.metric_pilotage_marge(uuid, text, date, date, text) TO authenticated, service_role;

UPDATE public.metric_definitions
   SET sql_definition = 'metric_pilotage_marge(p_tenant, p_dimension, p_debut, p_fin, p_statut)',
       note = 'Migration 467 : la formule prend la FENÊTRE et le STATUT des factures, comme l''écran. La 466 ignorait le statut — elle comptait les brouillons et les impayées, ce que l''écran ne fait pas. La v1 (JavaScript, sans fenêtre ni statut) reste close à la veille dans l''historique.'
 WHERE code = 'pilotage.marge_pct' AND version = 2 AND valide_au IS NULL;