\set ON_ERROR_STOP on
\ir ci/ledger_fixture.sql
DO $$
DECLARE v_t uuid := 'cc000000-0000-0000-0000-0000000000cc';
        v_v uuid := 'dd000000-0000-0000-0000-0000000000dd';
BEGIN
  INSERT INTO auth.users (id,email) VALUES (v_v,'viewer@audit.test') ON CONFLICT DO NOTHING;
  INSERT INTO tenants (id,name,plan,status,currency) VALUES (v_t,'Probe Droits','trial','active','EUR');
  INSERT INTO tenant_users (tenant_id,auth_id,email,name,role,status) VALUES (v_t,v_v,'viewer@audit.test','Lecteur','viewer','active');
  INSERT INTO company_settings (tenant_id,name,currency,country,fiscal_year_start) VALUES (v_t,'PD','EUR','France','2026-01-01') ON CONFLICT DO NOTHING;
  PERFORM _ledger_fixture(v_t);
  INSERT INTO customers (id,tenant_id,name) VALUES ('ff000000-0000-0000-0000-0000000000ff',v_t,'Client');
END $$;

BEGIN;
SELECT set_config('request.jwt.claim.sub','dd000000-0000-0000-0000-0000000000dd',true);
SELECT set_config('request.jwt.claims','{"sub":"dd000000-0000-0000-0000-0000000000dd","role":"authenticated"}',true);
SELECT set_config('request.headers','{"x-tenant-id":"cc000000-0000-0000-0000-0000000000cc"}',true);
SET LOCAL ROLE authenticated;
DO $$
DECLARE v_id uuid; v_n int;
BEGIN
  RAISE NOTICE 'P0 contexte : current_tenant_id=% rôle applicatif=%',
    current_tenant_id(), (SELECT role FROM tenant_users WHERE auth_id=auth.uid());
  BEGIN
    INSERT INTO invoices (tenant_id,number,customer_id,date,due_date,status,subtotal,vat_total,total)
    VALUES (current_tenant_id(),'FA-VIEWER','ff000000-0000-0000-0000-0000000000ff',
            CURRENT_DATE,CURRENT_DATE+30,'draft',100,20,120) RETURNING id INTO v_id;
    RAISE NOTICE 'P1 ⚠️ un LECTEUR (viewer) a CRÉÉ une facture — id %', v_id;
  EXCEPTION WHEN others THEN RAISE NOTICE 'P1 ✅ refusé : %', SQLERRM; END;
  BEGIN
    DELETE FROM customers WHERE id='ff000000-0000-0000-0000-0000000000ff';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n > 0 THEN RAISE NOTICE 'P2 ⚠️ un LECTEUR a SUPPRIMÉ un client';
    ELSE RAISE NOTICE 'P2 ✅ suppression sans effet'; END IF;
  EXCEPTION WHEN others THEN RAISE NOTICE 'P2 ✅ refusé : %', SQLERRM; END;
  BEGIN
    UPDATE tenant_users SET role='admin' WHERE auth_id=auth.uid();
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n > 0 THEN RAISE NOTICE 'P3 ⚠️ un LECTEUR s''est promu ADMIN';
    ELSE RAISE NOTICE 'P3 ✅ promotion sans effet'; END IF;
  EXCEPTION WHEN others THEN RAISE NOTICE 'P3 ✅ refusé : %', SQLERRM; END;
END $$;
ROLLBACK;
