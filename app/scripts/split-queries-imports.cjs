#!/usr/bin/env node
// Remplace les imports from '@/lib/queries' par des imports directs depuis les fichiers spécifiques
const fs = require('fs')
const path = require('path')
const { execSync } = require('child_process')

const root = path.resolve(__dirname, '..')

// Récupérer tous les exports du barrel
const barrelContent = fs.readFileSync(path.join(root, 'src/lib/queries/index.ts'), 'utf8')

// Map: nom d'export -> fichier source
const exportMap = {}

// Parse les export * from './file'
const starExports = barrelContent.matchAll(/export \* from '\.\/(\w+)'/g)
for (const m of starExports) {
  const file = m[1]
  const filePath = path.join(root, `src/lib/queries/${file}.ts`)
  if (!fs.existsSync(filePath)) continue
  const content = fs.readFileSync(filePath, 'utf8')
  // Extraire tous les exports nommés
  const namedExports = content.matchAll(/export (?:async )?(?:function|const|class|interface|type|enum) (\w+)/g)
  for (const e of namedExports) {
    exportMap[e[1]] = file
  }
}

// Parse les exports nommés individuels
const namedExports = barrelContent.matchAll(/export \{([^}]+)\} from '\.\/(\w+)'/g)
for (const m of namedExports) {
  const names = m[1].split(',').map(n => {
    const parts = n.trim().split(/\s+as\s+/)
    return parts[0].trim()
  })
  const file = m[2]
  for (const name of names) {
    if (name) exportMap[name] = file
  }
}

console.log('Exports mappés:', Object.keys(exportMap).length)

// Récupérer tous les fichiers qui importent depuis '@/lib/queries'
const files = execSync(`grep -rl "from '@/lib/queries'" src/ --include="*.tsx" --include="*.ts"`, { cwd: root, encoding: 'utf8' })
  .trim().split('\n')
  .filter(f => f && !f.includes('queries/index.ts'))

let totalModified = 0

for (const relFile of files) {
  const filePath = path.join(root, relFile)
  let content = fs.readFileSync(filePath, 'utf8')
  const original = content

  // Trouver tous les imports from '@/lib/queries'
  // Pattern 1: import { X, Y } from '@/lib/queries'
  // Pattern 2: import type { X } from '@/lib/queries'
  // Pattern 3: import X, { Y } from '@/lib/queries' (rare)

  // Pattern multi-line: import {\n  X,\n  Y,\n} from '@/lib/queries'
  const importRegex = /import\s+(type\s+)?\{([^}]+)\}\s+from\s+'@\/lib\/queries'/gs

  content = content.replace(importRegex, (match, typePrefix, importNames) => {
    const names = importNames.split(',').map(n => n.trim()).filter(n => n)
    
    // Grouper par fichier source
    const byFile = {}
    const unmapped = []
    
    for (const name of names) {
      // Gérer les alias: import { X as Y }
      const parts = name.split(/\s+as\s+/)
      const exportName = parts[0].trim()
      const aliasName = parts[1]?.trim() || exportName
      
      const sourceFile = exportMap[exportName]
      if (sourceFile) {
        if (!byFile[sourceFile]) byFile[sourceFile] = []
        byFile[sourceFile].push(parts.length > 1 ? `${exportName} as ${aliasName}` : exportName)
      } else {
        unmapped.push(name)
      }
    }
    
    // Générer les imports
    const importLines = []
    for (const [file, fileNames] of Object.entries(byFile)) {
      const prefix = typePrefix ? 'type ' : ''
      importLines.push(`import ${prefix}{ ${fileNames.join(', ')} } from '@/lib/queries/${file}'`)
    }
    
    if (unmapped.length > 0) {
      // Garder l'import original pour les non-mappés
      importLines.push(`import ${typePrefix || ''}{ ${unmapped.join(', ')} } from '@/lib/queries'`)
    }
    
    return importLines.join('\n')
  })

  if (content !== original) {
    fs.writeFileSync(filePath, content)
    totalModified++
  }
}

console.log(`Fichiers modifiés: ${totalModified}/${files.length}`)
