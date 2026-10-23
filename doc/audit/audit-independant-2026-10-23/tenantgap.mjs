import fs from 'node:fs'; import path from 'node:path'; import pg from 'pg'
const src=fs.readFileSync('src/lib/supabase.ts','utf8')
const setM=src.match(/const TENANT_TABLES = new Set\(\[([\s\S]*?)\]\)/)[1]
const T=new Set([...setM.matchAll(/'([a-z_0-9]+)'/g)].map(m=>m[1]))
const exM=src.match(/const EXEMPT_TABLES = new Set\(\[([\s\S]*?)\]\)/)
const EX=new Set(exM?[...exM[1].matchAll(/'([a-z_0-9]+)'/g)].map(m=>m[1]):[])
const files=[];(function w(d){for(const f of fs.readdirSync(d,{withFileTypes:true})){const p=path.join(d,f.name);if(f.isDirectory()){if(f.name!=='__tests__'&&f.name!=='__screen__'&&f.name!=='node_modules')w(p)}else if(/\.(ts|tsx)$/.test(f.name)&&!/\.test\./.test(f.name))files.push(p)}})('src')
const ins=new Map()
for(const f of files){const s=fs.readFileSync(f,'utf8');for(const m of s.matchAll(/from\(\s*'([a-z_0-9]+)'\s*\)\s*\.(insert|upsert)\(([^)]{0,80})/g)){const k=m[1];const raw=!/ti\(/.test(m[3]);if(!ins.has(k))ins.set(k,{files:new Set(),raw:false});ins.get(k).files.add(path.basename(f));if(raw)ins.get(k).raw=true}}
const c=new pg.Client({connectionString:'postgresql://postgres:postgres@localhost:55432/ui_fresh'});await c.connect()
const tt=(await c.query(`select c.table_name, c.column_default, c.is_nullable from information_schema.columns c join information_schema.tables t on t.table_name=c.table_name and t.table_schema='public' and t.table_type='BASE TABLE' where c.table_schema='public' and c.column_name='tenant_id'`)).rows
const trg=new Set((await c.query(`select distinct c.relname from pg_trigger g join pg_class c on c.oid=g.tgrelid join pg_proc p on p.oid=g.tgfoid where not g.tgisinternal and (g.tgtype & 2)=2 and (p.prosrc ilike '%tenant_id%' )`)).rows.map(r=>r.relname))
const res=[]
for(const [t,v] of ins){const row=tt.find(x=>x.table_name===t);if(!row)continue;const inList=T.has(t)&&!EX.has(t);const hasDef=!!row.column_default;if(!inList&&!trg.has(t)&&!hasDef)res.push({t,files:[...v.files].join(','),nullable:row.is_nullable})}
console.log('tables insérées par le front:',ins.size,'| avec tenant_id:',[...ins.keys()].filter(k=>tt.find(x=>x.table_name===k)).length)
console.log('SANS injection de tenant_id (ni liste, ni défaut, ni déclencheur):');console.table(res)
await c.end()
