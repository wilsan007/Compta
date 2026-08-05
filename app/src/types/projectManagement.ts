// Project Management & Task Management Types
// Source: Project & Task Management reference (section 25.3 — Fusion model)
// All types use snake_case to match Supabase database columns exactly

// ============ Enums / Unions ============

export type TaskStatus = 'todo' | 'doing' | 'blocked' | 'changes_requested' | 'approved' | 'done' | 'canceled'
export type TaskPriority = 'low' | 'medium' | 'high' | 'urgent'
export type DependencyType = 'finish-to-start' | 'start-to-start' | 'finish-to-finish' | 'start-to-finish'
export type RecurringRuleType = 'daily' | 'weekly' | 'monthly' | 'yearly'
export type PrivacyVisibility = 'followers' | 'employees' | 'portal'
export type ViewMode = 'day' | 'week' | 'month' | 'quarter' | 'year'
export type DisplayMode = 'tasks' | 'projects'
export type BoardView = 'table' | 'kanban' | 'gantt'

// ============ Extended Project ============

export interface ProjectExtended {
  id: string
  name: string
  description: string
  customer_id: string | null
  status: 'active' | 'completed' | 'on_hold' | 'cancelled'
  budget: number
  actual_cost: number
  start_date: string
  end_date: string
  created_at: string
  updated_at: string
  // Extended fields
  color: string
  display_order: string
  progress: number
  manager_id: string | null
  allow_subtasks: boolean
  allow_recurrent_tasks: boolean
  allow_milestones: boolean
  allow_task_dependencies: boolean
  allow_timesheets: boolean
  allow_billable: boolean
  privacy_visibility: PrivacyVisibility
  alias_name: string | null
  allocated_hours: number
  total_hours_spent: number
  remaining_hours: number
  tenant_id: string
}

// ============ Project Task ============

export interface ProjectTask {
  id: string
  tenant_id: string
  project_id: string | null
  parent_id: string | null
  title: string
  description: string | null
  status: TaskStatus
  priority: TaskPriority
  assignee: string | null
  assignee_id: string | null
  start_date: string | null
  due_date: string | null
  effort_estimate_h: number
  effort_spent_h: number
  progress: number
  display_order: string
  task_level: number
  budget: number
  color: number
  acceptance_criteria: string | null
  recurring_task: boolean
  recurring_interval: number
  recurring_rule_type: RecurringRuleType
  is_closed: boolean
  linked_action_id: string | null
  production_order_id: string | null
  created_at: string
  updated_at: string
  // Computed (not in DB, populated by queries)
  subtask_count?: number
  subtask_done_count?: number
  assignees?: ProjectTaskAssignee[]
  tags?: ProjectTag[]
  actions?: TaskAction[]
  dependencies?: ProjectTaskDependency[]
}

// ============ Project Task Dependency ============

export interface ProjectTaskDependency {
  id: string
  tenant_id: string
  task_id: string
  depends_on_task_id: string
  dependency_type: DependencyType
  lag_days: number
  created_at: string
}

// ============ Project Stage ============

export interface ProjectStage {
  id: string
  tenant_id: string
  name: string
  sequence: number
  fold: boolean
  case_default: boolean
  mail_template_id: string | null
  legend_priority: string | null
  legend_blocked: string | null
  legend_done: string | null
  legend_normal: string | null
  created_at: string
  updated_at: string
}

// ============ Project Milestone ============

export interface ProjectMilestone {
  id: string
  tenant_id: string
  project_id: string
  name: string
  deadline: string | null
  is_reached: boolean
  is_reached_manually: boolean
  sale_line_id: string | null
  sale_line_qty_percentage: number
  created_at: string
  updated_at: string
}

// ============ Project Tag ============

export interface ProjectTag {
  id: string
  tenant_id: string
  name: string
  color: number
  created_at: string
}

// ============ Project Task Assignee (junction) ============

export interface ProjectTaskAssignee {
  task_id: string
  employee_id: string
  employee_name?: string
}

// ============ Project Member ============

export type ProjectMemberRole = 'project_director' | 'project_manager' | 'team_member' | 'consultant' | 'observer' | 'guest'

