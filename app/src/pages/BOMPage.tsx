import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select, Badge } from '@/components/ui'
import { formatCurrency } from '@/lib/utils'
import { getBOMs, createBOM, deleteBOM, getBOMLines, createBOMLine, deleteBOMLine, getProducts } from '@/lib/queries'
import { Plus, Trash2, X, Layers, ChevronDown, ChevronRight, GitBranch } from 'lucide-react'
import type { BOM, Product } from '@/types'
import { useToast } from '@/lib/toast'
import { useStatusLabels } from '@/lib/statusUtils'
import { getRoutings } from '@/lib/queries'
import type { Routing } from '@/types'
import { ArticleInterrogationModal } from '@/components/ArticleInterrogationModal'

export function BOMPage() {
  const { t } = useTranslation('production')
  const { toast } = useToast()
  const { getStatusLabel } = useStatusLabels()
const [boms, setBOMs] = useState<BOM[]>([])
  const [products, setProducts] = useState<Product[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [expanded, setExpanded] = useState<Set<string>>(new Set())
  const [lines, setLines] = useState<Record<string, any[]>>({})
  const [showLineForm, setShowLineForm] = useState<string | null>(null)
  const [routings, setRoutings] = useState<Routing[]>([])
  const [typeFilter, setTypeFilter] = useState('')
  const [interrogationProduct, setInterrogationProduct] = useState<{ id: string; name?: string; sku?: string } | null>(null)

  const loadData = useCallback(async () => {
    try {
      const [bs, prods, rts] = await Promise.all([getBOMs(), getProducts(), getRoutings()])
      setBOMs(bs || [])
      setProducts(prods || [])
      setRoutings(rts || [])
    } catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function toggleExpand(id: string) {
    const next = new Set(expanded)
    if (next.has(id)) { next.delete(id) }
    else {
      next.add(id)
      if (!lines[id]) {
        try {
          const lns = await getBOMLines(id)
          setLines((prev) => ({ ...prev, [id]: lns }))
        } catch (err) { console.error('Error:', err) }
      }
    }
    setExpanded(next)
  }

  async function handleDelete(id: string) {
  if (!window.confirm(t('bom.confirmDelete'))) return
    try { await deleteBOM(id); await loadData() }
    catch (err: any) { toast('error', t('common.error'), err.message || 'échec') }
  }

  async function handleDeleteLine(lineId: string, bomId: string) {
    try { await deleteBOMLine(lineId); const lns = await getBOMLines(bomId); setLines((prev) => ({ ...prev, [bomId]: lns })) }
    catch (err: any) { toast('error', t('common.error'), err.message || 'échec') }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('title'), path: '/production' }, { label: t('bom.title') }]} />
      <PageHeader title={t('bom.title')} subtitle={`${boms.length} nomenclature(s)`}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('bom.new')}</Button>} />

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-48">
          <Select label={t('bom.type')} value={typeFilter} onChange={(e) => setTypeFilter(e.target.value)} options={[
            { value: '', label: 'Tous' }, { value: 'standard', label: t('bom.standard') }, { value: 'amalgam', label: t('bom.amalgam') },
          ]} />
        </div>
      </div>

      {loading ? <SkeletonTable rows={4} cols={4} /> : boms.length === 0 ? (
        <EmptyState icon={<Layers className="w-8 h-8" />} title={t('bom.noBOMs')} description={t('bom.noBOMsDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('bom.new')}</Button>} />
      ) : (
        <Card>
          <Table headers={['Code', t('bom.name'), t('bom.type'), t('bom.quantity'), t('bom.active'), t('common.actions')]}>
            {boms.filter((b) => !typeFilter || (b as any).bom_type === typeFilter).map((b) => (
              <div key={b.id}>
                <TableRow>
                  <TableCell className="font-mono text-xs">
                    <div className="flex items-center gap-1">
                      <button onClick={() => toggleExpand(b.id)} className="p-0.5 rounded hover:bg-[var(--color-neutral-100)]">
                        {expanded.has(b.id) ? <ChevronDown className="w-3.5 h-3.5" /> : <ChevronRight className="w-3.5 h-3.5" />}
                      </button>
                      {b.code}
                    </div>
                  </TableCell>
                  <TableCell className="font-medium">{b.name}</TableCell>
                  <TableCell>{(b as any).bom_type === 'amalgam' ? <Badge variant="warning"><GitBranch className="w-3 h-3 inline mr-1" />{t('bom.amalgam')}</Badge> : <Badge variant="neutral">{t('bom.standard')}</Badge>}</TableCell>
                  <TableCell className="font-mono text-xs">{Number(b.quantity)} {b.unit}</TableCell>
                  <TableCell><span className={`text-xs px-2 py-0.5 rounded ${b.active ? 'bg-[var(--color-success)]/10 text-[var(--color-success)]' : 'bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]'}`}>{b.active ? getStatusLabel('active') : getStatusLabel('inactive')}</span></TableCell>
                  <TableCell>
                    <div className="flex gap-1">
                      <button onClick={() => setShowLineForm(b.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)]"><Plus className="w-4 h-4" /></button>
                      <button onClick={() => handleDelete(b.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
                    </div>
                  </TableCell>
                </TableRow>
                {expanded.has(b.id) && (
                  <div className="px-8 py-3 bg-[var(--color-neutral-50)] border-y border-[var(--color-border)]">
                    {(lines[b.id] || []).length === 0 ? (
                      <p className="text-xs text-[var(--color-text-secondary)]">{t('bom.noLines')}</p>
                    ) : (
                      <Table headers={['#', t('bom.component'), t('bom.quantity'), t('bom.unitCost'), t('bom.totalCost'), t('common.actions')]}>
                        {(lines[b.id] || []).map((line, i) => (
                          <TableRow key={line.id}>
                            <TableCell className="text-xs">{i + 1}</TableCell>
                            <TableCell className="text-sm">
                              <button onClick={() => setInterrogationProduct({ id: line.product_id, name: line.products?.name, sku: line.products?.sku })} className="text-[var(--color-primary)] hover:underline">
                                {line.products?.name || '—'}
                              </button>
                              {(b as any).bom_type === 'amalgam' && Number(line.unit_cost) === 0 && (
                                <Badge variant="success" >{t('bom.finishedProduct')}</Badge>
                              )}
                            </TableCell>
                            <TableCell className="font-mono text-xs">{Number(line.quantity)}</TableCell>
                            <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(line.unit_cost))}</TableCell>
                            <TableCell className="font-mono text-xs font-semibold text-right">{formatCurrency(Number(line.quantity) * Number(line.unit_cost))}</TableCell>
                            <TableCell><button onClick={() => handleDeleteLine(line.id, b.id)} className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-3.5 h-3.5" /></button></TableCell>
                          </TableRow>
                        ))}
                      </Table>
                    )}
                  </div>
                )}
              </div>
            ))}
          </Table>
        </Card>
      )}

      {showForm && <BOMForm products={products} routings={routings} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
      {showLineForm && <BOMLineForm bomId={showLineForm} products={products} onClose={() => setShowLineForm(null)} onSaved={async () => { const id = showLineForm; setShowLineForm(null); const lns = await getBOMLines(id); setLines((prev) => ({ ...prev, [id]: lns })) }} />}
      {interrogationProduct && <ArticleInterrogationModal productId={interrogationProduct.id} productName={interrogationProduct.name} productSku={interrogationProduct.sku} open={true} onClose={() => setInterrogationProduct(null)} />}
    </div>
  )
}

function BOMForm({ products, routings, onClose, onSaved }: { products: Product[]; routings: Routing[]; onClose: () => void; onSaved: () => void }) {
  const [code, setCode] = useState('')
  const { t } = useTranslation('production')
  const { toast } = useToast()
  const [name, setName] = useState('')
  const [productId, setProductId] = useState('')
  const [quantity, setQuantity] = useState(1)
  const [unit, setUnit] = useState('unit')
  const [bomType, setBomType] = useState('standard')
  const [routingId, setRoutingId] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await createBOM({ code, name, product_id: productId || null, quantity, unit, active: true, bom_type: bomType, routing_id: routingId || null } as any)
      onSaved()
    } catch (err: any) { toast('error', t('common.error'), err.message || 'échec') }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('bom.create')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <Input label="Code" required value={code} onChange={(e) => setCode(e.target.value)} placeholder="BOM-001" />
            <Input label={t('bom.name')} required value={name} onChange={(e) => setName(e.target.value)} />
          </div>
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('bom.product')}</label>
            <select className="input" value={productId} onChange={(e) => setProductId(e.target.value)}>
              <option value="">{t('bom.selectProduct')}</option>
              {products.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('bom.quantity')} type="number" step="0.01" value={quantity} onChange={(e) => setQuantity(Number(e.target.value))} />
            <Input label={t('bom.unit')} value={unit} onChange={(e) => setUnit(e.target.value)} />
          </div>
          <Select label={t('bom.bomType')} value={bomType} onChange={(e) => setBomType(e.target.value)} options={[
            { value: 'standard', label: t('bom.standard') }, { value: 'amalgam', label: t('bom.amalgam') },
          ]} />
          <Select label={t('bom.routing')} value={routingId} onChange={(e) => setRoutingId(e.target.value)} options={[{ value: '', label: '—' }, ...routings.map((r) => ({ value: r.id, label: `${r.code} — ${r.name}` }))]} />
          {bomType === 'amalgam' && (
            <div className="bg-[var(--color-warning)]/10 border border-[var(--color-warning)]/30 rounded-lg p-3 text-xs text-[var(--color-text-secondary)]">
              <strong>{t('bom.amalgam')}:</strong> {t('bom.amalgamHint')}
            </div>
          )}
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>{t('common.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : t('common.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}

function BOMLineForm({ bomId, products, onClose, onSaved }: { bomId: string; products: Product[]; onClose: () => void; onSaved: () => void }) {
  const [productId, setProductId] = useState('')
  const { t } = useTranslation('production')
  const { toast } = useToast()
  const [quantity, setQuantity] = useState(1)
  const [unitCost, setUnitCost] = useState(0)
  const [position, setPosition] = useState(1)
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await createBOMLine({ bom_id: bomId, product_id: productId, quantity, unit_cost: unitCost, position } as any)
      onSaved()
    } catch (err: any) { toast('error', t('common.error'), err.message || 'échec') }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('bom.addLine')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('bom.component')}</label>
            <select className="input" value={productId} onChange={(e) => setProductId(e.target.value)} required>
              <option value="">{t('bom.selectProduct')}</option>
              {products.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
          </div>
          <div className="grid grid-cols-3 gap-4">
            <Input label={t('bom.quantity')} type="number" step="0.01" required value={quantity} onChange={(e) => setQuantity(Number(e.target.value))} />
            <Input label={t('bom.unitCost')} type="number" step="0.01" value={unitCost} onChange={(e) => setUnitCost(Number(e.target.value))} />
            <Input label={t('bom.position')} type="number" value={position} onChange={(e) => setPosition(Number(e.target.value))} />
          </div>
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>{t('common.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : t('common.add')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
