import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Plus, Trash2, Workflow as WorkflowIcon, Grid3x3, List, Clock, Check, X } from 'lucide-react'
import { Card, Button, Input, Select, Table, TableRow, TableCell, EmptyState, PageHeader, Breadcrumb, SkeletonTable, Badge } from '@/components/ui'
import { useToast } from '@/lib/toast'
import { useStatusLabels } from '@/lib/statusUtils'
import { getWorkflows, createWorkflow, deleteWorkflow, updateWorkflow, getOFDocumentAccess, createOFDocumentAccess, deleteOFDocumentAccess, updateOFDocumentAccess, getProductEquivalences, createProductEquivalence, deleteProductEquivalence, getProducts } from '@/lib/queries'
import { formatDate } from '@/lib/utils'
import type { Product } from '@/types'

export function WorkflowsPage() {
  const { toast } = useToast()
  const { t } = useTranslation('production')
  const { t: tCommon } = useTranslation('common')
  const { getStatusLabel } = useStatusLabels()
  const [workflows, setWorkflows] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [viewMode, setViewMode] = useState<'list' | 'grid'>('list')

  const loadData = useCallback(async () => {
    try { setWorkflows(await getWorkflows() || []) }
    catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
    if (!window.confirm(tCommon('form.confirmDelete'))) return
    try { await deleteWorkflow(id); await loadData() }
    catch (err: any) { toast('error', tCommon('toast.error'), err.message) }
  }

  async function handleToggle(id: string, currentStatus: string) {
    try { await updateWorkflow(id, { status: currentStatus === 'active' ? 'inactive' : 'active' }); await loadData() }
    catch (err: any) { toast('error', tCommon('toast.error'), err.message) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('workflows.title') }]} />
      <PageHeader title={t('workflows.title')} subtitle={`${workflows.length} ${t('workflows.count')}`}
        action={
          <div className="flex gap-2">
            <div className="flex border border-[var(--color-border)] rounded-lg overflow-hidden">
              <button onClick={() => setViewMode('list')} className={`px-3 py-1.5 text-sm ${viewMode === 'list' ? 'bg-[var(--color-primary)] text-white' : 'hover:bg-[var(--color-neutral-50)]'}`}><List className="w-4 h-4" /></button>
              <button onClick={() => setViewMode('grid')} className={`px-3 py-1.5 text-sm ${viewMode === 'grid' ? 'bg-[var(--color-primary)] text-white' : 'hover:bg-[var(--color-neutral-50)]'}`}><Grid3x3 className="w-4 h-4" /></button>
            </div>
            <Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('workflows.new')}</Button>
          </div>
        } />

      {loading ? <SkeletonTable rows={3} cols={4} /> : workflows.length === 0 ? (
        <EmptyState icon={<WorkflowIcon className="w-8 h-8" />} title={t('workflows.none')} description={t('workflows.noneDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('workflows.new')}</Button>} />
      ) : viewMode === 'list' ? (
        <Card>
          <Table headers={[tCommon('common.name'), t('workflows.type'), t('workflows.schedule'), t('workflows.lastRun'), tCommon('common.status'), tCommon('table.actions')]}>
            {workflows.map((wf) => (
              <TableRow key={wf.id}>
                <TableCell className="text-sm font-medium">{wf.name}</TableCell>
                <TableCell><Badge variant="neutral">{t(`workflows.typeLabels.${wf.workflow_type}`, { defaultValue: wf.workflow_type })}</Badge></TableCell>
                <TableCell className="text-xs">{wf.schedule || '—'}</TableCell>
                <TableCell className="text-xs">{wf.last_run ? formatDate(wf.last_run) : t('workflows.never')}</TableCell>
                <TableCell>
                  <button onClick={() => handleToggle(wf.id, wf.status)}>
                    <Badge variant={wf.status === 'active' ? 'success' : 'neutral'}>{getStatusLabel(wf.status)}</Badge>
                  </button>
                </TableCell>
                <TableCell>
                  <button onClick={() => handleDelete(wf.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {workflows.map((wf) => (
            <Card key={wf.id}>
              <div className="p-4">
                <div className="flex items-center justify-between mb-2">
                  <WorkflowIcon className="w-5 h-5 text-[var(--color-primary)]" />
                  <button onClick={() => handleToggle(wf.id, wf.status)}><Badge variant={wf.status === 'active' ? 'success' : 'neutral'}>{getStatusLabel(wf.status)}</Badge></button>
                </div>
                <h3 className="text-sm font-semibold">{wf.name}</h3>
                <p className="text-xs text-[var(--color-text-secondary)] mt-1">{wf.description || '—'}</p>
                <div className="mt-3 space-y-1 text-xs">
                  <p><span className="text-[var(--color-text-secondary)]">{t('workflows.type')}:</span> {t(`workflows.typeLabels.${wf.workflow_type}`, { defaultValue: wf.workflow_type })}</p>
                  <p><span className="text-[var(--color-text-secondary)]">{t('workflows.schedule')}:</span> {wf.schedule || '—'}</p>
                  <p className="flex items-center gap-1"><Clock className="w-3 h-3" /> {wf.last_run ? formatDate(wf.last_run) : t('workflows.neverRun')}</p>
                </div>
                <button onClick={() => handleDelete(wf.id)} className="mt-3 text-xs text-[var(--color-danger)] hover:underline">{tCommon('actions.delete')}</button>
              </div>
            </Card>
          ))}
        </div>
      )}

      {showForm && <WorkflowFormModal onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function WorkflowFormModal({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const { toast } = useToast()
  const { t } = useTranslation('production')
  const { t: tCommon } = useTranslation('common')
  const [name, setName] = useState('')
  const [description, setDescription] = useState('')
  const [workflowType, setWorkflowType] = useState('mrp')
  const [schedule, setSchedule] = useState('')

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!name) { toast('error', tCommon('toast.error'), t('workflows.nameRequired')); return }
    try {
      await createWorkflow({ name, description: description || null, workflow_type: workflowType as any, schedule: schedule || null, last_run: null, status: 'active' })
      onSaved()
    } catch (err: any) { toast('error', tCommon('toast.error'), err.message) }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40" onClick={onClose}>
      <div className="bg-[var(--color-surface)] rounded-xl shadow-xl p-6 w-full max-w-md" onClick={(e) => e.stopPropagation()}>
        <h2 className="text-lg font-semibold mb-4">{t('workflows.new')}</h2>
        <form onSubmit={handleSubmit} className="space-y-3">
          <Input label={tCommon('common.name')} value={name} onChange={(e) => setName(e.target.value)} required />
          <Input label={tCommon('common.description')} value={description} onChange={(e) => setDescription(e.target.value)} />
          <Select label={t('workflows.type')} value={workflowType} onChange={(e) => setWorkflowType(e.target.value)} options={[
            { value: 'mrp', label: t('workflows.typeLabels.mrp') }, { value: 'forecast', label: t('workflows.typeLabels.forecast') }, { value: 'planning', label: t('workflows.typeLabels.planning') }, { value: 'custom', label: t('workflows.typeLabels.custom') },
          ]} />
          <Input label={t('workflows.scheduleLabel')} value={schedule} onChange={(e) => setSchedule(e.target.value)} placeholder={t('workflows.schedulePlaceholder')} />
          <div className="flex gap-2 justify-end pt-2">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit">{tCommon('actions.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}

// ============ Equivalences Tab (embedded in ProductsPage or standalone) ============

export function EquivalencesPage() {
  const { toast } = useToast()
  const { t } = useTranslation('production')
  const { t: tCommon } = useTranslation('common')
  const [equivalences, setEquivalences] = useState<any[]>([])
  const [products, setProducts] = useState<Product[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)

  const loadData = useCallback(async () => {
    try {
      const [eqs, prods] = await Promise.all([getProductEquivalences(), getProducts()])
      setEquivalences(eqs || [])
      setProducts(prods || [])
    } catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
    try { await deleteProductEquivalence(id); await loadData() }
    catch (err: any) { toast('error', tCommon('toast.error'), err.message) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('equivalences.title') }]} />
      <PageHeader title={t('equivalences.title')} subtitle={`${equivalences.length} ${t('equivalences.count')}`}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('equivalences.new')}</Button>} />

      {loading ? <SkeletonTable rows={3} cols={4} /> : equivalences.length === 0 ? (
        <EmptyState icon={<WorkflowIcon className="w-8 h-8" />} title={t('equivalences.none')} description={t('equivalences.noneDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('equivalences.new')}</Button>} />
      ) : (
        <Card>
          <Table headers={[t('equivalences.product'), t('equivalences.equivalentProduct'), t('equivalences.ratio'), tCommon('table.actions')]}>
            {equivalences.map((eq) => (
              <TableRow key={eq.id}>
                <TableCell className="text-sm">{eq.products?.[0]?.name || '—'}</TableCell>
                <TableCell className="text-sm">{eq.products?.[1]?.name || '—'}</TableCell>
                <TableCell className="font-mono text-xs">{Number(eq.conversion_ratio)}</TableCell>
                <TableCell><button onClick={() => handleDelete(eq.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button></TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && <EquivalenceFormModal products={products} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function EquivalenceFormModal({ products, onClose, onSaved }: { products: Product[]; onClose: () => void; onSaved: () => void }) {
  const { toast } = useToast()
  const { t } = useTranslation('production')
  const { t: tCommon } = useTranslation('common')
  const [productId, setProductId] = useState('')
  const [equivalentId, setEquivalentId] = useState('')
  const [ratio, setRatio] = useState(1)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!productId || !equivalentId) { toast('error', tCommon('toast.error'), t('equivalences.selectTwoProducts')); return }
    if (productId === equivalentId) { toast('error', tCommon('toast.error'), t('equivalences.cannotBeSame')); return }
    try { await createProductEquivalence({ product_id: productId, equivalent_product_id: equivalentId, conversion_ratio: ratio }); onSaved() }
    catch (err: any) { toast('error', tCommon('toast.error'), err.message) }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40" onClick={onClose}>
      <div className="bg-[var(--color-surface)] rounded-xl shadow-xl p-6 w-full max-w-md" onClick={(e) => e.stopPropagation()}>
        <h2 className="text-lg font-semibold mb-4">{t('equivalences.new')}</h2>
        <form onSubmit={handleSubmit} className="space-y-3">
          <Select label={t('equivalences.product')} value={productId} onChange={(e) => setProductId(e.target.value)} options={[{ value: '', label: '—' }, ...products.map((p) => ({ value: p.id, label: p.name }))]} />
          <Select label={t('equivalences.equivalentProduct')} value={equivalentId} onChange={(e) => setEquivalentId(e.target.value)} options={[{ value: '', label: '—' }, ...products.map((p) => ({ value: p.id, label: p.name }))]} />
          <Input label={t('equivalences.conversionRatio')} type="number" step="0.0001" value={ratio} onChange={(e) => setRatio(Number(e.target.value))} />
          <div className="flex gap-2 justify-end pt-2">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit">{tCommon('actions.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}

// ============ OF Document Access Page ============

export function OFDocumentAccessPage() {
  const { toast } = useToast()
  const { t } = useTranslation('production')
  const { t: tCommon } = useTranslation('common')
  const [accessList, setAccessList] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)

  const loadData = useCallback(async () => {
    try { setAccessList(await getOFDocumentAccess() || []) }
    catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
    try { await deleteOFDocumentAccess(id); await loadData() }
    catch (err: any) { toast('error', tCommon('toast.error'), err.message) }
  }

  async function handleToggle(id: string, field: 'can_view' | 'can_print' | 'can_export', current: boolean) {
    try { await updateOFDocumentAccess(id, { [field]: !current } as any); await loadData() }
    catch (err: any) { toast('error', tCommon('toast.error'), err.message) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('ofDocAccess.title') }]} />
      <PageHeader title={t('ofDocAccess.title')} subtitle={`${accessList.length} ${t('ofDocAccess.rulesCount')}`}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('ofDocAccess.newRule')}</Button>} />

      {loading ? <SkeletonTable rows={3} cols={5} /> : accessList.length === 0 ? (
        <EmptyState icon={<Check className="w-8 h-8" />} title={t('ofDocAccess.noRestrictions')} description={t('ofDocAccess.noRestrictionsDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('ofDocAccess.newRule')}</Button>} />
      ) : (
        <Card>
          <Table headers={[t('ofDocAccess.user'), t('ofDocAccess.documentType'), t('ofDocAccess.view'), t('ofDocAccess.print'), t('ofDocAccess.export'), tCommon('table.actions')]}>
            {accessList.map((acc) => (
              <TableRow key={acc.id}>
                <TableCell className="text-sm">{acc.users?.full_name || acc.users?.email || '—'}</TableCell>
                <TableCell className="text-sm">{acc.document_type}</TableCell>
                <TableCell><button onClick={() => handleToggle(acc.id, 'can_view', acc.can_view)}>{acc.can_view ? <Check className="w-4 h-4 text-[var(--color-success)]" /> : <X className="w-4 h-4 text-[var(--color-danger)]" />}</button></TableCell>
                <TableCell><button onClick={() => handleToggle(acc.id, 'can_print', acc.can_print)}>{acc.can_print ? <Check className="w-4 h-4 text-[var(--color-success)]" /> : <X className="w-4 h-4 text-[var(--color-danger)]" />}</button></TableCell>
                <TableCell><button onClick={() => handleToggle(acc.id, 'can_export', acc.can_export)}>{acc.can_export ? <Check className="w-4 h-4 text-[var(--color-success)]" /> : <X className="w-4 h-4 text-[var(--color-danger)]" />}</button></TableCell>
                <TableCell><button onClick={() => handleDelete(acc.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button></TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && <OFDocAccessFormModal onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function OFDocAccessFormModal({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const { toast } = useToast()
  const { t } = useTranslation('production')
  const { t: tCommon } = useTranslation('common')
  const [userId, setUserId] = useState('')
  const [documentType, setDocumentType] = useState('of_label')
  const [canView, setCanView] = useState(true)
  const [canPrint, setCanPrint] = useState(false)
  const [canExport, setCanExport] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!userId) { toast('error', tCommon('toast.error'), t('ofDocAccess.userRequired')); return }
    try { await createOFDocumentAccess({ user_id: userId, document_type: documentType, can_view: canView, can_print: canPrint, can_export: canExport }); onSaved() }
    catch (err: any) { toast('error', tCommon('toast.error'), err.message) }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40" onClick={onClose}>
      <div className="bg-[var(--color-surface)] rounded-xl shadow-xl p-6 w-full max-w-md" onClick={(e) => e.stopPropagation()}>
        <h2 className="text-lg font-semibold mb-4">{t('ofDocAccess.newRule')}</h2>
        <form onSubmit={handleSubmit} className="space-y-3">
          <Input label={t('ofDocAccess.userId')} value={userId} onChange={(e) => setUserId(e.target.value)} placeholder="UUID" required />
          <Select label={t('ofDocAccess.documentType')} value={documentType} onChange={(e) => setDocumentType(e.target.value)} options={[
            { value: 'of_label', label: t('ofDocAccess.docTypes.of_label') }, { value: 'of_lot', label: t('ofDocAccess.docTypes.of_lot') }, { value: 'of_consumption', label: t('ofDocAccess.docTypes.of_consumption') }, { value: 'of_dossier', label: t('ofDocAccess.docTypes.of_dossier') },
          ]} />
          <div className="space-y-2">
            <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={canView} onChange={(e) => setCanView(e.target.checked)} className="rounded" /> {t('ofDocAccess.view')}</label>
            <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={canPrint} onChange={(e) => setCanPrint(e.target.checked)} className="rounded" /> {t('ofDocAccess.print')}</label>
            <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={canExport} onChange={(e) => setCanExport(e.target.checked)} className="rounded" /> {t('ofDocAccess.export')}</label>
          </div>
          <div className="flex gap-2 justify-end pt-2">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit">{tCommon('actions.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
