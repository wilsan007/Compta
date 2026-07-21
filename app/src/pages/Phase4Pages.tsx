import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input } from '@/components/ui'
import { useToast } from '@/lib/toast'
import { useLocale } from '@/hooks/useLocale'
import { Plus, Trash2 } from 'lucide-react'
import {
  getPayrollComponents, createPayrollComponent, deletePayrollComponent,
  getPayrollTemplates, createPayrollTemplate, deletePayrollTemplate,
  getSalaryAdvances, createSalaryAdvance, updateSalaryAdvance,
  getPayRecalls, createPayRecall,
  getDsnDeclarations, createDsnDeclaration, updateDsnDeclaration,
  getDpaeRecords, createDpaeRecord,
  getPayrollArchives,
  getLegalWatch, createLegalWatch, updateLegalWatch,
  getExpenseReports, createExpenseReport, updateExpenseReport,
  getInterviews, createInterview, updateInterview,
} from '@/lib/queries'

// ============ Payroll Components Page ============
export function PayrollComponentsPage() {
  const { t } = useTranslation('payroll')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ code: '', name: '', type: 'gross' as const, calculation_type: 'fixed' as const, default_value: 0, rate_employer: 0, rate_employee: 0, display_order: 100, active: true })

  const loadData = useCallback(async () => { setLoading(true); try { setItems(await getPayrollComponents() || []) } catch { } finally { setLoading(false) } }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() { try { await createPayrollComponent(form as any); toast('success', tCommon('common.success'), t('components.created')); setShowForm(false); setForm({ code: '', name: '', type: 'gross', calculation_type: 'fixed', default_value: 0, rate_employer: 0, rate_employee: 0, display_order: 100, active: true }); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }
  async function handleDelete(id: string) { if (!window.confirm(tCommon('common.confirmDelete'))) return; try { await deletePayrollComponent(id); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }

  return (
    <div>
      <Breadcrumb items={[{ label: t('components.breadcrumb1'), path: '/payroll' }, { label: t('components.title') }]} />
      <PageHeader title={t('components.title')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('components.new')}</Button>} />
      {showForm && (<Card className="p-4 mb-4 space-y-3"><div className="grid grid-cols-2 gap-3"><Input placeholder={t('components.code')} value={form.code} onChange={e => setForm({ ...form, code: e.target.value })} /><Input placeholder={t('components.name')} value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} /><select className="border rounded px-3 py-2" value={form.type} onChange={e => setForm({ ...form, type: e.target.value as any })}><option value="gross">{t('components.types.gross')}</option><option value="deduction">{t('components.types.deduction')}</option><option value="contribution">{t('components.types.contribution')}</option><option value="tax">{t('components.types.tax')}</option><option value="net">{t('components.types.net')}</option><option value="benefit">{t('components.types.benefit')}</option></select><select className="border rounded px-3 py-2" value={form.calculation_type} onChange={e => setForm({ ...form, calculation_type: e.target.value as any })}><option value="fixed">{t('components.calcTypes.fixed')}</option><option value="percentage">{t('components.calcTypes.percentage')}</option><option value="formula">{t('components.calcTypes.formula')}</option><option value="bracket">{t('components.calcTypes.bracket')}</option></select><Input type="number" placeholder={t('components.rateEmployer')} value={form.rate_employer} onChange={e => setForm({ ...form, rate_employer: parseFloat(e.target.value) || 0 })} /><Input type="number" placeholder={t('components.rateEmployee')} value={form.rate_employee} onChange={e => setForm({ ...form, rate_employee: parseFloat(e.target.value) || 0 })} /></div><div className="flex gap-2"><Button onClick={handleCreate}>{tCommon('common.save')}</Button><Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button></div></Card>)}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('components.empty')} /> : (
        <Table headers={[t('components.code'), t('components.name'), t('components.type'), t('components.calcType'), t('components.active'), t('common.actions')]}>
          {items.map(c => (<TableRow key={c.id}><TableCell>{c.code}</TableCell><TableCell>{c.name}</TableCell><TableCell>{t(`components.types.${c.type}`)}</TableCell><TableCell>{t(`components.calcTypes.${c.calculation_type}`)}</TableCell><TableCell>{c.active ? <Badge>{tCommon('common.yes')}</Badge> : <Badge>{tCommon('common.no')}</Badge>}</TableCell><TableCell><Button size="sm" variant="danger" onClick={() => handleDelete(c.id)}><Trash2 className="w-4 h-4" /></Button></TableCell></TableRow>))}
        </Table>
      )}
    </div>
  )
}

