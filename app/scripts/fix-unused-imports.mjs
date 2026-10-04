// Correcteur automatique des imports inutilisés (TS6196).
// S'appuie sur la sortie exacte de `tsc -b` : aucune heuristique.
// Usage: node scripts/fix-unused-imports.mjs [--dry]
import { execSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'

const dry = process.argv.includes('--dry')
const root = process.cwd()

// 1. Capturer les diagnostics TS6196
let out = ''
try {
  out = execSync('npx tsc -b --pretty false 2>&1', { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 })
} catch (e) {
  out = e.stdout?.toString() || '' + (e.stderr?.toString() || '')
}

const unusedByFile = new Map()
const re = /^(.+?)\((\d+),(\d+)\): error TS6196: '([^']+)' is declared but never used/
for (const line of out.split('\n')) {
  const m = line.match(re)
  if (!m) continue
  const file = m[1]
  if (!unusedByFile.has(file)) unusedByFile.set(file, new Set())
  unusedByFile.get(file).add(m[4])
}

console.log(`Fichiers avec imports inutilisés: ${unusedByFile.size}`)
let totalNames = 0
for (const s of unusedByFile.values()) totalNames += s.size
console.log(`Noms inutilisés au total: ${totalNames}`)

// 2. Supprimer ces noms des clauses d'import nommées
const importRe = /import\s+(type\s+)?\{([^}]*)\}\s*from\s*['"][^'"]+['"];?/gs
let totalRemoved = 0

for (const [relFile, names] of unusedByFile) {
  const abs = path.resolve(root, relFile)
  if (!fs.existsSync(abs)) { console.log(`(absent) ${relFile}`); continue }
  let src = fs.readFileSync(abs, 'utf8')
  let removedInFile = 0

  src = src.replace(importRe, (full, typeKw, clause) => {
    const items = clause.split(',').map(s => s.trim()).filter(Boolean)
    const kept = items.filter(it => {
      const name = it.split(/\s+as\s+/)[0].trim() // import alias: Original as Alias → flagged name is the local one
      const alias = it.includes(' as ') ? it.split(/\s+as\s+/)[1].trim() : name
      const local = alias || name
      if (names.has(local)) { removedInFile++; return false }
      return true
    })
    if (kept.length === 0) return '' // clause vide → supprimer tout l'import
    return `import ${typeKw || ''}{ ${kept.join(', ')} } from ${full.match(/from\s*(['"][^'"]+['"]);?/)[1]};`
  })

  if (removedInFile > 0) {
    totalRemoved += removedInFile
    console.log(`${relFile}: ${removedInFile} import(s) supprimé(s)`)
    if (!dry) fs.writeFileSync(abs, src)
  }
}

console.log(`\nTotal supprimé: ${totalRemoved}${dry ? ' (DRY — rien écrit)' : ''}`)
