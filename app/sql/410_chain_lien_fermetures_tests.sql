-- ============================================================
-- 320_chain_lien_fermetures_tests.sql — L3 : ce que l'ANNULATION doit au lien
--
-- Source : doc/audit/PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md (lot L3, « banc
-- d'épreuve » — première brique : ce que la fermeture garantit), le §8 de la 312
-- (le geste que les maillons ajouteront) et l'en-tête de la 319 (« il n'appelle
-- pas le cycle du lien sur le chemin d'annulation : c'est le reste de L3 »).
--
--   T01  commande confirmée puis ANNULÉE : les deux liens du tour 1 passent
--        `rompu`, datés, motivés et signés, l'événement `chain.link_broken` dit
--        lequel et pourquoi, et le lien n'est plus « intact » (M-03) ;
--   T02  bon de livraison expédié puis ANNULÉ : le lien de sortie de stock est
--        rompu, et l'AVAL d'origine reste celui de la sortie — l'écriture de
--        contrepassation de la 253 est un fait neuf, pas une réécriture ;
--   T03  réception reçue puis ANNULÉE : les liens PAR LIGNE de la 319 (deux
--        lignes → deux liens) sont rompus, et la contrepassation de la 251 est
--        écrite — le pendant exact du maillon tracé la veille ;
--   T04  le REJEU ne double rien : annuler deux fois (le métier le tolère) ne
--        produit ni seconde fermeture, ni second événement ;
--   T05  l'ENTRÉE retrouvée du maillon des réservations : confirmer DEUX fois
--        sans annuler ne réserve qu'une fois, et ne trace qu'une fois
--        (`applique`) — c'est le rejeu, le maillon saute la ligne ;
--   T06  aucun lien à fermer est un cas ORDINAIRE : annuler un document jamais
--        expédié (rien de tracé) ne lève pas et n'écrit rien — c'est la raison
--        du choix de la fermeture GLOBALE, qui rapporte 0 (tête du fichier §2) ;
--   T07  le CLOISONNEMENT : l'annulation chez A ne rompt ni ne journalise rien
--        chez B, et B ne voit ni les liens, ni les traces, ni les événements de A ;
--   T08  la STRUCTURE : trois compagnons `zz_l3_`, tous APRÈS leur maillon métier
--        (nom et phase), SECURITY DEFINER, non exposés, et le corps réécrit de
--        `reserve_stock_on_sales_order_confirm` porte bien son entrée.
--
-- Ce que cette suite NE mesure PAS : ni les neuf maillons RPC (caisse, paie
-- versée, relevé manuel), ni le banc D1→D8 — les deux tranches suivantes de L3.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '410', false);
DELETE FROM _audit_results WHERE file = '320';

-- ─────────────────────────────────────────────────────────────
-- Outillage propre à ce fichier (préfixé `_`, hors contrôle des droits)
-- ─────────────────────────────────────────────────────────────

