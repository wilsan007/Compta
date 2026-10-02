-- ============================================================
-- 319_chain_reception_tests.sql — LA RÉCEPTION, tracée PAR LIGNE (L3)
--
-- Source : inventaire de L1, tranche 4, §5 — « la réception de marchandise reste
-- non tracée : N mouvements à partir de N lignes, la correspondance ligne → ligne
-- demande la réécriture du corps (doctrine 311) ».
--
--   T01  une réception de DEUX lignes produit DEUX liens, et chacun désigne SA
--        ligne — c'est ce qu'un compagnon ne pouvait pas faire, et le seul
--        motif admis par la 311 pour réécrire un corps métier ;
--   T02  le lien porte la BONNE quantité, et désigne le mouvement du bon article,
--        du bon dépôt — la correspondance est exacte, pas seulement présente ;
--   T03  le maillon se TRACE (`applique`) et publie son événement ;
--   T04  une ligne à quantité nulle n'entre pas et ne se trace pas — le cas
--        ordinaire n'est pas un effet manqué ;
--   T05  le REJEU ne double ni le stock ni les liens — la réception déjà reçue
--        ne repasse pas par le maillon ;
--   T06  le contrat d'effet est déclaré et actif (la porte G2 l'exige) ;
--   T07  la société voisine ne voit ni les liens, ni les traces, ni l'événement.
--
-- Ce que cette suite NE mesure PAS : le cycle du lien (`chain_lien_fermer`) sur
-- l'annulation — aucun maillon ne l'appelle encore, c'est le reste de L3.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '319', false);
DELETE FROM _audit_results WHERE file = '319';

-- ─────────────────────────────────────────────────────────────
-- Décor : DEUX articles, une commande à deux lignes, et une réception de deux
-- lignes de quantités DIFFÉRENTES (7 et 3) — c'est ce qui rend la correspondance
-- ligne → ligne mesurable : un lien qui désignerait « n'importe quel mouvement »
-- serait indistinguable si les quantités étaient égales.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION _mk_reception319(p_nom text,
  OUT t uuid, OUT wh uuid, OUT gr uuid, OUT l1 uuid, OUT l2 uuid, OUT mv1 uuid, OUT mv2 uuid)
LANGUAGE plpgsql AS $$
DECLARE v_sup uuid; v_po uuid; p1 uuid; p2 uuid;
BEGIN
  t  := _mk_tenant(p_nom);
  PERFORM ensure_standard_journals(t);

  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt ' || p_nom)
    RETURNING id INTO wh;
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Fournisseur ' || p_nom) RETURNING id INTO v_sup;

  INSERT INTO products (tenant_id, name, sku, type, cost_price, purchase_price)
    VALUES (t, 'A1 ' || p_nom, 'A1-' || p_nom, 'stock', 40, 45) RETURNING id INTO p1;
  INSERT INTO products (tenant_id, name, sku, type, cost_price, purchase_price)
    VALUES (t, 'A2 ' || p_nom, 'A2-' || p_nom, 'stock', 10, 12) RETURNING id INTO p2;

  INSERT INTO purchase_orders (tenant_id, number, supplier_id, order_date, status)
    VALUES (t, 'CA-' || p_nom, v_sup, CURRENT_DATE, 'confirmed') RETURNING id INTO v_po;
  INSERT INTO purchase_order_lines (tenant_id, purchase_order_id, product_id, description, quantity, unit_price)
    VALUES (t, v_po, p1, 'A1', 10, 7), (t, v_po, p2, 'A2', 5, 3);

  INSERT INTO goods_receipts (tenant_id, number, supplier_id, purchase_order_id, warehouse_id, receipt_date, status)
    VALUES (t, 'BR-' || p_nom, v_sup, v_po, wh, CURRENT_DATE, 'pending') RETURNING id INTO gr;

  INSERT INTO goods_receipt_lines (tenant_id, goods_receipt_id, product_id, description,
                                   quantity_ordered, quantity_received)
    VALUES (t, gr, p1, 'A1', 10, 7) RETURNING id INTO l1;
  INSERT INTO goods_receipt_lines (tenant_id, goods_receipt_id, product_id, description,
                                   quantity_ordered, quantity_received)
    VALUES (t, gr, p2, 'A2', 5, 3) RETURNING id INTO l2;
END $$;

