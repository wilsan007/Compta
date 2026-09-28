// ============================================================
// Banc « chemin de l'écran » (X0, audit fonctionnel exécuté du 28/09/2026)
//
// Les scénarios appellent les VRAIES fonctions de requête des écrans
// (`src/lib/queries/*`), avec la charge utile exacte de l'écran, à travers le
// vrai client Supabase → passerelle → PostgREST réel → RLS réelle. Aucun mock.
// Les comptes et les sociétés viennent de `scripts/screen-rig/setup.mjs`
// (`.screen-rig/rig.json`, hors dépôt) ; `sql()` lit la base DIRECTEMENT pour
// constater l'effet, jamais pour préparer l'état qu'un écran devrait produire.
//
// Chaque `check(id, …)` est confronté, en fin de fichier, au registre
// `expected_failures.json` (même contrat que `sql/ci/expected_failures.sql`) :
// un rouge hors registre, ou un vert encore inscrit, fait échouer la CI.
// ============================================================
import fs from 'fs'
import path from 'path'
import pg from 'pg'

const RIG_FILE = process.env.SCREEN_RIG_FILE || path.resolve(__dirname, '../../.screen-rig/rig.json')
const RIG = JSON.parse(fs.readFileSync(RIG_FILE, 'utf8'))
export const A: string = RIG.A
export const B: string = RIG.B
const users: { id: string; email: string; password: string }[] = RIG.users
export const RIG_USERS = users

export async function login(i: number, tenant: string) {
  const { supabase, setTenantId } = await import('@/lib/supabase')
  await supabase.auth.signOut().catch(() => {})
  const { error } = await supabase.auth.signInWithPassword({ email: users[i].email, password: users[i].password })
  if (error) throw error
  await setTenantId(tenant)
  return supabase
}

export const OUT = path.resolve(path.dirname(RIG_FILE), 'out')
fs.mkdirSync(OUT, { recursive: true })
export function save(name: string, data: unknown) { fs.writeFileSync(path.join(OUT, name), JSON.stringify(data, null, 2)) }

let _pg: pg.Client | null = null
export async function sql<T = any>(q: string, params: unknown[] = []): Promise<T[]> {
  if (!_pg) {
    _pg = new pg.Client({ connectionString: process.env.DATABASE_URL || 'postgresql://postgres:postgres@localhost:5432/test_compta' })
    await _pg.connect()
  }
  return (await _pg.query(q, params)).rows as T[]
}
export async function closeSql() { if (_pg) { await _pg.end(); _pg = null } }

export type Finding = { id: string; label: string; ok: boolean; detail: unknown }
export const findings: Finding[] = []
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
