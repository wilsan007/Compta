import { useState, useEffect, useCallback, useMemo } from 'react'
import { useTranslation } from 'react-i18next'
import { Activity, Filter, ChevronDown, ChevronRight, ListTodo, ChevronsDownUp, ChevronsUpDown } from 'lucide-react'
import { useToast } from '@/lib/toast'
import { getActivityLog } from '@/lib/queries/projectManagementSprint1'
import type { ActivityLogEntry, ActivityActionType } from '@/types/projectManagement'

interface ActivityViewProps {
  projectId?: string
  taskId?: string
}

interface TaskGroup {
  task_id: string | null
  task_title: string | null
  entries: ActivityLogEntry[]
}

export function ActivityView({ projectId, taskId }: ActivityViewProps) {
  const { t } = useTranslation('taskManagement')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [entries, setEntries] = useState<ActivityLogEntry[]>([])
  const [loading, setLoading] = useState(true)
  const [filter, setFilter] = useState<ActivityActionType | 'all'>('all')
  const [expandedGroups, setExpandedGroups] = useState<Set<string>>(new Set())

  const loadActivity = useCallback(async () => {
    setLoading(true)
    try {
      const data = await getActivityLog(taskId, projectId, 200)
      setEntries(data)
    } catch (err: any) {
      console.error("catch:", err)
      // ignore
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadingError'))
    } finally {
      setLoading(false)
    }
  }, [taskId, projectId, tCommon, toast])

  useEffect(() => {
    loadActivity().catch(err => console.error('loadActivity:', err))
  }, [loadActivity])

  const filteredEntries = useMemo(() => {
    if (filter === 'all') return entries
    return entries.filter((e) => e.action_type === filter)
  }, [entries, filter])

  // Group entries by task
  const taskGroups = useMemo<TaskGroup[]>(() => {
    const groups = new Map<string, TaskGroup>()
    for (const entry of filteredEntries) {
      const key = entry.task_id || 'no-task'
      if (!groups.has(key)) {
        groups.set(key, {
          task_id: entry.task_id,
          task_title: entry.task_title || null,
          entries: [],
        })
      }
      groups.get(key)!.entries.push(entry)
    }
    return Array.from(groups.values()).sort((a, b) => {
      const aTime = new Date(a.entries[0]?.created_at || 0).getTime()
      const bTime = new Date(b.entries[0]?.created_at || 0).getTime()
      return bTime - aTime
    })
  }, [filteredEntries])

  const toggleGroup = useCallback((key: string) => {
    setExpandedGroups((prev) => {
      const next = new Set(prev)
      if (next.has(key)) {
        next.delete(key)
      } else {
        next.add(key)
      }
      return next
    })
  }, [])

  const expandAll = useCallback(() => {
    setExpandedGroups(new Set(taskGroups.map((g) => g.task_id || 'no-task')))
  }, [taskGroups])

  const collapseAll = useCallback(() => {
    setExpandedGroups(new Set())
  }, [])

  const filterOptions: { value: ActivityActionType | 'all'; label: string }[] = [
    { value: 'all', label: t('activity.filterAll') },
    { value: 'status_changed', label: t('activity.statusChanged') },
    { value: 'priority_changed', label: t('activity.priorityChanged') },
    { value: 'assigned', label: t('activity.assigned') },
    { value: 'created', label: t('activity.created') },
    { value: 'commented', label: t('activity.commented') },
  ]

  const actionIcons: Record<string, string> = {
    created: '✨',
    updated: '📝',
    status_changed: '🔄',
    priority_changed: '⚠️',
    assigned: '👤',
    title_changed: '✏️',
    due_date_changed: '📅',
    progress_changed: '📊',
    commented: '💬',
    uploaded: '📎',
    completed: '✅',
    archived: '📦',
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-full">
        <p className="text-[var(--color-text-secondary)]">{t('loading')}</p>
      </div>
    )
  }

  return (
    <div className="h-full overflow-auto p-4">
      {/* Header */}
      <div className="mb-4 flex items-center justify-between flex-wrap gap-2">
        <div>
          <h2 className="text-lg font-semibold flex items-center gap-2">
            <Activity className="w-5 h-5" />
            {t('activity.title')}
          </h2>
          <p className="text-sm text-[var(--color-text-secondary)]">{t('activity.subtitle')}</p>
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          {taskGroups.length > 0 && (
            <div className="flex items-center gap-1">
              <button
                onClick={expandAll}
                className="text-xs px-2 py-1 rounded border border-[var(--color-border)] bg-[var(--color-surface)] hover:bg-[var(--color-bg-hover)] transition-colors flex items-center gap-1"
                title={t('activity.expandAll')}
              >
                <ChevronsUpDown className="w-3 h-3" />
                {t('activity.expandAll')}
              </button>
              <button
                onClick={collapseAll}
                className="text-xs px-2 py-1 rounded border border-[var(--color-border)] bg-[var(--color-surface)] hover:bg-[var(--color-bg-hover)] transition-colors flex items-center gap-1"
                title={t('activity.collapseAll')}
              >
                <ChevronsDownUp className="w-3 h-3" />
                {t('activity.collapseAll')}
              </button>
            </div>
          )}
          <div className="flex items-center gap-1">
            <Filter className="w-3 h-3 text-[var(--color-text-secondary)]" />
            <select
              value={filter}
              onChange={(e) => setFilter(e.target.value as ActivityActionType | 'all')}
              className="text-xs px-2 py-1 rounded border border-[var(--color-border)] bg-[var(--color-surface)]"
            >
              {filterOptions.map((opt) => (
                <option key={opt.value} value={opt.value}>
                  {opt.label}
                </option>
              ))}
            </select>
          </div>
        </div>
      </div>

      {taskGroups.length === 0 ? (
        <div className="flex flex-col items-center justify-center h-64 gap-2">
          <Activity className="w-12 h-12 text-[var(--color-text-secondary)] opacity-50" />
          <p className="text-[var(--color-text)] font-medium">{t('activity.noActivity')}</p>
          <p className="text-sm text-[var(--color-text-secondary)]">{t('activity.noActivityDesc')}</p>
        </div>
      ) : (
        <div
          className="grid gap-3"
          style={{
            gridTemplateColumns: 'repeat(auto-fill, minmax(min(100%, 340px), 1fr))',
          }}
        >
          {taskGroups.map((group) => {
            const groupKey = group.task_id || 'no-task'
            const isExpanded = expandedGroups.has(groupKey)
            const lastEntry = group.entries[0]
            const previewEntries = group.entries.slice(0, 3)

            return (
              <div
                key={groupKey}
                className="rounded-lg border border-[var(--color-border)] bg-[var(--color-surface)] overflow-hidden flex flex-col"
              >
                {/* Card header — always visible, click to expand */}
                <button
                  onClick={() => toggleGroup(groupKey)}
                  className="w-full flex items-center gap-2 px-3 py-2.5 hover:bg-[var(--color-bg-hover)] transition-colors text-left"
                >
                  {isExpanded ? (
                    <ChevronDown className="w-4 h-4 text-[var(--color-text-secondary)] flex-shrink-0" />
                  ) : (
                    <ChevronRight className="w-4 h-4 text-[var(--color-text-secondary)] flex-shrink-0" />
                  )}
                  <ListTodo className="w-4 h-4 text-[var(--color-text-secondary)] flex-shrink-0" />
                  <span className="text-sm font-medium flex-1 truncate">
                    {group.task_title || t('activity.unassignedTask')}
                  </span>
                  <span className="text-xs text-[var(--color-text-secondary)] bg-[var(--color-bg)] px-2 py-0.5 rounded-full flex-shrink-0">
                    {group.entries.length}
                  </span>
                </button>

                {/* Collapsed preview: last activity summary + up to 3 entries */}
                {!isExpanded && (
                  <div className="px-3 pb-3 pt-0.5">
                    {/* Last activity highlight */}
                    {lastEntry && (
                      <div className="flex items-center gap-2 mb-2 text-xs text-[var(--color-text-secondary)]">
                        <span className="text-base flex-shrink-0">
                          {actionIcons[lastEntry.action_type] || '📝'}
                        </span>
                        <span className="font-medium text-[var(--color-text)] truncate">
                          {lastEntry.user_name || t('chatter.unknown')}
                        </span>
                        <span className="truncate flex-shrink-0">
                          {new Date(lastEntry.created_at).toLocaleDateString()}{' '}
                          {new Date(lastEntry.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                        </span>
                      </div>
                    )}
                    {/* Preview entries (max 3) */}
                    <div className="space-y-1">
                      {previewEntries.map((entry) => (
                        <div key={entry.id} className="flex items-start gap-2 text-xs">
                          <span className="flex-shrink-0 mt-0.5">
                            {actionIcons[entry.action_type] || '📝'}
                          </span>
                          <div className="flex-1 min-w-0">
                            <span className="text-[var(--color-text-secondary)] truncate block">
                              {entry.description || t(`activity.${entry.action_type}`, { defaultValue: t('activity.updated') })}
                            </span>
                          </div>
                        </div>
                      ))}
                    </div>
                    {group.entries.length > 3 && (
                      <p className="text-xs text-[var(--color-text-secondary)] mt-1.5 italic">
                        {t('activity.moreEntries', { count: group.entries.length - 3 })}
                      </p>
                    )}
                  </div>
                )}

                {/* Expanded: full timeline */}
                {isExpanded && (
                  <div className="relative px-3 pb-3 pt-1 flex-1 overflow-auto" style={{ maxHeight: '400px' }}>
                    <div className="absolute left-7 top-0 bottom-0 w-px bg-[var(--color-border)]" />
                    <div className="space-y-2">
                      {group.entries.map((entry) => (
                        <div key={entry.id} className="relative flex gap-3 pl-0">
                          <div className="w-8 h-8 rounded-full bg-[var(--color-bg)] border border-[var(--color-border)] flex items-center justify-center text-sm flex-shrink-0 z-10">
                            {actionIcons[entry.action_type] || '📝'}
                          </div>
                          <div className="flex-1 pb-2 min-w-0">
                            <div className="flex items-baseline gap-2 flex-wrap">
                              <span className="text-sm font-medium truncate">
                                {entry.user_name || t('chatter.unknown')}
                              </span>
                              <span className="text-xs text-[var(--color-text-secondary)] flex-shrink-0">
                                {new Date(entry.created_at).toLocaleString()}
                              </span>
                            </div>
                            <p className="text-sm text-[var(--color-text-secondary)] mt-0.5 break-words">
                              {entry.description || t(`activity.${entry.action_type}`, { defaultValue: t('activity.updated') })}
                            </p>
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}
