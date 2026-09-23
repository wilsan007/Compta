import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, SortableTable, TableRow, TableCell, Badge, EmptyState, AutoBreadcrumb, SkeletonTable, Input, Combobox, exportToCSV } from '@/components/ui'
import { getPurchaseInvoices, createPurchaseInvoice } from '@/lib/queries/sales'
import { getSuppliers, createSupplierPayment } from '@/lib/queries/partners'
import { nextDocumentNumber } from '@/lib/queries/core'
import { getChartAccounts, getFiscalYears, checkBudgetAvailability, createBudgetCommitment } from '@/lib/queries/accounting'
import { performThreeWayMatch } from '@/lib/queries/businessFunctions'
import { formatCurrency, formatDate, translateStatus } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import { Package, Plus, Search, Eye, X, CheckCircle, Download, AlertTriangle, UserPlus, ShieldCheck } from 'lucide-react'
import { useModuleAwareAccess } from '@/components/cross-module/useModuleAwareAccess'
import { QuickSupplierAccess } from '@/components/cross-module/QuickSupplierAccess'
import type { PurchaseInvoice, Supplier, ChartAccount, FiscalYear, BudgetControlResult } from '@/types'
import { confirmSync } from '@/lib/confirm'
import { usePermission } from '@/hooks/usePermission'
import { useLegislation } from '@/lib/legislation'
import { PaymentDialog, type PaymentValues } from '@/components/PaymentDialog'

