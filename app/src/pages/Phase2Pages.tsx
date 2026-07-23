import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input } from '@/components/ui'
import { useToast } from '@/lib/toast'
import { Plus, Trash2 } from 'lucide-react'
import {
  getProspects, createProspect, deleteProspect, convertProspectToCustomer,
  getSalesRepresentatives, createSalesRepresentative, deleteSalesRepresentative,
  getWarehouseLocations, createWarehouseLocation, deleteWarehouseLocation,
  getQualityChecks, createQualityCheck, updateQualityCheck,
  getPickLists, createPickList, updatePickList,
  getProductSerialNumbers, createProductSerialNumber, deleteProductSerialNumber,
  getProductBatches, createProductBatch, deleteProductBatch,
  getProductSubstitutes, createProductSubstitute, deleteProductSubstitute,
  getDeliverySchedules, createDeliverySchedule, deleteDeliverySchedule,
  getDocumentTemplates, createDocumentTemplate, deleteDocumentTemplate,
} from '@/lib/queries'

// ============ Prospects Page ============
export function ProspectsPage() {
  const { t } = useTranslation('sales')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ name: '', email: '', phone: '', address: '', city: '', country: '', contact_name: '', source: '', status: 'new' as const, notes: '', postal_code: '', assigned_rep_id: null as string | null, converted_customer_id: null as string | null })

  const loadData = useCallback(async () => {
    setLoading(true)
    try { setItems(await getProspects() || []) } catch { } finally { setLoading(false) }
  }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() {
    try { await createProspect(form as any); toast('success', tCommon('common.success'), t('prospects.created')); setShowForm(false); setForm({ name: '', email: '', phone: '', address: '', city: '', country: '', contact_name: '', source: '', status: 'new', notes: '', postal_code: '', assigned_rep_id: null, converted_customer_id: null }); await loadData() }
    catch (e: any) { toast('error', tCommon('common.error'), e.message) }
  }
  async function handleDelete(id: string) { if (!window.confirm(tCommon('form.confirmDelete'))) return; try { await deleteProspect(id); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }
  async function handleConvert(id: string) { if (!window.confirm(t('prospects.convertConfirm'))) return; try { await convertProspectToCustomer(id, { name: form.name } as any); toast('success', tCommon('common.success'), t('prospects.converted')); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }

  return (
    <div>
      <Breadcrumb items={[{ label: t('prospects.breadcrumb1'), path: '/sales' }, { label: t('prospects.title') }]} />
      <PageHeader title={t('prospects.title')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('prospects.new')}</Button>} />
      {showForm && (
        <Card className="p-4 mb-4 space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <Input placeholder={t('prospects.name')} value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} />
            <Input placeholder={t('prospects.email')} value={form.email} onChange={e => setForm({ ...form, email: e.target.value })} />
            <Input placeholder={t('prospects.phone')} value={form.phone} onChange={e => setForm({ ...form, phone: e.target.value })} />
            <Input placeholder={t('prospects.contactName')} value={form.contact_name} onChange={e => setForm({ ...form, contact_name: e.target.value })} />
            <Input placeholder={t('prospects.source')} value={form.source} onChange={e => setForm({ ...form, source: e.target.value })} />
          </div>
          <div className="flex gap-2">
            <Button onClick={handleCreate}>{tCommon('actions.save')}</Button>
            <Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button>
          </div>
        </Card>
      )}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('prospects.empty')} /> : (
        <Table headers={[t('prospects.name'), t('prospects.email'), t('prospects.phone'), t('prospects.status'), tCommon('common.actions')]}>
          {items.map(p => (
            <TableRow key={p.id}>
              <TableCell>{p.name}</TableCell>
              <TableCell>{p.email || '-'}</TableCell>
              <TableCell>{p.phone || '-'}</TableCell>
              <TableCell><Badge>{t(`prospects.statuses.${p.status}`)}</Badge></TableCell>
              <TableCell>
                <div className="flex gap-1">
                  {p.status !== 'converted' && <Button size="sm" variant="secondary" onClick={() => handleConvert(p.id)}>{t('prospects.convert')}</Button>}
                  <Button size="sm" variant="danger" onClick={() => handleDelete(p.id)}><Trash2 className="w-4 h-4" /></Button>
                </div>
              </TableCell>
            </TableRow>
          ))}
        </Table>
      )}
    </div>
  )
}

