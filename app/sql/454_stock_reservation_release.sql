-- ═══════════════════════════════════════════════════════════════════════════
-- 454 — Partie 5 : libérer une réservation à la main, sans la supprimer
-- ═══════════════════════════════════════════════════════════════════════════
--
-- L'écran des réservations (`releaseStockReservation`, src/lib/queries/stock.ts)
-- faisait `DELETE FROM stock_reservations`. Deux défauts :
--   1. la réservation est l'AVAL d'un lien actif (commande → réservation) :
--      la garde 453 refuse désormais cette suppression ;
--   2. mesuré le 02/10 : `stock_reservations` n'a AUCUN déclencheur — la
--      suppression ne rendait pas `stock_quantities.reserved_quantity`, le
--      stock restait bloqué pour une réservation disparue.
--
-- `release_stock_reservation(id)` fait ce que fait déjà l'annulation d'une
-- commande (`_release_sales_order_reservation`, `release_stock_on_sales_order_cancel`) :
-- décrémente la quantité réservée au dépôt, passe la réservation à `released`,
-- et FERME le lien qui la tient (rompu, motif). Rien n'est supprimé.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.release_stock_reservation(p_reservation_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_tid uuid := current_tenant_id();
  v_res stock_reservations%ROWTYPE;
  r     record;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucune société active : une réservation se libère dans le contexte d''une société.'
      USING ERRCODE = '42501';
  END IF;
  IF NOT can_perform('stock_reservations', 'update') THEN
    RAISE EXCEPTION 'Votre rôle ne permet pas de libérer une réservation.'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_res
  FROM stock_reservations
  WHERE id = p_reservation_id AND tenant_id = v_tid
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Réservation introuvable dans cette société.' USING ERRCODE = 'P0002';
  END IF;
  IF v_res.status <> 'active' THEN
    RAISE EXCEPTION 'Cette réservation n''est plus active (statut : %).', v_res.status
      USING ERRCODE = '22023';
  END IF;

  UPDATE stock_quantities
     SET reserved_quantity = GREATEST(0, COALESCE(reserved_quantity, 0) - v_res.quantity),
         updated_at = now()
   WHERE tenant_id = v_tid
     AND product_id = v_res.product_id
     AND (v_res.warehouse_id IS NULL OR warehouse_id = v_res.warehouse_id);

  UPDATE stock_reservations
     SET status = 'released', updated_at = now()
   WHERE id = p_reservation_id AND tenant_id = v_tid;

  FOR r IN
    SELECT amont_type, amont_id, effet, amont_ligne_id
    FROM document_links
    WHERE tenant_id = v_tid
      AND aval_type = 'stock_reservations'
      AND aval_id = p_reservation_id
      AND etat = 'actif'
  LOOP
    PERFORM chain_lien_fermer(v_tid, r.amont_type, r.amont_id, r.effet, r.amont_ligne_id,
      'rompu', 'Réservation libérée à la main (écran des réservations) : la quantité réservée est rendue.');
  END LOOP;
END $fn$;

COMMENT ON FUNCTION public.release_stock_reservation(uuid) IS
  '454 : libère une réservation ACTIVE de la société courante — quantité réservée rendue au dépôt, statut released, lien commande → réservation fermé (rompu). Contrôle le rôle (can_perform stock_reservations/update). Remplace le DELETE de l''écran.';

REVOKE ALL ON FUNCTION public.release_stock_reservation(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.release_stock_reservation(uuid) TO authenticated;