-- Deux articles à 100 en stock, un dépôt, un client.
DROP FUNCTION IF EXISTS _l320_vente(text);
CREATE OR REPLACE FUNCTION _l320_vente(p_nom text, OUT t uuid, OUT wh uuid, OUT c uuid,
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

-- Commande à DEUX lignes, puis confirmée (le maillon est un déclencheur UPDATE).
DROP FUNCTION IF EXISTS _l320_cmd(uuid, uuid, uuid, uuid, text);
CREATE OR REPLACE FUNCTION _l320_cmd(p_t uuid, p_c uuid, p1 uuid, p2 uuid, p_num text)
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
DROP FUNCTION IF EXISTS _l320_bl(uuid, uuid, uuid, uuid, uuid, text);
CREATE OR REPLACE FUNCTION _l320_bl(p_t uuid, p_c uuid, p1 uuid, p2 uuid, p_so uuid, p_num text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE bl uuid;
BEGIN
  INSERT INTO delivery_notes (tenant_id, number, customer_id, sales_order_id, delivery_date, status)
  VALUES (p_t, 'BL-' || p_num, p_c, p_so, CURRENT_DATE, 'pending') RETURNING id INTO bl;
  INSERT INTO delivery_note_lines (tenant_id, delivery_note_id, product_id, description, quantity)
  VALUES (p_t, bl, p1, 'Ligne 1', 3), (p_t, bl, p2, 'Ligne 2', 4);
  RETURN bl;
END $$;

-- Réception à DEUX lignes de quantités DIFFÉRENTES (7 et 3), en attente.
DROP FUNCTION IF EXISTS _l320_reception(text);
CREATE OR REPLACE FUNCTION _l320_reception(p_nom text,
  OUT t uuid, OUT wh uuid, OUT gr uuid, OUT l1 uuid, OUT l2 uuid)
LANGUAGE plpgsql AS $$
DECLARE v_sup uuid; v_po uuid; p1 uuid; p2 uuid;
BEGIN
  t := _mk_tenant(p_nom);
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

-- Les liens d'un document, avec l'état et le tour.
DROP FUNCTION IF EXISTS _l320_liens(uuid, text, uuid);
CREATE OR REPLACE FUNCTION _l320_liens(p_t uuid, p_amont_type text, p_amont_id uuid)
RETURNS TABLE(effet text, amont_ligne_id uuid, aval_type text, aval_id uuid,
              etat text, tour integer, ferme_le timestamptz, ferme_par uuid, motif text)
LANGUAGE sql AS $$
  SELECT dl.effet, dl.amont_ligne_id, dl.aval_type, dl.aval_id,
         dl.etat, dl.tour, dl.ferme_le, dl.ferme_par, dl.motif
  FROM document_links dl
  WHERE dl.tenant_id = p_t AND dl.amont_type = p_amont_type AND dl.amont_id = p_amont_id
  ORDER BY dl.effet, dl.amont_ligne_id, dl.tour
$$;

DROP FUNCTION IF EXISTS _l320_evt(uuid, text, uuid);
CREATE OR REPLACE FUNCTION _l320_evt(p_t uuid, p_nom text, p_agregat uuid)
RETURNS integer LANGUAGE sql AS $$
  SELECT count(*)::int FROM domain_events de
  WHERE de.tenant_id = p_t AND de.event_name = p_nom AND de.aggregate_id = p_agregat
$$;
-- ═════════════════════════════════════════════════════════════
-- T01 — Commande confirmée puis annulée : les liens du tour 1 sont ROMpus
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; so uuid; n_actifs int; n_actifs_avant int; n_rompus int; n_dates int; n_motifs int; n_signes int;
        n_evt_rompu int; n_intact_avant boolean; n_intact_apres boolean; v_motif text;
BEGIN
  v := _l320_vente('L3A');
  so := _l320_cmd(v.t, v.c, v.p1, v.p2, 'L3A');

  -- Avant l'annulation : deux liens actifs, et l'effet est « intact ».
  PERFORM _as_user();
  SELECT count(*) FILTER (WHERE etat = 'actif') INTO n_actifs_avant
    FROM _l320_liens(v.t, 'sales_orders', so);
  -- Le socle n'est PAS une API (`REVOKE … FROM authenticated`, 252 §14) : les
  -- lectures `chain_*` s'appellent ici comme les maillons les appellent — en tant
  -- que propriétaire. Les scénarios basculent avec `_as_user()` pour ce qui est
  -- du ressort de l'utilisateur (l'annulation), pas pour le socle.
  PERFORM set_config('role', 'none', true);
  n_intact_avant := chain_integrity_ok(v.t, 'sales_orders', so, 'stock_reservations',
    (SELECT aval_id FROM _l320_liens(v.t, 'sales_orders', so) WHERE etat = 'actif' LIMIT 1));

  -- L'ANNULATION : le métier libère les réservations (STK-02c) et la 320 ferme.
  PERFORM _as_user();
  UPDATE sales_orders SET status = 'cancelled' WHERE id = so;
  PERFORM set_config('role', 'none', true);

  SELECT count(*) FILTER (WHERE etat = 'actif'),
         count(*) FILTER (WHERE etat = 'rompu'),
         count(*) FILTER (WHERE etat = 'rompu' AND ferme_le IS NOT NULL),
         count(*) FILTER (WHERE etat = 'rompu' AND COALESCE(btrim(motif), '') <> ''),
         count(*) FILTER (WHERE etat = 'rompu' AND ferme_par IS NOT NULL),
         min(motif)
    INTO n_actifs, n_rompus, n_dates, n_motifs, n_signes, v_motif
    FROM _l320_liens(v.t, 'sales_orders', so);

  n_evt_rompu := _l320_evt(v.t, 'chain.link_broken', so);
  n_intact_apres := chain_integrity_ok(v.t, 'sales_orders', so, 'stock_reservations',
    (SELECT aval_id FROM _l320_liens(v.t, 'sales_orders', so) WHERE etat = 'rompu' LIMIT 1));

  PERFORM _rec('T01',
    'commande annulée : les 2 liens du tour 1 passent ROMpu, datés, motivés et signés, un événement `chain.link_broken` par lien, et l''effet n''est plus « intact » (M-03)',
    n_actifs = 0 AND n_rompus = 2 AND n_dates = 2 AND n_motifs = 2 AND n_signes = 2
      AND n_evt_rompu = 2 AND n_intact_avant IS TRUE AND n_intact_apres IS FALSE
      AND v_motif LIKE '%CV-L3A%',
    format('avant : actifs=%s intact=%s | après : actifs=%s rompus=%s datés=%s motivés=%s signés=%s événements=%s intact=%s motif=« %s »',
           n_actifs_avant, n_intact_avant, n_actifs, n_rompus, n_dates, n_motifs, n_signes,
           n_evt_rompu, n_intact_apres, left(COALESCE(v_motif, '—'), 60)));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T02 — Bon de livraison expédié puis annulé : le lien de sortie est rompu,
--   et l'aval d'origine reste celui de la SORTIE (la contrepassation est un
--   fait neuf, la 253 l'écrit ; le lien, lui, n'est pas réécrit).
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; so uuid; bl uuid; v_aval uuid;
        n_actifs int; n_rompus int; n_contrep int; n_sortie int; n_liens_justes int; v_ref text;
BEGIN
  v := _l320_vente('L3B');
  so := _l320_cmd(v.t, v.c, v.p1, v.p2, 'L3B');
  bl := _l320_bl(v.t, v.c, v.p1, v.p2, so, 'L3B');

  PERFORM _as_user();
  UPDATE delivery_notes SET status = 'shipped' WHERE id = bl;
  PERFORM set_config('role', 'none', true);
  SELECT aval_id INTO v_aval FROM _l320_liens(v.t, 'delivery_notes', bl)
   WHERE etat = 'actif' AND effet = 'sale.delivery.stock_out'
   ORDER BY amont_ligne_id LIMIT 1;

  PERFORM _as_user();
  UPDATE delivery_notes SET status = 'cancelled' WHERE id = bl;
  PERFORM set_config('role', 'none', true);

  SELECT count(*) FILTER (WHERE etat = 'actif'),
         count(*) FILTER (WHERE etat = 'rompu')
    INTO n_actifs, n_rompus
    FROM _l320_liens(v.t, 'delivery_notes', bl) WHERE effet = 'sale.delivery.stock_out';

  -- Chaque lien rompu pointe-t-il encore une SORTIE d'origine ?
  SELECT count(*) INTO n_liens_justes
    FROM _l320_liens(v.t, 'delivery_notes', bl) l
    JOIN stock_movements sm ON sm.id = l.aval_id
   WHERE l.effet = 'sale.delivery.stock_out' OR (l.etat = 'rompu'
         AND sm.reference_type = 'delivery_note' AND sm.movement_type = 'out');

  SELECT count(*) INTO n_contrep FROM stock_movements
   WHERE tenant_id = v.t AND reference_type = 'delivery_note_cancel' AND reference_id = bl;
  SELECT count(*) INTO n_sortie FROM stock_movements
   WHERE tenant_id = v.t AND reference_type = 'delivery_note' AND reference_id = bl AND movement_type = 'out';
  SELECT string_agg(DISTINCT sm.reference, ', ') INTO v_ref
    FROM stock_movements sm
   WHERE sm.tenant_id = v.t AND sm.reference_type = 'delivery_note_cancel' AND sm.reference_id = bl;

  PERFORM _rec('T02',
    'BL annulé : les 2 liens PAR LIGNE de la sortie de stock passent ROMpu et gardent l''AVAL de la sortie d''origine (l''aval de la ligne 1 est inchangé) ; les 2 sorties d''origine reçoivent leur contrepassation (fait neuf, la 253)',
    n_actifs = 0 AND n_rompus = 2 AND n_liens_justes = 2
      AND (SELECT aval_id FROM _l320_liens(v.t, 'delivery_notes', bl)
            WHERE etat = 'rompu' ORDER BY amont_ligne_id LIMIT 1) = v_aval
      AND n_contrep = 2 AND n_sortie = 2,
    format('liens actifs=%s rompus=%s (pointant une sortie d''origine=%s) aval ligne 1 avant=%s après=%s contrepassations=%s (réf. %s) sorties d''origine=%s',
           n_actifs, n_rompus, n_liens_justes, v_aval,
           (SELECT aval_id FROM _l320_liens(v.t, 'delivery_notes', bl)
             WHERE etat = 'rompu' ORDER BY amont_ligne_id LIMIT 1),
           n_contrep, COALESCE(v_ref, '—'), n_sortie));
END $$;
-- ═════════════════════════════════════════════════════════════
-- T03 — Réception reçue puis annulée : les liens PAR LIGNE de la 319 sont rompus
--   C'est le pendant exact du maillon tracé la veille (319) : N lignes → N liens,
--   et l'annulation rompt CES N liens (pas un lien d'en-tête qui n'existe pas).
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; n_liens int; n_actifs int; n_rompus int; n_lignes int; n_contrep int;
        n_evt int; n_intact boolean;
BEGIN
  v := _l320_reception('L3C');

  PERFORM _as_user();
  UPDATE goods_receipts SET status = 'received' WHERE id = v.gr;
  PERFORM set_config('role', 'none', true);
  SELECT count(*), count(DISTINCT amont_ligne_id) INTO n_liens, n_lignes
    FROM _l320_liens(v.t, 'goods_receipts', v.gr) WHERE etat = 'actif';
  n_intact := chain_integrity_ok(v.t, 'goods_receipts', v.gr, 'stock_movements',
    (SELECT aval_id FROM _l320_liens(v.t, 'goods_receipts', v.gr) WHERE etat = 'actif' LIMIT 1));

  PERFORM _as_user();
  UPDATE goods_receipts SET status = 'cancelled' WHERE id = v.gr;
  PERFORM set_config('role', 'none', true);

  SELECT count(*) FILTER (WHERE etat = 'actif'), count(*) FILTER (WHERE etat = 'rompu')
    INTO n_actifs, n_rompus FROM _l320_liens(v.t, 'goods_receipts', v.gr);
  SELECT count(*) INTO n_contrep FROM stock_movements
   WHERE tenant_id = v.t AND reference_type = 'goods_receipt_cancel' AND reference_id = v.gr;
  n_evt := _l320_evt(v.t, 'chain.link_broken', v.gr);

  PERFORM _rec('T03',
    'réception annulée : les 2 liens PAR LIGNE de la 319 sont ROMpus (un par ligne, la correspondance ligne → mouvement est conservée), les 2 entrées d''origine reçoivent leur contrepassation (251), et l''effet n''est plus intact',
    n_liens = 2 AND n_lignes = 2 AND n_intact IS TRUE
      AND n_actifs = 0 AND n_rompus = 2 AND n_contrep = 2 AND n_evt = 2,
    format('avant : liens=%s sur %s lignes intact=%s | après : actifs=%s rompus=%s contrepassations=%s événements=%s',
           n_liens, n_lignes, n_intact, n_actifs, n_rompus, n_contrep, n_evt));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T04 — Le REJEU ne double rien : annuler deux fois ne ferme qu'une fois
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; so uuid; n_rompus int; n_actifs int; n_evt int; n_motifs int;
BEGIN
  v := _l320_vente('L3D');
  so := _l320_cmd(v.t, v.c, v.p1, v.p2, 'L3D');

  PERFORM _as_user();
  UPDATE sales_orders SET status = 'cancelled' WHERE id = so;
  -- La seconde annulation : l'état ne change plus (déjà annulée). Le métier le
  -- tolère, et le compagnon doit se taire — sa garde est la transition, pas l'état.
  UPDATE sales_orders SET status = 'cancelled' WHERE id = so;
  PERFORM set_config('role', 'none', true);

  SELECT count(*) FILTER (WHERE etat = 'rompu'), count(*) FILTER (WHERE etat = 'actif'),
         count(*) FILTER (WHERE etat = 'rompu' AND ferme_le IS NOT NULL)
    INTO n_rompus, n_actifs, n_motifs
    FROM _l320_liens(v.t, 'sales_orders', so);
  n_evt := _l320_evt(v.t, 'chain.link_broken', so);

  PERFORM _rec('T04',
    'annuler deux fois ne double rien : 2 liens rompus (pas 4), aucune fermeture ni événement supplémentaire — la garde du compagnon est la TRANSITION d''état, comme celle du maillon métier',
    n_rompus = 2 AND n_actifs = 0 AND n_motifs = 2 AND n_evt = 2,
    format('rompus=%s (2 attendus) actifs=%s datés=%s événements=%s (2 attendus)', n_rompus, n_actifs, n_motifs, n_evt));
END $$;
-- ═════════════════════════════════════════════════════════════
-- T05 — L'ENTRÉE retrouvée du maillon des réservations (le rejeu ne double pas)
--   La 311 avait dû RETIRER `chain_avant` de ce maillon (le rouge de la suite 230
--   T04). La 320 le remet : confirmer une seconde fois — sans annuler — est un
--   REJEU, le maillon saute la ligne, la quantité réservée ne double pas, et la
--   trace dit `ignore` au lieu de mentir sur un second effet.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; so uuid; n_res int; n_actives int; n_applique int; n_ignore int; n_reserve numeric;
BEGIN
  v := _l320_vente('L3E');
  so := _l320_cmd(v.t, v.c, v.p1, v.p2, 'L3E');

  PERFORM _as_user();
  -- Le REJEU : on force la même transition en repassant par un état intermédiaire
  -- qui n'annule rien pour le stock (le métier ne libère que sur 'cancelled').
  UPDATE sales_orders SET status = 'draft' WHERE id = so;
  UPDATE sales_orders SET status = 'confirmed' WHERE id = so;
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO n_res FROM stock_reservations WHERE tenant_id = v.t AND reference_id = so;
  SELECT count(*) INTO n_actives FROM stock_reservations
   WHERE tenant_id = v.t AND reference_id = so AND status = 'active';
  SELECT COALESCE(sum(reserved_quantity), 0) INTO n_reserve FROM stock_quantities
   WHERE tenant_id = v.t AND product_id IN (v.p1, v.p2);
  SELECT count(*) FILTER (WHERE resultat = 'applique'), count(*) FILTER (WHERE resultat = 'ignore')
    INTO n_applique, n_ignore
    FROM chain_traces WHERE tenant_id = v.t AND effet = 'sale.order.reserved' AND amont_id = so;

  PERFORM _rec('T05',
    'confirmer deux fois sans annuler est un REJEU : 2 réservations (pas 4 — la quantité réservée ne double pas), UNE trace `applique` et les traces `ignore` du rejeu — c''est l''ENTRÉE que la 320 a rendue à ce maillon',
    n_res = 2 AND n_actives = 2 AND n_applique = 1 AND n_ignore >= 2,
    format('réservations=%s (2 attendues) dont actives=%s réservé total=%s | traces applique=%s ignore=%s',
           n_res, n_actives, n_reserve, n_applique, n_ignore));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T06 — Aucun lien à fermer est un cas ORDINAIRE : la fermeture globale rapporte 0
--   Un BL jamais expédié, une réception jamais reçue : rien n'a été tracé, donc
--   rien à rompre. C'est la DOCTRINE de la 312 §8 (« la globale RAPPORTE, la
--   ciblée REFUSE ») et la raison du choix de ce fichier : l'annulation d'un
--   document ordinaire ne doit pas échouer.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; bl uuid; gr record; v_bl uuid;
        n_leve boolean := false; msg text := '—'; n_liens int; n_evt int; n_traces int;