// ============ Sales Representatives Page ============
export function RepresentativesPage() {
  const { t } = useTranslation('sales')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ name: '', email: '', phone: '', commission_rate: 0, territory: '', active: true, tenant_id: null as string | null })

  const loadData = useCallback(async () => { setLoading(true); try { setItems(await getSalesRepresentatives() || []) } catch { } finally { setLoading(false) } }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() { try { await createSalesRepresentative(form); toast('success', tCommon('common.success'), t('reps.created')); setShowForm(false); setForm({ name: '', email: '', phone: '', commission_rate: 0, territory: '', active: true, tenant_id: null }); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }
  async function handleDelete(id: string) { if (!window.confirm(tCommon('form.confirmDelete'))) return; try { await deleteSalesRepresentative(id); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }

  return (
    <div>
      <Breadcrumb items={[{ label: t('reps.breadcrumb1'), path: '/sales' }, { label: t('reps.title') }]} />
      <PageHeader title={t('reps.title')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('reps.new')}</Button>} />
      {showForm && (
        <Card className="p-4 mb-4 space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <Input placeholder={t('reps.name')} value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} />
            <Input placeholder={t('reps.email')} value={form.email} onChange={e => setForm({ ...form, email: e.target.value })} />
            <Input placeholder={t('reps.phone')} value={form.phone} onChange={e => setForm({ ...form, phone: e.target.value })} />
            <Input type="number" placeholder={t('reps.commission')} value={form.commission_rate} onChange={e => setForm({ ...form, commission_rate: parseFloat(e.target.value) || 0 })} />
            <Input placeholder={t('reps.territory')} value={form.territory} onChange={e => setForm({ ...form, territory: e.target.value })} />
          </div>
          <div className="flex gap-2"><Button onClick={handleCreate}>{tCommon('actions.save')}</Button><Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button></div>
        </Card>
      )}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('reps.empty')} /> : (
        <Table headers={[t('reps.name'), t('reps.email'), t('reps.phone'), t('reps.commission'), t('reps.territory'), tCommon('common.actions')]}>
          {items.map(r => (<TableRow key={r.id}><TableCell>{r.name}</TableCell><TableCell>{r.email || '-'}</TableCell><TableCell>{r.phone || '-'}</TableCell><TableCell>{r.commission_rate}%</TableCell><TableCell>{r.territory || '-'}</TableCell><TableCell><Button size="sm" variant="danger" onClick={() => handleDelete(r.id)}><Trash2 className="w-4 h-4" /></Button></TableCell></TableRow>))}
        </Table>
      )}
    </div>
  )
}

