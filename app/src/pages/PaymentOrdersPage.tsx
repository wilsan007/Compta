import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getPaymentOrders, createPaymentOrder, updatePaymentOrder, deletePaymentOrder, getBankAccounts, getThirdPartyAccounts } from '@/lib/queries'
import { Plus, Trash2, X, CheckCircle2, Ban, FileText } from 'lucide-react'
import type { PaymentOrder, BankAccount, ThirdPartyAccount } from '@/types'
import { useToast } from '@/lib/toast'

const statusLabels: Record<string, string> = {
  draft: 'Brouillon',
  approved: 'Approuvé',
  executed: 'Exécuté',
  cancelled: 'Annulé',
}

export function PaymentOrdersPage() {
  const { toast } = useToast()
  const { t } = useTranslation('treasury')
  const { t: tCommon } = useTranslation('common')
const [orders, setOrders] = useState<PaymentOrder[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [statusFilter, setStatusFilter] = useState('')

  useEffect(() => { load() }, [])

  async function load() {
  try {
      const data = await getPaymentOrders(statusFilter || undefined)
      setOrders(data || [])
    } catch (err) {
      console.error('Error loading payment orders:', err)
    } finally {
      setLoading(false)
    }
  }

  async function handleStatusChange(id: string, status: string) {
    try { await updatePaymentOrder(id, { status: status as any }); await load() }
    catch (err: any) { toast('error', tCommon('error'), err.message || tCommon('error')) }
  }

  async function handleDelete(id: string) {
    if (!window.confirm(t('paymentOrders.deleteConfirm'))) return
    try { await deletePaymentOrder(id); await load() }
    catch (err: any) { toast('error', tCommon('error'), err.message || tCommon('error')) }
  }

  const totalAmount = orders.reduce((s, o) => s + Number(o.amount), 0)
  const pendingAmount = orders.filter((o) => o.status === 'draft' || o.status === 'approved').reduce((s, o) => s + Number(o.amount), 0)

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('paymentOrders.title') }]} />
      <PageHeader
        title={t('paymentOrders.title')}
        subtitle={t('paymentOrders.count', { count: orders.length, total: formatCurrency(totalAmount) })}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('paymentOrders.new')}</Button>}
      />

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-48">
          <Select label={t('paymentOrders.statusFilter')} value={statusFilter} onChange={(e) => { setStatusFilter(e.target.value); }}
            options={[
              { value: '', label: t('paymentOrders.all') },
              { value: 'draft', label: t('paymentOrders.statuses.draft') },
              { value: 'approved', label: t('paymentOrders.statuses.approved') },
              { value: 'executed', label: t('paymentOrders.statuses.executed') },
              { value: 'cancelled', label: t('paymentOrders.statuses.cancelled') },
            ]}
          />
        </div>
        <Button variant="secondary" onClick={load}>{t('paymentOrders.refresh')}</Button>
        <div className="ml-auto text-sm text-[var(--color-text-secondary)]">
          {t('paymentOrders.pending')} <strong className="font-mono">{formatCurrency(pendingAmount)}</strong>
        </div>
      </div>

      {loading ? (
        <SkeletonTable rows={6} cols={7} />
      ) : orders.length === 0 ? (
        <EmptyState
          icon={<FileText className="w-8 h-8" />}
          title={t('paymentOrders.noOrders')}
          description={t('paymentOrders.noOrdersDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('paymentOrders.new')}</Button>}
        />
      ) : (
        <Card>
          <Table headers={[t('paymentOrders.number'), t('paymentOrders.type'), t('paymentOrders.beneficiary'), t('paymentOrders.amount'), t('paymentOrders.date'), t('paymentOrders.status'), t('paymentOrders.actions')]}>
            {orders.map((o) => (
              <TableRow key={o.id}>
                <TableCell className="font-mono text-xs">{o.number}</TableCell>
                <TableCell className="text-xs">{t(`paymentOrders.types.${o.type}`) || o.type}</TableCell>
                <TableCell className="text-sm">{o.third_party_name || '—'}</TableCell>
                <TableCell className="font-mono text-right">{formatCurrency(Number(o.amount))}</TableCell>
                <TableCell className="text-xs">{formatDate(o.payment_date)}</TableCell>
                <TableCell>
                  <select
                    value={o.status}
                    onChange={(e) => handleStatusChange(o.id, e.target.value)}
                    className="text-xs border border-[var(--color-border)] rounded px-2 py-1 bg-[var(--color-surface)]"
                  >
                    {Object.entries(statusLabels).map(([k]) => <option key={k} value={k}>{t(`paymentOrders.statuses.${k}`)}</option>)}
                  </select>
                </TableCell>
                <TableCell>
                  <div className="flex gap-1">
                    {o.status === 'draft' && (
                      <button onClick={() => handleStatusChange(o.id, 'approved')} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-success)]" title={t('paymentOrders.approve')}>
                        <CheckCircle2 className="w-4 h-4" />
                      </button>
                    )}
                    <button onClick={() => handleStatusChange(o.id, 'cancelled')} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-warning)]" title={t('paymentOrders.cancelBtn')}>
                      <Ban className="w-4 h-4" />
                    </button>
                    <button onClick={() => handleDelete(o.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && (
        <PaymentOrderForm onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); load() }} />
      )}
    </div>
  )
}

