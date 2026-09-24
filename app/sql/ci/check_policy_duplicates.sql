-- ============================================================
-- check_policy_duplicates.sql — ISO-03 / ISO-04 (vague W0.4)
--
-- LE DÉFAUT QUE CE CONTRÔLE FERME. Mesuré le 24/09/2026 sur base neuve
-- (214 migrations) : **1 739 politiques RLS**, dont **495 couples (table,
-- commande) portant DEUX politiques permissives** sur 127 tables — soit 1 001
-- politiques. Le motif est toujours le même : une politique générique
-- `tenant_select` (posée par la 74) **et** une politique par table
-- `tenant_select_<table>` (posée par la 84 et les suivantes).
--
-- POURQUOI C'EST UNE FAILLE, ET PAS UNE REDONDANCE. Deux politiques
-- **permissives** sur la même (table, commande) sont **OU**-ées par PostgreSQL :
-- la plus large gagne. Or les politiques par table portent les gardes de droits
-- (`can_perform('commercial.invoice.create')`, 38 d'entre elles) : dès qu'une
-- politique générique sans garde les accompagne, la garde devient **inopérante**,
-- y compris par appel direct à PostgREST. Un `viewer` peut alors créer une
-- facture si l'écran le lui permet n'est plus la question : la base le permet.
--
-- LA RÈGLE. Deux politiques **permissives** sur le même `(table, commande)` sont
-- refusées. Une politique **restrictive** (`AS RESTRICTIVE`) en doublon est
-- légitime : elle se combine en **ET**, donc elle restreint — le contrôle ne
-- regarde que les permissives.
--
-- LE REGISTRE EST GELÉ, ET IL EST LE PÉRIMÈTRE EXACT DE LA 238. Les couples déjà
-- en double sont inscrits, un par table, avec les commandes concernées
-- (`r`=SELECT, `a`=INSERT, `w`=UPDATE, `d`=DELETE). Ce n'est pas une
-- autorisation : c'est un plafond daté. Deux échecs, pas un seul —
--   * un couple doublé **hors** registre → une nouvelle garde vient d'être
--     neutralisée : c'est le défaut ISO-03 qui revient ;
--   * un couple inscrit qui **n'est plus** doublé → le dédoublonnage a été fait
--     (migration 238) : la ligne doit être retirée du registre **dans le même
--     commit**, sinon le registre pourrit et cessera d'être lu.
-- Même contrat que `ci/expected_failures.sql`, `ci/check_tenant_guard.sql` et
-- `ci/check_anon_grants.sql`. Quand la 238 est passée, ce fichier ne garde que
-- la règle et son auto-test.
--
-- CE QUE LE CONTRÔLE NE PROUVE PAS. Il ne lit pas le corps des politiques : deux
-- politiques jumelles de même portée sémantique ne sont pas détectées comme
-- égales, et une politique permissive **unique** mais sans garde reste
-- silencieuse (c'est l'objet de la 239, rôles opposables).
-- ============================================================

\set ON_ERROR_STOP on

-- ------------------------------------------------------------
-- 1. Le détecteur
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW pg_temp.w_permissives_doubles AS
SELECT p.polrelid,
       p.polcmd,
       count(*) AS n,
       array_agg(p.polname ORDER BY p.polname) AS noms
FROM pg_policy p
WHERE p.polpermissive
GROUP BY p.polrelid, p.polcmd
HAVING count(*) > 1;

-- ------------------------------------------------------------
-- 2. L'auto-test : un contrôle qui n'a jamais vu une fixture fausse ne prouve rien
--    (§4.7, contre-épreuve par réintroduction). La fixture est une table
--    temporaire portant **deux** politiques permissives SELECT.
-- ------------------------------------------------------------
CREATE TEMP TABLE selftest_doublon (id int, tenant_id uuid);
CREATE POLICY a_selftest_doublon ON selftest_doublon FOR SELECT USING (true);
CREATE POLICY b_selftest_doublon ON selftest_doublon FOR SELECT USING (true);

DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n
  FROM pg_temp.w_permissives_doubles d
  WHERE d.polrelid = 'selftest_doublon'::regclass AND d.polcmd = 'r';
  IF n <> 1 THEN
    RAISE EXCEPTION
      '[ISO-03] le détecteur est aveugle : deux politiques permissives jumelles ne sont pas vues (n=%).',
      n;
  END IF;
END $$;

DROP TABLE selftest_doublon;  -- emporte ses deux politiques

-- ------------------------------------------------------------
-- 3. Le registre gelé (mesuré le 24/09/2026, 495 couples sur 127 tables).
--    `cmds` : r=SELECT, a=INSERT, w=UPDATE, d=DELETE.
-- ------------------------------------------------------------
CREATE TEMP TABLE doublons_registre (table_name text PRIMARY KEY, cmds text NOT NULL);
INSERT INTO doublons_registre (table_name, cmds) VALUES
  ('analytic_sections', 'rawd'),
  ('asset_batch_disposal_lines', 'rawd'),
  ('asset_batch_disposals', 'rawd'),
  ('asset_depreciation_plans', 'rawd'),
  ('asset_depreciations', 'rawd'),
  ('asset_documents', 'rawd'),
  ('asset_families', 'rawd'),
  ('asset_free_fields', 'rawd'),
  ('asset_revaluations', 'rawd'),
  ('asset_splits', 'rawd'),
  ('audit_log', 'ra'),
  ('bank_accounts', 'rawd'),
  ('bank_rules', 'rawd'),
  ('bank_transactions', 'rawd'),
  ('banks', 'r'),
  ('bom_lines', 'rawd'),
  ('boms', 'rawd'),
  ('budget_commitments', 'rawd'),
  ('budgets', 'rawd'),
  ('career_history', 'rawd'),
  ('chart_account_templates', 'r'),
  ('chart_accounts', 'rawd'),
  ('collection_reminders', 'rawd'),
  ('company_settings', 'rawd'),
  ('consolidated_treasury', 'rawd'),
  ('contracts', 'rawd'),
  ('cpf_accounts', 'rawd'),
  ('credit_lines', 'rawd'),
  ('credit_notes', 'rawd'),
  ('customer_payments', 'rawd'),
  ('customers', 'rawd'),
  ('delivery_notes', 'rawd'),
  ('delivery_schedules', 'rawd'),
  ('document_templates', 'rawd'),
  ('dpae_records', 'rawd'),
  ('dsn_declarations', 'rawd'),
  ('employees', 'rawd'),
  ('entry_templates', 'rawd'),
  ('expense_reports', 'rawd'),
  ('fiscal_periods', 'rawd'),
  ('fiscal_years', 'rawd'),
  ('fixed_assets', 'rawd'),
  ('future_accounting_movements', 'rawd'),
  ('goods_receipts', 'rawd'),
  ('interviews', 'rawd'),
  ('investments', 'rawd'),
  ('invoices', 'rawd'),
  ('journal_entries', 'rawd'),
  ('journal_lines', 'rawd'),
  ('journals', 'rawd'),
  ('leave_requests', 'rawd'),
  ('legal_declarations', 'rawd'),
  ('legal_watch', 'rawd'),
  ('machines', 'rawd'),
  ('manufacturing_orders', 'rawd'),
  ('mirror_verification_details', 'rawd'),
  ('module_document_access_log', 'ra'),
  ('module_document_shares', 'rawd'),
  ('module_documents', 'rawd'),
  ('mrp_pending_docs', 'rawd'),
  ('mrp_proposals', 'rawd'),
  ('mrp_runs', 'rawd'),
  ('notification_email_queue', 'rawd'),
  ('notification_preferences', 'rawd'),
  ('of_consumptions', 'rawd'),
  ('of_document_access', 'rawd'),
  ('of_labels', 'rawd'),
  ('of_lots', 'rawd'),
  ('pay_recalls', 'rawd'),
  ('pay_runs', 'rawd'),
  ('pay_slips', 'rawd'),
  ('payment_orders', 'rawd'),
  ('payroll_accounting_entries', 'rawd'),
  ('payroll_archives', 'rawd'),
  ('payroll_component_rates', 'rawd'),
  ('payroll_components', 'rawd'),
  ('payroll_templates', 'rawd'),
  ('pick_lists', 'rawd'),
  ('planning_slots', 'rawd'),
  ('price_list_lines', 'rawd'),
  ('price_lists', 'rawd'),
  ('product_attributes', 'rawd'),
  ('product_batches', 'rawd'),
  ('product_equivalences', 'rawd'),
  ('product_serial_numbers', 'rawd'),
  ('product_substitutes', 'rawd'),
  ('product_variants', 'rawd'),
  ('production_forecasts', 'rawd'),
  ('products', 'rawd'),
  ('project_members', 'rawd'),
  ('projects', 'rawd'),
  ('prospects', 'rawd'),
  ('purchase_credit_lines', 'rawd'),
  ('purchase_credit_notes', 'rawd'),
  ('purchase_invoices', 'rawd'),
  ('purchase_orders', 'rawd'),
  ('quality_checks', 'rawd'),
  ('quotes', 'rawd'),
  ('recurring_invoice_templates', 'rawd'),
  ('routing_operations', 'rawd'),
  ('routings', 'rawd'),
  ('salary_advances', 'rawd'),
  ('sales_orders', 'rawd'),
  ('sales_representatives', 'rawd'),
  ('st_orders', 'rawd'),
  ('st_receipt_lines', 'rawd'),
  ('st_receipts', 'rawd'),
  ('st_shipment_lines', 'rawd'),
  ('st_shipments', 'rawd'),
  ('standard_labels', 'rawd'),
  ('stock_movements', 'rawd'),
  ('stock_quantities', 'rawd'),
  ('supplier_payments', 'rawd'),
  ('suppliers', 'rawd'),
  ('tenants', 'r'),
  ('third_party_accounts', 'rawd'),
  ('timesheets', 'rawd'),
  ('toolings', 'rawd'),
  ('treasury_recurring', 'rawd'),
  ('treasury_transfers', 'rawd'),
  ('value_date_tracking', 'rawd'),
  ('vat_returns', 'rawd'),
  ('warehouse_locations', 'rawd'),
  ('warehouses', 'rawd'),
  ('work_centers', 'rawd'),
  ('work_hardship', 'rawd'),
  ('workflows', 'rawd')
;

CREATE OR REPLACE VIEW pg_temp.w_registre_couples AS
SELECT g.table_name, u.cmd
FROM doublons_registre g,
     unnest(string_to_array(g.cmds, NULL)) AS u(cmd);

CREATE OR REPLACE VIEW pg_temp.w_doublons_publics AS
SELECT c.relname AS table_name, d.polcmd, d.n, d.noms
FROM pg_temp.w_permissives_doubles d
JOIN pg_class c ON c.oid = d.polrelid
JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public';

-- ------------------------------------------------------------
-- 4. Le verdict
-- ------------------------------------------------------------
DO $$
DECLARE
  v_nouveaux text;
  v_perimes text;
  v_couples int;
  v_politiques int;
BEGIN
  SELECT count(*), coalesce(sum(n), 0) INTO v_couples, v_politiques
  FROM pg_temp.w_doublons_publics;

  SELECT string_agg(format('    %s(%s) ×%s → %s', d.table_name, d.polcmd, d.n, array_to_string(d.noms, ' + ')),
                    E'\n' ORDER BY d.table_name, d.polcmd)
  INTO v_nouveaux
  FROM pg_temp.w_doublons_publics d
  WHERE NOT EXISTS (SELECT 1 FROM pg_temp.w_registre_couples g
                    WHERE g.table_name = d.table_name AND g.cmd = d.polcmd);

  SELECT string_agg(format('    %s(%s)', g.table_name, g.cmd), E'\n' ORDER BY g.table_name, g.cmd)
  INTO v_perimes
  FROM pg_temp.w_registre_couples g
  WHERE NOT EXISTS (SELECT 1 FROM pg_temp.w_doublons_publics d
                    WHERE d.table_name = g.table_name AND d.polcmd = g.cmd);

  RAISE NOTICE '[ISO-03] % couple(s) (table, commande) doublé(s) — % politique(s) permissive(s) neutralisées.',
    v_couples, v_politiques;

  IF v_nouveaux IS NOT NULL THEN
    RAISE EXCEPTION E'[ISO-03] politique(s) permissive(s) jumelle(s) HORS REGISTRE — la garde accompagnée ne s\'applique plus :\n%', v_nouveaux;
  END IF;

  IF v_perimes IS NOT NULL THEN
    RAISE EXCEPTION E'[ISO-03] couple(s) inscrit(s) au registre qui ne sont PLUS doublés — retirer la ligne de ci/check_policy_duplicates.sql dans le même commit :\n%', v_perimes;
  END IF;

  RAISE NOTICE '[ISO-03] aucun doublon hors registre, et aucune ligne de registre périmée.';
END $$;
