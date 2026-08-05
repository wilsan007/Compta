import { type ReactNode } from 'react'
import { useTranslation } from 'react-i18next'
import { X } from 'lucide-react'

interface QuickAccessModalProps {
  title: string
  onClose: () => void
  onSaved?: () => void
  children: ReactNode
  maxWidth?: string
}

/**
 * Reusable modal shell for Cross-Module Quick Access components.
 * Provides consistent styling, close button, and i18n.
 */
export function QuickAccessModal({ title, onClose, children, maxWidth = '40rem' }: QuickAccessModalProps) {
  const { t } = useTranslation('common')

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold text-[var(--color-text)]">{title}</h2>
          <button
            onClick={onClose}
            className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]"
            aria-label={t('actions.close')}
          >
            <X className="w-5 h-5" />
          </button>
        </div>
        <div className="p-6 max-h-[70vh] overflow-y-auto">{children}</div>
      </div>
    </div>
  )
}
