import { type ReactNode, useEffect, useId } from 'react'
import { useFocusTrap } from '@/lib/hooks/accessibility'
import { useTranslation } from 'react-i18next'
import { X } from 'lucide-react'
import { cn } from '@/lib/utils'

interface ModalProps {
  open: boolean
  onClose: () => void
  title?: string
  children: ReactNode
  footer?: ReactNode
  maxWidth?: string
  className?: string
}

export function Modal({ open, onClose, title, children, footer, maxWidth = '36rem', className }: ModalProps) {
  const titleId = useId()
  const { t: tCommon } = useTranslation('common')
  // LOT7-07 : Échap et le blocage du défilement étaient déjà là ; manquaient le piège
  // de focus (Tab sortait derrière la boîte) et la restitution du focus à la fermeture.
  const dialogRef = useFocusTrap(open, onClose)
  useEffect(() => {
    if (!open) return
    document.body.style.overflow = 'hidden'
    return () => { document.body.style.overflow = '' }
  }, [open])

  if (!open) return null

  return (
    <div
      className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4"
      onClick={onClose}
    >
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={title ? titleId : undefined}
        tabIndex={-1}
        className={cn('card shadow-2xl rounded-lg w-full overflow-hidden', className)}
        style={{ maxWidth }}
        onClick={(e) => e.stopPropagation()}
      >
        {title && (
          <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
            <h2 id={titleId} className="text-lg font-semibold text-[var(--color-text)]">{title}</h2>
            <button
              onClick={onClose}
              aria-label={tCommon('actions.close')}
              title={tCommon('actions.close')}
              className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]"
            >
              <X className="w-5 h-5" aria-hidden="true" />
            </button>
          </div>
        )}
        <div className="p-6 max-h-[70vh] overflow-y-auto">{children}</div>
        {footer && (
          <div className="flex justify-end gap-3 px-6 py-4 border-t border-[var(--color-border)] bg-[var(--color-neutral-50)]">
            {footer}
          </div>
        )}
      </div>
    </div>
  )
}
