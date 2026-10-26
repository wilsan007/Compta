/* oxlint-disable react/only-export-components -- la barre et sa fonction de filtrage vont ensemble */
import { useRef, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { AlertCircle, Calendar, CheckCircle2, Clock, Filter, Flag, FolderKanban, Search, User, X } from 'lucide-react'
import { cn } from '@/lib/utils'
import type { ProjectTask, TaskFilters, TaskPriority, TaskStatus } from '@/types/projectManagement'
import { Floating } from './kit'

// Recherche + filtres avancés (statut, priorité, assigné, projet, période),
// comme dans wadashaqayn. Les filtres sont mémorisés (useTaskFilters).
export function applyTaskFilters(tasks: ProjectTask[], f: TaskFilters): ProjectTask[] {
  const q = f.search.trim().toLowerCase()
  return tasks.filter((t) => {
    if (q && !t.title.toLowerCase().includes(q) && !(t.description || '').toLowerCase().includes(q)) return false
    if (f.status.length && !f.status.includes(t.status)) return false
    if (f.priority.length && !f.priority.includes(t.priority)) return false
    if (f.assignee.length && !(t.assignee_id && f.assignee.includes(t.assignee_id))) return false
    if (f.project.length && !(t.project_id && f.project.includes(t.project_id))) return false
    if (f.dateFrom && !(t.start_date && t.start_date >= f.dateFrom)) return false
    if (f.dateTo && !(t.due_date && t.due_date <= f.dateTo)) return false
    return true
  })
}

const STATUS_OPTIONS: { value: TaskStatus; icon: typeof Clock; color: string }[] = [
  { value: 'todo', icon: Clock, color: 'text-gray-500' },
  { value: 'doing', icon: AlertCircle, color: 'text-blue-500' },
  { value: 'blocked', icon: AlertCircle, color: 'text-orange-500' },
  { value: 'done', icon: CheckCircle2, color: 'text-green-500' },
]
const PRIORITY_OPTIONS: { value: TaskPriority; dot: string }[] = [
  { value: 'low', dot: 'bg-gray-300' },
  { value: 'medium', dot: 'bg-blue-300' },
  { value: 'high', dot: 'bg-orange-300' },
  { value: 'urgent', dot: 'bg-red-300' },
]

interface FilterBarProps {
  filters: TaskFilters
  setFilters: (f: TaskFilters) => void
  reset: () => void
  projects: { id: string; name: string }[]
  employees: { id: string; name: string }[]
  total: number
  filtered: number
}

export function FilterBar({ filters, setFilters, reset, projects, employees, total, filtered }: FilterBarProps) {
  const { t } = useTranslation('taskManagement')
  const [open, setOpen] = useState(false)
  const anchor = useRef<HTMLButtonElement>(null)
  const set = (patch: Partial<TaskFilters>) => setFilters({ ...filters, ...patch })
  const toggle = (key: 'status' | 'priority' | 'assignee' | 'project', v: string) => {
    const cur = filters[key] as string[]
    set({ [key]: cur.includes(v) ? cur.filter((x) => x !== v) : [...cur, v] } as Partial<TaskFilters>)
  }
  const active = filters.status.length + filters.priority.length + filters.assignee.length + filters.project.length + (filters.dateFrom ? 1 : 0) + (filters.dateTo ? 1 : 0)
  const hasAny = active > 0 || filters.search.length > 0
  const chip = (on: boolean) =>
    cn('flex h-8 items-center justify-start rounded-md border px-2 text-xs transition-colors', on ? 'border-[var(--color-primary)] bg-[var(--color-primary)] text-white' : 'border-[var(--color-border)] hover:bg-[var(--color-neutral-100)]')
  const label = 'flex items-center gap-2 text-xs font-medium'
  const sep = <div className="h-px bg-[var(--color-border)]" />

  return (
    <div className="space-y-3">
      <div className="flex flex-col gap-3 sm:flex-row">
        <div className="relative flex-1">
          <Search className="absolute top-1/2 left-3 h-4 w-4 -translate-y-1/2 text-[var(--color-text-tertiary)]" />
          <input
            value={filters.search}
            onChange={(e) => set({ search: e.target.value })}
            placeholder={t('dyn.searchPlaceholder')}
            aria-label={t('dyn.searchPlaceholder')}
            className="h-9 w-full rounded-md border border-[var(--color-border)] bg-[var(--color-surface)] px-10 text-sm outline-none focus:ring-2 focus:ring-[var(--color-primary)]"
          />
          {filters.search && (
            <button type="button" onClick={() => set({ search: '' })} className="absolute top-1/2 right-1 flex h-7 w-7 -translate-y-1/2 items-center justify-center rounded hover:bg-[var(--color-neutral-100)]" aria-label={t('dyn.reset')}>
              <X className="h-3 w-3" />
            </button>
          )}
        </div>
        <button ref={anchor} type="button" onClick={() => setOpen((o) => !o)} className="relative flex h-9 items-center rounded-md border border-[var(--color-border)] px-3 text-sm hover:bg-[var(--color-neutral-100)]">
          <Filter className="me-2 h-4 w-4" />
          {t('dyn.filters')}
          {active > 0 && <span className="ms-2 flex h-5 w-5 items-center justify-center rounded-full bg-[var(--color-danger)] text-xs text-white">{active}</span>}
        </button>
        {hasAny && (
          <button type="button" onClick={reset} className="hidden items-center rounded-md px-2 text-sm hover:bg-[var(--color-neutral-100)] sm:flex">
            <X className="me-1 h-4 w-4" />
            {t('dyn.reset')}
          </button>
        )}
      </div>
      <Floating open={open} onClose={() => setOpen(false)} anchorRef={anchor} align="end" className="w-80 p-4">
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <h3 className="text-sm font-semibold">{t('dyn.advancedFilters')}</h3>
            {hasAny && (
              <button type="button" onClick={reset} className="flex h-7 items-center rounded px-2 text-xs hover:bg-[var(--color-neutral-100)]">
                <X className="me-1 h-3 w-3" />
                {t('dyn.reset')}
              </button>
            )}
          </div>
          {sep}
          <div className="space-y-2">
            <span className={label}><CheckCircle2 className="h-3 w-3" />{t('columns.status')}</span>
            <div className="grid grid-cols-2 gap-2">
              {STATUS_OPTIONS.map((s) => {
                const Icon = s.icon
                const on = filters.status.includes(s.value)
                return (
                  <button key={s.value} type="button" onClick={() => toggle('status', s.value)} className={chip(on)} aria-pressed={on}>
                    <Icon className={cn('me-1 h-3 w-3', !on && s.color)} />
                    {t(`status.${s.value}`)}
                  </button>
                )
              })}
            </div>
          </div>
          {sep}
          <div className="space-y-2">
            <span className={label}><Flag className="h-3 w-3" />{t('columns.priority')}</span>
            <div className="grid grid-cols-2 gap-2">
              {PRIORITY_OPTIONS.map((p) => {
                const on = filters.priority.includes(p.value)
                return (
                  <button key={p.value} type="button" onClick={() => toggle('priority', p.value)} className={chip(on)} aria-pressed={on}>
                    <span className={cn('me-2 h-2 w-2 rounded-full', p.dot)} />
                    {t(`priority.${p.value}`)}
                  </button>
                )
              })}
            </div>
          </div>
          {employees.length > 0 && (
            <>
              {sep}
              <MultiPick icon={<User className="h-3 w-3" />} title={t('dyn.assignedTo')} placeholder={t('dyn.select')}
                options={employees.map((e) => ({ id: e.id, name: e.name }))} picked={filters.assignee} onToggle={(id) => toggle('assignee', id)} />
            </>
          )}
          {projects.length > 0 && (
            <>
              {sep}
              <MultiPick icon={<FolderKanban className="h-3 w-3" />} title={t('columns.project')} placeholder={t('dyn.select')}
                options={projects} picked={filters.project} onToggle={(id) => toggle('project', id)} />
            </>
          )}
          {sep}
          <div className="space-y-2">
            <span className={label}><Calendar className="h-3 w-3" />{t('dyn.period')}</span>
            <div className="grid grid-cols-2 gap-2">
              <label className="text-xs text-[var(--color-text-tertiary)]">
                {t('dyn.from')}
                <input type="date" value={filters.dateFrom} onChange={(e) => set({ dateFrom: e.target.value })} className="mt-1 h-8 w-full rounded border border-[var(--color-border)] bg-[var(--color-surface)] px-1 text-xs" />
              </label>
              <label className="text-xs text-[var(--color-text-tertiary)]">
                {t('dyn.to')}
                <input type="date" value={filters.dateTo} onChange={(e) => set({ dateTo: e.target.value })} className="mt-1 h-8 w-full rounded border border-[var(--color-border)] bg-[var(--color-surface)] px-1 text-xs" />
              </label>
            </div>
          </div>
        </div>
      </Floating>
      {hasAny && (
        <div className="flex items-center gap-2 text-sm text-[var(--color-text-secondary)]">
          <span className="rounded-full border border-[var(--color-border)] px-2.5 py-0.5 text-xs font-semibold">{t('dyn.countOf', { filtered, total })}</span>
          {filters.search && <span className="text-xs">{t('dyn.forQuery', { q: filters.search })}</span>}
        </div>
      )}
    </div>
  )
}

function MultiPick({ icon, title, placeholder, options, picked, onToggle }: {
  icon: React.ReactNode
  title: string
  placeholder: string
  options: { id: string; name: string }[]
  picked: string[]
  onToggle: (id: string) => void
}) {
  return (
    <div className="space-y-2">
      <span className="flex items-center gap-2 text-xs font-medium">{icon}{title}</span>
      <select value="" onChange={(e) => e.target.value && onToggle(e.target.value)} aria-label={title} className="h-8 w-full rounded border border-[var(--color-border)] bg-[var(--color-surface)] px-2 text-xs">
        <option value="">{placeholder}</option>
        {options.map((o) => (
          <option key={o.id} value={o.id}>{o.name}{picked.includes(o.id) ? ' ✓' : ''}</option>
        ))}
      </select>
      {picked.length > 0 && (
        <div className="flex flex-wrap gap-1">
          {picked.map((id) => (
            <span key={id} className="inline-flex items-center rounded-full bg-[var(--color-neutral-100)] px-2 py-0.5 text-xs">
              {options.find((o) => o.id === id)?.name || '—'}
              <button type="button" onClick={() => onToggle(id)} className="ms-1" aria-label={`${title} — ${options.find((o) => o.id === id)?.name || ''}`}>
                <X className="h-3 w-3" />
              </button>
            </span>
          ))}
        </div>
      )}
    </div>
  )
}
