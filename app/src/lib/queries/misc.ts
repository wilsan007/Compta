import { supabase, isTenantTable } from '@/lib/supabase'
import { fetchAllRows, getTenantId, nextDocumentNumber, ti, tud } from './core'
import { createJournalEntry } from './accounting'
import { createStockMovement } from './stock'
import type { Customer, Invoice, CreditNote, BankAccount, JournalEntry, FixedAsset, Journal, SalesOrder, SalesOrderLine, DeliveryNote, DeliveryNoteLine, GoodsReceipt, SalesRepresentative, Prospect, DeliverySchedule, DocumentTemplate, CreditLine, Investment, ValueDateTracking, AssetFamily, AssetRevaluation, AssetDocument, AssetFreeField, AssetBatchDisposal, AssetSplit, PaymentTerm, MarkingType, ReminderLevel, Dispute, JustificatifSolde, EtatRapprochement, RevisionCycle, ReportingPlan, StatField, FusionLog, CompactionLog, RGPDRequest, GridTemplate, ReimputationLog, BankStatementTemplate, FiscalPosition, FiscalPositionMapping, AccountTag, AccountTagMapping, DocumentCharge, DocumentTransformation } from '@/types'

// ============ Journals Report ============
export async function getJournalsReport(startDate?: string, endDate?: string) {
  const tid = await getTenantId()
  let query = supabase
    .from('journal_entries')
    .select('*, journal_lines(*)')
    .order('date', { ascending: false })
  if (tid) query = query.eq('tenant_id', tid)
  if (startDate) query = query.gte('date', startDate)
  if (endDate) query = query.lte('date', endDate)
  const { data, error } = await query
  if (error) throw error
  return data as JournalEntry[]
}


// ============ Interconnections ============

// Generate journal entries from a pay run
export async function generatePayrollJournal(payRunId: string) {
  const tid = await getTenantId()
  let prQ = supabase.from('pay_runs').select('*').eq('id', payRunId)
  if (tid) prQ = prQ.eq('tenant_id', tid)
  const { data: payRun, error: prError } = await prQ.single()
  if (prError) throw prError

  const jeNumber = 'JE-PAY-' + payRun.number
  let jeChkQ = supabase.from('journal_entries').select('id').eq('number', jeNumber)
  if (tid) jeChkQ = jeChkQ.eq('tenant_id', tid)
  const { data: existing } = await jeChkQ.maybeSingle()
  if (existing) throw new Error('Écriture de journal déjà générée pour ce bulletin')

  const lines = [
    { account_code: '641000', account_name: 'Rémunérations du personnel', description: 'Salaires bruts ' + payRun.number, debit: Number(payRun.gross_total), credit: 0, line_order: 0 },
    { account_code: '645000', account_name: 'Charges sociales', description: 'Charges sociales ' + payRun.number, debit: Number(payRun.tax_total), credit: 0, line_order: 1 },
    { account_code: '421000', account_name: 'Personnel - Rémunérations dues', description: 'Net à payer ' + payRun.number, debit: 0, credit: Number(payRun.net_total), line_order: 2 },
    { account_code: '431000', account_name: 'Sécurité sociale - Charges', description: 'Charges sociales à payer ' + payRun.number, debit: 0, credit: Number(payRun.tax_total), line_order: 3 },
  ]

  return createJournalEntry({
    number: jeNumber,
    date: payRun.pay_date,
    description: 'Écriture de paie ' + payRun.number,
    journal_type: 'purchase',
    status: 'posted',
    total_debit: Number(payRun.gross_total) + Number(payRun.tax_total),
    total_credit: Number(payRun.net_total) + Number(payRun.tax_total),
    lines,
  } as any)
}

// Calculate and update depreciation for a fixed asset
export async function calculateDepreciation(assetId: string) {
  const tid = await getTenantId()
  let faQ = supabase.from('fixed_assets').select('*').eq('id', assetId)
  if (tid) faQ = faQ.eq('tenant_id', tid)
  const { data: asset, error } = await faQ.single()
  if (error) throw error

  const purchaseValue = Number(asset.purchase_value)
  const residualValue = Number(asset.residual_value)
  const usefulLife = Number(asset.useful_life_years)
  if (usefulLife <= 0) throw new Error('Durée de vie invalide')

  const annualDepreciation = (purchaseValue - residualValue) / usefulLife
  const yearsElapsed = Math.min(
    usefulLife,
    Math.floor((Date.now() - new Date(asset.purchase_date).getTime()) / (365.25 * 86400000))
  )
  const totalDepreciation = annualDepreciation * yearsElapsed
  const currentValue = Math.max(purchaseValue - totalDepreciation, residualValue)

  const status = currentValue <= residualValue ? 'fully_depreciated' : asset.status

  const { data, error: updateError } = await tud(supabase
    .from('fixed_assets')
    .update({ current_value: currentValue, status }), 'fixed_assets', tid)
    .eq('id', assetId)
    .select()
    .single()
  if (updateError) throw updateError
  return data as FixedAsset
}

// Calculate depreciation for all active assets
export async function calculateAllDepreciation() {
  const tid = await getTenantId()
  let q = supabase
    .from('fixed_assets')
    .select('*')
    .eq('status', 'active')
    .order('id')
  if (tid) q = q.eq('tenant_id', tid)
  // LOT7-03 : dotation aux amortissements de fin d'exercice. Tronquée à 1 000, elle
  // laissait des immobilisations sans dotation, sans aucun message.
  const assets = await fetchAllRows<any>(q, { label: 'calculateAllDepreciation/fixed_assets' })

  const results: FixedAsset[] = []
  for (const asset of assets) {
    try {
      const updated = await calculateDepreciation(asset.id)
      results.push(updated)
    } catch (err) {
      console.error('Depreciation failed for asset', asset.id, err)
    }
  }
  return results
}

// Create stock movement linked to an invoice
export async function createInvoiceStockMovement(productId: string, type: 'in' | 'out', quantity: number, reference: string, invoiceId?: string) {
  const sm = await createStockMovement({
    product_id: productId,
    type,
    quantity,
    reference,
    date: new Date().toISOString().split('T')[0],
  } as any)

  if (invoiceId) {
    const tid = await getTenantId()
    const { error } = await tud(supabase
      .from('stock_movements')
      .update({ reference: `${reference} (Facture: ${invoiceId.slice(0, 8)})` }), 'stock_movements', tid)
      .eq('id', sm.id)
    if (error) console.error('Failed to link stock movement to invoice:', error)
  }

  return sm
}

// Apply purchase credit note to purchase invoice (update amounts)
export async function applyPurchaseCreditToInvoice(creditNoteId: string, invoiceId: string) {
  const tid = await getTenantId()
  let cnQ = supabase.from('purchase_credit_notes').select('*').eq('id', creditNoteId)
  if (tid) cnQ = cnQ.eq('tenant_id', tid)
  const { data: cn, error: cnError } = await cnQ.single()
  if (cnError) throw cnError

  let invQ = supabase.from('purchase_invoices').select('*').eq('id', invoiceId)
  if (tid) invQ = invQ.eq('tenant_id', tid)
  const { data: inv, error: invError } = await invQ.single()
  if (invError) throw invError

  const creditAmount = Number(cn.total)
  const newAmountPaid = Number(inv.amount_paid) + creditAmount
  const newAmountDue = Math.max(Number(inv.amount_due) - creditAmount, 0)
  const newStatus = newAmountDue <= 0 ? 'paid' : inv.status

  const { error: invUpdateError } = await tud(supabase
    .from('purchase_invoices')
    .update({ amount_paid: newAmountPaid, amount_due: newAmountDue, status: newStatus }), 'purchase_invoices', tid)
    .eq('id', invoiceId)
  if (invUpdateError) throw invUpdateError

  const { error: cnUpdateError } = await tud(supabase
    .from('purchase_credit_notes')
    .update({ status: 'applied', purchase_invoice_id: invoiceId }), 'purchase_credit_notes', tid)
    .eq('id', creditNoteId)
  if (cnUpdateError) throw cnUpdateError

  return { invoice: { id: invoiceId, amount_due: newAmountDue, status: newStatus }, creditNote: { id: creditNoteId, status: 'applied' } }
}


// ============ Journals (codes journaux) ============
export async function getJournals() {
  const tid = await getTenantId()
  let q = supabase.from('journals').select('*').order('code', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as Journal[]
}

export async function createJournal(journal: Omit<Journal, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('journals').insert(ti(journal, 'journals', tid)).select().single()
  if (error) throw error
  return data as Journal
}

export async function updateJournal(id: string, updates: Partial<Journal>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('journals').update(updates), 'journals', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Journal
}

export async function deleteJournal(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('journals').delete(), 'journals', tid).eq('id', id)
  if (error) throw error
}


// ============ Sprint 6: Goods Receipts ============
export async function getGoodsReceipts(status?: string) {
  const tid = await getTenantId()
  let q = supabase.from('goods_receipts').select('*').order('receipt_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (status) q = q.eq('status', status)
  const { data, error } = await q
  if (error) throw error
  return data as GoodsReceipt[]
}

export async function createGoodsReceipt(gr: Omit<GoodsReceipt, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('goods_receipts').insert(ti(gr, 'goods_receipts', tid)).select().single()
  if (error) throw error
  return data as GoodsReceipt
}

export async function updateGoodsReceipt(id: string, updates: Partial<GoodsReceipt>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('goods_receipts').update(updates), 'goods_receipts', tid).eq('id', id).select().single()
  if (error) throw error
  return data as GoodsReceipt
}

export async function deleteGoodsReceipt(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('goods_receipts').delete(), 'goods_receipts', tid).eq('id', id)
  if (error) throw error
}


