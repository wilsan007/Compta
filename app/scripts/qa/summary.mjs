// Compte les verdicts d'une tournée : par règle, par module, par gravité.
// Sert à lire un rapport sans se noyer dans ses lignes.
// Usage : node scripts/qa/summary.mjs
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const APP = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..')
const file = path.join(APP, '.qa-out/findings.json')
if (!fs.existsSync(file)) { console.error('aucune mesure : lancer dispatch.mjs puis validate.mjs'); process.exit(2) }
const findings = JSON.parse(fs.readFileSync(file, 'utf8'))

const count = (key) => {
  const by = {}
  for (const f of findings) by[f[key]] = (by[f[key]] ?? 0) + 1
  return Object.entries(by).sort((a, b) => b[1] - a[1])
}
console.log(`${findings.length} défaut(s)\n`)
console.log('par gravité :')
for (const [k, v] of count('severity')) console.log(`  ${String(v).padStart(4)}  ${k}`)
console.log('\npar règle :')
for (const [k, v] of count('id')) console.log(`  ${String(v).padStart(4)}  ${k}`)
console.log('\npar module :')
for (const [k, v] of count('module')) console.log(`  ${String(v).padStart(4)}  ${k}`)
console.log('\npar gabarit :')
for (const [k, v] of count('viewport')) console.log(`  ${String(v).padStart(4)}  ${k}`)
const worst = {}
for (const f of findings) worst[f.route] = (worst[f.route] ?? 0) + 1
console.log('\nécrans les plus atteints :')
for (const [k, v] of Object.entries(worst).sort((a, b) => b[1] - a[1]).slice(0, 12)) console.log(`  ${String(v).padStart(4)}  ${k}`)