export function PurchaseInvoicesPage() {
  const { toast } = useToast()
  const { t } = useTranslation('purchases')
  const { canCreate } = usePermission('purchase_invoices')
  const { t: tCommon } = useTranslation('common')
  const [invoices, setInvoices] = useState<PurchaseInvoice[]>([])
  const [suppliers, setSuppliers] = useState<Supplier[]>([])
  const [accounts, setAccounts] = useState<ChartAccount[]>([])
  const [years, setYears] = useState<FiscalYear[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [showForm, setShowForm] = useState(false)
  const [viewing, setViewing] = useState<PurchaseInvoice | null>(null)
  const [actionLoading, setActionLoading] = useState<string | null>(null)
  const [paying, setPaying] = useState<PurchaseInvoice | null>(null)

  useEffect(() => {
    loadInvoices().catch(err => console.error('loadInvoices:', err))
  // oxlint-disable-next-line react-hooks/exhaustive-deps -- chargement volontairement limite aux valeurs listees
  }, [])

  async function loadInvoices() {
    try {
      const [inv, sup, accs, fys] = await Promise.all([getPurchaseInvoices(), getSuppliers(), getChartAccounts(), getFiscalYears()])
      setInvoices(inv || [])
      setSuppliers(sup || [])
      setAccounts(accs || [])
      setYears(fys || [])
    } catch (err: any) { console.error('Error loading purchase invoices:', err)
    toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadingError'))
    } finally {
      setLoading(false)
    }
  }

  // R-08 (décision D-10) : le décaissement demande date, montant, mode et compte bancaire
  async function handleRecordPayment(inv: PurchaseInvoice, values: PaymentValues) {
    setActionLoading(inv.id)
    try {
      await createSupplierPayment({
        number: await nextDocumentNumber('DEC'),
        supplier_id: inv.supplier_id,
        purchase_invoice_id: inv.id,
        payment_date: values.payment_date,
        amount: values.amount,
        method: values.method,
        bank_account_id: values.bank_account_id,
        reference: values.reference ?? inv.supplier_reference ?? inv.number ?? null,
        status: 'recorded',
      })
      setPaying(null)
      toast('success', t('purchaseInvoices.markedPaid'))
      await loadInvoices()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.updateError'))
    } finally {
      setActionLoading(null)
    }
  }

  async function handleThreeWayMatch(id: string) {
    setActionLoading('3way-' + id)
    try {
      const result = await performThreeWayMatch(id)
      const matched = result?.matched ?? result?.success ?? false
      const discrepancies = result?.discrepancies || result?.discrepancy_count || 0
      if (matched) {
        toast('success', 'Rapprochement 3 voies', `Conforme — ${discrepancies} écart(s)`)
      } else {
        toast('warning', 'Rapprochement 3 voies', `Écarts détectés — ${discrepancies} différence(s)`)
      }
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.updateError'))
    } finally {
      setActionLoading(null)
    }
  }

  function handleExportCSV() {
    const headers = [t('purchaseInvoices.number'), t('purchaseInvoices.supplier'), tCommon('common.date'), t('purchaseInvoices.dueDate'), tCommon('common.status'), t('purchaseInvoices.total'), t('purchaseInvoices.toPay')]
    const rows = filtered.map((inv) => [
      inv.number || '',
      inv.supplier_name || '',
      formatDate(inv.date),
      formatDate(inv.due_date),
      statusMap[inv.status]?.label || translateStatus(inv.status),
      Number(inv.total || 0),
      Number(inv.amount_due || 0),
    ])
    exportToCSV(`factures-achat-${new Date().toISOString().split('T')[0]}.csv`, headers, rows)
    toast('info', tCommon('toast.exportCSV'), tCommon('toast.exportedCount', { count: filtered.length }))
  }

  const statusMap: Record<string, { variant: 'success' | 'warning' | 'danger' | 'neutral' | 'primary'; label: string }> = {
    draft: { variant: 'neutral', label: t('invoices.statuses.draft') as string },
    received: { variant: 'primary', label: t('invoices.statuses.received') as string },
    paid: { variant: 'success', label: t('invoices.statuses.paid') as string },
    overdue: { variant: 'danger', label: t('invoices.statuses.overdue') as string },
    cancelled: { variant: 'neutral', label: t('invoices.statuses.cancelled') as string },
  }

  const filtered = invoices.filter((inv) =>
    inv.number?.toLowerCase().includes(search.toLowerCase()) ||
    inv.supplier_name?.toLowerCase().includes(search.toLowerCase())
  )

  const totalAmount = filtered.reduce((sum, inv) => sum + Number(inv.total || 0), 0)
  const totalDue = filtered.reduce((sum, inv) => sum + Number(inv.amount_due || 0), 0)

  return (
    <div className="animate-fade-in">
      <AutoBreadcrumb />
      <PageHeader
        title={t('purchaseInvoices.title')}
        subtitle={`${invoices.length} ${t('purchaseInvoices.invoices')} • ${formatCurrency(totalAmount)} ${tCommon('common.total')} • ${formatCurrency(totalDue)} ${t('purchaseInvoices.toPay')}`}
        action={
          <div className="flex items-center gap-2">
            <Button variant="secondary" onClick={handleExportCSV}><Download className="w-4 h-4" /> {tCommon('actions.export')}</Button>
            {canCreate && <Button variant="primary" onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('purchaseInvoices.new')}</Button>}
          </div>
        }
      />

      <Card>
        <div className="mb-4 relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-text-secondary)]" />
          <input
            className="input pl-10"
            placeholder={t('purchaseInvoices.searchPlaceholder')}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>

        {loading ? (
          <SkeletonTable rows={5} cols={8} />
        ) : filtered.length > 0 ? (
          <SortableTable
            headers={[
              { label: t('purchaseInvoices.number'), key: 'number', sortable: true },
              { label: t('purchaseInvoices.supplier'), key: 'supplier_name', sortable: true },
              { label: tCommon('common.date'), key: 'date', sortable: true },
              { label: t('purchaseInvoices.dueDate'), key: 'due_date', sortable: true },
              { label: tCommon('common.status'), key: 'status', sortable: true },
              { label: t('purchaseInvoices.total'), key: 'total', sortable: true, className: 'text-right' },
              { label: t('purchaseInvoices.toPay'), key: 'amount_due', sortable: true, className: 'text-right' },
              { label: 'Compta', key: 'transferred_entry_id', sortable: false },
              { label: tCommon('table.actions') },
            ]}
            data={filtered as any}
            initialSortKey="date"
            initialSortDir="desc"
            renderRow={(inv: any) => {
              const st = statusMap[inv.status] || { variant: 'neutral' as const, label: translateStatus(inv.status) }
              return (
                <TableRow key={inv.id}>
                  <TableCell className="font-medium">{inv.number}</TableCell>
                  <TableCell>{inv.supplier_name || '—'}</TableCell>
                  <TableCell>{formatDate(inv.date)}</TableCell>
                  <TableCell>{formatDate(inv.due_date)}</TableCell>
                  <TableCell><Badge variant={st.variant}>{st.label}</Badge></TableCell>
                  <TableCell className="font-medium text-right">{formatCurrency(Number(inv.total) || 0)}</TableCell>
                  <TableCell className={Number(inv.amount_due) > 0 ? 'text-[var(--color-danger)] font-medium text-right' : 'text-right'}>
                    {formatCurrency(Number(inv.amount_due) || 0)}
                  </TableCell>
                  <TableCell>{inv.transferred_entry_id ? <Badge variant="success">Comptabilisé</Badge> : <Badge variant="neutral">Non comptabilisé</Badge>}</TableCell>
                  <TableCell>
                    <div className="flex items-center gap-1">
                      <button onClick={() => setViewing(inv)} className="p-1.5 rounded text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-100)]" title={tCommon('actions.view')}>
                        <Eye className="w-4 h-4" />
                      </button>
                      {inv.approval_status === 'approved' && inv.status !== 'paid' && inv.status !== 'cancelled' && (
                        <button onClick={() => setPaying(inv)} disabled={actionLoading === inv.id} className="p-1.5 rounded text-[var(--color-success)] hover:bg-[rgba(0,135,90,0.1)] disabled:opacity-40" title={t('purchaseInvoices.markPaid')}>
                          <CheckCircle className="w-4 h-4" />
                        </button>
                      )}
                      <button onClick={() => handleThreeWayMatch(inv.id)} disabled={actionLoading === '3way-' + inv.id} className="p-1.5 rounded text-[var(--color-primary)] hover:bg-[var(--color-neutral-100)] disabled:opacity-40" title="Rapprochement 3 voies">
                        <ShieldCheck className="w-4 h-4" />
                      </button>
                    </div>
                  </TableCell>
                </TableRow>
              )
            }}
          />
        ) : (
          <EmptyState
            icon={<Package className="w-8 h-8" />}
            title={t('purchaseInvoices.noInvoices')}
            description={t('purchaseInvoices.noInvoicesDescription')}
            action={canCreate ? <Button variant="primary" onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('purchaseInvoices.recordPurchase')}</Button> : undefined}
          />
        )}
      </Card>

      {showForm && (
        <PurchaseInvoiceForm suppliers={suppliers} accounts={accounts} years={years} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadInvoices() }} />
      )}

      {viewing && (
        <PurchaseInvoiceDetailModal invoice={viewing} onClose={() => setViewing(null)} />
      )}

      {paying && (
        <PaymentDialog
          title={t('payments.recordFor', { number: paying.supplier_reference || paying.number })}
          defaultAmount={Number(paying.amount_due ?? paying.total ?? 0)}
          maxAmount={Number(paying.amount_due ?? paying.total ?? 0)}
          defaultReference={paying.supplier_reference || paying.number}
          overpaidNotice={(excess) => t('payments.overpaidNotice', { amount: excess })}
          onSubmit={(values) => handleRecordPayment(paying, values)}
          onClose={() => setPaying(null)}
        />
      )}

    </div>
  )
}

