import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select, Badge } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getSupplierPayments, createSupplierPayment, deleteSupplierPayment, getSuppliers } from '@/lib/queries/partners'
import { getBankAccounts } from '@/lib/queries/banking'
import { getPurchaseInvoices } from '@/lib/queries/sales'
import { Plus, Trash2, X, CreditCard, RefreshCw } from 'lucide-react'
import { CurrencySelector } from '@/components/CurrencySelector'
import { getLatestRate } from '@/lib/currencyRates'
import type { SupplierPayment, Supplier, BankAccount, PurchaseInvoice } from '@/types'
import { useToast } from '@/lib/toast'
import { useTranslation } from 'react-i18next'
import { confirmSync } from '@/lib/confirm'
import { nextDocumentNumber } from '@/lib/queries/core'

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
    } catch (err: any) { console.error('Error:', err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError')) }
    finally { setLoading(false) }
  }, [toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
  if (!confirmSync(t('payments.deleteConfirm'))) return
    try { await deleteSupplierPayment(id); await loadData() }
    catch (err: any) { toast('error', tCommon('toast.error'), err.message || tCommon('toast.createError')) }
  }

  const totalAmount = payments.reduce((s, p) => s + Number(p.amount), 0)

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.purchases') }, { label: t('payments.title') }]} />
      <PageHeader title={t('payments.title')} subtitle={t('payments.count', { count: payments.length, total: formatCurrency(totalAmount) })}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('payments.new')}</Button>} />

      {loading ? <SkeletonTable rows={6} cols={6} /> : payments.length === 0 ? (
        <EmptyState icon={<CreditCard className="w-8 h-8" />} title={t('payments.noPayments')} description={t('payments.noPaymentsDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('payments.new')}</Button>} />
      ) : (
        <Card>
          <Table headers={[t('payments.number'), t('payments.supplier'), t('payments.date'), t('payments.amount'), t('payments.currency'), t('payments.method'), t('payments.reference'), 'Compta', 'Banque', t('payments.actions')]}>
            {payments.map((p) => {
              const sup = suppliers.find((s) => s.id === p.supplier_id)
              return (
                <TableRow key={p.id}>
                  <TableCell className="font-mono text-xs">{p.number}</TableCell>
                  <TableCell className="text-sm">{sup?.name || '—'}</TableCell>
                  <TableCell className="text-xs">{formatDate(p.payment_date)}</TableCell>
                  <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(p.amount))}</TableCell>
                  <TableCell className="font-mono text-xs">{p.currency_code || 'EUR'}</TableCell>
                  <TableCell className="text-xs">{t(`payments.methods.${p.method || 'other'}`) as string}</TableCell>
                  <TableCell className="font-mono text-xs">{p.reference || '—'}</TableCell>
                  <TableCell>{p.journal_entry_id || p.journal_posted ? <Badge variant="success">OK</Badge> : <Badge variant="neutral">—</Badge>}</TableCell>
                  <TableCell>{p.bank_transaction_id ? <Badge variant="success">OK</Badge> : <Badge variant="neutral">—</Badge>}</TableCell>
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
  const [purchaseInvoiceId, setPurchaseInvoiceId] = useState('')
  const [purchaseInvoices, setPurchaseInvoices] = useState<PurchaseInvoice[]>([])
  const { toast } = useToast()
  const [amount, setAmount] = useState(0)
  const [paymentDate, setPaymentDate] = useState(new Date().toISOString().split('T')[0])
  const [method, setMethod] = useState('transfer')
  const [bankAccountId, setBankAccountId] = useState('')
  const [reference, setReference] = useState('')
  const [currencyCode, setCurrencyCode] = useState('EUR')
  const [exchangeRate, setExchangeRate] = useState(1.0)
  const [amountCurrency, setAmountCurrency] = useState<number | null>(null)
  const [rateLoading, setRateLoading] = useState(false)
  const [saving, setSaving] = useState(false)

  async function handleRefreshRate() {
    if (currencyCode === 'EUR') { setExchangeRate(1.0); setAmountCurrency(null); return }
    setRateLoading(true)
    try {
      const result = await getLatestRate('EUR', currencyCode)
      if (result) {
        setExchangeRate(result.rate)
        setAmountCurrency(amount * result.rate)
      }
    } catch { /* ignore */ }
    finally { setRateLoading(false) }
  }

  function handleAmountChange(v: number) {
    setAmount(v)
    if (currencyCode !== 'EUR' && exchangeRate && exchangeRate > 0) {
      setAmountCurrency(v * exchangeRate)
    }
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      const number = await nextDocumentNumber('RSF')
      await createSupplierPayment({ number, supplier_id: supplierId || null, purchase_invoice_id: purchaseInvoiceId || null, payment_date: paymentDate, amount, method: method as any, bank_account_id: bankAccountId || null, reference: reference || null, status: 'recorded', currency_code: currencyCode, exchange_rate: exchangeRate, amount_currency: amountCurrency, exchange_gain_loss: 0 } as any)
      onSaved()
    } catch (err: any) { toast('error', tCommon('toast.error'), err.message || tCommon('toast.createError')) }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('payments.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('payments.supplier')}</label>
            <select className="input" value={supplierId} onChange={async (e) => { setSupplierId(e.target.value); setPurchaseInvoiceId(''); setPurchaseInvoices([]); if (e.target.value) { try { const all = await getPurchaseInvoices(); setPurchaseInvoices((all || []).filter((i) => i.supplier_id === e.target.value && i.status !== 'paid')) } catch { /* ignore */ } } }} required>
              <option value="">{tCommon('form.selectPlaceholder')}</option>
              {suppliers.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('payments.invoice')}</label>
            <select className="input" value={purchaseInvoiceId} onChange={(e) => setPurchaseInvoiceId(e.target.value)} disabled={!supplierId}>
              <option value="">{tCommon('form.selectPlaceholder')}</option>
              {purchaseInvoices.map((i) => <option key={i.id} value={i.id}>{i.number}</option>)}
            </select>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('payments.amount')} type="number" step="0.01" required value={amount} onChange={(e) => handleAmountChange(Number(e.target.value))} />
            <Input label={t('payments.date')} type="date" required value={paymentDate} onChange={(e) => setPaymentDate(e.target.value)} />
          </div>
          <div className="grid grid-cols-3 gap-4">
            <div>
              <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('payments.currency')}</label>
              <CurrencySelector value={currencyCode} onChange={(v) => { setCurrencyCode(v); if (v === 'EUR') { setExchangeRate(1.0); setAmountCurrency(null) } }} />
            </div>
            <div>
              <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('payments.exchangeRate')}</label>
              <div className="flex gap-1">
                <input className="input" type="number" step="0.000001" value={exchangeRate} onChange={(e) => setExchangeRate(Number(e.target.value))} disabled={currencyCode === 'EUR'} />
                <button type="button" onClick={handleRefreshRate} disabled={rateLoading || currencyCode === 'EUR'} className="p-2 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)]" title={t('payments.refreshRate')}>
                  <RefreshCw className={`w-4 h-4 ${rateLoading ? 'animate-spin' : ''}`} />
                </button>
              </div>
            </div>
            {currencyCode !== 'EUR' && (
              <Input label={t('payments.amountCurrency')} type="number" step="0.01" value={amountCurrency ?? ''} onChange={(e) => setAmountCurrency(Number(e.target.value))} />
            )}
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
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
