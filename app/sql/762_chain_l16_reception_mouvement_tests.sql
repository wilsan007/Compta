-- ═══════════════════════════════════════════════════════════════════════════
-- 762_chain_l16_reception_mouvement_tests.sql — L16 · réception → mouvements de stock
-- ═══════════════════════════════════════════════════════════════════════════
--   T01  NOMINAL : la réception rattache son mouvement ; le LIEN est posé ; les
--        colonnes de l'entrée en stock (241) ne sont PAS réécrites ;
--   T02  IDEMPOTENCE (D1) : le rejeu est REFUSÉ (unique_violation) ;
--   T03  REFUS EXPLICITES : réception introuvable, mouvement introuvable, réception
--        qui n'a PAS reçu, mouvement se réclamant d'une AUTRE réception ;
--   T04  LA FRISE RÉPOND (I-01) : la frise voit les DEUX mouvements depuis la
--        réception (la fusion du 758), et la réception depuis le mouvement ;
--   T05  ISOLATION (D8) : le voisin ne rattache pas, et ne voit aucun lien.
-- ═══════════════════════════════════════════════════════════════════════════
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '762', false);
DELETE FROM _audit_results WHERE file = '762';

-- ── T01 — LE NOMINAL : la réception rattache son mouvement ─────────────────
DO $$
DECLARE t uuid; p uuid; gr uuid; m uuid; r jsonb; n int; vrt text; vri uuid;
BEGIN
  t := _mk_tenant('T762A');
  INSERT INTO products (tenant_id, name, type) VALUES (t, 'P-762-A', 'stock') RETURNING id INTO p;
  INSERT INTO goods_receipts (tenant_id, number, receipt_date, status)
    VALUES (t, 'BR-762-A', '2026-03-01', 'received') RETURNING id INTO gr;
  INSERT INTO stock_movements (tenant_id, product_id, type, movement_type, quantity, date,
                               reference, reference_type, reference_id)
    VALUES (t, p, 'in', 'in', 5, '2026-03-01', 'BR-762-A', 'goods_receipt', gr) RETURNING id INTO m;

  PERFORM _as_user();
  r := chain_l16_receipt_movement(gr, m);

  PERFORM _rec('T01a', 'la réception rattache son mouvement (jsonb de succès)',
    COALESCE((r->>'success')::boolean, false) AND (r->>'receipt_number') = 'BR-762-A', r::text);

  RESET ROLE;
  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_type = 'stock_movements' AND amont_id = m
     AND aval_type = 'goods_receipts' AND aval_id = gr
     AND effet = 'stock.receipt.movement_recorded' AND etat = 'actif';
  PERFORM _rec('T01b', 'le LIEN amont→aval est posé, actif, avec son effet (I-01)', n = 1, 'liens actifs = ' || n);

  SELECT reference_type, reference_id INTO vrt, vri FROM stock_movements WHERE id = m;
  PERFORM _rec('T01c', 'rien n''est réécrit : les colonnes de l''entrée en stock (241) sont intactes',
    vrt = 'goods_receipt' AND vri = gr, 'reference_type = ' || COALESCE(vrt, 'NULL'));
END $$;

-- ── T02 — IDEMPOTENCE (D1) : le rejeu est REFUSÉ ───────────────────────────
DO $$
DECLARE t uuid; p uuid; gr uuid; m uuid; n int;
BEGIN
  t := _mk_tenant('T762B');
  INSERT INTO products (tenant_id, name, type) VALUES (t, 'P-762-B', 'stock') RETURNING id INTO p;
  INSERT INTO goods_receipts (tenant_id, number, receipt_date, status)
    VALUES (t, 'BR-762-B', '2026-03-02', 'received') RETURNING id INTO gr;
  INSERT INTO stock_movements (tenant_id, product_id, type, movement_type, quantity, date,
                               reference, reference_type, reference_id)
    VALUES (t, p, 'in', 'in', 2, '2026-03-02', 'BR-762-B', 'goods_receipt', gr) RETURNING id INTO m;

  PERFORM _as_user();
  PERFORM chain_l16_receipt_movement(gr, m);
  BEGIN
    PERFORM chain_l16_receipt_movement(gr, m);
    PERFORM _rec('T02a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', false, 'second appel accepté !');
  EXCEPTION WHEN unique_violation THEN
    PERFORM _rec('T02a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', true, SQLERRM);
  END;
  RESET ROLE;
  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_id = m AND effet = 'stock.receipt.movement_recorded' AND etat = 'actif';
  PERFORM _rec('T02b', 'un SEUL lien — le rejeu n''a rien ajouté', n = 1, 'liens = ' || n);
