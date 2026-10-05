-- ═══════════════════════════════════════════════════════════════════════════
-- 494_chain_l16_commande_livraison_tests.sql — L16 · commande → livraison
-- ═══════════════════════════════════════════════════════════════════════════
-- Cette suite éprouve le maillon de la 494 sur les épreuves du banc qui ont un
-- sens ici :
--   T01  NOMINAL : la commande confirmée rattache son bon de livraison ; la
--        colonne `sales_order_id` est posée ; le LIEN est posé (effet
--        `sale.order.to_delivery`) ;
--   T02  IDEMPOTENCE (D1) : le rejeu est REFUSÉ (unique_violation) et n'ajoute
--        aucun lien ;
--   T03  REFUS EXPLICITES : commande en brouillon, bon d'un autre client, bon
--        annulé, bon inexistant — quatre refus, quatre raisons ;
--   T04  LA FRISE RÉPOND (I-01) : `chain_document_arborescence` voit le bon
--        depuis la commande, et la commande depuis le bon ;
--   T05  ISOLATION (D8) : le voisin ne peut PAS rattacher la commande d'autrui,
--        et ne voit aucun lien.
--
-- Ce que cette suite NE joue PAS, et le dit : D2 (concurrence), D3 (panne
-- partielle), D5 (réouverture) restent hors de portée d'une suite SQL d'un seul
-- processus ; D6 (retour arrière) est tenu par construction (fichier
-- transactionnel), D7 (volume) n'a pas de sens sur une chaîne de deux pièces.
-- ═══════════════════════════════════════════════════════════════════════════
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '494', false);
DELETE FROM _audit_results WHERE file = '494';

-- ── T01 — LE NOMINAL : la commande rattache son bon de livraison ───────────
DO $$
DECLARE t uuid; c uuid; o uuid; d uuid; r jsonb; n int; v_so uuid;
BEGIN
  t := _mk_tenant('T494A');
  INSERT INTO customers (tenant_id, name, account_tiers)
    VALUES (t, 'Client 494', 'C0494') RETURNING id INTO c;
  INSERT INTO sales_orders (tenant_id, number, customer_id, order_date, status, subtotal, vat, total)
    VALUES (t, 'BC-494-1', c, '2026-03-01', 'confirmed', 1000, 200, 1200) RETURNING id INTO o;
  INSERT INTO delivery_notes (tenant_id, number, customer_id, delivery_date, status)
    VALUES (t, 'BL-494-1', c, '2026-03-05', 'shipped') RETURNING id INTO d;

  PERFORM _as_user();
  r := chain_l16_order_deliver(o, d);

  PERFORM _rec('T01a', 'la commande confirmée rattache son bon de livraison (jsonb de succès)',
    COALESCE((r->>'success')::boolean, false) AND (r->>'delivery_id')::uuid = d, r::text);

  SELECT sales_order_id INTO v_so FROM delivery_notes WHERE id = d;
  PERFORM _rec('T01b', 'le bon porte désormais sales_order_id (la colonne que personne n''écrivait)',
    v_so = o, 'sales_order_id = ' || COALESCE(v_so::text, 'NULL'));

  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_type = 'sales_orders' AND amont_id = o
     AND aval_type = 'delivery_notes' AND aval_id = d
     AND effet = 'sale.order.to_delivery' AND etat = 'actif';
  PERFORM _rec('T01c', 'le LIEN amont→aval est posé, actif, avec son effet (I-01)', n = 1, 'liens actifs = ' || n);
END $$;

