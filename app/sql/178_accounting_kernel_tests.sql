-- ============================================================
-- 178_accounting_kernel_tests.sql — AUD-A01, lot C du plan correctif
--
-- Invariants du noyau de saisie comptable, exécutés sous le rôle
-- `authenticated`. Les défauts encore ouverts sont inscrits dans
-- ci/expected_failures.sql ; voir doc/audit/PLAN-CORRECTIF-AUDIT-2026-09-21.md.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '178', false);
DELETE FROM _audit_results WHERE file = '178';

-- A01 — une écriture déséquilibrée ne peut pas être validée
DO $$ DECLARE t uuid := _mk_tenant('A01'); BEGIN
  PERFORM _as_user();
  BEGIN
    PERFORM _entry(t, 'A01', DATE '2026-03-01', '[{"a":"512000","d":100},{"a":"706000","c":90}]');
    PERFORM _rec('A01', 'écriture 100/90 refusée', false, 'acceptée');
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('A01', 'écriture 100/90 refusée', true, SQLERRM); END;
END $$;

-- A02 — l'équilibre est strict, au centime
DO $$ DECLARE t uuid := _mk_tenant('A02'); BEGIN
  PERFORM _as_user();
  BEGIN
    PERFORM _entry(t, 'A02', DATE '2026-03-01', '[{"a":"512000","d":100.00},{"a":"706000","c":100.01}]');
    PERFORM _rec('A02', 'écart d''un centime refusé', false, 'acceptée : D 100,00 / C 100,01');
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('A02', 'écart d''un centime refusé', true, SQLERRM); END;
END $$;

-- A03 — pas de dérive cumulée de la balance
DO $$ DECLARE t uuid := _mk_tenant('A03'); n int := 0; BEGIN
  PERFORM _as_user();
  FOR i IN 1..50 LOOP
    BEGIN
      PERFORM _entry(t, 'A03-' || i, DATE '2026-03-01', '[{"a":"512000","d":10.00},{"a":"706000","c":10.01}]');
      n := n + 1;
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END LOOP;
  PERFORM _rec('A03', 'balance sans dérive après 50 écritures à 1 centime d''écart', n = 0,
    format('%s écriture(s) validée(s), balance D−C = %s', n,
      (SELECT COALESCE(sum(debit) - sum(credit), 0) FROM journal_lines WHERE tenant_id = t)));
END $$;

-- A04 — une écriture ne naît pas validée
DO $$ DECLARE t uuid := _mk_tenant('A04'); BEGIN
  PERFORM _as_user();
  BEGIN
    INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, total_debit, total_credit)
    VALUES (t, 'A04', DATE '2026-03-01', 'OD', 'posted', 'insertion directe', 5000, 5000);
    PERFORM _rec('A04', 'en-tête inséré directement en posted refusé', false, 'accepté : écriture validée sans ligne, total affiché 5000');
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('A04', 'en-tête inséré directement en posted refusé', true, SQLERRM); END;
END $$;

-- A05 — une ligne est au débit OU au crédit, jamais les deux ni aucun
DO $$ DECLARE t uuid := _mk_tenant('A05'); BEGIN
  PERFORM _as_user();
  BEGIN
    PERFORM _entry(t, 'A05', DATE '2026-03-01', '[{"a":"512000","d":100,"c":100},{"a":"706000","d":0,"c":0}]');
    PERFORM _rec('A05', 'ligne débit+crédit et ligne 0/0 refusées', false, 'acceptées');
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('A05', 'ligne débit+crédit et ligne 0/0 refusées', true, SQLERRM); END;
END $$;

-- A06 — seuls les comptes du plan sont imputables
DO $$ DECLARE t uuid := _mk_tenant('A06'); BEGIN
  PERFORM _as_user();
  BEGIN
    PERFORM _entry(t, 'A06', DATE '2026-03-01', '[{"a":"999999","d":100},{"a":"ZZTOP","c":100}]');
    PERFORM _rec('A06', 'compte absent du plan refusé', false, 'accepté : 999999 et ZZTOP');
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('A06', 'compte absent du plan refusé', true, SQLERRM); END;
END $$;

