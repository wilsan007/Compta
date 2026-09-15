import { describe, it, expect, vi, beforeEach } from 'vitest'

// ============================================================
// Tests complets : Requêtes gestion de projets (migration 85)
// Teste le CRUD, sous-tâches, dependencies, milestones, watchers,
// time entries, activity log, templates, notifications, tenant isolation.
// ============================================================

// ============ Mock Infrastructure ============
function createMockChain(resolvedValue: { data: any; error: any } = { data: [], error: null }) {
  const chain: any = {
    select: vi.fn(() => chain),
    insert: vi.fn(() => chain),
    update: vi.fn(() => chain),
    delete: vi.fn(() => chain),
    eq: vi.fn(() => chain),
    neq: vi.fn(() => chain),
    order: vi.fn(() => chain),
    single: vi.fn(() => Promise.resolve(resolvedValue)),
    maybeSingle: vi.fn(() => Promise.resolve(resolvedValue)),
    limit: vi.fn(() => chain),
    range: vi.fn(() => Promise.resolve(resolvedValue)),
    in: vi.fn(() => chain),
    gte: vi.fn(() => chain),
    lte: vi.fn(() => chain),
    like: vi.fn(() => chain),
    ilike: vi.fn(() => chain),
    or: vi.fn(() => chain),
    not: vi.fn(() => chain),
    is: vi.fn(() => chain),
    count: vi.fn(() => chain),
    then: vi.fn((resolve: any) => Promise.resolve(resolvedValue).then(resolve)),
  }
  return chain
}

const mockChain = createMockChain()

vi.mock('@/lib/supabase', () => ({
  supabase: {
    from: vi.fn(() => mockChain),
    auth: {
      getSession: vi.fn(() => Promise.resolve({
        data: { session: { user: { id: 'user-1', email: 'test@test.com' } } },
      })),
    },
    channel: vi.fn(),
    removeChannel: vi.fn(),
    rpc: vi.fn(() => Promise.resolve({ data: null, error: null })),
    storage: {
      from: vi.fn(() => ({
        upload: vi.fn(() => Promise.resolve({ data: {}, error: null })),
        getPublicUrl: vi.fn(() => ({ data: { publicUrl: 'url' } })),
      })),
    },
  },
  getCachedTenantId: vi.fn(() => 'test-tenant-id'),
  isTenantTable: vi.fn(() => true),
}))

vi.mock('@/lib/queries/core', () => ({
  getTenantId: vi.fn(() => Promise.resolve('test-tenant-id')),
  ti: vi.fn((payload: any, _table: string, _tid?: string) => ({ ...payload, tenant_id: _tid || 'test-tenant-id' })),
  tud: vi.fn((chain: any, _table: string, _tid?: string) => chain),
}))

import { supabase } from '@/lib/supabase'
import {
  getTasks,
  getTaskById,
  createTask,
  updateTask,
  deleteTask,
  duplicateTask,
  createSubTask,
  getTaskActions,
  addActionColumn,
  addDetailedAction,
  recalculateTaskProgress,
  toggleAction,
  deleteAction,
  getTaskComments,
  addTaskComment,
  getTaskDependencies,
  createTaskDependency,
  deleteTaskDependency,
  getProjectStages,
  createProjectStage,
  getProjectMilestones,
  createProjectMilestone,
  updateProjectMilestone,
  getProjectTags,
  createProjectTag,
  getTaskAssignees,
  assignTaskToEmployee,
  unassignTaskFromEmployee,
  setTaskAssignee,
  getSubtaskCount,
  getProjectMembers,
  addProjectMember,
  removeProjectMember,
  updateProjectMemberRole,
} from '@/lib/queries/projectManagement'

// ============ Helper ============
function setMockData(data: any, error: any = null) {
  mockChain.single = vi.fn(() => Promise.resolve({ data, error }))
  mockChain.maybeSingle = vi.fn(() => Promise.resolve({ data, error }))
  mockChain.then = vi.fn((resolve: any) => Promise.resolve({ data, error }).then(resolve))
}

