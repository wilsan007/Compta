import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Badge, SortableTable, TableRow, TableCell, EmptyState, AutoBreadcrumb, SkeletonTable, Input, Select, ConfirmDialog } from '@/components/ui'
import { getPurchaseRequests, createPurchaseRequest, updatePurchaseRequestStatus, convertPurchaseRequestToOrder, deletePurchaseRequest } from '@/lib/queries/purchaseAdvanced'
import { formatDate } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import { ShoppingCart, Plus, Search, Trash2, X, Check, Ban, ArrowRightCircle } from 'lucide-react'
import type { PurchaseRequest } from '@/types'
import { nextDocumentNumber } from '@/lib/queries/core'

export function PurchaseRequestsPage() {
  const { t } = useTranslation('purchases')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [requests, setRequests] = useState<PurchaseRequest[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('')
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<PurchaseRequest | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<PurchaseRequest | null>(null)

  // oxlint-disable-next-line react-hooks/exhaustive-deps -- chargement volontairement limite aux valeurs listees
  useEffect(() => { loadRequests() }, [])

  async function loadRequests() {
    try {
      const data = await getPurchaseRequests(statusFilter || undefined)
      setRequests(data || [])
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    } finally {
      setLoading(false)
    }
  }

  async function handleStatusChange(id: string, status: string) {
    try {
      await updatePurchaseRequestStatus(id, status, 'currentUser')
      toast('success', t('purchaseRequests.title'), t('purchaseRequests.statusChanged'))
      loadRequests().catch(err => console.error('loadRequests:', err))
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    }
  }

  async function handleConvert(id: string) {
    try {
      await convertPurchaseRequestToOrder(id, '')
      toast('success', t('purchaseRequests.title'), t('purchaseRequests.converted'))
      loadRequests().catch(err => console.error('loadRequests:', err))
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    }
  }

  async function handleDelete(id: string) {
    try {
      await deletePurchaseRequest(id)
      setRequests(requests.filter(r => r.id !== id))
      toast('success', t('purchaseRequests.title'), tCommon('toast.deleted'))
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    }
  }

  const filtered = requests.filter(r =>
    r.number?.toLowerCase().includes(search.toLowerCase()) ||
    r.requester?.toLowerCase().includes(search.toLowerCase())
  )

  const statusBadge: Record<string, 'success' | 'warning' | 'danger' | 'neutral' | 'primary'> = {
    draft: 'neutral', submitted: 'warning', approved: 'success', rejected: 'danger', converted: 'primary',
  }

  return (
    <div className="animate-fade-in">
      <AutoBreadcrumb />
      <PageHeader
        title={t('purchaseRequests.title')}
        subtitle={`${requests.length} ${t('purchaseRequests.title').toLowerCase()}`}
        action={<Button variant="primary" onClick={() => { setEditing(null); setShowForm(true) }}><Plus className="w-4 h-4" /> {t('purchaseRequests.new')}</Button>}
      />

      <Card>
        <div className="mb-4 flex gap-4">
          <div className="relative flex-1">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-text-secondary)]" />
            <input className="input pl-10" placeholder={t('purchaseRequests.searchPlaceholder')} value={search} onChange={e => setSearch(e.target.value)} />
          </div>
          <Select value={statusFilter} onChange={e => { setStatusFilter(e.target.value); setLoading(true); loadRequests() }}
            options={[
              { value: '', label: tCommon('table.all') },
              { value: 'draft', label: t('purchaseRequests.statusDraft') },
              { value: 'submitted', label: t('purchaseRequests.statusSubmitted') },
              { value: 'approved', label: t('purchaseRequests.statusApproved') },
              { value: 'rejected', label: t('purchaseRequests.statusRejected') },
              { value: 'converted', label: t('purchaseRequests.statusConverted') },
            ]} />
        </div>

        {loading ? (
          <SkeletonTable rows={5} cols={6} />
        ) : filtered.length > 0 ? (
          <SortableTable
            headers={[
              { label: t('purchaseRequests.number'), key: 'number', sortable: true },
              { label: t('purchaseRequests.requester'), key: 'requester', sortable: true },
              { label: t('purchaseRequests.status'), key: 'status', sortable: true },
              { label: t('purchaseRequests.priority'), key: 'priority', sortable: true },
              { label: t('purchaseRequests.expectedDate'), key: 'expected_date', sortable: true },
              { label: tCommon('table.actions') },
            ]}
            data={filtered as any}
            initialSortKey="created_at"
            renderRow={(r: any) => (
              <TableRow key={r.id}>
                <TableCell className="font-mono text-xs">{r.number}</TableCell>
                <TableCell>{r.requester || '—'}</TableCell>
                <TableCell><Badge variant={statusBadge[r.status] || 'neutral'}>{t(`purchaseRequests.status${r.status.charAt(0).toUpperCase() + r.status.slice(1)}`)}</Badge></TableCell>
                <TableCell><Badge variant={r.priority === 'urgent' ? 'danger' : r.priority === 'high' ? 'warning' : 'neutral'}>{t(`purchaseRequests.priority${r.priority.charAt(0).toUpperCase() + r.priority.slice(1)}`)}</Badge></TableCell>
                <TableCell>{r.expected_date ? formatDate(r.expected_date) : '—'}</TableCell>
                <TableCell>
                  <div className="flex items-center gap-1">
                    {r.status === 'submitted' && (
                      <>
                        <button onClick={() => handleStatusChange(r.id, 'approved')} className="p-1.5 rounded text-[var(--color-success)] hover:bg-[var(--color-neutral-100)]" title={t('purchaseRequests.approve')}><Check className="w-4 h-4" /></button>
                        <button onClick={() => handleStatusChange(r.id, 'rejected')} className="p-1.5 rounded text-[var(--color-danger)] hover:bg-[var(--color-neutral-100)]" title={t('purchaseRequests.reject')}><Ban className="w-4 h-4" /></button>
                      </>
                    )}
                    {r.status === 'approved' && (
                      <button onClick={() => handleConvert(r.id)} className="p-1.5 rounded text-[var(--color-primary)] hover:bg-[var(--color-neutral-100)]" title={t('purchaseRequests.convert')}><ArrowRightCircle className="w-4 h-4" /></button>
                    )}
                    <button onClick={() => setDeleteTarget(r)} className="p-1.5 rounded text-[var(--color-danger)] hover:bg-[rgba(222,53,11,0.1)]" title={tCommon('actions.delete')}><Trash2 className="w-4 h-4" /></button>
                  </div>
                </TableCell>
              </TableRow>
            )}
          />
        ) : (
          <EmptyState icon={<ShoppingCart className="w-8 h-8" />} title={t('purchaseRequests.noRequests')} description={t('purchaseRequests.noRequestsDescription')} action={<Button variant="primary" onClick={() => { setEditing(null); setShowForm(true) }}><Plus className="w-4 h-4" /> {t('purchaseRequests.new')}</Button>} />
        )}
      </Card>

      {showForm && (
        <PurchaseRequestForm
          request={editing}
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); loadRequests() }}
        />
      )}

      <ConfirmDialog
        open={!!deleteTarget}
        title={tCommon('actions.delete')}
        message={`${tCommon('form.confirmDelete')} ${deleteTarget?.number} ?`}
        confirmLabel={tCommon('actions.delete')}
        onConfirm={() => { if (deleteTarget) handleDelete(deleteTarget.id); setDeleteTarget(null) }}
        onCancel={() => setDeleteTarget(null)}
      />
    </div>
  )
}