-- ── T02 — IDEMPOTENCE (D1) : le rejeu est REFUSÉ ───────────────────────────
DO $$
DECLARE t uuid; c uuid; o uuid; d uuid; n int;
BEGIN
  t := _mk_tenant('T494B');
  INSERT INTO customers (tenant_id, name, account_tiers)
    VALUES (t, 'Client 494 B', 'C0494B') RETURNING id INTO c;
  INSERT INTO sales_orders (tenant_id, number, customer_id, order_date, status, subtotal, vat, total)
    VALUES (t, 'BC-494-B', c, '2026-03-02', 'confirmed', 500, 100, 600) RETURNING id INTO o;
  INSERT INTO delivery_notes (tenant_id, number, customer_id, delivery_date, status)
    VALUES (t, 'BL-494-B', c, '2026-03-06', 'shipped') RETURNING id INTO d;
  PERFORM _as_user();
  PERFORM chain_l16_order_deliver(o, d);
  BEGIN
    PERFORM chain_l16_order_deliver(o, d);
    PERFORM _rec('T02a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', false, 'second appel accepté !');
  EXCEPTION WHEN unique_violation THEN
    PERFORM _rec('T02a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', true, SQLERRM);
  END;
  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_id = o AND aval_id = d
     AND effet = 'sale.order.to_delivery' AND etat = 'actif';
  PERFORM _rec('T02b', 'un SEUL lien — le rejeu n''a rien ajouté', n = 1, 'liens = ' || n);
END $$;

