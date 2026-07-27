import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Select, Input } from '@/components/ui'
import { formatCurrency } from '@/lib/utils'
import {
  getMealVoucherConfig, updateMealVoucherConfig, calculateMealVouchers,
  generateMealVoucherElements, getPayRuns,
} from '@/lib/queries'
import type { MealVoucherConfig, PayRun } from '@/types'
import { useToast } from '@/lib/toast'
import { Utensils, Save, Download, X } from 'lucide-react'

export function MealVouchersPage() {
  const { t } = useTranslation('payroll')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const { toast } = useToast()
  const [config, setConfig] = useState<MealVoucherConfig | null>(null)
  const [calculations, setCalculations] = useState<any[]>([])
  const [payRuns, setPayRuns] = useState<PayRun[]>([])
  const [loading, setLoading] = useState(true)
  const [month, setMonth] = useState(new Date().getMonth() + 1)
  const [year, setYear] = useState(new Date().getFullYear())
  const [selectedPayRun, setSelectedPayRun] = useState('')
  const [showConfig, setShowConfig] = useState(false)
  const [saving, setSaving] = useState(false)

  const loadData = useCallback(async () => {
    try {
      const [cfg, runs] = await Promise.all([getMealVoucherConfig(), getPayRuns()])
      setConfig(cfg)
      setPayRuns(runs || [])
    } catch (err: any) { console.error(err) }
    finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleCalculate() {
    try {
      const results = await calculateMealVouchers(month, year)
      setCalculations(results)
      toast('success', tCommon('common.success'), t('mealVouchers.calculated'))
    } catch (err: any) { toast('error', tCommon('common.error'), err.message) }
  }

  async function handleGenerate() {
    if (!selectedPayRun) { toast('error', tCommon('common.error'), t('mealVouchers.selectPayRun')); return }
    try {
      setSaving(true)
      await generateMealVoucherElements(selectedPayRun, month, year)
      toast('success', tCommon('common.success'), t('mealVouchers.generated'))
    } catch (err: any) { toast('error', tCommon('common.error'), err.message) }
    finally { setSaving(false) }
  }

  function handleExport() {
    if (calculations.length === 0) return
    const headers = ['Employee,Department,WorkingDays,NbVouchers,VoucherValue,EmployerAmount,EmployeeAmount,Total']
    const rows = calculations.map((c) =>
      `${c.employee_name},${c.department},${c.working_days},${c.nb_vouchers},${c.voucher_value},${c.employer_amount},${c.employee_amount},${c.total}`
    )
    const csv = [...headers, ...rows].join('\n')
    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url; a.download = `meal-vouchers-${year}-${String(month).padStart(2, '0')}.csv`; a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.hr') }, { label: t('mealVouchers.title') }]} />
      <PageHeader title={t('mealVouchers.title')} subtitle={t('mealVouchers.subtitle')} />

      <div className="flex justify-between items-end mb-3">
        <div className="flex gap-3 items-end">
          <div className="w-32">
            <Select label={t('mealVouchers.month')} value={String(month)} onChange={(e) => setMonth(Number(e.target.value))} options={[
              ...Array.from({ length: 12 }, (_, i) => ({ value: String(i + 1), label: new Date(2000, i, 1).toLocaleDateString('fr', { month: 'long' }) })),
            ]} />
          </div>
          <div className="w-28">
            <Select label={t('mealVouchers.year')} value={String(year)} onChange={(e) => setYear(Number(e.target.value))} options={[
              { value: String(new Date().getFullYear() - 1), label: String(new Date().getFullYear() - 1) },
              { value: String(new Date().getFullYear()), label: String(new Date().getFullYear()) },
              { value: String(new Date().getFullYear() + 1), label: String(new Date().getFullYear() + 1) },
            ]} />
          </div>
          <Button onClick={handleCalculate}>{t('mealVouchers.calculate')}</Button>
        </div>
        <div className="flex gap-2">
          {calculations.length > 0 && <Button variant="secondary" onClick={handleExport}><Download className="w-4 h-4" /> {tCommon('actions.export')}</Button>}
          <Button variant="secondary" onClick={() => setShowConfig(true)}><Utensils className="w-4 h-4" /> {t('mealVouchers.config')}</Button>
        </div>
      </div>

      {config && (
        <div className="grid grid-cols-4 gap-3 mb-4">
          <Card className="p-4">
            <div className="text-xs text-[var(--color-text-secondary)]">{t('mealVouchers.voucherValue')}</div>
            <div className="text-lg font-bold">{formatCurrency(Number(config.voucher_value))}</div>
          </Card>
          <Card className="p-4">
            <div className="text-xs text-[var(--color-text-secondary)]">{t('mealVouchers.employerShare')}</div>
            <div className="text-lg font-bold">{Number(config.employer_share)}%</div>
          </Card>
          <Card className="p-4">
            <div className="text-xs text-[var(--color-text-secondary)]">{t('mealVouchers.employeeShare')}</div>
            <div className="text-lg font-bold">{Number(config.employee_share)}%</div>
          </Card>
          <Card className="p-4">
            <div className="text-xs text-[var(--color-text-secondary)]">{t('mealVouchers.maxPerMonth')}</div>
            <div className="text-lg font-bold">{config.max_per_month}</div>
          </Card>
        </div>
      )}

      {loading ? <SkeletonTable rows={5} cols={7} /> : calculations.length === 0 ? (
        <EmptyState icon={<Utensils className="w-8 h-8" />} title={t('mealVouchers.noData')} description={t('mealVouchers.noDataDescription')} />
      ) : (
        <Card>
          <Table headers={[
            t('mealVouchers.employee'), t('mealVouchers.department'), t('mealVouchers.workingDays'),
            t('mealVouchers.nbVouchers'), t('mealVouchers.voucherValue'), t('mealVouchers.employerAmount'),
            t('mealVouchers.employeeAmount'), t('mealVouchers.total'),
          ]}>
            {calculations.map((c) => (
              <TableRow key={c.employee_id}>
                <TableCell className="text-sm font-medium">{c.employee_name}</TableCell>
                <TableCell className="text-xs">{c.department}</TableCell>
                <TableCell className="font-mono text-xs">{c.working_days}</TableCell>
                <TableCell className="font-mono text-xs">{c.nb_vouchers}</TableCell>
                <TableCell className="font-mono text-xs">{formatCurrency(c.voucher_value)}</TableCell>
                <TableCell className="font-mono text-xs">{formatCurrency(c.employer_amount)}</TableCell>
                <TableCell className="font-mono text-xs">{formatCurrency(c.employee_amount)}</TableCell>
                <TableCell className="font-mono text-xs font-bold">{formatCurrency(c.total)}</TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {calculations.length > 0 && (
        <div className="mt-4 flex gap-3 items-end">
          <div className="flex-1">
            <Select label={t('mealVouchers.payRun')} value={selectedPayRun} onChange={(e) => setSelectedPayRun(e.target.value)} options={[
              { value: '', label: t('mealVouchers.selectPayRun') },
              ...payRuns.map((r) => ({ value: r.id, label: `${r.number} — ${r.period_start}` })),
            ]} />
          </div>
          <Button onClick={handleGenerate} disabled={saving || !selectedPayRun}>
            {saving ? '...' : t('mealVouchers.generateToPayroll')}
          </Button>
        </div>
      )}

      {showConfig && config && (
        <ConfigModal config={config} onClose={() => setShowConfig(false)} onSaved={() => { setShowConfig(false); loadData() }} />
      )}
    </div>
  )
}

function ConfigModal({ config, onClose, onSaved }: { config: MealVoucherConfig; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('payroll')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [voucherValue, setVoucherValue] = useState(String(config.voucher_value))
  const [employerShare, setEmployerShare] = useState(String(config.employer_share))
  const [employeeShare, setEmployeeShare] = useState(String(config.employee_share))
  const [maxPerMonth, setMaxPerMonth] = useState(String(config.max_per_month))
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault(); setSaving(true)
    try {
      await updateMealVoucherConfig(config.id, {
        voucher_value: Number(voucherValue),
        employer_share: Number(employerShare),
        employee_share: Number(employeeShare),
        max_per_month: Number(maxPerMonth),
      })
      onSaved()
    } catch (err: any) { toast('error', tCommon('common.error'), err.message) }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('mealVouchers.configTitle')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label={t('mealVouchers.voucherValue')} type="number" step="0.01" required value={voucherValue} onChange={(e) => setVoucherValue(e.target.value)} />
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('mealVouchers.employerShare')} type="number" required value={employerShare} onChange={(e) => setEmployerShare(e.target.value)} />
            <Input label={t('mealVouchers.employeeShare')} type="number" required value={employeeShare} onChange={(e) => setEmployeeShare(e.target.value)} />
          </div>
          <Input label={t('mealVouchers.maxPerMonth')} type="number" required value={maxPerMonth} onChange={(e) => setMaxPerMonth(e.target.value)} />
          <div className="flex justify-end gap-3 pt-2 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}><Save className="w-4 h-4" /> {saving ? '...' : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
