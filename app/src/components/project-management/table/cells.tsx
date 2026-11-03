// Cellules du panneau de gauche, calquées sur le tableau de wadashaqayn :
// titre éditable (sauvegarde différée 800 ms), pastille projet, date avec
// calendrier, badges à menu, progression, documents, commentaires, menu « ⋯ ».
import { memo, useEffect, useRef, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Calendar, Check, Copy, Download, Edit, FileText, Loader2, MessageSquare, MoreHorizontal, Plus, Send, Trash2 } from 'lucide-react'
import { cn } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import { getCurrentLocale } from '@/lib/utils'
import {
  addTaskComment,
  downloadProjectFile,
  getTaskComments,
  getTaskDocuments,
  uploadTaskDocument,
} from '@/lib/queries/projectManagement'
import type { ProjectTask, TaskComment, TaskDocument } from '@/types/projectManagement'
import { Modal } from '../Modal'
import { Floating, MiniCalendar, Pill, projectInk, shortDay } from './kit'

type SaveState = 'idle' | 'saving' | 'saved' | 'error'

// ------------------------------------------------------------------ titre
export const TitleCell = memo(function TitleCell({
  value,
  color,
  number,
  depth,
  isSub,
  ghost,
  readOnly,
  onCommit,
  onAction,
}: {
  value: string
  color?: string
  number: string
  depth: number
  isSub: boolean
  ghost: boolean
  readOnly: boolean
  onCommit: (v: string) => Promise<void> | void
  onAction?: () => void
}) {
  const { t } = useTranslation('taskManagement')
  const [editing, setEditing] = useState(false)
  const [draft, setDraft] = useState(value)
  const [state, setState] = useState<SaveState>('idle')
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const inputRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    if (!editing) setDraft(value)
  }, [value, editing])
  useEffect(() => {
    if (editing) inputRef.current?.focus()
  }, [editing])
  useEffect(() => () => {
    if (timer.current) clearTimeout(timer.current)
  }, [])

  const save = async (v: string) => {
    if (v.trim() === value.trim() || !v.trim()) {
      setState('idle')
      return
    }
    setState('saving')
    try {
      await onCommit(v.trim())
      setState('saved')
      setTimeout(() => setState('idle'), 2000)
    } catch {
      setState('error')
      setTimeout(() => setState('idle'), 3000)
    }
  }

  // Une ligne fantôme ne se crée qu'à la validation (Entrée ou sortie) : créer
  // pendant la frappe ferait une tâche par pause de 800 ms.
  const schedule = (v: string) => {
    setDraft(v)
    if (ghost) return
    if (timer.current) clearTimeout(timer.current)
    timer.current = setTimeout(() => void save(v), 800)
  }
  const flush = () => {
    setEditing(false)
    if (timer.current) clearTimeout(timer.current)
    void save(draft)
    if (ghost) setDraft('')
  }

  return (
    <div
      className={cn(
        'flex items-center gap-1',
        state === 'saving' && 'bg-yellow-50/60 dark:bg-yellow-950/40',
        state === 'saved' && 'bg-green-50/60 dark:bg-green-950/40'
      )}
      style={{ paddingInlineStart: depth * 20 }}
    >
      {!ghost && onAction ? (
        <button
          type="button"
          onClick={(e) => {
            e.stopPropagation()
            onAction()
          }}
          className="flex h-6 w-6 flex-shrink-0 items-center justify-center rounded opacity-0 transition-opacity group-hover:opacity-100 hover:bg-[var(--color-neutral-100)] focus-visible:opacity-100"
          title={isSub ? t('dyn.deleteSubtask') : t('dyn.createSubtask')}
          aria-label={isSub ? t('dyn.deleteSubtask') : t('dyn.createSubtask')}
        >
          {isSub ? <Trash2 className="h-3 w-3 text-[var(--color-danger)]" /> : <Plus className="h-3 w-3" />}
        </button>
      ) : (
        <span className="w-6 flex-shrink-0" />
      )}
      {!ghost && <span className="me-1 flex-shrink-0 text-xs font-semibold tabular-nums" style={color ? { color: projectInk(color) } : undefined}>{number}</span>}
      <div className="flex min-w-0 flex-1 items-center" onClick={(e) => e.stopPropagation()}>
        {editing && !readOnly ? (
          <input
            ref={inputRef}
            value={draft}
            onChange={(e) => schedule(e.target.value)}
            onBlur={flush}
            onKeyDown={(e) => {
              if (e.key === 'Enter') inputRef.current?.blur()
              if (e.key === 'Escape') {
                if (timer.current) clearTimeout(timer.current)
                setDraft(value)
                setState('idle')
                setEditing(false)
              }
            }}
            placeholder={ghost ? t('dyn.addTaskGhost') : undefined}
            className={cn('w-full rounded bg-transparent px-1 py-1 text-sm text-[var(--color-text)] outline-none focus:bg-[var(--color-neutral-100)]', isSub ? 'font-normal' : 'font-semibold')}
            style={color ? { color: projectInk(color) } : undefined}
          />
        ) : (
          <div
            onClick={() => !readOnly && setEditing(true)}
            className={cn(
              'w-full truncate rounded px-2 py-1 transition-colors',
              !readOnly && 'cursor-text hover:bg-[color-mix(in_srgb,var(--color-primary)_6%,transparent)]',
              readOnly && 'cursor-not-allowed opacity-60',
              // code couleur : la tâche ET ses sous-tâches s'écrivent à la couleur
              // de leur projet (demandé le 25/10) ; la sous-tâche se distingue par
              // son retrait, sa taille et sa graisse, pas par une autre couleur
              isSub ? 'text-[13px]' : 'text-sm font-semibold',
              !value && 'text-[var(--color-text-tertiary)]'
            )}
            title={readOnly ? t('dyn.editNotAllowed') : value}
            style={value && color ? { color: projectInk(color) } : undefined}
          >
            {value || (ghost ? t('dyn.addTaskGhost') : t('dyn.taskNamePlaceholder'))}
          </div>
        )}
        {state === 'saving' && <Loader2 className="ms-2 h-3 w-3 animate-spin text-blue-500" />}
        {state === 'saved' && <Check className="ms-2 h-3 w-3 text-green-500" />}
      </div>
    </div>
  )
})

