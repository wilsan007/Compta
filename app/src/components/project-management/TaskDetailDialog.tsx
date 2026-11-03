import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Edit, Eye } from 'lucide-react'
import { cn } from '@/lib/utils'
import { getEmployeesShared } from '@/lib/employeesShared'
import type { Employee } from '@/types'
import type { ProjectTask, TaskAction, TaskPriority, TaskStatus } from '@/types/projectManagement'
import { Modal } from './Modal'
import { Button } from '@/components/ui'
import { Pill, PRIORITY_STYLE, STATUS_STYLE, shortDay } from './table/kit'

interface TaskDetailDialogProps {
  task: ProjectTask | null
  subtasks: ProjectTask[]
  actions: TaskAction[]
  projects: { id: string; name: string }[]
  canEdit: boolean
  onClose: () => void
  onSave: (id: string, patch: Record<string, unknown>) => Promise<void>
}

const STATUSES: TaskStatus[] = ['todo', 'doing', 'blocked', 'changes_requested', 'approved', 'done', 'canceled']
const PRIORITIES: TaskPriority[] = ['low', 'medium', 'high', 'urgent']

// Détail d'une tâche (double-clic ou « Modifier ») : un onglet de lecture et un
// onglet d'édition, comme la fenêtre de détail de wadashaqayn.
export function TaskDetailDialog({ task, subtasks, actions, projects, canEdit, onClose, onSave }: TaskDetailDialogProps) {
  const { t } = useTranslation('taskManagement')
  const { t: tCommon } = useTranslation('common')
  const [tab, setTab] = useState<'details' | 'edit'>('details')
  const [employees, setEmployees] = useState<Employee[]>([])
  const [form, setForm] = useState<Record<string, string | number | null>>({})
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    if (!task) return
    setTab('details')
    setForm({
      title: task.title,
      description: task.description || '',
      status: task.status,
      priority: task.priority,
      start_date: task.start_date || '',
      due_date: task.due_date || '',
      effort_estimate_h: task.effort_estimate_h || 0,
      project_id: task.project_id || '',
      assignee_id: task.assignee_id || '',
    })
    getEmployeesShared().then(setEmployees).catch(() => setEmployees([]))
  }, [task])

  if (!task) return null
  const set = (k: string, v: string | number) => setForm((f) => ({ ...f, [k]: v }))
  const save = async () => {
    setBusy(true)
    try {
      const emp = employees.find((e) => e.id === form.assignee_id)
      await onSave(task.id, {
        title: String(form.title || '').trim() || task.title,
        description: form.description || null,
        status: form.status,
        priority: form.priority,
        start_date: form.start_date || null,
        due_date: form.due_date || null,
        effort_estimate_h: Number(form.effort_estimate_h) || 0,
        project_id: form.project_id || null,
        assignee_id: form.assignee_id || null,
        assignee: emp?.name || null,
      })
      onClose()
    } finally {
      setBusy(false)
    }
  }

  const field = 'w-full rounded border border-[var(--color-border)] bg-[var(--color-surface)] px-3 py-2 text-sm outline-none focus:border-[var(--color-primary)]'
  const lab = 'mb-1 block text-sm font-medium'
  const card = 'rounded-lg border border-[var(--color-border)] p-4'
  const tabBtn = (on: boolean) => cn('flex items-center gap-2 rounded-md px-3 py-1.5 text-sm', on ? 'bg-[var(--color-surface)] font-medium shadow-sm' : 'text-[var(--color-text-secondary)]')
  const project = projects.find((p) => p.id === task.project_id)

  return (
    <Modal
      open={!!task}
      onClose={onClose}
      title={task.title}
      maxWidth="44rem"
      footer={
        <>
          <Button variant="secondary" onClick={onClose} disabled={busy}>{tCommon('common.cancel')}</Button>
          {tab === 'edit' && <Button onClick={save} loading={busy} disabled={!String(form.title || '').trim()}>{t('actions.save')}</Button>}
        </>
      }
    >
      <p className="mb-3 text-sm text-[var(--color-text-secondary)]">{t('dyn.detailSubtitle')}</p>
      <div className="mb-4 inline-flex rounded-lg bg-[var(--color-neutral-100)] p-1" role="tablist">
        <button type="button" role="tab" aria-selected={tab === 'details'} className={tabBtn(tab === 'details')} onClick={() => setTab('details')}>
          <Eye className="h-4 w-4" />{t('dyn.tabDetails')}
        </button>
        {canEdit && (
          <button type="button" role="tab" aria-selected={tab === 'edit'} className={tabBtn(tab === 'edit')} onClick={() => setTab('edit')}>
            <Edit className="h-4 w-4" />{t('actions.edit')}
          </button>
        )}
      </div>

      {tab === 'details' ? (
        <div className="space-y-4">
          <div className={card}>
            <h3 className="mb-3 text-base font-medium">{t('dyn.generalInfo')}</h3>
            <dl className="grid grid-cols-2 gap-3 text-sm">
              <dt className="text-[var(--color-text-tertiary)]">{t('columns.status')}</dt>
              <dd><Pill className={STATUS_STYLE[task.status]}>{t(`status.${task.status}`)}</Pill></dd>
              <dt className="text-[var(--color-text-tertiary)]">{t('columns.priority')}</dt>
              <dd><Pill className={PRIORITY_STYLE[task.priority]}>{t(`priority.${task.priority}`)}</Pill></dd>
              <dt className="text-[var(--color-text-tertiary)]">{t('dyn.col.assignee')}</dt>
              <dd>{task.assignee || t('dyn.unassigned')}</dd>
              <dt className="text-[var(--color-text-tertiary)]">{t('dyn.col.project')}</dt>
              <dd>{project?.name || t('dyn.noProject')}</dd>
              <dt className="text-[var(--color-text-tertiary)]">{t('dyn.period')}</dt>
              <dd>{shortDay(task.start_date) || '—'} → {shortDay(task.due_date) || '—'}</dd>
              <dt className="text-[var(--color-text-tertiary)]">{t('dyn.col.effort')}</dt>
              <dd>{task.effort_estimate_h || 0} h</dd>
              <dt className="text-[var(--color-text-tertiary)]">{t('columns.progress')}</dt>
              <dd>{task.progress || 0}%</dd>
            </dl>
          </div>
          <div className={card}>
            <h3 className="mb-2 text-base font-medium">{t('dyn.description')}</h3>
            <p className="whitespace-pre-wrap text-sm text-[var(--color-text-secondary)]">{task.description || t('dyn.noDescription')}</p>
          </div>
          <div className={card}>
            <h3 className="mb-2 text-base font-medium">{t('dyn.subtasksAndActions')}</h3>
            {subtasks.length === 0 && actions.length === 0 ? (
              <p className="text-sm text-[var(--color-text-tertiary)]">{t('dyn.noSubtasksOrActions')}</p>
            ) : (
              <ul className="space-y-1 text-sm">
                {subtasks.map((s) => (
                  <li key={s.id} className="flex justify-between"><span>↳ {s.title}</span><span className="tabular-nums">{s.progress || 0}%</span></li>
                ))}
                {actions.map((a) => (
                  <li key={a.id} className="flex justify-between">
                    <span>{a.is_done ? '☑' : '☐'} {a.title}</span>
                    <span className="tabular-nums text-[var(--color-text-tertiary)]">{a.weight_percentage}%</span>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </div>
      ) : (
        <div className="space-y-4">
          <div>
            <label className={lab} htmlFor="td-title">{t('columns.title')}</label>
            <input id="td-title" value={String(form.title ?? '')} onChange={(e) => set('title', e.target.value)} className={field} />
          </div>
          <div>
            <label className={lab} htmlFor="td-desc">{t('dyn.description')}</label>
            <textarea id="td-desc" rows={3} value={String(form.description ?? '')} onChange={(e) => set('description', e.target.value)} className={field} />
          </div>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <div>
              <label className={lab} htmlFor="td-status">{t('columns.status')}</label>
              <select id="td-status" value={String(form.status)} onChange={(e) => set('status', e.target.value)} className={field}>
                {STATUSES.map((s) => <option key={s} value={s}>{t(`status.${s}`)}</option>)}
              </select>
            </div>
            <div>
              <label className={lab} htmlFor="td-priority">{t('columns.priority')}</label>
              <select id="td-priority" value={String(form.priority)} onChange={(e) => set('priority', e.target.value)} className={field}>
                {PRIORITIES.map((p) => <option key={p} value={p}>{t(`priority.${p}`)}</option>)}
              </select>
            </div>
            <div>
              <label className={lab} htmlFor="td-start">{t('dyn.col.start')}</label>
              <input id="td-start" type="date" value={String(form.start_date ?? '')} onChange={(e) => set('start_date', e.target.value)} className={field} />
            </div>
            <div>
              <label className={lab} htmlFor="td-due">{t('dyn.col.due')}</label>
              <input id="td-due" type="date" value={String(form.due_date ?? '')} onChange={(e) => set('due_date', e.target.value)} className={field} />
            </div>
            <div>
              <label className={lab} htmlFor="td-assignee">{t('dyn.col.assignee')}</label>
              <select id="td-assignee" value={String(form.assignee_id ?? '')} onChange={(e) => set('assignee_id', e.target.value)} className={field}>
                <option value="">{t('dyn.unassigned')}</option>
                {employees.map((e) => <option key={e.id} value={e.id}>{e.name}</option>)}
              </select>
            </div>
            <div>
              <label className={lab} htmlFor="td-effort">{t('dyn.effortHours')}</label>
              <input id="td-effort" type="number" min={0} step={0.5} value={Number(form.effort_estimate_h) || 0} onChange={(e) => set('effort_estimate_h', Number(e.target.value))} className={field} />
            </div>
            <div className="sm:col-span-2">
              <label className={lab} htmlFor="td-project">{t('dyn.col.project')}</label>
              <select id="td-project" value={String(form.project_id ?? '')} onChange={(e) => set('project_id', e.target.value)} className={field}>
                <option value="">{t('dyn.noProject')}</option>
                {projects.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
              </select>
            </div>
          </div>
        </div>
      )}
    </Modal>
  )
}
