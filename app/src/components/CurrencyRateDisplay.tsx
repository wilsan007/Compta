import { useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { RefreshCw } from 'lucide-react'
import { Badge } from '@/components/ui'

interface CurrencyRateDisplayProps {
  fromCurrency: string
  toCurrency?: string
  rate?: number | null
  rateDate?: string | null
  onRefresh?: () => void
}

export function CurrencyRateDisplay({ fromCurrency, toCurrency = 'EUR', rate, rateDate, onRefresh }: CurrencyRateDisplayProps) {
  const { t } = useTranslation('banking')
  const [refreshing, setRefreshing] = useState(false)

  const handleRefresh = useCallback(() => {
    if (onRefresh) {
      setRefreshing(true)
      onRefresh()
      setTimeout(() => setRefreshing(false), 1000)
    }
  }, [onRefresh])

  const isStale = rateDate ? (Date.now() - new Date(rateDate).getTime()) > 7 * 24 * 60 * 60 * 1000 : true
  const isFresh = rateDate ? (Date.now() - new Date(rateDate).getTime()) < 24 * 60 * 60 * 1000 : false

  return (
    <div className="flex items-center gap-3 text-sm">
      <span className="text-[var(--color-text-secondary)]">
        {fromCurrency}/{toCurrency}
      </span>
      {rate ? (
        <span className="font-medium">{rate.toFixed(6)}</span>
      ) : (
        <span className="text-[var(--color-text-secondary)]">{t('currencyRate.noRate')}</span>
      )}
      {rateDate && (
        <Badge variant={isFresh ? 'success' : isStale ? 'danger' : 'warning'}>
          {isFresh ? t('currencyRate.fresh') : t('currencyRate.stale')}
        </Badge>
      )}
      {onRefresh && (
        <button onClick={handleRefresh} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" title={t('currencyRate.refresh')}>
          <RefreshCw className={`w-4 h-4 ${refreshing ? 'animate-spin' : ''}`} />
        </button>
      )}
    </div>
  )
}
