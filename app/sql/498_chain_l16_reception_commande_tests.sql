-- ═══════════════════════════════════════════════════════════════════════════
-- 498_chain_l16_reception_commande_tests.sql — L16 · réception → commande (achats)
-- ═══════════════════════════════════════════════════════════════════════════
--   T01  NOMINAL : la commande d'achat rattache sa réception ; la colonne
--        `goods_receipts.purchase_order_id` est posée ; le LIEN est posé
--        (effet `purchase.order.to_receipt`) ;
--   T02  IDEMPOTENCE (D1) : le rejeu est REFUSÉ (unique_violation) ;
--   T03  REFUS EXPLICITES : commande brouillon, commande annulée, réception
--        annulée, autre fournisseur — quatre refus, quatre raisons ;
--   T04  LA FRISE RÉPOND (I-01) : la frise voit la réception depuis la commande,
--        et la commande depuis la réception ;
--   T05  ISOLATION (D8) : le voisin ne rattache pas, et ne voit aucun lien.
--
-- D2 (concurrence), D3 (panne partielle), D5 (réouverture) restent hors de
-- portée d'une suite SQL d'un seul processus ; D6 tenu par construction ; D7
-- sans objet sur une chaîne de deux pièces.
-- ═══════════════════════════════════════════════════════════════════════════
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '498', false);
DELETE FROM _audit_results WHERE file = '498';

-- ── T01 — LE NOMINAL : la commande rattache sa réception ───────────────────
DO $$
DECLARE t uuid; s uuid; o uuid; rcp uuid; r jsonb; n int; v_po uuid;
BEGIN
  t := _mk_tenant('T498A');
  INSERT INTO suppliers (tenant_id, name, account_tiers)
    VALUES (t, 'Fournisseur 498', 'F0498') RETURNING id INTO s;
  INSERT INTO purchase_orders (tenant_id, number, supplier_id, order_date, status, subtotal, vat, total)
    VALUES (t, 'CA-498-1', s, '2026-03-01', 'confirmed', 1000, 200, 1200) RETURNING id INTO o;
  INSERT INTO goods_receipts (tenant_id, number, supplier_id, receipt_date, status)
    VALUES (t, 'BR-498-1', s, '2026-03-05', 'received') RETURNING id INTO rcp;

  PERFORM _as_user();
  r := chain_l16_receipt_order(o, rcp);

  PERFORM _rec('T01a', 'la commande d''achat rattache sa réception (jsonb de succès)',
    COALESCE((r->>'success')::boolean, false) AND (r->>'receipt_id')::uuid = rcp, r::text);

  SELECT purchase_order_id INTO v_po FROM goods_receipts WHERE id = rcp;
  PERFORM _rec('T01b', 'la réception porte désormais purchase_order_id (la colonne que personne n''écrivait)',
    v_po = o, 'purchase_order_id = ' || COALESCE(v_po::text, 'NULL'));

  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_type = 'purchase_orders' AND amont_id = o
     AND aval_type = 'goods_receipts' AND aval_id = rcp
     AND effet = 'purchase.order.to_receipt' AND etat = 'actif';
  PERFORM _rec('T01c', 'le LIEN amont→aval est posé, actif, avec son effet (I-01)', n = 1, 'liens actifs = ' || n);
END $$;

