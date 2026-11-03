import { useCallback, useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import type { TFunction } from 'i18next'
import { AlertOctagon, AlertTriangle, CheckCircle2, ChevronRight, RefreshCw } from 'lucide-react'
import { cn, formatDate } from '@/lib/utils'
import { silentFailureReporter } from '@/lib/silentFailureGuard'
import { useTaskContext } from '@/contexts/TaskContext'
import { useProjectContext } from '@/contexts/ProjectContext'
import { getFolderSourceRows, getResourceSourceRows, type FolderSourceRows, type ResourceSourceRows } from '@/lib/queries/projectFolders'
import { assembleFolderSources, todayIso } from '@/lib/projectFolders'
import { computeResourceUsage, presetRange } from '@/lib/resourceUsage'
import { computeAttention, type AttentionItem, type Health, type ProjectHealth } from '@/lib/projectAttention'
import { ProgressBar } from './ProgressBar'

interface AttentionViewProps {
  projectId?: string
}

// Au-delà, la liste se replie derrière « Tout voir » : un portefeuille en difficulté ne doit pas noyer l'écran.
const VISIBLE_ITEMS = 10

const HEALTH_STYLE: Record<Health, { dot: string; chip: string }> = {
  red: { dot: '#dc2626', chip: 'bg-red-50 text-red-700' },
  amber: { dot: '#d97706', chip: 'bg-amber-50 text-amber-700' },
  green: { dot: '#16a34a', chip: 'bg-green-50 text-green-700' },
}

const folderHref = (kind: 'project' | 'task', id: string): string =>
  `/project-management/folders?dossier=${encodeURIComponent(`${kind}:${id}`)}`

// Où mène le bouton d'une ligne : le dossier concerné, ou la charge des personnes.
function targetOf(it: AttentionItem): { href: string; labelKey: string } {
  if (it.kind === 'overloaded') return { href: '/project-management/resources', labelKey: 'attention.openResources' }
  if (it.taskId) return { href: folderHref('task', it.taskId), labelKey: 'attention.openFolder' }
  if (it.projectId) return { href: folderHref('project', it.projectId), labelKey: 'attention.openFolder' }
  return { href: '/project-management/folders', labelKey: 'attention.openFolder' }
}

function sentence(it: AttentionItem, t: TFunction): string {
  return t(`attention.item.${it.kind}`, {
    task: it.taskTitle,
    person: it.person,
    days: it.days,
    rate: it.rate,
    progress: it.progress,
  })
}

export function AttentionView({ projectId }: AttentionViewProps) {
  const { t } = useTranslation('taskManagement')
  const { tasks, loading: tasksLoading } = useTaskContext()
  const { projects, loading: projectsLoading } = useProjectContext()
  const [folderRows, setFolderRows] = useState<FolderSourceRows | null>(null)
  const [resourceRows, setResourceRows] = useState<ResourceSourceRows | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [urgentOnly, setUrgentOnly] = useState(false)
  const [showAll, setShowAll] = useState(false)

  const month = useMemo(() => presetRange('thisMonth'), [])

  const load = useCallback(() => {
    setError(null)
    Promise.all([getFolderSourceRows(), getResourceSourceRows(month.from, month.to)])
      .then(([f, r]) => {
        setFolderRows(f)
        setResourceRows(r)
      })
      .catch((err: Error) => {
        silentFailureReporter.report({ type: 'load-failed', severity: 'error', message: `attention: ${err.message}` })
        setError(err.message)
      })
  }, [month.from, month.to])

  useEffect(() => {
    load()
  }, [load])

  const today = todayIso()

  const result = useMemo(() => {
    if (!folderRows || !resourceRows) return null
    const sources = assembleFolderSources({
      rows: folderRows,
      tasks,
      projects,
      projectId,
      noProjectLabel: t('folders.noProject'),
    })
    const usage = computeResourceUsage({
      from: month.from,
      to: month.to,
      today,
      employees: resourceRows.employees,
      tasks,
      assignments: resourceRows.assignments,
      timeEntries: resourceRows.timeEntries,
      absenceDays: resourceRows.absenceDays,
      projectNames: new Map(projects.map((p) => [p.id, p.name])),
      noProjectLabel: t('folders.noProject'),
      projectId: projectId || null,
    })
    return computeAttention({ sources, usage, today })
  }, [folderRows, resourceRows, tasks, projects, projectId, month.from, month.to, today, t])

  if (tasksLoading || projectsLoading || (!result && !error)) {
    return (
      <div className="flex items-center justify-center h-full">
        <p className="text-[var(--color-text-secondary)]">{t('loading')}</p>
      </div>
    )
  }

  if (error || !result) {
    return (
      <div className="flex flex-col items-center justify-center h-full gap-3 p-6 text-center">
        <p className="font-medium">{t('attention.loadError')}</p>
        {error && <p className="text-sm text-[var(--color-text-secondary)]">{error}</p>}
        <button
          type="button"
          onClick={load}
          className="px-3 py-1.5 text-sm rounded-lg border border-[var(--color-border)] hover:bg-[var(--color-neutral-50)]"
        >
          {t('attention.refresh')}
        </button>
      </div>
    )
  }

  const filtered = urgentOnly ? result.items.filter((i) => i.severity === 'high') : result.items
  const shown = showAll ? filtered : filtered.slice(0, VISIBLE_ITEMS)

  return (
    <div className="h-full overflow-auto p-4 space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <h2 className="text-lg font-semibold">{t('attention.title')}</h2>
          <p className="text-sm text-[var(--color-text-secondary)]">{t('attention.subtitle')}</p>
        </div>
        <button
          type="button"
          onClick={load}
          aria-label={t('attention.refresh')}
          title={t('attention.refresh')}
          className="flex items-center justify-center w-8 h-8 rounded-lg border border-[var(--color-border)] hover:bg-[var(--color-neutral-50)]"
        >
          <RefreshCw className="w-4 h-4" />
        </button>
      </div>

      {/* Le compte des feux */}
      <div className="grid gap-3 grid-cols-2 lg:grid-cols-4">
        <Tile label={t('attention.health.red')} value={result.counts.red} color={HEALTH_STYLE.red.dot} icon={<AlertOctagon className="w-4 h-4" />} />
        <Tile label={t('attention.health.amber')} value={result.counts.amber} color={HEALTH_STYLE.amber.dot} icon={<AlertTriangle className="w-4 h-4" />} />
        <Tile label={t('attention.health.green')} value={result.counts.green} color={HEALTH_STYLE.green.dot} icon={<CheckCircle2 className="w-4 h-4" />} />
        <Tile
          label={t('attention.toProcess')}
          value={result.counts.items}
          hint={t('attention.urgentCount', { count: result.counts.high })}
        />
      </div>

      {result.projects.length === 0 && result.items.length === 0 ? (
        <div className="flex flex-col items-center justify-center gap-2 py-12 text-center">
          <CheckCircle2 className="w-12 h-12 text-green-600 opacity-70" aria-hidden="true" />
          <p className="font-medium">{t('attention.nothing')}</p>
          <p className="text-sm text-[var(--color-text-secondary)]">{t('attention.nothingDesc')}</p>
        </div>
      ) : (
        <div className="grid gap-4 lg:grid-cols-[minmax(0,5fr)_minmax(0,7fr)]">
          {/* Santé de chaque projet */}
          <section aria-label={t('attention.projectsTitle')} className="space-y-2">
            <h3 className="text-sm font-semibold">{t('attention.projectsTitle')}</h3>
            {result.projects.length === 0 ? (
              <p className="text-sm text-[var(--color-text-secondary)]">{t('attention.noProjects')}</p>
            ) : (
              <ul className="space-y-2">
                {result.projects.map((p) => (
                  <li key={p.projectId}>
                    <ProjectRow project={p} t={t} />
                  </li>
                ))}
              </ul>
            )}
          </section>

          {/* Ce qui demande une action */}
          <section aria-label={t('attention.toProcess')} className="space-y-2">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <h3 className="text-sm font-semibold">
                {t('attention.toProcess')} ({filtered.length})
              </h3>
              <label className="flex items-center gap-1.5 text-xs text-[var(--color-text-secondary)] cursor-pointer">
                <input
                  type="checkbox"
                  checked={urgentOnly}
                  onChange={(e) => {
                    setUrgentOnly(e.target.checked)
                    setShowAll(false)
                  }}
                />
                {t('attention.urgentOnly')}
              </label>
            </div>
            {filtered.length === 0 ? (
              <p className="text-sm text-[var(--color-text-secondary)]">{t('attention.noItems')}</p>
            ) : (
              <ul className="divide-y divide-[var(--color-border)] rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)]">
                {shown.map((it) => (
                  <li key={it.id}>
                    <ItemRow item={it} t={t} />
                  </li>
                ))}
              </ul>
            )}
            {filtered.length > VISIBLE_ITEMS && (
              <button
                type="button"
                onClick={() => setShowAll((v) => !v)}
                className="text-sm text-[var(--color-primary)] hover:underline"
              >
                {showAll ? t('attention.showLess') : t('attention.showAll', { count: filtered.length })}
              </button>
            )}
          </section>
        </div>
      )}
    </div>
  )
}

function Tile({
  label,
  value,
  hint,
  color,
  icon,
}: {
  label: string
  value: number
  hint?: string
  color?: string
  icon?: React.ReactNode
}) {
  return (
    <div className="rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] p-3">
      <div className="flex items-center gap-1.5 text-xs text-[var(--color-text-secondary)]">
        {icon && <span style={{ color }}>{icon}</span>}
        {label}
      </div>
      <p className="text-2xl font-semibold tabular-nums" style={color ? { color } : undefined}>
        {value}
      </p>
      {hint && <p className="text-[11px] text-[var(--color-text-secondary)]">{hint}</p>}
    </div>
  )
}

function ProjectRow({ project: p, t }: { project: ProjectHealth; t: TFunction }) {
  const style = HEALTH_STYLE[p.health]
  return (
    <Link
      to={folderHref('project', p.projectId)}
      className="block rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] p-3 hover:shadow-md transition-shadow focus-visible:outline focus-visible:outline-2 focus-visible:outline-[var(--color-primary)]"
    >
      <div className="flex items-center gap-2">
        {/* le feu est dit en toutes lettres : la couleur seule ne suffit pas */}
        <span className={cn('text-[11px] font-semibold px-1.5 py-0.5 rounded-full flex items-center gap-1', style.chip)}>
          <span className="inline-block w-2 h-2 rounded-full" style={{ background: style.dot }} aria-hidden="true" />
          {t(`attention.healthLabel.${p.health}`)}
        </span>
        <span className="font-medium truncate flex-1">{p.name}</span>
        <ChevronRight className="w-4 h-4 flex-shrink-0 text-[var(--color-text-secondary)] rtl:rotate-180" aria-hidden="true" />
      </div>
      <div className="mt-2 grid grid-cols-2 gap-x-4 gap-y-1 text-xs text-[var(--color-text-secondary)]">
        <div>
          <div className="flex justify-between mb-0.5">
            <span>{t('folders.progress')}</span>
            <span className="font-semibold text-[var(--color-text)] tabular-nums">{p.progress}%</span>
          </div>
          <ProgressBar value={p.progress} color={p.color || undefined} />
        </div>
        <div>
          <div className="flex justify-between mb-0.5">
            <span>{t('folders.disbursement')}</span>
            <span className="font-semibold text-[var(--color-text)] tabular-nums">
              {p.disbursementRate === null ? '—' : `${p.disbursementRate}%`}
            </span>
          </div>
          <ProgressBar value={Math.min(p.disbursementRate ?? 0, 100)} color={p.disbursementRate !== null && p.disbursementRate > 100 ? '#dc2626' : undefined} />
        </div>
        <div className="col-span-2 flex justify-between">
          <span>{p.end ? `${t('attention.dueOn')} ${formatDate(p.end)}` : t('folders.deadline.none')}</span>
          <span>{t('attention.itemsCount', { count: p.items })}</span>
        </div>
      </div>
    </Link>
  )
}

function ItemRow({ item: it, t }: { item: AttentionItem; t: TFunction }) {
  const target = targetOf(it)
  const urgent = it.severity === 'high'
  return (
    <div className="flex items-start gap-3 px-3 py-2.5">
      <span
        className={cn(
          'mt-0.5 text-[10px] font-semibold px-1.5 py-0.5 rounded flex-shrink-0',
          urgent ? 'bg-red-50 text-red-700' : 'bg-amber-50 text-amber-700'
        )}
      >
        {t(urgent ? 'attention.urgent' : 'attention.watch')}
      </span>
      <div className="min-w-0 flex-1">
        <p className="text-sm">{sentence(it, t)}</p>
        <p className="text-xs text-[var(--color-text-secondary)] truncate">{it.projectName}</p>
      </div>
      <Link
        to={target.href}
        className="flex-shrink-0 text-xs font-medium px-2 py-1 rounded-lg border border-[var(--color-border)] hover:bg-[var(--color-neutral-50)]"
        aria-label={`${t(target.labelKey)} — ${sentence(it, t)}`}
      >
        {t(target.labelKey)}
      </Link>
    </div>
  )
}
