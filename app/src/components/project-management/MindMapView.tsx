import { useState, useMemo, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { cn } from '@/lib/utils'
import { Network, ChevronRight, ChevronDown, Circle } from 'lucide-react'
import { useTaskContext } from '@/contexts/TaskContext'
import { useProjectContext } from '@/contexts/ProjectContext'
import type { ProjectTask, TaskStatus } from '@/types/projectManagement'

interface MindMapViewProps {
  projectId?: string
}

interface MindNode {
  task: ProjectTask
  children: MindNode[]
  depth: number
}

const statusColors: Record<TaskStatus, string> = {
  todo: '#97a0af',
  doing: '#0066cc',
  blocked: '#ff9500',
  changes_requested: '#de350b',
  approved: '#8777d9',
  done: '#00875a',
  canceled: '#6b778c',
}

const priorityColors: Record<string, string> = {
  low: '#97a0af',
  medium: '#0066cc',
  high: '#ff9500',
  urgent: '#de350b',
}

export function MindMapView({ projectId }: MindMapViewProps) {
  const { t } = useTranslation('taskManagement')
  const { tasks, loading } = useTaskContext()
  const { projects } = useProjectContext()
  const [expandedNodes, setExpandedNodes] = useState<Set<string>>(new Set())
  const [selectedTask, setSelectedTask] = useState<string | null>(null)

  const projectNames = useMemo(() => {
    const map = new Map<string, string>()
    projects.forEach((p) => map.set(p.id, p.name))
    return map
  }, [projects])

  const tree = useMemo<MindNode[]>(() => {
    const filtered = projectId ? tasks.filter((t) => t.project_id === projectId) : tasks
    const byParent = new Map<string | null, ProjectTask[]>()
    for (const task of filtered) {
      const key = task.parent_id
      if (!byParent.has(key)) byParent.set(key, [])
      byParent.get(key)!.push(task)
    }
    const build = (parentId: string | null, depth: number): MindNode[] => {
      const items = byParent.get(parentId) || []
      return items
        .sort((a, b) => a.display_order.localeCompare(b.display_order))
        .map((task) => ({
          task,
          children: build(task.id, depth + 1),
          depth,
        }))
    }
    return build(null, 0)
  }, [tasks, projectId])

  const toggleExpand = useCallback((id: string) => {
    setExpandedNodes((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }, [])

  const expandAll = useCallback(() => {
    setExpandedNodes(new Set(tasks.map((t) => t.id)))
  }, [tasks])

  const collapseAll = useCallback(() => {
    setExpandedNodes(new Set())
  }, [])

  if (loading) {
    return (
      <div className="flex items-center justify-center h-full">
        <p className="text-[var(--color-text-secondary)]">{t('loading')}</p>
      </div>
    )
  }

  if (tree.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center h-full gap-2">
        <Network className="w-12 h-12 text-[var(--color-text-secondary)] opacity-50" />
        <p className="text-[var(--color-text)] font-medium">{t('mindMap.noTasks')}</p>
        <p className="text-sm text-[var(--color-text-secondary)]">{t('mindMap.noTasksDesc')}</p>
      </div>
    )
  }

  const renderNode = (node: MindNode) => {
    const hasChildren = node.children.length > 0
    const isExpanded = expandedNodes.has(node.task.id)
    const isSelected = selectedTask === node.task.id
    const statusColor = statusColors[node.task.status] || '#97a0af'
    const prioColor = priorityColors[node.task.priority] || '#97a0af'

    return (
      <div key={node.task.id} className="select-none">
        <div
          className={cn(
            'flex items-center gap-2 px-2 py-1.5 rounded-lg cursor-pointer transition-colors group',
            isSelected && 'bg-[var(--color-primary)]/10',
            !isSelected && 'hover:bg-[var(--color-neutral-50)]'
          )}
          style={{ paddingLeft: `${node.depth * 20 + 8}px` }}
          onClick={() => {
            setSelectedTask(node.task.id)
            if (hasChildren) toggleExpand(node.task.id)
          }}
        >
          {hasChildren ? (
            <button
              className="flex items-center justify-center w-4 h-4 text-[var(--color-text-secondary)] hover:text-[var(--color-text)] flex-shrink-0"
              onClick={(e) => {
                e.stopPropagation()
                toggleExpand(node.task.id)
              }}
            >
              {isExpanded ? <ChevronDown className="w-3.5 h-3.5" /> : <ChevronRight className="w-3.5 h-3.5" />}
            </button>
          ) : (
            <Circle className="w-2 h-2 flex-shrink-0 text-[var(--color-text-tertiary)]" />
          )}

          {/* Status dot */}
          <span className="w-2 h-2 rounded-full flex-shrink-0" style={{ background: statusColor }} />

          {/* Title */}
          <span
            className={cn(
              'text-sm flex-1 truncate',
              node.task.status === 'done' && 'line-through text-[var(--color-text-secondary)]'
            )}
          >
            {node.task.title}
          </span>

          {/* Priority indicator */}
          {node.task.priority !== 'low' && (
            <span
              className="w-1.5 h-1.5 rounded-full flex-shrink-0"
              style={{ background: prioColor }}
              title={t(`priority.${node.task.priority}`)}
            />
          )}

          {/* Project tag */}
          {node.task.project_id && node.depth === 0 && (
            <span className="text-[10px] text-[var(--color-text-secondary)] bg-[var(--color-neutral-100)] px-1.5 py-0.5 rounded flex-shrink-0">
              {projectNames.get(node.task.project_id) || ''}
            </span>
          )}

          {/* Subtask count */}
          {hasChildren && (
            <span className="text-[10px] text-[var(--color-text-secondary)] flex-shrink-0">
              {node.children.length}
            </span>
          )}
        </div>

        {/* Children */}
        {hasChildren && isExpanded && (
          <div className="relative">
            <div
              className="absolute top-0 bottom-0 w-px bg-[var(--color-border)]"
              style={{ left: `${node.depth * 20 + 14}px` }}
            />
            {node.children.map((child) => renderNode(child))}
          </div>
        )}
      </div>
    )
  }

  return (
    <div className="h-full overflow-auto p-4">
      <div className="mb-4 flex items-center justify-between">
        <div>
          <h2 className="text-lg font-semibold flex items-center gap-2">
            <Network className="w-5 h-5" />
            {t('mindMap.title')}
          </h2>
          <p className="text-sm text-[var(--color-text-secondary)]">{t('mindMap.subtitle')}</p>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={expandAll}
            className="text-xs px-2.5 py-1 rounded-lg border border-[var(--color-border)] hover:bg-[var(--color-neutral-50)] transition-colors"
          >
            {t('mindMap.expandAll')}
          </button>
          <button
            onClick={collapseAll}
            className="text-xs px-2.5 py-1 rounded-lg border border-[var(--color-border)] hover:bg-[var(--color-neutral-50)] transition-colors"
          >
            {t('mindMap.collapseAll')}
          </button>
        </div>
      </div>

      {/* Legend */}
      <div className="flex items-center gap-4 mb-3 text-xs text-[var(--color-text-secondary)]">
        {(['todo', 'doing', 'blocked', 'done'] as TaskStatus[]).map((s) => (
          <span key={s} className="flex items-center gap-1.5">
            <span className="w-2 h-2 rounded-full" style={{ background: statusColors[s] }} />
            {t(`status.${s}`)}
          </span>
        ))}
      </div>

      <div className="space-y-0.5">
        {tree.map((node) => renderNode(node))}
      </div>

      {/* Detail panel for selected task */}
      {selectedTask && (
        <div className="mt-4 p-4 rounded-lg border border-[var(--color-border)] bg-[var(--color-surface)]">
          {(() => {
            const task = tasks.find((t) => t.id === selectedTask)
            if (!task) return null
            return (
              <div className="space-y-2">
                <div className="flex items-center gap-2">
                  <span className="w-2.5 h-2.5 rounded-full" style={{ background: statusColors[task.status] }} />
                  <h3 className="text-sm font-semibold">{task.title}</h3>
                </div>
                {task.description && (
                  <p className="text-xs text-[var(--color-text-secondary)]">{task.description}</p>
                )}
                <div className="flex items-center gap-4 text-xs text-[var(--color-text-secondary)]">
                  {task.assignee && <span>👤 {task.assignee}</span>}
                  {task.due_date && <span>📅 {new Date(task.due_date).toLocaleDateString()}</span>}
                  {task.effort_estimate_h > 0 && <span>⏱ {task.effort_estimate_h}h</span>}
                  <span>📊 {task.progress}%</span>
                </div>
              </div>
            )
          })()}
        </div>
      )}
    </div>
  )
}
