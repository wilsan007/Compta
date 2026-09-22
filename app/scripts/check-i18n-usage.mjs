// Vérifie que les clés i18n utilisées dans le code existent dans les fichiers fr.
//
// check-i18n.mjs ne contrôle que la parité des clés entre langues ; il ne voit
// pas un appel t('a.b') dont la clé n'existe nulle part (constaté le 21/09/2026 :
// 31 clés purchaseInvoices.* absentes, common:toast.loadError appelé partout).
//
// Méthode : analyse syntaxique TypeScript de src/ (hors tests). Chaque liaison
// issue de useTranslation(ns, { keyPrefix }) — { t }, { t: tCommon }, { i18n } —
// est associée à ses espaces de noms, portée comprise (plusieurs composants d'un
// même fichier peuvent utiliser des espaces différents). Pour chaque appel dont
// la clé est littérale (chaîne, gabarit sans substitution, ou ternaire de
// littéraux), on résout comme i18next :
//   - préfixe « ns: » si ns est un espace connu, sinon options.ns, sinon les
//     espaces passés à useTranslation (dans l'ordre), sinon defaultNS 'common' ;
//   - avec { count } : la clé ou ses formes plurielles (_one, _other…) ;
//   - avec { context } : la clé ou une variante key_<contexte> ;
//   - une clé qui désigne un objet n'est acceptée qu'avec { returnObjects: true }.
// Les clés dynamiques (gabarit avec ${…}, concaténation, variable) sont ignorées
// et comptées. Une defaultValue ne dispense pas la clé d'exister : en en/ar,
// l'écran afficherait le texte par défaut, en français.
//
// Limite connue : une fonction t reçue en paramètre ou en prop n'est pas suivie.
//
// Usage : node scripts/check-i18n-usage.mjs [--json]

import { readdirSync, readFileSync, statSync } from 'fs'
import { join, relative } from 'path'
import ts from 'typescript'

const ROOT = process.cwd()
const SRC_DIR = join(ROOT, 'src')
const LOCALES_DIR = join(SRC_DIR, 'i18n/locales/fr')
const DEFAULT_NS = 'common'
const PLURAL_SUFFIXES = ['_zero', '_one', '_two', '_few', '_many', '_other']

// ── Ressources fr ────────────────────────────────────────────────────────────
const resources = {}
for (const f of readdirSync(LOCALES_DIR)) {
  if (!f.endsWith('.json')) continue
  resources[f.slice(0, -5)] = JSON.parse(readFileSync(join(LOCALES_DIR, f), 'utf-8'))
}
const knownNamespaces = new Set(Object.keys(resources))

function getPath(obj, key) {
  let cur = obj
  for (const part of key.split('.')) {
    if (cur === null || typeof cur !== 'object' || !(part in cur)) return undefined
    cur = cur[part]
  }
  return cur
}

// ── Fichiers source ──────────────────────────────────────────────────────────
function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name)
    if (statSync(p).isDirectory()) {
      if (name === '__tests__' || name === 'node_modules') continue
      walk(p, out)
    } else if (/\.(tsx?|jsx?)$/.test(name) && !/\.(test|spec)\.[jt]sx?$/.test(name) && !name.endsWith('.d.ts')) {
      out.push(p)
    }
  }
  return out
}
const files = walk(SRC_DIR)

const program = ts.createProgram({
  rootNames: files,
  options: { noResolve: true, noLib: true, types: [], allowJs: true, jsx: ts.JsxEmit.Preserve, noEmit: true },
})
const checker = program.getTypeChecker()

// ── Helpers AST ──────────────────────────────────────────────────────────────
function literalText(node) {
  if (!node) return undefined
  if (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node)) return node.text
  return undefined
}

