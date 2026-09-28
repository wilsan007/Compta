// Contrôle d'audit : colonnes écrites par les ÉCRANS au travers des fonctions de requête.
// écran: createX({ a, b }) -> queries: createX(p) { supabase.from('t').insert(...p) } -> t.a, t.b existent ?
import fs from 'fs'
import path from 'path'
import { createRequire } from 'module'
import pg from 'pg'
const APP = '/Users/awalehosman/Desktop/Projet Saas/compta/app'
const require = createRequire(APP + '/package.json')
const ts = require('typescript')

const client = new pg.Client({ connectionString: 'postgresql://postgres:postgres@localhost:5499/test_compta' })
await client.connect()
const cols = new Map()
for (const r of (await client.query(`select table_name, column_name from information_schema.columns where table_schema='public'`)).rows) {
  if (!cols.has(r.table_name)) cols.set(r.table_name, new Set())
  cols.get(r.table_name).add(r.column_name)
}
await client.end()

function walk(dir, out = []) {
  for (const f of fs.readdirSync(dir)) {
    const p = path.join(dir, f)
    if (fs.statSync(p).isDirectory()) { if (!/__tests__|test/.test(f)) walk(p, out) } else if (/\.(ts|tsx)$/.test(f) && !/\.test\./.test(f)) out.push(p)
  }
  return out
}
const parse = (p) => ts.createSourceFile(p, fs.readFileSync(p, 'utf8'), ts.ScriptTarget.Latest, true, p.endsWith('x') ? ts.ScriptKind.TSX : ts.ScriptKind.TS)

// 1. fonctions de requête -> table + mode + clés retirées
const fnTable = new Map()
for (const file of walk(path.join(APP, 'src/lib'))) {
  const sf = parse(file)
  sf.forEachChild(function visit(node) {
    if (ts.isFunctionDeclaration(node) && node.name && node.body && node.modifiers?.some((m) => m.kind === ts.SyntaxKind.ExportKeyword)) {
      const name = node.name.text
      const body = node.body.getText(sf)
      const froms = [...body.matchAll(/\.from\(\s*'([a-z_0-9]+)'\s*\)\s*\.(insert|update|upsert)\(/g)]
      const fromsAny = [...body.matchAll(/\.from\(\s*'([a-z_0-9]+)'\s*\)/g)]
      if (!froms.length && !/\bti\(|\btud\(/.test(body)) return
      if (/\.rpc\(/.test(body) && !froms.length) return
      const table = froms[0]?.[1] ?? fromsAny[0]?.[1]
      if (!table) return
      const removed = new Set()
      for (const m of body.matchAll(/const\s*\{([^}]*)\}\s*=\s*[a-zA-Z_]+/g)) for (const k of m[1].split(',')) { const n = k.trim().replace(/^\.\.\..*/, '').split(':')[0].trim(); if (n) removed.add(n) }
      const params = node.parameters.map((p) => p.name.getText(sf))
      fnTable.set(name, { table, removed, params, file: path.relative(APP, file) })
    }
  })
}

// 2. appels depuis les écrans
const hits = []
let calls = 0
for (const file of walk(path.join(APP, 'src')).filter((f) => !f.includes('/lib/queries/'))) {
  const sf = parse(file)
  const visit = (node) => {
    if (ts.isCallExpression(node)) {
      const callee = node.expression
      const name = ts.isIdentifier(callee) ? callee.text : ts.isPropertyAccessExpression(callee) ? callee.name.text : null
      const info = name && fnTable.get(name)
      if (info && /^(create|update|upsert|save|add|insert)/i.test(name)) {
        const argIdx = /^update/i.test(name) && info.params.length >= 2 ? 1 : 0
        let arg = node.arguments[argIdx]
        while (arg && (ts.isAsExpression(arg) || ts.isParenthesizedExpression(arg))) arg = arg.expression
        if (arg && ts.isIdentifier(arg)) {
          // suivre la variable jusqu'à sa déclaration (même fichier, la plus proche au-dessus)
          let best = null
          const target = arg.text, pos = arg.getStart()
          const find = (n) => { if (ts.isVariableDeclaration(n) && n.name.getText(sf) === target && n.initializer && n.getStart() < pos) { let init = n.initializer; while (ts.isAsExpression(init) || ts.isParenthesizedExpression(init)) init = init.expression; if (ts.isObjectLiteralExpression(init)) best = init } ts.forEachChild(n, find) }
          find(sf)
          if (best) arg = best
        }
        if (arg && ts.isObjectLiteralExpression(arg)) {
          calls++
          const table = info.table
          const known = cols.get(table)
          for (const p of arg.properties) {
            if (!(ts.isPropertyAssignment(p) || ts.isShorthandPropertyAssignment(p)) || !p.name) continue
            const key = p.name.getText(sf).replace(/['"]/g, '')
            if (info.removed.has(key) || key === 'lines') continue
            if (!known) { hits.push({ table, key, fn: name, at: `${path.relative(APP, file)}:${sf.getLineAndCharacterOfPosition(node.getStart()).line + 1}`, why: 'table absente' }); break }
            if (!known.has(key)) hits.push({ table, key, fn: name, at: `${path.relative(APP, file)}:${sf.getLineAndCharacterOfPosition(p.getStart()).line + 1}` })
          }
        }
      }
    }
    ts.forEachChild(node, visit)
  }
  visit(sf)
}
fs.writeFileSync(new URL('./out/screen-writes.json', import.meta.url), JSON.stringify(hits, null, 2))
console.log(`fonctions de requête écrivantes: ${fnTable.size} ; appels d'écran avec objet littéral: ${calls} ; colonnes inexistantes: ${hits.length}`)
const byFn = {}
for (const h of hits) (byFn[`${h.fn} -> ${h.table}`] ??= []).push(`${h.key} @${h.at}`)
for (const [k, v] of Object.entries(byFn)) console.log(`- ${k}: ${v.join(' ; ')}`)
