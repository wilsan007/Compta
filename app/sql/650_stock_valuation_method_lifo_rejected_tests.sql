-- ============================================================
-- 650_stock_valuation_method_lifo_rejected_tests.sql — STK-03
--
-- Mesuré AVANT la 650 : `stock_valuation_method` acceptait 'lifo'
-- (CHECK (… IN ('cump','fifo','lifo'))), une méthode interdite par IAS 2,
-- le PCG (art. 213-1, CRC 2004-06) et le SYSCOHADA, et absente d'Odoo.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '650', false);
DELETE FROM _audit_results WHERE file = '650';

-- Établit une ligne company_settings pour la société, puis rend la main.
CREATE OR REPLACE FUNCTION _cs650(p_nom text, OUT t uuid) LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom, false);
  INSERT INTO company_settings (tenant_id, name, stock_valuation_method)
  VALUES (t, 'Société ' || p_nom, 'cump')
  ON CONFLICT DO NOTHING;
END $$;

-- T01 — 'lifo' est refusé (interdit par IAS 2 / PCG / SYSCOHADA)
DO $$
DECLARE t uuid; v_refus boolean := false;
BEGIN
  SELECT * INTO t FROM _cs650('VAL650T01');
  BEGIN
    UPDATE company_settings SET stock_valuation_method = 'lifo' WHERE tenant_id = t;
  EXCEPTION WHEN check_violation THEN v_refus := true;
  END;
  PERFORM _rec('T01', 'la méthode « lifo » est REFUSÉE (IAS 2, PCG 2005, SYSCOHADA)',
    v_refus, CASE WHEN v_refus THEN 'refusée par le CHECK' ELSE 'ACCEPTÉE — la règle n''est pas portée' END);
END $$;

-- T02 — 'cump' (défaut, moteur de la 254) reste accepté
DO $$
DECLARE t uuid; v_ok boolean := false;
BEGIN
  SELECT * INTO t FROM _cs650('VAL650T02');
  BEGIN
    UPDATE company_settings SET stock_valuation_method = 'cump' WHERE tenant_id = t;
    v_ok := true;
  EXCEPTION WHEN check_violation THEN v_ok := false;
  END;
  PERFORM _rec('T02', 'la méthode « cump » (défaut) reste acceptée', v_ok, 'ok=' || v_ok);
END $$;

-- T03 — 'fifo' (PEPS, admis par les normes) reste accepté
DO $$
DECLARE t uuid; v_ok boolean := false;
BEGIN
  SELECT * INTO t FROM _cs650('VAL650T03');
  BEGIN
    UPDATE company_settings SET stock_valuation_method = 'fifo' WHERE tenant_id = t;
    v_ok := true;
  EXCEPTION WHEN check_violation THEN v_ok := false;
  END;
  PERFORM _rec('T03', 'la méthode « fifo » (PEPS, admise) reste acceptée', v_ok, 'ok=' || v_ok);
END $$;

-- T04 — une valeur inconnue est refusée : seuls deux jeux de valeurs existent
DO $$
DECLARE t uuid; v_refus boolean := false;
BEGIN
  SELECT * INTO t FROM _cs650('VAL650T04');
  BEGIN
    UPDATE company_settings SET stock_valuation_method = 'xyz' WHERE tenant_id = t;
  EXCEPTION WHEN check_violation THEN v_refus := true;
  END;
  PERFORM _rec('T04', 'une méthode inconnue est refusée (jeu admis : cump, fifo)',
    v_refus, 'refus=' || v_refus);
END $$;

SELECT _audit_assert('650');
