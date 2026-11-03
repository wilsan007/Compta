import { supabase } from '@/lib/supabase'
import { fetchAllRows, getTenantId, ti, tud, type RangeableQuery } from './core'
import { createNotification } from './projectManagementSprint1'
import { fromDbTask, taskStatusFromDb, toDbTaskWrite } from '@/lib/taskStatus'
import type {
  ProjectTask,
  TaskAction,
  TaskActionAttachment,
  TaskDocument,
  TaskComment,
  ProjectTaskDependency,
  ProjectDependency,
  ProjectStage,
  ProjectMilestone,
  ProjectTag,
  ProjectMember,
  ProjectMemberRole,
  TaskCreateInput,
  TaskUpdateInput,
} from '@/types/projectManagement'

// ============ Project Tasks — CRUD ============

export async function getTasks(projectId?: string): Promise<ProjectTask[]> {
  const tid = await getTenantId()
  let q = supabase
    .from('project_tasks')
    .select('*')
    .order('display_order', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  if (projectId) q = q.eq('project_id', projectId)
  const { data, error } = await q
  if (error) throw error
  return ((data || []) as ProjectTask[]).map(fromDbTask)
}

export async function getTaskById(id: string): Promise<ProjectTask | null> {
  const tid = await getTenantId()
  let q = supabase.from('project_tasks').select('*').eq('id', id)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.maybeSingle()
  if (error) throw error
  return data ? fromDbTask(data as ProjectTask) : null
}

export async function createTask(task: TaskCreateInput): Promise<ProjectTask> {
  const tid = await getTenantId()
  const payload = ti(toDbTaskWrite({ ...task, tenant_id: tid }), 'project_tasks', tid)
  const { data, error } = await supabase
    .from('project_tasks')
    .insert(payload)
    .select()
    .single()
  if (error) throw error
  return fromDbTask(data as ProjectTask)
}

export async function updateTask(id: string, updates: TaskUpdateInput): Promise<ProjectTask> {
  const tid = await getTenantId()
  const { data, error } = await tud(
    supabase.from('project_tasks').update(toDbTaskWrite(updates)),
    'project_tasks',
    tid
  )
    .eq('id', id)
    .eq('tenant_id', tid)
    .select()
    .single()
  if (error) throw error
  return fromDbTask(data as ProjectTask)
}

export async function deleteTask(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(
    supabase.from('project_tasks').delete(),
    'project_tasks',
    tid
  ).eq('id', id).eq('tenant_id', tid)
  if (error) throw error
}

export async function duplicateTask(id: string): Promise<ProjectTask> {
  const existing = await getTaskById(id)
  if (!existing) throw new Error('Task not found')
  const { id: _id, tenant_id: _tid, created_at: _ca, updated_at: _ua, is_closed: _ic, subtask_count: _sc, subtask_done_count: _sdc, assignees: _a, tags: _tg, actions: _act, dependencies: _dep, ...rest } = existing
  const copy: TaskCreateInput = {
    ...rest,
    title: `${existing.title} (copy)`,
    display_order: existing.display_order,
  }
  return createTask(copy)
}

export async function createSubTask(
  parentId: string,
  title: string,
  projectId?: string | null,
  taskLevel?: number,
  displayOrder?: string
): Promise<ProjectTask> {
  const parent = await getTaskById(parentId)
  if (!parent) throw new Error('Parent task not found')
  return createTask({
    title,
    project_id: projectId ?? parent.project_id,
    parent_id: parentId,
    status: 'todo',
    priority: 'medium',
    assignee: null,
    start_date: null,
    due_date: null,
    effort_estimate_h: 0,
    effort_spent_h: 0,
    progress: 0,
    display_order: displayOrder || '0',
    task_level: taskLevel ?? (parent.task_level + 1),
    budget: 0,
    color: 0,
    acceptance_criteria: null,
    recurring_task: false,
    recurring_interval: 1,
    recurring_rule_type: 'weekly',
    linked_action_id: null,
  })
}

// ============ Task Actions ============

export async function getTaskActions(taskId: string): Promise<TaskAction[]> {
  const tid = await getTenantId()
  let q = supabase
    .from('task_actions')
    .select('*')
    .eq('task_id', taskId)
    .order('created_at', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return (data || []) as TaskAction[]
}

// Une seule lecture pour toutes les lignes du tableau (la grille d'actions n'a pas
// à interroger la base une fois par tâche). Les identifiants sont envoyés par
// paquets pour borner la longueur de l'URL, et chaque paquet est paginé : PostgREST
// tronque à 1000 lignes. Le tri (date, puis identifiant) est total, sinon une page
// peut répéter ou perdre une ligne.
const ACTIONS_TASK_CHUNK = 100

export async function getActionsForTasks(taskIds: string[]): Promise<TaskAction[]> {
  if (taskIds.length === 0) return []
  const tid = await getTenantId()
  const chunks: string[][] = []
  for (let i = 0; i < taskIds.length; i += ACTIONS_TASK_CHUNK) {
    chunks.push(taskIds.slice(i, i + ACTIONS_TASK_CHUNK))
  }
  const pages = await Promise.all(
    chunks.map((ids) =>
      fetchAllRows<TaskAction>(
        () => {
          let q = supabase
            .from('task_actions')
            .select('*')
            .in('task_id', ids)
            .order('created_at', { ascending: true })
            .order('id', { ascending: true })
          if (tid) q = q.eq('tenant_id', tid)
          return q as unknown as RangeableQuery<TaskAction>
        },
        { label: 'getActionsForTasks' }
      )
    )
  )
  return pages.flat()
}

export async function addActionColumn(
  taskId: string,
  title: string,
  weightPercentage?: number
): Promise<TaskAction> {
  const tid = await getTenantId()
  const payload = ti(
    { task_id: taskId, title, weight_percentage: weightPercentage || 0, is_done: false, tenant_id: tid },
    'task_actions',
    tid
  )
  const { data, error } = await supabase
    .from('task_actions')
    .insert(payload)
    .select()
    .single()
  if (error) throw error
  return data as TaskAction
}

export async function addDetailedAction(
  taskId: string,
  title: string,
  weightPercentage: number,
  dueDate: string | null,
  notes: string | null
): Promise<TaskAction> {
  const tid = await getTenantId()
  const payload = ti(
    {
      task_id: taskId,
      title,
      weight_percentage: weightPercentage,
      is_done: false,
      due_date: dueDate,
      notes,
      tenant_id: tid,
    },
    'task_actions',
    tid
  )
  const { data, error } = await supabase
    .from('task_actions')
    .insert(payload)
    .select()
    .single()
  if (error) throw error
  return data as TaskAction
}

export async function toggleAction(actionId: string, isDone: boolean): Promise<{ action: TaskAction; progress: number }> {
  const tid = await getTenantId()
  const { data, error } = await tud(
    supabase.from('task_actions').update({ is_done: isDone }),
    'task_actions',
    tid
  )
    .eq('id', actionId)
    .eq('tenant_id', tid)
    .select()
    .single()
  if (error) throw error
  const action = data as TaskAction
  return { action, progress: await getTaskProgress(action.task_id) }
}

// La progression d'une tâche est calculée par la BASE (800 : actions pondérées,
// sous-tâches, remontée à la mère et au projet). Le client la relit, il ne la
// recalcule plus — l'ancien calcul client ignorait les sous-tâches et réécrivait
// la valeur de la base.
export async function getTaskProgress(taskId: string): Promise<number> {
  const tid = await getTenantId()
  let q = supabase.from('project_tasks').select('progress').eq('id', taskId)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.maybeSingle()
  if (error) throw error
  return (data as { progress: number } | null)?.progress ?? 0
}

export async function updateActionProgress(actionId: string, progress: number): Promise<TaskAction> {
  const tid = await getTenantId()
  const { data, error } = await tud(
    supabase.from('task_actions').update({ progress }),
    'task_actions',
    tid
  )
    .eq('id', actionId)
    .eq('tenant_id', tid)
    .select()
    .single()
  if (error) throw error
  return data as TaskAction
}

export async function updateActionWeight(actionId: string, weight: number): Promise<TaskAction> {
  const tid = await getTenantId()
  const { data, error } = await tud(
    supabase.from('task_actions').update({ weight_percentage: weight }),
    'task_actions',
    tid
  )
    .eq('id', actionId)
    .eq('tenant_id', tid)
    .select()
    .single()
  if (error) throw error
  return data as TaskAction
}

export async function deleteAction(actionId: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(
    supabase.from('task_actions').delete(),
    'task_actions',
    tid
  ).eq('id', actionId).eq('tenant_id', tid)
  if (error) throw error
}

// ============ Task Action Attachments ============

export async function getTaskActionAttachments(taskActionId: string): Promise<TaskActionAttachment[]> {
  const tid = await getTenantId()
  let q = supabase
    .from('task_action_attachments')
    .select('*')
    .eq('task_action_id', taskActionId)
    .order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return (data || []) as TaskActionAttachment[]
}

// ============ Task Documents ============

export async function getTaskDocuments(taskId: string): Promise<TaskDocument[]> {
  const tid = await getTenantId()
  let q = supabase
    .from('task_documents')
    .select('*')
    .eq('task_id', taskId)
    .order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return (data || []) as TaskDocument[]
}

export async function uploadTaskDocument(
  taskId: string,
  file: File,
  projectId?: string | null
): Promise<TaskDocument> {
  const tid = await getTenantId()
  if (!tid) throw new Error('Aucune société active')
  // Le compartiment `task-attachments` visé jusqu'ici n'existe pas : aucun
  // document ne pouvait être déposé. `project-docs` exige que le chemin commence
  // par l'identifiant de la société (politiques de stockage).
  const filePath = projectFilePath(tid, 'taches', taskId, file.name)
  const { error: uploadError } = await supabase.storage
    .from(PROJECT_BUCKET)
    .upload(filePath, file)
  if (uploadError) throw uploadError

  const payload = ti(
    {
      task_id: taskId,
      project_id: projectId || null,
      file_name: file.name,
      file_path: filePath,
      file_size: file.size,
      mime_type: file.type,
      tenant_id: tid,
    },
    'task_documents',
    tid
  )
  const { data, error } = await supabase
    .from('task_documents')
    .insert(payload)
    .select()
    .single()
  if (error) throw error
  return data as TaskDocument
}

// ============ Fichiers du tableau (documents, preuves d'action) ============

const PROJECT_BUCKET = 'project-docs'

function projectFilePath(tenantId: string, kind: 'taches' | 'actions', ownerId: string, name: string): string {
  const safe = name.normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^A-Za-z0-9._-]+/g, '_')
  return `${tenantId}/${kind}/${ownerId}/${Date.now()}-${safe}`
}

