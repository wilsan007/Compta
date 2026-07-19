import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { getFixedAssets, createFixedAsset, updateFixedAsset, deleteFixedAsset, calculateDepreciation, calculateAllDepreciation, getAssetDepreciations, disposeFixedAsset } from '@/lib/queries'
import { formatCurrency, formatDate } from '@/lib/utils'
import { Building, Plus, Trash2, X, Calculator, ChevronDown, ChevronRight, TrendingDown, PackageX } from 'lucide-react'
import type { FixedAsset, AssetDepreciation } from '@/types'
import { useToast } from '@/lib/toast'

const statusLabels: Record<string, string> = { active: 'Actif', disposed: 'Cédé', fully_depreciated: 'Amorti' }

const depTypeLabels: Record<string, string> = {
  depreciation: 'Amortissement',
  disposal: 'Cession',
  dotation: 'Dotation',
}

export function FixedAssetsPage() {
  const { toast } = useToast()
  const [assets, setAssets] = useState<FixedAsset[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [showDisposal, setShowDisposal] = useState<FixedAsset | null>(null)
  const [expanded, setExpanded] = useState<Set<string>>(new Set())
  const [depreciations, setDepreciations] = useState<Record<string, AssetDepreciation[]>>({})

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      setAssets(await getFixedAssets())
    } catch (err) {
      console.error('Failed to load fixed assets:', err)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function toggleExpand(asset: FixedAsset) {
    const next = new Set(expanded)
    if (next.has(asset.id)) {
      next.delete(asset.id)
    } else {
      next.add(asset.id)
      if (!depreciations[asset.id]) {
        try {
          const deps = await getAssetDepreciations(asset.id)
          setDepreciations((prev) => ({ ...prev, [asset.id]: deps }))
        } catch (err) { console.error('Error loading depreciations:', err) }
      }
    }
    setExpanded(next)
  }

  async function handleDelete(id: string) {
  if (!window.confirm('Supprimer cette immobilisation ?')) return
    try {
      await deleteFixedAsset(id)
      await loadData()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    }
  }

  async function handleStatusChange(id: string, status: string) {
    try {
      await updateFixedAsset(id, { status: status as any })
      await loadData()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    }
  }

  async function handleCalculateDepreciation(id: string) {
    try {
      await calculateDepreciation(id)
      const deps = await getAssetDepreciations(id)
      setDepreciations((prev) => ({ ...prev, [id]: deps }))
      await loadData()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    }
  }

  async function handleCalculateAll() {
    try {
      const results = await calculateAllDepreciation()
      toast('success', 'Recalcul terminé', `${results.length} immobilisation(s) recalculée(s)`)
      await loadData()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    }
  }

  const totalValue = assets.reduce((s, a) => s + Number(a.current_value), 0)
  const totalPurchase = assets.reduce((s, a) => s + Number(a.purchase_value), 0)
  const totalDepreciation = totalPurchase - totalValue

  return (
    <div>
      <Breadcrumb items={[{ label: 'Comptabilité' }, { label: 'Structure' }, { label: 'Immobilisations' }]} />
      <PageHeader
        title="Immobilisations"
        subtitle="Gérez vos actifs, amortissements et cessions"
        action={<div className="flex gap-2"><Button variant="secondary" onClick={handleCalculateAll}><Calculator className="w-4 h-4" /> Calculer amortissements</Button><Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouvelle immobilisation</Button></div>}
      />

      <div className="grid grid-cols-3 gap-4 mb-6">
        <Card>
          <div className="p-4">
            <p className="text-sm text-[var(--color-text-secondary)]">Valeur d'achat totale</p>
            <p className="text-2xl font-bold font-mono">{formatCurrency(totalPurchase)}</p>
          </div>
        </Card>
        <Card>
          <div className="p-4">
            <p className="text-sm text-[var(--color-text-secondary)] flex items-center gap-1"><TrendingDown className="w-4 h-4 text-[var(--color-danger)]" /> Amortissement cumulé</p>
            <p className="text-2xl font-bold font-mono text-[var(--color-danger)]">{formatCurrency(totalDepreciation)}</p>
          </div>
        </Card>
        <Card>
          <div className="p-4">
            <p className="text-sm text-[var(--color-text-secondary)]">Valeur nette actuelle</p>
            <p className="text-2xl font-bold font-mono">{formatCurrency(totalValue)}</p>
          </div>
        </Card>
      </div>

      {loading ? (
        <SkeletonTable rows={4} cols={8} />
      ) : assets.length === 0 ? (
        <EmptyState
          icon={<Building className="w-8 h-8" />}
          title="Aucune immobilisation"
          description="Ajoutez votre première immobilisation."
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouvelle immobilisation</Button>}
        />
      ) : (
        <Card>
          <Table headers={['Code', 'Nom', 'Catégorie', 'Date achat', 'Valeur achat', 'Valeur nette', 'Amortissement', 'Statut', 'Actions']}>
            {assets.map((a) => {
              const depreciation = Number(a.purchase_value) - Number(a.current_value)
              const isExpanded = expanded.has(a.id)
              const assetDeps = depreciations[a.id] || []
              return (
                <div key={a.id}>
                  <TableRow>
                    <TableCell className="font-mono text-xs">
                      <div className="flex items-center gap-1">
                        <button onClick={() => toggleExpand(a)} className="p-0.5 rounded hover:bg-[var(--color-neutral-100)]">
                          {isExpanded ? <ChevronDown className="w-3.5 h-3.5" /> : <ChevronRight className="w-3.5 h-3.5" />}
                        </button>
                        {a.code || '—'}
                      </div>
                    </TableCell>
                    <TableCell className="font-medium">{a.name}</TableCell>
                    <TableCell className="text-xs">{a.category || '—'}</TableCell>
                    <TableCell className="text-xs">{formatDate(a.purchase_date)}</TableCell>
                    <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(a.purchase_value))}</TableCell>
                    <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(a.current_value))}</TableCell>
                    <TableCell className="font-mono text-xs text-[var(--color-danger)] text-right">{formatCurrency(depreciation)}</TableCell>
                    <TableCell>
                      <select
                        value={a.status}
                        onChange={(e) => handleStatusChange(a.id, e.target.value)}
                        className="text-xs border border-[var(--color-border)] rounded px-2 py-1 bg-[var(--color-surface)]"
                      >
                        {Object.entries(statusLabels).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                      </select>
                    </TableCell>
                    <TableCell>
                      <div className="flex gap-1">
                        <button onClick={() => handleCalculateDepreciation(a.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)]" title="Calculer amortissement">
                          <Calculator className="w-4 h-4" />
                        </button>
                        {a.status === 'active' && (
                          <button onClick={() => setShowDisposal(a)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-warning)]" title="Céder">
                            <PackageX className="w-4 h-4" />
                          </button>
                        )}
                        <button onClick={() => handleDelete(a.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                          <Trash2 className="w-4 h-4" />
                        </button>
                      </div>
                    </TableCell>
                  </TableRow>
                  {isExpanded && (
                    <div className="px-8 py-3 bg-[var(--color-neutral-50)] border-y border-[var(--color-border)]">
                      <h4 className="text-xs font-semibold mb-2 text-[var(--color-text-secondary)]">Historique des amortissements</h4>
                      {assetDeps.length === 0 ? (
                        <p className="text-xs text-[var(--color-text-secondary)]">Aucun amortissement enregistré. Cliquez sur l'icône calculatrice pour générer.</p>
                      ) : (
                        <Table headers={['Type', 'Période', 'Montant', 'Cumul', 'VNC', 'N° écriture']}>
                          {assetDeps.map((d) => (
                            <TableRow key={d.id}>
                              <TableCell className="text-xs">{depTypeLabels[d.depreciation_type] || d.depreciation_type}</TableCell>
                              <TableCell className="text-xs">P{d.period} {d.fiscal_year_code || ''}</TableCell>
                              <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(d.amount))}</TableCell>
                              <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(d.cumulative_amount))}</TableCell>
                              <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(d.net_book_value))}</TableCell>
                              <TableCell className="font-mono text-xs">{d.entry_number || '—'}</TableCell>
                            </TableRow>
                          ))}
                        </Table>
                      )}
                    </div>
                  )}
                </div>
              )
            })}
          </Table>
        </Card>
      )}

      {showForm && (
        <AssetForm onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />
      )}

      {showDisposal && (
        <DisposalForm asset={showDisposal} onClose={() => setShowDisposal(null)} onSaved={() => { setShowDisposal(null); loadData() }} />
      )}
    </div>
  )
}

