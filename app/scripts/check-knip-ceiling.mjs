#!/usr/bin/env node
/**
 * LOT6-04 : Garde-fou objets sans consommateur
 *
 * Exécute knip et vérifie que le nombre total d'objets morts ne dépasse pas
 * le plafond gelé. Toute augmentation fait échouer la CI.
 *
 * Le plafond est intentionnellement gelé : on ne veut pas que des nouveaux
 * exports morts s'accumulent. Les diminutions sont acceptées et mettent
 * automatiquement à jour le plafond.
 */
import { execSync } from 'node:child_process'
import { readFileSync, writeFileSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const appRoot = join(__dirname, '..')
const ceilingFile = join(appRoot, '.knip-ceiling.json')

// Plafond par défaut si aucun fichier n'existe
const DEFAULT_CEILING = {
  files: 72,
  dependencies: 1,
  devDependencies: 1,
  exports: 25,
  types: 13,
  total: 112,
  frozenAt: '2026-09-14',
}

// Charger le plafond
let ceiling
if (existsSync(ceilingFile)) {
  ceiling = JSON.parse(readFileSync(ceilingFile, 'utf8'))
} else {
  ceiling = DEFAULT_CEILING
  writeFileSync(ceilingFile, JSON.stringify(DEFAULT_CEILING, null, 2) + '\n')
}

// Exécuter knip
let knipOutput
try {
  knipOutput = execSync('npx knip --reporter compact', {
    cwd: appRoot,
    encoding: 'utf8',
    timeout: 120000,
  })
} catch (err) {
  // knip retourne exit code 1 quand il trouve des objets morts
  knipOutput = err.stdout || ''
}

// Parser les compteurs
const counts = {
  files: 0,
  dependencies: 0,
  devDependencies: 0,
  exports: 0,
  types: 0,
}

const fileMatch = knipOutput.match(/Unused files \((\d+)\)/)
const depMatch = knipOutput.match(/Unused dependencies \((\d+)\)/)
const devDepMatch = knipOutput.match(/Unused devDependencies \((\d+)\)/)
const exportMatch = knipOutput.match(/Unused exports \((\d+)\)/)
const typeMatch = knipOutput.match(/Unused exported types \((\d+)\)/)

if (fileMatch) counts.files = parseInt(fileMatch[1])
if (depMatch) counts.dependencies = parseInt(depMatch[1])
if (devDepMatch) counts.devDependencies = parseInt(devDepMatch[1])
if (exportMatch) counts.exports = parseInt(exportMatch[1])
if (typeMatch) counts.types = parseInt(typeMatch[1])

const total = counts.files + counts.dependencies + counts.devDependencies + counts.exports + counts.types

console.log('=== LOT6-04 : Garde-fou objets sans consommateur ===')
console.log(`Fichiers morts:     ${counts.files} (plafond: ${ceiling.files})`)
console.log(`Déps mortes:        ${counts.dependencies} (plafond: ${ceiling.dependencies})`)
console.log(`DevDeps mortes:     ${counts.devDependencies} (plafond: ${ceiling.devDependencies})`)
console.log(`Exports morts:      ${counts.exports} (plafond: ${ceiling.exports})`)
console.log(`Types morts:        ${counts.types} (plafond: ${ceiling.types})`)
console.log(`TOTAL:              ${total} (plafond: ${ceiling.total})`)
console.log('')

// Vérifier chaque catégorie
let failed = false
for (const [key, label] of [
  ['files', 'Fichiers'],
  ['dependencies', 'Dépendances'],
  ['devDependencies', 'DevDependencies'],
  ['exports', 'Exports'],
  ['types', 'Types'],
]) {
  if (counts[key] > ceiling[key]) {
    console.error(`❌ ${label}: ${counts[key]} > plafond ${ceiling[key]} — augmentation détectée`)
    failed = true
  }
}

if (total > ceiling.total) {
  console.error(`❌ TOTAL: ${total} > plafond ${ceiling.total} — augmentation détectée`)
  failed = true
}

if (failed) {
  console.error("\nÉCHEC : Le nombre d'objets morts a augmenté. Nettoyer les nouveaux exports morts.")
  process.exit(1)
} else if (total < ceiling.total) {
  // Mise à jour automatique du plafond si le compte a diminué
  const newCeiling = { ...counts, total, frozenAt: new Date().toISOString().slice(0, 10) }
  writeFileSync(ceilingFile, JSON.stringify(newCeiling, null, 2) + '\n')
  console.log(`✅ OK : ${total} objets morts (plafond mis à jour de ${ceiling.total} à ${total})`)
} else {
  console.log(`✅ OK : ${total} objets morts (conforme au plafond)`)
}
