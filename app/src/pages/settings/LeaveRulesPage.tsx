import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { formatDate } from '@/lib/utils'
import {
  getLeaveRules, createLeaveRule, updateLeaveRule, deleteLeaveRule,
  getPublicHolidays, createPublicHoliday, deletePublicHoliday,
  getApprovalWorkflows, createApprovalWorkflow, updateApprovalWorkflow,
  getStaffRequirements, createStaffRequirement, updateStaffRequirement,
} from '@/lib/queries'
import type { LeaveRule, PublicHoliday, ApprovalWorkflow, StaffRequirement } from '@/types'
import { useToast } from '@/lib/toast'
import { Settings, Plus, Trash2, X, Calendar, Workflow, Users, CalendarDays } from 'lucide-react'

type Tab = 'rules' | 'holidays' | 'workflows' | 'staff'

export function LeaveRulesPage() {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const [tab, setTab] = useState<Tab>('rules')

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.hr') }, { label: t('leaveRules.title') }]} />
      <PageHeader title={t('leaveRules.title')} subtitle={t('leaveRules.subtitle')} />

      <div className="flex gap-2 mb-4 border-b border-[var(--color-border)]">
        {([
          { key: 'rules', label: t('leaveRules.tabs.rules'), icon: <Settings className="w-4 h-4" /> },
          { key: 'holidays', label: t('leaveRules.tabs.holidays'), icon: <CalendarDays className="w-4 h-4" /> },
          { key: 'workflows', label: t('leaveRules.tabs.workflows'), icon: <Workflow className="w-4 h-4" /> },
          { key: 'staff', label: t('leaveRules.tabs.staff'), icon: <Users className="w-4 h-4" /> },
        ] as { key: Tab; label: string; icon: React.ReactNode }[]).map((tb) => (
          <button
            key={tb.key}
            onClick={() => setTab(tb.key)}
            className={`flex items-center gap-2 px-4 py-2 text-sm font-medium border-b-2 transition-colors ${
              tab === tb.key
                ? 'border-[var(--color-primary)] text-[var(--color-primary)]'
                : 'border-transparent text-[var(--color-text-secondary)] hover:text-[var(--color-text)]'
            }`}
          >
            {tb.icon}
            {tb.label}
          </button>
        ))}
      </div>

      {tab === 'rules' && <RulesTab />}
      {tab === 'holidays' && <HolidaysTab />}
      {tab === 'workflows' && <WorkflowsTab />}
      {tab === 'staff' && <StaffTab />}
    </div>
  )
}