// ------------------------------------------------------------------ projet
// Pastille teintée de la couleur du projet (point plein, texte lisible dans les
// deux thèmes) ; « Aucun projet » en pointillés.
export function ProjectPill({ name, color }: { name: string | null; color: string }) {
  const { t } = useTranslation('taskManagement')
  if (!name) {
    return (
      <Pill className="border-dashed border-[var(--color-border)] font-normal text-[var(--color-text-tertiary)] opacity-70">
        <span className="me-1.5 h-1.5 w-1.5 rounded-full bg-[var(--color-border)]" />
        {t('dyn.noProject')}
      </Pill>
    )
  }
  return (
    <span
      className="inline-flex max-w-[150px] items-center rounded-full border px-2.5 py-0.5 text-xs font-medium"
      style={{
        backgroundColor: `color-mix(in srgb, ${color} 14%, transparent)`,
        borderColor: `color-mix(in srgb, ${color} 35%, transparent)`,
        color: projectInk(color),
      }}
      title={name}
    >
      <span className="me-1.5 h-1.5 w-1.5 flex-shrink-0 rounded-full" style={{ backgroundColor: color }} />
      <span className="truncate">{name}</span>
    </span>
  )
}

// ------------------------------------------------------------------ date
export function DateCell({
  value,
  onCommit,
  readOnly,
  small,
}: {
  value: string | null
  onCommit: (v: string) => void
  readOnly: boolean
  small: boolean
}) {
  const { t } = useTranslation('taskManagement')
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLButtonElement>(null)
  return (
    <>
      <button
        ref={ref}
        type="button"
        disabled={readOnly}
        onClick={(e) => {
          e.stopPropagation()
          setOpen(true)
        }}
        className={cn(
          'flex items-center gap-2 rounded px-2 py-1 transition-colors',
          !readOnly && 'hover:bg-[var(--color-neutral-100)]',
          readOnly && 'cursor-not-allowed opacity-60',
          open && 'bg-blue-50 ring-2 ring-blue-500 dark:bg-blue-950'
        )}
      >
        <Calendar className={cn(small ? 'h-3 w-3' : 'h-4 w-4', 'text-[var(--color-text-tertiary)]')} />
        <span className={cn(small ? 'text-xs' : 'text-sm')}>{value ? shortDay(value) : readOnly ? '-' : t('dyn.selectDate')}</span>
      </button>
      <Floating open={open} onClose={() => setOpen(false)} anchorRef={ref}>
        <MiniCalendar
          value={value}
          onSelect={(d) => {
            setOpen(false)
            if (d !== value) onCommit(d)
          }}
        />
      </Floating>
    </>
  )
}

