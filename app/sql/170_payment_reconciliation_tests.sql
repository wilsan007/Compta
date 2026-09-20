-- ============================================================
-- 170_payment_reconciliation_tests.sql
--
-- Régression : le rapprochement bancaire ne doit pas « dé-payer » une facture.
--
-- Avant sql/169_fix_payment_reconciled_status.sql, les triggers comptaient les
-- règlements `status IN ('recorded', 'validated')` alors que la contrainte
-- CHECK n'autorise que 'recorded' | 'reconciled' | 'cancelled'. Passer un
-- règlement à 'reconciled' le faisait sortir du total payé :
--   amount_paid 1000 -> 0, payment_state 'paid' -> 'not_paid', solde 0 -> 1000.
--
-- Ces tests rejouent le parcours complet sur la vraie base (pas de mock).
-- ============================================================

DO $$
DECLARE
  v_tenant_id   uuid := uuid_generate_v4();
  v_auth_id     uuid := uuid_generate_v4();
  v_customer_id uuid;
  v_supplier_id uuid;
  v_invoice_id  uuid;
  v_pinv_id     uuid;
  v_payment_id  uuid;
  v_spayment_id uuid;
  v_paid        numeric;
  v_due         numeric;
  v_state       text;
  v_balance     numeric;
BEGIN
  -- ---------- contexte tenant ----------
  INSERT INTO auth.users (id, email)
  VALUES (v_auth_id, 'test@payment-reconciliation.com') ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claim.sub', v_auth_id::text, false);

  INSERT INTO tenants (id, name, plan, status, currency, created_at)
  VALUES (v_tenant_id, 'Test Rapprochement', 'trial', 'active', 'EUR', NOW());

  INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status, created_at)
  VALUES (v_tenant_id, v_auth_id, 'test@payment-reconciliation.com', 'Test Admin', 'admin', 'active', NOW());

  INSERT INTO company_settings (tenant_id, name, currency, country, fiscal_year_start, created_at)
  VALUES (v_tenant_id, 'Test Company', 'EUR', 'France', '2026-01-01', NOW()) ON CONFLICT DO NOTHING;

  PERFORM set_config('app.active_tenant_id', v_tenant_id::text, true);

  IF current_tenant_id() IS DISTINCT FROM v_tenant_id THEN
    RAISE EXCEPTION 'Contexte tenant non établi — le test ne prouverait rien';
  END IF;

  -- ============================================================
  -- TEST 1 : encaissement client rapproché → la facture reste payée
  -- ============================================================
  INSERT INTO customers (name, tenant_id, balance, credit_used)
  VALUES ('Client Rapprochement', v_tenant_id, 0, 0) RETURNING id INTO v_customer_id;

  INSERT INTO invoices (number, date, due_date, status, tenant_id, customer_id,
                        total, amount_paid, amount_due, payment_state)
  VALUES ('FA-RAPPRO-1', CURRENT_DATE, CURRENT_DATE, 'sent', v_tenant_id, v_customer_id,
          1000, 0, 1000, 'not_paid')
  RETURNING id INTO v_invoice_id;

  INSERT INTO customer_payments (number, payment_date, amount, status, tenant_id, customer_id, invoice_id)
  VALUES ('REG-RAPPRO-1', CURRENT_DATE, 1000, 'recorded', v_tenant_id, v_customer_id, v_invoice_id)
  RETURNING id INTO v_payment_id;

  SELECT amount_paid, amount_due, payment_state INTO v_paid, v_due, v_state
  FROM invoices WHERE id = v_invoice_id;
  IF v_paid <> 1000 OR v_due <> 0 OR v_state <> 'paid' THEN
    RAISE EXCEPTION 'TEST 1 (encaissement) : attendu 1000/0/paid, obtenu %/%/%', v_paid, v_due, v_state;
  END IF;

  -- Ce que fait auto_match_bank_transactions
  UPDATE customer_payments SET status = 'reconciled' WHERE id = v_payment_id;

  SELECT amount_paid, amount_due, payment_state INTO v_paid, v_due, v_state
  FROM invoices WHERE id = v_invoice_id;
  IF v_paid <> 1000 OR v_due <> 0 OR v_state <> 'paid' THEN
    RAISE EXCEPTION 'TEST 1 (rapprochement) : la facture a été dé-payée — %/%/%', v_paid, v_due, v_state;
  END IF;

  SELECT balance INTO v_balance FROM customers WHERE id = v_customer_id;
  IF v_balance <> 0 THEN
    RAISE EXCEPTION 'TEST 1 (solde client) : attendu 0 après rapprochement, obtenu %', v_balance;
  END IF;
  RAISE NOTICE '✅ TEST 1 : rapprochement d''un encaissement — facture toujours payée, solde client inchangé';

  -- ============================================================
  -- TEST 2 : annulation d'un encaissement → la facture redevient impayée
  -- ============================================================
  UPDATE customer_payments SET status = 'cancelled' WHERE id = v_payment_id;

  SELECT amount_paid, amount_due, payment_state INTO v_paid, v_due, v_state
  FROM invoices WHERE id = v_invoice_id;
  IF v_paid <> 0 OR v_due <> 1000 OR v_state <> 'not_paid' THEN
    RAISE EXCEPTION 'TEST 2 (annulation) : attendu 0/1000/not_paid, obtenu %/%/%', v_paid, v_due, v_state;
  END IF;

  SELECT balance INTO v_balance FROM customers WHERE id = v_customer_id;
  IF v_balance <> 1000 THEN
    RAISE EXCEPTION 'TEST 2 (solde client) : attendu 1000 après annulation, obtenu %', v_balance;
  END IF;
  RAISE NOTICE '✅ TEST 2 : annulation d''un encaissement — facture impayée, solde client regonflé une seule fois';

  -- ============================================================
  -- TEST 3 : règlement fournisseur rapproché → facture d'achat toujours payée
  --          et solde fournisseur décrémenté une seule fois
  -- ============================================================
  INSERT INTO suppliers (name, tenant_id, balance)
  VALUES ('Fournisseur Rapprochement', v_tenant_id, 500) RETURNING id INTO v_supplier_id;

  INSERT INTO purchase_invoices (number, date, due_date, status, tenant_id, supplier_id,
                                 total, amount_paid, amount_due, payment_state)
  VALUES ('FF-RAPPRO-1', CURRENT_DATE, CURRENT_DATE, 'sent', v_tenant_id, v_supplier_id,
          500, 0, 500, 'not_paid')
  RETURNING id INTO v_pinv_id;

  INSERT INTO supplier_payments (number, payment_date, amount, status, tenant_id, supplier_id, purchase_invoice_id)
  VALUES ('REG-FF-RAPPRO-1', CURRENT_DATE, 500, 'recorded', v_tenant_id, v_supplier_id, v_pinv_id)
  RETURNING id INTO v_spayment_id;

  SELECT amount_paid, amount_due, payment_state INTO v_paid, v_due, v_state
  FROM purchase_invoices WHERE id = v_pinv_id;
  IF v_paid <> 500 OR v_due <> 0 OR v_state <> 'paid' THEN
    RAISE EXCEPTION 'TEST 3 (règlement) : attendu 500/0/paid, obtenu %/%/%', v_paid, v_due, v_state;
  END IF;

  SELECT balance INTO v_balance FROM suppliers WHERE id = v_supplier_id;
  IF v_balance <> 0 THEN
    RAISE EXCEPTION 'TEST 3 (solde fournisseur) : attendu 0 après règlement, obtenu %', v_balance;
  END IF;

  UPDATE supplier_payments SET status = 'reconciled' WHERE id = v_spayment_id;

  SELECT amount_paid, amount_due, payment_state INTO v_paid, v_due, v_state
  FROM purchase_invoices WHERE id = v_pinv_id;
  IF v_paid <> 500 OR v_due <> 0 OR v_state <> 'paid' THEN
    RAISE EXCEPTION 'TEST 3 (rapprochement) : la facture d''achat a été dé-payée — %/%/%', v_paid, v_due, v_state;
  END IF;

  SELECT balance INTO v_balance FROM suppliers WHERE id = v_supplier_id;
  IF v_balance <> 0 THEN
    RAISE EXCEPTION 'TEST 3 (solde fournisseur) : le rapprochement a rejoué le décaissement — solde %', v_balance;
  END IF;
  RAISE NOTICE '✅ TEST 3 : rapprochement d''un règlement fournisseur — facture payée, solde décrémenté une seule fois';

  -- ============================================================
  -- Nettoyage (triggers désactivés : les écritures validées sont immuables)
  -- ============================================================
  SET session_replication_role = 'replica';

  DELETE FROM supplier_payments WHERE tenant_id = v_tenant_id;
  DELETE FROM customer_payments WHERE tenant_id = v_tenant_id;
  DELETE FROM journal_lines WHERE tenant_id = v_tenant_id;
  DELETE FROM journal_entries WHERE tenant_id = v_tenant_id;
  DELETE FROM bank_transactions WHERE tenant_id = v_tenant_id;
  DELETE FROM purchase_invoices WHERE tenant_id = v_tenant_id;
  DELETE FROM invoices WHERE tenant_id = v_tenant_id;
  DELETE FROM suppliers WHERE tenant_id = v_tenant_id;
  DELETE FROM customers WHERE tenant_id = v_tenant_id;
  DELETE FROM company_settings WHERE tenant_id = v_tenant_id;
  DELETE FROM tenant_users WHERE tenant_id = v_tenant_id;
  DELETE FROM tenants WHERE id = v_tenant_id;
  DELETE FROM auth.users WHERE id = v_auth_id;
  PERFORM set_config('request.jwt.claim.sub', '', false);

  SET session_replication_role = 'origin';

  RAISE NOTICE '';
  RAISE NOTICE '🎉 TESTS DE RAPPROCHEMENT DES RÈGLEMENTS : 3/3 RÉUSSIS';

EXCEPTION WHEN OTHERS THEN
  SET session_replication_role = 'origin';
  RAISE EXCEPTION '❌ ÉCHEC DES TESTS DE RAPPROCHEMENT : %', SQLERRM;
END $$;
