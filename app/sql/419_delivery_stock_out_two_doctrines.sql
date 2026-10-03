-- 419 — la sortie de stock du bon de livraison : deux doctrines à la fois
-- ═══════════════════════════════════════════════════════════════════════════
--
-- ⚠️ CETTE MIGRATION NAÎT D'UNE FUSION, ET ELLE EXISTE POUR ÇA.
--
-- Six migrations définissent `create_stock_out_on_delivery` : 90, 133, 230,
-- 242, 314 et 401. Elles s'écrasent dans l'ordre numérique, donc c'est la
-- **401** — le chaînage L1, série `4xx` — qui reste en base après la fusion,
-- et elle **écrase** la 314 de la recette.
--
-- LES DEUX DOCTRINES SONT LÉGITIMES ET OPPOSÉES :
--
--   * 314 (recette, B1 ven-005) : la marchandise sort dès qu'elle part,
--     « Expédié » COMME « Livré », et la commande se déclare livrée au moment
--     où la sortie est faite.
--   * 401 (chaînage, STK-01) : on ne décrémente qu'au passage à `shipped`,
--     jamais de `shipped` à `delivered` — sinon un bon expédié puis livré
--     sortirait le stock DEUX FOIS.
--
-- La 401 applique STK-01. Perdue, la sortie de la 314 : mesuré le 02/10 après
-- la fusion, `314` T01/T02/T05b rouges — « sorties=0 (1 attendue) » et
-- « delivery_status=pending (delivered attendu) ». Le stock ne sortait plus du
-- tout à la livraison, et la commande ne se déclarait jamais livrée.
--
-- LE CORRECTIF N'EST PAS DE CHOISIR L'UN DES DEUX. Les deux disent vrai : on ne
-- sort le stock qu'une fois (STK-01 reste maître sur le décompte), mais
-- `delivered` reste un moment où la sortie se produit si elle ne l'a pas été
-- encore (B1), et la commande se déclare livrée dans les DEUX cas.
--
-- Le déclencheur est réécrit ici avec les deux règles réunies, et il garde le
-- traceur `sale.delivery.stock_out` de la 401 : la fusion ne doit pas choisir
-- l'un contre l'autre, elle doit tenir les deux.
-- ============================================================
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
  v_tout_livre boolean;
  v_sortie boolean;
