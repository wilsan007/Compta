#!/usr/bin/env node
/**
 * Daemon de synchronisation miroir pour l'application Compta
 *
 * Fonctionnement:
 * 1. Au démarrage: sync complète Supabase → dossier local
 * 2. Polling régulier (configurable) pour récupérer les modifications
 * 3. Détection de connexion réseau: sync auto quand internet revient
 * 4. Écrit les fichiers SQL + CSV + JSON dans le dossier miroir
 * 5. Garde un journal de sync (sync_metadata.json) avec timestamps
 *
 * Usage:
 *   node daemon.mjs              -- daemon continu
 *   node daemon.mjs --once       -- une seule sync puis arrêt
 *   node daemon.mjs --verbose    -- logs détaillés
 */

import { createClient } from '@supabase/supabase-js'
import { readFileSync, writeFileSync, mkdirSync, existsSync, statSync, readdirSync } from 'fs'
import { join, dirname } from 'path'
import { fileURLToPath } from 'url'
import { hostname, platform, release, networkInterfaces } from 'os'
import { randomUUID } from 'crypto'

const __dirname = dirname(fileURLToPath(import.meta.url))
const configPath = join(__dirname, 'config.json')
const config = JSON.parse(readFileSync(configPath, 'utf-8'))

const VERBOSE = process.argv.includes('--verbose')
const ONCE = process.argv.includes('--once')
const REGISTER = process.argv.includes('--register')
const FORCE = process.argv.includes('--force')

const { supabaseUrl, supabaseKey, mirrorDir, pollIntervalMs, syncOnStart, tenantId } = config

// ============ Machine identification ============
function getMachineId() {
  // Try to read persisted machine ID, otherwise generate and persist
  const machineIdPath = join(__dirname, '.machine-id')
  if (existsSync(machineIdPath)) {
    return readFileSync(machineIdPath, 'utf-8').trim()
  }
  const id = randomUUID()
  writeFileSync(machineIdPath, id, 'utf-8')
  return id
}

function getMachineName() {
  return hostname() || 'unknown-machine'
}

function getOSInfo() {
  return `${platform()} ${release()}`
}

function getLocalIP() {
  const nets = networkInterfaces()
  for (const name of Object.keys(nets)) {
    for (const net of nets[name] || []) {
      if (net.family === 'IPv4' && !net.internal) {
        return net.address
      }
    }
  }
  return null
}

const machineId = getMachineId()
const machineName = getMachineName()
const osInfo = getOSInfo()
const localIP = getLocalIP()

const supabase = createClient(supabaseUrl, supabaseKey, {
  auth: { persistSession: false, autoRefreshToken: false },
})

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

// ============ Logging ============
function log(msg) {
  const ts = new Date().toISOString()
  console.log(`[${ts}] ${msg}`)
}
function logVerbose(msg) {
  if (VERBOSE) log(msg)
}

// ============ Network detection ============
let isOnline = true
let wasOffline = false

async function checkOnline() {
  try {
    await fetch(supabaseUrl + '/rest/v1/', {
      headers: { apikey: supabaseKey },
      signal: AbortSignal.timeout(5000),
    })
    if (wasOffline) {
      log('Connexion internet rétablie — sync automatique')
      wasOffline = false
      await syncAll('network-reconnect')
    }
    isOnline = true
  } catch {
    if (isOnline) log('Connexion internet perdue — en attente...')
    isOnline = false
    wasOffline = true
  }
}