function DisposalForm({ asset, onClose, onSaved }: { asset: FixedAsset; onClose: () => void; onSaved: () => void }) {
  const { toast } = useToast()
  const [disposalValue, setDisposalValue] = useState(0)
  const [disposalDate, setDisposalDate] = useState(new Date().toISOString().split('T')[0])
  const [saving, setSaving] = useState(false)

  const gainLoss = Number(disposalValue) - Number(asset.current_value)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await disposeFixedAsset(asset.id, disposalValue, disposalDate)
      onSaved()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">Cession: {asset.name}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div className="p-3 rounded-lg bg-[var(--color-neutral-50)] text-sm space-y-1">
            <div className="flex justify-between"><span className="text-[var(--color-text-secondary)]">Valeur d'achat:</span><span className="font-mono">{formatCurrency(Number(asset.purchase_value))}</span></div>
            <div className="flex justify-between"><span className="text-[var(--color-text-secondary)]">Valeur nette comptable:</span><span className="font-mono">{formatCurrency(Number(asset.current_value))}</span></div>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label="Prix de cession" type="number" step="0.01" required value={disposalValue} onChange={(e) => setDisposalValue(Number(e.target.value))} />
            <Input label="Date de cession" type="date" required value={disposalDate} onChange={(e) => setDisposalDate(e.target.value)} />
          </div>
          <div className={`p-3 rounded-lg text-sm ${gainLoss >= 0 ? 'bg-[var(--color-success)]/10 text-[var(--color-success)]' : 'bg-[var(--color-danger)]/10 text-[var(--color-danger)]'}`}>
            {gainLoss >= 0 ? 'Plus-value' : 'Moins-value'}: <strong className="font-mono">{formatCurrency(Math.abs(gainLoss))}</strong>
          </div>
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>Annuler</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : 'Valider la cession'}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}