export async function downloadProjectFile(path: string): Promise<Blob> {
  const { data, error } = await supabase.storage.from(PROJECT_BUCKET).download(path)
  if (error) throw error
  return data
}

// Document de PREUVE d'une action : sans lui, la base refuse de la cocher (803).
export async function uploadActionProof(action: TaskAction, file: File): Promise<TaskActionAttachment> {
  const tid = await getTenantId()
  if (!tid) throw new Error('Aucune société active')
  const filePath = projectFilePath(tid, 'actions', action.id, file.name)
  const { error: uploadError } = await supabase.storage.from(PROJECT_BUCKET).upload(filePath, file)
  if (uploadError) throw uploadError
  const { data: auth } = await supabase.auth.getUser()
  const payload = ti(
    {
      task_action_id: action.id,
      task_id: action.task_id,
      file_name: file.name,
      file_path: filePath,
      file_size: file.size,
      mime_type: file.type,
      uploader_id: auth.user?.id ?? null,
      tenant_id: tid,
    },
    'task_action_attachments',
    tid
  )
  const { data, error } = await supabase.from('task_action_attachments').insert(payload).select().single()
  if (error) throw error
  return data as TaskActionAttachment
}

export interface TaskTableCounts {
  documents: Map<string, number> // par tâche
  comments: Map<string, number> // par tâche
  proofs: Map<string, number> // par action
}

