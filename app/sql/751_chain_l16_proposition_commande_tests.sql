-- ═══════════════════════════════════════════════════════════════════════════
-- 751_chain_l16_proposition_commande_tests.sql — L16 · proposition → commande
-- ═══════════════════════════════════════════════════════════════════════════
--   T01  NOMINAL : la proposition d'achat (MRP) rattache sa commande d'achat ;
--        la proposition passe `converted` ; le LIEN est posé
--        (effet `purchase.proposal.to_order`) ;
--   T02  IDEMPOTENCE (D1) : le rejeu est REFUSÉ (unique_violation) ;
--   T03  REFUS EXPLICITES : proposition rejetée, déjà convertie, de type
--        fabrication, commande annulée, autre fournisseur — cinq refus motivés ;
--   T04  LA FRISE RÉPOND (I-01) : la frise voit la commande depuis la proposition,
--        et la proposition depuis la commande ;
--   T05  ISOLATION (D8) : le voisin ne rattache pas, et ne voit aucun lien.
--
-- D2 (concurrence), D3 (panne partielle), D5 (réouverture) restent hors de
-- portée d'une suite SQL d'un seul processus ; D6 tenu par construction ; D7
-- sans objet sur une chaîne de deux pièces.
-- ═══════════════════════════════════════════════════════════════════════════
\ir ci/audit_helpers.sql

-- Un article par proposition (`mrp_proposals.product_id` est NOT NULL).
CREATE OR REPLACE FUNCTION _mk_product(p_t uuid) RETURNS uuid LANGUAGE plpgsql AS $x$
DECLARE v uuid;
BEGIN
  INSERT INTO products (tenant_id, name, type) VALUES (p_t, 'Article ' || gen_random_uuid()::text, 'stock') RETURNING id INTO v;
  RETURN v;
END $x$;

-- Un run MRP par proposition (`mrp_proposals.mrp_run_id` est NOT NULL).
CREATE OR REPLACE FUNCTION _mk_mrp_run(p_t uuid) RETURNS uuid LANGUAGE plpgsql AS $x$
DECLARE v uuid;
BEGIN
  INSERT INTO mrp_runs (tenant_id, run_number) VALUES (p_t, 'MRP-' || gen_random_uuid()::text) RETURNING id INTO v;
  RETURN v;
END $x$;
SELECT set_config('audit.file', '751', false);
DELETE FROM _audit_results WHERE file = '751';

-- ── T01 — LE NOMINAL : la proposition rattache sa commande ─────────────────
DO $$
DECLARE t uuid; s uuid; pr uuid; o uuid; r jsonb; n int; v_st text;
BEGIN
  t := _mk_tenant('T751A');
  INSERT INTO suppliers (tenant_id, name, account_tiers)
    VALUES (t, 'Fournisseur 751', 'F0751') RETURNING id INTO s;
  INSERT INTO mrp_proposals (tenant_id, mrp_run_id, product_id, proposal_type, status, supplier_id, suggested_quantity, suggested_date, net_need)
    VALUES (t, _mk_mrp_run(t), _mk_product(t), 'purchase', 'pending', s, 40, '2026-03-20', 40) RETURNING id INTO pr;
  INSERT INTO purchase_orders (tenant_id, number, supplier_id, order_date, status, subtotal, vat, total)
    VALUES (t, 'CA-751-1', s, '2026-03-20', 'confirmed', 400, 80, 480) RETURNING id INTO o;

  PERFORM _as_user();
  r := chain_l16_proposal_order(pr, o);

  PERFORM _rec('T01a', 'la proposition rattache sa commande d''achat (jsonb de succès)',
    COALESCE((r->>'success')::boolean, false) AND (r->>'order_id')::uuid = o, r::text);

  SELECT status INTO v_st FROM mrp_proposals WHERE id = pr;
  PERFORM _rec('T01b', 'la proposition passe au statut `converted` (le statut que personne ne posait)', v_st = 'converted',
    'statut = ' || v_st);

  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_type = 'mrp_proposals' AND amont_id = pr
     AND aval_type = 'purchase_orders' AND aval_id = o
     AND effet = 'purchase.proposal.to_order' AND etat = 'actif';
  PERFORM _rec('T01c', 'le LIEN amont→aval est posé, actif, avec son effet (I-01)', n = 1, 'liens actifs = ' || n);
END $$;

