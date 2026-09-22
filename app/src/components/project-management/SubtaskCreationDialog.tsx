import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Modal } from './Modal'
import { Button } from '@/components/ui'

interface SubtaskCreationDialogProps {
  open: boolean
  onClose: () => void
  onConfirm: (title: string) => void
  parentTitle: string
}

export function SubtaskCreationDialog({ open, onClose, onConfirm, parentTitle }: SubtaskCreationDialogProps) {
  const { t } = useTranslation('taskManagement')
  const { t: tCommon } = useTranslation('common')
  const [title, setTitle] = useState('')

  function handleConfirm() {
    if (!title.trim()) return
    onConfirm(title.trim())
    setTitle('')
    onClose()
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={t('subtask.title')}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>{tCommon('common.cancel')}</Button>
          <Button onClick={handleConfirm} disabled={!title.trim()}>{t('subtask.create')}</Button>
        </>
      }
    >
      <div className="space-y-3">
        <p className="text-sm text-[var(--color-text-secondary)]">
          {t('subtask.parent')}: <span className="font-medium text-[var(--color-text)]">{parentTitle}</span>
        </p>
        <input
          autoFocus
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && handleConfirm()}
          placeholder={t('subtask.placeholder')}
          className="w-full px-3 py-2 text-sm border border-[var(--color-border)] rounded bg-[var(--color-surface)] outline-none focus:border-[var(--color-primary)]"
        />
      </div>
    </Modal>
  )
}
