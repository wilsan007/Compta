-- ============================================================
-- 353_analytic_credit_note_grill_draft_tests.sql — tâche 2.13 (G1, les restes)
--
--   T01  avoir : la section posée sur la ligne d'avoir se retrouve sur la ligne
--        d'écriture de l'avoir
--   T02  grille à 100 % : une facture sans section prend la section de la grille
--        de son compte de produit
--   T03  grille 60 / 40 : la section dominante sur la ligne, et les DEUX parts
--        (600 et 400) dans `analytic_distribution_lines`
--   T04  grille invalide (90 %) : la facture se valide quand même, sans section —
--        une grille fausse ne bloque jamais une écriture
--   T05  la section de la ligne du document prime sur la grille
--   T06  un brouillon se modifie : lignes remplacées, totaux recalculés, section portée
--   T07  une facture validée ne se modifie pas par ce chemin
--   T08  le brouillon d'une autre société est introuvable
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '353', false);
DELETE FROM _audit_results WHERE file = '353';

DROP FUNCTION IF EXISTS _g353_section(uuid, text);
CREATE OR REPLACE FUNCTION _g353_section(p_t uuid, p_code text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid; pl uuid;
BEGIN
  SELECT id INTO pl FROM analytic_plans WHERE tenant_id = p_t LIMIT 1;
  IF pl IS NULL THEN
    INSERT INTO analytic_plans (tenant_id, code, name) VALUES (p_t, 'AX353', 'Plan 353') RETURNING id INTO pl;
  END IF;
  INSERT INTO analytic_sections (tenant_id, plan_id, code, name, axis, level)
    VALUES (p_t, pl, p_code, 'Section ' || p_code, 1, 1) RETURNING id INTO v;
  RETURN v;
END $$;

-- Une grille active sur 707000 : (section, pourcentage) × n
DROP FUNCTION IF EXISTS _g353_grille(uuid, text[], numeric[]);
CREATE OR REPLACE FUNCTION _g353_grille(p_t uuid, p_codes text[], p_pcts numeric[])
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE g uuid; i int;
BEGIN
  INSERT INTO distribution_grills (tenant_id, name, account_code, active)
    VALUES (p_t, 'Grille 353', '707000', true) RETURNING id INTO g;
  FOR i IN 1 .. array_length(p_codes, 1) LOOP
    INSERT INTO distribution_grill_lines (tenant_id, grill_id, section_code, percentage)
      VALUES (p_t, g, p_codes[i], p_pcts[i]);
  END LOOP;
  RETURN g;
END $$;

-- Une facture de 1 000 HT sur 707000, validée ; rend l'identifiant de sa ligne d'écriture de produit
DROP FUNCTION IF EXISTS _g353_vente(uuid, uuid, uuid);
CREATE OR REPLACE FUNCTION _g353_vente(p_t uuid, p_c uuid, p_section uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE inv uuid; l uuid;
BEGIN
  INSERT INTO invoices (tenant_id, number, customer_id, customer_name, date, due_date,
                        status, subtotal, vat_total, total, amount_paid, amount_due)
  VALUES (p_t, 'X', p_c, 'Client', CURRENT_DATE, CURRENT_DATE + 30, 'draft', 0, 0, 0, 0, 0)
  RETURNING id INTO inv;
  INSERT INTO invoice_lines (tenant_id, invoice_id, description, quantity, unit_price,
                             vat_rate, vat_code, analytic_section_id, line_order)
  VALUES (p_t, inv, 'Prestation', 1, 1000, 20, 'FR20', p_section, 1);
  UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
  SELECT jl.id INTO l FROM invoices i
    JOIN journal_lines jl ON jl.journal_id = i.transferred_entry_id AND jl.tenant_id = i.tenant_id
   WHERE i.id = inv AND jl.account_code = '707000';
  RETURN l;
END $$;

-- T01 — avoir
DO $$
DECLARE t uuid := _mk_tenant('P2G1T01'); c uuid; s uuid; cn uuid; n int := 0;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client 353') RETURNING id INTO c;
  s := _g353_section(t, 'AV01');
  PERFORM _as_user();
  INSERT INTO credit_notes (tenant_id, customer_id, date, subtotal, vat_total, total)
    VALUES (t, c, CURRENT_DATE, 0, 0, 0) RETURNING id INTO cn;
  EXECUTE 'INSERT INTO credit_note_lines (tenant_id, credit_note_id, description, quantity, unit_price, vat_rate, account_code, analytic_section_id)
           VALUES ($1, $2, ''Geste commercial'', 1, 400, 0, ''707000'', $3)' USING t, cn, s;
  UPDATE credit_notes SET status = 'validated' WHERE id = cn;
  EXECUTE 'RESET ROLE';
  SELECT count(*) INTO n FROM credit_notes k
    JOIN journal_lines jl ON jl.journal_id = k.transferred_entry_id AND jl.tenant_id = k.tenant_id
   WHERE k.id = cn AND jl.account_code ~ '^7' AND jl.analytic_section_id = s;
  PERFORM _rec('T01', 'la section de la ligne d''avoir se retrouve sur la ligne d''écriture de l''avoir',
    n = 1, format('lignes de produit portant la section=%s (1 attendue)', n));
EXCEPTION WHEN OTHERS THEN
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T01', 'la section de la ligne d''avoir se retrouve sur la ligne d''écriture de l''avoir', false, SQLERRM);
END $$;

-- T02 — grille à 100 %
DO $$
DECLARE t uuid := _mk_tenant('P2G1T02'); c uuid; s uuid; l uuid; v_sec uuid; v_amt numeric;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client 353') RETURNING id INTO c;
  s := _g353_section(t, 'GR100');
  PERFORM _g353_grille(t, ARRAY['GR100'], ARRAY[100]);
  PERFORM _as_user();
  l := _g353_vente(t, c, NULL);
  EXECUTE 'RESET ROLE';
  SELECT analytic_section_id, analytic_amount INTO v_sec, v_amt FROM journal_lines WHERE id = l;
  PERFORM _rec('T02', 'grille à 100 % : la ligne d''écriture prend la section de la grille de son compte',
    v_sec = s AND v_amt = 1000, format('section=%s (attendue %s), montant analytique=%s (1000 attendu)', v_sec, s, v_amt));
EXCEPTION WHEN OTHERS THEN
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T02', 'grille à 100 % : la ligne d''écriture prend la section de la grille de son compte', false, SQLERRM);
END $$;

-- T03 — grille 60 / 40
DO $$
DECLARE t uuid := _mk_tenant('P2G1T03'); c uuid; s60 uuid; s40 uuid; l uuid; v_sec uuid; v_amt numeric; v_parts text;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client 353') RETURNING id INTO c;
  s60 := _g353_section(t, 'GR60');
  s40 := _g353_section(t, 'GR40');
  PERFORM _g353_grille(t, ARRAY['GR60', 'GR40'], ARRAY[60, 40]);
  PERFORM _as_user();
  l := _g353_vente(t, c, NULL);
  EXECUTE 'RESET ROLE';
  SELECT analytic_section_id, analytic_amount INTO v_sec, v_amt FROM journal_lines WHERE id = l;
  SELECT string_agg(s.code || '=' || d.amount::numeric(12,2), ', ' ORDER BY s.code) INTO v_parts
    FROM analytic_distribution_lines d JOIN analytic_sections s ON s.id = d.section_id AND s.tenant_id = d.tenant_id
   WHERE d.journal_line_id = l;
  PERFORM _rec('T03', 'grille 60 / 40 : section dominante sur la ligne, et les deux parts ventilées',
    v_sec = s60 AND v_amt = 600 AND v_parts = 'GR40=400.00, GR60=600.00',
    format('dominante=%s montant=%s parts=[%s]', (v_sec = s60), v_amt, v_parts));
EXCEPTION WHEN OTHERS THEN
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T03', 'grille 60 / 40 : section dominante sur la ligne, et les deux parts ventilées', false, SQLERRM);
END $$;

-- T04 — grille invalide (90 %) : jamais bloquante
DO $$
DECLARE t uuid := _mk_tenant('P2G1T04'); c uuid; l uuid; v_sec uuid; n int;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client 353') RETURNING id INTO c;
  PERFORM _g353_section(t, 'KO60');
  PERFORM _g353_section(t, 'KO30');
  PERFORM _g353_grille(t, ARRAY['KO60', 'KO30'], ARRAY[60, 30]);
  PERFORM _as_user();
  l := _g353_vente(t, c, NULL);
  EXECUTE 'RESET ROLE';
  SELECT analytic_section_id INTO v_sec FROM journal_lines WHERE id = l;
  SELECT count(*) INTO n FROM analytic_distribution_lines WHERE journal_line_id = l;
  PERFORM _rec('T04', 'grille à 90 % : la facture se valide, la ligne reste sans section',
    l IS NOT NULL AND v_sec IS NULL AND n = 0, format('écriture=%s section=%s parts=%s', (l IS NOT NULL), v_sec, n));
EXCEPTION WHEN OTHERS THEN
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T04', 'grille à 90 % : la facture se valide, la ligne reste sans section', false, SQLERRM);
END $$;

-- T05 — le document prime sur la grille
DO $$
DECLARE t uuid := _mk_tenant('P2G1T05'); c uuid; s uuid; g uuid; l uuid; v_sec uuid; n int;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client 353') RETURNING id INTO c;
  s := _g353_section(t, 'DOC01');
  g := _g353_section(t, 'GRI01');
  PERFORM _g353_grille(t, ARRAY['GRI01'], ARRAY[100]);
  PERFORM _as_user();
  l := _g353_vente(t, c, s);
  EXECUTE 'RESET ROLE';
  SELECT analytic_section_id INTO v_sec FROM journal_lines WHERE id = l;
  SELECT count(*) INTO n FROM analytic_distribution_lines WHERE journal_line_id = l;
  PERFORM _rec('T05', 'la section choisie sur la ligne de facture prime sur la grille du compte',
    v_sec = s AND n = 0, format('section du document=%s parts de grille=%s', (v_sec = s), n));
EXCEPTION WHEN OTHERS THEN
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T05', 'la section choisie sur la ligne de facture prime sur la grille du compte', false, SQLERRM);
END $$;

-- T06, T07, T08 — modification d'un brouillon
DO $$
DECLARE
  t uuid := _mk_tenant('P2G1T06'); t2 uuid;
  c uuid; s uuid; inv uuid; r jsonb; n int; v_ht numeric; v_sec int; v_due date; v_num text;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client 353') RETURNING id INTO c;
  s := _g353_section(t, 'BR01');
  PERFORM _as_user();
  INSERT INTO invoices (tenant_id, number, customer_id, customer_name, date, due_date, status, subtotal, vat_total, total, amount_paid, amount_due)
    VALUES (t, 'X', c, 'Client', CURRENT_DATE, CURRENT_DATE + 30, 'draft', 0, 0, 0, 0, 0) RETURNING id INTO inv;
  INSERT INTO invoice_lines (tenant_id, invoice_id, description, quantity, unit_price, vat_rate, vat_code, line_order)
    VALUES (t, inv, 'Ancienne ligne', 1, 1000, 20, 'FR20', 0);
  SELECT number INTO v_num FROM invoices WHERE id = inv;

  BEGIN
    EXECUTE 'SELECT update_invoice_draft($1, $2, $3)' INTO r USING inv,
      jsonb_build_object('due_date', (CURRENT_DATE + 45)::text, 'notes', 'modifiée'),
      jsonb_build_array(
        jsonb_build_object('description', 'Ligne A', 'quantity', 3, 'unit_price', 100, 'vat_rate', 20, 'analytic_section_id', s),
        jsonb_build_object('description', 'Ligne B', 'quantity', 1, 'unit_price', 200, 'vat_rate', 20));
    SELECT count(*), count(analytic_section_id) INTO n, v_sec FROM invoice_lines WHERE invoice_id = inv;
    SELECT subtotal, due_date INTO v_ht, v_due FROM invoices WHERE id = inv;
    PERFORM _rec('T06', 'un brouillon se modifie : lignes remplacées, totaux recalculés, section portée',
      (r->>'success')::boolean AND n = 2 AND v_ht = 500 AND v_sec = 1 AND v_due = CURRENT_DATE + 45
        AND (SELECT number FROM invoices WHERE id = inv) = v_num,
      format('succès=%s lignes=%s HT=%s sections=%s échéance+45=%s', r->>'success', n, v_ht, v_sec, (v_due = CURRENT_DATE + 45)));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T06', 'un brouillon se modifie : lignes remplacées, totaux recalculés, section portée', false, SQLERRM);
  END;

  UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
  BEGIN
    EXECUTE 'SELECT update_invoice_draft($1, $2, $3)' INTO r USING inv, '{}'::jsonb,
      jsonb_build_array(jsonb_build_object('description', 'Pirate', 'quantity', 1, 'unit_price', 1, 'vat_rate', 20));
    SELECT count(*) INTO n FROM invoice_lines WHERE invoice_id = inv AND description = 'Pirate';
    PERFORM _rec('T07', 'une facture validée ne se modifie pas par ce chemin',
      NOT (r->>'success')::boolean AND n = 0, format('succès=%s lignes pirates=%s message=%s', r->>'success', n, r->>'error'));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T07', 'une facture validée ne se modifie pas par ce chemin', false, SQLERRM);
  END;

  -- une autre société ne voit pas ce brouillon
  EXECUTE 'RESET ROLE';
  INSERT INTO invoices (tenant_id, number, customer_id, customer_name, date, due_date, status, subtotal, vat_total, total, amount_paid, amount_due)
    VALUES (t, 'X', c, 'Client', CURRENT_DATE, CURRENT_DATE + 30, 'draft', 0, 0, 0, 0, 0) RETURNING id INTO inv;
  t2 := _mk_tenant('P2G1T08', false);   -- pose le contexte de l'AUTRE société
  PERFORM _as_user();
  BEGIN
    EXECUTE 'SELECT update_invoice_draft($1, $2, $3)' INTO r USING inv, '{}'::jsonb,
      jsonb_build_array(jsonb_build_object('description', 'Pirate', 'quantity', 1, 'unit_price', 1, 'vat_rate', 20));
    EXECUTE 'RESET ROLE';
    SELECT count(*) INTO n FROM invoice_lines WHERE invoice_id = inv;
    PERFORM _rec('T08', 'le brouillon d''une autre société est introuvable',
      NOT (r->>'success')::boolean AND n = 0, format('succès=%s lignes écrites=%s', r->>'success', n));
  EXCEPTION WHEN OTHERS THEN
    EXECUTE 'RESET ROLE';
    PERFORM _rec('T08', 'le brouillon d''une autre société est introuvable', false, SQLERRM);
  END;
EXCEPTION WHEN OTHERS THEN
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T06', 'T06 à T08 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

DROP FUNCTION IF EXISTS _g353_section(uuid, text);
DROP FUNCTION IF EXISTS _g353_grille(uuid, text[], numeric[]);
DROP FUNCTION IF EXISTS _g353_vente(uuid, uuid, uuid);

SELECT _audit_assert('353');
