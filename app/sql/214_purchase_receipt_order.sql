-- ============================================================
-- 214_purchase_receipt_order.sql — R-06 (phase 1 du reste-à-faire du 22/09)
--
-- `quantity_received` (195) solde les lignes d'une commande portant le même
-- article dans l'ordre de leur `id` — un uuid tiré au hasard. La ligne servie
-- en premier par une réception partielle était donc arbitraire, et les
-- reliquats par ligne pouvaient changer d'un tirage à l'autre : les commandes
-- pouvaient rester « partial » alors que la marchandise était là.
--
-- `purchase_order_lines` n'avait aucune colonne d'ordre. Cette migration :
--   1. ajoute `line_order` et la remplit dans l'ordre d'insertion existant
--      (reprise des commandes en cours) ;
--   2. l'attribue automatiquement à toute nouvelle ligne qui n'en porte pas,
--      pour que la règle tienne quelle que soit la porte d'entrée (écran, API,
--      conversion de demande d'achat) ;
--   3. trie l'allocation du reçu dessus.
--
-- Scénarios : sql/214_purchase_receipt_order_tests.sql (G06b, G06c, G06d).
-- ============================================================

-- ------------------------------------------------------------
-- 1. Colonne d'ordre + reprise des lignes existantes
-- ------------------------------------------------------------
ALTER TABLE purchase_order_lines ADD COLUMN IF NOT EXISTS line_order integer;

UPDATE purchase_order_lines pol
SET line_order = s.rn
FROM (
  -- purchase_order_lines n'a pas d'horodatage : l'ordre des uuid est celui
  -- auquel les lignes étaient déjà soldées avant cette migration
  SELECT id, row_number() OVER (PARTITION BY tenant_id, purchase_order_id ORDER BY id) AS rn
  FROM purchase_order_lines WHERE line_order IS NULL
) s
WHERE pol.id = s.id AND pol.line_order IS NULL;

-- ------------------------------------------------------------
-- 2. Attribution automatique à la création
--    (l'écran, l'API et la conversion de demande d'achat n'ont pas à s'en
--     occuper ; une valeur explicite reste prioritaire)
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
    WHERE tenant_id = NEW.tenant_id AND purchase_order_id = NEW.purchase_order_id;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS tg_purchase_order_line_order ON purchase_order_lines;
CREATE TRIGGER tg_purchase_order_line_order
  BEFORE INSERT ON purchase_order_lines
  FOR EACH ROW EXECUTE FUNCTION purchase_order_line_order();

COMMENT ON COLUMN purchase_order_lines.line_order IS
  'R-06 — ordre de la ligne dans la commande : c''est lui qui décide quelle ligne une réception partielle solde en premier.';

-- ------------------------------------------------------------
-- 3. Allocation du reçu : suivre line_order, pas l'uuid
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
    -- R-06 : les lignes précédentes sont celles de line_order inférieur
    SELECT COALESCE(sum(quantity), 0) AS q
    FROM purchase_order_lines
    WHERE purchase_order_id = pol.purchase_order_id AND tenant_id = pol.tenant_id
      AND product_id IS NOT DISTINCT FROM pol.product_id
      AND COALESCE(line_order, 0) < COALESCE(pol.line_order, 0)
  )
  SELECT GREATEST(LEAST(COALESCE(pol.quantity, 0), recu.q - avant.q), 0) FROM recu, avant
$$;