-- ============================================================
-- 218_document_number_seed_tests.sql — D-12 : la suite reprend après l'existant
--
-- Le cas mesuré sur la copie de production du 23/09 : une société reprise a des
-- factures FAC-2024-001 à 005 et AUCUNE ligne de séquence — le premier document
-- validé recevait donc le numéro 1, déjà porté par une facture du même exercice.
--
-- D01 — société reprise (5 factures 2024, aucune séquence) → FAC-2024-000006
-- D02 — société neuve, aucun document                      → FAC-2026-000001
-- D03 — la reprise de 2024 ne contamine pas 2026           → FAC-2026-000001
-- D04 — compteur resté en retard : réparé                  → FAC-2024-000008
-- D05 — compteur en avance : jamais rabaissé               → FAC-2026-000050
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '218', false);
DELETE FROM _audit_results WHERE file = '218';

-- Société « reprise » : documents au format historique, restaurés comme un dump
-- (triggers neutralisés le temps de la restauration), aucune ligne de séquence.
CREATE OR REPLACE FUNCTION _reprise218(p_name text, p_code text, p_start date, p_end date, p_docs text[])
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE t uuid; c uuid; n text;
BEGIN
  EXECUTE 'RESET ROLE';
  t := _mk_tenant(p_name, false);
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status)
  VALUES (t, p_code, p_start, p_end, 'open');
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client ' || p_name) RETURNING id INTO c;
  PERFORM set_config('session_replication_role', 'replica', true);
  FOREACH n IN ARRAY p_docs LOOP
    INSERT INTO invoices (tenant_id, customer_id, customer_name, number, date, due_date,
                          status, validation_status, subtotal, total, amount_due)
    VALUES (t, c, 'Client ' || p_name, n, p_start + 20, p_start + 50, 'sent', 'validated', 100, 120, 0);
  END LOOP;
  PERFORM set_config('session_replication_role', 'origin', true);
  RETURN t;
END $$;

-- Valide une facture d'une ligne par les chemins réels et rend son numéro
CREATE OR REPLACE FUNCTION _valide218(p_t uuid, p_date date, p_journal text DEFAULT 'VT')
RETURNS text LANGUAGE plpgsql AS $$
DECLARE c uuid; inv uuid; n text;
BEGIN
  PERFORM _as_user();
  SELECT id INTO c FROM customers WHERE tenant_id = p_t LIMIT 1;
  INSERT INTO invoices (tenant_id, customer_id, customer_name, date, due_date, status)
  VALUES (p_t, c, 'Client', p_date, p_date + 30, 'draft') RETURNING id INTO inv;
  INSERT INTO invoice_lines (tenant_id, invoice_id, description, quantity, unit_price, vat_rate, line_order)
  VALUES (p_t, inv, 'Prestation', 1, 100, 20, 0);
  UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
  SELECT number INTO n FROM invoices WHERE id = inv;
  RETURN n;
END $$;

DO $$
DECLARE t uuid; n text;
BEGIN
  BEGIN
    t := _reprise218('D01', 'EX2024', '2024-01-01', '2024-12-31',
                     ARRAY['FAC-2024-001','FAC-2024-002','FAC-2024-003','FAC-2024-004','FAC-2024-005']);
    n := _valide218(t, '2024-03-01');
    PERFORM _rec('D01', 'société reprise (FAC-2024-001 à 005, aucune séquence) : la facture est FAC-2024-000006',
      n = 'FAC-2024-000006', 'numéro = ' || COALESCE(n, '∅'));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('D01', 'société reprise (FAC-2024-001 à 005, aucune séquence) : la facture est FAC-2024-000006', false, SQLERRM); END;
END $$;

DO $$
DECLARE t uuid; n text;
BEGIN
  BEGIN
    EXECUTE 'RESET ROLE';
    t := _mk_tenant('D02', false);
    INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status)
    VALUES (t, 'FY2026', '2026-01-01', '2026-12-31', 'open');
    INSERT INTO customers (tenant_id, name) VALUES (t, 'Client D02');
    n := _valide218(t, '2026-03-01');
    PERFORM _rec('D02', 'société neuve sans document : la première facture est FAC-2026-000001',
      n = 'FAC-2026-000001', 'numéro = ' || COALESCE(n, '∅'));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('D02', 'société neuve sans document : la première facture est FAC-2026-000001', false, SQLERRM); END;
