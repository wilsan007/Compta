import { useState, useMemo } from 'react'
import { useTranslation } from 'react-i18next'
import { useTaskContext } from '@/contexts/TaskContext'
import { useProjectContext } from '@/contexts/ProjectContext'
import { Card, EmptyState } from '@/components/ui'
import { Grid3x3 } from 'lucide-react'
import { cn } from '@/lib/utils'

type RowField = 'project' | 'assignee' | 'priority'
type ColField = 'status' | 'priority' | 'assignee'
type Metric = 'count' | 'hours' | 'progress'

interface PivotViewProps {
  projectId?: string
}

export function PivotView(_props: PivotViewProps) {
  const { t } = useTranslation('taskManagement')
  const { tasks, loading } = useTaskContext()
  const { projects } = useProjectContext()
  const [rowField, setRowField] = useState<RowField>('project')
  const [colField, setColField] = useState<ColField>('status')
  const [metric, setMetric] = useState<Metric>('count')

  const projectNames = useMemo(() => {
    const m = new Map<string, string>()
    projects.forEach((p) => m.set(p.id, p.name))
    return m
  }, [projects])

  const { rowKeys, colKeys, matrix, totals } = useMemo(() => {
    const rowSet = new Set<string>()
    const colSet = new Set<string>()

    for (const task of tasks) {
      let rv = ''
      if (rowField === 'project') rv = task.project_id ? (projectNames.get(task.project_id) || t('pivot.unknown')) : t('pivot.noProject')
      else if (rowField === 'assignee') rv = task.assignee || t('pivot.unassigned')
      else if (rowField === 'priority') rv = task.priority

      let cv = ''
      if (colField === 'status') cv = task.status
      else if (colField === 'priority') cv = task.priority
      else if (colField === 'assignee') cv = task.assignee || t('pivot.unassigned')

      rowSet.add(rv)
      colSet.add(cv)
    }

    const rowKeys = Array.from(rowSet).sort()
    const colKeys = Array.from(colSet).sort()
    const matrix: Record<string, Record<string, number>> = {}
    const totals: { row: Record<string, number>; col: Record<string, number>; grand: number } = {
      row: {},
      col: {},
      grand: 0,
    }

    for (const rk of rowKeys) {
      matrix[rk] = {}
      for (const ck of colKeys) matrix[rk][ck] = 0
      totals.row[rk] = 0
    }
    for (const ck of colKeys) totals.col[ck] = 0

    for (const task of tasks) {
      let rv = ''
      if (rowField === 'project') rv = task.project_id ? (projectNames.get(task.project_id) || t('pivot.unknown')) : t('pivot.noProject')
      else if (rowField === 'assignee') rv = task.assignee || t('pivot.unassigned')
      else if (rowField === 'priority') rv = task.priority

      let cv = ''
      if (colField === 'status') cv = task.status
      else if (colField === 'priority') cv = task.priority
      else if (colField === 'assignee') cv = task.assignee || t('pivot.unassigned')

      let val = 0
      if (metric === 'count') val = 1
      else if (metric === 'hours') val = task.effort_estimate_h || 0
      else if (metric === 'progress') val = task.progress || 0

      matrix[rv][cv] += val
      totals.row[rv] += val
      totals.col[cv] += val
      totals.grand += val
    }

    return { rowKeys, colKeys, matrix, totals }
  }, [tasks, rowField, colField, metric, projectNames, t])

  if (loading) {
    return <div className="flex items-center justify-center h-64 text-[var(--color-text-secondary)]">{t('loading')}</div>
  }

  if (tasks.length === 0) {
    return <EmptyState icon={<Grid3x3 className="w-8 h-8" />} title={t('pivot.noData')} description={t('pivot.noDataDesc')} />
  }

  const rowOptions: { key: RowField; label: string }[] = [
    { key: 'project', label: t('pivot.rowProject') },
    { key: 'assignee', label: t('pivot.rowAssignee') },
    { key: 'priority', label: t('pivot.rowPriority') },
  ]
  const colOptions: { key: ColField; label: string }[] = [
    { key: 'status', label: t('pivot.colStatus') },
    { key: 'priority', label: t('pivot.colPriority') },
    { key: 'assignee', label: t('pivot.colAssignee') },
  ]
  const metricOptions: { key: Metric; label: string }[] = [
    { key: 'count', label: t('pivot.metricCount') },
    { key: 'hours', label: t('pivot.metricHours') },
    { key: 'progress', label: t('pivot.metricProgress') },
  ]

  return (
    <div className="flex flex-col h-full p-4 gap-4" role="region" aria-label={t('pivot.title')}>
      <div className="flex items-center gap-2 flex-wrap">
        <select value={rowField} onChange={(e) => setRowField(e.target.value as RowField)} className="px-3 py-1.5 text-sm border border-[var(--color-border)] rounded-lg bg-[var(--color-surface)]" aria-label={t('pivot.rows')}>
          {rowOptions.map((o) => <option key={o.key} value={o.key}>{o.label}</option>)}
        </select>
        <span className="text-[var(--color-text-secondary)]">×</span>
        <select value={colField} onChange={(e) => setColField(e.target.value as ColField)} className="px-3 py-1.5 text-sm border border-[var(--color-border)] rounded-lg bg-[var(--color-surface)]" aria-label={t('pivot.columns')}>
          {colOptions.map((o) => <option key={o.key} value={o.key}>{o.label}</option>)}
        </select>
        <div className="w-px h-6 bg-[var(--color-border)]" />
        <select value={metric} onChange={(e) => setMetric(e.target.value as Metric)} className="px-3 py-1.5 text-sm border border-[var(--color-border)] rounded-lg bg-[var(--color-surface)]" aria-label={t('pivot.metric')}>
          {metricOptions.map((o) => <option key={o.key} value={o.key}>{o.label}</option>)}
        </select>
      </div>

      <Card title={t('pivot.title')} subtitle={t('pivot.subtitle', { count: tasks.length })}>
        <div className="overflow-x-auto">
          <table className="w-full text-sm border-collapse">
            <thead>
              <tr className="border-b-2 border-[var(--color-border)]">
                <th className="text-left p-3 font-semibold text-[var(--color-text)] sticky left-0 bg-[var(--color-surface)]">
                  {rowOptions.find((r) => r.key === rowField)?.label}
                </th>
                {colKeys.map((ck) => (
                  <th key={ck} className="text-center p-3 font-semibold text-[var(--color-text)] min-w-[80px]">
                    {ck}
                  </th>
                ))}
                <th className="text-center p-3 font-bold text-[var(--color-primary)] border-l border-[var(--color-border)]">
                  {t('pivot.total')}
                </th>
              </tr>
            </thead>
            <tbody>
              {rowKeys.map((rk) => (
                <tr key={rk} className="border-b border-[var(--color-border)] hover:bg-[var(--color-neutral-50)]">
                  <td className="p-3 font-medium text-[var(--color-text)] sticky left-0 bg-[var(--color-surface)]">
                    {rk}
                  </td>
                  {colKeys.map((ck) => {
                    const val = matrix[rk][ck]
                    const isMax = val > 0 && val === Math.max(...colKeys.map((c) => matrix[rk][c]))
                    return (
                      <td key={ck} className={cn('text-center p-3', isMax && 'font-bold text-[var(--color-primary)]')}>
                        {val > 0 ? (metric === 'progress' ? `${val.toFixed(0)}%` : val.toFixed(metric === 'hours' ? 1 : 0)) : '—'}
                      </td>
                    )
                  })}
                  <td className="text-center p-3 font-bold text-[var(--color-primary)] border-l border-[var(--color-border)]">
                    {metric === 'progress' ? `${totals.row[rk].toFixed(0)}%` : totals.row[rk].toFixed(metric === 'hours' ? 1 : 0)}
                  </td>
                </tr>
              ))}
            </tbody>
            <tfoot>
              <tr className="border-t-2 border-[var(--color-border)] bg-[var(--color-neutral-50)]">
                <td className="p-3 font-bold text-[var(--color-text)] sticky left-0 bg-[var(--color-neutral-50)]">
                  {t('pivot.total')}
                </td>
                {colKeys.map((ck) => (
                  <td key={ck} className="text-center p-3 font-bold text-[var(--color-primary)]">
                    {metric === 'progress' ? `${totals.col[ck].toFixed(0)}%` : totals.col[ck].toFixed(metric === 'hours' ? 1 : 0)}
                  </td>
                ))}
                <td className="text-center p-3 font-bold text-[var(--color-primary)] border-l border-[var(--color-border)]">
                  {metric === 'progress' ? `${totals.grand.toFixed(0)}%` : totals.grand.toFixed(metric === 'hours' ? 1 : 0)}
                </td>
              </tr>
            </tfoot>
          </table>
        </div>
      </Card>
    </div>
  )
}
