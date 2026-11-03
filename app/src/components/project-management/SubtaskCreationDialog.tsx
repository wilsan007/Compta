import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Link2, ListChecks, Plus, Shuffle, Trash2, User } from 'lucide-react'
import { getEmployeesShared } from '@/lib/employeesShared'
import type { Employee } from '@/types'
import type { ProjectTask, TaskAction } from '@/types/projectManagement'
import { Modal } from './Modal'
import { Button } from '@/components/ui'

export interface SubtaskDraftAction {
  key: string
  title: string
  weight: number
  due_date: string | null
  notes: string | null
}

export interface SubtaskDraft {
  title: string
  start_date: string | null
  due_date: string | null
  effort_estimate_h: number
  assignee_id: string | null
  assignee: string | null
  linked_action_id: string | null
  actions: SubtaskDraftAction[]
}

interface SubtaskCreationDialogProps {
  parent: ProjectTask | null
  parentActions: TaskAction[]
  onClose: () => void
  onConfirm: (draft: SubtaskDraft) => Promise<void>
}

// Poids répartis à parts égales, le reste sur la première action : la somme fait 100.
function spread(actions: SubtaskDraftAction[]): SubtaskDraftAction[] {
  if (actions.length === 0) return actions
  const base = Math.floor(100 / actions.length)
  const rest = 100 - base * actions.length
  return actions.map((a, i) => ({ ...a, weight: i === 0 ? base + rest : base }))
}

