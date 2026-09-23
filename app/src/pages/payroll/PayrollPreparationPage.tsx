import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Select, Input } from '@/components/ui'
import { formatCurrency } from '@/lib/utils'
import { getPayRuns, getEmployees, getPayrollComponents } from '@/lib/queries/payroll'
import { getVariableElements, createVariableElement, deleteVariableElement, importTimesheetElements, importLeaveElements, importExpenseElements, generateMealVoucherElements, calculateGrossFromNet } from '@/lib/queries/leavesAbsences'
import { calculateOvertimePay, calculateSickLeavePay } from '@/lib/queries/businessFunctions'
import type { PayRun, Employee, PayrollVariableElement, PayrollComponent } from '@/types'
import { useToast } from '@/lib/toast'
import { Wand2, Plus, Trash2, X, ArrowRight, ArrowLeft, Calculator, Upload } from 'lucide-react'
import { confirmSync } from '@/lib/confirm'

type Step = 1 | 2 | 3 | 4 | 5

export function PayrollPreparationPage() {
  const { t } = useTranslation('payroll')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const { toast } = useToast()
  const [step, setStep] = useState<Step>(1)
  const [payRuns, setPayRuns] = useState<PayRun[]>([])
  const [employees, setEmployees] = useState<Employee[]>([])
  const [components, setComponents] = useState<PayrollComponent[]>([])
  const [selectedPayRun, setSelectedPayRun] = useState('')
  const [variableElements, setVariableElements] = useState<PayrollVariableElement[]>([])
  const [loading, setLoading] = useState(true)
  const [showAddElement, setShowAddElement] = useState(false)
  const [showReverseCalc, setShowReverseCalc] = useState(false)
  const [showOvertimeCalc, setShowOvertimeCalc] = useState(false)
  const [showSickLeaveCalc, setShowSickLeaveCalc] = useState(false)

  const loadData = useCallback(async () => {
    try {
      const [runs, emps, comps] = await Promise.all([getPayRuns(), getEmployees(), getPayrollComponents()])
      setPayRuns(runs || [])
      setEmployees(emps || [])
      setComponents(comps || [])
    } catch (err: any) { console.error(err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadingError')) }
    finally { setLoading(false) }
  }, [toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  const loadVariableElements = useCallback(async () => {
    if (!selectedPayRun) return
    try {
      const els = await getVariableElements(selectedPayRun)
      setVariableElements(els || [])
    } catch (err: any) { console.error(err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadingError')) }
  }, [selectedPayRun, tCommon, toast])

  useEffect(() => { loadVariableElements() }, [loadVariableElements])

  const activeEmployees = employees.filter((e) => e.status === 'active')
  const empName = (id: string) => employees.find((e) => e.id === id)?.name || '—'

  const selectedRun = payRuns.find((r) => r.id === selectedPayRun)
  const period = selectedRun ? `${selectedRun.period_start} - ${selectedRun.period_end}` : ''

  async function handleImport(source: 'timesheet' | 'leave' | 'expense' | 'meal') {
    if (!selectedPayRun) return
    try {
      const date = new Date(selectedRun?.period_start || new Date())
      const month = date.getMonth() + 1
      const year = date.getFullYear()
      switch (source) {
        case 'timesheet': await importTimesheetElements(selectedPayRun, month, year); break
        case 'leave': await importLeaveElements(selectedPayRun, month, year); break
        case 'expense': await importExpenseElements(selectedPayRun, month, year); break
        case 'meal': await generateMealVoucherElements(selectedPayRun, month, year); break
      }
      await loadVariableElements()
      toast('success', tCommon('common.success'), t('preparation.imported'))
    } catch (err: any) { toast('error', tCommon('common.error'), err.message) }
  }

  async function handleDeleteElement(id: string) {
    if (!confirmSync(tCommon('form.confirmDelete'))) return
    try { await deleteVariableElement(id); await loadVariableElements() }
    catch (err: any) { toast('error', tCommon('common.error'), err.message) }
  }

  const totalVariable = variableElements.reduce((s, e) => s + Number(e.amount), 0)

  const steps = [
    { num: 1, label: t('preparation.steps.period') },
    { num: 2, label: t('preparation.steps.constants') },
    { num: 3, label: t('preparation.steps.variables') },
    { num: 4, label: t('preparation.steps.preview') },
    { num: 5, label: t('preparation.steps.validate') },
  ]

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('groups.hr') }, { label: t('preparation.title') }]} />
      <PageHeader title={t('preparation.title')} subtitle={t('preparation.subtitle')} />

      <div className="flex items-center gap-1 mb-6 overflow-x-auto">
        {steps.map((s, idx) => (
          <div key={s.num} className="flex items-center">
            <div className={`flex items-center gap-2 px-3 py-2 rounded-lg text-sm font-medium ${
              step === s.num ? 'bg-[var(--color-primary)] text-white' :
              step > s.num ? 'bg-[var(--color-success)] text-white' : 'bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]'
            }`}>
              <span className="w-6 h-6 rounded-full flex items-center justify-center text-xs">
                {step > s.num ? '✓' : s.num}
              </span>
              {s.label}
            </div>
            {idx < steps.length - 1 && <ArrowRight className="w-4 h-4 mx-1 text-[var(--color-text-secondary)]" />}
          </div>
        ))}
      </div>

      {loading ? <SkeletonTable rows={4} cols={5} /> : (
        <>
          {step === 1 && (
            <Card className="p-6">
              <h3 className="text-lg font-semibold mb-4">{t('preparation.steps.period')}</h3>
              <Select label={t('preparation.selectPayRun')} value={selectedPayRun} onChange={(e) => setSelectedPayRun(e.target.value)} options={[
                { value: '', label: t('preparation.selectPayRun') },
                ...payRuns.map((r) => ({ value: r.id, label: `${r.number} — ${r.period_start} → ${r.period_end}` })),
              ]} />
              <div className="flex justify-end mt-4">
                <Button onClick={() => setStep(2)} disabled={!selectedPayRun}>
                  {t('preparation.next')} <ArrowRight className="w-4 h-4" />
                </Button>
              </div>
            </Card>
          )}

          {step === 2 && (
            <Card className="p-6">
              <h3 className="text-lg font-semibold mb-4">{t('preparation.steps.constants')}</h3>
              <div className="grid grid-cols-3 gap-4 mb-4">
                <div className="p-4 rounded-lg bg-[var(--color-neutral-50)]">
                  <div className="text-xs text-[var(--color-text-secondary)]">{t('preparation.activeEmployees')}</div>
                  <div className="text-2xl font-bold">{activeEmployees.length}</div>
                </div>
                <div className="p-4 rounded-lg bg-[var(--color-neutral-50)]">
                  <div className="text-xs text-[var(--color-text-secondary)]">{t('preparation.grossTotal')}</div>
                  <div className="text-2xl font-bold">{formatCurrency(selectedRun?.gross_total || 0)}</div>
                </div>
                <div className="p-4 rounded-lg bg-[var(--color-neutral-50)]">
                  <div className="text-xs text-[var(--color-text-secondary)]">{t('preparation.netTotal')}</div>
                  <div className="text-2xl font-bold">{formatCurrency(selectedRun?.net_total || 0)}</div>
                </div>
              </div>
              <div className="flex items-center gap-2 mb-4">
                <Button variant="secondary" onClick={() => setShowReverseCalc(true)}>
                  <Calculator className="w-4 h-4" /> {t('preparation.reverseCalc')}
                </Button>
                <Button variant="secondary" onClick={() => setShowOvertimeCalc(true)}>
                  <Calculator className="w-4 h-4" /> Calculer les heures sup
                </Button>
                <Button variant="secondary" onClick={() => setShowSickLeaveCalc(true)}>
                  <Calculator className="w-4 h-4" /> Calculer les IJSS
                </Button>
              </div>
              <div className="flex justify-between">
                <Button variant="secondary" onClick={() => setStep(1)}><ArrowLeft className="w-4 h-4" /> {t('preparation.prev')}</Button>
                <Button onClick={() => setStep(3)}>{t('preparation.next')} <ArrowRight className="w-4 h-4" /></Button>
              </div>
            </Card>
          )}

          {step === 3 && (
            <div>
              <div className="flex justify-between items-end mb-3">
                <div className="flex gap-2">
                  <Button variant="secondary" onClick={() => handleImport('timesheet')}><Upload className="w-4 h-4" /> {t('preparation.importTimesheet')}</Button>
                  <Button variant="secondary" onClick={() => handleImport('leave')}><Upload className="w-4 h-4" /> {t('preparation.importLeaves')}</Button>
                  <Button variant="secondary" onClick={() => handleImport('expense')}><Upload className="w-4 h-4" /> {t('preparation.importExpenses')}</Button>
                  <Button variant="secondary" onClick={() => handleImport('meal')}><Upload className="w-4 h-4" /> {t('preparation.importMealVouchers')}</Button>
                </div>
                <Button onClick={() => setShowAddElement(true)}><Plus className="w-4 h-4" /> {t('preparation.addElement')}</Button>
              </div>
              {variableElements.length === 0 ? (
                <EmptyState icon={<Wand2 className="w-8 h-8" />} title={t('preparation.noElements')} description={t('preparation.noElementsDescription')} />
              ) : (
                <Card>
                  <Table headers={[t('preparation.employee'), t('preparation.type'), t('preparation.description'), t('preparation.amount'), tCommon('table.actions')]}>
                    {variableElements.map((e) => (
                      <TableRow key={e.id}>
                        <TableCell className="text-sm">{empName(e.employee_id)}</TableCell>
                        <TableCell className="text-xs"><Badge variant="neutral">{t(`preparation.elementTypes.${e.element_type}`)}</Badge></TableCell>
                        <TableCell className="text-xs">{e.description || '—'}</TableCell>
                        <TableCell className="font-mono text-xs">{formatCurrency(Number(e.amount))}</TableCell>
                        <TableCell>
                          <button onClick={() => handleDeleteElement(e.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" aria-label={tCommon('actions.delete')} title={tCommon('actions.delete')}><Trash2 className="w-4 h-4" aria-hidden="true" /></button>
                        </TableCell>
                      </TableRow>
                    ))}
                  </Table>
                </Card>
              )}
              <div className="flex justify-between mt-4">
                <Button variant="secondary" onClick={() => setStep(2)}><ArrowLeft className="w-4 h-4" /> {t('preparation.prev')}</Button>
                <Button onClick={() => setStep(4)}>{t('preparation.next')} <ArrowRight className="w-4 h-4" /></Button>
              </div>
            </div>
          )}

          {step === 4 && (
            <Card className="p-6">
              <h3 className="text-lg font-semibold mb-4">{t('preparation.steps.preview')}</h3>
              <div className="grid grid-cols-3 gap-4 mb-4">
                <div className="p-4 rounded-lg bg-[var(--color-neutral-50)]">
                  <div className="text-xs text-[var(--color-text-secondary)]">{t('preparation.grossTotal')}</div>
                  <div className="text-xl font-bold">{formatCurrency(selectedRun?.gross_total || 0)}</div>
                </div>
                <div className="p-4 rounded-lg bg-[var(--color-neutral-50)]">
                  <div className="text-xs text-[var(--color-text-secondary)]">{t('preparation.variableTotal')}</div>
                  <div className="text-xl font-bold">{formatCurrency(totalVariable)}</div>
                </div>
                <div className="p-4 rounded-lg bg-[var(--color-neutral-50)]">
                  <div className="text-xs text-[var(--color-text-secondary)]">{t('preparation.estimatedTotal')}</div>
                  <div className="text-xl font-bold">{formatCurrency((selectedRun?.gross_total || 0) + totalVariable)}</div>
                </div>
              </div>
              <div className="flex justify-between">
                <Button variant="secondary" onClick={() => setStep(3)}><ArrowLeft className="w-4 h-4" /> {t('preparation.prev')}</Button>
                <Button onClick={() => setStep(5)}>{t('preparation.next')} <ArrowRight className="w-4 h-4" /></Button>
              </div>
            </Card>
          )}

          {step === 5 && (
            <Card className="p-6 text-center">
              <h3 className="text-lg font-semibold mb-4">{t('preparation.steps.validate')}</h3>
              <p className="text-sm text-[var(--color-text-secondary)] mb-4">{t('preparation.validateHint')}</p>
              <div className="flex justify-center gap-3">
                <Button variant="secondary" onClick={() => setStep(4)}><ArrowLeft className="w-4 h-4" /> {t('preparation.prev')}</Button>
                <Button onClick={() => toast('success', tCommon('common.success'), t('preparation.validated'))}>
                  <Calculator className="w-4 h-4" /> {t('preparation.validate')}
                </Button>
              </div>
            </Card>
          )}
        </>
      )}

      {showAddElement && (
        <AddElementModal
          employees={activeEmployees}
          payRunId={selectedPayRun}
          period={period}
          onClose={() => setShowAddElement(false)}
          onSaved={() => { setShowAddElement(false); loadVariableElements() }}
        />
      )}

      {showReverseCalc && (
        <ReverseCalcModal
          components={components}
          employees={activeEmployees}
          onClose={() => setShowReverseCalc(false)}
        />
      )}

      {showOvertimeCalc && (
        <OvertimeCalcModal
          employees={activeEmployees}
          onClose={() => setShowOvertimeCalc(false)}
        />
      )}

      {showSickLeaveCalc && (
        <SickLeaveCalcModal
          employees={activeEmployees}
          onClose={() => setShowSickLeaveCalc(false)}
        />
      )}
    </div>
  )
}

function AddElementModal({ employees, payRunId, period, onClose, onSaved }: {
  employees: Employee[]; payRunId: string; period: string; onClose: () => void; onSaved: () => void
}) {
  const { t } = useTranslation('payroll')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [employeeId, setEmployeeId] = useState('')
  const [elementType, setElementType] = useState('overtime')
  const [description, setDescription] = useState('')
  const [quantity, setQuantity] = useState('')
  const [unitPrice, setUnitPrice] = useState('')
  const [amount, setAmount] = useState('0')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault(); setSaving(true)
    try {
      await createVariableElement({
        employee_id: employeeId, pay_run_id: payRunId, period,
        element_type: elementType as any, description,
        quantity: quantity ? Number(quantity) : null,
        unit_price: unitPrice ? Number(unitPrice) : null,
        amount: Number(amount), source: 'manual', source_id: null, integrated: false,
      } as any)
      onSaved()
    } catch (err: any) { toast('error', tCommon('common.error'), err.message) }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('preparation.addElement')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Select label={t('preparation.employee')} required value={employeeId} onChange={(e) => setEmployeeId(e.target.value)} options={[
            { value: '', label: '—' },
            ...employees.map((e) => ({ value: e.id, label: e.name })),
          ]} />
          <Select label={t('preparation.type')} value={elementType} onChange={(e) => setElementType(e.target.value)} options={[
            { value: 'overtime', label: t('preparation.elementTypes.overtime') },
            { value: 'bonus', label: t('preparation.elementTypes.bonus') },
            { value: 'commission', label: t('preparation.elementTypes.commission') },
            { value: 'absence', label: t('preparation.elementTypes.absence') },
            { value: 'meal_voucher', label: t('preparation.elementTypes.meal_voucher') },
            { value: 'transport', label: t('preparation.elementTypes.transport') },
            { value: 'advance_deduction', label: t('preparation.elementTypes.advance_deduction') },
            { value: 'pay_recall', label: t('preparation.elementTypes.pay_recall') },
            { value: 'expense_reimbursement', label: t('preparation.elementTypes.expense_reimbursement') },
            { value: 'unpaid_leave_deduction', label: t('preparation.elementTypes.unpaid_leave_deduction') },
            { value: 'lateness_deduction', label: t('preparation.elementTypes.lateness_deduction') },
            { value: 'other', label: t('preparation.elementTypes.other') },
          ]} />
          <Input label={t('preparation.description')} value={description} onChange={(e) => setDescription(e.target.value)} />
          <div className="grid grid-cols-3 gap-4">
            <Input label={t('preparation.quantity')} type="number" step="0.01" value={quantity} onChange={(e) => setQuantity(e.target.value)} />
            <Input label={t('preparation.unitPrice')} type="number" step="0.01" value={unitPrice} onChange={(e) => setUnitPrice(e.target.value)} />
            <Input label={t('preparation.amount')} type="number" step="0.01" required value={amount} onChange={(e) => setAmount(e.target.value)} />
          </div>
          <div className="flex justify-end gap-3 pt-2 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}

function ReverseCalcModal({ components, employees, onClose }: {
  components: PayrollComponent[]; employees: Employee[]; onClose: () => void
}) {
  const { t } = useTranslation('payroll')
  const { t: tCommon } = useTranslation('common')
  const [targetNet, setTargetNet] = useState('2000')
  const [employeeId, setEmployeeId] = useState('')
  const [result, setResult] = useState<{ grossSalary: number; breakdown: { code: string; name: string; amount: number }[] } | null>(null)

  function handleCalculate() {
    const emp = employees.find((e) => e.id === employeeId)
    if (!emp) return
    const res = calculateGrossFromNet(Number(targetNet), components, emp)
    setResult(res)
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('reverseCalc.title')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <div className="p-6 space-y-4">
          <Select label={t('preparation.employee')} value={employeeId} onChange={(e) => setEmployeeId(e.target.value)} options={[
            { value: '', label: '—' },
            ...employees.map((e) => ({ value: e.id, label: e.name })),
          ]} />
          <Input label={t('reverseCalc.targetNet')} type="number" step="0.01" value={targetNet} onChange={(e) => setTargetNet(e.target.value)} />
          <Button onClick={handleCalculate} disabled={!employeeId}><Calculator className="w-4 h-4" /> {t('reverseCalc.calculate')}</Button>
          {result && (
            <div className="space-y-2">
              <div className="p-4 rounded-lg bg-[var(--color-neutral-50)]">
                <div className="text-xs text-[var(--color-text-secondary)]">{t('reverseCalc.calculatedGross')}</div>
                <div className="text-2xl font-bold">{formatCurrency(result.grossSalary)}</div>
              </div>
              {result.breakdown.length > 0 && (
                <Card>
                  <Table headers={[t('reverseCalc.code'), t('reverseCalc.name'), t('reverseCalc.amount')]}>
                    {result.breakdown.map((b) => (
                      <TableRow key={b.code}>
                        <TableCell className="text-xs font-mono">{b.code}</TableCell>
                        <TableCell className="text-xs">{b.name}</TableCell>
                        <TableCell className="font-mono text-xs">{formatCurrency(b.amount)}</TableCell>
                      </TableRow>
                    ))}
                  </Table>
                </Card>
              )}
            </div>
          )}
          <div className="flex justify-end pt-2 border-t border-[var(--color-border)]">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.close')}</Button>
          </div>
        </div>
      </div>
    </div>
  )
}

function OvertimeCalcModal({ employees, onClose }: { employees: Employee[]; onClose: () => void }) {
  const { t } = useTranslation('payroll')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [employeeId, setEmployeeId] = useState('')
  const [hours, setHours] = useState('')
  const [rate, setRate] = useState('1.25')
  const [result, setResult] = useState<number | null>(null)
  const [loading, setLoading] = useState(false)

  async function handleCalculate() {
    if (!employeeId) { toast('warning', tCommon('form.requiredField'), t('preparation.employee')); return }
    setLoading(true)
    try {
      const res = await calculateOvertimePay(employeeId, Number(hours) || 0, Number(rate) || 1.25)
      const amount = Number(res?.amount ?? res?.overtime_pay ?? res ?? 0)
      setResult(amount)
      toast('success', tCommon('common.success'), `Heures sup: ${formatCurrency(amount)}`)
    } catch (err: any) { toast('error', tCommon('common.error'), err.message) }
    finally { setLoading(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">Calculer les heures sup</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <div className="p-6 space-y-4">
          <Select label={t('preparation.employee')} value={employeeId} onChange={(e) => setEmployeeId(e.target.value)} options={[
            { value: '', label: '—' },
            ...employees.map((e) => ({ value: e.id, label: e.name })),
          ]} />
          <Input label="Heures" type="number" step="0.5" value={hours} onChange={(e) => setHours(e.target.value)} placeholder="0" />
          <Input label="Taux (ex: 1.25 = 25%)" type="number" step="0.01" value={rate} onChange={(e) => setRate(e.target.value)} />
          <Button onClick={handleCalculate} disabled={loading || !employeeId}><Calculator className="w-4 h-4" /> {loading ? '…' : 'Calculer'}</Button>
          {result !== null && (
            <div className="p-4 rounded-lg bg-[var(--color-neutral-50)]">
              <div className="text-xs text-[var(--color-text-secondary)]">Montant heures supplémentaires</div>
              <div className="text-2xl font-bold">{formatCurrency(result)}</div>
            </div>
          )}
          <div className="flex justify-end pt-2 border-t border-[var(--color-border)]">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.close')}</Button>
          </div>
        </div>
      </div>
    </div>
  )
}

function SickLeaveCalcModal({ employees, onClose }: { employees: Employee[]; onClose: () => void }) {
  const { t } = useTranslation('payroll')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [employeeId, setEmployeeId] = useState('')
  const [days, setDays] = useState('')
  const [result, setResult] = useState<number | null>(null)
  const [loading, setLoading] = useState(false)

  async function handleCalculate() {
    if (!employeeId) { toast('warning', tCommon('form.requiredField'), t('preparation.employee')); return }
    setLoading(true)
    try {
      const res = await calculateSickLeavePay(employeeId, Number(days) || 0)
      const amount = Number(res?.amount ?? res?.sick_leave_pay ?? res?.ijss ?? res ?? 0)
      setResult(amount)
      toast('success', tCommon('common.success'), `IJSS: ${formatCurrency(amount)}`)
    } catch (err: any) { toast('error', tCommon('common.error'), err.message) }
    finally { setLoading(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">Calculer les IJSS</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <div className="p-6 space-y-4">
          <Select label={t('preparation.employee')} value={employeeId} onChange={(e) => setEmployeeId(e.target.value)} options={[
            { value: '', label: '—' },
            ...employees.map((e) => ({ value: e.id, label: e.name })),
          ]} />
          <Input label="Jours d'arrêt" type="number" step="1" value={days} onChange={(e) => setDays(e.target.value)} placeholder="0" />
          <Button onClick={handleCalculate} disabled={loading || !employeeId}><Calculator className="w-4 h-4" /> {loading ? '…' : 'Calculer'}</Button>
          {result !== null && (
            <div className="p-4 rounded-lg bg-[var(--color-neutral-50)]">
              <div className="text-xs text-[var(--color-text-secondary)]">Indemnités journalières (IJSS)</div>
              <div className="text-2xl font-bold">{formatCurrency(result)}</div>
            </div>
          )}
          <div className="flex justify-end pt-2 border-t border-[var(--color-border)]">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.close')}</Button>
          </div>
        </div>
      </div>
    </div>
  )
}
