-- ============================================================
-- 216_document_number_year_tests.sql — le numéro légal porte l'année
--
-- Défaut trouvé sur copie de production (P0-06) : le numéro reprenait le code
-- libre de l'exercice. Selon la société, une facture s'appelait
-- FAC-2026-000001, FAC-FY2026-000001 (code posé par l'inscription) ou
-- FAC-EX2024-000001 (sociétés reprises).
--
-- N01 — exercice nommé « FY2026 » (ce que crée l'inscription) → FAC-2026-000001
-- N02 — exercice nommé « EX2024 » (sociétés reprises)        → FAC-2024-000001
-- N03 — exercice sans chiffre dans son code                  → année de début
-- N04 — deux sociétés aux codes différents, même année : même format, et
--       chacune garde son propre compteur
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '216', false);
DELETE FROM _audit_results WHERE file = '216';

-- Société avec un exercice au code choisi, et une facture d'une ligne validée
CREATE OR REPLACE FUNCTION _num216(p_name text, p_code text, p_start date, p_end date)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE t uuid; c uuid; inv uuid; num text;
BEGIN
  EXECUTE 'RESET ROLE';   -- le scénario précédent a pu laisser le rôle authenticated
  t := _mk_tenant(p_name, false);
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status)
  VALUES (t, p_code, p_start, p_end, 'open');
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client ' || p_name) RETURNING id INTO c;
  PERFORM _as_user();
  INSERT INTO invoices (tenant_id, customer_id, customer_name, date, due_date, status)
  VALUES (t, c, 'Client ' || p_name, p_start + 30, p_start + 60, 'draft') RETURNING id INTO inv;
  INSERT INTO invoice_lines (tenant_id, invoice_id, description, quantity, unit_price, vat_rate, line_order)
  VALUES (t, inv, 'Prestation', 1, 100, 20, 0);
  UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
  SELECT number INTO num FROM invoices WHERE id = inv;
  RETURN num;
END $$;

DO $$
DECLARE n text;
BEGIN
  BEGIN
    n := _num216('N01', 'FY2026', '2026-01-01', '2026-12-31');
    PERFORM _rec('N01', 'exercice « FY2026 » (celui de l''inscription) : la facture est FAC-2026-000001',
      n = 'FAC-2026-000001', 'numéro = ' || COALESCE(n, '∅'));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('N01', 'exercice « FY2026 » (celui de l''inscription) : la facture est FAC-2026-000001', false, SQLERRM); END;
END $$;

DO $$
DECLARE n text;
BEGIN
  BEGIN
    n := _num216('N02', 'EX2024', '2024-01-01', '2024-12-31');
    PERFORM _rec('N02', 'exercice « EX2024 » (société reprise) : la facture est FAC-2024-000001',
      n = 'FAC-2024-000001', 'numéro = ' || COALESCE(n, '∅'));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('N02', 'exercice « EX2024 » (société reprise) : la facture est FAC-2024-000001', false, SQLERRM); END;
END $$;

DO $$
DECLARE n text;
BEGIN
  BEGIN
    n := _num216('N03', 'Exercice courant', '2025-01-01', '2025-12-31');
    PERFORM _rec('N03', 'code sans chiffre : le numéro prend l''année de début (FAC-2025-000001)',
      n = 'FAC-2025-000001', 'numéro = ' || COALESCE(n, '∅'));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('N03', 'code sans chiffre : le numéro prend l''année de début (FAC-2025-000001)', false, SQLERRM); END;
END $$;

DO $$
DECLARE a text; b text;
BEGIN
  BEGIN
    a := _num216('N04A', '2026', '2026-01-01', '2026-12-31');
    b := _num216('N04B', 'FY2026', '2026-01-01', '2026-12-31');
    PERFORM _rec('N04', 'deux sociétés, deux codes d''exercice : même format et compteur propre à chacune',
      a = 'FAC-2026-000001' AND b = 'FAC-2026-000001',
      format('société A = %s ; société B = %s', COALESCE(a, '∅'), COALESCE(b, '∅')));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('N04', 'deux sociétés, deux codes d''exercice : même format et compteur propre à chacune', false, SQLERRM); END;
END $$;

DROP FUNCTION _num216(text, text, date, date);

SELECT _audit_assert('216');
