-- ============================================================
-- 529_regle_r046_lier_proposition_tests.sql — partie B, lot Production, R-046
--
--   T01  un OF d'origine MRP est LIÉ à sa proposition « converted » + colonnes renseignées ;
--   T02  un OF d'origine MRP SANS proposition convertie ne pose aucun lien (« sans_effet »).
-- \ir ci/audit_helpers.sql.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '529', false);
DELETE FROM _audit_results WHERE file = '529';

CREATE OR REPLACE FUNCTION _b529(p_nom text, p_avec_prop boolean, OUT t uuid, OUT mo uuid, OUT prop uuid)
LANGUAGE plpgsql AS $$
DECLARE p uuid; run uuid;
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO products (tenant_id, name, sku, type) VALUES (t, 'PF ' || p_nom, 'PF-' || p_nom, 'stock') RETURNING id INTO p;
  SELECT id INTO run FROM mrp_runs WHERE tenant_id = t LIMIT 1;
  IF run IS NULL THEN
    INSERT INTO mrp_runs (tenant_id, run_number, run_date) VALUES (t, 'RUN-' || p_nom, CURRENT_DATE) RETURNING id INTO run;
  END IF;
  IF p_avec_prop THEN
    INSERT INTO mrp_proposals (tenant_id, mrp_run_id, product_id, proposal_type, status)
      VALUES (t, run, p, 'manufacture', 'converted') RETURNING id INTO prop;
  END IF;
  INSERT INTO manufacturing_orders (tenant_id, number, product_id, quantity, status, origin)
    VALUES (t, 'OF-' || p_nom, p, 5, 'planned', 'mrp') RETURNING id INTO mo;
END $$;

DO $$
DECLARE x record; v_prop uuid; nl int; ne int;
BEGIN
  x := _b529('T01', true);
  PERFORM _as_user();
  SELECT mrp_proposal_id INTO v_prop FROM manufacturing_orders WHERE id = x.mo;
  PERFORM _rec('T01a', 'l''OF porte la PROPOSITION MRP qui l''a créé',
    v_prop IS NOT NULL AND v_prop = x.prop, format('mrp_proposal_id=%s (attendu %s)', v_prop, x.prop));

  SELECT count(*) INTO nl FROM document_links dl
  WHERE dl.tenant_id = x.t AND dl.amont_type = 'manufacturing_orders' AND dl.amont_id = x.mo
    AND dl.aval_type = 'mrp_proposals' AND dl.effet = 'production.order.mrp_linked';
  PERFORM _rec('T01b', 'l''OF est LIÉ à sa proposition (1 lien)', nl = 1, format('liens=%s (1 attendu)', nl));

  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'manufacturing_orders.mrp_linked' AND de.aggregate_id = x.mo;
  PERFORM _rec('T01c', 'un événement manufacturing_orders.mrp_linked est émis', ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

DO $$
DECLARE x record; nl int; nt int;
BEGIN
  x := _b529('T02', false);
  PERFORM _as_user();
  SELECT count(*) INTO nl FROM document_links dl
  WHERE dl.tenant_id = x.t AND dl.amont_id = x.mo AND dl.effet = 'production.order.mrp_linked';
  SELECT count(*) INTO nt FROM chain_traces ct
  WHERE ct.tenant_id = x.t AND ct.effet = 'production.order.mrp_linked' AND ct.amont_id = x.mo AND ct.resultat = 'sans_effet';
  PERFORM _rec('T02', 'sans proposition convertie : aucun lien, trace « sans_effet »',
    nl = 0 AND nt = 1, format('liens=%s trace sans_effet=%s (0 / 1 attendus)', nl, nt));
END $$;

SELECT _audit_assert('529');