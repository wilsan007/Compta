// Sprint 1 queries: Time Tracking, Watchers, Activity Log, Templates, Notifications
import { supabase } from '@/lib/supabase'
import { getTenantId, ti, tud } from '@/lib/queries/core'
import { shouldSendEmail } from '@/types/projectManagement'
import type {
  TimeEntry,
  TimeEntryCreateInput,
  TaskWatcher,
  ActivityLogEntry,
  ActivityActionType,
  TaskTemplate,
  TaskTemplateCreateInput,
  ProjectNotification,
  WorkloadEntry,
} from '@/types/projectManagement'
import type { ProjectTask } from '@/types/projectManagement'

// ============ Time Entries ============

export async function getTimeEntries(taskId?: string, employeeId?: string): Promise<TimeEntry[]> {
  const tid = await getTenantId()
  let q = supabase.from('project_time_entries').select('*')
  if (tid) q = q.eq('tenant_id', tid)
  if (taskId) q = q.eq('task_id', taskId)
  if (employeeId) q = q.eq('employee_id', employeeId)
  q = q.order('start_time', { ascending: false })
  const { data, error } = await q
  if (error) throw error
  return (data || []) as TimeEntry[]
}

export async function getRunningTimer(employeeId: string): Promise<TimeEntry | null> {
  const tid = await getTenantId()
  let q = supabase
    .from('project_time_entries')
    .select('*')
    .eq('employee_id', employeeId)
    .is('end_time', null)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.single()
  if (error && error.code !== 'PGRST116') throw error
  return (data as TimeEntry) || null
}

export async function startTimeTimer(input: TimeEntryCreateInput): Promise<TimeEntry> {
  const tid = await getTenantId()
  const payload = ti(
    {
      ...input,
      start_time: new Date().toISOString(),
      end_time: null,
      duration_seconds: 0,
      tenant_id: tid,
    },
    'project_time_entries',
    tid
  )
  const { data, error } = await supabase.from('project_time_entries').insert(payload).select().single()
  if (error) throw error
  return data as TimeEntry
}

export async function stopTimeTimer(entryId: string): Promise<TimeEntry> {
  const tid = await getTenantId()
  const now = new Date()
  const { data: entry, error: entryError } = await supabase
    .from('project_time_entries')
    .select('start_time')
    .eq('id', entryId)
    .single()
  if (entryError) throw entryError
  if (!entry) throw new Error('Time entry not found')
  const duration = Math.floor((now.getTime() - new Date(entry.start_time).getTime()) / 1000)
  const { data, error } = await tud(
    supabase
      .from('project_time_entries')
      .update({ end_time: now.toISOString(), duration_seconds: duration }),
    'project_time_entries',
    tid
  )
    .eq('id', entryId)
    .eq('tenant_id', tid)
    .select()
    .single()
  if (error) throw error

  // Update task effort_spent_h if task_id is set
  const updated = data as TimeEntry
  if (updated.task_id) {
    await recalculateTaskTimeSpent(updated.task_id)
  }
  return updated
}

export async function addManualTimeEntry(input: TimeEntryCreateInput): Promise<TimeEntry> {
  const tid = await getTenantId()
  const start = input.start_time ? new Date(input.start_time) : new Date()
  const end = input.end_time ? new Date(input.end_time) : new Date()
  const duration = input.duration_seconds || Math.floor((end.getTime() - start.getTime()) / 1000)
  const payload = ti(
    {
      ...input,
      start_time: start.toISOString(),
      end_time: end.toISOString(),
      duration_seconds: duration,
      tenant_id: tid,
    },
    'project_time_entries',
    tid
  )
  const { data, error } = await supabase.from('project_time_entries').insert(payload).select().single()
  if (error) throw error
  const entry = data as TimeEntry
  if (entry.task_id) {
    await recalculateTaskTimeSpent(entry.task_id)
  }
  return entry
}

export async function updateTimeEntry(id: string, updates: Partial<TimeEntryCreateInput>): Promise<TimeEntry> {
  const tid = await getTenantId()
  const { data, error } = await tud(
    supabase.from('project_time_entries').update(updates),
    'project_time_entries',
    tid
  )
    .eq('id', id)
    .eq('tenant_id', tid)
    .select()
    .single()
  if (error) throw error
  return data as TimeEntry
}

