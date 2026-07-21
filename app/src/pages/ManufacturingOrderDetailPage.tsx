import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { useParams, useNavigate, Link } from 'react-router-dom'
import { ArrowLeft, Plus, Trash2, Tag, Calendar, Package, Layers, ClipboardList, Printer } from 'lucide-react'
import { Card, Button, Input, Select, Table, TableRow, TableCell, EmptyState, PageHeader, Breadcrumb, SkeletonTable, Badge } from '@/components/ui'
import { useToast } from '@/lib/toast'
import {
  getManufacturingOrder,
  getOFLabels, generateOFLabels, updateOFLabel, deleteOFLabel,
  getOFLots, createOFLot, deleteOFLot,
  getOFConsumptions, createOFConsumption, deleteOFConsumption,
  getSubManufacturingOrders, getProducts,
} from '@/lib/queries'
import type { Product } from '@/types'

const originVariants: Record<string, 'neutral' | 'success' | 'warning'> = { manual: 'neutral', mrp: 'success', sub_level: 'warning' }
const statusVariants: Record<string, 'neutral' | 'success' | 'warning' | 'danger'> = { planned: 'neutral', in_progress: 'warning', completed: 'success', cancelled: 'danger' }

export function ManufacturingOrderDetailPage() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { t } = useTranslation('production')
  const { toast } = useToast()
  const [mo, setMo] = useState<any>(null)
  const [products, setProducts] = useState<Product[]>([])
  const [loading, setLoading] = useState(true)
  const [activeTab, setActiveTab] = useState<'info' | 'labels' | 'lots' | 'consumptions' | 'sublevels'>('info')
  const [labels, setLabels] = useState<any[]>([])
  const [lots, setLots] = useState<any[]>([])
  const [consumptions, setConsumptions] = useState<any[]>([])
  const [subMOs, setSubMOs] = useState<any[]>([])
  const [showLotForm, setShowLotForm] = useState(false)
  const [showConsForm, setShowConsForm] = useState(false)
  const [labelCount, setLabelCount] = useState(1)
  const [labelQty, setLabelQty] = useState(0)
  const [allowDeferred, setAllowDeferred] = useState(false)

  const loadData = useCallback(async () => {
    if (!id) return
    try {
      const [moData, prods] = await Promise.all([getManufacturingOrder(id), getProducts()])
      setMo(moData)
      setProducts(prods || [])
      if (moData?.product_id) {
        const prod = (prods || []).find((p: any) => p.id === moData.product_id)
        if ((prod as any)?.units_per_carton) setLabelQty((prod as any).units_per_carton)
      }
    } catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [id])

  useEffect(() => { loadData() }, [loadData])

  async function loadTabData(tab: string) {
    if (!id) return
    if (tab === 'labels' && labels.length === 0) {
      try { setLabels(await getOFLabels(id)) } catch (err) { console.error(err) }
    }
    if (tab === 'lots' && lots.length === 0) {
      try { setLots(await getOFLots(id)) } catch (err) { console.error(err) }
    }
    if (tab === 'consumptions' && consumptions.length === 0) {
      try { setConsumptions(await getOFConsumptions(id)) } catch (err) { console.error(err) }
    }
    if (tab === 'sublevels' && subMOs.length === 0) {
      try { setSubMOs(await getSubManufacturingOrders(id)) } catch (err) { console.error(err) }
    }
  }

  async function handleGenerateLabels() {
    if (!id) return
    try {
      await generateOFLabels(id, labelCount, labelQty, mo?.product_id || null)
      setLabels(await getOFLabels(id))
      toast('success', t('manufacturing.detail.labels.generated'), t('manufacturing.detail.labels.generatedMsg', { count: labelCount }))
    } catch (err: any) { toast('error', t('common.error'), err.message) }
  }

  async function handleDeclareLabel(labelId: string) {
    try {
      await updateOFLabel(labelId, { is_declared: true, is_complete: true })
      setLabels(await getOFLabels(id!))
      toast('success', t('manufacturing.detail.labels.declaredSuccess'), t('manufacturing.detail.labels.declaredSuccessMsg'))
    } catch (err: any) { toast('error', t('common.error'), err.message) }
  }

  async function handleDeleteLabel(labelId: string) {
    try { await deleteOFLabel(labelId); setLabels(await getOFLabels(id!)) }
    catch (err: any) { toast('error', t('common.error'), err.message) }
  }

  async function handleDeleteLot(lotId: string) {
    try { await deleteOFLot(lotId); setLots(await getOFLots(id!)) }
    catch (err: any) { toast('error', t('common.error'), err.message) }
  }

  async function handleDeleteCons(consId: string) {
    try { await deleteOFConsumption(consId); setConsumptions(await getOFConsumptions(id!)) }
    catch (err: any) { toast('error', t('common.error'), err.message) }
  }

  if (loading) return <SkeletonTable rows={4} cols={4} />
  if (!mo) return <EmptyState title={t('manufacturing.detail.notFound')} description={t('manufacturing.detail.notFoundDescription')} action={<Button onClick={() => navigate('/production/manufacturing')}><ArrowLeft className="w-4 h-4" /> {t('manufacturing.detail.back')}</Button>} />

  const tabs = [
    { key: 'info', label: t('manufacturing.detail.tabs.info'), icon: ClipboardList },
    { key: 'labels', label: t('manufacturing.detail.tabs.labels'), icon: Tag },
    { key: 'lots', label: t('manufacturing.detail.tabs.lots'), icon: Calendar },
    { key: 'consumptions', label: t('manufacturing.detail.tabs.consumptions'), icon: Package },
    { key: 'sublevels', label: t('manufacturing.detail.tabs.sublevels'), icon: Layers },
  ] as const

  return (
    <div>
      <Breadcrumb items={[{ label: t('title'), path: '/production' }, { label: t('manufacturing.title'), path: '/production/manufacturing' }, { label: mo.number }]} />
      <PageHeader title={`OF ${mo.number}`} subtitle={mo.products?.name || '—'}
        action={
          <div className="flex gap-2">
            <Button variant="secondary" onClick={() => window.print()}><Printer className="w-4 h-4" /> {t('manufacturing.detail.print')}</Button>
            <Button variant="secondary" onClick={() => navigate('/production/manufacturing')}><ArrowLeft className="w-4 h-4" /> {t('manufacturing.detail.back')}</Button>
          </div>
        } />

      <div className="flex gap-2 mb-4">
        <Badge variant={statusVariants[mo.status] || 'neutral'}>{t('manufacturing.statuses.' + mo.status)}</Badge>
        <Badge variant={originVariants[mo.origin] || 'neutral'}>{t('manufacturing.origin')}: {t('manufacturing.origins.' + (mo.origin || 'manual'))}</Badge>
      </div>

      <div className="flex gap-1 border-b border-[var(--color-border)] mb-4">
        {tabs.map((tab) => {
          const Icon = tab.icon
          return (
            <button key={tab.key} onClick={() => { setActiveTab(tab.key); loadTabData(tab.key) }}
              className={`inline-flex items-center gap-2 px-4 py-2 text-sm font-medium border-b-2 transition-colors ${
                activeTab === tab.key
                  ? 'border-[var(--color-primary)] text-[var(--color-primary)]'
                  : 'border-transparent text-[var(--color-text-secondary)] hover:text-[var(--color-text)]'
              }`}>
              <Icon className="w-4 h-4" /> {tab.label}
            </button>
          )
        })}
      </div>

      {/* Tab: Informations */}
      {activeTab === 'info' && (
        <Card>
          <div className="grid grid-cols-2 gap-4 p-4">
            <InfoRow label={t('manufacturing.detail.info.number')} value={mo.number} />
            <InfoRow label={t('manufacturing.detail.info.status')} value={t('manufacturing.statuses.' + mo.status)} />
            <InfoRow label={t('manufacturing.detail.info.bom')} value={mo.boms ? `${mo.boms.code} — ${mo.boms.name}` : '—'} />
            <InfoRow label={t('manufacturing.detail.info.product')} value={mo.products ? `${mo.products.sku} — ${mo.products.name}` : '—'} />
            <InfoRow label={t('manufacturing.detail.info.quantity')} value={String(mo.quantity)} />
            <InfoRow label={t('manufacturing.detail.info.warehouse')} value={mo.warehouses?.name || '—'} />
            <InfoRow label={t('manufacturing.detail.info.routing')} value={mo.routings ? `${mo.routings.code} — ${mo.routings.name}` : '—'} />
            <InfoRow label={t('manufacturing.detail.info.startDate')} value={mo.start_date || '—'} />
            <InfoRow label={t('manufacturing.detail.info.endDate')} value={mo.end_date || '—'} />
            <InfoRow label={t('manufacturing.detail.info.origin')} value={t('manufacturing.origins.' + (mo.origin || 'manual'))} />
            {mo.lot_number && <InfoRow label={t('manufacturing.detail.info.lotNumber')} value={mo.lot_number} />}
            {mo.expiry_date && <InfoRow label={t('manufacturing.detail.info.expiryDate')} value={mo.expiry_date} />}
            {mo.expiry_type && <InfoRow label={t('manufacturing.detail.info.expiryType')} value={mo.expiry_type} />}
            {mo.additional_text && <div className="col-span-2"><InfoRow label={t('manufacturing.detail.info.additionalText')} value={mo.additional_text} /></div>}
            {mo.notes && <div className="col-span-2"><InfoRow label={t('manufacturing.detail.info.notes')} value={mo.notes} /></div>}
          </div>
        </Card>
      )}

      {/* Tab: Suivi Quantité (Étiquettes) */}
      {activeTab === 'labels' && (
        <div className="space-y-4">
          <Card>
            <div className="flex items-end gap-3 p-4">
              <Input label={t('manufacturing.detail.labels.count')} type="number" value={labelCount} onChange={(e) => setLabelCount(Number(e.target.value))} />
              <Input label={t('manufacturing.detail.labels.qtyPerLabel')} type="number" step="0.01" value={labelQty} onChange={(e) => setLabelQty(Number(e.target.value))} />
              <Button onClick={handleGenerateLabels}><Tag className="w-4 h-4" /> {t('manufacturing.detail.labels.generate')}</Button>
            </div>
          </Card>
          <Card>
            {labels.length === 0 ? (
              <EmptyState icon={<Tag className="w-8 h-8" />} title={t('manufacturing.detail.labels.noLabels')} description={t('manufacturing.detail.labels.noLabelsDescription')} />
            ) : (
              <Table headers={[t('manufacturing.detail.labels.labelNumber'), t('manufacturing.detail.labels.product'), t('manufacturing.detail.labels.plannedQty'), t('manufacturing.detail.labels.actualQty'), t('manufacturing.detail.labels.complete'), t('manufacturing.detail.labels.declared'), t('common.actions')]}>
                {labels.map((lbl) => (
                  <TableRow key={lbl.id}>
                    <TableCell className="font-mono text-xs">{lbl.label_number}</TableCell>
                    <TableCell className="text-sm">{lbl.products?.name || '—'}</TableCell>
                    <TableCell className="font-mono text-xs">{Number(lbl.planned_quantity)}</TableCell>
                    <TableCell className="font-mono text-xs">{Number(lbl.actual_quantity)}</TableCell>
                    <TableCell>{lbl.is_complete ? <Badge variant="success">{t('common.yes')}</Badge> : '—'}</TableCell>
                    <TableCell>{lbl.is_declared ? <Badge variant="success">{t('manufacturing.detail.labels.declaredBadge')}</Badge> : <Badge variant="neutral">{t('manufacturing.detail.labels.pendingBadge')}</Badge>}</TableCell>
                    <TableCell>
                      <div className="flex gap-1">
                        {!lbl.is_declared && <button onClick={() => handleDeclareLabel(lbl.id)} className="text-xs px-2 py-1 rounded bg-[var(--color-success)] text-white hover:opacity-80">{t('manufacturing.detail.labels.declare')}</button>}
                        <button onClick={() => handleDeleteLabel(lbl.id)} className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-3.5 h-3.5" /></button>
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </Table>
            )}
          </Card>
        </div>
      )}

      {/* Tab: Lots & Péremption */}
      {activeTab === 'lots' && (
        <div className="space-y-4">
          <div className="flex justify-end">
            <Button onClick={() => setShowLotForm(true)}><Plus className="w-4 h-4" /> {t('manufacturing.detail.lots.add')}</Button>
          </div>
          <Card>
            {lots.length === 0 ? (
              <EmptyState icon={<Calendar className="w-8 h-8" />} title={t('manufacturing.detail.lots.noLots')} description={t('manufacturing.detail.lots.noLotsDescription')} />
            ) : (
              <Table headers={[t('manufacturing.detail.lots.lotNumber'), t('manufacturing.detail.lots.product'), t('manufacturing.detail.lots.quantity'), t('manufacturing.detail.lots.productionDate'), t('manufacturing.detail.lots.expiryDate'), t('manufacturing.detail.lots.type'), t('common.actions')]}>
                {lots.map((lot) => (
                  <TableRow key={lot.id}>
                    <TableCell className="font-mono text-xs">{lot.lot_number}</TableCell>
                    <TableCell className="text-sm">{lot.products?.name || '—'}</TableCell>
                    <TableCell className="font-mono text-xs">{Number(lot.quantity)}</TableCell>
                    <TableCell className="text-xs">{lot.production_date || '—'}</TableCell>
                    <TableCell className="text-xs">{lot.custom_expiry_date || lot.expiry_date || '—'}</TableCell>
                    <TableCell>{lot.expiry_type ? <Badge variant="neutral">{lot.expiry_type}</Badge> : '—'}</TableCell>
                    <TableCell><button onClick={() => handleDeleteLot(lot.id)} className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-3.5 h-3.5" /></button></TableCell>
                  </TableRow>
                ))}
              </Table>
            )}
          </Card>
          {showLotForm && <LotFormModal moId={id!} products={products} onClose={() => setShowLotForm(false)} onSaved={async () => { setShowLotForm(false); setLots(await getOFLots(id!)) }} />}
        </div>
      )}

      {/* Tab: Consommation */}
      {activeTab === 'consumptions' && (
        <div className="space-y-4">
          <Card>
            <div className="flex items-center gap-3 p-4">
              <label className="flex items-center gap-2 text-sm">
                <input type="checkbox" checked={allowDeferred} onChange={(e) => setAllowDeferred(e.target.checked)} className="rounded" />
                {t('manufacturing.detail.consumptions.allowDeferred')}
              </label>
            </div>
          </Card>
          <div className="flex justify-end">
            <Button onClick={() => setShowConsForm(true)} disabled={mo.status === 'completed' && !allowDeferred}>
              <Plus className="w-4 h-4" /> {t('manufacturing.detail.consumptions.add')}
            </Button>
          </div>
          <Card>
            {consumptions.length === 0 ? (
              <EmptyState icon={<Package className="w-8 h-8" />} title={t('manufacturing.detail.consumptions.noConsumptions')} description={t('manufacturing.detail.consumptions.noConsumptionsDescription')} />
            ) : (
              <Table headers={[t('manufacturing.detail.consumptions.product'), t('manufacturing.detail.consumptions.quantity'), t('manufacturing.detail.consumptions.unit'), t('manufacturing.detail.consumptions.date'), t('manufacturing.detail.consumptions.deferred'), t('manufacturing.detail.consumptions.notes'), t('common.actions')]}>
                {consumptions.map((cons) => (
                  <TableRow key={cons.id}>
                    <TableCell className="text-sm">{cons.products?.name || '—'}</TableCell>
                    <TableCell className="font-mono text-xs">{Number(cons.quantity)}</TableCell>
                    <TableCell className="text-xs">{cons.unit}</TableCell>
                    <TableCell className="text-xs">{cons.consumption_date}</TableCell>
                    <TableCell>{cons.is_deferred ? <Badge variant="warning">{t('manufacturing.detail.consumptions.deferred')}</Badge> : '—'}</TableCell>
                    <TableCell className="text-xs">{cons.notes || '—'}</TableCell>
                    <TableCell><button onClick={() => handleDeleteCons(cons.id)} className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-3.5 h-3.5" /></button></TableCell>
                  </TableRow>
                ))}
              </Table>
            )}
          </Card>
          {showConsForm && <ConsumptionFormModal moId={id!} products={products} isDeferred={mo.status === 'completed'} onClose={() => setShowConsForm(false)} onSaved={async () => { setShowConsForm(false); setConsumptions(await getOFConsumptions(id!)) }} />}
        </div>
      )}

      {/* Tab: Sous-niveaux */}
      {activeTab === 'sublevels' && (
        <Card>
          {subMOs.length === 0 ? (
            <EmptyState icon={<Layers className="w-8 h-8" />} title={t('manufacturing.detail.sublevels.noSubMOs')} description={t('manufacturing.detail.sublevels.noSubMOsDescription')} />
          ) : (
            <Table headers={[t('manufacturing.detail.sublevels.number'), t('manufacturing.detail.sublevels.product'), t('manufacturing.detail.sublevels.quantity'), t('manufacturing.detail.sublevels.status'), t('manufacturing.detail.sublevels.view')]}>
              {subMOs.map((sub) => (
                <TableRow key={sub.id}>
                  <TableCell className="font-mono text-xs">{sub.number}</TableCell>
                  <TableCell className="text-sm">—</TableCell>
                  <TableCell className="font-mono text-xs">{sub.quantity}</TableCell>
                  <TableCell><Badge variant={statusVariants[sub.status] || 'neutral'}>{t('manufacturing.statuses.' + sub.status)}</Badge></TableCell>
                  <TableCell><Link to={`/production/of/${sub.id}`} className="text-[var(--color-primary)] text-xs hover:underline">{t('manufacturing.detail.sublevels.view')} →</Link></TableCell>
                </TableRow>
              ))}
            </Table>
          )}
        </Card>
      )}
    </div>
  )
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="text-xs text-[var(--color-text-secondary)] mb-0.5">{label}</p>
      <p className="text-sm font-medium">{value}</p>
    </div>
  )
}

function LotFormModal({ moId, products, onClose, onSaved }: { moId: string; products: Product[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('production')
  const { toast } = useToast()
  const [lotNumber, setLotNumber] = useState('')
  const [productId, setProductId] = useState('')
  const [quantity, setQuantity] = useState(0)
  const [productionDate, setProductionDate] = useState('')
  const [expiryDate, setExpiryDate] = useState('')
  const [customExpiryDate, setCustomExpiryDate] = useState('')
  const [expiryType, setExpiryType] = useState('')

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!lotNumber) { toast('error', t('common.required'), t('manufacturing.detail.lots.lotNumberRequired')); return }
    try {
      await createOFLot({
        manufacturing_order_id: moId, lot_number: lotNumber,
        product_id: productId || null, quantity,
        production_date: productionDate || null,
        expiry_date: expiryDate || null,
        custom_expiry_date: customExpiryDate || null,
        expiry_type: (expiryType as any) || null,
      })
      onSaved()
    } catch (err: any) { toast('error', t('common.error'), err.message) }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40" onClick={onClose}>
      <div className="bg-[var(--color-surface)] rounded-xl shadow-xl p-6 w-full max-w-md" onClick={(e) => e.stopPropagation()}>
        <h2 className="text-lg font-semibold mb-4">{t('manufacturing.detail.lots.create')}</h2>
        <form onSubmit={handleSubmit} className="space-y-3">
          <Input label={t('manufacturing.detail.lots.lotNumber')} value={lotNumber} onChange={(e) => setLotNumber(e.target.value)} required />
          <Select label={t('manufacturing.detail.lots.product')} value={productId} onChange={(e) => setProductId(e.target.value)} options={[{ value: '', label: '—' }, ...products.map((p) => ({ value: p.id, label: p.name }))]} />
          <Input label={t('manufacturing.detail.lots.quantity')} type="number" step="0.01" value={quantity} onChange={(e) => setQuantity(Number(e.target.value))} />
          <Input label={t('manufacturing.detail.lots.productionDate')} type="date" value={productionDate} onChange={(e) => setProductionDate(e.target.value)} />
          <Input label={t('manufacturing.detail.lots.expiryDateAuto')} type="date" value={expiryDate} onChange={(e) => setExpiryDate(e.target.value)} />
          <Input label={t('manufacturing.detail.lots.expiryDateCustom')} type="date" value={customExpiryDate} onChange={(e) => setCustomExpiryDate(e.target.value)} />
          <Select label={t('manufacturing.detail.lots.expiryTypeLabel')} value={expiryType} onChange={(e) => setExpiryType(e.target.value)} options={[{ value: '', label: '—' }, { value: 'DLUO', label: 'DLUO' }, { value: 'DDM', label: 'DDM' }, { value: 'DLC', label: 'DLC' }]} />
          <div className="flex gap-2 justify-end pt-2">
            <Button type="button" variant="secondary" onClick={onClose}>{t('common.cancel')}</Button>
            <Button type="submit">{t('common.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}

function ConsumptionFormModal({ moId, products, isDeferred, onClose, onSaved }: { moId: string; products: Product[]; isDeferred: boolean; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('production')
  const { toast } = useToast()
  const [productId, setProductId] = useState('')
  const [quantity, setQuantity] = useState(0)
  const [unit, setUnit] = useState('unit')
  const [notes, setNotes] = useState('')

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!productId) { toast('error', t('common.required'), t('manufacturing.detail.consumptions.productRequired')); return }
    try {
      await createOFConsumption({
        manufacturing_order_id: moId, product_id: productId,
        quantity, unit, consumption_date: new Date().toISOString().split('T')[0],
        is_deferred: isDeferred, notes: notes || null,
      })
      onSaved()
    } catch (err: any) { toast('error', t('common.error'), err.message) }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40" onClick={onClose}>
      <div className="bg-[var(--color-surface)] rounded-xl shadow-xl p-6 w-full max-w-sm" onClick={(e) => e.stopPropagation()}>
        <h2 className="text-lg font-semibold mb-4">{t('manufacturing.detail.consumptions.add')}</h2>
        <form onSubmit={handleSubmit} className="space-y-3">
          <Select label={t('manufacturing.detail.consumptions.product')} value={productId} onChange={(e) => setProductId(e.target.value)} options={[{ value: '', label: '—' }, ...products.map((p) => ({ value: p.id, label: p.name }))]} />
          <Input label={t('manufacturing.detail.consumptions.quantity')} type="number" step="0.01" value={quantity} onChange={(e) => setQuantity(Number(e.target.value))} />
          <Input label={t('manufacturing.detail.consumptions.unit')} value={unit} onChange={(e) => setUnit(e.target.value)} />
          <Input label={t('manufacturing.detail.consumptions.notes')} value={notes} onChange={(e) => setNotes(e.target.value)} />
          {isDeferred && <p className="text-xs text-[var(--color-warning)]">{t('manufacturing.detail.consumptions.deferredHint')}</p>}
          <div className="flex gap-2 justify-end pt-2">
            <Button type="button" variant="secondary" onClick={onClose}>{t('common.cancel')}</Button>
            <Button type="submit">{t('common.add')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
