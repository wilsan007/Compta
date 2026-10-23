// ============================================================
// check-tenant-injection.mjs — audit indépendant du 23/10/2026
//
// Une table cloisonnée dont `tenant_id` est NOT NULL, sans valeur par défaut ni
// déclencheur BEFORE INSERT qui le pose, exige que le CLIENT l'envoie : la RLS
// refuse sinon l'insertion (403 « You are not allowed to perform this action »).
// `ti()` ne l'ajoute que pour les tables du registre `TENANT_TABLES`
// (src/lib/supabase.ts) : une table oubliée du registre rend sa création
// impossible depuis l'écran — mesuré le 23/10 sur 22 tables (stock, CRM,
// recrutement, champs personnalisés, modèles d'e-mail, …).
//
// Ce contrôle croise, sur une base migrée (DATABASE_URL), les tables que
// l'écran INSÈRE avec ce registre. Il échoue si une table à besoin client
// est écrite sans que `ti()` puisse lui poser son `tenant_id`.
// Usage : DATABASE_URL=postgresql://… node scripts/check-tenant-injection.mjs
// ============================================================
import fs from 'node:fs'
import path from 'node:path'
import pg from 'pg'

const url = process.env.DATABASE_URL
if (!url) { console.error('DATABASE_URL requis (base migrée)'); process.exit(2) }

const src = fs.readFileSync('src/lib/supabase.ts', 'utf8')
const names = (re) => new Set([...(src.match(re)?.[1] ?? '').matchAll(/'([a-z_0-9]+)'/g)].map((m) => m[1]))
const TENANT = names(/const TENANT_TABLES = new Set\(\[([\s\S]*?)\]\)/)
const EXEMPT = names(/const EXEMPT_TABLES = new Set\(\[([\s\S]*?)\]\)/)

const files = []
;(function walk(d) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name)
    if (e.isDirectory()) { if (!/^__|node_modules/.test(e.name)) walk(p) }
    else if (/\.(ts|tsx)$/.test(e.name) && !/\.test\./.test(e.name)) files.push(p)
  }
})('src')

/** table -> { files, viaTi, explicit, bare } */
const writes = new Map()
for (const f of files) {
  const s = fs.readFileSync(f, 'utf8')
  for (const m of s.matchAll(/from\(\s*'([a-z_0-9]+)'\s*\)\s*\.(insert|upsert)\(/g)) {
    const win = s.slice(m.index + m[0].length, m.index + m[0].length + 500)
    const rec = writes.get(m[1]) ?? { files: new Set(), viaTi: false, explicit: false, bare: false }
    rec.files.add(path.basename(f))
    if (/^\s*ti\(/.test(win) || /^\s*\n?\s*ti\(/.test(win)) rec.viaTi = true
    else if (/tenant_id/.test(win.slice(0, 350))) rec.explicit = true
    else rec.bare = true
    writes.set(m[1], rec)
  }
}

const c = new pg.Client({ connectionString: url })
await c.connect()
const need = new Set((await c.query(`
  SELECT c.table_name FROM information_schema.columns c
  JOIN information_schema.tables t ON t.table_schema = c.table_schema AND t.table_name = c.table_name AND t.table_type = 'BASE TABLE'
  WHERE c.table_schema = 'public' AND c.column_name = 'tenant_id' AND c.is_nullable = 'NO' AND c.column_default IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM pg_trigger g JOIN pg_proc p ON p.oid = g.tgfoid
      WHERE g.tgrelid = ('public.' || c.table_name)::regclass AND NOT g.tgisinternal
        AND (g.tgtype & 2) = 2 AND (g.tgtype & 4) = 4 AND p.prosrc ILIKE '%tenant_id%')`)).rows.map((r) => r.table_name))
await c.end()

const bad = []
for (const [t, w] of writes) {
  if (!need.has(t) || EXEMPT.has(t)) continue
  const inRegistry = TENANT.has(t)
  if (w.bare || (w.viaTi && !inRegistry && !w.explicit)) bad.push({ table: t, files: [...w.files].join(', '), cause: w.bare ? 'insert sans tenant_id ni ti()' : 'ti() sans effet : table absente de TENANT_TABLES' })
}
if (bad.length) {
  console.error(`❌ ${bad.length} table(s) écrites par l'écran sans que leur tenant_id soit posé (RLS : 403) :`)
  for (const b of bad) console.error(`   - ${b.table} (${b.files}) — ${b.cause}`)
  process.exit(1)
}
console.log(`✅ Les ${[...writes.keys()].filter((t) => need.has(t)).length} tables à tenant_id client écrites par l'écran sont toutes couvertes.`)
