\set ON_ERROR_STOP on
\ir ci/ledger_fixture.sql
DO $$
DECLARE
  v_t uuid := uuid_generate_v4(); v_u uuid := uuid_generate_v4();
  v_wh uuid; v_prod uuid; v_cust uuid; v_so uuid; v_dn uuid;
BEGIN
  INSERT INTO auth.users (id,email) VALUES (v_u,'probe2@audit.test') ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claim.sub', v_u::text, false);
  INSERT INTO tenants (id,name,plan,status,currency) VALUES (v_t,'Probe Ventes','trial','active','EUR');
  INSERT INTO tenant_users (tenant_id,auth_id,email,name,role,status) VALUES (v_t,v_u,'probe2@audit.test','A','admin','active');
  INSERT INTO company_settings (tenant_id,name,currency,country,fiscal_year_start) VALUES (v_t,'Probe2','EUR','France','2026-01-01') ON CONFLICT DO NOTHING;
  PERFORM _ledger_fixture(v_t);
  PERFORM set_config('app.active_tenant_id', v_t::text, true);
  INSERT INTO warehouses (tenant_id,name,code) VALUES (v_t,'Dépôt','W1') RETURNING id INTO v_wh;
  INSERT INTO products (tenant_id,name,sku,type,cost_price,stock_quantity,sale_price)
    VALUES (v_t,'Art','SKU-P2','stock',10,0,25) RETURNING id INTO v_prod;
  INSERT INTO customers (tenant_id,name) VALUES (v_t,'Client') RETURNING id INTO v_cust;

  -- entrée « propre » (comme le font les suites existantes) : dépôt + coût
  INSERT INTO stock_movements (tenant_id,product_id,warehouse_id,type,movement_type,quantity,unit_cost,date)
    VALUES (v_t,v_prod,v_wh,'in','in',100,10,CURRENT_DATE);
  RAISE NOTICE 'B0 stock initial : products=% / dépôt=% / couches=% / écritures=%',
    (SELECT stock_quantity FROM products WHERE id=v_prod),
    (SELECT quantity FROM stock_quantities WHERE product_id=v_prod),
    (SELECT coalesce(sum(remaining_qty),0) FROM stock_valuation_layers WHERE tenant_id=v_t),
    (SELECT count(*) FROM journal_entries WHERE tenant_id=v_t);

  -- ======== VENTES : commande confirmée → réservation ========
  INSERT INTO sales_orders (tenant_id,number,customer_id,order_date,status,subtotal,vat,total)
    VALUES (v_t,'SO-1',v_cust,CURRENT_DATE,'draft',2500,500,3000) RETURNING id INTO v_so;
  INSERT INTO sales_order_lines (tenant_id,sales_order_id,product_id,description,quantity,unit_price,vat_rate,line_total)
    VALUES (v_t,v_so,v_prod,'Art',40,25,20,1000);
  UPDATE sales_orders SET status='confirmed' WHERE id=v_so;
  RAISE NOTICE 'B1 après confirmation : réservations=% reserved_quantity=% disponible=%',
    (SELECT count(*) FROM stock_reservations WHERE tenant_id=v_t AND status='active'),
    (SELECT reserved_quantity FROM stock_quantities WHERE product_id=v_prod),
    (SELECT quantity_available FROM stock_quantities WHERE product_id=v_prod);

  -- ======== LIVRAISON ========
  INSERT INTO delivery_notes (tenant_id,number,customer_id,sales_order_id,delivery_date,status)
    VALUES (v_t,'BL-1',v_cust,v_so,CURRENT_DATE,'pending') RETURNING id INTO v_dn;
  INSERT INTO delivery_note_lines (tenant_id,delivery_note_id,product_id,description,quantity,sales_order_line_id)
    VALUES (v_t,v_dn,v_prod,'Art',40,(SELECT id FROM sales_order_lines WHERE sales_order_id=v_so));
  BEGIN
    UPDATE delivery_notes SET status='shipped' WHERE id=v_dn;
    RAISE NOTICE 'B2 expédition OK';
  EXCEPTION WHEN others THEN RAISE NOTICE 'B2 ❌ expédition : %', SQLERRM; END;

  RAISE NOTICE 'B3 après expédition : products=% / dépôt=% / couches restantes=% / écritures=%',
    (SELECT stock_quantity FROM products WHERE id=v_prod),
    (SELECT quantity FROM stock_quantities WHERE product_id=v_prod),
    (SELECT coalesce(sum(remaining_qty),0) FROM stock_valuation_layers WHERE tenant_id=v_t),
    (SELECT count(*) FROM journal_entries WHERE tenant_id=v_t);

  UPDATE delivery_notes SET status='delivered' WHERE id=v_dn;
  RAISE NOTICE 'B4 après « livré » : réservations actives=% reserved_quantity=% disponible=%',
    (SELECT count(*) FROM stock_reservations WHERE tenant_id=v_t AND status='active'),
    (SELECT reserved_quantity FROM stock_quantities WHERE product_id=v_prod),
    (SELECT quantity_available FROM stock_quantities WHERE product_id=v_prod);

  RAISE NOTICE 'B5 cohérence : products.stock_quantity=% vs somme des dépôts=%',
    (SELECT stock_quantity FROM products WHERE id=v_prod),
    (SELECT coalesce(sum(quantity),0) FROM stock_quantities WHERE product_id=v_prod);
END $$;
