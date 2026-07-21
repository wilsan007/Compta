import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { formatDate } from '@/lib/utils'
import { getLeaveRequests, createLeaveRequest, updateLeaveRequest, deleteLeaveRequest, getEmployees } from '@/lib/queries'
import { CalendarDays, Plus, Trash2, X, Check, XCircle } from 'lucide-react'
import type { Employee } from '@/types'
import { useToast } from '@/lib/toast'

const typeLabels: Record<string, string> = { annual: 'Congé payé', sick: 'Maladie', maternity: 'Maternité', paternity: 'Paternité', unpaid: 'Sans solde', other: 'Autre' }
const statusLabels: Record<string, string> = { pending: 'En attente', approved: 'Approuvé', rejected: 'Refusé', cancelled: 'Annulé' }
const statusBadge: Record<string, 'neutral' | 'success' | 'warning' | 'danger'> = { pending: 'warning', approved: 'success', rejected: 'danger', cancelled: 'neutral' }

export function LeaveRequestsPage() {
  const { toast } = useToast()
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
const [requests, setRequests] = useState<any[]>([])
  const [employees, setEmployees] = useState<Employee[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [statusFilter, setStatusFilter] = useState('')

  const loadData = useCallback(async () => {
    try {
      const [reqs, emps] = await Promise.all([getLeaveRequests(statusFilter || undefined), getEmployees()])
      setRequests(reqs || [])
      setEmployees(emps || [])
    } catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [statusFilter])

  useEffect(() => { loadData() }, [loadData])

  async function handleApprove(id: string) {
  try { await updateLeaveRequest(id, { status: 'approved', approved_at: new Date().toISOString() } as any); await loadData() }
    catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
  }

  async function handleReject(id: string) {
    try { await updateLeaveRequest(id, { status: 'rejected' }); await loadData() }
    catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
  }

  async function handleDelete(id: string) {
    if (!window.confirm(tCommon('form.confirmDelete'))) return
    try { await deleteLeaveRequest(id); await loadData() }
    catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.hr') }, { label: t('leaveRequests.title') }]} />
      <PageHeader title={t('leaveRequests.title')} subtitle={t('leaveRequests.subtitle')}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('leaveRequests.new')}</Button>} />

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-48">
          <Select label={t('leaveRequests.status')} value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} options={[
            { value: '', label: tCommon('table.all') }, { value: 'pending', label: t('leaveRequests.statuses.pending') }, { value: 'approved', label: t('leaveRequests.statuses.approved') },
            { value: 'rejected', label: t('leaveRequests.statuses.rejected') }, { value: 'cancelled', label: t('leaveRequests.statuses.cancelled') },
          ]} />
        </div>
      </div>

      {loading ? <SkeletonTable rows={5} cols={6} /> : requests.length === 0 ? (
        <EmptyState icon={<CalendarDays className="w-8 h-8" />} title={t('leaveRequests.noRequests')} description={t('leaveRequests.noRequestsDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('leaveRequests.new')}</Button>} />
      ) : (
        <Card>
          <Table headers={[t('leaveRequests.employee'), t('leaveRequests.type'), t('leaveRequests.startDate'), t('leaveRequests.endDate'), t('leaveRequests.days'), t('leaveRequests.reason'), t('leaveRequests.status'), tCommon('table.actions')]}>
            {requests.map((r) => (
              <TableRow key={r.id}>
                <TableCell className="text-sm">{r.employees?.name || '—'}</TableCell>
                <TableCell className="text-xs">{t(`leaveRequests.types.${r.leave_type}`) || typeLabels[r.leave_type] || r.leave_type}</TableCell>
                <TableCell className="text-xs">{formatDate(r.start_date)}</TableCell>
                <TableCell className="text-xs">{formatDate(r.end_date)}</TableCell>
                <TableCell className="font-mono text-xs">{Number(r.days)}</TableCell>
                <TableCell className="text-xs">{r.reason || '—'}</TableCell>
                <TableCell><Badge variant={statusBadge[r.status] || 'neutral'}>{t(`leaveRequests.statuses.${r.status}`) || statusLabels[r.status] || r.status}</Badge></TableCell>
                <TableCell>
                  <div className="flex gap-1">
                    {r.status === 'pending' && (
                      <>
                        <button onClick={() => handleApprove(r.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-success)]" title={t('leaveRequests.approve')}><Check className="w-4 h-4" /></button>
                        <button onClick={() => handleReject(r.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" title={t('leaveRequests.reject')}><XCircle className="w-4 h-4" /></button>
                      </>
                    )}
                    <button onClick={() => handleDelete(r.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && <LeaveForm employees={employees} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function LeaveForm({ employees, onClose, onSaved }: { employees: Employee[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const [employeeId, setEmployeeId] = useState('')
  const { toast } = useToast()
  const [leaveType, setLeaveType] = useState('annual')
  const [startDate, setStartDate] = useState(new Date().toISOString().split('T')[0])
  const [endDate, setEndDate] = useState(new Date().toISOString().split('T')[0])
  const [reason, setReason] = useState('')
  const [saving, setSaving] = useState(false)

  const days = Math.ceil((new Date(endDate).getTime() - new Date(startDate).getTime()) / (1000 * 60 * 60 * 24)) + 1

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await createLeaveRequest({ employee_id: employeeId, leave_type: leaveType as any, start_date: startDate, end_date: endDate, days, status: 'pending', reason: reason || null } as any)
      onSaved()
    } catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('leaveRequests.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('leaveRequests.employee')}</label>
            <select className="input" value={employeeId} onChange={(e) => setEmployeeId(e.target.value)} required>
              <option value="">{tCommon('form.selectPlaceholder') || '—'}</option>
              {employees.map((emp) => <option key={emp.id} value={emp.id}>{emp.name}</option>)}
            </select>
          </div>
          <Select label={t('leaveRequests.type')} value={leaveType} onChange={(e) => setLeaveType(e.target.value)} options={[
            { value: 'annual', label: t('leaveRequests.types.annual') }, { value: 'sick', label: t('leaveRequests.types.sick') }, { value: 'maternity', label: t('leaveRequests.types.maternity') },
            { value: 'paternity', label: t('leaveRequests.types.paternity') }, { value: 'unpaid', label: t('leaveRequests.types.unpaid') }, { value: 'other', label: t('leaveRequests.types.other') },
          ]} />
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('leaveRequests.startDate')} type="date" required value={startDate} onChange={(e) => setStartDate(e.target.value)} />
            <Input label={t('leaveRequests.endDate')} type="date" required value={endDate} onChange={(e) => setEndDate(e.target.value)} />
          </div>
          <div className="text-sm text-[var(--color-text-secondary)]">{t('leaveRequests.days')}: <span className="font-bold">{days > 0 ? days : 0}</span></div>
          <Input label={t('leaveRequests.reason')} value={reason} onChange={(e) => setReason(e.target.value)} />
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
