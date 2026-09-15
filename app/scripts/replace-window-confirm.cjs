#!/usr/bin/env node
// Remplace window.confirm(X) par confirmSync(X) dans tous les fichiers
// confirmSync est un wrapper qui sera progressivement remplacé par confirmDialog (async)
const fs = require('fs')
const path = require('path')
const { execSync } = require('child_process')

const root = path.resolve(__dirname, '..')
const files = execSync(`grep -rl "window\\.confirm" src/ --include="*.tsx" --include="*.ts"`, { cwd: root, encoding: 'utf8' })
  .trim().split('\n')
  .filter(f => f && !f.includes('useConfirm.tsx') && !f.includes('confirm.tsx'))

let totalReplaced = 0
let filesModified = 0

for (const relFile of files) {
  const filePath = path.join(root, relFile)
  let content = fs.readFileSync(filePath, 'utf8')
  const original = content

  // Compter les occurrences
  const count = (content.match(/window\.confirm/g) || []).length

  // 1. Remplacer window.confirm par confirmSync
  content = content.replace(/window\.confirm/g, 'confirmSync')

  // 2. Ajouter l'import de confirmSync si pas déjà présent
  if (!content.includes('confirmSync') || (content.includes('confirmSync') && !content.includes('from \'@/lib/confirm\''))) {
    // Vérifier si l'import existe déjà
    if (!content.includes("from '@/lib/confirm'")) {
      // Trouver la dernière ligne d'import
      const importLines = content.match(/^import .+$/gm) || []
      if (importLines.length > 0) {
        const lastImport = importLines[importLines.length - 1]
        content = content.replace(
          lastImport,
          lastImport + "\nimport { confirmSync } from '@/lib/confirm'"
        )
      } else {
        content = "import { confirmSync } from '@/lib/confirm'\n" + content
      }
    }
  }

  if (content !== original) {
    fs.writeFileSync(filePath, content)
    filesModified++
    totalReplaced += count
    console.log(`✅ ${relFile}: ${count} remplacement(s)`)
  }
}

console.log(`\nTotal: ${filesModified} fichiers modifiés, ${totalReplaced} remplacements`)
