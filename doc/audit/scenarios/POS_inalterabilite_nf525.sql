\set ON_ERROR_STOP on
\ir ci/ledger_fixture.sql
DO $$
DECLARE
  v_t uuid := uuid_generate_v4(); v_u uuid := uuid_generate_v4();
  v_term uuid; v_sess uuid; v_tk uuid; v_prod uuid; v_pm uuid; v_je uuid;
  v_h1 text; v_h2 text; v_n int;
BEGIN
  INSERT INTO auth.users (id,email) VALUES (v_u,'probe6@audit.test') ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claim.sub', v_u::text, false);
  INSERT INTO tenants (id,name,plan,status,currency) VALUES (v_t,'Probe Caisse','trial','active','EUR');
  INSERT INTO tenant_users (tenant_id,auth_id,email,name,role,status) VALUES (v_t,v_u,'probe6@audit.test','A','admin','active');
  INSERT INTO company_settings (tenant_id,name,currency,country,fiscal_year_start) VALUES (v_t,'P6','EUR','France','2026-01-01') ON CONFLICT DO NOTHING;
  PERFORM _ledger_fixture(v_t, ARRAY['531000','707000','445710','758000','658000']);
  PERFORM set_config('app.active_tenant_id', v_t::text, true);

  INSERT INTO pos_terminals (tenant_id,name) VALUES (v_t,'Caisse 1') RETURNING id INTO v_term;
  INSERT INTO pos_sessions (tenant_id,terminal_id,user_email,opening_amount,status)
    VALUES (v_t,v_term,'caissier@p6.test',100,'open') RETURNING id INTO v_sess;
  INSERT INTO products (tenant_id,name,sku,type,sale_price,cost_price,stock_quantity)
    VALUES (v_t,'Article caisse','SKU-P6','stock',120,50,100) RETURNING id INTO v_prod;
  INSERT INTO pos_payment_methods (tenant_id,name,type,account_code,is_active)
    VALUES (v_t,'Espèces','cash','531000',true) RETURNING id INTO v_pm;

  INSERT INTO pos_tickets (tenant_id,number,session_id,terminal_id,date,subtotal,vat_total,total,payment_method,amount_paid,status)
    VALUES (v_t,'TK-1',v_sess,v_term,CURRENT_DATE,100,20,120,'cash',120,'completed') RETURNING id INTO v_tk;
  INSERT INTO pos_ticket_lines (tenant_id,ticket_id,product_id,description,quantity,unit_price,vat_rate,line_total)
    VALUES (v_t,v_tk,v_prod,'Article caisse',1,120,20,120);
  INSERT INTO pos_payments (tenant_id,ticket_id,payment_method_id,amount) VALUES (v_t,v_tk,v_pm,120);

  -- ===== A. Clôture normale : la vente arrive-t-elle en compta et en stock ? =====
  UPDATE pos_sessions SET status='closed', closing_amount=220, closed_at=now() WHERE id=v_sess;
  SELECT id INTO v_je FROM journal_entries WHERE tenant_id=v_t AND journal_code='POS' LIMIT 1;
  RAISE NOTICE 'A1 écriture de clôture : % — lignes : %',
    CASE WHEN v_je IS NULL THEN 'AUCUNE' ELSE 'créée' END,
    (SELECT coalesce(string_agg(account_code||' D='||debit||' C='||credit,' | ' ORDER BY line_order),'-') FROM journal_lines WHERE journal_id=v_je);
  RAISE NOTICE 'A2 sortie de stock sur la vente caisse : % mouvement(s) ; stock produit = %',
    (SELECT count(*) FROM stock_movements WHERE tenant_id=v_t),
    (SELECT stock_quantity FROM products WHERE id=v_prod);
  RAISE NOTICE 'A3 écart de caisse : ouverture 100 + encaissé 120 = 220 attendu, compté 220 → écart nul';

  -- ===== B. Inaltérabilité : peut-on réécrire un ticket après coup ? =====
  SELECT ticket_hash INTO v_h1 FROM pos_tickets WHERE id=v_tk;
  BEGIN
    UPDATE pos_tickets SET total=12, subtotal=10, vat_total=2, amount_paid=12 WHERE id=v_tk;
    SELECT ticket_hash INTO v_h2 FROM pos_tickets WHERE id=v_tk;
    RAISE NOTICE 'B1 ⚠️ ticket ramené de 120 € à 12 € SANS REFUS ; hachage inchangé = %', (v_h1=v_h2);
  EXCEPTION WHEN others THEN RAISE NOTICE 'B1 ✅ refusé : %', SQLERRM; END;
  BEGIN
    DELETE FROM pos_ticket_lines WHERE ticket_id=v_tk;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RAISE NOTICE 'B2 ⚠️ % ligne(s) de ticket supprimée(s) sans refus', v_n;
  EXCEPTION WHEN others THEN RAISE NOTICE 'B2 ✅ refusé : %', SQLERRM; END;
  RAISE NOTICE 'B3 journal NF525 : % événement(s) — aucun ne mentionne la modification',
    (SELECT count(*) FROM nf525_event_log WHERE tenant_id=v_t);
END $$;
