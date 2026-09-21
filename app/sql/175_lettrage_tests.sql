-- ============================================================
-- 175_lettrage_tests.sql
--
-- B10 — le lettrage, rejoué en scénario complet sur la vraie base.
--
-- Avant `174_fix_lettrage_on_posted_lines.sql`, le TEST 1 échoue : le lettrage
-- était impossible sur une écriture validée, donc dans le seul cas réel. Le
-- TEST 4 échoue aussi : on pouvait lettrer la facture d'un client contre le
-- règlement d'un autre.
-- ============================================================

\ir ci/ledger_fixture.sql

DO $$
DECLARE
  v_tenant_id uuid := uuid_generate_v4();
  v_auth_id   uuid := uuid_generate_v4();
  v_fact      uuid;
  v_regl      uuid;
  v_autre     uuid;
  l_client_d  uuid;   -- 411001 au débit  (facture)
  l_client_c  uuid;   -- 411001 au crédit (règlement)
  l_autre_c   uuid;   -- 411002 au crédit (autre client)
  v_res       jsonb;
  v_code      text;
  v_n         int;
  v_solde     numeric;
BEGIN
  -- ---------- contexte tenant ----------
  INSERT INTO auth.users (id, email) VALUES (v_auth_id, 'test@lettrage.com') ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claim.sub', v_auth_id::text, false);
  INSERT INTO tenants (id, name, plan, status, currency, created_at)
  VALUES (v_tenant_id, 'Test Lettrage', 'trial', 'active', 'EUR', NOW());
  INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status, created_at)
  VALUES (v_tenant_id, v_auth_id, 'test@lettrage.com', 'Test Admin', 'admin', 'active', NOW());
  INSERT INTO company_settings (tenant_id, name, currency, country, fiscal_year_start, created_at)
  VALUES (v_tenant_id, 'Test Company', 'EUR', 'France', '2026-01-01', NOW()) ON CONFLICT DO NOTHING;
  PERFORM _ledger_fixture(v_tenant_id, '{411001,411002}');  -- plan (+ comptes clients du scénario), journaux, exercice (187)
  PERFORM set_config('app.active_tenant_id', v_tenant_id::text, true);

  IF current_tenant_id() IS DISTINCT FROM v_tenant_id THEN
    RAISE EXCEPTION 'Contexte tenant non établi — le test ne prouverait rien';
  END IF;

  -- ---------- facture : D 411001 1200 / C 707000 1000 / C 445710 200 ----------
  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description)
  VALUES (v_tenant_id, 'JE-LET-VT', CURRENT_DATE, 'VT', 'draft', 'Facture client A')
  RETURNING id INTO v_fact;
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description)
  VALUES (v_tenant_id, v_fact, '411001', '411001', 1200, 0, 'Client A - facture') RETURNING id INTO l_client_d;
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description)
  VALUES (v_tenant_id, v_fact, '707000', '707000', 0, 1000, 'Vente'),
         (v_tenant_id, v_fact, '445710', '445710', 0, 200, 'TVA collectée');
  UPDATE journal_entries SET status = 'posted' WHERE id = v_fact;

  -- ---------- règlement : D 512000 1200 / C 411001 1200 ----------
  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description)
  VALUES (v_tenant_id, 'JE-LET-BQ', CURRENT_DATE, 'BQ', 'draft', 'Règlement client A')
  RETURNING id INTO v_regl;
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description)
  VALUES (v_tenant_id, v_regl, '512000', '512000', 1200, 0, 'Banque');
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description)
  VALUES (v_tenant_id, v_regl, '411001', '411001', 0, 1200, 'Client A - règlement') RETURNING id INTO l_client_c;
  UPDATE journal_entries SET status = 'posted' WHERE id = v_regl;

  -- ============================================================
  -- TEST 1 : lettrer une facture validée contre un règlement validé
  -- ============================================================
  v_res := apply_lettrage(ARRAY[l_client_d, l_client_c], NULL);
  v_code := v_res->>'code';

  IF v_code IS NULL OR v_code !~ '^[A-Z]{1,2}[0-9]{2,3}$' THEN
    RAISE EXCEPTION 'TEST 1 : code de lettrage inattendu : %', COALESCE(v_code, '(nul)');
  END IF;

  SELECT count(*) INTO v_n FROM journal_lines
  WHERE tenant_id = v_tenant_id AND lettrage_code = v_code;
  IF v_n <> 2 THEN
    RAISE EXCEPTION 'TEST 1 : % ligne(s) lettrée(s) au lieu de 2', v_n;
  END IF;

  SELECT COALESCE(SUM(debit - credit), 0) INTO v_solde FROM journal_lines
  WHERE tenant_id = v_tenant_id AND lettrage_code = v_code;
  IF v_solde <> 0 THEN
    RAISE EXCEPTION 'TEST 1 : le lot lettré ne solde pas (%)', v_solde;
  END IF;
  RAISE NOTICE '✅ TEST 1 : facture validée lettrée contre règlement validé, code %, solde nul', v_code;

  -- ============================================================
  -- TEST 2 : les valeurs comptables restent gelées
  -- ============================================================
  BEGIN
    UPDATE journal_lines SET debit = 9999 WHERE id = l_client_d;
    RAISE EXCEPTION 'TEST 2 : le montant d''une ligne validée a pu être modifié';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%immuable%' THEN RAISE; END IF;
  END;

  BEGIN
    DELETE FROM journal_lines WHERE id = l_client_d;
    RAISE EXCEPTION 'TEST 2 : une ligne validée a pu être supprimée';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%immuable%' THEN RAISE; END IF;
  END;
  RAISE NOTICE '✅ TEST 2 : montant et suppression toujours interdits sur une écriture validée';

  -- ============================================================
  -- TEST 3 : délettrage
  -- ============================================================
  PERFORM remove_lettrage(ARRAY[l_client_d, l_client_c]);
  SELECT count(*) INTO v_n FROM journal_lines
  WHERE tenant_id = v_tenant_id AND lettrage_code IS NOT NULL;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'TEST 3 : % ligne(s) encore lettrée(s) après délettrage', v_n;
  END IF;
  RAISE NOTICE '✅ TEST 3 : délettrage d''une écriture validée';

  -- ============================================================
  -- TEST 4 : refus de lettrer deux tiers différents
  -- ============================================================
  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description)
  VALUES (v_tenant_id, 'JE-LET-BQ2', CURRENT_DATE, 'BQ', 'draft', 'Règlement client B')
  RETURNING id INTO v_autre;
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description)
  VALUES (v_tenant_id, v_autre, '512000', '512000', 1200, 0, 'Banque');
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description)
  VALUES (v_tenant_id, v_autre, '411002', '411002', 0, 1200, 'Client B - règlement') RETURNING id INTO l_autre_c;
  UPDATE journal_entries SET status = 'posted' WHERE id = v_autre;

  BEGIN
    PERFORM apply_lettrage(ARRAY[l_client_d, l_autre_c], NULL);
    RAISE EXCEPTION 'TEST 4 : la facture du client A a pu être lettrée contre le règlement du client B';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%comptes de tiers différents%' THEN RAISE; END IF;
  END;
  RAISE NOTICE '✅ TEST 4 : lettrage refusé entre deux comptes de tiers distincts (411001 / 411002)';

  -- ============================================================
  -- TEST 5 : refus d'un lettrage déséquilibré
  -- ============================================================
  BEGIN
    PERFORM apply_lettrage(ARRAY[l_client_d], NULL);
    RAISE EXCEPTION 'TEST 5 : un lettrage déséquilibré a été accepté';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%déséquilibré%' THEN RAISE; END IF;
  END;
  RAISE NOTICE '✅ TEST 5 : lettrage déséquilibré refusé';

  -- ============================================================
  -- Nettoyage
  -- ============================================================
  SET session_replication_role = 'replica';
  DELETE FROM journal_lines WHERE tenant_id = v_tenant_id;
  DELETE FROM journal_entries WHERE tenant_id = v_tenant_id;
  DELETE FROM company_settings WHERE tenant_id = v_tenant_id;
  DELETE FROM tenant_users WHERE tenant_id = v_tenant_id;
  DELETE FROM tenants WHERE id = v_tenant_id;
  DELETE FROM auth.users WHERE id = v_auth_id;
  PERFORM set_config('request.jwt.claim.sub', '', false);
  SET session_replication_role = 'origin';

  RAISE NOTICE '';
  RAISE NOTICE '🎉 TESTS DE LETTRAGE : 5/5 RÉUSSIS';

EXCEPTION WHEN OTHERS THEN
  SET session_replication_role = 'origin';
  RAISE EXCEPTION '❌ ÉCHEC DES TESTS DE LETTRAGE : %', SQLERRM;
END $$;
