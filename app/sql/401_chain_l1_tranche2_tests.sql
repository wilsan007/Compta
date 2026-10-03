-- ============================================================
-- 311_chain_l1_tranche2_tests.sql — L1 (tranche 2) : ce que le traçage PAR LIGNE
--   et les maillons multi-effets garantissent
--
-- Source : doc/audit/PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md (lot L1) ;
-- inventaire §1 de la tranche 2.
--
--   T01  commande confirmée, 2 lignes → 2 réservations, **2 liens par ligne**,
--        chacun pointant la réservation du bon article ; 1 événement, 1 mesure ;
--   T02  annulée puis reconfirmée : l'effet est REPRODUIT (2 réservations
--        actives), les 2 liens du tour 1 sont **rompus** et **remplacés** par 2
--        liens actifs du tour 2 pointant la réservation courante. ⚠️ Verdict
--        PRÉCISÉ le 02/10/2026 (L3, 320) : avant le cycle de vie du lien (312) et
--        la fermeture à l'annulation (320), l'assertion portait sur « deux liens
--        mis à jour » ; la même propriété est désormais mesurée SUR L'ÉTAT. La
--        trouvaille du lot (la clé du socle n'a pas de notion de tour) est née
--        d'un rouge de la suite 230 ;
--   T03  la société voisine ne voit ni les liens ni l'événement ;
--   T04  BL expédié, 2 lignes → 2 mouvements, 2 liens par ligne, le bon produit ;
--   T05  mode `refuse` : la sortie est BLOQUÉE avant tout effet, message nominatif,
--        et AUCUN mouvement n'est écrit (le fait générateur est l'état) ;
--   T06  expédition sous-traitance, 2 lignes → 2 liens par ligne ;
--   T07  réception sous-traitance, 2 lignes → 2 liens par ligne, coût façon porté ;
--   T08  clôture de caisse → lien session → écriture, et le décompte des mouvements
--        de stock NON liés (amont sans lignes) dans le payload ;
--   T09  rapprochement bancaire automatique → lien `created_from` vers l'encaissement ;
--   T10  OF terminé → deux liens (écriture ET entrée du produit fini) et le
--        décompte des sorties de composants ; ces sorties ne sont PAS liées ;
--   T11  structure : les compagnons `zz_l1_` du dépôt sont tous des déclencheurs
--        APRÈS, nommés après leur maillon métier (la caisse l'est par la phase),
--        et les quatre déclencheurs réécrits pointent bien leurs fonctions —
--        une PROPRIÉTÉ, pas un compte : la tranche 4 en a ajouté deux le 30/09 ;
--   T12  un document resté en brouillon ne trace rien (le fait est l'état).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '401', false);
DELETE FROM _audit_results WHERE file = '311';

-- ─────────────────────────────────────────────────────────────
-- Outillage propre à ce fichier
-- ─────────────────────────────────────────────────────────────

-- Deux articles à 100 en stock, un dépôt, un client.
CREATE OR REPLACE FUNCTION _l311_vente(p_nom text, OUT t uuid, OUT wh uuid, OUT c uuid,
                                       OUT p1 uuid, OUT p2 uuid)
LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom);
  PERFORM ensure_standard_journals(t);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt ' || p_nom)
    RETURNING id INTO wh;
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client ' || p_nom) RETURNING id INTO c;
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
    VALUES (t, 'Article 1 ' || p_nom, 'A1-' || p_nom, 'stock', 5) RETURNING id INTO p1;
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
    VALUES (t, 'Article 2 ' || p_nom, 'A2-' || p_nom, 'stock', 5) RETURNING id INTO p2;
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type,
                               quantity, unit_cost, reference, movement_date, date)
  VALUES (t, p1, wh, 'in', 'in', 100, 5, 'APPRO1-' || p_nom, CURRENT_DATE, CURRENT_DATE),
         (t, p2, wh, 'in', 'in', 100, 5, 'APPRO2-' || p_nom, CURRENT_DATE, CURRENT_DATE);
END $$;

