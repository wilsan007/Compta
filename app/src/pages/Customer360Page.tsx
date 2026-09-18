import { useEffect, useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Badge, SortableTable, TableRow, TableCell, EmptyState, AutoBreadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { getCustomer360, createCustomerContact, updateCustomerContact, deleteCustomerContact } from '@/lib/queries/customerAdvanced'
import { customerCreditScore, checkCustomerCreditLimit } from '@/lib/queries/businessFunctions'
import { formatCurrency, formatDate } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import { ArrowLeft, UserCircle, FileText, CreditCard, Bell, BarChart3, Users, Plus, Trash2, Edit2, AlertTriangle } from 'lucide-react'
import type { CustomerContact, Customer } from '@/types'

type Tab = 'infos' | 'documents' | 'payments' | 'reminders' | 'stats' | 'contacts'

export function Customer360Page() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { t } = useTranslation('sales')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [loading, setLoading] = useState(true)
  const [data, setData] = useState<Awaited<ReturnType<typeof getCustomer360>> | null>(null)
  const [activeTab, setActiveTab] = useState<Tab>('infos')
  const [showContactForm, setShowContactForm] = useState(false)
  const [editingContact, setEditingContact] = useState<CustomerContact | null>(null)
  const [scoringCredit, setScoringCredit] = useState(false)

  async function handleCreditScore() {
    if (!id) return
    setScoringCredit(true)
    try {
      const result = await customerCreditScore(id)
      toast('success', t('customer360.title'), `Score: ${result.score ?? result.credit_score ?? 0}/100 — Rating: ${result.rating ?? result.grade ?? '—'}`)
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    } finally {
      setScoringCredit(false)
    }
  }

  async function handleCheckCreditLimit() {
    if (!id) return
    try {
      const result = await checkCustomerCreditLimit(id)
      const exceeded = result?.exceeded ?? result?.limit_exceeded ?? false
      const used = result?.used ?? result?.credit_used ?? 0
      const limit = result?.limit ?? result?.credit_limit ?? 0
      if (exceeded) {
        toast('warning', 'Limite de crédit', `Limite dépassée — utilisé: ${used} / limite: ${limit}`)
      } else {
        toast('success', 'Limite de crédit', `OK — utilisé: ${used} / limite: ${limit}`)
      }
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    }
  }

  useEffect(() => {
    if (id) loadData().catch(err => console.error('loadData:', err))
  // oxlint-disable-next-line react-hooks/exhaustive-deps -- chargement volontairement limite aux valeurs listees
  }, [id])

  async function loadData() {
    try {
      const result = await getCustomer360(id!)
      setData(result as any)
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    } finally {
      setLoading(false)
    }
  }

  const tabs: { id: Tab; label: string; icon: React.ReactNode }[] = [
    { id: 'infos', label: t('customer360.tabs.infos'), icon: <UserCircle className="w-4 h-4" /> },
    { id: 'documents', label: t('customer360.tabs.documents'), icon: <FileText className="w-4 h-4" /> },
    { id: 'payments', label: t('customer360.tabs.payments'), icon: <CreditCard className="w-4 h-4" /> },
    { id: 'reminders', label: t('customer360.tabs.reminders'), icon: <Bell className="w-4 h-4" /> },
    { id: 'stats', label: t('customer360.tabs.stats'), icon: <BarChart3 className="w-4 h-4" /> },
    { id: 'contacts', label: t('customer360.tabs.contacts'), icon: <Users className="w-4 h-4" /> },
  ]

  if (loading) {
    return (
      <div className="animate-fade-in">
        <SkeletonTable rows={6} cols={4} />
      </div>
    )
  }

  if (!data) {
    return <EmptyState icon={<UserCircle className="w-8 h-8" />} title={t('customer360.title')} description={tCommon('toast.error')} />
  }

  const customer = data.infos as Customer
  const credit = data.credit
  const stats = data.stats

  return (
    <div className="animate-fade-in">
      <AutoBreadcrumb />
      <PageHeader
        title={`${t('customer360.title')} — ${customer?.name || ''}`}
        subtitle={customer?.email || ''}
        action={
          <div className="flex gap-2">
            <Button variant="secondary" onClick={handleCheckCreditLimit}>
              <CreditCard className="w-4 h-4" /> Vérifier la limite de crédit
            </Button>
            <Button variant="secondary" onClick={handleCreditScore} disabled={scoringCredit}>
              <BarChart3 className="w-4 h-4" /> {scoringCredit ? '…' : 'Calculer le score de crédit'}
            </Button>
            <Button variant="secondary" onClick={() => navigate('/sales/customers')}>
              <ArrowLeft className="w-4 h-4" /> {tCommon('actions.back')}
            </Button>
          </div>
        }
      />

      {/* Credit alert */}
      {credit.blocked && (
        <div className="mb-4 p-4 rounded-lg border border-[var(--color-danger)] bg-[rgba(222,53,11,0.05)] flex items-center gap-3">
          <AlertTriangle className="w-5 h-5 text-[var(--color-danger)]" />
          <span className="text-sm font-medium text-[var(--color-danger)]">{t('customer360.creditBlocked')}</span>
        </div>
      )}

      {/* Credit summary */}
      <div className="grid grid-cols-4 gap-4 mb-6">
        <Card className="p-4">
          <p className="text-xs text-[var(--color-text-secondary)]">{t('customer360.creditLimit')}</p>
          <p className="text-lg font-semibold mt-1">{formatCurrency(credit.limit)}</p>
        </Card>
        <Card className="p-4">
          <p className="text-xs text-[var(--color-text-secondary)]">{t('customer360.creditUsed')}</p>
          <p className="text-lg font-semibold mt-1 text-[var(--color-warning)]">{formatCurrency(credit.used)}</p>
        </Card>
        <Card className="p-4">
          <p className="text-xs text-[var(--color-text-secondary)]">{t('customer360.creditAvailable')}</p>
          <p className={`text-lg font-semibold mt-1 ${credit.available < 0 ? 'text-[var(--color-danger)]' : 'text-[var(--color-success)]'}`}>{formatCurrency(credit.available)}</p>
        </Card>
        <Card className="p-4">
          <p className="text-xs text-[var(--color-text-secondary)]">{t('customer360.annualRevenue')}</p>
          <p className="text-lg font-semibold mt-1">{formatCurrency(stats.annualRevenue)}</p>
        </Card>
      </div>

      {/* Tabs */}
      <div className="flex border-b border-[var(--color-border)] mb-4">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            type="button"
            onClick={() => setActiveTab(tab.id)}
            className={`px-4 py-2.5 text-sm font-medium border-b-2 transition-colors flex items-center gap-2 whitespace-nowrap ${
              activeTab === tab.id
                ? 'border-[var(--color-primary)] text-[var(--color-primary)]'
                : 'border-transparent text-[var(--color-text-secondary)] hover:text-[var(--color-text)]'
            }`}
          >
            {tab.icon} {tab.label}
          </button>
        ))}
      </div>

      {/* Tab content */}
      <div className="min-h-[300px]">
        {activeTab === 'infos' && (
          <Card className="p-6 space-y-3">
            <div className="grid grid-cols-2 gap-4">
              <div><span className="text-sm text-[var(--color-text-secondary)]">{t('customers.name')}</span><p className="font-medium">{customer?.name}</p></div>
              <div><span className="text-sm text-[var(--color-text-secondary)]">{t('customers.email')}</span><p className="font-medium">{customer?.email || '—'}</p></div>
              <div><span className="text-sm text-[var(--color-text-secondary)]">{t('customers.phone')}</span><p className="font-medium">{customer?.phone || '—'}</p></div>
              <div><span className="text-sm text-[var(--color-text-secondary)]">{t('customers.vatNumber')}</span><p className="font-medium">{customer?.vat_number || '—'}</p></div>
              <div><span className="text-sm text-[var(--color-text-secondary)]">{t('customers.address')}</span><p className="font-medium">{customer?.address || '—'}</p></div>
              <div><span className="text-sm text-[var(--color-text-secondary)]">{t('customers.paymentTerms')}</span><p className="font-medium">{customer?.payment_terms || '—'}</p></div>
              <div><span className="text-sm text-[var(--color-text-secondary)]">{t('customers.creditLimit')}</span><p className="font-medium">{formatCurrency(customer?.credit_limit || 0)}</p></div>
              <div><span className="text-sm text-[var(--color-text-secondary)]">{t('customers.outstandingBalance')}</span><p className="font-medium">{formatCurrency(customer?.balance || 0)}</p></div>
            </div>
          </Card>
        )}

        {activeTab === 'documents' && (
          <Card>
            {data.invoices.length === 0 && data.quotes.length === 0 && data.orders.length === 0 && data.deliveryNotes.length === 0 ? (
              <EmptyState icon={<FileText className="w-8 h-8" />} title={t('customer360.noDocuments')} />
            ) : (
              <SortableTable
                headers={[
                  { label: t('invoices.number'), key: 'number', sortable: true },
                  { label: t('invoices.status'), key: 'status', sortable: true },
                  { label: t('invoices.date'), key: 'date', sortable: true },
                  { label: t('invoices.amount'), key: 'total', sortable: true, className: 'text-right' },
                ]}
                data={[
                  ...(data.invoices || []).map((i: any) => ({ type: 'invoice', number: i.number, status: i.status, date: i.date, total: Number(i.total || 0) })),
                  ...(data.quotes || []).map((q: any) => ({ type: 'quote', number: q.number, status: q.status, date: q.date, total: Number(q.total || 0) })),
                  ...(data.orders || []).map((o: any) => ({ type: 'order', number: o.number, status: o.status, date: o.date, total: Number(o.total || 0) })),
                  ...(data.deliveryNotes || []).map((d: any) => ({ type: 'delivery', number: d.number, status: d.status, date: d.date, total: 0 })),
                ]}
                initialSortKey="date"
                renderRow={(row: any) => (
                  <TableRow key={`${row.type}-${row.number}`}>
                    <TableCell><Badge variant="neutral">{row.type}</Badge> {row.number}</TableCell>
                    <TableCell><Badge variant={row.status === 'paid' || row.status === 'accepted' || row.status === 'delivered' ? 'success' : row.status === 'overdue' || row.status === 'rejected' ? 'danger' : 'warning'}>{row.status}</Badge></TableCell>
                    <TableCell>{formatDate(row.date)}</TableCell>
                    <TableCell className="text-right">{row.total ? formatCurrency(row.total) : '—'}</TableCell>
                  </TableRow>
                )}
              />
            )}
          </Card>
        )}

        {activeTab === 'payments' && (
          <Card>
            {data.payments.length === 0 ? (
              <EmptyState icon={<CreditCard className="w-8 h-8" />} title={t('customer360.noPayments')} />
            ) : (
              <SortableTable
                headers={[
                  { label: t('payments.number'), key: 'number', sortable: true },
                  { label: t('payments.date'), key: 'payment_date', sortable: true },
                  { label: t('payments.amount'), key: 'amount', sortable: true, className: 'text-right' },
                  { label: t('payments.method'), key: 'method', sortable: true },
                  { label: t('payments.status'), key: 'status', sortable: true },
                ]}
                data={data.payments as any}
                initialSortKey="payment_date"
                renderRow={(p: any) => (
                  <TableRow key={p.id}>
                    <TableCell className="font-mono text-xs">{p.number || p.id.slice(0, 8)}</TableCell>
                    <TableCell>{formatDate(p.payment_date)}</TableCell>
                    <TableCell className="text-right font-medium">{formatCurrency(Number(p.amount || 0))}</TableCell>
                    <TableCell><Badge>{p.method}</Badge></TableCell>
                    <TableCell><Badge variant={p.status === 'completed' || p.status === 'paid' ? 'success' : 'warning'}>{p.status}</Badge></TableCell>
                  </TableRow>
                )}
              />
            )}
          </Card>
        )}

        {activeTab === 'reminders' && (
          <Card>
            {data.reminders.length === 0 ? (
              <EmptyState icon={<Bell className="w-8 h-8" />} title={t('customer360.noReminders')} />
            ) : (
              <SortableTable
                headers={[
                  { label: t('customer360.reminderDate'), key: 'created_at', sortable: true },
                  { label: t('customer360.reminderLevel'), key: 'level', sortable: true },
                  { label: t('customer360.reminderStatus'), key: 'status', sortable: true },
                ]}
                data={data.reminders as any}
                initialSortKey="created_at"
                renderRow={(r: any) => (
                  <TableRow key={r.id}>
                    <TableCell>{formatDate(r.created_at)}</TableCell>
                    <TableCell><Badge variant={r.level === 'final' ? 'danger' : 'warning'}>{r.level}</Badge></TableCell>
                    <TableCell><Badge>{r.status}</Badge></TableCell>
                  </TableRow>
                )}
              />
            )}
          </Card>
        )}

        {activeTab === 'stats' && (
          <div className="grid grid-cols-2 gap-4">
            <Card className="p-6">
              <p className="text-sm text-[var(--color-text-secondary)]">{t('customer360.annualRevenue')}</p>
              <p className="text-2xl font-bold mt-2">{formatCurrency(stats.annualRevenue)}</p>
            </Card>
            <Card className="p-6">
              <p className="text-sm text-[var(--color-text-secondary)]">{t('customer360.invoicesCount')}</p>
              <p className="text-2xl font-bold mt-2">{stats.invoicesCount}</p>
            </Card>
            <Card className="p-6">
              <p className="text-sm text-[var(--color-text-secondary)]">{t('customer360.avgPaymentDelay')}</p>
              <p className="text-2xl font-bold mt-2">{stats.avgPaymentDelay} {t('customer360.days')}</p>
            </Card>
            <Card className="p-6">
              <p className="text-sm text-[var(--color-text-secondary)]">{t('customer360.topProducts')}</p>
              <div className="mt-2 space-y-1">
                {stats.topProducts.map((p: any, i: number) => (
                  <div key={i} className="flex justify-between text-sm">
                    <span>{p.name}</span>
                    <span className="font-medium">{p.quantity}</span>
                  </div>
                ))}
                {stats.topProducts.length === 0 && <p className="text-sm text-[var(--color-text-secondary)]">—</p>}
              </div>
            </Card>
          </div>
        )}

        {activeTab === 'contacts' && (
          <Card className="p-6">
            <div className="flex justify-end mb-3">
              <Button variant="primary" onClick={() => { setEditingContact(null); setShowContactForm(true) }}>
                <Plus className="w-4 h-4" /> {t('customer360.addContact')}
              </Button>
            </div>
            {showContactForm && (
              <ContactForm
                customerId={id!}
                contact={editingContact}
                onClose={() => { setShowContactForm(false); setEditingContact(null) }}
                onSaved={() => { setShowContactForm(false); setEditingContact(null); loadData() }}
              />
            )}
            {data.contacts.length === 0 ? (
              <EmptyState icon={<Users className="w-8 h-8" />} title={t('customer360.noContacts')} />
            ) : (
              <SortableTable
                headers={[
                  { label: t('customer360.contactName'), key: 'name', sortable: true },
                  { label: t('customer360.contactRole'), key: 'role', sortable: true },
                  { label: t('customer360.contactEmail'), key: 'email', sortable: true },
                  { label: t('customer360.contactPhone'), key: 'phone', sortable: true },
                  { label: t('customer360.contactDefault'), key: 'is_default', sortable: true },
                  { label: tCommon('table.actions') },
                ]}
                data={data.contacts as any}
                initialSortKey="name"
                renderRow={(c: any) => (
                  <TableRow key={c.id}>
                    <TableCell className="font-medium">{c.name}</TableCell>
                    <TableCell><Badge variant="neutral">{c.role || '—'}</Badge></TableCell>
                    <TableCell>{c.email || '—'}</TableCell>
                    <TableCell>{c.phone || c.mobile || '—'}</TableCell>
                    <TableCell>{c.is_default ? <Badge variant="success">{tCommon('common.yes')}</Badge> : '—'}</TableCell>
                    <TableCell>
                      <div className="flex gap-1">
                        <Button variant="secondary" size="sm" onClick={() => { setEditingContact(c); setShowContactForm(true) }} ariaLabel={tCommon('actions.edit')}><Edit2 className="w-3 h-3" aria-hidden="true" /></Button>
                        <Button variant="danger" size="sm" onClick={async () => {
                          try { await deleteCustomerContact(c.id); toast('success', t('customer360.title'), tCommon('toast.deleted')); loadData() }
                          catch (e: any) { toast('error', tCommon('toast.error'), e.message) }
                        }} ariaLabel={tCommon('actions.delete')}><Trash2 className="w-3 h-3" aria-hidden="true" /></Button>
                      </div>
                    </TableCell>
                  </TableRow>
                )}
              />
            )}
          </Card>
        )}
      </div>
    </div>
  )
}

