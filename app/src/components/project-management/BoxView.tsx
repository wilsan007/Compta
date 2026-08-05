import { useState, useMemo } from 'react'
import { useTranslation } from 'react-i18next'
import { cn } from '@/lib/utils'
import { Boxes, ChevronRight, ChevronDown } from 'lucide-react'
import { useTaskContext } from '@/contexts/TaskContext'
import { useProjectContext } from '@/contexts/ProjectContext'
import type { ProjectTask, TaskStatus } from '@/types/projectManagement'

interface BoxViewProps {
  projectId?: string
}

const statusColors: Record<TaskStatus, { bg: string; border: string; text: string }> = {
  todo: { bg: '#f4f5f7', border: '#dfe1e6', text: '#5e6c84' },
  doing: { bg: '#deebff', border: '#4bb2ff', text: '#0066cc' },
  blocked: { bg: '#fff0b3', border: '#ff9500', text: '#974f00' },
  changes_requested: { bg: '#ffebe6', border: '#ff5c3a', text: '#de350b' },
  approved: { bg: '#eae6ff', border: '#8777d9', text: '#403293' },
  done: { bg: '#e3fcef', border: '#36b37e', text: '#00875a' },
  canceled: { bg: '#f4f5f7', border: '#dfe1e6', text: '#97a0af' },
}

