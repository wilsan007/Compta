#!/usr/bin/env node
/**
 * check-written-columns.mjs — W0.2 (défauts EF-04, EF-05, EF-07, EF-08)
 *
 * L'ANGLE MORT QUE CE CONTRÔLE FERME. `check-embeds.mjs` (N4) ne vérifie que les
 * LECTURES. Une colonne inexistante dans un `.insert()` / `.update()` n'est vue
 * ni par `tsc` (ce sont des objets littéraux passés à un client typé « any »),
 * ni par les tests (Supabase y est simulé), ni par PostgREST tant que la requête
 * n'est pas jouée. Mesuré le 23/09/2026 sur le schéma réel : **21 écritures
 * impossibles**, toutes dans `supabase/functions/`, et **aucune ne lit son
 * erreur** — donc aucune n'échouait visiblement :
 *
 *   cron-payment-reminders   days_overdue, sent_at, email_sent        (n'existent pas)
 *   submit-e-invoice         e_invoice_status, e_invoice_platform…    (aucune colonne e_invoice*)
 *   request-signature        provider, provider_signature_id, status… (signature_hash, signer_name)
 *   sync-bank-transactions   provider_requisition_id, link_url, user_id
 *   outgoing-webhooks        http_status → response_code ; next_retry_at → next_attempt_at
 *
 * LA RÈGLE. Toute clé de premier niveau d'un objet littéral écrit par
 * `.insert()` / `.update()` / `.upsert()` doit exister en base, pour la table
 * visée par le `.from()` de la **même** requête.
 *
 * LA BASELINE EST GELÉE. Les écritures impossibles déjà connues sont inscrites,
 * une par une, dans `scripts/verify-rules/written-columns.baseline.json` avec la
 * vague qui les corrige (W6 pour les fonctions Edge). Ce n'est pas une
 * autorisation : c'est un **plafond qui ne peut que baisser**. Une écriture
 * inscrite qui disparaît du code **fait échouer la CI** : la ligne doit être
 * retirée dans le même commit (même contrat que `ci/expected_failures.sql`).
 * `--update-baseline` existe mais ne sert qu'à **retirer** des lignes : il refuse
 * d'en ajouter.
 *
 * Usage :
 *   DATABASE_URL=... node scripts/check-written-columns.mjs
 *   DATABASE_URL=... node scripts/check-written-columns.mjs --update-baseline
 *
 * Sortie : code 1 si une écriture nouvelle apparaît, ou si une ligne gelée n'est
 * plus reproduite. Code 0 sinon.
 */
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const ROOT = path.join(__dirname, '..')
const BASELINE = path.join(__dirname, 'verify-rules', 'written-columns.baseline.json')
const UPDATE = process.argv.includes('--update-baseline')

const DATABASE_URL = process.env.DATABASE_URL
if (!DATABASE_URL && !process.env.PGHOST) {
  console.error('❌ DATABASE_URL (ou PGHOST/PGUSER/PGPASSWORD/PGDATABASE) est requis :')
  console.error('   le contrôle confronte le code au SCHÉMA RÉEL, pas à une liste devinée.')
  process.exit(2)
}

// ────────────────────────────────────────────────────────────
// 1. Le schéma réel
// ────────────────────────────────────────────────────────────
const { default: pg } = await import('pg')
const client = new pg.Client(
  DATABASE_URL
    ? { connectionString: DATABASE_URL }
    : {
        host: process.env.PGHOST,
        port: Number(process.env.PGPORT || 5432),
        user: process.env.PGUSER,
        password: process.env.PGPASSWORD,
        database: process.env.PGDATABASE,
      }
)