-- ─────────────────────────────────────────────────────────────
-- T01 — deux lignes, deux liens, chacun sur SA ligne
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v record; n_liens int; n_corrects int;
BEGIN
  v := _mk_reception319('S319A');
  UPDATE goods_receipts SET status = 'received' WHERE id = v.gr;

  SELECT count(*) INTO n_liens FROM document_links
   WHERE tenant_id = v.t AND amont_type = 'goods_receipts' AND amont_id = v.gr
     AND effet = 'purchase.receipt.stock_in';

  -- Chaque lien désigne le mouvement DU PRODUIT de sa ligne : c'est la
  -- correspondance ligne → ligne, que l'extérieur ne pouvait pas deviner.
  SELECT count(*) INTO n_corrects
    FROM document_links dl
    JOIN goods_receipt_lines l ON l.id = dl.amont_ligne_id
    JOIN stock_movements m     ON m.id = dl.aval_id
   WHERE dl.tenant_id = v.t AND dl.amont_id = v.gr AND l.product_id = m.product_id;

  PERFORM _rec('T01',
    'une réception de DEUX lignes produit DEUX liens, et chacun désigne le mouvement du produit de SA ligne — la correspondance ligne → ligne, qu''aucun compagnon ne pouvait établir',
    n_liens = 2 AND n_corrects = 2,
    format('liens=%s (2 attendus), liens sur la bonne ligne=%s (2 attendus)', n_liens, n_corrects));
END $$;

-- ─────────────────────────────────────────────────────────────
-- T02 — le lien dit la bonne quantité, le bon dépôt
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v record; n_exacts int; n_mv int;
BEGIN
  v := _mk_reception319('S319B');
  UPDATE goods_receipts SET status = 'received' WHERE id = v.gr;

  SELECT count(*) INTO n_exacts
    FROM document_links dl
    JOIN goods_receipt_lines l ON l.id = dl.amont_ligne_id
    JOIN stock_movements m     ON m.id = dl.aval_id
   WHERE dl.tenant_id = v.t AND dl.amont_id = v.gr
     AND (dl.payload ->> 'quantity')::numeric = l.quantity_received
     AND m.quantity = l.quantity_received
     AND m.warehouse_id = v.wh;

  SELECT count(*) INTO n_mv FROM stock_movements
   WHERE tenant_id = v.t AND reference_type = 'goods_receipt' AND reference_id = v.gr;

  PERFORM _rec('T02',
    'le lien porte la quantité RÉELLEMENT reçue, et désigne le mouvement du bon article, au bon dépôt : la correspondance est exacte, pas seulement présente',
    n_exacts = 2 AND n_mv = 2,
    format('liens exacts=%s (2 attendus), mouvements de la réception=%s (2 attendus)', n_exacts, n_mv));
END $$;

-- ─────────────────────────────────────────────────────────────
-- T03 — le maillon se trace, et publie son événement
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v record; n_traces int; n_events int;
BEGIN
  v := _mk_reception319('S319C');
  UPDATE goods_receipts SET status = 'received' WHERE id = v.gr;

  SELECT count(*) INTO n_traces FROM chain_traces
   WHERE tenant_id = v.t AND effet = 'purchase.receipt.stock_in' AND resultat = 'applique';

  SELECT count(*) INTO n_events FROM domain_events
   WHERE tenant_id = v.t AND event_name = 'goods_receipts.received' AND aggregate_id = v.gr;

  PERFORM _rec('T03',
    'la réception se TRACE (`applique`, la sortie du maillon) et publie son événement : le maillon est piloté, pas seulement exécuté',
    n_traces >= 1 AND n_events = 1,
    format('traces applique=%s (au moins 1), événements=%s (1 attendu)', n_traces, n_events));
END $$;


-- ─────────────────────────────────────────────────────────────
-- T04 — une ligne à zéro n'entre pas, et ne se trace pas
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v record; n_liens int; n_mv int;
BEGIN
  v := _mk_reception319('S319D');

  -- Une ligne AJOUTÉE avant la réception, avec 0 reçu : elle ne doit produire
  -- ni mouvement, ni lien — le maillon ne la voit même pas.
  INSERT INTO goods_receipt_lines (tenant_id, goods_receipt_id, product_id, description,
                                   quantity_ordered, quantity_received)
  SELECT v.t, v.gr, p.id, 'A3 non reçu', 4, 0 FROM products p
   WHERE p.tenant_id = v.t
     AND p.id NOT IN (SELECT product_id FROM goods_receipt_lines WHERE goods_receipt_id = v.gr)
   LIMIT 1;

  UPDATE goods_receipts SET status = 'received' WHERE id = v.gr;

  SELECT count(*) INTO n_liens FROM document_links
   WHERE tenant_id = v.t AND amont_id = v.gr AND effet = 'purchase.receipt.stock_in';
  SELECT count(*) INTO n_mv FROM stock_movements
   WHERE tenant_id = v.t AND reference_type = 'goods_receipt' AND reference_id = v.gr;

  PERFORM _rec('T04',
    'une ligne à quantité nulle ne produit ni mouvement ni lien : le cas ordinaire n''est pas un effet manqué, il n''existe pas',
    n_liens = 2 AND n_mv = 2,
    format('liens=%s (2 attendus, la ligne à 0 exclue), mouvements=%s (2 attendus)', n_liens, n_mv));