-- A07 — intangibilité d'une écriture validée
DO $$ DECLARE t uuid := _mk_tenant('A07'); e uuid; BEGIN
  PERFORM _as_user();
  e := _entry(t, 'A07', DATE '2026-03-01', '[{"a":"512000","d":100},{"a":"706000","c":100}]');
  BEGIN
    UPDATE journal_lines SET debit = 1 WHERE journal_id = e AND account_code = '512000';
    PERFORM _rec('A07a', 'montant d''une ligne validée non modifiable', false, 'modifié');
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('A07a', 'montant d''une ligne validée non modifiable', true, SQLERRM); END;
  BEGIN
    DELETE FROM journal_entries WHERE id = e;
    PERFORM _rec('A07b', 'écriture validée non supprimable', EXISTS (SELECT 1 FROM journal_entries WHERE id = e),
      'aucune erreur levée ; écriture ' || CASE WHEN EXISTS (SELECT 1 FROM journal_entries WHERE id = e) THEN 'toujours présente' ELSE 'supprimée' END);
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('A07b', 'écriture validée non supprimable', true, SQLERRM); END;
  BEGIN
    UPDATE journal_entries SET status = 'draft' WHERE id = e;
    PERFORM _rec('A07c', 'écriture validée non repassable en brouillard', false, 'repassée en brouillard');
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('A07c', 'écriture validée non repassable en brouillard', true, SQLERRM); END;
  BEGIN
    DELETE FROM journal_lines WHERE journal_id = e;
    PERFORM _rec('A07d', 'lignes d''une écriture validée non supprimables',
      EXISTS (SELECT 1 FROM journal_lines WHERE journal_id = e), 'aucune erreur levée');
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('A07d', 'lignes d''une écriture validée non supprimables', true, SQLERRM); END;
END $$;

-- A08 — seuls les comptes imputables du plan : ni déprécié, ni compte de regroupement
DO $$ DECLARE t uuid := _mk_tenant('A08'); parent uuid; ok_dep boolean := false; ok_par boolean := false; d1 text; d2 text; BEGIN
  UPDATE chart_accounts SET deprecated = true WHERE tenant_id = t AND code = '706000';
  SELECT id INTO parent FROM chart_accounts WHERE tenant_id = t AND code = '411000';
  INSERT INTO chart_accounts (tenant_id, code, name, type, parent_id) VALUES (t, '411990', 'Clients — sous-compte d''audit', 'asset', parent);
  PERFORM _as_user();
  BEGIN
    PERFORM _entry(t, 'A08a', DATE '2026-03-01', '[{"a":"512000","d":100},{"a":"706000","c":100}]');
    d1 := 'compte déprécié 706000 accepté';
  EXCEPTION WHEN OTHERS THEN ok_dep := true; d1 := SQLERRM; END;
  BEGIN
    PERFORM _entry(t, 'A08b', DATE '2026-03-01', '[{"a":"411000","d":100},{"a":"707000","c":100}]');
    d2 := 'compte de regroupement 411000 accepté';
  EXCEPTION WHEN OTHERS THEN ok_par := true; d2 := SQLERRM; END;
  PERFORM _rec('A08', 'compte déprécié et compte de regroupement refusés', ok_dep AND ok_par, d1 || ' | ' || d2);
END $$;