function PurchaseRequestForm({ request, onClose, onSaved }: {
  request: PurchaseRequest | null
  onClose: () => void
  onSaved: () => void
}) {
  const { t } = useTranslation('purchases')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  // Numéro attribué à l'enregistrement par la séquence si le champ est laissé vide (LOT4-10)
  const [number, setNumber] = useState(request?.number || '')
  const [requester, setRequester] = useState(request?.requester || '')
  const [department, setDepartment] = useState(request?.department || '')
  const [priority, setPriority] = useState(request?.priority || 'normal')
  const [expectedDate, setExpectedDate] = useState(request?.expected_date || '')
  const [notes, setNotes] = useState(request?.notes || '')
  const [lines, setLines] = useState<{ description: string; quantity: number; estimated_price: number }[]>(
    request?.purchase_request_lines?.map(l => ({ description: l.description, quantity: l.quantity, estimated_price: l.estimated_price || 0 })) || [{ description: '', quantity: 1, estimated_price: 0 }]
  )
  const [saving, setSaving] = useState(false)

  function addLine() { setLines([...lines, { description: '', quantity: 1, estimated_price: 0 }]) }
  function removeLine(idx: number) { setLines(lines.filter((_, i) => i !== idx)) }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      const data = {
        number: number.trim() || await nextDocumentNumber('PR'), requester, department, priority, expected_date: expectedDate || null, notes,
        status: 'draft' as const,
        purchase_request_lines: lines.filter(l => l.description.trim()),
      }
      await createPurchaseRequest(data as any)
      toast('success', t('purchaseRequests.title'), tCommon('toast.created'))
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '48rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('purchaseRequests.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4 max-h-[70vh] overflow-y-auto">
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('purchaseRequests.number')} value={number} placeholder="Auto" onChange={e => setNumber(e.target.value)} />
            <Input label={t('purchaseRequests.requester')} value={requester} onChange={e => setRequester(e.target.value)} />
            <Input label={t('purchaseRequests.department')} value={department} onChange={e => setDepartment(e.target.value)} />
            <Select label={t('purchaseRequests.priority')} value={priority} onChange={e => setPriority(e.target.value as any)}
              options={[
                { value: 'low', label: t('purchaseRequests.priorityLow') },
                { value: 'normal', label: t('purchaseRequests.priorityNormal') },
                { value: 'high', label: t('purchaseRequests.priorityHigh') },
                { value: 'urgent', label: t('purchaseRequests.priorityUrgent') },
              ]} />
            <Input label={t('purchaseRequests.expectedDate')} type="date" value={expectedDate} onChange={e => setExpectedDate(e.target.value)} />
          </div>
          <div>
            <div className="flex justify-between items-center mb-2">
              <span className="text-sm font-medium">{t('purchaseRequests.lines')}</span>
              <Button type="button" variant="secondary" size="sm" onClick={addLine}><Plus className="w-3 h-3" /> {t('purchaseRequests.addLine')}</Button>
            </div>
            {lines.map((line, idx) => (
              <div key={idx} className="grid grid-cols-12 gap-2 mb-2">
                <input className="input col-span-6" placeholder={t('purchaseRequests.description')} value={line.description} onChange={e => { const l = [...lines]; l[idx].description = e.target.value; setLines(l) }} />
                <input className="input col-span-2" type="number" placeholder={t('purchaseRequests.quantity')} value={line.quantity} onChange={e => { const l = [...lines]; l[idx].quantity = Number(e.target.value); setLines(l) }} />
                <input className="input col-span-3" type="number" placeholder={t('purchaseRequests.estimatedPrice')} value={line.estimated_price} onChange={e => { const l = [...lines]; l[idx].estimated_price = Number(e.target.value); setLines(l) }} />
                <button type="button" onClick={() => removeLine(idx)} className="col-span-1 p-2 rounded text-[var(--color-danger)] hover:bg-[rgba(222,53,11,0.1)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-4 h-4" aria-hidden="true" /></button>
              </div>
            ))}
          </div>
          <Input label={t('purchaseRequests.notes')} value={notes} onChange={e => setNotes(e.target.value)} />
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button variant="secondary" type="button" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" loading={saving}>{tCommon('actions.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
