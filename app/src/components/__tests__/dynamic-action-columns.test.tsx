import { describe, it, expect, vi } from 'vitest'
import { render, fireEvent, within, renderHook, waitFor } from '@testing-library/react'
import { createRef } from 'react'
import { TaskFixedColumns, type RowHandlers } from '@/components/project-management/TaskFixedColumns'
import { TaskActionColumns } from '@/components/project-management/TaskActionColumns'
import { buildTableRows, rowHeight } from '@/components/project-management/table/rows'
import { applyTaskFilters } from '@/components/project-management/table/FilterBar'
import {
  actionKey,
  buildActionMatrix,
  compareDisplayOrder,
  sortTasksByDisplayOrder,
} from '@/lib/actionColumns'
import { emptyTaskFilters, type ProjectTask, type TaskAction } from '@/types/projectManagement'

// Le tableau dynamique en DEUX panneaux, comme celui de wadashaqayn : colonnes
// de la tâche à gauche, colonnes d'actions à droite. Deux <table> distincts : ce
// qui les garde alignés, c'est UNE liste de lignes et UNE hauteur par ligne. Ces
// tests vérifient que les deux panneaux posent les mêmes lignes aux mêmes
// hauteurs, et le comportement des cases (preuve obligatoire, 803).

vi.mock('react-i18next', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react-i18next')>()
  return {
    ...actual,
    useTranslation: vi.fn(() => ({ t: (key: string) => key, i18n: { language: 'fr', changeLanguage: vi.fn() } })),
  }
})

// Le sélecteur de responsable interroge les employés et les modules du tenant :
// hors sujet ici, et sans Supabase simulé il rejette en tâche de fond.
vi.mock('@/components/project-management/AssigneeSelect', () => ({ AssigneeSelect: () => <span /> }))

const getTaskActionsForTasks = vi.hoisted(() => vi.fn())
vi.mock('@/lib/queries/projectManagement', () => ({ getActionsForTasks: getTaskActionsForTasks }))

function task(id: string, order: string, extra: Partial<ProjectTask> = {}): ProjectTask {
  return {
    id,
    tenant_id: 't1',
    project_id: null,
    parent_id: null,
    title: `Tâche ${id}`,
    description: null,
    status: 'todo',
    priority: 'medium',
    assignee: null,
    assignee_id: null,
    start_date: null,
    due_date: null,
    effort_estimate_h: 0,
    effort_spent_h: 0,
    progress: 0,
    display_order: order,
    task_level: 0,
    budget: 0,
    color: 0,
    acceptance_criteria: null,
    recurring_task: false,
    recurring_interval: 1,
    recurring_rule_type: 'weekly',
    is_closed: false,
    linked_action_id: null,
    created_at: '',
    updated_at: '',
    ...extra,
  } as ProjectTask
}

function action(id: string, taskId: string, title: string, extra: Partial<TaskAction> = {}): TaskAction {
  return {
    id,
    tenant_id: 't1',
    task_id: taskId,
    title,
    weight_percentage: 25,
    is_done: false,
    progress: extra.is_done ? 100 : 0,
    due_date: null,
    notes: null,
    created_at: '',
    ...extra,
  }
}

describe('ordre des lignes', () => {
  it('compare display_order en nombres, pas en texte', () => {
    expect(compareDisplayOrder('10', '2')).toBeGreaterThan(0)
    expect(compareDisplayOrder('1.10', '1.2')).toBeGreaterThan(0)
    expect(compareDisplayOrder('1', '1.1')).toBeLessThan(0)
    expect(compareDisplayOrder(null, '0')).toBe(0)
    expect(compareDisplayOrder('abc', '0')).toBe(0)
  })

  it('range 1, 2, 10 (et pas 1, 10, 2) en gardant l’ordre de lecture à rang égal', () => {
    const sorted = sortTasksByDisplayOrder([task('c', '10'), task('a', '2'), task('b', '1'), task('d', '2')])
    expect(sorted.map((t) => t.id)).toEqual(['b', 'a', 'd', 'c'])
  })
})