// Les compteurs du tableau en TROIS lectures pour toutes les lignes (wadashaqayn
// faisait une requête par action et par ligne). Paquets d'identifiants, pagination.
export async function getTaskTableCounts(taskIds: string[]): Promise<TaskTableCounts> {
  const counts: TaskTableCounts = { documents: new Map(), comments: new Map(), proofs: new Map() }
  if (taskIds.length === 0) return counts
  const tid = await getTenantId()
  const chunks: string[][] = []
  for (let i = 0; i < taskIds.length; i += ACTIONS_TASK_CHUNK) chunks.push(taskIds.slice(i, i + ACTIONS_TASK_CHUNK))
  const read = (table: string, column: string) =>
    Promise.all(
      chunks.map((ids) =>
        fetchAllRows<Record<string, string>>(
          () => {
            let q = supabase.from(table).select(`id, ${column}`).in('task_id', ids).order('id', { ascending: true })
            if (tid) q = q.eq('tenant_id', tid)
            return q as unknown as RangeableQuery<Record<string, string>>
          },
          { label: `getTaskTableCounts:${table}` }
        )
      )
    ).then((pages) => pages.flat())
  const [docs, comments, proofs] = await Promise.all([
    read('task_documents', 'task_id'),
    read('task_comments', 'task_id'),
    read('task_action_attachments', 'task_action_id'),
  ])
  const bump = (m: Map<string, number>, k: string) => m.set(k, (m.get(k) || 0) + 1)
  docs.forEach((r) => bump(counts.documents, r.task_id))
  comments.forEach((r) => bump(counts.comments, r.task_id))
  proofs.forEach((r) => bump(counts.proofs, r.task_action_id))
  return counts
}

