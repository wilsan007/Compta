import fs from 'fs'
import path from 'path'
export const A = '07c5c2cf-bed2-4ad6-98de-00a28f00b552'
export const B = '11addd29-6fd8-4bb4-b878-bd67be66d1d5'
const users = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../rig_users.json'), 'utf8'))
export async function login(i: number, tenant: string) {
  const { supabase, setTenantId } = await import('@/lib/supabase')
  await supabase.auth.signOut().catch(() => {})
  const { error } = await supabase.auth.signInWithPassword({ email: users[i].email, password: users[i].password })
  if (error) throw error
  await setTenantId(tenant)
  return supabase
}
export const OUT = path.resolve(__dirname, '../out')
fs.mkdirSync(OUT, { recursive: true })
export function save(name: string, data: unknown) { fs.writeFileSync(path.join(OUT, name), JSON.stringify(data, null, 2)) }
import pg from 'pg'
let _pg: pg.Client | null = null
export async function sql<T = any>(q: string, params: unknown[] = []): Promise<T[]> {
  if (!_pg) { _pg = new pg.Client({ connectionString: 'postgresql://postgres:postgres@localhost:5499/test_compta' }); await _pg.connect() }
  return (await _pg.query(q, params)).rows as T[]
}
export const findings: any[] = []
export function check(id: string, label: string, ok: boolean, detail: unknown) {
  findings.push({ id, label, ok, detail })
  console.log(`${ok ? 'OK ' : 'KO '} ${id} — ${label} :: ${typeof detail === 'string' ? detail : JSON.stringify(detail)}`)
}
export async function attempt<T>(fn: () => Promise<T>): Promise<{ ok: boolean; val?: T; err?: string }> {
  try { return { ok: true, val: await fn() } } catch (e: any) { return { ok: false, err: `${e?.code ?? ''} ${e?.message ?? e}`.trim() } }
}
export async function ledger(tid: string, sourceFilter = '') {
  return sql(`select l.account_code code, round(sum(l.debit),2)::float d, round(sum(l.credit),2)::float c from journal_lines l join journal_entries e on e.id=l.journal_id
   where e.tenant_id=$1 and e.status='posted' ${sourceFilter} group by l.account_code order by l.account_code`, [tid])
}