// ============ Payroll Templates Page ============
export function PayrollTemplatesPage() {
  const { t } = useTranslation('payroll')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ name: '', category: 'standard' as const, description: '', active: true })

  const loadData = useCallback(async () => { setLoading(true); try { setItems(await getPayrollTemplates() || []) } catch { } finally { setLoading(false) } }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() { try { await createPayrollTemplate(form as any); toast('success', tCommon('common.success'), t('templates.created')); setShowForm(false); setForm({ name: '', category: 'standard', description: '', active: true }); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }
  async function handleDelete(id: string) { if (!window.confirm(tCommon('common.confirmDelete'))) return; try { await deletePayrollTemplate(id); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }

  return (
    <div>
      <Breadcrumb items={[{ label: t('templates.breadcrumb1'), path: '/payroll' }, { label: t('templates.title') }]} />
      <PageHeader title={t('templates.title')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('templates.new')}</Button>} />
      {showForm && (<Card className="p-4 mb-4 space-y-3"><div className="grid grid-cols-2 gap-3"><Input placeholder={t('templates.name')} value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} /><select className="border rounded px-3 py-2" value={form.category} onChange={e => setForm({ ...form, category: e.target.value as any })}><option value="standard">{t('templates.categories.standard')}</option><option value="cadre">{t('templates.categories.cadre')}</option><option value="non_cadre">{t('templates.categories.non_cadre')}</option><option value="apprenti">{t('templates.categories.apprenti')}</option><option value="stagiaire">{t('templates.categories.stagiaire')}</option></select></div><div className="flex gap-2"><Button onClick={handleCreate}>{tCommon('common.save')}</Button><Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button></div></Card>)}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('templates.empty')} /> : (
        <Table headers={[t('templates.name'), t('templates.category'), t('common.actions')]}>
          {items.map(tpl => (<TableRow key={tpl.id}><TableCell>{tpl.name}</TableCell><TableCell>{t(`templates.categories.${tpl.category}`)}</TableCell><TableCell><Button size="sm" variant="danger" onClick={() => handleDelete(tpl.id)}><Trash2 className="w-4 h-4" /></Button></TableCell></TableRow>))}
        </Table>
      )}
    </div>
  )
}

// ============ Salary Advances Page ============
export function SalaryAdvancesPage() {
  const { t } = useTranslation('payroll')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatCurrency } = useLocale()
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ employee_id: '', amount: 0, advance_date: '', deduction_month: '', notes: '' })

  const loadData = useCallback(async () => { setLoading(true); try { setItems(await getSalaryAdvances() || []) } catch { } finally { setLoading(false) } }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() { try { await createSalaryAdvance(form as any); toast('success', tCommon('common.success'), t('advances.created')); setShowForm(false); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }
  async function handleDeduct(id: string) { try { await updateSalaryAdvance(id, { status: 'deducted' }); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }

  return (
    <div>
      <Breadcrumb items={[{ label: t('advances.breadcrumb1'), path: '/payroll' }, { label: t('advances.title') }]} />
      <PageHeader title={t('advances.title')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('advances.new')}</Button>} />
      {showForm && (<Card className="p-4 mb-4 space-y-3"><div className="grid grid-cols-2 gap-3"><Input placeholder={t('advances.employeeId')} value={form.employee_id} onChange={e => setForm({ ...form, employee_id: e.target.value })} /><Input type="number" placeholder={t('advances.amount')} value={form.amount} onChange={e => setForm({ ...form, amount: parseFloat(e.target.value) || 0 })} /><Input type="date" value={form.advance_date} onChange={e => setForm({ ...form, advance_date: e.target.value })} /></div><div className="flex gap-2"><Button onClick={handleCreate}>{tCommon('common.save')}</Button><Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button></div></Card>)}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('advances.empty')} /> : (
        <Table headers={[t('advances.employee'), t('advances.amount'), t('advances.date'), t('advances.status'), t('common.actions')]}>
          {items.map(a => (<TableRow key={a.id}><TableCell>{a.employees ? `${a.employees.first_name} ${a.employees.last_name}` : '-'}</TableCell><TableCell>{formatCurrency(a.amount)}</TableCell><TableCell>{a.advance_date}</TableCell><TableCell><Badge>{t(`advances.statuses.${a.status}`)}</Badge></TableCell><TableCell>{a.status === 'pending' && <Button size="sm" variant="secondary" onClick={() => handleDeduct(a.id)}>{t('advances.deduct')}</Button>}</TableCell></TableRow>))}
        </Table>
      )}
    </div>
  )
}

