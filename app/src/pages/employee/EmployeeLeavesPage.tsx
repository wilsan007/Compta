import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, SkeletonTable, Badge, Breadcrumb, Input, Select } from '@/components/ui'
import { Plus, X } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { getTenantId } from '@/lib/queries/core'
import { formatDate } from '@/lib/utils'
import { useToast } from '@/lib/toast'

export function EmployeeLeavesPage() {
  const { t } = useTranslation('employee')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const { toast } = useToast()
  const [tab, setTab] = useState<'requests' | 'balance' | 'planning'>('requests')
  const [requests, setRequests] = useState<any[]>([])
  const [balances, setBalances] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [leaveType, setLeaveType] = useState('')
  const [startDate, setStartDate] = useState('')
  const [endDate, setEndDate] = useState('')
  const [halfDay, setHalfDay] = useState(false)
  const [justification, setJustification] = useState('')

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const { data: { session } } = await supabase.auth.getSession()
      const userEmail = session?.user?.email
      if (!userEmail) return
      const { data: emp, error } = await supabase.from('employees').select('id').eq('email', userEmail).single()
      if (error) throw error
      if (!emp?.id) return
      const tid = await getTenantId()
      let rq = supabase.from('leave_requests').select('*').eq('employee_id', emp.id)
      if (tid) rq = rq.eq('tenant_id', tid)
      const { data: reqs } = await rq.order('created_at', { ascending: false })
      let bq = supabase.from('leave_balances').select('*').eq('employee_id', emp.id)
      if (tid) bq = bq.eq('tenant_id', tid)
      const { data: bals } = await bq
      setRequests(reqs || [])
      setBalances(bals || [])
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setLoading(false) }
  }, [toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    try {
      const { data: { session } } = await supabase.auth.getSession()
      const userEmail = session?.user?.email
      const { data: emp, error: empError } = await supabase.from('employees').select('id').eq('email', userEmail).single()
      if (empError) throw empError
      if (!emp?.id) return
      const tid = await getTenantId()
      const { error } = await supabase.from('leave_requests').insert({
        tenant_id: tid,
        employee_id: emp.id,
        leave_type: leaveType,
        start_date: startDate,
        end_date: endDate,
        half_day: halfDay,
        justification,
        status: 'pending',
      })
      if (error) throw error
      toast('success', tCommon('common.success'), tCommon('common.saved'))
      setShowForm(false)
      setLeaveType(''); setStartDate(''); setEndDate(''); setHalfDay(false); setJustification('')
      loadData().catch(err => console.error('loadData:', err))
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    }
  }

  async function handleCancel(id: string) {
    try {
      const tid = await getTenantId()
      const { error } = await supabase.from('leave_requests').update({ status: 'cancelled' }).eq('id', id).eq('tenant_id', tid)
      if (error) throw error
      toast('success', tCommon('common.success'), tCommon('common.saved'))
      loadData().catch(err => console.error('loadData:', err))
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    }
  }

  const statusBadge = (status: string) => {
    const variant = status === 'approved' ? 'success' : status === 'rejected' ? 'danger' : status === 'cancelled' ? 'neutral' : 'warning'
    return <Badge variant={variant as any}>{t(`leaves.status.${status}`)}</Badge>
  }

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.hr') }, { label: t('leaves.title') }]} />
      <PageHeader
        title={t('leaves.title')}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('leaves.newRequest')}</Button>}
      />

      <div className="flex gap-2 mb-4">
        <Button variant={tab === 'requests' ? 'primary' : 'ghost'} onClick={() => setTab('requests')}>{t('leaves.myRequests')}</Button>
        <Button variant={tab === 'balance' ? 'primary' : 'ghost'} onClick={() => setTab('balance')}>{t('leaves.myBalance')}</Button>
        <Button variant={tab === 'planning' ? 'primary' : 'ghost'} onClick={() => setTab('planning')}>{t('leaves.planning')}</Button>
      </div>

      {showForm && (
        <Card className="mb-4">
          <form onSubmit={handleSubmit} className="p-4 space-y-3">
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div>
                <label className="text-xs text-[var(--color-text-secondary)]">{t('leaves.leaveType')}</label>
                <Select value={leaveType} onChange={e => setLeaveType(e.target.value)} required options={[
                  { value: '', label: '--' },
                  { value: 'annual', label: t('leaves.types.annual') },
                  { value: 'rtt', label: t('leaves.types.rtt') },
                  { value: 'recovery', label: t('leaves.types.recovery') },
                  { value: 'sick', label: t('leaves.types.sick') },
                  { value: 'unpaid', label: t('leaves.types.unpaid') },
                  { value: 'special', label: t('leaves.types.special') },
                ]} />
              </div>
              <div>
                <label className="text-xs text-[var(--color-text-secondary)]">{t('leaves.startDate')}</label>
                <Input type="date" value={startDate} onChange={e => setStartDate(e.target.value)} required />
              </div>
              <div>
                <label className="text-xs text-[var(--color-text-secondary)]">{t('leaves.endDate')}</label>
                <Input type="date" value={endDate} onChange={e => setEndDate(e.target.value)} required />
              </div>
              <div className="flex items-center gap-2 pt-4">
                <input type="checkbox" id="halfDay" checked={halfDay} onChange={e => setHalfDay(e.target.checked)} />
                <label htmlFor="halfDay" className="text-sm">{t('leaves.halfDay')}</label>
              </div>
            </div>
            <div>
              <label className="text-xs text-[var(--color-text-secondary)]">{t('leaves.justification')}</label>
              <Input value={justification} onChange={e => setJustification(e.target.value)} />
            </div>
            <div className="flex gap-2">
              <Button type="submit">{tCommon('common.confirm')}</Button>
              <Button type="button" variant="ghost" onClick={() => setShowForm(false)}><X className="w-4 h-4" /> {tCommon('common.cancel')}</Button>
            </div>
          </form>
        </Card>
      )}

      {loading ? <SkeletonTable rows={5} cols={5} /> : tab === 'requests' ? (
        <Card>
          <Table headers={[t('leaves.leaveType'), t('leaves.startDate'), t('leaves.endDate'), t('leaves.status'), tCommon('table.actions')]}>
            {requests.map(r => (
              <TableRow key={r.id}>
                <TableCell className="text-sm">{t(`leaves.types.${r.leave_type}`) || r.leave_type}</TableCell>
                <TableCell className="text-xs">{formatDate(r.start_date)}</TableCell>
                <TableCell className="text-xs">{formatDate(r.end_date)}</TableCell>
                <TableCell>{statusBadge(r.status)}</TableCell>
                <TableCell>
                  {r.status === 'pending' && <Button size="sm" variant="danger" onClick={() => handleCancel(r.id)}>{t('leaves.cancel')}</Button>}
                </TableCell>
              </TableRow>
            ))}
            {requests.length === 0 && <TableRow><TableCell colSpan={5} className="text-center text-[var(--color-text-secondary)] text-sm">{t('leaves.noRequests')}</TableCell></TableRow>}
          </Table>
        </Card>
      ) : tab === 'balance' ? (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {balances.map(b => (
            <Card key={b.id}>
              <div className="p-4">
                <p className="text-sm font-medium mb-2">{t(`leaves.types.${b.leave_type}`) || b.leave_type}</p>
                <div className="grid grid-cols-2 gap-2 text-sm">
                  <div><span className="text-[var(--color-text-secondary)]">{t('leaves.acquired')}: </span><span className="font-mono">{b.acquired_days}</span></div>
                  <div><span className="text-[var(--color-text-secondary)]">{t('leaves.taken')}: </span><span className="font-mono">{b.taken_days}</span></div>
                  <div><span className="text-[var(--color-text-secondary)]">{t('leaves.pending')}: </span><span className="font-mono">{b.pending_days}</span></div>
                  <div><span className="text-[var(--color-text-secondary)]">{t('leaves.remaining')}: </span><span className="font-mono font-bold">{b.current_balance}</span></div>
                </div>
              </div>
            </Card>
          ))}
          {balances.length === 0 && <EmptyState title={t('leaves.noRequests')} />}
        </div>
      ) : (
        <Card>
          <div className="p-8 text-center text-[var(--color-text-secondary)]">{t('leaves.planning')} — {t('leaves.noRequests')}</div>
        </Card>
      )}
    </div>
  )
}