// ============ Warehouse Locations Page ============
export function WarehouseLocationsPage() {
  const { t } = useTranslation('stock')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ warehouse_id: '', zone: '', aisle: '', shelf: '', code: '', description: '' })

  const loadData = useCallback(async () => { setLoading(true); try { setItems(await getWarehouseLocations() || []) } catch { } finally { setLoading(false) } }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() { try { await createWarehouseLocation(form as any); toast('success', tCommon('common.success'), t('locations.created')); setShowForm(false); setForm({ warehouse_id: '', zone: '', aisle: '', shelf: '', code: '', description: '' }); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }
  async function handleDelete(id: string) { if (!window.confirm(tCommon('form.confirmDelete'))) return; try { await deleteWarehouseLocation(id); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }

  return (
    <div>
      <Breadcrumb items={[{ label: t('locations.breadcrumb1'), path: '/stock' }, { label: t('locations.title') }]} />
      <PageHeader title={t('locations.title')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('locations.new')}</Button>} />
      {showForm && (<Card className="p-4 mb-4 space-y-3"><div className="grid grid-cols-3 gap-3"><Input placeholder={t('locations.code')} value={form.code} onChange={e => setForm({ ...form, code: e.target.value })} /><Input placeholder={t('locations.zone')} value={form.zone} onChange={e => setForm({ ...form, zone: e.target.value })} /><Input placeholder={t('locations.aisle')} value={form.aisle} onChange={e => setForm({ ...form, aisle: e.target.value })} /><Input placeholder={t('locations.shelf')} value={form.shelf} onChange={e => setForm({ ...form, shelf: e.target.value })} /></div><div className="flex gap-2"><Button onClick={handleCreate}>{tCommon('actions.save')}</Button><Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button></div></Card>)}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('locations.empty')} /> : (
        <Table headers={[t('locations.code'), t('locations.zone'), t('locations.aisle'), t('locations.shelf'), tCommon('common.actions')]}>
          {items.map(l => (<TableRow key={l.id}><TableCell>{l.code}</TableCell><TableCell>{l.zone || '-'}</TableCell><TableCell>{l.aisle || '-'}</TableCell><TableCell>{l.shelf || '-'}</TableCell><TableCell><Button size="sm" variant="danger" onClick={() => handleDelete(l.id)}><Trash2 className="w-4 h-4" /></Button></TableCell></TableRow>))}
        </Table>
      )}
    </div>
  )
}

// ============ Quality Checks Page ============
export function QualityCheckPage() {
  const { t } = useTranslation('stock')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ product_id: '', reference_type: 'goods_receipt', status: 'pending', notes: '' })

  const loadData = useCallback(async () => { setLoading(true); try { setItems(await getQualityChecks() || []) } catch { } finally { setLoading(false) } }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() { try { await createQualityCheck(form as any); toast('success', tCommon('common.success'), t('quality.created')); setShowForm(false); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }
  async function handleStatus(id: string, status: string) { try { await updateQualityCheck(id, { status: status as any, checked_at: new Date().toISOString() }); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }

  return (
    <div>
      <Breadcrumb items={[{ label: t('quality.breadcrumb1'), path: '/stock' }, { label: t('quality.title') }]} />
      <PageHeader title={t('quality.title')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('quality.new')}</Button>} />
      {showForm && (<Card className="p-4 mb-4 space-y-3"><Input placeholder={t('quality.productId')} value={form.product_id} onChange={e => setForm({ ...form, product_id: e.target.value })} /><Input placeholder={t('quality.notes')} value={form.notes} onChange={e => setForm({ ...form, notes: e.target.value })} /><div className="flex gap-2"><Button onClick={handleCreate}>{tCommon('actions.save')}</Button><Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button></div></Card>)}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('quality.empty')} /> : (
        <Table headers={[t('quality.product'), t('quality.status'), t('quality.date'), tCommon('common.actions')]}>
          {items.map(q => (<TableRow key={q.id}><TableCell>{q.products?.name || '-'}</TableCell><TableCell><Badge>{t(`quality.statuses.${q.status}`)}</Badge></TableCell><TableCell>{q.checked_at ? new Date(q.checked_at).toLocaleDateString() : '-'}</TableCell><TableCell><div className="flex gap-1"><Button size="sm" variant="secondary" onClick={() => handleStatus(q.id, 'passed')}>{t('quality.pass')}</Button><Button size="sm" variant="secondary" onClick={() => handleStatus(q.id, 'failed')}>{t('quality.fail')}</Button></div></TableCell></TableRow>))}
        </Table>
      )}
    </div>
  )
}