// ============ DSN Page ============
export function DSNPage() {
  const { t } = useTranslation('payroll')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ period: '', type: 'mensuelle' as const })

  const loadData = useCallback(async () => { setLoading(true); try { setItems(await getDsnDeclarations() || []) } catch { } finally { setLoading(false) } }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() { try { await createDsnDeclaration(form as any); toast('success', tCommon('common.success'), t('dsn.created')); setShowForm(false); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }
  async function handleTransmit(id: string) { try { await updateDsnDeclaration(id, { status: 'transmitted', transmitted_at: new Date().toISOString() }); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }

  return (
    <div>
      <Breadcrumb items={[{ label: t('dsn.breadcrumb1'), path: '/payroll' }, { label: t('dsn.title') }]} />
      <PageHeader title={t('dsn.title')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('dsn.new')}</Button>} />
      {showForm && (<Card className="p-4 mb-4 space-y-3"><div className="grid grid-cols-2 gap-3"><Input placeholder={t('dsn.period')} value={form.period} onChange={e => setForm({ ...form, period: e.target.value })} /><select className="border rounded px-3 py-2" value={form.type} onChange={e => setForm({ ...form, type: e.target.value as any })}><option value="mensuelle">{t('dsn.types.mensuelle')}</option><option value="arret">{t('dsn.types.arret')}</option><option value="reprise">{t('dsn.types.reprise')}</option><option value="fin_contrat">{t('dsn.types.fin_contrat')}</option></select></div><div className="flex gap-2"><Button onClick={handleCreate}>{tCommon('common.save')}</Button><Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button></div></Card>)}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('dsn.empty')} /> : (
        <Table headers={[t('dsn.period'), t('dsn.type'), t('dsn.status'), t('common.actions')]}>
          {items.map(d => (<TableRow key={d.id}><TableCell>{d.period}</TableCell><TableCell>{t(`dsn.types.${d.type}`)}</TableCell><TableCell><Badge>{t(`dsn.statuses.${d.status}`)}</Badge></TableCell><TableCell>{d.status === 'generated' && <Button size="sm" variant="secondary" onClick={() => handleTransmit(d.id)}>{t('dsn.transmit')}</Button>}</TableCell></TableRow>))}
        </Table>
      )}
    </div>
  )
}