-- ── T02 — IDEMPOTENCE (D1) : le rejeu est REFUSÉ ───────────────────────────
DO $$
DECLARE t uuid; s uuid; o uuid; rcp uuid; n int;
BEGIN
  t := _mk_tenant('T498B');
  INSERT INTO suppliers (tenant_id, name, account_tiers)
    VALUES (t, 'Fournisseur 498 B', 'F0498B') RETURNING id INTO s;
  INSERT INTO purchase_orders (tenant_id, number, supplier_id, order_date, status, subtotal, vat, total)
    VALUES (t, 'CA-498-B', s, '2026-03-02', 'confirmed', 500, 100, 600) RETURNING id INTO o;
  INSERT INTO goods_receipts (tenant_id, number, supplier_id, receipt_date, status)
    VALUES (t, 'BR-498-B', s, '2026-03-06', 'received') RETURNING id INTO rcp;
  PERFORM _as_user();
  PERFORM chain_l16_receipt_order(o, rcp);
  BEGIN
    PERFORM chain_l16_receipt_order(o, rcp);
    PERFORM _rec('T02a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', false, 'second appel accepté !');
  EXCEPTION WHEN unique_violation THEN
    PERFORM _rec('T02a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', true, SQLERRM);
  END;
  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_id = o AND aval_id = rcp
     AND effet = 'purchase.order.to_receipt' AND etat = 'actif';
  PERFORM _rec('T02b', 'un SEUL lien — le rejeu n''a rien ajouté', n = 1, 'liens = ' || n);
END $$;