// ------------------------------------------------------------------ badge à menu
export function BadgeSelect({
  value,
  options,
  styles,
  onCommit,
  readOnly,
  small,
}: {
  value: string
  options: { value: string; label: string }[]
  styles: Record<string, string>
  onCommit: (v: string) => void
  readOnly: boolean
  small: boolean
}) {
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLButtonElement>(null)
  const current = options.find((o) => o.value === value)
  return (
    <>
      <button
        ref={ref}
        type="button"
        disabled={readOnly}
        onClick={(e) => {
          e.stopPropagation()
          setOpen(true)
        }}
        className={cn('inline-flex rounded transition-opacity hover:opacity-80', open && 'ring-2 ring-blue-500', readOnly && 'cursor-not-allowed opacity-60')}
      >
        <Pill className={cn(styles[value], small && 'px-2 py-0.5')}>{current?.label || value}</Pill>
      </button>
      <Floating open={open} onClose={() => setOpen(false)} anchorRef={ref} className="w-48">
        {options.map((o) => (
          <button
            key={o.value}
            type="button"
            onClick={() => {
              setOpen(false)
              if (o.value !== value) onCommit(o.value)
            }}
            className="flex w-full rounded px-1 py-1 hover:bg-[var(--color-neutral-100)]"
          >
            <Pill className={cn(styles[o.value], 'w-full justify-center')}>{o.label}</Pill>
          </button>
        ))}
      </Floating>
    </>
  )
}

// ------------------------------------------------------------------ progression
export function ProgressCell({ value, color, small }: { value: number; color: string; small: boolean }) {
  return (
    <div className="flex items-center gap-2">
      <div className={cn('overflow-hidden rounded-full bg-[var(--color-neutral-100)]', small ? 'h-1 w-12' : 'h-2 w-16')}>
        <div className="h-full rounded-full transition-all" style={{ width: `${Math.min(100, Math.max(0, value))}%`, backgroundColor: color }} />
      </div>
      <span className={cn('font-medium tabular-nums', small ? 'text-xs' : 'text-sm')}>{value}%</span>
    </div>
  )
}