END $$;

-- ── T03 — REFUS EXPLICITES : quatre refus, quatre raisons ──────────────────
DO $$
DECLARE t uuid; p uuid; gr_pending uuid; gr_autre uuid; m_autre uuid; m_ok uuid;
BEGIN
  t := _mk_tenant('T762C');
  INSERT INTO products (tenant_id, name, type) VALUES (t, 'P-762-C', 'stock') RETURNING id INTO p;
  INSERT INTO goods_receipts (tenant_id, number, receipt_date, status)
    VALUES (t, 'BR-762-C-ATT', '2026-03-03', 'pending') RETURNING id INTO gr_pending;
  INSERT INTO goods_receipts (tenant_id, number, receipt_date, status)
    VALUES (t, 'BR-762-C-AUT', '2026-03-03', 'received') RETURNING id INTO gr_autre;
  -- un mouvement légitime (pour la réception « autre »), et un mouvement qui
  -- se réclame d'une AUTRE réception que celle qu'on lui présente
  INSERT INTO stock_movements (tenant_id, product_id, type, movement_type, quantity, date,
                               reference, reference_type, reference_id)
    VALUES (t, p, 'in', 'in', 3, '2026-03-03', 'BR-762-C-AUT', 'goods_receipt', gr_autre) RETURNING id INTO m_autre;
  INSERT INTO stock_movements (tenant_id, product_id, type, movement_type, quantity, date,
                               reference, reference_type, reference_id)
    VALUES (t, p, 'in', 'in', 1, '2026-03-03', 'BR-762-C-ATT', 'goods_receipt', gr_pending) RETURNING id INTO m_ok;

  PERFORM _as_user();
  BEGIN
    PERFORM chain_l16_receipt_movement('00000000-0000-0000-0000-000000000001'::uuid, m_autre);
    PERFORM _rec('T03a', 'une réception INTROUVABLE est refusée (no_data_found)', false, 'accepté !');
  EXCEPTION WHEN no_data_found THEN
    PERFORM _rec('T03a', 'une réception INTROUVABLE est refusée (no_data_found)', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_receipt_movement(gr_autre, '00000000-0000-0000-0000-000000000002'::uuid);
    PERFORM _rec('T03b', 'un mouvement INTROUVABLE est refusé (no_data_found)', false, 'accepté !');
  EXCEPTION WHEN no_data_found THEN
    PERFORM _rec('T03b', 'un mouvement INTROUVABLE est refusé (no_data_found)', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_receipt_movement(gr_pending, m_ok);
    PERFORM _rec('T03c', 'une réception qui n''a PAS reçu est refusée (check_violation)', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03c', 'une réception qui n''a PAS reçu est refusée (check_violation)', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_receipt_movement(gr_autre, m_ok);
    PERFORM _rec('T03d', 'un mouvement se réclamant d''une AUTRE réception est refusé', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03d', 'un mouvement se réclamant d''une AUTRE réception est refusé', true, SQLERRM);
  END;
END $$;

-- ── T04 — LA FRISE RÉPOND (I-01) : une réception, DEUX mouvements ──────────
-- C'est l'épreuve de la leçon du 758 : deux `amont` distincts vers un même
-- `aval` tiennent deux liens (l'inverse n'en tiendrait qu'un). La mesure a
-- trouvé `uq_stock_movement_source (tenant_id, reference_type, reference_id,
-- product_id, movement_type)` : une réception ne produit qu'UN mouvement par
-- produit — les deux mouvements viennent donc de DEUX produits.
DO $$
DECLARE t uuid; p1 uuid; p2 uuid; gr uuid; m1 uuid; m2 uuid; n int;
BEGIN
  t := _mk_tenant('T762D');
  INSERT INTO products (tenant_id, name, type) VALUES (t, 'P-762-D1', 'stock') RETURNING id INTO p1;
  INSERT INTO products (tenant_id, name, type) VALUES (t, 'P-762-D2', 'stock') RETURNING id INTO p2;
  INSERT INTO goods_receipts (tenant_id, number, receipt_date, status)
    VALUES (t, 'BR-762-D', '2026-03-04', 'received') RETURNING id INTO gr;
  INSERT INTO stock_movements (tenant_id, product_id, type, movement_type, quantity, date,
                               reference, reference_type, reference_id)
    VALUES (t, p1, 'in', 'in', 8, '2026-03-04', 'BR-762-D', 'goods_receipt', gr) RETURNING id INTO m1;
  INSERT INTO stock_movements (tenant_id, product_id, type, movement_type, quantity, date,
                               reference, reference_type, reference_id)
    VALUES (t, p2, 'in', 'in', 4, '2026-03-04', 'BR-762-D', 'goods_receipt', gr) RETURNING id INTO m2;

  PERFORM _as_user();
  PERFORM chain_l16_receipt_movement(gr, m1);
  PERFORM chain_l16_receipt_movement(gr, m2);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'goods_receipts', gr, 'amont', 5, false)
   WHERE type = 'stock_movements' AND id IN (m1, m2);
  PERFORM _rec('T04a', 'depuis la RÉCEPTION, la frise voit ses DEUX mouvements', n = 2, 'nœuds amont = ' || n);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'stock_movements', m1, 'aval', 5, false)
   WHERE type = 'goods_receipts' AND id = gr;
  PERFORM _rec('T04b', 'depuis le MOUVEMENT, la frise voit la RÉCEPTION', n = 1, 'nœuds aval = ' || n);
END $$;

-- ── T05 — ISOLATION (D8) : le voisin ne rattache pas, et ne voit rien ───────
DO $$
DECLARE ta uuid; tb uuid; pa uuid; gra uuid; ma uuid; n int;
BEGIN
  ta := _mk_tenant('T762E1');
  INSERT INTO products (tenant_id, name, type) VALUES (ta, 'P-762-E1', 'stock') RETURNING id INTO pa;
  INSERT INTO goods_receipts (tenant_id, number, receipt_date, status)
    VALUES (ta, 'BR-762-E1', '2026-03-05', 'received') RETURNING id INTO gra;
  INSERT INTO stock_movements (tenant_id, product_id, type, movement_type, quantity, date,
                               reference, reference_type, reference_id)
    VALUES (ta, pa, 'in', 'in', 3, '2026-03-05', 'BR-762-E1', 'goods_receipt', gra) RETURNING id INTO ma;
  PERFORM _as_user();
  PERFORM chain_l16_receipt_movement(gra, ma);

  RESET ROLE;
  tb := _mk_tenant('T762E2');
  PERFORM _as_user();
  BEGIN
    PERFORM chain_l16_receipt_movement(gra, ma);
    PERFORM _rec('T05a', 'le VOISIN ne peut pas rattacher la réception d''autrui', false, 'accepté !');
  EXCEPTION WHEN no_data_found THEN
    PERFORM _rec('T05a', 'le VOISIN ne peut pas rattacher la réception d''autrui (no_data_found)', true, SQLERRM);
  END;

  SELECT count(*) INTO n FROM document_links
   WHERE amont_type = 'stock_movements' AND amont_id = ma AND aval_type = 'goods_receipts';
  PERFORM _rec('T05b', 'le voisin ne voit AUCUN lien de la société A', n = 0, 'liens visibles = ' || n);

  RESET ROLE;
  SELECT count(*) INTO n FROM document_links
   WHERE amont_id = ma AND effet = 'stock.receipt.movement_recorded' AND tenant_id = ta;
  PERFORM _rec('T05c', 'le lien de A existe toujours, un seul, et reste à A', n = 1, 'liens de A = ' || n);
END $$;

-- ── Le VERDICT (G5 : toute suite rend un verdict) ─────────────────────────
SELECT _audit_assert('762');
