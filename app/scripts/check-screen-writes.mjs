#!/usr/bin/env node
/**
 * check-screen-writes.mjs — X0 (audit fonctionnel exécuté du 28/09/2026)
 *
 * L'ANGLE MORT. `check-written-columns` confronte au schéma l'objet écrit DANS la
 * requête (`.from('t').insert({ … })`). Or le chemin normal d'un écran est
 * « écran → fonction de requête → `.insert(param)` » : l'objet est construit dans
 * la PAGE, passé à `createX(obj)`, et la fonction l'écrit tel quel. Aucun contrôle
 * ne suivait l'objet de l'écran jusqu'à la table. Mesure d'entrée (28/09/2026,
 * 238 migrations) : 62 colonnes inexistantes dans 6 fonctions — comptes de tiers
 * 46, journaux 8, immobilisations 3, compte à la volée 2, sections analytiques 2,
 * lot de paie 1 — dont chacune fait ÉCHOUER la création à l'écran (PGRST204),
 * confirmé en exécution par src/__screen__/06_screenwrites.screen.ts.
 *
 * CE QUE FAIT LE CONTRÔLE.
 *   1. repère les fonctions exportées de `src/lib/**` qui écrivent une table
 *      (`.from('t').insert|update|upsert(`, ou via `ti(` / `tud(`), et les clés
 *      qu'elles retirent par déstructuration (`const { lines, ...rest } = p`) ;
 *   2. dans tous les autres fichiers de `src/`, suit chaque appel
 *      `create*|update*|upsert*|save*|add*|insert*(…)` d'une de ces fonctions
 *      jusqu'à l'OBJET LITTÉRAL passé — directement, ou par une variable du même
 *      fichier déclarée plus haut ;
 *   3. confronte chaque clé aux colonnes réelles (information_schema).
 * Les clés calculées (`[field]`) et `lines` (écrites dans une table fille) sont
 * écartées.
 *
 * LA BASELINE EST GELÉE à la mesure d'entrée ; elle ne peut que baisser.
 * `--update-baseline` ne sait que retirer. L'objectif (X8) est ZÉRO.
 *
 * Usage :
 *   DATABASE_URL=... node scripts/check-screen-writes.mjs
 *   DATABASE_URL=... node scripts/check-screen-writes.mjs --update-baseline
 * Code 1 si une colonne inexistante nouvelle apparaît, ou si une entrée de la
 * baseline n'est plus reproduite. Code 2 si le schéma ou la baseline manquent.
 * Issu de doc/audit/harnais-audit-2026-09-28/screen-writes.mjs.
 */
import fs from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'
import ts from 'typescript'
import pg from 'pg'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const ROOT = path.resolve(__dirname, '..')
const SRC = path.join(ROOT, 'src')
const BASELINE = path.join(__dirname, 'verify-rules', 'screen-writes.baseline.json')
const UPDATE = process.argv.includes('--update-baseline')

if (!process.env.DATABASE_URL && !process.env.PGHOST) {
  console.error('❌ DATABASE_URL (ou PGHOST/…) est requis : le contrôle lit le schéma réel.')
  process.exit(2)
}
const client = new pg.Client(process.env.DATABASE_URL ? { connectionString: process.env.DATABASE_URL } : {})
await client.connect()
const cols = new Map()
for (const r of (await client.query(`select table_name, column_name from information_schema.columns where table_schema='public'`)).rows) {
  if (!cols.has(r.table_name)) cols.set(r.table_name, new Set())
  cols.get(r.table_name).add(r.column_name)
}
await client.end()
if (cols.size < 100) { console.error(`❌ Schéma incomplet (${cols.size} tables) : migrations non appliquées ?`); process.exit(2) }

function walk(dir, out = []) {
  for (const f of fs.readdirSync(dir)) {
    const p = path.join(dir, f)
    if (fs.statSync(p).isDirectory()) { if (!/^(__tests__|__screen__|test)$/.test(f)) walk(p, out) }
    else if (/\.(ts|tsx)$/.test(f) && !/\.(test|spec)\./.test(f)) out.push(p)
  }
  return out
}
const parse = (p) => ts.createSourceFile(p, fs.readFileSync(p, 'utf8'), ts.ScriptTarget.Latest, true, p.endsWith('x') ? ts.ScriptKind.TSX : ts.ScriptKind.TS)
const rel = (p) => path.relative(ROOT, p)