function RulesTab() {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [rules, setRules] = useState<LeaveRule[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<LeaveRule | null>(null)

  const loadData = useCallback(async () => {
    try {
      const data = await getLeaveRules()
      setRules(data || [])
    } catch (err: any) { console.error(err) }
    finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
    if (!window.confirm(tCommon('form.confirmDelete'))) return
    try { await deleteLeaveRule(id); await loadData() }
    catch (err: any) { toast('error', tCommon('common.error'), err.message) }
  }

  return (
    <div>
      <div className="flex justify-end mb-3">
        <Button onClick={() => { setEditing(null); setShowForm(true) }}><Plus className="w-4 h-4" /> {t('leaveRules.new')}</Button>
      </div>
      {loading ? <SkeletonTable rows={4} cols={8} /> : rules.length === 0 ? (
        <EmptyState icon={<Settings className="w-8 h-8" />} title={t('leaveRules.noRules')} description={t('leaveRules.noRulesDescription')} />
      ) : (
        <Card>
          <Table headers={[
            t('leaveRules.leaveType'), t('leaveRules.label'), t('leaveRules.accrualRate'),
            t('leaveRules.maxCarryOver'), t('leaveRules.minNotice'), t('leaveRules.maxConsecutive'),
            t('leaveRules.countMethod'), t('leaveRules.active'), tCommon('table.actions'),
          ]}>
            {rules.map((r) => (
              <TableRow key={r.id}>
                <TableCell className="text-xs font-mono">{r.leave_type}</TableCell>
                <TableCell className="text-sm">{r.label}</TableCell>
                <TableCell className="font-mono text-xs">{Number(r.accrual_rate)}</TableCell>
                <TableCell className="font-mono text-xs">{Number(r.max_carry_over)}</TableCell>
                <TableCell className="font-mono text-xs">{r.min_notice_days}</TableCell>
                <TableCell className="font-mono text-xs">{r.max_consecutive_days}</TableCell>
                <TableCell className="text-xs">{t(`leaveRules.countMethods.${r.count_method}`) || r.count_method}</TableCell>
                <TableCell><Badge variant={r.active ? 'success' : 'neutral'}>{r.active ? tCommon('common.yes') : tCommon('common.no')}</Badge></TableCell>
                <TableCell>
                  <div className="flex gap-1">
                    <button onClick={() => { setEditing(r); setShowForm(true) }} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)]">✎</button>
                    <button onClick={() => handleDelete(r.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}
      {showForm && <RuleForm rule={editing} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function RuleForm({ rule, onClose, onSaved }: { rule: LeaveRule | null; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [leaveType, setLeaveType] = useState(rule?.leave_type || 'annual')
  const [label, setLabel] = useState(rule?.label || '')
  const [accrualRate, setAccrualRate] = useState(String(rule?.accrual_rate ?? 2.08))
  const [maxCarryOver, setMaxCarryOver] = useState(String(rule?.max_carry_over ?? 0))
  const [minNotice, setMinNotice] = useState(String(rule?.min_notice_days ?? 7))
  const [maxConsecutive, setMaxConsecutive] = useState(String(rule?.max_consecutive_days ?? 30))
  const [countMethod, setCountMethod] = useState(rule?.count_method || 'working_days')
  const [color, setColor] = useState(rule?.color || '#3b82f6')
  const [active, setActive] = useState(rule?.active ?? true)
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault(); setSaving(true)
    try {
      const data = { leave_type: leaveType, label, accrual_rate: Number(accrualRate), max_carry_over: Number(maxCarryOver), min_notice_days: Number(minNotice), max_consecutive_days: Number(maxConsecutive), count_method: countMethod as any, color, active }
      if (rule) await updateLeaveRule(rule.id, data)
      else await createLeaveRule(data as any)
      onSaved()
    } catch (err: any) { toast('error', tCommon('common.error'), err.message) }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{rule ? t('leaveRules.edit') : t('leaveRules.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Select label={t('leaveRules.leaveType')} value={leaveType} onChange={(e) => setLeaveType(e.target.value)} options={[
            { value: 'annual', label: t('leaveRequests.types.annual') }, { value: 'rtt', label: 'RTT' }, { value: 'recovery', label: t('leaveRules.types.recovery') },
            { value: 'sick', label: t('leaveRequests.types.sick') }, { value: 'unpaid', label: t('leaveRequests.types.unpaid') },
            { value: 'maternity', label: t('leaveRequests.types.maternity') }, { value: 'paternity', label: t('leaveRequests.types.paternity') },
            { value: 'special', label: t('leaveRules.types.special') },
          ]} />
          <Input label={t('leaveRules.label')} required value={label} onChange={(e) => setLabel(e.target.value)} />
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('leaveRules.accrualRate')} type="number" step="0.01" required value={accrualRate} onChange={(e) => setAccrualRate(e.target.value)} />
            <Input label={t('leaveRules.maxCarryOver')} type="number" step="0.01" value={maxCarryOver} onChange={(e) => setMaxCarryOver(e.target.value)} />
            <Input label={t('leaveRules.minNotice')} type="number" value={minNotice} onChange={(e) => setMinNotice(e.target.value)} />
            <Input label={t('leaveRules.maxConsecutive')} type="number" value={maxConsecutive} onChange={(e) => setMaxConsecutive(e.target.value)} />
          </div>
          <Select label={t('leaveRules.countMethod')} value={countMethod} onChange={(e) => setCountMethod(e.target.value)} options={[
            { value: 'working_days', label: t('leaveRules.countMethods.working_days') },
            { value: 'working_days_excl_saturday', label: t('leaveRules.countMethods.working_days_excl_saturday') },
            { value: 'calendar_days', label: t('leaveRules.countMethods.calendar_days') },
          ]} />
          <div className="flex items-center gap-4">
            <div>
              <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('leaveRules.color')}</label>
              <input type="color" value={color} onChange={(e) => setColor(e.target.value)} className="w-12 h-10 rounded border border-[var(--color-border)]" />
            </div>
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={active} onChange={(e) => setActive(e.target.checked)} />
              {t('leaveRules.active')}
            </label>
          </div>
          <div className="flex justify-end gap-3 pt-2 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}

function HolidaysTab() {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [holidays, setHolidays] = useState<PublicHoliday[]>([])
  const [loading, setLoading] = useState(true)
  const [year, setYear] = useState(new Date().getFullYear())
  const [showForm, setShowForm] = useState(false)

  const loadData = useCallback(async () => {
    try {
      const data = await getPublicHolidays(year)
      setHolidays(data || [])
    } catch (err: any) { console.error(err) }
    finally { setLoading(false) }
  }, [year])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
    if (!window.confirm(tCommon('form.confirmDelete'))) return
    try { await deletePublicHoliday(id); await loadData() }
    catch (err: any) { toast('error', tCommon('common.error'), err.message) }
  }

  return (
    <div>
      <div className="flex justify-between items-end mb-3">
        <div className="w-32">
          <Input label={t('leaveRules.year')} type="number" value={String(year)} onChange={(e) => setYear(Number(e.target.value))} />
        </div>
        <Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('leaveRules.newHoliday')}</Button>
      </div>
      {loading ? <SkeletonTable rows={5} cols={5} /> : holidays.length === 0 ? (
        <EmptyState icon={<CalendarDays className="w-8 h-8" />} title={t('leaveRules.noHolidays')} description={t('leaveRules.noHolidaysDescription')} />
      ) : (
        <Card>
          <Table headers={[t('leaveRules.holidayName'), t('leaveRules.holidayDate'), t('leaveRules.region'), t('leaveRules.country'), tCommon('table.actions')]}>
            {holidays.map((h) => (
              <TableRow key={h.id}>
                <TableCell className="text-sm">{h.name}</TableCell>
                <TableCell className="text-xs">{formatDate(h.holiday_date)}</TableCell>
                <TableCell className="text-xs">{h.region}</TableCell>
                <TableCell className="text-xs">{h.country}</TableCell>
                <TableCell>
                  <button onClick={() => handleDelete(h.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}
      {showForm && <HolidayForm onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function HolidayForm({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [name, setName] = useState('')
  const [date, setDate] = useState(new Date().toISOString().split('T')[0])
  const [region, setRegion] = useState('national')
  const [country, setCountry] = useState('FR')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault(); setSaving(true)
    try {
      await createPublicHoliday({ name, holiday_date: date, region, country, is_working_day: false } as any)
      onSaved()
    } catch (err: any) { toast('error', tCommon('common.error'), err.message) }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('leaveRules.newHoliday')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label={t('leaveRules.holidayName')} required value={name} onChange={(e) => setName(e.target.value)} />
          <Input label={t('leaveRules.holidayDate')} type="date" required value={date} onChange={(e) => setDate(e.target.value)} />
          <Select label={t('leaveRules.region')} value={region} onChange={(e) => setRegion(e.target.value)} options={[
            { value: 'national', label: 'National' }, { value: 'alsace-moselle', label: 'Alsace-Moselle' },
            { value: 'guadeloupe', label: 'Guadeloupe' }, { value: 'martinique', label: 'Martinique' },
            { value: 'guyane', label: 'Guyane' }, { value: 'reunion', label: 'Réunion' },
            { value: 'mayotte', label: 'Mayotte' }, { value: 'custom', label: t('leaveRules.customRegion') },
          ]} />
          <Input label={t('leaveRules.country')} value={country} onChange={(e) => setCountry(e.target.value)} />
          <div className="flex justify-end gap-3 pt-2 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}

function WorkflowsTab() {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [workflows, setWorkflows] = useState<ApprovalWorkflow[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)

  const loadData = useCallback(async () => {
    try {
      const data = await getApprovalWorkflows()
      setWorkflows(data || [])
    } catch (err: any) { console.error(err) }
    finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  return (
    <div>
      <div className="flex justify-end mb-3">
        <Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('leaveRules.newWorkflow')}</Button>
      </div>
      {loading ? <SkeletonTable rows={3} cols={4} /> : workflows.length === 0 ? (
        <EmptyState icon={<Workflow className="w-8 h-8" />} title={t('leaveRules.noWorkflows')} description={t('leaveRules.noWorkflowsDescription')} />
      ) : (
        <Card>
          <Table headers={[t('leaveRules.workflowName'), t('leaveRules.entityType'), t('leaveRules.steps'), t('leaveRules.active')]}>
            {workflows.map((w) => (
              <TableRow key={w.id}>
                <TableCell className="text-sm">{w.name}</TableCell>
                <TableCell className="text-xs">{w.entity_type}</TableCell>
                <TableCell className="text-xs">{(w.steps || []).map((s: any) => `${s.order}.${s.role}`).join(' → ')}</TableCell>
                <TableCell><Badge variant={w.active ? 'success' : 'neutral'}>{w.active ? tCommon('common.yes') : tCommon('common.no')}</Badge></TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}
      {showForm && <WorkflowForm onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function WorkflowForm({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [name, setName] = useState('')
  const [entityType, setEntityType] = useState('leave_request')
  const [stepsJson, setStepsJson] = useState('[{"role":"manager","order":1},{"role":"hr","order":2}]')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault(); setSaving(true)
    try {
      const steps = JSON.parse(stepsJson)
      await createApprovalWorkflow({ name, entity_type: entityType as any, steps, active: true } as any)
      onSaved()
    } catch (err: any) { toast('error', tCommon('common.error'), err.message) }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('leaveRules.newWorkflow')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label={t('leaveRules.workflowName')} required value={name} onChange={(e) => setName(e.target.value)} />
          <Select label={t('leaveRules.entityType')} value={entityType} onChange={(e) => setEntityType(e.target.value)} options={[
            { value: 'leave_request', label: t('leaveRules.entityTypes.leave_request') },
            { value: 'expense_report', label: t('leaveRules.entityTypes.expense_report') },
            { value: 'timesheet', label: t('leaveRules.entityTypes.timesheet') },
          ]} />
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('leaveRules.stepsJson')}</label>
            <textarea className="input font-mono text-xs" rows={4} value={stepsJson} onChange={(e) => setStepsJson(e.target.value)} />
          </div>
          <div className="flex justify-end gap-3 pt-2 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}

function StaffTab() {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [reqs, setReqs] = useState<StaffRequirement[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)

  const loadData = useCallback(async () => {
    try {
      const data = await getStaffRequirements()
      setReqs(data || [])
    } catch (err: any) { console.error(err) }
    finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleToggle(id: string, active: boolean) {
    try { await updateStaffRequirement(id, { active: !active }); await loadData() }
    catch (err: any) { toast('error', tCommon('common.error'), err.message) }
  }

  return (
    <div>
      <div className="flex justify-end mb-3">
        <Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('leaveRules.newStaffReq')}</Button>
      </div>
      {loading ? <SkeletonTable rows={3} cols={5} /> : reqs.length === 0 ? (
        <EmptyState icon={<Users className="w-8 h-8" />} title={t('leaveRules.noStaffReqs')} description={t('leaveRules.noStaffReqsDescription')} />
      ) : (
        <Card>
          <Table headers={[t('leaveRules.department'), t('leaveRules.minStaff'), t('leaveRules.daysOfWeek'), t('leaveRules.active'), tCommon('table.actions')]}>
            {reqs.map((r) => (
              <TableRow key={r.id}>
                <TableCell className="text-sm">{r.department}</TableCell>
                <TableCell className="font-mono text-xs">{r.min_staff}</TableCell>
                <TableCell className="text-xs">{(r.days_of_week || []).join(', ')}</TableCell>
                <TableCell><Badge variant={r.active ? 'success' : 'neutral'}>{r.active ? tCommon('common.yes') : tCommon('common.no')}</Badge></TableCell>
                <TableCell>
                  <button onClick={() => handleToggle(r.id, r.active)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)]">✓</button>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}
      {showForm && <StaffForm onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function StaffForm({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [department, setDepartment] = useState('')
  const [minStaff, setMinStaff] = useState('1')
  const [daysOfWeek, setDaysOfWeek] = useState('1,2,3,4,5')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault(); setSaving(true)
    try {
      await createStaffRequirement({ department, min_staff: Number(minStaff), days_of_week: daysOfWeek.split(','), active: true } as any)
      onSaved()
    } catch (err: any) { toast('error', tCommon('common.error'), err.message) }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('leaveRules.newStaffReq')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label={t('leaveRules.department')} required value={department} onChange={(e) => setDepartment(e.target.value)} />
          <Input label={t('leaveRules.minStaff')} type="number" required value={minStaff} onChange={(e) => setMinStaff(e.target.value)} />
          <Input label={t('leaveRules.daysOfWeek')} value={daysOfWeek} onChange={(e) => setDaysOfWeek(e.target.value)} />
          <div className="flex justify-end gap-3 pt-2 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
