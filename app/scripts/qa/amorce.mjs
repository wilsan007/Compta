// ============================================================
// qa/amorce.mjs — l'AGENT D'AMORÇAGE : la société reçoit des données
//
// Un écran vide ne se teste pas : il ne prouve ni les colonnes, ni les totaux,
// ni les onglets. Cet agent remplit la société de la session avec un jeu de
// données métier — clients, fournisseurs, produits, devis, commandes,
// livraisons, factures, règlements, écritures, immobilisations, budgets,
// salariés, congés, notes de frais, projets, temps, ordres de fabrication,
// dépôt, tickets de caisse.
//
// Il écrit par l'API RÉELLE du produit (PostgREST + RLS + déclencheurs), avec
// le jeton du propriétaire de la société : ce n'est pas un INSERT en douce.
// Colonnes obligatoires inconnues : il les demande au schéma et les remplit par
// type, et il DIT ce qui a échoué au lieu de le taire.
//
// Usage : node scripts/qa/amorce.mjs [--module=commercial] [--dry]
// ============================================================
import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { QA_DIR } from './inventory.mjs'
import { PLAN } from './amorce-plan.mjs'

const APP = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..')
const OUT = path.join(APP, '.qa-out')
const DB = process.env.QA_DB_CONTAINER || 'supabase_db_app'
const REST = (process.env.QA_API_URL || 'http://127.0.0.1:54321').replace(/\/$/, '') + '/rest/v1'
const DRY = process.argv.includes('--dry')
const ONLY = (process.argv.find((a) => a.startsWith('--module=')) || '').split('=')[1] || null

if (!/^https?:\/\/(127\.0\.0\.1|localhost)/.test(REST)) {
  console.error('Refus : l\'amorçage écrit — l\'API doit être locale.')
  process.exit(2)
}

function sql(statement) {
  return execFileSync('docker', ['exec', DB, 'psql', '-U', 'postgres', '-d', 'postgres', '-tAc', statement], { encoding: 'utf8' }).trim()
}

/** Le jeton du propriétaire, lu dans l'état de session du navigateur. */
function ownerToken() {
  const session = JSON.parse(fs.readFileSync(path.join(QA_DIR, 'session.json'), 'utf8'))
  const state = JSON.parse(fs.readFileSync(session.owner.storageState, 'utf8'))
  for (const origin of state.origins ?? []) {
    // `localStorage` d'un storageState Playwright est un TABLEAU de { name, value }
    // — lu comme une table, on n'y voyait que les indices 0, 1, 2 (mesuré le 29/09).
    for (const item of origin.localStorage ?? []) {
      if (!/^sb-.+-auth-token$/.test(item.name)) continue
      const parsed = JSON.parse(item.value)
      if (parsed?.access_token) return { token: parsed.access_token, tenantId: session.tenantId, company: session.company, email: session.owner.email }
    }
  }
  throw new Error('jeton du propriétaire introuvable dans ' + session.owner.storageState)
}

const KEYS = JSON.parse(fs.readFileSync(path.join(QA_DIR, 'local-keys.json'), 'utf8'))

const columnsCache = new Map()
/** Les colonnes obligatoires sans valeur par défaut : ce que l'appelant doit fournir. */
function requiredColumns(table) {
  if (!columnsCache.has(table)) {
    const rows = sql(`SELECT column_name || ':' || data_type || ':' || (column_default IS NOT NULL)::text
      FROM information_schema.columns WHERE table_schema='public' AND table_name='${table}'
      AND is_nullable='NO' AND column_default IS NULL ORDER BY ordinal_position`)
    columnsCache.set(table, rows ? rows.split('\n').map((l) => { const [name, type, hasDefault] = l.split(':'); return { name, type, hasDefault: hasDefault === 'true' } }) : [])
  }
  return columnsCache.get(table)
}
function hasColumn(table, column) {
  return sql(`SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='${table}' AND column_name='${column}'`) !== '0'
}

/** Les colonnes réelles d'une table (une requête par table, mises en cache). */
const allColumnsCache = new Map()
function allColumns(table) {
  if (!allColumnsCache.has(table)) {
    const raw = sql(`SELECT string_agg(column_name, ' ') FROM information_schema.columns WHERE table_schema='public' AND table_name='${table}'`)
    allColumnsCache.set(table, new Set((raw || '').split(' ').filter(Boolean)))
  }
  return allColumnsCache.get(table)
}

