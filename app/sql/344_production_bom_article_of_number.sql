-- ════════════════════════════════════════════════════════════════════════════
-- 344 — Partie 2, tâche 2.5 : nomenclature sans article, coût des composants,
--       et numéro d'ordre de fabrication (D10, D11)
-- ════════════════════════════════════════════════════════════════════════════
--
-- D3 (un OF terminé affichait 0,00 € et « aucune consommation ») est fermé par
-- `bc92cf9`, déjà sur la ligne principale. Restaient, mesurés (suite 344) :
--
--   D10 (stk-008)  une nomenclature ACTIVE pouvait ne porter aucun article : un
--                  OF bâti dessus est refusé plus tard, sans que la nomenclature
--                  dise pourquoi.
--   D10 (stk-009)  le coût d'un composant se saisit à la main, 0 par défaut :
--                  aucune lecture du coût moyen pondéré n'était offerte à l'écran.
--   D11 (stk-011)  l'écran prenait le numéro de l'OF AVANT de l'enregistrer
--                  (`get_next_document_number`, dans sa propre transaction) : un
--                  OF refusé consommait son numéro, et la suite avait un trou.
--
-- CE QUE FAIT CE FICHIER.
--   1. `boms` : une nomenclature active porte un article. Les nomenclatures
--      actives sans article sont DÉSACTIVÉES (jamais supprimées).
--   2. `product_current_cump` : le coût moyen pondéré courant d'un article
--      (stocks détenus, tous dépôts), à défaut son prix de revient. Lecture
--      seule, sous les droits de l'appelant — l'écran s'en sert pour proposer le
--      coût d'un composant. Rien n'est écrit d'office : un coût nul saisi dans
--      une nomenclature garde son sens (« pas de coût standard », 302).
--   3. `manufacturing_orders` : le numéro est attribué par la base, DANS la
--      transaction de l'enregistrement et APRÈS la garde de l'article. Un refus
--      annule tout, numéro compris.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. Une nomenclature active porte un article ───────────────────────────
UPDATE public.boms SET active = false
 WHERE product_id IS NULL AND COALESCE(active, true);

-- Une GARDE par déclencheur, et non une contrainte CHECK : la suite d'isolation
-- (105) alimente chaque table avec ses valeurs par défaut, déclencheurs coupés —
-- une nomenclature « active, sans article » — et une contrainte la ferait
-- échouer sans rien dire de l'isolation. Le refus est le même pour un écran.
ALTER TABLE public.boms DROP CONSTRAINT IF EXISTS boms_active_requires_product;

CREATE OR REPLACE FUNCTION public.boms_active_requires_product()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $fn$
BEGIN
  IF COALESCE(NEW.active, true) AND NEW.product_id IS NULL THEN
    RAISE EXCEPTION 'Nomenclature % : une nomenclature active doit porter l''article qu''elle fabrique (choisissez un article, ou enregistrez-la inactive).',
      COALESCE(NEW.code, '?')
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $fn$;

DROP TRIGGER IF EXISTS boms_active_requires_product ON public.boms;
CREATE TRIGGER boms_active_requires_product
  BEFORE INSERT OR UPDATE OF active, product_id ON public.boms
  FOR EACH ROW EXECUTE FUNCTION public.boms_active_requires_product();

REVOKE ALL ON FUNCTION public.boms_active_requires_product() FROM PUBLIC, anon, authenticated;

-- ── 2. Le coût moyen pondéré courant d'un article ─────────────────────────
CREATE OR REPLACE FUNCTION public.product_current_cump(p_product_id uuid)
RETURNS numeric
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $fn$
  SELECT round(COALESCE(
    (SELECT sum(sq.quantity * sq.unit_cost) / NULLIF(sum(sq.quantity), 0)
       FROM stock_quantities sq
      WHERE sq.product_id = p_product_id AND sq.quantity > 0 AND COALESCE(sq.unit_cost, 0) > 0),
    (SELECT NULLIF(p.cost_price, 0) FROM products p WHERE p.id = p_product_id),
    (SELECT NULLIF(p.purchase_price, 0) FROM products p WHERE p.id = p_product_id),
    0), 4)
$fn$;

COMMENT ON FUNCTION public.product_current_cump(uuid) IS
  '344 — coût moyen pondéré courant d''un article : stocks détenus (tous dépôts), à défaut prix de revient, à défaut prix d''achat. Lecture seule, sous les droits de l''appelant (la RLS borne à sa société). Proposé à l''écran comme coût d''un composant de nomenclature.';

REVOKE ALL ON FUNCTION public.product_current_cump(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.product_current_cump(uuid) TO authenticated, service_role;

-- ── 3. Le numéro d'OF est attribué dans la transaction de l'enregistrement ─
CREATE OR REPLACE FUNCTION public.manufacturing_order_assign_number()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $fn$
BEGIN
  IF btrim(COALESCE(NEW.number, '')) = '' THEN
    NEW.number := get_next_document_number('OF');
  END IF;
  RETURN NEW;
END $fn$;

-- « b_ » : après `a_manufacturing_order_product` (la garde de l'article), donc
-- un OF refusé ne demande même pas de numéro ; et si un refus survient plus
-- tard, la transaction annulée rend le numéro.
DROP TRIGGER IF EXISTS b_manufacturing_order_number ON public.manufacturing_orders;
CREATE TRIGGER b_manufacturing_order_number
  BEFORE INSERT ON public.manufacturing_orders
  FOR EACH ROW EXECUTE FUNCTION public.manufacturing_order_assign_number();

REVOKE ALL ON FUNCTION public.manufacturing_order_assign_number() FROM PUBLIC, anon, authenticated;