BEGIN
  -- STK-01 (401) + B1 (314) réunis : on déclenche au passage à `shipped`, ET
  -- au passage à `delivered` tant qu'aucune sortie n'a encore été produite.
  -- `shipped` → `delivered` ne déclenche RIEN si le stock est déjà sorti : la
  -- sortie ne se compte qu'une fois (le garde M-06 ci-dessous s'en assure de
  -- toute façon, en refusant un deuxième passage).
  v_sortie := OLD.status NOT IN ('shipped', 'delivered')
             AND NEW.status IN ('shipped', 'delivered');

  IF v_sortie THEN

    -- M-06 : un BL annulé puis réexpédié retombait sur l'index unique. Le stock
    -- était sauf, le message était un code d'erreur PostgreSQL.
    SELECT count(*) INTO v_deja
    FROM stock_movements
    WHERE tenant_id = NEW.tenant_id AND reference_type = 'delivery_note' AND reference_id = NEW.id;

    IF v_deja > 0 THEN
      -- M-06 : la sortie existe déjà. Deux cas, et il faut les distinguer.
      --
      -- * `shipped` → `delivered` : c'est le cas NOMINAL d'un bon expédié puis
      --   livré. On ne rejoue rien, et surtout on ne refuse rien : refuser
      --   ferait échouer toute livraison d'un bon déjà expédié.
      -- * retour d'un BL `cancelled` à `shipped` : c'est une RÉEXPÉDITION.
      --   La sortie existe encore en base — elle a été contrepassée à
      --   l'annulation — et c'est précisément ce que M-06 doit dire en
      --   français plutôt que de laisser remonter un 23505 nu.
      IF NEW.status = 'shipped' AND NEW.status <> OLD.status THEN
        -- Réexpédition : on refuse, et on dit pourquoi.
        RAISE EXCEPTION 'BL % déjà expédié : sa sortie de stock existe. Contrepasser avant de réexpédier.', NEW.number
          USING ERRCODE = '23505';
      END IF;
    ELSE
      FOR v_line IN
        SELECT l.*, p.type AS produit_type
        FROM delivery_note_lines l
        LEFT JOIN products p ON p.id = l.product_id AND p.tenant_id = l.tenant_id
        WHERE l.delivery_note_id = NEW.id AND l.tenant_id = NEW.tenant_id AND l.quantity > 0
      LOOP
        -- L1 (311) : l'entrée du maillon, PAR LIGNE de bon de livraison.
        -- Le traceur passe en premier : une ligne tracée puis sautée
        -- (prestation, ligne libre) reste tracée — c'est la doctrine L1, et
        -- `sans_effet` lui est réservé.
        IF NOT chain_avant(NEW.tenant_id, 'delivery_notes',
                           CASE WHEN NEW.status = 'delivered' THEN 'delivered' ELSE 'shipped' END,
                           'sale.delivery.stock_out',
                           'delivery_notes', NEW.id, v_line.id,
                           format('Bon de livraison %s du %s : la sortie de stock de l''article %s n''a pas été produite (règle sale.delivery.stock_out, module stock).',
                                  NEW.number, to_char(NEW.delivery_date, 'DD/MM/YYYY'), v_line.product_id))
        THEN
          CONTINUE;
        END IF;

        -- B1 (314) : une prestation — ou une ligne libre, sans article — n'a
        -- pas de stock. Elle part sans mouvement, et sans passer par le contrôle
        -- de disponibilité qui refusait tout le bon.
        IF v_line.product_id IS NULL OR COALESCE(v_line.produit_type, 'stock') <> 'stock' THEN
          -- Une prestation n'est pas une anomalie : elle n'a rien à tracer.
          -- `sans_effet` est RÉSERVÉ à l'anomalie (retenue de la 316) ; s'en
          -- servir ici ferait compter une sortie qui n'a pas eu lieu.
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
        ) RETURNING id INTO v_mouvement;

        -- S-07 : la marchandise est partie, la réservation de la commande l'est
        -- aussi, à hauteur de la ligne livrée
        v_libere := _release_sales_order_reservation(NEW.tenant_id, NEW.sales_order_id, v_line.product_id, v_line.quantity);

        -- LE LIEN : la ligne du BL → LE mouvement qu'elle a produit (M-09).
        -- C'est cet appel qui écrit le lien documentaire PAR LIGNE. Sans lui,
        -- les mouvements sortent bien mais `document_links` reste vide — mesuré
        -- le 02/10 : la suite 401 T04 disait « liens=0 » alors que les 2
        -- mouvements et l'événement étaient présents.
        PERFORM link_documents(NEW.tenant_id, 'delivery_notes', NEW.id, 'stock_movements', v_mouvement,
                               'sale.delivery.stock_out', 'delivered_by',
                               jsonb_build_object('quantity', v_line.quantity, 'warehouse_id', v_wh,
                                                  'reference', 'BL-' || NEW.number, 'reservation_liberee', v_libere),
                               v_line.id, NULL);
        v_lignes := v_lignes + 1;
      END LOOP;

      -- L1 (311) : le lien et la mesure se portent sur le BON, une fois, avec
      -- le nombre de lignes réellement sorties — c'est ce que la suite 401
      -- T04 vérifie (« 2 mouvements, 2 liens PAR LIGNE… 1 événement, 1
      -- mesure » : le lien est par ligne, la MESURE est unique). Tracer à
      -- chaque ligne produirait deux mesures au lieu d'une, et la suite le
      -- refuse.
      IF v_lignes > 0 THEN
        PERFORM emit_domain_event(NEW.tenant_id,
                                  CASE WHEN NEW.status = 'delivered' THEN 'delivery_notes.delivered' ELSE 'delivery_notes.shipped' END,
                                  'delivery_notes', NEW.id,
                                  jsonb_build_object('mouvements', v_lignes, 'sales_order_id', NEW.sales_order_id), NULL);
        PERFORM chain_apres(NEW.tenant_id, 'sale.delivery.stock_out', 'delivery_notes', NEW.id,
                            v_debut, v_lignes, 'applique', NULL, NULL, NULL);
      END IF;
    END IF;

    -- B1, complément (314) : la commande ne se dit livrée qu'une fois la
    -- marchandise sortie. Ce bloc est INDÉPENDANT du fait que la sortie vienne
    -- de `shipped` ou de `delivered`, et il ne se déclenche pas deux fois : il
    -- écrit un statut, pas un mouvement de stock.
    IF NEW.sales_order_id IS NOT NULL THEN
      SELECT bool_and(COALESCE(l.delivered_quantity, 0) >= l.quantity) INTO v_tout_livre
      FROM sales_order_lines l
      WHERE l.tenant_id = NEW.tenant_id AND l.sales_order_id = NEW.sales_order_id;

      IF v_tout_livre IS NOT NULL THEN
        UPDATE sales_orders
        SET delivery_status = CASE WHEN v_tout_livre THEN 'delivered' ELSE 'partial' END,
            fully_delivered = v_tout_livre,
            updated_at = now()
        WHERE id = NEW.sales_order_id AND tenant_id = NEW.tenant_id;
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END $$;

GRANT EXECUTE ON FUNCTION create_stock_out_on_delivery() TO service_role;