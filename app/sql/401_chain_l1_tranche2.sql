-- ============================================================
-- 311_chain_l1_tranche2.sql — L1 (tranche 2) : les effets à N LIGNES et les
--   maillons multi-effets entrent dans la chaîne
--
-- Source : doc/audit/PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md (lot L1) et
-- doc/audit/INVENTAIRE-CHAINAGES-L1-2026-09-29.md (§1, maillons 5 à 11 :
-- « N lignes pour un document » et « multi-effets »).
--
-- ÉTAT D'ENTRÉE. La tranche 1 (310) a tracé SIX effets dont l'aval est UN
-- document, par des déclencheurs compagnons (`zz_l1_…`). Les maillons qui
-- restaient ont été écartés pour une raison précise, écrite à l'inventaire :
-- leur effet produit **N lignes** (une par ligne de document) pour **un**
-- document amont, et la correspondance ligne → ligne n'est **pas déductible
-- de l'extérieur** — le compagnon ne peut pas savoir quelle ligne a produit
-- quelle ligne. Le socle, lui, porte la granularité qui le permet :
-- `amont_ligne_id` (M-09), qui **fait partie de la clé unique**.
--
-- LA DOCTRINE DE LA TRANCHE 2 — deux règles, et une nuance mesurée
--
--   1. **L'amont a des lignes → on réécrit le maillon, et le lien est par
--      ligne.** `amont_ligne_id` = la ligne du document amont, `aval_id` = la
--      ligne aval qu'elle a fait naître. Le compagnon ne pouvait pas connaître
--      cette correspondance : c'est la seule raison qui justifie ici de
--      réécrire un corps de maillon.
--   1 bis. **L'ENTRÉE du maillon (`chain_avant`) n'est posée que si le maillon
--      est à sens unique.** Le socle identifie un effet par
--      (société, amont, effet, ligne) — il n'a **pas de notion de tour** : il ne
--      distingue pas « le même effet rejoué » de « le même effet légitimement
--      reproduit après une annulation ». Or deux flux légitimes existent :
--        * une commande **annulée puis reconfirmée** doit re-réserver — la suite
--          `230` (T04) le prouve, et la première version de ce fichier l'a cassé
--          (mesuré : réservé = 0 au lieu de 10) ;
--        * une expédition sous-traitée peut repasser `returned → shipped`
--          (`st_shipments.status`), et la faire sauter en silence serait un
--          TROU, pas une protection.
--      Sur ces maillons, la garde reste donc celle du métier (transition d'état
--      ou absence de garde, telle quelle), et c'est le **lien** qui reste
--      unique : `link_documents` met à jour son aval au lieu d'empiler.
--      **Trouvaille pour le lot L3 / la phase D** : un cycle de vie du lien
--      (le lien est remplacé, pas réécrit) est la vraie réponse ; elle ne se
--      devine pas dans une migration de traçage.
--      Les maillons **à sens unique** — le bon de livraison, qui REFUSE d'être
--      réexpédié sans contre-passation (`M-06`) — gardent, eux, `chain_avant`,
--      et le mode `refuse` bloque alors l'opération **avant** tout effet (T05).
--   2. **L'amont n'a pas de lignes → le lien reste au niveau du document**, vers
--      l'aval **unique** quand il existe, et le `payload` porte le décompte de
--      ce qui n'est pas lié. On n'invente pas de ligne.
--
--   4 maillons réécrits (leurs lignes sont réelles et désignables) :
--     `reserve_stock_on_sales_order_confirm`  → stock_reservations
--     `create_stock_out_on_delivery`          → stock_movements
--     `st_shipment_stock_out`                 → stock_movements
--     `st_receipt_stock_in`                   → stock_movements
--   3 compagnons (l'aval est unique et résoluble) :
--     `pos_sessions` (clôture)  → journal_entries   pos.session.closure
--     `bank_transactions`       → customer_payments treasury.bank_transaction.reconciled
--     `manufacturing_orders`    → journal_entries   production.order.generated_entry
--
-- DEUX FAITS MESURÉS AU MOMENT D'ÉCRIRE CES LIGNES, ET QUI CHANGENT LE PLAN
--
--   * **`post_pos_session_on_close` (187) n'est plus atteignable** : aucune
--     entrée de `pg_trigger` ne pointe sur cette fonction (`SELECT … FROM
--     pg_trigger WHERE tgfoid = 'post_pos_session_on_close'::regproc` → 0 ligne).
--     C'est `post_pos_session_on_close_multi` (281), déclenché `BEFORE UPDATE`
--     sur `pos_sessions`, qui clôt les sessions. Le maillon nommé « artère » au
--     référentiel est donc du **code mort** : la tranche 2 instrumente celui qui
--     vit, et **inscrit le constat** ici plutôt que de tracer un fantôme. (Sa
--     clôture est aussi plus complète : ventilation de TVA par taux, un débit
--     par moyen de paiement.)
--   * **Les besoins d'un ordre de fabrication sont CALCULÉS**
--     (`manufacturing_requirements`, 302:69) : il n'existe pas de table de
--     composants d'OF. Les mouvements de sortie de l'OF n'ont donc **pas de
--     ligne amont à désigner** — leur lien reste au niveau de l'OF (règle 2).
--
-- CE QUE CE FICHIER NE FAIT PAS
--   * il ne déclare aucun contrat d'effet (lot L7) : en mode `observe`, chaque
--     exécution trace `tolere` (contrat absent) puis `applique` ;
--   * il ne touche pas aux maillons dont la correspondance demande une colonne
--     nouvelle (`stock_movements` d'une livraison partielle : voir §1 de
--     l'inventaire) — le constat est écrit, le travail est instruit ;
--   * il ne mesure toujours pas les budgets (porte G6, lot L2).
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- T-1 — Commande confirmée → une réservation PAR LIGNE
--   Maillon métier : déclencheur `reserve_stock_on_so_confirm`
--   (AFTER UPDATE ON sales_orders). Corps réécrit : l'entrée et le lien
--   portent la ligne de commande (`amont_ligne_id`, M-09).
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
      -- L1 (311) : POURQUOI CE MAILLON N'APPELLE PAS `chain_avant`.
      -- Une commande peut être **annulée puis reconfirmée**, et elle DOIT alors
      -- re-réserver : la suite 230 (T04) le prouve, et la première version de ce
      -- fichier l'a cassé — mesuré : `chain_avant` retrouvait le lien de la
      -- première confirmation, rendait false, et la boucle sautait l'effet
      -- (réservé = 0 au lieu de 10). La clé d'idempotence du socle —
      -- (société, amont, effet, ligne) — n'a pas de notion de TOUR : elle ne
      -- distingue pas « le même effet rejoué » de « le même effet légitimement
      -- reproduit après annulation ». La garde reste donc celle du maillon (la
      -- transition d'état), et le lien est MIS À JOUR (`ON CONFLICT` du socle) :
      -- il pointe toujours la réservation courante, et il reste unique par ligne.
      -- C'est une trouvaille pour le lot L3 / la phase D (cycle de vie du lien),
      -- pas une commodité : elle est écrite ici et dans la preuve de la vague.

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
      -- 252 / M-11) et la contrainte a refusé `reserved_by`, que ce fichier
      -- avait d'abord écrit — mesuré. Une réservation naît d'une commande :
      -- c'est `created_from` qui le dit.
      PERFORM link_documents(v_tid, 'sales_orders', NEW.id, 'stock_reservations', v_reservation,
                             'sale.order.reserved', 'created_from',
                             jsonb_build_object('quantity', v_line.quantity, 'warehouse_id', v_warehouse_id),
                             v_line.id, NULL);
      v_lignes := v_lignes + 1;
    END LOOP;

    -- Un seul événement et une seule mesure pour le document : le détail est
    -- dans les liens, pas dans dix lignes de trace.
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
  'L1 (311) : commande confirmée → une réservation par ligne de commande, tracée par ligne (sale.order.reserved).';

-- ─────────────────────────────────────────────────────────────
-- T-2 — Bon de livraison expédié → une sortie de stock PAR LIGNE
--   Maillon métier : `create_stock_out_on_delivery` (AFTER UPDATE ON
--   delivery_notes). C'est l'archétype du plan (§3.2 : `sale.delivery.stock_out`)
--   et la règle `R-006` du référentiel : la sortie se fait « par dépôt ».
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION create_stock_out_on_delivery()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_line RECORD;
  v_deja int;
  v_wh uuid;
  v_libere numeric;
  v_mouvement uuid;
  v_debut  timestamptz := clock_timestamp();
  v_lignes integer := 0;
BEGIN
  -- STK-01 : Déclencher uniquement au passage de draft/confirmed → shipped
  -- (pas sur shipped → delivered, qui ne doit pas re-décrémenter le stock)
  IF OLD.status NOT IN ('shipped', 'delivered') AND NEW.status = 'shipped' THEN

    -- M-06 : un BL annulé puis réexpédié retombait sur l'index unique. Le stock
    -- était sauf, le message était un code d'erreur PostgreSQL.
    SELECT count(*) INTO v_deja
    FROM stock_movements
    WHERE tenant_id = NEW.tenant_id AND reference_type = 'delivery_note' AND reference_id = NEW.id;

    IF v_deja > 0 THEN
      RAISE EXCEPTION 'BL % déjà expédié : sa sortie de stock existe. Contrepasser avant de réexpédier.', NEW.number
        USING ERRCODE = '23505';
    END IF;

    FOR v_line IN
      SELECT * FROM delivery_note_lines
      WHERE delivery_note_id = NEW.id AND tenant_id = NEW.tenant_id AND quantity > 0
    LOOP
      -- L1 (311) : l'entrée du maillon, PAR LIGNE de bon de livraison.
      IF NOT chain_avant(NEW.tenant_id, 'delivery_notes', 'shipped', 'sale.delivery.stock_out',
                         'delivery_notes', NEW.id, v_line.id,
                         format('Bon de livraison %s du %s : la sortie de stock de l''article %s n''a pas été produite (règle sale.delivery.stock_out, module stock).',
                                NEW.number, to_char(NEW.delivery_date, 'DD/MM/YYYY'), v_line.product_id))
      THEN
        CONTINUE;
      END IF;

      -- S-05 : le dépôt de la sortie — réservation de la commande, dépôt qui
      -- peut servir la ligne, dépôt de la société
      v_wh := resolve_delivery_warehouse(NEW.tenant_id, NEW.sales_order_id, v_line.product_id, v_line.quantity);

      INSERT INTO stock_movements (
        tenant_id, product_id, warehouse_id, movement_type, type, quantity,
        lot_id, serial_id,
        reference, reference_type, reference_id, date, movement_date, notes
      ) VALUES (
        NEW.tenant_id, v_line.product_id, v_wh, 'out', 'out', v_line.quantity,
        v_line.lot_id, v_line.serial_id,
        'BL-' || NEW.number, 'delivery_note', NEW.id, NEW.delivery_date, NEW.delivery_date, v_line.description
      )
      RETURNING id INTO v_mouvement;

      -- S-07 : la marchandise est partie, la réservation de la commande l'est
      -- aussi, à hauteur de la ligne livrée
      v_libere := _release_sales_order_reservation(NEW.tenant_id, NEW.sales_order_id, v_line.product_id, v_line.quantity);

      -- LE LIEN : la ligne du BL → LE mouvement qu'elle a produit (M-09).
      PERFORM link_documents(NEW.tenant_id, 'delivery_notes', NEW.id, 'stock_movements', v_mouvement,
                             'sale.delivery.stock_out', 'delivered_by',
                             jsonb_build_object('quantity', v_line.quantity, 'warehouse_id', v_wh,
                                                'reference', 'BL-' || NEW.number, 'reservation_liberee', v_libere),
                             v_line.id, NULL);
      v_lignes := v_lignes + 1;
    END LOOP;

    IF v_lignes > 0 THEN
      PERFORM emit_domain_event(NEW.tenant_id, 'delivery_notes.shipped', 'delivery_notes', NEW.id,
                                jsonb_build_object('mouvements', v_lignes, 'sales_order_id', NEW.sales_order_id), NULL);
      PERFORM chain_apres(NEW.tenant_id, 'sale.delivery.stock_out', 'delivery_notes', NEW.id,
                          v_debut, v_lignes, 'applique', NULL, NULL, NULL);
    END IF;
  END IF;
  RETURN NEW;
END $$;

COMMENT ON FUNCTION public.create_stock_out_on_delivery() IS
  'L1 (311) : BL expédié → une sortie de stock par ligne, tracée par ligne (sale.delivery.stock_out). Règle R-006.';

-- ─────────────────────────────────────────────────────────────
-- T-3 — Expédition chez le sous-traitant → une sortie PAR LIGNE
--   Maillon métier : `st_shipment_stock_out_trigger` (AFTER UPDATE ON
--   st_shipments). Référentiel A.3 : un des seize maillons les plus fragiles
--   (3/7 — filtre de société présent, mais ni garde d'idempotence, ni trace de
--   référence, ni erreur gérée, ni refus explicite).
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION st_shipment_stock_out()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_line record;
  v_product_id uuid;
  v_unit_cost numeric;
  v_mouvement uuid;
  v_debut timestamptz := clock_timestamp();
  v_lignes integer := 0;
  v_tid uuid := NEW.tenant_id;
BEGIN
  IF NEW.status <> 'shipped' THEN
    RETURN NEW;
  END IF;

  -- Pour chaque ligne d'expédition, créer un mouvement de stock sortant
  FOR v_line IN
    SELECT * FROM st_shipment_lines
    WHERE st_shipment_id = NEW.id AND tenant_id = v_tid
  LOOP
    -- Récupérer le produit et le coût unitaire
    SELECT product_id INTO v_product_id
    FROM st_orders
    WHERE id = NEW.st_order_id AND tenant_id = v_tid;

    SELECT unit_cost INTO v_unit_cost
    FROM stock_quantities
    WHERE tenant_id = v_tid AND product_id = v_product_id
    LIMIT 1;

    -- L1 (311) : pas d'appel à `chain_avant` ici, et la raison est mesurée.
    -- Ce maillon n'a AUCUNE garde à sens unique : `st_shipments.status` admet
    -- `pending → shipped → returned → shipped`. Appeler `chain_avant` ferait
    -- sauter silencieusement la sortie de stock d'une réexpédition légitime —
    -- un trou, pas une protection. Le lien suit donc le dernier mouvement
    -- (`ON CONFLICT` du socle met à jour son aval), et la question « quelle
    -- reprise est un rejeu, laquelle est un nouveau tour ? » revient au lot L3
    -- et à la règle métier de la sous-traitance — elle ne se devine pas ici.

    -- Mouvement de stock 'out' vers le sous-traitant
    INSERT INTO stock_movements (
      tenant_id, product_id, warehouse_id, movement_type,
      quantity, unit_cost, reference, reference_type, movement_date, notes, created_at
    ) VALUES (
      v_tid, v_product_id, NULL, 'out',
      v_line.quantity, COALESCE(v_unit_cost, 0),
      'ST-' || NEW.number, 'manual', now(),
      'Expédition sous-traitance', now()
    )
    RETURNING id INTO v_mouvement;

    -- Décrémenter le stock physique
    UPDATE stock_quantities
    SET quantity = quantity - v_line.quantity, updated_at = now()
    WHERE tenant_id = v_tid AND product_id = v_product_id;

    -- LE LIEN : la ligne d'expédition → le mouvement qu'elle a produit (M-09).
    PERFORM link_documents(v_tid, 'st_shipments', NEW.id, 'stock_movements', v_mouvement,
                           'subcontracting.shipment.stock_out', 'delivered_by',
                           jsonb_build_object('quantity', v_line.quantity,
                                              'unit_cost', COALESCE(v_unit_cost, 0),
                                              'reference', 'ST-' || NEW.number),
                           v_line.id, NULL);
    v_lignes := v_lignes + 1;
  END LOOP;

  IF v_lignes > 0 THEN
    PERFORM emit_domain_event(v_tid, 'st_shipments.shipped', 'st_shipments', NEW.id,
                              jsonb_build_object('mouvements', v_lignes, 'st_order_id', NEW.st_order_id), NULL);
    PERFORM chain_apres(v_tid, 'subcontracting.shipment.stock_out', 'st_shipments', NEW.id,
                        v_debut, v_lignes, 'applique', NULL, NULL, NULL);
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.st_shipment_stock_out() IS
  'L1 (311) : expédition sous-traitance → une sortie de stock par ligne, tracée par ligne (subcontracting.shipment.stock_out).';

-- ─────────────────────────────────────────────────────────────
-- T-4 — Réception du sous-traitant → une entrée PAR LIGNE
--   Maillon métier : `st_receipt_stock_in_trigger` (AFTER UPDATE ON st_receipts).
--   Le coût (matière + façon) est écrit dans le mouvement : le lien le porte
--   aussi, pour que l'analyse d'impact (M-12) puisse chiffrer un retour arrière.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION st_receipt_stock_in()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_line record;
  v_product_id uuid;
  v_material_cost numeric := 0;
  v_subcontracting_cost numeric := 0;
  v_total_cost numeric;
  v_mouvement uuid;
  v_debut timestamptz := clock_timestamp();
  v_lignes integer := 0;
  v_tid uuid := NEW.tenant_id;
  v_order record;
BEGIN
  IF NEW.status <> 'received' THEN
    RETURN NEW;
  END IF;

  -- Récupérer l'ordre de sous-traitance
  SELECT * INTO v_order FROM st_orders WHERE id = NEW.st_order_id AND tenant_id = v_tid;

  FOR v_line IN
    SELECT * FROM st_receipt_lines
    WHERE st_receipt_id = NEW.id AND tenant_id = v_tid
  LOOP
    -- Coût matière = coût unitaire du stock × quantité reçue
    SELECT unit_cost INTO v_material_cost
    FROM stock_quantities
    WHERE tenant_id = v_tid AND product_id = v_order.product_id
    LIMIT 1;

    -- Coût façon = coût de l'opération sous-traitée
    v_subcontracting_cost := COALESCE(v_order.unit_price, 0) * v_line.quantity;

    -- Coût total = matière + façon
    v_total_cost := COALESCE(v_material_cost, 0) + v_subcontracting_cost;
    v_product_id := v_order.product_id;

    -- L1 (311) : pas d'appel à `chain_avant` — même raison qu'à l'expédition :
    -- la réception admet `pending → received → partial → received`, et bloquer
    -- la reprise ferait disparaître une entrée en stock légitime sans un mot.
    -- Le lien suit le dernier mouvement ; l'idempotence à sens unique attend la
    -- règle métier (L3 / phase D).

    -- Mouvement de stock 'in' valorisé
    INSERT INTO stock_movements (
      tenant_id, product_id, warehouse_id, movement_type,
      quantity, unit_cost, reference, reference_type, movement_date, notes, created_at
    ) VALUES (
      v_tid, v_product_id, NULL, 'in',
      v_line.quantity, v_total_cost / v_line.quantity,
      'ST-REC-' || NEW.number, 'goods_receipt', now(),
      'Réception sous-traitance', now()
    )
    RETURNING id INTO v_mouvement;

    -- Incrémenter le stock
    UPDATE stock_quantities
    SET quantity = quantity + v_line.quantity,
      unit_cost = v_total_cost / v_line.quantity,
      updated_at = now()
    WHERE tenant_id = v_tid AND product_id = v_product_id;

    -- LE LIEN : la ligne de réception → le mouvement qu'elle a produit (M-09).
    PERFORM link_documents(v_tid, 'st_receipts', NEW.id, 'stock_movements', v_mouvement,
                           'subcontracting.receipt.stock_in', 'delivered_by',
                           jsonb_build_object('quantity', v_line.quantity,
                                              'cost_material', COALESCE(v_material_cost, 0),
                                              'cost_subcontracting', v_subcontracting_cost,
                                              'reference', 'ST-REC-' || NEW.number),
                           v_line.id, NULL);
    v_lignes := v_lignes + 1;
  END LOOP;

  IF v_lignes > 0 THEN
    PERFORM emit_domain_event(v_tid, 'st_receipts.received', 'st_receipts', NEW.id,
                              jsonb_build_object('mouvements', v_lignes, 'st_order_id', NEW.st_order_id), NULL);
    PERFORM chain_apres(v_tid, 'subcontracting.receipt.stock_in', 'st_receipts', NEW.id,
                        v_debut, v_lignes, 'applique', NULL, NULL, NULL);
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.st_receipt_stock_in() IS
  'L1 (311) : réception sous-traitance → une entrée de stock valorisée par ligne, tracée par ligne (subcontracting.receipt.stock_in).';

-- ═════════════════════════════════════════════════════════════
-- LES TROIS MAILLONS MULTI-EFFETS — par déclencheur compagnon
--
-- Leur aval principal est UN document (l'écriture), résoluble exactement : la
-- réécriture d'un maillon de 150 à 213 lignes n'apporterait rien ici et ferait
-- courir un risque inutile à la caisse, qui est la chaîne la plus complète du
-- produit (référentiel §B.3 : 5/7, `219`). On garde donc la doctrine de la
-- tranche 1 — compagnon `zz_l1_` — pour la partie « un document en produit un ».
--
-- REGLE 2, APPLIQUÉE ET DITE : ce que la caisse agrège PAR PRODUIT (les sorties
-- de stock, `GROUP BY l.product_id, t.warehouse_id`) n'a pas de ligne amont à
-- désigner — la ligne de ticket n'est pas la ligne du mouvement. Ces mouvements
-- ne reçoivent donc PAS de lien ; ils sont **comptés** dans le `payload` du lien
-- du document, et restent navigables par `reference_type = 'pos_session'` et
-- `reference_id` (le chemin qui existe aujourd'hui). Inventer une ligne pour
-- faire joli aurait produit un lien que la vue chaîne n'aurait pas su lire.
-- ═════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- T-5 — Session de caisse clôturée → l'écriture de clôture
--   Maillon métier : `post_pos_session_on_close_multi` (BEFORE UPDATE ON
--   pos_sessions, 281). Il écrit l'écriture `number = 'POS-' || id`.
--   ⚠️ `post_pos_session_on_close` (187), nommé « artère » au référentiel, n'a
--   PLUS aucun déclencheur : mesuré, il est inatteignable. Ce n'est donc pas lui
--   qui est tracé ici, et le constat est inscrit plutôt que masqué.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l1_pos_session_closure()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut  timestamptz := clock_timestamp();
  v_aval   uuid;
  v_mvts   integer := 0;
  v_total  numeric := 0;
  v_lignes integer := 0;
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status OR NEW.status IS DISTINCT FROM 'closed' THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- L'aval : l'écriture de clôture, produite par le maillon métier (BEFORE).
  SELECT je.id INTO v_aval
  FROM journal_entries je
  WHERE je.tenant_id = NEW.tenant_id AND je.number = 'POS-' || NEW.id::text
  LIMIT 1;
  IF v_aval IS NULL THEN
    RETURN NULL;
  END IF;

  -- Ce qui n'est PAS lié, et pourquoi (règle 2) : les sorties de stock agrégées.
  SELECT count(*), COALESCE(sum(sm.quantity * sm.unit_cost), 0)
    INTO v_mvts, v_total
  FROM stock_movements sm
  WHERE sm.tenant_id = NEW.tenant_id
    AND sm.reference_type = 'pos_session' AND sm.reference_id = NEW.id;

  IF NOT chain_avant(NEW.tenant_id, 'pos_sessions', 'closed', 'pos.session.closure',
                     'pos_sessions', NEW.id, NULL,
                     format('Session de caisse %s du %s : l''écriture de clôture n''a pas été produite (règle pos.session.closure, module caisse).',
                            COALESCE(NEW.session_number, NEW.id::text), to_char(COALESCE(NEW.closed_at, now()), 'DD/MM/YYYY'))) THEN
    RETURN NULL;
  END IF;

  PERFORM link_documents(NEW.tenant_id, 'pos_sessions', NEW.id, 'journal_entries', v_aval,
                         'pos.session.closure', 'generated_entry',
                         jsonb_build_object('number', 'POS-' || NEW.id::text,
                                            'mouvements_stock', v_mvts,
                                            'cout_mouvements', v_total,
                                            'lien_par_ligne', false));
  v_lignes := v_lignes + 1;

  PERFORM emit_domain_event(NEW.tenant_id, 'pos_sessions.closed', 'pos_sessions', NEW.id,
                            jsonb_build_object('entry_id', v_aval, 'mouvements_stock', v_mvts), NULL);

  PERFORM chain_apres(NEW.tenant_id, 'pos.session.closure', 'pos_sessions', NEW.id,
                      v_debut, v_lignes, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

COMMENT ON FUNCTION public.chain_l1_pos_session_closure() IS
  'L1 (311) : maillon compagnon d''une clôture de caisse — lie la session à son écriture (pos.session.closure) et compte les mouvements de stock non liés (amont sans lignes).';

DROP TRIGGER IF EXISTS zz_l1_pos_session_closure ON pos_sessions;
CREATE TRIGGER zz_l1_pos_session_closure
  AFTER UPDATE ON pos_sessions
  FOR EACH ROW EXECUTE FUNCTION public.chain_l1_pos_session_closure();
REVOKE ALL ON FUNCTION public.chain_l1_pos_session_closure() FROM PUBLIC, anon, authenticated;

-- ─────────────────────────────────────────────────────────────
-- T-6 — Rapprochement bancaire automatique → l'encaissement créé
--   Maillon métier : `auto_reconcile_by_score` (AFTER INSERT ON
--   bank_transactions). Quand un score ≥ 70 est trouvé, il crée UN encaissement
--   dont le numéro est déterministe : `REG-REL-<10 premiers caractères de l'id>`
--   — c'est cette clé qui rend l'aval résoluble de l'extérieur, sans réécrire le
--   maillon. Le lien porte `created_from` (vocabulaire fermé du socle, M-11) :
--   l'encaissement a été **créé à partir de** la ligne bancaire.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l1_bank_reconciliation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut  timestamptz := clock_timestamp();
  v_aval   uuid;
  v_lignes integer := 0;
BEGIN
  -- Le maillon métier n'agit que sur un crédit non rapproché, de montant positif.
  IF NEW.matched IS TRUE OR NEW.type IS DISTINCT FROM 'credit' OR COALESCE(NEW.amount, 0) <= 0 THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT cp.id INTO v_aval
  FROM customer_payments cp
  WHERE cp.tenant_id = NEW.tenant_id
    AND cp.number = 'REG-REL-' || upper(left(replace(NEW.id::text, '-', ''), 10))
  LIMIT 1;
  -- Score < 70 : le maillon n'a produit que des suggestions — rien à lier.
  IF v_aval IS NULL THEN
    RETURN NULL;
  END IF;

  IF NOT chain_avant(NEW.tenant_id, 'bank_transactions', 'reconciled', 'treasury.bank_transaction.reconciled',
                     'bank_transactions', NEW.id, NULL,
                     format('Ligne bancaire %s du %s : l''encaissement rapproché n''a pas été créé (règle treasury.bank_transaction.reconciled, module trésorerie).',
                            COALESCE(NEW.reference, NEW.id::text), to_char(NEW.date, 'DD/MM/YYYY'))) THEN
    RETURN NULL;
  END IF;

  PERFORM link_documents(NEW.tenant_id, 'bank_transactions', NEW.id, 'customer_payments', v_aval,
                         'treasury.bank_transaction.reconciled', 'created_from',
                         jsonb_build_object('amount', NEW.amount, 'reference', NEW.reference,
                                            'date', NEW.date,
                                            'number', 'REG-REL-' || upper(left(replace(NEW.id::text, '-', ''), 10))));
  v_lignes := v_lignes + 1;

  PERFORM emit_domain_event(NEW.tenant_id, 'bank_transactions.reconciled', 'bank_transactions', NEW.id,
                            jsonb_build_object('payment_id', v_aval, 'amount', NEW.amount), NULL);

  PERFORM chain_apres(NEW.tenant_id, 'treasury.bank_transaction.reconciled', 'bank_transactions', NEW.id,
                      v_debut, v_lignes, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

COMMENT ON FUNCTION public.chain_l1_bank_reconciliation() IS
  'L1 (311) : maillon compagnon d''un rapprochement bancaire automatique — lie la ligne bancaire à l''encaissement créé (created_from).';

DROP TRIGGER IF EXISTS zz_l1_bank_reconciliation ON bank_transactions;
CREATE TRIGGER zz_l1_bank_reconciliation
  AFTER INSERT ON bank_transactions
  FOR EACH ROW EXECUTE FUNCTION public.chain_l1_bank_reconciliation();
REVOKE ALL ON FUNCTION public.chain_l1_bank_reconciliation() FROM PUBLIC, anon, authenticated;

-- ─────────────────────────────────────────────────────────────
-- T-7 — Ordre de fabrication terminé → écriture ET entrée du produit fini
--   Maillon métier : `trg_manufacturing_complete_stock` (AFTER UPDATE ON
--   manufacturing_orders) → `create_stock_on_manufacturing_complete` (302,
--   réécrit par W8). Deux effets liés, deux avals **uniques** :
--     * l'écriture `reference = 'JE-OF-' || number` (créée si le coût > 0) ;
--     * le mouvement d'entrée du produit fini (un seul, pour la quantité bonne).
--   Les sorties de composants (N, une par composant de la nomenclature
--   **calculée** — il n'existe pas de table de composants d'OF, mesuré) suivent
--   la règle 2 : comptées dans le `payload`, non liées.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l1_manufacturing_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut    timestamptz := clock_timestamp();
  v_ecriture uuid;
  v_entree   uuid;
  v_sorties  integer := 0;
  v_lignes   integer := 0;
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status OR NEW.status IS DISTINCT FROM 'completed' THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT je.id INTO v_ecriture
  FROM journal_entries je
  WHERE je.tenant_id = NEW.tenant_id AND je.reference = 'JE-OF-' || NEW.number
  LIMIT 1;

  SELECT sm.id INTO v_entree
  FROM stock_movements sm
  WHERE sm.tenant_id = NEW.tenant_id AND sm.reference_type = 'production'
    AND sm.reference_id = NEW.id AND sm.movement_type = 'in'
  LIMIT 1;

  SELECT count(*) INTO v_sorties
  FROM stock_movements sm
  WHERE sm.tenant_id = NEW.tenant_id AND sm.reference_type = 'production'
    AND sm.reference_id = NEW.id AND sm.movement_type = 'out';

  IF v_ecriture IS NULL AND v_entree IS NULL THEN
    RETURN NULL;
  END IF;

  -- E-1 : l'écriture de production (elle reporte le coût, PROD-02).
  IF v_ecriture IS NOT NULL
     AND chain_avant(NEW.tenant_id, 'manufacturing_orders', 'completed', 'production.order.generated_entry',
                     'manufacturing_orders', NEW.id, NULL,
                     format('Ordre de fabrication %s du %s : l''écriture de production n''a pas été produite (règle production.order.generated_entry, module production).',
                            NEW.number, to_char(COALESCE(NEW.end_date, NEW.start_date, CURRENT_DATE), 'DD/MM/YYYY'))) THEN
    PERFORM link_documents(NEW.tenant_id, 'manufacturing_orders', NEW.id, 'journal_entries', v_ecriture,
                           'production.order.generated_entry', 'generated_entry',
                           jsonb_build_object('number', NEW.number, 'reference', 'JE-OF-' || NEW.number,
                                              'quantite_bonne', NEW.qty_produced));
    v_lignes := v_lignes + 1;
  END IF;

  -- E-2 : l'entrée en stock du produit fini (un seul mouvement pour l'OF).
  IF v_entree IS NOT NULL
     AND chain_avant(NEW.tenant_id, 'manufacturing_orders', 'completed', 'production.order.stock_in',
                     'manufacturing_orders', NEW.id, NULL,
                     format('Ordre de fabrication %s du %s : l''entrée en stock du produit fini n''a pas été produite (règle production.order.stock_in, module stock).',
                            NEW.number, to_char(COALESCE(NEW.end_date, NEW.start_date, CURRENT_DATE), 'DD/MM/YYYY'))) THEN
    PERFORM link_documents(NEW.tenant_id, 'manufacturing_orders', NEW.id, 'stock_movements', v_entree,
                           'production.order.stock_in', 'created_from',
                           jsonb_build_object('product_id', NEW.product_id, 'quantity', NEW.qty_produced));
    v_lignes := v_lignes + 1;
  END IF;

  PERFORM emit_domain_event(NEW.tenant_id, 'manufacturing_orders.completed', 'manufacturing_orders', NEW.id,
                            jsonb_build_object('entry_id', v_ecriture, 'entree_id', v_entree,
                                               'sorties_composants', v_sorties, 'lien_par_ligne', false), NULL);

  PERFORM chain_apres(NEW.tenant_id, 'production.order.completion', 'manufacturing_orders', NEW.id,
                      v_debut, v_lignes, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

COMMENT ON FUNCTION public.chain_l1_manufacturing_order() IS
  'L1 (311) : maillon compagnon d''un ordre de fabrication terminé — lie l''écriture de production et l''entrée du produit fini, et compte les sorties de composants (nomenclature calculée, sans ligne amont).';

DROP TRIGGER IF EXISTS zz_l1_manufacturing_order ON manufacturing_orders;
CREATE TRIGGER zz_l1_manufacturing_order
  AFTER UPDATE ON manufacturing_orders
  FOR EACH ROW EXECUTE FUNCTION public.chain_l1_manufacturing_order();
REVOKE ALL ON FUNCTION public.chain_l1_manufacturing_order() FROM PUBLIC, anon, authenticated;






