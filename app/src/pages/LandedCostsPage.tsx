import { Fragment, useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select, Badge } from '@/components/ui'
import { errorMessage, formatCurrency } from '@/lib/utils'
import {
  getLandedCosts, createLandedCost, deleteLandedCost,
  getLandedCostReceipts, addLandedCostReceipt, getLandedCostLines, distributeLandedCost, listGoodsReceipts,
  type LandedCost, type LandedCostLine, type LandedCostReceipt,
} from '@/lib/queries/stock'
import { Plus, Trash2, X, Truck, ChevronDown, ChevronRight, Calculator } from 'lucide-react'
import { useToast } from '@/lib/toast'
import { confirmSync } from '@/lib/confirm'

// STK-08 / E.3 : les frais accessoires d'achat. La 658 a corrigé le moteur (il ne
// répartit que sur les réceptions CIBLÉES, avec gardes et idempotence).
export function LandedCostsPage() {
  const { t } = useTranslation('stock')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [costs, setCosts] = useState<LandedCost[]>([])
  const [receipts, setReceipts] = useState<{ id: string; number: string; receipt_date: string | null }[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [expanded, setExpanded] = useState<Set<string>>(new Set())
  const [targets, setTargets] = useState<Record<string, LandedCostReceipt[]>>({})
  const [lines, setLines] = useState<Record<string, LandedCostLine[]>>({})
  const [pick, setPick] = useState<Record<string, string>>({})

  const loadData = useCallback(async () => {
    try {
      const [lc, rc] = await Promise.all([getLandedCosts(), listGoodsReceipts()])
      setCosts(lc || [])
      setReceipts(rc || [])
    } catch (err) { console.error('Error:', err); toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.loadingError')) }
    finally { setLoading(false) }
  }, [tCommon, toast])

  useEffect(() => { loadData() }, [loadData])

  const receiptNumber = (id: string) => receipts.find((r) => r.id === id)?.number ?? id.slice(0, 8)

  async function refreshDetail(id: string) {
    try {
      const [tg, ln] = await Promise.all([getLandedCostReceipts(id), getLandedCostLines(id)])
      setTargets((prev) => ({ ...prev, [id]: tg }))
      setLines((prev) => ({ ...prev, [id]: ln }))
    } catch (err) { toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.loadingError')) }
  }

  async function toggleExpand(id: string) {
    const next = new Set(expanded)
    if (next.has(id)) { next.delete(id) }
    else { next.add(id); await refreshDetail(id) }
    setExpanded(next)
  }

  async function handleAddReceipt(id: string) {
    const rid = pick[id]
    if (!rid) return
    try { await addLandedCostReceipt(id, rid); setPick((p) => ({ ...p, [id]: '' })); await refreshDetail(id) }
    catch (err) { toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.error')) }
  }

  async function handleDistribute(id: string) {
    if (!confirmSync(t('landed.confirmDistribute'))) return
    try { await distributeLandedCost(id); await loadData(); if (expanded.has(id)) await refreshDetail(id) }
    catch (err) { toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.error')) }
  }

  async function handleDelete(id: string) {
    if (!confirmSync(t('landed.confirmDelete'))) return
    try { await deleteLandedCost(id); await loadData() }
    catch (err) { toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.error')) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('title'), path: '/stock' }, { label: t('landed.title') }]} />
      <PageHeader title={t('landed.title')} subtitle={t('landed.subtitle')}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('landed.new')}</Button>} />

      {loading ? <SkeletonTable rows={4} cols={5} /> : costs.length === 0 ? (
        <EmptyState icon={<Truck className="w-8 h-8" />} title={t('landed.noCosts')} description={t('landed.noCostsDescription')} />
      ) : (
        <Card>
          <Table headers={[t('landed.invoice'), t('landed.amount'), t('landed.method'), t('landed.status'), tCommon('common.actions')]}>
            {costs.map((c) => (
              <Fragment key={c.id}>
                <TableRow>
                  <TableCell className="font-mono text-xs">
                    <div className="flex items-center gap-1">
                      <button onClick={() => toggleExpand(c.id)} aria-label={tCommon(expanded.has(c.id) ? 'actions.collapse' : 'actions.expand')} title={tCommon(expanded.has(c.id) ? 'actions.collapse' : 'actions.expand')} className="p-0.5 rounded hover:bg-[var(--color-neutral-100)]">
                        {expanded.has(c.id) ? <ChevronDown className="w-3.5 h-3.5" /> : <ChevronRight className="w-3.5 h-3.5" />}
                      </button>
                      {c.invoice_number ?? '—'}
                    </div>
                  </TableCell>
                  <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(c.total_amount))}</TableCell>
                  <TableCell className="text-xs">{t(`landed.methods.${c.distribution_method}`)}</TableCell>
                  <TableCell><Badge variant={c.status === 'distributed' ? 'success' : 'neutral'}>{t(`landed.statuses.${c.status ?? 'pending'}`)}</Badge></TableCell>
                  <TableCell>
                    <div className="flex gap-1">
                      {c.status !== 'distributed' && (
                        <button onClick={() => handleDistribute(c.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)]" aria-label={t('landed.distribute')} title={t('landed.distribute')}><Calculator className="w-4 h-4" aria-hidden="true" /></button>
                      )}
                      <button onClick={() => handleDelete(c.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" aria-label={tCommon('actions.delete')} title={tCommon('actions.delete')}><Trash2 className="w-4 h-4" aria-hidden="true" /></button>
                    </div>
                  </TableCell>
                </TableRow>
                {expanded.has(c.id) && (
                  <tr><td colSpan={5} className="p-0">
                    <div className="px-8 py-3 bg-[var(--color-neutral-50)] border-y border-[var(--color-border)] space-y-3">
                      {c.status !== 'distributed' && (
                        <div className="flex items-end gap-2">
                          <div className="w-64"><Select label={t('landed.targetReceipt')} value={pick[c.id] ?? ''} onChange={(e) => setPick((p) => ({ ...p, [c.id]: e.target.value }))} options={[{ value: '', label: t('landed.selectReceipt') }, ...receipts.map((r) => ({ value: r.id, label: r.number }))]} /></div>
                          <Button onClick={() => handleAddReceipt(c.id)}>{tCommon('actions.add')}</Button>
                        </div>
                      )}
                      <div>
                        <p className="text-xs font-semibold mb-1">{t('landed.targets')}</p>
                        {(targets[c.id] || []).length === 0 ? <p className="text-xs text-[var(--color-text-secondary)]">{t('landed.noTargets')}</p> : (
                          <div className="flex flex-wrap gap-2">{(targets[c.id] || []).map((tg) => <Badge key={tg.id} variant="neutral">{receiptNumber(tg.receipt_id)}</Badge>)}</div>
                        )}
                      </div>
                      {(lines[c.id] || []).length > 0 && (
                        <Table headers={[t('landed.originalCost'), t('landed.distributedAmount'), t('landed.newCost')]}>
                          {(lines[c.id] || []).map((l) => (
                            <TableRow key={l.id}>
                              <TableCell className="font-mono text-xs">{Number(l.original_unit_cost ?? 0)}</TableCell>
                              <TableCell className="font-mono text-xs">{formatCurrency(Number(l.distributed_amount))}</TableCell>
                              <TableCell className="font-mono text-xs">{Number(l.new_unit_cost ?? 0)}</TableCell>
                            </TableRow>
                          ))}
                        </Table>
                      )}
                    </div>
                  </td></tr>
                )}
              </Fragment>
            ))}
          </Table>
        </Card>
      )}

      {showForm && <LandedCostForm onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function LandedCostForm({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('stock')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [invoice, setInvoice] = useState('')
  const [amount, setAmount] = useState(0)
  const [method, setMethod] = useState('value')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await createLandedCost({ invoice_number: invoice || null, supplier_id: null, total_amount: amount, distribution_method: method, status: 'pending' })
      onSaved()
    } catch (err) { toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.error')) }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '30rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('landed.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label={t('landed.invoice')} value={invoice} onChange={(e) => setInvoice(e.target.value)} />
          <Input label={t('landed.amount')} type="number" step="0.01" required value={amount} onChange={(e) => setAmount(Number(e.target.value))} />
          <Select label={t('landed.method')} value={method} onChange={(e) => setMethod(e.target.value)} options={[{ value: 'value', label: t('landed.methods.value') }, { value: 'quantity', label: t('landed.methods.quantity') }, { value: 'weight', label: t('landed.methods.weight') }, { value: 'volume', label: t('landed.methods.volume') }]} />
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
