# Miroir des données — Tenant: default

**Dernière sync:** 2026-07-17T14:02:44.405Z
**Source:** https://ndtaedcgwnaopopugiql.supabase.co
**Total:** 329 lignes sur 21 tables

## Structure du dossier

- `sql/full-export.sql` — Dump SQL complet (importable dans PostgreSQL)
- `csv/<table>.csv` — Un fichier CSV par table avec données
- `json/full-export.json` — Export JSON complet
- `sync_metadata.json` — Métadonnées de la dernière sync

## Tables avec données

- **company_settings**: 2 lignes
- **users**: 4 lignes
- **chart_accounts**: 64 lignes
- **customers**: 10 lignes
- **suppliers**: 8 lignes
- **products**: 5 lignes
- **invoices**: 10 lignes
- **invoice_lines**: 18 lignes
- **quotes**: 4 lignes
- **credit_notes**: 2 lignes
- **purchase_invoices**: 7 lignes
- **bank_accounts**: 8 lignes
- **bank_transactions**: 45 lignes
- **bank_rules**: 15 lignes
- **journal_entries**: 17 lignes
- **journal_lines**: 71 lignes
- **journals**: 5 lignes
- **vat_returns**: 9 lignes
- **fiscal_years**: 1 lignes
- **fiscal_periods**: 12 lignes
- **projects**: 12 lignes

## Tables vides

- quote_lines
- credit_note_lines
- purchase_invoice_lines
- entry_templates
- third_party_accounts
- analytic_sections
- budgets
- budget_commitments
- standard_labels
- fixed_assets
- asset_depreciations
- employees
- pay_runs
- timesheets
- pay_slips
- payroll_accounting_entries
- leave_requests
- contracts
- legal_declarations
- stock_movements
- stock_quantities
- warehouses
- currencies
- payment_orders
- collection_reminders
- sales_orders
- sales_order_lines
- delivery_notes
- delivery_note_lines
- customer_payments
- purchase_orders
- purchase_order_lines
- goods_receipts
- goods_receipt_lines
- supplier_payments
- purchase_credit_notes
- purchase_credit_lines
- price_lists
- price_list_lines
- boms
- bom_lines
- manufacturing_orders
- audit_log

## Comment restaurer

1. Installer PostgreSQL (ou utiliser pgAdmin/DBeaver)
2. Créer les tables avec le schéma (`supabase-schema.sql`)
3. Importer `sql/full-export.sql`
4. Toutes vos données sont restaurées