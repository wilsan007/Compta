import { useCallback, useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Input, Select, EmptyState, Breadcrumb, Skeleton } from '@/components/ui'
import { errorMessage } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import {
  getCollectiveAgreements,
  createCollectiveAgreement,
  getCollectiveClassifications,
  createCollectiveClassification,
  getEmployeeOptions,
  setEmployeeCollectiveAgreement,
  type CollectiveAgreement,
  type CollectiveClassification,
  type EmployeeOption,
} from '@/lib/queries/collectiveAgreements'
import { FileText, Plus } from 'lucide-react'

export function CollectiveAgreementsPage() {
  const { t } = useTranslation('settings')
  const { t: tNav } = useTranslation('nav')
  const { toast } = useToast()

  const [agreements, setAgreements] = useState<CollectiveAgreement[]>([])
  const [selected, setSelected] = useState<string>('')
  const [classifications, setClassifications] = useState<CollectiveClassification[]>([])
  const [employees, setEmployees] = useState<EmployeeOption[]>([])
  const [loading, setLoading] = useState(true)

  const [idcc, setIdcc] = useState('')
  const [name, setName] = useState('')
  const [appDate, setAppDate] = useState('')
  const [coef, setCoef] = useState('')
  const [minSalary, setMinSalary] = useState('')
  const [empId, setEmpId] = useState('')
  const [classId, setClassId] = useState('')

  const loadAll = useCallback(async () => {
    try {
      const [a, e] = await Promise.all([getCollectiveAgreements(), getEmployeeOptions()])
      setAgreements(a)
      setEmployees(e)
      setSelected((cur) => (cur && a.some((x) => x.id === cur) ? cur : (a[0]?.id ?? '')))
    } catch (err) {
      toast('error', t('collectiveAgreements.title'), errorMessage(err))
    } finally {
      setLoading(false)
    }
  }, [toast, t])

  useEffect(() => { loadAll() }, [loadAll])
  useEffect(() => {
    if (!selected) { setClassifications([]); return }
    getCollectiveClassifications(selected)
      .then(setClassifications)
      .catch((err) => toast('error', t('collectiveAgreements.title'), errorMessage(err)))
  }, [selected, toast, t])

  async function handleCreateAgreement() {
    if (!idcc.trim() || !name.trim() || !appDate) return
    try {
      await createCollectiveAgreement({ idccCode: idcc.trim(), name: name.trim(), applicationDate: appDate })
      setIdcc(''); setName(''); setAppDate('')
      await loadAll()
    } catch (err) {
      toast('error', t('collectiveAgreements.title'), errorMessage(err))
    }
  }

  async function handleCreateClassification() {
    if (!selected || !coef || !minSalary) return
    try {
      await createCollectiveClassification({
        agreementId: selected,
        coefficient: Number(coef),
        minimumMonthlySalary: Number(minSalary),
      })
      setCoef(''); setMinSalary('')
      setClassifications(await getCollectiveClassifications(selected))
    } catch (err) {
      toast('error', t('collectiveAgreements.title'), errorMessage(err))
    }
  }

  async function handleAssign() {
    if (!empId) return
    try {
      await setEmployeeCollectiveAgreement(empId, selected || null, classId || null)
      toast('success', t('collectiveAgreements.assigned'), '')
      setEmployees(await getEmployeeOptions())
    } catch (err) {
      toast('error', t('collectiveAgreements.title'), errorMessage(err))
    }
  }

  async function handleClear() {
    if (!empId) return
    try {
      await setEmployeeCollectiveAgreement(empId, null, null)
      setEmployees(await getEmployeeOptions())
    } catch (err) {
      toast('error', t('collectiveAgreements.title'), errorMessage(err))
    }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('groups.system') }, { label: t('collectiveAgreements.title') }]} />
      <PageHeader title={t('collectiveAgreements.title')} subtitle={t('collectiveAgreements.subtitle')} />

      {loading ? (
        <Skeleton className="h-40 w-full" />
      ) : (
        <div className="space-y-6">
          <Card>
            <h3 className="font-semibold mb-3">{t('collectiveAgreements.createTitle')}</h3>
            <div className="grid grid-cols-1 md:grid-cols-4 gap-2">
              <Input label={t('collectiveAgreements.idcc')} value={idcc}
                onChange={(e) => setIdcc(e.target.value)} placeholder="1234" />
              <Input label={t('collectiveAgreements.name')} value={name}
                onChange={(e) => setName(e.target.value)} />
              <Input label={t('collectiveAgreements.date')} type="date" value={appDate}
                onChange={(e) => setAppDate(e.target.value)} />
              <div className="flex items-end">
                <Button onClick={handleCreateAgreement} disabled={!idcc.trim() || !name.trim() || !appDate}>
                  <Plus className="w-4 h-4 mr-1" aria-hidden="true" />{t('collectiveAgreements.create')}
                </Button>
              </div>
            </div>
          </Card>

          {agreements.length === 0 ? (
            <EmptyState icon={<FileText className="w-8 h-8" aria-hidden="true" />} title={t('collectiveAgreements.empty')} />
          ) : (
            <Card>
              <div className="mb-4 max-w-md">
                <Select label={t('collectiveAgreements.select')} value={selected} onChange={(e) => setSelected(e.target.value)}>
                  {agreements.map((a) => <option key={a.id} value={a.id}>{a.idcc_code} — {a.name}</option>)}
                </Select>
              </div>

              <h4 className="font-medium mb-2">{t('collectiveAgreements.classifications')}</h4>
              <ul className="divide-y divide-[var(--color-border)] mb-3">
                {classifications.map((c) => (
                  <li key={c.id} className="flex items-center justify-between py-1.5 text-sm">
                    <span>{t('collectiveAgreements.coefficient')} {c.coefficient}</span>
                    <span>{Number(c.minimum_monthly_salary).toFixed(2)}</span>
                  </li>
                ))}
              </ul>
              <div className="grid grid-cols-1 md:grid-cols-3 gap-2 mb-6">
                <Input label={t('collectiveAgreements.coefficient')} value={coef}
                  onChange={(e) => setCoef(e.target.value.replace(/[^0-9.]/g, ''))} />
                <Input label={t('collectiveAgreements.minSalary')} value={minSalary}
                  onChange={(e) => setMinSalary(e.target.value.replace(/[^0-9.]/g, ''))} />
                <div className="flex items-end">
                  <Button variant="secondary" onClick={handleCreateClassification} disabled={!coef || !minSalary}>
                    <Plus className="w-4 h-4 mr-1" aria-hidden="true" />{t('collectiveAgreements.addClassification')}
                  </Button>
                </div>
              </div>

              <h4 className="font-medium mb-2">{t('collectiveAgreements.assignTitle')}</h4>
              <div className="grid grid-cols-1 md:grid-cols-4 gap-2">
                <Select label={t('collectiveAgreements.employee')} value={empId} onChange={(e) => setEmpId(e.target.value)}>
                  <option value="">{t('collectiveAgreements.employee')}</option>
                  {employees.map((emp) => <option key={emp.id} value={emp.id}>{emp.name}</option>)}
                </Select>
                <Select label={t('collectiveAgreements.classification')} value={classId} onChange={(e) => setClassId(e.target.value)}>
                  <option value="">—</option>
                  {classifications.map((c) => <option key={c.id} value={c.id}>{c.coefficient}</option>)}
                </Select>
                <div className="flex items-end gap-2">
                  <Button variant="secondary" onClick={handleAssign} disabled={!empId}>{t('collectiveAgreements.assign')}</Button>
                  <Button variant="ghost" onClick={handleClear} disabled={!empId}>{t('collectiveAgreements.clear')}</Button>
                </div>
              </div>
            </Card>
          )}
        </div>
      )}
    </div>
  )
}