// ============ DPAE Page ============
export function DPAEPage() {
  const { t } = useTranslation('payroll')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ employee_id: '', hire_date: '', contract_type: '', position: '' })

  const loadData = useCallback(async () => { setLoading(true); try { setItems(await getDpaeRecords() || []) } catch { } finally { setLoading(false) } }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() { try { await createDpaeRecord(form as any); toast('success', tCommon('common.success'), t('dpae.created')); setShowForm(false); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }

  return (
    <div>
      <Breadcrumb items={[{ label: t('dpae.breadcrumb1'), path: '/payroll' }, { label: t('dpae.title') }]} />
      <PageHeader title={t('dpae.title')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('dpae.new')}</Button>} />
      {showForm && (<Card className="p-4 mb-4 space-y-3"><div className="grid grid-cols-2 gap-3"><Input placeholder={t('dpae.employeeId')} value={form.employee_id} onChange={e => setForm({ ...form, employee_id: e.target.value })} /><Input type="date" value={form.hire_date} onChange={e => setForm({ ...form, hire_date: e.target.value })} /><Input placeholder={t('dpae.contractType')} value={form.contract_type} onChange={e => setForm({ ...form, contract_type: e.target.value })} /><Input placeholder={t('dpae.position')} value={form.position} onChange={e => setForm({ ...form, position: e.target.value })} /></div><div className="flex gap-2"><Button onClick={handleCreate}>{tCommon('common.save')}</Button><Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button></div></Card>)}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('dpae.empty')} /> : (
        <Table headers={[t('dpae.employee'), t('dpae.hireDate'), t('dpae.contractType'), t('dpae.status')]}>
          {items.map(d => (<TableRow key={d.id}><TableCell>{d.employees ? `${d.employees.first_name} ${d.employees.last_name}` : '-'}</TableCell><TableCell>{d.hire_date}</TableCell><TableCell>{d.contract_type || '-'}</TableCell><TableCell><Badge>{t(`dpae.statuses.${d.status}`)}</Badge></TableCell></TableRow>))}
        </Table>
      )}
    </div>
  )
}

// ============ Legal Watch Page ============
export function LegalWatchPage() {
  const { t } = useTranslation('payroll')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ title: '', category: '', source: '', summary: '', content_url: '', published_date: '', relevance: 'info' as const })

  const loadData = useCallback(async () => { setLoading(true); try { setItems(await getLegalWatch() || []) } catch { } finally { setLoading(false) } }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() { try { await createLegalWatch(form as any); toast('success', tCommon('common.success'), t('legalWatch.created')); setShowForm(false); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }
  async function handleRead(id: string) { try { await updateLegalWatch(id, { read: true }); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }

  return (
    <div>
      <Breadcrumb items={[{ label: t('legalWatch.breadcrumb1'), path: '/payroll' }, { label: t('legalWatch.title') }]} />
      <PageHeader title={t('legalWatch.title')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('legalWatch.new')}</Button>} />
      {showForm && (<Card className="p-4 mb-4 space-y-3"><div className="grid grid-cols-2 gap-3"><Input placeholder={t('legalWatch.title')} value={form.title} onChange={e => setForm({ ...form, title: e.target.value })} /><Input placeholder={t('legalWatch.category')} value={form.category} onChange={e => setForm({ ...form, category: e.target.value })} /><Input placeholder={t('legalWatch.source')} value={form.source} onChange={e => setForm({ ...form, source: e.target.value })} /><Input type="date" value={form.published_date} onChange={e => setForm({ ...form, published_date: e.target.value })} /></div><div className="flex gap-2"><Button onClick={handleCreate}>{tCommon('common.save')}</Button><Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button></div></Card>)}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('legalWatch.empty')} /> : (
        <Table headers={[t('legalWatch.title'), t('legalWatch.category'), t('legalWatch.date'), t('legalWatch.relevance'), t('common.actions')]}>
          {items.map(l => (<TableRow key={l.id}><TableCell>{l.title}</TableCell><TableCell>{l.category || '-'}</TableCell><TableCell>{l.published_date || '-'}</TableCell><TableCell><Badge>{t(`legalWatch.relevance.${l.relevance}`)}</Badge></TableCell><TableCell>{!l.read && <Button size="sm" variant="secondary" onClick={() => handleRead(l.id)}>{t('legalWatch.markRead')}</Button>}</TableCell></TableRow>))}
        </Table>
      )}
    </div>
  )
}

