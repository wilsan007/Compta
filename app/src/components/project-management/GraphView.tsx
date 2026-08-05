import { useState, useMemo } from 'react'
import { useTranslation } from 'react-i18next'
import { useTaskContext } from '@/contexts/TaskContext'
import { useProjectContext } from '@/contexts/ProjectContext'
import { BarChart, Bar, PieChart, Pie, Cell, LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts'
import { Card, EmptyState } from '@/components/ui'
import { BarChart3, PieChart as PieIcon, TrendingUp } from 'lucide-react'
import { cn } from '@/lib/utils'

type ChartType = 'bar' | 'pie' | 'line'
type GroupBy = 'status' | 'priority' | 'assignee' | 'project'

const STATUS_COLORS: Record<string, string> = {
  todo: '#6b7280',
  doing: '#3b82f6',
  blocked: '#ef4444',
  changes_requested: '#f59e0b',
  approved: '#10b981',
  done: '#22c55e',
  canceled: '#9ca3af',
}

const PRIORITY_COLORS: Record<string, string> = {
  low: '#6b7280',
  medium: '#3b82f6',
  high: '#f59e0b',
  urgent: '#ef4444',
}

const PROJECT_COLORS = ['#3b82f6', '#10b981', '#f59e0b', '#8b5cf6', '#ec4899', '#06b6d4', '#84cc16', '#f97316']

interface GraphViewProps {
  projectId?: string
}

export function GraphView({ projectId }: GraphViewProps) {
  const { t } = useTranslation('taskManagement')
  const { tasks, loading } = useTaskContext()
  const { projects } = useProjectContext()
  const [chartType, setChartType] = useState<ChartType>('bar')
  const [groupBy, setGroupBy] = useState<GroupBy>('status')

  const projectNames = useMemo(() => {
    const m = new Map<string, string>()
    projects.forEach((p) => m.set(p.id, p.name))
    return m
  }, [projects])

  const chartData = useMemo(() => {
    const counts = new Map<string, number>()
    for (const task of tasks) {
      let key = ''
      if (groupBy === 'status') key = task.status
      else if (groupBy === 'priority') key = task.priority
      else if (groupBy === 'assignee') key = task.assignee || t('graph.unassigned')
      else if (groupBy === 'project') key = task.project_id ? (projectNames.get(task.project_id) || t('graph.unknownProject')) : t('graph.noProject')
      counts.set(key, (counts.get(key) || 0) + 1)
    }
    return Array.from(counts.entries()).map(([name, value]) => ({ name, value }))
  }, [tasks, groupBy, projectNames, t])

  const colorMap = useMemo(() => {
    if (groupBy === 'status') return STATUS_COLORS
    if (groupBy === 'priority') return PRIORITY_COLORS
    const m: Record<string, string> = {}
    chartData.forEach((d, i) => { m[d.name] = PROJECT_COLORS[i % PROJECT_COLORS.length] })
    return m
  }, [groupBy, chartData])

  if (loading) {
    return <div className="flex items-center justify-center h-64 text-[var(--color-text-secondary)]">{t('loading')}</div>
  }

  if (tasks.length === 0) {
    return <EmptyState icon={<BarChart3 className="w-8 h-8" />} title={t('graph.noData')} description={t('graph.noDataDesc')} />
  }

  const chartTypes: { key: ChartType; label: string; icon: React.ReactNode }[] = [
    { key: 'bar', label: t('graph.bar'), icon: <BarChart3 className="w-4 h-4" /> },
    { key: 'pie', label: t('graph.pie'), icon: <PieIcon className="w-4 h-4" /> },
    { key: 'line', label: t('graph.line'), icon: <TrendingUp className="w-4 h-4" /> },
  ]

  const groupOptions: { key: GroupBy; label: string }[] = [
    { key: 'status', label: t('graph.byStatus') },
    { key: 'priority', label: t('graph.byPriority') },
    { key: 'assignee', label: t('graph.byAssignee') },
    { key: 'project', label: t('graph.byProject') },
  ]

  return (
    <div className="flex flex-col h-full p-4 gap-4" role="region" aria-label={t('graph.title')}>
      <div className="flex items-center gap-2 flex-wrap">
        <div className="flex items-center gap-1" role="tablist" aria-label={t('graph.chartType')}>
          {chartTypes.map((ct) => (
            <button
              key={ct.key}
              role="tab"
              aria-selected={chartType === ct.key}
              onClick={() => setChartType(ct.key)}
              className={cn(
                'flex items-center gap-1.5 px-3 py-1.5 text-sm rounded-lg font-medium transition-colors',
                chartType === ct.key ? 'bg-[var(--color-primary)] text-white' : 'text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-100)]'
              )}
            >
              {ct.icon}
              {ct.label}
            </button>
          ))}
        </div>
        <div className="w-px h-6 bg-[var(--color-border)]" />
        <select
          value={groupBy}
          onChange={(e) => setGroupBy(e.target.value as GroupBy)}
          className="px-3 py-1.5 text-sm border border-[var(--color-border)] rounded-lg bg-[var(--color-surface)] outline-none focus:border-[var(--color-primary)]"
          aria-label={t('graph.groupBy')}
        >
          {groupOptions.map((opt) => (
            <option key={opt.key} value={opt.key}>{opt.label}</option>
          ))}
        </select>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 flex-1">
        <Card title={t('graph.title')} subtitle={t('graph.subtitle', { count: tasks.length })}>
          <ResponsiveContainer width="100%" height={350}>
            {chartType === 'bar' ? (
              <BarChart data={chartData}>
                <CartesianGrid strokeDasharray="3 3" stroke="var(--color-border)" />
                <XAxis dataKey="name" stroke="var(--color-text-secondary)" style={{ fontSize: 11 }} />
                <YAxis stroke="var(--color-text-secondary)" style={{ fontSize: 12 }} allowDecimals={false} />
                <Tooltip contentStyle={{ background: 'var(--color-surface)', border: '1px solid var(--color-border)', borderRadius: '8px', fontSize: 12 }} />
                <Bar dataKey="value" name={t('graph.taskCount')} radius={[4, 4, 0, 0]}>
                  {chartData.map((entry, i) => (
                    <Cell key={i} fill={colorMap[entry.name] || PROJECT_COLORS[i % PROJECT_COLORS.length]} />
                  ))}
                </Bar>
              </BarChart>
            ) : chartType === 'pie' ? (
              <PieChart>
                <Pie data={chartData} cx="50%" cy="50%" outerRadius={120} dataKey="value" nameKey="name" label={(entry: any) => entry.name}>
                  {chartData.map((entry, i) => (
                    <Cell key={i} fill={colorMap[entry.name] || PROJECT_COLORS[i % PROJECT_COLORS.length]} />
                  ))}
                </Pie>
                <Tooltip contentStyle={{ background: 'var(--color-surface)', border: '1px solid var(--color-border)', borderRadius: '8px', fontSize: 12 }} />
                <Legend wrapperStyle={{ fontSize: 12 }} />
              </PieChart>
            ) : (
              <LineChart data={chartData}>
                <CartesianGrid strokeDasharray="3 3" stroke="var(--color-border)" />
                <XAxis dataKey="name" stroke="var(--color-text-secondary)" style={{ fontSize: 11 }} />
                <YAxis stroke="var(--color-text-secondary)" style={{ fontSize: 12 }} allowDecimals={false} />
                <Tooltip contentStyle={{ background: 'var(--color-surface)', border: '1px solid var(--color-border)', borderRadius: '8px', fontSize: 12 }} />
                <Line type="monotone" dataKey="value" name={t('graph.taskCount')} stroke="var(--color-primary)" strokeWidth={2} dot={{ r: 5 }} />
              </LineChart>
            )}
          </ResponsiveContainer>
        </Card>

        <Card title={t('graph.summary')} subtitle={t('graph.summaryDesc')}>
          <div className="space-y-3">
            {chartData.map((item) => (
              <div key={item.name} className="flex items-center justify-between p-3 rounded-lg bg-[var(--color-neutral-50)] border border-[var(--color-border)]">
                <div className="flex items-center gap-3">
                  <div className="w-3 h-3 rounded-full" style={{ background: colorMap[item.name] || '#3b82f6' }} />
                  <span className="text-sm font-medium text-[var(--color-text)]">{item.name}</span>
                </div>
                <div className="flex items-center gap-2">
                  <span className="text-lg font-bold text-[var(--color-text)]">{item.value}</span>
                  <span className="text-xs text-[var(--color-text-secondary)]">
                    ({((item.value / tasks.length) * 100).toFixed(1)}%)
                  </span>
                </div>
              </div>
            ))}
          </div>
        </Card>
      </div>
    </div>
  )
}
