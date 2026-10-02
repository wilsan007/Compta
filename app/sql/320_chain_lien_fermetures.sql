-- ============================================================
-- 320_chain_lien_fermetures.sql — L3 (tranche 1) : LES CHEMINS D'ANNULATION
--   FERMENT LEURS LIENS — et le maillon des réservations regagne son entrée
--
-- Source : le §8 de la 312 (« le geste que les maillons ajouteront (L3) »),
-- l'en-tête de la 319 (« il n'appelle pas le cycle du lien
-- (`chain_lien_fermer`) sur le chemin d'annulation. Aucun maillon ne le fait
-- encore — c'est le reste de L3 ») et
-- doc/audit/INVENTAIRE-CHAINAGES-L1-TRANCHE4-2026-09-30.md (§5, troisième
-- limite : « la réception de marchandise est TRACÉE … les neuf autres sont
-- des RPC »).
--
-- L'ÉTAT D'ENTRÉE, MESURÉ. La 312 a donné au lien un cycle de vie
-- (`actif` → `remplace` | `rompu`, avec date, motif et auteur), rendu l'index
-- d'idempotence PARTIEL et fait redevenir VRAI `chain_avant` après une
-- fermeture. Le prérequis est donc en place — et RIEN ne l'utilise encore.
-- Mesure du 30/09/2026, sur la base compilée : deux fonctions seulement
-- mentionnent `chain_lien_fermer` dans leur corps, et ce sont les deux portes
-- de la 312 elle-même (`chain_lien_remplacer`, `chain_lien_rompre`). Aucun
-- maillon métier ne ferme, donc. La conséquence est un mensonge silencieux, et
-- il est nommé :
--   * une commande annulée garde ses liens `actif` alors que ses réservations
--     sont libérées (STK-02c) — la vue chaîne (L6) lirait « effet intact » sur
--     un effet retiré, et `chain_integrity_ok` (M-03) dirait vrai ;
--   * un bon de livraison annulé garde son lien actif alors que sa sortie de
--     stock est contrepassee (253) ;
--   * une réception annulée garde son lien actif alors que son entrée de stock
--     est contrepassee (251).
-- Ce fichier ferme les trois.
--
-- CE QUE CE FICHIER FAIT, ET POURQUOI AINSI
--
--   1. TROIS DÉCLENCHEURS COMPAGNONS (`zz_l3_…`) sur les TROIS chemins
--      d'annulation qui CONTRÉPASSENT un effet déjà tracé — donc les trois
--      seuls cas mesurés où « l'effet est retiré » est la vérité :
--        `sales_orders`   confirmée → annulée : les réservations actives sont
--                         libérées par `release_stock_on_sales_order_cancel`
--                         (STK-02c) → les liens `sale.order.reserved` sont rompus ;
--        `delivery_notes` expédié|livré → annulé : la sortie de stock est
--                         contrepassee par `reverse_stock_on_delivery_cancel`
--                         (253) → les liens `sale.delivery.stock_out` sont rompus ;
--        `goods_receipts` reçue|partielle → annulée : l'entrée de stock est
--                         contrepassee par `reverse_stock_on_goods_receipt_cancel`
--                         (251) → les liens `purchase.receipt.stock_in` sont rompus.
--      Un COMPAGNON, et pas une réécriture — la règle de la 310 : un
--      déclencheur additif sur la MÊME table et le MÊME événement, nommé
--      `zz_l3_`, donc trié APRÈS le maillon métier (les 15 déclencheurs de ces
--      trois tables portent un nom qui trie avant `zz_` — mesuré sur
--      `pg_trigger`, suite 320 T08). Elle est disponible ici parce que la
--      fermeture ne décide de RIEN du travail du maillon : elle CONSTATE un
--      effet réversible, là où `chain_avant` (qui décide de produire) exige
--      d'être appelé avant. Les trois corps métier ne sont donc pas touchés :
--      la 251 et la 253 ont mesuré ce qu'elles contrepasent, et les recopier
--      serait le chemin le plus court vers une régression silencieuse.