function ContactForm({ customerId, contact, onClose, onSaved }: {
  customerId: string
  contact: CustomerContact | null
  onClose: () => void
  onSaved: () => void
}) {
  const { t } = useTranslation('sales')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [form, setForm] = useState({
    name: contact?.name || '',
    role: contact?.role || '',
    email: contact?.email || '',
    phone: contact?.phone || '',
    mobile: contact?.mobile || '',
    is_default: contact?.is_default || false,
    active: contact?.active ?? true,
    notes: contact?.notes || '',
  })
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!form.name.trim()) { toast('warning', tCommon('form.requiredField'), t('customer360.contactName')); return }
    setSaving(true)
    try {
      const data = { ...form, customer_id: customerId }
      if (contact) {
        await updateCustomerContact(contact.id, data as any)
        toast('success', t('customer360.title'), tCommon('toast.updated'))
      } else {
        await createCustomerContact(data as any)
        toast('success', t('customer360.title'), tCommon('toast.created'))
      }
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    } finally {
      setSaving(false)
    }
  }

  return (
    <Card className="p-4 mb-4 space-y-3">
      <form onSubmit={handleSubmit} className="space-y-3">
        <div className="grid grid-cols-2 gap-3">
          <Input label={t('customer360.contactName')} required value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} />
          <Select label={t('customer360.contactRole')} value={form.role || ''} onChange={e => setForm({ ...form, role: e.target.value })}
            options={[
              { value: '', label: '—' },
              { value: 'billing', label: t('customer360.roleBilling') },
              { value: 'delivery', label: t('customer360.roleDelivery') },
              { value: 'technical', label: t('customer360.roleTechnical') },
              { value: 'sales', label: t('customer360.roleSales') },
              { value: 'other', label: t('customer360.roleOther') },
            ]} />
        </div>
        <div className="grid grid-cols-2 gap-3">
          <Input label={t('customer360.contactEmail')} type="email" value={form.email} onChange={e => setForm({ ...form, email: e.target.value })} />
          <Input label={t('customer360.contactPhone')} value={form.phone} onChange={e => setForm({ ...form, phone: e.target.value })} />
        </div>
        <Input label={t('customer360.contactMobile')} value={form.mobile} onChange={e => setForm({ ...form, mobile: e.target.value })} />
        <div className="flex items-center gap-4">
          <label className="flex items-center gap-2"><input type="checkbox" checked={form.is_default} onChange={e => setForm({ ...form, is_default: e.target.checked })} /> {t('customer360.contactDefault')}</label>
          <label className="flex items-center gap-2"><input type="checkbox" checked={form.active} onChange={e => setForm({ ...form, active: e.target.checked })} /> {t('customer360.contactActive')}</label>
        </div>
        <div className="flex gap-2">
          <Button type="submit" loading={saving}>{tCommon('actions.save')}</Button>
          <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
        </div>
      </form>
    </Card>
  )
}