export interface ProjectMember {
  id: string
  tenant_id: string
  project_id: string
  employee_id: string
  role: ProjectMemberRole
  created_at: string
  updated_at: string
  employee_name?: string
}

// ============ Task Action ============

export interface TaskAction {
  id: string
  tenant_id: string
  task_id: string
  title: string
  weight_percentage: number
  is_done: boolean
  due_date: string | null
  notes: string | null
  created_at: string
}

// ============ Task Action Attachment ============

export interface TaskActionAttachment {
  id: string
  tenant_id: string
  task_action_id: string
  task_id: string
  file_name: string
  file_path: string
  file_size: number | null
  mime_type: string | null
  uploader_id: string | null
  created_at: string
}

// ============ Task Document ============

export interface TaskDocument {
  id: string
  tenant_id: string
  task_id: string
  project_id: string | null
  file_name: string
  file_path: string
  file_size: number | null
  mime_type: string | null
  uploader_id: string | null
  created_at: string
}

// ============ Task Comment ============

export interface TaskComment {
  id: string
  tenant_id: string
  task_id: string
  content: string
  comment_type: string
  author_id: string | null
  created_at: string
}

// ============ Task Filters ============

export interface TaskFilters {
  search: string
  status: TaskStatus[]
  priority: TaskPriority[]
  assignee: string[]
  project: string[]
  tags: string[]
  dateFrom: string
  dateTo: string
}

export const emptyTaskFilters: TaskFilters = {
  search: '',
  status: [],
  priority: [],
  assignee: [],
  project: [],
  tags: [],
  dateFrom: '',
  dateTo: '',
}

// ============ Gantt Types ============

export interface GanttTask {
  id: string
  title: string
  start_date: string
  due_date: string
  progress: number
  project_id: string | null
  project_name?: string
  project_color?: string
  parent_id: string | null
  task_level: number
  status: TaskStatus
  priority: TaskPriority
  assignee: string | null
  display_order: string
}

export interface ViewConfig {
  viewMode: ViewMode
  yearBuffer: number
}

export const DEFAULT_VIEW_CONFIG: ViewConfig = {
  viewMode: 'month',
  yearBuffer: 1,
}

// ============ Helper Types ============

export type TaskCreateInput = Omit<ProjectTask, 'id' | 'tenant_id' | 'created_at' | 'updated_at' | 'is_closed' | 'subtask_count' | 'subtask_done_count' | 'assignees' | 'tags' | 'actions' | 'dependencies' | 'description' | 'assignee_id'> & {
  description?: string | null
  assignee_id?: string | null
}
export type TaskUpdateInput = Partial<TaskCreateInput>

// ============ Time Entry (Sprint 1) ============

export interface TimeEntry {
  id: string
  tenant_id: string
  task_id: string | null
  project_id: string | null
  employee_id: string | null
  start_time: string
  end_time: string | null
  duration_seconds: number
  description: string | null
  is_billable: boolean
  hourly_rate: number
  tags: string[]
  created_at: string
  updated_at: string
}

export interface TimeEntryCreateInput {
  task_id?: string | null
  project_id?: string | null
  employee_id?: string | null
  start_time?: string
  end_time?: string | null
  duration_seconds?: number
  description?: string | null
  is_billable?: boolean
  hourly_rate?: number
  tags?: string[]
}

// ============ Task Watcher (Sprint 1) ============

export interface TaskWatcher {
  id: string
  tenant_id: string
  task_id: string
  employee_id: string
  employee_name?: string
  created_at: string
}

// ============ Activity Log Entry (Sprint 1) ============

export type ActivityActionType =
  | 'created' | 'updated' | 'status_changed' | 'priority_changed'
  | 'assigned' | 'title_changed' | 'due_date_changed' | 'progress_changed'
  | 'commented' | 'uploaded' | 'completed' | 'archived'

export interface ActivityLogEntry {
  id: string
  tenant_id: string
  task_id: string | null
  project_id: string | null
  user_id: string | null
  user_name: string | null
  action_type: ActivityActionType
  old_value: Record<string, unknown> | null
  new_value: Record<string, unknown> | null
  description: string | null
  created_at: string
  // Joined from project_tasks
  task_title?: string | null
}

