import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getPriceLists, createPriceList, deletePriceList, getPriceListLines, createPriceListLine, deletePriceListLine, getProducts } from '@/lib/queries'
import { Plus, Trash2, X, Tag, ChevronDown, ChevronRight } from 'lucide-react'
import type { PriceList, Product } from '@/types'
import { useToast } from '@/lib/toast'

export function PriceListsPage() {
  const { toast } = useToast()
const [lists, setLists] = useState<PriceList[]>([])
  const [products, setProducts] = useState<Product[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [expanded, setExpanded] = useState<Set<string>>(new Set())
  const [lines, setLines] = useState<Record<string, any[]>>({})
  const [showLineForm, setShowLineForm] = useState<string | null>(null)

  const loadData = useCallback(async () => {
    try {
      const [pls, prods] = await Promise.all([getPriceLists(), getProducts()])
      setLists(pls || [])
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
          const lns = await getPriceListLines(id)
          setLines((prev) => ({ ...prev, [id]: lns }))
        } catch (err) { console.error('Error:', err) }
      }
    }
    setExpanded(next)
  }

  async function handleDelete(id: string) {
  if (!window.confirm('Supprimer cette liste de prix ?')) return
    try { await deletePriceList(id); await loadData() }
    catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
  }

  async function handleDeleteLine(lineId: string, listId: string) {
    try { await deletePriceListLine(lineId); const lns = await getPriceListLines(listId); setLines((prev) => ({ ...prev, [listId]: lns })) }
    catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: 'Stock' }, { label: 'Listes de prix' }]} />
      <PageHeader title="Listes de prix" subtitle={`${lists.length} liste(s)`}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouvelle liste</Button>} />

      {loading ? <SkeletonTable rows={4} cols={5} /> : lists.length === 0 ? (
        <EmptyState icon={<Tag className="w-8 h-8" />} title="Aucune liste de prix" description="Créez votre première liste de prix."
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouvelle liste</Button>} />
      ) : (
        <Card>
          <Table headers={['Nom', 'Type', 'Devise', 'Validité', 'Actions']}>
            {lists.map((l) => (
              <div key={l.id}>
                <TableRow>
                  <TableCell className="font-medium">
                    <div className="flex items-center gap-1">
                      <button onClick={() => toggleExpand(l.id)} className="p-0.5 rounded hover:bg-[var(--color-neutral-100)]">
                        {expanded.has(l.id) ? <ChevronDown className="w-3.5 h-3.5" /> : <ChevronRight className="w-3.5 h-3.5" />}
                      </button>
                      {l.name}
                    </div>
                  </TableCell>
                  <TableCell className="text-xs">{l.type === 'sales' ? 'Vente' : 'Achat'}</TableCell>
                  <TableCell className="text-xs">{l.currency}</TableCell>
                  <TableCell className="text-xs">{l.valid_from ? formatDate(l.valid_from) : '—'} → {l.valid_to ? formatDate(l.valid_to) : '—'}</TableCell>
                  <TableCell>
                    <div className="flex gap-1">
                      <button onClick={() => setShowLineForm(l.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)]" title="Ajouter ligne">
                        <Plus className="w-4 h-4" />
                      </button>
                      <button onClick={() => handleDelete(l.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </div>
                  </TableCell>
                </TableRow>
                {expanded.has(l.id) && (
                  <div className="px-8 py-3 bg-[var(--color-neutral-50)] border-y border-[var(--color-border)]">
                    {(lines[l.id] || []).length === 0 ? (
                      <p className="text-xs text-[var(--color-text-secondary)]">Aucune ligne. Cliquez sur + pour ajouter un produit.</p>
                    ) : (
                      <Table headers={['Produit', 'Prix', 'Qté min', 'Remise %', 'Actions']}>
                        {(lines[l.id] || []).map((line) => (
                          <TableRow key={line.id}>
                            <TableCell className="text-sm">{line.products?.name || '—'}</TableCell>
                            <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(line.unit_price))}</TableCell>
                            <TableCell className="font-mono text-xs">{Number(line.min_quantity)}</TableCell>
                            <TableCell className="font-mono text-xs">{Number(line.discount_percent)}%</TableCell>
                            <TableCell>
                              <button onClick={() => handleDeleteLine(line.id, l.id)} className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                                <Trash2 className="w-3.5 h-3.5" />
                              </button>
                            </TableCell>
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

      {showForm && <PriceListForm onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
      {showLineForm && <PriceListLineForm priceListId={showLineForm} products={products} onClose={() => setShowLineForm(null)} onSaved={async () => { const id = showLineForm; setShowLineForm(null); const lns = await getPriceListLines(id); setLines((prev) => ({ ...prev, [id]: lns })) }} />}
    </div>
  )
}

function PriceListForm({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const [name, setName] = useState('')
  const { toast } = useToast()
  const [code, setCode] = useState('')
  const [type, setType] = useState('sales')
  const [validFrom, setValidFrom] = useState('')
  const [validTo, setValidTo] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await createPriceList({ name, code: code || null, type: type as any, currency: 'EUR', valid_from: validFrom || null, valid_to: validTo || null, active: true, is_default: false } as any)
      onSaved()
    } catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">Nouvelle liste de prix</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label="Nom" required value={name} onChange={(e) => setName(e.target.value)} />
          <div className="grid grid-cols-2 gap-4">
            <Input label="Code" value={code} onChange={(e) => setCode(e.target.value)} />
            <Select label="Type" value={type} onChange={(e) => setType(e.target.value)} options={[{ value: 'sales', label: 'Vente' }, { value: 'purchase', label: 'Achat' }]} />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label="Valable depuis" type="date" value={validFrom} onChange={(e) => setValidFrom(e.target.value)} />
            <Input label="Valable jusqu'au" type="date" value={validTo} onChange={(e) => setValidTo(e.target.value)} />
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

function PriceListLineForm({ priceListId, products, onClose, onSaved }: { priceListId: string; products: Product[]; onClose: () => void; onSaved: () => void }) {
  const [productId, setProductId] = useState('')
  const { toast } = useToast()
  const [unitPrice, setUnitPrice] = useState(0)
  const [minQuantity, setMinQuantity] = useState(1)
  const [discountPercent, setDiscountPercent] = useState(0)
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await createPriceListLine({ price_list_id: priceListId, product_id: productId, unit_price: unitPrice, min_quantity: minQuantity, discount_percent: discountPercent } as any)
      onSaved()
    } catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">Ajouter un produit</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">Produit</label>
            <select className="input" value={productId} onChange={(e) => setProductId(e.target.value)} required>
              <option value="">— Sélectionner —</option>
              {products.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
          </div>
          <div className="grid grid-cols-3 gap-4">
            <Input label="Prix unitaire" type="number" step="0.01" required value={unitPrice} onChange={(e) => setUnitPrice(Number(e.target.value))} />
            <Input label="Qté min" type="number" step="0.01" value={minQuantity} onChange={(e) => setMinQuantity(Number(e.target.value))} />
            <Input label="Remise %" type="number" step="0.01" value={discountPercent} onChange={(e) => setDiscountPercent(Number(e.target.value))} />
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