// ============ Full Data Export ============
export const EXPORT_TABLES = [
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

export interface ExportResult {
  tableName: string
  rowCount: number
  columns: string[]
  rows: Record<string, any>[]
}

export async function exportAllData(): Promise<{ tables: ExportResult[]; exportedAt: string; totalRows: number }> {
  const tid = await getTenantId()
  const tables: ExportResult[] = []
  let totalRows = 0

  for (const table of EXPORT_TABLES) {
    try {
      let q = supabase.from(table).select('*')
      if (tid && isTenantTable(table)) q = q.eq('tenant_id', tid)
      const { data, error } = await q
      if (error) {
        console.warn(`Export: skipping table ${table}:`, error.message)
        tables.push({ tableName: table, rowCount: 0, columns: [], rows: [] })
        continue
      }
      const rows = data || []
      const columns = rows.length > 0 ? Object.keys(rows[0]) : []
      tables.push({ tableName: table, rowCount: rows.length, columns, rows })
      totalRows += rows.length
    } catch (err) {
      console.warn(`Export: error on table ${table}:`, err)
      tables.push({ tableName: table, rowCount: 0, columns: [], rows: [] })
    }
  }

  return { tables, exportedAt: new Date().toISOString(), totalRows }
}

function escapeSqlValue(val: any): string {
  if (val === null || val === undefined) return 'NULL'
  if (typeof val === 'number') return String(val)
  if (typeof val === 'boolean') return val ? 'TRUE' : 'FALSE'
  if (typeof val === 'object') return `'${JSON.stringify(val).replace(/\\/g, '\\\\').replace(/'/g, "''").replaceAll('\0', '')}'`
  const str = String(val).replace(/\\/g, '\\\\').replace(/'/g, "''").replaceAll('\0', '')
  return `'${str}'`
}

function quoteIdentifier(name: string): string {
  return '"' + String(name).replace(/"/g, '""').replaceAll('\0', '') + '"'
}

export function generateSqlDump(tables: ExportResult[], exportedAt: string): string {
  const lines: string[] = []
  lines.push(`-- ============================================`)
  lines.push(`-- EXPORT COMPLET DES DONNEES`)
  lines.push(`-- Date: ${exportedAt}`)
  lines.push(`-- Source: Supabase (compta app)`)
  lines.push(`-- Total: ${tables.reduce((s, t) => s + t.rowCount, 0)} lignes`)
  lines.push(`-- ============================================`)
  lines.push('')
  lines.push('-- Metadonnees de sync')
  lines.push(`CREATE TABLE IF NOT EXISTS sync_metadata (`)
  lines.push(`  table_name text,`)
  lines.push(`  last_sync_at timestamptz,`)
  lines.push(`  row_count integer,`)
  lines.push(`  source text`)
  lines.push(`);`)
  lines.push('')

  for (const table of tables) {
    const quotedTable = quoteIdentifier(table.tableName)
    lines.push(`-- Table: ${table.tableName} (${table.rowCount} lignes)`)
    lines.push(`INSERT INTO sync_metadata (table_name, last_sync_at, row_count, source) VALUES ('${table.tableName.replace(/'/g, "''")}', '${exportedAt}', ${table.rowCount}, 'supabase');`)
    lines.push('')

    if (table.rowCount === 0) {
      lines.push(`-- ${table.tableName}: aucune donnee`)
      lines.push('')
      continue
    }

    const cols = table.columns.map(c => quoteIdentifier(c)).join(', ')
    for (const row of table.rows) {
      const values = table.columns.map(c => escapeSqlValue(row[c])).join(', ')
      lines.push(`INSERT INTO ${quotedTable} (${cols}) VALUES (${values});`)
    }
    lines.push('')
  }

  lines.push('-- ============================================')
  lines.push("-- FIN DE L'EXPORT")
  lines.push('-- ============================================')
  return lines.join('\n')
}

export function generateCsvForTable(table: ExportResult): string {
  if (table.rowCount === 0) return ''
  const headers = table.columns.join(';')
  const rows = table.rows.map(row =>
    table.columns.map(c => {
      const val = row[c]
      if (val === null || val === undefined) return ''
      if (typeof val === 'object') return `"${JSON.stringify(val).replace(/"/g, '""')}"`
      let str = String(val)
      // SECURITY: Prevent CSV formula injection
      if (/^[=+\-@]/.test(str)) str = '\t' + str
      str = str.replace(/"/g, '""')
      return str.includes(';') || str.includes('\n') || str.includes('\t') ? `"${str}"` : str
    }).join(';')
  )
  return [headers, ...rows].join('\n')
}


// ============ Mirror Server Management ============
export interface MirrorServer {
  id: string
  tenant_id: string
  machine_id: string
  machine_name: string
  os: string | null
  ip_address: string | null
  mirror_dir: string | null
  registered_at: string
  last_heartbeat: string
  status: 'active' | 'inactive' | 'revoked'
  config: Record<string, any> | null
}

export async function registerMirrorServer(data: {
  tenant_id: string
  machine_id: string
  machine_name: string
  os?: string
  ip_address?: string
  mirror_dir?: string
  config?: Record<string, any>
}): Promise<{ success: boolean; error?: string; server?: MirrorServer }> {
  const { data: existing, error: checkError } = await supabase
    .from('mirror_servers')
    .select('*')
    .eq('tenant_id', data.tenant_id)
    .eq('status', 'active')
    .maybeSingle()

  if (checkError) {
    return { success: false, error: checkError.message }
  }

  if (existing && existing.machine_id !== data.machine_id) {
    return {
      success: false,
      error: `Un serveur miroir est déjà enregistré pour ce tenant sur la machine "${existing.machine_name}". Un seul serveur miroir par tenant est autorisé. Révoquez-le d'abord pour enregistrer un nouveau.`,
    }
  }

  if (existing && existing.machine_id === data.machine_id) {
    const { data: updated, error: updateError } = await supabase
      .from('mirror_servers')
      .update({
        machine_name: data.machine_name,
        os: data.os || null,
        ip_address: data.ip_address || null,
        mirror_dir: data.mirror_dir || null,
        last_heartbeat: new Date().toISOString(),
        status: 'active',
        config: data.config || null,
      })
      .eq('id', existing.id)
      .select()
      .single()
    if (updateError) return { success: false, error: updateError.message }
    return { success: true, server: updated as MirrorServer }
  }

  const { data: created, error: insertError } = await supabase
    .from('mirror_servers')
    .insert({
      tenant_id: data.tenant_id,
      machine_id: data.machine_id,
      machine_name: data.machine_name,
      os: data.os || null,
      ip_address: data.ip_address || null,
      mirror_dir: data.mirror_dir || null,
      status: 'active',
      config: data.config || null,
    })
    .select()
    .single()

  if (insertError) {
    if (insertError.code === '23505') {
      return { success: false, error: 'Un serveur miroir est déjà enregistré pour ce tenant.' }
    }
    return { success: false, error: insertError.message }
  }

  return { success: true, server: created as MirrorServer }
}

export async function getMirrorServer(tenantId: string): Promise<MirrorServer | null> {
  const { data, error } = await supabase
    .from('mirror_servers')
    .select('*')
    .eq('tenant_id', tenantId)
    .maybeSingle()
  if (error) {
    console.error('Error getting mirror server:', error)
    return null
  }
  return data as MirrorServer | null
}

export async function updateMirrorHeartbeat(machineId: string): Promise<void> {
  await supabase
    .from('mirror_servers')
    .update({ last_heartbeat: new Date().toISOString() })
    .eq('machine_id', machineId)
}

export async function revokeMirrorServer(tenantId: string): Promise<{ error?: string }> {
  // SECURITY: Verify caller is an admin of the target tenant
  const guard = await requireAdminOfTenant(tenantId)
  if (!guard.ok) return { error: guard.error }

  const { error } = await supabase
    .from('mirror_servers')
    .update({ status: 'revoked' })
    .eq('tenant_id', tenantId)
  if (error) return { error: error.message }
  return {}
}


// ============ Mirror Server Installation Flow ============

export async function preRegisterMirrorServer(data: {
  tenant_id: string
  install_platform: 'mac' | 'windows' | 'linux'
}): Promise<{ success: boolean; error?: string; install_token?: string }> {
  // SECURITY: Verify caller is an admin of the target tenant
  const guard = await requireAdminOfTenant(data.tenant_id)
  if (!guard.ok) return { success: false, error: guard.error }

  const { data: existing } = await supabase
    .from('mirror_servers')
    .select('*')
    .eq('tenant_id', data.tenant_id)
    .in('status', ['active'])
    .maybeSingle()

  if (existing && existing.install_status === 'verified') {
    return { success: false, error: 'Un serveur miroir vérifié est déjà installé pour ce tenant.' }
  }

  const installToken = crypto.randomUUID()

  if (existing) {
    const { error } = await supabase
      .from('mirror_servers')
      .update({
        install_status: 'pending',
        install_token: installToken,
        install_platform: data.install_platform,
      })
      .eq('id', existing.id)
    if (error) return { success: false, error: error.message }
  } else {
    const { error } = await supabase
      .from('mirror_servers')
      .insert({
        tenant_id: data.tenant_id,
        machine_id: 'pending-' + installToken,
        machine_name: 'En attente d\'installation',
        status: 'active',
        install_status: 'pending',
        install_token: installToken,
        install_platform: data.install_platform,
      })
    if (error) return { success: false, error: error.message }
  }

  return { success: true, install_token: installToken }
}

export async function getMirrorServerStatus(tenantId: string): Promise<{
  exists: boolean
  install_status?: string
  install_platform?: string
  machine_name?: string
  verified_at?: string
  verification_data?: Record<string, any>
  last_heartbeat?: string
}> {
  const { data, error } = await supabase
    .from('mirror_servers')
    .select('*')
    .eq('tenant_id', tenantId)
    .maybeSingle()

  if (error) { console.error('checkMirrorServerExists:', error); return { exists: false } }
  if (!data) return { exists: false }

  return {
    exists: true,
    install_status: data.install_status,
    install_platform: data.install_platform,
    machine_name: data.machine_name,
    verified_at: data.verified_at,
    verification_data: data.verification_data,
    last_heartbeat: data.last_heartbeat,
  }
}

export async function getMirrorVerificationDetails(serverId: string): Promise<any[]> {
  const { data, error } = await supabase
    .from('mirror_verification_details')
    .select('*')
    .eq('mirror_server_id', serverId)
    .order('table_name')
  if (error) { console.error('getMirrorVerificationDetails:', error); return [] }
  return data || []
}

export function generateMacInstaller(config: {
  supabaseUrl: string
  supabaseKey: string
  tenantId: string
  installToken: string
}): string {
  return `#!/bin/bash
# Installateur du serveur miroir Compta - macOS
# Généré automatiquement depuis la plateforme

set -e

INSTALL_DIR="$HOME/compta-mirror"
TENANT_ID="${config.tenantId}"
SUPABASE_URL="${config.supabaseUrl}"
SUPABASE_KEY="${config.supabaseKey}"
INSTALL_TOKEN="${config.installToken}"

echo "======================================================"
echo "  INSTALLATION SERVEUR MIROIR COMPTA - macOS          "
echo "======================================================"
echo ""

# Vérifier Node.js
if ! command -v node &> /dev/null; then
  echo "ERREUR: Node.js n'est pas installé."
  echo "Installez-le depuis: https://nodejs.org (version 18+)"
  exit 1
fi
NODE_PATH=$(which node)
echo "Node.js: $NODE_PATH ($(node --version))"

# Créer le dossier
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
echo "Dossier: $INSTALL_DIR"

# Écrire la configuration
cat > config.json << EOF
{
  "supabaseUrl": "$SUPABASE_URL",
  "supabaseKey": "$SUPABASE_KEY",
  "mirrorDir": "./mirror-data",
  "pollIntervalMs": 300000,
  "syncOnStart": true,
  "tenantId": "$TENANT_ID",
  "installToken": "$INSTALL_TOKEN"
}
EOF

# Écrire package.json
cat > package.json << EOF
{
  "name": "compta-mirror-daemon",
  "version": "1.0.0",
  "type": "module",
  "dependencies": { "@supabase/supabase-js": "^2.45.0" }
}
EOF

echo "Installation des dépendances..."
npm install --production 2>&1 | tail -3

# Télécharger le daemon depuis le bucket de stockage Supabase
echo "Téléchargement du daemon..."
DAEMON_URL="$SUPABASE_URL/storage/v1/object/public/mirror-daemon/daemon.mjs"
curl -sfL "$DAEMON_URL" -o daemon.mjs || {
  echo "ERREUR: Impossible de télécharger daemon.mjs depuis $DAEMON_URL"
  echo "Veuillez télécharger manuellement le fichier daemon.mjs et le placer dans $INSTALL_DIR/"
  exit 1
}

# Enregistrer + première sync + vérification
echo ""
echo "=== Enregistrement et synchronisation ==="
node daemon.mjs --register --force --once --verbose

if [ $? -ne 0 ]; then
  echo "ERREUR: L'installation a échoué."
  exit 1
fi

# Configurer launchd
PLIST_LABEL="com.compta.mirror-daemon"
PLIST_PATH="$HOME/Library/LaunchAgents/\${PLIST_LABEL}.plist"
mkdir -p "$(dirname "$PLIST_PATH")"

cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>\${PLIST_LABEL}</string>
  <key>ProgramArguments</key><array>
    <string>\${NODE_PATH}</string>
    <string>\${INSTALL_DIR}/daemon.mjs</string>
  </array>
  <key>WorkingDirectory</key><string>\${INSTALL_DIR}</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>\${INSTALL_DIR}/daemon.log</string>
  <key>StandardErrorPath</key><string>\${INSTALL_DIR}/daemon-error.log</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"

echo ""
echo "======================================================"
echo "  INSTALLATION TERMINÉE ET VÉRIFIÉE                   "
echo "  Le daemon est actif. Données dans:                  "
echo "  $INSTALL_DIR/mirror-data/                           "
echo "  Démarrage automatique au boot.                      "
echo "======================================================"
`
}

export function generateWindowsInstaller(config: {
  supabaseUrl: string
  supabaseKey: string
  tenantId: string
  installToken: string
}): string {
  return `# Installateur du serveur miroir Compta - Windows (PowerShell)
# Genere automatiquement depuis la plateforme
# Usage: Right-click > Run with PowerShell

$ErrorActionPreference = "Stop"

$INSTALL_DIR = "$env:USERPROFILE\\compta-mirror"
$TENANT_ID = "${config.tenantId}"
$SUPABASE_URL = "${config.supabaseUrl}"
$SUPABASE_KEY = "${config.supabaseKey}"
$INSTALL_TOKEN = "${config.installToken}"

Write-Host "======================================================="
Write-Host "  INSTALLATION SERVEUR MIROIR COMPTA - Windows        "
Write-Host "======================================================="
Write-Host ""

# Verifier Node.js
$nodePath = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $nodePath) {
    Write-Host "ERREUR: Node.js n'est pas installe." -ForegroundColor Red
    Write-Host "Installez-le depuis: https://nodejs.org (version 18+)"
    exit 1
}
Write-Host "Node.js: $nodePath ($(node --version))"

# Creer le dossier
New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null
Set-Location $INSTALL_DIR
Write-Host "Dossier: $INSTALL_DIR"

# Ecrire la configuration
$conf = @{
    supabaseUrl = $SUPABASE_URL
    supabaseKey = $SUPABASE_KEY
    mirrorDir = "./mirror-data"
    pollIntervalMs = 300000
    syncOnStart = $true
    tenantId = $TENANT_ID
    installToken = $INSTALL_TOKEN
} | ConvertTo-Json
$conf | Out-File -FilePath "config.json" -Encoding utf8

# Ecrire package.json
$pkg = @{
    name = "compta-mirror-daemon"
    version = "1.0.0"
    type = "module"
    dependencies = @{ "@supabase/supabase-js" = "^2.45.0" }
} | ConvertTo-Json
$pkg | Out-File -FilePath "package.json" -Encoding utf8

Write-Host "Installation des dependances..."
npm install --production 2>&1 | Select-Object -Last 3

# Telecharger le daemon depuis le bucket de stockage Supabase
Write-Host "Telechargement du daemon..."
$daemonUrl = "$SUPABASE_URL/storage/v1/object/public/mirror-daemon/daemon.mjs"
try {
    Invoke-WebRequest -Uri $daemonUrl -OutFile "daemon.mjs" -ErrorAction Stop
} catch {
    Write-Host "ERREUR: Impossible de telecharger daemon.mjs depuis $daemonUrl" -ForegroundColor Red
    Write-Host "Veuillez telecharger manuellement le fichier daemon.mjs et le placer dans $INSTALL_DIR/"
    exit 1
}

# Enregistrer + premiere sync + verification
Write-Host ""
Write-Host "=== Enregistrement et synchronisation ==="
node daemon.mjs --register --force --once --verbose

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERREUR: L'installation a echoue." -ForegroundColor Red
    exit 1
}

# Creer la tache planifiee Windows
$action = New-ScheduledTaskAction -Execute $nodePath -Argument "daemon.mjs" -WorkingDirectory $INSTALL_DIR
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName "ComptaMirrorDaemon" -Action $action -Trigger $trigger -Settings $settings -Force

Write-Host ""
Write-Host "======================================================="
Write-Host "  INSTALLATION TERMINEE ET VERIFIEE                   "
Write-Host "  Tache planifiee: ComptaMirrorDaemon                  "
Write-Host "  Donnees dans: $INSTALL_DIR\\mirror-data\\           "
Write-Host "======================================================="
`
}


// ============ Multi-Tenant Management ============

export interface Tenant {
  id: string
  name: string
  legal_name: string | null
  siren: string | null
  siret: string | null
  vat_number: string | null
  address: string | null
  city: string | null
  postal_code: string | null
  country: string
  currency: string
  phone: string | null
  email: string | null
  logo_url: string | null
  status: string
  plan: string
  trial_ends_at: string | null
  enabled_modules: string[]
  created_at: string
  legislation_pack_code?: string | null
}

export interface TenantUser {
  id: string
  tenant_id: string
  auth_id: string | null
  email: string
  name: string
  role: 'admin' | 'accountant' | 'manager' | 'viewer' | 'custom' | 'auditor'
  permissions: Record<string, string[]>
  module_roles?: Record<string, string>
  guest_permissions?: Record<string, any>
  status: 'pending' | 'active' | 'revoked'
  invited_by: string | null
  invited_at: string
  accepted_at: string | null
  last_login: string | null
  created_at: string
  valid_from: string | null
  valid_until: string | null
}

export async function createTenantForUser(data: {
  name: string
  legal_name?: string
  siren?: string
  vat_number?: string
  address?: string
  city?: string
  postal_code?: string
  country?: string
  currency?: string
  email?: string
  phone?: string
  legislation_pack_code?: string
  enabled_modules?: string[]
}): Promise<{ success: boolean; error?: string; tenant?: Tenant }> {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return { success: false, error: 'Non connecté' }

  const authId = session.user.id
  const userEmail = session.user.email || data.email || ''
  // Use the user's actual name from auth metadata, NOT the company name
  const userDisplayName = (session.user.user_metadata?.name as string) || session.user.user_metadata?.full_name || userEmail

  const { data: tenant, error: tenantErr } = await supabase
    .from('tenants')
    .insert({
      name: data.name,
      legal_name: data.legal_name || data.name,
      siren: data.siren || null,
      vat_number: data.vat_number || null,
      address: data.address || null,
      city: data.city || null,
      postal_code: data.postal_code || null,
      country: data.country || 'France',
      currency: data.currency || 'EUR',
      email: data.email || userEmail,
      phone: data.phone || null,
      legislation_pack_code: data.legislation_pack_code || null,
      country_code: data.legislation_pack_code || null,
      enabled_modules: data.enabled_modules || ['home', 'accounting', 'commercial', 'treasury', 'stock', 'production', 'hr', 'dashboards', 'reporting', 'system'],
      status: 'active',
      plan: 'trial',
      trial_ends_at: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
    })
    .select()
    .single()

  if (tenantErr) return { success: false, error: tenantErr.message }

  const { error: tuErr } = await supabase
    .from('tenant_users')
    .insert({
      tenant_id: tenant.id,
      auth_id: authId,
      email: userEmail,
      name: userDisplayName,
      role: 'admin',
      permissions: {},
      status: 'active',
      accepted_at: new Date().toISOString(),
    })

  if (tuErr) {
    await supabase.from('tenants').delete().eq('id', tenant.id)
    return { success: false, error: tuErr.message }
  }

  // Also create an employee record for the tenant admin
  const { error: empErr } = await supabase
    .from('employees')
    .insert({
      tenant_id: tenant.id,
      name: userDisplayName,
      email: userEmail,
      position: 'Admin',
      department: 'Direction',
      hire_date: new Date().toISOString().split('T')[0],
      status: 'active',
    })
  if (empErr) {
    console.error('Failed to create employee record for admin:', empErr.message)
    // Non-fatal: tenant is still created
  }

  // Seed reference data (chart of accounts, journals, currencies, fiscal year,
  // company settings) so the app is immediately usable. Non-fatal: if it fails,
  // the tenant still exists and the user can import/create data manually.
  const { error: bootstrapErr } = await supabase.rpc('bootstrap_tenant', { p_tenant_id: tenant.id })
  if (bootstrapErr) {
    console.error('bootstrap_tenant failed:', bootstrapErr.message)
  }

  return { success: true, tenant: tenant as Tenant }
}

export async function createSiteForCurrentTenant(data: {
  siteName: string
  address: string
}): Promise<{ success: boolean; error?: string; tenant?: Tenant }> {
  const current = await getCurrentTenant()
  if (!current) return { success: false, error: 'Aucun tenant actif' }

  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return { success: false, error: 'Non connecté' }

  const authId = session.user.id
  const userEmail = session.user.email || current.email || ''
  const userDisplayName = (session.user.user_metadata?.name as string) || session.user.user_metadata?.full_name || userEmail

  const { data: tenant, error: tenantErr } = await supabase
    .from('tenants')
    .insert({
      name: data.siteName,
      legal_name: current.legal_name || data.siteName,
      siren: current.siren,
      siret: null,
      vat_number: current.vat_number,
      address: data.address,
      city: current.city,
      postal_code: current.postal_code,
      country: current.country,
      currency: current.currency,
      email: current.email,
      phone: current.phone,
      legislation_pack_code: current.legislation_pack_code || null,
      country_code: current.legislation_pack_code || null,
      enabled_modules: current.enabled_modules,
      status: 'active',
      plan: current.plan,
      trial_ends_at: current.trial_ends_at,
    })
    .select()
    .single()

  if (tenantErr) return { success: false, error: tenantErr.message }

  const { error: tuErr } = await supabase
    .from('tenant_users')
    .insert({
      tenant_id: tenant.id,
      auth_id: authId,
      email: userEmail,
      name: userDisplayName,
      role: 'admin',
      permissions: {},
      status: 'active',
      accepted_at: new Date().toISOString(),
    })

  if (tuErr) {
    await supabase.from('tenants').delete().eq('id', tenant.id)
    return { success: false, error: tuErr.message }
  }

  const { error: empErr } = await supabase
    .from('employees')
    .insert({
      tenant_id: tenant.id,
      name: userDisplayName,
      email: userEmail,
      position: 'Admin',
      department: 'Direction',
      hire_date: new Date().toISOString().split('T')[0],
      status: 'active',
    })
  if (empErr) {
    console.error('Failed to create employee record for site admin:', empErr.message)
  }

  const { error: bootstrapErr } = await supabase.rpc('bootstrap_tenant', { p_tenant_id: tenant.id })
  if (bootstrapErr) {
    console.error('bootstrap_tenant failed:', bootstrapErr.message)
  }

  return { success: true, tenant: tenant as Tenant }
}

export async function getCurrentTenant(): Promise<Tenant | null> {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return null

  const { data, error } = await supabase
    .from('tenant_users')
    .select('tenant_id, tenants(*)')
    .eq('auth_id', session.user.id)
    .eq('status', 'active')

  if (error) { console.error('getActiveTenant:', error); return null }
  if (!data || data.length === 0) return null
  const stored = localStorage.getItem('active_tenant_id')
  const match = data.find(tu => tu.tenant_id === stored) || data[0]
  return (match as any).tenants as Tenant
}

export async function getCurrentTenantUser(): Promise<TenantUser | null> {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return null

  const { data, error } = await supabase
    .from('tenant_users')
    .select('*')
    .eq('auth_id', session.user.id)
    .eq('status', 'active')

  if (error) { console.error('getActiveTenantUser:', error); return null }
  if (!data || data.length === 0) return null
  const stored = localStorage.getItem('active_tenant_id')
  const match = data.find(tu => tu.tenant_id === stored) || data[0]
  return match as TenantUser
}

export async function getTenantEnabledModules(): Promise<string[]> {
  const tenant = await getCurrentTenant()
  const DEFAULT_MODS = ['home', 'accounting', 'commercial', 'treasury', 'stock', 'production', 'hr', 'projectManagement', 'dashboards', 'reporting', 'system']
  if (!tenant) return DEFAULT_MODS
  const mods = tenant.enabled_modules || DEFAULT_MODS
  // Ensure new modules are included if tenant has a saved list
  if (!mods.includes('projectManagement')) return [...mods, 'projectManagement']
  return mods
}

async function requireAdminOfTenant(tenantId: string): Promise<{ ok: boolean; error?: string }> {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return { ok: false, error: 'Non connecté' }
  const { data: tu } = await supabase
    .from('tenant_users')
    .select('role, status, tenant_id')
    .eq('auth_id', session.user.id)
    .eq('status', 'active')
    .eq('tenant_id', tenantId)
    .maybeSingle()
  if (!tu) return { ok: false, error: 'Utilisateur non trouvé' }
  if (tu.role !== 'admin') return { ok: false, error: 'Action réservée aux administrateurs' }
  return { ok: true }
}

export async function updateTenantModules(tenantId: string, modules: string[]): Promise<{ success: boolean; error?: string }> {
  const guard = await requireAdminOfTenant(tenantId)
  if (!guard.ok) return { success: false, error: guard.error }
  const { error } = await supabase
    .from('tenants')
    .update({ enabled_modules: modules, updated_at: new Date().toISOString() })
    .eq('id', tenantId)
  if (error) return { success: false, error: error.message }
  return { success: true }
}

export async function getTenantUsers(tenantId: string): Promise<TenantUser[]> {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) throw new Error('Non connecté')
  const tid = await getTenantId()
  if (!tid || tid !== tenantId) throw new Error('Accès non autorisé à ce tenant')

  const { data, error } = await supabase
    .from('tenant_users')
    .select('*')
    .eq('tenant_id', tenantId)
    .order('created_at', { ascending: false })

  if (error) throw error
  return (data || []) as TenantUser[]
}

export async function inviteUser(data: {
  tenantId: string
  email: string
  name: string
  role: TenantUser['role']
  permissions?: Record<string, string[]>
  moduleRoles?: Record<string, string>
  guestPermissions?: Record<string, any>
  invitedBy?: string
  validFrom?: string | null
  validUntil?: string | null
}): Promise<{ success: boolean; error?: string; message?: string }> {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return { success: false, error: 'Non connecté' }

  // Defense-in-depth: verify caller is admin of this tenant before calling edge function
  const guard = await requireAdminOfTenant(data.tenantId)
  if (!guard.ok) return { success: false, error: guard.error }

  // Get current locale for email localization
  const locale = localStorage.getItem('i18nextLng')?.split('-')[0] || 'en'

  try {
    const { data: result, error } = await supabase.functions.invoke('create-user', {
      body: {
        email: data.email,
        name: data.name,
        role: data.role,
        permissions: data.permissions || {},
        module_roles: data.moduleRoles || {},
        guest_permissions: data.guestPermissions || {},
        tenant_id: data.tenantId,
        invited_by: data.invitedBy || null,
        locale,
        valid_from: data.validFrom || null,
        valid_until: data.validUntil || null,
      },
    })

    if (error) {
      // Try to extract the error message from the function response body
      let msg = error.message
      try {
        const ctx = (error as any).context
        if (ctx && typeof ctx.json === 'function') {
          const body = await ctx.json()
          if (body?.error) msg = body.error
        }
      } catch { /* keep default message */ }
      return { success: false, error: msg || 'Erreur lors de la création' }
    }

    if (result?.error) {
      return { success: false, error: result.error }
    }

    return { success: true, message: result?.message }
  } catch (err: any) {
    return { success: false, error: err.message || 'Erreur réseau' }
  }
}

export async function updateUserRole(
  tenantUserId: string,
  role: TenantUser['role'],
  permissions?: Record<string, string[]>,
  moduleRoles?: Record<string, string>,
  guestPermissions?: Record<string, any>
): Promise<{ success: boolean; error?: string }> {
  const tid = await getTenantId()
  if (!tid) return { success: false, error: 'Aucun tenant actif' }
  const guard = await requireAdminOfTenant(tid)
  if (!guard.ok) return { success: false, error: guard.error }

  const update: Record<string, any> = { role }
  if (permissions !== undefined) update.permissions = permissions
  if (moduleRoles !== undefined) update.module_roles = moduleRoles
  if (guestPermissions !== undefined) update.guest_permissions = guestPermissions

  const { error } = await supabase
    .from('tenant_users')
    .update(update)
    .eq('id', tenantUserId)
    .eq('tenant_id', tid)

  if (error) return { success: false, error: error.message }
  return { success: true }
}

export async function revokeUser(tenantUserId: string): Promise<{ success: boolean; error?: string }> {
  const tid = await getTenantId()
  if (!tid) return { success: false, error: 'Aucun tenant actif' }
  const guard = await requireAdminOfTenant(tid)
  if (!guard.ok) return { success: false, error: guard.error }

  const { error } = await supabase
    .from('tenant_users')
    .update({ status: 'revoked' })
    .eq('id', tenantUserId)
    .eq('tenant_id', tid)

  if (error) return { success: false, error: error.message }
  return { success: true }
}

export async function reactivateUser(tenantUserId: string): Promise<{ success: boolean; error?: string }> {
  const tid = await getTenantId()
  if (!tid) return { success: false, error: 'Aucun tenant actif' }
  const guard = await requireAdminOfTenant(tid)
  if (!guard.ok) return { success: false, error: guard.error }

  const { error } = await supabase
    .from('tenant_users')
    .update({ status: 'active' })
    .eq('id', tenantUserId)
    .eq('tenant_id', tid)

  if (error) return { success: false, error: error.message }
  return { success: true }
}

export async function reinviteUser(tenantUserId: string, email: string): Promise<{ success: boolean; error?: string; emailSent?: boolean }> {
  const tid = await getTenantId()
  if (!tid) return { success: false, error: 'Aucun tenant actif' }
  const guard = await requireAdminOfTenant(tid)
  if (!guard.ok) return { success: false, error: guard.error }

  const { error: updateError } = await supabase
    .from('tenant_users')
    .update({ status: 'pending' })
    .eq('id', tenantUserId)
    .eq('tenant_id', tid)

  if (updateError) return { success: false, error: updateError.message }

  let emailSent = false
  try {
    const redirectTo = `${window.location.origin}/accept-invitation?tenant=${tid}`
    const locale = localStorage.getItem('i18nextLng')?.split('-')[0] || 'en'
    const otpOptions: Record<string, any> = { emailRedirectTo: redirectTo }
    if (['fr', 'en', 'ar'].includes(locale)) {
      otpOptions.lang = locale
    }
    const { error: inviteError } = await supabase.auth.signInWithOtp({
      email,
      options: otpOptions,
    })
    emailSent = !inviteError
  } catch (e) {
    // Email service might not be configured
    console.error('inviteUser: email send failed:', e)
  }

  return { success: true, emailSent }
}

// Called after an invited user clicks the magic link and lands on /accept-invitation.
// Links the authenticated auth.users id to the pending tenant_users row, activates it,
// and optionally sets a password so the user can log in with email/password later.
export async function acceptInvitation(
  password?: string,
  tenantId?: string
): Promise<{ success: boolean; error?: string; tenantName?: string; otherPendingInvites?: { tenantId: string; tenantName: string }[] }> {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return { success: false, error: 'Lien invalide ou expiré. Redemandez une invitation.' }

  const authId = session.user.id
  const email = session.user.email
  if (!email) return { success: false, error: 'Email introuvable dans la session.' }

  // Find all pending/active invitations for this email
  // SECURITY: Use .limit(10) instead of .maybeSingle() to handle multiple tenant invitations
  const { data: invitations, error: findError } = await supabase
    .from('tenant_users')
    .select('id, tenant_id, status, auth_id, tenants:tenant_id (name)')
    .eq('email', email)
    .neq('status', 'revoked')
    .order('accepted_at', { ascending: false, nullsFirst: true })
    .limit(10)

  if (findError) return { success: false, error: findError.message }
  if (!invitations || invitations.length === 0) {
    return { success: false, error: "Aucune invitation trouvée pour cet email." }
  }

  // If tenantId is provided (from magic link URL), target that specific invitation
  // Otherwise fall back to: 1) matching auth_id, 2) null auth_id (pending), 3) first
  let tenantUser
  if (tenantId) {
    tenantUser = invitations.find(i => i.tenant_id === tenantId)
  }
  if (!tenantUser) {
    tenantUser = invitations.find(i => i.auth_id === authId)
      || invitations.find(i => !i.auth_id)
      || invitations[0]
  }

  // Security: if the invitation already has a different auth_id, refuse
  if (tenantUser.auth_id && tenantUser.auth_id !== authId) {
    return { success: false, error: 'Cette invitation est associée à un autre compte.' }
  }

  // Link auth_id + activate
  // CRITICAL: filter by status='pending' to prevent race condition where
  // a revoked user could reactivate themselves between lookup and update
  const { error: updateError } = await supabase
    .from('tenant_users')
    .update({
      auth_id: authId,
      status: 'active',
      accepted_at: new Date().toISOString(),
      last_login: new Date().toISOString(),
    })
    .eq('id', tenantUser.id)
    .eq('email', email)
    .in('status', ['pending', 'active'])

  if (updateError) return { success: false, error: updateError.message }

  // Optionally set a password — enforce strong password policy
  if (password) {
    if (password.length < 8 || !/[A-Z]/.test(password) || !/[a-z]/.test(password) || !/[0-9]/.test(password)) {
      return { success: false, error: 'Le mot de passe doit contenir au moins 8 caractères, une majuscule, une minuscule et un chiffre.' }
    }
    const { error: pwError } = await supabase.auth.updateUser({ password })
    if (pwError) return { success: false, error: `Compte activé mais mot de passe non défini: ${pwError.message}` }
  }

  const tenantName = (tenantUser as any).tenants?.name || null

  // Collect other pending invitations so the UI can offer them to the user
  const otherPendingInvites = invitations
    .filter(i => i.tenant_id !== tenantUser.tenant_id && i.status === 'pending')
    .map(i => ({ tenantId: i.tenant_id, tenantName: (i as any).tenants?.name || i.tenant_id }))

  return { success: true, tenantName, otherPendingInvites }
}

export function hasPermission(
  user: TenantUser | null,
  table: string,
  action: 'select' | 'insert' | 'update' | 'delete'
): boolean {
  if (!user) return false
  if (user.role === 'admin') return true
  if (user.role === 'accountant') {
    if (action === 'select' || action === 'insert' || action === 'update') return true
    if (action === 'delete' && ['journal_entries', 'journal_lines', 'invoice_lines', 'quote_lines', 'credit_note_lines'].includes(table)) return true
    return false
  }
  if (user.role === 'manager') {
    if (action === 'select') return true
    if (action === 'insert' || action === 'update') {
      const commercialTables = ['invoices', 'invoice_lines', 'quotes', 'quote_lines', 'credit_notes', 'credit_note_lines', 'customers', 'products', 'delivery_notes', 'delivery_note_lines', 'sales_orders', 'sales_order_lines', 'purchase_orders', 'purchase_order_lines', 'document_charges', 'document_transformations', 'product_grids', 'product_grid_combinations', 'product_packagings', 'product_links', 'promotions', 'warehouse_users', 'stock_alerts', 'crm_opportunities', 'crm_activities', 'crm_campaigns', 'crm_campaign_recipients', 'crm_territories', 'crm_forecasts', 'service_tickets', 'service_ticket_messages', 'service_contracts', 'knowledge_base_articles', 'saved_filters']
      return commercialTables.includes(table)
    }
    return false
  }
  if (user.role === 'viewer') return action === 'select'
  if (user.role === 'auditor') return action === 'select'
  if (user.role === 'custom') {
    const perms = user.permissions[table]
    if (!perms) return false
    return perms.includes(action)
  }
  return false
}

export const PERMISSION_TABLES = [
  { name: 'invoices' },
  { name: 'quotes' },
  { name: 'customers' },
  { name: 'suppliers' },
  { name: 'products' },
  { name: 'purchase_invoices' },
  { name: 'purchase_orders' },
  { name: 'journal_entries' },
  { name: 'bank_transactions' },
  { name: 'chart_accounts' },
  { name: 'budgets' },
  { name: 'fiscal_years' },
  { name: 'vat_returns' },
  { name: 'employees' },
  { name: 'pay_runs' },
  { name: 'company_settings' },
  { name: 'projects' },
  { name: 'warehouses' },
  { name: 'stock_movements' },
  { name: 'audit_log' },
] as const

export const PERMISSION_ACTIONS = [
  { value: 'select' },
  { value: 'insert' },
  { value: 'update' },
  { value: 'delete' },
] as const


// ============ EDI-TVA Submission ============
export async function submitEdiTva(vatReturnId: string) {
  const tid = await getTenantId()
  const ediId = `EDI-${Date.now()}`
  const { data, error } = await supabase
    .from('vat_returns')
    .update({
      edi_tva_id: ediId,
      edi_status: 'submitted',
      edi_submitted_at: new Date().toISOString(),
    })
    .eq('id', vatReturnId)
    .eq('tenant_id', tid ?? '')
    .select()
    .single()
  if (error) throw error
  return data
}


// ============ Phase 2: Sales Representatives ============
export async function getSalesRepresentatives() {
  const tid = await getTenantId()
  let q = supabase.from('sales_representatives').select('*').order('name')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as SalesRepresentative[]
}
export async function createSalesRepresentative(r: Omit<SalesRepresentative, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('sales_representatives').insert(ti(r, 'sales_representatives', tid)).select().single()
  if (error) throw error
  return data as SalesRepresentative
}
export async function updateSalesRepresentative(id: string, updates: Partial<SalesRepresentative>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('sales_representatives').update(updates), 'sales_representatives', tid).eq('id', id).select().single()
  if (error) throw error
  return data as SalesRepresentative
}
export async function deleteSalesRepresentative(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('sales_representatives').delete(), 'sales_representatives', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 2: Prospects ============
export async function getProspects() {
  const tid = await getTenantId()
  let q = supabase.from('prospects').select('*, sales_representatives(name)').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}
export async function createProspect(p: Omit<Prospect, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('prospects').insert(ti(p, 'prospects', tid)).select().single()
  if (error) throw error
  return data as Prospect
}
export async function updateProspect(id: string, updates: Partial<Prospect>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('prospects').update(updates), 'prospects', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Prospect
}
export async function deleteProspect(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('prospects').delete(), 'prospects', tid).eq('id', id)
  if (error) throw error
}
export async function convertProspectToCustomer(id: string, customerData: Partial<Customer>) {
  const tid = await getTenantId()
  const { data: cust, error: custErr } = await supabase.from('customers').insert(ti(customerData as any, 'customers', tid)).select().single()
  if (custErr) throw custErr
  await tud(supabase.from('prospects').update({ status: 'converted', converted_customer_id: cust.id }), 'prospects', tid).eq('id', id)
  return cust as Customer
}


// ============ Phase 2: Delivery Schedules ============
export async function getDeliverySchedules() {
  const tid = await getTenantId()
  let q = supabase.from('delivery_schedules').select('*, customers(name), products(name, sku)').order('start_date')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}
export async function createDeliverySchedule(d: Omit<DeliverySchedule, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('delivery_schedules').insert(ti(d, 'delivery_schedules', tid)).select().single()
  if (error) throw error
  return data as DeliverySchedule
}
export async function deleteDeliverySchedule(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('delivery_schedules').delete(), 'delivery_schedules', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 2: Document Templates ============
export async function getDocumentTemplates() {
  const tid = await getTenantId()
  let q = supabase.from('document_templates').select('*').order('name')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as DocumentTemplate[]
}
export async function createDocumentTemplate(t: Omit<DocumentTemplate, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('document_templates').insert(ti(t, 'document_templates', tid)).select().single()
  if (error) throw error
  return data as DocumentTemplate
}
export async function updateDocumentTemplate(id: string, updates: Partial<DocumentTemplate>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('document_templates').update(updates), 'document_templates', tid).eq('id', id).select().single()
  if (error) throw error
  return data as DocumentTemplate
}
export async function deleteDocumentTemplate(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('document_templates').delete(), 'document_templates', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 3: Credit Lines ============
export async function getCreditLines() {
  const tid = await getTenantId()
  let q = supabase.from('credit_lines').select('*, bank_accounts(name)').order('name')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}
export async function createCreditLine(c: Omit<CreditLine, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('credit_lines').insert(ti(c, 'credit_lines', tid)).select().single()
  if (error) throw error
  return data as CreditLine
}
export async function updateCreditLine(id: string, updates: Partial<CreditLine>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('credit_lines').update(updates), 'credit_lines', tid).eq('id', id).select().single()
  if (error) throw error
  return data as CreditLine
}
export async function deleteCreditLine(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('credit_lines').delete(), 'credit_lines', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 3: Investments ============
export async function getInvestments() {
  const tid = await getTenantId()
  let q = supabase.from('investments').select('*').order('name')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as Investment[]
}
export async function createInvestment(i: Omit<Investment, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('investments').insert(ti(i, 'investments', tid)).select().single()
  if (error) throw error
  return data as Investment
}
export async function updateInvestment(id: string, updates: Partial<Investment>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('investments').update(updates), 'investments', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Investment
}
export async function deleteInvestment(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('investments').delete(), 'investments', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 3: Value Date Tracking ============
export async function getValueDateTrackings() {
  const tid = await getTenantId()
  let q = supabase.from('value_date_tracking').select('*, bank_accounts(name)').order('value_date')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}
export async function createValueDateTracking(v: Omit<ValueDateTracking, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('value_date_tracking').insert(ti(v, 'value_date_tracking', tid)).select().single()
  if (error) throw error
  return data as ValueDateTracking
}


// ============ Phase 5: Asset Families ============
export async function getAssetFamilies() {
  const tid = await getTenantId()
  let q = supabase.from('asset_families').select('*').order('code')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as AssetFamily[]
}
export async function createAssetFamily(f: Omit<AssetFamily, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('asset_families').insert(ti(f, 'asset_families', tid)).select().single()
  if (error) throw error
  return data as AssetFamily
}
export async function updateAssetFamily(id: string, updates: Partial<AssetFamily>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('asset_families').update(updates), 'asset_families', tid).eq('id', id).select().single()
  if (error) throw error
  return data as AssetFamily
}
export async function deleteAssetFamily(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('asset_families').delete(), 'asset_families', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 5: Asset Revaluations ============
export async function getAssetRevaluations(assetId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('asset_revaluations').select('*, fixed_assets(name)').order('revaluation_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (assetId) q = q.eq('asset_id', assetId)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}
export async function createAssetRevaluation(r: Omit<AssetRevaluation, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('asset_revaluations').insert(ti(r, 'asset_revaluations', tid)).select().single()
  if (error) throw error
  return data as AssetRevaluation
}


// ============ Phase 5: Asset Documents ============
export async function getAssetDocuments(assetId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('asset_documents').select('*, fixed_assets(name)')
  if (tid) q = q.eq('tenant_id', tid)
  if (assetId) q = q.eq('asset_id', assetId)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}
export async function createAssetDocument(d: Omit<AssetDocument, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('asset_documents').insert(ti(d, 'asset_documents', tid)).select().single()
  if (error) throw error
  return data as AssetDocument
}
export async function deleteAssetDocument(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('asset_documents').delete(), 'asset_documents', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 5: Asset Free Fields ============
export async function getAssetFreeFields(assetId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('asset_free_fields').select('*')
  if (tid) q = q.eq('tenant_id', tid)
  if (assetId) q = q.eq('asset_id', assetId)
  const { data, error } = await q
  if (error) throw error
  return data as AssetFreeField[]
}
export async function createAssetFreeField(f: Omit<AssetFreeField, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('asset_free_fields').insert(ti(f, 'asset_free_fields', tid)).select().single()
  if (error) throw error
  return data as AssetFreeField
}


// ============ Phase 5: Asset Batch Disposals ============
export async function getAssetBatchDisposals() {
  const tid = await getTenantId()
  let q = supabase.from('asset_batch_disposals').select('*').order('disposal_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as AssetBatchDisposal[]
}
export async function createAssetBatchDisposal(b: Omit<AssetBatchDisposal, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('asset_batch_disposals').insert(ti(b, 'asset_batch_disposals', tid)).select().single()
  if (error) throw error
  return data as AssetBatchDisposal
}
export async function updateAssetBatchDisposal(id: string, updates: Partial<AssetBatchDisposal>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('asset_batch_disposals').update(updates), 'asset_batch_disposals', tid).eq('id', id).select().single()
  if (error) throw error
  return data as AssetBatchDisposal
}


// ============ Phase 5: Asset Splits ============
export async function getAssetSplits() {
  const tid = await getTenantId()
  let q = supabase.from('asset_splits').select('*, fixed_assets(name)').order('split_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}
export async function createAssetSplit(s: Omit<AssetSplit, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('asset_splits').insert(ti(s, 'asset_splits', tid)).select().single()
  if (error) throw error
  return data as AssetSplit
}


// ============ Fiscal Positions (#32, #56) ============

export async function getFiscalPositions(): Promise<FiscalPosition[]> {
  const tid = await getTenantId()
  let q = supabase.from('fiscal_positions').select('*').order('name', { ascending: true })
  if (tid) q = q.or(`tenant_id.is.null,tenant_id.eq.${tid}`)
  const { data, error } = await q
  if (error) throw error
  return data as FiscalPosition[]
}

export async function createFiscalPosition(fp: Omit<FiscalPosition, 'id' | 'created_at' | 'tenant_id'>): Promise<FiscalPosition> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('fiscal_positions').insert({ ...fp, tenant_id: tid }).select().single()
  if (error) throw error
  return data as FiscalPosition
}

export async function updateFiscalPosition(id: string, updates: Partial<FiscalPosition>): Promise<FiscalPosition> {
  const tid = await getTenantId()
  let q = supabase.from('fiscal_positions').update(updates).eq('id', id)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.select().single()
  if (error) throw error
  return data as FiscalPosition
}

export async function deleteFiscalPosition(id: string): Promise<void> {
  const tid = await getTenantId()
  let q = supabase.from('fiscal_positions').delete().eq('id', id)
  if (tid) q = q.eq('tenant_id', tid)
  const { error } = await q
  if (error) throw error
}


// ============ Fiscal Position Mappings (#56) ============

export async function getFiscalPositionMappings(fiscalPositionId: string): Promise<FiscalPositionMapping[]> {
  const tid = await getTenantId()
  let q = supabase.from('fiscal_position_mappings').select('*').eq('fiscal_position_id', fiscalPositionId).order('created_at', { ascending: true })
  if (tid) q = q.or(`tenant_id.is.null,tenant_id.eq.${tid}`)
  const { data, error } = await q
  if (error) throw error
  return data as FiscalPositionMapping[]
}

export async function createFiscalPositionMapping(m: Omit<FiscalPositionMapping, 'id' | 'created_at' | 'tenant_id'>): Promise<FiscalPositionMapping> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('fiscal_position_mappings').insert({ ...m, tenant_id: tid }).select().single()
  if (error) throw error
  return data as FiscalPositionMapping
}

export async function deleteFiscalPositionMapping(id: string): Promise<void> {
  const tid = await getTenantId()
  let q = supabase.from('fiscal_position_mappings').delete().eq('id', id)
  if (tid) q = q.eq('tenant_id', tid)
  const { error } = await q
  if (error) throw error
}


// ============ Account Tags (#22) ============

export async function getAccountTags(): Promise<AccountTag[]> {
  const tid = await getTenantId()
  let q = supabase.from('account_tags').select('*').order('name', { ascending: true })
  if (tid) q = q.or(`tenant_id.is.null,tenant_id.eq.${tid}`)
  const { data, error } = await q
  if (error) throw error
  return data as AccountTag[]
}

export async function createAccountTag(tag: Omit<AccountTag, 'id' | 'created_at' | 'tenant_id'>): Promise<AccountTag> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('account_tags').insert({ ...tag, tenant_id: tid }).select().single()
  if (error) throw error
  return data as AccountTag
}

export async function deleteAccountTag(id: string): Promise<void> {
  const tid = await getTenantId()
  let q = supabase.from('account_tags').delete().eq('id', id)
  if (tid) q = q.eq('tenant_id', tid)
  const { error } = await q
  if (error) throw error
}

export async function updateAccountTag(id: string, updates: Partial<AccountTag>): Promise<AccountTag> {
  const tid = await getTenantId()
  let q = supabase.from('account_tags').update(updates).eq('id', id)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.select().single()
  if (error) throw error
  return data as AccountTag
}


// ============ Account Tag Mappings (#22) ============

export async function getAccountTagMappings(tagId?: string, entityType?: string, entityId?: string): Promise<AccountTagMapping[]> {
  const tid = await getTenantId()
  let q = supabase.from('account_tag_mappings').select('*').order('created_at', { ascending: false })
  if (tid) q = q.or(`tenant_id.is.null,tenant_id.eq.${tid}`)
  if (tagId) q = q.eq('tag_id', tagId)
  if (entityType) q = q.eq('entity_type', entityType)
  if (entityId) q = q.eq('entity_id', entityId)
  const { data, error } = await q
  if (error) throw error
  return data as AccountTagMapping[]
}

export async function createAccountTagMapping(m: Omit<AccountTagMapping, 'id' | 'created_at' | 'tenant_id'>): Promise<AccountTagMapping> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('account_tag_mappings').insert({ ...m, tenant_id: tid }).select().single()
  if (error) throw error
  return data as AccountTagMapping
}

export async function deleteAccountTagMapping(id: string): Promise<void> {
  const tid = await getTenantId()
  let q = supabase.from('account_tag_mappings').delete().eq('id', id)
  if (tid) q = q.eq('tenant_id', tid)
  const { error } = await q
  if (error) throw error
}


// ============ Marking Types (Types de marquage) ============

export async function getMarkingTypes(): Promise<MarkingType[]> {
  const tid = await getTenantId()
  let q = supabase.from('marking_types').select('*').order('code', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as MarkingType[]
}

export async function createMarkingType(mt: Omit<MarkingType, 'id' | 'tenant_id' | 'created_at' | 'updated_at'>): Promise<MarkingType> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('marking_types').insert({ ...mt, tenant_id: tid }).select().single()
  if (error) throw error
  return data as MarkingType
}

export async function deleteMarkingType(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('marking_types').delete(), 'marking_types', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 7B: Reminder Levels ============

export async function getReminderLevels(): Promise<ReminderLevel[]> {
  const tid = await getTenantId()
  let q = supabase.from('reminder_levels').select('*').order('level', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as ReminderLevel[]
}

export async function createReminderLevel(rl: Omit<ReminderLevel, 'id' | 'created_at' | 'updated_at' | 'tenant_id'>): Promise<ReminderLevel> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('reminder_levels').insert({ ...rl, tenant_id: tid }).select().single()
  if (error) throw error
  return data as ReminderLevel
}

export async function updateReminderLevel(id: string, updates: Partial<ReminderLevel>): Promise<ReminderLevel> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('reminder_levels').update(updates), 'reminder_levels', tid).eq('id', id).select().single()
  if (error) throw error
  return data as ReminderLevel
}

export async function deleteReminderLevel(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('reminder_levels').delete(), 'reminder_levels', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 7B: Disputes ============

export async function getDisputes(): Promise<Dispute[]> {
  const tid = await getTenantId()
  let q = supabase.from('disputes').select('*').order('opened_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as Dispute[]
}

export async function createDispute(d: Omit<Dispute, 'id' | 'created_at' | 'updated_at' | 'tenant_id'>): Promise<Dispute> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('disputes').insert({ ...d, tenant_id: tid }).select().single()
  if (error) throw error
  return data as Dispute
}

export async function updateDispute(id: string, updates: Partial<Dispute>): Promise<Dispute> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('disputes').update(updates), 'disputes', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Dispute
}

export async function deleteDispute(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('disputes').delete(), 'disputes', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 7B: Multi-Echeance Generation ============

export function generateMultiEcheances(
  date: string,
  paymentTerm: PaymentTerm
): { date: string; amount_pct: number; label: string }[] {
  const baseDate = new Date(date)
  const echeances: { date: string; amount_pct: number; label: string }[] = []

  if (paymentTerm.type === 'fixed' || paymentTerm.type === 'end_of_month') {
    const echeance = new Date(baseDate)
    echeance.setDate(echeance.getDate() + paymentTerm.days_1)
    if (paymentTerm.type === 'end_of_month') {
      echeance.setMonth(echeance.getMonth() + 1, 0)
    }
    echeances.push({
      date: echeance.toISOString().slice(0, 10),
      amount_pct: 100,
      label: `Échéance ${paymentTerm.code}`,
    })
  } else if (paymentTerm.type === 'split') {
    const pct1 = paymentTerm.pct_1 || 50
    const pct2 = paymentTerm.pct_2 || 50
    const echeance1 = new Date(baseDate)
    echeance1.setDate(echeance1.getDate() + paymentTerm.days_1)
    echeances.push({
      date: echeance1.toISOString().slice(0, 10),
      amount_pct: pct1,
      label: `Échéance 1 (${pct1}%)`,
    })
    if (paymentTerm.days_2) {
      const echeance2 = new Date(baseDate)
      echeance2.setDate(echeance2.getDate() + paymentTerm.days_2)
      echeances.push({
        date: echeance2.toISOString().slice(0, 10),
        amount_pct: pct2,
        label: `Échéance 2 (${pct2}%)`,
      })
    }
  }

  return echeances
}


// ============ Phase 7B: Justificatif de Solde ============

export async function generateJustificatifSolde(
  accountCode: string,
  thirdPartyCode: string | null,
  fiscalPeriodId: string | null
): Promise<JustificatifSolde> {
  const tid = await getTenantId()
  let q = supabase.from('journal_lines').select('debit, credit')
  if (tid) q = q.eq('tenant_id', tid)
  q = q.eq('account_code', accountCode)
  if (thirdPartyCode) q = q.eq('account_tiers', thirdPartyCode)
  if (fiscalPeriodId) {
    const { data: fp } = await supabase.from('fiscal_periods').select('start_date, end_date').eq('id', fiscalPeriodId).single()
    if (fp) {
      q = q.gte('line_date', fp.start_date).lte('line_date', fp.end_date)
    }
  }
  const { data: lines, error } = await q
  if (error) throw error

  const totalDebit = (lines || []).reduce((s: number, l: any) => s + (Number(l.debit) || 0), 0)
  const totalCredit = (lines || []).reduce((s: number, l: any) => s + (Number(l.credit) || 0), 0)
  const closingBalance = totalDebit - totalCredit

  const record = {
    account_code: accountCode,
    third_party_code: thirdPartyCode,
    fiscal_period_id: fiscalPeriodId,
    opening_balance: 0,
    total_debit: totalDebit,
    total_credit: totalCredit,
    closing_balance: closingBalance,
    generated_by: null,
  }

  const { data, error: insertError } = await supabase.from('justificatif_solde').insert({ ...record, tenant_id: tid }).select().single()
  if (insertError) throw insertError
  return data as JustificatifSolde
}

export async function getJustificatifsSolde(): Promise<JustificatifSolde[]> {
  const tid = await getTenantId()
  let q = supabase.from('justificatif_solde').select('*').order('generated_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as JustificatifSolde[]
}


// ============ Phase 7B: Etat Rapprochement ============

export async function generateEtatRapprochement(
  accountCode: string,
  bankAccountId: string | null,
  periodStart: string,
  periodEnd: string
): Promise<EtatRapprochement> {
  const tid = await getTenantId()
  let q = supabase.from('journal_lines').select('debit, credit')
  if (tid) q = q.eq('tenant_id', tid)
  q = q.eq('account_code', accountCode)
  q = q.gte('line_date', periodStart).lte('line_date', periodEnd)
  const { data: lines, error } = await q
  if (error) throw error

  const bookBalance = (lines || []).reduce((s: number, l: any) => s + (Number(l.debit) || 0) - (Number(l.credit) || 0), 0)

  let bankBalance = 0
  if (bankAccountId) {
    let bq = supabase.from('bank_transactions').select('amount')
    if (tid) bq = bq.eq('tenant_id', tid)
    bq = bq.eq('bank_account_id', bankAccountId)
    bq = bq.gte('transaction_date', periodStart).lte('transaction_date', periodEnd)
    const { data: txns, error: txnError } = await bq
    if (txnError) throw txnError
    bankBalance = (txns || []).reduce((s: number, t: any) => s + (Number(t.amount) || 0), 0)
  }

  const record = {
    bank_account_id: bankAccountId,
    account_code: accountCode,
    period_start: periodStart,
    period_end: periodEnd,
    bank_balance: bankBalance,
    book_balance: bookBalance,
    difference: bankBalance - bookBalance,
    reconciled_items: 0,
    unreconciled_items: 0,
    generated_by: null,
  }

  const { data, error: insertError } = await supabase.from('etat_rapprochement').insert({ ...record, tenant_id: tid }).select().single()
  if (insertError) throw insertError
  return data as EtatRapprochement
}

export async function getEtatsRapprochement(): Promise<EtatRapprochement[]> {
  const tid = await getTenantId()
  let q = supabase.from('etat_rapprochement').select('*').order('generated_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as EtatRapprochement[]
}


// ============ Phase 7B: Mark line with marking code ============

export async function markLineWithCode(lineId: string, markingCode: string | null): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(
    supabase.from('journal_lines').update({ marking_code: markingCode }),
    'journal_lines', tid
  ).eq('id', lineId)
  if (error) throw error
}


// ============ Phase 7C: Revision Cycles ============

export async function getRevisionCycles(): Promise<RevisionCycle[]> {
  const tid = await getTenantId()
  let q = supabase.from('revision_cycles').select('*').order('name', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as RevisionCycle[]
}

export async function createRevisionCycle(rc: Omit<RevisionCycle, 'id' | 'created_at' | 'updated_at' | 'tenant_id'>): Promise<RevisionCycle> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('revision_cycles').insert({ ...rc, tenant_id: tid }).select().single()
  if (error) throw error
  return data as RevisionCycle
}

export async function updateRevisionCycle(id: string, updates: Partial<RevisionCycle>): Promise<RevisionCycle> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('revision_cycles').update(updates), 'revision_cycles', tid).eq('id', id).select().single()
  if (error) throw error
  return data as RevisionCycle
}

export async function deleteRevisionCycle(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('revision_cycles').delete(), 'revision_cycles', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 7C: Reporting Plans ============

export async function getReportingPlans(): Promise<ReportingPlan[]> {
  const tid = await getTenantId()
  let q = supabase.from('reporting_plans').select('*').order('name', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as ReportingPlan[]
}

export async function createReportingPlan(rp: Omit<ReportingPlan, 'id' | 'created_at' | 'updated_at' | 'tenant_id'>): Promise<ReportingPlan> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('reporting_plans').insert({ ...rp, tenant_id: tid }).select().single()
  if (error) throw error
  return data as ReportingPlan
}

export async function updateReportingPlan(id: string, updates: Partial<ReportingPlan>): Promise<ReportingPlan> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('reporting_plans').update(updates), 'reporting_plans', tid).eq('id', id).select().single()
  if (error) throw error
  return data as ReportingPlan
}

export async function deleteReportingPlan(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('reporting_plans').delete(), 'reporting_plans', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 7C: Stat Fields ============

export async function getStatFields(entityType?: string, entityId?: string): Promise<StatField[]> {
  const tid = await getTenantId()
  let q = supabase.from('stat_fields').select('*').order('field_name', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  if (entityType) q = q.eq('entity_type', entityType)
  if (entityId) q = q.eq('entity_id', entityId)
  const { data, error } = await q
  if (error) throw error
  return data as StatField[]
}

export async function createStatField(sf: Omit<StatField, 'id' | 'created_at' | 'updated_at' | 'tenant_id'>): Promise<StatField> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('stat_fields').insert({ ...sf, tenant_id: tid }).select().single()
  if (error) throw error
  return data as StatField
}

export async function deleteStatField(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('stat_fields').delete(), 'stat_fields', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 7C: Fusion de comptes ============

export async function getFusionLogs(): Promise<FusionLog[]> {
  const tid = await getTenantId()
  let q = supabase.from('fusion_logs').select('*').order('fused_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as FusionLog[]
}

export async function fuseAccounts(sourceCode: string, targetCode: string): Promise<FusionLog> {
  const tid = await getTenantId()
  // Move all journal_lines from source to target
  const { data: moved, error: moveError } = await tud(
    supabase.from('journal_lines').update({ account_code: targetCode, account_general: targetCode }),
    'journal_lines', tid
  ).eq('account_general', sourceCode).select('id')
  if (moveError) throw moveError
  const linesMoved = moved?.length || 0

  // Log the fusion
  const { data, error: insertError } = await supabase.from('fusion_logs').insert({
    source_account_code: sourceCode,
    target_account_code: targetCode,
    lines_moved: linesMoved,
    fused_by: null,
    tenant_id: tid,
  }).select().single()
  if (insertError) throw insertError
  return data as FusionLog
}


// ============ Phase 7C: Compaction ============

export async function getCompactionLogs(): Promise<CompactionLog[]> {
  const tid = await getTenantId()
  let q = supabase.from('compaction_logs').select('*').order('compacted_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as CompactionLog[]
}

export async function createCompactionLog(cl: Omit<CompactionLog, 'id' | 'compacted_at' | 'tenant_id'>): Promise<CompactionLog> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('compaction_logs').insert({ ...cl, tenant_id: tid }).select().single()
  if (error) throw error
  return data as CompactionLog
}

export async function updateCompactionLog(id: string, updates: Partial<CompactionLog>): Promise<CompactionLog> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('compaction_logs').update(updates), 'compaction_logs', tid).eq('id', id).select().single()
  if (error) throw error
  return data as CompactionLog
}


// ============ Phase 7C: RGPD Requests ============

export async function getRGPDRequests(): Promise<RGPDRequest[]> {
  const tid = await getTenantId()
  let q = supabase.from('rgpd_requests').select('*').order('requested_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as RGPDRequest[]
}

export async function createRGPDRequest(rr: Omit<RGPDRequest, 'id' | 'requested_at' | 'tenant_id'>): Promise<RGPDRequest> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('rgpd_requests').insert({ ...rr, tenant_id: tid }).select().single()
  if (error) throw error
  return data as RGPDRequest
}

export async function updateRGPDRequest(id: string, updates: Partial<RGPDRequest>): Promise<RGPDRequest> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('rgpd_requests').update(updates), 'rgpd_requests', tid).eq('id', id).select().single()
  if (error) throw error
  return data as RGPDRequest
}


// ============ Phase 7D: Grid Templates (Modèles de grille) ============

export async function getGridTemplates(): Promise<GridTemplate[]> {
  const tid = await getTenantId()
  let q = supabase.from('grid_templates').select('*').order('code')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as GridTemplate[]
}

export async function createGridTemplate(gt: Omit<GridTemplate, 'id' | 'created_at' | 'updated_at' | 'tenant_id'>): Promise<GridTemplate> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('grid_templates').insert({ ...gt, tenant_id: tid }).select().single()
  if (error) throw error
  return data as GridTemplate
}

export async function updateGridTemplate(id: string, updates: Partial<GridTemplate>): Promise<GridTemplate> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('grid_templates').update(updates), 'grid_templates', tid).eq('id', id).select().single()
  if (error) throw error
  return data as GridTemplate
}