// ============ Pick Lists Page ============
export function PickListPage() {
  const { t } = useTranslation('stock')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ number: '', reference_type: 'sales_order', warehouse_id: '', status: 'draft' })

  const loadData = useCallback(async () => { setLoading(true); try { setItems(await getPickLists() || []) } catch { } finally { setLoading(false) } }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() { try { await createPickList(form as any); toast('success', tCommon('common.success'), t('picking.created')); setShowForm(false); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }
  async function handleStatus(id: string, status: string) { try { await updatePickList(id, { status: status as any, picked_at: new Date().toISOString() }); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }

  return (
    <div>
      <Breadcrumb items={[{ label: t('picking.breadcrumb1'), path: '/stock' }, { label: t('picking.title') }]} />
      <PageHeader title={t('picking.title')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('picking.new')}</Button>} />
      {showForm && (<Card className="p-4 mb-4 space-y-3"><Input placeholder={t('picking.number')} value={form.number} onChange={e => setForm({ ...form, number: e.target.value })} /><div className="flex gap-2"><Button onClick={handleCreate}>{tCommon('actions.save')}</Button><Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button></div></Card>)}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('picking.empty')} /> : (
        <Table headers={[t('picking.number'), t('picking.status'), t('picking.date'), tCommon('common.actions')]}>
          {items.map(p => (<TableRow key={p.id}><TableCell>{p.number}</TableCell><TableCell><Badge>{t(`picking.statuses.${p.status}`)}</Badge></TableCell><TableCell>{new Date(p.created_at).toLocaleDateString()}</TableCell><TableCell><div className="flex gap-1"><Button size="sm" variant="secondary" onClick={() => handleStatus(p.id, 'in_progress')}>{t('picking.start')}</Button><Button size="sm" variant="secondary" onClick={() => handleStatus(p.id, 'completed')}>{t('picking.complete')}</Button></div></TableCell></TableRow>))}
        </Table>
      )}
    </div>
  )
}

// ============ Serial Numbers Page ============
export function SerialNumbersPage() {
  const { t } = useTranslation('stock')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ product_id: '', serial_number: '', status: 'in_stock', warranty_expiry: '', notes: '' })

  const loadData = useCallback(async () => { setLoading(true); try { setItems(await getProductSerialNumbers() || []) } catch { } finally { setLoading(false) } }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() { try { await createProductSerialNumber(form as any); toast('success', tCommon('common.success'), t('serials.created')); setShowForm(false); setForm({ product_id: '', serial_number: '', status: 'in_stock', warranty_expiry: '', notes: '' }); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }
  async function handleDelete(id: string) { if (!window.confirm(tCommon('form.confirmDelete'))) return; try { await deleteProductSerialNumber(id); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }

  return (
    <div>
      <Breadcrumb items={[{ label: t('serials.breadcrumb1'), path: '/stock' }, { label: t('serials.title') }]} />
      <PageHeader title={t('serials.title')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('serials.new')}</Button>} />
      {showForm && (<Card className="p-4 mb-4 space-y-3"><div className="grid grid-cols-2 gap-3"><Input placeholder={t('serials.productId')} value={form.product_id} onChange={e => setForm({ ...form, product_id: e.target.value })} /><Input placeholder={t('serials.number')} value={form.serial_number} onChange={e => setForm({ ...form, serial_number: e.target.value })} /></div><div className="flex gap-2"><Button onClick={handleCreate}>{tCommon('actions.save')}</Button><Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button></div></Card>)}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('serials.empty')} /> : (
        <Table headers={[t('serials.product'), t('serials.number'), t('serials.status'), tCommon('common.actions')]}>
          {items.map(s => (<TableRow key={s.id}><TableCell>{s.products?.name || '-'}</TableCell><TableCell>{s.serial_number}</TableCell><TableCell><Badge>{t(`serials.statuses.${s.status}`)}</Badge></TableCell><TableCell><Button size="sm" variant="danger" onClick={() => handleDelete(s.id)}><Trash2 className="w-4 h-4" /></Button></TableCell></TableRow>))}
        </Table>
      )}
    </div>
  )
}

