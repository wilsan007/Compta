import { Fragment, useCallback, useEffect, useMemo, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { AlertTriangle, CheckCircle2, ChevronDown, ChevronRight, Gauge, RefreshCw, Users } from 'lucide-react'
import { cn, formatDate } from '@/lib/utils'
import { silentFailureReporter } from '@/lib/silentFailureGuard'
import { useTaskContext } from '@/contexts/TaskContext'
import { useProjectContext } from '@/contexts/ProjectContext'
import { getResourceSourceRows, type ResourceSourceRows } from '@/lib/queries/projectFolders'
import { todayIso } from '@/lib/projectFolders'
import {
  computeResourceUsage,
  presetRange,
  type PeriodPreset,
  type ResourceRow,
  type UsageStatus,
} from '@/lib/resourceUsage'
import { ProgressBar } from './ProgressBar'

interface ResourceUsageViewProps {
  projectId?: string
}

type PresetKey = PeriodPreset | 'custom'
const PRESETS: PeriodPreset[] = ['thisWeek', 'thisMonth', 'lastMonth', 'thisQuarter', 'thisYear']

const STATUS_STYLE: Record<UsageStatus, string> = {
  overloaded: 'bg-red-50 text-red-700',
  balanced: 'bg-green-50 text-green-700',
  underloaded: 'bg-blue-50 text-blue-700',
  unknown: 'bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]',
}
const STATUS_COLOR: Record<UsageStatus, string> = {
  overloaded: '#dc2626',
  balanced: '#16a34a',
  underloaded: '#2563eb',
  unknown: '#9ca3af',
}

const fmtHours = (h: number): string => `${new Intl.NumberFormat(undefined, { maximumFractionDigits: 1 }).format(h)} h`

export function ResourceUsageView({ projectId }: ResourceUsageViewProps) {
  const { t } = useTranslation('taskManagement')
  const { tasks, loading: tasksLoading } = useTaskContext()
  const { projects, loading: projectsLoading } = useProjectContext()

  const [preset, setPreset] = useState<PresetKey>('thisMonth')
  const [range, setRange] = useState(() => presetRange('thisMonth'))
  const [projectFilter, setProjectFilter] = useState<string>(projectId || '')
  const [rows, setRows] = useState<ResourceSourceRows | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [expanded, setExpanded] = useState<Set<string>>(new Set())

  const validRange = !!range.from && !!range.to && range.from <= range.to

  const load = useCallback(() => {
    if (!validRange) return
    setError(null)
    getResourceSourceRows(range.from, range.to)
      .then(setRows)
      .catch((err: Error) => {
        silentFailureReporter.report({ type: 'load-failed', severity: 'error', message: `getResourceSourceRows: ${err.message}` })
        setError(err.message)
      })
  }, [range.from, range.to, validRange])

  useEffect(() => {
    load()
  }, [load])

  const choosePreset = (p: PresetKey) => {
    setPreset(p)
    if (p !== 'custom') setRange(presetRange(p))
  }

  const projectNames = useMemo(() => new Map(projects.map((p) => [p.id, p.name])), [projects])

  const usage = useMemo(() => {
    if (!rows || !validRange) return null
    return computeResourceUsage({
      from: range.from,
      to: range.to,
      today: todayIso(),
      employees: rows.employees,
      tasks,
      assignments: rows.assignments,
      timeEntries: rows.timeEntries,
      absenceDays: rows.absenceDays,
      projectNames,
      noProjectLabel: t('folders.noProject'),
      projectId: projectFilter || null,
    })
  }, [rows, tasks, projectNames, range.from, range.to, validRange, projectFilter, t])

  const toggle = (key: string) =>
    setExpanded((prev) => {
      const next = new Set(prev)
      if (next.has(key)) next.delete(key)
      else next.add(key)
      return next
    })

  const loading = tasksLoading || projectsLoading || (!rows && !error)

  return (
    <div className="h-full overflow-auto p-4 space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <h2 className="text-lg font-semibold">{t('resources.title')}</h2>
          <p className="text-sm text-[var(--color-text-secondary)]">{t('resources.subtitle')}</p>
        </div>
        <button
          type="button"
          onClick={load}
          aria-label={t('resources.refresh')}
          title={t('resources.refresh')}
          className="flex items-center justify-center w-8 h-8 rounded-lg border border-[var(--color-border)] hover:bg-[var(--color-neutral-50)]"
        >
          <RefreshCw className="w-4 h-4" />
        </button>
      </div>

      {/* Période et projet */}
      <div className="flex flex-wrap items-end gap-3 rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] p-3">
        <div role="group" aria-label={t('resources.period')} className="flex flex-wrap gap-1.5">
          {[...PRESETS, 'custom' as const].map((p) => (
            <button
              key={p}
              type="button"
              onClick={() => choosePreset(p)}
              aria-pressed={preset === p}
              className={cn(
                'px-2.5 py-1 text-sm rounded-lg border',
                preset === p
                  ? 'bg-[var(--color-primary)] text-white border-[var(--color-primary)]'
                  : 'border-[var(--color-border)] hover:bg-[var(--color-neutral-50)]'
              )}
            >
              {t(`resources.presets.${p}`)}
            </button>
          ))}
        </div>
        <label className="text-xs text-[var(--color-text-secondary)] flex flex-col gap-0.5">
          {t('resources.from')}
          <input
            type="date"
            value={range.from}
            onChange={(e) => {
              setPreset('custom')
              setRange((r) => ({ ...r, from: e.target.value }))
            }}
            className="px-2 py-1 text-sm rounded-lg border border-[var(--color-border)] bg-[var(--color-surface)] text-[var(--color-text)]"
          />
        </label>
        <label className="text-xs text-[var(--color-text-secondary)] flex flex-col gap-0.5">
          {t('resources.to')}
          <input
            type="date"
            value={range.to}
            onChange={(e) => {
              setPreset('custom')
              setRange((r) => ({ ...r, to: e.target.value }))
            }}
            className="px-2 py-1 text-sm rounded-lg border border-[var(--color-border)] bg-[var(--color-surface)] text-[var(--color-text)]"
          />
        </label>
        {!projectId && (
          <label className="text-xs text-[var(--color-text-secondary)] flex flex-col gap-0.5">
            {t('resources.project')}
            <select
              value={projectFilter}
              onChange={(e) => setProjectFilter(e.target.value)}
              className="px-2 py-1 text-sm rounded-lg border border-[var(--color-border)] bg-[var(--color-surface)] text-[var(--color-text)] max-w-[16rem]"
            >
              <option value="">{t('resources.allProjects')}</option>
              {projects.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name}
                </option>
              ))}
            </select>
          </label>
        )}
      </div>

      {!validRange && (
        <p role="alert" className="text-sm text-red-600">
          {t('resources.invalidRange')}
        </p>
      )}

      {validRange && loading && (
        <div className="flex items-center justify-center py-16">
          <p className="text-[var(--color-text-secondary)]">{t('loading')}</p>
        </div>
      )}

      {validRange && error && (
        <div className="flex flex-col items-center gap-3 py-12 text-center">
          <p className="font-medium">{t('resources.loadError')}</p>
          <p className="text-sm text-[var(--color-text-secondary)]">{error}</p>
        </div>
      )}

      {validRange && usage && !loading && (
        <>
          <p className="text-xs text-[var(--color-text-secondary)]">
            {t('resources.periodLabel', { from: formatDate(range.from), to: formatDate(range.to) })}
            {projectFilter && ` · ${t('resources.projectOnly', { name: projectNames.get(projectFilter) || '' })}`}
          </p>

          {/* Chiffres d'ensemble */}
          <div className="grid gap-3 grid-cols-2 lg:grid-cols-4">
            <Kpi label={t('resources.kpi.people')} value={String(usage.totals.people)} icon={<Users className="w-4 h-4" />} />
            <Kpi
              label={t('resources.kpi.avgRate')}
              value={usage.totals.plannedRate === null ? '—' : `${usage.totals.plannedRate}%`}
              hint={t('resources.kpi.avgRateHint', {
                planned: fmtHours(usage.totals.plannedHours),
                capacity: fmtHours(usage.totals.capacityHours),
              })}
              icon={<Gauge className="w-4 h-4" />}
            />
            <Kpi
              label={t('resources.kpi.overloaded')}
              value={String(usage.totals.overloaded)}
              tone={usage.totals.overloaded > 0 ? 'bad' : undefined}
              icon={<AlertTriangle className="w-4 h-4" />}
            />
            <Kpi
              label={t('resources.kpi.unassigned')}
              value={String(usage.unassignedTasks)}
              tone={usage.unassignedTasks > 0 ? 'warn' : undefined}
              hint={t('resources.kpi.unassignedHint')}
              icon={<CheckCircle2 className="w-4 h-4" />}
            />
          </div>

          {rows && !rows.absencesAvailable && (
            <p className="text-xs text-amber-700 bg-amber-50 rounded-lg px-3 py-2">{t('resources.absencesUnavailable')}</p>
          )}

          {usage.rows.length === 0 ? (
            <div className="flex flex-col items-center justify-center gap-2 py-12 text-center">
              <Users className="w-12 h-12 text-[var(--color-text-secondary)] opacity-50" aria-hidden="true" />
              <p className="font-medium">{t('resources.empty')}</p>
              <p className="text-sm text-[var(--color-text-secondary)]">{t('resources.emptyDesc')}</p>
            </div>
          ) : (
            <div className="overflow-x-auto rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)]">
              <table className="w-full text-sm">
                <caption className="sr-only">{t('resources.title')}</caption>
                <thead>
                  <tr className="text-xs text-[var(--color-text-secondary)] border-b border-[var(--color-border)]">
                    <th scope="col" className="text-start font-medium px-3 py-2">{t('resources.person')}</th>
                    <th scope="col" className="text-end font-medium px-3 py-2">{t('resources.tasks')}</th>
                    <th scope="col" className="text-end font-medium px-3 py-2">{t('resources.projects')}</th>
                    <th scope="col" className="text-end font-medium px-3 py-2">{t('resources.capacity')}</th>
                    <th scope="col" className="text-end font-medium px-3 py-2">{t('resources.planned')}</th>
                    <th scope="col" className="text-end font-medium px-3 py-2">{t('resources.logged')}</th>
                    <th scope="col" className="text-start font-medium px-3 py-2 min-w-[11rem]">{t('resources.utilization')}</th>
                  </tr>
                </thead>
                <tbody>
                  {usage.rows.map((r) => (
                    <PersonRow key={r.key} row={r} open={expanded.has(r.key)} onToggle={() => toggle(r.key)} t={t} />
                  ))}
                </tbody>
              </table>
            </div>
          )}

          <p className="text-xs text-[var(--color-text-secondary)]">{t('resources.method')}</p>
        </>
      )}
    </div>
  )
}