BEGIN
  v := _l320_vente('L3F');
  v_bl := _l320_cmd(v.t, v.c, v.p1, v.p2, 'L3F');
  bl := _l320_bl(v.t, v.c, v.p1, v.p2, v_bl, 'L3F');
  gr := _l320_reception('L3F2');

  PERFORM _as_user();
  BEGIN
    -- Jamais expédié, jamais reçu : rien n'a été tracé.
    UPDATE delivery_notes SET status = 'cancelled' WHERE id = bl;
    UPDATE goods_receipts SET status = 'cancelled' WHERE id = gr.gr;
  EXCEPTION WHEN OTHERS THEN
    n_leve := true; msg := SQLERRM;
  END;
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO n_liens FROM _l320_liens(v.t, 'delivery_notes', bl);
  n_evt := _l320_evt(v.t, 'chain.link_broken', bl) + _l320_evt(v.t, 'chain.link_broken', gr.gr);
  SELECT count(*) INTO n_traces FROM chain_traces
   WHERE tenant_id = v.t AND amont_id IN (bl, gr.gr);

  PERFORM _rec('T06',
    'annuler un document JAMAIS expédié (rien de tracé) ne lève pas, n''écrit ni lien, ni événement, ni trace : la fermeture est GLOBALE et rapporte 0 — l''annulation ordinaire n''échoue pas',
    n_leve IS FALSE AND n_liens = 0 AND n_evt = 0 AND n_traces = 0,
    format('exception=%s (%s) liens=%s événements de fermeture=%s traces=%s', n_leve, left(msg, 40), n_liens, n_evt, n_traces));
