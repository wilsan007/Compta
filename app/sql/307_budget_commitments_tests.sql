-- ============================================================
-- 307_budget_commitments_tests.sql — W7 (M-04) : les engagements vivent
--
--   BUD-03 🟠 `budget_commitments` prévoit `status = 'consumed'` et
--             `source_type IN ('purchase_order','purchase_invoice')`, mais
--             **rien ne crée d'engagement depuis une commande, et rien ne le
--             solde à la facturation** : un engagement saisi (ou laissé actif)
--             est déduit une première fois comme engagement, puis une seconde
--             comme réalisé — le disponible est faux.
--
-- Les scénarios : confirmer une commande crée l'engagement ; l'approbation de
-- la facture liée le **consomme** ; annuler la commande l'annule ; confirmer
-- deux fois ne duplique pas.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '307', false);
DELETE FROM _audit_results WHERE file = '307';

DROP FUNCTION IF EXISTS _bud307_commande(uuid, uuid, numeric);
CREATE OR REPLACE FUNCTION _bud307_commande(p_t uuid, p_s uuid, p_montant numeric)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE o uuid; pr uuid;
BEGIN
  INSERT INTO suppliers (tenant_id, name, account_tiers) VALUES (p_t, 'Fournisseur ' || left(p_s::text, 6), 'F' || left(p_s::text, 6))
    RETURNING id INTO pr;
  INSERT INTO purchase_orders (tenant_id, number, supplier_id, order_date, expected_date, status, subtotal, vat, total)
  VALUES (p_t, 'BC-' || left(uuid_generate_v4()::text, 8), pr, '2026-03-10', '2026-03-20', 'draft', p_montant, 0, p_montant)
  RETURNING id INTO o;
  INSERT INTO purchase_order_lines (tenant_id, purchase_order_id, description, quantity, unit_price, vat_rate, line_total, line_order)
  VALUES (p_t, o, 'Article', 1, p_montant, 0, p_montant, 1);
  RETURN o;
END $$;

-- T01/T03 — confirmer une commande de 1 000 crée **un** engagement actif de
-- 1 000 ; la confirmer de nouveau ne le duplique pas.
DO $$
DECLARE t uuid; s uuid; o uuid; n int; mnt numeric; st text; src text;
BEGIN
  t := _mk_tenant('BUD01');
  PERFORM _as_user();
  BEGIN
    o := _bud307_commande(t, uuid_generate_v4(), 1000);
    UPDATE purchase_orders SET status = 'confirmed' WHERE id = o;
    UPDATE purchase_orders SET status = 'draft' WHERE id = o;
    UPDATE purchase_orders SET status = 'confirmed' WHERE id = o;
    PERFORM set_config('role', 'postgres', true);
    SELECT count(*), COALESCE(sum(amount), 0), max(status), max(source_type)
      INTO n, mnt, st, src FROM budget_commitments WHERE tenant_id = t;
    PERFORM _rec('T01', 'confirmer une commande de 1 000 crée un engagement actif de 1 000',
      n = 1 AND mnt = 1000 AND st = 'active' AND src = 'purchase_order',
      format('engagements=%s montant=%s statut=%s source=%s', n, mnt, st, src));
    PERFORM _rec('T03', 'confirmer deux fois la même commande ne duplique pas l''engagement',
      n = 1, format('engagements=%s (1 attendu)', n));
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'postgres', true);
    PERFORM _rec('T01', 'confirmer une commande de 1 000 crée un engagement actif de 1 000', false, SQLERRM);
    PERFORM _rec('T03', 'confirmer deux fois la même commande ne duplique pas l''engagement', false, SQLERRM);
  END;
END $$;

-- T02 — l'approbation de la facture **liée à la commande** consomme l'engagement :
-- le réalisé prend le relais, l'engagement n'est plus déduit deux fois.
DO $$
DECLARE t uuid; s uuid; o uuid; f uuid; st text; n int;
BEGIN
  t := _mk_tenant('BUD02');
  PERFORM _as_user();
  BEGIN
    s := uuid_generate_v4();
    o := _bud307_commande(t, s, 2000);
    UPDATE purchase_orders SET status = 'confirmed' WHERE id = o;
    INSERT INTO purchase_invoices (tenant_id, number, supplier_id, supplier_name, date, due_date,
                                   status, subtotal, vat_total, total, amount_paid, amount_due,
                                   approval_status, purchase_order_id)
    SELECT tenant_id, 'FRN-' || left(uuid_generate_v4()::text, 8), supplier_id, 'Fournisseur',
           CURRENT_DATE, CURRENT_DATE + 30, 'draft', 2000, 0, 2000, 0, 2000, 'pending', id
    FROM purchase_orders WHERE id = o
    RETURNING id INTO f;
    INSERT INTO purchase_invoice_lines (tenant_id, purchase_invoice_id, description, quantity,
                                        unit_price, vat_rate, vat_code, total, vat_amount, line_order)
    VALUES (t, f, 'Article', 1, 2000, 0, 'FR0', 2000, 0, 1);
    PERFORM set_config('role', 'postgres', true);

    PERFORM _as_user();
    UPDATE purchase_invoices SET approval_status = 'approved' WHERE id = f;
    PERFORM set_config('role', 'postgres', true);

    SELECT count(*) INTO n FROM budget_commitments WHERE tenant_id = t AND status = 'active';
    SELECT max(status) INTO st FROM budget_commitments WHERE tenant_id = t;
    PERFORM _rec('T02', 'l''approbation de la facture liée consomme l''engagement (plus de double déduction)',
      st = 'consumed' AND n = 0,
      format('statut=%s engagements encore actifs=%s (0 attendu)', st, n));
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'postgres', true);
    PERFORM _rec('T02', 'l''approbation de la facture liée consomme l''engagement (plus de double déduction)', false, SQLERRM);
  END;
END $$;

-- T04 — annuler la commande annule l'engagement resté actif.
DO $$
DECLARE t uuid; o uuid; st text;
BEGIN
  t := _mk_tenant('BUD03');
  PERFORM _as_user();
  BEGIN
    o := _bud307_commande(t, uuid_generate_v4(), 500);
    UPDATE purchase_orders SET status = 'confirmed' WHERE id = o;
    UPDATE purchase_orders SET status = 'cancelled' WHERE id = o;
    PERFORM set_config('role', 'postgres', true);
    SELECT max(status) INTO st FROM budget_commitments WHERE tenant_id = t;
    PERFORM _rec('T04', 'annuler la commande annule l''engagement actif',
      st = 'cancelled', format('statut=%s (cancelled attendu)', st));
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'postgres', true);
    PERFORM _rec('T04', 'annuler la commande annule l''engagement actif', false, SQLERRM);
  END;
END $$;

DROP FUNCTION _bud307_commande(uuid, uuid, numeric);
SELECT _audit_assert('307');

