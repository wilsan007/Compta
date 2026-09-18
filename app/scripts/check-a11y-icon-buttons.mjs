#!/usr/bin/env node
/**
 * LOT7-07 — Garde-fou : tout bouton n'affichant qu'une icône doit avoir un libellé.
 *
 * Un `<button><Trash2 /></button>` est annoncé « bouton » par un lecteur d'écran :
 * rien ne dit ce qu'il fait. Le libellé passe par `aria-label` (bouton natif) ou par
 * la prop `ariaLabel` du composant `Button` de `ui.tsx`, qui pose aussi `title`.
 *
 * 127 boutons muets ont été corrigés le 18/09/2026 ; ce contrôle empêche le retour.
 * Usage : node scripts/check-a11y-icon-buttons.mjs
 */
import { readFileSync, readdirSync, statSync } from 'fs'
import { join, relative, dirname } from 'path'
import { fileURLToPath } from 'url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const SRC = join(ROOT, 'src')

function walk(dir) {
  const out = []
  for (const e of readdirSync(dir)) {
    const p = join(dir, e)
    if (statSync(p).isDirectory()) {
      if (e === '__tests__' || e === 'node_modules') continue
      out.push(...walk(p))
    } else if (p.endsWith('.tsx')) out.push(p)
  }
  return out
}

// <Button …><Icone … /></Button> : un bouton dont le seul enfant est une icône.
const ICON_ONLY = /<(Button|button)\b([^>]*)>\s*(?:<[A-Z][A-Za-z0-9]*\s[^>]*\/>|<[A-Z][A-Za-z0-9]*\/>)\s*<\/\1>/g

const offenders = []
for (const file of walk(SRC)) {
  const src = readFileSync(file, 'utf8')
  for (const m of src.matchAll(ICON_ONLY)) {
    const attrs = m[2]
    if (/\baria-label\b|\bariaLabel\b|\btitle=/.test(attrs)) continue
    offenders.push({ file: relative(ROOT, file), line: src.slice(0, m.index).split('\n').length })
  }
}

if (offenders.length === 0) {
  console.log('✅ Tous les boutons icône portent un libellé accessible.')
  process.exit(0)
}
console.error(`❌ ${offenders.length} bouton(s) n'affichant qu'une icône, sans libellé accessible :`)
for (const o of offenders) console.error(`   ${o.file}:${o.line}`)
console.error(`\n   Ajouter ariaLabel={…} sur <Button>, ou aria-label={…} sur un <button> natif.`)
console.error(`   Les libellés usuels existent déjà : common.json → actions.close, actions.delete, actions.edit…`)
process.exit(1)
