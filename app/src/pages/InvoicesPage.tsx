import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { useNavigate } from 'react-router-dom'
import { Card, PageHeader, Button, SortableTable, TableRow, TableCell, Badge, EmptyState, AutoBreadcrumb, SkeletonTable, Input, Combobox, Modal, exportToCSV } from '@/components/ui'
import { getInvoices, createInvoice, updateInvoice, getOpenAdvanceInvoices, type OpenAdvanceInvoice } from '@/lib/queries/sales'
import { getCustomers, createCustomerPayment } from '@/lib/queries/partners'
import { getProducts } from '@/lib/queries/stock'
import { createAdvanceInvoice } from '@/lib/queries/misc'
import { errorMessage, formatCurrency, formatDate, translateStatus } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import { FileText, Plus, Search, Send, Eye, Download, X, CheckCircle, FileCode, Receipt, DollarSign, UserPlus } from 'lucide-react'
import { generateFacturX, downloadXML, isDraftDocument, lineExemptionReason, type EInvoiceOptions } from '@/lib/facturX'
import { downloadInvoicePdf } from '@/lib/invoicePdf'
import { getCompanySettings } from '@/lib/queries/accounting'
import { getFiscalPositions } from '@/lib/queries/misc'
import { useModuleAwareAccess } from '@/components/cross-module/useModuleAwareAccess'
import { QuickCustomerAccess } from '@/components/cross-module/QuickCustomerAccess'
import { PaymentDialog, type PaymentValues } from '@/components/PaymentDialog'
import type { Invoice, Customer, CompanySettings, Product, FiscalPosition } from '@/types'
import { usePermission } from '@/hooks/usePermission'
import { nextDocumentNumber } from '@/lib/queries/core'
import { useLegislation } from '@/lib/legislation'
import { confirmSync } from '@/lib/confirm'

