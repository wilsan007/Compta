import { useMemo } from 'react'
import { useTranslation } from 'react-i18next'
import { useTaskContext } from '@/contexts/TaskContext'
import { Card, EmptyState } from '@/components/ui'
import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts'
import { TrendingDown } from 'lucide-react'

interface BurndownChartProps {
  projectId?: string
}

export function BurndownChart({ projectId }: BurndownChartProps) {
  const { t } = useTranslation('taskManagement')
  const { tasks, loading } = useTaskContext()

  const chartData = useMemo(() => {
    if (tasks.length === 0) return []

    const totalTasks = tasks.length
    const totalHours = tasks.reduce((sum, task) => sum + (task.effort_estimate_h || 0), 0)

    const dates = tasks
      .map((task) => task.due_date || task.start_date || task.created_at)
      .filter(Boolean)
      .sort()

    if (dates.length === 0) return []

    const startDate = new Date(dates[0])
    const endDate = new Date(dates[dates.length - 1])
    const totalDays = Math.max(1, Math.ceil((endDate.getTime() - startDate.getTime()) / (1000 * 60 * 60 * 24)))

    const days: { date: string; remaining: number; ideal: number; remainingHours: number }[] = []
    for (let d = 0; d <= totalDays; d++) {
      const currentDate = new Date(startDate)
      currentDate.setDate(currentDate.getDate() + d)
      const dateStr = currentDate.toISOString().split('T')[0]

      const completedByDate = tasks.filter((task) => {
        if (task.status !== 'done' && task.status !== 'canceled') return false
        const taskDate = task.due_date || task.start_date || task.created_at
        return taskDate && taskDate.split('T')[0] <= dateStr
      }).length

      const remaining = totalTasks - completedByDate
      const ideal = Math.round(totalTasks * (1 - d / totalDays))
      const completedHoursByDate = tasks
        .filter((task) => {
          if (task.status !== 'done' && task.status !== 'canceled') return false
          const taskDate = task.due_date || task.start_date || task.created_at
          return taskDate && taskDate.split('T')[0] <= dateStr
        })
        .reduce((sum, task) => sum + (task.effort_estimate_h || 0), 0)

      days.push({
        date: dateStr,
        remaining,
        ideal,
        remainingHours: totalHours - completedHoursByDate,
      })
    }

    return days
  }, [tasks])

  if (loading) {
    return <div className="flex items-center justify-center h-64 text-[var(--color-text-secondary)]">{t('loading')}</div>
  }

  if (tasks.length === 0 || chartData.length === 0) {
    return <EmptyState icon={<TrendingDown className="w-8 h-8" />} title={t('burndown.noData')} description={t('burndown.noDataDesc')} />
  }

  const totalTasks = tasks.length
  const completedTasks = tasks.filter((task) => task.status === 'done' || task.status === 'canceled').length
  const remainingTasks = totalTasks - completedTasks
  const onTrack = chartData.length > 0 && chartData[chartData.length - 1].remaining <= chartData[chartData.length - 1].ideal

  return (
    <div className="flex flex-col h-full p-4 gap-4" role="region" aria-label={t('burndown.title')}>
      <div className="grid grid-cols-1 md:grid-cols-4 gap-3">
        <Card className="p-4">
          <div className="text-xs text-[var(--color-text-secondary)]">{t('burndown.totalTasks')}</div>
          <div className="text-2xl font-bold text-[var(--color-text)]">{totalTasks}</div>
        </Card>
        <Card className="p-4">
          <div className="text-xs text-[var(--color-text-secondary)]">{t('burndown.completed')}</div>
          <div className="text-2xl font-bold text-[var(--color-success)]">{completedTasks}</div>
        </Card>
        <Card className="p-4">
          <div className="text-xs text-[var(--color-text-secondary)]">{t('burndown.remaining')}</div>
          <div className="text-2xl font-bold text-[var(--color-warning)]">{remainingTasks}</div>
        </Card>
        <Card className="p-4">
          <div className="text-xs text-[var(--color-text-secondary)]">{t('burndown.status')}</div>
          <div className={`text-2xl font-bold ${onTrack ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>
            {onTrack ? t('burndown.onTrack') : t('burndown.behind')}
          </div>
        </Card>
      </div>

      <Card title={t('burndown.title')} subtitle={t('burndown.subtitle')} className="flex-1">
        <ResponsiveContainer width="100%" height={400}>
          <AreaChart data={chartData}>
            <defs>
              <linearGradient id="colorRemaining" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="var(--color-primary)" stopOpacity={0.3} />
                <stop offset="95%" stopColor="var(--color-primary)" stopOpacity={0} />
              </linearGradient>
              <linearGradient id="colorIdeal" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="var(--color-success)" stopOpacity={0.2} />
                <stop offset="95%" stopColor="var(--color-success)" stopOpacity={0} />
              </linearGradient>
            </defs>
            <CartesianGrid strokeDasharray="3 3" stroke="var(--color-border)" />
            <XAxis dataKey="date" stroke="var(--color-text-secondary)" style={{ fontSize: 11 }} />
            <YAxis stroke="var(--color-text-secondary)" style={{ fontSize: 12 }} allowDecimals={false} />
            <Tooltip contentStyle={{ background: 'var(--color-surface)', border: '1px solid var(--color-border)', borderRadius: '8px', fontSize: 12 }} />
            <Legend wrapperStyle={{ fontSize: 12 }} />
            <Area type="monotone" dataKey="ideal" name={t('burndown.idealLine')} stroke="var(--color-success)" strokeWidth={2} strokeDasharray="5 5" fill="url(#colorIdeal)" />
            <Area type="monotone" dataKey="remaining" name={t('burndown.actualLine')} stroke="var(--color-primary)" strokeWidth={2} fill="url(#colorRemaining)" />
          </AreaChart>
        </ResponsiveContainer>
      </Card>
    </div>
  )
}