/** Clés littérales d'une expression ; null si dynamique. */
function literalKeys(node) {
  if (!node) return null
  while (ts.isParenthesizedExpression(node) || ts.isAsExpression(node) || ts.isSatisfiesExpression?.(node)) node = node.expression
  const s = literalText(node)
  if (s !== undefined) return [s]
  if (ts.isConditionalExpression(node)) {
    const a = literalKeys(node.whenTrue)
    const b = literalKeys(node.whenFalse)
    return a && b ? [...a, ...b] : null
  }
  return null
}

function objectProps(node) {
  const props = {}
  if (!node || !ts.isObjectLiteralExpression(node)) return props
  for (const p of node.properties) {
    if (ts.isShorthandPropertyAssignment(p)) props[p.name.text] = p.name
    else if (ts.isPropertyAssignment(p) && (ts.isIdentifier(p.name) || ts.isStringLiteral(p.name))) props[p.name.text] = p.initializer
  }
  return props
}

/** Espaces de noms d'un appel useTranslation(...) ; null si non littéral. */
function namespacesOf(arg) {
  if (!arg) return [DEFAULT_NS]
  const s = literalText(arg)
  if (s !== undefined) return [s]
  if (ts.isArrayLiteralExpression(arg)) {
    const list = arg.elements.map(literalText)
    return list.every(x => x !== undefined) ? list : null
  }
  return null
}

function symbolOf(node) {
  const sym = checker.getSymbolAtLocation(node)
  return sym && sym.flags & ts.SymbolFlags.Alias ? sym : sym
}

// ── Collecte ─────────────────────────────────────────────────────────────────
const errors = [] // { file, line, key, ns, reason }
let checkedCalls = 0
let dynamicCalls = 0