--   2. LA FERMETURE GLOBALE (`chain_liens_fermer`), pas la ciblée
--      (`chain_lien_rompre`). La 312 écrit la différence, et elle est ici
--      décisive : la ciblée REFUSE quand il n'y a rien à fermer (« son
--      appelant affirme savoir qu'un lien existe »), la globale RAPPORTE le
--      nombre fermé. Or sur un chemin d'annulation, « zéro lien actif » est un
--      état LÉGITIME — un bon de livraison annulé sans avoir jamais été
--      expédié, une réception d'avant la 310, une commande annulée depuis un
--      état où rien n'avait été réservé. Faire échouer l'annulation d'un
--      document ordinaire serait un défaut, pas une garde (suite 320 T06).
--
--   3. LE MAILLON DES RÉSERVATIONS REGAGNE SON ENTRÉE (`chain_avant`). La 311
--      avait dû la retirer — et l'écrire — parce que la clé du socle n'avait
--      pas de TOUR : `chain_avant` retrouvait le lien de la première
--      confirmation, rendait faux, et la reconfirmation d'une commande annulée
--      ne réservait plus rien (rouge mesuré de la suite 230 T04 : réservé = 0
--      au lieu de 10). La 312 a levé exactement cela, et ce fichier tient la
--      promesse qu'elle a écrite. C'est une RÉÉCRITURE de corps — la seule de
--      ce fichier, et sa justification est celle de la 319 : `chain_avant` doit
--      être appelé AVANT l'effet, un compagnon s'exécute APRÈS et ne peut donc
--      pas le porter. Le corps est repris de la 311 à l'identique ; s'y
--      ajoutent l'entrée, par ligne, et le `CONTINUE` qu'elle impose.
--
--   Ce que la fermeture n'écrit PAS : aucune `chain_traces`. Une trace mesure
--   l'exécution d'un maillon (durée, lignes écrites, résultat) ; fermer un lien
--   est un acte de gestion, pas un maillon qui tourne. Le journal du cycle de
--   vie est `domain_events` — un `chain.link_broken` par lien fermé, écrit par
--   la 312 — et `document_links` lui-même (état, date, motif, auteur).
--
-- ⚠️ LIMITES, DITES
--   * La fermeture suit la TRANSITION MÉTIER qui contrepasse, à l'identique de
--     la garde du maillon d'annulation : `confirmée → annulée`,
--     `expédié|livré → annulé`, `reçue|partielle → annulée`. Un chemin qui
--     n'annule PAS le stock (une commande confirmée qui repasserait en
--     brouillon) ne ferme donc rien — et c'est cohérent, l'effet est toujours
--     là. Écrire ce chemin-là est une règle d'état (phase D), pas une
--     fermeture.
--   * Il ne traite pas les NEUF MAILLONS RPC (caisse, paie versée, relevé) —
--     ils se tracent par leur chemin d'appel, pas par un déclencheur — ni le
--     BANC D'ÉPREUVES D1→D8 : ce sont les deux tranches suivantes de L3.
--   * Une fermeture ne survit pas à un rollback : c'est une propriété de
--     PostgreSQL, déjà dite au §5 de la 252, et elle vaut ici comme ailleurs.
--
-- REJOUABLE : déclencheurs par `DROP … IF EXISTS` puis `CREATE`, fonctions par
-- `CREATE OR REPLACE` — aucune donnée n'est écrite par le chargement.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. VENTE — la commande annulée rompt ses liens de réservation
--    Maillon métier : `release_stock_on_sales_order_cancel` (133, rejoué par la
--    188), qui libère les réservations actives de la commande (STK-02c). Le
--    compagnon s'exécute APRÈS lui (son nom trie après le sien) : la garde de
--    transition est recopiée volontairement — ce qui est fermé est exactement
--    ce qui a été contrepasse ; un chemin qui ne libère rien ne ferme rien.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l3_sales_order_cancel_liens()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
BEGIN
  IF NOT (NEW.status = 'cancelled' AND OLD.status = 'confirmed') THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN
    RETURN NULL;
  END IF;

  PERFORM chain_liens_fermer(
    NEW.tenant_id, 'sales_orders', NEW.id, 'rompu',
    format('Commande %s du %s annulée : les réservations tracées sont retirées (règle sale.order.reserved, module stock).',
           NEW.number, COALESCE(to_char(NEW.order_date, 'DD/MM/YYYY'), 'sans date')));

  RETURN NULL;
