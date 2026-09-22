import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, SortableTable, TableRow, TableCell, Badge, EmptyState, AutoBreadcrumb, SkeletonTable, Input, Combobox, exportToCSV } from '@/components/ui'
import { getInvoices, createInvoice, updateInvoice } from '@/lib/queries/sales'
import { getCustomers, createCustomerPayment } from '@/lib/queries/partners'
import { transformInvoiceToCreditNote, createAdvanceInvoice } from '@/lib/queries/misc'
import { formatCurrency, formatDate, translateStatus } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import { FileText, Plus, Search, Send, Eye, Download, X, CheckCircle, FileCode, Receipt, DollarSign, UserPlus } from 'lucide-react'
import { generateFacturX, downloadXML } from '@/lib/facturX'
import { getCompanySettings } from '@/lib/queries/accounting'
import { useModuleAwareAccess } from '@/components/cross-module/useModuleAwareAccess'
import { QuickCustomerAccess } from '@/components/cross-module/QuickCustomerAccess'
import type { Invoice, Customer, CompanySettings } from '@/types'
import { usePermission } from '@/hooks/usePermission'
import { nextDocumentNumber } from '@/lib/queries/core'
import { useLegislation } from '@/lib/legislation'

export function InvoicesPage() {
  const { t: tf } = useTranslation('features')
  const { t } = useTranslation('sales')
  const { canCreate } = usePermission('invoices')
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
  const [showAdvanceForm, setShowAdvanceForm] = useState(false)
  const [typeFilter, setTypeFilter] = useState('')

  useEffect(() => {
    loadInvoices().catch(err => console.error('loadInvoices:', err))
  // oxlint-disable-next-line react-hooks/exhaustive-deps -- chargement volontairement limite aux valeurs listees
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
    } catch (err: any) { console.error('Error loading invoices:', err)
    toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError'))
    } finally {
      setLoading(false)
    }
  }

  async function handleSend(id: string) {
    setActionLoading(id)
    try {
      // Un brouillon ne part pas chez le client : la validation attribue le numéro
      // définitif et passe l'écriture, puis la facture est envoyée
      const inv = invoices.find(i => i.id === id)
      if (inv && inv.validation_status !== 'validated') {
        await updateInvoice(id, { validation_status: 'validated' as any })
      }
      await updateInvoice(id, { status: 'sent' })
      toast('success', t('invoices.title'), tCommon('toast.sent'))
      await loadInvoices()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.sendError'))
    } finally {
      setActionLoading(null)
    }
  }

  async function handleValidate(id: string) {
    setActionLoading(id)
    try {
      await updateInvoice(id, { validation_status: 'validated' as any })
      toast('success', t('invoices.title'), tCommon('toast.saved'))
      await loadInvoices()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.updateError'))
    } finally {
      setActionLoading(null)
    }
  }

  async function handleMarkPaid(id: string) {
    setActionLoading(id)
    try {
      const inv = invoices.find(i => i.id === id)
      if (!inv) return
      // Do NOT mutate invoice status directly. Instead record a customer_payment
      // so the balance agée, treasury and accounting stay consistent. A DB
      // trigger is expected to flip the invoice status / payment_state once the
      // payment covers the outstanding amount.
      const amount = Number(inv.amount_due ?? inv.total ?? 0)
      if (amount <= 0) {
        toast('warning', t('invoices.title'), tCommon('toast.updateError'))
        return
      }
      await createCustomerPayment({
        // un numéro par règlement : une facture peut en recevoir plusieurs
        number: await nextDocumentNumber('REG'),
        customer_id: inv.customer_id,
        invoice_id: inv.id,
        payment_date: new Date().toISOString().split('T')[0],
        amount,
        method: 'other',
        bank_account_id: null,
        reference: inv.number || null,
        status: 'recorded',
      })
      toast('success', t('invoices.title'), tCommon('toast.updated'))
      await loadInvoices()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.updateError'))
    } finally {
      setActionLoading(null)
    }
  }

  async function handleCreateCreditNote(inv: Invoice) {
    const reason = window.prompt(t('transformations.creditNoteReason'), '')
    if (!reason) return
    try {
      await transformInvoiceToCreditNote(inv.id, reason)
      toast('success', tCommon('toast.success'), t('transformations.transformationSuccess'))
      await loadInvoices()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || t('transformations.transformationError'))
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
    const content = `${t('invoices.title')} ${inv.number}\n${t('invoices.customer')}: ${inv.customer_name}\n${t('invoices.date')}: ${formatDate(inv.date)}\n${t('invoices.dueDate')}: ${formatDate(inv.due_date)}\n${t('invoices.total')}: ${formatCurrency(Number(inv.total))}\n${t('invoices.balance')}: ${formatCurrency(Number(inv.amount_due))}`
    const blob = new Blob([content], { type: 'text/plain' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `${inv.number}.txt`
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
    const matchesType = !typeFilter || inv.invoice_type === typeFilter || (!inv.invoice_type && typeFilter === 'standard')
    return matchesSearch && matchesFilter && matchesType
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
            <Button variant="secondary" onClick={() => setShowAdvanceForm(true)}><DollarSign className="w-4 h-4" /> {t('invoices.advanceInvoice')}</Button>
            {canCreate && <Button variant="primary" onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('invoices.new')}</Button>}
          </div>
        }
      />

      <div className="flex items-center gap-2 mb-4">
        <select value={typeFilter} onChange={(e) => setTypeFilter(e.target.value)} className="input max-w-[180px]">
          <option value="">{t('invoices.filterByType')}</option>
          <option value="standard">{t('invoices.invoiceTypeStandard')}</option>
          <option value="advance">{t('invoices.invoiceTypeAdvance')}</option>
          <option value="balance">{t('invoices.invoiceTypeBalance')}</option>
          <option value="proforma">{t('invoices.invoiceTypeProforma')}</option>
        </select>
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
              { label: t('invoices.invoiceType'), key: 'invoice_type', sortable: false },
              { label: t('invoices.status'), key: 'status', sortable: true },
              { label: t('invoices.total'), key: 'total', sortable: true, className: 'text-right' },
              { label: t('invoices.balance'), key: 'amount_due', sortable: true, className: 'text-right' },
              { label: 'Compta', key: 'transferred_entry_id', sortable: false },
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
                  <TableCell>
                    <span className="text-xs">
                      {inv.invoice_type === 'advance' ? t('invoices.invoiceTypeAdvance') : inv.invoice_type === 'balance' ? t('invoices.invoiceTypeBalance') : inv.invoice_type === 'proforma' ? t('invoices.invoiceTypeProforma') : t('invoices.invoiceTypeStandard')}
                    </span>
                  </TableCell>
                  <TableCell><Badge variant={st.variant}>{st.label}</Badge></TableCell>
                  <TableCell className="font-medium text-right">{formatCurrency(Number(inv.total) || 0)}</TableCell>
                  <TableCell className={Number(inv.amount_due) > 0 ? 'text-[var(--color-warning-text)] font-medium text-right' : 'text-right'}>
                    {formatCurrency(Number(inv.amount_due) || 0)}
                  </TableCell>
                  <TableCell>{inv.transferred_entry_id ? <Badge variant="success">Comptabilisé</Badge> : <Badge variant="neutral">Non comptabilisé</Badge>}</TableCell>
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
                      {inv.validation_status !== 'validated' && inv.status !== 'cancelled' && (
                        <button onClick={() => handleValidate(inv.id)} disabled={actionLoading === inv.id} className="p-1.5 rounded text-[var(--color-success)] hover:bg-[rgba(0,135,90,0.1)] disabled:opacity-40" title={tCommon('actions.validate')}>
                          {actionLoading === inv.id ? <CheckCircle className="w-4 h-4 animate-pulse" /> : <FileCode className="w-4 h-4" />}
                        </button>
                      )}
                      {inv.validation_status === 'validated' && inv.status !== 'paid' && inv.status !== 'cancelled' && (
                        <button onClick={() => handleMarkPaid(inv.id)} disabled={actionLoading === inv.id} className="p-1.5 rounded text-[var(--color-success)] hover:bg-[rgba(0,135,90,0.1)] disabled:opacity-40" title={t('invoices.markAsPaid')}>
                          <CheckCircle className="w-4 h-4" />
                        </button>
                      )}
                      {inv.validation_status === 'validated' && inv.status !== 'cancelled' && inv.invoice_type !== 'advance' && (
                        <button onClick={() => handleCreateCreditNote(inv)} className="p-1.5 rounded text-[var(--color-danger)] hover:bg-[rgba(204,0,0,0.1)]" title={t('invoices.createCreditNote')}>
                          <Receipt className="w-4 h-4" />
                        </button>
                      )}
                      <button onClick={() => handleDownload(inv)} className="p-1.5 rounded text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-100)]" title={tCommon('actions.download')}>
                        <Download className="w-4 h-4" />
                      </button>
                      {inv.validation_status === 'validated' && inv.status !== 'cancelled' && (
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
            action={canCreate ? <Button variant="primary" onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('invoices.createFirst')}</Button> : undefined}
          />
        )}
      </Card>

      {showForm && (
        <InvoiceForm customers={customers} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadInvoices() }} />
      )}

      {showAdvanceForm && (
        <AdvanceInvoiceForm customers={customers} onClose={() => setShowAdvanceForm(false)} onSaved={() => { setShowAdvanceForm(false); loadInvoices() }} />
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
  const { t: tCross } = useTranslation('crossModule')
  const { getAccessStrategy } = useModuleAwareAccess()
  const commercialStrategy = getAccessStrategy('commercial')
  const [showQuickAddCustomer, setShowQuickAddCustomer] = useState(false)
  const [date, setDate] = useState(new Date().toISOString().split('T')[0])
  const [dueDate, setDueDate] = useState('')
  const { defaultVatRate } = useLegislation()
  const emptyLine = () => ({ description: '', quantity: 1, unit_price: 0, vat_rate: defaultVatRate })
  const [lines, setLines] = useState<{ description: string; quantity: number; unit_price: number; vat_rate: number }[]>([emptyLine()])
  const [saving, setSaving] = useState(false)

  // Aperçu : le serveur fait foi (arrondi au centime par ligne, comme lui)
  const round2 = (n: number) => Math.round(n * 100) / 100
  const lineHt = (l: { quantity: number; unit_price: number }) => round2(Number(l.quantity) * Number(l.unit_price))
  const lineVat = (l: { quantity: number; unit_price: number; vat_rate: number }) => round2(lineHt(l) * Number(l.vat_rate) / 100)
  const filledLines = lines.filter(l => l.description.trim() && lineHt(l) > 0)
  const subtotal = filledLines.reduce((sum, l) => sum + lineHt(l), 0)
  const vatTotal = filledLines.reduce((sum, l) => sum + lineVat(l), 0)
  const total = round2(subtotal + vatTotal)

  function updateLine(idx: number, field: 'description' | 'quantity' | 'unit_price' | 'vat_rate', value: string | number) {
    setLines(prev => prev.map((l, i) => (i === idx ? { ...l, [field]: value } : l)))
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!customerId) { toast('warning', t('invoices.customer'), tCommon('form.requiredField')); return }
    if (filledLines.length === 0) { toast('warning', t('invoices.title'), t('invoices.atLeastOneLine')); return }
    setSaving(true)
    try {
      const customer = customers.find(c => c.id === customerId)
      await createInvoice({
        customer_id: customerId,
        customer_name: customer?.name || '',
        date,
        due_date: dueDate || date,
        status: 'draft',
        subtotal,
        vat_total: vatTotal,
        total,
        amount_paid: 0,
        amount_due: total,
        notes: '',
        recurring: false,
        recurring_frequency: null,
        lines: filledLines.map((l, i) => ({
          product_id: null,
          description: l.description.trim(),
          quantity: Number(l.quantity),
          unit_price: Number(l.unit_price),
          vat_rate: Number(l.vat_rate),
          total: lineHt(l),
          vat_total: lineVat(l),
          vat_amount: lineVat(l),
          line_order: i,
        })),
      })
      toast('success', t('invoices.title'), t('invoices.draftCreated'))
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.createError'))
    } finally {
      setSaving(false)
    }
  }

  const cellInput = 'text-xs border border-[var(--color-border)] rounded px-2 py-1 w-full bg-[var(--color-surface)]'

  return (
    <>
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4 overflow-y-auto">
      <div className="card shadow-2xl overflow-hidden my-8" style={{ width: '100%', maxWidth: '48rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('invoices.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <p className="text-xs text-[var(--color-text-secondary)]">{t('invoices.numberAssigned')}</p>
          <Combobox label={t('invoices.customer')} required value={customerId} onChange={(v) => setCustomerId(v)} placeholder={tCommon('form.selectOption')} options={customers.map(c => ({ value: c.id, label: c.name }))} />
          {commercialStrategy === 'inline' && (
            <button type="button" onClick={() => setShowQuickAddCustomer(true)} className="text-xs text-[var(--color-primary)] flex items-center gap-1 hover:underline">
              <UserPlus className="w-3.5 h-3.5" /> {tCross('customer.add')}
            </button>
          )}
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('invoices.date')} type="date" required value={date} onChange={(e) => setDate(e.target.value)} />
            <Input label={t('invoices.dueDate')} type="date" value={dueDate} onChange={(e) => setDueDate(e.target.value)} />
          </div>

          <div className="border border-[var(--color-border)] rounded-lg overflow-x-auto">
            <table className="app-table min-w-[640px]">
              <thead className="bg-[var(--color-neutral-50)]">
                <tr>
                  <th className="px-3 py-2 text-left text-xs font-semibold">{t('invoices.description')}</th>
                  <th className="px-3 py-2 text-right text-xs font-semibold w-20">{t('invoices.quantity')}</th>
                  <th className="px-3 py-2 text-right text-xs font-semibold w-28">{t('invoices.unitPrice')}</th>
                  <th className="px-3 py-2 text-right text-xs font-semibold w-20">{t('invoices.vatRate')}</th>
                  <th className="px-3 py-2 text-right text-xs font-semibold w-28">{t('invoices.total')}</th>
                  <th className="w-8"></th>
                </tr>
              </thead>
              <tbody>
                {lines.map((line, idx) => (
                  <tr key={idx} className="border-t border-[var(--color-border)]">
                    <td className="px-3 py-2"><input aria-label={t('invoices.description')} value={line.description} onChange={(e) => updateLine(idx, 'description', e.target.value)} className={cellInput} placeholder={t('invoices.description')} /></td>
                    <td className="px-3 py-2"><input aria-label={t('invoices.quantity')} type="number" step="0.01" min={0} value={line.quantity} onChange={(e) => updateLine(idx, 'quantity', Number(e.target.value))} className={cellInput + ' text-right'} /></td>
                    <td className="px-3 py-2"><input aria-label={t('invoices.unitPrice')} type="number" step="0.01" min={0} value={line.unit_price} onChange={(e) => updateLine(idx, 'unit_price', Number(e.target.value))} className={cellInput + ' text-right'} /></td>
                    <td className="px-3 py-2"><input aria-label={t('invoices.vatRate')} type="number" step="0.01" min={0} value={line.vat_rate} onChange={(e) => updateLine(idx, 'vat_rate', Number(e.target.value))} className={cellInput + ' text-right'} /></td>
                    <td className="px-3 py-2 text-right text-xs font-mono">{formatCurrency(lineHt(line) + lineVat(line))}</td>
                    <td className="px-3 py-2">
                      {lines.length > 1 && <button type="button" onClick={() => setLines(prev => prev.filter((_, i) => i !== idx))} className="text-[var(--color-danger)] hover:bg-[var(--color-neutral-100)] rounded p-1" aria-label={tCommon('actions.delete')} title={tCommon('actions.delete')}><X className="w-3 h-3" aria-hidden="true" /></button>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            <button type="button" onClick={() => setLines(prev => [...prev, emptyLine()])} className="w-full py-2 text-sm text-[var(--color-primary)] hover:bg-[var(--color-neutral-50)] border-t border-[var(--color-border)]">
              + {t('invoices.addLine')}
            </button>
          </div>

          <div className="flex justify-end gap-6 text-sm">
            <div><span className="text-[var(--color-text-secondary)]">{t('invoices.subtotal')}: </span><span className="font-mono font-semibold">{formatCurrency(subtotal)}</span></div>
            <div><span className="text-[var(--color-text-secondary)]">{t('invoices.vatAmount')}: </span><span className="font-mono font-semibold">{formatCurrency(vatTotal)}</span></div>
            <div><span className="text-[var(--color-text-secondary)]">{t('invoices.total')}: </span><span className="font-mono font-bold text-base">{formatCurrency(total)}</span></div>
          </div>

          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button variant="secondary" type="button" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" loading={saving}>{tCommon('actions.create')}</Button>
          </div>
        </form>
      </div>
    </div>
    {showQuickAddCustomer && (
      <QuickCustomerAccess
        onClose={() => setShowQuickAddCustomer(false)}
        onSaved={() => { setShowQuickAddCustomer(false); onSaved() }}
      />
    )}
    </>
  )
}

function InvoiceDetailModal({ invoice, onClose }: { invoice: Invoice; onClose: () => void }) {
  const { t } = useTranslation('sales')
  const { t: tAcc } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('invoices.title')} {invoice.number}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <div className="p-6 space-y-3">
          <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">{t('invoices.customer')}</span><span className="font-medium">{invoice.customer_name || '—'}</span></div>
          <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">{t('invoices.date')}</span><span>{formatDate(invoice.date)}</span></div>
          <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">{t('invoices.dueDate')}</span><span>{formatDate(invoice.due_date)}</span></div>
          <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">{t('invoices.status')}</span><Badge variant={invoice.status === 'paid' ? 'success' : invoice.status === 'overdue' ? 'danger' : 'neutral'}>{translateStatus(invoice.status)}</Badge></div>
          {invoice.payment_state && (
            <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">{tAcc('writingsEnhancement.paymentState.' + invoice.payment_state, { defaultValue: invoice.payment_state })}</span><Badge variant={invoice.payment_state === 'paid' ? 'success' : invoice.payment_state === 'partial' ? 'warning' : 'neutral'}>{tAcc('writingsEnhancement.paymentState.' + invoice.payment_state, { defaultValue: invoice.payment_state })}</Badge></div>
          )}
          <div className="flex justify-between text-sm border-t border-[var(--color-border)] pt-3"><span className="text-[var(--color-text-secondary)]">{t('invoices.total')}</span><span className="font-mono font-bold">{formatCurrency(Number(invoice.total))}</span></div>
          <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">{t('invoices.paidAmount')}</span><span className="font-mono text-[var(--color-success)]">{formatCurrency(Number(invoice.amount_paid))}</span></div>
          <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">{t('invoices.balance')}</span><span className="font-mono text-[var(--color-warning-text)]">{formatCurrency(Number(invoice.amount_due))}</span></div>
        </div>
      </div>
    </div>
  )
}

function AdvanceInvoiceForm({ customers, onClose, onSaved }: {
  customers: Customer[]
  onClose: () => void
  onSaved: () => void
}) {
  const { t } = useTranslation('sales')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [customerId, setCustomerId] = useState('')
  const [amount, setAmount] = useState(0)
  const [vatRate, setVatRate] = useState(20)
  const [saving, setSaving] = useState(false)

  const vatAmount = amount * (vatRate / 100)
  const total = amount + vatAmount

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!customerId || amount <= 0) return
    setSaving(true)
    try {
      await createAdvanceInvoice(customerId, amount, vatRate)
      toast('success', tCommon('toast.success'), t('invoices.advanceInvoiceCreated'))
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.createError'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '28rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('invoices.advanceInvoice')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="text-xs font-medium text-[var(--color-text-secondary)] mb-1 block">{t('invoices.customer')} *</label>
            <select required value={customerId} onChange={(e) => setCustomerId(e.target.value)} className="input">
              <option value="">—</option>
              {customers.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="text-xs font-medium text-[var(--color-text-secondary)] mb-1 block">{t('invoices.advanceAmount')} *</label>
              <input type="number" step="0.01" min={0} required value={amount} onChange={(e) => setAmount(Number(e.target.value))} className="input" />
            </div>
            <div>
              <label className="text-xs font-medium text-[var(--color-text-secondary)] mb-1 block">{t('invoices.vatRate')} *</label>
              <input type="number" step="0.01" min={0} max={100} required value={vatRate} onChange={(e) => setVatRate(Number(e.target.value))} className="input" />
            </div>
          </div>
          <div className="flex justify-end gap-4 text-sm">
            <div><span className="text-[var(--color-text-secondary)]">{t('invoices.vatAmount')}: </span><span className="font-mono">{formatCurrency(vatAmount)}</span></div>
            <div><span className="text-[var(--color-text-secondary)]">{t('invoices.total')}: </span><span className="font-mono font-bold">{formatCurrency(total)}</span></div>
          </div>
          <div className="flex justify-end gap-3 pt-2 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
