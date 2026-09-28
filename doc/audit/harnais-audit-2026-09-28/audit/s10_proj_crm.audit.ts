import { it } from 'vitest'
import { login, A, sql, check, attempt, save, findings } from './rig'
it('Projets et CRM', async () => {
  await login(0, A)
  const acc = await import('@/lib/queries/accounting')
  const pm = await import('@/lib/queries/projectManagement')
  const crm = await import('@/lib/queries/crmAdvanced')
  const core = await import('@/lib/queries/core')
  const cust = (await sql(`select id from customers where tenant_id=$1 limit 1`, [A]))[0]
  const p = await attempt(() => acc.createProject({ name: 'Projet Audit', description: '', customer_id: cust.id, status: 'active', budget: 10000, actual_cost: 0, start_date: '2026-09-01', end_date: null } as any))
  check('J01', 'créer un projet (ProjectsPage)', p.ok, p.err ?? (p.val as any).id)
  const t = p.ok ? await attempt(() => pm.createTask({ project_id: (p.val as any).id, title: 'Analyse', status: 'todo', priority: 'medium', effort_estimate_h: 8 } as any)) : p
  check('J02', 'créer une tâche', t.ok, t.err ?? (t.val as any).id)
  const tasks = p.ok ? await attempt(() => pm.getTasks((p.val as any).id)) : p
  check('J03', 'la tâche apparaît dans la liste du projet', tasks.ok && (tasks.val as any[]).length === 1, tasks.err ?? (tasks.val as any[]).length)
  const o = await attempt(async () => crm.createOpportunity({ tenant_id: null, number: await core.nextDocumentNumber('OPP'), customer_id: cust.id, prospect_id: null, title: 'Opp Audit', description: null, stage: 'qualification', probability: 20, expected_amount: 5000, expected_close_date: null, actual_amount: null, actual_close_date: null, sales_rep_id: null, source: null, lost_reason: null, tags: null } as any))
  const orow = o.ok ? (await sql(`select tenant_id from crm_opportunities where id=$1`, [(o.val as any).id]))[0] : null
  check('J04', 'créer une opportunité (OpportunitiesPage) rattachée à la société', o.ok && orow?.tenant_id === A, o.err ?? orow)
  const ol = await attempt(() => (crm as any).getOpportunities())
  check('J05', 'l\'opportunité apparaît dans le pipeline', ol.ok && (ol.val as any[]).some((x: any) => x.title === 'Opp Audit'), ol.err ?? (ol.val as any[]).length)
  save('s10.json', findings)
})
