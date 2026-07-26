import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, EmptyState, AutoBreadcrumb, Select, Input, Badge } from '@/components/ui'
import { getEmployees, getActiveLegislationPack, getActivePayrollTaxGrid, getPayrollTaxGridLines } from '@/lib/queries'
import { calculatePayroll, type PayrollInput, type PayrollResult, formatPayrollAmount } from '@/lib/payroll'
import { Calculator, FileText, Globe } from 'lucide-react'
import type { Employee, PayrollTaxGridLine, LegislationPack } from '@/types'

export function PayrollCalcPage() {
  const { t } = useTranslation('features')
  const [employees, setEmployees] = useState<Employee[]>([])
  const [loading, setLoading] = useState(true)
  const [selectedEmp, setSelectedEmp] = useState('')
  const [result, setResult] = useState<PayrollResult | null>(null)
  const [gridLines, setGridLines] = useState<PayrollTaxGridLine[]>([])
  const [legislationPack, setLegislationPack] = useState<LegislationPack | null>(null)
  const [usingGrid, setUsingGrid] = useState(false)

  const [grossSalary, setGrossSalary] = useState(2500)
  const [contractType, setContractType] = useState<'cdi' | 'cdd' | 'apprentice'>('cdi')
  const [hoursPerWeek, setHoursPerWeek] = useState(35)
  const [overtimeHours, setOvertimeHours] = useState(0)
  const [mealVouchers, setMealVouchers] = useState(80)
  const [transportAllowance, setTransportAllowance] = useState(75)
  const [taxRate, setTaxRate] = useState(3.5)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [empData, pack] = await Promise.all([
        getEmployees().catch(() => []),
        getActiveLegislationPack().catch(() => null),
      ])
      setEmployees((empData || []).filter((e) => e.status === 'active'))
      setLegislationPack(pack)

      if (pack?.country_code) {
        const grid = await getActivePayrollTaxGrid(pack.country_code, 'composite').catch(() => undefined)
        if (!grid) {
          const itsGrid = await getActivePayrollTaxGrid(pack.country_code, 'its').catch(() => undefined)
          if (itsGrid) {
            const lines = await getPayrollTaxGridLines(itsGrid.id).catch(() => [])
            const empGrid = await getActivePayrollTaxGrid(pack.country_code, 'employee_contribution').catch(() => undefined)
            const empLines = empGrid ? await getPayrollTaxGridLines(empGrid.id).catch(() => []) : []
            const allLines = [...lines, ...empLines]
            if (allLines.length > 0) {
              setGridLines(allLines)
              setUsingGrid(true)
              return
            }
          }
        } else {
          const lines = await getPayrollTaxGridLines(grid.id).catch(() => [])
          if (lines.length > 0) {
            setGridLines(lines)
            setUsingGrid(true)
            return
          }
        }
      }
      setUsingGrid(false)
    } catch (err) {
      console.error('Error loading payroll data:', err)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    loadData()
  }, [loadData])

  function handleEmployeeChange(id: string) {
    setSelectedEmp(id)
    const emp = employees.find((e) => e.id === id)
    if (emp) {
      setGrossSalary(Number(emp.salary) || 2500)
    }
  }

  function handleCalculate() {
    const input: PayrollInput = {
      grossSalary,
      contractType,
      hoursPerWeek,
      overtimeHours,
      mealVouchers,
      transportAllowance,
      age: 30,
      department: '',
      taxRate,
    }
    setResult(calculatePayroll(input, usingGrid ? gridLines : undefined))
  }

  const activeEmployees = employees

  return (
    <div className="animate-fade-in">
      <AutoBreadcrumb />
      <PageHeader title={t('payroll.title')} subtitle={t('payroll.subtitle')} />

      <Card className="mb-4">
        <div className="p-4">
          <div className="flex items-center gap-2 mb-4">
            <p className="text-sm text-[var(--color-text-secondary)]">{t('payroll.intro')}</p>
            {legislationPack && (
              <Badge variant={usingGrid ? 'success' : 'warning'}>
                <Globe className="w-3 h-3 mr-1 inline" />
                {legislationPack.country_name}
                {usingGrid ? ' — ' + t('payroll.gridLoaded') : ' — ' + t('payroll.fallbackRates')}
              </Badge>
            )}
          </div>
          <div className="grid md:grid-cols-3 gap-4">
            <div className="md:col-span-3">
              <Select
                label={t('payroll.employee')}
                value={selectedEmp}
                onChange={(e) => handleEmployeeChange(e.target.value)}
                options={[
                  { value: '', label: t('payroll.selectEmployee') },
                  ...activeEmployees.map((e) => ({ value: e.id, label: `${e.name} — ${e.position}` })),
                ]}
              />
            </div>
            <div>
              <Input label={t('payroll.grossSalary')} type="number" value={String(grossSalary)} onChange={(e) => setGrossSalary(Number(e.target.value))} />
            </div>
            <div>
              <Select
                label={t('payroll.contractType')}
                value={contractType}
                onChange={(e) => setContractType(e.target.value as any)}
                options={[
                  { value: 'cdi', label: t('payroll.cdi') },
                  { value: 'cdd', label: t('payroll.cdd') },
                  { value: 'apprentice', label: t('payroll.apprentice') },
                ]}
              />
            </div>
            <div>
              <Input label={t('payroll.hoursPerWeek')} type="number" value={String(hoursPerWeek)} onChange={(e) => setHoursPerWeek(Number(e.target.value))} />
            </div>
            <div>
              <Input label={t('payroll.overtimeHours')} type="number" value={String(overtimeHours)} onChange={(e) => setOvertimeHours(Number(e.target.value))} />
            </div>
            <div>
              <Input label={t('payroll.mealVouchers')} type="number" value={String(mealVouchers)} onChange={(e) => setMealVouchers(Number(e.target.value))} />
            </div>
            <div>
              <Input label={t('payroll.transportAllowance')} type="number" value={String(transportAllowance)} onChange={(e) => setTransportAllowance(Number(e.target.value))} />
            </div>
            <div>
              <Input label={t('payroll.taxRate')} type="number" step="0.1" value={String(taxRate)} onChange={(e) => setTaxRate(Number(e.target.value))} />
            </div>
          </div>
          <div className="mt-4">
            <Button onClick={handleCalculate} disabled={!selectedEmp && activeEmployees.length > 0}>
              <Calculator className="w-4 h-4" /> {t('payroll.calculate')}
            </Button>
          </div>
        </div>
      </Card>

      {loading ? (
        <Card><div className="p-8 text-center text-[var(--color-text-secondary)]">...</div></Card>
      ) : activeEmployees.length === 0 ? (
        <EmptyState
          icon={<FileText className="w-8 h-8" />}
          title={t('payroll.noEmployees')}
          description={t('payroll.noEmployeesDesc')}
        />
      ) : result ? (
        <div className="space-y-4">
          <Card>
            <div className="p-4">
              <h3 className="text-sm font-semibold mb-4">{t('payroll.results')}</h3>
              <div className="grid md:grid-cols-2 gap-6">
                <div className="space-y-2">
                  <h4 className="text-xs font-semibold uppercase text-[var(--color-text-secondary)]">{t('payroll.totalGross')}</h4>
                  <Row label={t('payroll.grossSalary')} value={formatPayrollAmount(result.grossSalary)} />
                  <Row label={t('payroll.overtimePay')} value={formatPayrollAmount(result.overtimePay)} />
                  <Row label={t('payroll.totalGross')} value={formatPayrollAmount(result.totalGross)} bold />
                  <Row label={t('payroll.mealVouchers')} value={formatPayrollAmount(result.mealVouchers)} />
                  <Row label={t('payroll.transportAllowance')} value={formatPayrollAmount(result.transportAllowance)} />
                </div>
                <div className="space-y-2">
                  <h4 className="text-xs font-semibold uppercase text-[var(--color-text-secondary)]">{t('payroll.employeeContributions')}</h4>
                  <Row label={t('payroll.socialSecurity')} value={formatPayrollAmount(result.socialSecurityEmployee)} />
                  <Row label={t('payroll.health')} value={formatPayrollAmount(result.healthEmployee)} />
                  <Row label={t('payroll.retirement')} value={formatPayrollAmount(result.retirementEmployee)} />
                  <Row label={t('payroll.unemployment')} value={formatPayrollAmount(result.unemploymentEmployee)} />
                  <Row label={t('payroll.csgCrds')} value={formatPayrollAmount(result.csgCrds)} />
                  <Row label={t('payroll.employeeContributions')} value={formatPayrollAmount(result.totalEmployeeContributions)} bold />
                </div>
                <div className="space-y-2">
                  <h4 className="text-xs font-semibold uppercase text-[var(--color-text-secondary)]">{t('payroll.employerContributions')}</h4>
                  <Row label={t('payroll.socialSecurity')} value={formatPayrollAmount(result.socialSecurityEmployer)} />
                  <Row label={t('payroll.health')} value={formatPayrollAmount(result.healthEmployer)} />
                  <Row label={t('payroll.retirement')} value={formatPayrollAmount(result.retirementEmployer)} />
                  <Row label={t('payroll.unemployment')} value={formatPayrollAmount(result.unemploymentEmployer)} />
                  <Row label={t('payroll.employerContributions')} value={formatPayrollAmount(result.totalEmployerContributions)} bold />
                </div>
                <div className="space-y-2">
                  <h4 className="text-xs font-semibold uppercase text-[var(--color-text-secondary)]">{t('payroll.netPay')}</h4>
                  <Row label={t('payroll.incomeTax')} value={formatPayrollAmount(result.incomeTax)} />
                  <Row label={t('payroll.netPay')} value={formatPayrollAmount(result.netPay)} bold />
                  <Row label={t('payroll.netPayable')} value={formatPayrollAmount(result.netPayable)} bold />
                  <div className="pt-2 border-t border-[var(--color-border)]">
                    <Row label={t('payroll.totalCostEmployer')} value={formatPayrollAmount(result.totalCostEmployer)} bold highlight />
                  </div>
                </div>
              </div>
              {result.lineDetails && result.lineDetails.length > 0 && (
                <div className="mt-4 pt-4 border-t border-[var(--color-border)]">
                  <h4 className="text-xs font-semibold uppercase text-[var(--color-text-secondary)] mb-2">{t('payroll.breakdown')}</h4>
                  <div className="space-y-1">
                    {result.lineDetails.map((d, i) => (
                      <div key={i} className="flex justify-between text-sm">
                        <span className="text-[var(--color-text-secondary)]">{d.label}</span>
                        <span className="font-mono">{formatPayrollAmount(d.amount)}</span>
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </div>
          </Card>
        </div>
      ) : null}
    </div>
  )
}

function Row({ label, value, bold, highlight }: { label: string; value: string; bold?: boolean; highlight?: boolean }) {
  return (
    <div className={`flex justify-between items-center py-1 ${bold ? 'font-bold' : ''} ${highlight ? 'text-[var(--color-primary)] text-lg' : ''}`}>
      <span className="text-sm text-[var(--color-text-secondary)]">{label}</span>
      <span className="font-mono">{value}</span>
    </div>
  )
}
