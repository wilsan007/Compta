import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select, Badge } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getBudgetCommitments, createBudgetCommitment, updateBudgetCommitment, deleteBudgetCommitment, getChartAccounts, getFiscalYears, getSuppliers } from '@/lib/queries'
import { Plus, Trash2, X, FileText } from 'lucide-react'
import type { BudgetCommitment, ChartAccount, FiscalYear, Supplier } from '@/types'
import { useToast } from '@/lib/toast'

const statusVariants: Record<string, 'success' | 'warning' | 'danger' | 'neutral'> = {
  active: 'warning',
  consumed: 'success',
  cancelled: 'neutral',
}

export function BudgetCommitmentsPage() {
  const { toast } = useToast()
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const [commitments, setCommitments] = useState<BudgetCommitment[]>([])
  const [accounts, setAccounts] = useState<ChartAccount[]>([])
  const [years, setYears] = useState<FiscalYear[]>([])
  const [suppliers, setSuppliers] = useState<Supplier[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [yearFilter, setYearFilter] = useState('')

  useEffect(() => { load() }, [])

  async function load() {
    try {
      const [c, accs, fys, sups] = await Promise.all([
        getBudgetCommitments(yearFilter || undefined),
        getChartAccounts(),
        getFiscalYears(),
        getSuppliers(),
      ])
      setCommitments(c || [])
      setAccounts(accs || [])
      setYears(fys || [])
      setSuppliers(sups || [])
    } catch (err) {
      console.error('Error loading commitments:', err)
    } finally {
      setLoading(false)
    }
  }

  function handleFilterChange(v: string) {
    setYearFilter(v)
    setTimeout(load, 0)
  }

  async function handleDelete(id: string) {
    if (!window.confirm(t('budgetCommitments.deleteConfirm'))) return
    try { await deleteBudgetCommitment(id); await load() }
    catch (err: any) { toast('error', tCommon('toast.error'), err.message || tCommon('toast.deleteError')) }
  }

  async function handleCancel(id: string) {
    try { await updateBudgetCommitment(id, { status: 'cancelled' }); await load() }
    catch (err: any) { toast('error', tCommon('toast.error'), err.message || tCommon('toast.updateError')) }
  }

  const totalActive = commitments.filter(c => c.status === 'active').reduce((s, c) => s + Number(c.amount), 0)

  if (loading) return <SkeletonTable rows={6} />

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('home.structure') }, { label: t('budgetCommitments.title') }]} />
      <PageHeader title={t('budgetCommitments.title')} subtitle={t('budgetCommitments.subtitle', { count: commitments.length, total: formatCurrency(totalActive) })}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('budgetCommitments.new')}</Button>} />

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-48">
          <Select label={t('fiscalYears.title')} value={yearFilter} onChange={(e) => handleFilterChange(e.target.value)} options={[
            { value: '', label: t('budgetCommitments.allYears') },
            ...years.map(y => ({ value: y.id, label: y.code })),
          ]} />
        </div>
        <Button variant="secondary" onClick={load}>{tCommon('common.refresh')}</Button>
      </div>

      {commitments.length === 0 ? (
        <EmptyState icon={<FileText className="w-8 h-8" />} title={t('budgetCommitments.none')} description={t('budgetCommitments.noneDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('budgetCommitments.new')}</Button>} />
      ) : (
        <Card>
          <Table headers={[tCommon('common.date'), tCommon('common.description'), t('budgetCommitments.account'), t('budgetCommitments.supplier'), tCommon('common.amount'), t('budgetCommitments.source'), tCommon('common.status'), tCommon('table.actions')]}>
            <tbody>
              {commitments.map((c) => {
                const sup = suppliers.find(s => s.id === c.supplier_id)
                const st = { variant: statusVariants[c.status] || 'neutral' as const, label: t(`budgetCommitments.statusLabels.${c.status}`, { defaultValue: c.status }) }
                return (
                  <TableRow key={c.id}>
                    <TableCell className="text-xs">{formatDate(c.commitment_date)}</TableCell>
                    <TableCell className="text-sm">{c.description}</TableCell>
                    <TableCell className="font-mono text-xs">{c.account_code}</TableCell>
                    <TableCell className="text-sm">{sup?.name || '—'}</TableCell>
                    <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(c.amount))}</TableCell>
                    <TableCell><span className="text-xs">{t(`budgetCommitments.sourceLabels.${c.source_type}`, { defaultValue: c.source_type })}</span></TableCell>
                    <TableCell><Badge variant={st.variant}>{st.label}</Badge></TableCell>
                    <TableCell>
                      <div className="flex items-center gap-1">
                        {c.status === 'active' && (
                          <button onClick={() => handleCancel(c.id)} className="p-1.5 rounded text-[var(--color-warning)] hover:bg-[var(--color-neutral-100)]" title={t('budgetCommitments.cancel')}>
                            <X className="w-4 h-4" />
                          </button>
                        )}
                        <button onClick={() => handleDelete(c.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" title={tCommon('actions.delete')}>
                          <Trash2 className="w-4 h-4" />
                        </button>
                      </div>
                    </TableCell>
                  </TableRow>
                )
              })}
            </tbody>
          </Table>
        </Card>
      )}

      {showForm && (
        <CommitmentForm accounts={accounts} years={years} suppliers={suppliers} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); load() }} />
      )}
    </div>
  )
}

