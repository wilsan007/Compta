import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, SortableTable, TableRow, TableCell, Badge, EmptyState, AutoBreadcrumb, SkeletonTable, Input, Combobox, exportToCSV } from '@/components/ui'
import { getInvoices, getCustomers, createInvoice, updateInvoice } from '@/lib/queries'
import { formatCurrency, formatDate, translateStatus } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import { FileText, Plus, Search, Send, Eye, Download, X, CheckCircle, FileCode } from 'lucide-react'
import { generateFacturX, downloadXML } from '@/lib/facturX'
import { getCompanySettings } from '@/lib/queries'
import type { Invoice, Customer, CompanySettings } from '@/types'

export function InvoicesPage() {
  const { t: tf } = useTranslation('features')
  const { t } = useTranslation('sales')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [invoices, setInvoices] = useState<Invoice[]>([])
  const [customers, setCustomers] = useState<Customer[]>([])
  const [company, setCompany] = useState<CompanySettings | null>(null)
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [filter, setFilter] = useState('all')
  const [showForm, setShowForm] = useState(false)
  const [viewing, setViewing] = useState<Invoice | null>(null)
  const [actionLoading, setActionLoading] = useState<string | null>(null)

  useEffect(() => {
    loadInvoices()
  }, [])

  async function loadInvoices() {
    try {
      const [inv, cust, comp] = await Promise.all([
        getInvoices(),
        getCustomers(),
        getCompanySettings().catch(() => null),
      ])
      setInvoices(inv || [])
      setCustomers(cust || [])
      setCompany(comp)
    } catch (err) {
      console.error('Error loading invoices:', err)
    } finally {
      setLoading(false)
    }
  }

  async function handleSend(id: string) {
    setActionLoading(id)
    try {
      await updateInvoice(id, { status: 'sent' })
      toast('success', t('invoices.title'), tCommon('toast.sent'))
      await loadInvoices()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.sendError'))
    } finally {
      setActionLoading(null)
    }
  }

  async function handleMarkPaid(id: string) {
    setActionLoading(id)
    try {
      const inv = invoices.find(i => i.id === id)
      if (!inv) return
      await updateInvoice(id, { status: 'paid', amount_paid: inv.total, amount_due: 0 })
      toast('success', t('invoices.title'), tCommon('toast.updated'))
      await loadInvoices()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.updateError'))
    } finally {
      setActionLoading(null)
    }
  }

  function handleExportCSV() {
    const headers = [t('invoices.number'), t('invoices.customer'), t('invoices.date'), t('invoices.dueDate'), t('invoices.status'), t('invoices.total'), t('invoices.balance')]
    const rows = filtered.map((inv) => [
      inv.number || '',
      inv.customer_name || '',
      formatDate(inv.date),
      formatDate(inv.due_date),
      statusMap[inv.status]?.label || inv.status,
      Number(inv.total || 0),
      Number(inv.amount_due || 0),
    ])
    exportToCSV(`factures-${new Date().toISOString().split('T')[0]}.csv`, headers, rows)
    toast('info', tCommon('actions.export'), `${filtered.length} ${t('invoices.title').toLowerCase()} ${tCommon('toast.exported').toLowerCase()}`)
  }

  function handleDownload(inv: Invoice) {
    const content = `FACTURE ${inv.number}\nClient: ${inv.customer_name}\nDate: ${formatDate(inv.date)}\nÉchéance: ${formatDate(inv.due_date)}\nTotal: ${formatCurrency(Number(inv.total))}\nÀ payer: ${formatCurrency(Number(inv.amount_due))}`
    const blob = new Blob([content], { type: 'text/plain' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `facture-${inv.number}.txt`
    a.click()
    URL.revokeObjectURL(url)
  }

  function handleEInvoice(inv: Invoice) {
    const customer = customers.find((c) => c.id === inv.customer_id) || null
    const xml = generateFacturX(inv, customer, company)
    downloadXML(xml, `${inv.number}.factur-x.xml`)
    toast('success', tf('eInvoice.facturXGenerated'), tf('eInvoice.facturXGeneratedDesc', { number: inv.number }))
  }

  const statusMap: Record<string, { variant: 'success' | 'warning' | 'danger' | 'neutral' | 'primary'; label: string }> = {
    draft: { variant: 'neutral', label: tCommon('status.draft') },
    sent: { variant: 'primary', label: tCommon('status.sent') },
    viewed: { variant: 'primary', label: tCommon('status.viewed') },
    paid: { variant: 'success', label: tCommon('status.paid') },
    overdue: { variant: 'danger', label: tCommon('status.overdue') },
    cancelled: { variant: 'neutral', label: tCommon('status.cancelled') },
  }

  const filtered = invoices.filter((inv) => {
    const matchesSearch = inv.number?.toLowerCase().includes(search.toLowerCase()) ||
      inv.customer_name?.toLowerCase().includes(search.toLowerCase())
    const matchesFilter = filter === 'all' || inv.status === filter
    return matchesSearch && matchesFilter
  })

  const totalAmount = filtered.reduce((sum, inv) => sum + Number(inv.total || 0), 0)
  const totalDue = filtered.reduce((sum, inv) => sum + Number(inv.amount_due || 0), 0)

  return (
    <div className="animate-fade-in">
      <AutoBreadcrumb />
      <PageHeader
        title={t('invoices.title')}
        subtitle={`${invoices.length} ${t('invoices.title').toLowerCase()} • ${formatCurrency(totalAmount)} • ${formatCurrency(totalDue)}`}
        action={
          <div className="flex items-center gap-2">
            <Button variant="secondary" onClick={handleExportCSV}><Download className="w-4 h-4" /> {tCommon('actions.export')}</Button>
            <Button variant="primary" onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('invoices.new')}</Button>
          </div>
        }
      />

      <div className="flex items-center gap-2 mb-4">
        {[
          { value: 'all', label: tCommon('filters.all') },
          { value: 'draft', label: tCommon('status.draft') },
          { value: 'sent', label: tCommon('status.sent') },
          { value: 'overdue', label: tCommon('status.overdue') },
          { value: 'paid', label: tCommon('status.paid') },
        ].map((tab) => (
          <button
            key={tab.value}
            onClick={() => setFilter(tab.value)}
            className={`px-3 py-1.5 rounded-md text-sm font-medium transition-colors ${
              filter === tab.value
                ? 'bg-[var(--color-primary)] text-white'
                : 'bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-200)]'
            }`}
          >
            {tab.label}
          </button>
        ))}
      </div>

      <Card>
        <div className="mb-4 relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-text-secondary)]" />
          <input
            className="input pl-10"
            placeholder={t('invoices.searchPlaceholder')}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>

        {loading ? (
          <SkeletonTable rows={5} cols={8} />
        ) : filtered.length > 0 ? (
          <SortableTable
            headers={[
              { label: t('invoices.number'), key: 'number', sortable: true },
              { label: t('invoices.customer'), key: 'customer_name', sortable: true },
              { label: t('invoices.date'), key: 'date', sortable: true },
              { label: t('invoices.dueDate'), key: 'due_date', sortable: true },
              { label: t('invoices.status'), key: 'status', sortable: true },
              { label: t('invoices.total'), key: 'total', sortable: true, className: 'text-right' },
              { label: t('invoices.balance'), key: 'amount_due', sortable: true, className: 'text-right' },
              { label: tCommon('table.actions') },
            ]}
            data={filtered as any}
            initialSortKey="date"
            initialSortDir="desc"
            renderRow={(inv: any) => {
              const st = statusMap[inv.status] || statusMap.draft
              return (
                <TableRow key={inv.id}>
                  <TableCell className="font-medium">{inv.number}</TableCell>
                  <TableCell>{inv.customer_name || '—'}</TableCell>
                  <TableCell>{formatDate(inv.date)}</TableCell>
                  <TableCell>{formatDate(inv.due_date)}</TableCell>
                  <TableCell><Badge variant={st.variant}>{st.label}</Badge></TableCell>
                  <TableCell className="font-medium text-right">{formatCurrency(Number(inv.total) || 0)}</TableCell>
                  <TableCell className={Number(inv.amount_due) > 0 ? 'text-[var(--color-warning)] font-medium text-right' : 'text-right'}>
                    {formatCurrency(Number(inv.amount_due) || 0)}
                  </TableCell>
                  <TableCell>
                    <div className="flex items-center gap-1">
                      <button onClick={() => setViewing(inv)} className="p-1.5 rounded text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-100)]" title={tCommon('actions.view')}>
                        <Eye className="w-4 h-4" />
                      </button>
                      {inv.status === 'draft' && (
                        <button onClick={() => handleSend(inv.id)} disabled={actionLoading === inv.id} className="p-1.5 rounded text-[var(--color-primary)] hover:bg-[rgba(0,102,204,0.1)] disabled:opacity-40" title={tCommon('actions.send')}>
                          {actionLoading === inv.id ? <CheckCircle className="w-4 h-4 animate-pulse" /> : <Send className="w-4 h-4" />}
                        </button>
                      )}
                      {inv.status !== 'paid' && inv.status !== 'cancelled' && (
                        <button onClick={() => handleMarkPaid(inv.id)} disabled={actionLoading === inv.id} className="p-1.5 rounded text-[var(--color-success)] hover:bg-[rgba(0,135,90,0.1)] disabled:opacity-40" title={t('invoices.markAsPaid')}>
                          <CheckCircle className="w-4 h-4" />
                        </button>
                      )}
                      <button onClick={() => handleDownload(inv)} className="p-1.5 rounded text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-100)]" title={tCommon('actions.download')}>
                        <Download className="w-4 h-4" />
                      </button>
                      {inv.status !== 'draft' && inv.status !== 'cancelled' && (
                        <button onClick={() => handleEInvoice(inv)} className="p-1.5 rounded text-[var(--color-primary)] hover:bg-[rgba(0,102,204,0.1)]" title={tf('eInvoice.buttonTitle')}>
                          <FileCode className="w-4 h-4" />
                        </button>
                      )}
                    </div>
                  </TableCell>
                </TableRow>
              )
            }}
          />
        ) : (
          <EmptyState
            icon={<FileText className="w-8 h-8" />}
            title={t('invoices.noInvoices')}
            description={t('invoices.noInvoicesDescription')}
            action={<Button variant="primary" onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('invoices.createFirst')}</Button>}
          />
        )}
      </Card>

      {showForm && (
        <InvoiceForm customers={customers} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadInvoices() }} />
      )}

      {viewing && (
        <InvoiceDetailModal invoice={viewing} onClose={() => setViewing(null)} />
      )}
    </div>
  )
}