/** Confronte le plan au schéma : colonnes inventées, obligatoires manquantes. */
function checkPlan() {
  let problems = 0
  for (const step of PLAN) {
    const cols = allColumns(step.table)
    if (!cols.size) { console.log(`${step.table.padEnd(22)} TABLE ABSENTE`); problems++; continue }
    const invented = new Set()
    for (const row of step.rows) {
      for (const k of Object.keys(row)) {
        if (k.startsWith('__')) continue
        if (!cols.has(k) && !String(row[k]).startsWith('@')) invented.add(k)
      }
    }
    const missing = requiredColumns(step.table).filter((c) => c.name !== 'tenant_id' && !step.rows.some((r) => c.name in r))
    if (invented.size || missing.length) {
      problems++
      console.log(`${step.table.padEnd(22)} ${invented.size ? `colonnes inexistantes : ${[...invented].join(', ')}` : ''}${missing.length ? ` | obligatoires non fournies : ${missing.map((m) => m.name).join(', ')}` : ''}`)
    }
  }
  console.log(`\n${problems} étape(s) à corriger sur ${PLAN.length}`)
}


function valueForType(type) {
  if (/uuid/.test(type)) return crypto.randomUUID()
  if (/int|numeric|real|double/.test(type)) return 1
  if (/timestamp/.test(type)) return new Date().toISOString()
  if (/date/.test(type)) return new Date().toISOString().slice(0, 10)
  if (/bool/.test(type)) return false
  if (/json/.test(type)) return {}
  return 'QA'
}

// ── Le plan d'amorçage : ce qui doit exister pour qu'un écran ait à montrer ──
// Les valeurs `@nom.champ` sont résolues avec les lignes réellement insérées
// (l'API rend la représentation). Les colonnes obligatoires non listées sont
// remplies par type ; chaque échec est rapporté, jamais masqué.
// ── Le moteur ───────────────────────────────────────────────────────
const ctx = {}
const results = []

function resolve(ref) {
  const [name, field] = ref.slice(1).split('.')
  const row = ctx[name]
  if (!row) throw new Error(`référence inconnue : ${ref}`)
  return row[field]
}

// Clés par lesquelles une ligne déjà présente se retrouve : l'amorçage doit
// pouvoir être rejoué (mesuré le 29/09/2026 : une seconde passe échouait en 409
// sur 8 tables, et les références tombaient avec elle).
const KEY_CANDIDATES = ['number', 'code', 'sku', 'name', 'reference', 'period']

async function getExisting(table, row, tenantId, token) {
  for (const key of KEY_CANDIDATES) {
    if (row[key] === undefined || row[key] === null) continue
    const url = `${REST}/${table}?select=*&${key}=eq.${encodeURIComponent(row[key])}&limit=1`
    const res = await fetch(url, { headers: { apikey: KEYS.anon, Authorization: `Bearer ${token}`, 'x-tenant-id': tenantId } })
    if (!res.ok) continue
    const body = await res.json().catch(() => null)
    if (Array.isArray(body) && body.length) return body[0]
  }
  // Une ligne de document n'a ni numéro ni code : on la retrouve par son parent
  // (et sa position), seuls identifiants dont elle dispose.
  const fk = Object.keys(row).find((k) => k.endsWith('_id') && row[k])
  if (fk) {
    const extra = row.line_order !== undefined ? `&line_order=eq.${row.line_order}` : ''
    const url = `${REST}/${table}?select=*&${fk}=eq.${encodeURIComponent(row[fk])}${extra}&limit=1`
    const res = await fetch(url, { headers: { apikey: KEYS.anon, Authorization: `Bearer ${token}`, 'x-tenant-id': tenantId } })
    if (res.ok) {
      const body = await res.json().catch(() => null)
      if (Array.isArray(body) && body.length) return body[0]
    }
  }
  return null
}