// ============ Product Batches Page ============
export function ProductBatchesPage() {
  const { t } = useTranslation('stock')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ product_id: '', batch_number: '', quantity: 0, expiry_date: '', status: 'active' })

  const loadData = useCallback(async () => { setLoading(true); try { setItems(await getProductBatches() || []) } catch { } finally { setLoading(false) } }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() { try { await createProductBatch(form as any); toast('success', tCommon('common.success'), t('batches.created')); setShowForm(false); setForm({ product_id: '', batch_number: '', quantity: 0, expiry_date: '', status: 'active' }); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }
  async function handleDelete(id: string) { if (!window.confirm(tCommon('form.confirmDelete'))) return; try { await deleteProductBatch(id); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }

  return (
    <div>
      <Breadcrumb items={[{ label: t('batches.breadcrumb1'), path: '/stock' }, { label: t('batches.title') }]} />
      <PageHeader title={t('batches.title')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('batches.new')}</Button>} />
      {showForm && (<Card className="p-4 mb-4 space-y-3"><div className="grid grid-cols-2 gap-3"><Input placeholder={t('batches.productId')} value={form.product_id} onChange={e => setForm({ ...form, product_id: e.target.value })} /><Input placeholder={t('batches.number')} value={form.batch_number} onChange={e => setForm({ ...form, batch_number: e.target.value })} /><Input type="number" placeholder={t('batches.quantity')} value={form.quantity} onChange={e => setForm({ ...form, quantity: parseFloat(e.target.value) || 0 })} /><Input type="date" value={form.expiry_date} onChange={e => setForm({ ...form, expiry_date: e.target.value })} /></div><div className="flex gap-2"><Button onClick={handleCreate}>{tCommon('actions.save')}</Button><Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button></div></Card>)}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('batches.empty')} /> : (
        <Table headers={[t('batches.product'), t('batches.number'), t('batches.quantity'), t('batches.expiry'), t('batches.status'), tCommon('common.actions')]}>
          {items.map(b => (<TableRow key={b.id}><TableCell>{b.products?.name || '-'}</TableCell><TableCell>{b.batch_number}</TableCell><TableCell>{b.quantity}</TableCell><TableCell>{b.expiry_date || '-'}</TableCell><TableCell><Badge>{t(`batches.statuses.${b.status}`)}</Badge></TableCell><TableCell><Button size="sm" variant="danger" onClick={() => handleDelete(b.id)}><Trash2 className="w-4 h-4" /></Button></TableCell></TableRow>))}
        </Table>
      )}
    </div>
  )
}

// ============ Document Templates Page ============
export function DocumentTemplatesPage() {
  const { t } = useTranslation('sales')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ name: '', document_type: 'invoice', logo_url: '', primary_color: '#2563eb', secondary_color: '#64748b', is_default: false })

  const loadData = useCallback(async () => { setLoading(true); try { setItems(await getDocumentTemplates() || []) } catch { } finally { setLoading(false) } }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() { try { await createDocumentTemplate(form as any); toast('success', tCommon('common.success'), t('docTemplates.created')); setShowForm(false); setForm({ name: '', document_type: 'invoice', logo_url: '', primary_color: '#2563eb', secondary_color: '#64748b', is_default: false }); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }
  async function handleDelete(id: string) { if (!window.confirm(tCommon('form.confirmDelete'))) return; try { await deleteDocumentTemplate(id); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }

  return (
    <div>
      <Breadcrumb items={[{ label: t('docTemplates.breadcrumb1'), path: '/settings' }, { label: t('docTemplates.title') }]} />
      <PageHeader title={t('docTemplates.title')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('docTemplates.new')}</Button>} />
      {showForm && (<Card className="p-4 mb-4 space-y-3"><div className="grid grid-cols-2 gap-3"><Input placeholder={t('docTemplates.name')} value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} /><select className="border rounded px-3 py-2" value={form.document_type} onChange={e => setForm({ ...form, document_type: e.target.value })}><option value="invoice">{t('docTemplates.types.invoice')}</option><option value="quote">{t('docTemplates.types.quote')}</option><option value="delivery_note">{t('docTemplates.types.delivery_note')}</option><option value="credit_note">{t('docTemplates.types.credit_note')}</option></select><Input type="color" value={form.primary_color} onChange={e => setForm({ ...form, primary_color: e.target.value })} /><Input type="color" value={form.secondary_color} onChange={e => setForm({ ...form, secondary_color: e.target.value })} /></div><div className="flex gap-2"><Button onClick={handleCreate}>{tCommon('actions.save')}</Button><Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button></div></Card>)}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('docTemplates.empty')} /> : (
        <Table headers={[t('docTemplates.name'), t('docTemplates.type'), t('docTemplates.color'), tCommon('common.actions')]}>
          {items.map(d => (<TableRow key={d.id}><TableCell>{d.name}</TableCell><TableCell>{t(`docTemplates.types.${d.document_type}`)}</TableCell><TableCell><div className="flex gap-1"><div className="w-6 h-6 rounded" style={{ backgroundColor: d.primary_color }} /><div className="w-6 h-6 rounded" style={{ backgroundColor: d.secondary_color }} /></div></TableCell><TableCell><Button size="sm" variant="danger" onClick={() => handleDelete(d.id)}><Trash2 className="w-4 h-4" /></Button></TableCell></TableRow>))}
        </Table>
      )}
    </div>
  )
}