// ============ Expense Reports Page ============
export function ExpenseReportsPage() {
  const { t } = useTranslation('payroll')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatCurrency } = useLocale()
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ employee_id: '', number: '', period: '', total_amount: 0, notes: '' })

  const loadData = useCallback(async () => { setLoading(true); try { setItems(await getExpenseReports() || []) } catch { } finally { setLoading(false) } }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() { try { await createExpenseReport(form as any); toast('success', tCommon('common.success'), t('expenseReports.created')); setShowForm(false); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }
  async function handleApprove(id: string) { try { await updateExpenseReport(id, { status: 'approved', approved_at: new Date().toISOString() }); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }

  return (
    <div>
      <Breadcrumb items={[{ label: t('expenseReports.breadcrumb1'), path: '/payroll' }, { label: t('expenseReports.title') }]} />
      <PageHeader title={t('expenseReports.title')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('expenseReports.new')}</Button>} />
      {showForm && (<Card className="p-4 mb-4 space-y-3"><div className="grid grid-cols-2 gap-3"><Input placeholder={t('expenseReports.employeeId')} value={form.employee_id} onChange={e => setForm({ ...form, employee_id: e.target.value })} /><Input placeholder={t('expenseReports.number')} value={form.number} onChange={e => setForm({ ...form, number: e.target.value })} /><Input type="number" placeholder={t('expenseReports.amount')} value={form.total_amount} onChange={e => setForm({ ...form, total_amount: parseFloat(e.target.value) || 0 })} /></div><div className="flex gap-2"><Button onClick={handleCreate}>{tCommon('common.save')}</Button><Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button></div></Card>)}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('expenseReports.empty')} /> : (
        <Table headers={[t('expenseReports.number'), t('expenseReports.employee'), t('expenseReports.amount'), t('expenseReports.status'), t('common.actions')]}>
          {items.map(e => (<TableRow key={e.id}><TableCell>{e.number}</TableCell><TableCell>{e.employees ? `${e.employees.first_name} ${e.employees.last_name}` : '-'}</TableCell><TableCell>{formatCurrency(e.total_amount)}</TableCell><TableCell><Badge>{t(`expenseReports.statuses.${e.status}`)}</Badge></TableCell><TableCell>{e.status === 'submitted' && <Button size="sm" variant="secondary" onClick={() => handleApprove(e.id)}>{t('expenseReports.approve')}</Button>}</TableCell></TableRow>))}
        </Table>
      )}
    </div>
  )
}

// ============ Pay Recalls Page ============
export function PayRecallsPage() {
  const { t } = useTranslation('payroll')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatCurrency } = useLocale()
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ employee_id: '', reference_period: '', recall_amount: 0, reason: '' })

  const loadData = useCallback(async () => { setLoading(true); try { setItems(await getPayRecalls() || []) } catch { } finally { setLoading(false) } }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() { try { await createPayRecall(form as any); toast('success', tCommon('common.success'), t('recalls.created')); setShowForm(false); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }

  return (
    <div>
      <Breadcrumb items={[{ label: t('recalls.breadcrumb1'), path: '/payroll' }, { label: t('recalls.title') }]} />
      <PageHeader title={t('recalls.title')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('recalls.new')}</Button>} />
      {showForm && (<Card className="p-4 mb-4 space-y-3"><div className="grid grid-cols-2 gap-3"><Input placeholder={t('recalls.employeeId')} value={form.employee_id} onChange={e => setForm({ ...form, employee_id: e.target.value })} /><Input placeholder={t('recalls.period')} value={form.reference_period} onChange={e => setForm({ ...form, reference_period: e.target.value })} /><Input type="number" placeholder={t('recalls.amount')} value={form.recall_amount} onChange={e => setForm({ ...form, recall_amount: parseFloat(e.target.value) || 0 })} /></div><div className="flex gap-2"><Button onClick={handleCreate}>{tCommon('common.save')}</Button><Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button></div></Card>)}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('recalls.empty')} /> : (
        <Table headers={[t('recalls.employee'), t('recalls.period'), t('recalls.amount'), t('recalls.status')]}>
          {items.map(r => (<TableRow key={r.id}><TableCell>{r.employees ? `${r.employees.first_name} ${r.employees.last_name}` : '-'}</TableCell><TableCell>{r.reference_period}</TableCell><TableCell>{formatCurrency(r.recall_amount)}</TableCell><TableCell><Badge>{t(`recalls.statuses.${r.status}`)}</Badge></TableCell></TableRow>))}
        </Table>
      )}
    </div>
  )
}