END $maillon$;

COMMENT ON FUNCTION public.chain_l3_sales_order_cancel_liens() IS
  'L3 (320) : l''annulation d''une commande confirmée ROMPT ses liens de réservation (sale.order.reserved) — l''effet est retiré par le métier (STK-02c), le lien le dit. Fermeture globale : zéro lien actif est un état légitime.';

DROP TRIGGER IF EXISTS zz_l3_sales_order_cancel_liens ON sales_orders;
CREATE TRIGGER zz_l3_sales_order_cancel_liens
  AFTER UPDATE OF status ON sales_orders
  FOR EACH ROW EXECUTE FUNCTION public.chain_l3_sales_order_cancel_liens();
REVOKE ALL ON FUNCTION public.chain_l3_sales_order_cancel_liens() FROM PUBLIC, anon, authenticated;

-- ─────────────────────────────────────────────────────────────
-- 2. VENTE — le bon de livraison annulé rompt son lien de sortie de stock
--    Maillon métier : `reverse_stock_on_delivery_cancel` (253), qui écrit la
--    sortie MIRROIR (`reference_type = 'delivery_note_cancel'`) et son écriture
--    au journal ST. L'écriture d'origine reste intacte — contrepassation,
--    jamais réécriture — et le lien de la sortie d'origine est donc rompu.
--    ⚠️ La RÉEXPÉDITION d'un BL annulé reste refusée par le métier (M-06) : ce
--    n'est pas le chaînage qui l'interdit, et la suite le mesure (T04).
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l3_delivery_cancel_liens()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
BEGIN
  IF NOT (NEW.status = 'cancelled' AND OLD.status IN ('shipped', 'delivered')) THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN
    RETURN NULL;
  END IF;

  PERFORM chain_liens_fermer(
    NEW.tenant_id, 'delivery_notes', NEW.id, 'rompu',
    format('Bon de livraison %s du %s annulé : la sortie de stock tracée est contrepassee (règle sale.delivery.stock_out, module stock).',
           NEW.number, COALESCE(to_char(NEW.delivery_date, 'DD/MM/YYYY'), 'sans date')));

  RETURN NULL;
END $maillon$;

COMMENT ON FUNCTION public.chain_l3_delivery_cancel_liens() IS
  'L3 (320) : l''annulation d''un BL expédié ou livré ROMPT ses liens de sortie de stock (sale.delivery.stock_out) — la contrepassation est écrite par la 253, et le lien ne peut plus dire « effet intact ».';

DROP TRIGGER IF EXISTS zz_l3_delivery_cancel_liens ON delivery_notes;
CREATE TRIGGER zz_l3_delivery_cancel_liens
  AFTER UPDATE OF status ON delivery_notes
  FOR EACH ROW EXECUTE FUNCTION public.chain_l3_delivery_cancel_liens();
REVOKE ALL ON FUNCTION public.chain_l3_delivery_cancel_liens() FROM PUBLIC, anon, authenticated;
-- ─────────────────────────────────────────────────────────────
-- 3. ACHAT — la réception annulée rompt son lien d'entrée de stock
--    Maillon métier : `reverse_stock_on_goods_receipt_cancel` (251), qui écrit
--    la sortie MIRROIR (`reference_type = 'goods_receipt_cancel'`). C'est le
--    pendant exact du maillon tracé par la 319 : la réception a été liée PAR
--    LIGNE, l'annulation rompt ces liens — la vue chaîne cesse de présenter
--    une entrée de stock qui n'existe plus.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l3_goods_receipt_cancel_liens()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
BEGIN
  IF NOT (NEW.status = 'cancelled' AND OLD.status IN ('received', 'partial')) THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN
    RETURN NULL;
  END IF;

  PERFORM chain_liens_fermer(
    NEW.tenant_id, 'goods_receipts', NEW.id, 'rompu',
    format('Réception %s du %s annulée : l''entrée de stock tracée est contrepassee (règle purchase.receipt.stock_in, module stock).',
           NEW.number, COALESCE(to_char(NEW.receipt_date, 'DD/MM/YYYY'), 'sans date')));

  RETURN NULL;