-- Commande à DEUX lignes, confirmée (le maillon déclenche à la confirmation).
CREATE OR REPLACE FUNCTION _l311_cmd(p_t uuid, p_c uuid, p1 uuid, p2 uuid, p_num text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE so uuid;
BEGIN
  INSERT INTO sales_orders (tenant_id, number, customer_id, order_date, status)
  VALUES (p_t, 'CV-' || p_num, p_c, CURRENT_DATE, 'draft') RETURNING id INTO so;
  INSERT INTO sales_order_lines (tenant_id, sales_order_id, product_id, description, quantity, unit_price)
  VALUES (p_t, so, p1, 'Ligne 1', 3, 20), (p_t, so, p2, 'Ligne 2', 4, 20);
  UPDATE sales_orders SET status = 'confirmed' WHERE id = so;
  RETURN so;
END $$;

-- Bon de livraison à DEUX lignes, rattaché à la commande (non expédié).
CREATE OR REPLACE FUNCTION _l311_bl(p_t uuid, p_c uuid, p1 uuid, p2 uuid, p_so uuid, p_num text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE bl uuid;
BEGIN
  INSERT INTO delivery_notes (tenant_id, number, customer_id, sales_order_id, delivery_date, status)
  VALUES (p_t, 'BL-' || p_num, p_c, p_so, CURRENT_DATE, 'pending') RETURNING id INTO bl;
  INSERT INTO delivery_note_lines (tenant_id, delivery_note_id, product_id, description, quantity)
  VALUES (p_t, bl, p1, 'Ligne 1', 3), (p_t, bl, p2, 'Ligne 2', 4);
  RETURN bl;
END $$;

-- Les liens d'un document, avec la ligne amont, l'aval, l'ÉTAT et le TOUR.
-- ⚠️ `etat` et `tour` ont été AJOUTÉS le 02/10/2026 (L3, 320) : depuis la 312
-- un lien a un cycle de vie, et depuis la 320 l'annulation d'une commande FERME
-- ses liens au lieu de les réécrire. Un scénario qui lit les liens sans dire
-- lesquels sont actifs mesure le passé et le présent confondus. `DROP` avant
-- `CREATE` : une signature qui change ne se remplace pas, elle se recrée.
DROP FUNCTION IF EXISTS _l311_liens(uuid, text, uuid);
CREATE OR REPLACE FUNCTION _l311_liens(p_t uuid, p_amont_type text, p_amont_id uuid)
RETURNS TABLE(effet text, amont_ligne_id uuid, aval_type text, aval_id uuid, link_type text, payload jsonb, created_at timestamptz, etat text, tour integer)
LANGUAGE sql AS $$
  SELECT dl.effet, dl.amont_ligne_id, dl.aval_type, dl.aval_id, dl.link_type, dl.payload, dl.created_at, dl.etat, dl.tour
  FROM document_links dl
  WHERE dl.tenant_id = p_t AND dl.amont_type = p_amont_type AND dl.amont_id = p_amont_id
  ORDER BY dl.effet, dl.amont_ligne_id, dl.tour
$$;

CREATE OR REPLACE FUNCTION _l311_evt(p_t uuid, p_nom text, p_agregat uuid)
RETURNS integer LANGUAGE sql AS $$
  SELECT count(*)::int FROM domain_events de
  WHERE de.tenant_id = p_t AND de.event_name = p_nom AND de.aggregate_id = p_agregat
$$;

-- ═════════════════════════════════════════════════════════════
-- T01 — Commande à deux lignes : deux réservations, DEUX liens par ligne
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; so uuid; n_liens int; n_lignes int; n_ok int; n_evt int; n_applique int;
        n_reservations int;
BEGIN
  v := _l311_vente('L2A');
  so := _l311_cmd(v.t, v.c, v.p1, v.p2, 'L2A');
  PERFORM _as_user();
  BEGIN
    SELECT count(*), count(DISTINCT amont_ligne_id) INTO n_liens, n_lignes
      FROM _l311_liens(v.t, 'sales_orders', so);
    -- Chaque lien pointe la réservation DU MÊME article que sa ligne de commande :
    -- c'est la correspondance ligne → ligne que le compagnon ne pouvait pas deviner.
    SELECT count(*) INTO n_ok
    FROM _l311_liens(v.t, 'sales_orders', so) l
    JOIN sales_order_lines sl ON sl.id = l.amont_ligne_id
    JOIN stock_reservations sr ON sr.id = l.aval_id
    WHERE sr.product_id = sl.product_id AND sr.reference_id = so AND sr.status = 'active';
    SELECT count(*) INTO n_reservations FROM stock_reservations WHERE tenant_id = v.t AND reference_id = so;
    n_evt := _l311_evt(v.t, 'sales_orders.confirmed', so);
    SELECT count(*) INTO n_applique FROM chain_traces
     WHERE tenant_id = v.t AND effet = 'sale.order.reserved' AND amont_id = so AND resultat = 'applique';
    PERFORM _rec('T01',
      'commande à 2 lignes → 2 réservations et 2 liens PAR LIGNE, chacun pointant la réservation de son article ; 1 événement, 1 mesure',
      n_liens = 2 AND n_lignes = 2 AND n_ok = 2 AND n_reservations = 2 AND n_evt = 1 AND n_applique = 1,
      format('liens=%s lignes distinctes=%s correspondances justes=%s réservations=%s événements=%s mesures=%s',
             n_liens, n_lignes, n_ok, n_reservations, n_evt, n_applique));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T01', 'commande à 2 lignes → 2 réservations et 2 liens PAR LIGNE, chacun pointant la réservation de son article ; 1 événement, 1 mesure', false, SQLERRM);
  END;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T02 — Annulée puis reconfirmée : l'effet revient, l'historique garde les tours
--   Ce scénario est né d'un ROUGE : la première version du lot appelait
--   `chain_avant` en tête de boucle, et la suite 230 (T04) a prouvé que la
--   re-confirmation d'une commande annulée ne réservait plus rien (la clé du
--   socle n'a pas de notion de « tour »).
--
--   ⚠️ LE VERDICT A CHANGÉ LE 02/10/2026 (L3, migration 320), ET IL EST PLUS
--   FORT. Le monde autour n'est plus le même : la 312 a donné au lien un CYCLE
--   DE VIE (`actif` → `remplace` | `rompu`) et la 320 fait FERMER — par le
--   maillon d'annulation lui-même — les liens de la commande que le métier vient
--   de libérer. Le lien n'est donc plus MIS À JOUR, il est REMPLACÉ : l'ancien
--   reste (`rompu`, daté, motivé), et un NOUVEAU naît au tour suivant.
--   Ce que le scénario mesure aujourd'hui : l'effet est reproduit (2
--   réservations ACTIVES), l'historique garde les DEUX tours (2 rompus + 2
--   actifs), et le lien ACTIF pointe la réservation COURANTE — l'assertion porte
--   donc sur le lien actif, parce que c'est lui qui décrit le présent.
--   Les deux verdicts sont conservés : « deux liens actifs » était vrai avant
--   par réécriture, il l'est après par remplacement — c'est la même propriété,
--   et elle est désormais prouvée sur l'état, pas sur un compte de lignes.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; so uuid; ligne1 uuid; n_liens int; n_actifs int; n_rompus int; n_tours int;
        n_actives int; n_total int; v_avant uuid; v_apres uuid;
BEGIN
  v := _l311_vente('L2B');
  so := _l311_cmd(v.t, v.c, v.p1, v.p2, 'L2B');
  PERFORM _as_user();
  BEGIN
    SELECT id INTO ligne1 FROM sales_order_lines
     WHERE sales_order_id = so AND product_id = v.p1;
    SELECT aval_id INTO v_avant FROM _l311_liens(v.t, 'sales_orders', so)
     WHERE amont_ligne_id = ligne1 AND etat = 'actif' LIMIT 1;

    -- Annulation : le maillon de libération consomme la réservation, et le
    -- maillon compagnon de la 320 ROMPT les liens qui décrivaient l'effet.
    UPDATE sales_orders SET status = 'cancelled' WHERE id = so;
    -- Reconformation : la réservation doit REVENIR (sans quoi le métier refuse),
    -- et l'entrée du maillon — vraie depuis que le lien est fermé — autorise la
    -- reproduction au tour suivant.
    UPDATE sales_orders SET status = 'confirmed' WHERE id = so;

    SELECT count(*), count(*) FILTER (WHERE etat = 'actif'),
           count(*) FILTER (WHERE etat = 'rompu'), count(DISTINCT tour)
      INTO n_liens, n_actifs, n_rompus, n_tours
      FROM _l311_liens(v.t, 'sales_orders', so);
    SELECT count(*) INTO n_total FROM stock_reservations
     WHERE tenant_id = v.t AND reference_id = so;
    SELECT count(*) INTO n_actives FROM stock_reservations
     WHERE tenant_id = v.t AND reference_id = so AND status = 'active';
    SELECT aval_id INTO v_apres FROM _l311_liens(v.t, 'sales_orders', so)
     WHERE amont_ligne_id = ligne1 AND etat = 'actif' LIMIT 1;

    PERFORM _rec('T02',
      'commande annulée puis reconfirmée : l''effet est reproduit (2 réservations actives), les 2 liens du tour 1 sont ROMpus et remplacés par 2 liens actifs (tour 2) pointant la réservation courante',
      n_actifs = 2 AND n_rompus = 2 AND n_tours = 2 AND n_actives = 2 AND n_total >= 3
        AND v_apres IS DISTINCT FROM v_avant,
      format('liens=%s dont actifs=%s rompus=%s tours=%s réservations actives=%s (total=%s) aval actif avant=%s après=%s',
             n_liens, n_actifs, n_rompus, n_tours, n_actives, n_total, v_avant, v_apres));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T02', 'commande annulée puis reconfirmée : l''effet est reproduit (2 réservations actives), les 2 liens du tour 1 sont ROMpus et remplacés par 2 liens actifs (tour 2) pointant la réservation courante', false, SQLERRM);
  END;
END $$;


-- ═════════════════════════════════════════════════════════════
-- T03 — La société voisine ne voit rien
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; so uuid; tb uuid; n_liens int; n_evt int; n_avant int;
BEGIN
  v := _l311_vente('L2C');
  so := _l311_cmd(v.t, v.c, v.p1, v.p2, 'L2C');
  SELECT count(*) INTO n_avant FROM document_links WHERE amont_id = so;
  tb := _mk_tenant('L2C-bis');
  PERFORM _as_user();
  BEGIN
    SELECT count(*) INTO n_liens FROM document_links WHERE amont_id = so;
    SELECT count(*) INTO n_evt FROM domain_events WHERE aggregate_id = so;
    PERFORM _rec('T03',
      'la société voisine ne voit ni les liens par ligne ni l''événement de la première société',
      n_avant = 2 AND n_liens = 0 AND n_evt = 0,
      format('liens écrits=%s, visibles par la voisine=%s, événements visibles=%s', n_avant, n_liens, n_evt));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T03', 'la société voisine ne voit ni les liens par ligne ni l''événement de la première société', false, SQLERRM);
  END;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T04 — BL expédié, deux lignes : deux mouvements, deux liens par ligne
--   L'archétype du plan (`sale.delivery.stock_out`, règle R-006).
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; so uuid; bl uuid; n_liens int; n_ok int; n_mvts int; n_evt int; n_applique int;
BEGIN
  v := _l311_vente('L2D');
  so := _l311_cmd(v.t, v.c, v.p1, v.p2, 'L2D');
  bl := _l311_bl(v.t, v.c, v.p1, v.p2, so, 'L2D');
  PERFORM _as_user();
  BEGIN
    UPDATE delivery_notes SET status = 'shipped' WHERE id = bl;
    SELECT count(*) INTO n_liens FROM _l311_liens(v.t, 'delivery_notes', bl);
    SELECT count(*) INTO n_ok
    FROM _l311_liens(v.t, 'delivery_notes', bl) l
    JOIN delivery_note_lines dl ON dl.id = l.amont_ligne_id
    JOIN stock_movements sm ON sm.id = l.aval_id
    WHERE sm.product_id = dl.product_id AND sm.movement_type = 'out'
      -- Le maillon écrit 'BL-' || number (number vaut déjà 'BL-L2D').
      AND sm.reference = 'BL-' || (SELECT number FROM delivery_notes WHERE id = bl)
      AND sm.reference_id = bl;
    SELECT count(*) INTO n_mvts FROM stock_movements
     WHERE tenant_id = v.t AND reference_type = 'delivery_note' AND reference_id = bl;
    n_evt := _l311_evt(v.t, 'delivery_notes.shipped', bl);
    SELECT count(*) INTO n_applique FROM chain_traces
     WHERE tenant_id = v.t AND effet = 'sale.delivery.stock_out' AND amont_id = bl AND resultat = 'applique';
    PERFORM _rec('T04',
      'BL expédié à 2 lignes → 2 mouvements et 2 liens PAR LIGNE, chacun pointant le mouvement de son article ; 1 événement, 1 mesure',
      n_liens = 2 AND n_ok = 2 AND n_mvts = 2 AND n_evt = 1 AND n_applique = 1,
      format('liens=%s correspondances justes=%s mouvements=%s événements=%s mesures=%s',
             n_liens, n_ok, n_mvts, n_evt, n_applique));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T04', 'BL expédié à 2 lignes → 2 mouvements et 2 liens PAR LIGNE, chacun pointant le mouvement de son article ; 1 événement, 1 mesure', false, SQLERRM);
  END;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T05 — Mode refuse : la sortie est bloquée AVANT tout effet
--   Le maillon réécrit appelle `chain_avant` avant d'écrire : quand le contrat
--   est éteint et la société en `refuse`, la ligne ne produit RIEN — ni
--   mouvement, ni lien, ni événement — et le document n'est pas expédié.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; so uuid; bl uuid; msg text := 'ACCEPTÉ'; n_mvts int; n_liens int; statut text;
BEGIN
  v := _l311_vente('L2E');
  so := _l311_cmd(v.t, v.c, v.p1, v.p2, 'L2E');
  bl := _l311_bl(v.t, v.c, v.p1, v.p2, so, 'L2E');
  -- L'effet est ÉTEINT pour cette société, et elle demande le mode `refuse`.
  INSERT INTO document_effects (tenant_id, document_type, evenement, effet, actif)
  VALUES (v.t, 'delivery_notes', 'shipped', 'sale.delivery.stock_out', false)
  ON CONFLICT (COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
               document_type, evenement, effet)
  DO UPDATE SET actif = false;
  INSERT INTO chain_settings (tenant_id, enforcement) VALUES (v.t, 'refuse')
  ON CONFLICT (tenant_id) DO UPDATE SET enforcement = 'refuse';
  PERFORM _as_user();
  BEGIN
    UPDATE delivery_notes SET status = 'shipped' WHERE id = bl;
  EXCEPTION WHEN OTHERS THEN
    msg := SQLERRM;
  END;
  SELECT status INTO statut FROM delivery_notes WHERE id = bl;
  SELECT count(*) INTO n_mvts FROM stock_movements
   WHERE tenant_id = v.t AND reference_type = 'delivery_note' AND reference_id = bl;
  n_liens := (SELECT count(*) FROM _l311_liens(v.t, 'delivery_notes', bl));
  PERFORM _rec('T05',
    'mode refuse : la sortie est bloquée AVANT l''effet — aucun mouvement, aucun lien, BL resté non expédié, message nominatif',
    msg <> 'ACCEPTÉ' AND msg LIKE '%sale.delivery.stock_out%' AND msg LIKE '%module stock%'
      AND msg LIKE '%BL-L2E%' AND n_mvts = 0 AND n_liens = 0 AND statut IS DISTINCT FROM 'shipped',
    format('message=« %s » mouvements=%s liens=%s statut=%s', left(msg, 200), n_mvts, n_liens, statut));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T06 et T07 — La sous-traitance : expédition et réception, par ligne
--   Le produit vient de l'ORDRE (le maillon fait `SELECT product_id FROM
--   st_orders`), donc les deux lignes portent le même article : c'est la
--   **quantité** qui identifie la correspondance ligne → mouvement, et le test
--   l'utilise comme telle.
-- ═════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION _l311_st(p_nom text, OUT t uuid, OUT wh uuid, OUT s uuid,
                                   OUT o uuid, OUT p uuid, OUT exp uuid, OUT rec uuid)
LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom);
  PERFORM ensure_standard_journals(t);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt ' || p_nom)
    RETURNING id INTO wh;
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Sous-traitant ' || p_nom) RETURNING id INTO s;
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
    VALUES (t, 'Pièce ' || p_nom, 'P-' || p_nom, 'stock', 5) RETURNING id INTO p;
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type,
                               quantity, unit_cost, reference, movement_date, date)
  VALUES (t, p, wh, 'in', 'in', 100, 5, 'APPRO-' || p_nom, CURRENT_DATE, CURRENT_DATE);
  INSERT INTO st_orders (tenant_id, number, supplier_id, product_id, unit_price)
    VALUES (t, 'ST-' || p_nom, s, p, 2) RETURNING id INTO o;
  INSERT INTO st_shipments (tenant_id, number, st_order_id, status)
    VALUES (t, 'EXP-' || p_nom, o, 'pending') RETURNING id INTO exp;
  INSERT INTO st_shipment_lines (tenant_id, st_shipment_id, product_id, quantity)
    VALUES (t, exp, p, 5), (t, exp, p, 7);
  INSERT INTO st_receipts (tenant_id, number, st_order_id, status)
    VALUES (t, 'REC-' || p_nom, o, 'pending') RETURNING id INTO rec;
  INSERT INTO st_receipt_lines (tenant_id, st_receipt_id, product_id, quantity, line_type)
    VALUES (t, rec, p, 5, 'received'), (t, rec, p, 7, 'received');
END $$;

-- T06 — expédition chez le sous-traitant
DO $$
DECLARE v record; n_liens int; n_ok int; n_evt int;
BEGIN
  SELECT * INTO v FROM _l311_st('L2F');
  PERFORM _as_user();
  BEGIN
    UPDATE st_shipments SET status = 'shipped' WHERE id = v.exp;
    SELECT count(*) INTO n_liens FROM _l311_liens(v.t, 'st_shipments', v.exp);
    SELECT count(*) INTO n_ok
    FROM _l311_liens(v.t, 'st_shipments', v.exp) l
    JOIN st_shipment_lines sl ON sl.id = l.amont_ligne_id
    JOIN stock_movements sm ON sm.id = l.aval_id
    WHERE sm.quantity = sl.quantity AND sm.product_id = sl.product_id
      AND sm.movement_type = 'out' AND sm.reference = 'ST-EXP-L2F';
    n_evt := _l311_evt(v.t, 'st_shipments.shipped', v.exp);
    PERFORM _rec('T06',
      'expédition sous-traitance à 2 lignes → 2 liens PAR LIGNE, chacun pointant le mouvement de sa quantité',
      n_liens = 2 AND n_ok = 2 AND n_evt = 1,
      format('liens=%s correspondances justes=%s événements=%s', n_liens, n_ok, n_evt));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T06', 'expédition sous-traitance à 2 lignes → 2 liens PAR LIGNE, chacun pointant le mouvement de sa quantité', false, SQLERRM);
  END;
END $$;

-- T07 — réception du sous-traitant (coût matière + façon dans le payload)
DO $$
DECLARE v record; n_liens int; n_ok int; n_cout int; n_evt int;
BEGIN
  SELECT * INTO v FROM _l311_st('L2G');
  PERFORM _as_user();
  BEGIN
    UPDATE st_receipts SET status = 'received' WHERE id = v.rec;
    SELECT count(*) INTO n_liens FROM _l311_liens(v.t, 'st_receipts', v.rec);
    SELECT count(*) INTO n_ok
    FROM _l311_liens(v.t, 'st_receipts', v.rec) l
    JOIN st_receipt_lines rl ON rl.id = l.amont_ligne_id
    JOIN stock_movements sm ON sm.id = l.aval_id
    WHERE sm.quantity = rl.quantity AND sm.movement_type = 'in'
      -- Le maillon préfixe le numéro du bon : 'ST-REC-' || number (number = 'REC-L2G').
      AND sm.reference = 'ST-REC-' || (SELECT number FROM st_receipts WHERE id = v.rec);
    -- Le coût de la façon est porté par le lien (analyse d'impact, M-12).
    SELECT count(*) INTO n_cout FROM _l311_liens(v.t, 'st_receipts', v.rec)
     WHERE (payload->>'cost_subcontracting')::numeric > 0;
    n_evt := _l311_evt(v.t, 'st_receipts.received', v.rec);
    PERFORM _rec('T07',
      'réception sous-traitance à 2 lignes → 2 liens PAR LIGNE, le coût de la façon porté par le payload',
      n_liens = 2 AND n_ok = 2 AND n_cout = 2 AND n_evt = 1,
      format('liens=%s correspondances justes=%s liens avec coût façon=%s événements=%s', n_liens, n_ok, n_cout, n_evt));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T07', 'réception sous-traitance à 2 lignes → 2 liens PAR LIGNE, le coût de la façon porté par le payload', false, SQLERRM);
  END;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T08 — Clôture de caisse : le lien du document, et ce qui n'est PAS lié
--   Les sorties de stock sont agrégées par produit : l'amont n'a pas de ligne à
--   désigner (règle 2). Le lien les **compte** au lieu de les inventer.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('L2H'); w uuid; p uuid; term uuid; pm uuid; sess uuid;
        k1 uuid; l record; n_liens int; n_mvts int; n_evt int;
BEGIN
  PERFORM ensure_standard_journals(t);
  INSERT INTO warehouses (tenant_id, name, code) VALUES (t, 'Magasin', 'MAG-L2H') RETURNING id INTO w;
  INSERT INTO products (tenant_id, name, sku, type, cost_price, stock_quantity)
    VALUES (t, 'Article POS L2H', 'SKU-L2H', 'stock', 0, 0) RETURNING id INTO p;
  PERFORM _as_user();
  BEGIN
    INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, type, movement_type, quantity, unit_cost, date)
    VALUES (t, p, w, 'in', 'in', 10, 5, '2026-03-01');
    INSERT INTO pos_terminals (tenant_id, name, warehouse_id) VALUES (t, 'Caisse L2H', w) RETURNING id INTO term;
    INSERT INTO pos_payment_methods (tenant_id, name, type, account_code) VALUES (t, 'Espèces L2H', 'cash', '530000') RETURNING id INTO pm;
    INSERT INTO pos_sessions (tenant_id, terminal_id, user_email, opening_amount, status)
    VALUES (t, term, 'caisse-l2h@audit.test', 0, 'open') RETURNING id INTO sess;
    INSERT INTO pos_tickets (tenant_id, number, session_id, terminal_id, subtotal, vat_total, total, payment_method, amount_paid, status)
    VALUES (t, 'TK-L2H-1', sess, term, 10, 2, 12, 'cash', 12, 'completed') RETURNING id INTO k1;
    INSERT INTO pos_ticket_lines (tenant_id, ticket_id, product_id, description, quantity, unit_price, vat_rate, line_total)
    VALUES (t, k1, p, 'Article POS L2H', 2, 10, 20, 20);

    -- La clôture : c'est le maillon métier (281, BEFORE UPDATE) qui écrit.
    UPDATE pos_sessions SET status = 'closed', closing_amount = 24 WHERE id = sess;

    SELECT * INTO l FROM _l311_liens(t, 'pos_sessions', sess) LIMIT 1;
    SELECT count(*) INTO n_liens FROM _l311_liens(t, 'pos_sessions', sess);
    SELECT count(*) INTO n_mvts FROM stock_movements
     WHERE tenant_id = t AND reference_type = 'pos_session' AND reference_id = sess;
    n_evt := _l311_evt(t, 'pos_sessions.closed', sess);
    PERFORM _rec('T08',
      'clôture de caisse → un lien session → écriture, et le décompte (non nul) des mouvements de stock NON liés dans le payload',
      n_liens = 1 AND l.aval_type = 'journal_entries' AND l.aval_id IS NOT NULL
        AND n_mvts >= 1 AND (l.payload->>'mouvements_stock')::int = n_mvts
        AND (l.payload->>'lien_par_ligne')::boolean = false AND n_evt = 1,
      format('liens=%s aval=%s mouvements=%s payload=%s événements=%s', n_liens, l.aval_type, n_mvts, l.payload, n_evt));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T08', 'clôture de caisse → un lien session → écriture, et le décompte (non nul) des mouvements de stock NON liés dans le payload', false, SQLERRM);
  END;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T09 — Rapprochement bancaire automatique : `created_from`
--   L'encaissement créé porte un numéro déterministe : c'est lui qui rend l'aval
--   résoluble de l'extérieur, sans réécrire le maillon.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('L2I'); acc uuid; cli uuid; inv uuid; num text; k uuid;
        l record; n_liens int; n_evt int; n_pay int;
BEGIN
  PERFORM ensure_standard_journals(t);
  INSERT INTO bank_accounts (tenant_id, name, type, account_code, currency, balance)
  VALUES (t, 'Banque L2I', 'chequing', '512000', 'EUR', 0) RETURNING id INTO acc;
  INSERT INTO customers (tenant_id, name, account_tiers) VALUES (t, 'Client L2I', 'C2I') RETURNING id INTO cli;
  PERFORM _as_user();
  BEGIN
    INSERT INTO invoices (tenant_id, number, customer_id, customer_name, date, due_date,
                          status, subtotal, vat_total, total, amount_paid, amount_due)
    VALUES (t, 'F-L2I', cli, 'Client L2I', '2026-03-01', '2026-03-31', 'draft', 100, 20, 120, 0, 120)
    RETURNING id INTO inv;
    INSERT INTO invoice_lines (tenant_id, invoice_id, description, quantity, unit_price, vat_rate, total, vat_code, vat_amount)
    VALUES (t, inv, 'Prestation L2I', 1, 100, 20, 100, 'FR20', 20);
    UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
    SELECT number INTO num FROM invoices WHERE id = inv;

    -- Une ligne de relevé créditrice : montant identique et numéro de facture dans
    -- le libellé → score 90 (50 + 40), donc encaissement automatique.
    INSERT INTO bank_transactions (tenant_id, account_id, bank_account_id, date, description, type, amount, source)
    VALUES (t, acc, acc, '2026-03-06', 'VIR ' || num, 'credit', 120, 'import')
    RETURNING id INTO k;

    -- ⚠️ Adapté le 30/09/2026 par la tranche 5 (migration 316) : cette ligne de
    -- relevé porte désormais DEUX liens légitimes — celui d'ici (vers
    -- l'encaissement créé, effet `treasury.bank_transaction.reconciled`) et celui
    -- de la tranche 5 (vers la ligne du grand livre,
    -- `treasury.statement_line.matched`, car le rapprochement a AUSSI marqué une
    -- écriture). Le scénario mesure donc SON effet et non « tous les liens du
    -- document » : compter tous les liens faisait dépendre ce test de la tranche
    -- suivante, ce qui n'est pas ce qu'il prétend vérifier.
    SELECT * INTO l FROM _l311_liens(t, 'bank_transactions', k)
     WHERE effet = 'treasury.bank_transaction.reconciled' LIMIT 1;
    SELECT count(*) INTO n_liens FROM _l311_liens(t, 'bank_transactions', k)
     WHERE effet = 'treasury.bank_transaction.reconciled';
    SELECT count(*) INTO n_pay FROM customer_payments WHERE tenant_id = t;
    n_evt := _l311_evt(t, 'bank_transactions.reconciled', k);
    PERFORM _rec('T09',
      'rapprochement bancaire automatique → un lien `created_from` de la ligne de relevé vers l''encaissement créé',
      n_liens = 1 AND l.aval_type = 'customer_payments' AND l.link_type = 'created_from'
        AND n_pay = 1 AND n_evt = 1,
      format('liens=%s aval=%s type=%s encaissements=%s événements=%s', n_liens, l.aval_type, l.link_type, n_pay, n_evt));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T09', 'rapprochement bancaire automatique → un lien `created_from` de la ligne de relevé vers l''encaissement créé', false, SQLERRM);
  END;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T10 — Ordre de fabrication terminé : deux liens, et ce qui n'est PAS lié
--   L'écriture et l'entrée du produit fini sont des avals uniques → liés.
--   Les sorties de composants viennent d'une nomenclature CALCULÉE : pas de
--   ligne amont à désigner → comptées, non liées (règle 2).
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE t uuid := _mk_tenant('L2J'); wh uuid; pf uuid; mp uuid; b uuid; mo uuid;
        n_liens int; n_ecriture int; n_entree int; n_out_lies int; n_sorties int;
        n_evt int; n_payload int;
BEGIN
  PERFORM ensure_standard_journals(t);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-L2J', 'Dépôt L2J') RETURNING id INTO wh;
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
    VALUES (t, 'PF L2J', 'PF-L2J', 'stock', 0) RETURNING id INTO pf;
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
    VALUES (t, 'MP L2J', 'MP-L2J', 'stock', 5) RETURNING id INTO mp;
  INSERT INTO boms (tenant_id, code, name, product_id, quantity)
    VALUES (t, 'B-L2J', 'Nomenclature L2J', pf, 1) RETURNING id INTO b;
  INSERT INTO bom_lines (tenant_id, bom_id, product_id, quantity, unit_cost) VALUES (t, b, mp, 2, 5);
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type,
                               quantity, unit_cost, reference, movement_date, date)
  VALUES (t, mp, wh, 'in', 'in', 10000, 5, 'APPRO-L2J', CURRENT_DATE, CURRENT_DATE);
  INSERT INTO manufacturing_orders (tenant_id, number, bom_id, product_id, quantity, status, warehouse_id)
    VALUES (t, 'OF-L2J', b, pf, 10, 'planned', wh) RETURNING id INTO mo;
  PERFORM _as_user();
  BEGIN
    UPDATE manufacturing_orders SET status = 'completed', qty_produced = 10 WHERE id = mo;

    SELECT count(*) INTO n_liens FROM _l311_liens(t, 'manufacturing_orders', mo);
    SELECT count(*) INTO n_ecriture FROM _l311_liens(t, 'manufacturing_orders', mo)
     WHERE effet = 'production.order.generated_entry' AND aval_type = 'journal_entries';
    SELECT count(*) INTO n_entree FROM _l311_liens(t, 'manufacturing_orders', mo)
     WHERE effet = 'production.order.stock_in' AND aval_type = 'stock_movements';
    -- Aucun lien ne doit pointer une SORTIE de composant (règle 2).
    SELECT count(*) INTO n_out_lies
    FROM _l311_liens(t, 'manufacturing_orders', mo) l
    JOIN stock_movements sm ON sm.id = l.aval_id
    WHERE sm.movement_type = 'out';
    SELECT count(*) INTO n_sorties FROM stock_movements
     WHERE tenant_id = t AND reference_type = 'production' AND reference_id = mo AND movement_type = 'out';
    SELECT count(*) INTO n_evt FROM domain_events
     WHERE tenant_id = t AND event_name = 'manufacturing_orders.completed' AND aggregate_id = mo;
    SELECT (payload->>'sorties_composants')::int INTO n_payload FROM domain_events
     WHERE tenant_id = t AND event_name = 'manufacturing_orders.completed' AND aggregate_id = mo LIMIT 1;

    PERFORM _rec('T10',
      'OF terminé → un lien vers l''écriture et un vers l''entrée du produit fini ; les sorties de composants sont comptées, pas liées',
      n_liens = 2 AND n_ecriture = 1 AND n_entree = 1 AND n_out_lies = 0
        AND n_sorties >= 1 AND n_evt = 1 AND n_payload = n_sorties,
      format('liens=%s écriture=%s entrée PF=%s liens vers des sorties=%s sorties réelles=%s payload=%s événements=%s',
             n_liens, n_ecriture, n_entree, n_out_lies, n_sorties, n_payload, n_evt));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T10', 'OF terminé → un lien vers l''écriture et un vers l''entrée du produit fini ; les sorties de composants sont comptées, pas liées', false, SQLERRM);
  END;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T11 — La structure : huit compagnons, et quatre déclencheurs métier intacts
--   Cinq compagnons viennent de la 310, trois de la 311. Les quatre maillons
--   réécrits gardent LEUR déclencheur (on n'en a pas ajouté : on a changé le
--   corps de la fonction qu'il appelle).
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v_comp int; v_apres int; v_avant int; v_grand int; v_metier int; v_pos_before boolean;
BEGIN
  SELECT count(*) INTO v_comp FROM pg_trigger WHERE tgname LIKE 'zz_l1_%' AND NOT tgisinternal;
  SELECT count(*) INTO v_apres FROM pg_trigger
   WHERE tgname LIKE 'zz_l1_%' AND NOT tgisinternal AND (tgtype & 2) = 0 AND (tgtype & 1) = 1;
  -- Sept compagnons sur huit ont un frère métier de MÊME événement dont le nom
  -- trie avant eux. Le huitième — la clôture de caisse — n'en a pas : le maillon
  -- métier y est un déclencheur **BEFORE** (`post_pos_session_on_close_multi`,
  -- mesuré), donc l'ordre est garanti par la PHASE et non par le nom. C'est une
  -- différence de nature, pas un défaut : le test la nomme au lieu de la lisser.
  --
  -- ⚠️ Mesure PRÉCISÉE le 30/09/2026 par la tranche 5 (migration 316), sur deux
  -- points — les deux trouvés rouges sur base neuve :
  --   • la comparaison exigeait un `tgtype` IDENTIQUE. Or un maillon métier peut
  --     porter sur INSERT *et* UPDATE (`create_billable_line`, mesuré : 21) là où
  --     le compagnon ne porte que sur INSERT (5) — il le précède pourtant bien à
  --     l'INSERTION, et `zz_l1_time_entry_billed` était compté « sans frère
  --     avant » à tort. La propriété qui compte est « **APRÈS tous les deux, et
  --     au moins un événement en commun** » — un BEFORE n'est pas « avant par le
  --     nom », il est avant par la phase ;
  --   • le frère « après » exclut désormais les COMPAGNONS `zz_l1_` : une table
  --     peut en porter plusieurs (`bank_transactions` : tranche 1 puis tranche 5 ;
  --     `pay_runs` : rappels puis acomptes) et leur ordre relatif est sans effet,
  --     chacun ne lisant que les marqueurs de son propre maillon.
  SELECT count(*) INTO v_avant FROM pg_trigger z
   WHERE z.tgname LIKE 'zz_l1_%' AND NOT z.tgisinternal AND (z.tgtype & 2) = 0
     AND EXISTS (SELECT 1 FROM pg_trigger m
                 WHERE m.tgrelid = z.tgrelid AND (m.tgtype & 2) = 0
                   AND (m.tgtype & z.tgtype & 20) <> 0
                   AND NOT m.tgisinternal AND m.tgname < z.tgname
                   AND m.tgname NOT LIKE 'zz_l1\_%');
  SELECT count(*) INTO v_grand FROM pg_trigger z
   WHERE z.tgname LIKE 'zz_l1_%' AND NOT z.tgisinternal AND (z.tgtype & 2) = 0
     AND EXISTS (SELECT 1 FROM pg_trigger m
                 WHERE m.tgrelid = z.tgrelid AND (m.tgtype & 2) = 0
                   AND (m.tgtype & z.tgtype & 20) <> 0
                   AND NOT m.tgisinternal AND m.tgname > z.tgname
                   AND m.tgname NOT LIKE 'zz_l1\_%');
  SELECT EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
                 WHERE NOT t.tgisinternal AND c.relname = 'pos_sessions'
                   AND t.tgname = 'post_pos_session_on_close_multi_trigger'
                   AND (t.tgtype & 2) = 2) INTO v_pos_before;
  -- Les quatre déclencheurs métier réécrits existent toujours, sur leur table.
  SELECT count(*) INTO v_metier
  FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
  WHERE NOT t.tgisinternal AND (
        (t.tgname = 'reserve_stock_on_so_confirm' AND c.relname = 'sales_orders')
     OR (t.tgname = 'create_stock_out_on_delivery' AND c.relname = 'delivery_notes')
     OR (t.tgname = 'st_shipment_stock_out_trigger' AND c.relname = 'st_shipments')
     OR (t.tgname = 'st_receipt_stock_in_trigger' AND c.relname = 'st_receipts'));

  -- ⚠️ Verdict ÉLARGI le 30/09/2026 : les comptes étaient figés sur la tranche 2
  -- (8 compagnons). La tranche 4 (migration 314) en ajoute deux, avec la même
  -- doctrine — les comptes deviennent donc des PROPRIÉTÉS : tous les compagnons
  -- du dépôt sont APRÈS, tous sauf la clôture de caisse ont un frère métier de
  -- même événement qui trie avant eux (la caisse est garantie par la PHASE), et
  -- aucun frère ne trie après eux. C'est plus fort qu'un compte, qui vieillit mal.
  -- La tranche 5 (migration 316) en ajoute cinq — **15 au total** — sans changer
  -- la propriété : elle a seulement fallu la PRÉCISER (voir ci-dessus), et elle
  -- tient alors telle quelle. C'est bien ce qu'on lui demandait.
  PERFORM _rec('T11',
    'les compagnons `zz_l1_` sont tous APRÈS (tous sauf la caisse après leur frère par le nom, la caisse par la phase) et les quatre déclencheurs des maillons réécrits sont en place',
    v_comp >= 8 AND v_apres = v_comp AND v_avant = v_comp - 1 AND v_grand = 0 AND v_metier = 4 AND v_pos_before,
    format('compagnons=%s (8 à la tranche 2, +2 à la tranche 4, +5 à la tranche 5) après=%s frères avant (nom)=%s frères après=%s caisse BEFORE=%s déclencheurs métier=%s',
           v_comp, v_apres, v_avant, v_grand, v_pos_before, v_metier));
END $$;


-- ═════════════════════════════════════════════════════════════
-- T12 — Un document resté en brouillon ne trace rien
--   Le fait générateur est l'ÉTAT, pas l'existence du document : c'est ce qui
--   rend la trace lisible (aucune ligne pour un brouillon).
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; so uuid; bl uuid; n_liens int; n_mvts int; n_evt int;
BEGIN
  v := _l311_vente('L2K');
  so := _l311_cmd(v.t, v.c, v.p1, v.p2, 'L2K');
  bl := _l311_bl(v.t, v.c, v.p1, v.p2, so, 'L2K');
  PERFORM _as_user();
  BEGIN
    SELECT count(*) INTO n_liens FROM _l311_liens(v.t, 'delivery_notes', bl);
    SELECT count(*) INTO n_mvts FROM stock_movements
     WHERE tenant_id = v.t AND reference_type = 'delivery_note' AND reference_id = bl;
    n_evt := _l311_evt(v.t, 'delivery_notes.shipped', bl);
    PERFORM _rec('T12',
      'un BL resté en brouillon ne trace ni lien, ni mouvement, ni événement — le fait générateur est l''état',
      n_liens = 0 AND n_mvts = 0 AND n_evt = 0,
      format('liens=%s mouvements=%s événements=%s', n_liens, n_mvts, n_evt));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T12', 'un BL resté en brouillon ne trace ni lien, ni mouvement, ni événement — le fait générateur est l''état', false, SQLERRM);
  END;
END $$;

SELECT _audit_assert('401');






