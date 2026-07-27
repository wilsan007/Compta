import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, Button, Table, TableRow, TableCell, EmptyState, Select, Input } from '@/components/ui'
import { formatCurrency } from '@/lib/utils'
import { getDocumentCharges, addDocumentCharge, deleteDocumentCharge, getSuppliers } from '@/lib/queries'
import { useToast } from '@/lib/toast'
import { Plus, Trash2, X, Truck } from 'lucide-react'
import type { DocumentCharge, Supplier } from '@/types'

interface Props {
  documentType: 'quote' | 'sales_order' | 'delivery_note' | 'invoice' | 'credit_note' | 'purchase_order' | 'purchase_invoice'
  documentId: string
}

export function DocumentCharges({ documentType, documentId }: Props) {
  const { t } = useTranslation('sales')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [charges, setCharges] = useState<DocumentCharge[]>([])
  const [suppliers, setSuppliers] = useState<Supplier[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)

  const loadCharges = useCallback(async () => {
    if (!documentId) return
    setLoading(true)
    try {
      const [ch, sup] = await Promise.all([getDocumentCharges(documentType, documentId), getSuppliers()])
      setCharges(ch || [])
      setSuppliers(sup || [])
    } catch (err) {
      console.error('Failed to load charges:', err)
    } finally {
      setLoading(false)
    }
  }, [documentType, documentId])

  useEffect(() => { loadCharges() }, [loadCharges])

  async function handleDelete(id: string) {
    try {
      await deleteDocumentCharge(id)
      toast('success', tCommon('toast.success'), t('documentCharges.chargeDeleted'))
      await loadCharges()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || t('documentCharges.chargeDeleteError'))
    }
  }

  const totalCharges = charges.reduce((sum, c) => sum + Number(c.total_amount || 0), 0)

  return (
    <Card>
      <div className="flex items-center justify-between px-4 py-3 border-b border-[var(--color-border)]">
        <h3 className="text-sm font-semibold flex items-center gap-2">
          <Truck className="w-4 h-4 text-[var(--color-text-secondary)]" />
          {t('documentCharges.title')}
        </h3>
        <Button size="sm" onClick={() => setShowForm(true)}>
          <Plus className="w-3 h-3" /> {t('documentCharges.add')}
        </Button>
      </div>

      {loading ? (
        <div className="p-4 text-sm text-[var(--color-text-secondary)]">...</div>
      ) : charges.length === 0 ? (
        <EmptyState
          icon={<Truck className="w-6 h-6" />}
          title={t('documentCharges.noCharges')}
          description={t('documentCharges.noChargesDescription')}
        />
      ) : (
        <>
          <Table headers={[t('documentCharges.type'), t('documentCharges.label'), t('documentCharges.amount'), t('documentCharges.vatRate'), t('documentCharges.total'), tCommon('table.actions')]}>
            {charges.map((c) => (
              <TableRow key={c.id}>
                <TableCell className="text-xs">{t(`documentCharges.${c.charge_type}`)}</TableCell>
                <TableCell className="text-xs">{c.label}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(c.amount))}</TableCell>
                <TableCell className="font-mono text-xs text-right">{Number(c.vat_rate)}%</TableCell>
                <TableCell className="font-mono text-xs text-right font-semibold">{formatCurrency(Number(c.total_amount))}</TableCell>
                <TableCell>
                  <button onClick={() => handleDelete(c.id)} className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" title={t('documentCharges.delete')}>
                    <Trash2 className="w-3.5 h-3.5" />
                  </button>
                </TableCell>
              </TableRow>
            ))}
          </Table>
          <div className="flex justify-end px-4 py-2 border-t border-[var(--color-border)] text-sm">
            <span className="text-[var(--color-text-secondary)] mr-2">{t('documentCharges.totalCharges')}:</span>
            <span className="font-mono font-bold">{formatCurrency(totalCharges)}</span>
          </div>
        </>
      )}

      {showForm && (
        <ChargeForm
          suppliers={suppliers}
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); loadCharges() }}
          documentType={documentType}
          documentId={documentId}
        />
      )}
    </Card>
  )
}

function ChargeForm({ suppliers, onClose, onSaved, documentType, documentId }: {
  suppliers: Supplier[]
  onClose: () => void
  onSaved: () => void
  documentType: string
  documentId: string
}) {
  const { t } = useTranslation('sales')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [chargeType, setChargeType] = useState('shipping')
  const [label, setLabel] = useState('')
  const [amount, setAmount] = useState(0)
  const [vatRate, setVatRate] = useState(20)
  const [supplierId, setSupplierId] = useState('')
  const [saving, setSaving] = useState(false)

  const vatAmount = amount * (vatRate / 100)
  const total = amount + vatAmount

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await addDocumentCharge({
        document_type: documentType as any,
        document_id: documentId,
        charge_type: chargeType as any,
        label,
        amount,
        vat_rate: vatRate,
        vat_amount: vatAmount,
        total_amount: total,
        supplier_id: supplierId || null,
      } as any)
      toast('success', tCommon('toast.success'), t('documentCharges.chargeAdded'))
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || t('documentCharges.chargeAddError'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '28rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('documentCharges.add')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Select label={t('documentCharges.type')} required value={chargeType} onChange={(e) => setChargeType(e.target.value)} options={[
            { value: 'shipping', label: t('documentCharges.shipping') },
            { value: 'handling', label: t('documentCharges.handling') },
            { value: 'insurance', label: t('documentCharges.insurance') },
            { value: 'packaging', label: t('documentCharges.packaging') },
            { value: 'other', label: t('documentCharges.other') },
          ]} />
          <Input label={t('documentCharges.label')} required value={label} onChange={(e) => setLabel(e.target.value)} />
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('documentCharges.amount')} type="number" step="0.01" required value={amount} onChange={(e) => setAmount(Number(e.target.value))} />
            <Input label={t('documentCharges.vatRate')} type="number" step="0.01" required value={vatRate} onChange={(e) => setVatRate(Number(e.target.value))} />
          </div>
          <Select label={t('documentCharges.carrier')} value={supplierId} onChange={(e) => setSupplierId(e.target.value)} options={[
            { value: '', label: t('documentCharges.carrierPlaceholder') },
            ...suppliers.map(s => ({ value: s.id, label: s.name })),
          ]} />
          <div className="flex justify-end gap-4 text-sm">
            <div><span className="text-[var(--color-text-secondary)]">{t('documentCharges.vatAmount')}: </span><span className="font-mono">{formatCurrency(vatAmount)}</span></div>
            <div><span className="text-[var(--color-text-secondary)]">{t('documentCharges.total')}: </span><span className="font-mono font-bold">{formatCurrency(total)}</span></div>
          </div>
          <div className="flex justify-end gap-3 pt-2 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : t('documentCharges.add')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