END $maillon$;

COMMENT ON FUNCTION public.chain_l3_goods_receipt_cancel_liens() IS
  'L3 (320) : l''annulation d''une réception reçue ou partielle ROMPT ses liens d''entrée de stock (purchase.receipt.stock_in) — posés par ligne par la 319 ; la contrepassation est écrite par la 251.';

DROP TRIGGER IF EXISTS zz_l3_goods_receipt_cancel_liens ON goods_receipts;
CREATE TRIGGER zz_l3_goods_receipt_cancel_liens
  AFTER UPDATE OF status ON goods_receipts
  FOR EACH ROW EXECUTE FUNCTION public.chain_l3_goods_receipt_cancel_liens();
REVOKE ALL ON FUNCTION public.chain_l3_goods_receipt_cancel_liens() FROM PUBLIC, anon, authenticated;
-- ─────────────────────────────────────────────────────────────
-- 4. LE MAILLON DES RÉSERVATIONS REGAGNE SON ENTRÉE (`chain_avant`, PAR LIGNE)
--
--    Corps repris de la 311 (lignes 90-177) à l'IDENTIQUE, hormis deux ajouts :
--    l'entrée du maillon par ligne, et le `CONTINUE` qu'elle impose.
--
--    Ce qui a changé, c'est le monde autour, et le commentaire de la 311 le
--    disait déjà : la clé d'idempotence du socle n'avait pas de notion de TOUR,
--    donc `chain_avant` confondait « le même effet REJOUÉ » (ne rien produire)
--    et « le même effet LÉGITIMEMENT REPRODUIT après annulation » (produire).
--    Mesure de ce défaut : la suite 230 T04 a rougi, réservé = 0 au lieu de 10.
--    La 312 a donné le tour ; la 320 ferme le lien au moment de l'annulation.
--    Les deux ensemble rendent l'entrée vraie : après annulation, le lien est
--    `rompu`, donc `chain_deja_fait` rend faux, donc `chain_avant` rend vrai et
--    la reconfirmation RE-RÉSERVE — au tour 2, sans réécrire l'historique.
--
--    ⚠️ UNE CONSÉQUENCE MESURÉE, ET ELLE EST UNE AMÉLIORATION (`320 T03`) :
--    une commande confirmée qui repasserait en brouillon puis serait
--    reconfirmée ne réservait pas deux fois auparavant (`link_documents`
--    mettait à jour le lien, mais le maillon INSÉRAIT une seconde réservation —
--    la quantité réservée doublait, mesuré). L'entrée l'empêche : l'effet est
--    déjà produit et son lien est actif, donc le maillon passe la ligne.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION reserve_stock_on_sales_order_confirm()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_line RECORD;
  v_warehouse_id UUID;
  v_reservation UUID;
  v_debut  timestamptz := clock_timestamp();
  v_lignes integer := 0;
  v_tid UUID := NEW.tenant_id;