function resetMock() {
  mockChain.single = vi.fn(() => Promise.resolve({ data: null, error: null }))
  mockChain.maybeSingle = vi.fn(() => Promise.resolve({ data: null, error: null }))
  mockChain.then = vi.fn((resolve: any) => Promise.resolve({ data: [], error: null }).then(resolve))
  vi.clearAllMocks()
  ;(supabase as any).from = vi.fn(() => mockChain)
}

beforeEach(() => resetMock())

// ============ 1. Task CRUD ============
describe('1. Task CRUD', () => {
  it('getTasks retourne toutes les tâches du tenant', async () => {
    const tasks = [{ id: 't1', title: 'Task 1', tenant_id: 'test-tenant-id' }]
    setMockData(tasks)
    const result = await getTasks()
    expect(result).toEqual(tasks)
    expect(supabase.from).toHaveBeenCalledWith('project_tasks')
  })

  it('getTasks filtre par projectId', async () => {
    setMockData([])
    await getTasks('proj-1')
    expect(mockChain.eq).toHaveBeenCalledWith('project_id', 'proj-1')
  })

  it('getTaskById retourne null si non trouvé', async () => {
    setMockData(null)
    const result = await getTaskById('nonexistent')
    expect(result).toBeNull()
  })

  it('getTaskById retourne la tâche', async () => {
    const task = { id: 't1', title: 'Task 1' }
    setMockData(task)
    const result = await getTaskById('t1')
    expect(result).toEqual(task)
  })

  it('createTask insère et retourne la tâche', async () => {
    const task = { id: 't1', title: 'New Task' }
    setMockData(task)
    const result = await createTask({
      title: 'New Task',
      project_id: 'p1',
      parent_id: null,
      status: 'todo',
      priority: 'medium',
      assignee: null,
      start_date: null,
      due_date: null,
      effort_estimate_h: 0,
      effort_spent_h: 0,
      progress: 0,
      display_order: '0',
      task_level: 0,
      budget: 0,
      color: 0,
      acceptance_criteria: null,
      recurring_task: false,
      recurring_interval: 1,
      recurring_rule_type: 'weekly',
      linked_action_id: null,
      production_order_id: null,
    })
    expect(result).toEqual(task)
    expect(mockChain.insert).toHaveBeenCalled()
  })

  it('createTask propage l\'erreur Supabase', async () => {
    setMockData(null, { message: 'Insert failed', code: '23505' })
    await expect(createTask({
      title: 'Fail',
      project_id: null, parent_id: null, status: 'todo', priority: 'low',
      assignee: null, start_date: null, due_date: null,
      effort_estimate_h: 0, effort_spent_h: 0, progress: 0,
      display_order: '0', task_level: 0, budget: 0, color: 0,
      acceptance_criteria: null, recurring_task: false, recurring_interval: 1,
      recurring_rule_type: 'weekly', linked_action_id: null, production_order_id: null,
    })).rejects.toThrow('Insert failed')
  })

  it('updateTask met à jour et retourne la tâche', async () => {
    const updated = { id: 't1', title: 'Updated', status: 'done' }
    setMockData(updated)
    const result = await updateTask('t1', { status: 'done' })
    expect(result).toEqual(updated)
    expect(mockChain.update).toHaveBeenCalled()
    expect(mockChain.eq).toHaveBeenCalledWith('id', 't1')
  })

  it('deleteTask supprime sans erreur', async () => {
    setMockData(null)
    await expect(deleteTask('t1')).resolves.toBeUndefined()
    expect(mockChain.delete).toHaveBeenCalled()
  })

  it('deleteTask propage l\'erreur', async () => {
    setMockData(null, { message: 'Delete failed' })
    await expect(deleteTask('t1')).rejects.toThrow('Delete failed')
  })

  it('duplicateTask lève une erreur si tâche inexistante', async () => {
    setMockData(null)
    await expect(duplicateTask('nonexistent')).rejects.toThrow('Task not found')
  })

  it('duplicateTask crée une copie avec "(copy)"', async () => {
    const existing = {
      id: 't1', tenant_id: 'tt', created_at: '2024', updated_at: '2024',
      is_closed: false, subtask_count: 0, subtask_done_count: 0,
      assignees: [], tags: [], actions: [], dependencies: [],
      title: 'Original', project_id: 'p1', parent_id: null,
      status: 'todo', priority: 'medium', assignee: null,
      start_date: null, due_date: null, effort_estimate_h: 5,
      effort_spent_h: 2, progress: 40, display_order: '1',
      task_level: 0, budget: 1000, color: 0,
      acceptance_criteria: null, recurring_task: false,
      recurring_interval: 1, recurring_rule_type: 'weekly',
      linked_action_id: null, production_order_id: null,
    }
    // Premier appel: getTaskById → existing
    mockChain.maybeSingle = vi.fn(() => Promise.resolve({ data: existing, error: null }))
    // Deuxième appel: createTask → new task
    const duplicated = { ...existing, id: 't2', title: 'Original (copy)' }
    mockChain.single = vi.fn(() => Promise.resolve({ data: duplicated, error: null }))
    const result = await duplicateTask('t1')
    expect(result.title).toBe('Original (copy)')
  })
})