function Kpi({
  label,
  value,
  hint,
  icon,
  tone,
}: {
  label: string
  value: string
  hint?: string
  icon: React.ReactNode
  tone?: 'bad' | 'warn'
}) {
  return (
    <div className="rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] p-3">
      <div className="flex items-center gap-1.5 text-xs text-[var(--color-text-secondary)]">
        {icon}
        {label}
      </div>
      <p className={cn('text-2xl font-semibold tabular-nums', tone === 'bad' && 'text-red-600', tone === 'warn' && 'text-amber-600')}>
        {value}
      </p>
      {hint && <p className="text-[11px] text-[var(--color-text-secondary)]">{hint}</p>}
    </div>
  )
}

function PersonRow({
  row: r,
  open,
  onToggle,
  t,
}: {
  row: ResourceRow
  open: boolean
  onToggle: () => void
  t: ReturnType<typeof useTranslation>['t']
}) {
  const planned = r.plannedRate
  return (
    <Fragment>
      <tr className="border-b border-[var(--color-border)] last:border-b-0 align-top">
        <th scope="row" className="text-start font-normal px-3 py-2">
          <button
            type="button"
            onClick={onToggle}
            aria-expanded={open}
            aria-label={t('resources.toggleDetails', { name: r.name })}
            className="flex items-start gap-1.5 text-start"
          >
            {open ? (
              <ChevronDown className="w-4 h-4 mt-0.5 flex-shrink-0 rtl:rotate-90" aria-hidden="true" />
            ) : (
              <ChevronRight className="w-4 h-4 mt-0.5 flex-shrink-0 rtl:rotate-180" aria-hidden="true" />
            )}
            <span>
              <span className="font-medium">{r.name}</span>
              {r.position && <span className="block text-xs text-[var(--color-text-secondary)]">{r.position}</span>}
              {r.unlinked && <span className="block text-xs text-amber-700">{t('resources.unlinked')}</span>}
            </span>
          </button>
        </th>
        <td className="px-3 py-2 text-end tabular-nums">
          {r.tasks}
          {r.overdueTasks > 0 && (
            <span className="block text-xs text-red-600">{t('resources.overdue', { count: r.overdueTasks })}</span>
          )}
        </td>
        <td className="px-3 py-2 text-end tabular-nums">{r.projects}</td>
        <td className="px-3 py-2 text-end tabular-nums">
          {fmtHours(r.capacityHours)}
          {r.absenceDays > 0 && (
            <span className="block text-xs text-[var(--color-text-secondary)]">
              {t('resources.absences', { days: r.absenceDays })}
            </span>
          )}
        </td>
        <td className="px-3 py-2 text-end tabular-nums">{fmtHours(r.plannedHours)}</td>
        <td className="px-3 py-2 text-end tabular-nums">{fmtHours(r.loggedHours)}</td>
        <td className="px-3 py-2">
          <div className="flex items-center justify-between gap-2 mb-0.5">
            <span className="font-semibold tabular-nums">{planned === null ? '—' : `${planned}%`}</span>
            <span className={cn('text-[11px] font-medium px-1.5 py-0.5 rounded-full', STATUS_STYLE[r.status])}>
              {t(`resources.status.${r.status}`)}
            </span>
          </div>
          <ProgressBar value={Math.min(planned ?? 0, 100)} color={STATUS_COLOR[r.status]} />
          <p className="text-[11px] text-[var(--color-text-secondary)] mt-0.5">
            {t('resources.realized')} : {r.loggedRate === null ? '—' : `${r.loggedRate}%`}
          </p>
        </td>
      </tr>
      {open && (
        <tr className="border-b border-[var(--color-border)] bg-[var(--color-neutral-50)]">
          <td colSpan={7} className="px-3 py-3">
            <div className="flex flex-wrap gap-x-6 gap-y-1 text-xs text-[var(--color-text-secondary)] mb-2">
              <span>{t('resources.openTasks')} : {r.openTasks}</span>
              {r.unscheduledTasks > 0 && <span>{t('resources.unscheduled')} : {r.unscheduledTasks}</span>}
              {r.unestimatedTasks > 0 && <span>{t('resources.unestimated')} : {r.unestimatedTasks}</span>}
              <span>{t('resources.weeklyHours')} : {fmtHours(r.weeklyHours)}</span>
            </div>
            {r.byProject.length > 0 && (
              <table className="w-full text-xs">
                <caption className="sr-only">{t('resources.details', { name: r.name })}</caption>
                <thead>
                  <tr className="text-[var(--color-text-secondary)]">
                    <th scope="col" className="text-start font-medium py-1">{t('resources.project')}</th>
                    <th scope="col" className="text-end font-medium py-1">{t('resources.tasks')}</th>
                    <th scope="col" className="text-end font-medium py-1">{t('resources.planned')}</th>
                    <th scope="col" className="text-end font-medium py-1">{t('resources.logged')}</th>
                  </tr>
                </thead>
                <tbody>
                  {r.byProject.map((l) => (
                    <tr key={l.projectId ?? 'none'} className="border-t border-[var(--color-border)]">
                      <th scope="row" className="text-start font-normal py-1">{l.name}</th>
                      <td className="text-end tabular-nums py-1">{l.tasks}</td>
                      <td className="text-end tabular-nums py-1">{fmtHours(l.plannedHours)}</td>
                      <td className="text-end tabular-nums py-1">{fmtHours(l.loggedHours)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </td>
        </tr>
      )}
    </Fragment>
  )
}
