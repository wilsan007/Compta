\set ON_ERROR_STOP on
\ir ci/ledger_fixture.sql
DO $$
DECLARE
  v_t uuid := uuid_generate_v4(); v_u uuid := uuid_generate_v4();
  v_wh uuid; v_prod uuid; v_sup uuid; v_cust uuid;
  v_po uuid; v_gr uuid; v_so uuid; v_dn uuid;
  r record; v_txt text;
BEGIN
  INSERT INTO auth.users (id,email) VALUES (v_u,'probe1@audit.test') ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claim.sub', v_u::text, false);
  INSERT INTO tenants (id,name,plan,status,currency) VALUES (v_t,'Probe Achats/Stock','trial','active','EUR');
  INSERT INTO tenant_users (tenant_id,auth_id,email,name,role,status) VALUES (v_t,v_u,'probe1@audit.test','A','admin','active');
  INSERT INTO company_settings (tenant_id,name,currency,country,fiscal_year_start) VALUES (v_t,'Probe','EUR','France','2026-01-01') ON CONFLICT DO NOTHING;
  PERFORM _ledger_fixture(v_t);
  PERFORM set_config('app.active_tenant_id', v_t::text, true);

  INSERT INTO warehouses (tenant_id,name,code) VALUES (v_t,'Dépôt','W1') RETURNING id INTO v_wh;
  INSERT INTO products (tenant_id,name,sku,type,cost_price,stock_quantity,sale_price)
    VALUES (v_t,'Article probe','SKU-P1','stock',10,0,25) RETURNING id INTO v_prod;
  INSERT INTO suppliers (tenant_id,name) VALUES (v_t,'Fournisseur P') RETURNING id INTO v_sup;
  INSERT INTO customers (tenant_id,name) VALUES (v_t,'Client P') RETURNING id INTO v_cust;

  -- ======== ACHATS : commande puis réception ========
  INSERT INTO purchase_orders (tenant_id,number,supplier_id,order_date,status,subtotal,vat,total)
    VALUES (v_t,'PO-1',v_sup,CURRENT_DATE,'confirmed',1000,200,1200) RETURNING id INTO v_po;
  INSERT INTO purchase_order_lines (tenant_id,purchase_order_id,product_id,description,quantity,unit_price,vat_rate,line_total,line_order)
    VALUES (v_t,v_po,v_prod,'Article probe',100,10,20,1000,0);

  INSERT INTO goods_receipts (tenant_id,number,supplier_id,purchase_order_id,receipt_date,status)
    VALUES (v_t,'BR-1',v_sup,v_po,CURRENT_DATE,'pending') RETURNING id INTO v_gr;
  INSERT INTO goods_receipt_lines (tenant_id,goods_receipt_id,product_id,description,quantity_ordered,quantity_received)
    VALUES (v_t,v_gr,v_prod,'Article probe',100,100);

  BEGIN
    UPDATE goods_receipts SET status='received' WHERE id=v_gr;
    RAISE NOTICE 'A1 réception OK (pas d''exception)';
  EXCEPTION WHEN others THEN
    RAISE NOTICE 'A1 ❌ réception RELEVE UNE EXCEPTION : %', SQLERRM;
  END;

  RAISE NOTICE 'A2 mouvements créés=% qté totale=%',
    (SELECT count(*) FROM stock_movements WHERE tenant_id=v_t),
    (SELECT coalesce(sum(quantity),0) FROM stock_movements WHERE tenant_id=v_t);

  RAISE NOTICE 'A3 products.stock_quantity = %', (SELECT stock_quantity FROM products WHERE id=v_prod);
  RAISE NOTICE 'A4 stock_quantities lignes = % (qté=%)',
    (SELECT count(*) FROM stock_quantities WHERE tenant_id=v_t),
    (SELECT coalesce(sum(quantity),0) FROM stock_quantities WHERE tenant_id=v_t);
  RAISE NOTICE 'A5 couches de valorisation = % (valeur=%)',
    (SELECT count(*) FROM stock_valuation_layers WHERE tenant_id=v_t),
    (SELECT coalesce(sum(value),0) FROM stock_valuation_layers WHERE tenant_id=v_t);
  RAISE NOTICE 'A6 écritures comptables = %', (SELECT count(*) FROM journal_entries WHERE tenant_id=v_t);
  RAISE NOTICE 'A7 avertissements traçabilité = %', (SELECT count(*) FROM tracking_warnings WHERE tenant_id=v_t);
  RAISE NOTICE 'A8 mouvement : warehouse=% lot=% unit_cost=%',
    (SELECT warehouse_id IS NULL FROM stock_movements WHERE tenant_id=v_t LIMIT 1),
    (SELECT lot_id IS NULL FROM stock_movements WHERE tenant_id=v_t LIMIT 1),
    (SELECT unit_cost FROM stock_movements WHERE tenant_id=v_t LIMIT 1);
END $$;