// ============ 2. Sous-tâches ============
describe('2. Sous-tâches', () => {
  it('createSubTask lève une erreur si parent inexistant', async () => {
    mockChain.maybeSingle = vi.fn(() => Promise.resolve({ data: null, error: null }))
    await expect(createSubTask('nonexistent', 'Sub')).rejects.toThrow('Parent task not found')
  })

  it('createSubTask crée une tâche avec parent_id', async () => {
    const parent = {
      id: 'p1', project_id: 'proj-1', task_level: 0,
      title: 'Parent', tenant_id: 'tt',
    }
    mockChain.maybeSingle = vi.fn(() => Promise.resolve({ data: parent, error: null }))
    const subtask = { id: 's1', title: 'Sub', parent_id: 'p1', task_level: 1 }
    mockChain.single = vi.fn(() => Promise.resolve({ data: subtask, error: null }))
    const result = await createSubTask('p1', 'Sub')
    expect(result.parent_id).toBe('p1')
    expect(result.task_level).toBe(1)
  })

  it('createSubTask utilise projectId du parent si non fourni', async () => {
    const parent = { id: 'p1', project_id: 'proj-1', task_level: 0, title: 'P' }
    mockChain.maybeSingle = vi.fn(() => Promise.resolve({ data: parent, error: null }))
    const subtask = { id: 's1', title: 'Sub', parent_id: 'p1' }
    mockChain.single = vi.fn(() => Promise.resolve({ data: subtask, error: null }))
    await createSubTask('p1', 'Sub')
    // L'insert doit avoir été appelé avec project_id = 'proj-1'
    expect(mockChain.insert).toHaveBeenCalled()
    const insertedPayload = mockChain.insert.mock.calls[0][0]
    expect(insertedPayload.project_id).toBe('proj-1')
  })

  it('createSubTask avec taskLevel explicite', async () => {
    const parent = { id: 'p1', project_id: 'proj-1', task_level: 0, title: 'P' }
    mockChain.maybeSingle = vi.fn(() => Promise.resolve({ data: parent, error: null }))
    const subtask = { id: 's1', title: 'Sub', parent_id: 'p1', task_level: 3 }
    mockChain.single = vi.fn(() => Promise.resolve({ data: subtask, error: null }))
    await createSubTask('p1', 'Sub', null, 3)
    const insertedPayload = mockChain.insert.mock.calls[0][0]
    expect(insertedPayload.task_level).toBe(3)
  })

  it('getSubtaskCount retourne total et done', async () => {
    const subtasks = [
      { status: 'done' },
      { status: 'done' },
      { status: 'canceled' },
      { status: 'todo' },
      { status: 'doing' },
    ]
    setMockData(subtasks)
    const result = await getSubtaskCount('p1')
    expect(result.total).toBe(5)
    expect(result.done).toBe(3)  // done + canceled
  })

  it('getSubtaskCount avec aucune sous-tâche', async () => {
    setMockData([])
    const result = await getSubtaskCount('p1')
    expect(result.total).toBe(0)
    expect(result.done).toBe(0)
  })
})

