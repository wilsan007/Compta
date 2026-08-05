import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Modal } from './Modal'
import { Button } from '@/components/ui'

interface ActionCreationDialogProps {
  open: boolean
  onClose: () => void
  onConfirm: (title: string, weight: number, dueDate: string | null, notes: string | null) => void
}

export function ActionCreationDialog({ open, onClose, onConfirm }: ActionCreationDialogProps) {
  const { t } = useTranslation('taskManagement')
  const { t: tCommon } = useTranslation('common')
  const [title, setTitle] = useState('')
  const [weight, setWeight] = useState(0)
  const [dueDate, setDueDate] = useState('')
  const [notes, setNotes] = useState('')

  function handleConfirm() {
    if (!title.trim()) return
    onConfirm(title.trim(), weight, dueDate || null, notes.trim() || null)
    setTitle('')
    setWeight(0)
    setDueDate('')
    setNotes('')
    onClose()
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={t('action.title')}
      maxWidth="28rem"
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>{tCommon('cancel')}</Button>
          <Button onClick={handleConfirm} disabled={!title.trim()}>{t('action.create')}</Button>
        </>
      }
    >
      <div className="space-y-4">
        <div>
          <label className="text-sm font-medium text-[var(--color-text)] mb-1 block">{t('action.name')}</label>
          <input
            autoFocus
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder={t('action.namePlaceholder')}
            className="w-full px-3 py-2 text-sm border border-[var(--color-border)] rounded bg-[var(--color-surface)] outline-none focus:border-[var(--color-primary)]"
          />
        </div>
        <div>
          <label className="text-sm font-medium text-[var(--color-text)] mb-1 block">
            {t('action.weight')}: {weight}%
          </label>
          <input
            type="range"
            min={0}
            max={100}
            value={weight}
            onChange={(e) => setWeight(Number(e.target.value))}
            className="w-full accent-[var(--color-primary)]"
          />
        </div>
        <div>
          <label className="text-sm font-medium text-[var(--color-text)] mb-1 block">{t('action.dueDate')}</label>
          <input
            type="date"
            value={dueDate}
            onChange={(e) => setDueDate(e.target.value)}
            className="w-full px-3 py-2 text-sm border border-[var(--color-border)] rounded bg-[var(--color-surface)] outline-none focus:border-[var(--color-primary)]"
          />
        </div>
        <div>
          <label className="text-sm font-medium text-[var(--color-text)] mb-1 block">{t('action.notes')}</label>
          <textarea
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            rows={2}
            placeholder={t('action.notesPlaceholder')}
            className="w-full px-3 py-2 text-sm border border-[var(--color-border)] rounded bg-[var(--color-surface)] outline-none focus:border-[var(--color-primary)] resize-none"
          />
        </div>
      </div>
    </Modal>
  )
}
