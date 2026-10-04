-- ============================================================
-- 254_stock_valuation_cump_single_truth.sql — une seule vérité de valorisation
--
-- Constat, mesuré (suite 254, base neuve à la 253) :
--   T01 ✅ 100@10 puis 100@14 : 200 unités à CUMP 12, couches = 2 400
--   T02 ❌ une sortie de 50 diminue la comptabilité de 600 (50 × 12, CUMP) et
--          les couches de 500 (50 × 10, la plus ancienne en FIFO) — 100 €
--          d'écart entre deux tables qui décrivent le même stock
--   T03 ❌ la cohérence ne tient pas sur un cycle entrée / sortie / entrée
--   T04 ✅ l'historique comptable n'est pas réécrit
--   T05 ❌ avec `company_settings.stock_valuation_method = 'fifo'`, la même
--          divergence apparaît : le paramètre est écrit et jamais lu (la
--          fonction de consommation dit elle-même `v_method := 'cump'`).
--
-- DÉCISION, et pourquoi celle-là : la comptabilité valorise au **CUMP** —
-- `create_journal_on_stock_movement` sort au CUMP du dépôt, et les écritures
-- d'entrée portent le coût réel. Les couches FIFO étaient donc le seul endroit
-- du produit qui racontait autre chose. Le fichier aligne les couches sur la
-- valeur que la comptabilité enregistre : après chaque mouvement, les couches
-- vivantes du couple (article, dépôt) portent le CUMP courant, et leur valeur
-- vaut donc exactement `quantité × CUMP`.
--   * une entrée ne change pas la somme (100×10 + 100×14 = 2 400 = 200×12) ;
--   * une sortie diminue les deux du même montant (50 × 12 = 600) ;
--   * l'historique comptable n'est jamais touché : seules des **couches** sont
--     restatées, et la quantité consommée reste FIFO (traçabilité des lots).
--
-- LIMITE DITE : les valeurs `fifo` et `lifo` de
-- `company_settings.stock_valuation_method` restent **inertes** — elles ne
-- l'étaient déjà pas pour la comptabilité, et le devenir demanderait un moteur
-- de sortie par couche avec son écriture, ce que ni le plan ni cette vague ne
-- portent. Le test T05 le mesure au lieu de le taire.
-- ============================================================
CREATE OR REPLACE FUNCTION public.restate_valuation_layers_to_cump()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_cump numeric;
  v_tid uuid := COALESCE(NEW.tenant_id, current_tenant_id());
BEGIN
  IF NEW.movement_type NOT IN ('in', 'out', 'initial', 'adjustment') THEN
    RETURN NEW;
  END IF;

  SELECT NULLIF(COALESCE(sq.unit_cost, 0), 0) INTO v_cump
  FROM stock_quantities sq
  WHERE sq.tenant_id = v_tid
    AND sq.product_id = NEW.product_id
    AND sq.warehouse_id = NEW.warehouse_id;

  IF v_cump IS NULL THEN
    RETURN NEW;
  END IF;

  UPDATE stock_valuation_layers l
  SET unit_cost = v_cump,
      value = l.remaining_qty * v_cump
  WHERE l.tenant_id = v_tid
    AND l.product_id = NEW.product_id
    AND l.warehouse_id = NEW.warehouse_id
    AND l.remaining_qty > 0
    AND (l.unit_cost IS DISTINCT FROM v_cump
         OR l.value IS DISTINCT FROM l.remaining_qty * v_cump);

  RETURN NEW;
END $$;

COMMENT ON FUNCTION public.restate_valuation_layers_to_cump() IS
  '254 : après chaque mouvement, les couches vivantes du couple (article, dépôt) portent le CUMP courant — la valeur des couches vaut alors quantité × CUMP, comme la comptabilité. L''historique comptable n''est jamais touché.';

-- Le nom du déclencheur trie APRÈS `update_cump` (les déclencheurs s'exécutent
-- dans l'ordre alphabétique) : le CUMP est recalculé avant d'être appliqué.
DROP TRIGGER IF EXISTS zz_restate_layers_to_cump ON stock_movements;
CREATE TRIGGER zz_restate_layers_to_cump
  AFTER INSERT ON stock_movements
  FOR EACH ROW
  EXECUTE FUNCTION public.restate_valuation_layers_to_cump();

-- Reprise : les couches déjà en base suivent la même règle.
DO $$
DECLARE v_n int;
BEGIN
  UPDATE stock_valuation_layers l
  SET unit_cost = sq.unit_cost,
      value = l.remaining_qty * sq.unit_cost
  FROM stock_quantities sq
  WHERE l.tenant_id = sq.tenant_id
    AND l.product_id = sq.product_id
    AND l.warehouse_id = sq.warehouse_id
    AND l.remaining_qty > 0
    AND COALESCE(sq.unit_cost, 0) > 0
    AND (l.unit_cost IS DISTINCT FROM sq.unit_cost
         OR l.value IS DISTINCT FROM l.remaining_qty * sq.unit_cost);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n > 0 THEN
    RAISE NOTICE '254 : % couche(s) de valorisation alignées sur le CUMP du dépôt (reprise)', v_n;
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────
-- Droits — un déclencheur n'est pas une RPC (leçon de la 228)
-- ─────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.restate_valuation_layers_to_cump() FROM PUBLIC, anon, authenticated;