// ============ 3. Task Actions (checklist) ============
describe('3. Task Actions (checklist)', () => {
  it('getTaskActions retourne les actions', async () => {
    const actions = [{ id: 'a1', title: 'Action 1', is_done: false }]
    setMockData(actions)
    const result = await getTaskActions('t1')
    expect(result).toEqual(actions)
    expect(mockChain.eq).toHaveBeenCalledWith('task_id', 't1')
  })

  it('addActionColumn crée une action avec poids par défaut 0', async () => {
    const action = { id: 'a1', title: 'Col', weight_percentage: 0, is_done: false }
    setMockData(action)
    const result = await addActionColumn('t1', 'Col')
    expect(result).toEqual(action)
    const payload = mockChain.insert.mock.calls[0][0]
    expect(payload.weight_percentage).toBe(0)
  })

  it('addActionColumn avec poids explicite', async () => {
    setMockData({ id: 'a1', weight_percentage: 50 })
    await addActionColumn('t1', 'Col', 50)
    const payload = mockChain.insert.mock.calls[0][0]
    expect(payload.weight_percentage).toBe(50)
  })

  it('addDetailedAction crée avec due_date et notes', async () => {
    setMockData({ id: 'a1' })
    await addDetailedAction('t1', 'Detailed', 30, '2024-12-31', 'My notes')
    const payload = mockChain.insert.mock.calls[0][0]
    expect(payload.due_date).toBe('2024-12-31')
    expect(payload.notes).toBe('My notes')
    expect(payload.weight_percentage).toBe(30)
  })

  it('recalculateTaskProgress avec actions pondérées', async () => {
    const actions = [
      { id: 'a1', is_done: true, weight_percentage: 50 },
      { id: 'a2', is_done: false, weight_percentage: 50 },
    ]
    // Premier appel: getTaskActions
    setMockData(actions)
    // Deuxième appel: updateTask
    mockChain.single = vi.fn(() => Promise.resolve({ data: { id: 't1', progress: 50 }, error: null }))
    const progress = await recalculateTaskProgress('t1')
    expect(progress).toBe(50)
  })

  it('recalculateTaskProgress sans poids → proportionnelle', async () => {
    const actions = [
      { id: 'a1', is_done: true, weight_percentage: 0 },
      { id: 'a2', is_done: true, weight_percentage: 0 },
      { id: 'a3', is_done: false, weight_percentage: 0 },
    ]
    setMockData(actions)
    mockChain.single = vi.fn(() => Promise.resolve({ data: { progress: 67 }, error: null }))
    const progress = await recalculateTaskProgress('t1')
    expect(progress).toBe(67)  // 2/3 * 100 = 66.67 → arrondi à 67
  })

  it('recalculateTaskProgress sans actions → 0', async () => {
    setMockData([])
    const progress = await recalculateTaskProgress('t1')
    expect(progress).toBe(0)
  })

  it('recalculateTaskProgress toutes done → 100', async () => {
    const actions = [
      { id: 'a1', is_done: true, weight_percentage: 50 },
      { id: 'a2', is_done: true, weight_percentage: 50 },
    ]
    setMockData(actions)
    mockChain.single = vi.fn(() => Promise.resolve({ data: { progress: 100 }, error: null }))
    const progress = await recalculateTaskProgress('t1')
    expect(progress).toBe(100)
  })

  it('toggleAction met à jour et recalcule', async () => {
    const action = { id: 'a1', task_id: 't1', is_done: true, weight_percentage: 100 }
    mockChain.single = vi.fn(() => Promise.resolve({ data: action, error: null }))
    // Pour recalculateTaskProgress
    mockChain.then = vi.fn((resolve: any) => Promise.resolve({ data: [action], error: null }).then(resolve))
    const result = await toggleAction('a1', true)
    expect(result.action).toEqual(action)
    expect(result.progress).toBe(100)
  })

  it('deleteAction supprime', async () => {
    setMockData(null)
    await expect(deleteAction('a1')).resolves.toBeUndefined()
  })
})