// 1. fonctions de requête écrivantes → table + clés retirées
const fnTable = new Map()
for (const file of walk(path.join(SRC, 'lib'))) {
  const sf = parse(file)
  sf.forEachChild((node) => {
    if (!(ts.isFunctionDeclaration(node) && node.name && node.body && node.modifiers?.some((m) => m.kind === ts.SyntaxKind.ExportKeyword))) return
    const body = node.body.getText(sf)
    const writes = [...body.matchAll(/\.from\(\s*'([a-z_0-9]+)'\s*\)\s*\.(insert|update|upsert)\(/g)]
    const anyFrom = [...body.matchAll(/\.from\(\s*'([a-z_0-9]+)'\s*\)/g)]
    if (!writes.length && !/\bti\(|\btud\(/.test(body)) return
    if (/\.rpc\(/.test(body) && !writes.length) return
    const table = writes[0]?.[1] ?? anyFrom[0]?.[1]
    if (!table) return
    const removed = new Set()
    for (const m of body.matchAll(/const\s*\{([^}]*)\}\s*=\s*[a-zA-Z_]+/g)) {
      for (const k of m[1].split(',')) { const n = k.trim().replace(/^\.\.\..*/, '').split(':')[0].trim(); if (n) removed.add(n) }
    }
    fnTable.set(node.name.text, { table, removed, arity: node.parameters.length, file: rel(file) })
  })
}

// 2. appels depuis les écrans
const hits = []
let calls = 0
for (const file of walk(SRC).filter((f) => !f.includes(`${path.sep}lib${path.sep}queries${path.sep}`))) {
  const sf = parse(file)
  const visit = (node) => {
    if (ts.isCallExpression(node)) {
      const callee = node.expression
      const name = ts.isIdentifier(callee) ? callee.text : ts.isPropertyAccessExpression(callee) ? callee.name.text : null
      const info = name && fnTable.get(name)
      if (info && /^(create|update|upsert|save|add|insert)/i.test(name)) {
        const argIdx = /^update/i.test(name) && info.arity >= 2 ? 1 : 0
        let arg = node.arguments[argIdx]
        while (arg && (ts.isAsExpression(arg) || ts.isParenthesizedExpression(arg))) arg = arg.expression
        if (arg && ts.isIdentifier(arg)) {
          let best = null
          const target = arg.text, pos = arg.getStart()
          const find = (n) => {
            if (ts.isVariableDeclaration(n) && n.name.getText(sf) === target && n.initializer && n.getStart() < pos) {
              let init = n.initializer
              while (ts.isAsExpression(init) || ts.isParenthesizedExpression(init)) init = init.expression
              if (ts.isObjectLiteralExpression(init)) best = init
            }
            ts.forEachChild(n, find)
          }
          find(sf)
          if (best) arg = best
        }
        if (arg && ts.isObjectLiteralExpression(arg)) {
          calls++
          const known = cols.get(info.table)
          for (const p of arg.properties) {
            if (!(ts.isPropertyAssignment(p) || ts.isShorthandPropertyAssignment(p)) || !p.name) continue
            if (ts.isComputedPropertyName(p.name)) continue
            const key = p.name.getText(sf).replace(/['"]/g, '')
            if (info.removed.has(key) || key === 'lines') continue
            if (!known) { hits.push({ fn: name, table: info.table, key: '(table absente)', file: rel(file), line: sf.getLineAndCharacterOfPosition(node.getStart()).line + 1 }); break }
            if (!known.has(key)) hits.push({ fn: name, table: info.table, key, file: rel(file), line: sf.getLineAndCharacterOfPosition(p.getStart()).line + 1 })
          }
        }
      }
    }
    ts.forEachChild(node, visit)
  }
  visit(sf)
}

// 3. baseline gelée
const keyOf = (h) => `${h.file}|${h.fn}|${h.table}.${h.key}`
const found = new Map(hits.map((h) => [keyOf(h), h]))
if (!fs.existsSync(BASELINE)) { console.error(`❌ Baseline absente : ${rel(BASELINE)}`); process.exit(2) }
const baseline = JSON.parse(fs.readFileSync(BASELINE, 'utf8'))
const frozen = new Set(baseline.findings.map((f) => `${f.file}|${f.fn}|${f.table}.${f.key}`))
const nouveaux = [...found.keys()].filter((k) => !frozen.has(k))
const disparus = [...frozen].filter((k) => !found.has(k))

if (UPDATE) {
  if (nouveaux.length) {
    console.error('❌ --update-baseline refuse d’AJOUTER des colonnes inexistantes :')
    for (const k of nouveaux) console.error(`   ${k}  (ligne ${found.get(k).line})`)
    process.exit(1)
  }
  baseline.findings = baseline.findings.filter((f) => found.has(`${f.file}|${f.fn}|${f.table}.${f.key}`))
  baseline.total = baseline.findings.length
  baseline.frozenAt = new Date().toISOString().slice(0, 10)
  fs.writeFileSync(BASELINE, JSON.stringify(baseline, null, 2) + '\n')
  console.log(`✅ Baseline mise à jour : ${baseline.total} colonne(s) inexistante(s) gelée(s).`)
  process.exit(0)
}

const parFn = {}
for (const h of hits) {
  const k = `${h.fn} → ${h.table}`
  parFn[k] = (parFn[k] ?? 0) + 1
}
console.log(`Écritures des écrans : ${fnTable.size} fonctions de requête écrivantes, ${calls} appel(s) d'écran avec objet suivi, ${hits.length} colonne(s) inexistante(s) (baseline ${frozen.size}).`)
for (const [k, n] of Object.entries(parFn)) console.log(`   ${k} : ${n}`)
let ko = false
if (nouveaux.length) {
  ko = true
  console.error('\n❌ COLONNE(S) INEXISTANTE(S) ÉCRITE(S) PAR UN ÉCRAN — la création échouera (PGRST204) :')
  for (const k of nouveaux) { const h = found.get(k); console.error(`   ${h.file}:${h.line}  ${h.fn}() → ${h.table}.${h.key}`) }
}
if (disparus.length) {
  ko = true
  console.error('\n❌ Baseline périmée — ces entrées ne se reproduisent plus (corrigées ?) :')
  for (const k of disparus) console.error(`   ${k}`)
  console.error('   Retirez-les dans le même commit : node scripts/check-screen-writes.mjs --update-baseline')
}
if (ko) process.exit(1)
console.log('✅ Aucune colonne inexistante hors baseline.')
