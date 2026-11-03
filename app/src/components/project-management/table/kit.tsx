/* oxlint-disable react/only-export-components -- petites briques et constantes d'apparence du tableau, exportées ensemble */
// Briques d'apparence du tableau dynamique, calquées sur celles de wadashaqayn
// (badges de priorité et de statut, avatar à initiales, mini-calendrier,
// fenêtre flottante contrôlée).
import { useEffect, useLayoutEffect, useRef, useState, type ReactNode, type RefObject } from 'react'
import { createPortal } from 'react-dom'
import { ChevronLeft, ChevronRight } from 'lucide-react'
import { cn } from '@/lib/utils'
import { formatDay, parseDay } from '@/lib/dayMath'
import { getCurrentLocale } from '@/lib/utils'

// Hauteurs de ligne : les DEUX panneaux posent les mêmes, c'est ce qui les aligne.
export const ROW_H = 64
export const SUB_ROW_H = 51
export const BAND_H = 44
export const HEAD_H = 52
// Le tableau occupe toute la hauteur d'écran restante (barre de l'application,
// barre d'outils et filtres déduites), 420 px au moins.
export const PANEL_H = 'max(420px, calc(100dvh - 290px))'

// En-tête des deux panneaux : une bande PLEINE à la couleur principale, texte
// blanc, pour que les intitulés tranchent nettement sur le contenu (demandé le
// 25/10 — le fond neutre se confondait avec les lignes). Une seule couleur, pas
// de dégradé.
export const HEADER_ROW = 'bg-[color-mix(in_srgb,var(--color-primary)_88%,black)]'
export const HEADER_CELL = 'border-b border-black/20 text-xs font-semibold uppercase tracking-wide text-white'

// Encre d'une couleur de projet : la couleur, rapprochée du texte du thème
// (éclaircie en sombre, assombrie en clair) pour rester lisible dans les deux.
export function projectInk(color: string): string {
  return `color-mix(in srgb, ${color} 80%, var(--color-text))`
}

export const PRIORITY_STYLE: Record<string, string> = {
  low: 'bg-emerald-500/10 text-emerald-700 border-emerald-500/30 dark:text-emerald-300',
  medium: 'bg-amber-500/10 text-amber-700 border-amber-500/30 dark:text-amber-300',
  high: 'bg-sky-500/10 text-sky-700 border-sky-500/30 dark:text-sky-300',
  urgent: 'bg-red-500/10 text-red-700 border-red-500/30 dark:text-red-300',
}

export const STATUS_STYLE: Record<string, string> = {
  todo: 'bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)] border-[var(--color-border)]',
  doing: 'bg-blue-500/10 text-blue-700 border-blue-500/30 dark:text-blue-300',
  blocked: 'bg-red-500/10 text-red-700 border-red-500/30 dark:text-red-300',
  changes_requested: 'bg-orange-500/10 text-orange-700 border-orange-500/30 dark:text-orange-300',
  approved: 'bg-teal-500/10 text-teal-700 border-teal-500/30 dark:text-teal-300',
  done: 'bg-emerald-500/10 text-emerald-700 border-emerald-500/30 dark:text-emerald-300',
  canceled: 'bg-gray-500/10 text-gray-600 border-gray-500/30 dark:text-gray-300',
}

export function Pill({ className, children }: { className?: string; children: ReactNode }) {
  return (
    <span className={cn('inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-semibold whitespace-nowrap', className)}>
      {children}
    </span>
  )
}

export function Initials({ name, size = 24 }: { name: string; size?: number }) {
  return (
    <span
      className="inline-flex flex-shrink-0 items-center justify-center rounded-full bg-[color-mix(in_srgb,var(--color-primary)_20%,transparent)] text-xs font-semibold text-[var(--color-primary)]"
      style={{ width: size, height: size }}
      aria-hidden="true"
    >
      {name.slice(0, 2).toUpperCase()}
    </span>
  )
}