// Une tâche neuve avec toutes ses valeurs par défaut (le type d'écriture exige
// chaque colonne).
export function newTaskInput(partial: Partial<TaskCreateInput> & { title: string }): TaskCreateInput {
  return {
    project_id: null,
    parent_id: null,
    status: 'todo',
    priority: 'medium',
    assignee: null,
    assignee_id: null,
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
    ...partial,
  }
}

// ============ Task Comments ============

export async function getTaskComments(taskId: string): Promise<TaskComment[]> {
  const tid = await getTenantId()
  let q = supabase
    .from('task_comments')
    .select('*')
    .eq('task_id', taskId)
    .order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return (data || []) as TaskComment[]
}

export async function addTaskComment(
  taskId: string,
  content: string,
  commentType?: string
): Promise<TaskComment> {
  const tid = await getTenantId()
  const payload = ti(
    { task_id: taskId, content, comment_type: commentType || 'general', tenant_id: tid },
    'task_comments',
    tid
  )
  const { data, error } = await supabase
    .from('task_comments')
    .insert(payload)
    .select()
    .single()
  if (error) throw error
  return data as TaskComment
}

// ============ Task Dependencies ============

export async function getTaskDependencies(taskId: string): Promise<ProjectTaskDependency[]> {
  const tid = await getTenantId()
  let q = supabase
    .from('project_task_dependencies')
    .select('*')
    .eq('task_id', taskId)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return (data || []) as ProjectTaskDependency[]
}

export async function createTaskDependency(
  taskId: string,
  dependsOnTaskId: string,
  dependencyType?: string,
  lagDays?: number
): Promise<ProjectTaskDependency> {
  const tid = await getTenantId()
  const payload = ti(
    {
      task_id: taskId,
      depends_on_task_id: dependsOnTaskId,
      dependency_type: dependencyType || 'finish-to-start',
      lag_days: lagDays || 0,
      tenant_id: tid,
    },
    'project_task_dependencies',
    tid
  )
  const { data, error } = await supabase
    .from('project_task_dependencies')
    .insert(payload)
    .select()
    .single()
  if (error) throw error
  return data as ProjectTaskDependency
}

// Tous les liens qui touchent les tâches affichées, en une lecture (paquets
// d'identifiants pour borner l'URL, pagination pour les 1000 lignes de PostgREST).
export async function getDependenciesForTasks(taskIds: string[]): Promise<ProjectTaskDependency[]> {
  if (taskIds.length === 0) return []
  const tid = await getTenantId()
  const chunks: string[][] = []
  for (let i = 0; i < taskIds.length; i += ACTIONS_TASK_CHUNK) chunks.push(taskIds.slice(i, i + ACTIONS_TASK_CHUNK))
  const pages = await Promise.all(
    chunks.map((ids) =>
      fetchAllRows<ProjectTaskDependency>(
        () => {
          let q = supabase
            .from('project_task_dependencies')
            .select('*')
            .in('task_id', ids)
            .order('created_at', { ascending: true })
            .order('id', { ascending: true })
          if (tid) q = q.eq('tenant_id', tid)
          return q as unknown as RangeableQuery<ProjectTaskDependency>
        },
        { label: 'getDependenciesForTasks' }
      )
    )
  )
  return pages.flat()
}