END $$;
-- ═════════════════════════════════════════════════════════════
-- T07 — Le CLOISONNEMENT : fermer chez A ne ferme rien chez B
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE va record; vb record; sa uuid; sb uuid; ua uuid; ub uuid;
        n_rompus_a int; n_actifs_b int; n_rompus_b int;
        n_liens_voisin int; n_ev_voisin int; n_tr_voisin int;
BEGIN
  va := _l320_vente('L3G');
  sa := _l320_cmd(va.t, va.c, va.p1, va.p2, 'L3G');
  vb := _l320_vente('L3H');
  sb := _l320_cmd(vb.t, vb.c, vb.p1, vb.p2, 'L3H');

  SELECT auth_id INTO ua FROM tenant_users WHERE tenant_id = va.t AND status = 'active' LIMIT 1;
  SELECT auth_id INTO ub FROM tenant_users WHERE tenant_id = vb.t AND status = 'active' LIMIT 1;
  IF ua IS NULL OR ub IS NULL THEN
    RAISE EXCEPTION 'Contexte de société non établi — le scénario ne prouverait rien';
  END IF;

  -- L'UTILISATEUR DE A annule SA commande. Le contexte doit être celui de A :
  -- c'est la RLS qui décide de la ligne que l'UPDATE atteint, et un scénario qui
  -- l'oublie mesurerait… rien (le rouge de ce scénario, mesuré le 02/10 : le
  -- contexte était resté sur B, l'UPDATE n'a touché aucune ligne, « A rompus=0 »).
  PERFORM set_config('request.jwt.claim.sub', ua::text, false);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, false);
  PERFORM set_config('app.active_tenant_id', va.t::text, false);
  PERFORM _as_user();
  UPDATE sales_orders SET status = 'cancelled' WHERE id = sa;
  PERFORM set_config('role', 'none', true);

  SELECT count(*) FILTER (WHERE etat = 'rompu') INTO n_rompus_a
    FROM _l320_liens(va.t, 'sales_orders', sa);

  -- B, dont la commande n'a pas bougé : ses liens doivent rester TOUS actifs.
  SELECT count(*) FILTER (WHERE etat = 'actif'), count(*) FILTER (WHERE etat = 'rompu')
    INTO n_actifs_b, n_rompus_b FROM _l320_liens(vb.t, 'sales_orders', sb);

  -- B se connecte : la RLS doit lui cacher liens, événements et traces de A.
  PERFORM set_config('request.jwt.claim.sub', ub::text, false);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', ub, 'role', 'authenticated')::text, false);
  PERFORM set_config('app.active_tenant_id', vb.t::text, false);
  PERFORM _as_user();

  SELECT count(*) INTO n_liens_voisin FROM document_links WHERE amont_id = sa;
  SELECT count(*) INTO n_ev_voisin FROM domain_events WHERE aggregate_id = sa;
  SELECT count(*) INTO n_tr_voisin FROM chain_traces WHERE tenant_id = va.t;

  PERFORM _rec('T07',
    'l''annulation chez A rompt SES 2 liens sans toucher ceux de B ; et B ne voit ni les liens, ni les traces, ni les événements de A (contrôle positif sur ses propres liens)',
    n_rompus_a = 2 AND n_actifs_b = 2 AND n_rompus_b = 0
      AND n_liens_voisin = 0 AND n_ev_voisin = 0 AND n_tr_voisin = 0,
    format('A rompus=%s | B actifs=%s rompus=%s | vus par B : liens de A=%s événements de A=%s traces de A=%s',
           n_rompus_a, n_actifs_b, n_rompus_b, n_liens_voisin, n_ev_voisin, n_tr_voisin));