-- A09 — une facture exonérée se comptabilise sans ligne 0/0 (AUD-C03)
DO $$ DECLARE t uuid := _mk_tenant('A09'); c uuid; inv uuid; n0 int; n int; st text; BEGIN
  PERFORM _as_user();
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client export') RETURNING id INTO c;
  INSERT INTO invoices (tenant_id, number, customer_id, customer_name, date, due_date, status, subtotal, vat_total, total, amount_paid, amount_due)
  VALUES (t, 'F-EXO', c, 'Client export', '2026-03-01', '2026-03-31', 'draft', 1000, 0, 1000, 0, 1000) RETURNING id INTO inv;
  INSERT INTO invoice_lines (tenant_id, invoice_id, description, quantity, unit_price, vat_rate, total, vat_code, vat_amount)
  VALUES (t, inv, 'Export', 1, 1000, 0, 1000, 'EXO', 0);
  BEGIN
    UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
  EXCEPTION WHEN OTHERS THEN st := SQLERRM; END;
  SELECT count(*), count(*) FILTER (WHERE jl.debit = 0 AND jl.credit = 0) INTO n, n0
  FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id WHERE je.tenant_id = t;
  PERFORM _rec('A09', 'facture exonérée : écriture sans ligne 0/0', st IS NULL AND n = 2 AND n0 = 0,
    format('lignes=%s dont 0/0=%s erreur=%s', n, n0, COALESCE(st, 'aucune')));
END $$;

-- B01 — pas de saisie dans une période close
DO $$ DECLARE t uuid := _mk_tenant('B01'); fy uuid; BEGIN
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status) VALUES (t, '2025', '2025-01-01', '2025-12-31', 'open') RETURNING id INTO fy;
  INSERT INTO fiscal_periods (tenant_id, fiscal_year_id, period_number, period_label, start_date, end_date, status)
    VALUES (t, fy, 6, '2025-06', '2025-06-01', '2025-06-30', 'closed');
  PERFORM _as_user();
  BEGIN
    PERFORM _entry(t, 'B01', DATE '2025-06-15', '[{"a":"512000","d":100},{"a":"706000","c":100}]');
    PERFORM _rec('B01', 'saisie dans une période close refusée', false, 'acceptée');
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('B01', 'saisie dans une période close refusée', true, SQLERRM); END;
END $$;

-- B02 — pas de saisie dans un exercice clos, même sans découpage en périodes
DO $$ DECLARE t uuid := _mk_tenant('B02'); BEGIN
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status) VALUES (t, '2024', '2024-01-01', '2024-12-31', 'closed');
  PERFORM _as_user();
  BEGIN
    PERFORM _entry(t, 'B02', DATE '2024-06-15', '[{"a":"512000","d":100},{"a":"706000","c":100}]');
    PERFORM _rec('B02', 'saisie dans un exercice clos refusée', false, 'acceptée dans l''exercice 2024 clos');
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('B02', 'saisie dans un exercice clos refusée', true, SQLERRM); END;
END $$;

-- B03 — la date d'une écriture appartient à un exercice
DO $$ DECLARE t uuid := _mk_tenant('B03', false); BEGIN
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status) VALUES (t, '2026', '2026-01-01', '2026-12-31', 'open');
  PERFORM _as_user();
  BEGIN
    PERFORM _entry(t, 'B03', DATE '1990-06-15', '[{"a":"512000","d":100},{"a":"706000","c":100}]');
    PERFORM _rec('B03', 'écriture datée hors exercice refusée', false, 'acceptée en 1990');
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('B03', 'écriture datée hors exercice refusée', true, SQLERRM); END;
END $$;

-- B04 — la période close tient aussi sans contexte tenant.
-- Volontairement exécuté SANS _as_user() : reproduit un job service_role ou un
-- trigger SECURITY DEFINER, qui écrivent sans en-tête x-tenant-id.
DO $$ DECLARE t uuid := _mk_tenant('B04'); fy uuid; BEGIN
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status) VALUES (t, '2025', '2025-01-01', '2025-12-31', 'open') RETURNING id INTO fy;
  INSERT INTO fiscal_periods (tenant_id, fiscal_year_id, period_number, period_label, start_date, end_date, status)
    VALUES (t, fy, 6, '2025-06', '2025-06-01', '2025-06-30', 'closed');
  PERFORM set_config('app.active_tenant_id', '', false);
  BEGIN
    PERFORM _entry(t, 'B04', DATE '2025-06-15', '[{"a":"512000","d":100},{"a":"706000","c":100}]', false);
    PERFORM _rec('B04', 'période close respectée sans contexte tenant', false, 'brouillon accepté : le contrôle lit current_tenant_id() et non NEW.tenant_id');
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('B04', 'période close respectée sans contexte tenant', true, SQLERRM); END;
END $$;