export async function deleteGridTemplate(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('grid_templates').delete(), 'grid_templates', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 7D: Reimputation Logs (Réimputation) ============

export async function getReimputationLogs(): Promise<ReimputationLog[]> {
  const tid = await getTenantId()
  let q = supabase.from('reimputation_logs').select('*').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as ReimputationLog[]
}

export async function createReimputationLog(rl: Omit<ReimputationLog, 'id' | 'created_at' | 'tenant_id'>): Promise<ReimputationLog> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('reimputation_logs').insert({ ...rl, tenant_id: tid }).select().single()
  if (error) throw error
  return data as ReimputationLog
}


// ============ Template Validation Logic ============
// Flow: user validates AI results. If no corrections → consecutive_successes++.
// When consecutive_successes >= 2 → status = 'validated'.
// If corrections made → consecutive_successes = 0, status stays 'pending'.

export async function getTemplateByBankId(bankId: string): Promise<BankStatementTemplate | null> {
  // First try own tenant's template
  const tid = await getTenantId()
  let q = supabase.from('bank_statement_templates').select('*').eq('bank_id', bankId).eq('is_active', true)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.order('updated_at', { ascending: false }).limit(1)
  if (error) throw error
  if (data && data.length > 0) return data[0] as BankStatementTemplate

  // Fallback: any validated template from any tenant (shared knowledge)
  const { data: validated, error: vErr } = await supabase
    .from('bank_statement_templates')
    .select('*')
    .eq('bank_id', bankId)
    .eq('validation_status', 'validated')
    .eq('is_active', true)
    .order('updated_at', { ascending: false })
    .limit(1)
  if (vErr) throw vErr
  return (validated && validated.length > 0) ? validated[0] as BankStatementTemplate : null
}

