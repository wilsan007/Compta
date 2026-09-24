-- ============================================================
-- 251_cancel_paths_and_quality_quantity_tests.sql — S-12, S-13
--
-- Audit des modules hors comptabilité (23/09), § S-08 à S-13 :
--
--   S-12 🟡 `create_stock_out_on_delivery` ne se déclenche plus deux fois
--           (230, entrée draft/confirmed → shipped) et un BL réexpédié est
--           refusé explicitement. MAIS aucun chemin d'annulation ne remet le
--           stock : une réception reçue puis annulée laisse son entrée en
--           stock, sa couche de valorisation et son écriture. Le stock affiché
--           ne correspond plus aux marchandises présentes.
--   S-13 🟠 `quality_checks` n'a PAS de colonne quantité. Un contrôle en échec
--           rebute `quantity_received` — la TOTALITÉ de la ligne reçue — même
--           si un seul article est défectueux, et l'écriture de rebut suit.
--
-- Ce fichier mesure aussi ce que la vague ne doit PAS casser : la réception
-- reste celle de la 241 (T01), un contrôle réussi n'entre pas deux fois (T05,
-- STK-01b/141), et un échec sans quantité contrôlée garde le comportement
-- d'avant — rebuter tout ce qui est reçu (T06).
--
-- 6 scénarios, T01 → T06. Mesuré AVANT la 251 : T02 (stock non rendu),
-- T03 (rien n'empêche une seconde contrepassation), T04 (10 rebutés au lieu
-- de 3) rouges ; T01, T05, T06 verts — ce sont les non-régressions.
-- ============================================================
\ir ci/audit_helpers.sql
\ir ci/ledger_fixture.sql
SELECT set_config('audit.file', '251', false);
DELETE FROM _audit_results WHERE file = '251';

-- Société, dépôt, article à 5 avec 100 en stock (dépôt et article d'accord,
-- couche de valorisation créée par le mouvement), prix d'achat de l'article.
CREATE OR REPLACE FUNCTION _mk_achat251(p_nom text, OUT t uuid, OUT wh uuid, OUT p uuid)
LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom, false);
  PERFORM _ledger_fixture(t);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt ' || p_nom)
    RETURNING id INTO wh;
  INSERT INTO products (tenant_id, name, sku, type, cost_price, purchase_price, stock_quantity)
    VALUES (t, 'Article ' || p_nom, 'A-' || p_nom, 'stock', 5, 5, 0) RETURNING id INTO p;
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type,
    quantity, unit_cost, reference, movement_date, date)
  VALUES (t, p, wh, 'in', 'in', 100, 5, 'APPRO-' || p_nom, CURRENT_DATE, CURRENT_DATE);
END $$;

-- Bon de réception : en-tête, ligne, puis passage au statut reçu.
CREATE OR REPLACE FUNCTION _br251(p_t uuid, p_wh uuid, p_p uuid, p_num text,
  p_qte numeric, p_cout numeric)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE gr uuid;
BEGIN
  -- 241 : le coût vient du prix d'achat de l'article (ou de la ligne de
  -- commande) ; le poser ici reproduit le paramétrage d'achat.
  UPDATE products SET purchase_price = p_cout WHERE id = p_p AND tenant_id = p_t;
  INSERT INTO goods_receipts (tenant_id, number, warehouse_id, receipt_date, status)
    VALUES (p_t, p_num, p_wh, CURRENT_DATE, 'pending') RETURNING id INTO gr;
  INSERT INTO goods_receipt_lines (tenant_id, goods_receipt_id, product_id, description,
    quantity_ordered, quantity_received)
    VALUES (p_t, gr, p_p, 'Article reçu', p_qte, p_qte);
  UPDATE goods_receipts SET status = 'received' WHERE id = gr;
  RETURN gr;
END $$;

