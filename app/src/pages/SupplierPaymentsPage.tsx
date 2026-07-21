import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getSupplierPayments, createSupplierPayment, deleteSupplierPayment, getSuppliers, getBankAccounts } from '@/lib/queries'
import { Plus, Trash2, X, CreditCard } from 'lucide-react'
import type { SupplierPayment, Supplier, BankAccount } from '@/types'
import { useToast } from '@/lib/toast'
import { useTranslation } from 'react-i18next'

export function SupplierPaymentsPage() {
  const { t } = useTranslation('purchases')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const { toast } = useToast()
const [payments, setPayments] = useState<SupplierPayment[]>([])
  const [suppliers, setSuppliers] = useState<Supplier[]>([])
  const [banks, setBanks] = useState<BankAccount[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)

  const loadData = useCallback(async () => {
    try {
      const [pays, sups, bks] = await Promise.all([getSupplierPayments(), getSuppliers(), getBankAccounts()])
      setPayments(pays || [])
      setSuppliers(sups || [])
      setBanks(bks || [])
    } catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
  if (!window.confirm(t('payments.deleteConfirm'))) return
    try { await deleteSupplierPayment(id); await loadData() }
    catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
  }

  const totalAmount = payments.reduce((s, p) => s + Number(p.amount), 0)

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.purchases') }, { label: t('payments.title') }]} />
      <PageHeader title={t('payments.title')} subtitle={`${payments.length} ${t('payments.title').toLowerCase()} — ${formatCurrency(totalAmount)}`}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('payments.new')}</Button>} />

      {loading ? <SkeletonTable rows={6} cols={6} /> : payments.length === 0 ? (
        <EmptyState icon={<CreditCard className="w-8 h-8" />} title={t('payments.noPayments')} description={t('payments.noPaymentsDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('payments.new')}</Button>} />
      ) : (
        <Card>
          <Table headers={[t('payments.number'), t('payments.supplier'), t('payments.date'), t('payments.amount'), t('payments.method'), t('payments.reference'), t('payments.actions')]}>
            {payments.map((p) => {
              const sup = suppliers.find((s) => s.id === p.supplier_id)
              return (
                <TableRow key={p.id}>
                  <TableCell className="font-mono text-xs">{p.number}</TableCell>
                  <TableCell className="text-sm">{sup?.name || '—'}</TableCell>
                  <TableCell className="text-xs">{formatDate(p.payment_date)}</TableCell>
                  <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(p.amount))}</TableCell>
                  <TableCell className="text-xs">{t(`payments.methods.${p.method || 'other'}`) as string}</TableCell>
                  <TableCell className="font-mono text-xs">{p.reference || '—'}</TableCell>
                  <TableCell>
                    <button onClick={() => handleDelete(p.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </TableCell>
                </TableRow>
              )
            })}
          </Table>
        </Card>
      )}

      {showForm && <PaymentForm suppliers={suppliers} banks={banks} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function PaymentForm({ suppliers, banks, onClose, onSaved }: { suppliers: Supplier[]; banks: BankAccount[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('purchases')
  const { t: tCommon } = useTranslation('common')
  const [supplierId, setSupplierId] = useState('')
  const { toast } = useToast()
  const [amount, setAmount] = useState(0)
  const [paymentDate, setPaymentDate] = useState(new Date().toISOString().split('T')[0])
  const [method, setMethod] = useState('transfer')
  const [bankAccountId, setBankAccountId] = useState('')
  const [reference, setReference] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      const number = `RSF-${new Date().getFullYear()}-${String(Date.now()).slice(-6)}`
      await createSupplierPayment({ number, supplier_id: supplierId || null, purchase_invoice_id: null, payment_date: paymentDate, amount, method: method as any, bank_account_id: bankAccountId || null, reference: reference || null, status: 'recorded' } as any)
      onSaved()
    } catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('payments.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('payments.supplier')}</label>
            <select className="input" value={supplierId} onChange={(e) => setSupplierId(e.target.value)} required>
              <option value="">{tCommon('form.selectPlaceholder')}</option>
              {suppliers.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('payments.amount')} type="number" step="0.01" required value={amount} onChange={(e) => setAmount(Number(e.target.value))} />
            <Input label={t('payments.date')} type="date" required value={paymentDate} onChange={(e) => setPaymentDate(e.target.value)} />
          </div>
          <Select label={t('payments.method')} value={method} onChange={(e) => setMethod(e.target.value)} options={[
            { value: 'transfer', label: t('payments.methods.transfer') }, { value: 'check', label: t('payments.methods.check') }, { value: 'cash', label: t('payments.methods.cash') },
            { value: 'card', label: t('payments.methods.card') }, { value: 'direct_debit', label: t('payments.methods.direct_debit') }, { value: 'other', label: t('payments.methods.other') },
          ]} />
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('payments.bank')}</label>
            <select className="input" value={bankAccountId} onChange={(e) => setBankAccountId(e.target.value)}>
              <option value="">{tCommon('form.selectPlaceholder')}</option>
              {banks.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
            </select>
          </div>
          <Input label={t('payments.reference')} value={reference} onChange={(e) => setReference(e.target.value)} />
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
