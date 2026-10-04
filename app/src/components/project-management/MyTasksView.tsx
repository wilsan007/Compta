import { useState, useMemo } from 'react'
import { useTranslation } from 'react-i18next'
import { useTaskContext } from '@/contexts/TaskContext'
import { useProjectContext } from '@/contexts/ProjectContext'
import { useAuth } from '@/lib/auth'
import { Card, EmptyState, Badge } from '@/components/ui'
import { CheckSquare, ListTodo, Clock, AlertCircle, User, Users } from 'lucide-react'
import { cn } from '@/lib/utils'
import { formatDate } from '@/lib/utils'
import type { TaskStatus } from '@/types/projectManagement'

const STATUS_VARIANTS: Record<TaskStatus, 'neutral' | 'primary' | 'danger' | 'warning' | 'success'> = {
  todo: 'neutral',
  doing: 'primary',
  blocked: 'danger',
  changes_requested: 'warning',
  approved: 'primary',
  done: 'success',
  canceled: 'neutral',
}

type FilterTab = 'mine' | 'all' | 'overdue' | 'private'

interface MyTasksViewProps {
  projectId?: string
}

export function MyTasksView(_props: MyTasksViewProps) {
  const { t } = useTranslation('taskManagement')
  const { tasks, loading } = useTaskContext()
  const { projects, projectColorMap } = useProjectContext()
  const { user } = useAuth()
  const [tab, setTab] = useState<FilterTab>('mine')

  const userName = user?.name || ''
  const isAdmin = user?.role === 'admin'

  const projectNames = useMemo(() => {
    const m = new Map<string, string>()
    projects.forEach((p) => m.set(p.id, p.name))
    return m
  }, [projects])

  const myTasks = useMemo(() =>
    tasks.filter((task) =>
      task.assignee && task.assignee === userName &&
      task.status !== 'done' && task.status !== 'canceled'
    ),
  [tasks, userName])

  const filteredTasks = useMemo(() => {
    const now = new Date().toISOString().split('T')[0]
    switch (tab) {
      case 'mine':
        return myTasks
      case 'overdue':
        return tasks.filter((task) =>
          task.due_date && task.due_date < now &&
          task.status !== 'done' && task.status !== 'canceled'
        )
      case 'private':
        return tasks.filter((task) => !task.project_id)
      default:
        return tasks
    }
  }, [tasks, myTasks, tab])

  const stats = useMemo(() => {
    const myActive = myTasks.length
    const allActive = tasks.filter((task) => task.status !== 'done' && task.status !== 'canceled').length
    const overdue = tasks.filter((task) =>
      task.due_date && task.due_date < new Date().toISOString().split('T')[0] &&
      task.status !== 'done' && task.status !== 'canceled'
    ).length
    const completed = tasks.filter((task) => task.status === 'done').length
    return { myActive, allActive, overdue, completed }
  }, [tasks, myTasks])

  if (loading) {
    return <div className="flex items-center justify-center h-64 text-[var(--color-text-secondary)]">{t('loading')}</div>
  }

  const tabs: { key: FilterTab; label: string; icon: React.ReactNode; count: number }[] = [
    { key: 'mine', label: t('myTasks.mine'), icon: <User className="w-4 h-4" />, count: stats.myActive },
    { key: 'all', label: isAdmin ? t('myTasks.allTeam') : t('myTasks.all'), icon: <Users className="w-4 h-4" />, count: stats.allActive },
    { key: 'overdue', label: t('myTasks.overdue'), icon: <AlertCircle className="w-4 h-4" />, count: stats.overdue },
    { key: 'private', label: t('myTasks.private'), icon: <Clock className="w-4 h-4" />, count: tasks.filter((task) => !task.project_id).length },
  ]

  return (
    <div className="flex flex-col h-full p-4 gap-4" role="region" aria-label={t('myTasks.title')}>
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <Card className="p-4">
          <div className="flex items-center gap-2">
            <User className="w-5 h-5 text-[var(--color-primary)]" />
            <div>
              <div className="text-xs text-[var(--color-text-secondary)]">{t('myTasks.assignedToMe')}</div>
              <div className="text-2xl font-bold text-[var(--color-text)]">{stats.myActive}</div>
            </div>
          </div>
        </Card>
        <Card className="p-4">
          <div className="flex items-center gap-2">
            <Users className="w-5 h-5 text-[var(--color-text-secondary)]" />
            <div>
              <div className="text-xs text-[var(--color-text-secondary)]">{t('myTasks.activeTasks')}</div>
              <div className="text-2xl font-bold text-[var(--color-text)]">{stats.allActive}</div>
            </div>
          </div>
        </Card>
        <Card className="p-4">
          <div className="flex items-center gap-2">
            <AlertCircle className="w-5 h-5 text-[var(--color-danger)]" />
            <div>
              <div className="text-xs text-[var(--color-text-secondary)]">{t('myTasks.overdueTasks')}</div>
              <div className="text-2xl font-bold text-[var(--color-danger)]">{stats.overdue}</div>
            </div>
          </div>
        </Card>
        <Card className="p-4">
          <div className="flex items-center gap-2">
            <CheckSquare className="w-5 h-5 text-[var(--color-success)]" />
            <div>
              <div className="text-xs text-[var(--color-text-secondary)]">{t('myTasks.completedTasks')}</div>
              <div className="text-2xl font-bold text-[var(--color-success)]">{stats.completed}</div>
            </div>
          </div>
        </Card>
      </div>

      <div className="flex items-center gap-1" role="tablist" aria-label={t('myTasks.title')}>
        {tabs.map((tb) => (
          <button
            key={tb.key}
            role="tab"
            aria-selected={tab === tb.key}
            onClick={() => setTab(tb.key)}
            className={cn(
              'flex items-center gap-1.5 px-3 py-1.5 text-sm rounded-lg font-medium transition-colors',
              tab === tb.key ? 'bg-[var(--color-primary)] text-white' : 'text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-100)]'
            )}
          >
            {tb.icon}
            {tb.label}
            <span className={cn(
              'ml-1 px-1.5 py-0.5 text-xs rounded-full',
              tab === tb.key ? 'bg-white/20' : 'bg-[var(--color-neutral-100)]'
            )}>
              {tb.count}
            </span>
          </button>
        ))}
      </div>

      {filteredTasks.length === 0 ? (
        <EmptyState icon={<ListTodo className="w-8 h-8" />} title={t('myTasks.noTasks')} description={t('myTasks.noTasksDesc')} />
      ) : (
        <div className="flex-1 overflow-y-auto space-y-2">
          {filteredTasks.map((task) => {
            const projectName = task.project_id ? (projectNames.get(task.project_id) || '') : null
            const projectColor = task.project_id ? (projectColorMap.get(task.project_id) || '#3b82f6') : '#6b7280'
            const isOverdue = task.due_date && task.due_date < new Date().toISOString().split('T')[0] && task.status !== 'done' && task.status !== 'canceled'

            return (
              <div
                key={task.id}
                className="flex items-center gap-3 p-3 rounded-lg border border-[var(--color-border)] bg-[var(--color-surface)] hover:shadow-sm transition-shadow"
              >
                <div className="w-1 h-10 rounded-full" style={{ background: projectColor }} />
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-medium text-[var(--color-text)] truncate">{task.title}</span>
                    {task.parent_id && (
                      <span className="text-xs text-[var(--color-text-secondary)]">↳ {t('myTasks.subtask')}</span>
                    )}
                  </div>
                  <div className="flex items-center gap-2 mt-1">
                    {projectName && (
                      <span className="text-xs px-2 py-0.5 rounded-full" style={{ background: `${projectColor}20`, color: projectColor }}>
                        {projectName}
                      </span>
                    )}
                    <Badge variant={STATUS_VARIANTS[task.status]}>{t(`status.${task.status}`)}</Badge>
                    {task.priority === 'urgent' && (
                      <span className="text-xs text-[var(--color-danger)] font-medium">{t('myTasks.urgent')}</span>
                    )}
                  </div>
                </div>
                <div className="text-right">
                  {task.due_date && (
                    <div className={cn(
                      'text-xs',
                      isOverdue ? 'text-[var(--color-danger)] font-medium' : 'text-[var(--color-text-secondary)]'
                    )}>
                      {formatDate(task.due_date)}
                    </div>
                  )}
                  {task.assignee && (
                    <div className="text-xs text-[var(--color-text-secondary)] mt-0.5">@{task.assignee}</div>
                  )}
                </div>
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}
