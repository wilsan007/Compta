-- ═══════════════════════════════════════════════════════════════════════════
-- 499_chain_l16_ordre_virement_tests.sql — L16 · ordre de paiement → virement
-- ═══════════════════════════════════════════════════════════════════════════
--   T01  NOMINAL (achat) : l'ordre de paiement rattache son virement (règlement
--        fournisseur) ; l'ordre passe `executed` ; le LIEN est posé ;
--   T02  NOMINAL (vente) : le même maillon retrouve un règlement CLIENT (le type
--        du tiers décide) ;
--   T03  IDEMPOTENCE (D1) : le rejeu est REFUSÉ (unique_violation) ;
--   T04  REFUS EXPLICITES : ordre annulé, ordre déjà exécuté, virement
--        introuvable, virement > ordre — quatre refus, quatre raisons ;
--   T05  LA FRISE RÉPOND (I-01) : la frise voit le virement depuis l'ordre, et
--        l'ordre depuis le virement ;
--   T06  ISOLATION (D8) : le voisin ne rattache pas, et ne voit aucun lien.
--
-- D2 (concurrence), D3 (panne partielle), D5 (réouverture) restent hors de
-- portée d'une suite SQL d'un seul processus ; D6 tenu par construction ; D7
-- sans objet sur une chaîne de deux pièces.
-- ═══════════════════════════════════════════════════════════════════════════
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '499', false);
DELETE FROM _audit_results WHERE file = '499';

-- ── T01 — LE NOMINAL (achat) : l'ordre rattache son virement ───────────────
DO $$
DECLARE t uuid; s uuid; o uuid; p uuid; r jsonb; n int; v_st text;
BEGIN
  t := _mk_tenant('T499A');
  INSERT INTO suppliers (tenant_id, name, account_tiers)
    VALUES (t, 'Fournisseur 499', 'F0499') RETURNING id INTO s;
  INSERT INTO payment_orders (tenant_id, number, type, status, amount, payment_date)
    VALUES (t, 'OP-499-1', 'sepa_transfer', 'approved', 1200, '2026-03-10') RETURNING id INTO o;
  INSERT INTO supplier_payments (tenant_id, number, supplier_id, payment_date, amount, method, status)
    VALUES (t, 'RF-499-1', s, '2026-03-10', 1200, 'transfer', 'recorded') RETURNING id INTO p;

  PERFORM _as_user();
  r := chain_l16_order_payment(o, p);

  PERFORM _rec('T01a', 'l''ordre de paiement rattache son virement (jsonb de succès, kind=purchase)',
    COALESCE((r->>'success')::boolean, false) AND (r->>'payment_id')::uuid = p AND (r->>'kind') = 'purchase', r::text);

  SELECT status INTO v_st FROM payment_orders WHERE id = o;
  PERFORM _rec('T01b', 'l''ordre passe au statut `executed` (le statut que personne ne posait)', v_st = 'executed',
    'statut = ' || v_st);

  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_type = 'payment_orders' AND amont_id = o
     AND aval_type = 'supplier_payments' AND aval_id = p
     AND effet = 'treasury.order.to_payment' AND etat = 'actif';
  PERFORM _rec('T01c', 'le LIEN amont→aval est posé, actif, avec son effet (I-01)', n = 1, 'liens actifs = ' || n);
END $$;

-- ── T02 — LE NOMINAL (vente) : le type du tiers décide de la table ─────────
DO $$
DECLARE t uuid; c uuid; o uuid; p uuid; r jsonb; n int;
BEGIN
  t := _mk_tenant('T499B');
  INSERT INTO customers (tenant_id, name, account_tiers)
    VALUES (t, 'Client 499', 'C0499') RETURNING id INTO c;
  INSERT INTO payment_orders (tenant_id, number, type, status, amount, payment_date)
    VALUES (t, 'OP-499-B', 'sepa_transfer', 'approved', 500, '2026-03-11') RETURNING id INTO o;
  INSERT INTO customer_payments (tenant_id, number, customer_id, payment_date, amount, method, status)
    VALUES (t, 'RC-499-B', c, '2026-03-11', 500, 'transfer', 'recorded') RETURNING id INTO p;

  PERFORM _as_user();
  r := chain_l16_order_payment(o, p);

  PERFORM _rec('T02a', 'le même maillon retrouve un règlement CLIENT (kind=sale)', (r->>'kind') = 'sale', r::text);
  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_id = o AND aval_type = 'customer_payments' AND aval_id = p
     AND effet = 'treasury.order.to_payment' AND etat = 'actif';
  PERFORM _rec('T02b', 'le lien pointe vers customer_payments', n = 1, 'liens = ' || n);
