import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { getCurrencyRevaluations, createCurrencyRevaluation, deleteCurrencyRevaluation } from '@/lib/queries'
import { useLocale } from '@/hooks/useLocale'
import { Plus, Trash2, TrendingUp, TrendingDown } from 'lucide-react'
import type { CurrencyRevaluation } from '@/types'
import { useToast } from '@/lib/toast'

export function CurrencyRevaluationPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatCurrency, formatDate } = useLocale()
  const [entries, setEntries] = useState<CurrencyRevaluation[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const data = await getCurrencyRevaluations()
      setEntries(data || [])
    } catch (err) {
      console.error('Failed to load currency revaluations:', err)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
    if (!window.confirm(t('revaluation.deleteConfirm'))) return
    try {
      await deleteCurrencyRevaluation(id)
      toast('success', tCommon('common.success'), t('revaluation.deleteSuccess'))
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    }
  }

  const tableHeaders = [
    t('revaluation.date'),
    t('revaluation.account'),
    t('revaluation.currency'),
    t('revaluation.originalRate'),
    t('revaluation.newRate'),
    t('revaluation.originalAmount'),
    t('revaluation.revaluedAmount'),
    t('revaluation.gainLoss'),
    t('revaluation.type'),
    t('revaluation.status'),
    tCommon('common.table.actions'),
  ]

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb') }, { label: t('etats.breadcrumb') }, { label: t('revaluation.breadcrumb') }]} />
      <PageHeader
        title={t('revaluation.title')}
        subtitle={t('revaluation.subtitle')}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('revaluation.new')}</Button>}
      />

      {loading ? (
        <SkeletonTable rows={4} cols={11} />
      ) : entries.length === 0 ? (
        <EmptyState
          icon={<TrendingUp className="w-8 h-8" />}
          title={t('revaluation.noEntries')}
          description={t('revaluation.noEntriesDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('revaluation.new')}</Button>}
        />
      ) : (
        <Card>
          <Table headers={tableHeaders}>
            {entries.map((entry) => (
              <TableRow key={entry.id}>
                <TableCell className="text-xs">{formatDate(entry.period_date)}</TableCell>
                <TableCell className="font-mono text-xs">{entry.account_code}</TableCell>
                <TableCell className="text-xs">{entry.currency}</TableCell>
                <TableCell className="font-mono text-xs text-right">{Number(entry.original_rate).toFixed(4)}</TableCell>
                <TableCell className="font-mono text-xs text-right">{Number(entry.new_rate).toFixed(4)}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(entry.original_amount_eur))}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(entry.revalued_amount_eur))}</TableCell>
                <TableCell className="font-mono text-xs text-right">
                  <span className={Number(entry.gain_loss) >= 0 ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}>
                    {Number(entry.gain_loss) >= 0 ? <TrendingUp className="w-3 h-3 inline" /> : <TrendingDown className="w-3 h-3 inline" />}
                    {formatCurrency(Number(entry.gain_loss))}
                  </span>
                </TableCell>
                <TableCell>
                  <Badge variant={entry.type === 'receivable' ? 'success' : 'warning'}>
                    {t(`revaluation.types.${entry.type}`)}
                  </Badge>
                </TableCell>
                <TableCell>
                  <Badge variant={entry.status === 'posted' ? 'success' : 'neutral'}>
                    {t(`revaluation.statuses.${entry.status}`)}
                  </Badge>
                </TableCell>
                <TableCell>
                  <button
                    onClick={() => handleDelete(entry.id)}
                    className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"
                    title={tCommon('common.actions.delete')}
                  >
                    <Trash2 className="w-4 h-4" />
                  </button>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && (
        <RevaluationForm
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); loadData() }}
        />
      )}
    </div>
  )
}

function RevaluationForm({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()

  const [periodDate, setPeriodDate] = useState(new Date().toISOString().slice(0, 10))
  const [accountCode, setAccountCode] = useState('')
  const [thirdPartyCode, setThirdPartyCode] = useState('')
  const [currency, setCurrency] = useState('USD')
  const [originalRate, setOriginalRate] = useState(1)
  const [newRate, setNewRate] = useState(1)
  const [originalAmount, setOriginalAmount] = useState(0)
  const [type, setType] = useState<'receivable' | 'payable'>('receivable')
  const [saving, setSaving] = useState(false)

  const originalAmountEur = Number(originalAmount) * Number(originalRate)
  const revaluedAmountEur = Number(originalAmount) * Number(newRate)
  const gainLoss = revaluedAmountEur - originalAmountEur

  async function handleSave() {
    if (!accountCode || !currency || !originalAmount) {
      toast('warning', tCommon('common.warning'), tCommon('common.fillRequired'))
      return
    }
    setSaving(true)
    try {
      await createCurrencyRevaluation({
        fiscal_year_id: null,
        period_date: periodDate,
        account_code: accountCode,
        third_party_code: thirdPartyCode || null,
        currency,
        original_rate: Number(originalRate),
        new_rate: Number(newRate),
        original_amount: Number(originalAmount),
        original_amount_eur: originalAmountEur,
        revalued_amount_eur: revaluedAmountEur,
        gain_loss: gainLoss,
        type,
        status: 'pending',
      })
      toast('success', tCommon('common.success'), t('revaluation.saveSuccess'))
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('revaluation.create')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]">✕</button>
        </div>
        <div className="p-6 space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('revaluation.date')} type="date" value={periodDate} onChange={(e) => setPeriodDate(e.target.value)} required />
            <Select
              label={t('revaluation.type')}
              value={type}
              onChange={(e) => setType(e.target.value as any)}
              options={[
                { value: 'receivable', label: t('revaluation.types.receivable') },
                { value: 'payable', label: t('revaluation.types.payable') },
              ]}
            />
            <Input label={t('revaluation.account')} value={accountCode} onChange={(e) => setAccountCode(e.target.value)} required />
            <Input label={t('revaluation.thirdParty')} value={thirdPartyCode} onChange={(e) => setThirdPartyCode(e.target.value)} />
            <Input label={t('revaluation.currency')} value={currency} onChange={(e) => setCurrency(e.target.value)} required />
            <Input label={t('revaluation.originalAmount')} type="number" value={originalAmount} onChange={(e) => setOriginalAmount(Number(e.target.value))} required />
            <Input label={t('revaluation.originalRate')} type="number" value={originalRate} onChange={(e) => setOriginalRate(Number(e.target.value))} required />
            <Input label={t('revaluation.newRate')} type="number" value={newRate} onChange={(e) => setNewRate(Number(e.target.value))} required />
          </div>
          <div className="flex justify-end gap-6 text-sm border-t border-[var(--color-border)] pt-4">
            <span className="text-[var(--color-text-secondary)]">{t('revaluation.originalAmountEur')}: <strong className="font-mono">{originalAmountEur.toFixed(2)}</strong></span>
            <span className="text-[var(--color-text-secondary)]">{t('revaluation.revaluedAmountEur')}: <strong className="font-mono">{revaluedAmountEur.toFixed(2)}</strong></span>
            <span className={gainLoss >= 0 ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}>
              {t('revaluation.gainLoss')}: <strong className="font-mono">{gainLoss.toFixed(2)}</strong>
            </span>
          </div>
        </div>
        <div className="flex justify-end gap-3 px-6 py-4 border-t border-[var(--color-border)]">
          <Button variant="secondary" onClick={onClose}>{tCommon('common.actions.cancel')}</Button>
          <Button onClick={handleSave} disabled={saving}>
            {saving ? tCommon('common.saving') : tCommon('common.actions.save')}
          </Button>
        </div>
      </div>
    </div>
  )
}
