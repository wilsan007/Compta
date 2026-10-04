-- ============================================================
-- 229_manufacturing_order_tests.sql — M-08 : la production, au-delà de la 177
--
-- La 177 prouve le coût d'un OF sans incident. Ces scénarios prennent les deux
-- cas que la vie impose et que rien ne vérifiait : un OF qui produit des
-- rebuts, et un OF qu'on clôture deux fois.
--
-- Mesuré sur base neuve à la 228, AVANT la 229 :
--   T01 stock produit fini = 100 au lieu de 90   (rebuts entrés comme bons)
--   T02 coût unitaire = 10,00 au lieu de 11,11   (réparti sur 100 au lieu de 90)
--   T03 qty_produced = 100, donc produit + rebuté = 110 pour 100 lancées
--   T04 seconde clôture acceptée : 20 pièces entrées pour 10 produites
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '229', false);
DELETE FROM _audit_results WHERE file = '229';

-- Atelier complet : dépôt, matière approvisionnée, produit fini, nomenclature.
-- 1 produit fini consomme 2 matières à 5,00 → 10,00 de matière par pièce.
CREATE OR REPLACE FUNCTION _mk_atelier229(p_nom text, p_qte numeric, p_rebut numeric,
  OUT t uuid, OUT wh uuid, OUT pf uuid, OUT mp uuid, OUT mo uuid)
LANGUAGE plpgsql AS $$
DECLARE b uuid;
BEGIN
  t := _mk_tenant(p_nom);
  PERFORM ensure_standard_journals(t);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt') RETURNING id INTO wh;
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
    VALUES (t, 'Produit fini ' || p_nom, 'PF-' || p_nom, 'stock', 0) RETURNING id INTO pf;
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
    VALUES (t, 'Matière ' || p_nom, 'MP-' || p_nom, 'stock', 5) RETURNING id INTO mp;
  INSERT INTO boms (tenant_id, code, name, product_id, quantity)
    VALUES (t, 'B-' || p_nom, 'Nomenclature ' || p_nom, pf, 1) RETURNING id INTO b;
  INSERT INTO bom_lines (tenant_id, bom_id, product_id, quantity, unit_cost) VALUES (t, b, mp, 2, 5);
  -- Approvisionnement de la matière, hors production (reference_type NULL)
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type, quantity, unit_cost, reference, movement_date, date)
    VALUES (t, mp, wh, 'in', 'in', 10000, 5, 'APPRO', CURRENT_DATE, CURRENT_DATE);
  INSERT INTO manufacturing_orders (tenant_id, number, bom_id, product_id, quantity, status, warehouse_id, qty_scrapped)
    VALUES (t, 'OF-' || p_nom, b, pf, p_qte, 'planned', wh, p_rebut) RETURNING id INTO mo;
END $$;

-- T01/T02/T03 : un OF de 100 pièces dont 10 rebutées
DO $$
DECLARE a record; q_in numeric; q_out numeric; uc numeric; ct numeric; qp numeric; qs numeric;
BEGIN
  a := _mk_atelier229('T01', 100, 10);
  PERFORM _as_user();
  UPDATE manufacturing_orders SET status = 'completed' WHERE id = a.mo;
  PERFORM set_config('role', 'postgres', true);

  SELECT COALESCE(sum(quantity) FILTER (WHERE movement_type = 'in'), 0),
         COALESCE(sum(quantity) FILTER (WHERE movement_type = 'out'), 0)
    INTO q_in, q_out
  FROM stock_movements WHERE tenant_id = a.t AND reference_type = 'production';
  SELECT unit_cost, cost_total, qty_produced, COALESCE(qty_scrapped, 0)
    INTO uc, ct, qp, qs FROM manufacturing_orders WHERE id = a.mo;

  PERFORM _rec('T01', '100 lancées dont 10 rebutées : 90 pièces entrent en stock, pas 100',
    q_in = 90,
    format('entrées en stock=%s (90 attendues) sorties matières=%s (200 attendues)', q_in, q_out));

  PERFORM _rec('T02', 'le coût total se répartit sur les pièces bonnes : 1 000 / 90 = 11,11',
    ct = 1000 AND round(uc, 2) = 11.11,
    format('coût total=%s (1000 attendu) coût unitaire=%s (11,11 attendu)', ct, round(COALESCE(uc, 0), 2)));

  PERFORM _rec('T03', 'produites + rebutées = lancées (90 + 10 = 100)',
    qp = 90 AND qs = 10 AND qp + qs = 100,
    format('qty_produced=%s (90 attendu) qty_scrapped=%s (10 attendu) somme=%s (100 attendue)', qp, qs, qp + qs));