// ============ Payroll Archives Page ============
export function PayrollArchivePage() {
  const { t } = useTranslation('payroll')
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)

  const loadData = useCallback(async () => { setLoading(true); try { setItems(await getPayrollArchives() || []) } catch { } finally { setLoading(false) } }, [])
  useEffect(() => { loadData() }, [loadData])

  return (
    <div>
      <Breadcrumb items={[{ label: t('archives.breadcrumb1'), path: '/payroll' }, { label: t('archives.title') }]} />
      <PageHeader title={t('archives.title')} />
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('archives.empty')} /> : (
        <Table headers={[t('archives.employee'), t('archives.period'), t('archives.type'), t('archives.retention')]}>
          {items.map(a => (<TableRow key={a.id}><TableCell>{a.employees ? `${a.employees.first_name} ${a.employees.last_name}` : '-'}</TableCell><TableCell>{a.period}</TableCell><TableCell>{t(`archives.types.${a.archive_type}`)}</TableCell><TableCell>{a.retention_until || '-'}</TableCell></TableRow>))}
        </Table>
      )}
    </div>
  )
}

// ============ Interviews Page ============
export function InterviewsPage() {
  const { t } = useTranslation('payroll')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ employee_id: '', type: 'annual' as const, scheduled_date: '', objectives: '' })

  const loadData = useCallback(async () => { setLoading(true); try { setItems(await getInterviews() || []) } catch { } finally { setLoading(false) } }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() { try { await createInterview(form as any); toast('success', tCommon('common.success'), t('interviews.created')); setShowForm(false); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }
  async function handleConduct(id: string) { try { await updateInterview(id, { status: 'conducted', conducted_at: new Date().toISOString() }); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }

  return (
    <div>
      <Breadcrumb items={[{ label: t('interviews.breadcrumb1'), path: '/payroll' }, { label: t('interviews.title') }]} />
      <PageHeader title={t('interviews.title')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('interviews.new')}</Button>} />
      {showForm && (<Card className="p-4 mb-4 space-y-3"><div className="grid grid-cols-2 gap-3"><Input placeholder={t('interviews.employeeId')} value={form.employee_id} onChange={e => setForm({ ...form, employee_id: e.target.value })} /><select className="border rounded px-3 py-2" value={form.type} onChange={e => setForm({ ...form, type: e.target.value as any })}><option value="annual">{t('interviews.types.annual')}</option><option value="mid_year">{t('interviews.types.mid_year')}</option><option value="professional">{t('interviews.types.professional')}</option><option value="exit">{t('interviews.types.exit')}</option></select><Input type="date" value={form.scheduled_date} onChange={e => setForm({ ...form, scheduled_date: e.target.value })} /></div><div className="flex gap-2"><Button onClick={handleCreate}>{tCommon('common.save')}</Button><Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button></div></Card>)}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('interviews.empty')} /> : (
        <Table headers={[t('interviews.employee'), t('interviews.type'), t('interviews.date'), t('interviews.status'), t('common.actions')]}>
          {items.map(i => (<TableRow key={i.id}><TableCell>{i.employees ? `${i.employees.first_name} ${i.employees.last_name}` : '-'}</TableCell><TableCell>{t(`interviews.types.${i.type}`)}</TableCell><TableCell>{i.scheduled_date || '-'}</TableCell><TableCell><Badge>{t(`interviews.statuses.${i.status}`)}</Badge></TableCell><TableCell>{i.status === 'scheduled' && <Button size="sm" variant="secondary" onClick={() => handleConduct(i.id)}>{t('interviews.conduct')}</Button>}</TableCell></TableRow>))}
        </Table>
      )}
    </div>
  )
}