export async function getProjectDependencies(): Promise<ProjectDependency[]> {
  const tid = await getTenantId()
  return fetchAllRows<ProjectDependency>(
    () => {
      let q = supabase
        .from('project_dependencies')
        .select('*')
        .order('created_at', { ascending: true })
        .order('id', { ascending: true })
      if (tid) q = q.eq('tenant_id', tid)
      return q as unknown as RangeableQuery<ProjectDependency>
    },
    { label: 'getProjectDependencies' }
  )
}

export async function createProjectDependency(
  projectId: string,
  dependsOnProjectId: string,
  lagDays = 0
): Promise<ProjectDependency> {
  const tid = await getTenantId()
  const payload = ti(
    { project_id: projectId, depends_on_project_id: dependsOnProjectId, lag_days: lagDays, tenant_id: tid },
    'project_dependencies',
    tid
  )
  const { data, error } = await supabase.from('project_dependencies').insert(payload).select().single()
  if (error) throw error
  return data as ProjectDependency
}

export async function deleteProjectDependency(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(
    supabase.from('project_dependencies').delete(),
    'project_dependencies',
    tid
  ).eq('id', id).eq('tenant_id', tid)
  if (error) throw error
}

export async function deleteTaskDependency(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(
    supabase.from('project_task_dependencies').delete(),
    'project_task_dependencies',
    tid
  ).eq('id', id).eq('tenant_id', tid)
  if (error) throw error
}

// ============ Project Stages ============

