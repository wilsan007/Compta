import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { formatCurrency } from '@/lib/utils'
import { getBudgets, createBudget, updateBudget, deleteBudget, getFiscalYears, getChartAccounts } from '@/lib/queries'
import { Plus, Pencil, Trash2, X, Target } from 'lucide-react'
import type { Budget, FiscalYear, ChartAccount } from '@/types'
import { useToast } from '@/lib/toast'

export function BudgetsPage() {
  const { toast } = useToast()
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
const [budgets, setBudgets] = useState<Budget[]>([])
  const [years, setYears] = useState<FiscalYear[]>([])
  const [accounts, setAccounts] = useState<ChartAccount[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<Budget | null>(null)

  useEffect(() => { load() }, [])

  async function load() {
    try {
      const [b, fy, accs] = await Promise.all([getBudgets(), getFiscalYears(), getChartAccounts()])
      setBudgets(b || [])
      setYears(fy || [])
      setAccounts(accs || [])
    } catch (err) {
      console.error('Error loading budgets:', err)
    } finally {
      setLoading(false)
    }
  }

  function openCreate() { setEditing(null); setShowForm(true) }
  function openEdit(b: Budget) { setEditing(b); setShowForm(true) }

  async function handleDelete(id: string) {
  if (!window.confirm(t('budgets.deleteConfirm'))) return
    try { await deleteBudget(id); await load() }
    catch (err) { toast('error', tCommon('toast.error'), tCommon('toast.deleteError')) }
  }

  const periodLabels = [
    t('budgets.months.jan'), t('budgets.months.feb'), t('budgets.months.mar'), t('budgets.months.apr'),
    t('budgets.months.may'), t('budgets.months.jun'), t('budgets.months.jul'), t('budgets.months.aug'),
    t('budgets.months.sep'), t('budgets.months.oct'), t('budgets.months.nov'), t('budgets.months.dec'),
  ]

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('home.structure') }, { label: t('budgets.title') }]} />
      <PageHeader
        title={t('budgets.title')}
        subtitle={t('budgets.subtitle', { count: budgets.length })}
        action={<Button onClick={openCreate}><Plus className="w-4 h-4" /> {t('budgets.new')}</Button>}
      />

      {loading ? (
        <SkeletonTable rows={4} cols={6} />
      ) : budgets.length === 0 ? (
        <EmptyState
          icon={<Target className="w-8 h-8" />}
          title={t('budgets.noBudgets')}
          description={t('budgets.noBudgetsDescription')}
          action={<Button onClick={openCreate}><Plus className="w-4 h-4" /> {t('budgets.new')}</Button>}
        />
      ) : (
        <div className="space-y-4">
          {budgets.map((b) => {
            const total = ['period_1','period_2','period_3','period_4','period_5','period_6','period_7','period_8','period_9','period_10','period_11','period_12']
              .reduce((s, k) => s + Number((b as any)[k]), 0)
            const year = years.find((y) => y.id === b.fiscal_year_id)
            return (
              <Card key={b.id}>
                <div className="p-4 flex items-center justify-between mb-3">
                  <div>
                    <h3 className="font-semibold text-sm">{b.name}</h3>
                    <p className="text-xs text-[var(--color-text-secondary)]">
                      {b.account_code && `${t('budgets.account')}: ${b.account_code} — `}
                      {year?.code || t('budgets.allYears')} — {t('budgets.total')}: {formatCurrency(total)}
                    </p>
                  </div>
                  <div className="flex gap-2">
                    <button onClick={() => openEdit(b)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]">
                      <Pencil className="w-4 h-4" />
                    </button>
                    <button onClick={() => handleDelete(b.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </div>
                </div>
                <Table headers={periodLabels}>
                  <TableRow>
                    {['period_1','period_2','period_3','period_4','period_5','period_6','period_7','period_8','period_9','period_10','period_11','period_12'].map((k) => (
                      <TableCell key={k} className="font-mono text-xs text-right">{formatCurrency(Number((b as any)[k]))}</TableCell>
                    ))}
                  </TableRow>
                </Table>
              </Card>
            )
          })}
        </div>
      )}

      {showForm && (
        <BudgetForm
          budget={editing}
          years={years}
          accounts={accounts}
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); load() }}
        />
      )}
    </div>
  )
}

function BudgetForm({ budget, years, accounts, onClose, onSaved }: {
  budget: Budget | null; years: FiscalYear[]; accounts: ChartAccount[]
  onClose: () => void; onSaved: () => void
}) {
  const [name, setName] = useState(budget?.name || '')
  const { toast } = useToast()
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const [fiscalYearId, setFiscalYearId] = useState(budget?.fiscal_year_id || '')
  const [accountCode, setAccountCode] = useState(budget?.account_code || '')
  const [periods, setPeriods] = useState<number[]>(
    budget
      ? ['period_1','period_2','period_3','period_4','period_5','period_6','period_7','period_8','period_9','period_10','period_11','period_12'].map((k) => Number((budget as any)[k]))
      : new Array(12).fill(0)
  )
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      const data: any = { name, fiscal_year_id: fiscalYearId || null, account_code: accountCode || null }
      periods.forEach((v, i) => { data[`period_${i + 1}`] = v })
      if (budget) await updateBudget(budget.id, data)
      else await createBudget(data)
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.createError'))
    } finally {
      setSaving(false)
    }
  }

  const total = periods.reduce((s, v) => s + v, 0)

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4 overflow-y-auto">
      <div className="card shadow-2xl overflow-hidden my-8" style={{ width: '100%', maxWidth: '48rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{budget ? t('budgets.edit') : t('budgets.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label={t('budgets.name')} required value={name} onChange={(e) => setName(e.target.value)} placeholder={t('budgets.namePlaceholder')} />
          <div className="grid grid-cols-2 gap-4">
            <Select label={t('fiscalYears.title')} value={fiscalYearId} onChange={(e) => setFiscalYearId(e.target.value)}
              options={[{ value: '', label: tCommon('common.all') }, ...years.map((y) => ({ value: y.id, label: y.code }))]} />
            <div>
              <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('budgets.account')}</label>
              <select className="input" value={accountCode} onChange={(e) => setAccountCode(e.target.value)}>
                <option value="">{tCommon('common.all')}</option>
                {accounts.map((a) => <option key={a.id} value={a.code}>{a.code} — {a.name}</option>)}
              </select>
            </div>
          </div>
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-2">{t('budgets.amountsByPeriod')}</label>
            <div className="grid grid-cols-6 gap-2">
              {periods.map((v, i) => (
                <div key={i}>
                  <label className="text-xs text-[var(--color-text-secondary)]">{[t('budgets.months.jan'), t('budgets.months.feb'), t('budgets.months.mar'), t('budgets.months.apr'), t('budgets.months.may'), t('budgets.months.jun'), t('budgets.months.jul'), t('budgets.months.aug'), t('budgets.months.sep'), t('budgets.months.oct'), t('budgets.months.nov'), t('budgets.months.dec')][i]}</label>
                  <input type="number" step="0.01" className="input text-sm" value={v}
                    onChange={(e) => setPeriods((prev) => { const next = [...prev]; next[i] = Number(e.target.value); return next })} />
                </div>
              ))}
            </div>
          </div>
          <div className="p-3 rounded-lg bg-[var(--color-neutral-50)] text-sm">
            <span className="text-[var(--color-text-secondary)]">{t('budgets.total')}: </span>
            <span className="font-mono font-bold">{formatCurrency(total)}</span>
          </div>
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('common.saving') : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
