-- ============================================================
-- 242_delivery_warehouse_and_reservation_tests.sql — S-05, S-06, S-07
--
-- Audit des modules hors comptabilité (23/09), § Ventes → stock :
--
--   S-05  `create_stock_out_on_delivery` crée un mouvement SANS dépôt : la
--         livraison décrémente le total de l'article, jamais le dépôt. Le
--         stock du dépôt et le stock de l'article racontent deux histoires.
--   S-06  Ce mouvement n'a pas de dépôt, donc la consommation des couches de
--         valorisation (`consume_valuation_layers_on_exit`, qui compare
--         `COALESCE(layer.warehouse_id, NEW.warehouse_id) = NEW.warehouse_id`)
--         ne trouve rien : un article sorti reste valorisé au stock.
--   S-07  Les réservations ne sont JAMAIS libérées dans le parcours réel :
--         `release_stock_on_delivery` est branché sur `sales_orders.status =
--         'delivered'`, or l'écran pose `delivery_status = 'delivered'` et
--         laisse `status` à « confirmé » (misc.ts:2483). Mesuré : commande
--         confirmée puis livrée → `reserved_quantity` inchangé, réservation
--         toujours `active`, disponible définitivement amputé.
--
-- Mesuré sur base neuve à la 234 (migrations antérieures seules), AVANT la 242 :
-- T01 à T03 et T05 rouges (dépôt inchangé, couches jamais consommées, réservation
-- active), T04 rouge (aucune libération partielle). T06, écrit ensuite, chiffre
-- le chemin d'avant pour une société EXISTANTE — un mouvement de sortie sans
-- dépôt, exécuté sur la base à jour : article 94, dépôts 100 (mesuré).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '242', false);
DELETE FROM _audit_results WHERE file = '242';

-- Société, dépôt, client, article à 5 avec 100 en stock dans le dépôt
CREATE OR REPLACE FUNCTION _mk_vente235(p_nom text, OUT t uuid, OUT wh uuid, OUT c uuid, OUT p uuid)
LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom);
  PERFORM ensure_standard_journals(t);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt ' || p_nom)
    RETURNING id INTO wh;
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client ' || p_nom) RETURNING id INTO c;
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
    VALUES (t, 'Article ' || p_nom, 'A-' || p_nom, 'stock', 5) RETURNING id INTO p;
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type,
    quantity, unit_cost, reference, movement_date, date)
  VALUES (t, p, wh, 'in', 'in', 100, 5, 'APPRO-' || p_nom, CURRENT_DATE, CURRENT_DATE);
END $$;

-- Commande confirmée de p_qte → réservation posée
CREATE OR REPLACE FUNCTION _mk_commande235(p_t uuid, p_c uuid, p_p uuid, p_num text, p_qte numeric)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE so uuid;
BEGIN
  INSERT INTO sales_orders (tenant_id, number, customer_id, order_date, status)
  VALUES (p_t, 'CV-' || p_num, p_c, CURRENT_DATE, 'draft') RETURNING id INTO so;
  INSERT INTO sales_order_lines (tenant_id, sales_order_id, product_id, description, quantity, unit_price)
  VALUES (p_t, so, p_p, 'Article vendu', p_qte, 20);
  UPDATE sales_orders SET status = 'confirmed' WHERE id = so;
  RETURN so;
END $$;