let cols
try {
  await client.connect()
  const { rows } = await client.query(
    `SELECT table_name, column_name FROM information_schema.columns
     WHERE table_schema = 'public'`
  )
  cols = new Map()
  for (const r of rows) {
    if (!cols.has(r.table_name)) cols.set(r.table_name, new Set())
    cols.get(r.table_name).add(r.column_name)
  }
} catch (err) {
  console.error('❌ Lecture du schéma impossible :', err.message)
  process.exit(2)
} finally {
  await client.end().catch(() => {})
}
if (cols.size === 0) {
  console.error('❌ Schéma vide : le contrôle ne prouverait rien. Chargez 00_schema_dump.sql d’abord.')
  process.exit(2)
}

// ────────────────────────────────────────────────────────────
// 2. Le corpus : le front ET les fonctions Edge
// ────────────────────────────────────────────────────────────
const files = []
function walk(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name)
    if (e.isDirectory()) {
      if (/node_modules|__tests__|\.git$|dist$/.test(p)) continue
      walk(p)
    } else if (/\.(ts|tsx)$/.test(p) && !/\.test\.|database-generated/.test(p)) {
      files.push(p)
    }
  }
}
for (const r of ['src', 'supabase/functions']) {
  const abs = path.join(ROOT, r)
  if (fs.existsSync(abs)) walk(abs)
}

// Découpe équilibrée d'un objet littéral à partir de la position de son '{'
function readObject(src, start) {
  let depth = 0
  let i = start
  let inStr = null
  let prev = ''
  for (; i < src.length; i++) {
    const ch = src[i]
    if (inStr) {
      if (ch === inStr && prev !== '\\') inStr = null
    } else if (ch === '"' || ch === "'" || ch === '`') inStr = ch
    else if (ch === '{') depth++
    else if (ch === '}') {
      depth--
      if (depth === 0) return src.slice(start, i + 1)
    }
    prev = ch
  }
  return null
}

