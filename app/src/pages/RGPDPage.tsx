import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { formatDate } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import { getRGPDRequests, createRGPDRequest, updateRGPDRequest } from '@/lib/queries/misc'
import { Shield, Plus, X, CheckCircle, XCircle } from 'lucide-react'
import type { RGPDRequest } from '@/types'

export function RGPDPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [requests, setRequests] = useState<RGPDRequest[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)

  const [form, setForm] = useState({
    request_type: 'export' as 'export' | 'delete' | 'anonymize' | 'access',
    entity_type: 'customer' as 'customer' | 'supplier' | 'employee' | 'all',
    entity_id: '',
    notes: '',
  })

  const load = useCallback(async () => {
    try {
      setLoading(true)
      const data = await getRGPDRequests()
      setRequests(data || [])
    } catch (err) {
      console.error('Error loading RGPD requests:', err)
      toast('error', t('rgpd.title'), t('rgpd.loadError'))
    } finally {
      setLoading(false)
    }
  }, [toast, t])

  useEffect(() => { load() }, [load])

  function resetForm() {
    setForm({ request_type: 'export', entity_type: 'customer', entity_id: '', notes: '' })
    setShowForm(false)
  }

  async function handleSubmit() {
    try {
      await createRGPDRequest({
        ...form,
        entity_id: form.entity_id || null,
        notes: form.notes || null,
        status: 'pending',
        requested_by: null,
        processed_by: null,
        processed_at: null,
      } as any)
      toast('success', t('rgpd.title'), t('rgpd.createSuccess'))
      resetForm()
      await load()
    } catch (err) {
      console.error('Error creating RGPD request:', err)
      toast('error', t('rgpd.title'), t('rgpd.createError'))
    }
  }

  async function handleProcess(id: string, status: 'completed' | 'rejected') {
    try {
      await updateRGPDRequest(id, {
        status,
        processed_at: new Date().toISOString(),
      })
      toast('success', t('rgpd.title'), t(`rgpd.${status === 'completed' ? 'processSuccess' : 'rejectSuccess'}`))
      await load()
    } catch (err) {
      console.error('Error processing:', err)
      toast('error', t('rgpd.title'), t('rgpd.processError'))
    }
  }

  if (loading) {
    return (
      <div>
        <Breadcrumb items={[{ label: t('title') }, { label: t('home.structure') }, { label: t('rgpd.title') }]} />
        <PageHeader title={t('rgpd.title')} subtitle={t('rgpd.subtitle')} />
        <SkeletonTable rows={6} cols={6} />
      </div>
    )
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('home.structure') }, { label: t('rgpd.title') }]} />
      <PageHeader title={t('rgpd.title')} subtitle={t('rgpd.subtitle')} />

      {showForm && (
        <Card className="mb-4">
          <div className="p-4">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-semibold">{t('rgpd.newRequest')}</h3>
              <Button variant="secondary" onClick={resetForm}><X className="w-4 h-4" /></Button>
            </div>
            <div className="grid grid-cols-3 gap-4">
              <Select
                label={t('rgpd.requestType')}
                value={form.request_type}
                onChange={(e) => setForm({ ...form, request_type: e.target.value as any })}
                options={[
                  { value: 'export', label: t('rgpd.types.export') },
                  { value: 'delete', label: t('rgpd.types.delete') },
                  { value: 'anonymize', label: t('rgpd.types.anonymize') },
                  { value: 'access', label: t('rgpd.types.access') },
                ]}
              />
              <Select
                label={t('rgpd.entityType')}
                value={form.entity_type}
                onChange={(e) => setForm({ ...form, entity_type: e.target.value as any })}
                options={[
                  { value: 'customer', label: t('rgpd.entities.customer') },
                  { value: 'supplier', label: t('rgpd.entities.supplier') },
                  { value: 'employee', label: t('rgpd.entities.employee') },
                  { value: 'all', label: t('rgpd.entities.all') },
                ]}
              />
              <Input label={t('rgpd.entityId')} value={form.entity_id} onChange={(e) => setForm({ ...form, entity_id: e.target.value })} />
              <div className="col-span-3">
                <Input label={t('rgpd.notes')} value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} />
              </div>
            </div>
            <div className="flex justify-end gap-3 mt-4">
              <Button variant="secondary" onClick={resetForm}>{tCommon('actions.cancel')}</Button>
              <Button onClick={handleSubmit}>{tCommon('actions.save')}</Button>
            </div>
          </div>
        </Card>
      )}

      <div className="flex justify-end mb-3">
        <Button onClick={() => setShowForm(true)}>
          <Plus className="w-4 h-4" /> {t('rgpd.newRequest')}
        </Button>
      </div>

      {requests.length === 0 ? (
        <EmptyState icon={<Shield className="w-8 h-8" />} title={t('rgpd.empty')} description={t('rgpd.emptyDesc')} />
      ) : (
        <Card>
          <Table headers={[
            t('rgpd.requestType'),
            t('rgpd.entityType'),
            t('rgpd.entityId'),
            t('rgpd.status'),
            t('rgpd.requestedAt'),
            '',
          ]}>
            {requests.map((req) => (
              <TableRow key={req.id}>
                <TableCell className="text-xs">{t(`rgpd.types.${req.request_type}`)}</TableCell>
                <TableCell className="text-xs">{t(`rgpd.entities.${req.entity_type}`)}</TableCell>
                <TableCell className="font-mono text-xs">{req.entity_id || '—'}</TableCell>
                <TableCell>
                  <Badge variant={req.status === 'completed' ? 'success' : req.status === 'rejected' ? 'danger' : req.status === 'processing' ? 'warning' : 'neutral'}>
                    {t(`rgpd.statuses.${req.status}`)}
                  </Badge>
                </TableCell>
                <TableCell className="text-xs">{formatDate(req.requested_at)}</TableCell>
                <TableCell>
                  {req.status === 'pending' && (
                    <div className="flex gap-1">
                      <button onClick={() => handleProcess(req.id, 'completed')} className="p-1 text-[var(--color-text-secondary)] hover:text-[var(--color-success)]" title={t('rgpd.process')}>
                        <CheckCircle className="w-4 h-4" />
                      </button>
                      <button onClick={() => handleProcess(req.id, 'rejected')} className="p-1 text-[var(--color-text-secondary)] hover:text-[var(--color-danger)]" title={t('rgpd.reject')}>
                        <XCircle className="w-4 h-4" />
                      </button>
                    </div>
                  )}
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}
    </div>
  )
}
