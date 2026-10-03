-- ═══════════════════════════════════════════════════════════════════════════
-- 465 — I-08 : la marge de pilotage devient une fonction NOMMÉE
-- ═══════════════════════════════════════════════════════════════════════════
--
-- La 464 a inscrit `pilotage.marge_pct` en notant qu'elle est calculée en
-- JAVASCRIPT, à l'affichage, en trois endroits. C'était le reliquat du
-- défaut « définitions concurrentes » : trois exécutions, trois occasions
-- de diverger. Ce fichier le ferme.
--
-- LA FORMULE EST REPRISE À L'IDENTIQUE, sans la retoucher.
--   chiffre d'affaires = Σ invoice_lines.total            (montant HT)
--   coût               = Σ quantité × coût de revient     (coût_achat)
--   marge              = chiffre d'affaires − coût
--   marge %            = marge / chiffre d'affaires × 100 (0 si CA = 0)
-- C'est la formule de `pilotage.ts` lignes 129-146 et 295, y compris le
-- correctif M10 du 28/09 : le coût vient du COÛT DE REVIENT de l'article,
-- plus d'une estimation à 70 % du prix qui rendait la marge égale à 30 %
-- quoi qu'il arrive. On ne « améliore » rien au passage : une migration
-- qui change un résultat en même temps qu'elle le déplace est deux
-- migrations déguisées en une.
--
-- ET LA DATE EST LE MÉCANISME : la définition v1 (le JavaScript) est
-- CLÔTURÉE à aujourd'hui, la v2 (cette fonction) commence aujourd'hui.
-- C'est le premier usage réel du dictionnaire — on verra, dans un an,
-- quel chiffre a été produit par quelle formule.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.metric_pilotage_marge(
  p_tenant    uuid,
  p_dimension text DEFAULT 'product'
)
RETURNS TABLE (
  cle             text,
  chiffre_affaires numeric,
  cout            numeric,
  marge           numeric,
  marge_pct       numeric
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
 GROUP BY 1
 ORDER BY 1;
$fn$;

COMMENT ON FUNCTION public.metric_pilotage_marge(uuid, text) IS
  '465 (I-08) : la marge de pilotage, en une seule définition NOMMÉE. Formule reprise à l''identique de pilotage.ts (dont le correctif M10 : coût de revient de l''article, jamais une estimation). Remplace trois calculs JavaScript refaits à l''affichage.';

REVOKE ALL ON FUNCTION public.metric_pilotage_marge(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.metric_pilotage_marge(uuid, text) TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────
-- Le dictionnaire : v1 se ferme, v2 commence AUJOURD'HUI
-- ─────────────────────────────────────────────────────────────
-- On ne se chevauche pas, même d'UN JOUR : la garde refuse que deux
-- définitions soient valables à la même date (mesuré ici). La bascule se
-- fait donc la VEILLE du déploiement — v1 se ferme hier, v2 commence
-- aujourd'hui. Aujourd'hui, on lit donc bien v2.
UPDATE public.metric_definitions
   SET valide_au = CURRENT_DATE - 1
 WHERE code = 'pilotage.marge_pct' AND version = 1;

INSERT INTO public.metric_definitions (tenant_id, code, version, libelle, unite, sql_definition, valide_du, valide_au, note)
VALUES (NULL, 'pilotage.marge_pct', 2, 'Marge en % du chiffre d''affaires', '%',
        'metric_pilotage_marge(p_tenant, p_dimension)',
        CURRENT_DATE, NULL,
        'Migration 465 : la formule quitte le JAVASCRIPT (pilotage.ts, trois endroits) pour UNE fonction SQL nommée. Formule inchangée, correctif M10 inclus. La version 1 se ferme la veille — premier usage réel du dictionnaire.')
ON CONFLICT DO NOTHING;