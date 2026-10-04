import { useTranslation } from 'react-i18next'
import type { ProjectTask, TaskStatus, TaskPriority } from '@/types/projectManagement'
import { EditableTitleCell } from './cells/EditableTitleCell'
import { EditableDateCell } from './cells/EditableDateCell'
import { EditableSelectCell } from './cells/EditableSelectCell'
import { EditableCellWithDebounce } from './cells/EditableCellWithDebounce'
import { ProgressBar } from './ProgressBar'
import { TaskRowActions } from './TaskRowActions'
import { AssigneeSelect } from './AssigneeSelect'
import { Paperclip, MessageSquare } from 'lucide-react'

interface TaskRowProps {
  task: ProjectTask
  hasSubTasks: boolean
  isCollapsed: boolean
  onToggleCollapse: () => void
  onUpdate: (updates: Record<string, unknown>) => void
  onDelete: () => void
  onDuplicate: () => void
  onAddSubTask: () => void
  projectColor: string
  projectName: string
  canEdit?: boolean
}

export function TaskRow({
  task,
  hasSubTasks,
  isCollapsed,
  onToggleCollapse,
  onUpdate,
  onDelete,
  onDuplicate,
  onAddSubTask,
  projectColor,
  projectName,
  canEdit = true,
}: TaskRowProps) {
  const { t } = useTranslation('taskManagement')

  const statusOptions = [
    { value: 'todo', label: t('status.todo') },
    { value: 'doing', label: t('status.doing') },
    { value: 'blocked', label: t('status.blocked') },
    { value: 'changes_requested', label: t('status.changes_requested') },
    { value: 'approved', label: t('status.approved') },
    { value: 'done', label: t('status.done') },
    { value: 'canceled', label: t('status.canceled') },
  ]

  const priorityOptions = [
    { value: 'low', label: t('priority.low') },
    { value: 'medium', label: t('priority.medium') },
    { value: 'high', label: t('priority.high') },
    { value: 'urgent', label: t('priority.urgent') },
  ]

  return (
    <tr className="group border-b border-[var(--color-border)] hover:bg-[var(--color-neutral-50)]">
      <td className="px-1">
        <EditableTitleCell
          value={task.title}
          onCommit={(v) => onUpdate({ title: v })}
          onAddSubTask={onAddSubTask}
          onCollapse={onToggleCollapse}
          isCollapsed={isCollapsed}
          hasSubTasks={hasSubTasks}
          taskLevel={task.task_level}
          disabled={!canEdit}
        />
      </td>
      <td className="px-2 py-1">
        <div className="flex items-center gap-1.5">
          <div className="w-2 h-2 rounded-full flex-shrink-0" style={{ backgroundColor: projectColor }} />
          <span className="text-xs text-[var(--color-text-secondary)] truncate" title={projectName}>
            {projectName || '—'}
          </span>
        </div>
      </td>
      <td className="px-2 py-1">
        <AssigneeSelect
          value={task.assignee_id}
          onCommit={(employeeId, employeeName) => onUpdate({ assignee_id: employeeId, assignee: employeeName })}
          disabled={!canEdit}
        />
      </td>
      <td className="px-1 py-1">
        <EditableSelectCell
          value={task.status}
          options={statusOptions}
          onCommit={(v) => onUpdate({ status: v as TaskStatus })}
          disabled={!canEdit}
        />
      </td>
      <td className="px-1 py-1">
        <EditableSelectCell
          value={task.priority}
          options={priorityOptions}
          onCommit={(v) => onUpdate({ priority: v as TaskPriority })}
          disabled={!canEdit}
        />
      </td>
      <td className="px-1 py-1">
        <EditableDateCell
          value={task.start_date}
          onCommit={(v) => onUpdate({ start_date: v })}
          disabled={!canEdit}
        />
      </td>
      <td className="px-1 py-1">
        <EditableDateCell
          value={task.due_date}
          onCommit={(v) => onUpdate({ due_date: v })}
          disabled={!canEdit}
        />
      </td>
      <td className="px-2 py-1">
        <EditableCellWithDebounce
          value={task.effort_estimate_h}
          type="number"
          onCommit={async (v) => onUpdate({ effort_estimate_h: Number(v) })}
          disabled={!canEdit}
        />
      </td>
      <td className="px-2 py-1">
        <ProgressBar value={task.progress} showLabel size="sm" />
      </td>
      <td className="px-1 py-1">
        <TaskRowActions
          onEdit={() => onUpdate({})}
          onDuplicate={onDuplicate}
          onDelete={onDelete}
        />
      </td>
      <td className="px-2 py-1 text-center">
        <button
          className="p-1 rounded hover:bg-[var(--color-neutral-100)] cursor-not-allowed opacity-50"
          title={t('columns.documents')}
          disabled
        >
          <Paperclip className="w-3.5 h-3.5 text-[var(--color-text-tertiary)]" />
        </button>
      </td>
      <td className="px-2 py-1 text-center">
        <button
          className="p-1 rounded hover:bg-[var(--color-neutral-100)] cursor-not-allowed opacity-50"
          title={t('columns.comments')}
          disabled
        >
          <MessageSquare className="w-3.5 h-3.5 text-[var(--color-text-tertiary)]" />
        </button>
      </td>
    </tr>
  )
}
