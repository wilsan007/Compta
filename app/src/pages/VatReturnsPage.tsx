import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input } from '@/components/ui'
import { getVatReturns, createVatReturn, updateVatReturn, deleteVatReturn, calcVatFromEntries } from '@/lib/queries'
import { useLocale } from '@/hooks/useLocale'
import { FileText, Plus, Trash2, X, Calculator } from 'lucide-react'
import type { VatReturn } from '@/types'
import { useToast } from '@/lib/toast'

export function VatReturnsPage() {
  const { toast } = useToast()
  const { t } = useTranslation('reports')
  const { t: tCommon } = useTranslation('common')
  const { formatCurrency, formatDate } = useLocale()
const [vatReturns, setVatReturns] = useState<VatReturn[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      setVatReturns(await getVatReturns())
    } catch (err) {
      console.error('Failed to load VAT returns:', err)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleStatusChange(id: string, status: string) {
  try {
      const updates: any = { status }
      if (status === 'submitted') updates.submitted_date = new Date().toISOString().split('T')[0]
      await updateVatReturn(id, updates)
      await loadData()
    } catch (err: any) {
      toast('error', t('vat.error'), err.message || tCommon('error'))
    }
  }

  async function handleDelete(id: string) {
    if (!window.confirm(t('vat.deleteConfirm'))) return
    try {
      await deleteVatReturn(id)
      await loadData()
    } catch (err: any) {
      toast('error', t('vat.error'), err.message || tCommon('error'))
    }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('vat.title') }]} />
      <PageHeader
        title={t('vat.title')}
        subtitle={t('vat.subtitle')}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('vat.new')}</Button>}
      />

      {loading ? (
        <SkeletonTable rows={4} cols={7} />
      ) : vatReturns.length === 0 ? (
        <EmptyState
          icon={<FileText className="w-8 h-8" />}
          title={t('vat.noDeclarations')}
          description={t('vat.noDeclarationsDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('vat.new')}</Button>}
        />
      ) : (
        <Card>
          <Table headers={[t('vat.period'), t('vat.status'), t('vat.collectedVat'), t('vat.deductibleVat'), t('vat.netVat'), t('vat.sales'), t('vat.purchases'), t('vat.actions')]}>
            {vatReturns.map((v) => (
              <TableRow key={v.id}>
                <TableCell className="text-xs">{formatDate(v.period_start)} → {formatDate(v.period_end)}</TableCell>
                <TableCell>
                  <select
                    value={v.status}
                    onChange={(e) => handleStatusChange(v.id, e.target.value)}
                    className="text-xs border border-[var(--color-border)] rounded px-2 py-1 bg-[var(--color-surface)]"
                  >
                    {Object.entries({ draft: t('vat.statusLabels.draft'), submitted: t('vat.statusLabels.submitted'), paid: t('vat.statusLabels.paid') }).map(([k, val]) => <option key={k} value={k}>{val}</option>)}
                  </select>
                </TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(v.box1_output_vat))}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(v.box2_input_vat))}</TableCell>
                <TableCell className={`font-mono text-xs font-bold text-right ${Number(v.box5_net_vat) >= 0 ? 'text-[var(--color-danger)]' : 'text-[var(--color-success)]'}`}>
                  {formatCurrency(Number(v.box5_net_vat))}
                </TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(v.total_sales))}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(v.total_purchases))}</TableCell>
                <TableCell>
                  <button onClick={() => handleDelete(v.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                    <Trash2 className="w-4 h-4" />
                  </button>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && (
        <VatForm onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />
      )}
    </div>
  )
}

function VatForm({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const { toast } = useToast()
  const { t } = useTranslation('reports')
  const { t: tCommon } = useTranslation('common')
  const { formatCurrency } = useLocale()
  const [periodStart, setPeriodStart] = useState('')
  const [periodEnd, setPeriodEnd] = useState('')
  const [outputVat, setOutputVat] = useState(0)
  const [inputVat, setInputVat] = useState(0)
  const [totalSales, setTotalSales] = useState(0)
  const [totalPurchases, setTotalPurchases] = useState(0)
  const [saving, setSaving] = useState(false)
  const [calculating, setCalculating] = useState(false)

  const netVat = outputVat - inputVat

  async function handleAutoCalc() {
    if (!periodStart || !periodEnd) {
      toast('warning', tCommon('warning'), t('vat.selectDatesFirst'))
      return
    }
    setCalculating(true)
    try {
      const result = await calcVatFromEntries(periodStart, periodEnd)
      setOutputVat(result.outputVat)
      setInputVat(result.inputVat)
      setTotalSales(result.totalSales)
      setTotalPurchases(result.totalPurchases)
    } catch (err: any) {
      toast('error', t('vat.calcError'), err.message || tCommon('error'))
    } finally {
      setCalculating(false)
    }
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await createVatReturn({
        period_start: periodStart,
        period_end: periodEnd,
        status: 'draft',
        box1_output_vat: outputVat,
        box2_input_vat: inputVat,
        box3_vat_due: netVat > 0 ? netVat : 0,
        box4_repayment_due: netVat < 0 ? Math.abs(netVat) : 0,
        box5_net_vat: netVat,
        total_sales: totalSales,
        total_purchases: totalPurchases,
      } as any)
      onSaved()
    } catch (err: any) {
      toast('error', t('vat.error'), err.message || tCommon('error'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('vat.newReturn')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('vat.periodStart')} type="date" required value={periodStart} onChange={(e) => setPeriodStart(e.target.value)} />
            <Input label={t('vat.periodEnd')} type="date" required value={periodEnd} onChange={(e) => setPeriodEnd(e.target.value)} />
          </div>
          <Button type="button" variant="secondary" onClick={handleAutoCalc} disabled={calculating}>
            <Calculator className="w-4 h-4" /> {calculating ? t('vat.calculating') : t('vat.autoCalc')}
          </Button>
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('vat.outputVatLabel')} type="number" step="0.01" value={outputVat} onChange={(e) => setOutputVat(Number(e.target.value))} />
            <Input label={t('vat.inputVatLabel')} type="number" step="0.01" value={inputVat} onChange={(e) => setInputVat(Number(e.target.value))} />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('vat.totalSalesLabel')} type="number" step="0.01" value={totalSales} onChange={(e) => setTotalSales(Number(e.target.value))} />
            <Input label={t('vat.totalPurchasesLabel')} type="number" step="0.01" value={totalPurchases} onChange={(e) => setTotalPurchases(Number(e.target.value))} />
          </div>
          <div className="p-3 rounded-lg bg-[var(--color-neutral-50)] text-sm">
            <span className="text-[var(--color-text-secondary)]">{t('vat.netVatPayable')}: </span>
            <span className={`font-mono font-bold ${netVat >= 0 ? 'text-[var(--color-danger)]' : 'text-[var(--color-success)]'}`}>
              {formatCurrency(netVat)}
            </span>
          </div>
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{t('vat.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : t('vat.createBtn')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
