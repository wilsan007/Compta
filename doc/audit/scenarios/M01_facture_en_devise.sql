\set ON_ERROR_STOP on
\ir ci/ledger_fixture.sql
DO $$
DECLARE
  v_t uuid := uuid_generate_v4(); v_u uuid := uuid_generate_v4();
  v_cust uuid; v_inv uuid; v_je uuid;
  v_d numeric; v_c numeric;
BEGIN
  INSERT INTO auth.users (id,email) VALUES (v_u,'probe4@audit.test') ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claim.sub', v_u::text, false);
  INSERT INTO tenants (id,name,plan,status,currency) VALUES (v_t,'Probe Devises','trial','active','EUR');
  INSERT INTO tenant_users (tenant_id,auth_id,email,name,role,status) VALUES (v_t,v_u,'probe4@audit.test','A','admin','active');
  INSERT INTO company_settings (tenant_id,name,currency,country,fiscal_year_start) VALUES (v_t,'P4','EUR','France','2026-01-01') ON CONFLICT DO NOTHING;
  PERFORM _ledger_fixture(v_t, ARRAY['411000','701000','445710','666000','766000']);
  PERFORM set_config('app.active_tenant_id', v_t::text, true);
  INSERT INTO customers (tenant_id,name) VALUES (v_t,'Client US') RETURNING id INTO v_cust;

  -- Facture de 1 000 USD, taux 0,90 → 900 EUR en devise de tenue
  INSERT INTO invoices (tenant_id,number,customer_id,date,due_date,status,subtotal,vat_total,total,
                        currency_code,exchange_rate,amount_untaxed_currency,amount_total_currency,validation_status)
  VALUES (v_t,'FA-USD-1',v_cust,CURRENT_DATE,CURRENT_DATE+30,'draft',1000,0,1000,
          'USD',0.90,1000,1000,'draft') RETURNING id INTO v_inv;
  INSERT INTO invoice_lines (tenant_id,invoice_id,description,quantity,unit_price,vat_rate,total,line_order)
  VALUES (v_t,v_inv,'Prestation',1,1000,0,1000,0);

  UPDATE invoices SET validation_status='validated', status='sent' WHERE id=v_inv;

  SELECT id INTO v_je FROM journal_entries WHERE tenant_id=v_t ORDER BY created_at DESC LIMIT 1;
  IF v_je IS NULL THEN RAISE NOTICE 'C0 ❌ aucune écriture produite'; RETURN; END IF;
  SELECT sum(debit), sum(credit) INTO v_d, v_c FROM journal_lines WHERE journal_id=v_je;
  RAISE NOTICE 'C1 facture 1 000 USD au taux 0,90 → écriture : débit=% crédit=%', v_d, v_c;
  RAISE NOTICE 'C2 attendu en devise de tenue (EUR) : 900,00';
  RAISE NOTICE 'C3 lignes : %', (SELECT string_agg(account_code||' D='||debit||' C='||credit,' | ' ORDER BY line_order) FROM journal_lines WHERE journal_id=v_je);
  RAISE NOTICE 'C4 colonnes devise sur les lignes d''écriture : %',
    (SELECT coalesce(string_agg(column_name,', '),'AUCUNE') FROM information_schema.columns
     WHERE table_name='journal_lines' AND column_name ~ 'curren|exchange|devise');
END $$;