// Fenêtre flottante CONTRÔLÉE (le Popover maison ne se ferme pas depuis son
// contenu) : posée en position fixe sous son ancre, fermée par un clic ailleurs,
// Échap ou un défilement.
export function Floating({
  open,
  onClose,
  anchorRef,
  align = 'start',
  className,
  children,
}: {
  open: boolean
  onClose: () => void
  anchorRef: RefObject<HTMLElement | null>
  align?: 'start' | 'end'
  className?: string
  children: ReactNode
}) {
  const ref = useRef<HTMLDivElement>(null)
  const [pos, setPos] = useState<{ top: number; left: number } | null>(null)

  useLayoutEffect(() => {
    if (!open || !anchorRef.current) return
    const r = anchorRef.current.getBoundingClientRect()
    const width = ref.current?.offsetWidth || 240
    let left = align === 'end' ? r.right - width : r.left
    left = Math.max(8, Math.min(left, window.innerWidth - width - 8))
    let top = r.bottom + 4
    const height = ref.current?.offsetHeight || 0
    if (top + height > window.innerHeight - 8) top = Math.max(8, r.top - height - 4)
    setPos({ top, left })
  }, [open, align, anchorRef])

  useEffect(() => {
    if (!open) return
    const onDown = (e: MouseEvent) => {
      const t = e.target as Node
      if (ref.current?.contains(t) || anchorRef.current?.contains(t)) return
      onClose()
    }
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose()
    const onScroll = (e: Event) => {
      if (ref.current && e.target instanceof Node && ref.current.contains(e.target)) return
      onClose()
    }
    document.addEventListener('mousedown', onDown)
    document.addEventListener('keydown', onKey)
    window.addEventListener('scroll', onScroll, true)
    return () => {
      document.removeEventListener('mousedown', onDown)
      document.removeEventListener('keydown', onKey)
      window.removeEventListener('scroll', onScroll, true)
    }
  }, [open, onClose, anchorRef])

  if (!open) return null
  return createPortal(
    <div
      ref={ref}
      onClick={(e) => e.stopPropagation()}
      style={{ position: 'fixed', top: pos?.top ?? -9999, left: pos?.left ?? -9999, zIndex: 9999 }}
      className={cn('rounded-lg border border-[var(--color-border)] bg-[var(--color-surface)] p-1 shadow-lg', className)}
    >
      {children}
    </div>,
    document.body
  )
}

// Mini-calendrier (jours en heure locale, AAAA-MM-JJ) : un mois, flèches, aujourd'hui marqué.
export function MiniCalendar({ value, onSelect }: { value: string | null; onSelect: (day: string) => void }) {
  const selected = parseDay(value)
  const [month, setMonth] = useState(() => {
    const base = selected || new Date()
    return new Date(base.getFullYear(), base.getMonth(), 1)
  })
  const locale = getCurrentLocale()
  const first = (month.getDay() + 6) % 7 // lundi en premier
  const days = new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate()
  const cells: (number | null)[] = [...Array(first).fill(null), ...Array.from({ length: days }, (_, i) => i + 1)]
  const today = formatDay(new Date())
  const weekdays = Array.from({ length: 7 }, (_, i) =>
    new Date(2024, 0, 1 + i).toLocaleDateString(locale, { weekday: 'narrow' })
  )
  return (
    <div className="w-64 p-2" dir="ltr">
      <div className="mb-2 flex items-center justify-between">
        <button type="button" className="rounded p-1 hover:bg-[var(--color-neutral-100)]" onClick={() => setMonth(new Date(month.getFullYear(), month.getMonth() - 1, 1))} aria-label="‹">
          <ChevronLeft className="h-4 w-4" />
        </button>
        <span className="text-sm font-medium capitalize">{month.toLocaleDateString(locale, { month: 'long', year: 'numeric' })}</span>
        <button type="button" className="rounded p-1 hover:bg-[var(--color-neutral-100)]" onClick={() => setMonth(new Date(month.getFullYear(), month.getMonth() + 1, 1))} aria-label="›">
          <ChevronRight className="h-4 w-4" />
        </button>
      </div>
      <div className="grid grid-cols-7 gap-0.5 text-center text-[11px] text-[var(--color-text-tertiary)]">
        {weekdays.map((w, i) => <span key={i}>{w}</span>)}
      </div>
      <div className="mt-1 grid grid-cols-7 gap-0.5">
        {cells.map((d, i) => {
          if (d === null) return <span key={i} />
          const day = formatDay(new Date(month.getFullYear(), month.getMonth(), d))
          const isSel = value === day
          return (
            <button
              key={i}
              type="button"
              onClick={() => onSelect(day)}
              className={cn(
                'h-8 rounded text-sm hover:bg-[var(--color-neutral-100)]',
                isSel && 'bg-[var(--color-primary)] text-white hover:bg-[var(--color-primary)]',
                !isSel && day === today && 'font-bold text-[var(--color-primary)]'
              )}
            >
              {d}
            </button>
          )
        })}
      </div>
    </div>
  )
}

// « 10/10 » comme le tableau de wadashaqayn (jour/mois), dans la langue de l'application.
export function shortDay(value: string | null): string {
  const d = parseDay(value)
  return d ? d.toLocaleDateString(getCurrentLocale(), { day: '2-digit', month: '2-digit' }) : ''
}