export async function validateTemplateResult(templateId: string, hadCorrections: boolean, correctionNotes?: string): Promise<BankStatementTemplate> {
  const tid = await getTenantId()
  // Fetch current state
  const { data: current, error: fetchErr } = await supabase
    .from('bank_statement_templates')
    .select('consecutive_successes, validation_count, validation_status')
    .eq('id', templateId)
    .single()
  if (fetchErr || !current) throw fetchErr || new Error('Template not found')

  const cur = current as any
  let newConsecutive: number
  let newStatus: string

  if (hadCorrections) {
    newConsecutive = 0
    newStatus = 'pending'
  } else {
    newConsecutive = (cur.consecutive_successes || 0) + 1
    newStatus = newConsecutive >= 2 ? 'validated' : 'pending'
  }

  const updates = {
    consecutive_successes: newConsecutive,
    validation_count: (cur.validation_count || 0) + 1,
    validation_status: newStatus,
    last_validated_at: new Date().toISOString(),
    last_correction_notes: hadCorrections ? (correctionNotes || null) : null,
  }

  const { data, error } = await tud(
    supabase.from('bank_statement_templates').update(updates),
    'bank_statement_templates',
    tid
  ).eq('id', templateId).select().single()
  if (error) throw error
  return data as BankStatementTemplate
}