-- C01 — un échec de la RPC ne consomme pas de numéro
DO $$ DECLARE t uuid := _mk_tenant('C01'); r1 jsonb; r2 jsonb; r3 jsonb; BEGIN
  PERFORM _as_user();
  r1 := post_journal_entry('{"date":"2026-03-01","journal_code":"OD","description":"c1"}',
        '[{"account_code":"512000","debit":10},{"account_code":"706000","credit":10}]');
  r2 := post_journal_entry('{"date":"2026-03-01","journal_code":"OD","description":"c2"}',
        '[{"account_code":"512000","debit":10,"line_date":"pas-une-date"},{"account_code":"706000","credit":10}]');
  r3 := post_journal_entry('{"date":"2026-03-01","journal_code":"OD","description":"c3"}',
        '[{"account_code":"512000","debit":10},{"account_code":"706000","credit":10}]');
  PERFORM _rec('C01', 'numérotation continue malgré un échec',
    (r1->>'success')::boolean AND NOT COALESCE((r2->>'success')::boolean, false) AND (r3->>'success')::boolean
      AND (r3->>'number') = 'OD-0002',
    format('n1=%s | n2 : %s | n3=%s', r1->>'number', COALESCE(r2->>'error', 'ok'), r3->>'number'));
END $$;

-- C02 — un numéro d'écriture est unique, même sans code journal
DO $$ DECLARE t uuid := _mk_tenant('C02'); BEGIN
  PERFORM _as_user();
  BEGIN
    INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description) VALUES (t, 'DUP', DATE '2026-03-01', NULL, 'draft', 'x');
    INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description) VALUES (t, 'DUP', DATE '2026-03-01', NULL, 'draft', 'y');
    PERFORM _rec('C02', 'numéro en double refusé (journal_code NULL)', false, 'accepté : UNIQUE ignore journal_code NULL');
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('C02', 'numéro en double refusé (journal_code NULL)', true, SQLERRM); END;
END $$;

-- C03 — post_journal_entry sait créer une écriture directement validée
DO $$ DECLARE t uuid := _mk_tenant('C03'); r jsonb; st text; BEGIN
  PERFORM _as_user();
  r := post_journal_entry('{"date":"2026-03-01","journal_code":"OD","description":"validée d''emblée","status":"posted"}',
        '[{"account_code":"512000","debit":10},{"account_code":"706000","credit":10}]');
  SELECT status INTO st FROM journal_entries WHERE id = (r->>'entry_id')::uuid;
  PERFORM _rec('C03', 'post_journal_entry avec status=posted', COALESCE((r->>'success')::boolean, false) AND st = 'posted', r::text);
END $$;

-- C04 — une demande de validation déséquilibrée est refusée par la RPC
DO $$ DECLARE t uuid := _mk_tenant('C04'); r jsonb; BEGIN
  PERFORM _as_user();
  r := post_journal_entry('{"date":"2026-03-01","journal_code":"OD","description":"déséquilibrée","status":"posted"}',
        '[{"account_code":"512000","debit":10},{"account_code":"706000","credit":9}]');
  PERFORM _rec('C04', 'post_journal_entry refuse une validation déséquilibrée',
    NOT COALESCE((r->>'success')::boolean, true)
      AND NOT EXISTS (SELECT 1 FROM journal_entries WHERE tenant_id = t AND status = 'posted'),
    r::text);
END $$;

