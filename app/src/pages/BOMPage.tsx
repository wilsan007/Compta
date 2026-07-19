import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input } from '@/components/ui'
import { formatCurrency } from '@/lib/utils'
import { getBOMs, createBOM, deleteBOM, getBOMLines, createBOMLine, deleteBOMLine, getProducts } from '@/lib/queries'
import { Plus, Trash2, X, Layers, ChevronDown, ChevronRight } from 'lucide-react'
import type { BOM, Product } from '@/types'
import { useToast } from '@/lib/toast'

export function BOMPage() {
  const { toast } = useToast()
const [boms, setBOMs] = useState<BOM[]>([])
  const [products, setProducts] = useState<Product[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [expanded, setExpanded] = useState<Set<string>>(new Set())
  const [lines, setLines] = useState<Record<string, any[]>>({})
  const [showLineForm, setShowLineForm] = useState<string | null>(null)

  const loadData = useCallback(async () => {
    try {
      const [bs, prods] = await Promise.all([getBOMs(), getProducts()])
      setBOMs(bs || [])
      setProducts(prods || [])
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
  if (!window.confirm('Supprimer cette nomenclature ?')) return
    try { await deleteBOM(id); await loadData() }
    catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
  }

  async function handleDeleteLine(lineId: string, bomId: string) {
    try { await deleteBOMLine(lineId); const lns = await getBOMLines(bomId); setLines((prev) => ({ ...prev, [bomId]: lns })) }
    catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: 'Stock' }, { label: 'Nomenclatures' }]} />
      <PageHeader title="Nomenclatures (BOM)" subtitle={`${boms.length} nomenclature(s)`}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouvelle BOM</Button>} />

      {loading ? <SkeletonTable rows={4} cols={4} /> : boms.length === 0 ? (
        <EmptyState icon={<Layers className="w-8 h-8" />} title="Aucune nomenclature" description="Créez votre première nomenclature."
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouvelle BOM</Button>} />
      ) : (
        <Card>
          <Table headers={['Code', 'Nom', 'Quantité', 'Actif', 'Actions']}>
            {boms.map((b) => (
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
                  <TableCell className="font-mono text-xs">{Number(b.quantity)} {b.unit}</TableCell>
                  <TableCell><span className={`text-xs px-2 py-0.5 rounded ${b.active ? 'bg-[var(--color-success)]/10 text-[var(--color-success)]' : 'bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]'}`}>{b.active ? 'Actif' : 'Inactif'}</span></TableCell>
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
                      <p className="text-xs text-[var(--color-text-secondary)]">Aucune ligne. Cliquez sur + pour ajouter un composant.</p>
                    ) : (
                      <Table headers={['#', 'Composant', 'Quantité', 'Coût unit.', 'Coût total', 'Actions']}>
                        {(lines[b.id] || []).map((line, i) => (
                          <TableRow key={line.id}>
                            <TableCell className="text-xs">{i + 1}</TableCell>
                            <TableCell className="text-sm">{line.products?.name || '—'}</TableCell>
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

      {showForm && <BOMForm products={products} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
      {showLineForm && <BOMLineForm bomId={showLineForm} products={products} onClose={() => setShowLineForm(null)} onSaved={async () => { const id = showLineForm; setShowLineForm(null); const lns = await getBOMLines(id); setLines((prev) => ({ ...prev, [id]: lns })) }} />}
    </div>
  )
}

function BOMForm({ products, onClose, onSaved }: { products: Product[]; onClose: () => void; onSaved: () => void }) {
  const [code, setCode] = useState('')
  const { toast } = useToast()
  const [name, setName] = useState('')
  const [productId, setProductId] = useState('')
  const [quantity, setQuantity] = useState(1)
  const [unit, setUnit] = useState('unit')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await createBOM({ code, name, product_id: productId || null, quantity, unit, active: true } as any)
      onSaved()
    } catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">Nouvelle nomenclature</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <Input label="Code" required value={code} onChange={(e) => setCode(e.target.value)} placeholder="BOM-001" />
            <Input label="Nom" required value={name} onChange={(e) => setName(e.target.value)} />
          </div>
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">Produit fini</label>
            <select className="input" value={productId} onChange={(e) => setProductId(e.target.value)}>
              <option value="">— Sélectionner —</option>
              {products.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label="Quantité" type="number" step="0.01" value={quantity} onChange={(e) => setQuantity(Number(e.target.value))} />
            <Input label="Unité" value={unit} onChange={(e) => setUnit(e.target.value)} />
          </div>
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>Annuler</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : 'Créer'}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}

function BOMLineForm({ bomId, products, onClose, onSaved }: { bomId: string; products: Product[]; onClose: () => void; onSaved: () => void }) {
  const [productId, setProductId] = useState('')
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
    } catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">Ajouter un composant</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">Composant</label>
            <select className="input" value={productId} onChange={(e) => setProductId(e.target.value)} required>
              <option value="">— Sélectionner —</option>
              {products.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
          </div>
          <div className="grid grid-cols-3 gap-4">
            <Input label="Quantité" type="number" step="0.01" required value={quantity} onChange={(e) => setQuantity(Number(e.target.value))} />
            <Input label="Coût unitaire" type="number" step="0.01" value={unitCost} onChange={(e) => setUnitCost(Number(e.target.value))} />
            <Input label="Position" type="number" value={position} onChange={(e) => setPosition(Number(e.target.value))} />
          </div>
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>Annuler</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : 'Ajouter'}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
