-- ═══════════════════════════════════════════════════════════════════════
-- 766 — L20, tranche 2 : LA RÉGÉNÉRATION EN CASCADE (suite)
-- ═══════════════════════════════════════════════════════════════════════
--
-- Voir l'en-tête de la migration pour le défaut, et le § « LES HUIT
-- SCÉNARIOS » pour la liste. Rouge d'abord : `chain_regenerer_en_cascade`
-- n'existe pas avant la 766 — T01 le constate, les autres s'appuient
-- sur `_mk766_env` (scénario 765 à deux articles, pour que N > 1
-- mouvements soit mesurable).
-- ═══════════════════════════════════════════════════════════════════════

SELECT set_config('audit.file', '766', false);

\ir ci/audit_helpers.sql
DELETE FROM _audit_results WHERE file = '766';

-- ─────────────────────────────────────────────────────────────
-- Décor : le même scénario que la 765 (réception → mouvements),
-- plus un second article pour que la fusion N→1 soit visible.
-- ─────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS _mk766_env(text, numeric);
CREATE OR REPLACE FUNCTION _mk766_env(p_nom text, p_prix numeric,
  OUT t uuid, OUT wh uuid, OUT sup uuid, OUT po uuid, OUT gr uuid)
LANGUAGE plpgsql AS $$
DECLARE v_p uuid;
BEGIN
  t := _mk_tenant('L20C' || p_nom);
  PERFORM ensure_standard_journals(t);
  INSERT INTO warehouses (tenant_id, code, name)
    VALUES (t, 'W-' || p_nom, 'Dépôt ' || p_nom) RETURNING id INTO wh;
  INSERT INTO suppliers (tenant_id, name)
    VALUES (t, 'Fournisseur ' || p_nom) RETURNING id INTO sup;
  -- Article A : prix 50, réception de 10
  INSERT INTO products (tenant_id, name, sku, type, cost_price, purchase_price)
    VALUES (t, 'Article A' || p_nom, 'A-' || p_nom, 'stock', 40, p_prix)
    RETURNING id INTO v_p;
  INSERT INTO purchase_orders (tenant_id, number, supplier_id, order_date, status)
    VALUES (t, 'CA-' || p_nom, sup, CURRENT_DATE, 'confirmed')
    RETURNING id INTO po;
  INSERT INTO purchase_order_lines (tenant_id, purchase_order_id, product_id,
    description, quantity, unit_price)
    VALUES (t, po, v_p, 'Article A' || p_nom, 10, p_prix);
  -- Article B : prix 100, réception de 5 (deuxième mouvement = N>1)
  INSERT INTO products (tenant_id, name, sku, type, cost_price, purchase_price)
    VALUES (t, 'Article B' || p_nom, 'B-' || p_nom, 'stock', 80, 100)
    RETURNING id INTO v_p;
  INSERT INTO purchase_order_lines (tenant_id, purchase_order_id, product_id,
    description, quantity, unit_price)
    VALUES (t, po, v_p, 'Article B' || p_nom, 5, 100);
  -- La réception → le déclencheur 241 crée les mouvements (goods_receipt)
  INSERT INTO goods_receipts (tenant_id, number, supplier_id, purchase_order_id,
    warehouse_id, receipt_date, status)
    VALUES (t, 'BR-' || p_nom, sup, po, wh, CURRENT_DATE, 'pending')
    RETURNING id INTO gr;
  INSERT INTO goods_receipt_lines (tenant_id, goods_receipt_id, product_id,
    description, quantity_ordered, quantity_received)
    SELECT t, gr, pol.product_id, 'Reçu', pol.quantity, pol.quantity
      FROM purchase_order_lines pol WHERE pol.purchase_order_id = po;
  UPDATE goods_receipts SET status = 'received' WHERE id = gr;
END $$;

