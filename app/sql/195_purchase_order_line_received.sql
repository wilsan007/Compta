-- ============================================================
-- 195_purchase_order_line_received.sql — lot G du plan correctif (vague V3)
--
-- AUD-G06 (G19 de la liste blanche PostgREST) : le MRP lisait
-- purchase_order_lines.quantity_received, colonne inexistante — la requête était
-- refusée et les en-cours d'achat étaient surestimés (tout le commandé passait
-- pour non reçu).
--
-- Colonne calculée PostgREST (fonction sur le type ligne, sélectionnable comme
-- une colonne) : le reçu d'une ligne se lit sur les réceptions de la commande
-- (statut « received » ou « partial »), article par article. Si plusieurs lignes
-- de la commande portent le même article, le reçu les solde dans l'ordre.
-- Aucune donnée dupliquée à maintenir.
-- ============================================================
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
    SELECT COALESCE(sum(quantity), 0) AS q
    FROM purchase_order_lines
    WHERE purchase_order_id = pol.purchase_order_id AND tenant_id = pol.tenant_id
      AND product_id IS NOT DISTINCT FROM pol.product_id AND id < pol.id
  )
  SELECT GREATEST(LEAST(COALESCE(pol.quantity, 0), recu.q - avant.q), 0) FROM recu, avant
$$;
COMMENT ON FUNCTION quantity_received(purchase_order_lines) IS
  'AUD-G06 — quantité reçue d''une ligne de commande fournisseur (colonne calculée PostgREST)';
GRANT EXECUTE ON FUNCTION quantity_received(purchase_order_lines) TO authenticated;

-- Réception partielle : update_po_status_on_receipt passe la commande en « partial »,
-- statut que la contrainte refusait — valider une réception qui ne solde pas la
-- commande échouait (prouvé par G06).
ALTER TABLE purchase_orders DROP CONSTRAINT IF EXISTS purchase_orders_status_check;
ALTER TABLE purchase_orders ADD CONSTRAINT purchase_orders_status_check
  CHECK (status IN ('draft', 'confirmed', 'partial', 'received', 'cancelled'));
