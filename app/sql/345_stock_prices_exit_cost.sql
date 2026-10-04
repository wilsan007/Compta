-- ════════════════════════════════════════════════════════════════════════════
-- 345 — Partie 2, tâche 2.7 : prix d'article négatif, et coût d'une sortie de
--       stock (D6, D7)
-- ════════════════════════════════════════════════════════════════════════════
--
-- Mesuré (suite 345) :
--   D6 (stk-001)  un article s'enregistrait avec un prix de vente ou d'achat
--                 NÉGATIF : aucune contrainte.
--   D7 (stk-003)  une sortie de stock s'affichait à 0,00 € : `unit_cost` restait
--                 vide sur le mouvement, alors que la comptabilité la valorisait
--                 au coût moyen pondéré (elle le dérive elle-même).
--
-- CE QUE FAIT CE FICHIER.
--   1. `products` : prix de vente, d'achat et de revient non négatifs. Les
--      contraintes sont posées pour les écritures NOUVELLES ; si des articles
--      existants portent un prix négatif, ils ne sont PAS modifiés (décision
--      D-QA-3 ouverte : remis à 0, ou désactivés) et leur nombre est dit.
--   2. `stock_movements` : une SORTIE sans coût reçoit le coût moyen pondéré au
--      moment de la sortie — par la MÊME règle que l'écriture comptable (dépôt
--      du mouvement, à défaut tous dépôts, à défaut prix de revient). Le
--      mouvement affiche donc ce que le grand livre porte. Un coût fourni est
--      respecté.
--
-- CE QU'IL NE FAIT PAS.
--   * L'écriture comptable du STOCK INITIAL (D8, décision D-QA-4 : à-nouveau
--     3x / 890000, ou simple avertissement) : non codée, la décision est ouverte.
--   * Les mouvements déjà enregistrés ne sont pas recalculés.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. Prix non négatifs ──────────────────────────────────────────────────
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_sale_price_nonneg;
ALTER TABLE public.products ADD CONSTRAINT products_sale_price_nonneg
  CHECK (sale_price IS NULL OR sale_price >= 0) NOT VALID;
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_purchase_price_nonneg;
ALTER TABLE public.products ADD CONSTRAINT products_purchase_price_nonneg
  CHECK (purchase_price IS NULL OR purchase_price >= 0) NOT VALID;
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_cost_price_nonneg;
ALTER TABLE public.products ADD CONSTRAINT products_cost_price_nonneg
  CHECK (cost_price IS NULL OR cost_price >= 0) NOT VALID;

DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.products
   WHERE COALESCE(sale_price, 0) < 0 OR COALESCE(purchase_price, 0) < 0 OR COALESCE(cost_price, 0) < 0;
  IF n = 0 THEN
    ALTER TABLE public.products VALIDATE CONSTRAINT products_sale_price_nonneg;
    ALTER TABLE public.products VALIDATE CONSTRAINT products_purchase_price_nonneg;
    ALTER TABLE public.products VALIDATE CONSTRAINT products_cost_price_nonneg;
  ELSE
    RAISE NOTICE '345 : % article(s) portent un prix négatif — contraintes posées pour les écritures nouvelles ; ces lignes ne sont pas modifiées (décision D-QA-3)', n;
  END IF;
END $$;

-- ── 2. Le coût d'une sortie ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.stock_movement_exit_cost()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_cost numeric;
BEGIN
  IF NEW.movement_type IS DISTINCT FROM 'out' OR COALESCE(NEW.unit_cost, 0) <> 0 THEN
    RETURN NEW;
  END IF;

  -- EXACTEMENT la règle de `create_journal_on_stock_movement` (même structure,
  -- même absence d'arrondi) : avec un dépôt, le coût moyen de CE dépôt ; sans
  -- dépôt, celui de tous les dépôts ; à défaut, le prix de revient de la fiche.
  -- L'écriture comptable lira ensuite ce coût sur le mouvement : mêmes montants.
  IF NEW.warehouse_id IS NOT NULL THEN
    SELECT NULLIF(COALESCE(sq.unit_cost, 0), 0) INTO v_cost
    FROM stock_quantities sq
    WHERE sq.product_id = NEW.product_id
      AND sq.warehouse_id = NEW.warehouse_id
      AND sq.tenant_id = NEW.tenant_id;
  ELSE
    SELECT NULLIF(SUM(sq.quantity * COALESCE(sq.unit_cost, 0)) / NULLIF(SUM(sq.quantity), 0), 0)
    INTO v_cost
    FROM stock_quantities sq
    WHERE sq.product_id = NEW.product_id
      AND sq.tenant_id = NEW.tenant_id;
  END IF;
  IF v_cost IS NULL THEN
    SELECT NULLIF(COALESCE(p.cost_price, 0), 0) INTO v_cost
    FROM products p WHERE p.id = NEW.product_id AND p.tenant_id = NEW.tenant_id;
  END IF;

  IF v_cost IS NOT NULL THEN
    NEW.unit_cost := v_cost;
  END IF;
  RETURN NEW;
END $fn$;

-- « b_ » : après `a_stock_movement_type_sync`, qui aligne `movement_type`.
DROP TRIGGER IF EXISTS b_stock_movement_exit_cost ON public.stock_movements;
CREATE TRIGGER b_stock_movement_exit_cost
  BEFORE INSERT ON public.stock_movements
  FOR EACH ROW EXECUTE FUNCTION public.stock_movement_exit_cost();

REVOKE ALL ON FUNCTION public.stock_movement_exit_cost() FROM PUBLIC, anon, authenticated;
