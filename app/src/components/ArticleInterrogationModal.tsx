import { useState, useEffect, useCallback } from 'react'
import { X, RefreshCw, Package, Truck, FileText, Layers } from 'lucide-react'
import { Button, Table, TableRow, TableCell, Badge, SkeletonTable } from '@/components/ui'
import { getProductStock, getProductSupplierPrices, getProductDocuments, getProductBOMs } from '@/lib/queries'
import { formatCurrency, formatDate } from '@/lib/utils'

interface ArticleInterrogationModalProps {
  productId: string
  productName?: string
  productSku?: string
  open: boolean
  onClose: () => void
}

type TabKey = 'stock' | 'suppliers' | 'documents' | 'boms'

const tabs: { key: TabKey; label: string; icon: any }[] = [
  { key: 'stock', label: 'Stock', icon: Package },
  { key: 'suppliers', label: 'Tarifs fournisseurs', icon: Truck },
  { key: 'documents', label: 'Documents liés', icon: FileText },
  { key: 'boms', label: 'Nomenclatures', icon: Layers },
]

export function ArticleInterrogationModal({ productId, productName, productSku, open, onClose }: ArticleInterrogationModalProps) {
  const [activeTab, setActiveTab] = useState<TabKey>('stock')
  const [loading, setLoading] = useState(true)
  const [stock, setStock] = useState<any[]>([])
  const [supplierPrices, setSupplierPrices] = useState<any[]>([])
  const [documents, setDocuments] = useState<any[]>([])
  const [bomsData, setBomsData] = useState<{ asFinished: any[]; asComponent: any[] }>({ asFinished: [], asComponent: [] })

  const loadData = useCallback(async () => {
    if (!productId) return
    setLoading(true)
    try {
      if (activeTab === 'stock') {
        setStock(await getProductStock(productId))
      } else if (activeTab === 'suppliers') {
        setSupplierPrices(await getProductSupplierPrices(productId))
      } else if (activeTab === 'documents') {
        setDocuments(await getProductDocuments(productId))
      } else if (activeTab === 'boms') {
        setBomsData(await getProductBOMs(productId))
      }
    } catch (err) { console.error('Error loading article data:', err) }
    finally { setLoading(false) }
  }, [productId, activeTab])

  useEffect(() => {
    if (open) loadData()
  }, [open, loadData])

  function handleRefresh() { loadData() }

  if (!open) return null

  const totalStock = stock.reduce((sum, s) => sum + Number(s.quantity || 0), 0)
  const totalValue = stock.reduce((sum, s) => sum + Number(s.quantity || 0) * Number(s.unit_cost || 0), 0)

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40" onClick={onClose}>
      <div className="bg-[var(--color-surface)] rounded-xl shadow-xl w-full max-w-4xl max-h-[90vh] flex flex-col" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <div>
            <h2 className="text-lg font-semibold">Interrogation article</h2>
            <p className="text-sm text-[var(--color-text-secondary)]">{productName || '—'} {productSku ? `· ${productSku}` : ''}</p>
          </div>
          <div className="flex items-center gap-2">
            <Button variant="secondary" size="sm" onClick={handleRefresh}><RefreshCw className="w-3.5 h-3.5" /> Actualiser</Button>
            <button onClick={onClose} className="p-2 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
          </div>
        </div>

        <div className="flex border-b border-[var(--color-border)] px-6">
          {tabs.map((tab) => {
            const Icon = tab.icon
            return (
              <button key={tab.key} onClick={() => setActiveTab(tab.key)}
                className={`flex items-center gap-2 px-4 py-3 text-sm font-medium border-b-2 transition-colors ${activeTab === tab.key ? 'border-[var(--color-primary)] text-[var(--color-primary)]' : 'border-transparent text-[var(--color-text-secondary)] hover:text-[var(--color-text)]'}`}>
                <Icon className="w-4 h-4" /> {tab.label}
              </button>
            )
          })}
        </div>

        <div className="flex-1 overflow-y-auto p-6">
          {loading ? <SkeletonTable rows={4} cols={5} /> : (
            <>
              {activeTab === 'stock' && (
                <div>
                  <div className="grid grid-cols-3 gap-4 mb-4">
                    <div className="p-3 rounded-lg bg-[var(--color-neutral-50)]">
                      <p className="text-xs text-[var(--color-text-secondary)]">Stock total</p>
                      <p className="text-lg font-semibold">{totalStock}</p>
                    </div>
                    <div className="p-3 rounded-lg bg-[var(--color-neutral-50)]">
                      <p className="text-xs text-[var(--color-text-secondary)]">Valeur stock</p>
                      <p className="text-lg font-semibold">{formatCurrency(totalValue)}</p>
                    </div>
                    <div className="p-3 rounded-lg bg-[var(--color-neutral-50)]">
                      <p className="text-xs text-[var(--color-text-secondary)]">Dépôts</p>
                      <p className="text-lg font-semibold">{stock.length}</p>
                    </div>
                  </div>
                  {stock.length === 0 ? (
                    <p className="text-center text-sm text-[var(--color-text-secondary)] py-8">Aucun stock enregistré pour cet article.</p>
                  ) : (
                    <Table headers={['Dépôt', 'Quantité', 'Réservée', 'Disponible', 'Coût unitaire', 'Valeur']}>
                      {stock.map((s) => (
                        <TableRow key={s.id}>
                          <TableCell className="text-sm">{s.warehouses?.name || '—'}</TableCell>
                          <TableCell className="font-mono text-xs">{Number(s.quantity)}</TableCell>
                          <TableCell className="font-mono text-xs">{Number(s.reserved_quantity || 0)}</TableCell>
                          <TableCell className="font-mono text-xs font-semibold">{Number(s.quantity) - Number(s.reserved_quantity || 0)}</TableCell>
                          <TableCell className="font-mono text-xs">{formatCurrency(Number(s.unit_cost || 0))}</TableCell>
                          <TableCell className="font-mono text-xs">{formatCurrency(Number(s.quantity) * Number(s.unit_cost || 0))}</TableCell>
                        </TableRow>
                      ))}
                    </Table>
                  )}
                </div>
              )}

              {activeTab === 'suppliers' && (
                <div>
                  {supplierPrices.length === 0 ? (
                    <p className="text-center text-sm text-[var(--color-text-secondary)] py-8">Aucun tarif fournisseur enregistré.</p>
                  ) : (
                    <Table headers={['Fournisseur', 'Liste de prix', 'Prix unitaire', 'Devise', 'Qté min', 'Remise %']}>
                      {supplierPrices.map((p) => (
                        <TableRow key={p.id}>
                          <TableCell className="text-sm">{p.suppliers?.name || '—'}</TableCell>
                          <TableCell className="text-sm">{p.price_lists?.name || '—'}</TableCell>
                          <TableCell className="font-mono text-xs">{formatCurrency(Number(p.unit_price || 0))}</TableCell>
                          <TableCell className="text-xs">{p.currency || 'EUR'}</TableCell>
                          <TableCell className="font-mono text-xs">{Number(p.min_quantity || 0)}</TableCell>
                          <TableCell className="font-mono text-xs">{Number(p.discount_percent || 0)}%</TableCell>
                        </TableRow>
                      ))}
                    </Table>
                  )}
                </div>
              )}

              {activeTab === 'documents' && (
                <div>
                  {documents.length === 0 ? (
                    <p className="text-center text-sm text-[var(--color-text-secondary)] py-8">Aucun document lié à cet article.</p>
                  ) : (
                    <Table headers={['Type', 'N°', 'Date', 'Quantité', 'Statut']}>
                      {documents.map((d, i) => (
                        <TableRow key={i}>
                          <TableCell className="text-sm">{d.type}</TableCell>
                          <TableCell className="font-mono text-xs">{d.number || '—'}</TableCell>
                          <TableCell className="text-xs">{d.date ? formatDate(d.date) : '—'}</TableCell>
                          <TableCell className="font-mono text-xs">{Number(d.quantity || 0)}</TableCell>
                          <TableCell><Badge variant="neutral">{d.status || '—'}</Badge></TableCell>
                        </TableRow>
                      ))}
                    </Table>
                  )}
                </div>
              )}

              {activeTab === 'boms' && (
                <div className="space-y-6">
                  <div>
                    <h3 className="text-sm font-semibold mb-2">Produit fini dans les nomenclatures</h3>
                    {bomsData.asFinished.length === 0 ? (
                      <p className="text-xs text-[var(--color-text-secondary)]">Cet article n'est produit fini dans aucune nomenclature.</p>
                    ) : (
                      <Table headers={['Code', 'Nom', 'Type', 'Version']}>
                        {bomsData.asFinished.map((b) => (
                          <TableRow key={b.id}>
                            <TableCell className="font-mono text-xs">{b.code}</TableCell>
                            <TableCell className="text-sm">{b.name}</TableCell>
                            <TableCell><Badge variant={b.bom_type === 'amalgam' ? 'warning' : 'neutral'}>{b.bom_type || 'standard'}</Badge></TableCell>
                            <TableCell className="text-xs">{b.version || 1}</TableCell>
                          </TableRow>
                        ))}
                      </Table>
                    )}
                  </div>
                  <div>
                    <h3 className="text-sm font-semibold mb-2">Composant dans les nomenclatures</h3>
                    {bomsData.asComponent.length === 0 ? (
                      <p className="text-xs text-[var(--color-text-secondary)]">Cet article n'est composant dans aucune nomenclature.</p>
                    ) : (
                      <Table headers={['BOM', 'Quantité', 'Unité', 'Coût']}>
                        {bomsData.asComponent.map((bl) => (
                          <TableRow key={bl.id}>
                            <TableCell className="text-sm">{bl.boms?.code || '—'} — {bl.boms?.name || '—'}</TableCell>
                            <TableCell className="font-mono text-xs">{Number(bl.quantity)}</TableCell>
                            <TableCell className="text-xs">{bl.unit || '—'}</TableCell>
                            <TableCell className="font-mono text-xs">{formatCurrency(Number(bl.cost || 0))}</TableCell>
                          </TableRow>
                        ))}
                      </Table>
                    )}
                  </div>
                </div>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  )
}
