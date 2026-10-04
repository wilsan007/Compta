const { Client } = require('pg'); const tok = require('./tok.cjs')
const A = '07c5c2cf-bed2-4ad6-98de-00a28f00b552'
;(async () => {
  const c = new Client({ connectionString: 'postgresql://postgres:postgres@localhost:5499/test_compta' }); await c.connect()
  const tables = (await c.query(`select c.relname t from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p') and not c.relispartition
     and exists(select 1 from pg_attribute a where a.attrelid=c.oid and a.attname='tenant_id') and exists(select 1 from pg_attribute a where a.attrelid=c.oid and a.attname='id')`)).rows.map(r => r.t)
  const t = await tok(2)
  const out = { writable: [], refused: [], skipped: 0 }
  for (const tb of tables) {
    const row = (await c.query(`select * from ${tb} where tenant_id=$1 limit 1`, [A])).rows[0]
    if (!row) { out.skipped++; continue }
    const col = Object.keys(row).find(k => !['id','tenant_id','created_at','updated_at','number','status','posting_number','hash','previous_hash'].includes(k) && typeof row[k] === 'string' && row[k].length < 200)
      || Object.keys(row).find(k => !['id','tenant_id'].includes(k) && (typeof row[k] === 'boolean' || typeof row[k] === 'number'))
    if (!col) { out.skipped++; continue }
    const r = await fetch(`http://localhost:54399/rest/v1/${tb}?id=eq.${row.id}`, { method: 'PATCH', headers: { authorization: 'Bearer ' + t, 'x-tenant-id': A, 'content-type': 'application/json', Prefer: 'return=representation' }, body: JSON.stringify({ [col]: row[col] }) })
    const body = await r.text()
    if (r.status < 300 && body.startsWith('[{')) out.writable.push(tb); else out.refused.push(`${tb} (${r.status} ${body.slice(0, 80)})`)
  }
  console.log(JSON.stringify({ tables: tables.length, ecrivables_par_lecteur: out.writable.length, refusees: out.refused.length, sans_ligne: out.skipped, writable: out.writable }, null, 1))
  await c.end()
})()