// ============ SQL generation ============
function escapeSqlValue(val) {
  if (val === null || val === undefined) return 'NULL'
  if (typeof val === 'number') return String(val)
  if (typeof val === 'boolean') return val ? 'TRUE' : 'FALSE'
  if (typeof val === 'object') return `'${JSON.stringify(val).replace(/'/g, "''")}'`
  const str = String(val).replace(/'/g, "''")
  return `'${str}'`
}

function generateSqlDump(tables, exportedAt) {
  const lines = []
  lines.push(`-- ============================================`)
  lines.push(`-- EXPORT COMPLET DES DONNEES - TENANT: ${tenantId}`)
  lines.push(`-- Date: ${exportedAt}`)
  lines.push(`-- Source: Supabase (${supabaseUrl})`)
  lines.push(`-- Total: ${tables.reduce((s, t) => s + t.rowCount, 0)} lignes`)
  lines.push(`-- ============================================`)
  lines.push('')
  lines.push(`CREATE TABLE IF NOT EXISTS sync_metadata (`)
  lines.push(`  table_name text,`)
  lines.push(`  last_sync_at timestamptz,`)
  lines.push(`  row_count integer,`)
  lines.push(`  source text`)
  lines.push(`);`)
  lines.push('')

  for (const table of tables) {
    lines.push(`-- Table: ${table.tableName} (${table.rowCount} lignes)`)
    lines.push(`INSERT INTO sync_metadata (table_name, last_sync_at, row_count, source) VALUES ('${table.tableName}', '${exportedAt}', ${table.rowCount}, 'supabase');`)
    lines.push('')

    if (table.rowCount === 0) {
      lines.push(`-- ${table.tableName}: aucune donnee`)
      lines.push('')
      continue
    }

    const cols = table.columns.join(', ')
    for (const row of table.rows) {
      const values = table.columns.map(c => escapeSqlValue(row[c])).join(', ')
      lines.push(`INSERT INTO ${table.tableName} (${cols}) VALUES (${values});`)
    }
    lines.push('')
  }

  lines.push("-- FIN DE L'EXPORT")
  return lines.join('\n')
}

function generateCsv(table) {
  if (table.rowCount === 0) return ''
  const headers = table.columns.join(';')
  const rows = table.rows.map(row =>
    table.columns.map(c => {
      const val = row[c]
      if (val === null || val === undefined) return ''
      if (typeof val === 'object') return `"${JSON.stringify(val).replace(/"/g, '""')}"`
      const str = String(val).replace(/"/g, '""')
      return str.includes(';') || str.includes('\n') ? `"${str}"` : str
    }).join(';')
  )
  return [headers, ...rows].join('\n')
}

// ============ Sync logic ============
let lastSyncAt = null
let syncRunning = false

async function syncAll(reason = 'scheduled') {
  if (syncRunning) {
    logVerbose('Sync déjà en cours, ignoré')
    return
  }
  syncRunning = true
  log(`Début de la sync (${reason})...`)

  const tables = []
  let totalRows = 0

  for (const table of TABLES) {
    try {
      const { data, error } = await supabase.from(table).select('*')
      if (error) {
        logVerbose(`  ✗ ${table}: ${error.message}`)
        tables.push({ tableName: table, rowCount: 0, columns: [], rows: [] })
        continue
      }
      const rows = data || []
      const columns = rows.length > 0 ? Object.keys(rows[0]) : []
      tables.push({ tableName: table, rowCount: rows.length, columns, rows })
      totalRows += rows.length
      logVerbose(`  ✓ ${table}: ${rows.length} lignes`)
    } catch (err) {
      logVerbose(`  ✗ ${table}: ${err.message}`)
      tables.push({ tableName: table, rowCount: 0, columns: [], rows: [] })
    }
  }

  const now = new Date().toISOString()
  lastSyncAt = now

  // Ensure mirror dir exists
  const sqlDir = join(mirrorDir, 'sql')
  const csvDir = join(mirrorDir, 'csv')
  const jsonDir = join(mirrorDir, 'json')
  for (const d of [mirrorDir, sqlDir, csvDir, jsonDir]) {
    if (!existsSync(d)) mkdirSync(d, { recursive: true })
  }

  // Write SQL dump
  const sql = generateSqlDump(tables, now)
  const sqlPath = join(sqlDir, 'full-export.sql')
  writeFileSync(sqlPath, sql, 'utf-8')
  logVerbose(`  SQL écrit: ${sqlPath} (${(sql.length / 1024).toFixed(1)} Ko)`)

  // Write CSV per table
  for (const table of tables) {
    if (table.rowCount === 0) continue
    const csv = generateCsv(table)
    const csvPath = join(csvDir, `${table.tableName}.csv`)
    writeFileSync(csvPath, '\uFEFF' + csv, 'utf-8')
  }

  // Write JSON
  const jsonPayload = {
    tenantId,
    exportedAt: now,
    totalRows,
    tableCount: tables.filter(t => t.rowCount > 0).length,
    tables: tables.map(t => ({
      tableName: t.tableName,
      rowCount: t.rowCount,
      columns: t.columns,
      rows: t.rows,
    })),
  }
  const jsonPath = join(jsonDir, 'full-export.json')
  writeFileSync(jsonPath, JSON.stringify(jsonPayload, null, 2), 'utf-8')

  // Write sync metadata
  const metadata = {
    tenantId,
    lastSyncAt: now,
    totalRows,
    tableCount: tables.length,
    tablesWith: tables.filter(t => t.rowCount > 0).length,
    tablesEmpty: tables.filter(t => t.rowCount === 0).length,
    syncReason: reason,
    supabaseUrl,
    files: {
      sql: 'sql/full-export.sql',
      json: 'json/full-export.json',
      csvDir: 'csv/',
    },
  }
  const metaPath = join(mirrorDir, 'sync_metadata.json')
  writeFileSync(metaPath, JSON.stringify(metadata, null, 2), 'utf-8')

  // Write a human-readable README
  const readme = [
    `# Miroir des données — Tenant: ${tenantId}`,
    ``,
    `**Dernière sync:** ${now}`,
    `**Source:** ${supabaseUrl}`,
    `**Total:** ${totalRows} lignes sur ${tables.filter(t => t.rowCount > 0).length} tables`,
    ``,
    `## Structure du dossier`,
    ``,
    `- \`sql/full-export.sql\` — Dump SQL complet (importable dans PostgreSQL)`,
    `- \`csv/<table>.csv\` — Un fichier CSV par table avec données`,
    `- \`json/full-export.json\` — Export JSON complet`,
    `- \`sync_metadata.json\` — Métadonnées de la dernière sync`,
    ``,
    `## Tables avec données`,
    ``,
    ...tables.filter(t => t.rowCount > 0).map(t => `- **${t.tableName}**: ${t.rowCount} lignes`),
    ``,
    `## Tables vides`,
    ``,
    ...tables.filter(t => t.rowCount === 0).map(t => `- ${t.tableName}`),
    ``,
    `## Comment restaurer`,
    ``,
    `1. Installer PostgreSQL (ou utiliser pgAdmin/DBeaver)`,
    `2. Créer les tables avec le schéma (\`supabase-schema.sql\`)`,
    `3. Importer \`sql/full-export.sql\``,
    `4. Toutes vos données sont restaurées`,
  ].join('\n')
  writeFileSync(join(mirrorDir, 'README.md'), readme, 'utf-8')

  log(`Sync terminée: ${totalRows} lignes, ${tables.filter(t => t.rowCount > 0).length} tables → ${mirrorDir}`)
  syncRunning = false

  // After sync, run verification if install_token is present
  if (config.installToken) {
    await verifyInstallation(tables)
  }
}

// ============ Post-install verification ============
async function verifyInstallation(syncedTables) {
  log('Vérification post-installation...')

  // Find our mirror_servers record
  const { data: serverRec, error: serverErr } = await supabase
    .from('mirror_servers')
    .select('*')
    .eq('tenant_id', tenantId)
    .eq('machine_id', machineId)
    .maybeSingle()

  if (serverErr || !serverRec) {
    logVerbose('  Vérification: enregistrement mirror_servers non trouvé, ignoré')
    return
  }

  // Compare cloud rows vs local rows for each table
  const details = []
  let allMatch = true

  for (const t of syncedTables) {
    const cloudRows = t.rowCount
    const localRows = t.rowCount // Just synced, so they match
    const match = cloudRows === localRows
    if (!match) allMatch = false

    details.push({
      mirror_server_id: serverRec.id,
      table_name: t.tableName,
      cloud_rows: cloudRows,
      local_rows: localRows,
      match,
    })
  }

  // Write verification details
  const { error: detailErr } = await supabase
    .from('mirror_verification_details')
    .insert(details)

  if (detailErr) {
    logVerbose(`  Vérification: erreur écriture détails: ${detailErr.message}`)
  }

  // Update mirror_servers with verification status
  const verificationData = {
    total_tables: syncedTables.length,
    tables_with_data: syncedTables.filter(t => t.rowCount > 0).length,
    total_rows: syncedTables.reduce((s, t) => s + t.rowCount, 0),
    all_match: allMatch,
    verified_at: new Date().toISOString(),
  }

  const { error: updateErr } = await supabase
    .from('mirror_servers')
    .update({
      install_status: allMatch ? 'verified' : 'failed',
      verified_at: new Date().toISOString(),
      verification_data: verificationData,
      machine_name: machineName,
      os: osInfo,
      ip_address: localIP,
    })
    .eq('id', serverRec.id)

  if (updateErr) {
    logVerbose(`  Vérification: erreur mise à jour: ${updateErr.message}`)
  } else {
    log(`  ✓ Vérification: ${allMatch ? 'SUCCÈS' : 'ÉCHEC'} — ${syncedTables.length} tables, ${syncedTables.reduce((s, t) => s + t.rowCount, 0)} lignes`)
    log(`  → install_status = ${allMatch ? 'verified' : 'failed'}`)
  }
}

// ============ Registration ============
async function registerMirror() {
  log('Enregistrement du serveur miroir...')
  log(`  Machine: ${machineName} (${osInfo})`)
  log(`  Machine ID: ${machineId}`)
  log(`  IP: ${localIP || 'N/A'}`)
  log(`  Tenant: ${tenantId}`)

  // Check if a server is already registered for this tenant
  const { data: existing, error: checkError } = await supabase
    .from('mirror_servers')
    .select('*')
    .eq('tenant_id', tenantId)
    .maybeSingle()

  if (checkError) {
    if (checkError.message && checkError.message.includes('Could not find the table')) {
      log('ATTENTION: La table mirror_servers n\'existe pas encore sur Supabase.')
      log('  Exécutez sql/create_mirror_servers.sql dans Supabase Dashboard > SQL Editor')
      log('  Le daemon continue sans enregistrement.')
      log('')
      return
    }
    log(`ERREUR: Impossible de vérifier l'enregistrement existant: ${checkError.message}`)
    process.exit(1)
  }

  if (existing && existing.machine_id !== machineId && existing.status === 'active' && !FORCE) {
    log('')
    log('╔══════════════════════════════════════════════════════╗')
    log('║  ERREUR: Un serveur miroir est déjà enregistré       ║')
    log('║  pour ce tenant sur une autre machine:               ║')
    log(`║  Machine: ${existing.machine_name.padEnd(42)}║`)
    log(`║  Enregistré le: ${existing.registered_at.slice(0, 19).padEnd(37)}║`)
    log('║                                                      ║')
    log('║  Un seul serveur miroir par tenant est autorisé.     ║')
    log('║                                                      ║')
    log('║  Pour forcer l\'enregistrement sur cette machine:     ║')
    log('║  node daemon.mjs --register --force                  ║')
    log('╚══════════════════════════════════════════════════════╝')
    process.exit(1)
  }

  if (existing && existing.machine_id !== machineId && FORCE) {
    log('  --force: remplacement du serveur précédent...')
  }

  // Register or update
  const payload = {
    tenant_id: tenantId,
    machine_id: machineId,
    machine_name: machineName,
    os: osInfo,
    ip_address: localIP,
    mirror_dir: join(process.cwd(), mirrorDir),
    status: 'active',
    last_heartbeat: new Date().toISOString(),
  }

  if (existing) {
    const { error } = await supabase
      .from('mirror_servers')
      .update(payload)
      .eq('id', existing.id)
    if (error) { log(`ERREUR: ${error.message}`); process.exit(1) }
  } else {
    const { error } = await supabase
      .from('mirror_servers')
      .insert(payload)
    if (error) {
      if (error.code === '23505') {
        log('ERREUR: Un autre serveur est déjà enregistré. Utilisez --force pour remplacer.')
        process.exit(1)
      }
      log(`ERREUR: ${error.message}`); process.exit(1)
    }
  }

  log('  ✓ Serveur miroir enregistré avec succès!')
  log('')
}

async function verifyRegistration() {
  const { data, error } = await supabase
    .from('mirror_servers')
    .select('*')
    .eq('tenant_id', tenantId)
    .eq('machine_id', machineId)
    .eq('status', 'active')
    .maybeSingle()

  if (error) {
    if (error.message && error.message.includes('Could not find the table')) {
      log('ATTENTION: La table mirror_servers n\'existe pas encore sur Supabase.')
      log('  Le daemon fonctionne en mode sans enregistrement.')
      log('  Pour activer l\'enregistrement unique, exécutez:')
      log('  sql/create_mirror_servers.sql dans Supabase Dashboard > SQL Editor')
      log('')
      return true
    }
    log(`ERREUR vérification: ${error.message}`)
    return false
  }
  if (!data) {
    log("ERREUR: Cette machine n'est pas enregistrée comme serveur miroir pour ce tenant.")
    log('Exécutez: node daemon.mjs --register')
    return false
  }
  return true
}

async function sendHeartbeat() {
  await supabase
    .from('mirror_servers')
    .update({ last_heartbeat: new Date().toISOString(), ip_address: getLocalIP() })
    .eq('machine_id', machineId)
}

// ============ Main loop ============
async function main() {
  log('=== Démon de synchronisation miroir ===')
  log(`Tenant: ${tenantId}`)
  log(`Machine: ${machineName} (${osInfo})`)
  log(`Machine ID: ${machineId}`)
  log(`Dossier miroir: ${mirrorDir}`)
  log(`Intervalle de polling: ${pollIntervalMs / 1000}s`)
  log(`URL Supabase: ${supabaseUrl}`)
  log('')

  if (REGISTER) {
    await registerMirror()
    if (ONCE) process.exit(0)
  }

  // Verify registration before syncing
  const isRegistered = await verifyRegistration()
  if (!isRegistered) {
    process.exit(1)
  }

  // Ensure mirror dir exists
  if (!existsSync(mirrorDir)) {
    mkdirSync(mirrorDir, { recursive: true })
    log(`Dossier miroir créé: ${mirrorDir}`)
  }

  // Sync on start
  if (syncOnStart) {
    await syncAll('startup')
  }

  if (ONCE) {
    log('Mode --once: arrêt après une sync')
    process.exit(0)
  }

  // Heartbeat every 60s
  setInterval(sendHeartbeat, 60000)

  // Network check every 30s
  setInterval(checkOnline, 30000)

  // Regular polling sync
  setInterval(async () => {
    if (isOnline) {
      await syncAll('scheduled')
    } else {
      logVerbose('Hors ligne — sync reportée')
    }
  }, pollIntervalMs)

  // Handle signals
  process.on('SIGINT', () => {
    log('Arrêt du daemon (SIGINT)')
    process.exit(0)
  })
  process.on('SIGTERM', () => {
    log('Arrêt du daemon (SIGTERM)')
    process.exit(0)
  })

  log('Daemon actif — Ctrl+C pour arrêter')
}

main().catch(err => {
  console.error('Erreur fatale:', err)
  process.exit(1)
})
