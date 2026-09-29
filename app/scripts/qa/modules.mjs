// ============================================================
// qa/modules.mjs — l'état des modules et de leurs données
//
// Répond à deux questions avant toute tournée :
//   1. quels modules l'application propose-t-elle, et lesquels la société a-t-elle ?
//   2. pour chacun, la société a-t-elle des données — ou l'agent ne mesurerait
//      que des écrans vides ?
//
// La liste vient de `src/components/navModules.ts` (la navigation réelle, pas
// une liste tenue à la main) ; les volumes viennent de la base, table par table,
// filtrés sur la société de la session (`.qa/session.json`).
//
// Usage : node scripts/qa/modules.mjs [--json]
// ============================================================
import fs from 'node:fs'
import path from 'node:path'
import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { loadInventory, QA_DIR } from './inventory.mjs'

const APP = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..')
const DB = process.env.QA_DB_CONTAINER || 'supabase_db_app'

// Les tables qui « portent » un module : s'il n'y a rien dedans, l'écran sera
// vide. Les modules home, dashboards et reporting n'ont pas de table propre :
// ils lisent les autres.
const SIGNATURES = {
  accounting: ['chart_accounts', 'journals', 'journal_entries', 'fiscal_years', 'fixed_assets', 'budgets', 'analytic_sections', 'tax_rates'],
  commercial: ['customers', 'quotes', 'sales_orders', 'delivery_notes', 'invoices', 'credit_notes', 'customer_payments', 'products'],
  treasury: ['bank_accounts', 'bank_transactions'],
  stock: ['warehouses', 'stock_quantities', 'stock_movements', 'stock_valuation_layers', 'purchase_orders', 'goods_receipts', 'purchase_invoices', 'supplier_payments'],
  production: ['boms', 'bom_lines', 'manufacturing_orders'],
  hr: ['employees', 'contracts', 'pay_runs', 'pay_slips', 'leave_requests', 'expense_reports', 'timesheets'],
  projectManagement: ['projects', 'project_tasks', 'project_time_entries'],
  system: ['tenant_users', 'company_settings'],
  home: [], dashboards: [], reporting: [],
}

function sql(statement) {
  return execFileSync('docker', ['exec', DB, 'psql', '-U', 'postgres', '-d', 'postgres', '-tAc', statement], { encoding: 'utf8' }).trim()
}

/** Les modules de la navigation, avec les écrans qu'ils déclarent. */
export function navModulesFromSource() {
  const src = fs.readFileSync(path.join(APP, 'src/components/navModules.ts'), 'utf8')
  const body = src.slice(src.indexOf('export const navModules'))
  const ids = [...body.matchAll(/\n    id: '([A-Za-z]+)',/g)].map((m) => ({ id: m[1], at: m.index }))
  return ids.map((entry, i) => {
    const slice = body.slice(entry.at, ids[i + 1]?.at ?? body.length)
    const paths = [...new Set([...slice.matchAll(/path: '([^']+)'/g)].map((m) => m[1]))]
    return { id: entry.id, paths }
  })
}

/** La société de la session courante et ses modules activés. */
function sessionTenant() {
  const file = path.join(QA_DIR, 'session.json')
  if (!fs.existsSync(file)) return null
  const s = JSON.parse(fs.readFileSync(file, 'utf8'))
  const raw = sql(`SELECT enabled_modules::text FROM tenants WHERE id = '${s.tenantId}'`)
  let enabled = []
  try { enabled = JSON.parse(raw) } catch { enabled = raw ? [raw] : [] }
  return { tenantId: s.tenantId, company: s.company, enabled: [...new Set(enabled)] }
}
/** Compte les lignes de la société, table par table, en tolérant les absentes. */
function countsFor(tenantId, tables) {
  if (!tables.length) return []
  const list = tables.map((t) => `'${t}'`).join(',')
  const present = new Set((sql(`SELECT string_agg(table_name, ' ') FROM information_schema.tables WHERE table_schema='public' AND table_name IN (${list})`) || '').split(' ').filter(Boolean))
  const withTenant = new Set((sql(`SELECT string_agg(table_name, ' ') FROM information_schema.columns WHERE table_schema='public' AND column_name='tenant_id' AND table_name IN (${list})`) || '').split(' ').filter(Boolean))
  return tables.map((t) => {
    if (!present.has(t)) return { table: t, rows: null, note: 'table absente du schéma' }
    const rows = Number(sql(`SELECT count(*) FROM ${t}${withTenant.has(t) ? ` WHERE tenant_id = '${tenantId}'` : ''}`))
    return { table: t, rows, note: withTenant.has(t) ? '' : 'table globale' }
  })
}

const inv = loadInventory()
const modules = navModulesFromSource()
const session = sessionTenant()
const moduleOf = (routePath) => modules.find((m) => m.paths.some((p) => routePath === p || routePath.startsWith(`${p}/`)))?.id ?? null

const report = modules.map((m) => ({
  id: m.id,
  enabled: session ? session.enabled.includes(m.id) : null,
  navScreens: m.paths.length,
  routes: inv.routes.filter((r) => moduleOf(r.path) === m.id).length,
  tables: countsFor(session?.tenantId, SIGNATURES[m.id] ?? []),
}))

fs.mkdirSync(QA_DIR, { recursive: true })
fs.writeFileSync(path.join(QA_DIR, 'modules.json'), JSON.stringify({ session, modules: report }, null, 2))

if (process.argv.includes('--json')) {
  console.log(JSON.stringify({ session, modules: report }, null, 2))
} else {
  console.log(session ? `société « ${session.company} »` : 'aucune session : lancer seed.mjs')
  console.log(`modules activés : ${session ? session.enabled.join(', ') : '—'}\n`)
  console.log('module             actif  écrans(routes)  données (lignes métier)')
  console.log('------------------------------------------------------------------')
  let total = 0
  for (const m of report) {
    const filled = m.tables.filter((t) => t.rows)
    total += filled.reduce((a, t) => a + t.rows, 0)
    const data = !m.tables.length
      ? (m.enabled ? '(module dérivé : lit les autres)' : '(non activé)')
      : (filled.length ? filled.map((t) => `${t.table}=${t.rows}`).join(' ') : '⚠ AUCUNE DONNÉE')
    console.log(`${m.id.padEnd(18)} ${String(m.enabled ?? '?').padEnd(6)} ${String(`${m.navScreens}(${m.routes})`).padEnd(15)} ${data}`)
  }
  console.log(`\n${report.length} module(s), ${report.reduce((a, m) => a + m.routes, 0)} route(s), ${total} ligne(s) métier`)
}

