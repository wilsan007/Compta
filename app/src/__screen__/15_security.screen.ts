// X1-urgent et X1 (270, 271) prouvés PAR L'API, comme l'audit du 28/09/2026 les
// avait mesurés : requêtes PostgREST d'un visiteur non connecté (clé anon seule)
// et d'un lecteur (JWT réel), puis balayage de toutes les tables de la société A
// (issu de doc/audit/harnais-audit-2026-09-28/viewer-sweep.cjs). Joué en DERNIER :
// il a besoin des lignes que les autres scénarios ont créées.
import { it } from 'vitest'
import fs from 'fs'
import path from 'path'
import { login, A, sql, check, save, findings, OUT } from './rig'

const GW = process.env.SCREEN_GATEWAY_URL || 'http://localhost:54399'
const RIG = JSON.parse(fs.readFileSync(process.env.SCREEN_RIG_FILE || path.resolve(__dirname, '../../.screen-rig/rig.json'), 'utf8'))

// Tables qu'un lecteur PEUT légitimement modifier (décision D-6) : ses propres
// préférences et notifications. Liste publiée ; elle ne peut que se discuter, pas grossir en silence.
const LECTEUR_AUTORISE = new Set<string>(['notifications', 'user_preferences', 'user_dashboard_layouts'])

async function patch(table: string, filter: string, body: object, token?: string) {
  const headers: Record<string, string> = { apikey: RIG.anonKey, 'content-type': 'application/json', Prefer: 'return=representation', 'x-tenant-id': A }
  if (token) headers.authorization = 'Bearer ' + token
  const r = await fetch(`${GW}/rest/v1/${table}?${filter}`, { method: 'PATCH', headers, body: JSON.stringify(body) })
  const txt = await r.text()
  return { status: r.status, wrote: r.status < 300 && txt.startsWith('[{'), txt: txt.slice(0, 120) }
}

it('Sécurité par l\'API : anonyme, lecteur', async () => {
  // C1 — catalogue des événements, par un anonyme
  const c1 = await patch('webhook_event_catalog', 'limit=1', { is_active: true })
  check('X1U-C1', 'un visiteur non connecté ne modifie pas webhook_event_catalog (PATCH anonyme)', !c1.wrote, c1)

  // C2 — SMIC global, par un anonyme puis par un lecteur
  const smic0 = (await sql(`select value::text v from payroll_legal_parameters where tenant_id is null and code='SMIC_H' limit 1`))[0]?.v
  const c2a = await patch('payroll_legal_parameters', 'code=eq.SMIC_H&tenant_id=is.null', { value: 1 })
  const supa = await login(2, A)
  const tokViewer = (await supa.auth.getSession()).data.session?.access_token
  const c2b = await patch('payroll_legal_parameters', 'code=eq.SMIC_H&tenant_id=is.null', { value: 1 }, tokViewer)
  const smic1 = (await sql(`select value::text v from payroll_legal_parameters where tenant_id is null and code='SMIC_H' limit 1`))[0]?.v
  check('X1U-C2', 'ni un anonyme ni un lecteur ne réécrivent le SMIC global', !c2a.wrote && !c2b.wrote && smic0 === smic1,
    { anonyme: c2a, lecteur: c2b, smic_avant: smic0, smic_apres: smic1 })

  // C3 — numérotation des pièces, par un lecteur
  const seq = (await sql(`select id, next_number from document_number_sequences where tenant_id=$1 order by next_number desc limit 1`, [A]))[0]
  const c3 = seq ? await patch('document_number_sequences', `id=eq.${seq.id}`, { next_number: 2 }, tokViewer) : { status: 0, wrote: false, txt: 'aucune séquence' }
  const seqApres = seq ? (await sql(`select next_number from document_number_sequences where id=$1`, [seq.id]))[0].next_number : null
  check('X1-C3', 'un lecteur ne remet pas la numérotation des pièces à 2', !!seq && !c3.wrote && seqApres === seq.next_number, { avant: seq?.next_number, apres: seqApres, reponse: c3 })

  // M8 — balayage : chaque table de la société A qui a une ligne, PATCH d'une colonne à sa propre valeur
  const tables = (await sql(`select c.relname t from pg_class c join pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public' and c.relkind in ('r','p') and not c.relispartition
       and exists(select 1 from pg_attribute a where a.attrelid=c.oid and a.attname='tenant_id')
       and exists(select 1 from pg_attribute a where a.attrelid=c.oid and a.attname='id') order by 1`)).map((r: any) => r.t)
  const ecrites: string[] = []
  let testees = 0
  for (const tb of tables) {
    // tri total (balayage reproductible) ; sur tenant_users, la ligne d'un AUTRE membre :
    // modifier sa propre fiche (nom, préférences) est permis, son rôle est gardé (X1-ROLE).
    const autre = tb === 'tenant_users' ? ` and auth_id <> '${RIG.users[2].id}'` : ''
    const row = (await sql(`select * from ${tb} where tenant_id=$1${autre} order by id limit 1`, [A]))[0]
    if (!row) continue
    const col = Object.keys(row).find((k) => !['id', 'tenant_id', 'created_at', 'updated_at', 'number', 'status', 'posting_number', 'hash', 'previous_hash'].includes(k) && typeof row[k] === 'string' && row[k].length < 200)
      || Object.keys(row).find((k) => !['id', 'tenant_id'].includes(k) && (typeof row[k] === 'boolean' || typeof row[k] === 'number'))
    if (!col) continue
    testees++
    const r = await patch(tb, `id=eq.${row.id}`, { [col]: row[col] }, tokViewer)
    if (r.wrote && !LECTEUR_AUTORISE.has(tb)) ecrites.push(tb)
  }
  // Le lecteur et sa propre fiche : il ne se promeut pas administrateur
  const moi = (await sql(`select id, role from tenant_users where tenant_id=$1 and auth_id=$2`, [A, RIG.users[2].id]))[0]
  const esc = await patch('tenant_users', `id=eq.${moi.id}`, { role: 'admin' }, tokViewer)
  const roleApres = (await sql(`select role from tenant_users where id=$1`, [moi.id]))[0].role
  check('X1-ROLE', 'un lecteur ne se promeut pas administrateur par sa propre fiche', !esc.wrote && roleApres === 'viewer', { reponse: esc, role: roleApres })

  fs.writeFileSync(path.join(OUT, 'viewer-writes.json'), JSON.stringify({ testees, ecrites }, null, 2))
  check('X1-M8', `un lecteur ne modifie aucune table de société hors la liste D-6 (${testees} tables testées)`, testees > 20 && ecrites.length === 0, { testees, ecrites })
  save('s15.json', findings)
})
