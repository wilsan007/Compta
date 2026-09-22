import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Select, Input } from '@/components/ui'
import { getRhRequests, createRhRequest, assignRhRequest, resolveRhRequest } from '@/lib/queries/dematRh'
import { getEmployees } from '@/lib/queries/payroll'
import type { RhRequest, Employee } from '@/types'
import { useToast } from '@/lib/toast'
import { Plus, UserCheck, CheckCircle } from 'lucide-react'

export function RhRequestsPage() {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const { toast } = useToast()
  const [loading, setLoading] = useState(true)
  const [requests, setRequests] = useState<RhRequest[]>([])
  const [employees, setEmployees] = useState<Employee[]>([])
  const [statusFilter, setStatusFilter] = useState('')
  const [showForm, setShowForm] = useState(false)
  const [showResolve, setShowResolve] = useState<string | null>(null)
  const [resolveText, setResolveText] = useState('')
  const [formEmp, setFormEmp] = useState('')
  const [formType, setFormType] = useState('document_copy')
  const [formSubject, setFormSubject] = useState('')
  const [formDesc, setFormDesc] = useState('')

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [reqs, emps] = await Promise.all([
        statusFilter ? getRhRequests(statusFilter) : getRhRequests(),
        getEmployees(),
      ])
      setRequests(reqs as RhRequest[])
      setEmployees(emps)
    } catch (e: any) {
      toast('error', tCommon('common.error'), e.message)
    } finally {
      setLoading(false)
    }
  }, [statusFilter, toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  const handleCreate = async () => {
    try {
      await createRhRequest({
        tenant_id: null,
        employee_id: formEmp,
        request_type: formType as any,
        subject: formSubject,
        description: formDesc || null,
        status: 'pending',
        assigned_to: null,
        response: null,
        resolved_at: null,
      })
      toast('success', tCommon('common.success'), tCommon('common.saved'))
      setShowForm(false)
      setFormEmp(''); setFormSubject(''); setFormDesc('')
      loadData().catch(err => console.error('loadData:', err))
    } catch (e: any) {
      toast('error', tCommon('common.error'), e.message)
    }
  }

  const handleAssign = async (id: string, assignedTo: string) => {
    try {
      await assignRhRequest(id, assignedTo)
      toast('success', t('requests.assigned'))
      loadData().catch(err => console.error('loadData:', err))
    } catch (e: any) {
      toast('error', tCommon('common.error'), e.message)
    }
  }

  const handleResolve = async () => {
    if (!showResolve || !resolveText) return
    try {
      await resolveRhRequest(showResolve, resolveText)
      toast('success', t('requests.resolved'))
      setShowResolve(null)
      setResolveText('')
      loadData().catch(err => console.error('loadData:', err))
    } catch (e: any) {
      toast('error', tCommon('common.error'), e.message)
    }
  }

  const statusVariant = (status: string): 'success' | 'warning' | 'danger' | 'neutral' | 'primary' => {
    switch (status) {
      case 'resolved': return 'success'
      case 'rejected': return 'danger'
      case 'in_progress': return 'primary'
      default: return 'neutral'
    }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('groups.hr') }, { label: t('requests.title') }]} />
      <PageHeader title={t('requests.title')} subtitle={t('requests.subtitle')} />

      <div className="flex gap-3 mb-4 items-end">
        <Select label={t('requests.status')} value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} options={[
          { value: '', label: tCommon('table.all') },
          { value: 'pending', label: t('requests.statuses.pending') },
          { value: 'in_progress', label: t('requests.statuses.in_progress') },
          { value: 'resolved', label: t('requests.statuses.resolved') },
          { value: 'rejected', label: t('requests.statuses.rejected') },
        ]} />
        <Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4 mr-2" />{t('requests.newRequest')}</Button>
      </div>

      {loading ? <SkeletonTable /> : requests.length === 0 ? (
        <EmptyState title={t('requests.noRequests')} />
      ) : (
        <Card>
          <Table headers={[t('requests.employee'), t('requests.type'), t('requests.subject'), t('requests.status'), t('requests.assignedTo'), t('requests.date'), t('requests.actions')]}>
            {requests.map(req => (
              <TableRow key={req.id}>
                <TableCell className="text-sm">{(req as any).employees?.name || '-'}</TableCell>
                <TableCell className="text-xs">{t(`requests.types.${req.request_type}`)}</TableCell>
                <TableCell className="text-sm">{req.subject}</TableCell>
                <TableCell><Badge variant={statusVariant(req.status)}>{t(`requests.statuses.${req.status}`)}</Badge></TableCell>
                <TableCell className="text-xs">{req.assigned_to || '-'}</TableCell>
                <TableCell className="text-xs">{new Date(req.created_at).toLocaleDateString()}</TableCell>
                <TableCell>
                  {req.status === 'pending' && <Button size="sm" variant="ghost" onClick={() => handleAssign(req.id, 'RH Manager')}><UserCheck className="w-4 h-4 mr-1" />{t('requests.assign')}</Button>}
                  {req.status === 'in_progress' && <Button size="sm" variant="ghost" onClick={() => setShowResolve(req.id)}><CheckCircle className="w-4 h-4 mr-1" />{t('requests.resolve')}</Button>}
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <Card className="w-full max-w-md p-6">
            <h3 className="font-medium mb-4">{t('requests.newRequest')}</h3>
            <div className="space-y-3">
              <Select label={t('requests.employee')} value={formEmp} onChange={(e) => setFormEmp(e.target.value)} options={employees.map(emp => ({ value: emp.id, label: emp.name }))} />
              <Select label={t('requests.type')} value={formType} onChange={(e) => setFormType(e.target.value)} options={[
                { value: 'document_copy', label: t('requests.types.document_copy') },
                { value: 'certificate', label: t('requests.types.certificate') },
                { value: 'leave_info', label: t('requests.types.leave_info') },
                { value: 'salary_change', label: t('requests.types.salary_change') },
                { value: 'address_change', label: t('requests.types.address_change') },
                { value: 'other', label: t('requests.types.other') },
              ]} />
              <Input label={t('requests.subject')} value={formSubject} onChange={(e) => setFormSubject(e.target.value)} />
              <div>
                <label className="block text-sm font-medium mb-1">{t('requests.description')}</label>
                <textarea className="w-full px-3 py-2 border rounded text-sm" rows={3} value={formDesc} onChange={(e) => setFormDesc(e.target.value)} />
              </div>
            </div>
            <div className="flex gap-2 mt-4">
              <Button onClick={handleCreate} disabled={!formEmp || !formSubject}>{tCommon('actions.save')}</Button>
              <Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('actions.cancel')}</Button>
            </div>
          </Card>
        </div>
      )}

      {showResolve && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <Card className="w-full max-w-md p-6">
            <h3 className="font-medium mb-4">{t('requests.resolve')}</h3>
            <div>
              <label className="block text-sm font-medium mb-1">{t('requests.response')}</label>
              <textarea className="w-full px-3 py-2 border rounded text-sm" rows={4} value={resolveText} onChange={(e) => setResolveText(e.target.value)} />
            </div>
            <div className="flex gap-2 mt-4">
              <Button onClick={handleResolve} disabled={!resolveText}>{t('requests.resolve')}</Button>
              <Button variant="secondary" onClick={() => setShowResolve(null)}>{tCommon('actions.cancel')}</Button>
            </div>
          </Card>
        </div>
      )}
    </div>
  )
}
