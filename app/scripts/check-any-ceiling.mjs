#!/usr/bin/env node
/**
 * Plafond des `any` explicites — production ET tests, comptés séparément.
 *
 * Pourquoi ce garde-fou : un `any` désactive tout contrôle sur la valeur qu'il
 * porte. `src/types/database-generated.ts` (382 tables, régénéré et vérifié par
 * la CI) et `src/types/dbRow.ts` (`Row<T>`, `Joined<T,K>`) existent déjà pour
 * donner le bon type — mais la dette est grande (mesurée le 2026-10-01 : 1811 en
 * production, 796 dans les tests).
 *
 * Doctrine du dépôt (identique à check-knip-ceiling.mjs) : le plafond est GELÉ.
 * Une augmentation fait échouer la CI ; une diminution abaisse le plafond
 * automatiquement. Le compteur ne peut donc que descendre.
 *
 * Deux compteurs distincts parce que les deux gisements n'ont pas le même poids :
 * un `any` dans un test ne masque pas un bug de production, un `any` dans
 * `src/lib/queries` ou `src/pages` si.
 *
 * Le comptage est volontairement restreint aux POSITIONS DE TYPE
 * (`: any`, `as any`, `<any>`, `any[]`) pour ne pas compter le mot anglais
 * « any » dans un commentaire ou un libellé.
 */
import { readFileSync, writeFileSync, existsSync, readdirSync, statSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const appRoot = join(__dirname, '..')
const srcDir = join(appRoot, 'src')
const ceilingFile = join(appRoot, '.any-ceiling.json')

// Positions de type uniquement — jamais le mot « any » isolé.
const ANY_RE = /:\s*any\b|\bas\s+any\b|<\s*any\s*>|\bany\[\]/g

// Un fichier de test (le gisement « toléré, mais gelé lui aussi »).
function isTestFile(file) {
  return /__tests__\//.test(file) || /\.test\.(ts|tsx)$/.test(file) || /__screen__\//.test(file)
}

function walk(dir, acc = []) {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry)
    if (statSync(full).isDirectory()) walk(full, acc)
    else if (/\.(ts|tsx)$/.test(entry)) acc.push(full)
  }
  return acc
}

const files = walk(srcDir)
let production = 0
let tests = 0
const perFile = {}

for (const file of files) {
  const content = readFileSync(file, 'utf8')
  const count = (content.match(ANY_RE) || []).length
  if (count === 0) continue
  if (isTestFile(file)) tests += count
  else {
    production += count
    perFile[file.replace(appRoot + '/', '')] = count
  }
}

const total = production + tests

console.log('=== Plafond des `any` explicites ===')
console.log(`Production: ${production} (plafond: ${(existsSync(ceilingFile) ? JSON.parse(readFileSync(ceilingFile, 'utf8')) : {}).production ?? '—'})`)
console.log(`Tests:      ${tests} (plafond: ${(existsSync(ceilingFile) ? JSON.parse(readFileSync(ceilingFile, 'utf8')) : {}).tests ?? '—'})`)
console.log(`TOTAL:      ${total}`)
console.log('')

// Charger / créer le plafond gelé
let ceiling
if (existsSync(ceilingFile)) {
  ceiling = JSON.parse(readFileSync(ceilingFile, 'utf8'))
} else {
  ceiling = { production, tests, total, frozenAt: new Date().toISOString().slice(0, 10) }
  writeFileSync(ceilingFile, JSON.stringify(ceiling, null, 2) + '\n')
}

let failed = false
if (production > ceiling.production) {
  console.error(`❌ Production: ${production} > plafond ${ceiling.production} — ${production - ceiling.production} nouveau(x) \`any\`.`)
  console.error('   Fichiers de production concernés (top 15) :')
  for (const [file, n] of Object.entries(perFile).sort((a, b) => b[1] - a[1]).slice(0, 15)) {
    console.error(`   - ${n}  ${file}`)
  }
  failed = true
}
if (tests > ceiling.tests) {
  console.error(`❌ Tests: ${tests} > plafond ${ceiling.tests} — ${tests - ceiling.tests} nouveau(x) \`any\`.`)
  failed = true
}
if (total > ceiling.total) {
  console.error(`❌ TOTAL: ${total} > plafond ${ceiling.total}`)
  failed = true
}

if (failed) {
  console.error('\nÉCHEC : la dette de `any` a augmenté.')
  console.error('  Cible : `Row<\'table\'>` / `Joined<\'table\',\'col\'>` de @/types/dbRow,')
  console.error('  ou le type de @/types. Ne pas relever le plafond pour faire passer la CI.')
  process.exit(1)
}

if (total < ceiling.total) {
  const next = { production, tests, total, frozenAt: new Date().toISOString().slice(0, 10) }
  writeFileSync(ceilingFile, JSON.stringify(next, null, 2) + '\n')
  console.log(`✅ OK : ${total} \`any\` (plafond abaissé de ${ceiling.total} à ${total} : production ${ceiling.production}→${production}, tests ${ceiling.tests}→${tests})`)
} else {
  console.log(`✅ OK : ${total} \`any\` (conforme au plafond)`)
}
