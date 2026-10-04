import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, EmptyState, AutoBreadcrumb, Select, Input, Badge } from '@/components/ui'
import { useToast } from '@/lib/toast'
import { getEmployees, simulatePayslip, type PayslipSimulation } from '@/lib/queries/payroll'
import { getActiveLegislationPack } from '@/lib/queries/accounting'
import { formatPayrollAmount } from '@/lib/payrollFormat'
import { Calculator, FileText, Globe } from 'lucide-react'
import type { Employee, LegislationPack } from '@/types'

// C2 (rh-005) — cet écran APPELLE le moteur (`simulate_payslip`, migration 319)
// et affiche ce qu'il rend. Il ne recalcule plus rien : avant, il avait son
// propre barème TypeScript, un second moteur, et 2 500 EUR brut y donnaient
// 1 798,53 EUR de net au lieu des 1 919,53 EUR du moteur de la base.
//
// Les champs retirés (type de contrat, heures par semaine, heures
// supplémentaires, titres-restaurant, indemnité transport, taux de PAS) ne
// l'ont pas été au hasard : le moteur ne les prenait pas en entrée — ils
// n'influençaient rien, et l'écran laissait croire le contraire. La simulation
// porte sur le salaire d'un salarié ; le reste vient de la grille et des
// paramètres légaux, que la société a déclarés.

export function PayrollCalcPage() {
  const { t } = useTranslation('features')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [employees, setEmployees] = useState<Employee[]>([])
  const [loading, setLoading] = useState(true)
  const [selectedEmp, setSelectedEmp] = useState('')
  const [result, setResult] = useState<PayslipSimulation | null>(null)
  const [calculating, setCalculating] = useState(false)
  const [legislationPack, setLegislationPack] = useState<LegislationPack | null>(null)

  const [grossSalary, setGrossSalary] = useState(2500)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [empData, pack] = await Promise.all([
        getEmployees().catch(() => []),
        getActiveLegislationPack().catch(() => null),
      ])
      setEmployees((empData || []).filter((e) => e.status === 'active'))
      setLegislationPack(pack)
    } catch (err: any) {
      console.error('Error loading payroll data:', err)
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadingError'))
    } finally {
      setLoading(false)
    }
  }, [toast, tCommon])

  useEffect(() => {
    loadData().catch(err => console.error('loadData:', err))
  }, [loadData])

  function handleEmployeeChange(id: string) {
    setSelectedEmp(id)
    const emp = employees.find((e) => e.id === id)
    if (emp) setGrossSalary(Number(emp.salary) || 2500)
  }

  async function handleCalculate() {
    if (!selectedEmp) return
    setCalculating(true)
    try {
      // Le moteur, en lecture : même grille, mêmes taux, aucune écriture.
      setResult(await simulatePayslip(selectedEmp, grossSalary))
    } catch (err: any) {
      setResult(null)
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.error'))
    } finally {
      setCalculating(false)
    }
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
            {/* C2 : le badge disait « grille chargée » ou « taux de repli » selon
                un état local ; il n'y en a plus. Le moteur choisit la grille,
                et c'est sa version qu'on affiche, quand il a répondu. */}
            {legislationPack && (
              <Badge variant="neutral">
                <Globe className="w-3 h-3 mr-1 inline" />
                {legislationPack.country_name}
                {result?.grid_version ? ` — ${result.grid_version}` : ''}
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
          </div>
          <div className="mt-4">
            <Button onClick={handleCalculate} loading={calculating} disabled={!selectedEmp}>
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
                  <Row label={t('payroll.grossSalary')} value={formatPayrollAmount(result.gross_salary)} />
                  <Row label={t('payroll.totalGross')} value={formatPayrollAmount(result.total_gross)} bold />
                </div>
                <div className="space-y-2">
                  <h4 className="text-xs font-semibold uppercase text-[var(--color-text-secondary)]">{t('payroll.employeeContributions')}</h4>
                  <Row label={t('payroll.socialSecurity')} value={formatPayrollAmount(result.social_security_employee)} />
                  <Row label={t('payroll.csgDeductible')} value={formatPayrollAmount(result.csg_deductible)} />
                  <Row label={t('payroll.csgNonDeductible')} value={formatPayrollAmount(result.csg_non_deductible)} />
                  <Row label={t('payroll.crds')} value={formatPayrollAmount(result.crds)} />
                  <Row label={t('payroll.employeeContributions')} value={formatPayrollAmount(result.total_deductions)} bold />
                </div>
                <div className="space-y-2">
                  <h4 className="text-xs font-semibold uppercase text-[var(--color-text-secondary)]">{t('payroll.employerContributions')}</h4>
                  <Row label={t('payroll.employerContributions')} value={formatPayrollAmount(result.employer_contributions)} bold />
                  {/* C2 : la réduction générale était calculée par le moteur et
                      jamais montrée. Elle vaut jusqu'à 743 EUR au SMIC : c'est une
                      ligne de résultat, pas un détail. */}
                  <Row label={t('payroll.reductionGenerale')} value={formatPayrollAmount(result.reduction_generale)} bold />
                  {Number(result.rgdu_coefficient) > 0 && (
                    <Row label={t('payroll.rgduCoefficient')} value={String(result.rgdu_coefficient)} />
                  )}
                </div>
                <div className="space-y-2">
                  <h4 className="text-xs font-semibold uppercase text-[var(--color-text-secondary)]">{t('payroll.netPay')}</h4>
                  <Row label={t('payroll.netImposable')} value={formatPayrollAmount(result.net_taxable)} />
                  <Row label={t('payroll.incomeTax')} value={formatPayrollAmount(result.income_tax)} />
                  <Row label={t('payroll.netSocial')} value={formatPayrollAmount(result.net_social)} />
                  <Row label={t('payroll.netPayable')} value={formatPayrollAmount(result.net_salary)} bold />
                  <div className="pt-2 border-t border-[var(--color-border)]">
                    <Row
                      label={t('payroll.totalCostEmployer')}
                      value={formatPayrollAmount(Number(result.total_gross) + Number(result.employer_contributions) - Number(result.reduction_generale))}
                      bold
                      highlight
                    />
                  </div>
                </div>
              </div>
              {result.contributions && result.contributions.length > 0 && (
                <div className="mt-4 pt-4 border-t border-[var(--color-border)]">
                  <h4 className="text-xs font-semibold uppercase text-[var(--color-text-secondary)] mb-2">{t('payroll.breakdown')}</h4>
                  <div className="space-y-1">
                    {result.contributions.map((d, i) => (
                      <div key={i} className="flex justify-between text-sm">
                        <span className="text-[var(--color-text-secondary)]">
                          {d.label}
                          {Number(d.rate_employee) > 0 && (
                            <span className="text-[var(--color-text-tertiary)]"> · {Number(d.rate_employee) * 100} %</span>
                          )}
                        </span>
                        <span className="font-mono">{formatPayrollAmount(d.employee)}</span>
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
