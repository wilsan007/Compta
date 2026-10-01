#!/usr/bin/env node
/**
 * Plafond des `console.error` — production ET tests, comptés séparément.
 *
 * Pourquoi ce garde-fou : le dépôt a déjà l'outillage du bon remplacement
 * (`src/lib/silentFailureGuard.ts`, `npm run audit:silent`, et `toast()` pour
 * l'utilisateur). Un `console.error` dans un écran est une erreur que PERSONNE
 * ne verra jamais — un succès partiel affiché comme un succès. La dette est
 * mesurée le 2026-10-01 : 486 en production, 1 dans les tests.
 *
 * Doctrine du dépôt (identique à check-knip-ceiling.mjs) : le plafond est GELÉ.
 * Hausse ⇒ échec CI ; baisse ⇒ plafond abaissé automatiquement.
 */
import { readFileSync, writeFileSync, existsSync, readdirSync, statSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const appRoot = join(__dirname, '..')
const srcDir = join(appRoot, 'src')
const ceilingFile = join(appRoot, '.console-error-ceiling.json')

const CE_RE = /console\.error/g

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
  const count = (content.match(CE_RE) || []).length
  if (count === 0) continue
  if (isTestFile(file)) tests += count
  else {
    production += count
    perFile[file.replace(appRoot + '/', '')] = count
  }
}

const total = production + tests
const currentCeiling = existsSync(ceilingFile) ? JSON.parse(readFileSync(ceilingFile, 'utf8')) : null

console.log('=== Plafond des `console.error` ===')
console.log(`Production: ${production} (plafond: ${currentCeiling?.production ?? '—'})`)
console.log(`Tests:      ${tests} (plafond: ${currentCeiling?.tests ?? '—'})`)
console.log(`TOTAL:      ${total}`)
console.log('')

let ceiling
if (currentCeiling) {
  ceiling = currentCeiling
} else {
  ceiling = { production, tests, total, frozenAt: new Date().toISOString().slice(0, 10) }
  writeFileSync(ceilingFile, JSON.stringify(ceiling, null, 2) + '\n')
}

let failed = false
if (production > ceiling.production) {
  console.error(`❌ Production: ${production} > plafond ${ceiling.production} — ${production - ceiling.production} nouveau(x) \`console.error\`.`)
  console.error('   Fichiers de production concernés (top 15) :')
  for (const [file, n] of Object.entries(perFile).sort((a, b) => b[1] - a[1]).slice(0, 15)) {
    console.error(`   - ${n}  ${file}`)
  }
  failed = true
}
if (tests > ceiling.tests) {
  console.error(`❌ Tests: ${tests} > plafond ${ceiling.tests} — ${tests - ceiling.tests} nouveau(x) \`console.error\`.`)
  failed = true
}
if (total > ceiling.total) {
  console.error(`❌ TOTAL: ${total} > plafond ${ceiling.total}`)
  failed = true
}

if (failed) {
  console.error('\nÉCHEC : la dette de `console.error` a augmenté.')
  console.error('  Cible : `toast(\'error\', …)` pour l\'utilisateur (déjà importé dans la plupart des écrans),')
  console.error('  et `reportSilentFailure()` de @/lib/silentFailureGuard pour la trace. Ne pas relever le plafond.')
  process.exit(1)
}

if (total < ceiling.total) {
  const next = { production, tests, total, frozenAt: new Date().toISOString().slice(0, 10) }
  writeFileSync(ceilingFile, JSON.stringify(next, null, 2) + '\n')
  console.log(`✅ OK : ${total} \`console.error\` (plafond abaissé de ${ceiling.total} à ${total} : production ${ceiling.production}→${production}, tests ${ceiling.tests}→${tests})`)
} else {
  console.log(`✅ OK : ${total} \`console.error\` (conforme au plafond)`)
}
