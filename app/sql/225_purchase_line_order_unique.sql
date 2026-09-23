-- ============================================================
-- 225_purchase_line_order_unique.sql — l'ordre des lignes doit être total (R-06)
--
-- La 214 fait décider `line_order` de la ligne qu'une réception partielle solde
-- en premier, mais rien n'empêche deux lignes d'une même commande de porter le
-- MÊME ordre : le trigger n'attribue une valeur que si elle est absente, une
-- valeur explicite restant prioritaire (écran, API, conversion). Or la règle
-- « les lignes précédentes sont celles de line_order inférieur » n'est vraie que
-- si l'ordre est total : à égalité, aucune des deux lignes n'est « avant »
-- l'autre, et toutes deux s'attribuent la même réception.
--
-- Mesuré : deux lignes de 3 du même article, toutes deux en line_order 1,
-- réception de 4 → `quantity_received` rend 3 et 3, soit 6 reçus sur 4 livrés.
-- La commande se solde alors que deux unités manquent. L'ancien tri par uuid,
-- lui, ne pouvait pas double-compter : c'est une régression de la 214.
--
-- Trois verrous, du plus fort au plus faible :
--   1. index unique (tenant, commande, ordre) — le double-comptage devient
--      impossible, et une tentative échoue bruyamment au lieu de fausser un
--      reliquat en silence ;
--   2. le trigger attribue aussi l'ordre à la MISE À JOUR qui l'efface ;
--   3. `quantity_received` départage par `id` à ordre égal, pour rester total
--      même si l'index venait à manquer (base ancienne, restauration partielle).
--
-- Scénarios : sql/225_purchase_line_order_unique_tests.sql (G06e, G06f, G06g).
-- ============================================================

-- ------------------------------------------------------------
-- 1. Reprise : renuméroter les commandes qui portent un doublon ou un trou
-- ------------------------------------------------------------
WITH concernees AS (
  SELECT tenant_id, purchase_order_id
  FROM purchase_order_lines
  WHERE purchase_order_id IS NOT NULL
  GROUP BY tenant_id, purchase_order_id
  -- count(DISTINCT) ignore les NULL : attrape le doublon comme l'ordre absent
  HAVING count(*) <> count(DISTINCT line_order)
), renum AS (
  SELECT pol.id,
         row_number() OVER (PARTITION BY pol.tenant_id, pol.purchase_order_id
                            ORDER BY pol.line_order NULLS LAST, pol.id) AS rn
  FROM purchase_order_lines pol
  JOIN concernees c ON c.tenant_id = pol.tenant_id AND c.purchase_order_id = pol.purchase_order_id
)
UPDATE purchase_order_lines pol
SET line_order = renum.rn
FROM renum
WHERE pol.id = renum.id AND pol.line_order IS DISTINCT FROM renum.rn;

-- ------------------------------------------------------------
-- 2. Index unique : un ordre, une ligne
-- ------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS uq_purchase_order_lines_line_order
  ON purchase_order_lines (tenant_id, purchase_order_id, line_order)
  WHERE purchase_order_id IS NOT NULL AND line_order IS NOT NULL;

-- ------------------------------------------------------------
-- 3. Attribution automatique à la création ET à la mise à jour
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION purchase_order_line_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.line_order IS NULL THEN
    SELECT COALESCE(max(line_order), 0) + 1 INTO NEW.line_order
    FROM purchase_order_lines
    WHERE tenant_id = NEW.tenant_id AND purchase_order_id = NEW.purchase_order_id
      AND id IS DISTINCT FROM NEW.id;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS tg_purchase_order_line_order ON purchase_order_lines;
CREATE TRIGGER tg_purchase_order_line_order
  BEFORE INSERT OR UPDATE OF line_order ON purchase_order_lines
  FOR EACH ROW EXECUTE FUNCTION purchase_order_line_order();

-- ------------------------------------------------------------
-- 4. Allocation : ordre total, `id` départageant une égalité résiduelle
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION quantity_received(pol purchase_order_lines)
RETURNS numeric
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  WITH recu AS (
    SELECT COALESCE(sum(grl.quantity_received), 0) AS q
    FROM goods_receipts gr
    JOIN goods_receipt_lines grl ON grl.goods_receipt_id = gr.id AND grl.tenant_id = gr.tenant_id
    WHERE gr.purchase_order_id = pol.purchase_order_id AND gr.tenant_id = pol.tenant_id
      AND gr.status IN ('received', 'partial')
      AND grl.product_id IS NOT DISTINCT FROM pol.product_id
  ), avant AS (
    -- R-06 : les lignes précédentes sont celles de line_order inférieur ; à ordre
    -- égal (base ancienne, sans l'index unique de la 225) l'uuid départage, pour
    -- que la règle reste un ordre TOTAL et qu'aucune réception ne compte deux fois
    SELECT COALESCE(sum(quantity), 0) AS q
    FROM purchase_order_lines
    WHERE purchase_order_id = pol.purchase_order_id AND tenant_id = pol.tenant_id
      AND product_id IS NOT DISTINCT FROM pol.product_id
      AND (COALESCE(line_order, 2147483647), id) < (COALESCE(pol.line_order, 2147483647), pol.id)
  )
  SELECT GREATEST(LEAST(COALESCE(pol.quantity, 0), recu.q - avant.q), 0) FROM recu, avant
$$;

COMMENT ON INDEX uq_purchase_order_lines_line_order IS
  'R-06 : deux lignes d''une même commande ne peuvent pas porter le même ordre — sans quoi une réception partielle serait comptée deux fois (225).';
