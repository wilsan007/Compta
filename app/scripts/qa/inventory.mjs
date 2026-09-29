// ============================================================
// qa/inventory.mjs — l'inventaire de tournée de l'essaim QA
//
// Lit `src/App.tsx` et en tire la liste RÉELLE des routes, leur module
// (premier segment du chemin), l'écran source qui les sert et, quand il
// existe, le nom du composant lazy. C'est le plan que le dispatcheur découpe
// en shards : rien n'est écrit à la main, donc aucune page ne peut être
// oubliée par paresse — seule une route absente de `App.tsx` l'est.
//
// Sortie : `.qa/inventory.json` (+ résumé à l'écran).
// Usage  : node scripts/qa/inventory.mjs [--json]
// ============================================================
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const DIR = path.dirname(fileURLToPath(import.meta.url))
export const APP_DIR = path.resolve(DIR, '../..')
export const QA_DIR = path.join(APP_DIR, '.qa')
const APP_TSX = path.join(APP_DIR, 'src/App.tsx')

/** Import path → fichier source réel (pour dire où corriger). */
function sourceOf(importPath) {
  const rel = importPath.replace(/^@\//, 'src/')
  for (const ext of ['.tsx', '.ts', '/index.tsx', '/index.ts']) {
    const full = path.join(APP_DIR, rel + ext)
    if (fs.existsSync(full)) return full.slice(APP_DIR.length + 1)
  }
  return null
}

export function buildInventory() {
  const src = fs.readFileSync(APP_TSX, 'utf8')

  // 1. Les écrans importés en lazy : composant → chemin d'import.
  const lazyMap = new Map()
  for (const m of src.matchAll(/const\s+(\w+)\s*=\s*lazy\(\(\)\s*=>\s*import\('([^']+)'\)/g)) {
    lazyMap.set(m[1], m[2])
  }
  // Les imports statiques (layouts, hubs) comptent aussi : ils servent des routes.
  for (const m of src.matchAll(/import\s+\{([^}]+)\}\s+from\s+'([^']+)'/g)) {
    for (const name of m[1].split(',').map((s) => s.trim().split(/\s+as\s+/).pop()).filter(Boolean)) {
      if (!lazyMap.has(name)) lazyMap.set(name, m[2])
    }
  }

  // 2. Les routes, avec la résolution des chemins RELATIFS et l'imbrication.
  //    `<Route path="documents">` sous `<Route path="/employee">` vaut
  //    `/employee/documents`. Un attribut JSX comme `element={<X />}` contient
  //    un `>` et un `/>` : une expression régulière s'y trompe (mesuré deux
  //    fois le 29/09/2026, avec des chemins empilés de 900 caractères). On lit
  //    donc la balise caractère par caractère, en suivant les accolades.
  const events = []
  for (let i = 0; i < src.length;) {
    const openIdx = src.indexOf('<Route', i)
    const closeIdx = src.indexOf('</Route>', i)
    if (openIdx === -1 && closeIdx === -1) break
    if (closeIdx !== -1 && (openIdx === -1 || closeIdx < openIdx)) { events.push({ close: true }); i = closeIdx + 8; continue }
    let j = openIdx + 6
    let depth = 0
    let quote = null
    while (j < src.length) {
      const ch = src[j]
      if (quote) { if (ch === quote) quote = null }
      else if (ch === '"' || ch === "'") quote = ch
      else if (ch === '{') depth++
      else if (ch === '}') depth--
      else if (ch === '>' && depth === 0) break
      j++
    }
    const raw = src.slice(openIdx, j + 1)
    events.push({ raw, selfClosing: raw.endsWith('/>') })
    i = j + 1
  }

  const routes = []
  const seen = new Set()
  const stack = []
  for (const ev of events) {
    if (ev.close) { stack.pop(); continue }
    const attrs = ev.raw.slice(6, -1)
    const p = /path="([^"]*)"/.exec(attrs)
    if (!ev.selfClosing) stack.push(p ? p[1] : '')
    if (!p) continue
    const raw = p[1]
    if (raw === '*' || raw.includes(':')) continue            // redirection, ou route à identifiant
    const parents = stack.slice(0, -1).filter(Boolean)
    const full = (raw.startsWith('/') ? raw : [...parents, raw].join('/')).replace(/\/{2,}/g, '/')
    const path = full.startsWith('/') ? full : `/${full}`
    if (seen.has(path)) continue
    seen.add(path)
    const el = /element=\{<\s*(\w+)/.exec(attrs)
    const component = el ? el[1] : null
    const importPath = component ? lazyMap.get(component) ?? null : null
    routes.push({
      path,
      component,
      import: importPath,
      source: importPath ? sourceOf(importPath) : null,
      module: path === '/' ? 'home' : path.split('/').filter(Boolean)[0],
      group: path.split('/').filter(Boolean).slice(0, 2).join('/') || 'home',
    })
  }
  routes.sort((a, b) => a.path.localeCompare(b.path))

  const byModule = {}
  for (const r of routes) byModule[r.module] = (byModule[r.module] ?? 0) + 1

  return {
    generatedAt: new Date().toISOString(),
    appTsx: 'src/App.tsx',
    totalRoutes: routes.length,
    modules: Object.fromEntries(Object.entries(byModule).sort((a, b) => b[1] - a[1])),
    routes,
  }
}

export function writeInventory(inv) {
  fs.mkdirSync(QA_DIR, { recursive: true })
  const out = path.join(QA_DIR, 'inventory.json')
  fs.writeFileSync(out, JSON.stringify(inv, null, 2))
  return out
}

export function loadInventory() {
  const file = path.join(QA_DIR, 'inventory.json')
  if (fs.existsSync(file)) return JSON.parse(fs.readFileSync(file, 'utf8'))
  const inv = buildInventory()
  writeInventory(inv)
  return inv
}

// Exécuté directement : on imprime le plan de tournée.
if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  const inv = buildInventory()
  if (process.argv.includes('--json')) {
    console.log(JSON.stringify(inv, null, 2))
  } else {
    const file = writeInventory(inv)
    console.log(`inventaire : ${inv.totalRoutes} route(s) servie(s) par ${Object.keys(inv.modules).length} module(s)`)
    for (const [mod, n] of Object.entries(inv.modules)) console.log(`  ${String(n).padStart(3)}  ${mod}`)
    const orphans = inv.routes.filter((r) => !r.source)
    if (orphans.length) {
      console.log(`\n⚠️  ${orphans.length} route(s) sans écran source identifiable (composant non importé) :`)
      for (const r of orphans.slice(0, 20)) console.log(`  ${r.path}  ← ${r.component ?? 'aucun élément'}`)
    }
    console.log(`\n→ ${file.slice(APP_DIR.length + 1)}`)
  }
}
