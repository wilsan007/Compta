-- ============================================================
-- 254_stock_valuation_single_truth_tests.sql — couches et CUMP : une vérité
--
-- Constat (mesuré sur base neuve, avant la 254) : le produit valorise le stock
-- de deux façons qui ne se parlent pas.
--   * `create_journal_on_stock_movement` sort au **CUMP** du dépôt
--     (`stock_quantities.unit_cost`) — c'est ce que la comptabilité enregistre ;
--   * `consume_valuation_layers_on_exit` consomme les couches en **FIFO** et
--     garde le coût d'origine de chaque couche (`v_method := 'cump'` est écrit…
--     et jamais lu).
-- Conséquence mesurée : 100 unités à 10 puis 100 à 14 donnent un CUMP de 12 ;
-- une sortie de 50 diminue la **comptabilité de 600** (50 × 12) et les
-- **couches de 500** (50 × 10, la plus ancienne) — 100 € d'écart entre deux
-- tables qui prétendent décrire le même stock.
--
-- Ce que le fichier mesure, et ce qu'il refuse de laisser passer :
--   T01 la valeur des couches = quantité × CUMP (les deux tables d'accord)
--   T02 une sortie diminue les couches ET l'écriture du MÊME montant
--   T03 la cohérence tient sur un cycle entrée / sortie / entrée
--   T04 l'historique comptable n'est pas réécrit par la valorisation
--   T05 le paramètre `company_settings.stock_valuation_method` reste inerte :
--       'fifo' n'a jamais été appliqué par la comptabilité, et ne l'est
--       toujours pas — la limite est mesurée, pas supposée
--
-- Mesuré AVANT la 254 : T01 et T04 verts, **T02, T03 et T05 rouges**.
-- ============================================================
\ir ci/audit_helpers.sql
\ir ci/ledger_fixture.sql
SELECT set_config('audit.file', '254', false);
DELETE FROM _audit_results WHERE file = '254';

-- Société, dépôt, article — les mouvements sont créés par le scénario.
CREATE OR REPLACE FUNCTION _mk_val254(p_nom text, OUT t uuid, OUT wh uuid, OUT p uuid)
LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom, false);
  PERFORM _ledger_fixture(t);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt ' || p_nom)
    RETURNING id INTO wh;
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
    VALUES (t, 'Article ' || p_nom, 'A-' || p_nom, 'stock', 0) RETURNING id INTO p;
END $$;

-- Une entrée ou une sortie, comme les écrans et les déclencheurs les posent.
CREATE OR REPLACE FUNCTION _mv254(p_t uuid, p_p uuid, p_wh uuid, p_type text,
  p_qte numeric, p_cout numeric DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type,
    quantity, unit_cost, reference, movement_date, date)
  VALUES (p_t, p_p, p_wh, p_type, p_type, p_qte, p_cout,
          'MV-' || p_type || '-' || p_qte || '-' || COALESCE(p_cout::text, '0'), CURRENT_DATE, CURRENT_DATE);
END $$;

-- La valeur des couches, la quantité et le CUMP du dépôt.
CREATE OR REPLACE FUNCTION _val254(p_t uuid, p_p uuid, p_wh uuid,
  OUT couches_qte numeric, OUT couches_val numeric, OUT depot_qte numeric,
  OUT cump numeric, OUT reflets int)
LANGUAGE plpgsql AS $$
BEGIN
  SELECT COALESCE(sum(remaining_qty), 0), COALESCE(sum(remaining_qty * unit_cost), 0)
    INTO couches_qte, couches_val
    FROM stock_valuation_layers WHERE tenant_id = p_t AND product_id = p_p AND remaining_qty > 0;
  SELECT quantity, unit_cost INTO depot_qte, cump
    FROM stock_quantities WHERE tenant_id = p_t AND product_id = p_p AND warehouse_id = p_wh;
  SELECT count(DISTINCT unit_cost) INTO reflets
    FROM stock_valuation_layers WHERE tenant_id = p_t AND product_id = p_p AND remaining_qty > 0;
END $$;

-- ═════════════════════════════════════════════════════════════
-- T01 — la valeur des couches = quantité × CUMP
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; s record;
BEGIN
  SELECT * INTO v FROM (SELECT * FROM _mk_val254('VAL254T01')) x;
  PERFORM _mv254(v.t, v.p, v.wh, 'in', 100, 10);
  PERFORM _mv254(v.t, v.p, v.wh, 'in', 100, 14);
  SELECT * INTO s FROM (SELECT * FROM _val254(v.t, v.p, v.wh)) x;
  PERFORM _rec('T01', 'après 100@10 puis 100@14 : 200 unités à CUMP 12, couches = 2 400',
    s.depot_qte = 200 AND s.cump = 12 AND s.couches_qte = 200 AND s.couches_val = 2400,
    format('dépôt=%s à %s, couches=%s valant %s (200 à 12 = 2400 attendus)',
           s.depot_qte, s.cump, s.couches_qte, s.couches_val));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T02 — une sortie diminue les couches ET l'écriture du même montant
