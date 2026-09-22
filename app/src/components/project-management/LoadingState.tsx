import { useTranslation } from 'react-i18next'
import { Loader2, AlertCircle } from 'lucide-react'

export function LoadingState() {
  const { t } = useTranslation('common')
  return (
    <div className="flex items-center justify-center py-12">
      <Loader2 className="w-6 h-6 animate-spin text-[var(--color-primary)]" />
      <span className="ml-2 text-sm text-[var(--color-text-secondary)]">{t('common.loading')}</span>
    </div>
  )
}

export function ErrorState({ message, onRetry }: { message: string; onRetry?: () => void }) {
  const { t } = useTranslation('common')
  return (
    <div className="flex flex-col items-center justify-center py-12 gap-3">
      <AlertCircle className="w-8 h-8 text-[var(--color-danger)]" />
      <span className="text-sm text-[var(--color-text-secondary)]">{message}</span>
      {onRetry && (
        <button
          onClick={onRetry}
          className="px-4 py-2 text-sm rounded-lg bg-[var(--color-primary)] text-white hover:opacity-90"
        >
          {t('actions.retry')}
        </button>
      )}
    </div>
  )
}
