#!/usr/bin/env node
/**
 * check-embeds.mjs — LOT7-04
 *
 * Rejoue contre un PostgREST réel toutes les colonnes et ressources jointes nommées
 * dans le code — `select('...')` et filtres `.eq('col', …)`, `.order('col')`… — et
 * signale celles que PostgREST refuse. Ces défauts ne se voient NI à la compilation
 * (ce sont des chaînes de caractères), NI dans les tests unitaires (Supabase est
 * mocké) : seule une exécution réelle les révèle.
 *
 * Deux familles trouvées le 17/09/2026 sur `getPendingLeaveRequests` :
 *   - PGRST201 (HTTP 300) : deux clés étrangères relient les mêmes tables, l'embed est
 *     ambigu. Correctif : nommer la contrainte — `employees!ma_contrainte_fkey(...)`.
 *   - 42703 (HTTP 400) : colonne inexistante dans la ressource jointe (colonne fantôme).
 *
 * Usage :
 *   1. lancer PostgREST sur la base de test :
 *      docker run --rm -d --name onusuite-pgrst -p 3333:3000 \
 *        -e PGRST_DB_URI="postgres://postgres:postgres@host.docker.internal:55432/test_compta" \
 *        -e PGRST_DB_SCHEMAS=public -e PGRST_DB_ANON_ROLE=postgres postgrest/postgrest
 *   2. node scripts/check-embeds.mjs            (défaut : http://localhost:3333)
 *      PGRST_URL=http://... node scripts/check-embeds.mjs
 *
 * Sort en code 1 dès qu'un embed est refusé, pour pouvoir être branché en CI à la
 * suite du job `db-integration`.
 */
import { readFileSync, readdirSync, statSync } from 'fs'
import { join, relative } from 'path'
import { fileURLToPath } from 'url'
import { dirname } from 'path'

const __dirname = dirname(fileURLToPath(import.meta.url))
const ROOT = join(__dirname, '..')
const SRC = join(ROOT, 'src')
const PGRST_URL = process.env.PGRST_URL || 'http://localhost:3333'

function walk(dir) {
  const out = []
  for (const entry of readdirSync(dir)) {
    const p = join(dir, entry)
    if (statSync(p).isDirectory()) {
      if (entry === '__tests__' || entry === 'node_modules') continue
      out.push(...walk(p))
    } else if (/\.tsx?$/.test(p)) {
      out.push(p)
    }
  }
  return out
}

// Opérateurs de filtre dont le 1er argument est un nom de colonne.
const FILTERS = ['eq', 'neq', 'gt', 'gte', 'lt', 'lte', 'like', 'ilike', 'is', 'in', 'contains', 'order']

/** Table du `.from('x')` le plus proche au-dessus de la ligne i. */
function nearestTable(lines, i) {
  for (let j = i; j >= Math.max(0, i - 12); j--) {
    const m = lines[j].match(/\.from\('([a-z_0-9]+)'\)/)
    if (m) return m[1]
  }
  return null
}

/**
 * Extrait de chaque fichier :
 *  - les `select('...')` littéraux (avec ou sans ressource jointe) ;
 *  - les colonnes passées aux filtres `.eq('col', …)`, `.order('col')`, etc.
 * Les deux sont rejoués tels quels : PostgREST refuse une colonne inexistante.
 */
function extractQueries(file) {
  const lines = readFileSync(file, 'utf8').split('\n')
  const found = []
  for (let i = 0; i < lines.length; i++) {
    for (const s of lines[i].matchAll(/\.select\(\s*'([^']+)'/g)) {
      const table = nearestTable(lines, i)
      if (!table) continue
      found.push({ file: relative(ROOT, file), line: i + 1, table, select: s[1].replace(/\s+/g, ' ').trim(), kind: 'select' })
    }
    for (const f of lines[i].matchAll(/\.(\w+)\(\s*'([^']+)'/g)) {
      if (!FILTERS.includes(f[1])) continue
      const col = f[2]
      // une colonne d'une ressource jointe (`journal_entries.date`) est validée par son select
      if (col.includes('.') || col.includes(',') || !/^[a-z_0-9]+$/.test(col)) continue
      const table = nearestTable(lines, i)
      if (!table) continue
      found.push({ file: relative(ROOT, file), line: i + 1, table, select: col, kind: `filtre .${f[1]}()` })
    }
  }
  return found
}

const all = walk(SRC).flatMap(extractQueries)
const seen = new Set()
const embeds = all.filter((e) => {
  const k = `${e.table}|${e.select}`
  if (seen.has(k)) return false
  seen.add(k)
  return true
})

console.log(`${embeds.length} requêtes distinctes extraites du code, vérification contre ${PGRST_URL}\n`)

const failures = []
for (const e of embeds) {
  const url = `${PGRST_URL}/${e.table}?select=${encodeURIComponent(e.select)}&limit=1`
  let res
  try {
    res = await fetch(url)
  } catch (err) {
    console.error(`❌ PostgREST injoignable sur ${PGRST_URL} : ${err.message}`)
    console.error(`   Lancer le conteneur (voir l'en-tête de ce script) puis relancer.`)
    process.exit(2)
  }
  if (res.ok) continue
  let body
  try { body = await res.json() } catch { body = { message: await res.text() } }
  failures.push({ ...e, status: res.status, code: body.code ?? '?', message: body.message ?? '' })
}

if (failures.length === 0) {
  console.log(`✅ Les ${embeds.length} requêtes sont acceptées par PostgREST.`)
  process.exit(0)
}

const byCode = new Map()
for (const f of failures) {
  if (!byCode.has(f.code)) byCode.set(f.code, [])
  byCode.get(f.code).push(f)
}
for (const [code, items] of [...byCode].sort((a, b) => b[1].length - a[1].length)) {
  console.log(`=== ${code} (HTTP ${items[0].status}) — ${items.length} requête(s) refusée(s) ===`)
  for (const f of items) {
    console.log(`  ${f.file}:${f.line}  [${f.table}]`)
    console.log(`     ${f.kind === 'select' ? 'select' : f.kind} : ${f.select}`)
    console.log(`     erreur : ${f.message}`)
  }
  console.log()
}
console.error(`❌ ${failures.length} requête(s) sur ${embeds.length} sont refusées par PostgREST.`)
process.exit(1)