-- ── T02 — IDEMPOTENCE (D1) : le rejeu est REFUSÉ ───────────────────────────
DO $$
DECLARE t uuid; s uuid; pr uuid; o uuid; n int;
BEGIN
  t := _mk_tenant('T751B');
  INSERT INTO suppliers (tenant_id, name, account_tiers)
    VALUES (t, 'Fournisseur 751 B', 'F0751B') RETURNING id INTO s;
  INSERT INTO mrp_proposals (tenant_id, mrp_run_id, product_id, proposal_type, status, supplier_id, suggested_quantity, suggested_date)
    VALUES (t, _mk_mrp_run(t), _mk_product(t), 'purchase', 'pending', s, 10, '2026-03-21') RETURNING id INTO pr;
  INSERT INTO purchase_orders (tenant_id, number, supplier_id, order_date, status, subtotal, vat, total)
    VALUES (t, 'CA-751-B', s, '2026-03-21', 'confirmed', 100, 20, 120) RETURNING id INTO o;
  PERFORM _as_user();
  PERFORM chain_l16_proposal_order(pr, o);
  BEGIN
    PERFORM chain_l16_proposal_order(pr, o);
    PERFORM _rec('T02a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', false, 'second appel accepté !');
  EXCEPTION WHEN unique_violation THEN
    PERFORM _rec('T02a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', true, SQLERRM);
  END;
  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_id = pr AND aval_id = o
     AND effet = 'purchase.proposal.to_order' AND etat = 'actif';
  PERFORM _rec('T02b', 'un SEUL lien — le rejeu n''a rien ajouté', n = 1, 'liens = ' || n);
END $$;

-- ── T03 — REFUS EXPLICITES : cinq refus, cinq raisons ──────────────────────
DO $$
DECLARE t uuid; s uuid; s2 uuid; o uuid; o_cancel uuid;
        pr_rej uuid; pr_conv uuid; pr_mfg uuid; pr_other_sup uuid;