-- Contrôle qualité : la quantité contrôlée et la quantité rebutée naissent avec
-- la 251 — avant elle, l'insertion dynamique échoue et le contrôle se pose sans
-- quantités (l'état mesuré du défaut S-13).
CREATE OR REPLACE FUNCTION _qc251(p_t uuid, p_gr uuid, p_p uuid, p_status text,
  p_checked numeric DEFAULT NULL, p_rejected numeric DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE qc uuid;
BEGIN
  BEGIN
    EXECUTE 'INSERT INTO quality_checks (tenant_id, product_id, reference_type, reference_id,
               status, checked_by, checked_at, quantity_checked, quantity_rejected)
             VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING id'
      INTO qc USING p_t, p_p, 'goods_receipt', p_gr, 'pending', 'audit', now(), p_checked, p_rejected;
  EXCEPTION WHEN undefined_column THEN
    INSERT INTO quality_checks (tenant_id, product_id, reference_type, reference_id,
      status, checked_by, checked_at)
      VALUES (p_t, p_p, 'goods_receipt', p_gr, 'pending', 'audit', now()) RETURNING id INTO qc;
  END;
  UPDATE quality_checks SET status = p_status WHERE id = qc;
  RETURN qc;
END $$;

-- L'état du stock, tel que l'écran le montre : article, dépôt, couches, valeur.
CREATE OR REPLACE FUNCTION _stock251(p_t uuid, p_p uuid, p_wh uuid,
  OUT article numeric, OUT depot numeric, OUT couches numeric, OUT valeur numeric)
LANGUAGE plpgsql AS $$
BEGIN
  SELECT stock_quantity INTO article FROM products WHERE id = p_p AND tenant_id = p_t;
  SELECT quantity INTO depot FROM stock_quantities
    WHERE tenant_id = p_t AND product_id = p_p AND warehouse_id = p_wh;
  SELECT COALESCE(sum(remaining_qty), 0), COALESCE(sum(remaining_qty * unit_cost), 0)
    INTO couches, valeur
    FROM stock_valuation_layers WHERE tenant_id = p_t AND product_id = p_p;
END $$;

-- L'écriture de stock d'une référence : nombre, débit et crédit du compte 31x.
CREATE OR REPLACE FUNCTION _ecr251(p_t uuid, p_ref text,
  OUT nb int, OUT d31 numeric, OUT c31 numeric, OUT statut text)
LANGUAGE plpgsql AS $$
BEGIN
  SELECT count(DISTINCT je.id), COALESCE(sum(jl.debit), 0), COALESCE(sum(jl.credit), 0), max(je.status)
    INTO nb, d31, c31, statut
  FROM journal_entries je
  LEFT JOIN journal_lines jl ON jl.journal_id = je.id AND jl.account_code LIKE '31%'
  WHERE je.tenant_id = p_t AND je.reference = p_ref;
END $$;



-- ═════════════════════════════════════════════════════════════
-- T01 — non-régression 241 : la réception reçue entre en stock, au
--       dépôt, en couches, et en comptabilité
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE a record; s record; e record;
BEGIN
  SELECT * INTO a FROM (SELECT * FROM _mk_achat251('A251T01')) x;
  PERFORM _br251(a.t, a.wh, a.p, 'T01', 10, 7);
  SELECT * INTO s FROM (SELECT * FROM _stock251(a.t, a.p, a.wh)) x;
  SELECT * INTO e FROM (SELECT * FROM _ecr251(a.t, 'BR-T01')) x;
  PERFORM _rec('T01', 'la réception entre en stock, au dépôt et au journal ST (241 non régressée)',
    s.article = 110 AND s.depot = 110 AND s.couches = 110 AND s.valeur = 570
      AND e.nb = 1 AND e.d31 = 70 AND e.c31 = 0 AND e.statut = 'posted',
    format('article=%s dépôt=%s couches=%s valeur=%s (110/110/110/570 attendus) | BR-T01 : %s écriture(s) %s, D31=%s, C31=%s',
           s.article, s.depot, s.couches, s.valeur, e.nb, e.statut, e.d31, e.c31));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T02 — S-12 : annuler une réception remet le stock et contrepasse
--       l'écriture (l'écriture d'origine reste intacte)
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE a record; s record; eo record; ea record; gr uuid; n int;
BEGIN
  SELECT * INTO a FROM (SELECT * FROM _mk_achat251('A251T02')) x;
  gr := _br251(a.t, a.wh, a.p, 'T02', 10, 7);
  UPDATE goods_receipts SET status = 'cancelled' WHERE id = gr;
  SELECT * INTO s FROM (SELECT * FROM _stock251(a.t, a.p, a.wh)) x;
  SELECT * INTO eo FROM (SELECT * FROM _ecr251(a.t, 'BR-T02')) x;
  SELECT * INTO ea FROM (SELECT * FROM _ecr251(a.t, 'BR-ANN-T02')) x;
  SELECT count(*) INTO n FROM stock_movements
    WHERE tenant_id = a.t AND reference_type = 'goods_receipt_cancel' AND reference_id = gr;
  PERFORM _rec('T02', 'annuler une réception remet le stock et contrepasse son écriture (S-12)',
    s.article = 100 AND s.depot = 100 AND s.couches = 100 AND n = 1
      AND eo.nb = 1 AND eo.d31 = 70 AND eo.c31 = 0 AND eo.statut = 'posted'
      AND ea.nb = 1 AND ea.c31 = 70 AND ea.d31 = 0 AND ea.statut = 'posted',
    format('article=%s dépôt=%s couches=%s (100/100/100 attendus), contrepassations=%s (1 attendue) | origine D31=%s (%s), contrepartie C31=%s (%s)',
           s.article, s.depot, s.couches, n, eo.d31, eo.statut, ea.c31, ea.statut));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T03 — S-12 : une réception ne rentre pas deux fois, une
--       contrepassation ne s'écrit pas deux fois
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE a record; s record; gr uuid; s1 text; s2 text; s3 text; n int; err text := '—';
BEGIN
  SELECT * INTO a FROM (SELECT * FROM _mk_achat251('A251T03')) x;
  gr := _br251(a.t, a.wh, a.p, 'T03', 10, 7);
  UPDATE goods_receipts SET status = 'cancelled' WHERE id = gr;

  -- (a) réexpédier une réception annulée : l'entrée de stock existe déjà
  BEGIN
    UPDATE goods_receipts SET status = 'received' WHERE id = gr;
  EXCEPTION WHEN others THEN s1 := SQLSTATE; err := SQLERRM;
  END;

  -- (b) annuler deux fois : le statut ne change pas, rien ne se contrepasse
  BEGIN
    UPDATE goods_receipts SET status = 'cancelled' WHERE id = gr;
    s2 := 'aucune erreur';
  EXCEPTION WHEN others THEN s2 := SQLSTATE;
  END;

  -- (c) l'état hostile fabriqué : le statut remis à « reçu » en neutralisant le
  --     déclencheur d'entrée (comme une base d'avant la 251), puis une seconde
  --     annulation — la garde explicite doit refuser.
  ALTER TABLE goods_receipts DISABLE TRIGGER trg_goods_receipt_stock;
  ALTER TABLE goods_receipts DISABLE TRIGGER prevent_goods_receipt_double_entry_trg;
  UPDATE goods_receipts SET status = 'received' WHERE id = gr;
  ALTER TABLE goods_receipts ENABLE TRIGGER prevent_goods_receipt_double_entry_trg;
  ALTER TABLE goods_receipts ENABLE TRIGGER trg_goods_receipt_stock;
  BEGIN
    UPDATE goods_receipts SET status = 'cancelled' WHERE id = gr;
  EXCEPTION WHEN others THEN s3 := SQLSTATE; err := SQLERRM;
  END;

  SELECT * INTO s FROM (SELECT * FROM _stock251(a.t, a.p, a.wh)) x;
  SELECT count(*) INTO n FROM stock_movements
    WHERE tenant_id = a.t AND reference_type = 'goods_receipt_cancel' AND reference_id = gr;
  PERFORM _rec('T03', 'une réception annulée ne se réexpédie pas, et ne se contrepasse qu''une fois',
    s1 = '23505' AND s2 = 'aucune erreur' AND s3 = '23505'
      AND s.article = 100 AND s.depot = 100 AND n = 1,
    format('réexpédition SQLSTATE=%s (23505 attendu), 2ᵉ annulation=%s, contrepassation forcée SQLSTATE=%s (23505 attendu), stock=%s/%s, contrepassations=%s | %s',
           COALESCE(s1, 'aucune erreur'), s2, COALESCE(s3, 'aucune erreur'), s.article, s.depot, n, left(err, 60)));