function CommitmentForm({ accounts, years, suppliers, onClose, onSaved }: {
  accounts: ChartAccount[]
  years: FiscalYear[]
  suppliers: Supplier[]
  onClose: () => void
  onSaved: () => void
}) {
  const [description, setDescription] = useState('')
  const { toast } = useToast()
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const [accountCode, setAccountCode] = useState('')
  const [fiscalYearId, setFiscalYearId] = useState('')
  const [amount, setAmount] = useState('')
  const [commitmentDate, setCommitmentDate] = useState(new Date().toISOString().split('T')[0])
  const [supplierId, setSupplierId] = useState('')
  const [notes, setNotes] = useState('')
  const [saving, setSaving] = useState(false)

  const expenseAccounts = accounts.filter(a => a.type === 'expense')

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!description || !accountCode || !amount) {
      toast('warning', tCommon('toast.warning'), t('budgetCommitments.requiredFields'))
      return
    }
    setSaving(true)
    try {
      await createBudgetCommitment({
        description,
        account_code: accountCode,
        fiscal_year_id: fiscalYearId || null,
        amount: Number(amount),
        commitment_date: commitmentDate,
        source_type: 'manual',
        source_id: null,
        status: 'active',
        supplier_id: supplierId || null,
        notes: notes || null,
      })
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.createError'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('budgetCommitments.create')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label={t('budgetCommitments.description')} required value={description} onChange={(e) => setDescription(e.target.value)} placeholder={t('budgetCommitments.descriptionPlaceholder')} />
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('budgetCommitments.expenseAccount')}</label>
              <select className="input" value={accountCode} onChange={(e) => setAccountCode(e.target.value)} required>
                <option value="">{t('budgetCommitments.selectAccount')}</option>
                {expenseAccounts.map(a => <option key={a.id} value={a.code}>{a.code} — {a.name}</option>)}
              </select>
            </div>
            <div>
              <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('fiscalYears.title')}</label>
              <select className="input" value={fiscalYearId} onChange={(e) => setFiscalYearId(e.target.value)}>
                <option value="">{tCommon('common.all')}</option>
                {years.map(y => <option key={y.id} value={y.id}>{y.code}</option>)}
              </select>
            </div>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('budgetCommitments.amount')} type="number" step="0.01" required value={amount} onChange={(e) => setAmount(e.target.value)} placeholder="0.00" />
            <Input label={t('budgetCommitments.commitmentDate')} type="date" required value={commitmentDate} onChange={(e) => setCommitmentDate(e.target.value)} />
          </div>
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('budgetCommitments.supplierOptional')}</label>
            <select className="input" value={supplierId} onChange={(e) => setSupplierId(e.target.value)}>
              <option value="">{t('budgetCommitments.none')}</option>
              {suppliers.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
          </div>
          <Input label={t('budgetCommitments.notes')} value={notes} onChange={(e) => setNotes(e.target.value)} />
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('common.saving') : tCommon('actions.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