function PurchaseInvoiceForm({ suppliers, accounts, years, onClose, onSaved }: {
  suppliers: Supplier[]
  accounts: ChartAccount[]
  years: FiscalYear[]
  onClose: () => void
  onSaved: () => void
}) {
  const [supplierId, setSupplierId] = useState('')
  const { toast } = useToast()
  const { t } = useTranslation('purchases')
  const { t: tCommon } = useTranslation('common')
  const { t: tCross } = useTranslation('crossModule')
  const { getAccessStrategy } = useModuleAwareAccess()
  const commercialStrategy = getAccessStrategy('commercial')
  const [showQuickAddSupplier, setShowQuickAddSupplier] = useState(false)
  // AUD-G02 : le numéro interne ACH-<exercice>-n est attribué par le serveur à
  // l'approbation ; l'écran saisit le numéro de la facture reçue du fournisseur
  const [supplierRef, setSupplierRef] = useState('')
  const [date, setDate] = useState(new Date().toISOString().split('T')[0])
  const [dueDate, setDueDate] = useState('')
  const { defaultVatRate } = useLegislation()
  const emptyLine = () => ({ description: '', quantity: 1, unit_price: 0, vat_rate: defaultVatRate })
  const [lines, setLines] = useState<{ description: string; quantity: number; unit_price: number; vat_rate: number }[]>([emptyLine()])
  const [accountCode, setAccountCode] = useState('')
  const [fiscalYearId, setFiscalYearId] = useState('')
  const [budgetCheck, setBudgetCheck] = useState<BudgetControlResult | null>(null)
  const [checking, setChecking] = useState(false)
  const [saving, setSaving] = useState(false)

  const expenseAccounts = accounts.filter(a => a.type === 'expense')
  // Aperçu : le serveur recalcule chaque ligne au centime
  const round2 = (n: number) => Math.round(n * 100) / 100
  const lineHt = (l: { quantity: number; unit_price: number }) => round2(Number(l.quantity) * Number(l.unit_price))
  const lineVat = (l: { quantity: number; unit_price: number; vat_rate: number }) => round2(lineHt(l) * Number(l.vat_rate) / 100)
  const filledLines = lines.filter(l => l.description.trim() && lineHt(l) > 0)
  const subtotal = filledLines.reduce((sum, l) => sum + lineHt(l), 0)
  const vatTotal = filledLines.reduce((sum, l) => sum + lineVat(l), 0)
  const total = round2(subtotal + vatTotal)
  // Le budget se contrôle hors taxe
  const totalNum = subtotal

  function updateLine(idx: number, field: 'description' | 'quantity' | 'unit_price' | 'vat_rate', value: string | number) {
    setLines(prev => prev.map((l, i) => (i === idx ? { ...l, [field]: value } : l)))
  }

  // Contrôle budgétaire différé de 300 ms après la dernière saisie
  useEffect(() => {
    if (!accountCode || totalNum <= 0) {
      setBudgetCheck(null)
      return
    }
    const t = setTimeout(async () => {
      setChecking(true)
      try {
        const result = await checkBudgetAvailability(accountCode, totalNum, fiscalYearId || undefined)
        setBudgetCheck(result)
      } catch (err: any) { console.error('Budget check error:', err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadingError')) }
      finally { setChecking(false) }
    }, 300)
    return () => clearTimeout(t)
  }, [accountCode, totalNum, fiscalYearId, tCommon, toast])

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!supplierId) { toast('warning', tCommon('toast.warning'), t('purchaseInvoices.selectSupplier')); return }
    if (!supplierRef.trim()) { toast('warning', tCommon('toast.warning'), t('purchaseInvoices.supplierReferenceRequired')); return }
    if (filledLines.length === 0) { toast('warning', tCommon('toast.warning'), t('purchaseInvoices.atLeastOneLine')); return }
    setSaving(true)
    try {
      if (budgetCheck?.would_exceed) {
        if (!confirmSync(t('purchaseInvoices.budgetExceedWarning', { amount: formatCurrency(totalNum), overshoot: formatCurrency(budgetCheck.overshoot_amount) }))) {
          setSaving(false)
          return
        }
      }
      const supplier = suppliers.find(s => s.id === supplierId)
      const inv = await createPurchaseInvoice({
        supplier_reference: supplierRef.trim(),
        supplier_id: supplierId,
        supplier_name: supplier?.name || '',
        date,
        due_date: dueDate || date,
        status: 'draft',
        subtotal,
        vat_total: vatTotal,
        total,
        amount_paid: 0,
        amount_due: total,
        notes: '',
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
      if (accountCode) {
        await createBudgetCommitment({
          description: `Facture achat ${supplierRef.trim()}`,
          account_code: accountCode,
          fiscal_year_id: fiscalYearId || null,
          amount: totalNum,
          commitment_date: date,
          source_type: 'purchase_invoice',
          source_id: inv.id,
          status: 'active',
          supplier_id: supplierId,
          notes: null,
        })
      }
      toast('success', t('purchaseInvoices.created'), t('purchaseInvoices.createdMsg', { number: supplierRef.trim() }))
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
          <h2 className="text-lg font-semibold">{t('purchaseInvoices.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <p className="text-xs text-[var(--color-text-secondary)]">{t('purchaseInvoices.numberAssigned')}</p>
          <Input label={t('purchaseInvoices.supplierReference')} required value={supplierRef} onChange={(e) => setSupplierRef(e.target.value)} />
          <Combobox label={t('purchaseInvoices.supplier')} required value={supplierId} onChange={(v) => setSupplierId(v)} placeholder={t('purchaseInvoices.selectSupplierPlaceholder')} options={suppliers.map(s => ({ value: s.id, label: s.name }))} />
          {commercialStrategy === 'inline' && (
            <button type="button" onClick={() => setShowQuickAddSupplier(true)} className="text-xs text-[var(--color-primary)] flex items-center gap-1 hover:underline">
              <UserPlus className="w-3.5 h-3.5" /> {tCross('supplier.add')}
            </button>
          )}
          <div className="grid grid-cols-2 gap-4">
            <Input label={tCommon('common.date')} type="date" required value={date} onChange={(e) => setDate(e.target.value)} />
            <Input label={t('purchaseInvoices.dueDate')} type="date" value={dueDate} onChange={(e) => setDueDate(e.target.value)} />
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
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('purchaseInvoices.budgetAccount')}</label>
              <select className="input" value={accountCode} onChange={(e) => setAccountCode(e.target.value)}>
                <option value="">— {tCommon('common.none')} —</option>
                {expenseAccounts.map(a => <option key={a.id} value={a.code}>{a.code} — {a.name}</option>)}
              </select>
            </div>
            <div>
              <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('purchaseInvoices.fiscalYear')}</label>
              <select className="input" value={fiscalYearId} onChange={(e) => setFiscalYearId(e.target.value)}>
                <option value="">— {tCommon('common.all')} —</option>
                {years.map(y => <option key={y.id} value={y.id}>{y.code}</option>)}
              </select>
            </div>
          </div>
          {checking && <p className="text-xs text-[var(--color-text-secondary)]">{t('purchaseInvoices.budgetChecking')}</p>}
          {budgetCheck && (
            <div className={`rounded-lg p-3 text-sm ${budgetCheck.would_exceed ? 'bg-red-50 border border-red-200 text-red-700' : 'bg-green-50 border border-green-200 text-green-700'}`}>
              <div className="flex items-start gap-2">
                {budgetCheck.would_exceed && <AlertTriangle className="w-4 h-4 mt-0.5 flex-shrink-0" />}
                <div className="space-y-1">
                  <div className="flex justify-between"><span>{t('purchaseInvoices.budgetTotal')}:</span><span className="font-mono">{formatCurrency(budgetCheck.budget_total)}</span></div>
                  <div className="flex justify-between"><span>{t('purchaseInvoices.realized')}:</span><span className="font-mono">{formatCurrency(budgetCheck.realized)}</span></div>
                  <div className="flex justify-between"><span>{t('purchaseInvoices.committed')}:</span><span className="font-mono">{formatCurrency(budgetCheck.committed)}</span></div>
                  <div className="flex justify-between font-semibold"><span>{t('purchaseInvoices.available')}:</span><span className="font-mono">{formatCurrency(budgetCheck.available)}</span></div>
                  {budgetCheck.would_exceed && (
                    <div className="flex justify-between font-bold"><span>{t('purchaseInvoices.overshoot')}:</span><span className="font-mono">{formatCurrency(budgetCheck.overshoot_amount)}</span></div>
                  )}
                </div>
              </div>
            </div>
          )}
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button variant="secondary" type="button" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" loading={saving}>{tCommon('actions.create')}</Button>
          </div>
        </form>
      </div>
    </div>
    {showQuickAddSupplier && (
      <QuickSupplierAccess
        onClose={() => setShowQuickAddSupplier(false)}
        onSaved={() => { setShowQuickAddSupplier(false); onSaved() }}
      />
    )}
    </>
  )
}

function PurchaseInvoiceDetailModal({ invoice, onClose }: { invoice: PurchaseInvoice; onClose: () => void }) {
  const { t } = useTranslation('purchases')
  const { t: tCommon } = useTranslation('common')
  const { t: tAcc } = useTranslation('accounting')
  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('purchaseInvoices.invoice')} {invoice.number}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <div className="p-6 space-y-3">
          <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">{t('purchaseInvoices.supplier')}</span><span className="font-medium">{invoice.supplier_name || 'N/A'}</span></div>
          <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">{tCommon('common.date')}</span><span>{formatDate(invoice.date)}</span></div>
          <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">{t('purchaseInvoices.dueDate')}</span><span>{formatDate(invoice.due_date)}</span></div>
          <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">{tCommon('common.status')}</span><Badge variant={invoice.status === 'paid' ? 'success' : invoice.status === 'overdue' ? 'danger' : 'neutral'}>{translateStatus(invoice.status)}</Badge></div>
          {invoice.payment_state && (
            <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">{tAcc('writingsEnhancement.paymentState.' + invoice.payment_state, { defaultValue: invoice.payment_state })}</span><Badge variant={invoice.payment_state === 'paid' ? 'success' : invoice.payment_state === 'partial' ? 'warning' : 'neutral'}>{tAcc('writingsEnhancement.paymentState.' + invoice.payment_state, { defaultValue: invoice.payment_state })}</Badge></div>
          )}
          <div className="flex justify-between text-sm border-t border-[var(--color-border)] pt-3"><span className="text-[var(--color-text-secondary)]">{t('purchaseInvoices.total')}</span><span className="font-mono font-bold">{formatCurrency(Number(invoice.total))}</span></div>
          <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">{t('purchaseInvoices.paid')}</span><span className="font-mono text-[var(--color-success)]">{formatCurrency(Number(invoice.amount_paid))}</span></div>
          <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">{t('purchaseInvoices.remainingToPay')}</span><span className="font-mono text-[var(--color-danger)]">{formatCurrency(Number(invoice.amount_due))}</span></div>
        </div>
      </div>
    </div>
  )
}
