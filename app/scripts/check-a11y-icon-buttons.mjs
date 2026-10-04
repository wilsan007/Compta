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

/**
 * Trouve la fin de la balise ouvrante à partir de l'indice du `<`.
 * Une expression régulière ne suffit pas : un attribut JSX contient souvent un `>`
 * (`onClick={() => …}`, une chaîne, une comparaison). Il faut suivre les accolades et
 * les guillemets. La première version de ce contrôle s'y est laissé prendre dans les
 * deux sens : elle ratait les boutons écrits sur plusieurs lignes, puis, une fois le
 * motif élargi, elle signalait des boutons qui portent une icône ET du texte.
 */
function endOfOpenTag(src, i) {
  let depth = 0
  let quote = null
  for (let k = i; k < src.length; k++) {
    const c = src[k]
    if (quote) {
      if (c === quote && src[k - 1] !== '\\') quote = null
      continue
    }
    if (c === '"' || c === "'" || c === '`') { quote = c; continue }
    if (c === '{') { depth++; continue }
    if (c === '}') { depth--; continue }
    if (depth === 0 && c === '>') return k
  }
  return -1
}

/** Le contenu d'un bouton se réduit-il à une seule balise auto-fermante ? */
function isIconOnly(inner) {
  const trimmed = inner.trim()
  if (!trimmed.startsWith('<') || !trimmed.endsWith('/>')) return false
  // une seule balise : pas d'autre `<` après la première
  if (trimmed.slice(1).includes('<')) return false
  // une icône commence par une majuscule (composant), pas une balise HTML
  return /^<[A-Z]/.test(trimmed)
}

const offenders = []
for (const file of walk(SRC)) {
  const src = readFileSync(file, 'utf8')
  for (const m of src.matchAll(/<(Button|button)(?=[\s>])/g)) {
    const tag = m[1]
    const openEnd = endOfOpenTag(src, m.index)
    if (openEnd === -1) continue
    if (src[openEnd - 1] === '/') continue // balise auto-fermante : pas d'enfant
    const attrs = src.slice(m.index + tag.length + 1, openEnd)
    const close = src.indexOf(`</${tag}>`, openEnd)
    if (close === -1) continue
    const inner = src.slice(openEnd + 1, close)
    // un bouton imbriqué dans le contenu : on laisse l'itération suivante le traiter
    if (inner.includes(`<${tag}`)) continue
    if (!isIconOnly(inner)) continue
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