export async function getProjectStages(): Promise<ProjectStage[]> {
  const tid = await getTenantId()
  let q = supabase
    .from('project_stages')
    .select('*')
    .order('sequence', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return (data || []) as ProjectStage[]
}

export async function createProjectStage(
  name: string,
  sequence: number,
  fold?: boolean
): Promise<ProjectStage> {
  const tid = await getTenantId()
  const payload = ti(
    { name, sequence, fold: fold || false, case_default: false, tenant_id: tid },
    'project_stages',
    tid
  )
  const { data, error } = await supabase
    .from('project_stages')
    .insert(payload)
    .select()
    .single()
  if (error) throw error
  return data as ProjectStage
}

// ============ Project Milestones ============

export async function getProjectMilestones(projectId: string): Promise<ProjectMilestone[]> {
  const tid = await getTenantId()
  let q = supabase
    .from('project_milestones')
    .select('*')
    .eq('project_id', projectId)
    .order('deadline', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return (data || []) as ProjectMilestone[]
}

export async function createProjectMilestone(
  projectId: string,
  name: string,
  deadline: string | null
): Promise<ProjectMilestone> {
  const tid = await getTenantId()
  const payload = ti(
    { project_id: projectId, name, deadline, is_reached: false, is_reached_manually: false, tenant_id: tid },
    'project_milestones',
    tid
  )
  const { data, error } = await supabase
    .from('project_milestones')
    .insert(payload)
    .select()
    .single()
  if (error) throw error
  return data as ProjectMilestone
}

export async function updateProjectMilestone(
  id: string,
  updates: Partial<ProjectMilestone>
): Promise<ProjectMilestone> {
  const tid = await getTenantId()
  const { data, error } = await tud(
    supabase.from('project_milestones').update(updates),
    'project_milestones',
    tid
  )
    .eq('id', id)
    .eq('tenant_id', tid)
    .select()
    .single()
  if (error) throw error
  return data as ProjectMilestone
}

// ============ Project Tags ============

export async function getProjectTags(): Promise<ProjectTag[]> {
  const tid = await getTenantId()
  let q = supabase
    .from('project_tags')
    .select('*')
    .order('name', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return (data || []) as ProjectTag[]
}

export async function createProjectTag(name: string, color?: number): Promise<ProjectTag> {
  const tid = await getTenantId()
  const payload = ti({ name, color: color || 0, tenant_id: tid }, 'project_tags', tid)
  const { data, error } = await supabase
    .from('project_tags')
    .insert(payload)
    .select()
    .single()
  if (error) throw error
  return data as ProjectTag
}

// ============ Task Assignees ============

// `project_task_assignees` porte `tenant_id` depuis la 805. Avant elle, la colonne
// n'existait pas : le filtre applicatif renvoyait 400/42703 (LOT7-04) et changer le
// responsable d'une tâche échouait. Lectures et écritures la filtrent de nouveau
// par société ; la RLS (société + `can_perform`) et les clés composites tiennent
// l'isolation en base.
export async function getTaskAssignees(taskId: string): Promise<{ task_id: string; employee_id: string }[]> {
  const tid = await getTenantId()
  let q = supabase
    .from('project_task_assignees')
    .select('task_id, employee_id')
    .eq('task_id', taskId)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data || []
}

export async function assignTaskToEmployee(taskId: string, employeeId: string): Promise<void> {
  const tid = await getTenantId()
  const payload = ti({ task_id: taskId, employee_id: employeeId, tenant_id: tid }, 'project_task_assignees', tid)
  const { error } = await supabase
    .from('project_task_assignees')
    .insert(payload)
  if (error) throw error
}

export async function unassignTaskFromEmployee(taskId: string, employeeId: string): Promise<void> {
  const tid = await getTenantId()
  let q = supabase
    .from('project_task_assignees')
    .delete()
    .eq('task_id', taskId)
    .eq('employee_id', employeeId)
  if (tid) q = q.eq('tenant_id', tid)
  const { error } = await q
  if (error) throw error
}

export async function setTaskAssignee(taskId: string, employeeId: string | null, employeeName: string | null): Promise<void> {
  const tid = await getTenantId()

  // 1. Update denormalized assignee field on project_tasks
  await updateTask(taskId, { assignee: employeeName })

  // 2. Clear existing junction entries for this task
  let delQ = supabase.from('project_task_assignees').delete().eq('task_id', taskId)
  if (tid) delQ = delQ.eq('tenant_id', tid)
  const { error: delError } = await delQ
  if (delError) throw delError

  // 3. Insert new junction entry if an employee is assigned
  if (employeeId) {
    const payload = ti({ task_id: taskId, employee_id: employeeId, tenant_id: tid }, 'project_task_assignees', tid)
    const { error: insError } = await supabase.from('project_task_assignees').insert(payload)
    if (insError) throw insError

    // 4. Notify the assigned employee
    try {
      // Fetch task info for the notification message
      const { data: taskData, error } = await supabase
        .from('project_tasks')
        .select('title, project_id')
        .eq('id', taskId)
        .single()
      if (error) throw error
      if (taskData) {
        const locale = localStorage.getItem('i18nextLng')?.split('-')[0] || 'fr'
        const titleMsg: Record<string, string> = {
          fr: `Nouvelle tâche assignée : ${taskData.title}`,
          en: `New task assigned: ${taskData.title}`,
          ar: `مهمة جديدة مسندة: ${taskData.title}`,
        }
        const bodyMsg: Record<string, string> = {
          fr: `Vous avez été assigné à la tâche « ${taskData.title} ».<br><br>Cliquez ci-dessous pour y accéder directement.`,
          en: `You have been assigned to the task "${taskData.title}".<br><br>Click below to access it directly.`,
          ar: `تم تكليفك بالمهمة « ${taskData.title} ».<br><br>انقر أدناه للوصول إليها مباشرة.`,
        }
        await createNotification(
          employeeId,
          'task_assigned',
          titleMsg[locale] || titleMsg.en,
          bodyMsg[locale] || bodyMsg.en,
          taskId,
          taskData.project_id || null,
          `/projects/${taskData.project_id || ''}?task=${taskId}`
        )
      }
    } catch (err) {
      console.error("catch:", err)
      // Notification failure should not block assignment
    }
  }
}

// ============ Batch / Aggregation ============

export async function getSubtaskCount(parentId: string): Promise<{ total: number; done: number }> {
  const tid = await getTenantId()
  let q = supabase
    .from('project_tasks')
    .select('status')
    .eq('parent_id', parentId)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  const all = data || []
  const done = all.filter((t: { status: string }) => ['done', 'canceled'].includes(taskStatusFromDb(t.status))).length
  return { total: all.length, done }
}

// ============ Project Members ============

export async function getProjectMembers(projectId: string): Promise<ProjectMember[]> {
  const tid = await getTenantId()
  let q = supabase
    .from('project_members')
    // Clé composite depuis la 237 (ISO-02) : `employee_id` seul ne désigne plus la
    // relation, le nom de la contrainte si (LOT7-04, mesuré sur PostgREST v16.3).
    .select('*, employees:employees!project_members_employee_id_fkey(name)')
    .eq('project_id', projectId)
    .order('created_at', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return (data || []).map((row: any) => ({
    ...(row || {}),
    employee_name: row?.employees?.name || null,
  })) as ProjectMember[]
}

export async function addProjectMember(projectId: string, employeeId: string, role: ProjectMemberRole = 'team_member'): Promise<ProjectMember> {
  const tid = await getTenantId()
  const payload = ti({ project_id: projectId, employee_id: employeeId, role, tenant_id: tid }, 'project_members', tid)
  const { data, error } = await supabase
    .from('project_members')
    .insert(payload)
    .select()
    .single()
  if (error) throw error

  // Notify the added member
  try {
    const { data: projectData, error } = await supabase
      .from('projects')
      .select('name')
      .eq('id', projectId)
      .single()
    if (error) throw error
    if (projectData) {
      const locale = localStorage.getItem('i18nextLng')?.split('-')[0] || 'fr'
      const titleMsg: Record<string, string> = {
        fr: `Bienvenue dans le projet ${projectData.name} !`,
        en: `Welcome to project ${projectData.name}!`,
        ar: `مرحباً بك في مشروع ${projectData.name}!`,
      }
      const roleLabels: Record<string, Record<string, string>> = {
        project_director: { fr: 'directeur de projet', en: 'project director', ar: 'مدير مشروع' },
        project_manager: { fr: 'chef de projet', en: 'project manager', ar: 'مدير مشروع' },
        team_member: { fr: "membre d'\u00e9quipe", en: 'team member', ar: '\u0639\u0636\u0648 \u0641\u0631\u064a\u0642' },
        consultant: { fr: 'consultant', en: 'consultant', ar: 'مستشار' },
        guest: { fr: 'invité', en: 'guest', ar: 'ضيف' },
      }
      const roleLabel = roleLabels[role]?.[locale] || role
      const bodyMsg: Record<string, string> = {
        fr: `Vous avez rejoint le projet <strong>${projectData.name}</strong> en tant que ${roleLabel}.<br><br>Vous pouvez désormais consulter les tâches et suivre l'avancement.`,
        en: `You have joined the project <strong>${projectData.name}</strong> as ${roleLabel}.<br><br>You can now view tasks and track progress.`,
        ar: `انضممت إلى مشروع <strong>${projectData.name}</strong> بصفتك ${roleLabel}.<br><br>يمكنك الآن عرض المهام ومتابعة التقدم.`,
      }
      await createNotification(
        employeeId,
        'project_member_added',
        titleMsg[locale] || titleMsg.en,
        bodyMsg[locale] || bodyMsg.en,
        null,
        projectId,
        `/projects/${projectId}`
      )
    }
  } catch (err) {
    console.error("catch:", err)
    // Notification failure should not block member addition
  }

  return data as ProjectMember
}

export async function removeProjectMember(memberId: string): Promise<void> {
  const tid = await getTenantId()
  let q = supabase
    .from('project_members')
    .delete()
    .eq('id', memberId)
  if (tid) q = q.eq('tenant_id', tid)
  const { error } = await q
  if (error) throw error
}

export async function updateProjectMemberRole(memberId: string, role: ProjectMemberRole): Promise<void> {
  const tid = await getTenantId()
  let q = supabase
    .from('project_members')
    .update({ role, updated_at: new Date().toISOString() })
    .eq('id', memberId)
  if (tid) q = q.eq('tenant_id', tid)
  const { error } = await q
  if (error) throw error
}
