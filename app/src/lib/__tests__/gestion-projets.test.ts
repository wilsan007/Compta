import { describe, it, expect } from 'vitest'
import { orderAsTree, groupByProject, depthMap, NO_PROJECT } from '@/lib/taskTree'
import { addDaysToDay, diffDays, formatDay, parseDay } from '@/lib/dayMath'
import { applyDrag, buildGanttRows, dependencyPath, projectBounds, taskBounds, type Bounds } from '@/lib/ganttModel'
import { fromDbTask, taskStatusFromDb, taskStatusToDb, toDbTaskWrite } from '@/lib/taskStatus'
import type { ProjectTask, ProjectTaskDependency } from '@/types/projectManagement'

function task(id: string, extra: Partial<ProjectTask> = {}): ProjectTask {
  return {
    id, tenant_id: 't', project_id: null, parent_id: null, title: id, description: null,
    status: 'todo', priority: 'medium', assignee: null, assignee_id: null,
    start_date: null, due_date: null, effort_estimate_h: 0, effort_spent_h: 0, progress: 0,
    display_order: '0', task_level: 0, budget: 0, color: 0, acceptance_criteria: null,
    recurring_task: false, recurring_interval: 1, recurring_rule_type: 'weekly', is_closed: false,
    linked_action_id: null, created_at: '', updated_at: '', ...extra,
  } as ProjectTask
}

const NONE: Bounds = { minStart: null, maxEnd: null, minEnd: null, childMinStart: null, childMaxEnd: null }

describe('statuts : la base parle in_progress/cancelled, l’écran doing/canceled', () => {
  it('traduit dans les deux sens, sans toucher aux autres', () => {
    expect(taskStatusFromDb('in_progress')).toBe('doing')
    expect(taskStatusFromDb('cancelled')).toBe('canceled')
    expect(taskStatusFromDb('completed')).toBe('done')
    expect(taskStatusFromDb('blocked')).toBe('blocked')
    expect(taskStatusToDb('doing')).toBe('in_progress')
    expect(taskStatusToDb('canceled')).toBe('cancelled')
    expect(taskStatusToDb('done')).toBe('done')
  })
  it('n’invente pas de statut pour une lecture partielle, et traduit une écriture', () => {
    expect(fromDbTask({ id: 'x' } as { id: string; status?: string })).toEqual({ id: 'x' })
    expect(fromDbTask({ status: 'in_progress' }).status).toBe('doing')
    expect(toDbTaskWrite({ status: 'doing' as const, title: 'a' })).toEqual({ status: 'in_progress', title: 'a' })
    expect(toDbTaskWrite({ title: 'a' } as { title: string; status?: string })).toEqual({ title: 'a' })
  })
})

describe('jours : pas de passage par UTC', () => {
  it('lit et écrit AAAA-MM-JJ en heure locale', () => {
    const d = parseDay('2026-03-29')! // nuit du changement d'heure en Europe
    expect(formatDay(d)).toBe('2026-03-29')
    expect(addDaysToDay('2026-03-28', 2)).toBe('2026-03-30')
    expect(diffDays(parseDay('2026-03-28')!, parseDay('2026-03-30')!)).toBe(2)
    expect(addDaysToDay('2026-02-27', 2)).toBe('2026-03-01')
  })
})

describe('arbre et regroupement par projet', () => {
  it('une mère est suivie de ses sous-tâches, même si display_order vaut « 0 » partout', () => {
    const tasks = [task('B'), task('A1', { parent_id: 'A' }), task('A'), task('A11', { parent_id: 'A1' }), task('A2', { parent_id: 'A' })]
    // racines à rang égal : l'ordre de lecture est gardé (B avant A)
    expect(orderAsTree(tasks).map((t) => t.id)).toEqual(['B', 'A', 'A1', 'A11', 'A2'])
    expect(depthMap(tasks).get('A11')).toBe(2)
  })
  it('groupe dans l’ordre des projets, « sans projet » en dernier, la sous-tâche avec sa racine', () => {
    const tasks = [
      task('x', { project_id: null }),
      task('p2a', { project_id: 'p2' }),
      task('p1a', { project_id: 'p1' }),
      task('p1a-sub', { project_id: null, parent_id: 'p1a' }),
    ]
    const g = groupByProject(tasks, ['p1', 'p2'])
    expect(g.map((x) => x.projectId)).toEqual(['p1', 'p2', NO_PROJECT])
    expect(g[0].tasks.map((t) => t.id)).toEqual(['p1a', 'p1a-sub'])
  })
  it('une boucle de parenté ne fait rien disparaître', () => {
    const tasks = [task('a', { parent_id: 'b' }), task('b', { parent_id: 'a' })]
    expect(orderAsTree(tasks).map((t) => t.id).sort()).toEqual(['a', 'b'])
  })
})

