-- ============================================================
-- 509_regle_production_of_source_mrp_tests.sql — partie B, lot Production, règle R-046
--
-- Ce que la règle garantit (doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md) :
--   T01  un OF créé d'origine `mrp` émet `manufacturing_orders.mrp_sourced` + trace ;
--   T02  un OF `manual` n'émet RIEN (la règle ne vise que le MRP) ;
--   T03  IDEMPOTENCE — repasser à `mrp` n'émet pas un second événement.
--
-- \ir ci/audit_helpers.sql : société posée en superutilisateur, puis rôle
-- `authenticated` (un utilisateur réel, sous RLS).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '509', false);
DELETE FROM _audit_results WHERE file = '509';

-- Société isolée + un article fabriqué.
CREATE OR REPLACE FUNCTION _b509(p_nom text, OUT t uuid, OUT p uuid)
LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO products (tenant_id, name, sku, type)
    VALUES (t, 'PF ' || p_nom, 'PF-' || p_nom, 'stock') RETURNING id INTO p;
END $$;

-- ── T01 : OF d'origine MRP ──────────────────────────────────────
DO $$
DECLARE x record; m uuid; ne int; nt int;
BEGIN
  x := _b509('T01');
  PERFORM _as_user();
  INSERT INTO manufacturing_orders (tenant_id, number, product_id, quantity, origin)
    VALUES (x.t, 'OF-T01', x.p, 5, 'mrp') RETURNING id INTO m;

  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'manufacturing_orders.mrp_sourced' AND de.aggregate_id = m;
  PERFORM _rec('T01a', 'un OF d''origine MRP émet manufacturing_orders.mrp_sourced',
    ne = 1, format('événements=%s (1 attendu)', ne));

  SELECT count(*) INTO nt FROM chain_traces ct
  WHERE ct.tenant_id = x.t AND ct.effet = 'production.order.mrp_sourced'
    AND ct.amont_id = m AND ct.resultat = 'applique';
  PERFORM _rec('T01b', 'la traçabilité amont de l''OF MRP est tracée « applique »',
    nt = 1, format('traces=%s (1 attendue)', nt));
END $$;

-- ── T02 : OF manuel → aucun événement ───────────────────────────
DO $$
DECLARE x record; m uuid; ne int;
BEGIN
  x := _b509('T02');
  PERFORM _as_user();
  INSERT INTO manufacturing_orders (tenant_id, number, product_id, quantity, origin)
    VALUES (x.t, 'OF-T02', x.p, 5, 'manual') RETURNING id INTO m;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'manufacturing_orders.mrp_sourced' AND de.aggregate_id = m;
  PERFORM _rec('T02', 'un OF d''origine manuelle n''émet rien',
    ne = 0, format('événements=%s (0 attendu)', ne));
END $$;

-- ── T03 : idempotence ───────────────────────────────────────────
DO $$
DECLARE x record; m uuid; ne int;
BEGIN
  x := _b509('T03');
  PERFORM _as_user();
  INSERT INTO manufacturing_orders (tenant_id, number, product_id, quantity, origin)
    VALUES (x.t, 'OF-T03', x.p, 5, 'mrp') RETURNING id INTO m;
  UPDATE manufacturing_orders SET origin = 'manual' WHERE id = m;
  UPDATE manufacturing_orders SET origin = 'mrp'    WHERE id = m;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'manufacturing_orders.mrp_sourced' AND de.aggregate_id = m;
  PERFORM _rec('T03', 'un rejeu de l''origine « mrp » n''émet pas un second événement',
    ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

SELECT _audit_assert('509');