import { useTranslation } from 'react-i18next'
import type { ProjectTask } from '@/types/projectManagement'
import { TaskRow } from './TaskRow'

interface TaskTableBodyProps {
  tasks: ProjectTask[]
  collapsedIds: Set<string>
  onToggleCollapse: (id: string) => void
  onUpdateTask: (id: string, updates: Record<string, unknown>) => void
  onDeleteTask: (id: string) => void
  onDuplicateTask: (id: string) => void
  onAddSubTask: (parentId: string) => void
  projectColorMap: Map<string, string>
  projectNames: Map<string, string>
  canEdit?: boolean
}

export function TaskTableBody({
  tasks,
  collapsedIds,
  onToggleCollapse,
  onUpdateTask,
  onDeleteTask,
  onDuplicateTask,
  onAddSubTask,
  projectColorMap,
  projectNames,
  canEdit = true,
}: TaskTableBodyProps) {
  const { t } = useTranslation('taskManagement')

  const sorted = [...tasks].sort((a, b) => {
    const aOrder = a.display_order || '0'
    const bOrder = b.display_order || '0'
    return aOrder.localeCompare(bOrder)
  })

  const visibleTasks = sorted.filter((task) => {
    if (!task.parent_id) return true
    let parentId = task.parent_id
    while (parentId) {
      if (collapsedIds.has(parentId)) return false
      const parent = sorted.find((t) => t.id === parentId)
      parentId = parent?.parent_id || null
    }
    return true
  })

  if (visibleTasks.length === 0) {
    return (
      <tbody>
        <tr>
          <td colSpan={12} className="text-center py-12 text-sm text-[var(--color-text-tertiary)]">
            {t('table.noTasks')}
          </td>
        </tr>
      </tbody>
    )
  }

  return (
    <tbody>
      {visibleTasks.map((task) => (
        <TaskRow
          key={task.id}
          task={task}
          hasSubTasks={tasks.some((t) => t.parent_id === task.id)}
          isCollapsed={collapsedIds.has(task.id)}
          onToggleCollapse={() => onToggleCollapse(task.id)}
          onUpdate={(updates) => onUpdateTask(task.id, updates)}
          onDelete={() => onDeleteTask(task.id)}
          onDuplicate={() => onDuplicateTask(task.id)}
          onAddSubTask={() => onAddSubTask(task.id)}
          projectColor={task.project_id ? projectColorMap.get(task.project_id) || '#0066cc' : '#97a0af'}
          projectName={task.project_id ? projectNames.get(task.project_id) || '' : ''}
          canEdit={canEdit}
        />
      ))}
    </tbody>
  )
}