// Clés de premier niveau seulement ({ a: 1, b: { c: 2 } } → a, b)
function topLevelKeys(obj) {
  const body = obj.slice(1, -1)
  const keys = []
  let depth = 0
  let inStr = null
  let prev = ''
  let tokenStart = 0
  const parts = []
  for (let i = 0; i < body.length; i++) {
    const ch = body[i]
    if (inStr) {
      if (ch === inStr && prev !== '\\') inStr = null
    } else if (ch === '"' || ch === "'" || ch === '`') inStr = ch
    else if ('{[('.includes(ch)) depth++
    else if ('}])'.includes(ch)) depth--
    else if (ch === ',' && depth === 0) {
      parts.push(body.slice(tokenStart, i))
      tokenStart = i + 1
    }
    prev = ch
  }
  parts.push(body.slice(tokenStart))
  for (const p of parts) {
    const m = p.match(/^\s*(?:\/\/[^\n]*\n\s*)*['"]?([A-Za-z_][A-Za-z0-9_]*)['"]?\s*:/)
    if (m) keys.push(m[1])
    else {
      const sh = p.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*$/) // raccourci { foo }
      if (sh) keys.push(sh[1])
    }
  }
  return keys
}

const problems = []
for (const file of files) {
  const src = fs.readFileSync(file, 'utf8')
  const rel = path.relative(ROOT, file)
  const re =
    /\.from\(\s*['"`]([a-z0-9_]+)['"`]\s*\)([\s\S]{0,400}?)\.(insert|update|upsert)\s*\(\s*(\{|\[)/g
  let m
  while ((m = re.exec(src))) {
    const table = m[1]
    const op = m[3]
    const gap = m[2]
    // Faux positifs : un autre .from(), ou un point-virgule entre le .from() et
    // l'écriture = ce n'est pas la même requête.
    if (/\.from\(|;/.test(gap)) continue
    const line = src.slice(0, m.index).split('\n').length
    if (!cols.has(table)) {
      problems.push({ file: rel, table, column: '(table inconnue)', op, line })
      continue
    }
    let braceAt = m.index + m[0].length - 1
    if (m[4] === '[') {
      braceAt = src.indexOf('{', braceAt)
      if (braceAt < 0) continue
    }
    const obj = readObject(src, braceAt)
    if (!obj || obj.length > 6000) continue
    for (const k of topLevelKeys(obj)) {
      if (!cols.get(table).has(k)) problems.push({ file: rel, table, column: k, op, line })
    }
  }
}

// Une (fichier, table, colonne) n'est comptée qu'une fois : c'est elle qui est
// gelée, pas ses occurrences.
const seen = new Map()
for (const p of problems) {
  const key = `${p.file}|${p.table}|${p.column}`
  if (!seen.has(key)) seen.set(key, p)
}
const found = [...seen.keys()].sort()

// --json : imprime les constats bruts (sert à geler ou à relire la baseline)
if (process.argv.includes('--json')) {
  console.log(JSON.stringify([...seen.values()], null, 2))
  process.exit(0)
}

// ────────────────────────────────────────────────────────────
// 3. Confrontation à la baseline gelée
// ────────────────────────────────────────────────────────────
if (!fs.existsSync(BASELINE)) {
  console.error(`❌ Baseline absente : ${path.relative(ROOT, BASELINE)}`)
  console.error('   Sans elle, une écriture impossible ne serait pas distinguée d’une autre.')
  process.exit(2)
}
const baseline = JSON.parse(fs.readFileSync(BASELINE, 'utf8'))
const frozen = new Map(baseline.findings.map((f) => [`${f.file}|${f.table}|${f.column}`, f]))

const nouveaux = found.filter((k) => !frozen.has(k))
const disparus = [...frozen.keys()].filter((k) => !seen.has(k))

if (UPDATE) {
  if (nouveaux.length > 0) {
    console.error('❌ --update-baseline refuse d’AJOUTER des écritures impossibles :')
    for (const k of nouveaux) console.error(`   ${k}  (${seen.get(k).file}:${seen.get(k).line})`)
    console.error('   La baseline est un plafond qui ne peut que baisser. Corrigez l’écriture,')
    console.error('   ou inscrivez la ligne à la main avec la vague et la raison.')
    process.exit(1)
  }
  baseline.findings = baseline.findings.filter((f) => seen.has(`${f.file}|${f.table}|${f.column}`))
  baseline.frozenAt = new Date().toISOString().slice(0, 10)
  baseline.total = baseline.findings.length
  fs.writeFileSync(BASELINE, JSON.stringify(baseline, null, 2) + '\n')
  console.log(`✅ Baseline mise à jour : ${baseline.findings.length} écriture(s) impossible(s) gelée(s).`)
  process.exit(0)
}

console.log(
  `Colonnes écrites : ${files.length} fichiers, ${cols.size} tables, ${found.length} écriture(s) suspecte(s).`
)
console.log(`Baseline gelée   : ${frozen.size} entrée(s), gelée le ${baseline.frozenAt || 'inconnu'}.`)

if (nouveaux.length > 0) {
  console.error('\n❌ ÉCRITURE(S) IMPOSSIBLE(S) NOUVELLE(S) — colonne absente du schéma :')
  for (const k of nouveaux) {
    const p = seen.get(k)
    console.error(`   ${p.file}:${p.line}  →  ${p.table}.${p.column}  (${p.op})`)
  }
  console.error('\n   Au 23/09/2026 ce contrôle en trouvait 21 dans les fonctions Edge ; aucune')
  console.error('   ne lisait son erreur. Ce qui est déjà gelé est en baseline ; ce qui est')
  console.error('   nouveau doit être corrigé, pas inscrit.')
  process.exit(1)
}

if (disparus.length > 0) {
  console.error('\n❌ ÉCRITURE(S) GELÉE(S) QUI N’EXISTENT PLUS — la ligne doit être retirée :')
  for (const k of disparus) console.error(`   ${k}  — ${frozen.get(k).reason || 'sans raison'}`)
  console.error('\n   `node scripts/check-written-columns.mjs --update-baseline` retire les lignes')
  console.error('   devenues fausses ; il n’en ajoute jamais.')
  process.exit(1)
}

console.log('✅ Aucune nouvelle écriture impossible, et aucune ligne gelée n’est périmée.')