export function BoxView({ projectId }: BoxViewProps) {
  const { t } = useTranslation('taskManagement')
  const { tasks, loading } = useTaskContext()
  const { projects, projectColorMap } = useProjectContext()
  const [expandedBoxes, setExpandedBoxes] = useState<Set<string>>(new Set())
  const [selectedProject, setSelectedProject] = useState<string | 'all'>('all')

  const projectNames = useMemo(() => {
    const map = new Map<string, string>()
    projects.forEach((p) => map.set(p.id, p.name))
    return map
  }, [projects])

  const filteredTasks = useMemo(() => {
    if (projectId) return tasks.filter((t) => t.project_id === projectId)
    if (selectedProject !== 'all') return tasks.filter((t) => t.project_id === selectedProject)
    return tasks
  }, [tasks, projectId, selectedProject])

  const taskTree = useMemo(() => {
    const byParent = new Map<string | null, ProjectTask[]>()
    for (const task of filteredTasks) {
      const key = task.parent_id
      if (!byParent.has(key)) byParent.set(key, [])
      byParent.get(key)!.push(task)
    }
    return byParent
  }, [filteredTasks])

  const toggleBox = (id: string) => {
    setExpandedBoxes((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-full">
        <p className="text-[var(--color-text-secondary)]">{t('loading')}</p>
      </div>
    )
  }

  if (filteredTasks.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center h-full gap-2">
        <Boxes className="w-12 h-12 text-[var(--color-text-secondary)] opacity-50" />
        <p className="text-[var(--color-text)] font-medium">{t('box.noTasks')}</p>
        <p className="text-sm text-[var(--color-text-secondary)]">{t('box.noTasksDesc')}</p>
      </div>
    )
  }

  const renderBox = (task: ProjectTask, depth: number): React.ReactNode => {
    const children = taskTree.get(task.id) || []
    const isExpanded = expandedBoxes.has(task.id)
    const hasChildren = children.length > 0
    const colors = statusColors[task.status] || statusColors.todo
    const projColor = task.project_id ? projectColorMap.get(task.project_id) : undefined
    const projName = task.project_id ? projectNames.get(task.project_id) : undefined

    return (
      <div key={task.id} className={cn(depth === 0 ? 'mb-3' : 'mt-2')}>
        <div
          className={cn(
            'rounded-xl border-2 transition-all cursor-pointer overflow-hidden',
            isExpanded && hasChildren && 'shadow-md'
          )}
          style={{
            background: depth === 0 ? 'var(--color-surface)' : colors.bg,
            borderColor: depth === 0 ? (projColor || 'var(--color-border)') : colors.border,
          }}
          onClick={() => hasChildren && toggleBox(task.id)}
        >
          {/* Box header */}
          <div className="flex items-center gap-2 px-3 py-2">
            {hasChildren ? (
              <button className="flex items-center justify-center w-5 h-5 rounded flex-shrink-0 hover:bg-black/5 transition-colors">
                {isExpanded ? <ChevronDown className="w-3.5 h-3.5" /> : <ChevronRight className="w-3.5 h-3.5" />}
              </button>
            ) : (
              <span className="w-5 h-5 flex-shrink-0" />
            )}

            {/* Status badge */}
            <span
              className="text-[10px] font-semibold px-1.5 py-0.5 rounded flex-shrink-0"
              style={{ background: colors.bg, color: colors.text, border: `1px solid ${colors.border}` }}
            >
              {t(`status.${task.status}`)}
            </span>

            {/* Title */}
            <span
              className={cn(
                'text-sm font-medium flex-1 truncate',
                task.status === 'done' && 'line-through opacity-60'
              )}
              style={{ color: depth === 0 ? 'var(--color-text)' : colors.text }}
            >
              {task.title}
            </span>

            {/* Project tag (root only) */}
            {depth === 0 && projName && (
              <span
                className="text-[10px] px-1.5 py-0.5 rounded flex-shrink-0"
                style={{
                  background: projColor ? `${projColor}15` : 'var(--color-neutral-100)',
                  color: projColor || 'var(--color-text-secondary)',
                }}
              >
                {projName}
              </span>
            )}

            {/* Assignee */}
            {task.assignee && (
              <div className="w-6 h-6 rounded-full bg-[var(--color-primary)] text-white flex items-center justify-center text-[10px] font-medium flex-shrink-0">
                {task.assignee.charAt(0).toUpperCase()}
              </div>
            )}

            {/* Subtask count */}
            {hasChildren && (
              <span className="text-[10px] text-[var(--color-text-secondary)] bg-[var(--color-neutral-100)] px-1.5 py-0.5 rounded-full flex-shrink-0">
                {children.length}
              </span>
            )}

            {/* Progress bar */}
            {task.progress > 0 && (
              <div className="w-16 h-1.5 rounded-full bg-[var(--color-neutral-100)] overflow-hidden flex-shrink-0">
                <div
                  className="h-full rounded-full transition-all"
                  style={{ width: `${task.progress}%`, background: colors.text }}
                />
              </div>
            )}
          </div>

          {/* Box body: metadata */}
          {(task.due_date || task.effort_estimate_h > 0 || task.priority !== 'low') && (
            <div className="flex items-center gap-3 px-3 pb-2 text-[10px] text-[var(--color-text-secondary)]">
              {task.priority !== 'low' && (
                <span className="flex items-center gap-1">
                  <span
                    className="w-1.5 h-1.5 rounded-full"
                    style={{
                      background: task.priority === 'urgent' ? '#de350b' : task.priority === 'high' ? '#ff9500' : '#0066cc',
                    }}
                  />
                  {t(`priority.${task.priority}`)}
                </span>
              )}
              {task.due_date && <span>📅 {new Date(task.due_date).toLocaleDateString()}</span>}
              {task.effort_estimate_h > 0 && <span>⏱ {task.effort_estimate_h}h</span>}
              {task.effort_spent_h > 0 && <span>✓ {task.effort_spent_h}h</span>}
            </div>
          )}

          {/* Nested children boxes */}
          {hasChildren && isExpanded && (
            <div className="px-3 pb-3 pt-1 space-y-2 bg-[var(--color-neutral-50)]/50">
              {children.map((child) => renderBox(child, depth + 1))}
            </div>
          )}
        </div>
      </div>
    )
  }

  const rootTasks = taskTree.get(null) || []

  return (
    <div className="h-full overflow-auto p-4">
      <div className="mb-4 flex items-center justify-between">
        <div>
          <h2 className="text-lg font-semibold flex items-center gap-2">
            <Boxes className="w-5 h-5" />
            {t('box.title')}
          </h2>
          <p className="text-sm text-[var(--color-text-secondary)]">{t('box.subtitle')}</p>
        </div>

        {!projectId && projects.length > 0 && (
          <select
            value={selectedProject}
            onChange={(e) => setSelectedProject(e.target.value as string | 'all')}
            className="text-xs px-3 py-1.5 rounded-lg border border-[var(--color-border)] bg-[var(--color-surface)]"
          >
            <option value="all">{t('box.allProjects')}</option>
            {projects.map((p) => (
              <option key={p.id} value={p.id}>{p.name}</option>
            ))}
          </select>
        )}
      </div>

      <div className="grid gap-3 lg:grid-cols-2 xl:grid-cols-3">
        {rootTasks.map((task) => renderBox(task, 0))}
      </div>
    </div>
  )
}
