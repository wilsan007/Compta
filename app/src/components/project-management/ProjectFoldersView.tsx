import { useCallback, useEffect, useMemo, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import type { TFunction } from 'i18next'
import { Download, FileText, Folder, FolderOpen, Home, Paperclip, RefreshCw, Search, Users, CalendarDays, Wallet, ChevronRight } from 'lucide-react'
import { cn, formatCurrency, formatDate } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import { silentFailureReporter } from '@/lib/silentFailureGuard'
import { useTaskContext } from '@/contexts/TaskContext'
import { useProjectContext } from '@/contexts/ProjectContext'
import { getFolderSourceRows, type FolderSourceRows } from '@/lib/queries/projectFolders'
import { downloadProjectFile } from '@/lib/queries/projectManagement'
import {
  NO_PROJECT_FOLDER,
  assembleFolderSources,
  documentsOf,
  filterFolders,
  folderTrail,
  listFolders,
  summarizeFolder,
  type DeadlineState,
  type FolderRef,
  type FolderSources,
  type FolderSummary,
} from '@/lib/projectFolders'
import { ProgressBar } from './ProgressBar'

interface ProjectFoldersViewProps {
  projectId?: string
}

const DEADLINE_STYLE: Record<DeadlineState, string> = {
  none: 'bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]',
  done: 'bg-green-50 text-green-700',
  late: 'bg-red-50 text-red-700',
  soon: 'bg-amber-50 text-amber-700',
  ontrack: 'bg-blue-50 text-blue-700',
}

// L'adresse garde le dossier ouvert (`?dossier=task:<id>`) : retour arrière, lien partagé.
const parseRef = (raw: string | null): FolderRef | null => {
  if (!raw) return null
  const [kind, ...rest] = raw.split(':')
  const id = rest.join(':')
  if ((kind !== 'project' && kind !== 'task') || !id) return null
  return { kind, id }
}
const refParam = (r: FolderRef): string => `${r.kind}:${r.id}`

const formatSize = (bytes: number | null): string => {
  if (!bytes || bytes <= 0) return ''
  if (bytes < 1024) return `${bytes} o`
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} Ko`
  return `${(bytes / (1024 * 1024)).toFixed(1)} Mo`
}

const initials = (name: string): string =>
  name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((w) => w.charAt(0).toUpperCase())
    .join('')

export function ProjectFoldersView({ projectId }: ProjectFoldersViewProps) {
  const { t } = useTranslation('taskManagement')
  const { toast } = useToast()
  const { tasks, loading: tasksLoading } = useTaskContext()
  const { projects, loading: projectsLoading } = useProjectContext()
  const [params, setParams] = useSearchParams()
  const [rows, setRows] = useState<FolderSourceRows | null>(null)
  const [rowsError, setRowsError] = useState<string | null>(null)
  const [query, setQuery] = useState('')

  const load = useCallback(() => {
    setRowsError(null)
    getFolderSourceRows()
      .then(setRows)
      .catch((err: Error) => {
        silentFailureReporter.report({ type: 'load-failed', severity: 'error', message: `getFolderSourceRows: ${err.message}` })
        setRowsError(err.message)
      })
  }, [])

  useEffect(() => {
    load()
  }, [load])

  const open = parseRef(params.get('dossier'))
  const setOpen = (ref: FolderRef | null) => {
    const next = new URLSearchParams(params)
    if (ref) next.set('dossier', refParam(ref))
    else next.delete('dossier')
    setParams(next)
    setQuery('')
  }

  const sources = useMemo<FolderSources | null>(
    () =>
      rows
        ? assembleFolderSources({ rows, tasks, projects, projectId, noProjectLabel: t('folders.noProject') })
        : null,
    [rows, tasks, projects, projectId, t]
  )

  const folders = useMemo(() => (sources ? listFolders(sources, open) : []), [sources, open])
  const visible = useMemo(() => filterFolders(folders, query), [folders, query])
  const current = useMemo(() => (sources && open ? summarizeFolder(sources, open) : null), [sources, open])
  const trail = useMemo(() => (sources ? folderTrail(sources, open) : []), [sources, open])
  const documents = useMemo(() => (sources && open ? documentsOf(sources, open) : []), [sources, open])

  const nameOf = useCallback(
    (ref: FolderRef): string => {
      if (!sources) return ''
      return summarizeFolder(sources, ref)?.name || ''
    },
    [sources]
  )

  const download = async (doc: { file_path: string; file_name: string }) => {
    try {
      const blob = await downloadProjectFile(doc.file_path)
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = doc.file_name
      a.click()
      setTimeout(() => URL.revokeObjectURL(url), 1000)
    } catch (e) {
      toast('error', t('folders.downloadFailed'), (e as Error).message)
    }
  }

  if (tasksLoading || projectsLoading || (!rows && !rowsError)) {
    return (
      <div className="flex items-center justify-center h-full">
        <p className="text-[var(--color-text-secondary)]">{t('loading')}</p>
      </div>
    )
  }

  if (rowsError || !sources) {
    return (
      <div className="flex flex-col items-center justify-center h-full gap-3 p-6 text-center">
        <p className="font-medium text-[var(--color-text)]">{t('folders.loadError')}</p>
        {rowsError && <p className="text-sm text-[var(--color-text-secondary)]">{rowsError}</p>}
        <button
          type="button"
          onClick={load}
          className="px-3 py-1.5 text-sm rounded-lg border border-[var(--color-border)] hover:bg-[var(--color-neutral-50)]"
        >
          {t('folders.refresh')}
        </button>
      </div>
    )
  }

  return (
    <div className="h-full overflow-auto p-4 space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="min-w-0">
          <h2 className="text-lg font-semibold">{t('folders.title')}</h2>
          <p className="text-sm text-[var(--color-text-secondary)]">{t('folders.subtitle')}</p>
        </div>
        <div className="flex items-center gap-2">
          <label className="relative">
            <span className="sr-only">{t('folders.search')}</span>
            <Search className="absolute start-2.5 top-2 w-4 h-4 text-[var(--color-text-secondary)]" aria-hidden="true" />
            <input
              type="search"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder={t('folders.search')}
              className="ps-8 pe-3 py-1.5 text-sm rounded-lg border border-[var(--color-border)] bg-[var(--color-surface)] w-64 max-w-full"
            />
          </label>
          <button
            type="button"
            onClick={load}
            aria-label={t('folders.refresh')}
            title={t('folders.refresh')}
            className="flex items-center justify-center w-8 h-8 rounded-lg border border-[var(--color-border)] hover:bg-[var(--color-neutral-50)]"
          >
            <RefreshCw className="w-4 h-4" />
          </button>
        </div>
      </div>

      {/* Fil d'Ariane : on remonte d'un clic */}
      <nav aria-label={t('folders.trail')} className="flex flex-wrap items-center gap-1 text-sm">
        <button
          type="button"
          onClick={() => setOpen(null)}
          className={cn(
            'flex items-center gap-1 rounded px-1.5 py-0.5 hover:bg-[var(--color-neutral-100)]',
            !open && 'font-semibold text-[var(--color-text)]'
          )}
          aria-current={!open ? 'page' : undefined}
        >
          <Home className="w-3.5 h-3.5" aria-hidden="true" />
          {t('folders.root')}
        </button>
        {trail.map((ref, i) => {
          const last = i === trail.length - 1
          return (
            <span key={`${ref.kind}:${ref.id}`} className="flex items-center gap-1 min-w-0">
              <ChevronRight className="w-3.5 h-3.5 text-[var(--color-text-secondary)] rtl:rotate-180" aria-hidden="true" />
              <button
                type="button"
                onClick={() => setOpen(ref)}
                className={cn(
                  'rounded px-1.5 py-0.5 truncate max-w-[16rem] hover:bg-[var(--color-neutral-100)]',
                  last && 'font-semibold text-[var(--color-text)]'
                )}
                aria-current={last ? 'page' : undefined}
              >
                {nameOf(ref) || (ref.id === NO_PROJECT_FOLDER ? t('folders.noProject') : '…')}
              </button>
            </span>
          )
        })}
      </nav>

      {/* Résumé du dossier ouvert */}
      {current && (
        <section aria-label={t('folders.openFolder')} className="rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] p-4">
          <FolderFacts folder={current} t={t} />
        </section>
      )}

      {/* Sous-dossiers */}
      {visible.length > 0 ? (
        <ul className="grid gap-3 grid-cols-1 md:grid-cols-2 xl:grid-cols-3">
          {visible.map((f) => (
            <li key={`${f.kind}:${f.id}`}>
              <FolderCard folder={f} onOpen={() => setOpen({ kind: f.kind, id: f.id })} t={t} />
            </li>
          ))}
        </ul>
      ) : (
        <div className="flex flex-col items-center justify-center gap-2 py-12 text-center">
          <Folder className="w-12 h-12 text-[var(--color-text-secondary)] opacity-50" aria-hidden="true" />
          <p className="font-medium text-[var(--color-text)]">
            {query ? t('folders.noMatch') : open ? t('folders.emptyFolder') : t('folders.empty')}
          </p>
          {!query && !open && <p className="text-sm text-[var(--color-text-secondary)]">{t('folders.emptyDesc')}</p>}
        </div>
      )}

      {/* Documents posés sur le dossier ouvert */}
      {open?.kind === 'task' && (
        <section aria-label={t('folders.documents')} className="space-y-2">
          <h3 className="flex items-center gap-2 text-sm font-semibold">
            <FileText className="w-4 h-4" aria-hidden="true" />
            {t('folders.documents')} ({documents.length})
          </h3>
          {documents.length === 0 ? (
            <p className="text-sm text-[var(--color-text-secondary)]">{t('folders.noDocuments')}</p>
          ) : (
            <ul className="divide-y divide-[var(--color-border)] rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)]">
              {documents.map((d) => (
                <li key={`${d.kind}:${d.id}`} className="flex items-center gap-3 px-3 py-2">
                  {d.kind === 'proof' ? (
                    <Paperclip className="w-4 h-4 flex-shrink-0 text-[var(--color-text-secondary)]" aria-hidden="true" />
                  ) : (
                    <FileText className="w-4 h-4 flex-shrink-0 text-[var(--color-text-secondary)]" aria-hidden="true" />
                  )}
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium">{d.file_name}</p>
                    <p className="text-xs text-[var(--color-text-secondary)]">
                      {formatDate(d.created_at)}
                      {formatSize(d.file_size) && ` · ${formatSize(d.file_size)}`}
                    </p>
                  </div>
                  {d.kind === 'proof' && (
                    <span className="text-[10px] font-semibold px-1.5 py-0.5 rounded bg-purple-50 text-purple-700">
                      {t('folders.proof')}
                    </span>
                  )}
                  <button
                    type="button"
                    onClick={() => download(d)}
                    aria-label={t('folders.download', { name: d.file_name })}
                    title={t('folders.download', { name: d.file_name })}
                    className="flex items-center justify-center w-8 h-8 rounded hover:bg-[var(--color-neutral-100)]"
                  >
                    <Download className="w-4 h-4" />
                  </button>
                </li>
              ))}
            </ul>
          )}
        </section>
      )}
    </div>
  )
}

type TFn = TFunction

function deadlineLabel(f: FolderSummary, t: TFn): string {
  switch (f.deadline) {
    case 'late':
      return t('folders.deadline.late', { days: Math.abs(f.daysLeft ?? 0) })
    case 'soon':
      return t('folders.deadline.soon', { days: f.daysLeft ?? 0 })
    default:
      return t(`folders.deadline.${f.deadline}`)
  }
}

// Une couleur qui dit où en est le décaissement par rapport au budget.
function rateColor(rate: number): string {
  if (rate > 100) return '#dc2626'
  if (rate >= 80) return '#d97706'
  return '#16a34a'
}

function FolderCard({ folder: f, onOpen, t }: { folder: FolderSummary; onOpen: () => void; t: TFn }) {
  // Toute la carte ouvre le dossier (le bouton du titre s'étire sur elle) ; le
  // contenu de la carte reste du texte simple, lisible au lecteur d'écran.
  return (
    <div className="relative rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] p-4 space-y-3 transition-shadow hover:shadow-md focus-within:outline focus-within:outline-2 focus-within:outline-[var(--color-primary)]">
      <div className="flex items-start gap-3">
        <FolderOpen
          className="w-8 h-8 flex-shrink-0"
          style={{ color: f.color || 'var(--color-primary)' }}
          aria-hidden="true"
        />
        <div className="min-w-0 flex-1">
          <button
            type="button"
            onClick={onOpen}
            aria-label={t('folders.open', { name: f.name })}
            className="block max-w-full truncate text-start font-semibold after:absolute after:inset-0 after:content-[''] focus:outline-none"
          >
            {f.name}
          </button>
          <p className="flex flex-wrap gap-x-2 text-xs text-[var(--color-text-secondary)]">
            <span className="whitespace-nowrap font-medium">{t(`folders.kind.${f.kind}`)}</span>
            <span className="whitespace-nowrap">{t('folders.subfoldersCount')} {f.subfolders}</span>
            <span className="whitespace-nowrap">{t('folders.documents')} : {f.documents}</span>
          </p>
        </div>
      </div>
      <FolderFacts folder={f} t={t} compact />
    </div>
  )
}

function FolderFacts({ folder: f, t, compact = false }: { folder: FolderSummary; t: TFn; compact?: boolean }) {
  const shown = f.people.slice(0, 4)
  return (
    <div className={cn('space-y-2.5 text-sm', !compact && 'grid gap-4 md:grid-cols-2 space-y-0')}>
      {!compact && (
        <div className="md:col-span-2 flex items-center gap-2">
          <FolderOpen className="w-6 h-6" style={{ color: f.color || 'var(--color-primary)' }} aria-hidden="true" />
          <h3 className="font-semibold truncate">{f.name}</h3>
          <span className="flex flex-wrap gap-x-2 text-xs text-[var(--color-text-secondary)]">
            <span className="whitespace-nowrap">{t('folders.subfoldersCount')} {f.subfolders}</span>
            <span className="whitespace-nowrap">{t('folders.tasksCount')} {f.tasks}</span>
            <span className="whitespace-nowrap">{t('folders.documents')} : {f.documents}</span>
          </span>
        </div>
      )}

      {/* Personnes en charge */}
      <div className="flex items-center gap-2">
        <Users className="w-4 h-4 flex-shrink-0 text-[var(--color-text-secondary)]" aria-hidden="true" />
        {f.people.length === 0 ? (
          <span className="text-[var(--color-text-secondary)]">{t('folders.noPeople')}</span>
        ) : (
          <div className="flex items-center gap-1.5 min-w-0">
            <div className="flex -space-x-1.5 rtl:space-x-reverse">
              {shown.map((p) => (
                <span
                  key={p}
                  className="flex items-center justify-center w-6 h-6 rounded-full text-[10px] font-semibold bg-[var(--color-primary)] text-white ring-2 ring-[var(--color-surface)]"
                  aria-hidden="true"
                >
                  {initials(p)}
                </span>
              ))}
            </div>
            <span className="truncate text-[var(--color-text)]">
              {f.people.slice(0, 2).join(', ')}
              {f.people.length > 2 && ` +${f.people.length - 2}`}
            </span>
          </div>
        )}
      </div>

      {/* Délai prévu */}
      <div className="flex items-center gap-2 flex-wrap">
        <CalendarDays className="w-4 h-4 flex-shrink-0 text-[var(--color-text-secondary)]" aria-hidden="true" />
        <span>
          {f.start || f.end
            ? `${f.start ? formatDate(f.start) : '…'} → ${f.end ? formatDate(f.end) : '…'}`
            : t('folders.deadline.none')}
        </span>
        {f.end && (
          <span className={cn('text-[11px] font-medium px-1.5 py-0.5 rounded-full', DEADLINE_STYLE[f.deadline])}>
            {deadlineLabel(f, t)}
          </span>
        )}
      </div>

      {/* Budget et taux de décaissement */}
      <div className="space-y-1">
        <div className="flex items-center gap-2">
          <Wallet className="w-4 h-4 flex-shrink-0 text-[var(--color-text-secondary)]" aria-hidden="true" />
          {f.budget > 0 ? (
            <span>
              {t('folders.budget')} {formatCurrency(f.budget)} · {t('folders.spent')} {formatCurrency(f.spent)}
            </span>
          ) : (
            <span className="text-[var(--color-text-secondary)]">
              {t('folders.noBudget')}
              {f.spent > 0 && ` · ${t('folders.spent')} ${formatCurrency(f.spent)}`}
            </span>
          )}
        </div>
        {f.budget > 0 && f.disbursementRate !== null && (
          <div title={t('folders.spentBreakdown', { material: formatCurrency(f.spentMaterial), time: formatCurrency(f.spentTime) })}>
            <div className="flex items-center justify-between text-xs text-[var(--color-text-secondary)] mb-0.5">
              <span>{t('folders.disbursement')}</span>
              <span className="font-semibold tabular-nums" style={{ color: rateColor(f.disbursementRate) }}>
                {f.disbursementRate}%
              </span>
            </div>
            <ProgressBar value={Math.min(f.disbursementRate, 100)} color={rateColor(f.disbursementRate)} />
          </div>
        )}
      </div>

      {/* Avancement */}
      <div>
        <div className="flex items-center justify-between text-xs text-[var(--color-text-secondary)] mb-0.5">
          <span>{t('folders.progress')}</span>
          <span className="font-semibold tabular-nums text-[var(--color-text)]">{f.progress}%</span>
        </div>
        <ProgressBar value={f.progress} color={f.color || undefined} />
      </div>
    </div>
  )
}