function InvoiceForm({ customers, onClose, onSaved }: {
  customers: Customer[]
  onClose: () => void
  onSaved: () => void
}) {
  const [customerId, setCustomerId] = useState('')
  const { toast } = useToast()
  const { t } = useTranslation('sales')
  const { t: tCommon } = useTranslation('common')
  const [date, setDate] = useState(new Date().toISOString().split('T')[0])
  const [dueDate, setDueDate] = useState('')
  const [number, setNumber] = useState('FAC-' + new Date().getFullYear() + '-' + String(Math.floor(Math.random() * 9999)).padStart(3, '0'))
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!customerId) { toast('warning', t('invoices.customer'), tCommon('form.requiredField')); return }
    setSaving(true)
    try {
      const customer = customers.find(c => c.id === customerId)
      await createInvoice({
        number,
        customer_id: customerId,
        customer_name: customer?.name || '',
        date,
        due_date: dueDate || date,
        status: 'draft',
        subtotal: 0,
        vat_total: 0,
        total: 0,
        amount_paid: 0,
        amount_due: 0,
        lines: [],
      } as any)
      toast('success', t('invoices.title'), `${t('invoices.number')} ${number} ${tCommon('toast.created').toLowerCase()}`)
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
          <h2 className="text-lg font-semibold">{t('invoices.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label={t('invoices.number')} required value={number} onChange={(e) => setNumber(e.target.value)} />
          <Combobox label={t('invoices.customer')} required value={customerId} onChange={(v) => setCustomerId(v)} placeholder={tCommon('form.selectOption')} options={customers.map(c => ({ value: c.id, label: c.name }))} />
          <Input label={t('invoices.date')} type="date" required value={date} onChange={(e) => setDate(e.target.value)} />
          <Input label={t('invoices.dueDate')} type="date" value={dueDate} onChange={(e) => setDueDate(e.target.value)} />
          <p className="text-xs text-[var(--color-text-secondary)]">{t('invoices.notes')}</p>
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button variant="secondary" type="button" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" loading={saving}>{tCommon('actions.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}

function InvoiceDetailModal({ invoice, onClose }: { invoice: Invoice; onClose: () => void }) {
  const { t } = useTranslation('sales')
  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('invoices.title')} {invoice.number}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <div className="p-6 space-y-3">
          <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">{t('invoices.customer')}</span><span className="font-medium">{invoice.customer_name || '—'}</span></div>
          <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">{t('invoices.date')}</span><span>{formatDate(invoice.date)}</span></div>
          <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">{t('invoices.dueDate')}</span><span>{formatDate(invoice.due_date)}</span></div>
          <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">{t('invoices.status')}</span><Badge variant={invoice.status === 'paid' ? 'success' : invoice.status === 'overdue' ? 'danger' : 'neutral'}>{translateStatus(invoice.status)}</Badge></div>
          <div className="flex justify-between text-sm border-t border-[var(--color-border)] pt-3"><span className="text-[var(--color-text-secondary)]">{t('invoices.total')}</span><span className="font-mono font-bold">{formatCurrency(Number(invoice.total))}</span></div>
          <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">{t('invoices.paidAmount')}</span><span className="font-mono text-[var(--color-success)]">{formatCurrency(Number(invoice.amount_paid))}</span></div>
          <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">{t('invoices.balance')}</span><span className="font-mono text-[var(--color-warning)]">{formatCurrency(Number(invoice.amount_due))}</span></div>
        </div>
      </div>
    </div>
  )
}
