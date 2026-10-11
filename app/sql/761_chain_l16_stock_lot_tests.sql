-- ═══════════════════════════════════════════════════════════════════════════
-- 761_chain_l16_stock_lot_tests.sql — L16 · mouvement de stock → son lot
-- ═══════════════════════════════════════════════════════════════════════════
--   T01  NOMINAL : le mouvement trace son lot ; la colonne est posée ; le LIEN est là ;
--   T02  IDEMPOTENCE (D1) : le rejeu est REFUSÉ (unique_violation) ;
--   T03  REFUS EXPLICITES : mouvement introuvable, lot introuvable, lot d'un
--        AUTRE produit, mouvement sans produit, mouvement portant DÉJÀ un autre
--        lot — cinq refus, cinq raisons ;
--   T04  LA FRISE RÉPOND (I-01) : la frise voit le lot depuis le mouvement, et
--        les MOUVEMENTS depuis le lot (la question de la traçabilité) ;
--   T05  ISOLATION (D8) : le voisin ne rattache pas, et ne voit aucun lien.
-- ═══════════════════════════════════════════════════════════════════════════
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '761', false);
DELETE FROM _audit_results WHERE file = '761';

-- ── T01 — LE NOMINAL : le mouvement trace son lot ──────────────────────────
DO $$
DECLARE t uuid; p uuid; w uuid; b uuid; m uuid; r jsonb; n int; vl uuid;
BEGIN
  t := _mk_tenant('T761A');
  INSERT INTO products (tenant_id, name, type) VALUES (t, 'P-761-A', 'stock') RETURNING id INTO p;
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W761A', 'Entrepôt A') RETURNING id INTO w;
  INSERT INTO product_batches (tenant_id, product_id, batch_number, quantity)
    VALUES (t, p, 'LOT-761-A', 10) RETURNING id INTO b;
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, type, movement_type, quantity, date, movement_date)
    VALUES (t, p, w, 'in', 'in', 10, '2026-03-01', '2026-03-01') RETURNING id INTO m;

  PERFORM _as_user();
  r := chain_l16_stock_lot(m, b);

  PERFORM _rec('T01a', 'le mouvement trace son lot (jsonb de succès)',
    COALESCE((r->>'success')::boolean, false) AND (r->>'batch_id')::uuid = b, r::text);

  RESET ROLE;
  SELECT lot_id INTO vl FROM stock_movements WHERE id = m;
  PERFORM _rec('T01b', 'la COLONNE lot_id est posée (le mouvement porte son lot)', vl = b, 'lot_id = ' || COALESCE(vl::text, 'NULL'));

  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_type = 'stock_movements' AND amont_id = m
     AND aval_type = 'product_batches' AND aval_id = b
     AND effet = 'stock.movement.lot_traced' AND etat = 'actif';
  PERFORM _rec('T01c', 'le LIEN amont→aval est posé, actif, avec son effet (I-01)', n = 1, 'liens actifs = ' || n);
END $$;

-- ── T02 — IDEMPOTENCE (D1) : le rejeu est REFUSÉ ───────────────────────────
DO $$
DECLARE t uuid; p uuid; b uuid; m uuid; n int;
BEGIN
  t := _mk_tenant('T761B');
  INSERT INTO products (tenant_id, name, type) VALUES (t, 'P-761-B', 'stock') RETURNING id INTO p;
  INSERT INTO product_batches (tenant_id, product_id, batch_number, quantity)
    VALUES (t, p, 'LOT-761-B', 4) RETURNING id INTO b;
  INSERT INTO stock_movements (tenant_id, product_id, type, movement_type, quantity, date)
    VALUES (t, p, 'in', 'in', 4, '2026-03-02') RETURNING id INTO m;

  PERFORM _as_user();
  PERFORM chain_l16_stock_lot(m, b);
  BEGIN
    PERFORM chain_l16_stock_lot(m, b);
    PERFORM _rec('T02a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', false, 'second appel accepté !');
  EXCEPTION WHEN unique_violation THEN
    PERFORM _rec('T02a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', true, SQLERRM);
  END;
  RESET ROLE;
  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_id = m AND effet = 'stock.movement.lot_traced' AND etat = 'actif';
  PERFORM _rec('T02b', 'un SEUL lien — le rejeu n''a rien ajouté', n = 1, 'liens = ' || n);
END $$;