async function postRows(table, rows, tenantId, token) {
  const res = await fetch(`${REST}/${table}`, {
    method: 'POST',
    headers: {
      apikey: KEYS.anon, Authorization: `Bearer ${token}`,
      // `current_tenant_id()` lit d'abord l'en-tête `x-tenant-id` (priorité 1),
      // puis le GUC de session. Sans cet en-tête, chaque écriture est refusée par
      // la RLS (403) — c'est le contrat que l'écran respecte, mesuré le 29/09/2026.
      'x-tenant-id': tenantId,
      'Content-Type': 'application/json', Prefer: 'return=representation',
    },
    body: JSON.stringify(rows),
  })
  const body = await res.json().catch(() => null)
  if (!res.ok) return { ok: false, status: res.status, error: `${res.status} ${String(body?.message || body?.hint || JSON.stringify(body) || '').slice(0, 200)}`, rows: [] }
  return { ok: true, rows: Array.isArray(body) ? body : [] }
}

async function insertRows({ table, rows }, tenantId, token) {
  const payload = rows.map((row) => {
    const out = {}
    for (const [k, v] of Object.entries(row)) {
      if (k.startsWith('__')) continue
      out[k] = typeof v === 'string' && v.startsWith('@') ? resolve(v) : v
    }
    if (hasColumn(table, 'tenant_id')) out.tenant_id = tenantId
    return out
  })
  // Les colonnes obligatoires que le plan ne mentionne pas : remplies par type.
  // Si une contrainte les refuse, l'échec est rapporté tel quel.
  for (const col of requiredColumns(table)) {
    if (col.name === 'tenant_id') continue
    for (const row of payload) if (row[col.name] === undefined) row[col.name] = valueForType(col.type)
  }

  const batch = await postRows(table, payload, tenantId, token)
  if (batch.ok) return { ok: true, rows: batch.rows, error: null, already: 0 }

  // Le lot est refusé : on reprend ligne par ligne, pour qu'une ligne déjà
  // présente ne fasse pas tomber les autres (et pour nommer la vraie cause).
  const kept = []
  let already = 0
  const errors = []
  for (const row of payload) {
    const one = await postRows(table, [row], tenantId, token)
    if (one.ok) { kept.push(one.rows[0]); continue }
    if (one.status === 409) {
      const existing = await getExisting(table, row, tenantId, token)
      if (existing) { kept.push(existing); already++; continue }
    }
    errors.push(one.error)
  }
  return {
    ok: kept.length === payload.length,
    rows: kept,
    already,
    error: errors.length ? [...new Set(errors)].join(' | ').slice(0, 240) : null,
  }
}

async function main() {
  const { token, tenantId, company, email } = ownerToken()
  if (process.argv.includes('--check')) { checkPlan(); return }
  console.log(`amorçage de « ${company} » par ${email}`)
  const plan = ONLY ? PLAN.filter((s) => s.module === ONLY) : PLAN
  console.log(`${plan.length} étape(s), ${plan.reduce((a, s) => a + s.rows.length, 0)} ligne(s)\n`)
  for (const step of plan) {
    if (DRY) { console.log(`[à faire] ${step.table} (${step.module}) : ${step.rows.length} ligne(s)`); continue }
    let outcome
    try {
      outcome = await insertRows(step, tenantId, token)
    } catch (e) {
      outcome = { ok: false, error: String(e.message).slice(0, 200), rows: [] }
    }
    step.rows.forEach((row, i) => { if (row.__as && outcome.rows[i]) ctx[row.__as] = outcome.rows[i] })
    results.push({ module: step.module, table: step.table, asked: step.rows.length, inserted: outcome.rows.length, error: outcome.error })
    console.log(`${step.table.padEnd(22)} ${outcome.ok ? `ok (${outcome.rows.length})` : `ÉCHEC : ${outcome.error}`}`)
  }
  if (DRY) return
  const inserted = results.reduce((a, r) => a + r.inserted, 0)
  const failed = results.filter((r) => r.error)
  fs.mkdirSync(OUT, { recursive: true })
  fs.writeFileSync(path.join(OUT, 'amorce.json'), JSON.stringify({ at: new Date().toISOString(), company, tenantId, inserted, results }, null, 2))
  console.log(`\n${inserted} ligne(s) écrite(s) ; ${failed.length} étape(s) en échec`)
  for (const r of failed) console.log(`  ✗ ${r.table} : ${r.error}`)
  console.log('détail : .qa-out/amorce.json')
}

main().catch((e) => { console.error('amorçage : échec —', e.stack || e.message); process.exit(1) })