export function InvoicesPage() {
  const { t: tf } = useTranslation('features')
  const { t } = useTranslation('sales')
  const { canCreate } = usePermission('invoices')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const navigate = useNavigate()
  const [invoices, setInvoices] = useState<Invoice[]>([])
  const [customers, setCustomers] = useState<Customer[]>([])
  const [products, setProducts] = useState<Product[]>([])
  const [fiscalPositions, setFiscalPositions] = useState<FiscalPosition[]>([])
  const [company, setCompany] = useState<CompanySettings | null>(null)
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [filter, setFilter] = useState('all')
  const [showForm, setShowForm] = useState(false)
  const [viewing, setViewing] = useState<Invoice | null>(null)
  const [actionLoading, setActionLoading] = useState<string | null>(null)
  const [paying, setPaying] = useState<Invoice | null>(null)
  const [showAdvanceForm, setShowAdvanceForm] = useState(false)
  const [typeFilter, setTypeFilter] = useState('')

  useEffect(() => {
    loadInvoices().catch(err => console.error('loadInvoices:', err))
  // oxlint-disable-next-line react-hooks/exhaustive-deps -- chargement volontairement limite aux valeurs listees
  }, [])

  async function loadInvoices() {
    try {
      const [inv, cust, comp, prods, positions] = await Promise.all([
        getInvoices(),
        getCustomers(),
        getCompanySettings().catch(() => null),
        getProducts().catch(() => [] as Product[]),
        getFiscalPositions().catch(() => [] as FiscalPosition[]),
      ])
      setInvoices(inv || [])
      setCustomers(cust || [])
      setCompany(comp)
setProducts(prods || [])
      setFiscalPositions(positions || [])
    } catch (err) { console.error('Error loading invoices:', err)
    toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.loadingError'))
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
    } catch (err) {
      toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.sendError'))
    } finally {
      setActionLoading(null)
    }
  }

  async function handleValidate(id: string) {
    // B12 (pil-009) : la validation attribue le numéro définitif et passe
    // l'écriture — une action irréversible, donc confirmée.
    const inv = invoices.find(i => i.id === id)
    if (!confirmSync(t('invoices.confirmValidate', { number: inv?.number ?? '' }))) return
    setActionLoading(id)
    try {
      await updateInvoice(id, { validation_status: 'validated' as any })
      toast('success', t('invoices.title'), tCommon('toast.saved'))
      await loadInvoices()
    } catch (err) {
      toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.updateError'))
    } finally {
      setActionLoading(null)
    }
  }

  // R-08 (décision D-10) : date, montant, mode et compte bancaire sont demandés ;
  // le payé reste le résultat du règlement enregistré, jamais une saisie sur la facture.
  async function handleRecordPayment(inv: Invoice, values: PaymentValues) {
    setActionLoading(inv.id)
    try {
      await createCustomerPayment({
        // un numéro par règlement : une facture peut en recevoir plusieurs
        number: await nextDocumentNumber('REG'),
        customer_id: inv.customer_id,
        invoice_id: inv.id,
        payment_date: values.payment_date,
        amount: values.amount,
        method: values.method,
        bank_account_id: values.bank_account_id,
        reference: values.reference ?? inv.number ?? null,
        status: 'recorded',
      })
      setPaying(null)
      toast('success', t('invoices.title'), tCommon('toast.updated'))
      await loadInvoices()
    } catch (err) {
      toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.updateError'))
    } finally {
      setActionLoading(null)
    }
  }

  async function handleCreateCreditNote(inv: Invoice) {
// B5 (ven-011) : l'action ouvrait un `window.prompt` sans suite mesurable.
    // Elle ouvre désormais l'écran des avoirs, pré-rempli de la facture source
    // (client, lignes, comptes) — c'est la même saisie que « Nouvel avoir ».
    navigate(`/sales/credits?invoice=${inv.id}`)
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
    // B8 (ven-010) : un vrai PDF — vendeur, client, lignes, HT par taux, TVA,
    // TTC et mentions légales — au lieu d'un texte de 156 octets. Un brouillon
    // se télécharge en « PRO FORMA » et le dit (R-11).
    const provisoire = isDraftDocument(inv)
    const customer = customers.find((c) => c.id === inv.customer_id) || null
    downloadInvoicePdf(inv, customer, company, {
      title: t('invoices.title'),
      proForma: provisoire ? t('invoices.proFormaNotice') : '',
      seller: t('invoices.pdfSeller'),
      customer: t('invoices.customer'),
      date: t('invoices.date'),
      dueDate: t('invoices.dueDate'),
      description: t('invoices.description'),
      quantity: t('invoices.quantity'),
      unitPrice: t('invoices.unitPrice'),
      vatRate: t('invoices.vatRate'),
      lineTotal: t('invoices.total'),
      subtotal: t('invoices.subtotal'),
      vatTotal: t('invoices.vatAmount'),
      total: t('invoices.total'),
      balance: t('invoices.balance'),
      mentions: [
        t('invoices.pdfMentionPenalties'),
        t('invoices.pdfMentionIndemnity'),
        t('invoices.pdfMentionDiscount'),
        // B3 (ven-009) : la mention de l'opération non taxée en France
        ...untaxedMentions(inv),
      ],
    })
  }

  // B3 (ven-009) : le régime fiscal du client et les mentions des opérations
  // non taxées en France. Le régime vient de la position fiscale du tiers
  // (migration 323) ; la catégorie Factur-X dépend aussi du type d'article.
  const productTypes: Record<string, string> = Object.fromEntries(products.map((p) => [p.id, String(p.type)]))
  const eInvoiceOptions: EInvoiceOptions = { productTypes }
  const regimeOf = (customerId: string | null | undefined): string | null => {
    const c = customers.find((x) => x.id === customerId)
    if (!c?.fiscal_position_id) return null
    return fiscalPositions.find((p) => p.id === c.fiscal_position_id)?.regime ?? null
  }
  const untaxedMentions = (inv: Invoice): string[] => {
    const lines = (inv.invoice_lines || []) as { vat_code?: string | null; product_id?: string | null }[]
    const reasons = new Set<string>()
    for (const l of lines) {
      const reason = lineExemptionReason(l, productTypes)
      if (reason) reasons.add(reason)
    }
    return [...reasons]
  }

  function handleEInvoice(inv: Invoice) {
    // R-11 : le bouton est masqué sur un brouillon, mais la génération refuse
    // aussi (garde dans facturX.ts) — on ne présente pas une pièce au numéro
    // provisoire comme une facture électronique.
    if (isDraftDocument(inv)) {
      toast('error', tCommon('common.error'), t('invoices.proFormaNotice'))
      return
    }
    const customer = customers.find((c) => c.id === inv.customer_id) || null
    const xml = generateFacturX(inv, customer, company, eInvoiceOptions)
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

  // B9 (ven-015) : « En retard » se calcule — échéance dépassée et reste dû
  // positif — au lieu de dépendre d'un statut que rien ne posait. Un brouillon
  // ou une pièce annulée n'est jamais « en retard » (elle n'est pas due).
  const isOverdue = (inv: Invoice) => {
    if (inv.validation_status !== 'validated' || inv.status === 'cancelled' || inv.status === 'paid') return false
    if (Number(inv.amount_due || 0) <= 0) return false
    if (!inv.due_date) return false
    const today = new Date().toISOString().split('T')[0]
    return String(inv.due_date).slice(0, 10) < today
  }
  const overdueCount = invoices.filter(isOverdue).length

  const filtered = invoices.filter((inv) => {
    const matchesSearch = inv.number?.toLowerCase().includes(search.toLowerCase()) ||
      inv.customer_name?.toLowerCase().includes(search.toLowerCase())
    const matchesFilter = filter === 'all' || (filter === 'overdue' ? isOverdue(inv) : inv.status === filter)
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
        subtitle={`${invoices.length} ${t('invoices.title').toLowerCase()} • ${t('invoices.headerTotal')} ${formatCurrency(totalAmount)} • ${t('invoices.balance')} ${formatCurrency(totalDue)}`}
        action={
          <div className="flex items-center gap-2">
            <Button variant="secondary" onClick={handleExportCSV}><Download className="w-4 h-4" /> {tCommon('actions.export')}</Button>
            <Button variant="secondary" onClick={() => setShowAdvanceForm(true)}><DollarSign className="w-4 h-4" /> {t('invoices.advanceInvoice')}</Button>
            {canCreate && <Button variant="primary" onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('invoices.new')}</Button>}
          </div>
        }
      />

      <div className="flex items-center gap-2 mb-4">
        <select value={typeFilter} onChange={(e) => setTypeFilter(e.target.value)} className="input max-w-[180px]" aria-label={t('invoices.filterByType')} title={t('invoices.filterByType')}>
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
          { value: 'overdue', label: `${tCommon('status.overdue')}${overdueCount ? ` (${overdueCount})` : ''}` },
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
              const st = isOverdue(inv) ? statusMap.overdue : (statusMap[inv.status] || statusMap.draft)
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
                        <button onClick={() => setPaying(inv)} disabled={actionLoading === inv.id} className="p-1.5 rounded text-[var(--color-success)] hover:bg-[rgba(0,135,90,0.1)] disabled:opacity-40" title={t('invoices.markAsPaid')}>
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
            title={filter === 'overdue' ? t('invoices.noOverdue') : t('invoices.noInvoices')}
            description={filter === 'overdue' ? t('invoices.noOverdueDescription') : t('invoices.noInvoicesDescription')}
            action={filter === 'overdue' || !canCreate ? undefined : <Button variant="primary" onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('invoices.createFirst')}</Button>}
          />
        )}
      </Card>

      {showForm && (
        <InvoiceForm customers={customers} products={products} customerRegime={regimeOf} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadInvoices() }} />
      )}

      {showAdvanceForm && (
        <AdvanceInvoiceForm customers={customers} onClose={() => setShowAdvanceForm(false)} onSaved={() => { setShowAdvanceForm(false); loadInvoices() }} />
      )}

      {viewing && (
        <InvoiceDetailModal invoice={viewing} onClose={() => setViewing(null)} />
      )}

      {paying && (
        <PaymentDialog
          title={t('payments.recordFor', { number: paying.number })}
          defaultAmount={Number(paying.amount_due ?? paying.total ?? 0)}
          maxAmount={Number(paying.amount_due ?? paying.total ?? 0)}
          defaultReference={paying.number}
          onSubmit={(values) => handleRecordPayment(paying, values)}
          onClose={() => setPaying(null)}
        />
      )}
    </div>
  )
}