END $$;
-- ═════════════════════════════════════════════════════════════
-- T08 — La STRUCTURE : trois compagnons, APRÈS leur maillon, jamais exposés
--   Une PROPRIÉTÉ, pas un compte : ce qui doit tenir demain, c'est qu'aucun
--   déclencheur métier de ces tables ne trie APRÈS les `zz_l3_` — l'ordre
--   alphabétique garantit que le compagnon voit ce que le maillon a écrit.
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE n_fonc int; n_exposes int; n_apres int; n_apres_moi int; n_trigger int; v_avant boolean;
BEGIN
  -- a) les trois fonctions existent, en SECURITY DEFINER.
  SELECT count(*) FILTER (WHERE p.prosecdef) INTO n_fonc
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname IN ('chain_l3_sales_order_cancel_liens',
                       'chain_l3_delivery_cancel_liens',
                       'chain_l3_goods_receipt_cancel_liens');

  -- b) aucune n'est exposée à `authenticated` ni à `anon` (leçon de la 228).
  SELECT count(*) INTO n_exposes
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname IN ('chain_l3_sales_order_cancel_liens',
                       'chain_l3_delivery_cancel_liens',
                       'chain_l3_goods_receipt_cancel_liens')
     AND (has_function_privilege('authenticated', p.oid, 'EXECUTE')
          OR has_function_privilege('anon', p.oid, 'EXECUTE'));

  -- c) les trois déclencheurs sont APRÈS (tgtype & 2 = 0), sur UPDATE (& 16).
  SELECT count(*) FILTER (WHERE (t.tgtype & 2) = 0 AND (t.tgtype & 16) = 16),
         count(*)
    INTO n_apres, n_trigger
    FROM pg_trigger t
   WHERE NOT t.tgisinternal
     AND t.tgname IN ('zz_l3_sales_order_cancel_liens',
                      'zz_l3_delivery_cancel_liens',
                      'zz_l3_goods_receipt_cancel_liens');

  -- d) AUCUN déclencheur métier de ces tables ne trie après eux : leur nom est
  --    le plus grand des déclencheurs UPDATE. C'est ce qui rend l'observation
  --    « APRÈS le maillon » structurelle, et pas un espoir.
  SELECT count(*) INTO n_apres_moi
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace ns ON ns.oid = c.relnamespace
   WHERE NOT t.tgisinternal AND ns.nspname = 'public'
     AND c.relname IN ('sales_orders', 'delivery_notes', 'goods_receipts')
     AND (t.tgtype & 16) = 16
     AND t.tgname NOT IN ('zz_l3_sales_order_cancel_liens',
                          'zz_l3_delivery_cancel_liens',
                          'zz_l3_goods_receipt_cancel_liens')
     AND t.tgname > (SELECT max(tgname) FROM pg_trigger
                      WHERE NOT tgisinternal
                        AND tgname IN ('zz_l3_sales_order_cancel_liens',
                                       'zz_l3_delivery_cancel_liens',
                                       'zz_l3_goods_receipt_cancel_liens'));

  -- e) le corps RÉÉCRIT du maillon des réservations porte bien son entrée.
  SELECT prosrc LIKE '%chain_avant%' AND prosrc LIKE '%CONTINUE%' INTO v_avant
    FROM pg_proc WHERE proname = 'reserve_stock_on_sales_order_confirm';

  PERFORM _rec('T08',
    'structure : 3 fonctions SECURITY DEFINER non exposées, 3 déclencheurs APRÈS sur UPDATE, aucun déclencheur métier qui trie après eux, et le maillon des réservations porte son entrée',
    n_fonc = 3 AND n_exposes = 0 AND n_apres = 3 AND n_trigger = 3
      AND n_apres_moi = 0 AND v_avant IS TRUE,
    format('fonctions SECURITY DEFINER=%s/3 exposées=%s | déclencheurs=%s dont APRÈS-UPDATE=%s | métier triant après eux=%s | entrée du maillon=%s',
           n_fonc, n_exposes, n_trigger, n_apres, n_apres_moi, v_avant));
END $$;

-- ─────────────────────────────────────────────────────────────
-- Le registre des échecs attendus reste VIDE : aucun scénario de ce fichier
-- n'a le droit d'échouer (doctrine AUD-A02).
-- ─────────────────────────────────────────────────────────────
SELECT _audit_assert('410');