function PaymentOrderForm({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('treasury')
  const { t: tCommon } = useTranslation('common')
  const [type, setType] = useState<'sepa_transfer' | 'check' | 'cash' | 'card' | 'other'>('sepa_transfer')
  const { toast } = useToast()
  const [bankAccountId, setBankAccountId] = useState('')
  const [thirdPartyId, setThirdPartyId] = useState('')
  const [thirdPartyName, setThirdPartyName] = useState('')
  const [thirdPartyIban, setThirdPartyIban] = useState('')
  const [amount, setAmount] = useState(0)
  const [paymentDate, setPaymentDate] = useState(new Date().toISOString().split('T')[0])
  const [reference, setReference] = useState('')
  const [description, setDescription] = useState('')
  const [saving, setSaving] = useState(false)
  const [bankAccounts, setBankAccounts] = useState<BankAccount[]>([])
  const [tiers, setTiers] = useState<ThirdPartyAccount[]>([])

  useEffect(() => { loadRef() }, [])

  async function loadRef() {
    try {
      const [ba, tp] = await Promise.all([getBankAccounts(), getThirdPartyAccounts()])
      setBankAccounts(ba || [])
      setTiers(tp || [])
    } catch (err) { console.error('Error loading ref:', err) }
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      const number = `PAY-${new Date().getFullYear()}-${String(Date.now()).slice(-6)}`
      await createPaymentOrder({
        number, type, status: 'draft',
        bank_account_id: bankAccountId || null,
        third_party_id: thirdPartyId || null,
        third_party_name: thirdPartyName || null,
        third_party_iban: thirdPartyIban || null,
        amount, payment_date: paymentDate,
        reference: reference || null,
        description: description || null,
        remise_number: null,
      } as any)
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('error'), err.message || tCommon('error'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('paymentOrders.form.title')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Select label={t('paymentOrders.form.type')} value={type} onChange={(e) => setType(e.target.value as any)} options={[
            { value: 'sepa_transfer', label: t('paymentOrders.types.sepa_transfer') },
            { value: 'check', label: t('paymentOrders.types.check') },
            { value: 'cash', label: t('paymentOrders.types.cash') },
            { value: 'card', label: t('paymentOrders.types.card') },
            { value: 'other', label: t('paymentOrders.types.other') },
          ]} />
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('paymentOrders.form.bankAccount')}</label>
            <select className="input" value={bankAccountId} onChange={(e) => setBankAccountId(e.target.value)}>
              <option value="">{t('paymentOrders.form.selectPlaceholder')}</option>
              {bankAccounts.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('paymentOrders.form.beneficiary')}</label>
            <select className="input" value={thirdPartyId} onChange={(e) => {
              setThirdPartyId(e.target.value)
              const tp = tiers.find((tp) => tp.id === e.target.value)
              setThirdPartyName(tp?.name || '')
            }}>
              <option value="">{t('paymentOrders.form.selectPlaceholder')}</option>
              {tiers.map((tp) => <option key={tp.id} value={tp.id}>{tp.code} — {tp.name}</option>)}
            </select>
          </div>
          <Input label={t('paymentOrders.form.iban')} value={thirdPartyIban} onChange={(e) => setThirdPartyIban(e.target.value)} placeholder={t('paymentOrders.form.ibanPlaceholder')} />
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('paymentOrders.form.amount')} type="number" step="0.01" required value={amount} onChange={(e) => setAmount(Number(e.target.value))} />
            <Input label={t('paymentOrders.form.paymentDate')} type="date" required value={paymentDate} onChange={(e) => setPaymentDate(e.target.value)} />
          </div>
          <Input label={t('paymentOrders.form.reference')} value={reference} onChange={(e) => setReference(e.target.value)} />
          <Input label={t('paymentOrders.form.description')} value={description} onChange={(e) => setDescription(e.target.value)} />
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>{t('paymentOrders.form.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : t('paymentOrders.form.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