function InvoiceForm({ customers, products, customerRegime, onClose, onSaved }: {
  customers: Customer[]
  products: Product[]
  /** B3 (ven-009) : régime fiscal du client (fr | eu_vat | non_eu | null) */
  customerRegime: (customerId: string) => string | null
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
  // B12 (pil-009) : l'échéance par défaut suit les conditions de paiement du
  // client ; une saisie manuelle la fige (`dueTouched`).
  const [dueTouched, setDueTouched] = useState(false)
  const { defaultVatRate } = useLegislation()
  // B2 (ven-008) : la ligne se choisit dans le catalogue (comme sur le devis) ;
  // une ligne libre porte son propre compte de vente.
  const emptyLine = () => ({ product_id: '', account_code: '', description: '', quantity: 1, unit_price: 0, vat_rate: defaultVatRate })
  const [lines, setLines] = useState<{ product_id: string; account_code: string; description: string; quantity: number; unit_price: number; vat_rate: number }[]>([emptyLine()])
  const [saving, setSaving] = useState(false)
  // R-03 : acomptes validés du client à déduire (ligne négative rattachée à l'acompte)
  const [openAdvances, setOpenAdvances] = useState<OpenAdvanceInvoice[]>([])
  const [deducted, setDeducted] = useState<Record<string, boolean>>({})

  useEffect(() => {
    setOpenAdvances([]); setDeducted({})
    if (!customerId) return
    let cancelled = false
    getOpenAdvanceInvoices(customerId)
      .then(list => { if (!cancelled) setOpenAdvances(list) })
      .catch(() => { if (!cancelled) setOpenAdvances([]) })
    return () => { cancelled = true }
  }, [customerId])

  // Aperçu : le serveur fait foi (arrondi au centime par ligne, comme lui)
  const round2 = (n: number) => Math.round(n * 100) / 100
  const lineHt = (l: { quantity: number; unit_price: number }) => round2(Number(l.quantity) * Number(l.unit_price))
  const lineVat = (l: { quantity: number; unit_price: number; vat_rate: number }) => round2(lineHt(l) * Number(l.vat_rate) / 100)
  const filledLines = lines.filter(l => l.description.trim() && lineHt(l) > 0)
  const deductionLines = openAdvances.filter(a => deducted[a.id]).map(a => ({
    description: t('invoices.advanceDeductionLine', { number: a.number }),
    quantity: 1, unit_price: -a.remaining, vat_rate: a.vat_rate, advance_invoice_id: a.id,
  }))
  const allLines: { description: string; quantity: number; unit_price: number; vat_rate: number; advance_invoice_id?: string; product_id?: string; account_code?: string }[] =
    [...filledLines, ...deductionLines]
  const subtotal = round2(allLines.reduce((sum, l) => sum + lineHt(l), 0))
  const vatTotal = round2(allLines.reduce((sum, l) => sum + lineVat(l), 0))
  const total = round2(subtotal + vatTotal)

  function updateLine(idx: number, field: 'product_id' | 'account_code' | 'description' | 'quantity' | 'unit_price' | 'vat_rate', value: string | number) {
    setLines(prev => prev.map((l, i) => (i === idx ? { ...l, [field]: value } : l)))
  }

  // B2 (ven-008) : choisir un article remplit description, prix, taux et le
  // rattache ; le laisser vide garde la saisie libre et son compte de vente.
  function selectProduct(idx: number, productId: string) {
    const product = products.find(p => p.id === productId)
    setLines(prev => prev.map((l, i) => {
      if (i !== idx) return l
      if (!productId || !product) return { ...l, product_id: '' }
      return {
        ...l,
        product_id: productId,
        description: product.name,
        unit_price: Number(product.sale_price) || 0,
        vat_rate: Number(product.vat_rate) || 0,
      }
    }))
  }

  // B12 : échéance proposée = date + conditions de paiement du client (le
  // premier nombre de « payment_terms », 30 jours par défaut).
  function paymentTermsDays(id: string): number {
    const m = /(\d+)/.exec(customers.find(c => c.id === id)?.payment_terms || '')
    const days = m ? Number(m[1]) : 30
    return Number.isFinite(days) && days >= 0 ? days : 30
  }
  function addDays(iso: string, days: number): string {
    const d = new Date(`${iso || new Date().toISOString().split('T')[0]}T00:00:00Z`)
    d.setUTCDate(d.getUTCDate() + days)
    return d.toISOString().split('T')[0]
  }
  function chooseCustomer(id: string) {
    setCustomerId(id)
    if (!dueTouched) setDueDate(addDays(date, paymentTermsDays(id)))
    // B3 (ven-009) : une facture à un client UE assujetti (ou hors UE) ne porte
    // pas de TVA française — le taux 0 est proposé d'office. La base le pose de
    // toute façon (code UE / EXO, migration 323).
    const regime = customerRegime(id)
    if (regime === 'eu_vat' || regime === 'non_eu') {
      setLines(prev => prev.map(l => ({ ...l, vat_rate: 0 })))
    }
  }

  // B3 : les mentions légales que portera la pièce (autoliquidation, exonération)
  const regime = customerRegime(customerId)
  const untaxedReasons = regime === 'eu_vat' || regime === 'non_eu'
    ? [...new Set(lines.map(l => lineExemptionReason({ vat_code: regime === 'eu_vat' ? 'UE' : 'EXO', product_id: l.product_id }, Object.fromEntries(products.map(p => [p.id, String(p.type)])))).filter(Boolean))]
    : []

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!customerId) { toast('warning', t('invoices.customer'), tCommon('form.requiredField')); return }
    if (filledLines.length === 0) { toast('warning', t('invoices.title'), t('invoices.atLeastOneLine')); return }
    if (total < 0) { toast('warning', t('invoices.title'), t('invoices.advanceExceedsTotal')); return }
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
        lines: allLines.map((l, i) => ({
          product_id: l.product_id || null,
          description: l.description.trim(),
          quantity: Number(l.quantity),
          unit_price: Number(l.unit_price),
          vat_rate: Number(l.vat_rate),
          total: lineHt(l),
          vat_total: lineVat(l),
          vat_amount: lineVat(l),
          line_order: i,
          advance_invoice_id: l.advance_invoice_id ?? null,
          // B2 : une ligne libre porte le compte de vente choisi (706/707) ;
          // avec un article, c'est sa fiche qui le donne.
          account_code: l.product_id ? null : (l.account_code || null),
        })),
      })
      toast('success', t('invoices.title'), t('invoices.draftCreated'))
      onSaved()
    } catch (err) {
      toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.createError'))
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
          <Combobox label={t('invoices.customer')} required value={customerId} onChange={chooseCustomer} placeholder={tCommon('form.selectOption')} options={customers.map(c => ({ value: c.id, label: c.name }))} />
          {commercialStrategy === 'inline' && (
            <button type="button" onClick={() => setShowQuickAddCustomer(true)} className="text-xs text-[var(--color-primary)] flex items-center gap-1 hover:underline">
              <UserPlus className="w-3.5 h-3.5" /> {tCross('customer.add')}
            </button>
          )}
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('invoices.date')} type="date" required value={date} onChange={(e) => { setDate(e.target.value); if (!dueTouched) setDueDate(addDays(e.target.value, paymentTermsDays(customerId))) }} />
            <Input label={t('invoices.dueDate')} type="date" value={dueDate} onChange={(e) => { setDueTouched(true); setDueDate(e.target.value) }} />
          </div>

          <div className="border border-[var(--color-border)] rounded-lg overflow-x-auto">
            <table className="app-table min-w-[720px]">
              <thead className="bg-[var(--color-neutral-50)]">
                <tr>
                  <th className="px-3 py-2 text-left text-xs font-semibold w-40">{t('invoices.product')}</th>
                  <th className="px-3 py-2 text-left text-xs font-semibold">{t('invoices.description')}</th>
                  <th className="px-3 py-2 text-left text-xs font-semibold w-28">{t('invoices.saleAccount')}</th>
                  <th className="px-3 py-2 text-right text-xs font-semibold w-20">{t('invoices.quantity')}</th>
                  <th className="px-3 py-2 text-right text-xs font-semibold w-28">{t('invoices.unitPrice')}</th>
                  <th className="px-3 py-2 text-right text-xs font-semibold w-20">{t('invoices.vatRate')}</th>
                  <th className="px-3 py-2 text-right text-xs font-semibold w-28">{t('invoices.total')}</th>
                  <th className="w-8"></th>
                </tr>
              </thead>
              <tbody>
                {lines.map((line, idx) => {
                  const product = products.find(p => p.id === line.product_id)
                  return (
                  <tr key={idx} className="border-t border-[var(--color-border)]">
                    <td className="px-3 py-2">
                      <select aria-label={t('invoices.product')} title={t('invoices.product')} value={line.product_id} onChange={(e) => selectProduct(idx, e.target.value)} className={cellInput}>
                        <option value="">{t('invoices.freeLine')}</option>
                        {products.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
                      </select>
                    </td>
                    <td className="px-3 py-2"><input aria-label={t('invoices.description')} value={line.description} onChange={(e) => updateLine(idx, 'description', e.target.value)} className={cellInput} placeholder={t('invoices.description')} /></td>
                    <td className="px-3 py-2">
                      {line.product_id ? (
                        <span className="text-xs font-mono text-[var(--color-text-secondary)]" title={t('invoices.saleAccountFromProduct')}>
                          {product?.sale_account_code || (product?.type === 'service' ? '706000' : '707000')}
                        </span>
                      ) : (
                        <select aria-label={t('invoices.saleAccount')} title={t('invoices.saleAccount')} value={line.account_code} onChange={(e) => updateLine(idx, 'account_code', e.target.value)} className={cellInput}>
                          <option value="">{t('invoices.saleAccountDefault')}</option>
                          <option value="706000">{t('invoices.saleAccountService')}</option>
                          <option value="707000">{t('invoices.saleAccountGoods')}</option>
                        </select>
                      )}
                    </td>
                    <td className="px-3 py-2"><input aria-label={t('invoices.quantity')} type="number" step="0.01" min={0} value={line.quantity} onChange={(e) => updateLine(idx, 'quantity', Number(e.target.value))} className={cellInput + ' text-right'} /></td>
                    <td className="px-3 py-2"><input aria-label={t('invoices.unitPrice')} type="number" step="0.01" min={0} value={line.unit_price} onChange={(e) => updateLine(idx, 'unit_price', Number(e.target.value))} className={cellInput + ' text-right'} /></td>
                    <td className="px-3 py-2"><input aria-label={t('invoices.vatRate')} type="number" step="0.01" min={0} value={line.vat_rate} onChange={(e) => updateLine(idx, 'vat_rate', Number(e.target.value))} className={cellInput + ' text-right'} /></td>
                    <td className="px-3 py-2 text-right text-xs font-mono">{formatCurrency(lineHt(line) + lineVat(line))}</td>
                    <td className="px-3 py-2">
                      {lines.length > 1 && <button type="button" onClick={() => setLines(prev => prev.filter((_, i) => i !== idx))} className="text-[var(--color-danger)] hover:bg-[var(--color-neutral-100)] rounded p-1" aria-label={tCommon('actions.delete')} title={tCommon('actions.delete')}><X className="w-3 h-3" aria-hidden="true" /></button>}
                    </td>
                  </tr>
                  )
                })}
              </tbody>
            </table>
            <button type="button" onClick={() => setLines(prev => [...prev, emptyLine()])} className="w-full py-2 text-sm text-[var(--color-primary)] hover:bg-[var(--color-neutral-50)] border-t border-[var(--color-border)]">
              + {t('invoices.addLine')}
            </button>
          </div>

          {untaxedReasons.length > 0 && (
            <p className="text-xs text-[var(--color-text-secondary)] bg-[var(--color-neutral-50)] border border-[var(--color-border)] rounded px-3 py-2">
              <strong>{t('invoices.untaxedMention')}</strong> — {untaxedReasons.join(' · ')}
            </p>
          )}

          {openAdvances.length > 0 && (
            <fieldset className="border border-[var(--color-border)] rounded-lg p-3 space-y-2">
              <legend className="text-xs font-semibold px-1">{t('invoices.advanceDeductions')}</legend>
              {openAdvances.map(a => (
                <label key={a.id} className="flex items-center justify-between gap-3 text-sm">
                  <span className="flex items-center gap-2">
                    <input type="checkbox" checked={!!deducted[a.id]} onChange={(e) => setDeducted(prev => ({ ...prev, [a.id]: e.target.checked }))} />
                    {a.number} — {formatDate(a.date)}
                  </span>
                  <span className="font-mono text-xs">{t('invoices.advanceRemaining', { amount: formatCurrency(a.remaining), rate: a.vat_rate })}</span>
                </label>
              ))}
            </fieldset>
          )}

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

// B6 (ven-006, restitution) : la fenêtre « Voir » n'affichait que l'en-tête et
// trois montants — pas une ligne, pas le HT ni la TVA par taux, alors que la
// liste charge déjà `invoice_lines(*)`. Elle passe au `Modal` commun (E1 :
// corps défilant, piège à focus, Échap) et montre les lignes puis la
// ventilation HT / TVA par taux, comme sur le PDF.
function InvoiceDetailModal({ invoice, onClose }: { invoice: Invoice; onClose: () => void }) {
  const { t } = useTranslation('sales')
  const { t: tAcc } = useTranslation('accounting')
  const lines = (invoice.invoice_lines || [])
    .slice()
    .sort((a, b) => (a.line_order ?? 0) - (b.line_order ?? 0))
  // HT et TVA par taux — la déduction d'acompte (ligne négative) participe
  // à la base, et une ligne autoliquidée (B3) porte son code à côté du taux.
  const vatByRate = new Map<number, { base: number; vat: number; code: string | null }>()
  for (const l of lines) {
    const rate = Number(l.vat_rate) || 0
    const e = vatByRate.get(rate) ?? { base: 0, vat: 0, code: l.vat_code ?? null }
    e.base += Number(l.total) || 0
    e.vat += Number(l.vat_total) || 0
    vatByRate.set(rate, e)
  }
  const rates = [...vatByRate.entries()].sort((a, b) => a[0] - b[0])
  return (
    <Modal open onClose={onClose} title={`${t('invoices.title')} ${invoice.number}`} size="lg">
      <div className="space-y-4 text-sm">
        <div className="space-y-2">
          <div className="flex justify-between"><span className="text-[var(--color-text-secondary)]">{t('invoices.customer')}</span><span className="font-medium">{invoice.customer_name || '—'}</span></div>
          <div className="flex justify-between"><span className="text-[var(--color-text-secondary)]">{t('invoices.date')}</span><span>{formatDate(invoice.date)}</span></div>
          <div className="flex justify-between"><span className="text-[var(--color-text-secondary)]">{t('invoices.dueDate')}</span><span>{formatDate(invoice.due_date)}</span></div>
          <div className="flex justify-between"><span className="text-[var(--color-text-secondary)]">{t('invoices.status')}</span><Badge variant={invoice.status === 'paid' ? 'success' : invoice.status === 'overdue' ? 'danger' : 'neutral'}>{translateStatus(invoice.status)}</Badge></div>
          {invoice.payment_state && (
            <div className="flex justify-between"><span className="text-[var(--color-text-secondary)]">{tAcc('writingsEnhancement.paymentState.' + invoice.payment_state, { defaultValue: invoice.payment_state })}</span><Badge variant={invoice.payment_state === 'paid' ? 'success' : invoice.payment_state === 'partial' ? 'warning' : 'neutral'}>{tAcc('writingsEnhancement.paymentState.' + invoice.payment_state, { defaultValue: invoice.payment_state })}</Badge></div>
          )}
        </div>
        {lines.length > 0 && (
          <div className="border border-[var(--color-border)] rounded-lg overflow-x-auto">
            <table className="app-table w-full">
              <thead className="bg-[var(--color-neutral-50)]">
                <tr>
                  <th className="px-3 py-2 text-left text-xs font-semibold">{t('invoices.description')}</th>
                  <th className="px-3 py-2 text-right text-xs font-semibold w-20">{t('invoices.quantity')}</th>
                  <th className="px-3 py-2 text-right text-xs font-semibold w-28">{t('invoices.unitPrice')}</th>
                  <th className="px-3 py-2 text-right text-xs font-semibold w-24">{t('invoices.vatRate')}</th>
                  <th className="px-3 py-2 text-right text-xs font-semibold w-28">{t('invoices.total')}</th>
                </tr>
              </thead>
              <tbody>
                {lines.map(l => (
                  <tr key={l.id} className="border-t border-[var(--color-border)]">
                    <td className="px-3 py-2">{l.description || '—'}</td>
                    <td className="px-3 py-2 text-right font-mono">{Number(l.quantity)}</td>
                    <td className="px-3 py-2 text-right font-mono">{formatCurrency(Number(l.unit_price) || 0)}</td>
                    <td className="px-3 py-2 text-right font-mono">{Number(l.vat_rate) || 0} %{l.vat_code ? ` (${l.vat_code})` : ''}</td>
                    <td className="px-3 py-2 text-right font-mono">{formatCurrency(Number(l.total) || 0)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <div className="space-y-1.5 border-t border-[var(--color-border)] pt-3">
          {rates.map(([rate, e]) => (
            <div key={rate} className="space-y-1.5">
              <div className="flex justify-between"><span className="text-[var(--color-text-secondary)]">{t('invoices.subtotal')} {rate} %{e.code ? ` (${e.code})` : ''}</span><span className="font-mono">{formatCurrency(e.base)}</span></div>
              <div className="flex justify-between"><span className="text-[var(--color-text-secondary)]">{t('invoices.vatAmount')} {rate} %</span><span className="font-mono">{formatCurrency(e.vat)}</span></div>
            </div>
          ))}
        </div>
        <div className="space-y-1.5 border-t border-[var(--color-border)] pt-3">
          <div className="flex justify-between font-semibold"><span>{t('invoices.subtotal')}</span><span className="font-mono">{formatCurrency(Number(invoice.subtotal) || 0)}</span></div>
          <div className="flex justify-between"><span className="text-[var(--color-text-secondary)]">{t('invoices.vatAmount')}</span><span className="font-mono">{formatCurrency(Number(invoice.vat_total) || 0)}</span></div>
          <div className="flex justify-between border-t border-[var(--color-border)] pt-2 font-bold"><span>{t('invoices.total')}</span><span className="font-mono">{formatCurrency(Number(invoice.total) || 0)}</span></div>
          <div className="flex justify-between"><span className="text-[var(--color-text-secondary)]">{t('invoices.paidAmount')}</span><span className="font-mono text-[var(--color-success)]">{formatCurrency(Number(invoice.amount_paid) || 0)}</span></div>
          <div className="flex justify-between"><span className="text-[var(--color-text-secondary)]">{t('invoices.balance')}</span><span className="font-mono text-[var(--color-warning-text)]">{formatCurrency(Number(invoice.amount_due) || 0)}</span></div>
        </div>
      </div>
    </Modal>
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
    } catch (err) {
      toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.createError'))
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