function AssetForm({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const { toast } = useToast()
  const [name, setName] = useState('')
  const [code, setCode] = useState('')
  const [category, setCategory] = useState('')
  const [purchaseDate, setPurchaseDate] = useState(new Date().toISOString().split('T')[0])
  const [purchaseValue, setPurchaseValue] = useState(0)
  const [usefulLife, setUsefulLife] = useState(5)
  const [residualValue, setResidualValue] = useState(0)
  const [depMethod, setDepMethod] = useState('straight_line')
  const [saving, setSaving] = useState(false)

  const currentValue = purchaseValue - ((purchaseValue - residualValue) / Math.max(usefulLife, 1)) * Math.min(usefulLife, Math.floor((Date.now() - new Date(purchaseDate).getTime()) / (365.25 * 86400000)))

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await createFixedAsset({
        name, code: code || undefined, category,
        purchase_date: purchaseDate,
        purchase_value: purchaseValue,
        current_value: Math.max(currentValue, residualValue),
        depreciation_method: depMethod,
        useful_life_years: usefulLife,
        residual_value: residualValue,
        status: 'active',
      } as any)
      onSaved()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">Nouvelle immobilisation</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <Input label="Nom" required value={name} onChange={(e) => setName(e.target.value)} />
            <Input label="Code" value={code} onChange={(e) => setCode(e.target.value)} placeholder="IMMO-001" />
          </div>
          <Input label="Catégorie" value={category} onChange={(e) => setCategory(e.target.value)} placeholder="Ex: Matériel informatique" />
          <div className="grid grid-cols-2 gap-4">
            <Input label="Date d'achat" type="date" required value={purchaseDate} onChange={(e) => setPurchaseDate(e.target.value)} />
            <Input label="Valeur d'achat" type="number" step="0.01" required value={purchaseValue} onChange={(e) => setPurchaseValue(Number(e.target.value))} />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label="Durée (années)" type="number" value={usefulLife} onChange={(e) => setUsefulLife(Number(e.target.value))} />
            <Input label="Valeur résiduelle" type="number" step="0.01" value={residualValue} onChange={(e) => setResidualValue(Number(e.target.value))} />
          </div>
          <Select label="Méthode d'amortissement" value={depMethod} onChange={(e) => setDepMethod(e.target.value)} options={[
            { value: 'straight_line', label: 'Linéaire' },
            { value: 'declining_balance', label: 'Dégressif' },
            { value: 'units_of_production', label: 'Unités produites' },
          ]} />
          <div className="p-3 rounded-lg bg-[var(--color-neutral-50)] text-sm">
            <span className="text-[var(--color-text-secondary)]">Valeur actuelle estimée: </span>
            <span className="font-mono font-bold">{formatCurrency(Math.max(currentValue, residualValue))}</span>
          </div>
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>Annuler</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : 'Créer'}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