-- CUMP d'un produit (état vivant de la "couche" CUMP)
DROP FUNCTION IF EXISTS _cump766(uuid, text);
CREATE OR REPLACE FUNCTION _cump766(p_t uuid, p_sku text)
RETURNS numeric LANGUAGE sql STABLE AS $$
  SELECT sq.unit_cost
    FROM stock_quantities sq
    JOIN products pr ON pr.id = sq.product_id
   WHERE sq.tenant_id = p_t AND pr.sku = p_sku;
$$;


-- ═══════════════════════════════════════════════════════════════════════
-- T01 — la cascade existe et RÉGÉNÈRE de vrai
-- ═══════════════════════════════════════════════════════════════════════
DO $$
DECLARE v record; lc_id uuid; r jsonb;
        cump_avant numeric; cump_apres numeric;
        liens_t1 int; liens_t2 int; logs int;
BEGIN
  v := _mk766_env('T01', 50);
  PERFORM set_config('app.current_tenant', v.t::text, false);
  INSERT INTO landed_costs (tenant_id, supplier_id, total_amount, distribution_method)
    VALUES (v.t, v.sup, 100, 'value') RETURNING id INTO lc_id;
  INSERT INTO landed_cost_receipts (tenant_id, landed_cost_id, receipt_id)
    VALUES (v.t, lc_id, v.gr);   -- le ciblage (contrat 658 unifié)
  PERFORM distribute_landed_cost(lc_id);
  cump_avant := _cump766(v.t, 'A-T01');

  -- le prix de revient est CORRIGÉ : 100 → 200
  UPDATE landed_costs SET total_amount = 200 WHERE id = lc_id;

  -- LA CASCADE : elle n'existe pas encore (rouge avant la 766)
  BEGIN
    r := chain_regenerer_en_cascade(v.t, 'landed_costs', lc_id,
                                    'prix de revient corrigé 100 → 200');
  EXCEPTION WHEN undefined_function THEN
    PERFORM _rec('T01', 'la cascade régénère de vrai un prix de revient corrigé (CUMP, lignes, liens, journal)',
      false, 'ROUGE AVANT : chain_regenerer_en_cascade n''existe pas — la tranche 2 n''est pas livrée');
    RETURN;
  END;

  cump_apres := _cump766(v.t, 'A-T01');
  SELECT count(*) INTO liens_t1 FROM document_links dl
   WHERE dl.tenant_id = v.t AND dl.amont_type = 'landed_costs'
     AND dl.amont_id = lc_id AND dl.etat = 'remplace';
  SELECT count(*) INTO liens_t2 FROM document_links dl
   WHERE dl.tenant_id = v.t AND dl.amont_type = 'landed_costs'
     AND dl.amont_id = lc_id AND dl.etat = 'actif';
  SELECT count(*) INTO logs FROM chain_regeneration_log l
   WHERE l.tenant_id = v.t AND l.amont_type = 'landed_costs'
     AND l.amont_id = lc_id AND l.cause LIKE '%prix de revient corrigé%';

  -- répartition 'value', base = 50×10 + 100×5 = 1000 :
  --   frais 100 → A reçoit 100×500/1000 = 50, soit +5/unité (50 → 55)
  --   frais 200 → A reçoit 200×500/1000 = 100, soit +10/unité (50 → 60)
  PERFORM _rec('T01', 'la cascade régénère de vrai un prix de revient corrigé (CUMP, lignes, liens, journal)',
    cump_avant = 55 AND cump_apres = 60
    AND liens_t1 >= 1 AND liens_t2 >= 1 AND logs >= 1
    AND (r->>'regeneres')::int >= 1,
    format('CUMP avant=%s (55 attendu) après=%s (60 attendu) | liens remplacés=%s actifs=%s | journal=%s | rapport=%s',
           cump_avant, cump_apres, liens_t1, liens_t2, logs, r));
END $$;