BEGIN
  IF NEW.status = 'confirmed' AND OLD.status IS DISTINCT FROM 'confirmed' THEN
    FOR v_line IN SELECT * FROM sales_order_lines WHERE sales_order_id = NEW.id AND tenant_id = v_tid AND quantity > 0 LOOP
      -- L3 (320) : l'ENTRÉE du maillon, par ligne de commande. Le maillon
      -- saute la ligne quand l'effet est DÉJÀ produit et son lien ACTIF : c'est
      -- le rejeu, et il ne doit rien faire. Après une annulation le lien a été
      -- rompu par le compagnon de la 320 — `chain_avant` rend alors vrai, et la
      -- réservation est reproduite au tour suivant.
      IF NOT chain_avant(v_tid, 'sales_orders', 'confirmed', 'sale.order.reserved',
                         'sales_orders', NEW.id, v_line.id,
                         format('Commande %s du %s : la réservation de l''article %s n''a pas été produite (règle sale.order.reserved, module stock).',
                                NEW.number, COALESCE(to_char(NEW.order_date, 'DD/MM/YYYY'), 'sans date'),
                                v_line.product_id)) THEN
        CONTINUE;
      END IF;

      -- STK-02 : la ligne de commande ne porte pas de dépôt : choisir celui qui a le plus de disponible
      SELECT sq.warehouse_id INTO v_warehouse_id
      FROM stock_quantities sq
      WHERE sq.tenant_id = v_tid AND sq.product_id = v_line.product_id
      ORDER BY (COALESCE(sq.quantity, 0) - COALESCE(sq.reserved_quantity, 0)) DESC, sq.warehouse_id
      LIMIT 1;

      -- S-05/S-07 : un article sans ligne de dépôt (stock d'avant la 241) ne
      -- doit pas produire une réservation sans dépôt, que la sortie ne pourrait
      -- pas suivre
      IF v_warehouse_id IS NULL THEN
        v_warehouse_id := resolve_default_warehouse(v_tid);
      END IF;
-- Créer la réservation avec warehouse_id
      INSERT INTO stock_reservations (
        tenant_id, product_id, warehouse_id, quantity,
        reserved_by, reference_id, reference_type, status
      ) VALUES (
        v_tid, v_line.product_id, v_warehouse_id, v_line.quantity,
        'sales_order', NEW.id, 'sales_order', 'active'
      )
      RETURNING id INTO v_reservation;

      -- STK-02 : Mettre à jour la quantité réservée uniquement pour le dépôt concerné
      IF v_warehouse_id IS NOT NULL THEN
        UPDATE stock_quantities
        SET reserved_quantity = reserved_quantity + v_line.quantity,
          updated_at = now()
        WHERE tenant_id = v_tid
          AND product_id = v_line.product_id
          AND warehouse_id = v_warehouse_id;
      END IF;

      -- LE LIEN : la ligne de commande → LA réservation qu'elle a fait naître.
      -- `created_from` : le vocabulaire de `link_type` est FERMÉ (huit valeurs,
      -- 252 / M-11) et la contrainte a refusé `reserved_by`, que la 311 avait
      -- d'abord écrit — mesuré. Une réservation naît d'une commande : c'est
      -- `created_from` qui le dit.
      PERFORM link_documents(v_tid, 'sales_orders', NEW.id, 'stock_reservations', v_reservation,
                             'sale.order.reserved', 'created_from',
                             jsonb_build_object('quantity', v_line.quantity, 'warehouse_id', v_warehouse_id),
                             v_line.id, NULL);
      v_lignes := v_lignes + 1;
    END LOOP;

    -- Un seul événement et une seule mesure pour le document : le détail est
    -- dans les liens, pas dans dix lignes de trace. `v_lignes` ne compte plus
    -- les lignes SAUTÉES par l'entrée — un maillon rejoué ne mesure rien.
    IF v_lignes > 0 THEN
      PERFORM emit_domain_event(v_tid, 'sales_orders.confirmed', 'sales_orders', NEW.id,
                                jsonb_build_object('reservations', v_lignes), NULL);
      PERFORM chain_apres(v_tid, 'sale.order.reserved', 'sales_orders', NEW.id,
                          v_debut, v_lignes, 'applique', NULL, NULL, NULL);
    END IF;
  END IF;

  RETURN NEW;
END $$;

COMMENT ON FUNCTION public.reserve_stock_on_sales_order_confirm() IS
  'L1 (311), entrée ajoutée par L3 (320) : commande confirmée → une réservation par ligne de commande, tracée par ligne (sale.order.reserved). Le maillon appelle son entrée (`chain_avant`) : le rejeu ne double pas la réservation, et l''annulation — qui rompt les liens — rend la reproduction légitime au tour suivant.';


-- ─────────────────────────────────────────────────────────────
-- 5. Droits — un déclencheur n'est pas une RPC (leçon de la 228)
--    `reserve_stock_on_sales_order_confirm` est une fonction de déclencheur
--    réécrite : `CREATE OR REPLACE` conserve ses droits, il n'y a donc rien à
--    révoquer pour elle. Les TROIS fonctions neuves, si — elles sont créées
--    avec le droit PUBLIC par défaut, et `check_anon_grants.sql` est le
--    garde-fou du jour où une migration l'oubliera (les trois `REVOKE` sont
--    posés au-dessus, avec leur déclencheur, comme le fait la 312).
-- ─────────────────────────────────────────────────────────────