-- ── T03 — REFUS EXPLICITES : cinq refus, cinq raisons ──────────────────────
DO $$
DECLARE t uuid; p1 uuid; p2 uuid; b1 uuid; b2 uuid; m uuid; m2 uuid; autre uuid;
BEGIN
  t := _mk_tenant('T761C');
  INSERT INTO products (tenant_id, name, type) VALUES (t, 'P-761-C1', 'stock') RETURNING id INTO p1;
  INSERT INTO products (tenant_id, name, type) VALUES (t, 'P-761-C2', 'stock') RETURNING id INTO p2;
  INSERT INTO product_batches (tenant_id, product_id, batch_number, quantity)
    VALUES (t, p1, 'LOT-761-C1', 5) RETURNING id INTO b1;
  INSERT INTO product_batches (tenant_id, product_id, batch_number, quantity)
    VALUES (t, p2, 'LOT-761-C2', 5) RETURNING id INTO b2;
  INSERT INTO stock_movements (tenant_id, product_id, type, movement_type, quantity, date)
    VALUES (t, p1, 'in', 'in', 5, '2026-03-03') RETURNING id INTO m;
  -- un mouvement SANS produit, et un mouvement portant DÉJÀ un autre lot
  INSERT INTO stock_movements (tenant_id, product_id, type, movement_type, quantity, date)
    VALUES (t, NULL, 'in', 'in', 1, '2026-03-03') RETURNING id INTO m2;
  INSERT INTO stock_movements (tenant_id, product_id, type, movement_type, quantity, date, lot_id)
    VALUES (t, p1, 'out', 'out', 1, '2026-03-03', b2) RETURNING id INTO autre;

  PERFORM _as_user();
  BEGIN
    PERFORM chain_l16_stock_lot('00000000-0000-0000-0000-000000000001'::uuid, b1);
    PERFORM _rec('T03a', 'un mouvement INTROUVABLE est refusé (no_data_found)', false, 'accepté !');
  EXCEPTION WHEN no_data_found THEN
    PERFORM _rec('T03a', 'un mouvement INTROUVABLE est refusé (no_data_found)', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_stock_lot(m, '00000000-0000-0000-0000-000000000002'::uuid);
    PERFORM _rec('T03b', 'un lot INTROUVABLE est refusé (no_data_found)', false, 'accepté !');
  EXCEPTION WHEN no_data_found THEN
    PERFORM _rec('T03b', 'un lot INTROUVABLE est refusé (no_data_found)', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_stock_lot(m, b2);
    PERFORM _rec('T03c', 'un lot d''un AUTRE produit est refusé (traçabilité fausse)', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03c', 'un lot d''un AUTRE produit est refusé (traçabilité fausse)', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_stock_lot(m2, b1);
    PERFORM _rec('T03d', 'un mouvement SANS produit est refusé', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03d', 'un mouvement SANS produit est refusé', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_stock_lot(autre, b1);
    PERFORM _rec('T03e', 'un mouvement portant DÉJÀ un autre lot est refusé', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03e', 'un mouvement portant DÉJÀ un autre lot est refusé', true, SQLERRM);
  END;
END $$;

-- ── T04 — LA FRISE RÉPOND (I-01) : la question de la traçabilité ───────────
DO $$
DECLARE t uuid; p uuid; b uuid; m uuid; m2 uuid; n int;
BEGIN
  t := _mk_tenant('T761D');
  INSERT INTO products (tenant_id, name, type) VALUES (t, 'P-761-D', 'stock') RETURNING id INTO p;
  INSERT INTO product_batches (tenant_id, product_id, batch_number, quantity)
    VALUES (t, p, 'LOT-761-D', 12) RETURNING id INTO b;
  INSERT INTO stock_movements (tenant_id, product_id, type, movement_type, quantity, date)
    VALUES (t, p, 'in', 'in', 8, '2026-03-04') RETURNING id INTO m;
  INSERT INTO stock_movements (tenant_id, product_id, type, movement_type, quantity, date)
    VALUES (t, p, 'out', 'out', 4, '2026-03-05') RETURNING id INTO m2;

  PERFORM _as_user();
  PERFORM chain_l16_stock_lot(m, b);
  PERFORM chain_l16_stock_lot(m2, b);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'stock_movements', m, 'aval', 5, false)
   WHERE type = 'product_batches' AND id = b;
  PERFORM _rec('T04a', 'depuis le MOUVEMENT, la frise voit le LOT', n = 1, 'nœuds aval = ' || n);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'product_batches', b, 'amont', 5, false)
   WHERE type = 'stock_movements' AND id IN (m, m2);
  PERFORM _rec('T04b', 'depuis le LOT, la frise voit ses DEUX mouvements (traçabilité)', n = 2, 'nœuds amont = ' || n);
END $$;

-- ── T05 — ISOLATION (D8) : le voisin ne rattache pas, et ne voit rien ───────
DO $$
DECLARE ta uuid; tb uuid; pa uuid; ba uuid; ma uuid; n int;
BEGIN
  ta := _mk_tenant('T761E1');
  INSERT INTO products (tenant_id, name, type) VALUES (ta, 'P-761-E1', 'stock') RETURNING id INTO pa;
  INSERT INTO product_batches (tenant_id, product_id, batch_number, quantity)
    VALUES (ta, pa, 'LOT-761-E1', 3) RETURNING id INTO ba;
  INSERT INTO stock_movements (tenant_id, product_id, type, movement_type, quantity, date)
    VALUES (ta, pa, 'in', 'in', 3, '2026-03-06') RETURNING id INTO ma;
  PERFORM _as_user();
  PERFORM chain_l16_stock_lot(ma, ba);

  RESET ROLE;
  tb := _mk_tenant('T761E2');
  PERFORM _as_user();
  BEGIN
    PERFORM chain_l16_stock_lot(ma, ba);
    PERFORM _rec('T05a', 'le VOISIN ne peut pas rattacher le mouvement d''autrui', false, 'accepté !');
  EXCEPTION WHEN no_data_found THEN
    PERFORM _rec('T05a', 'le VOISIN ne peut pas rattacher le mouvement d''autrui (no_data_found)', true, SQLERRM);
  END;

  SELECT count(*) INTO n FROM document_links
   WHERE amont_type = 'stock_movements' AND amont_id = ma AND aval_type = 'product_batches';
  PERFORM _rec('T05b', 'le voisin ne voit AUCUN lien de la société A', n = 0, 'liens visibles = ' || n);

  RESET ROLE;
  SELECT count(*) INTO n FROM document_links
   WHERE amont_id = ma AND effet = 'stock.movement.lot_traced' AND tenant_id = ta;
  PERFORM _rec('T05c', 'le lien de A existe toujours, un seul, et reste à A', n = 1, 'liens de A = ' || n);
END $$;

-- ── Le VERDICT (G5 : toute suite rend un verdict) ─────────────────────────
SELECT _audit_assert('761');
