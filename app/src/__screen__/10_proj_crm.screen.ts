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
  // --- 2.14 (G3, pil-006) : la tâche parente et l'avancement, par la charge utile de
  // TaskCreationDialog. 10 h à 100 % + 90 h à 0 % → le parent ET le projet sont à 10 %
  // (303 : une règle de pondération, deux niveaux), pas à 50 %.
  const dlg = (o: Record<string, unknown>) => ({ description: null, status: 'todo', priority: 'medium', assignee: null, assignee_id: null,
    start_date: null, due_date: null, effort_spent_h: 0, display_order: new Date().toISOString(), budget: 0, color: 0,
    acceptance_criteria: null, recurring_task: false, recurring_interval: 0, recurring_rule_type: 'daily', linked_action_id: null, ...o })
  const p2 = await attempt(() => acc.createProject({ name: 'Projet Avancement', description: '', customer_id: cust.id, status: 'active', budget: 0, actual_cost: 0, start_date: '2026-09-01', end_date: null } as any))
  const pid = (p2.val as any)?.id
  const par = await attempt(() => pm.createTask(dlg({ project_id: pid, title: 'Lot', parent_id: null, effort_estimate_h: 0, progress: 0, task_level: 0 }) as any))
  const parId = (par.val as any)?.id
  const c1 = await attempt(() => pm.createTask(dlg({ project_id: pid, title: 'Petite', parent_id: parId, effort_estimate_h: 10, progress: 100, task_level: 1 }) as any))
  const c2 = await attempt(() => pm.createTask(dlg({ project_id: pid, title: 'Grosse', parent_id: parId, effort_estimate_h: 90, progress: 0, task_level: 1 }) as any))
  check('J06', 'créer une tâche parente et deux sous-tâches avec leur avancement (TaskCreationDialog)', par.ok && c1.ok && c2.ok, par.err ?? c1.err ?? c2.err ?? 'ok')
  const lst = await attempt(() => pm.getTasks(pid))
  const lot = lst.ok ? (lst.val as any[]).find((x) => x.id === parId) : null
  check('J07', 'avancement pondéré du parent : 10 h à 100 % + 90 h à 0 % → 10 % (liste et Gantt lisent project_tasks.progress)', Number(lot?.progress) === 10, lst.err ?? lot?.progress)
  const prj = (await sql(`select progress from projects where id=$1`, [pid]))[0]
  check('J08', 'avancement du projet : la même règle → 10 %', Number(prj?.progress) === 10, prj?.progress)
  const self = await attempt(() => pm.updateTask(parId, { parent_id: parId } as any))
  check('J09', 'une tâche son propre parent : refusée, et le refus dit pourquoi', !self.ok && /propre parent/.test(self.err ?? ''), self.err ?? 'acceptée')
  const cyc = await attempt(() => pm.updateTask(parId, { parent_id: (c1.val as any)?.id } as any))
  check('J10', 'cycle parent → enfant → parent : refusé, et nommé', !cyc.ok && /Cycle de tâches refusé/.test(cyc.err ?? ''), cyc.err ?? 'accepté')

  // --- 2.14 (G5) : un engagement de −50 est refusé par une contrainte NOMMÉE, que
  // lib/errors.ts traduit (test Vitest sql-errors) ; le champ porte min=0.
  const neg = await attempt(() => acc.createBudgetCommitment({ description: 'Engagement négatif', account_code: '606400', fiscal_year_id: null, amount: -50,
    commitment_date: '2026-09-15', source_type: 'manual', source_id: null, status: 'active', supplier_id: null, notes: null } as any))
  check('J11', 'engagement de −50 : refusé par budget_commitments_amount_nonneg', !neg.ok && /budget_commitments_amount_nonneg/.test(neg.err ?? ''), neg.err ?? 'accepté')
  save('s10.json', findings)
})