END $$;


-- ═════════════════════════════════════════════════════════════
-- T04 — S-13 : un contrôle en échec ne rebute que la quantité
--       contrôlée, jamais la totalité de la ligne reçue
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE a record; s record; gr uuid; qc uuid; n int; q numeric; s_ref text; err text := '—';
BEGIN
  SELECT * INTO a FROM (SELECT * FROM _mk_achat251('A251T04')) x;
  gr := _br251(a.t, a.wh, a.p, 'T04', 10, 7);
  qc := _qc251(a.t, gr, a.p, 'failed', 3);
  SELECT * INTO s FROM (SELECT * FROM _stock251(a.t, a.p, a.wh)) x;
  SELECT COALESCE(sum(quantity), 0) INTO q FROM stock_movements
    WHERE tenant_id = a.t AND reference_type = 'quality_check' AND movement_type = 'out';
  SELECT count(*) INTO n FROM stock_movements
    WHERE tenant_id = a.t AND reference_type = 'quality_check' AND reference_id = qc;
  -- Un contrôle ne peut pas inspecter plus qu'il n'est entré.
  BEGIN
    UPDATE quality_checks SET quantity_checked = 20 WHERE id = qc;
  EXCEPTION WHEN others THEN s_ref := SQLSTATE; err := SQLERRM;
  END;
  PERFORM _rec('T04', 'un contrôle en échec ne rebute que la quantité contrôlée (S-13)',
    s.article = 107 AND s.depot = 107 AND s.couches = 107 AND n = 1 AND q = 3 AND s_ref = '23514',
    format('article=%s dépôt=%s couches=%s (107/107/107 attendus), rebuts=%s de %s unités (1 de 3 attendus), contrôle de 20 sur 10 reçus SQLSTATE=%s | %s',
           s.article, s.depot, s.couches, n, q, COALESCE(s_ref, 'aucune erreur'), left(err, 60)));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T05 — non-régression 141 : un contrôle réussi n'entre pas une