// ============ Delivery Schedules Page ============
export function DeliverySchedulePage() {
  const { t } = useTranslation('sales')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ customer_id: '', product_id: '', frequency: 'weekly', quantity: 0, start_date: '', end_date: '', active: true })

  const loadData = useCallback(async () => { setLoading(true); try { setItems(await getDeliverySchedules() || []) } catch { } finally { setLoading(false) } }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() { try { await createDeliverySchedule(form as any); toast('success', tCommon('common.success'), t('schedules.created')); setShowForm(false); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }
  async function handleDelete(id: string) { if (!window.confirm(tCommon('form.confirmDelete'))) return; try { await deleteDeliverySchedule(id); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }

  return (
    <div>
      <Breadcrumb items={[{ label: t('schedules.breadcrumb1'), path: '/sales' }, { label: t('schedules.title') }]} />
      <PageHeader title={t('schedules.title')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('schedules.new')}</Button>} />
      {showForm && (<Card className="p-4 mb-4 space-y-3"><div className="grid grid-cols-2 gap-3"><Input placeholder={t('schedules.customerId')} value={form.customer_id} onChange={e => setForm({ ...form, customer_id: e.target.value })} /><Input placeholder={t('schedules.productId')} value={form.product_id} onChange={e => setForm({ ...form, product_id: e.target.value })} /><select className="border rounded px-3 py-2" value={form.frequency} onChange={e => setForm({ ...form, frequency: e.target.value })}><option value="daily">{t('schedules.freq.daily')}</option><option value="weekly">{t('schedules.freq.weekly')}</option><option value="monthly">{t('schedules.freq.monthly')}</option></select><Input type="number" placeholder={t('schedules.quantity')} value={form.quantity} onChange={e => setForm({ ...form, quantity: parseFloat(e.target.value) || 0 })} /><Input type="date" value={form.start_date} onChange={e => setForm({ ...form, start_date: e.target.value })} /></div><div className="flex gap-2"><Button onClick={handleCreate}>{tCommon('actions.save')}</Button><Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button></div></Card>)}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('schedules.empty')} /> : (
        <Table headers={[t('schedules.customer'), t('schedules.product'), t('schedules.frequency'), t('schedules.quantity'), t('schedules.startDate'), tCommon('common.actions')]}>
          {items.map(s => (<TableRow key={s.id}><TableCell>{s.customers?.name || '-'}</TableCell><TableCell>{s.products?.name || '-'}</TableCell><TableCell>{t(`schedules.freq.${s.frequency}`)}</TableCell><TableCell>{s.quantity}</TableCell><TableCell>{s.start_date}</TableCell><TableCell><Button size="sm" variant="danger" onClick={() => handleDelete(s.id)}><Trash2 className="w-4 h-4" /></Button></TableCell></TableRow>))}
        </Table>
      )}
    </div>
  )
}