-- C05 — l'écriture est rattachée à sa période (AUD-C08)
DO $$ DECLARE t uuid := _mk_tenant('C05', false); fy uuid; p uuid; r jsonb; got uuid; BEGIN
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status) VALUES (t, '2026', '2026-01-01', '2026-12-31', 'open') RETURNING id INTO fy;
  INSERT INTO fiscal_periods (tenant_id, fiscal_year_id, period_number, period_label, start_date, end_date, status)
    VALUES (t, fy, 2, '2026-02', '2026-02-01', '2026-02-28', 'open');
  INSERT INTO fiscal_periods (tenant_id, fiscal_year_id, period_number, period_label, start_date, end_date, status)
    VALUES (t, fy, 3, '2026-03', '2026-03-01', '2026-03-31', 'open') RETURNING id INTO p;
  PERFORM _as_user();
  r := post_journal_entry('{"date":"2026-03-15","journal_code":"OD","description":"c5","status":"posted"}',
        '[{"account_code":"512000","debit":10},{"account_code":"706000","credit":10}]');
  SELECT fiscal_period_id INTO got FROM journal_entries WHERE id = (r->>'entry_id')::uuid;
  PERFORM _rec('C05', 'écriture rattachée à sa période (mars)', got IS NOT DISTINCT FROM p AND got IS NOT NULL,
    format('période=%s attendue=%s retour=%s', COALESCE(got::text, '∅'), p, r));
END $$;

-- C06 — numéro définitif attribué à la validation, continu par journal et par exercice (AUD-C11)
DO $$ DECLARE t uuid := _mk_tenant('C06', false); e1 uuid; e2 uuid; e3 uuid; e4 uuid; got text; BEGIN
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status) VALUES (t, '2025', '2025-01-01', '2025-12-31', 'open');
  INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status) VALUES (t, '2026', '2026-01-01', '2026-12-31', 'open');
  PERFORM _as_user();
  BEGIN
    e1 := _entry(t, 'N1', DATE '2025-03-01', '[{"a":"512000","d":10},{"a":"706000","c":10}]', false);
    e2 := _entry(t, 'N2', DATE '2025-03-02', '[{"a":"512000","d":10},{"a":"706000","c":9}]', false);
    e3 := _entry(t, 'N3', DATE '2025-03-03', '[{"a":"512000","d":10},{"a":"706000","c":10}]', false);
    e4 := _entry(t, 'N4', DATE '2026-01-05', '[{"a":"512000","d":10},{"a":"706000","c":10}]', false);
    UPDATE journal_entries SET status = 'posted' WHERE id = e1;
    BEGIN UPDATE journal_entries SET status = 'posted' WHERE id = e2; EXCEPTION WHEN OTHERS THEN NULL; END;
    UPDATE journal_entries SET status = 'posted' WHERE id = e3;
    UPDATE journal_entries SET status = 'posted' WHERE id = e4;
    EXECUTE format($q$SELECT string_agg(number || '=' || COALESCE(posting_number, '∅'), ' ' ORDER BY number)
                       FROM journal_entries WHERE tenant_id = %L$q$, t) INTO got;
    PERFORM _rec('C06', 'numéros définitifs 1, 2 sans trou malgré un échec ; remise à 1 sur le nouvel exercice',
      got = 'N1=OD-2025-000001 N2=∅ N3=OD-2025-000002 N4=OD-2026-000001', got);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('C06', 'numéros définitifs 1, 2 sans trou malgré un échec ; remise à 1 sur le nouvel exercice', false, SQLERRM);
  END;
END $$;

-- F01 — isolation : le tenant B ne lit rien du tenant A
DO $$ DECLARE ta uuid := _mk_tenant('F-A'); tb uuid; n int; BEGIN
  PERFORM _entry(ta, 'SECRET-A', DATE '2026-03-01', '[{"a":"512000","d":777},{"a":"706000","c":777}]');
  tb := _mk_tenant('F-B');
  PERFORM _as_user();
  SELECT count(*) INTO n FROM journal_lines WHERE tenant_id = ta;
  PERFORM _rec('F01', 'le tenant B ne lit aucune ligne du tenant A', n = 0, n || ' ligne(s) visible(s)');
END $$;

SELECT _audit_assert('178');
