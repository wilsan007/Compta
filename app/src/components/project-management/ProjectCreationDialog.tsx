import { useState, useEffect } from 'react'
import { useTranslation } from 'react-i18next'
import { Modal } from './Modal'
import { Button } from '@/components/ui'
import { AssigneeSelect } from './AssigneeSelect'
import { createProject } from '@/lib/queries/accounting'
import { getCustomers } from '@/lib/queries/partners'
import type { Project } from '@/types'

interface ProjectCreationDialogProps {
  open: boolean
  onClose: () => void
  onCreated?: () => void
}

interface Customer {
  id: string
  name: string
}

export function ProjectCreationDialog({ open, onClose, onCreated }: ProjectCreationDialogProps) {
  const { t } = useTranslation('taskManagement')
  const { t: tCommon } = useTranslation('common')
  const [name, setName] = useState('')
  const [description, setDescription] = useState('')
  const [customerId, setCustomerId] = useState('')
  const [budget, setBudget] = useState(0)
  const [startDate, setStartDate] = useState('')
  const [endDate, setEndDate] = useState('')
  const [status, setStatus] = useState<'active' | 'completed' | 'on_hold' | 'cancelled'>('active')
  const [managerId, setManagerId] = useState<string | null>(null)
  const [customers, setCustomers] = useState<Customer[]>([])
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (open) {
      setName('')
      setDescription('')
      setCustomerId('')
      setBudget(0)
      setStartDate('')
      setEndDate('')
      setStatus('active')
      setManagerId(null)
      setError(null)
      getCustomers().then((data) => {
        setCustomers(data as Customer[])
      }).catch(() => {
        setCustomers([])
      })
    }
  }, [open])

  async function handleConfirm() {
    if (!name.trim()) return
    setSaving(true)
    setError(null)
    try {
      const projectData: Omit<Project, 'id' | 'created_at' | 'updated_at'> = {
        name: name.trim(),
        description: description.trim(),
        customer_id: customerId || null,
        status,
        budget,
        actual_cost: 0,
        start_date: startDate,
        end_date: endDate,
        manager_id: managerId,
      }
      await createProject(projectData)
      onCreated?.()
      onClose()
    } catch (err: any) {
      setError(err.message || 'Failed to create project')
    } finally {
      setSaving(false)
    }
  }

  const inputClass = 'w-full px-3 py-2 text-sm border border-[var(--color-border)] rounded bg-[var(--color-surface)] outline-none focus:border-[var(--color-primary)]'
  const labelClass = 'text-sm font-medium text-[var(--color-text)] mb-1 block'

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={t('actions.newProject')}
      maxWidth="32rem"
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>{tCommon('common.cancel')}</Button>
          <Button onClick={handleConfirm} disabled={!name.trim() || saving}>
            {saving ? t('doc.saving') : t('actions.save')}
          </Button>
        </>
      }
    >
      <div className="space-y-4">
        {error && (
          <div className="px-3 py-2 text-sm text-red-600 bg-red-50 rounded-lg border border-red-200">
            {error}
          </div>
        )}
        <div>
          <label className={labelClass}>{t('dialog.title')}</label>
          <input
            autoFocus
            value={name}
            onChange={(e) => setName(e.target.value)}
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
              value={customerId}
              onChange={(e) => setCustomerId(e.target.value)}
              className={inputClass}
            >
              <option value="">—</option>
              {customers.map((c) => (
                <option key={c.id} value={c.id}>{c.name}</option>
              ))}
            </select>
          </div>
          <div>
            <label className={labelClass}>{t('dialog.status')}</label>
            <select
              value={status}
              onChange={(e) => setStatus(e.target.value as typeof status)}
              className={inputClass}
            >
              <option value="active">{t('status.todo')}</option>
              <option value="on_hold">{t('status.blocked')}</option>
              <option value="completed">{t('status.done')}</option>
              <option value="cancelled">{t('status.canceled')}</option>
            </select>
          </div>
        </div>
        <div>
          <label className={labelClass}>{t('dialog.projectManager')}</label>
          <div className="mt-1">
            <AssigneeSelect
              value={managerId}
              onCommit={(empId) => {
                setManagerId(empId)
              }}
            />
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
              value={endDate}
              onChange={(e) => setEndDate(e.target.value)}
              className={inputClass}
            />
          </div>
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
    </Modal>
  )
}
