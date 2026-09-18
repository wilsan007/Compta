import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select, Badge } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getCustomerPayments, createCustomerPayment, deleteCustomerPayment, getCustomers } from '@/lib/queries/partners'
import { getBankAccounts } from '@/lib/queries/banking'
import { getInvoices } from '@/lib/queries/sales'
import { Plus, Trash2, X, CreditCard, RefreshCw } from 'lucide-react'
import { CurrencySelector } from '@/components/CurrencySelector'
import { getLatestRate } from '@/lib/currencyRates'
import type { CustomerPayment, Customer, BankAccount, Invoice } from '@/types'
import { useToast } from '@/lib/toast'
import { confirmSync } from '@/lib/confirm'
import { nextDocumentNumber } from '@/lib/queries/core'

export function CustomerPaymentsPage() {
  const { toast } = useToast()
  const { t } = useTranslation('sales')
  const { t: tCommon } = useTranslation('common')
const [payments, setPayments] = useState<CustomerPayment[]>([])
  const [customers, setCustomers] = useState<Customer[]>([])
  const [banks, setBanks] = useState<BankAccount[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)

  const loadData = useCallback(async () => {
    try {
      const [pays, custs, bks] = await Promise.all([getCustomerPayments(), getCustomers(), getBankAccounts()])
      setPayments(pays || [])
      setCustomers(custs || [])
      setBanks(bks || [])
    } catch (err: any) { console.error('Error:', err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError')) }
    finally { setLoading(false) }
  }, [tCommon, toast])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
    if (!confirmSync(tCommon('form.confirmDelete'))) return
    try { await deleteCustomerPayment(id); await loadData() }
    catch (err: any) { toast('error', tCommon('toast.error'), err.message || tCommon('toast.deleteError')) }
  }

  const totalAmount = payments.reduce((s, p) => s + Number(p.amount), 0)

  return (
    <div>
      <Breadcrumb items={[{ label: t('payments.title') }]} />
      <PageHeader title={t('payments.title')} subtitle={`${payments.length} ${t('payments.title').toLowerCase()} — ${formatCurrency(totalAmount)}`}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('payments.new')}</Button>} />

      {loading ? <SkeletonTable rows={6} cols={6} /> : payments.length === 0 ? (
        <EmptyState icon={<CreditCard className="w-8 h-8" />} title={t('payments.noPayments')} description={t('payments.noPaymentsDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('payments.new')}</Button>} />
      ) : (
        <Card>
          <Table headers={[t('payments.number'), t('payments.customer'), t('payments.date'), t('payments.amount'), t('payments.currency'), t('payments.method'), t('payments.reference'), 'Compta', 'Banque', tCommon('table.actions')]}>
            {payments.map((p) => {
              const cust = customers.find((c) => c.id === p.customer_id)
              return (
                <TableRow key={p.id}>
                  <TableCell className="font-mono text-xs">{p.number}</TableCell>
                  <TableCell className="text-sm">{cust?.name || '—'}</TableCell>
                  <TableCell className="text-xs">{formatDate(p.payment_date)}</TableCell>
                  <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(p.amount))}</TableCell>
                  <TableCell className="font-mono text-xs">{p.currency_code || 'EUR'}</TableCell>
                  <TableCell className="text-xs">{t(`payments.methods.${p.method || 'other'}`)}</TableCell>
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

      {showForm && <PaymentForm customers={customers} banks={banks} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function PaymentForm({ customers, banks, onClose, onSaved }: { customers: Customer[]; banks: BankAccount[]; onClose: () => void; onSaved: () => void }) {
  const [customerId, setCustomerId] = useState('')
  const [invoiceId, setInvoiceId] = useState('')
  const [invoices, setInvoices] = useState<Invoice[]>([])
  const { toast } = useToast()
  const { t } = useTranslation('sales')
  const { t: tCommon } = useTranslation('common')
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
      const number = await nextDocumentNumber('RGT')
      await createCustomerPayment({ number, customer_id: customerId || null, invoice_id: invoiceId || null, payment_date: paymentDate, amount, method: method as any, bank_account_id: bankAccountId || null, reference: reference || null, status: 'recorded', currency_code: currencyCode, exchange_rate: exchangeRate, amount_currency: amountCurrency, exchange_gain_loss: 0 } as any)
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
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('payments.customer')}</label>
            <select className="input" value={customerId} onChange={async (e) => { setCustomerId(e.target.value); setInvoiceId(''); setInvoices([]); if (e.target.value) { try { const all = await getInvoices(); setInvoices((all || []).filter((i) => i.customer_id === e.target.value && i.status !== 'paid')) } catch { /* ignore */ } } }} required>
              <option value="">— {tCommon('form.selectOption')} —</option>
              {customers.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('payments.invoice')}</label>
            <select className="input" value={invoiceId} onChange={(e) => setInvoiceId(e.target.value)} disabled={!customerId}>
              <option value="">— {tCommon('form.selectOption')} —</option>
              {invoices.map((i) => <option key={i.id} value={i.id}>{i.number}</option>)}
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
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('payments.bankAccount')}</label>
            <select className="input" value={bankAccountId} onChange={(e) => setBankAccountId(e.target.value)}>
              <option value="">— {tCommon('form.selectOption')} —</option>
              {banks.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
            </select>
          </div>
          <Input label={t('payments.reference')} value={reference} onChange={(e) => setReference(e.target.value)} />
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