// ============ Product Substitutes Page ============
export function ProductSubstitutesPage() {
  const { t } = useTranslation('stock')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ product_id: '', substitute_id: '', priority: 1 })

  const loadData = useCallback(async () => { setLoading(true); try { setItems(await getProductSubstitutes() || []) } catch { } finally { setLoading(false) } }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() { try { await createProductSubstitute(form as any); toast('success', tCommon('common.success'), t('substitutes.created')); setShowForm(false); setForm({ product_id: '', substitute_id: '', priority: 1 }); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }
  async function handleDelete(id: string) { if (!window.confirm(tCommon('form.confirmDelete'))) return; try { await deleteProductSubstitute(id); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }

  return (
    <div>
      <Breadcrumb items={[{ label: t('substitutes.breadcrumb1'), path: '/stock' }, { label: t('substitutes.title') }]} />
      <PageHeader title={t('substitutes.title')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('substitutes.new')}</Button>} />
      {showForm && (<Card className="p-4 mb-4 space-y-3"><div className="grid grid-cols-2 gap-3"><Input placeholder={t('substitutes.productId')} value={form.product_id} onChange={e => setForm({ ...form, product_id: e.target.value })} /><Input placeholder={t('substitutes.substituteId')} value={form.substitute_id} onChange={e => setForm({ ...form, substitute_id: e.target.value })} /><Input type="number" placeholder={t('substitutes.priority')} value={form.priority} onChange={e => setForm({ ...form, priority: parseInt(e.target.value) || 1 })} /></div><div className="flex gap-2"><Button onClick={handleCreate}>{tCommon('actions.save')}</Button><Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button></div></Card>)}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('substitutes.empty')} /> : (
        <Table headers={[t('substitutes.product'), t('substitutes.substitute'), t('substitutes.priority'), tCommon('common.actions')]}>
          {items.map(s => (<TableRow key={s.id}><TableCell>{s.products?.name || '-'}</TableCell><TableCell>{s.products?.sub_name || '-'}</TableCell><TableCell>{s.priority}</TableCell><TableCell><Button size="sm" variant="danger" onClick={() => handleDelete(s.id)}><Trash2 className="w-4 h-4" /></Button></TableCell></TableRow>))}
        </Table>
      )}
    </div>
  )
}

// ============ Dormant Stock Page ============
export function DormantStockPage() {
  const { t } = useTranslation('stock')
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [days, setDays] = useState(90)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const { supabase } = await import('@/lib/supabase')
      const { getTenantId } = await import('@/lib/queries')
      const tid = await getTenantId()
      const cutoff = new Date()
      cutoff.setDate(cutoff.getDate() - days)
      let q = supabase.from('stock_quantities').select('*, products(name, sku), warehouses(name)').lt('updated_at', cutoff.toISOString())
      if (tid) q = q.eq('tenant_id', tid)
      const { data, error } = await q
      if (error) throw error
      setItems(data || [])
    } catch { } finally { setLoading(false) }
  }, [days])
  useEffect(() => { loadData() }, [loadData])

  return (
    <div>
      <Breadcrumb items={[{ label: t('dormant.breadcrumb1'), path: '/stock' }, { label: t('dormant.title') }]} />
      <PageHeader title={t('dormant.title')} />
      <Card className="p-4 mb-4">
        <div className="flex items-center gap-3">
          <label className="text-sm">{t('dormant.daysThreshold')}</label>
          <Input type="number" value={days} onChange={e => setDays(parseInt(e.target.value) || 90)} className="w-32" />
        </div>
      </Card>
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('dormant.empty')} /> : (
        <Table headers={[t('dormant.product'), t('dormant.sku'), t('dormant.warehouse'), t('dormant.quantity'), t('dormant.lastUpdate')]}>
          {items.map(s => (<TableRow key={s.id}><TableCell>{s.products?.name || '-'}</TableCell><TableCell>{s.products?.sku || '-'}</TableCell><TableCell>{s.warehouses?.name || '-'}</TableCell><TableCell>{s.quantity}</TableCell><TableCell>{new Date(s.updated_at).toLocaleDateString()}</TableCell></TableRow>))}
        </Table>
      )}
    </div>
  )
}