-- ═══════════════════════════════════════════════════════════════════════
-- T02 — sans société, refus : le cloisonnement ne s'ouvre pas
-- ═══════════════════════════════════════════════════════════════════════
DO $$
DECLARE v_refus boolean := false; v_msg text;
BEGIN
  BEGIN PERFORM chain_regenerer_en_cascade(NULL, 'landed_costs', gen_random_uuid(), 'cause');
  EXCEPTION WHEN check_violation THEN v_refus := true; v_msg := SQLERRM; END;

  PERFORM _rec('T02', 'sans société, la cascade est REFUSÉE',
    v_refus AND v_msg ILIKE '%société%',
    format('refus=%s (%s)', v_refus, left(COALESCE(v_msg,''), 70)));
END $$;

-- ═══════════════════════════════════════════════════════════════════════
-- T03 — contexte d'une AUTRE société : refusé (garde G4) ;
--      cause muette : refusée.
-- ═══════════════════════════════════════════════════════════════════════
DO $$
DECLARE t1 uuid; t2 uuid; sup1 uuid;
        v_refus boolean := false; v_msg text;
        v_refus2 boolean := false; v_msg2 text;
BEGIN
  t1 := _mk_tenant('L20CT03A', false);
  PERFORM set_config('app.current_tenant', t1::text, false);
  INSERT INTO suppliers (tenant_id, name) VALUES (t1, 'F') RETURNING id INTO sup1;
  t2 := _mk_tenant('L20CT03B', false);
  PERFORM set_config('app.current_tenant', t2::text, false);

  BEGIN PERFORM chain_regenerer_en_cascade(t1, 'landed_costs', gen_random_uuid(), 'cause');
  EXCEPTION WHEN check_violation THEN v_refus := true; v_msg := SQLERRM; END;

  BEGIN PERFORM chain_regenerer_en_cascade(t2, 'landed_costs', gen_random_uuid(), '   ');
  EXCEPTION WHEN check_violation THEN v_refus2 := true; v_msg2 := SQLERRM; END;

  PERFORM _rec('T03', 'contexte d''une autre société REFUSÉ (G4) ; cause muette REFUSÉE',
    v_refus AND v_msg ILIKE '%société%' AND v_refus2 AND v_msg2 ILIKE '%cause%',
    format('autre société=%s (%s) | cause muette=%s (%s)',
           v_refus, left(COALESCE(v_msg,''), 34),
           v_refus2, left(COALESCE(v_msg2,''), 34)));
END $$;

-- ═══════════════════════════════════════════════════════════════════════
-- T04 — racine SANS lien actif : refus nommé, il n'y a rien à régénérer
-- ═══════════════════════════════════════════════════════════════════════
DO $$
DECLARE v record; lc_id uuid; v_refus boolean := false; v_msg text;
BEGIN
  v := _mk766_env('T04', 50);
  PERFORM set_config('app.current_tenant', v.t::text, false);
  INSERT INTO landed_costs (tenant_id, supplier_id, total_amount, distribution_method)
    VALUES (v.t, v.sup, 100, 'value') RETURNING id INTO lc_id;

  BEGIN PERFORM chain_regenerer_en_cascade(v.t, 'landed_costs', lc_id, 'cause');
  EXCEPTION WHEN check_violation THEN v_refus := true; v_msg := SQLERRM; END;

  PERFORM _rec('T04', 'une racine sans lien actif est REFUSÉE nommée',
    v_refus AND v_msg ILIKE '%lien%',
    format('refus=%s (%s)', v_refus, left(COALESCE(v_msg,''), 70)));
END $$;


-- ═══════════════════════════════════════════════════════════════════════
-- T05 — l'HISTORIQUE se relit : avant ET après au journal, événements
--      par effet, et le résumé au catalogue (sinon 415 T05 rougit).
-- ═══════════════════════════════════════════════════════════════════════
DO $$
DECLARE v record; lc_id uuid; r jsonb;
        v_avant jsonb; v_apres text; n_evt int; n_cat int;