// ============ Task Template (Sprint 1) ============

export interface TaskTemplate {
  id: string
  tenant_id: string
  name: string
  description: string | null
  default_status: TaskStatus
  default_priority: TaskPriority
  default_assignee_id: string | null
  default_tags: string[]
  default_effort_estimate: number
  default_budget: number
  checklist_template: Array<{ title: string; weight_percentage: number }>
  subtasks_template: Array<{ title: string }>
  is_public: boolean
  created_at: string
  updated_at: string
}

export interface TaskTemplateCreateInput {
  name: string
  description?: string | null
  default_status?: TaskStatus
  default_priority?: TaskPriority
  default_assignee_id?: string | null
  default_tags?: string[]
  default_effort_estimate?: number
  default_budget?: number
  checklist_template?: Array<{ title: string; weight_percentage: number }>
  subtasks_template?: Array<{ title: string }>
  is_public?: boolean
}

// ============ Notification (Sprint 1) ============

export type NotificationType =
  | 'task_assigned' | 'status_changed' | 'comment_added'
  | 'due_date_approaching' | 'task_overdue' | 'mention' | 'watcher_update'
  // Extended types — centralized notification system
  | 'project_member_added' | 'task_completed' | 'progress_changed'
  | 'payment_overdue' | 'stock_critical' | 'stock_warning'
  | 'budget_exceeded' | 'approval_request' | 'invitation_pending'

export type NotificationSeverity = 'critical' | 'important' | 'informational'

// Notification types that trigger an email by default (critical severity)
export const EMAIL_CRITICAL_TYPES: NotificationType[] = [
  'task_assigned',
  'task_overdue',
  'due_date_approaching',
  'payment_overdue',
  'stock_critical',
  'invitation_pending',
]

// Notification types that are important but not critical (email optional)
export const EMAIL_IMPORTANT_TYPES: NotificationType[] = [
  'status_changed',
  'mention',
  'budget_exceeded',
  'approval_request',
  'project_member_added',
]

// Informational types — in-app only by default
export const EMAIL_INFORMATIONAL_TYPES: NotificationType[] = [
  'comment_added',
  'watcher_update',
  'stock_warning',
  'task_completed',
  'progress_changed',
]

export function getNotificationSeverity(type: string): NotificationSeverity {
  if (EMAIL_CRITICAL_TYPES.includes(type as NotificationType)) return 'critical'
  if (EMAIL_IMPORTANT_TYPES.includes(type as NotificationType)) return 'important'
  return 'informational'
}

export function shouldSendEmail(type: string, userPrefs?: { email_enabled: boolean; email_types: Record<string, boolean> }): boolean {
  const severity = getNotificationSeverity(type)
  if (severity === 'informational') return false
  if (!userPrefs) return severity === 'critical'
  if (!userPrefs.email_enabled) return false
  // Check explicit user preference for this type
  if (type in userPrefs.email_types) return userPrefs.email_types[type]
  // Default: critical = email, important = no email
  return severity === 'critical'
}

export interface ProjectNotification {
  id: string
  tenant_id: string
  recipient_id: string
  task_id: string | null
  project_id: string | null
  notification_type: NotificationType
  title: string
  message: string | null
  is_read: boolean
  action_url: string | null
  created_at: string
}

// ============ Workload Data (Sprint 1) ============

export interface WorkloadEntry {
  employee_id: string
  employee_name: string
  total_tasks: number
  active_tasks: number
  overdue_tasks: number
  estimated_hours: number
  spent_hours: number
  capacity_hours: number
  utilization_percentage: number
  status: 'underloaded' | 'balanced' | 'overloaded'
}

// ============ Timeline Item (Sprint 1) ============

export interface TimelineItem {
  id: string
  title: string
  start_date: string
  due_date: string | null
  status: TaskStatus
  priority: TaskPriority
  project_id: string | null
  project_name?: string
  project_color?: string
  assignee: string | null
  progress: number
  parent_id: string | null
  task_level: number
}