END $$;

-- ── T03 — IDEMPOTENCE (D1) : le rejeu est REFUSÉ ───────────────────────────
DO $$
DECLARE t uuid; s uuid; o uuid; p uuid; n int;
BEGIN
  t := _mk_tenant('T499C');
  INSERT INTO suppliers (tenant_id, name, account_tiers)
    VALUES (t, 'Fournisseur 499 C', 'F0499C') RETURNING id INTO s;
  INSERT INTO payment_orders (tenant_id, number, type, status, amount, payment_date)
    VALUES (t, 'OP-499-C', 'sepa_transfer', 'approved', 300, '2026-03-12') RETURNING id INTO o;
  INSERT INTO supplier_payments (tenant_id, number, supplier_id, payment_date, amount, method, status)
    VALUES (t, 'RF-499-C', s, '2026-03-12', 300, 'transfer', 'recorded') RETURNING id INTO p;
  PERFORM _as_user();
  PERFORM chain_l16_order_payment(o, p);
  BEGIN
    PERFORM chain_l16_order_payment(o, p);
    PERFORM _rec('T03a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', false, 'second appel accepté !');
  EXCEPTION WHEN unique_violation THEN
    PERFORM _rec('T03a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', true, SQLERRM);
  END;
  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_id = o AND aval_id = p
     AND effet = 'treasury.order.to_payment' AND etat = 'actif';
  PERFORM _rec('T03b', 'un SEUL lien — le rejeu n''a rien ajouté', n = 1, 'liens = ' || n);
END $$;

