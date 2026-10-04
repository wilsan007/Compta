// Scanner : colonnes écrites par .insert({...}) / .update({...}) confrontées au schéma réel.
//
// Angle mort comblé : `app/scripts/check-embeds.mjs` ne vérifie que les LECTURES.
// Une colonne inexistante dans un `.insert()` n'est vue ni par tsc, ni par les tests
// (Supabase y est simulé), ni par PostgREST tant que la requête n'est pas jouée.
// Au 23/09/2026 ce contrôle trouve 21 écritures impossibles, toutes dans des
// fonctions Edge, et aucune ne vérifie son erreur.
//
// Usage, depuis `app/` :
//   psql "$DATABASE_URL" -At -F'|' \
//     -c "select table_name||'|'||column_name from information_schema.columns
//         where table_schema='public' order by 1" > /tmp/audit/columns.txt
//   node ../doc/audit/scenarios/scan-colonnes-ecrites.mjs /tmp/audit
//
// Sort 0 si tout va bien ; chaque ligne suspecte est imprimée sur stdout.

import fs from 'node:fs'
import path from 'node:path'

const S = process.argv[2]
if (!S) {
  console.error('Usage : node scan-colonnes-ecrites.mjs <dossier contenant columns.txt>')
  process.exit(2)
}
const cols = new Map()
for (const line of fs.readFileSync(path.join(S,'columns.txt'),'utf8').trim().split('\n')) {
  const [t,c] = line.split('|')
  if (!cols.has(t)) cols.set(t,new Set())
  cols.get(t).add(c)
}

const roots = ['src','supabase/functions']
const files = []
function walk(d){ for (const e of fs.readdirSync(d,{withFileTypes:true})) {
  const p = path.join(d,e.name)
  if (e.isDirectory()) { if (!/node_modules|__tests__|\.test\./.test(p)) walk(p) }
  else if (/\.(ts|tsx)$/.test(p) && !/\.test\.|database-generated/.test(p)) files.push(p)
} }
for (const r of roots) if (fs.existsSync(r)) walk(r)

// Découpe équilibrée d'un objet littéral à partir de la position de son '{'
function readObject(src, start) {
  let depth = 0, i = start, inStr = null, prev = ''
  for (; i < src.length; i++) {
    const ch = src[i]
    if (inStr) { if (ch === inStr && prev !== '\\') inStr = null }
    else if (ch === '"' || ch === "'" || ch === '`') inStr = ch
    else if (ch === '{') depth++
    else if (ch === '}') { depth--; if (depth === 0) return src.slice(start, i+1) }
    prev = ch
  }
  return null
}

// Clés de premier niveau seulement
function topLevelKeys(obj) {
  const body = obj.slice(1,-1)
  const keys = []
  let depth = 0, inStr = null, prev = '', tokenStart = 0
  const parts = []
  for (let i=0;i<body.length;i++){
    const ch = body[i]
    if (inStr) { if (ch===inStr && prev!=='\\') inStr=null }
    else if (ch==='"'||ch==="'"||ch==='`') inStr=ch
    else if ('{[('.includes(ch)) depth++
    else if ('}])'.includes(ch)) depth--
    else if (ch===',' && depth===0) { parts.push(body.slice(tokenStart,i)); tokenStart=i+1 }
    prev=ch
  }
  parts.push(body.slice(tokenStart))
  for (const p of parts) {
    const m = p.match(/^\s*(?:\/\/[^\n]*\n\s*)*['"]?([A-Za-z_][A-Za-z0-9_]*)['"]?\s*:/)
    if (m) keys.push(m[1])
    else {
      const sh = p.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*$/)   // raccourci { foo }
      if (sh) keys.push(sh[1])
    }
  }
  return keys
}

const problems = []
for (const f of files) {
  const src = fs.readFileSync(f,'utf8')
  const re = /\.from\(\s*['"`]([a-z0-9_]+)['"`]\s*\)([\s\S]{0,400}?)\.(insert|update|upsert)\s*\(\s*(\{|\[)/g
  let m
  while ((m = re.exec(src))) {
    const table = m[1], op = m[3], gap = m[2]
    // Écarter les faux positifs : un autre .from(), une parenthèse fermante de trop,
    // ou un point-virgule entre le .from() et le .insert() = ce n'est pas la même requête.
    if (/\.from\(|;/.test(gap)) continue
    if (!cols.has(table)) { problems.push({f,table,op,col:'(table inconnue)',line:src.slice(0,m.index).split('\n').length}); continue }
    // position du '{' de l'objet (ou du premier objet du tableau)
    let braceAt = m.index + m[0].length - 1
    if (m[4] === '[') { braceAt = src.indexOf('{', braceAt); if (braceAt < 0) continue }
    const obj = readObject(src, braceAt)
    if (!obj) continue
    if (obj.length > 6000) continue
    for (const k of topLevelKeys(obj)) {
      if (!cols.get(table).has(k)) {
        problems.push({f,table,op,col:k,line:src.slice(0,m.index).split('\n').length})
      }
    }
  }
}
const seen = new Set()
for (const p of problems) {
  const key = `${p.f}|${p.table}|${p.col}`
  if (seen.has(key)) continue
  seen.add(key)
  console.log(`${p.f}:${p.line}\t${p.table}.${p.col}\t(${p.op})`)
}
console.error(`\n${seen.size} écritures suspectes sur ${files.length} fichiers`)
