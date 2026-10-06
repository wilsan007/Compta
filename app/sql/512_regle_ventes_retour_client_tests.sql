-- ============================================================
-- 512_regle_ventes_retour_client_tests.sql — partie B, lot Ventes, règle R-007
--
-- Ce que la règle garantit (doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md) :
--   T01  un BL passé à `returned` RÉINTÈGRE la marchandise (1 entrée, même dépôt,
--        même coût), pose UN lien et UN événement ;
--   T02  un BL SANS sortie d'origine ne crée AUCUN stock fantôme (trace « sans_effet ») ;
--   T03  IDEMPOTENCE — un rejeu ne ré-intègre pas une seconde fois.
--
-- \ir ci/audit_helpers.sql.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '512', false);
DELETE FROM _audit_results WHERE file = '512';

-- Société isolée : dépôt, article (stock initial 100), un BL expédié avec SA sortie.
-- p_avec_sortie = false : le BL n'a jamais produit de sortie (cas T02).
CREATE OR REPLACE FUNCTION _b512(p_nom text, p_avec_sortie boolean DEFAULT true,
                                 OUT t uuid, OUT dn uuid, OUT wh uuid, OUT p uuid)
LANGUAGE plpgsql AS $$
DECLARE c uuid;
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt') RETURNING id INTO wh;
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client ' || p_nom) RETURNING id INTO c;
  INSERT INTO products (tenant_id, name, sku, type) VALUES (t, 'Art ' || p_nom, 'A-' || p_nom, 'stock') RETURNING id INTO p;
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type, quantity, unit_cost, reference, movement_date, date)
    VALUES (t, p, wh, 'in', 'in', 100, 8, 'INIT', CURRENT_DATE, CURRENT_DATE);
  INSERT INTO delivery_notes (tenant_id, number, customer_id, delivery_date, status, validation_status)
    VALUES (t, 'BL-' || p_nom, c, '2026-03-05', 'shipped', 'validated') RETURNING id INTO dn;
  INSERT INTO delivery_note_lines (tenant_id, delivery_note_id, product_id, description, quantity)
    VALUES (t, dn, p, 'Ligne ' || p_nom, 5);
  IF p_avec_sortie THEN
    INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type, quantity, unit_cost,
                                 reference, reference_type, reference_id, movement_date, date)
      VALUES (t, p, wh, 'out', 'out', 5, 8, 'BL-' || p_nom, 'delivery_note', dn, CURRENT_DATE, CURRENT_DATE);
  END IF;
END $$;

-- ── T01 : retour → réintégration ────────────────────────────────
DO $$
DECLARE x record; n_in int; nl int; ne int; cout numeric;
BEGIN
  x := _b512('T01');
  PERFORM _as_user();
  UPDATE delivery_notes SET status = 'returned' WHERE id = x.dn;

  SELECT count(*), max(unit_cost) INTO n_in, cout FROM stock_movements sm
  WHERE sm.tenant_id = x.t AND sm.reference = 'RET-BL-T01'
    AND sm.reference_type = 'delivery_note' AND sm.reference_id = x.dn AND sm.movement_type = 'in';
  PERFORM _rec('T01a', 'un retour réintègre 1 entrée, au coût de la sortie (8)',
    n_in = 1 AND cout = 8, format('entrées=%s coût=%s (1 / 8 attendus)', n_in, cout));

  SELECT count(*) INTO nl FROM document_links dl
  WHERE dl.tenant_id = x.t AND dl.amont_type = 'delivery_notes' AND dl.amont_id = x.dn
    AND dl.aval_type = 'stock_movements' AND dl.effet = 'sale.delivery.returned';
  PERFORM _rec('T01b', 'le BL est lié à son mouvement de retour', nl = 1, format('liens=%s (1 attendu)', nl));

  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'delivery_notes.returned' AND de.aggregate_id = x.dn;
  PERFORM _rec('T01c', 'un événement delivery_notes.returned est émis', ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

-- ── T02 : aucune sortie → aucun stock fantôme ───────────────────
DO $$
DECLARE x record; n_in int; n_trace int;
BEGIN
  x := _b512('T02', false);
  PERFORM _as_user();
  UPDATE delivery_notes SET status = 'returned' WHERE id = x.dn;
  SELECT count(*) INTO n_in FROM stock_movements sm
  WHERE sm.tenant_id = x.t AND sm.reference_type = 'delivery_note' AND sm.reference_id = x.dn
    AND sm.movement_type = 'in' AND sm.reference LIKE 'RET-%';
  SELECT count(*) INTO n_trace FROM chain_traces ct
  WHERE ct.tenant_id = x.t AND ct.effet = 'sale.delivery.returned' AND ct.amont_id = x.dn AND ct.resultat = 'sans_effet';
  PERFORM _rec('T02', 'un BL sans sortie ne crée aucun stock (trace « sans_effet »)',
    n_in = 0 AND n_trace = 1, format('entrées=%s trace sans_effet=%s (0 / 1 attendus)', n_in, n_trace));
END $$;

-- ── T03 : idempotence ───────────────────────────────────────────
DO $$
DECLARE x record; n_in int;
BEGIN
  x := _b512('T03');
  PERFORM _as_user();
  UPDATE delivery_notes SET status = 'returned' WHERE id = x.dn;
  UPDATE delivery_notes SET status = 'pending'  WHERE id = x.dn;  -- recule SANS re-expédier
  UPDATE delivery_notes SET status = 'returned' WHERE id = x.dn;
  SELECT count(*) INTO n_in FROM stock_movements sm
  WHERE sm.tenant_id = x.t AND sm.reference_type = 'delivery_note' AND sm.reference_id = x.dn
    AND sm.movement_type = 'in' AND sm.reference LIKE 'RET-%';
  PERFORM _rec('T03', 'un rejeu ne ré-intègre pas une seconde fois',
    n_in = 1, format('entrées de retour=%s (1 attendue)', n_in));
END $$;

SELECT _audit_assert('512');