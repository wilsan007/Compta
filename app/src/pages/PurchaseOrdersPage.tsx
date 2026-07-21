import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getPurchaseOrders, createPurchaseOrder, updatePurchaseOrder, deletePurchaseOrder, getSuppliers, getChartAccounts, getFiscalYears, checkBudgetAvailability, createBudgetCommitment } from '@/lib/queries'
import { Plus, Trash2, X, FileText, AlertTriangle } from 'lucide-react'
import type { PurchaseOrder, Supplier, ChartAccount, FiscalYear, BudgetControlResult } from '@/types'
import { useToast } from '@/lib/toast'
import { useTranslation } from 'react-i18next'

export function PurchaseOrdersPage() {
  const { t } = useTranslation('purchases')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const { toast } = useToast()
  const [orders, setOrders] = useState<PurchaseOrder[]>([])
  const [suppliers, setSuppliers] = useState<Supplier[]>([])
  const [accounts, setAccounts] = useState<ChartAccount[]>([])
  const [years, setYears] = useState<FiscalYear[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [statusFilter, setStatusFilter] = useState('')

  const loadData = useCallback(async () => {
    try {
      const [ords, sups, accs, fys] = await Promise.all([getPurchaseOrders(statusFilter || undefined), getSuppliers(), getChartAccounts(), getFiscalYears()])
      setOrders(ords || [])
      setSuppliers(sups || [])
      setAccounts(accs || [])
      setYears(fys || [])
    } catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [statusFilter])

  useEffect(() => { loadData() }, [loadData])

  async function handleStatusChange(id: string, status: string) {
  try { await updatePurchaseOrder(id, { status: status as any }); await loadData() }
    catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
  }

  async function handleDelete(id: string) {
    if (!window.confirm(t('orders.deleteConfirm'))) return
    try { await deletePurchaseOrder(id); await loadData() }
    catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
  }

  const totalAmount = orders.reduce((s, o) => s + Number(o.total), 0)

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.purchases') }, { label: t('orders.title') }]} />
      <PageHeader title={t('orders.title')} subtitle={`${orders.length} ${t('orders.title').toLowerCase()} — ${formatCurrency(totalAmount)}`}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('orders.new')}</Button>} />

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-48">
          <Select label={t('orders.status')} value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} options={[
            { value: '', label: tCommon('common.all') }, { value: 'draft', label: t('orders.statuses.draft') }, { value: 'confirmed', label: t('orders.statuses.confirmed') },
            { value: 'received', label: t('orders.statuses.received') }, { value: 'cancelled', label: t('orders.statuses.cancelled') },
          ]} />
        </div>
        <Button variant="secondary" onClick={loadData}>{t('orders.refresh')}</Button>
      </div>

      {loading ? <SkeletonTable rows={6} cols={6} /> : orders.length === 0 ? (
        <EmptyState icon={<FileText className="w-8 h-8" />} title={t('orders.noOrders')} description={t('orders.noOrdersDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('orders.new')}</Button>} />
      ) : (
        <Card>
          <Table headers={[t('orders.number'), t('orders.supplier'), t('orders.date'), t('orders.expectedDate'), t('orders.amount'), t('orders.status'), t('orders.actions')]}>
            {orders.map((o) => {
              const sup = suppliers.find((s) => s.id === o.supplier_id)
              return (
                <TableRow key={o.id}>
                  <TableCell className="font-mono text-xs">{o.number}</TableCell>
                  <TableCell className="text-sm">{sup?.name || '—'}</TableCell>
                  <TableCell className="text-xs">{formatDate(o.order_date)}</TableCell>
                  <TableCell className="text-xs">{o.expected_date ? formatDate(o.expected_date) : '—'}</TableCell>
                  <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(o.total))}</TableCell>
                  <TableCell>
                    <select value={o.status} onChange={(e) => handleStatusChange(o.id, e.target.value)}
                      className="text-xs border border-[var(--color-border)] rounded px-2 py-1 bg-[var(--color-surface)]">
                      {['draft', 'confirmed', 'received', 'cancelled'].map((k) => <option key={k} value={k}>{t(`orders.statuses.${k}`) as string}</option>)}
                    </select>
                  </TableCell>
                  <TableCell>
                    <button onClick={() => handleDelete(o.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </TableCell>
                </TableRow>
              )
            })}
          </Table>
        </Card>
      )}

      {showForm && <POForm suppliers={suppliers} accounts={accounts} years={years} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function POForm({ suppliers, accounts, years, onClose, onSaved }: { suppliers: Supplier[]; accounts: ChartAccount[]; years: FiscalYear[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('purchases')
  const { t: tCommon } = useTranslation('common')
  const [supplierId, setSupplierId] = useState('')
  const { toast } = useToast()
  const [orderDate, setOrderDate] = useState(new Date().toISOString().split('T')[0])
  const [expectedDate, setExpectedDate] = useState('')
  const [total, setTotal] = useState(0)
  const [notes, setNotes] = useState('')
  const [accountCode, setAccountCode] = useState('')
  const [fiscalYearId, setFiscalYearId] = useState('')
  const [budgetCheck, setBudgetCheck] = useState<BudgetControlResult | null>(null)
  const [checking, setChecking] = useState(false)
  const [saving, setSaving] = useState(false)

  const expenseAccounts = accounts.filter(a => a.type === 'expense')

  async function checkBudget() {
    if (!accountCode || total <= 0) return
    setChecking(true)
    try {
      const result = await checkBudgetAvailability(accountCode, total, fiscalYearId || undefined)
      setBudgetCheck(result)
    } catch (err) { console.error('Budget check error:', err) }
    finally { setChecking(false) }
  }

  useEffect(() => {
    if (accountCode && total > 0) {
      const t = setTimeout(checkBudget, 300)
      return () => clearTimeout(t)
    } else {
      setBudgetCheck(null)
    }
  }, [accountCode, total, fiscalYearId])

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      if (budgetCheck?.would_exceed) {
        if (!window.confirm(t('orders.budgetExceedConfirm', { amount: formatCurrency(total), overshoot: formatCurrency(budgetCheck.overshoot_amount) }))) {
          setSaving(false)
          return
        }
      }
      const number = `CF-${new Date().getFullYear()}-${String(Date.now()).slice(-6)}`
      const po = await createPurchaseOrder({ number, supplier_id: supplierId || null, order_date: orderDate, expected_date: expectedDate || null, status: 'draft', subtotal: total, vat: 0, total, notes: notes || null } as any)
      if (accountCode) {
        await createBudgetCommitment({
          description: `Commande ${number}`,
          account_code: accountCode,
          fiscal_year_id: fiscalYearId || null,
          amount: total,
          commitment_date: orderDate,
          source_type: 'purchase_order',
          source_id: po.id,
          status: 'active',
          supplier_id: supplierId || null,
          notes: notes || null,
        })
      }
      onSaved()
    } catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('orders.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('orders.supplier')}</label>
            <select className="input" value={supplierId} onChange={(e) => setSupplierId(e.target.value)} required>
              <option value="">{tCommon('form.selectPlaceholder')}</option>
              {suppliers.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('orders.orderDate')} type="date" required value={orderDate} onChange={(e) => setOrderDate(e.target.value)} />
            <Input label={t('orders.expectedDate')} type="date" value={expectedDate} onChange={(e) => setExpectedDate(e.target.value)} />
          </div>
          <Input label={t('orders.totalAmount')} type="number" step="0.01" required value={total} onChange={(e) => setTotal(Number(e.target.value))} />
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('orders.budgetAccount')}</label>
              <select className="input" value={accountCode} onChange={(e) => setAccountCode(e.target.value)}>
                <option value="">{t('orders.none')}</option>
                {expenseAccounts.map(a => <option key={a.id} value={a.code}>{a.code} — {a.name}</option>)}
              </select>
            </div>
            <div>
              <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('orders.fiscalYear')}</label>
              <select className="input" value={fiscalYearId} onChange={(e) => setFiscalYearId(e.target.value)}>
                <option value="">{t('orders.allFiscalYears')}</option>
                {years.map(y => <option key={y.id} value={y.id}>{y.code}</option>)}
              </select>
            </div>
          </div>
          {checking && <p className="text-xs text-[var(--color-text-secondary)]">{t('orders.budgetChecking')}</p>}
          {budgetCheck && (
            <div className={`rounded-lg p-3 text-sm ${budgetCheck.would_exceed ? 'bg-red-50 border border-red-200 text-red-700' : 'bg-green-50 border border-green-200 text-green-700'}`}>
              <div className="flex items-start gap-2">
                {budgetCheck.would_exceed && <AlertTriangle className="w-4 h-4 mt-0.5 flex-shrink-0" />}
                <div className="space-y-1">
                  <div className="flex justify-between"><span>{t('orders.budgetTotal')}:</span><span className="font-mono">{formatCurrency(budgetCheck.budget_total)}</span></div>
                  <div className="flex justify-between"><span>{t('orders.budgetRealized')}:</span><span className="font-mono">{formatCurrency(budgetCheck.realized)}</span></div>
                  <div className="flex justify-between"><span>{t('orders.budgetCommitted')}:</span><span className="font-mono">{formatCurrency(budgetCheck.committed)}</span></div>
                  <div className="flex justify-between font-semibold"><span>{t('orders.budgetAvailable')}:</span><span className="font-mono">{formatCurrency(budgetCheck.available)}</span></div>
                  {budgetCheck.would_exceed && (
                    <div className="flex justify-between font-bold"><span>{t('orders.budgetOvershoot')}:</span><span className="font-mono">{formatCurrency(budgetCheck.overshoot_amount)}</span></div>
                  )}
                </div>
              </div>
            </div>
          )}
          <Input label={t('orders.notes')} value={notes} onChange={(e) => setNotes(e.target.value)} />
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
