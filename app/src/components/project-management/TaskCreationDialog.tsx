import { useState, useEffect } from 'react'
import { useTranslation } from 'react-i18next'
import { Modal } from './Modal'
import { Button } from '@/components/ui'
import { AssigneeSelect } from './AssigneeSelect'
import { useProjectContext } from '@/contexts/ProjectContext'
import type { TaskCreateInput, TaskStatus, TaskPriority } from '@/types/projectManagement'

interface TaskCreationDialogProps {
  open: boolean
  onClose: () => void
  onConfirm: (task: TaskCreateInput) => void
  projectId?: string
}

const STATUSES: TaskStatus[] = ['todo', 'doing', 'blocked', 'changes_requested', 'approved', 'done', 'canceled']
const PRIORITIES: TaskPriority[] = ['low', 'medium', 'high', 'urgent']

export function TaskCreationDialog({ open, onClose, onConfirm, projectId }: TaskCreationDialogProps) {
  const { t } = useTranslation('taskManagement')
  const { t: tCommon } = useTranslation('common')
  const { projects } = useProjectContext()

  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')
  const [selectedProject, setSelectedProject] = useState(projectId || '')
  const [status, setStatus] = useState<TaskStatus>('todo')
  const [priority, setPriority] = useState<TaskPriority>('medium')
  const [assignee, setAssignee] = useState('')
  const [assigneeId, setAssigneeId] = useState<string | null>(null)
  const [startDate, setStartDate] = useState('')
  const [dueDate, setDueDate] = useState('')
  const [effort, setEffort] = useState(0)
  const [budget, setBudget] = useState(0)

  useEffect(() => {
    if (open) {
      setTitle('')
      setDescription('')
      setSelectedProject(projectId || '')
      setStatus('todo')
      setPriority('medium')
      setAssignee('')
      setAssigneeId(null)
      setStartDate('')
      setDueDate('')
      setEffort(0)
      setBudget(0)
    }
  }, [open, projectId])

  function handleConfirm() {
    if (!title.trim()) return
    const task: TaskCreateInput = {
      title: title.trim(),
      description: description.trim() || null,
      project_id: selectedProject || null,
      parent_id: null,
      status,
      priority,
      assignee: assignee.trim() || null,
      assignee_id: assigneeId,
      start_date: startDate || null,
      due_date: dueDate || null,
      effort_estimate_h: effort,
      effort_spent_h: 0,
      progress: 0,
      display_order: new Date().toISOString(),
      task_level: 0,
      budget,
      color: 0,
      acceptance_criteria: null,
      recurring_task: false,
      recurring_interval: 0,
      recurring_rule_type: 'daily',
      linked_action_id: null,
      production_order_id: null,
    }
    onConfirm(task)
    onClose()
  }

  const inputClass = 'w-full px-3 py-2 text-sm border border-[var(--color-border)] rounded bg-[var(--color-surface)] outline-none focus:border-[var(--color-primary)]'
  const labelClass = 'text-sm font-medium text-[var(--color-text)] mb-1 block'

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={t('dialog.newTask')}
      maxWidth="32rem"
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>{tCommon('common.cancel')}</Button>
          <Button onClick={handleConfirm} disabled={!title.trim()}>{t('actions.save')}</Button>
        </>
      }
    >
      <div className="space-y-4">
        <div>
          <label className={labelClass}>{t('dialog.title')}</label>
          <input
            autoFocus
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && handleConfirm()}
            placeholder={t('dialog.title')}
            className={inputClass}
          />
        </div>

        <div>
          <label className={labelClass}>{t('dialog.description')}</label>
          <textarea
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            rows={2}
            placeholder={t('dialog.description')}
            className={inputClass}
          />
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className={labelClass}>{t('dialog.project')}</label>
            <select
              value={selectedProject}
              onChange={(e) => setSelectedProject(e.target.value)}
              className={inputClass}
            >
              <option value="">—</option>
              {projects.map((p) => (
                <option key={p.id} value={p.id}>{p.name}</option>
              ))}
            </select>
          </div>
          <div>
            <label className={labelClass}>{t('dialog.assignee')}</label>
            <div className="mt-1">
              <AssigneeSelect
                value={assigneeId}
                onCommit={(empId, empName) => {
                  setAssigneeId(empId)
                  setAssignee(empName || '')
                }}
              />
            </div>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className={labelClass}>{t('dialog.status')}</label>
            <select
              value={status}
              onChange={(e) => setStatus(e.target.value as TaskStatus)}
              className={inputClass}
            >
              {STATUSES.map((s) => (
                <option key={s} value={s}>{t(`status.${s}`)}</option>
              ))}
            </select>
          </div>
          <div>
            <label className={labelClass}>{t('dialog.priority')}</label>
            <select
              value={priority}
              onChange={(e) => setPriority(e.target.value as TaskPriority)}
              className={inputClass}
            >
              {PRIORITIES.map((p) => (
                <option key={p} value={p}>{t(`priority.${p}`)}</option>
              ))}
            </select>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className={labelClass}>{t('dialog.startDate')}</label>
            <input
              type="date"
              value={startDate}
              onChange={(e) => setStartDate(e.target.value)}
              className={inputClass}
            />
          </div>
          <div>
            <label className={labelClass}>{t('dialog.dueDate')}</label>
            <input
              type="date"
              value={dueDate}
              onChange={(e) => setDueDate(e.target.value)}
              className={inputClass}
            />
          </div>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className={labelClass}>{t('dialog.effort')}</label>
            <input
              type="number"
              min={0}
              value={effort}
              onChange={(e) => setEffort(Number(e.target.value))}
              className={inputClass}
            />
          </div>
          <div>
            <label className={labelClass}>{t('dialog.budget')}</label>
            <input
              type="number"
              min={0}
              value={budget}
              onChange={(e) => setBudget(Number(e.target.value))}
              className={inputClass}
            />
          </div>
        </div>
      </div>
    </Modal>
  )
}