END $$;

-- T04 : OF terminé → annulé → terminé. Les trois statuts sont permis par la
--       contrainte CHECK, donc le chemin est atteignable depuis l'écran.
DO $$
DECLARE a record; n_in int; q_in numeric; n_je int; refuse boolean := false; err text := '—';
BEGIN
  a := _mk_atelier229('T04', 10, 0);
  PERFORM _as_user();
  UPDATE manufacturing_orders SET status = 'completed' WHERE id = a.mo;
  UPDATE manufacturing_orders SET status = 'cancelled' WHERE id = a.mo;
  BEGIN
    UPDATE manufacturing_orders SET status = 'completed' WHERE id = a.mo;
  EXCEPTION WHEN OTHERS THEN refuse := true; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);

  SELECT count(*), COALESCE(sum(quantity), 0) INTO n_in, q_in
  FROM stock_movements WHERE tenant_id = a.t AND reference_type = 'production' AND movement_type = 'in';
  SELECT count(*) INTO n_je FROM journal_entries WHERE tenant_id = a.t AND reference = 'JE-OF-OF-T04';

  PERFORM _rec('T04', 'reclôturer un OF : refusé, 10 pièces entrées une seule fois, une seule écriture',
    refuse AND n_in = 1 AND q_in = 10 AND n_je = 1,
    format('refus=%s entrées=%s (1 attendue) quantité=%s (10 attendue) écritures=%s (1 attendue) | %s',
           refuse, n_in, q_in, n_je, left(err, 70)));
END $$;

-- T05 : non-régression — un OF sans rebut se comporte comme avant la 229
DO $$
DECLARE a record; q_in numeric; q_out numeric; uc numeric; n_je int;
        v_deb numeric; v_cre numeric; st text;
BEGIN
  a := _mk_atelier229('T05', 10, 0);
  PERFORM _as_user();
  UPDATE manufacturing_orders SET status = 'completed' WHERE id = a.mo;
  PERFORM set_config('role', 'postgres', true);

  SELECT COALESCE(sum(quantity) FILTER (WHERE movement_type = 'in'), 0),
         COALESCE(sum(quantity) FILTER (WHERE movement_type = 'out'), 0)
    INTO q_in, q_out
  FROM stock_movements WHERE tenant_id = a.t AND reference_type = 'production';
  SELECT unit_cost INTO uc FROM manufacturing_orders WHERE id = a.mo;
  SELECT count(*) INTO n_je FROM journal_entries WHERE tenant_id = a.t AND reference = 'JE-OF-OF-T05';
  SELECT status INTO st FROM journal_entries WHERE tenant_id = a.t AND reference = 'JE-OF-OF-T05';
  SELECT COALESCE(sum(jl.debit), 0), COALESCE(sum(jl.credit), 0) INTO v_deb, v_cre
  FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id
  WHERE je.tenant_id = a.t AND je.reference = 'JE-OF-OF-T05';

  PERFORM _rec('T05', 'sans rebut : 10 entrées, 20 sorties matières, coût unitaire 10,00',
    q_in = 10 AND q_out = 20 AND round(uc, 2) = 10.00,
    format('entrées=%s sorties=%s coût unitaire=%s', q_in, q_out, round(COALESCE(uc, 0), 2)));

  PERFORM _rec('T06', 'l''écriture de production est équilibrée, validée, dans le journal OF',
    n_je = 1 AND st = 'posted' AND v_deb = v_cre AND v_deb = 200,
    format('écritures=%s statut=%s débit=%s crédit=%s (200 = 100 matières + 100 produit fini)',
           n_je, COALESCE(st, '—'), v_deb, v_cre));
END $$;

DROP FUNCTION _mk_atelier229(text, numeric, numeric);
SELECT _audit_assert('229');