// ============ #30 — Credit limit check ============
export async function checkCreditLimit(tpaCode: string): Promise<{ exceeded: boolean; balance: number; limit: number | null }> {
  const tid = await getTenantId()
  let q = supabase.from('third_party_accounts').select('balance, credit_limit').eq('code', tpaCode)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.single()
  if (error) { console.error('checkCreditLimit:', error); return { exceeded: false, balance: 0, limit: null } }
  if (!data) return { exceeded: false, balance: 0, limit: null }
  const balance = Number(data.balance || 0)
  const limit = data.credit_limit != null ? Number(data.credit_limit) : null
  return { exceeded: limit != null && balance > limit, balance, limit }
}


// ============ #26 — Export to Excel (CSV) ============
export function exportToExcel(filename: string, headers: string[], rows: (string | number)[][]) {
  const escapeCsv = (val: string | number) => {
    const s = String(val ?? '')
    if (s.includes(',') || s.includes('"') || s.includes('\n')) {
      return `"${s.replace(/"/g, '""')}"`
    }
    return s
  }
  const csv = [headers.map(escapeCsv).join(','), ...rows.map(r => r.map(escapeCsv).join(','))].join('\n')
  const blob = new Blob(['\ufeff' + csv], { type: 'text/csv;charset=utf-8;' })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = `${filename}.csv`
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
  URL.revokeObjectURL(url)
}