--       (c'est ici que FIFO et CUMP divergeaient de 100 €)
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; s record; v_ecr numeric;
BEGIN
  SELECT * INTO v FROM (SELECT * FROM _mk_val254('VAL254T02')) x;
  PERFORM _mv254(v.t, v.p, v.wh, 'in', 100, 10);
  PERFORM _mv254(v.t, v.p, v.wh, 'in', 100, 14);
  PERFORM _mv254(v.t, v.p, v.wh, 'out', 50);

  SELECT * INTO s FROM (SELECT * FROM _val254(v.t, v.p, v.wh)) x;
  -- Ce que la comptabilité a sorti : le crédit du compte 31x des écritures de sortie
  SELECT COALESCE(sum(jl.credit), 0) INTO v_ecr
  FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id
  WHERE je.tenant_id = v.t AND jl.account_code LIKE '31%' AND je.reference LIKE 'MV-out%';

  PERFORM _rec('T02', 'une sortie de 50 vaut 600 en comptabilité ET 600 en couches (CUMP 12)',
    s.couches_qte = 150 AND s.couches_val = 1800 AND v_ecr = 600 AND (2400 - s.couches_val) = v_ecr,
    format('couches restantes=%s valant %s (150 à 12 = 1800 attendus), sortie comptable=%s (600 attendue), écart=%s (0 attendu)',
           s.couches_qte, s.couches_val, v_ecr, 2400 - s.couches_val));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T03 — la cohérence tient sur un cycle entrée / sortie / entrée
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; s record; attendu numeric;
BEGIN
  SELECT * INTO v FROM (SELECT * FROM _mk_val254('VAL254T03')) x;
  PERFORM _mv254(v.t, v.p, v.wh, 'in', 100, 10);
  PERFORM _mv254(v.t, v.p, v.wh, 'out', 40);
  PERFORM _mv254(v.t, v.p, v.wh, 'in', 60, 16);
  SELECT * INTO s FROM (SELECT * FROM _val254(v.t, v.p, v.wh)) x;
  -- CUMP = (60 × 10 + 60 × 16) / 120 = 13
  attendu := round(s.depot_qte * s.cump, 2);
  PERFORM _rec('T03', 'entrée 100@10, sortie 40, entrée 60@16 : couches et CUMP d''accord (120 à 13 = 1 560)',
    s.depot_qte = 120 AND round(s.cump, 4) = 13 AND round(s.couches_val, 2) = attendu AND s.reflets = 1,
    format('dépôt=%s à %s, couches=%s valant %s (attendu %s), valeurs distinctes dans les couches=%s (1 attendue)',
           s.depot_qte, round(s.cump, 4), s.couches_qte, s.couches_val, attendu, s.reflets));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T04 — l'historique comptable n'est pas réécrit par la valorisation
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; n_av int; m_av numeric; n_ap int; m_ap numeric;
BEGIN
  SELECT * INTO v FROM (SELECT * FROM _mk_val254('VAL254T04')) x;
  PERFORM _mv254(v.t, v.p, v.wh, 'in', 100, 10);
  SELECT count(*), COALESCE(sum(jl.debit + jl.credit), 0) INTO n_av, m_av
  FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id
  WHERE je.tenant_id = v.t;
  PERFORM _mv254(v.t, v.p, v.wh, 'in', 100, 14);
  PERFORM _mv254(v.t, v.p, v.wh, 'out', 50);
  SELECT count(*) FILTER (WHERE je.reference LIKE 'MV-in%'), COALESCE(sum(jl.debit + jl.credit) FILTER (WHERE je.reference LIKE 'MV-in%'), 0)
    INTO n_ap, m_ap
  FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id
  WHERE je.tenant_id = v.t;
  PERFORM _rec('T04', 'la valorisation ne réécrit aucune écriture : l''entrée d''origine est intacte',
    m_av = 2000 AND m_ap >= 2000,
    format('après la 1ʳᵉ entrée : %s écritures pour %s ; après les deux suivantes, entrées cumulées = %s (≥ 2000 attendu)',
           n_av, m_av, m_ap));
END $$;

-- ═════════════════════════════════════════════════════════════
-- T05 — le paramètre de méthode reste inerte : 'fifo' n'est pas appliqué
--       (limite mesurée, dite — la comptabilité n'a jamais su faire FIFO)
-- ═════════════════════════════════════════════════════════════
DO $$
DECLARE v record; s record; v_ecr numeric;
BEGIN
  SELECT * INTO v FROM (SELECT * FROM _mk_val254('VAL254T05')) x;
  UPDATE company_settings SET stock_valuation_method = 'fifo' WHERE tenant_id = v.t;
  PERFORM _mv254(v.t, v.p, v.wh, 'in', 100, 10);
  PERFORM _mv254(v.t, v.p, v.wh, 'in', 100, 14);
  PERFORM _mv254(v.t, v.p, v.wh, 'out', 50);
  SELECT * INTO s FROM (SELECT * FROM _val254(v.t, v.p, v.wh)) x;
  SELECT COALESCE(sum(jl.credit), 0) INTO v_ecr
  FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id
  WHERE je.tenant_id = v.t AND jl.account_code LIKE '31%' AND je.reference LIKE 'MV-out%';
  PERFORM _rec('T05', 'avec la méthode « fifo » réglée, la valeur reste au CUMP — la limite est dite',
    s.couches_val = 1800 AND v_ecr = 600,
    format('couches=%s (1800 = 150 × 12, CUMP), sortie comptable=%s (600) — FIFO donnerait 1 900 et 500', s.couches_val, v_ecr));
END $$;

DROP FUNCTION _val254(uuid, uuid, uuid);
DROP FUNCTION _mv254(uuid, uuid, uuid, text, numeric, numeric);
DROP FUNCTION _mk_val254(text);

SELECT _audit_assert('254');