describe('buildActionMatrix', () => {
  it('une colonne par titre, casse et espaces ignorés, dans l’ordre de première apparition', () => {
    const m = buildActionMatrix(
      ['t1', 't2', 't3'],
      [
        action('a1', 't1', 'Valider le devis'),
        action('a2', 't1', 'Envoyer'),
        action('a3', 't2', 'valider  LE devis '),
        action('a4', 't2', 'Facturer'),
        action('a5', 't3', 'Envoyer'),
      ]
    )
    expect(m.columns.map((c) => c.title)).toEqual(['Valider le devis', 'Envoyer', 'Facturer'])
    expect(m.columns.map((c) => c.taskCount)).toEqual([2, 2, 1])
    expect(m.byTask.get('t2')!.get(actionKey('Valider le devis'))!.id).toBe('a3')
    expect(m.byTask.get('t2')!.has(actionKey('Envoyer'))).toBe(false)
  })

  it('deux actions de même titre sur une tâche : une seule colonne, la première gagne', () => {
    const m = buildActionMatrix(['t1'], [action('a1', 't1', 'Envoyer'), action('a2', 't1', 'envoyer')])
    expect(m.columns).toHaveLength(1)
    expect(m.byTask.get('t1')!.get('envoyer')!.id).toBe('a1')
  })

  it('ignore les actions d’une tâche absente du tableau et les titres vides', () => {
    const m = buildActionMatrix(['t1'], [action('a1', 'ailleurs', 'X'), action('a2', 't1', '   ')])
    expect(m.columns).toHaveLength(0)
  })

  it('reste rapide à 300 tâches × 40 colonnes', () => {
    const ids = Array.from({ length: 300 }, (_, i) => `t${i}`)
    const actions = ids.flatMap((id, i) =>
      Array.from({ length: 40 }, (_, j) => action(`a${i}-${j}`, id, `Action ${j}`))
    )
    const start = performance.now()
    const m = buildActionMatrix(ids, actions)
    const ms = performance.now() - start
    expect(m.columns).toHaveLength(40)
    expect(ms).toBeLessThan(250) // 12 000 actions ; mesuré à quelques ms, marge large pour la CI
  })
})

const noop = () => {}
const handlers: RowHandlers = {
  onSelect: noop, onEdit: noop, onUpdate: async () => {}, onDelete: noop, onDuplicate: noop,
  onAddSubTask: noop, onCreateFromGhost: async () => {}, onToggleBand: noop, onCountsChanged: noop,
}

function renderPanels(tasks: ProjectTask[], actions: TaskAction[], opts: { proofs?: Map<string, number>; selected?: string | null; canEdit?: boolean; onToggle?: (a: TaskAction) => void; onProof?: (a: TaskAction) => void } = {}) {
  const sorted = sortTasksByDisplayOrder(tasks)
  const matrix = buildActionMatrix(sorted.map((t) => t.id), actions)
  const projects = [{ id: 'p1', name: 'Projet 1', progress: 40, start_date: '2026-01-01', end_date: '2026-12-31' }]
  const rows = buildTableRows(sorted, projects, new Map([['p1', '#123456']]), new Set(), true)
  const view = render(
    <div>
      <TaskFixedColumns rows={rows} handlers={handlers} selectedTaskId={opts.selected ?? null} projectNames={new Map([['p1', 'Projet 1']])}
        documents={new Map()} comments={new Map()} canEdit={opts.canEdit ?? true} canDelete scrollRef={createRef()} onScroll={noop} />
      <TaskActionColumns rows={rows} matrix={matrix} proofs={opts.proofs ?? new Map()} selectedTaskId={opts.selected ?? null}
        canEdit={opts.canEdit ?? true} onToggle={opts.onToggle ?? noop} onProof={opts.onProof ?? noop} scrollRef={createRef()} onScroll={noop} />
    </div>
  )
  const [left, right] = Array.from(view.container.querySelectorAll('[data-panel]'))
  return { rows, left: left as HTMLElement, right: right as HTMLElement, matrix }
}

