import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { getRateHistory, saveRate, refreshRatesFromECB, type ExchangeRate } from '@/lib/currencyRates'
import { formatDate } from '@/lib/utils'
import { getCurrencies } from '@/lib/queries'
import { RefreshCw, Plus, X, TrendingUp, TrendingDown, Calendar } from 'lucide-react'
import type { Currency } from '@/types'
import { useToast } from '@/lib/toast'

export function ExchangeRatesPage() {
  const { t } = useTranslation('settings')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [rates, setRates] = useState<ExchangeRate[]>([])
  const [currencies, setCurrencies] = useState<Currency[]>([])
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)
  const [baseCurrency, setBaseCurrency] = useState('EUR')
  const [quoteCurrency, setQuoteCurrency] = useState('USD')
  const [showForm, setShowForm] = useState(false)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [history, curs] = await Promise.all([
        getRateHistory(baseCurrency, quoteCurrency, 30).catch(() => []),
        getCurrencies().catch(() => []),
      ])
      setRates(history)
      setCurrencies(curs || [])
    } catch (err) {
      console.error('Error loading exchange rates:', err)
    } finally {
      setLoading(false)
    }
  }, [baseCurrency, quoteCurrency])

  useEffect(() => { loadData() }, [loadData])

  async function handleRefreshECB() {
    setRefreshing(true)
    try {
      const saved = await refreshRatesFromECB('EUR')
      toast('success', tCommon('toast.success'), t('exchangeRates.refreshed', { count: saved }))
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || t('exchangeRates.refreshError'))
    } finally {
      setRefreshing(false)
    }
  }

  const latestRate = rates.length > 0 ? rates[rates.length - 1] : null
  const previousRate = rates.length > 1 ? rates[rates.length - 2] : null
  const trend = latestRate && previousRate
    ? Number(latestRate.rate) > Number(previousRate.rate) ? 'up' : Number(latestRate.rate) < Number(previousRate.rate) ? 'down' : 'stable'
    : 'stable'

  return (
    <div>
      <Breadcrumb items={[{ label: t('currencies.breadcrumb') }, { label: t('exchangeRates.breadcrumb') }]} />
      <PageHeader
        title={t('exchangeRates.title')}
        subtitle={t('exchangeRates.subtitle')}
        action={
          <div className="flex gap-2">
            <Button variant="secondary" onClick={handleRefreshECB} disabled={refreshing}>
              <RefreshCw className={`w-4 h-4 ${refreshing ? 'animate-spin' : ''}`} />
              {t('exchangeRates.refreshECB')}
            </Button>
            <Button onClick={() => setShowForm(true)}>
              <Plus className="w-4 h-4" />
              {t('exchangeRates.addManual')}
            </Button>
          </div>
        }
      />

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-40">
          <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('exchangeRates.base')}</label>
          <Select
            value={baseCurrency}
            onChange={(e) => setBaseCurrency(e.target.value)}
            options={currencies.map((c) => ({ value: c.code, label: `${c.code} — ${c.name}` }))}
          />
        </div>
        <div className="w-40">
          <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('exchangeRates.quote')}</label>
          <Select
            value={quoteCurrency}
            onChange={(e) => setQuoteCurrency(e.target.value)}
            options={currencies.map((c) => ({ value: c.code, label: `${c.code} — ${c.name}` }))}
          />
        </div>
      </div>

      {latestRate && (
        <Card className="mb-4">
          <div className="flex items-center justify-between p-4">
            <div>
              <div className="text-sm text-[var(--color-text-secondary)]">
                {baseCurrency} / {quoteCurrency}
              </div>
              <div className="text-2xl font-bold font-mono">
                {Number(latestRate.rate).toFixed(6)}
              </div>
              <div className="text-xs text-[var(--color-text-secondary)] flex items-center gap-1 mt-1">
                <Calendar className="w-3 h-3" />
                {latestRate.rate_date}
                <Badge variant={latestRate.source === 'ecb' ? 'success' : 'neutral'}>
                  {latestRate.source.toUpperCase()}
                </Badge>
              </div>
            </div>
            <div className="flex items-center gap-2">
              {trend === 'up' && <TrendingUp className="w-6 h-6 text-[var(--color-success)]" />}
              {trend === 'down' && <TrendingDown className="w-6 h-6 text-[var(--color-danger)]" />}
              {trend === 'stable' && <span className="text-[var(--color-text-secondary)] text-sm">—</span>}
            </div>
          </div>
        </Card>
      )}

      {loading ? (
        <SkeletonTable rows={8} cols={4} />
      ) : rates.length === 0 ? (
        <EmptyState
          icon={<TrendingUp className="w-8 h-8" />}
          title={t('exchangeRates.noRates')}
          description={t('exchangeRates.noRatesDescription')}
          action={<Button onClick={handleRefreshECB} disabled={refreshing}><RefreshCw className="w-4 h-4" /> {t('exchangeRates.refreshECB')}</Button>}
        />
      ) : (
        <Card>
          <Table headers={[t('exchangeRates.date'), t('exchangeRates.rate'), t('exchangeRates.source'), t('exchangeRates.actions')]}>
            {[...rates].reverse().map((r) => (
              <TableRow key={r.id}>
                <TableCell className="font-mono text-sm">{r.rate_date}</TableCell>
                <TableCell className="font-mono font-semibold">{Number(r.rate).toFixed(6)}</TableCell>
                <TableCell>
                  <Badge variant={r.source === 'ecb' ? 'success' : 'neutral'}>{r.source.toUpperCase()}</Badge>
                </TableCell>
                <TableCell className="text-xs text-[var(--color-text-secondary)]">
                  {formatDate(r.created_at)}
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && (
        <ManualRateForm
          currencies={currencies}
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); loadData() }}
        />
      )}
    </div>
  )
}

function ManualRateForm({ currencies, onClose, onSaved }: { currencies: Currency[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('settings')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [base, setBase] = useState('EUR')
  const [quote, setQuote] = useState('USD')
  const [rate, setRate] = useState(1)
  const [rateDate, setRateDate] = useState(new Date().toISOString().split('T')[0])
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await saveRate(base, quote, rate, rateDate, 'manual')
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.createError'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '28rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('exchangeRates.addManual')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <Select
              label={t('exchangeRates.base')}
              value={base}
              onChange={(e) => setBase(e.target.value)}
              options={currencies.map((c) => ({ value: c.code, label: c.code }))}
            />
            <Select
              label={t('exchangeRates.quote')}
              value={quote}
              onChange={(e) => setQuote(e.target.value)}
              options={currencies.map((c) => ({ value: c.code, label: c.code }))}
            />
          </div>
          <Input label={t('exchangeRates.rate')} type="number" step="0.000001" required value={rate} onChange={(e) => setRate(Number(e.target.value))} />
          <Input label={t('exchangeRates.date')} type="date" required value={rateDate} onChange={(e) => setRateDate(e.target.value)} />
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