export async function deleteTimeEntry(id: string): Promise<void> {
  const tid = await getTenantId()
  const { data: entry, error: entryError } = await supabase.from('project_time_entries').select('task_id').eq('id', id).single()
  if (entryError) throw entryError
  const { error } = await tud(
    supabase.from('project_time_entries').delete(),
    'project_time_entries',
    tid
  ).eq('id', id).eq('tenant_id', tid)
  if (error) throw error
  if (entry?.task_id) {
    await recalculateTaskTimeSpent(entry.task_id)
  }
}

async function recalculateTaskTimeSpent(taskId: string): Promise<void> {
  const tid = await getTenantId()
  let q = supabase.from('project_time_entries').select('duration_seconds').eq('task_id', taskId)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) { console.error('recalculateTaskTimeSpent:', error); return }
  const totalSeconds = (data || []).reduce((sum: number, e: any) => sum + (e.duration_seconds || 0), 0)
  const totalHours = Math.round((totalSeconds / 3600) * 10) / 10
  await updateTaskEffortSpent(taskId, totalHours)
}

async function updateTaskEffortSpent(taskId: string, hours: number): Promise<void> {
  const tid = await getTenantId()
  await tud(
    supabase.from('project_tasks').update({ effort_spent_h: hours }),
    'project_tasks',
    tid
  ).eq('id', taskId).eq('tenant_id', tid)
}

// ============ Watchers ============

export async function getTaskWatchers(taskId: string): Promise<TaskWatcher[]> {
  const tid = await getTenantId()
  let q = supabase
    .from('project_task_watchers')
    .select(`
      id, tenant_id, task_id, employee_id, created_at,
      employees!inner(name)
    `)
    .eq('task_id', taskId)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return (data || []).map((w: any) => ({
    id: w.id,
    tenant_id: w.tenant_id,
    task_id: w.task_id,
    employee_id: w.employee_id,
    employee_name: w.employees?.name,
    created_at: w.created_at,
  })) as TaskWatcher[]
}

export async function addWatcher(taskId: string, employeeId: string): Promise<void> {
  const tid = await getTenantId()
  const payload = ti({ task_id: taskId, employee_id: employeeId, tenant_id: tid }, 'project_task_watchers', tid)
  const { error } = await supabase.from('project_task_watchers').insert(payload)
  if (error) throw error
}

export async function removeWatcher(taskId: string, employeeId: string): Promise<void> {
  const tid = await getTenantId()
  let q = supabase
    .from('project_task_watchers')
    .delete()
    .eq('task_id', taskId)
    .eq('employee_id', employeeId)
  if (tid) q = q.eq('tenant_id', tid)
  const { error } = await q
  if (error) throw error
}

// ============ Activity Log ============

async function getCurrentUserInfo(): Promise<{ id: string | null; name: string | null }> {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return { id: null, name: null }
  const tid = await getTenantId()
  let q = supabase
    .from('tenant_users')
    .select('id, name')
    .eq('auth_id', session.user.id)
    .eq('status', 'active')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.single()
  if (error || !data) return { id: session.user.id, name: session.user.email || null }
  return { id: data.id, name: data.name }
}

export async function getActivityLog(
  taskId?: string,
  projectId?: string,
  limit: number = 50
): Promise<ActivityLogEntry[]> {
  const tid = await getTenantId()
  let q = supabase.from('project_activity_log').select(
    '*, task:project_tasks(title)'
  )
  if (tid) q = q.eq('tenant_id', tid)
  if (taskId) q = q.eq('task_id', taskId)
  if (projectId) q = q.eq('project_id', projectId)
  q = q.order('created_at', { ascending: false }).limit(limit)
  const { data, error } = await q
  if (error) throw error
  return (data || []).map((row: any) => ({
    ...(row || {}),
    task_title: row?.task?.title ?? null,
  })) as ActivityLogEntry[]
}

export async function logActivity(
  taskId: string,
  actionType: ActivityActionType,
  description: string,
  oldValue?: Record<string, unknown> | null,
  newValue?: Record<string, unknown> | null
): Promise<void> {
  const tid = await getTenantId()
  const userInfo = await getCurrentUserInfo()
  const payload = ti(
    {
      task_id: taskId,
      user_id: userInfo.id,
      user_name: userInfo.name,
      action_type: actionType,
      description,
      old_value: oldValue,
      new_value: newValue,
      tenant_id: tid,
    },
    'project_activity_log',
    tid
  )
  const { error } = await supabase.from('project_activity_log').insert(payload)
  if (error) throw error
}

