import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { getPurchaseCreditNotes, createPurchaseCreditNote, deletePurchaseCreditNote, getSuppliers, getPurchaseInvoices } from '@/lib/queries'
import { formatCurrency, formatDate } from '@/lib/utils'
import { Receipt, Plus, Trash2, X, ChevronDown, ChevronRight } from 'lucide-react'
import type { PurchaseCreditNote, Supplier, PurchaseInvoice } from '@/types'
import { useToast } from '@/lib/toast'
import { useLegislation } from '@/lib/legislation'
import { useTranslation } from 'react-i18next'

export function PurchaseCreditNotesPage() {
  const { t } = useTranslation('purchases')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const { toast } = useToast()
const [creditNotes, setCreditNotes] = useState<PurchaseCreditNote[]>([])
  const [suppliers, setSuppliers] = useState<Supplier[]>([])
  const [invoices, setInvoices] = useState<PurchaseInvoice[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [expanded, setExpanded] = useState<Set<string>>(new Set())

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [cn, s, inv] = await Promise.all([getPurchaseCreditNotes(), getSuppliers(), getPurchaseInvoices()])
      setCreditNotes(cn)
      setSuppliers(s)
      setInvoices(inv)
    } catch (err) {
      console.error('Failed to load:', err)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  function toggleExpand(id: string) {
  setExpanded(prev => { const n = new Set(prev); if (n.has(id)) n.delete(id); else n.add(id); return n })
  }

  async function handleDelete(id: string) {
    if (!window.confirm(t('creditNotes.deleteConfirm'))) return
    try { await deletePurchaseCreditNote(id); await loadData() } catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.purchases') }, { label: t('creditNotes.title') }]} />
      <PageHeader
        title={t('creditNotes.title')}
        subtitle={t('creditNotes.subtitle')}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('creditNotes.new')}</Button>}
      />

      {loading ? (
        <SkeletonTable rows={4} cols={6} />
      ) : creditNotes.length === 0 ? (
        <EmptyState icon={<Receipt className="w-8 h-8" />} title={t('creditNotes.noCreditNotes')} description={t('creditNotes.noCreditNotesDescription')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('creditNotes.new')}</Button>} />
      ) : (
        <Card>
          <Table headers={['', t('creditNotes.number'), t('creditNotes.date'), t('creditNotes.supplier'), t('creditNotes.amount'), t('creditNotes.status'), t('creditNotes.actions')]}>
            {creditNotes.map((cn) => (
              <div key={cn.id}>
                <TableRow onClick={() => toggleExpand(cn.id)}>
                  <TableCell className="w-8">
                    {cn.purchase_credit_lines?.length ? (expanded.has(cn.id) ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />) : <span className="w-4 inline-block" />}
                  </TableCell>
                  <TableCell className="font-mono font-semibold">{cn.number}</TableCell>
                  <TableCell>{formatDate(cn.date)}</TableCell>
                  <TableCell>{cn.supplier_name || 'N/A'}</TableCell>
                  <TableCell className="font-mono text-[var(--color-success)] text-right">{formatCurrency(Number(cn.total))}</TableCell>
                  <TableCell><Badge variant={cn.status === 'applied' ? 'success' : 'warning'}>{t(`creditNotes.statuses.${cn.status}`) as string}</Badge></TableCell>
                  <TableCell>
                    <button onClick={(e) => { e.stopPropagation(); handleDelete(cn.id) }} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </TableCell>
                </TableRow>
                {expanded.has(cn.id) && cn.purchase_credit_lines?.map((line) => (
                  <tr key={line.id} className="bg-[var(--color-neutral-50)]">
                    <TableCell /><TableCell className="font-mono text-xs">{line.quantity}x</TableCell>
                    <TableCell colSpan={2} className="text-xs text-[var(--color-text-secondary)]">{line.description}</TableCell>
                    <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(line.total))}</TableCell>
                    <TableCell /><TableCell />
                  </tr>
                ))}
                {cn.reason && (
                  <tr className="bg-[var(--color-neutral-50)]"><TableCell /><TableCell colSpan={6} className="text-xs italic text-[var(--color-text-secondary)]">{t('creditNotes.reasonLabel')}: {cn.reason}</TableCell></tr>
                )}
              </div>
            ))}
          </Table>
        </Card>
      )}

      {showForm && (
        <PurchaseCreditForm suppliers={suppliers} invoices={invoices} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />
      )}
    </div>
  )
}