// ============ Statement Balance Update (#70) ============
export async function updateStatementBalance(accountId: string, statementBalance: number, statementDate: string) {
  const tid = await getTenantId()
  const { data: account, error: accErr } = await supabase.from('bank_accounts').select('calculated_balance').eq('id', accountId).single()
  if (accErr) throw accErr
  const calculated = Number(account?.calculated_balance || 0)
  const diff = statementBalance - calculated
  const { data, error } = await tud(
    supabase.from('bank_accounts').update({
      statement_balance: statementBalance,
      statement_balance_date: statementDate,
      reconciliation_diff: diff,
    }),
    'bank_accounts', tid
  ).eq('id', accountId).select().single()
  if (error) throw error
  return data as BankAccount
}


// ============ IBAN Validation (#80) ============
export function validateIBAN(iban: string): boolean {
  const cleaned = iban.replace(/\s/g, '').toUpperCase()
  if (!/^[A-Z]{2}[0-9]{2}[A-Z0-9]{1,30}$/.test(cleaned)) return false
  const rearranged = cleaned.slice(4) + cleaned.slice(0, 4)
  const converted = rearranged.replace(/[A-Z]/g, (ch) => String(ch.charCodeAt(0) - 55))
  let remainder: number
  let block = converted
  while (block.length > 9) {
    remainder = Number(block.slice(0, 9)) % 97
    block = remainder.toString() + block.slice(9)
  }
  return Number(block) % 97 === 1
}