// ============ Task Templates ============

export async function getTaskTemplates(): Promise<TaskTemplate[]> {
  const tid = await getTenantId()
  let q = supabase.from('project_task_templates').select('*').order('name', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return (data || []) as TaskTemplate[]
}

export async function createTaskTemplate(input: TaskTemplateCreateInput): Promise<TaskTemplate> {
  const tid = await getTenantId()
  const payload = ti({ ...input, tenant_id: tid }, 'project_task_templates', tid)
  const { data, error } = await supabase
    .from('project_task_templates')
    .insert(payload)
    .select()
    .single()
  if (error) throw error
  return data as TaskTemplate
}

export async function deleteTaskTemplate(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(
    supabase.from('project_task_templates').delete(),
    'project_task_templates',
    tid
  ).eq('id', id).eq('tenant_id', tid)
  if (error) throw error
}

export async function applyTaskTemplate(
  templateId: string,
  projectId?: string | null
): Promise<ProjectTask> {
  const tid = await getTenantId()
  let q = supabase.from('project_task_templates').select('*').eq('id', templateId)
  if (tid) q = q.eq('tenant_id', tid)
  const { data: template, error: tErr } = await q.single()
  if (tErr) throw tErr
  const tpl = template as TaskTemplate

  const taskPayload = ti(
    {
      title: tpl.name,
      description: tpl.description,
      project_id: projectId ?? null,
      status: tpl.default_status,
      priority: tpl.default_priority,
      assignee: null,
      start_date: null,
      due_date: null,
      effort_estimate_h: tpl.default_effort_estimate,
      effort_spent_h: 0,
      progress: 0,
      display_order: '0',
      task_level: 0,
      budget: tpl.default_budget,
      color: 0,
      acceptance_criteria: null,
      recurring_task: false,
      recurring_interval: 1,
      recurring_rule_type: 'weekly',
      linked_action_id: null,
      production_order_id: null,
      tenant_id: tid,
    },
    'project_tasks',
    tid
  )
  const { data: task, error: taskErr } = await supabase
    .from('project_tasks')
    .insert(taskPayload)
    .select()
    .single()
  if (taskErr) throw taskErr
  const created = task as ProjectTask

  // Create checklist items
  if (tpl.checklist_template && Array.isArray(tpl.checklist_template)) {
    for (const item of tpl.checklist_template) {
      const actionPayload = ti(
        {
          task_id: created.id,
          title: item.title,
          weight_percentage: item.weight_percentage || 0,
          is_done: false,
        },
        'task_actions',
        tid
      )
      await supabase.from('task_actions').insert(actionPayload)
    }
  }

  // Create subtasks
  if (tpl.subtasks_template && Array.isArray(tpl.subtasks_template)) {
    for (const sub of tpl.subtasks_template) {
      const subPayload = ti(
        {
          title: sub.title,
          project_id: projectId ?? created.project_id,
          parent_id: created.id,
          status: 'todo',
          priority: 'medium',
          assignee: null,
          start_date: null,
          due_date: null,
          effort_estimate_h: 0,
          effort_spent_h: 0,
          progress: 0,
          display_order: '0',
          task_level: 1,
          budget: 0,
          color: 0,
          acceptance_criteria: null,
          recurring_task: false,
          recurring_interval: 1,
          recurring_rule_type: 'weekly',
          linked_action_id: null,
          production_order_id: null,
          tenant_id: tid,
        },
        'project_tasks',
        tid
      )
      await supabase.from('project_tasks').insert(subPayload)
    }
  }

  return created
}

// ============ Notifications ============

export async function getNotifications(recipientId: string, unreadOnly: boolean = false): Promise<ProjectNotification[]> {
  const tid = await getTenantId()
  let q = supabase
    .from('project_notifications')
    .select('*')
    .eq('recipient_id', recipientId)
  if (tid) q = q.eq('tenant_id', tid)
  if (unreadOnly) q = q.eq('is_read', false)
  q = q.order('created_at', { ascending: false }).limit(50)
  const { data, error } = await q
  if (error) throw error
  return (data || []) as ProjectNotification[]
}

export async function markNotificationRead(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(
    supabase.from('project_notifications').update({ is_read: true }),
    'project_notifications',
    tid
  ).eq('id', id).eq('tenant_id', tid)
  if (error) throw error
}

export async function markAllNotificationsRead(recipientId: string): Promise<void> {
  const tid = await getTenantId()
  let q = supabase
    .from('project_notifications')
    .update({ is_read: true })
    .eq('recipient_id', recipientId)
    .eq('is_read', false)
  if (tid) q = q.eq('tenant_id', tid)
  const { error } = await q
  if (error) throw error
}

export async function createNotification(
  recipientId: string,
  type: string,
  title: string,
  message: string,
  taskId?: string | null,
  projectId?: string | null,
  actionUrl?: string | null
): Promise<void> {
  const tid = await getTenantId()
  const payload = ti(
    {
      recipient_id: recipientId,
      notification_type: type,
      title,
      message,
      task_id: taskId,
      project_id: projectId,
      action_url: actionUrl,
      is_read: false,
      tenant_id: tid,
    },
    'project_notifications',
    tid
  )
  const { error } = await supabase.from('project_notifications').insert(payload)
  if (error) throw error

  // Send email notification for critical types
  try {
    if (!shouldSendEmail(type)) return

    // Look up employee email
    const { data: employee, error } = await supabase
      .from('employees')
      .select('email, name')
      .eq('id', recipientId)
      .single()
    if (error) throw error
    if (!employee?.email) return

    // Look up tenant name
    let tenantName = ''
    if (tid) {
      const { data: tenant, error } = await supabase
        .from('tenants')
        .select('name')
        .eq('id', tid)
        .single()
      if (error) throw error
      tenantName = tenant?.name || ''
    }

    // Build full action URL
    const fullActionUrl = actionUrl ? `${window.location.origin}${actionUrl}` : null

    // Get user locale
    const locale = localStorage.getItem('i18nextLng')?.split('-')[0] || 'fr'

    // Invoke the send-notification-email Edge Function
    const { error: emailError } = await supabase.functions.invoke('send-notification-email', {
      body: {
        to_email: employee.email,
        to_name: employee.name,
        notification_type: type,
        title,
        message,
        action_url: fullActionUrl,
        locale,
        tenant_name: tenantName,
        tenant_id: tid,
      },
    })

    if (emailError) {
      console.error('Failed to send notification email:', emailError.message)
    }
  } catch (emailErr) {
    // Email failure should not block the in-app notification
    console.error('Notification email error:', emailErr)
  }
}

// ============ Workload Computation ============

export async function getWorkloadData(tasks: ProjectTask[], capacityHoursPerWeek: number = 40): Promise<WorkloadEntry[]> {
  const now = new Date()
  const overdueThreshold = now.toISOString().split('T')[0]

  const byEmployee = new Map<string, { name: string; tasks: ProjectTask[] }>()

  for (const task of tasks) {
    if (!task.assignee || task.status === 'done' || task.status === 'canceled') continue
    const name = task.assignee
    if (!byEmployee.has(name)) {
      byEmployee.set(name, { name, tasks: [] })
    }
    byEmployee.get(name)!.tasks.push(task)
  }

  const entries: WorkloadEntry[] = []
  for (const [name, info] of byEmployee) {
    const total = info.tasks.length
    const active = info.tasks.filter((t) => t.status === 'doing' || t.status === 'todo').length
    const overdue = info.tasks.filter(
      (t) => t.due_date && t.due_date < overdueThreshold && t.status !== 'done' && t.status !== 'canceled'
    ).length
    const estimated = info.tasks.reduce((sum, t) => sum + (t.effort_estimate_h || 0), 0)
    const spent = info.tasks.reduce((sum, t) => sum + (t.effort_spent_h || 0), 0)
    const utilization = capacityHoursPerWeek > 0 ? Math.round((estimated / capacityHoursPerWeek) * 100) : 0

    let status: WorkloadEntry['status'] = 'balanced'
    if (utilization > 100) status = 'overloaded'
    else if (utilization < 50) status = 'underloaded'

    entries.push({
      employee_id: name,
      employee_name: name,
      total_tasks: total,
      active_tasks: active,
      overdue_tasks: overdue,
      estimated_hours: Math.round(estimated * 10) / 10,
      spent_hours: Math.round(spent * 10) / 10,
      capacity_hours: capacityHoursPerWeek,
      utilization_percentage: utilization,
      status,
    })
  }

  return entries.sort((a, b) => b.utilization_percentage - a.utilization_percentage)
}
