// PRF-02 : ConfirmDialog autonome pour éviter de tirer ui.tsx (932 lignes) dans le chunk initial
import { useTranslation } from 'react-i18next'
import { X } from 'lucide-react'

interface ConfirmDialogProps {
  open: boolean
  title: string
  message: string
  confirmLabel?: string
  cancelLabel?: string
  variant?: 'danger' | 'primary'
  onConfirm: () => void
  onCancel: () => void
}

export function ConfirmDialog({
  open, title, message, confirmLabel, cancelLabel, variant = 'danger', onConfirm, onCancel,
}: ConfirmDialogProps) {
  const { t } = useTranslation('common')
  const cLabel = confirmLabel || t('actions.confirm')
  const cancelLbl = cancelLabel || t('actions.cancel')
  if (!open) return null

  const variantClass = variant === 'danger' ? 'btn-danger' : 'btn-primary'

  return (
    <div className="fixed inset-0 bg-black/40 z-[9995] flex items-center justify-center p-4">
      <div className="card shadow-2xl max-w-md w-full animate-scale-in">
        <div className="px-6 py-4 border-b border-[var(--color-border)] flex items-center justify-between">
          <h3 className="text-base font-semibold text-[var(--color-text)]">{title}</h3>
          <button onClick={onCancel} className="text-[var(--color-text-secondary)] hover:text-[var(--color-text)]" aria-label={t('actions.close')} title={t('actions.close')}>
            <X className="w-4 h-4" aria-hidden="true" />
          </button>
        </div>
        <div className="px-6 py-4">
          <p className="text-sm text-[var(--color-text-secondary)]">{message}</p>
        </div>
        <div className="flex items-center justify-end gap-2 px-6 py-4 border-t border-[var(--color-border)]">
          <button type="button" onClick={onCancel} className="btn btn-secondary text-xs px-3 py-1.5 inline-flex items-center gap-2">
            {cancelLbl}
          </button>
          <button type="button" onClick={onConfirm} className={`btn ${variantClass} text-xs px-3 py-1.5 inline-flex items-center gap-2`}>
            {cLabel}
          </button>
        </div>
      </div>
    </div>
  )
}