BEGIN
  v := _mk766_env('T05', 50);
  PERFORM set_config('app.current_tenant', v.t::text, false);
  INSERT INTO landed_costs (tenant_id, supplier_id, total_amount, distribution_method)
    VALUES (v.t, v.sup, 100, 'value') RETURNING id INTO lc_id;
  INSERT INTO landed_cost_receipts (tenant_id, landed_cost_id, receipt_id)
    VALUES (v.t, lc_id, v.gr);   -- le ciblage (contrat 658 unifié)
  PERFORM distribute_landed_cost(lc_id);
  UPDATE landed_costs SET total_amount = 200 WHERE id = lc_id;
  r := chain_regenerer_en_cascade(v.t, 'landed_costs', lc_id, 'prix de revient corrigé');

  SELECT l.avant INTO v_avant FROM chain_regeneration_log l
   WHERE l.tenant_id = v.t AND l.effet = 'stock.landed_cost.distributed'
   ORDER BY l.id DESC LIMIT 1;
  SELECT (l.apres IS NOT NULL)::text INTO v_apres FROM chain_regeneration_log l
   WHERE l.tenant_id = v.t AND l.effet = 'stock.landed_cost.distributed'
   ORDER BY l.id DESC LIMIT 1;
  SELECT count(*) INTO n_evt FROM domain_events e
   WHERE e.tenant_id = v.t AND e.event_name = 'chain.regenerated';
  SELECT count(*) INTO n_cat FROM webhook_event_catalog c
   WHERE c.event_name = 'chain.cascade_regenerated' AND c.is_active;

  PERFORM _rec('T05', 'l''historique se relit (avant/après, événements, catalogue)',
    v_avant IS NOT NULL AND v_apres = 'true' AND n_evt >= 1 AND n_cat = 1,
    format('avant=%s après=%s | chain.regenerated=%s | catalogue=%s',
           left(COALESCE(v_avant::text,''), 60), v_apres, n_evt, n_cat));
END $$;



-- ═══════════════════════════════════════════════════════════════════════
-- T06 — le REJEU est REFUSÉ nommé (contrat unifié 658 + 765) :
--      un frais déjà réparti ne repartage pas — et rien n'est
--      réécrit (lignes et CUMP inchangées).
-- ═══════════════════════════════════════════════════════════════════════
DO $$
DECLARE v record; lc_id uuid; r1 jsonb;
        n1 int; cump1 numeric; n2 int; cump2 numeric; msg text := '';
BEGIN
  v := _mk766_env('T06', 50);
  PERFORM set_config('app.current_tenant', v.t::text, false);
  INSERT INTO landed_costs (tenant_id, supplier_id, total_amount, distribution_method)
    VALUES (v.t, v.sup, 100, 'value') RETURNING id INTO lc_id;
  INSERT INTO landed_cost_receipts (tenant_id, landed_cost_id, receipt_id)
    VALUES (v.t, lc_id, v.gr);   -- le ciblage (contrat 658 unifié)
  r1 := distribute_landed_cost(lc_id);
  SELECT count(*) INTO n1 FROM landed_cost_lines WHERE landed_cost_id = lc_id;
  cump1 := _cump766(v.t, 'A-T06');

  BEGIN
    PERFORM distribute_landed_cost(lc_id);
  EXCEPTION WHEN OTHERS THEN
    msg := SQLERRM;
  END;
  SELECT count(*) INTO n2 FROM landed_cost_lines WHERE landed_cost_id = lc_id;
  cump2 := _cump766(v.t, 'A-T06');

  PERFORM _rec('T06', 'le rejeu est REFUSÉ nommé (« déjà réparti ») — rien n''est réécrit (contrat 658)',
    msg LIKE '%déjà réparti%' AND n2 = n1 AND cump2 = cump1 AND (r1->>'success') = 'true',
    format('refus=%s | lignes avant=%s après=%s | CUMP avant=%s après=%s',
           left(msg, 60), n1, n2, cump1, cump2));