// ------------------------------------------------------------------ documents
export function DocumentsCell({
  task,
  count,
  small,
  canUpload,
  onChanged,
}: {
  task: ProjectTask
  count: number
  small: boolean
  canUpload: boolean
  onChanged: () => void
}) {
  const { t } = useTranslation('taskManagement')
  const { toast } = useToast()
  const [open, setOpen] = useState(false)
  const [busy, setBusy] = useState(false)
  const [docs, setDocs] = useState<TaskDocument[]>([])
  const input = useRef<HTMLInputElement>(null)

  useEffect(() => {
    if (!open) return
    getTaskDocuments(task.id)
      .then(setDocs)
      .catch((e: Error) => toast('error', t('saveError'), e.message))
  }, [open, task.id, toast, t])

  const upload = async (file: File) => {
    setBusy(true)
    try {
      await uploadTaskDocument(task.id, file, task.project_id)
      toast('success', t('dyn.uploadDone'))
      onChanged()
    } catch (e) {
      toast('error', t('dyn.uploadFailed'), (e as Error).message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="flex items-center gap-1" onClick={(e) => e.stopPropagation()}>
      {canUpload && (
        <>
          <input
            ref={input}
            type="file"
            className="hidden"
            onChange={(e) => {
              const f = e.target.files?.[0]
              e.target.value = ''
              if (f) void upload(f)
            }}
          />
          <button
            type="button"
            disabled={busy}
            onClick={() => input.current?.click()}
            className={cn('flex items-center justify-center rounded hover:bg-[var(--color-neutral-100)]', small ? 'h-6 w-6' : 'h-8 w-8')}
            aria-label={t('dyn.addDocument', { title: task.title })}
            title={t('dyn.addDocument', { title: task.title })}
          >
            {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <Plus className={small ? 'h-3 w-3' : 'h-4 w-4'} />}
          </button>
        </>
      )}
      {count > 0 && (
        <button
          type="button"
          onClick={() => setOpen(true)}
          className={cn('flex items-center rounded hover:bg-[var(--color-neutral-100)]', small ? 'h-6 px-1 text-xs' : 'h-8 px-2 text-sm')}
          aria-label={t('dyn.documentsOf', { title: task.title })}
        >
          <FileText className={cn('me-1', small ? 'h-3 w-3' : 'h-4 w-4')} />
          {count}
        </button>
      )}
      <Modal open={open} onClose={() => setOpen(false)} title={t('dyn.documentsOf', { title: task.title })} maxWidth="28rem">
        <div className="space-y-3">
          {docs.map((d) => (
            <div key={d.id} className="flex items-center justify-between rounded bg-[var(--color-neutral-50)] p-2">
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-medium">{d.file_name}</p>
                <p className="text-xs text-[var(--color-text-tertiary)]">{new Date(d.created_at).toLocaleDateString(getCurrentLocale())}</p>
              </div>
              <button
                type="button"
                className="flex h-8 w-8 items-center justify-center rounded hover:bg-[var(--color-neutral-100)]"
                aria-label={t('dyn.download', { name: d.file_name })}
                onClick={async () => {
                  try {
                    const blob = await downloadProjectFile(d.file_path)
                    const url = URL.createObjectURL(blob)
                    const a = document.createElement('a')
                    a.href = url
                    a.download = d.file_name
                    a.click()
                    setTimeout(() => URL.revokeObjectURL(url), 1000)
                  } catch (e) {
                    toast('error', t('dyn.downloadFailed'), (e as Error).message)
                  }
                }}
              >
                <Download className="h-4 w-4" />
              </button>
            </div>
          ))}
        </div>
      </Modal>
    </div>
  )
}

// ------------------------------------------------------------------ commentaires
export function CommentsCell({ task, count, small, onChanged }: { task: ProjectTask; count: number; small: boolean; onChanged: () => void }) {
  const { t } = useTranslation('taskManagement')
  const { toast } = useToast()
  const [open, setOpen] = useState(false)
  const [comments, setComments] = useState<TaskComment[]>([])
  const [draft, setDraft] = useState('')
  const [busy, setBusy] = useState(false)

  const load = () =>
    getTaskComments(task.id)
      .then((c) => setComments([...c].reverse()))
      .catch((e: Error) => toast('error', t('saveError'), e.message))

  useEffect(() => {
    if (open) void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open])

  const send = async () => {
    if (!draft.trim()) return
    setBusy(true)
    try {
      await addTaskComment(task.id, draft.trim())
      setDraft('')
      toast('success', t('dyn.commentAdded'))
      await load()
      onChanged()
    } catch (e) {
      toast('error', t('saveError'), (e as Error).message)
    } finally {
      setBusy(false)
    }
  }

  const ago = (iso: string) => {
    const s = Math.round((Date.now() - new Date(iso).getTime()) / 1000)
    const rtf = new Intl.RelativeTimeFormat(getCurrentLocale(), { numeric: 'auto' })
    if (s < 60) return rtf.format(-s, 'second')
    if (s < 3600) return rtf.format(-Math.round(s / 60), 'minute')
    if (s < 86400) return rtf.format(-Math.round(s / 3600), 'hour')
    return rtf.format(-Math.round(s / 86400), 'day')
  }

  return (
    <div onClick={(e) => e.stopPropagation()}>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className={cn('flex items-center rounded hover:bg-[var(--color-neutral-100)]', small ? 'h-6 px-1 text-xs' : 'h-8 px-2 text-sm')}
        aria-label={t('dyn.commentsOf', { title: task.title })}
      >
        <MessageSquare className={cn('me-1', small ? 'h-3 w-3' : 'h-4 w-4')} />
        {count}
      </button>
      <Modal open={open} onClose={() => setOpen(false)} title={t('dyn.commentsOf', { title: task.title })} maxWidth="32rem">
        <div className="flex h-96 flex-col">
          <div className="mb-3 flex-1 space-y-3 overflow-y-auto pe-2">
            {comments.length === 0 ? (
              <p className="text-center text-sm text-[var(--color-text-tertiary)]">{t('dyn.noComments')}</p>
            ) : (
              comments.map((c) => (
                <div key={c.id} className="rounded-md bg-[var(--color-neutral-50)] p-2">
                  <div className="mb-1 text-xs text-[var(--color-text-tertiary)]">{ago(c.created_at)}</div>
                  <div className="whitespace-pre-wrap text-sm">{c.content}</div>
                </div>
              ))
            )}
          </div>
          <div className="border-t border-[var(--color-border)] pt-3">
            <textarea
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              placeholder={t('dyn.addComment')}
              aria-label={t('dyn.addComment')}
              disabled={busy}
              className="mb-2 min-h-[60px] w-full resize-none rounded border border-[var(--color-border)] bg-[var(--color-surface)] p-2 text-sm outline-none focus:border-[var(--color-primary)]"
            />
            <button
              type="button"
              onClick={send}
              disabled={!draft.trim() || busy}
              className="flex w-full items-center justify-center gap-1 rounded-lg bg-[var(--color-primary)] px-3 py-1.5 text-sm text-white disabled:opacity-50"
            >
              <Send className="h-3 w-3" />
              {busy ? t('dyn.sending') : t('dyn.send')}
            </button>
          </div>
        </div>
      </Modal>
    </div>
  )
}

// ------------------------------------------------------------------ menu « ⋯ »
export function RowMenu({
  onEdit,
  onDuplicate,
  onDelete,
  canDelete,
}: {
  onEdit: () => void
  onDuplicate: () => void
  onDelete: () => void
  canDelete: boolean
}) {
  const { t } = useTranslation('taskManagement')
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLButtonElement>(null)
  const item = 'flex w-full items-center gap-2 rounded px-2 py-1.5 text-sm hover:bg-[var(--color-neutral-100)]'
  return (
    <>
      <button
        ref={ref}
        type="button"
        onClick={(e) => {
          e.stopPropagation()
          setOpen(true)
        }}
        className="flex h-8 w-8 items-center justify-center rounded hover:bg-[var(--color-neutral-100)]"
        aria-label={t('columns.actions')}
      >
        <MoreHorizontal className="h-4 w-4" />
      </button>
      <Floating open={open} onClose={() => setOpen(false)} anchorRef={ref} align="end" className="w-44">
        <button type="button" className={item} onClick={() => { setOpen(false); onEdit() }}>
          <Edit className="h-4 w-4" />
          {t('actions.edit')}
        </button>
        <button type="button" className={item} onClick={() => { setOpen(false); onDuplicate() }}>
          <Copy className="h-4 w-4" />
          {t('actions.duplicate')}
        </button>
        {canDelete && (
          <button type="button" className={cn(item, 'text-[var(--color-danger)]')} onClick={() => { setOpen(false); onDelete() }}>
            <Trash2 className="h-4 w-4" />
            {t('actions.delete')}
          </button>
        )}
      </Floating>
    </>
  )
}