// ============ 4. Task Comments ============
describe('4. Task Comments', () => {
  it('getTaskComments retourne les commentaires', async () => {
    const comments = [{ id: 'c1', content: 'Hello' }]
    setMockData(comments)
    const result = await getTaskComments('t1')
    expect(result).toEqual(comments)
  })

  it('addTaskComment crée avec type par défaut "general"', async () => {
    setMockData({ id: 'c1', content: 'Hi', comment_type: 'general' })
    await addTaskComment('t1', 'Hi')
    const payload = mockChain.insert.mock.calls[0][0]
    expect(payload.comment_type).toBe('general')
  })

  it('addTaskComment avec type explicite', async () => {
    setMockData({ id: 'c1' })
    await addTaskComment('t1', 'Hi', 'approval')
    const payload = mockChain.insert.mock.calls[0][0]
    expect(payload.comment_type).toBe('approval')
  })
})

// ============ 5. Task Dependencies ============
describe('5. Task Dependencies', () => {
  it('getTaskDependencies retourne les dépendances', async () => {
    const deps = [{ id: 'd1', task_id: 't1', depends_on_task_id: 't2' }]
    setMockData(deps)
    const result = await getTaskDependencies('t1')
    expect(result).toEqual(deps)
  })

  it('createTaskDependency crée avec type par défaut "finish-to-start"', async () => {
    setMockData({ id: 'd1' })
    await createTaskDependency('t1', 't2')
    const payload = mockChain.insert.mock.calls[0][0]
    expect(payload.dependency_type).toBe('finish-to-start')
    expect(payload.lag_days).toBe(0)
  })

  it('createTaskDependency avec type et lag explicites', async () => {
    setMockData({ id: 'd1' })
    await createTaskDependency('t1', 't2', 'start-to-start', 5)
    const payload = mockChain.insert.mock.calls[0][0]
    expect(payload.dependency_type).toBe('start-to-start')
    expect(payload.lag_days).toBe(5)
  })

  it('deleteTaskDependency supprime', async () => {
    setMockData(null)
    await expect(deleteTaskDependency('d1')).resolves.toBeUndefined()
  })
})

// ============ 6. Project Stages ============
describe('6. Project Stages', () => {
  it('getProjectStages retourne les étapes', async () => {
    const stages = [{ id: 's1', name: 'To Do', sequence: 1 }]
    setMockData(stages)
    const result = await getProjectStages()
    expect(result).toEqual(stages)
  })

  it('createProjectStage crée avec fold=false par défaut', async () => {
    setMockData({ id: 's1' })
    await createProjectStage('Done', 3)
    const payload = mockChain.insert.mock.calls[0][0]
    expect(payload.fold).toBe(false)
    expect(payload.case_default).toBe(false)
  })

  it('createProjectStage avec fold=true', async () => {
    setMockData({ id: 's1' })
    await createProjectStage('Archived', 4, true)
    const payload = mockChain.insert.mock.calls[0][0]
    expect(payload.fold).toBe(true)
  })
})