describe('lignes communes aux deux panneaux', () => {
  const tasks = [task('a', '1', { project_id: 'p1' }), task('a1', '0', { project_id: 'p1', parent_id: 'a' }), task('b', '2', { project_id: 'p1' }), task('z', '3')]

  it('bandeau par projet, sous-tâche après sa mère, numéros 1 / 1.1 / 2, « sans projet » puis UNE ligne fantôme', () => {
    const rows = buildTableRows(sortTasksByDisplayOrder(tasks), [{ id: 'p1', name: 'P1', progress: 0, start_date: null, end_date: null }], new Map(), new Set(), true)
    expect(rows.map((r) => (r.kind === 'task' ? `${r.number}:${r.task.id}` : r.kind))).toEqual([
      'band', '1:a', '1.1:a1', '2:b', 'band', '3:z', 'ghost',
    ])
    expect(rows.map(rowHeight).slice(0, 4)).toEqual([44, 64, 51, 64])
  })

  it('les deux panneaux posent exactement les mêmes lignes, aux mêmes hauteurs', () => {
    const { left, right } = renderPanels(tasks, [action('x', 'a', 'Valider')])
    const h = (el: HTMLElement) => Array.from(el.querySelectorAll('tbody > tr')).map((tr) => (tr as HTMLElement).style.height)
    expect(h(left).length).toBe(7)
    expect(h(right)).toEqual(h(left))
  })
})

describe('colonnes d’actions', () => {
  const tasks = [task('a', '1', { project_id: 'p1' }), task('b', '2', { project_id: 'p1' })]
  const actions = [action('x1', 'a', 'Valider'), action('x2', 'a', 'Envoyer'), action('x3', 'b', 'Envoyer'), action('x4', 'b', 'Facturer', { is_done: true })]

  it('une colonne par titre ; une case vide (point discret) là où la tâche n’a pas l’action', () => {
    const { right } = renderPanels(tasks, actions)
    expect(within(right).getAllByRole('columnheader').map((th) => th.textContent)).toEqual(['Valider', 'Envoyer', 'Facturer'])
    const rowB = within(right).getAllByRole('row').find((r) => within(r).queryAllByRole('checkbox', { name: /Tâche b/ }).length > 0)!
    expect(within(rowB).getAllByRole('checkbox')).toHaveLength(2)
    expect(within(rowB).getByText('·')).toBeTruthy()
  })

  it('la tâche sélectionnée voit ses colonnes passer en premier', () => {
    const { right } = renderPanels(tasks, actions, { selected: 'b' })
    expect(within(right).getAllByRole('columnheader').map((th) => th.textContent)).toEqual(['Envoyer', 'Facturer', 'Valider'])
  })

  it('sans preuve, la case est grisée ; avec une preuve elle se coche et signale la bonne action', () => {
    const onToggle = vi.fn()
    const { right } = renderPanels(tasks, actions, { proofs: new Map([['x2', 1]]), onToggle })
    const sansPreuve = within(right).getByRole('checkbox', { name: /Valider — Tâche a/ })
    expect(sansPreuve).toBeDisabled()
    fireEvent.click(sansPreuve)
    expect(onToggle).not.toHaveBeenCalled()
    fireEvent.click(within(right).getByRole('checkbox', { name: /Envoyer — Tâche a/ }))
    expect(onToggle.mock.calls[0][0].id).toBe('x2')
  })

  it('une action déjà cochée reste décochable sans preuve ; le « + » ouvre ses preuves', () => {
    const onToggle = vi.fn()
    const onProof = vi.fn()
    const { right } = renderPanels(tasks, actions, { onToggle, onProof })
    const faite = within(right).getByRole('checkbox', { name: /Facturer/ })
    expect(faite).toHaveAttribute('aria-checked', 'true')
    expect(faite).not.toBeDisabled()
    fireEvent.click(within(right).getAllByRole('button', { name: 'dyn.proofAdd' })[0])
    expect(onProof).toHaveBeenCalledTimes(1)
  })

  it('un lecteur sans droit d’édition ne voit ni case active ni « + »', () => {
    const { right } = renderPanels(tasks, actions, { canEdit: false, proofs: new Map([['x2', 1]]) })
    within(right).getAllByRole('checkbox').forEach((c) => expect(c).toBeDisabled())
    expect(within(right).queryAllByRole('button', { name: 'dyn.proofAdd' })).toHaveLength(0)
  })

  it('sans aucune action : le message « aucune colonne » à la place du tableau', () => {
    const { right } = renderPanels(tasks, [])
    expect(within(right).getByText('dyn.noActionColumns')).toBeTruthy()
  })
})