END $$;

-- ─────────────────────────────────────────────────────────────
-- T05 — le rejeu ne double rien
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v record; n_mv1 int; n_l1 int; n_mv2 int; n_l2 int;
BEGIN
  v := _mk_reception319('S319E');
  UPDATE goods_receipts SET status = 'received' WHERE id = v.gr;

  SELECT count(*) INTO n_mv1 FROM stock_movements WHERE tenant_id = v.t AND reference_id = v.gr;
  SELECT count(*) INTO n_l1  FROM document_links   WHERE tenant_id = v.t AND amont_id = v.gr;

  -- Le rejeu : la réception est DÉJÀ reçue. Le garde du corps (`OLD.status`) et
  -- l'entrée du maillon (`chain_avant`, faux sur un lien existant) le refusent.
  UPDATE goods_receipts SET status = 'received' WHERE id = v.gr;
  UPDATE goods_receipts SET notes = 'relu' WHERE id = v.gr;

  SELECT count(*) INTO n_mv2 FROM stock_movements WHERE tenant_id = v.t AND reference_id = v.gr;
  SELECT count(*) INTO n_l2  FROM document_links   WHERE tenant_id = v.t AND amont_id = v.gr;

  PERFORM _rec('T05',
    'un rejeu de la réception ne double NI le stock NI les liens : le garde du corps et l''entrée du maillon le refusent tous les deux',
    n_mv1 = 2 AND n_mv2 = 2 AND n_l1 = 2 AND n_l2 = 2,
    format('mouvements %s → %s, liens %s → %s (2 et 2 attendus)', n_mv1, n_mv2, n_l1, n_l2));
END $$;

-- ─────────────────────────────────────────────────────────────
-- T06 — le contrat d'effet est déclaré et actif
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE c boolean; cmd text;
BEGIN
  SELECT actif, journal_code INTO c, cmd FROM document_effects
   WHERE tenant_id IS NULL AND document_type = 'goods_receipts'
     AND evenement = 'received' AND effet = 'purchase.receipt.stock_in';

  PERFORM _rec('T06',
    'le contrat « goods_receipts / received / purchase.receipt.stock_in » est déclaré et ACTIF, journal ST : sans lui, chaque réception tracerait « contrat manquant » (porte G2)',
    c IS TRUE AND cmd = 'ST',
    format('actif=%s, journal=%s (« ST » attendu)', c, cmd));
END $$;

-- ─────────────────────────────────────────────────────────────
-- T07 — la société voisine ne voit rien
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v record; b uuid; u uuid; n_liens int; n_traces int; n_events int;
BEGIN
  v := _mk_reception319('S319F');
  UPDATE goods_receipts SET status = 'received' WHERE id = v.gr;

  b := _mk_tenant('S319G');
  SELECT auth_id INTO u FROM tenant_users WHERE tenant_id = b AND status = 'active' LIMIT 1;
  PERFORM set_config('request.jwt.claim.sub', u::text, false);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, false);
  PERFORM set_config('app.active_tenant_id', b::text, false);
  PERFORM set_config('role', 'authenticated', true);

  SELECT count(*) INTO n_liens  FROM document_links WHERE tenant_id = v.t AND amont_id = v.gr;
  SELECT count(*) INTO n_traces FROM chain_traces   WHERE tenant_id = v.t AND amont_id = v.gr;
  SELECT count(*) INTO n_events FROM domain_events  WHERE tenant_id = v.t AND aggregate_id = v.gr;

  PERFORM _rec('T07',
    'la société voisine ne voit ni les liens, ni les traces, ni l''événement de la réception : le chaînage est cloisonné comme le reste',
    n_liens = 0 AND n_traces = 0 AND n_events = 0,
    format('liens=%s, traces=%s, événements=%s (0 attendu partout)', n_liens, n_traces, n_events));
END $$;

SELECT _audit_assert('319');