describe('Gantt : lignes', () => {
  it('mode tâches : un récapitulatif par projet puis ses tâches ; replier un projet cache ses tâches', () => {
    const tasks = [task('t1', { project_id: 'p1', start_date: '2026-05-01', due_date: '2026-05-05' })]
    const projects = [{ id: 'p1', name: 'P1', progress: 40, start_date: '2026-05-01', end_date: '2026-05-31' }]
    const colors = new Map([['p1', '#123456']])
    const rows = buildGanttRows('tasks', tasks, projects, colors, new Set(), 'Sans projet')
    expect(rows.map((r) => `${r.kind}:${r.id}`)).toEqual(['project:p1', 'task:t1'])
    expect(rows[1].color).toBe('#123456')
    expect(buildGanttRows('tasks', tasks, projects, colors, new Set(['project:p1']), '—')).toHaveLength(1)
    expect(buildGanttRows('projects', tasks, projects, colors, new Set(), '—').map((r) => r.kind)).toEqual(['project'])
  })
  it('un projet sans dates n’est pas déplaçable, sa barre couvre ses tâches', () => {
    const tasks = [task('t1', { project_id: 'p1', start_date: '2026-05-03', due_date: '2026-05-09' })]
    const rows = buildGanttRows('tasks', tasks, [{ id: 'p1', name: 'P1', progress: 0, start_date: null, end_date: null }], new Map(), new Set(), '—')
    expect(rows[0]).toMatchObject({ kind: 'project', start: '2026-05-03', end: '2026-05-09', draggable: false })
  })
})

describe('Gantt : bornes pendant le glissement (mêmes règles que 801 et 802)', () => {
  const parent = task('M', { project_id: 'p', start_date: '2026-03-01', due_date: '2026-03-31' })
  const child = task('F', { project_id: 'p', parent_id: 'M', start_date: '2026-03-10', due_date: '2026-03-20' })
  const pred = task('A', { project_id: 'p', start_date: '2026-03-01', due_date: '2026-03-12' })
  const byId = new Map([parent, child, pred].map((t) => [t.id, t]))
  const projects = new Map([['p', { id: 'p', name: 'P', progress: 0, start_date: '2026-01-01', end_date: '2026-12-31' }]])
  const dep: ProjectTaskDependency = { id: 'd', tenant_id: 't', task_id: 'F', depends_on_task_id: 'A', dependency_type: 'finish-to-start', lag_days: 0, created_at: '' }

  it('une sous-tâche glissée s’arrête au bord de sa mère', () => {
    const b = taskBounds(child, byId, projects, [], [])
    expect(applyDrag('move', '2026-03-10', '2026-03-20', +30, b)).toEqual({ start: '2026-03-21', end: '2026-03-31' })
    expect(applyDrag('move', '2026-03-10', '2026-03-20', -30, b)).toEqual({ start: '2026-03-01', end: '2026-03-11' })
  })
  it('un successeur ne recule pas avant le lendemain de la fin de son prédécesseur', () => {
    const b = taskBounds(child, byId, projects, [], [dep])
    expect(b.minStart).toBe('2026-03-13')
    expect(applyDrag('move', '2026-03-13', '2026-03-23', -5, b).start).toBe('2026-03-13')
  })
  it('redimensionner une mère ne coupe pas sa fille, et garde au moins un jour', () => {
    const b = taskBounds(parent, byId, projects, [child], [])
    expect(applyDrag('resize-end', '2026-03-01', '2026-03-31', -20, b).end).toBe('2026-03-20')
    expect(applyDrag('resize-start', '2026-03-01', '2026-03-31', +15, b).start).toBe('2026-03-10')
    expect(applyDrag('resize-end', '2026-03-01', '2026-03-05', -40, NONE).end).toBe('2026-03-01')
  })
  it('un projet ne commence pas avant la fin de celui qu’il attend', () => {
    const ps = new Map([
      ['p1', { id: 'p1', name: 'P1', progress: 0, start_date: '2026-01-01', end_date: '2026-01-31' }],
      ['p2', { id: 'p2', name: 'P2', progress: 0, start_date: '2026-02-01', end_date: '2026-02-28' }],
    ])
    const b = projectBounds(ps, [], [{ id: 'x', tenant_id: 't', project_id: 'p2', depends_on_project_id: 'p1', lag_days: 2, created_at: '' }])
    expect(b.minStart).toBe('2026-02-03')
  })
})

describe('Gantt : tracé des flèches', () => {
  it('fin → début : angle droit simple quand il y a de la place', () => {
    expect(dependencyPath('finish-to-start', { x1: 0, x2: 100, y: 18 }, { x1: 140, x2: 200, y: 54 }, 36)).toBe('M 100 18 H 108 V 54 H 140')
  })
  it('chevauchement : le trait passe par l’interligne au lieu de traverser les barres', () => {
    const d = dependencyPath('finish-to-start', { x1: 0, x2: 100, y: 18 }, { x1: 60, x2: 120, y: 54 }, 36)
    expect(d).toBe('M 100 18 H 108 V 36 H 52 V 54 H 60')
  })
})