// Création d'une sous-tâche, comme dans wadashaqayn : titre, dates (dans la
// période de la mère), charge, responsable (hérité), liaison à une action de la
// mère (la sous-tâche en donne alors l'avancement), et ses propres actions.
export function SubtaskCreationDialog({ parent, parentActions, onClose, onConfirm }: SubtaskCreationDialogProps) {
  const { t } = useTranslation('taskManagement')
  const { t: tCommon } = useTranslation('common')
  const [employees, setEmployees] = useState<Employee[]>([])
  const [title, setTitle] = useState('')
  const [start, setStart] = useState('')
  const [due, setDue] = useState('')
  const [effort, setEffort] = useState(1)
  const [assignee, setAssignee] = useState('')
  const [linked, setLinked] = useState('')
  const [actions, setActions] = useState<SubtaskDraftAction[]>([])
  const [newTitle, setNewTitle] = useState('')
  const [newDue, setNewDue] = useState('')
  const [newNotes, setNewNotes] = useState('')
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    if (!parent) return
    setTitle(t('dyn.subtaskOf', { title: parent.title }))
    setStart(parent.start_date || '')
    setDue(parent.due_date || '')
    setEffort(1)
    setAssignee(parent.assignee_id || '')
    setLinked('')
    setActions([])
    getEmployeesShared().then(setEmployees).catch(() => setEmployees([]))
  }, [parent, t])

  const addAction = () => {
    if (!newTitle.trim()) return
    setActions((a) => spread([...a, { key: `${Date.now()}`, title: newTitle.trim().slice(0, 40), weight: 0, due_date: newDue || null, notes: newNotes.trim() || null }]))
    setNewTitle('')
    setNewDue('')
    setNewNotes('')
  }

  const confirm = async () => {
    if (!title.trim() || !parent) return
    setBusy(true)
    try {
      const emp = employees.find((e) => e.id === assignee)
      await onConfirm({
        title: title.trim(),
        start_date: start || null,
        due_date: due || null,
        effort_estimate_h: effort,
        assignee_id: assignee || null,
        assignee: emp?.name || null,
        linked_action_id: linked || null,
        actions,
      })
      onClose()
    } finally {
      setBusy(false)
    }
  }

  const field = 'w-full rounded border border-[var(--color-border)] bg-[var(--color-surface)] px-3 py-2 text-sm outline-none focus:border-[var(--color-primary)]'
  const lab = 'mb-1 block text-sm font-medium'
  const total = actions.reduce((s, a) => s + a.weight, 0)

  return (
    <Modal
      open={!!parent}
      onClose={onClose}
      title={t('subtask.title')}
      maxWidth="44rem"
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>{tCommon('common.cancel')}</Button>
          <Button onClick={confirm} disabled={!title.trim() || busy} loading={busy}>{t('dyn.createSubtaskBtn')}</Button>
        </>
      }
    >
      {parent && (
        <div className="space-y-4">
          <div>
            <label className={lab} htmlFor="st-title">{t('dyn.subtaskTitle')}</label>
            <input id="st-title" value={title} onChange={(e) => setTitle(e.target.value)} maxLength={100} placeholder={t('dyn.subtaskTitlePlaceholder')} className={field} autoFocus />
          </div>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
            <div>
              <label className={lab} htmlFor="st-start">{t('dyn.col.start')}</label>
              <input id="st-start" type="date" value={start} min={parent.start_date || undefined} max={parent.due_date || undefined} onChange={(e) => setStart(e.target.value)} className={field} />
            </div>
            <div>
              <label className={lab} htmlFor="st-due">{t('dyn.col.due')}</label>
              <input id="st-due" type="date" value={due} min={start || parent.start_date || undefined} max={parent.due_date || undefined} onChange={(e) => setDue(e.target.value)} className={field} />
            </div>
            <div>
              <label className={lab} htmlFor="st-effort">{t('dyn.effortHours')}</label>
              <input id="st-effort" type="number" min={0.5} step={0.5} value={effort} onChange={(e) => setEffort(Number(e.target.value) || 0)} className={field} />
            </div>
          </div>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <div>
              <label className={`${lab} flex items-center gap-2`} htmlFor="st-assignee"><User className="h-4 w-4" />{t('dyn.col.assignee')}</label>
              <select id="st-assignee" value={assignee} onChange={(e) => setAssignee(e.target.value)} className={field}>
                <option value="">{t('dyn.unassigned')}</option>
                {employees.map((e) => <option key={e.id} value={e.id}>{e.name}</option>)}
              </select>
            </div>
            <div>
              <label className={`${lab} flex items-center gap-2`} htmlFor="st-link"><Link2 className="h-4 w-4" />{t('dyn.linkToAction')}</label>
              <select id="st-link" value={linked} onChange={(e) => setLinked(e.target.value)} className={field}>
                <option value="">{t('dyn.noLink')}</option>
                {parentActions.map((a) => <option key={a.id} value={a.id}>{a.title} ({a.weight_percentage}%)</option>)}
              </select>
            </div>
          </div>
          <div className="rounded-lg bg-[var(--color-neutral-50)] p-3 text-sm">
            <p><strong>{t('dyn.parentTask')} :</strong> {parent.title}</p>
            <p><strong>{t('dyn.inheritedAssignee')} :</strong> {parent.assignee || t('dyn.unassigned')}</p>
          </div>

          <div className="space-y-3 rounded-lg border border-[var(--color-border)] p-3">
            <div className="flex items-center justify-between">
              <span className="flex items-center gap-2 text-base font-semibold"><ListChecks className="h-4 w-4" />{t('dyn.subtaskActions', { count: actions.length })}</span>
              {actions.length > 1 && (
                <button type="button" onClick={() => setActions((a) => spread(a))} className="flex items-center gap-1 rounded px-2 py-1 text-xs hover:bg-[var(--color-neutral-100)]">
                  <Shuffle className="h-3 w-3" />{t('dyn.redistribute')}
                </button>
              )}
            </div>
            {actions.length > 0 && (
              <div className="max-h-32 space-y-2 overflow-y-auto">
                {actions.map((a) => (
                  <div key={a.key} className="flex items-center justify-between rounded bg-[var(--color-neutral-50)] px-2 py-1 text-sm">
                    <span className="truncate">{a.title}</span>
                    <span className="flex items-center gap-2">
                      <span className="rounded-full border border-[var(--color-border)] px-2 text-xs font-semibold">{a.weight}%</span>
                      <button type="button" onClick={() => setActions((x) => spread(x.filter((y) => y.key !== a.key)))} aria-label={`${t('actions.delete')} ${a.title}`}>
                        <Trash2 className="h-3 w-3 text-[var(--color-danger)]" />
                      </button>
                    </span>
                  </div>
                ))}
                <p className="text-right text-xs text-[var(--color-text-tertiary)]">{t('dyn.weightTotal', { total })}</p>
              </div>
            )}
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
              <input value={newTitle} onChange={(e) => setNewTitle(e.target.value)} maxLength={40} placeholder={t('action.namePlaceholder')} aria-label={t('action.name')} className={field}
                onKeyDown={(e) => e.key === 'Enter' && addAction()} />
              <input type="date" value={newDue} min={start || undefined} max={due || undefined} onChange={(e) => setNewDue(e.target.value)} aria-label={t('action.dueDate')} className={field} />
              <input value={newNotes} onChange={(e) => setNewNotes(e.target.value)} placeholder={t('action.notesPlaceholder')} aria-label={t('action.notes')} className={field} />
            </div>
            <button type="button" onClick={addAction} disabled={!newTitle.trim()} className="flex items-center gap-1 rounded border border-[var(--color-border)] px-3 py-1.5 text-sm hover:bg-[var(--color-neutral-100)] disabled:opacity-50">
              <Plus className="h-4 w-4" />{t('dyn.addAction')}
            </button>
          </div>
        </div>
      )}
    </Modal>
  )
}
