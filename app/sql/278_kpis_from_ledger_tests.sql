-- ============================================================
-- 278_kpis_from_ledger_tests.sql — vague X6 / M5
--
--   T01 get_kpis = grand livre : CA 70x, charges 6x, encours 411x / 401x, trésorerie 5x
--   T02 la période borne les flux (CA, charges) ; les soldes sont cumulés au p_to
--   T03 une autre société ne voit pas ces chiffres
--   T04 une facture validée passe au statut « émise » (sent)
--
-- T01–T04 sont ROUGES avant la 278.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '278', false);
DELETE FROM _audit_results WHERE file = '278';

DO $$
DECLARE t uuid; t2 uuid; k jsonb; k2 jsonb; kb jsonb; ex text;
BEGIN
  t := _mk_tenant('X6M5');
  PERFORM _entry(t, 'V1', '2026-03-10', '[{"a":"411000","d":1200},{"a":"707000","c":1000},{"a":"445711","c":200}]');
  PERFORM _entry(t, 'A1', '2026-04-05', '[{"a":"607000","d":500},{"a":"445661","d":100},{"a":"401000","c":600}]');
  PERFORM _entry(t, 'R1', '2026-05-02', '[{"a":"512000","d":700},{"a":"411000","c":700}]');
  PERFORM _entry(t, 'V2', '2026-11-15', '[{"a":"411000","d":240},{"a":"706000","c":200},{"a":"445711","c":40}]');
  PERFORM _entry(t, 'BR', '2026-06-01', '[{"a":"606100","d":999},{"a":"512000","c":999}]', false);  -- brouillon : ignoré
  PERFORM _as_user();
  BEGIN
    EXECUTE 'SELECT get_kpis($1, $2)' INTO k USING '2026-01-01'::date, '2026-12-31'::date;
    EXECUTE 'SELECT get_kpis($1, $2)' INTO k2 USING '2026-04-01'::date, '2026-06-30'::date;
  EXCEPTION WHEN undefined_function THEN ex := SQLERRM;
  END;
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T01', 'get_kpis = grand livre (CA 1 200, charges 500, clients 740, fournisseurs 600, trésorerie 700)',
    ex IS NULL AND (k->>'revenue')::numeric = 1200 AND (k->>'expenses')::numeric = 500 AND (k->>'receivables')::numeric = 740
      AND (k->>'payables')::numeric = 600 AND (k->>'cash')::numeric = 700 AND (k->>'draft_entries')::int = 1,
    coalesce(ex, k::text));
  PERFORM _rec('T02', 'avril-juin : CA 0, charges 500 ; soldes au 30/06 (clients 500, trésorerie 700)',
    ex IS NULL AND (k2->>'revenue')::numeric = 0 AND (k2->>'expenses')::numeric = 500
      AND (k2->>'receivables')::numeric = 500 AND (k2->>'cash')::numeric = 700, coalesce(ex, k2::text));

  t2 := _mk_tenant('X6M5B');
  PERFORM _as_user();
  BEGIN
    EXECUTE 'SELECT get_kpis($1, $2)' INTO kb USING '2026-01-01'::date, '2026-12-31'::date;
  EXCEPTION WHEN undefined_function THEN ex := SQLERRM;
  END;
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T03', 'une autre société ne voit pas ces chiffres', ex IS NULL AND (kb->>'revenue')::numeric = 0 AND (kb->>'cash')::numeric = 0,
    coalesce(ex, kb::text));
END $$;

DO $$
DECLARE t uuid; c uuid; i uuid; st text;
BEGIN
  t := _mk_tenant('X6M5F');
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client') RETURNING id INTO c;
  PERFORM _as_user();
  INSERT INTO invoices (tenant_id, customer_id, customer_name, date, due_date, status) VALUES (t, c, 'Client', '2026-09-10', '2026-10-10', 'draft') RETURNING id INTO i;
  INSERT INTO invoice_lines (tenant_id, invoice_id, description, quantity, unit_price, vat_rate, total, vat_amount)
  VALUES (t, i, 'Prestation', 1, 100, 20, 100, 20);
  UPDATE invoices SET validation_status = 'validated' WHERE id = i;
  EXECUTE 'RESET ROLE';
  SELECT status INTO st FROM invoices WHERE id = i;
  PERFORM _rec('T04', 'une facture validée passe au statut « émise » (sent)', st = 'sent', st);
END $$;

SELECT _audit_assert('278');