END $$;

DO $$
DECLARE t uuid; n text;
BEGIN
  BEGIN
    t := _reprise218('D03', 'EX2024', '2024-01-01', '2024-12-31', ARRAY['FAC-2024-001','FAC-2024-002']);
    EXECUTE 'RESET ROLE';
    INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status)
    VALUES (t, '2026', '2026-01-01', '2026-12-31', 'open');
    n := _valide218(t, '2026-03-01');
    PERFORM _rec('D03', 'un autre exercice ne reprend pas la numérotation d''un exercice antérieur : FAC-2026-000001',
      n = 'FAC-2026-000001', 'numéro = ' || COALESCE(n, '∅'));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('D03', 'un autre exercice ne reprend pas la numérotation d''un exercice antérieur : FAC-2026-000001', false, SQLERRM); END;
END $$;
-- D04 : un compteur resté en retard est remonté par la réparation
DO $$
DECLARE t uuid; n text; fy uuid; v_n integer; avant integer;
BEGIN
  BEGIN
    t := _reprise218('D04', 'EX2024', '2024-01-01', '2024-12-31',
                     ARRAY['FAC-2024-001','FAC-2024-002','FAC-2024-003','FAC-2024-004',
                           'FAC-2024-005','FAC-2024-006','FAC-2024-007']);
    SELECT id INTO fy FROM fiscal_years WHERE tenant_id = t AND code = 'EX2024';
    -- compteur en retard : il annonce 2 alors que 7 documents existent
    INSERT INTO document_number_sequences (tenant_id, prefix, fiscal_year_id, next_number)
    VALUES (t, 'FAC', fy, 2);
    SELECT next_number INTO avant FROM document_number_sequences
    WHERE tenant_id = t AND prefix = 'FAC' AND fiscal_year_id = fy;
    v_n := repair_document_number_sequences();
    n := _valide218(t, '2024-03-01');
    PERFORM _rec('D04', 'compteur en retard (2) sur 7 documents : réparé, la facture est FAC-2024-000008',
      n = 'FAC-2024-000008' AND v_n >= 1,
      format('avant=%s, réparés=%s, numéro=%s', avant, v_n, COALESCE(n, '∅')));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('D04', 'compteur en retard (2) sur 7 documents : réparé, la facture est FAC-2024-000008', false, SQLERRM); END;
END $$;

-- D05 : un compteur en avance n'est jamais rabaissé (un numéro attribué à une
-- pièce supprimée reste consommé)
DO $$
DECLARE t uuid; n text; fy uuid; v_n integer; apres integer;
BEGIN
  BEGIN
    t := _reprise218('D05', 'EX2026', '2026-01-01', '2026-12-31', ARRAY['FAC-2026-001','FAC-2026-002','FAC-2026-003']);
    SELECT id INTO fy FROM fiscal_years WHERE tenant_id = t AND code = 'EX2026';
    INSERT INTO document_number_sequences (tenant_id, prefix, fiscal_year_id, next_number)
    VALUES (t, 'FAC', fy, 50);
    v_n := repair_document_number_sequences();
    SELECT next_number INTO apres FROM document_number_sequences
    WHERE tenant_id = t AND prefix = 'FAC' AND fiscal_year_id = fy;
    n := _valide218(t, '2026-03-01');
    PERFORM _rec('D05', 'compteur en avance (50) : jamais rabaissé, la facture est FAC-2026-000050',
      apres = 50 AND n = 'FAC-2026-000050',
      format('compteur après réparation=%s, numéro=%s', apres, COALESCE(n, '∅')));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('D05', 'compteur en avance (50) : jamais rabaissé, la facture est FAC-2026-000050', false, SQLERRM); END;
END $$;

DROP FUNCTION _reprise218(text, text, date, date, text[]);
DROP FUNCTION _valide218(uuid, date, text);

SELECT _audit_assert('218');