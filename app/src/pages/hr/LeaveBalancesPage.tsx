import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Select } from '@/components/ui'
import { formatCurrency } from '@/lib/utils'
import { getLeaveBalances, initializeYearLeaveBalances, carryOverLeaveBalances, getLeaveProvisions, calculateLeaveProvisions, postLeaveProvisions } from '@/lib/queries/leavesAbsences'
import { getEmployees } from '@/lib/queries/payroll'
import { calculateLeaveAcquisition } from '@/lib/queries/businessFunctions'
import type { LeaveBalance, LeaveProvision, Employee } from '@/types'
import { useToast } from '@/lib/toast'
import { Scale, Calendar, RefreshCw, CheckCircle, Wallet } from 'lucide-react'

type Tab = 'balances' | 'provisions'

export function LeaveBalancesPage() {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const { toast } = useToast()
  const [tab, setTab] = useState<Tab>('balances')
  const [balances, setBalances] = useState<LeaveBalance[]>([])
  const [provisions, setProvisions] = useState<LeaveProvision[]>([])
  const [employees, setEmployees] = useState<Employee[]>([])
  const [loading, setLoading] = useState(true)
  const [year, setYear] = useState(new Date().getFullYear())
  const [period, setPeriod] = useState('')

  const loadData = useCallback(async () => {
    try {
      const [bals, emps] = await Promise.all([getLeaveBalances(undefined, year), getEmployees()])
      setBalances(bals || [])
      setEmployees(emps || [])
      if (tab === 'provisions') {
        const provs = await getLeaveProvisions(period || undefined)
        setProvisions(provs || [])
      }
    } catch (err: any) { console.error(err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadingError')) }
    finally { setLoading(false) }
  }, [year, tab, period, toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  async function handleInitYear() {
    try {
      await initializeYearLeaveBalances(year)
      toast('success', tCommon('common.success'), t('leaveBalances.yearInitialized'))
      await loadData()
    } catch (err: any) { toast('error', tCommon('common.error'), err.message) }
  }

  async function handleCarryOver() {
    try {
      for (const emp of employees) {
        await carryOverLeaveBalances(emp.id, year - 1, year)
      }
      toast('success', tCommon('common.success'), t('leaveBalances.carryOverDone'))
      await loadData()
    } catch (err: any) { toast('error', tCommon('common.error'), err.message) }
  }

  async function handleCalcProvisions() {
    if (!period) { toast('error', tCommon('common.error'), t('leaveBalances.selectPeriod')); return }
    try {
      const results = await calculateLeaveProvisions(period)
      setProvisions(results)
      toast('success', tCommon('common.success'), t('leaveBalances.provisionsCalculated'))
    } catch (err: any) { toast('error', tCommon('common.error'), err.message) }
  }

  async function handlePostProvisions() {
    try {
      await postLeaveProvisions(period)
      toast('success', tCommon('common.success'), t('leaveBalances.provisionsPosted'))
      await loadData()
    } catch (err: any) { toast('error', tCommon('common.error'), err.message) }
  }

  async function handleCalcAcquisition() {
    try {
      const targets = employees.length > 0 ? employees : []
      if (targets.length === 0) { toast('error', tCommon('common.error'), t('leaveBalances.noBalances')); return }
      let totalDays = 0
      for (const emp of targets) {
        const res = await calculateLeaveAcquisition(emp.id, year)
        totalDays += Number(res) || 0
      }
      toast('success', tCommon('common.success'), `${'Droits acquis calculés'} — ${totalDays.toFixed(2)} j (2,5/mois)`)
      await loadData()
    } catch (err: any) { toast('error', tCommon('common.error'), err.message) }
  }

  const empName = (id: string) => employees.find((e) => e.id === id)?.name || '—'
  const groupedByEmp = balances.reduce((acc, b) => {
    if (!acc[b.employee_id]) acc[b.employee_id] = []
    acc[b.employee_id].push(b)
    return acc
  }, {} as Record<string, LeaveBalance[]>)

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('groups.hr') }, { label: t('leaveBalances.title') }]} />
      <PageHeader title={t('leaveBalances.title')} subtitle={t('leaveBalances.subtitle')} />

      <div className="flex gap-2 mb-4 border-b border-[var(--color-border)]">
        {([
          { key: 'balances', label: t('leaveBalances.tabs.balances'), icon: <Scale className="w-4 h-4" /> },
          { key: 'provisions', label: t('leaveBalances.tabs.provisions'), icon: <Wallet className="w-4 h-4" /> },
        ] as { key: Tab; label: string; icon: React.ReactNode }[]).map((tb) => (
          <button key={tb.key} onClick={() => setTab(tb.key)}
            className={`flex items-center gap-2 px-4 py-2 text-sm font-medium border-b-2 transition-colors ${
              tab === tb.key ? 'border-[var(--color-primary)] text-[var(--color-primary)]' : 'border-transparent text-[var(--color-text-secondary)] hover:text-[var(--color-text)]'
            }`}>
            {tb.icon} {tb.label}
          </button>
        ))}
      </div>

      {tab === 'balances' && (
        <div>
          <div className="flex justify-between items-end mb-3">
            <div className="flex gap-3 items-end">
              <div className="w-32">
                <Select label={t('leaveBalances.year')} value={String(year)} onChange={(e) => setYear(Number(e.target.value))} options={[
                  { value: String(new Date().getFullYear() + 1), label: String(new Date().getFullYear() + 1) },
                  { value: String(new Date().getFullYear()), label: String(new Date().getFullYear()) },
                  { value: String(new Date().getFullYear() - 1), label: String(new Date().getFullYear() - 1) },
                ]} />
              </div>
              <Button variant="secondary" onClick={handleInitYear}><Calendar className="w-4 h-4" /> {t('leaveBalances.initYear')}</Button>
              <Button variant="secondary" onClick={handleCarryOver}><RefreshCw className="w-4 h-4" /> {t('leaveBalances.carryOverBtn')}</Button>
              <Button variant="secondary" onClick={handleCalcAcquisition}><RefreshCw className="w-4 h-4" /> Calculer les droits acquis</Button>
            </div>
          </div>
          {loading ? <SkeletonTable rows={5} cols={7} /> : Object.keys(groupedByEmp).length === 0 ? (
            <EmptyState icon={<Scale className="w-8 h-8" />} title={t('leaveBalances.noBalances')} description={t('leaveBalances.noBalancesDescription')} />
          ) : (
            <Card>
              <Table headers={[
                t('leaveBalances.employee'), t('leaveBalances.type'), t('leaveBalances.acquired'),
                t('leaveBalances.taken'), t('leaveBalances.pending'), t('leaveBalances.remaining'),
                t('leaveBalances.carryOver'),
              ]}>
                {Object.entries(groupedByEmp).map(([empId, empBalances]) =>
                  empBalances.map((b, idx) => (
                    <TableRow key={b.id}>
                      <TableCell className="text-sm font-medium">{idx === 0 ? empName(empId) : ''}</TableCell>
                      <TableCell className="text-xs"><Badge variant="neutral">{b.leave_type}</Badge></TableCell>
                      <TableCell className="font-mono text-xs">{Number(b.acquired).toFixed(2)}</TableCell>
                      <TableCell className="font-mono text-xs">{Number(b.taken).toFixed(2)}</TableCell>
                      <TableCell className="font-mono text-xs">{Number(b.pending).toFixed(2)}</TableCell>
                      <TableCell className="font-mono text-xs font-bold">{Number(b.remaining).toFixed(2)}</TableCell>
                      <TableCell className="font-mono text-xs">{Number(b.carry_over).toFixed(2)}</TableCell>
                    </TableRow>
                  ))
                )}
              </Table>
            </Card>
          )}
        </div>
      )}

      {tab === 'provisions' && (
        <div>
          <div className="flex justify-between items-end mb-3">
            <div className="w-40">
              <Select label={t('leaveBalances.period')} value={period} onChange={(e) => setPeriod(e.target.value)} options={[
                ...Array.from({ length: 12 }, (_, i) => {
                  const m = String(i + 1).padStart(2, '0')
                  return { value: `${year}-${m}`, label: `${year}-${m}` }
                }),
              ]} />
            </div>
            <div className="flex gap-2">
              <Button onClick={handleCalcProvisions}><RefreshCw className="w-4 h-4" /> {t('leaveBalances.calculate')}</Button>
              <Button variant="secondary" onClick={handlePostProvisions} disabled={provisions.length === 0}><CheckCircle className="w-4 h-4" /> {t('leaveBalances.post')}</Button>
            </div>
          </div>
          {loading ? <SkeletonTable rows={4} cols={7} /> : provisions.length === 0 ? (
            <EmptyState icon={<Wallet className="w-8 h-8" />} title={t('leaveBalances.noProvisions')} description={t('leaveBalances.noProvisionsDescription')} />
          ) : (
            <Card>
              <Table headers={[
                t('leaveBalances.employee'), t('leaveBalances.cpDays'), t('leaveBalances.dailyRate'),
                t('leaveBalances.cpProvision'), t('leaveBalances.rttProvision'), t('leaveBalances.recoveryProvision'),
                t('leaveBalances.total'),
              ]}>
                {provisions.map((p) => (
                  <TableRow key={p.id}>
                    <TableCell className="text-sm">{empName(p.employee_id)}</TableCell>
                    <TableCell className="font-mono text-xs">{Number(p.cp_remaining_days).toFixed(2)}</TableCell>
                    <TableCell className="font-mono text-xs">{formatCurrency(Number(p.daily_rate))}</TableCell>
                    <TableCell className="font-mono text-xs">{formatCurrency(Number(p.cp_provision))}</TableCell>
                    <TableCell className="font-mono text-xs">{formatCurrency(Number(p.rtt_provision))}</TableCell>
                    <TableCell className="font-mono text-xs">{formatCurrency(Number(p.recovery_provision))}</TableCell>
                    <TableCell className="font-mono text-xs font-bold">{formatCurrency(Number(p.total_provision))}</TableCell>
                  </TableRow>
                ))}
              </Table>
            </Card>
          )}
        </div>
      )}
    </div>
  )
}
