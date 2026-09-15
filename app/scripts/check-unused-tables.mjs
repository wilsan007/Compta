#!/usr/bin/env node
/**
 * LOT6-04 : Détection des tables métier jamais lues par le frontend
 *
 * Croise les tables du schéma SQL avec les références dans src/lib/queries/
 * pour identifier les tables qui ne sont jamais lues par l'application.
 *
 * Le plafond est gelé dans .unused-tables-ceiling.json.
 * Toute augmentation fait échouer la CI.
 */

import { readFileSync, writeFileSync, existsSync, readdirSync, statSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const appRoot = join(__dirname, '..')
const sqlDir = join(appRoot, 'sql')
const queriesDir = join(appRoot, 'src', 'lib', 'queries')
const ceilingFile = join(appRoot, '.unused-tables-ceiling.json')

// 1. Extraire les noms de tables depuis le schéma SQL
function extractTableNames() {
  const tables = new Set()
  const files = readdirSync(sqlDir).filter(f => f.endsWith('.sql'))
  for (const file of files) {
    const content = readFileSync(join(sqlDir, file), 'utf8')
    // CREATE TABLE IF NOT EXISTS table_name (
    const matches = content.matchAll(/CREATE\s+TABLE(?:\s+IF\s+NOT\s+EXISTS)?\s+(\w+)/gi)
    for (const m of matches) {
      tables.add(m[1])
    }
  }
  return Array.from(tables).sort()
}

// 2. Extraire les références de tables dans src/lib/queries/
function extractTableReferences() {
  const refs = new Set()
  function scanDir(dir) {
    for (const entry of readdirSync(dir)) {
      const fullPath = join(dir, entry)
      const stat = statSync(fullPath)
      if (stat.isDirectory()) {
        scanDir(fullPath)
      } else if (entry.endsWith('.ts') || entry.endsWith('.tsx')) {
        const content = readFileSync(fullPath, 'utf8')
        // .from('table_name') ou .from("table_name")
        const fromMatches = content.matchAll(/\.from\(['"`](\w+)['"`]/g)
        for (const m of fromMatches) refs.add(m[1])
        // .rpc('function_name' — pas une table mais on l'ignore
      }
    }
  }
  scanDir(queriesDir)
  // Aussi scanner src/pages pour les requêtes directes
  const pagesDir = join(appRoot, 'src', 'pages')
  if (existsSync(pagesDir)) {
    function scanPages(dir) {
      for (const entry of readdirSync(dir)) {
        const fullPath = join(dir, entry)
        const stat = statSync(fullPath)
        if (stat.isDirectory()) {
          scanPages(fullPath)
        } else if (entry.endsWith('.tsx')) {
          const content = readFileSync(fullPath, 'utf8')
          const fromMatches = content.matchAll(/\.from\(['"`](\w+)['"`]/g)
          for (const m of fromMatches) refs.add(m[1])
        }
      }
    }
    scanPages(pagesDir)
  }
  return refs
}

// 3. Tables métier (exclure les tables système, vues, et tables d'audit)
const SYSTEM_TABLE_PREFIXES = [
  'pg_', 'schema_', 'sql_', 'cron_', 'supabase_', 'audit_',
]
const SYSTEM_TABLES = [
  'migrations', 'sql_migrations_tracker', 'rls_audit',
  'supabase_migrations', 'schema_migrations',
]

function isBusinessTable(name) {
  if (SYSTEM_TABLES.includes(name)) return false
  for (const prefix of SYSTEM_TABLE_PREFIXES) {
    if (name.startsWith(prefix)) return false
  }
  // Exclure les vues (commencent souvent par v_)
  if (name.startsWith('v_')) return false
  return true
}

// 4. Calculer les tables non lues
const allTables = extractTableNames()
const referencedTables = extractTableReferences()
const businessTables = allTables.filter(isBusinessTable)
const unusedTables = businessTables.filter(t => !referencedTables.has(t))

console.log('=== LOT6-04 : Tables métier jamais lues par le frontend ===')
console.log(`Tables totales:     ${allTables.length}`)
console.log(`Tables métier:      ${businessTables.length}`)
console.log(`Tables référencées: ${referencedTables.size}`)
console.log(`Tables non lues:    ${unusedTables.length}`)
console.log('')

if (unusedTables.length > 0 && unusedTables.length <= 50) {
  console.log('Tables non lues:')
  for (const t of unusedTables) {
    console.log(`  - ${t}`)
  }
  console.log('')
}

// 5. Vérifier le plafond
let ceiling
if (existsSync(ceilingFile)) {
  ceiling = JSON.parse(readFileSync(ceilingFile, 'utf8'))
} else {
  ceiling = { unusedTables: unusedTables.length, frozenAt: '2026-09-14' }
  writeFileSync(ceilingFile, JSON.stringify(ceiling, null, 2) + '\n')
}

if (unusedTables.length > ceiling.unusedTables) {
  console.error(`❌ ÉCHEC : ${unusedTables.length} tables non lues > plafond ${ceiling.unusedTables}`)
  console.error('   Nouvelles tables non lues:')
  for (const t of unusedTables) {
    console.error(`   - ${t}`)
  }
  process.exit(1)
} else if (unusedTables.length < ceiling.unusedTables) {
  const newCeiling = { unusedTables: unusedTables.length, frozenAt: new Date().toISOString().slice(0, 10) }
  writeFileSync(ceilingFile, JSON.stringify(newCeiling, null, 2) + '\n')
  console.log(`✅ OK : ${unusedTables.length} tables non lues (plafond mis à jour de ${ceiling.unusedTables} à ${unusedTables.length})`)
} else {
  console.log(`✅ OK : ${unusedTables.length} tables non lues (conforme au plafond)`)
}
