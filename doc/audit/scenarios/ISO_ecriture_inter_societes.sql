\set ON_ERROR_STOP on
\ir ci/ledger_fixture.sql
-- identifiants fixes pour pouvoir rejouer sous le rôle applicatif
DO $$
DECLARE
  vA uuid := '77000000-0000-0000-0000-0000000000aa'; vB uuid := '77000000-0000-0000-0000-0000000000bb';
  uA uuid := '77000000-0000-0000-0000-00000000a111'; uB uuid := '77000000-0000-0000-0000-00000000b111';
BEGIN
  DELETE FROM tenants WHERE id IN (vA,vB);
  INSERT INTO auth.users (id,email) VALUES (uA,'a@x7b.test'),(uB,'b@x7b.test') ON CONFLICT DO NOTHING;
  INSERT INTO tenants (id,name,plan,status,currency) VALUES (vA,'Société A','trial','active','EUR'),(vB,'Société B','trial','active','EUR');
  INSERT INTO tenant_users (tenant_id,auth_id,email,name,role,status) VALUES
    (vA,uA,'a@x7b.test','A','admin','active'),(vB,uB,'b@x7b.test','B','admin','active');
  INSERT INTO company_settings (tenant_id,name,currency,country,fiscal_year_start)
    VALUES (vA,'A','EUR','France','2026-01-01'),(vB,'B','EUR','France','2026-01-01') ON CONFLICT DO NOTHING;
  PERFORM _ledger_fixture(vA); PERFORM _ledger_fixture(vB);
  INSERT INTO customers (id,tenant_id,name) VALUES ('77000000-0000-0000-0000-00000000c111',vB,'Client SECRET de B');
  INSERT INTO projects (id,tenant_id,name) VALUES ('77000000-0000-0000-0000-00000000d111',vB,'Projet de B'),
                                                  ('77000000-0000-0000-0000-00000000d222',vA,'Projet de A');
  INSERT INTO project_tasks (id,tenant_id,project_id,title,status,progress)
    VALUES ('77000000-0000-0000-0000-00000000e111',vB,'77000000-0000-0000-0000-00000000d111','Tâche de B','todo',0);
END $$;

BEGIN;
SELECT set_config('request.jwt.claim.sub','77000000-0000-0000-0000-00000000a111',true);
SELECT set_config('request.jwt.claims','{"sub":"77000000-0000-0000-0000-00000000a111","role":"authenticated"}',true);
SELECT set_config('request.headers','{"x-tenant-id":"77000000-0000-0000-0000-0000000000aa"}',true);
SET LOCAL ROLE authenticated;
DO $$
DECLARE v_id uuid; v_n int; v_st text;
BEGIN
  RAISE NOTICE 'Y0 contexte : société active = %, le client de B est-il visible ? %',
    current_tenant_id(),
    (SELECT count(*) FROM customers WHERE id='77000000-0000-0000-0000-00000000c111');
  BEGIN
    INSERT INTO invoices (tenant_id,number,customer_id,date,due_date,status,subtotal,vat_total,total)
    VALUES (current_tenant_id(),'FA-Y7','77000000-0000-0000-0000-00000000c111',CURRENT_DATE,CURRENT_DATE+30,'draft',100,20,120)
    RETURNING id INTO v_id;
    RAISE NOTICE 'Y1 ⚠️ facture de A rattachée au client INVISIBLE de B — acceptée';
  EXCEPTION WHEN others THEN RAISE NOTICE 'Y1 ✅ refusé : %', left(SQLERRM,140); END;
  BEGIN
    INSERT INTO project_tasks (tenant_id,project_id,parent_id,title,status,progress)
    VALUES (current_tenant_id(),'77000000-0000-0000-0000-00000000d222','77000000-0000-0000-0000-00000000e111','Sous-tâche','done',100);
    RAISE NOTICE 'Y2 ⚠️ tâche de A rattachée à une tâche de B — acceptée';
  EXCEPTION WHEN others THEN RAISE NOTICE 'Y2 ✅ refusé : %', left(SQLERRM,140); END;
END $$;
COMMIT;
-- constat après coup, hors du rôle applicatif
SELECT 'Y3 statut de la tâche de B après le rollback : '||status FROM project_tasks WHERE id='77000000-0000-0000-0000-00000000e111';