-- ── T03 — REFUS EXPLICITES : quatre refus, quatre raisons ──────────────────
DO $$
DECLARE t uuid; c uuid; c2 uuid; o uuid; d uuid; o_draft uuid; d_cancel uuid; d_other uuid;
BEGIN
  t := _mk_tenant('T494C');
  INSERT INTO customers (tenant_id, name, account_tiers) VALUES
    (t, 'Client 494 C', 'C0494C'),
    (t, 'Client 494 C2', 'C0494C2');
  SELECT id INTO c  FROM customers WHERE tenant_id = t AND account_tiers = 'C0494C';
  SELECT id INTO c2 FROM customers WHERE tenant_id = t AND account_tiers = 'C0494C2';
  INSERT INTO sales_orders (tenant_id, number, customer_id, order_date, status, subtotal, vat, total)
    VALUES (t, 'BC-494-C', c, '2026-03-03', 'confirmed', 100, 20, 120) RETURNING id INTO o;
  INSERT INTO sales_orders (tenant_id, number, customer_id, order_date, status, subtotal, vat, total)
    VALUES (t, 'BC-494-Cd', c, '2026-03-03', 'draft', 100, 20, 120) RETURNING id INTO o_draft;
  INSERT INTO delivery_notes (tenant_id, number, customer_id, delivery_date, status)
    VALUES (t, 'BL-494-C', c, '2026-03-05', 'shipped') RETURNING id INTO d;
  INSERT INTO delivery_notes (tenant_id, number, customer_id, delivery_date, status)
    VALUES (t, 'BL-494-Ca', c, '2026-03-05', 'cancelled') RETURNING id INTO d_cancel;
  INSERT INTO delivery_notes (tenant_id, number, customer_id, delivery_date, status)
    VALUES (t, 'BL-494-Co', c2, '2026-03-05', 'shipped') RETURNING id INTO d_other;
  PERFORM _as_user();

  BEGIN
    PERFORM chain_l16_order_deliver(o_draft, d);
    PERFORM _rec('T03a', 'une commande en BROUILLON est refusée, avec sa raison', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03a', 'une commande en BROUILLON est refusée, avec sa raison', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_order_deliver(o, d_other);
    PERFORM _rec('T03b', 'un bon d''un AUTRE client est refusé', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03b', 'un bon d''un AUTRE client est refusé', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_order_deliver(o, d_cancel);
    PERFORM _rec('T03c', 'un bon ANNULE est refusé', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03c', 'un bon ANNULE est refusé', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_order_deliver(o, '00000000-0000-0000-0000-000000000001'::uuid);
    PERFORM _rec('T03d', 'un bon INEXISTANT est refusé (no_data_found)', false, 'accepté !');
  EXCEPTION WHEN no_data_found THEN
    PERFORM _rec('T03d', 'un bon INEXISTANT est refusé (no_data_found)', true, SQLERRM);
  END;
END $$;

-- ── T04 — LA FRISE RÉPOND (I-01) ───────────────────────────────────────────
DO $$
DECLARE t uuid; c uuid; o uuid; d uuid; n int;
BEGIN
  t := _mk_tenant('T494D');
  INSERT INTO customers (tenant_id, name, account_tiers)
    VALUES (t, 'Client 494 D', 'C0494D') RETURNING id INTO c;
  INSERT INTO sales_orders (tenant_id, number, customer_id, order_date, status, subtotal, vat, total)
    VALUES (t, 'BC-494-D', c, '2026-03-04', 'confirmed', 200, 40, 240) RETURNING id INTO o;
  INSERT INTO delivery_notes (tenant_id, number, customer_id, delivery_date, status)
    VALUES (t, 'BL-494-D', c, '2026-03-06', 'shipped') RETURNING id INTO d;
  PERFORM _as_user();
  PERFORM chain_l16_order_deliver(o, d);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'sales_orders', o, 'aval', 5, false)
   WHERE type = 'delivery_notes' AND id = d;
  PERFORM _rec('T04a', 'depuis la COMMANDE, la frise voit le BON DE LIVRAISON', n = 1, 'nœuds aval = ' || n);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'delivery_notes', d, 'amont', 5, false)
   WHERE type = 'sales_orders' AND id = o;
  PERFORM _rec('T04b', 'depuis le BON, la frise voit la COMMANDE', n = 1, 'nœuds amont = ' || n);
END $$;

-- ── T05 — ISOLATION (D8) : le voisin ne rattache pas, et ne voit rien ───────
DO $$
DECLARE ta uuid; tb uuid; ca uuid; oa uuid; da uuid; n int;
BEGIN
  ta := _mk_tenant('T494E1');
  INSERT INTO customers (tenant_id, name, account_tiers)
    VALUES (ta, 'Client E1', 'CE1') RETURNING id INTO ca;
  INSERT INTO sales_orders (tenant_id, number, customer_id, order_date, status, subtotal, vat, total)
    VALUES (ta, 'BC-494-E1', ca, '2026-03-07', 'confirmed', 100, 20, 120) RETURNING id INTO oa;
  INSERT INTO delivery_notes (tenant_id, number, customer_id, delivery_date, status)
    VALUES (ta, 'BL-494-E1', ca, '2026-03-08', 'shipped') RETURNING id INTO da;
  PERFORM _as_user();
  PERFORM chain_l16_order_deliver(oa, da);

  -- Société B : le décor change le tenant actif, et B tente de rattacher la
  -- commande de A — c'est le scénario du voisin.
  RESET ROLE;
  tb := _mk_tenant('T494E2');
  PERFORM _as_user();
  BEGIN
    PERFORM chain_l16_order_deliver(oa, da);
    PERFORM _rec('T05a', 'le VOISIN ne peut pas rattacher la commande d''autrui', false, 'accepté !');
  EXCEPTION WHEN no_data_found THEN
    PERFORM _rec('T05a', 'le VOISIN ne peut pas rattacher la commande d''autrui (no_data_found)', true, SQLERRM);
  END;

  SELECT count(*) INTO n FROM document_links
   WHERE amont_type = 'sales_orders' AND amont_id = oa AND aval_type = 'delivery_notes';
  PERFORM _rec('T05b', 'le voisin ne voit AUCUN lien de la société A', n = 0, 'liens visibles = ' || n);

  RESET ROLE;
  SELECT count(*) INTO n FROM document_links
   WHERE amont_id = oa AND aval_id = da AND effet = 'sale.order.to_delivery' AND tenant_id = ta;
  PERFORM _rec('T05c', 'le lien de A existe toujours, un seul, et reste à A', n = 1, 'liens de A = ' || n);
END $$;

-- ── Le VERDICT (G5 : toute suite rend un verdict) ─────────────────────────
SELECT _audit_assert('494');

