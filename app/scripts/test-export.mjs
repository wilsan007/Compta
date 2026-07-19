import { createClient } from '@supabase/supabase-js'

const supabaseUrl = 'https://ndtaedcgwnaopopugiql.supabase.co'
const supabaseKey = 'sb_publishable_6WZDE3wBMwc5ildtfy19Nw_pxdPnAZK'

const supabase = createClient(supabaseUrl, supabaseKey)

const TABLES = [
  'company_settings', 'users', 'chart_accounts', 'customers', 'suppliers',
  'products', 'invoices', 'invoice_lines', 'quotes', 'quote_lines',
  'credit_notes', 'credit_note_lines', 'purchase_invoices', 'purchase_invoice_lines',
  'bank_accounts', 'bank_transactions', 'bank_rules',
  'journal_entries', 'journal_lines', 'journals', 'vat_returns',
  'fiscal_years', 'fiscal_periods', 'entry_templates', 'third_party_accounts',
  'analytic_sections', 'budgets', 'budget_commitments', 'standard_labels',
  'projects', 'fixed_assets', 'asset_depreciations',
  'employees', 'pay_runs', 'timesheets', 'pay_slips', 'payroll_accounting_entries',
  'leave_requests', 'contracts', 'legal_declarations',
  'stock_movements', 'stock_quantities', 'warehouses',
  'currencies', 'payment_orders', 'collection_reminders',
  'sales_orders', 'sales_order_lines', 'delivery_notes', 'delivery_note_lines',
  'customer_payments', 'purchase_orders', 'purchase_order_lines',
  'goods_receipts', 'goods_receipt_lines', 'supplier_payments',
  'purchase_credit_notes', 'purchase_credit_lines',
  'price_lists', 'price_list_lines',
  'boms', 'bom_lines', 'manufacturing_orders',
  'audit_log',
]

async function runExport() {
  console.log('=== TEST EXPORT COMPLET ===\n')
  let totalRows = 0
  const results = []

  for (const table of TABLES) {
    try {
      const { data, error } = await supabase.from(table).select('*')
      if (error) {
        console.log(`  ✗ ${table}: ${error.message}`)
        results.push({ table, rows: 0, error: error.message })
        continue
      }
      const rows = data || []
      totalRows += rows.length
      const status = rows.length > 0 ? '✓' : '○'
      console.log(`  ${status} ${table}: ${rows.length} lignes`)
      results.push({ table, rows: rows.length })
    } catch (err) {
      console.log(`  ✗ ${table}: ${err.message}`)
      results.push({ table, rows: 0, error: err.message })
    }
  }

  console.log(`\n=== RÉSUMÉ ===`)
  console.log(`Tables totales: ${TABLES.length}`)
  console.log(`Tables avec données: ${results.filter(r => r.rows > 0).length}`)
  console.log(`Tables vides: ${results.filter(r => r.rows === 0 && !r.error).length}`)
  console.log(`Tables en erreur: ${results.filter(r => r.error).length}`)
  console.log(`Total lignes: ${totalRows}`)

  // Generate a sample SQL for the first table with data
  const firstWithData = results.find(r => r.rows > 0 && !r.error)
  if (firstWithData) {
    const { data } = await supabase.from(firstWithData.table).select('*').limit(2)
    if (data && data.length > 0) {
      console.log(`\n=== Aperçu SQL (${firstWithData.table}) ===`)
      const cols = Object.keys(data[0])
      for (const row of data) {
        const values = cols.map(c => {
          const v = row[c]
          if (v === null) return 'NULL'
          if (typeof v === 'number') return String(v)
          if (typeof v === 'object') return `'${JSON.stringify(v).replace(/'/g, "''")}'`
          return `'${String(v).replace(/'/g, "''")}'`
        }).join(', ')
        console.log(`INSERT INTO ${firstWithData.table} (${cols.join(', ')}) VALUES (${values});`)
      }
    }
  }

  console.log('\n=== TEST TERMINÉ ===')
}

runExport().catch(console.error)
