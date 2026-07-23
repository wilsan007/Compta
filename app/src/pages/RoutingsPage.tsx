import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Plus, Trash2, ChevronDown, ChevronRight, Route, ArrowUpDown, Download, Upload } from 'lucide-react'
import { Card, Button, Input, Select, Table, TableRow, TableCell, EmptyState, PageHeader, Breadcrumb, SkeletonTable, Badge } from '@/components/ui'
import { useToast } from '@/lib/toast'
import {
  getRoutings, createRouting, deleteRouting,
  getRoutingOperations, createRoutingOperation, deleteRoutingOperation, renumberAllOperations,
  getProducts, getWorkCenters, getMachines, getToolings, getSuppliers,
} from '@/lib/queries'
import { exportToExcel, importFromExcel } from '@/lib/excel-utils'
import type { Product, WorkCenter, Machine, Tooling, Supplier } from '@/types'

export function RoutingsPage() {
  const { t } = useTranslation('production')
  const { toast } = useToast()
  const [routings, setRoutings] = useState<any[]>([])
  const [products, setProducts] = useState<Product[]>([])
  const [workCenters, setWorkCenters] = useState<WorkCenter[]>([])
  const [machines, setMachines] = useState<Machine[]>([])
  const [toolings, setToolings] = useState<Tooling[]>([])
  const [suppliers, setSuppliers] = useState<Supplier[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [expanded, setExpanded] = useState<Set<string>>(new Set())
  const [operations, setOperations] = useState<Record<string, any[]>>({})
  const [showOpForm, setShowOpForm] = useState<string | null>(null)

  const routingHeaders = [t('common.code'), t('routings.name'), t('routings.product'), t('routings.version'), t('routings.active'), t('common.actions')]
  const operationHeaders = [t('routings.seq'), t('routings.name'), t('routings.center'), t('routings.machine'), t('routings.tooling'), t('routings.prepMin'), t('routings.execMin'), t('routings.st'), t('common.actions')]

  const loadData = useCallback(async () => {
    try {
      const [rts, prods, wcs, macs, tls, sups] = await Promise.all([
        getRoutings(), getProducts(), getWorkCenters(), getMachines(), getToolings(), getSuppliers(),
      ])
      setRoutings(rts || [])
      setProducts(prods || [])
      setWorkCenters(wcs || [])
      setMachines(macs || [])
      setToolings(tls || [])
      setSuppliers(sups || [])
    } catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function toggleExpand(id: string) {
    const next = new Set(expanded)
    if (next.has(id)) { next.delete(id) }
    else {
      next.add(id)
      if (!operations[id]) {
        try {
          const ops = await getRoutingOperations(id)
          setOperations((prev) => ({ ...prev, [id]: ops }))
        } catch (err) { console.error('Error:', err) }
      }
    }
    setExpanded(next)
  }

  async function handleDelete(id: string) {
    if (!window.confirm(t('routings.confirmDelete'))) return
    try { await deleteRouting(id); await loadData() }
    catch (err: any) { toast('error', t('common.error'), err.message || 'échec') }
  }

  async function handleDeleteOp(opId: string, routingId: string) {
    try {
      await deleteRoutingOperation(opId)
      const ops = await getRoutingOperations(routingId)
      setOperations((prev) => ({ ...prev, [routingId]: ops }))
    } catch (err: any) { toast('error', t('common.error'), err.message || 'échec') }
  }

  async function handleRenumber(routingId: string) {
    try {
      await renumberAllOperations(routingId)
      const ops = await getRoutingOperations(routingId)
      setOperations((prev) => ({ ...prev, [routingId]: ops }))
      toast('success', t('routings.renumberSuccess'), t('routings.renumberSuccessMessage'))
    } catch (err: any) { toast('error', t('common.error'), err.message || 'échec') }
  }

  function handleExport() {
    const rows: any[] = []
    for (const r of routings) {
      const ops = operations[r.id] || []
      if (ops.length === 0) {
        rows.push({ code: r.code, name: r.name, produit: r.products?.name || '', sequence: '', operation: '', centre: '', machine: '', outillage: '', temps_prep: '', temps_exec: '', sous_traite: '' })
      } else {
        for (const op of ops) {
          rows.push({
            code: r.code, name: r.name, produit: r.products?.name || '',
            sequence: op.sequence, operation: op.name,
            centre: op.work_centers?.name || '', machine: op.machines?.name || '',
            outillage: op.toolings?.name || '', temps_prep: op.setup_time_min, temps_exec: op.run_time_min,
            sous_traite: op.is_subcontracted ? 'Oui' : 'Non',
          })
        }
      }
    }
    exportToExcel(rows, 'gammes_operatoires.xlsx', 'Gammes')
  }

  async function handleImport(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    try {
      const rows = await importFromExcel(file)
      toast('success', t('routings.import'), t('routings.importSuccess', { count: rows.length }))
    } catch (err: any) { toast('error', t('routings.importError'), err.message) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('routings.title') }]} />
      <PageHeader title={t('routings.title')} subtitle={`${routings.length} gamme(s)`}
        action={
          <div className="flex gap-2">
            <Button variant="secondary" onClick={handleExport}><Download className="w-4 h-4" /> {t('routings.export')}</Button>
            <label className="inline-flex items-center gap-2 px-3 py-2 text-sm rounded-lg border border-[var(--color-border)] bg-[var(--color-surface)] cursor-pointer hover:bg-[var(--color-neutral-50)]">
              <Upload className="w-4 h-4" /> {t('routings.import')}
              <input type="file" accept=".xlsx,.xls" className="hidden" onChange={handleImport} />
            </label>
            <Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('routings.new')}</Button>
          </div>
        } />

      {loading ? <SkeletonTable rows={4} cols={5} /> : routings.length === 0 ? (
        <EmptyState icon={<Route className="w-8 h-8" />} title={t('routings.noRoutings')} description={t('routings.noRoutingsDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('routings.new')}</Button>} />
      ) : (
        <Card>
          <Table headers={routingHeaders}>
            {routings.map((r: any) => (
              <div key={r.id}>
                <TableRow>
                  <TableCell className="font-mono text-xs">
                    <div className="flex items-center gap-1">
                      <button onClick={() => toggleExpand(r.id)} className="p-0.5 rounded hover:bg-[var(--color-neutral-100)]">
                        {expanded.has(r.id) ? <ChevronDown className="w-3.5 h-3.5" /> : <ChevronRight className="w-3.5 h-3.5" />}
                      </button>
                      {r.code}
                    </div>
                  </TableCell>
                  <TableCell className="font-medium">{r.name}</TableCell>
                  <TableCell className="text-sm">{r.products?.name || '—'}</TableCell>
                  <TableCell className="font-mono text-xs">v{r.version}</TableCell>
                  <TableCell><Badge variant={r.active ? 'success' : 'neutral'}>{r.active ? t('routings.active') : t('routings.inactive')}</Badge></TableCell>
                  <TableCell>
                    <div className="flex gap-1">
                      <button onClick={() => setShowOpForm(r.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)]" title={t('routings.addOperation')}><Plus className="w-4 h-4" /></button>
                      <button onClick={() => handleDelete(r.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
                    </div>
                  </TableCell>
                </TableRow>
                {expanded.has(r.id) && (
                  <div className="px-8 py-3 bg-[var(--color-neutral-50)] border-y border-[var(--color-border)]">
                    <div className="flex justify-between items-center mb-2">
                      <span className="text-xs font-semibold text-[var(--color-text-secondary)]">{t('routings.operations')}</span>
                      <button onClick={() => handleRenumber(r.id)} className="text-xs inline-flex items-center gap-1 px-2 py-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)]">
                        <ArrowUpDown className="w-3 h-3" /> {t('routings.renumber')}
                      </button>
                    </div>
                    {(operations[r.id] || []).length === 0 ? (
                      <p className="text-xs text-[var(--color-text-secondary)]">{t('routings.noOperations')}</p>
                    ) : (
                      <Table headers={operationHeaders}>
                        {(operations[r.id] || []).map((op) => (
                          <TableRow key={op.id}>
                            <TableCell className="font-mono text-xs">{op.sequence}</TableCell>
                            <TableCell className="text-sm">{op.name}</TableCell>
                            <TableCell className="text-xs">{op.work_centers?.name || '—'}</TableCell>
                            <TableCell className="text-xs">{op.machines?.name || '—'}</TableCell>
                            <TableCell className="text-xs">{op.toolings?.name || '—'}</TableCell>
                            <TableCell className="font-mono text-xs">{op.setup_time_min}</TableCell>
                            <TableCell className="font-mono text-xs">{op.run_time_min}</TableCell>
                            <TableCell>{op.is_subcontracted ? <Badge variant="warning">{t('routings.st')}</Badge> : '—'}</TableCell>
                            <TableCell>
                              <button onClick={() => handleDeleteOp(op.id, r.id)} className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-3.5 h-3.5" /></button>
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

      {showForm && <RoutingFormModal products={products} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
      {showOpForm && <RoutingOperationFormModal routingId={showOpForm} workCenters={workCenters} machines={machines} toolings={toolings} suppliers={suppliers} onClose={() => setShowOpForm(null)} onSaved={async () => { const id = showOpForm; setShowOpForm(null); const ops = await getRoutingOperations(id); setOperations((prev) => ({ ...prev, [id]: ops })) }} />}
    </div>
  )
}

function RoutingFormModal({ products, onClose, onSaved }: { products: Product[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('production')
  const { toast } = useToast()
  const [code, setCode] = useState('')
  const [name, setName] = useState('')
  const [productId, setProductId] = useState('')
  const [description, setDescription] = useState('')

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!code || !name) { toast('error', t('common.required'), t('routings.name') + ' & Code'); return }
    try {
      await createRouting({ code, name, description, product_id: productId || null, version: 1, active: true })
      onSaved()
    } catch (err: any) { toast('error', t('common.error'), err.message || 'échec') }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40" onClick={onClose}>
      <div className="bg-[var(--color-surface)] rounded-xl shadow-xl p-6 w-full max-w-md" onClick={(e) => e.stopPropagation()}>
        <h2 className="text-lg font-semibold mb-4">{t('routings.create')}</h2>
        <form onSubmit={handleSubmit} className="space-y-3">
          <Input label={t('common.code')} value={code} onChange={(e) => setCode(e.target.value)} placeholder="GAM-001" required />
          <Input label={t('routings.name')} value={name} onChange={(e) => setName(e.target.value)} placeholder="Gamme de montage" required />
          <Select label={t('routings.product')} value={productId} onChange={(e) => setProductId(e.target.value)} options={[{ value: '', label: '—' }, ...products.map((p) => ({ value: p.id, label: p.name }))]} />
          <Input label={t('common.description')} value={description} onChange={(e) => setDescription(e.target.value)} />
          <div className="flex gap-2 justify-end pt-2">
            <Button type="button" variant="secondary" onClick={onClose}>{t('common.cancel')}</Button>
            <Button type="submit">{t('routings.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}

function RoutingOperationFormModal({ routingId, workCenters, machines, toolings, suppliers, onClose, onSaved }: {
  routingId: string; workCenters: WorkCenter[]; machines: Machine[]; toolings: Tooling[]; suppliers: Supplier[]
  onClose: () => void; onSaved: () => void
}) {
  const { t } = useTranslation('production')
  const { toast } = useToast()
  const [name, setName] = useState('')
  const [sequence, setSequence] = useState(10)
  const [workCenterId, setWorkCenterId] = useState('')
  const [machineId, setMachineId] = useState('')
  const [toolingId, setToolingId] = useState('')
  const [setupTime, setSetupTime] = useState(0)
  const [runTime, setRunTime] = useState(0)
  const [isSubcontracted, setIsSubcontracted] = useState(false)
  const [supplierId, setSupplierId] = useState('')
  const [stUnit, setStUnit] = useState('')
  const [stQuantity, setStQuantity] = useState(1)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!name) { toast('error', t('common.required'), t('routings.operationName')); return }
    try {
      await createRoutingOperation({
        routing_id: routingId, sequence, name, description: null,
        work_center_id: workCenterId || null, machine_id: machineId || null, tooling_id: toolingId || null,
        setup_time_min: setupTime, run_time_min: runTime,
        is_subcontracted: isSubcontracted, supplier_id: supplierId || null,
        st_unit: stUnit || null, st_quantity: stQuantity,
      })
      onSaved()
    } catch (err: any) { toast('error', t('common.error'), err.message || 'échec') }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40" onClick={onClose}>
      <div className="bg-[var(--color-surface)] rounded-xl shadow-xl p-6 w-full max-w-lg max-h-[90vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
        <h2 className="text-lg font-semibold mb-4">{t('routings.addOperation')}</h2>
        <form onSubmit={handleSubmit} className="space-y-3">
          <Input label={t('routings.operationName')} value={name} onChange={(e) => setName(e.target.value)} placeholder="Découpe" required />
          <Input label={t('routings.sequence')} type="number" value={sequence} onChange={(e) => setSequence(Number(e.target.value))} />
          <Select label={t('routings.center')} value={workCenterId} onChange={(e) => setWorkCenterId(e.target.value)} options={[{ value: '', label: '—' }, ...workCenters.map((wc) => ({ value: wc.id, label: wc.name }))]} />
          <Select label={t('routings.machine')} value={machineId} onChange={(e) => setMachineId(e.target.value)} options={[{ value: '', label: '—' }, ...machines.map((m) => ({ value: m.id, label: m.name }))]} />
          <Select label={t('routings.tooling')} value={toolingId} onChange={(e) => setToolingId(e.target.value)} options={[{ value: '', label: '—' }, ...toolings.map((tl) => ({ value: tl.id, label: tl.name }))]} />
          <div className="grid grid-cols-2 gap-3">
            <Input label={t('routings.prepMin')} type="number" value={setupTime} onChange={(e) => setSetupTime(Number(e.target.value))} />
            <Input label={t('routings.execMin')} type="number" value={runTime} onChange={(e) => setRunTime(Number(e.target.value))} />
          </div>
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={isSubcontracted} onChange={(e) => setIsSubcontracted(e.target.checked)} className="rounded" />
            {t('routings.subcontracted')}
          </label>
          {isSubcontracted && (
            <div className="space-y-3 border-l-2 border-[var(--color-primary)] pl-3">
              <Select label={t('subcontracting.orders.supplier')} value={supplierId} onChange={(e) => setSupplierId(e.target.value)} options={[{ value: '', label: '—' }, ...suppliers.map((s) => ({ value: s.id, label: s.name }))]} />
              <div className="grid grid-cols-2 gap-3">
                <Input label={t('routings.st') + ' Unit'} value={stUnit} onChange={(e) => setStUnit(e.target.value)} placeholder="Kg" />
                <Input label={t('routings.st') + ' Qty'} type="number" step="0.01" value={stQuantity} onChange={(e) => setStQuantity(Number(e.target.value))} />
              </div>
            </div>
          )}
          <div className="flex gap-2 justify-end pt-2">
            <Button type="button" variant="secondary" onClick={onClose}>{t('common.cancel')}</Button>
            <Button type="submit">{t('routings.addOperation')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
