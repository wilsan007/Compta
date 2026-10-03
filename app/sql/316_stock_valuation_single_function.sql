-- ============================================================
-- 316_stock_valuation_single_function.sql — D2 (stk-005)
--
-- Recette /qa du 29/09/2026, bouton « Valoriser le stock » :
--   1. dépôt « Tous » → PostgREST ne savait pas choisir entre DEUX surcharges
--      (`(p_method, p_warehouse_id)` et `(p_tenant_id, p_method, p_date)`) :
--      erreur 300 « Could not choose the best candidate function » ;
--   2. avec un dépôt → UNE seule ligne « — | 0 | 0,00 € | 5 600,00 € », la même
--      en FIFO comme en CUMP : 5 600 = Σ quantité × prix d'achat de la FICHE,
--      quand les couches en portaient 5 900.
--
-- Règle W10 (une fonction, un nom) et doctrine de la 254 (les couches portent le
-- CUMP : elles sont la valeur de la comptabilité) : il ne reste qu'UNE fonction,
-- adossée à `calculate_stock_valuation_at_date` (111) qui lit les couches et
-- rejoue les mouvements — donc une ligne par article, au coût des couches.
--
-- Le client (`businessFunctions.ts`) n'appelle que `p_method` et
-- `p_warehouse_id` : la date prend sa valeur par défaut (aujourd'hui), et la
-- signature ne peut plus être confondue avec celle de `…_at_date`.
--
-- Mesuré sur base neuve à la 315, avant ce fichier : `316_*_tests` T01/T02/T03
-- rouges (l'appel à trois arguments partait dans la surcharge `(uuid, text,
-- date)` — « invalid input syntax for type uuid: "cump" »).
-- ============================================================

-- Les deux surcharges de la 88 et de la 152 disparaissent.
DROP FUNCTION IF EXISTS calculate_stock_valuation(text, uuid);
DROP FUNCTION IF EXISTS calculate_stock_valuation(uuid, text, date);

-- Une seule fonction : méthode, dépôt (optionnel), date.
CREATE OR REPLACE FUNCTION calculate_stock_valuation(
  p_method text DEFAULT NULL,
  p_warehouse_id uuid DEFAULT NULL,
  p_date date DEFAULT CURRENT_DATE
)
RETURNS TABLE(
  product_id uuid,
  product_name text,
  warehouse_id uuid,
  quantity numeric,
  unit_cost numeric,
  total_value numeric,
  method text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT v.product_id, v.product_name, v.warehouse_id, v.quantity, v.unit_cost, v.total_value, v.method
  FROM calculate_stock_valuation_at_date(current_tenant_id(), p_date, p_method) v
  WHERE v.quantity > 0
    AND (p_warehouse_id IS NULL OR v.warehouse_id = p_warehouse_id);
$$;

COMMENT ON FUNCTION calculate_stock_valuation(text, uuid, date) IS
  'D2 (316) : valorisation du stock d''une société — une ligne par article et par dépôt, lue sur les couches de valorisation (calculate_stock_valuation_at_date), CUMP ou FIFO/LIFO. Le dépôt est optionnel (NULL = tous), la date aussi (défaut : aujourd''hui).';

GRANT EXECUTE ON FUNCTION calculate_stock_valuation(text, uuid, date) TO authenticated;