-- ── T03 — REFUS EXPLICITES : quatre refus, quatre raisons ──────────────────
DO $$
DECLARE t uuid; s uuid; s2 uuid; o uuid; o_draft uuid; o_cancel uuid; rcp uuid; rcp_cancel uuid; rcp_other uuid;
BEGIN
  t := _mk_tenant('T498C');
  INSERT INTO suppliers (tenant_id, name, account_tiers) VALUES
    (t, 'Fournisseur 498 C', 'F0498C'),
    (t, 'Fournisseur 498 C2', 'F0498C2');
  SELECT id INTO s  FROM suppliers WHERE tenant_id = t AND account_tiers = 'F0498C';
  SELECT id INTO s2 FROM suppliers WHERE tenant_id = t AND account_tiers = 'F0498C2';
  INSERT INTO purchase_orders (tenant_id, number, supplier_id, order_date, status, subtotal, vat, total)
    VALUES (t, 'CA-498-C', s, '2026-03-03', 'confirmed', 100, 20, 120) RETURNING id INTO o;
  INSERT INTO purchase_orders (tenant_id, number, supplier_id, order_date, status, subtotal, vat, total)
    VALUES (t, 'CA-498-Cd', s, '2026-03-03', 'draft', 100, 20, 120) RETURNING id INTO o_draft;
  INSERT INTO purchase_orders (tenant_id, number, supplier_id, order_date, status, subtotal, vat, total)
    VALUES (t, 'CA-498-Cx', s, '2026-03-03', 'cancelled', 100, 20, 120) RETURNING id INTO o_cancel;
  INSERT INTO goods_receipts (tenant_id, number, supplier_id, receipt_date, status)
    VALUES (t, 'BR-498-C', s, '2026-03-05', 'received') RETURNING id INTO rcp;
  INSERT INTO goods_receipts (tenant_id, number, supplier_id, receipt_date, status)
    VALUES (t, 'BR-498-Cc', s, '2026-03-05', 'cancelled') RETURNING id INTO rcp_cancel;
  INSERT INTO goods_receipts (tenant_id, number, supplier_id, receipt_date, status)
    VALUES (t, 'BR-498-Co', s2, '2026-03-05', 'received') RETURNING id INTO rcp_other;
  PERFORM _as_user();

  BEGIN
    PERFORM chain_l16_receipt_order(o_draft, rcp);
    PERFORM _rec('T03a', 'une commande en BROUILLON est refusée, avec sa raison', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03a', 'une commande en BROUILLON est refusée, avec sa raison', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_receipt_order(o_cancel, rcp);
    PERFORM _rec('T03b', 'une commande ANNULÉE est refusée', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03b', 'une commande ANNULÉE est refusée', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_receipt_order(o, rcp_cancel);
    PERFORM _rec('T03c', 'une réception ANNULÉE est refusée', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03c', 'une réception ANNULÉE est refusée', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_receipt_order(o, rcp_other);
    PERFORM _rec('T03d', 'une réception d''un AUTRE fournisseur est refusée', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03d', 'une réception d''un AUTRE fournisseur est refusée', true, SQLERRM);
  END;
END $$;

-- ── T04 — LA FRISE RÉPOND (I-01) ───────────────────────────────────────────
DO $$
DECLARE t uuid; s uuid; o uuid; rcp uuid; n int;
BEGIN
  t := _mk_tenant('T498D');
  INSERT INTO suppliers (tenant_id, name, account_tiers)
    VALUES (t, 'Fournisseur 498 D', 'F0498D') RETURNING id INTO s;
  INSERT INTO purchase_orders (tenant_id, number, supplier_id, order_date, status, subtotal, vat, total)
    VALUES (t, 'CA-498-D', s, '2026-03-04', 'confirmed', 200, 40, 240) RETURNING id INTO o;
  INSERT INTO goods_receipts (tenant_id, number, supplier_id, receipt_date, status)
    VALUES (t, 'BR-498-D', s, '2026-03-06', 'received') RETURNING id INTO rcp;
  PERFORM _as_user();
  PERFORM chain_l16_receipt_order(o, rcp);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'purchase_orders', o, 'aval', 5, false)
   WHERE type = 'goods_receipts' AND id = rcp;
  PERFORM _rec('T04a', 'depuis la COMMANDE D''ACHAT, la frise voit la RÉCEPTION', n = 1, 'nœuds aval = ' || n);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'goods_receipts', rcp, 'amont', 5, false)
   WHERE type = 'purchase_orders' AND id = o;
  PERFORM _rec('T04b', 'depuis la RÉCEPTION, la frise voit la COMMANDE D''ACHAT', n = 1, 'nœuds amont = ' || n);
END $$;

-- ── T05 — ISOLATION (D8) : le voisin ne rattache pas, et ne voit rien ───────
DO $$
DECLARE ta uuid; tb uuid; sa uuid; oa uuid; ra uuid; n int;
BEGIN
  ta := _mk_tenant('T498E1');
  INSERT INTO suppliers (tenant_id, name, account_tiers)
    VALUES (ta, 'Fournisseur E1', 'FE1') RETURNING id INTO sa;
  INSERT INTO purchase_orders (tenant_id, number, supplier_id, order_date, status, subtotal, vat, total)
    VALUES (ta, 'CA-498-E1', sa, '2026-03-07', 'confirmed', 100, 20, 120) RETURNING id INTO oa;
  INSERT INTO goods_receipts (tenant_id, number, supplier_id, receipt_date, status)
    VALUES (ta, 'BR-498-E1', sa, '2026-03-08', 'received') RETURNING id INTO ra;
  PERFORM _as_user();
  PERFORM chain_l16_receipt_order(oa, ra);

  RESET ROLE;
  tb := _mk_tenant('T498E2');
  PERFORM _as_user();
  BEGIN
    PERFORM chain_l16_receipt_order(oa, ra);
    PERFORM _rec('T05a', 'le VOISIN ne peut pas rattacher la réception d''autrui', false, 'accepté !');
  EXCEPTION WHEN no_data_found THEN
    PERFORM _rec('T05a', 'le VOISIN ne peut pas rattacher la réception d''autrui (no_data_found)', true, SQLERRM);
  END;

  SELECT count(*) INTO n FROM document_links
   WHERE amont_type = 'purchase_orders' AND amont_id = oa AND aval_type = 'goods_receipts';
  PERFORM _rec('T05b', 'le voisin ne voit AUCUN lien de la société A', n = 0, 'liens visibles = ' || n);

  RESET ROLE;
  SELECT count(*) INTO n FROM document_links
   WHERE amont_id = oa AND aval_id = ra AND effet = 'purchase.order.to_receipt' AND tenant_id = ta;
  PERFORM _rec('T05c', 'le lien de A existe toujours, un seul, et reste à A', n = 1, 'liens de A = ' || n);
END $$;

-- ── Le VERDICT (G5 : toute suite rend un verdict) ─────────────────────────
SELECT _audit_assert('498');
