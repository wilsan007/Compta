\set ON_ERROR_STOP on
\ir ci/ledger_fixture.sql
DO $$
DECLARE
  v_t uuid := uuid_generate_v4(); v_u uuid := uuid_generate_v4();
  v_wh uuid; v_prod uuid; v_emp uuid; v_run uuid; v_ba uuid;
  n1 int; n2 int; n3 int;
BEGIN
  INSERT INTO auth.users (id,email) VALUES (v_u,'probe3@audit.test') ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claim.sub', v_u::text, false);
  INSERT INTO tenants (id,name,plan,status,currency) VALUES (v_t,'Probe Suppressions','trial','active','EUR');
  INSERT INTO tenant_users (tenant_id,auth_id,email,name,role,status) VALUES (v_t,v_u,'probe3@audit.test','A','admin','active');
  INSERT INTO company_settings (tenant_id,name,currency,country,fiscal_year_start) VALUES (v_t,'P3','EUR','France','2026-01-01') ON CONFLICT DO NOTHING;
  PERFORM _ledger_fixture(v_t);
  PERFORM set_config('app.active_tenant_id', v_t::text, true);

  -- ---- produit avec historique de mouvements + écritures ----
  INSERT INTO warehouses (tenant_id,name,code) VALUES (v_t,'D','W1') RETURNING id INTO v_wh;
  INSERT INTO products (tenant_id,name,sku,type,cost_price,stock_quantity) VALUES (v_t,'Art','SKU-P3','stock',10,0) RETURNING id INTO v_prod;
  INSERT INTO stock_movements (tenant_id,product_id,warehouse_id,type,movement_type,quantity,unit_cost,date)
    VALUES (v_t,v_prod,v_wh,'in','in',100,10,CURRENT_DATE);
  SELECT count(*) INTO n1 FROM stock_movements WHERE tenant_id=v_t;
  SELECT count(*) INTO n2 FROM journal_entries WHERE tenant_id=v_t;
  SELECT count(*) INTO n3 FROM stock_valuation_layers WHERE tenant_id=v_t;
  RAISE NOTICE 'D0 avant : mouvements=% écritures=% couches=%', n1,n2,n3;
  BEGIN
    DELETE FROM products WHERE id=v_prod;
    SELECT count(*) INTO n1 FROM stock_movements WHERE tenant_id=v_t;
    SELECT count(*) INTO n3 FROM stock_valuation_layers WHERE tenant_id=v_t;
    RAISE NOTICE 'D1 ⚠️ produit SUPPRIMÉ sans refus : mouvements restants=% couches restantes=% ; écritures restantes=% (lignes orphelines)',
      n1, n3, (SELECT count(*) FROM journal_entries WHERE tenant_id=v_t);
  EXCEPTION WHEN others THEN RAISE NOTICE 'D1 ✅ suppression produit refusée : %', SQLERRM; END;

  -- ---- produit SANS écriture (cas réel après une réception : coût nul) ----
  DECLARE v_prod2 uuid; BEGIN
    INSERT INTO products (tenant_id,name,sku,type,cost_price,stock_quantity) VALUES (v_t,'Art2','SKU-P3B','stock',0,0) RETURNING id INTO v_prod2;
    INSERT INTO stock_movements (tenant_id,product_id,warehouse_id,type,movement_type,quantity,unit_cost,date)
      VALUES (v_t,v_prod2,v_wh,'in','in',50,0,CURRENT_DATE);
    RAISE NOTICE 'D1b produit sans écriture : mouvements=%', (SELECT count(*) FROM stock_movements WHERE product_id=v_prod2);
    DELETE FROM products WHERE id=v_prod2;
    RAISE NOTICE 'D1b ⚠️ produit SUPPRIMÉ : mouvements restants=%', (SELECT count(*) FROM stock_movements WHERE product_id=v_prod2);
  EXCEPTION WHEN others THEN RAISE NOTICE 'D1b ✅ refusée : %', SQLERRM; END;

  -- ---- salarié avec bulletins ----
  INSERT INTO employees (tenant_id,name,email,hire_date,salary,status)
    VALUES (v_t,'Jean Test','jt@p3.test',CURRENT_DATE,3000,'active') RETURNING id INTO v_emp;
  INSERT INTO pay_runs (tenant_id,period_start,period_end,pay_date,status,number)
    VALUES (v_t,date_trunc('month',CURRENT_DATE)::date,(date_trunc('month',CURRENT_DATE)+interval '1 month -1 day')::date,CURRENT_DATE,'draft','PR-001') RETURNING id INTO v_run;
  INSERT INTO pay_slips (tenant_id,number,employee_id,pay_run_id,period_start,period_end,gross_salary,net_salary,status)
    VALUES (v_t,'BP-001',v_emp,v_run,date_trunc('month',CURRENT_DATE)::date,(date_trunc('month',CURRENT_DATE)+interval '1 month -1 day')::date,3000,2200,'draft');
  RAISE NOTICE 'D2 bulletins avant = %', (SELECT count(*) FROM pay_slips WHERE tenant_id=v_t);
  BEGIN
    DELETE FROM employees WHERE id=v_emp;
    RAISE NOTICE 'D3 ⚠️ salarié SUPPRIMÉ sans refus : bulletins restants = %', (SELECT count(*) FROM pay_slips WHERE tenant_id=v_t);
  EXCEPTION WHEN others THEN RAISE NOTICE 'D3 ✅ suppression salarié refusée : %', SQLERRM; END;

  -- ---- compte bancaire avec mouvements ----
  INSERT INTO bank_accounts (tenant_id,name,type,account_number,balance,currency)
    VALUES (v_t,'Compte','chequing','FR7630001007941234567890185',0,'EUR') RETURNING id INTO v_ba;
  INSERT INTO bank_transactions (tenant_id,account_id,date,label,description,type,amount)
    VALUES (v_t,v_ba,CURRENT_DATE,'Virement','Virement','credit',500);
  RAISE NOTICE 'D4 opérations bancaires avant = %', (SELECT count(*) FROM bank_transactions WHERE tenant_id=v_t);
  BEGIN
    DELETE FROM bank_accounts WHERE id=v_ba;
    RAISE NOTICE 'D5 ⚠️ compte bancaire SUPPRIMÉ sans refus : opérations restantes = %', (SELECT count(*) FROM bank_transactions WHERE tenant_id=v_t);
  EXCEPTION WHEN others THEN RAISE NOTICE 'D5 ✅ suppression compte refusée : %', SQLERRM; END;
END $$;