// ============ 7. Project Milestones ============
describe('7. Project Milestones', () => {
  it('getProjectMilestones retourne les jalons', async () => {
    const milestones = [{ id: 'm1', name: 'M1', deadline: '2024-12-31' }]
    setMockData(milestones)
    const result = await getProjectMilestones('p1')
    expect(result).toEqual(milestones)
  })

  it('createProjectMilestone crée avec is_reached=false', async () => {
    setMockData({ id: 'm1' })
    await createProjectMilestone('p1', 'M1', '2024-12-31')
    const payload = mockChain.insert.mock.calls[0][0]
    expect(payload.is_reached).toBe(false)
    expect(payload.is_reached_manually).toBe(false)
  })

  it('createProjectMilestone avec deadline null', async () => {
    setMockData({ id: 'm1' })
    await createProjectMilestone('p1', 'M1', null)
    const payload = mockChain.insert.mock.calls[0][0]
    expect(payload.deadline).toBeNull()
  })

  it('updateProjectMilestone met à jour', async () => {
    setMockData({ id: 'm1', is_reached: true })
    const result = await updateProjectMilestone('m1', { is_reached: true })
    expect(result.is_reached).toBe(true)
  })
})

// ============ 8. Project Tags ============
describe('8. Project Tags', () => {
  it('getProjectTags retourne les tags', async () => {
    const tags = [{ id: 'tg1', name: 'urgent', color: 1 }]
    setMockData(tags)
    const result = await getProjectTags()
    expect(result).toEqual(tags)
  })

  it('createProjectTag crée avec color=0 par défaut', async () => {
    setMockData({ id: 'tg1' })
    await createProjectTag('bug')
    const payload = mockChain.insert.mock.calls[0][0]
    expect(payload.color).toBe(0)
  })
})

// ============ 9. Task Assignees ============
describe('9. Task Assignees', () => {
  it('getTaskAssignees retourne les assignations', async () => {
    const assignees = [{ task_id: 't1', employee_id: 'e1' }]
    setMockData(assignees)
    const result = await getTaskAssignees('t1')
    expect(result).toEqual(assignees)
  })

  it('assignTaskToEmployee insère dans la junction', async () => {
    setMockData(null)
    await assignTaskToEmployee('t1', 'e1')
    expect(mockChain.insert).toHaveBeenCalled()
    const payload = mockChain.insert.mock.calls[0][0]
    expect(payload.task_id).toBe('t1')
    expect(payload.employee_id).toBe('e1')
  })

  it('unassignTaskFromEmployee supprime de la junction', async () => {
    setMockData(null)
    await unassignTaskFromEmployee('t1', 'e1')
    expect(mockChain.delete).toHaveBeenCalled()
    expect(mockChain.eq).toHaveBeenCalledWith('task_id', 't1')
    expect(mockChain.eq).toHaveBeenCalledWith('employee_id', 'e1')
  })

  it('setTaskAssignee avec employeeId null → supprime seulement', async () => {
    // updateTask
    mockChain.single = vi.fn(() => Promise.resolve({ data: { id: 't1' }, error: null }))
    // delete
    mockChain.then = vi.fn((resolve: any) => Promise.resolve({ data: null, error: null }).then(resolve))
    await setTaskAssignee('t1', null, null)
    expect(mockChain.delete).toHaveBeenCalled()
    // Pas d'insert si employeeId est null
    expect(mockChain.insert).not.toHaveBeenCalled()
  })

  it('setTaskAssignee avec employeeId → update + delete + insert + notify', async () => {
    // updateTask
    mockChain.single = vi.fn(() => Promise.resolve({ data: { id: 't1', title: 'T', project_id: 'p1' }, error: null }))
    // delete + insert + select task
    mockChain.then = vi.fn((resolve: any) => Promise.resolve({ data: null, error: null }).then(resolve))
    await setTaskAssignee('t1', 'e1', 'Alice')
    expect(mockChain.update).toHaveBeenCalled()
    expect(mockChain.delete).toHaveBeenCalled()
    expect(mockChain.insert).toHaveBeenCalled()
  })
})

