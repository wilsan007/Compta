-- ═══════════════════════════════════════════════════════════════════════════
-- 466 — I-08 : la marge de pilotage, version PÉRIODIQUE
-- ═══════════════════════════════════════════════════════════════════════════
--
-- 465 a déplacé la formule de pilotage en SQL — mais SANS la période.
-- Mesuré en préparant le branchement des écrans : `getMarginAnalysis`
-- filtre sur une période (mois / trimestre / année) et calcule une
-- fenêtre glissante, alors que `metric_pilotage_marge` prenait TOUT
-- l'historique. Brancher l'un sur l'autre tel quel aurait changé les
-- chiffres affichés, en silence, pour tous les utilisateurs. C'est
-- exactement le genre de faute que ce chantier doit éviter.
--
-- On ne rebranche donc rien tant que les deux ne disent pas la même
-- chose. Cette migration ajoute la période à la fonction, et le
-- dictionnaire bascule sur une v3 datée — la v2 (sans période) se ferme
-- aujourd'hui. L'historique reste lisible : dans un an, on saura que la
-- v2 ne tenait pas compte de la période.
--
-- LA FORMULE RESTE IDENTIQUE. Seule la fenêtre change.
-- ═══════════════════════════════════════════════════════════════════════════

-- La surcharge à 2 arguments de la 465 est RETIREE : sinon PostgreSQL ne sait
-- plus laquelle choisir (« function metric_pilotage_marge(unknown, unknown) is
-- not unique ») — mesuré. Elle n'a jamais été livrée.
DROP FUNCTION IF EXISTS public.metric_pilotage_marge(uuid, text);

CREATE OR REPLACE FUNCTION public.metric_pilotage_marge(
  p_tenant    uuid,
  p_dimension text DEFAULT 'product',
  p_debut     date DEFAULT NULL,
  p_fin       date DEFAULT NULL
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
   -- La fenêtre : celle de l'écran. Sans date, on prend tout (v2).
   AND (p_debut IS NULL OR i.date >= p_debut)
   AND (p_fin   IS NULL OR i.date <= p_fin)
 GROUP BY 1
 ORDER BY 1;
$fn$;

COMMENT ON FUNCTION public.metric_pilotage_marge(uuid, text, date, date) IS
  '466 (I-08) : marge de pilotage, version PÉRIODIQUE — la même formule que la 465, sur une fenêtre de dates. Les deux bornes nulles donnent le comportement de la v2 (tout l''historique).';

REVOKE ALL ON FUNCTION public.metric_pilotage_marge(uuid, text, date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.metric_pilotage_marge(uuid, text, date, date) TO authenticated, service_role;

-- Bascule datée.
--
-- La v2 (migration 465, sans période) est RETIRÉE plutôt que datée :
-- elle n'a jamais été livrée — la 465 n'est pas encore fusionnée — donc
-- personne n'a jamais lu un chiffre sous sa définition. La retirer ne
-- perd rien et évite un artefact dans l'historique.
--
-- On a d'abord tenté de la dater (v2 fermée hier, v3 aujourd'hui) : la
-- contrainte `valide_au >= valide_du` l'a refusée, à raison, puisque v2
-- COMMENCE aujourd'hui. Un numéro de définition ne se réattribue pas.
DELETE FROM public.metric_definitions
 WHERE code = 'pilotage.marge_pct' AND version = 2;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.metric_definitions
                  WHERE code = 'pilotage.marge_pct' AND tenant_id IS NULL) THEN
  INSERT INTO public.metric_definitions (tenant_id, code, version, libelle, unite, sql_definition, valide_du, valide_au, note)
  VALUES (NULL, 'pilotage.marge_pct', 2, 'Marge en % du chiffre d''affaires (période)', '%',
          'metric_pilotage_marge(p_tenant, p_dimension, p_debut, p_fin)',
          CURRENT_DATE, NULL,
          'Migration 466 : la formule accepte la FENÊTRE de dates de l''écran (mois / trimestre / année). La 465 l''ignorait — la brancher aurait changé les chiffres en silence. La v1 (JavaScript) reste dans l''historique, close à la veille : on saura qu''elle était recalculée à l''affichage, sans période.');
  END IF;
END $$;