-- ── T04 — REFUS EXPLICITES : quatre refus, quatre raisons ──────────────────
DO $$
DECLARE t uuid; s uuid; o uuid; o_cancel uuid; o_exec uuid; p uuid; p_big uuid;
BEGIN
  t := _mk_tenant('T499D');
  INSERT INTO suppliers (tenant_id, name, account_tiers)
    VALUES (t, 'Fournisseur 499 D', 'F0499D') RETURNING id INTO s;
  INSERT INTO payment_orders (tenant_id, number, type, status, amount, payment_date)
    VALUES (t, 'OP-499-D', 'sepa_transfer', 'approved', 100, '2026-03-13') RETURNING id INTO o;
  INSERT INTO payment_orders (tenant_id, number, type, status, amount, payment_date)
    VALUES (t, 'OP-499-Dc', 'sepa_transfer', 'cancelled', 100, '2026-03-13') RETURNING id INTO o_cancel;
  INSERT INTO payment_orders (tenant_id, number, type, status, amount, payment_date)
    VALUES (t, 'OP-499-De', 'sepa_transfer', 'executed', 100, '2026-03-13') RETURNING id INTO o_exec;
  INSERT INTO supplier_payments (tenant_id, number, supplier_id, payment_date, amount, method, status)
    VALUES (t, 'RF-499-D', s, '2026-03-13', 100, 'transfer', 'recorded') RETURNING id INTO p;
  INSERT INTO supplier_payments (tenant_id, number, supplier_id, payment_date, amount, method, status)
    VALUES (t, 'RF-499-Db', s, '2026-03-13', 200, 'transfer', 'recorded') RETURNING id INTO p_big;
  PERFORM _as_user();

  BEGIN
    PERFORM chain_l16_order_payment(o_cancel, p);
    PERFORM _rec('T04a', 'un ordre ANNULÉ est refusé, avec sa raison', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T04a', 'un ordre ANNULÉ est refusé, avec sa raison', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_order_payment(o_exec, p);
    PERFORM _rec('T04b', 'un ordre DÉJÀ EXÉCUTÉ est refusé', false, 'accepté !');
  EXCEPTION WHEN unique_violation THEN
    PERFORM _rec('T04b', 'un ordre DÉJÀ EXÉCUTÉ est refusé', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_order_payment(o, '00000000-0000-0000-0000-000000000001'::uuid);
    PERFORM _rec('T04c', 'un virement INTROUVABLE est refusé (no_data_found)', false, 'accepté !');
  EXCEPTION WHEN no_data_found THEN
    PERFORM _rec('T04c', 'un virement INTROUVABLE est refusé (no_data_found)', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_order_payment(o, p_big);
    PERFORM _rec('T04d', 'un virement SUPÉRIEUR à l''ordre est refusé', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T04d', 'un virement SUPÉRIEUR à l''ordre est refusé', true, SQLERRM);
  END;
END $$;

-- ── T05 — LA FRISE RÉPOND (I-01) ───────────────────────────────────────────
DO $$
DECLARE t uuid; s uuid; o uuid; p uuid; n int;
BEGIN
  t := _mk_tenant('T499E');
  INSERT INTO suppliers (tenant_id, name, account_tiers)
    VALUES (t, 'Fournisseur 499 E', 'F0499E') RETURNING id INTO s;
  INSERT INTO payment_orders (tenant_id, number, type, status, amount, payment_date)
    VALUES (t, 'OP-499-E', 'sepa_transfer', 'approved', 200, '2026-03-14') RETURNING id INTO o;
  INSERT INTO supplier_payments (tenant_id, number, supplier_id, payment_date, amount, method, status)
    VALUES (t, 'RF-499-E', s, '2026-03-14', 200, 'transfer', 'recorded') RETURNING id INTO p;
  PERFORM _as_user();
  PERFORM chain_l16_order_payment(o, p);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'payment_orders', o, 'aval', 5, false)
   WHERE type = 'supplier_payments' AND id = p;
  PERFORM _rec('T05a', 'depuis l''ORDRE, la frise voit le VIREMENT', n = 1, 'nœuds aval = ' || n);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'supplier_payments', p, 'amont', 5, false)
   WHERE type = 'payment_orders' AND id = o;
  PERFORM _rec('T05b', 'depuis le VIREMENT, la frise voit l''ORDRE', n = 1, 'nœuds amont = ' || n);
END $$;

-- ── T06 — ISOLATION (D8) : le voisin ne rattache pas, et ne voit rien ───────
DO $$
DECLARE ta uuid; tb uuid; sa uuid; oa uuid; pa uuid; n int;
BEGIN
  ta := _mk_tenant('T499F1');
  INSERT INTO suppliers (tenant_id, name, account_tiers)
    VALUES (ta, 'Fournisseur F1', 'FF1') RETURNING id INTO sa;
  INSERT INTO payment_orders (tenant_id, number, type, status, amount, payment_date)
    VALUES (ta, 'OP-499-F1', 'sepa_transfer', 'approved', 100, '2026-03-15') RETURNING id INTO oa;
  INSERT INTO supplier_payments (tenant_id, number, supplier_id, payment_date, amount, method, status)
    VALUES (ta, 'RF-499-F1', sa, '2026-03-15', 100, 'transfer', 'recorded') RETURNING id INTO pa;
  PERFORM _as_user();
  PERFORM chain_l16_order_payment(oa, pa);

  RESET ROLE;
  tb := _mk_tenant('T499F2');
  PERFORM _as_user();
  BEGIN
    PERFORM chain_l16_order_payment(oa, pa);
    PERFORM _rec('T06a', 'le VOISIN ne peut pas rattacher l''ordre d''autrui', false, 'accepté !');
  EXCEPTION WHEN no_data_found THEN
    PERFORM _rec('T06a', 'le VOISIN ne peut pas rattacher l''ordre d''autrui (no_data_found)', true, SQLERRM);
  END;

  SELECT count(*) INTO n FROM document_links
   WHERE amont_type = 'payment_orders' AND amont_id = oa;
  PERFORM _rec('T06b', 'le voisin ne voit AUCUN lien de la société A', n = 0, 'liens visibles = ' || n);

  RESET ROLE;
  SELECT count(*) INTO n FROM document_links
   WHERE amont_id = oa AND aval_id = pa AND effet = 'treasury.order.to_payment' AND tenant_id = ta;
  PERFORM _rec('T06c', 'le lien de A existe toujours, un seul, et reste à A', n = 1, 'liens de A = ' || n);
END $$;

-- ── Le VERDICT (G5 : toute suite rend un verdict) ─────────────────────────
SELECT _audit_assert('499');