-- Bon de livraison, éventuellement rattaché à la commande
CREATE OR REPLACE FUNCTION _mk_bl235(p_t uuid, p_c uuid, p_p uuid, p_num text, p_qte numeric, p_so uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE bl uuid;
BEGIN
  INSERT INTO delivery_notes (tenant_id, number, customer_id, sales_order_id, delivery_date, status)
  VALUES (p_t, 'BL-' || p_num, p_c, p_so, CURRENT_DATE, 'pending') RETURNING id INTO bl;
  INSERT INTO delivery_note_lines (tenant_id, delivery_note_id, product_id, description, quantity)
  VALUES (p_t, bl, p_p, 'Article livré', p_qte);
  RETURN bl;
END $$;

-- Expédie comme le fait l'écran : sous le rôle d'un utilisateur connecté
CREATE OR REPLACE FUNCTION _expedier235(p_bl uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('role', 'authenticated', true);
  UPDATE delivery_notes SET status = 'shipped' WHERE id = p_bl;
  PERFORM set_config('role', 'postgres', true);
END $$;
-- T01 — S-05 : la sortie se prend sur le dépôt, pas seulement sur l'article
DO $$
DECLARE v record; so uuid; bl uuid; qa numeric; whq numeric; mv record;
BEGIN
  v := _mk_vente235('T01');
  so := _mk_commande235(v.t, v.c, v.p, 'T01', 6);
  bl := _mk_bl235(v.t, v.c, v.p, 'T01', 6, so);
  PERFORM _expedier235(bl);

  SELECT stock_quantity INTO qa FROM products WHERE id = v.p;
  SELECT quantity INTO whq FROM stock_quantities WHERE product_id = v.p AND warehouse_id = v.wh;
  SELECT warehouse_id INTO mv FROM stock_movements WHERE reference_id = bl AND reference_type = 'delivery_note';
  PERFORM _rec('T01', 'livraison de 6 : 94 sur l''article ET 94 dans le dépôt, la sortie porte le dépôt',
    qa = 94 AND whq = 94 AND mv.warehouse_id = v.wh,
    format('article=%s (94 attendu) dépôt=%s (94 attendu) sortie=%s (attendu %s)', qa, whq, COALESCE(mv.warehouse_id::text, 'NULL'), v.wh));
END $$;

-- T02 — S-06 : la sortie consomme la couche de valorisation
DO $$
DECLARE v record; so uuid; bl uuid; rest numeric; val numeric; n int;
BEGIN
  v := _mk_vente235('T02');
  so := _mk_commande235(v.t, v.c, v.p, 'T02', 6);
  bl := _mk_bl235(v.t, v.c, v.p, 'T02', 6, so);
  PERFORM _expedier235(bl);

  SELECT count(*), COALESCE(sum(remaining_qty), 0), COALESCE(sum(value), 0) INTO n, rest, val
  FROM stock_valuation_layers WHERE product_id = v.p;
  PERFORM _rec('T02', 'après livraison de 6 sur une entrée de 100 à 5 : 94 restants, valeur 470',
    n = 1 AND rest = 94 AND val = 470,
    format('couches=%s restants=%s (94 attendus) valeur=%s (470 attendue)', n, rest, val));
END $$;

-- T03 — S-07 : la livraison consomme la réservation de la commande
DO $$
DECLARE v record; so uuid; bl uuid; resv numeric; n_act int; n_con int;
BEGIN
  v := _mk_vente235('T03');
  so := _mk_commande235(v.t, v.c, v.p, 'T03', 6);
  bl := _mk_bl235(v.t, v.c, v.p, 'T03', 6, so);
  PERFORM _expedier235(bl);

  SELECT COALESCE(sum(reserved_quantity), 0) INTO resv FROM stock_quantities WHERE product_id = v.p;
  SELECT count(*) FILTER (WHERE status = 'active'), count(*) FILTER (WHERE status = 'consumed')
    INTO n_act, n_con FROM stock_reservations WHERE reference_id = so;
  PERFORM _rec('T03', 'commande livrée : plus rien de réservé, réservation consommée',
    resv = 0 AND n_act = 0 AND n_con = 1,
    format('réservé=%s (0 attendu) actives=%s (0 attendue) consommées=%s (1 attendue)', resv, n_act, n_con));
END $$;

-- T04 — S-07 (livraison partielle) : seule la quantité expédiée est libérée
DO $$
DECLARE v record; so uuid; bl uuid; resv numeric; n_act int; qte numeric;
BEGIN
  v := _mk_vente235('T04');
  so := _mk_commande235(v.t, v.c, v.p, 'T04', 10);
  bl := _mk_bl235(v.t, v.c, v.p, 'T04', 4, so);   -- 4 sur 10
  PERFORM _expedier235(bl);

  SELECT COALESCE(sum(reserved_quantity), 0) INTO resv FROM stock_quantities WHERE product_id = v.p;
  SELECT count(*), COALESCE(max(quantity), 0) INTO n_act, qte
    FROM stock_reservations WHERE reference_id = so AND status = 'active';
  PERFORM _rec('T04', 'livraison de 4 sur une commande de 10 : 6 restent réservés pour la suite',
    resv = 6 AND n_act = 1 AND qte = 6,
    format('réservé=%s (6 attendu) réservations actives=%s (1 attendue) reste=%s (6 attendu)', resv, n_act, qte));
END $$;

-- T05 — S-05/S-06 sans commande : la sortie choisit le dépôt qui détient l'article
DO $$
DECLARE v record; bl uuid; qa numeric; whq numeric; rest numeric; mv record;
BEGIN
  v := _mk_vente235('T05');
  bl := _mk_bl235(v.t, v.c, v.p, 'T05', 6, NULL);
  PERFORM _expedier235(bl);

  SELECT stock_quantity INTO qa FROM products WHERE id = v.p;
  SELECT quantity INTO whq FROM stock_quantities WHERE product_id = v.p AND warehouse_id = v.wh;
  SELECT warehouse_id INTO mv FROM stock_movements WHERE reference_id = bl AND reference_type = 'delivery_note';
  SELECT COALESCE(sum(remaining_qty), 0) INTO rest FROM stock_valuation_layers WHERE product_id = v.p;
  PERFORM _rec('T05', 'BL sans commande : la sortie se prend sur le dépôt qui détient l''article, couche consommée',
    mv.warehouse_id = v.wh AND qa = 94 AND whq = 94 AND rest = 94,
    format('sortie=%s (attendu %s) article=%s dépôt=%s couches=%s', COALESCE(mv.warehouse_id::text, 'NULL'), v.wh, qa, whq, rest));
END $$;

-- T06 — S-05 (stock antérieur, non localisé) : la livraison rattache le stock au dépôt
--       au lieu de la refuser — c'est l'état des sociétés existantes, dont les
--       réceptions d'avant la 241 n'écrivaient aucune ligne de dépôt.
DO $$
DECLARE v record; bl uuid; qa numeric; whq numeric; n_lig int;
BEGIN
  v := _mk_vente235('T06');
  DELETE FROM stock_quantities WHERE product_id = v.p;            -- stock non localisé
  DELETE FROM stock_valuation_layers WHERE product_id = v.p;      -- ni couche (entrée d'avant la 241)
  bl := _mk_bl235(v.t, v.c, v.p, 'T06', 6, NULL);
  PERFORM _expedier235(bl);

  SELECT stock_quantity INTO qa FROM products WHERE id = v.p;
  SELECT COALESCE(sum(quantity), 0), count(*) INTO whq, n_lig
  FROM stock_quantities WHERE product_id = v.p AND warehouse_id = v.wh;
  PERFORM _rec('T06', 'stock non localisé (société existante) : la livraison de 6 rattache le reste au dépôt (94 et 94)',
    qa = 94 AND whq = 94 AND n_lig = 1,
    format('article=%s (94 attendu) dépôt=%s (94 attendu) lignes de dépôt=%s (1 attendue)', qa, whq, n_lig));
END $$;

DROP FUNCTION _expedier235(uuid);
DROP FUNCTION _mk_bl235(uuid, uuid, uuid, text, numeric, uuid);
DROP FUNCTION _mk_commande235(uuid, uuid, uuid, text, numeric);
DROP FUNCTION _mk_vente235(text);
SELECT _audit_assert('242');