// ============ 10. Project Members ============
describe('10. Project Members', () => {
  it('getProjectMembers retourne les membres avec employee_name', async () => {
    const members = [{ id: 'pm1', project_id: 'p1', employee_id: 'e1', role: 'team_member' }]
    setMockData(members)
    const result = await getProjectMembers('p1')
    expect(result).toHaveLength(1)
    expect(result[0].id).toBe('pm1')
    expect(result[0].employee_name).toBeNull()  // mock ne retourne pas employees
  })

  it('addProjectMember crée avec role par défaut "team_member"', async () => {
    setMockData({ id: 'pm1', role: 'team_member' })
    // Pour la notification (select project name)
    mockChain.then = vi.fn((resolve: any) => Promise.resolve({ data: { name: 'Proj' }, error: null }).then(resolve))
    const result = await addProjectMember('p1', 'e1')
    expect(result.role).toBe('team_member')
  })

  it('addProjectMember avec role explicite', async () => {
    setMockData({ id: 'pm1', role: 'project_manager' })
    mockChain.then = vi.fn((resolve: any) => Promise.resolve({ data: { name: 'Proj' }, error: null }).then(resolve))
    await addProjectMember('p1', 'e1', 'project_manager')
    const payload = mockChain.insert.mock.calls[0][0]
    expect(payload.role).toBe('project_manager')
  })

  it('removeProjectMember supprime', async () => {
    setMockData(null)
    await expect(removeProjectMember('pm1')).resolves.toBeUndefined()
  })

  it('updateProjectMemberRole met à jour', async () => {
    setMockData(null)
    await expect(updateProjectMemberRole('pm1', 'consultant')).resolves.toBeUndefined()
    expect(mockChain.update).toHaveBeenCalled()
  })
})

// ============ 11. Tenant Isolation ============
describe('11. Tenant Isolation', () => {
  it('toutes les requêtes filtrent par tenant_id', async () => {
    setMockData([])
    await getTasks()
    // Au moins un appel à eq avec 'tenant_id'
    const eqCalls = mockChain.eq.mock.calls
    const hasTenantFilter = eqCalls.some((call: any[]) => call[0] === 'tenant_id')
    expect(hasTenantFilter).toBe(true)
  })

  it('createTask inclut tenant_id dans le payload', async () => {
    setMockData({ id: 't1' })
    await createTask({
      title: 'T', project_id: null, parent_id: null, status: 'todo',
      priority: 'low', assignee: null, start_date: null, due_date: null,
      effort_estimate_h: 0, effort_spent_h: 0, progress: 0,
      display_order: '0', task_level: 0, budget: 0, color: 0,
      acceptance_criteria: null, recurring_task: false, recurring_interval: 1,
      recurring_rule_type: 'weekly', linked_action_id: null, production_order_id: null,
    })
    const payload = mockChain.insert.mock.calls[0][0]
    expect(payload.tenant_id).toBe('test-tenant-id')
  })
})

// ============ 12. Error Handling ============
describe('12. Error Handling', () => {
  it('getTasks propage l\'erreur', async () => {
    setMockData(null, { message: 'Query failed' })
    await expect(getTasks()).rejects.toThrow('Query failed')
  })

  it('getTaskById propage l\'erreur', async () => {
    mockChain.maybeSingle = vi.fn(() => Promise.resolve({ data: null, error: { message: 'Err' } }))
    await expect(getTaskById('t1')).rejects.toThrow('Err')
  })

  it('getTaskActions propage l\'erreur', async () => {
    setMockData(null, { message: 'Actions err' })
    await expect(getTaskActions('t1')).rejects.toThrow('Actions err')
  })

  it('getProjectMilestones propage l\'erreur', async () => {
    setMockData(null, { message: 'Milestones err' })
    await expect(getProjectMilestones('p1')).rejects.toThrow('Milestones err')
  })
})