--       seconde fois en stock (la réception l'a déjà fait)
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE a record; s record; gr uuid; n int;
BEGIN
  SELECT * INTO a FROM (SELECT * FROM _mk_achat251('A251T05')) x;
  gr := _br251(a.t, a.wh, a.p, 'T05', 10, 7);
  PERFORM _qc251(a.t, gr, a.p, 'passed');
  SELECT * INTO s FROM (SELECT * FROM _stock251(a.t, a.p, a.wh)) x;
  SELECT count(*) INTO n FROM stock_movements
    WHERE tenant_id = a.t AND reference_type = 'quality_check';
  PERFORM _rec('T05', 'un contrôle réussi n''ajoute pas de mouvement : la réception a déjà fait entrer (141 non régressée)',
    s.article = 110 AND s.depot = 110 AND n = 0,
    format('article=%s dépôt=%s (110/110 attendus), mouvements de contrôle=%s (0 attendu)', s.article, s.depot, n));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T06 — S-13, le comportement d'avant, dit : un échec sans
--       quantité contrôlée rebute tout ce qui est reçu
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE a record; s record; gr uuid; n int; q numeric;
BEGIN
  SELECT * INTO a FROM (SELECT * FROM _mk_achat251('A251T06')) x;
  gr := _br251(a.t, a.wh, a.p, 'T06', 10, 7);
  PERFORM _qc251(a.t, gr, a.p, 'failed');
  SELECT * INTO s FROM (SELECT * FROM _stock251(a.t, a.p, a.wh)) x;
  SELECT count(*), COALESCE(sum(quantity), 0) INTO n, q FROM stock_movements
    WHERE tenant_id = a.t AND reference_type = 'quality_check' AND movement_type = 'out';
  PERFORM _rec('T06', 'un échec sans quantité contrôlée rebute la totalité du reçu (comportement documenté)',
    s.article = 100 AND s.depot = 100 AND n = 1 AND q = 10,
    format('article=%s dépôt=%s (100/100 attendus), rebuts=%s de %s unités (1 de 10 attendus)', s.article, s.depot, n, q));
END $$;

DROP FUNCTION _qc251(uuid, uuid, uuid, text, numeric, numeric);
DROP FUNCTION _br251(uuid, uuid, uuid, text, numeric, numeric);
DROP FUNCTION _ecr251(uuid, text);
DROP FUNCTION _stock251(uuid, uuid, uuid);
DROP FUNCTION _mk_achat251(text);

SELECT _audit_assert('251');