describe('filtres', () => {
  const tasks = [
    task('a', '1', { title: 'Maquettes', status: 'doing', priority: 'high', project_id: 'p1', start_date: '2026-03-01', due_date: '2026-03-10', assignee_id: 'e1' }),
    task('b', '2', { title: 'Recette', description: 'tests de maquette', status: 'todo', priority: 'low', start_date: '2026-04-01', due_date: '2026-04-10' }),
  ]
  it('recherche titre ET description ; statut, priorité, projet, assigné, période', () => {
    const f = { ...emptyTaskFilters }
    expect(applyTaskFilters(tasks, { ...f, search: 'maquette' }).map((t) => t.id)).toEqual(['a', 'b'])
    expect(applyTaskFilters(tasks, { ...f, status: ['doing'] }).map((t) => t.id)).toEqual(['a'])
    expect(applyTaskFilters(tasks, { ...f, priority: ['low'] }).map((t) => t.id)).toEqual(['b'])
    expect(applyTaskFilters(tasks, { ...f, project: ['p1'] }).map((t) => t.id)).toEqual(['a'])
    expect(applyTaskFilters(tasks, { ...f, assignee: ['e1'] }).map((t) => t.id)).toEqual(['a'])
    expect(applyTaskFilters(tasks, { ...f, dateFrom: '2026-03-15' }).map((t) => t.id)).toEqual(['b'])
    expect(applyTaskFilters(tasks, { ...f, dateTo: '2026-03-31' }).map((t) => t.id)).toEqual(['a'])
  })
})

describe('useTaskActionMatrix', () => {
  it('lit les actions en une requête, puis seulement celles des nouvelles tâches', async () => {
    const { useTaskActionMatrix } = await import('@/hooks/useTaskActionMatrix')
    getTaskActionsForTasks.mockReset()
    getTaskActionsForTasks.mockImplementation(async (ids: string[]) =>
      ids.map((id) => action(`act-${id}`, id, 'Valider'))
    )
    const { result, rerender } = renderHook(({ list }) => useTaskActionMatrix(list), {
      initialProps: { list: [task('a', '1'), task('b', '2')] },
    })
    await waitFor(() => expect(result.current.matrix.columns).toHaveLength(1))
    expect(getTaskActionsForTasks).toHaveBeenCalledTimes(1)
    expect(getTaskActionsForTasks.mock.calls[0][0].sort()).toEqual(['a', 'b'])

    // même tâches, autre ordre : aucune relecture
    rerender({ list: [task('b', '1'), task('a', '2')] })
    // une tâche de plus : seule celle-là est lue
    rerender({ list: [task('b', '1'), task('a', '2'), task('c', '3')] })
    await waitFor(() => expect(getTaskActionsForTasks).toHaveBeenCalledTimes(2))
    expect(getTaskActionsForTasks.mock.calls[1][0]).toEqual(['c'])
    await waitFor(() => expect(result.current.matrix.byTask.has('c')).toBe(true))

    // une tâche retirée perd ses actions sans relecture
    rerender({ list: [task('c', '3')] })
    await waitFor(() => expect(result.current.matrix.byTask.has('a')).toBe(false))
    expect(getTaskActionsForTasks).toHaveBeenCalledTimes(2)
  })
})
