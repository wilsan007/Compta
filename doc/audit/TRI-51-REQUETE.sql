\set ON_ERROR_STOP on
CREATE TEMP TABLE map_modul (motif text, module text);
INSERT INTO map_modul VALUES
 ('journal_entries','compta'),('journal_lines','compta'),('chart_accounts','compta'),
 ('invoices','commercial'),('invoice_lines','commercial'),('sales_orders','commercial'),
 ('purchase_orders','commercial'),('purchase_invoices','commercial'),('credit_notes','commercial'),
 ('delivery_notes','commercial'),('customer_payments','commercial'),('supplier_payments','commercial'),
 ('stock_movements','stock'),('stock_reservations','stock'),('products','stock'),
 ('pay_runs','rh'),('payroll_lines','rh'),('payroll_variable_elements','rh'),('employees','rh'),
 ('expense_reports','rh'),('timesheets','rh'),('bank_transactions','tresorerie'),
 ('bank_accounts','tresorerie'),('statements','tresorerie'),('reconciliations','tresorerie'),
 ('manufacturing_orders','production'),('goods_receipts','production'),('projects','projets'),
 ('tenants','systeme'),('tenant_users','systeme'),('company_settings','systeme'),
 ('journals','systeme'),('fiscal_years','systeme'),('notifications','systeme'),('document_links','systeme');

CREATE TEMP TABLE t AS
SELECT p.proname,
  count(DISTINCT m.module) AS nb,
  string_agg(DISTINCT m.module, ',' ORDER BY m.module) AS modules,
  (p.prosrc ~* 'chain_avant|chain_apres|link_documents') AS lien,
  (p.prosrc ~* 'INSERT\s+INTO\s+(public\.)?(journal_entries|journal_lines|stock_movements|payroll_lines|payroll_variable_elements|invoice_lines|delivery_notes)') AS etat,
  (p.prosrc ~* 'RAISE EXCEPTION') AS leve,
  (p.prosrc ~* 'INSERT\s+INTO\s+(public\.)?notifications') AS notifie,
  EXISTS (SELECT 1 FROM pg_trigger tg WHERE tg.tgfoid = p.oid) AS trig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
JOIN map_modul m ON position(m.motif in p.prosrc) > 0
WHERE n.nspname='public' AND p.proname NOT LIKE '\_%'
  AND p.prosrc ~* 'INSERT\s+INTO|UPDATE\s+\w+\s+SET|DELETE\s+FROM'
GROUP BY p.proname, p.prosrc, p.oid
HAVING count(DISTINCT m.module) >= 2;

\echo '=== LES 51 : tous les signaux, dans l ordre du nom ==='
SELECT proname, nb AS mod, modules,
  CASE WHEN lien THEN 'LIEN' ELSE '.' END AS lien,
  CASE WHEN etat THEN 'ETAT' ELSE '.' END AS etat,
  CASE WHEN leve THEN 'LEVE' ELSE '.' END AS leve,
  CASE WHEN notifie THEN 'NOTIF' ELSE '.' END AS notif,
  CASE WHEN trig THEN 'trig' ELSE 'appel' END AS entree
FROM t ORDER BY proname;