// ============ Sprint A: Commercial Transformations ============

// --- Document Charges ---
export async function getDocumentCharges(documentType: string, documentId: string) {
  const tid = await getTenantId()
  let q = supabase.from('document_charges').select('*').eq('document_type', documentType).eq('document_id', documentId).order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as DocumentCharge[]
}

export async function addDocumentCharge(charge: Omit<DocumentCharge, 'id' | 'tenant_id' | 'created_at'>) {
  const tid = await getTenantId()
  const vatAmount = Number(charge.amount) * (Number(charge.vat_rate) / 100)
  const totalAmount = Number(charge.amount) + vatAmount
  const { data, error } = await supabase
    .from('document_charges')
    .insert({ ...charge, vat_amount: vatAmount, total_amount: totalAmount, tenant_id: tid })
    .select()
    .single()
  if (error) throw error
  return data as DocumentCharge
}

export async function deleteDocumentCharge(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('document_charges').delete(), 'document_charges', tid).eq('id', id)
  if (error) throw error
}

// --- Document Transformations ---
export async function getDocumentTransformations(sourceType?: string, sourceId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('document_transformations').select('*').order('transformed_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (sourceType) q = q.eq('source_type', sourceType)
  if (sourceId) q = q.eq('source_id', sourceId)
  const { data, error } = await q
  if (error) throw error
  return data as DocumentTransformation[]
}

async function recordTransformation(sourceType: string, sourceId: string, targetType: string, targetId: string, transformationType: 'full' | 'partial', notes?: string) {
  const tid = await getTenantId()
  const { error } = await supabase
    .from('document_transformations')
    .insert({ tenant_id: tid, source_type: sourceType, source_id: sourceId, target_type: targetType, target_id: targetId, transformation_type: transformationType, notes: notes || null })
  if (error) throw error
}

// --- Transform Quote to Sales Order ---
export async function transformQuoteToSalesOrder(quoteId: string) {
  const tid = await getTenantId()
  const { data: quote, error: qErr } = await supabase.from('quotes').select('*, quote_lines(*)').eq('id', quoteId).single()
  if (qErr) throw qErr

  const orderNumber = await nextDocumentNumber('CMD')
  const { data: order, error: oErr } = await supabase
    .from('sales_orders')
    .insert({ tenant_id: tid, number: orderNumber, customer_id: quote.customer_id, order_date: new Date().toISOString().split('T')[0], delivery_date: null, status: 'confirmed', subtotal: Number(quote.subtotal), vat: Number(quote.vat_total), total: Number(quote.total), notes: quote.notes, quote_id: quoteId })
    .select()
    .single()
  if (oErr) throw oErr

  for (const line of quote.quote_lines || []) {
    const { error: lErr } = await supabase
      .from('sales_order_lines')
      .insert({ tenant_id: tid, sales_order_id: order.id, product_id: line.product_id, description: line.description, quantity: Number(line.quantity), unit_price: Number(line.unit_price), vat_rate: Number(line.vat_rate), line_total: Number(line.total), delivered_quantity: 0 })
    if (lErr) throw lErr
  }

  await tud(supabase.from('quotes').update({ transformed_to_order_id: order.id, transformation_status: 'transformed' }), 'quotes', tid).eq('id', quoteId)
  await recordTransformation('quote', quoteId, 'sales_order', order.id, 'full')
  return order as SalesOrder
}

// --- Transform Sales Order to Delivery Note ---
export async function transformSalesOrderToDeliveryNote(orderId: string, lines: { sales_order_line_id: string; quantity: number }[]) {
  const tid = await getTenantId()
  const { data: order, error: oErr } = await supabase.from('sales_orders').select('*, sales_order_lines(*)').eq('id', orderId).single()
  if (oErr) throw oErr

  const dnNumber = await nextDocumentNumber('BL')
  const { data: dn, error: dErr } = await supabase
    .from('delivery_notes')
    .insert({ tenant_id: tid, number: dnNumber, customer_id: order.customer_id, sales_order_id: orderId, delivery_date: new Date().toISOString().split('T')[0], status: 'pending', carrier: null, tracking_number: null, notes: null })
    .select()
    .single()
  if (dErr) throw dErr

  let allDelivered = true
  for (const sel of lines) {
    const ol = (order.sales_order_lines || []).find((l: any) => l.id === sel.sales_order_line_id)
    if (!ol) continue
    const { error: lErr } = await supabase
      .from('delivery_note_lines')
      .insert({ tenant_id: tid, delivery_note_id: dn.id, product_id: ol.product_id, description: ol.description, quantity: sel.quantity, invoiced_quantity: 0, sales_order_line_id: sel.sales_order_line_id })
    if (lErr) throw lErr

    const newDelivered = Number(ol.delivered_quantity || 0) + sel.quantity
    await tud(supabase.from('sales_order_lines').update({ delivered_quantity: newDelivered }), 'sales_order_lines', tid).eq('id', sel.sales_order_line_id)
    if (newDelivered < Number(ol.quantity)) allDelivered = false
  }

  await tud(supabase.from('sales_orders').update({ delivery_status: allDelivered ? 'delivered' : 'partial', fully_delivered: allDelivered }), 'sales_orders', tid).eq('id', orderId)
  await recordTransformation('sales_order', orderId, 'delivery_note', dn.id, allDelivered ? 'full' : 'partial')
  return dn as DeliveryNote
}

// --- Transform Delivery Note to Invoice ---
export async function transformDeliveryNoteToInvoice(dnId: string, lines: { delivery_note_line_id: string; quantity: number }[]) {
  const tid = await getTenantId()
  const { data: dn, error: dErr } = await supabase.from('delivery_notes').select('*, delivery_note_lines(*)').eq('id', dnId).single()
  if (dErr) throw dErr

  const invNumber = await nextDocumentNumber('FAC')
  let subtotal = 0
  let vatTotal = 0

  const { data: inv, error: iErr } = await supabase
    .from('invoices')
    .insert({ tenant_id: tid, number: invNumber, customer_id: dn.customer_id, customer_name: null, date: new Date().toISOString().split('T')[0], due_date: new Date(Date.now() + 30 * 86400000).toISOString().split('T')[0], status: 'draft', subtotal: 0, vat_total: 0, total: 0, amount_paid: 0, amount_due: 0, notes: '', recurring: false, recurring_frequency: null, delivery_note_id: dnId, invoice_type: 'standard' })
    .select()
    .single()
  if (iErr) throw iErr

  let allInvoiced = true
  for (const sel of lines) {
    const dl = (dn.delivery_note_lines || []).find((l: any) => l.id === sel.delivery_note_line_id)
    if (!dl) continue
    const olData = dl.sales_order_line_id ? (await supabase.from('sales_order_lines').select('*').eq('id', dl.sales_order_line_id).single()).data : null
    const unitPrice = olData ? Number(olData.unit_price) : 0
    const vatRate = olData ? Number(olData.vat_rate) : 0
    const lineTotal = sel.quantity * unitPrice
    const lineVat = lineTotal * (vatRate / 100)
    subtotal += lineTotal
    vatTotal += lineVat

    const { error: lErr } = await supabase
      .from('invoice_lines')
      .insert({ tenant_id: tid, invoice_id: inv.id, product_id: dl.product_id, description: dl.description, quantity: sel.quantity, unit_price: unitPrice, vat_rate: vatRate, total: lineTotal, vat_total: lineVat, line_order: 0, delivery_note_line_id: sel.delivery_note_line_id, sales_order_line_id: dl.sales_order_line_id || null })
    if (lErr) throw lErr

    const newInvoiced = Number(dl.invoiced_quantity || 0) + sel.quantity
    await tud(supabase.from('delivery_note_lines').update({ invoiced_quantity: newInvoiced }), 'delivery_note_lines', tid).eq('id', sel.delivery_note_line_id)
    if (newInvoiced < Number(dl.quantity)) allInvoiced = false
  }

  await tud(supabase.from('invoices').update({ subtotal, vat_total: vatTotal, total: subtotal + vatTotal, amount_due: subtotal + vatTotal }), 'invoices', tid).eq('id', inv.id)
  await tud(supabase.from('delivery_notes').update({ invoice_status: allInvoiced ? 'invoiced' : 'partial', fully_invoiced: allInvoiced }), 'delivery_notes', tid).eq('id', dnId)
  await recordTransformation('delivery_note', dnId, 'invoice', inv.id, allInvoiced ? 'full' : 'partial')
  return inv as Invoice
}

// --- Transform Invoice to Credit Note ---
export async function transformInvoiceToCreditNote(invoiceId: string, reason: string) {
  const tid = await getTenantId()
  const { data: inv, error: iErr } = await supabase.from('invoices').select('*, invoice_lines(*)').eq('id', invoiceId).single()
  if (iErr) throw iErr

  const cnNumber = await nextDocumentNumber('AV')
  const { data: cn, error: cErr } = await supabase
    .from('credit_notes')
    .insert({ tenant_id: tid, number: cnNumber, customer_id: inv.customer_id, customer_name: inv.customer_name, date: new Date().toISOString().split('T')[0], status: 'draft', subtotal: Number(inv.subtotal), vat_total: Number(inv.vat_total), total: Number(inv.total), reason, invoice_id: invoiceId, source_invoice_id: invoiceId })
    .select()
    .single()
  if (cErr) throw cErr

  for (const line of inv.invoice_lines || []) {
    const { error: lErr } = await supabase
      .from('credit_note_lines')
      .insert({ tenant_id: tid, credit_note_id: cn.id, description: line.description, quantity: Number(line.quantity), unit_price: Number(line.unit_price), vat_rate: Number(line.vat_rate), total: Number(line.total), vat_total: Number(line.vat_total) })
    if (lErr) throw lErr
  }

  await recordTransformation('invoice', invoiceId, 'credit_note', cn.id, 'full')
  return cn as CreditNote
}

// --- Create Advance Invoice ---
export async function createAdvanceInvoice(customerId: string, amount: number, vatRate: number) {
  const tid = await getTenantId()
  const { data: cust, error: cErr } = await supabase.from('customers').select('name').eq('id', customerId).single()
  if (cErr) throw cErr

  const vatAmount = amount * (vatRate / 100)
  const total = amount + vatAmount
  const invNumber = await nextDocumentNumber('AC')

  const { data: inv, error: iErr } = await supabase
    .from('invoices')
    .insert({ tenant_id: tid, number: invNumber, customer_id: customerId, customer_name: cust?.name || null, date: new Date().toISOString().split('T')[0], due_date: new Date(Date.now() + 30 * 86400000).toISOString().split('T')[0], status: 'draft', subtotal: amount, vat_total: vatAmount, total, amount_paid: 0, amount_due: total, notes: '', recurring: false, recurring_frequency: null, is_advance_invoice: true, advance_amount: amount, invoice_type: 'advance' })
    .select()
    .single()
  if (iErr) throw iErr

  const { error: lErr } = await supabase
    .from('invoice_lines')
    .insert({ tenant_id: tid, invoice_id: inv.id, product_id: null, description: 'Acompte', quantity: 1, unit_price: amount, vat_rate: vatRate, total: amount, vat_total: vatAmount, line_order: 0 })
  if (lErr) throw lErr

  return inv as Invoice
}

// --- Stock helpers ---
export async function checkStockAvailability(productId: string, requiredQty: number) {
  const tid = await getTenantId()
  let q = supabase.from('stock_quantities').select('quantity').eq('product_id', productId).order('id')
  if (tid) q = q.eq('tenant_id', tid)
  // LOT7-03 : disponibilité = somme sur tous les dépôts et tous les lots.
  const data = await fetchAllRows<any>(q, { label: 'checkStockAvailability/stock_quantities' })
  const available = data.reduce((sum, s) => sum + Number(s.quantity || 0), 0)
  return { available, required: requiredQty, sufficient: available >= requiredQty }
}

export async function getStockForecast(productId: string) {
  const tid = await getTenantId()
  let qS = supabase.from('stock_quantities').select('quantity').eq('product_id', productId).order('id')
  if (tid) qS = qS.eq('tenant_id', tid)
  // LOT7-03 : prévision de stock — somme sur tous les dépôts et toutes les commandes.
  const stock = await fetchAllRows<any>(qS, { label: 'getStockForecast/stock_quantities' })
  const current = stock.reduce((sum: number, s: any) => sum + Number(s.quantity || 0), 0)

  let qP = supabase.from('sales_order_lines').select('quantity, delivered_quantity, sales_orders(status)').eq('product_id', productId).order('id')
  if (tid) qP = qP.eq('tenant_id', tid)
  const pending = await fetchAllRows<any>(qP, { label: 'getStockForecast/sales_order_lines' })
  const pendingQty = pending.filter((p: any) => p.sales_orders?.status === 'confirmed').reduce((sum: number, p: any) => sum + (Number(p.quantity) - Number(p.delivered_quantity || 0)), 0)

  return { current, pending: pendingQty, forecast: current - pendingQty }
}

// --- Get sales order lines ---
export async function getSalesOrderLines(orderId: string) {
  const tid = await getTenantId()
  let q = supabase.from('sales_order_lines').select('*').eq('sales_order_id', orderId).order('line_total', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as SalesOrderLine[]
}

// --- Get delivery note lines ---
export async function getDeliveryNoteLines(dnId: string) {
  const tid = await getTenantId()
  let q = supabase.from('delivery_note_lines').select('*').eq('delivery_note_id', dnId)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as DeliveryNoteLine[]
}