function PurchaseCreditForm({ suppliers, invoices, onClose, onSaved }: { suppliers: Supplier[]; invoices: PurchaseInvoice[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('purchases')
  const { t: tCommon } = useTranslation('common')
  const [number, setNumber] = useState('AVF-' + new Date().getFullYear() + '-' + String(Math.floor(Math.random() * 999)).padStart(3, '0'))
  const { toast } = useToast()
  const [date, setDate] = useState(new Date().toISOString().split('T')[0])
  const [supplierId, setSupplierId] = useState('')
  const [invoiceId, setInvoiceId] = useState('')
  const [reason, setReason] = useState('')
  const { defaultVatRate } = useLegislation()
  const [lines, setLines] = useState([{ description: '', quantity: 1, unit_price: 0, vat_rate: defaultVatRate, total: 0, vat_total: 0 }])
  const [saving, setSaving] = useState(false)

  const subtotal = lines.reduce((s, l) => s + l.total, 0)
  const vatTotal = lines.reduce((s, l) => s + l.vat_total, 0)
  const total = subtotal + vatTotal

  function updateLine(idx: number, field: string, value: any) {
    setLines(prev => prev.map((l, i) => {
      if (i !== idx) return l
      const u = { ...l, [field]: value }
      if (field === 'quantity' || field === 'unit_price' || field === 'vat_rate') {
        u.total = Number(u.quantity) * Number(u.unit_price)
        u.vat_total = u.total * (Number(u.vat_rate) / 100)
      }
      return u
    }))
  }

  const supplierInvoices = invoices.filter(i => i.supplier_id === supplierId)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    const supplier = suppliers.find(s => s.id === supplierId)
    setSaving(true)
    try {
      await createPurchaseCreditNote({
        number, date, supplier_id: supplierId || null, supplier_name: supplier?.name || null,
        status: 'draft', subtotal, vat_total: vatTotal, total,
        reason: reason || null, purchase_invoice_id: invoiceId || null,
        purchase_credit_lines: lines.filter(l => l.description).map(l => ({
          description: l.description, quantity: l.quantity, unit_price: l.unit_price,
          vat_rate: l.vat_rate, total: l.total, vat_total: l.vat_total,
        })),
      } as any)
      onSaved()
    } catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) } finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4 overflow-y-auto">
      <div className="card shadow-2xl overflow-hidden my-8" style={{ width: '100%', maxWidth: '48rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('creditNotes.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('creditNotes.number')} required value={number} onChange={(e) => setNumber(e.target.value)} />
            <Input label={t('creditNotes.date')} type="date" required value={date} onChange={(e) => setDate(e.target.value)} />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Select label={t('creditNotes.supplier')} required value={supplierId} onChange={(e) => { setSupplierId(e.target.value); setInvoiceId('') }} options={[
              { value: '', label: tCommon('form.selectPlaceholder') },
              ...suppliers.map(s => ({ value: s.id, label: s.name })),
            ]} />
            <Select label={t('creditNotes.linkedInvoiceOptional')} value={invoiceId} onChange={(e) => setInvoiceId(e.target.value)} options={[
              { value: '', label: t('creditNotes.none') },
              ...supplierInvoices.map(i => ({ value: i.id, label: `${i.number} - ${formatCurrency(Number(i.total))}` })),
            ]} />
          </div>
          <div className="border border-[var(--color-border)] rounded-lg overflow-hidden">
            <table className="app-table min-w-[760px]">
              <thead className="bg-[var(--color-neutral-50)]">
                <tr>
                  <th className="px-3 py-2 text-left text-xs font-semibold">{t('invoices.description')}</th>
                  <th className="px-3 py-2 text-right text-xs font-semibold w-20">{t('invoices.quantity')}</th>
                  <th className="px-3 py-2 text-right text-xs font-semibold w-28">{t('invoices.unitPrice')}</th>
                  <th className="px-3 py-2 text-right text-xs font-semibold w-20">{t('invoices.vatRate')}</th>
                  <th className="px-3 py-2 text-right text-xs font-semibold w-28">{t('creditNotes.total')}</th>
                  <th className="w-8"></th>
                </tr>
              </thead>
              <tbody>
                {lines.map((line, idx) => (
                  <tr key={idx} className="border-t border-[var(--color-border)]">
                    <td className="px-3 py-2"><input value={line.description} onChange={(e) => updateLine(idx, 'description', e.target.value)} className="text-xs border border-[var(--color-border)] rounded px-2 py-1 w-full bg-[var(--color-surface)]" placeholder={t('invoices.description')} /></td>
                    <td className="px-3 py-2"><input type="number" step="0.01" value={line.quantity} onChange={(e) => updateLine(idx, 'quantity', Number(e.target.value))} className="text-xs border border-[var(--color-border)] rounded px-2 py-1 w-full bg-[var(--color-surface)] text-right" /></td>
                    <td className="px-3 py-2"><input type="number" step="0.01" value={line.unit_price} onChange={(e) => updateLine(idx, 'unit_price', Number(e.target.value))} className="text-xs border border-[var(--color-border)] rounded px-2 py-1 w-full bg-[var(--color-surface)] text-right" /></td>
                    <td className="px-3 py-2"><input type="number" step="0.01" value={line.vat_rate} onChange={(e) => updateLine(idx, 'vat_rate', Number(e.target.value))} className="text-xs border border-[var(--color-border)] rounded px-2 py-1 w-full bg-[var(--color-surface)] text-right" /></td>
                    <td className="px-3 py-2 text-right text-xs font-mono">{formatCurrency(line.total + line.vat_total)}</td>
                    <td className="px-3 py-2">{lines.length > 1 && <button type="button" onClick={() => setLines(prev => prev.filter((_, i) => i !== idx))} className="text-[var(--color-danger)] hover:bg-[var(--color-neutral-100)] rounded p-1"><X className="w-3 h-3" /></button>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            <button type="button" onClick={() => setLines(prev => [...prev, { description: '', quantity: 1, unit_price: 0, vat_rate: defaultVatRate, total: 0, vat_total: 0 }])} className="w-full py-2 text-sm text-[var(--color-primary)] hover:bg-[var(--color-neutral-50)] border-t border-[var(--color-border)]">+ {t('invoices.addLine')}</button>
          </div>
          <div className="flex justify-end gap-6 text-sm">
            <div><span className="text-[var(--color-text-secondary)]">{t('creditNotes.subtotal')}: </span><span className="font-mono font-semibold">{formatCurrency(subtotal)}</span></div>
            <div><span className="text-[var(--color-text-secondary)]">{t('creditNotes.vat')}: </span><span className="font-mono font-semibold">{formatCurrency(vatTotal)}</span></div>
            <div><span className="text-[var(--color-text-secondary)]">{t('creditNotes.total')}: </span><span className="font-mono font-bold text-base">{formatCurrency(total)}</span></div>
          </div>
          <Input label={t('creditNotes.reasonLabel')} value={reason} onChange={(e) => setReason(e.target.value)} placeholder={t('creditNotes.reason')} />
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