END $$;

-- ═══════════════════════════════════════════════════════════════════════
-- T07 — un effet SANS repreneur déclaré est NOMMÉ dans le rapport,
--      pas passé sous silence — et ses liens restent intacts.
-- ═══════════════════════════════════════════════════════════════════════
DO $$
DECLARE v record; lc_id uuid; r jsonb; n_actifs int; mv uuid;
BEGIN
  v := _mk766_env('T07', 50);
  PERFORM set_config('app.current_tenant', v.t::text, false);
  INSERT INTO landed_costs (tenant_id, supplier_id, total_amount, distribution_method)
    VALUES (v.t, v.sup, 100, 'value') RETURNING id INTO lc_id;
  INSERT INTO landed_cost_receipts (tenant_id, landed_cost_id, receipt_id)
    VALUES (v.t, lc_id, v.gr);   -- le ciblage (contrat 658 unifié)
  PERFORM distribute_landed_cost(lc_id);
  SELECT id INTO mv FROM stock_movements WHERE tenant_id = v.t LIMIT 1;

  PERFORM link_documents(v.t, 'landed_costs', lc_id, 'stock_movements', mv,
                         'stock.landed_cost.sans_repreneur', 'adjusted_by');

  r := chain_regenerer_en_cascade(v.t, 'landed_costs', lc_id, 'prix corrigé');
  SELECT count(*) INTO n_actifs FROM document_links dl
   WHERE dl.tenant_id = v.t AND dl.amont_type = 'landed_costs'
     AND dl.amont_id = lc_id AND dl.effet = 'stock.landed_cost.sans_repreneur'
     AND dl.etat = 'actif';

  PERFORM _rec('T07', 'un effet sans repreneur est NOMMÉ et ses liens intacts',
    (r->'sans_repreneur') IS NOT NULL
    AND (r->'sans_repreneur')::text LIKE '%stock.landed_cost.sans_repreneur%'
    AND n_actifs >= 1,
    format('sans_repreneur=%s | liens intacts=%s', r->'sans_repreneur', n_actifs));
END $$;


-- ═══════════════════════════════════════════════════════════════════════
-- T08 — un lien ROMPU n'est pas suivi : la cascade s'arrête à la
--      rupture et la nomme (M-03 : passer ne répare pas).
-- ═══════════════════════════════════════════════════════════════════════
DO $$
DECLARE v record; lc_id uuid; r jsonb;
BEGIN
  v := _mk766_env('T08', 50);
  PERFORM set_config('app.current_tenant', v.t::text, false);
  INSERT INTO landed_costs (tenant_id, supplier_id, total_amount, distribution_method)
    VALUES (v.t, v.sup, 100, 'value') RETURNING id INTO lc_id;
  INSERT INTO landed_cost_receipts (tenant_id, landed_cost_id, receipt_id)
    VALUES (v.t, lc_id, v.gr);   -- le ciblage (contrat 658 unifié)
  PERFORM distribute_landed_cost(lc_id);
  UPDATE landed_costs SET total_amount = 200 WHERE id = lc_id;

  PERFORM chain_lien_rompre(v.t, 'landed_costs', lc_id,
                            'stock.landed_cost.distributed',
                            'annulation métier de test (766 T08)');

  r := chain_regenerer_en_cascade(v.t, 'landed_costs', lc_id, 'prix corrigé');

  PERFORM _rec('T08', 'un lien rompu n''est pas suivi — arrêt nommé (M-03)',
    (r->>'regeneres')::int = 0
    AND (r->'ruptures')::text LIKE '%stock.landed_cost.distributed%',
    format('rapport=%s', r));
END $$;

DROP FUNCTION _mk766_env(text, numeric);
DROP FUNCTION _cump766(uuid, text);
SELECT _audit_assert('766');