BEGIN
  t := _mk_tenant('T751C');
  INSERT INTO suppliers (tenant_id, name, account_tiers) VALUES
    (t, 'Fournisseur 751 C', 'F0751C'),
    (t, 'Fournisseur 751 C2', 'F0751C2');
  SELECT id INTO s  FROM suppliers WHERE tenant_id = t AND account_tiers = 'F0751C';
  SELECT id INTO s2 FROM suppliers WHERE tenant_id = t AND account_tiers = 'F0751C2';
  INSERT INTO purchase_orders (tenant_id, number, supplier_id, order_date, status, subtotal, vat, total)
    VALUES (t, 'CA-751-C', s, '2026-03-22', 'confirmed', 100, 20, 120) RETURNING id INTO o;
  INSERT INTO purchase_orders (tenant_id, number, supplier_id, order_date, status, subtotal, vat, total)
    VALUES (t, 'CA-751-Cx', s, '2026-03-22', 'cancelled', 100, 20, 120) RETURNING id INTO o_cancel;
  INSERT INTO mrp_proposals (tenant_id, mrp_run_id, product_id, proposal_type, status, supplier_id, suggested_quantity, suggested_date)
    VALUES (t, _mk_mrp_run(t), _mk_product(t), 'purchase', 'rejected', s, 10, '2026-03-22') RETURNING id INTO pr_rej;
  INSERT INTO mrp_proposals (tenant_id, mrp_run_id, product_id, proposal_type, status, supplier_id, suggested_quantity, suggested_date)
    VALUES (t, _mk_mrp_run(t), _mk_product(t), 'purchase', 'converted', s, 10, '2026-03-22') RETURNING id INTO pr_conv;
  INSERT INTO mrp_proposals (tenant_id, mrp_run_id, product_id, proposal_type, status, supplier_id, suggested_quantity, suggested_date)
    VALUES (t, _mk_mrp_run(t), _mk_product(t), 'manufacture', 'pending', s, 10, '2026-03-22') RETURNING id INTO pr_mfg;
  INSERT INTO mrp_proposals (tenant_id, mrp_run_id, product_id, proposal_type, status, supplier_id, suggested_quantity, suggested_date)
    VALUES (t, _mk_mrp_run(t), _mk_product(t), 'purchase', 'pending', s2, 10, '2026-03-22') RETURNING id INTO pr_other_sup;
  PERFORM _as_user();

  BEGIN
    PERFORM chain_l16_proposal_order(pr_rej, o);
    PERFORM _rec('T03a', 'une proposition REJETÉE est refusée, avec sa raison', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03a', 'une proposition REJETÉE est refusée, avec sa raison', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_proposal_order(pr_conv, o);
    PERFORM _rec('T03b', 'une proposition DÉJÀ CONVERTIE est refusée', false, 'accepté !');
  EXCEPTION WHEN unique_violation THEN
    PERFORM _rec('T03b', 'une proposition DÉJÀ CONVERTIE est refusée', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_proposal_order(pr_mfg, o);
    PERFORM _rec('T03c', 'une proposition de FABRICATION est refusée (elle va vers un OF)', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03c', 'une proposition de FABRICATION est refusée (elle va vers un OF)', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_proposal_order(pr_other_sup, o_cancel);
    PERFORM _rec('T03d', 'une commande ANNULÉE est refusée', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03d', 'une commande ANNULÉE est refusée', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_proposal_order(pr_other_sup, o);
    PERFORM _rec('T03e', 'une proposition d''un AUTRE fournisseur est refusée', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03e', 'une proposition d''un AUTRE fournisseur est refusée', true, SQLERRM);
  END;
END $$;

-- ── T04 — LA FRISE RÉPOND (I-01) ───────────────────────────────────────────
DO $$
DECLARE t uuid; s uuid; pr uuid; o uuid; n int;
BEGIN
  t := _mk_tenant('T751D');
  INSERT INTO suppliers (tenant_id, name, account_tiers)
    VALUES (t, 'Fournisseur 751 D', 'F0751D') RETURNING id INTO s;
  INSERT INTO mrp_proposals (tenant_id, mrp_run_id, product_id, proposal_type, status, supplier_id, suggested_quantity, suggested_date)
    VALUES (t, _mk_mrp_run(t), _mk_product(t), 'purchase', 'pending', s, 5, '2026-03-23') RETURNING id INTO pr;
  INSERT INTO purchase_orders (tenant_id, number, supplier_id, order_date, status, subtotal, vat, total)
    VALUES (t, 'CA-751-D', s, '2026-03-23', 'confirmed', 50, 10, 60) RETURNING id INTO o;
  PERFORM _as_user();
  PERFORM chain_l16_proposal_order(pr, o);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'mrp_proposals', pr, 'aval', 5, false)
   WHERE type = 'purchase_orders' AND id = o;
  PERFORM _rec('T04a', 'depuis la PROPOSITION, la frise voit la COMMANDE', n = 1, 'nœuds aval = ' || n);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'purchase_orders', o, 'amont', 5, false)
   WHERE type = 'mrp_proposals' AND id = pr;
  PERFORM _rec('T04b', 'depuis la COMMANDE, la frise voit la PROPOSITION', n = 1, 'nœuds amont = ' || n);
END $$;

-- ── T05 — ISOLATION (D8) : le voisin ne rattache pas, et ne voit rien ───────
DO $$
DECLARE ta uuid; tb uuid; sa uuid; pra uuid; oa uuid; n int;
BEGIN
  ta := _mk_tenant('T751E1');
  INSERT INTO suppliers (tenant_id, name, account_tiers)
    VALUES (ta, 'Fournisseur E1', 'FE1') RETURNING id INTO sa;
  INSERT INTO mrp_proposals (tenant_id, mrp_run_id, product_id, proposal_type, status, supplier_id, suggested_quantity, suggested_date)
    VALUES (ta, _mk_mrp_run(ta), _mk_product(ta), 'purchase', 'pending', sa, 5, '2026-03-24') RETURNING id INTO pra;
  INSERT INTO purchase_orders (tenant_id, number, supplier_id, order_date, status, subtotal, vat, total)
    VALUES (ta, 'CA-751-E1', sa, '2026-03-24', 'confirmed', 50, 10, 60) RETURNING id INTO oa;
  PERFORM _as_user();
  PERFORM chain_l16_proposal_order(pra, oa);

  RESET ROLE;
  tb := _mk_tenant('T751E2');
  PERFORM _as_user();
  BEGIN
    PERFORM chain_l16_proposal_order(pra, oa);
    PERFORM _rec('T05a', 'le VOISIN ne peut pas rattacher la proposition d''autrui', false, 'accepté !');
  EXCEPTION WHEN no_data_found THEN
    PERFORM _rec('T05a', 'le VOISIN ne peut pas rattacher la proposition d''autrui (no_data_found)', true, SQLERRM);
  END;

  SELECT count(*) INTO n FROM document_links
   WHERE amont_type = 'mrp_proposals' AND amont_id = pra AND aval_type = 'purchase_orders';
  PERFORM _rec('T05b', 'le voisin ne voit AUCUN lien de la société A', n = 0, 'liens visibles = ' || n);

  RESET ROLE;
  SELECT count(*) INTO n FROM document_links
   WHERE amont_id = pra AND aval_id = oa AND effet = 'purchase.proposal.to_order' AND tenant_id = ta;
  PERFORM _rec('T05c', 'le lien de A existe toujours, un seul, et reste à A', n = 1, 'liens de A = ' || n);
END $$;

-- ── Le VERDICT (G5 : toute suite rend un verdict) ─────────────────────────
SELECT _audit_assert('751');
