-- ============================================================
-- 217_posting_number_year_tests.sql — le numéro d'ÉCRITURE porte l'année
--
-- Défaut mesuré sur la copie de production du 23/09 : le numéro d'écriture
-- reprenait le code libre de l'exercice — AN-EX2024-000001, BQ-EX2024-000001,
-- OD-EX2024-000001, VT-EX2024-000001 à côté de VT-2026-000342 —, et cette
-- colonne est exportée au FEC comme numéro de pièce. La 216 avait corrigé le
-- numéro des pièces (FAC, ACH, AV, AVF), pas celui des écritures.
--
-- P01 — exercice « FY2026 » (celui que l'inscription crée) → OD-2026-000001
-- P02 — exercice « EX2024 » (société reprise)                → OD-2024-000001
-- P03 — code sans chiffre                                    → année de début
-- P04 — pièce et écriture du même exercice portent la MÊME année (cohérence)
-- P05 — un compteur par journal : OD-2026-000001, OD-2026-000002,
--       VT-2026-000001 — ni partage, ni trou
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '217', false);
DELETE FROM _audit_results WHERE file = '217';

-- Société dont l'exercice porte le code choisi, et numéro d'écriture obtenu
-- en validant une écriture OD équilibrée par les chemins réels (noyau de 187).
CREATE OR REPLACE FUNCTION _num217(p_name text, p_code text, p_start date, p_end date)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE t uuid; e uuid; n text;
BEGIN
  EXECUTE 'RESET ROLE';   -- le scénario précédent a pu laisser le rôle authenticated
  t := _mk_tenant(p_name, false);
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status)
  VALUES (t, p_code, p_start, p_end, 'open');
  PERFORM _as_user();
  e := _entry(t, 'OD-' || p_name, p_start + 30,
              '[{"a":"512000","d":100},{"a":"707000","c":100}]'::jsonb);
  SELECT posting_number INTO n FROM journal_entries WHERE id = e;
  RETURN n;
END $$;

DO $$
DECLARE n text;
BEGIN
  BEGIN
    n := _num217('P01', 'FY2026', '2026-01-01', '2026-12-31');
    PERFORM _rec('P01', 'exercice « FY2026 » (celui de l''inscription) : l''écriture est OD-2026-000001',
      n = 'OD-2026-000001', 'numéro = ' || COALESCE(n, '∅'));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('P01', 'exercice « FY2026 » (celui de l''inscription) : l''écriture est OD-2026-000001', false, SQLERRM); END;
END $$;

DO $$
DECLARE n text;
BEGIN
  BEGIN
    n := _num217('P02', 'EX2024', '2024-01-01', '2024-12-31');
    PERFORM _rec('P02', 'exercice « EX2024 » (société reprise) : l''écriture est OD-2024-000001',
      n = 'OD-2024-000001', 'numéro = ' || COALESCE(n, '∅'));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('P02', 'exercice « EX2024 » (société reprise) : l''écriture est OD-2024-000001', false, SQLERRM); END;
END $$;

DO $$
DECLARE n text;
BEGIN
  BEGIN
    n := _num217('P03', 'Exercice courant', '2025-01-01', '2025-12-31');
    PERFORM _rec('P03', 'code sans chiffre : le numéro prend l''année de début (OD-2025-000001)',
      n = 'OD-2025-000001', 'numéro = ' || COALESCE(n, '∅'));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('P03', 'code sans chiffre : le numéro prend l''année de début (OD-2025-000001)', false, SQLERRM); END;
END $$;

-- P04 : les deux numérotations (216 pour la pièce, 217 pour l'écriture) ne
-- peuvent plus diverger — c'est le sens de la correction.
DO $$
DECLARE t uuid; c uuid; inv uuid; e uuid; num_piece text; num_ecriture text;
BEGIN
  BEGIN
    EXECUTE 'RESET ROLE';
    t := _mk_tenant('P04', false);
    INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status)
    VALUES (t, 'FY2026', '2026-01-01', '2026-12-31', 'open');
    INSERT INTO customers (tenant_id, name) VALUES (t, 'Client P04') RETURNING id INTO c;
    PERFORM _as_user();
    INSERT INTO invoices (tenant_id, customer_id, customer_name, date, due_date, status)
    VALUES (t, c, 'Client P04', '2026-02-10', '2026-03-12', 'draft') RETURNING id INTO inv;
    INSERT INTO invoice_lines (tenant_id, invoice_id, description, quantity, unit_price, vat_rate, line_order)
    VALUES (t, inv, 'Prestation', 1, 100, 20, 0);
    UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
    SELECT number INTO num_piece FROM invoices WHERE id = inv;
    e := _entry(t, 'OD-P04', '2026-02-10', '[{"a":"512000","d":100},{"a":"707000","c":100}]'::jsonb);
    SELECT posting_number INTO num_ecriture FROM journal_entries WHERE id = e;
    PERFORM _rec('P04', 'pièce FAC-2026-000001 et écriture OD-2026-000001 : la même année',
      num_piece = 'FAC-2026-000001' AND num_ecriture = 'OD-2026-000001',
      format('pièce = %s ; écriture = %s', COALESCE(num_piece, '∅'), COALESCE(num_ecriture, '∅')));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('P04', 'pièce FAC-2026-000001 et écriture OD-2026-000001 : la même année', false, SQLERRM); END;
END $$;

-- P05 : un compteur par journal et par exercice, sans trou
DO $$
DECLARE t uuid; e1 uuid; e2 uuid; e3 uuid; n1 text; n2 text; n3 text;
BEGIN
  BEGIN
    EXECUTE 'RESET ROLE';
    t := _mk_tenant('P05', false);
    INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status)
    VALUES (t, 'FY2026', '2026-01-01', '2026-12-31', 'open');
    PERFORM _as_user();
    e1 := _entry(t, 'OD-P05-1', '2026-03-01', '[{"a":"512000","d":10},{"a":"707000","c":10}]'::jsonb);
    e2 := _entry(t, 'OD-P05-2', '2026-03-02', '[{"a":"512000","d":20},{"a":"707000","c":20}]'::jsonb);
    e3 := _entry(t, 'VT-P05-1', '2026-03-03', '[{"a":"512000","d":30},{"a":"707000","c":30}]'::jsonb,
                 true, 'VT');
    SELECT posting_number INTO n1 FROM journal_entries WHERE id = e1;
    SELECT posting_number INTO n2 FROM journal_entries WHERE id = e2;
    SELECT posting_number INTO n3 FROM journal_entries WHERE id = e3;
    PERFORM _rec('P05', 'un compteur par journal : OD-2026-000001, OD-2026-000002, VT-2026-000001',
      n1 = 'OD-2026-000001' AND n2 = 'OD-2026-000002' AND n3 = 'VT-2026-000001',
      format('OD = %s, %s ; VT = %s', COALESCE(n1, '∅'), COALESCE(n2, '∅'), COALESCE(n3, '∅')));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('P05', 'un compteur par journal : OD-2026-000001, OD-2026-000002, VT-2026-000001', false, SQLERRM); END;
END $$;

DROP FUNCTION _num217(text, text, date, date);

SELECT _audit_assert('217');