for (const sf of program.getSourceFiles()) {
  if (!sf.fileName.startsWith(SRC_DIR)) continue
  const rel = relative(ROOT, sf.fileName)
  /** symbole → { kind: 't' | 'i18n' | 'hook', ns: string[], keyPrefix?: string } */
  const bindings = new Map()

  const report = (node, key, ns, reason) => {
    const { line } = sf.getLineAndCharacterOfPosition(node.getStart(sf))
    errors.push({ file: rel, line: line + 1, key, ns, reason })
  }

  // 1er passage : liaisons useTranslation et import i18n
  function collect(node) {
    if (ts.isVariableDeclaration(node) && node.initializer) {
      let init = node.initializer
      if (ts.isCallExpression(init) && ts.isIdentifier(init.expression) && init.expression.text === 'useTranslation') {
        const ns = namespacesOf(init.arguments[0])
        const keyPrefix = literalText(objectProps(init.arguments[1]).keyPrefix)
        if (ns) {
          for (const n of ns) {
            if (!knownNamespaces.has(n)) report(init, '*', n, `espace de noms « ${n} » inexistant`)
          }
          const info = { ns, keyPrefix }
          if (ts.isObjectBindingPattern(node.name)) {
            for (const el of node.name.elements) {
              const prop = (el.propertyName ?? el.name).getText(sf)
              if (!ts.isIdentifier(el.name)) continue
              const sym = symbolOf(el.name)
              if (!sym) continue
              if (prop === 't') bindings.set(sym, { kind: 't', ...info })
              if (prop === 'i18n') bindings.set(sym, { kind: 'i18n', ns: [DEFAULT_NS] })
            }
          } else if (ts.isIdentifier(node.name)) {
            const sym = symbolOf(node.name)
            if (sym) bindings.set(sym, { kind: 'hook', ...info })
          }
        }
      }
    }
    // import i18n from '@/i18n' / 'i18next'
    if (ts.isImportDeclaration(node) && node.importClause?.name) {
      const from = literalText(node.moduleSpecifier) ?? ''
      if (/(^i18next$|\/i18n(\/index)?$|^@\/i18n$)/.test(from)) {
        const sym = symbolOf(node.importClause.name)
        if (sym) bindings.set(sym, { kind: 'i18n', ns: [DEFAULT_NS] })
      }
    }
    ts.forEachChild(node, collect)
  }
  collect(sf)
  if (bindings.size === 0) continue

  function tBindingOfCallee(callee) {
    if (ts.isIdentifier(callee)) {
      const b = bindings.get(symbolOf(callee))
      return b?.kind === 't' ? b : undefined
    }
    if (ts.isPropertyAccessExpression(callee) && callee.name.text === 't') {
      let target = callee.expression
      // t.i18n.t / translation.i18n.t
      const b = ts.isIdentifier(target) ? bindings.get(symbolOf(target)) : undefined
      if (b?.kind === 'i18n') return { ns: [DEFAULT_NS] }
      if (b?.kind === 'hook') return b
    }
    return undefined
  }

  function checkKey(node, rawKey, binding, opts) {
    let key = rawKey
    let nsList = binding.ns
    const optNs = literalText(opts.ns)
    if (optNs) nsList = [optNs]
    const colon = key.indexOf(':')
    let explicitNs = false
    if (colon > 0 && knownNamespaces.has(key.slice(0, colon))) {
      nsList = [key.slice(0, colon)]
      key = key.slice(colon + 1)
      explicitNs = true
    }
    if (binding.keyPrefix && !explicitNs) key = `${binding.keyPrefix}.${key}`

    for (const ns of nsList) {
      const res = resources[ns]
      if (!res) continue
      const v = getPath(res, key)
      if (typeof v === 'string') return
      if (v !== undefined && typeof v === 'object') {
        if (opts.returnObjects) return
        report(node, rawKey, nsList.join('|'), 'la clé désigne un objet (returnObjects absent)')
        return
      }
      if (opts.count && PLURAL_SUFFIXES.some(s => typeof getPath(res, key + s) === 'string')) return
      if (opts.context) {
        const lastDot = key.lastIndexOf('.')
        const parent = lastDot >= 0 ? getPath(res, key.slice(0, lastDot)) : res
        const leaf = key.slice(lastDot + 1)
        if (parent && typeof parent === 'object' && Object.keys(parent).some(k => k.startsWith(leaf + '_'))) return
      }
    }
    const unknown = nsList.filter(n => !knownNamespaces.has(n))
    report(node, rawKey, nsList.join('|'), unknown.length ? `espace de noms « ${unknown.join(', ')} » inexistant` : 'clé absente en fr')
  }

  function visit(node) {
    if (ts.isCallExpression(node)) {
      const binding = tBindingOfCallee(node.expression)
      if (binding) {
        const keys = literalKeys(node.arguments[0])
        if (!keys) {
          dynamicCalls++
        } else {
          checkedCalls++
          const p = objectProps(node.arguments[1])
          const opts = {
            ns: p.ns,
            count: 'count' in p,
            context: 'context' in p,
            returnObjects: p.returnObjects?.kind === ts.SyntaxKind.TrueKeyword,
          }
          for (const k of keys) checkKey(node, k, binding, opts)
        }
      }
    }
    ts.forEachChild(node, visit)
  }
  visit(sf)
}

// ── Rapport ──────────────────────────────────────────────────────────────────
if (process.argv.includes('--json')) {
  console.log(JSON.stringify(errors, null, 2))
  process.exit(errors.length ? 1 : 0)
}

console.log(`\nClés i18n utilisées dans le code (${files.length} fichiers, ${checkedCalls} appels littéraux vérifiés, ${dynamicCalls} dynamiques ignorés)\n`)
if (errors.length) {
  const byFile = new Map()
  for (const e of errors) {
    if (!byFile.has(e.file)) byFile.set(e.file, [])
    byFile.get(e.file).push(e)
  }
  for (const [file, list] of byFile) {
    console.error(`  ✗ ${file}`)
    for (const e of list) console.error(`      ${e.line}: ${e.ns}:${e.key} — ${e.reason}`)
  }
  const distinct = new Set(errors.map(e => `${e.ns}:${e.key}`)).size
  console.error(`\n❌ ${errors.length} appels en défaut (${distinct} clés distinctes, ${byFile.size} fichiers)`)
  process.exit(1)
}
console.log('✅ Toutes les clés littérales existent en fr')
