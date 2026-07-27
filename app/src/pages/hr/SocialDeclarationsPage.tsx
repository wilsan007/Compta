import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Select, Input } from '@/components/ui'
import {
  getSocialDeclarations, generateDsnFile, transmitDsn, checkDsnAnomalies,
  generateDadsU, generateDucs, generateAed, generateDpae, generateDtsMsa,
  generateCibtp, generateCongesPayesBtp, generateRefusCdi, generateCt2025, generatePasrau,
  getCiceConfig, calculateCice, generateCiceFile,
  getPasRates, getAtRates, importPasRates, importAtRates,
  getHonorariumRecords, createHonorariumRecord, updateHonorariumRecord, generateHonorariumAccounting,
  getEmployees,
} from '@/lib/queries'
import type { SocialDeclaration, CiceConfig, HonorariumRecord, Employee } from '@/types'
import { useToast } from '@/lib/toast'
import { FileText, Send, AlertTriangle, Download, Calculator, Upload, Plus } from 'lucide-react'

type Tab = 'dsn' | 'dadsu' | 'ducs' | 'aed' | 'dpae' | 'btp' | 'msa' | 'cice' | 'pasrau' | 'other' | 'rates' | 'honorarium'

export function SocialDeclarationsPage() {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const { toast } = useToast()
  const [tab, setTab] = useState<Tab>('dsn')
  const [loading, setLoading] = useState(true)
  const [declarations, setDeclarations] = useState<SocialDeclaration[]>([])
  const [employees, setEmployees] = useState<Employee[]>([])
  const [month, setMonth] = useState(new Date().getMonth() + 1)
  const [year, setYear] = useState(new Date().getFullYear())
  const [dsnStep, setDsnStep] = useState(1)
  const [anomalies, setAnomalies] = useState<any[]>([])
  const [ciceConfigs, setCiceConfigs] = useState<CiceConfig[]>([])
  const [ciceResults, setCiceResults] = useState<any[]>([])
  const [pasRates, setPasRates] = useState<any[]>([])
  const [atRates, setAtRates] = useState<any[]>([])
  const [honorariums, setHonorariums] = useState<HonorariumRecord[]>([])
  const [showHonorariumForm, setShowHonorariumForm] = useState(false)
  const [selectedEmployee, setSelectedEmployee] = useState('')
  const [honName, setHonName] = useState('')
  const [honType, setHonType] = useState('external')
  const [honPeriod, setHonPeriod] = useState('')
  const [honAmount, setHonAmount] = useState('')
  const [honDesc, setHonDesc] = useState('')

  const period = `${year}-${String(month).padStart(2, '0')}`

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [decls, emps] = await Promise.all([
        getSocialDeclarations(),
        getEmployees(),
      ])
      setDeclarations(decls)
      setEmployees(emps)
      if (tab === 'cice') {
        const configs = await getCiceConfig()
        setCiceConfigs(configs)
      }
      if (tab === 'rates') {
        const [pas, at] = await Promise.all([getPasRates(), getAtRates()])
        setPasRates(pas)
        setAtRates(at)
      }
      if (tab === 'honorarium') {
        const hon = await getHonorariumRecords()
        setHonorariums(hon)
      }
    } catch (e: any) {
      toast('error', tCommon('common.error'), e.message)
    } finally {
      setLoading(false)
    }
  }, [tab, toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  const handleDsnCheck = async () => {
    try {
      const anoms = await checkDsnAnomalies(period)
      setAnomalies(anoms)
      setDsnStep(2)
      if (anoms.length === 0) toast('success', t('socialDecl.noAnomalies'))
    } catch (e: any) {
      toast('error', tCommon('common.error'), e.message)
    }
  }

  const handleDsnGenerate = async () => {
    try {
      await generateDsnFile(period)
      setDsnStep(3)
      toast('success', t('socialDecl.generated'))
      loadData()
    } catch (e: any) {
      toast('error', tCommon('common.error'), e.message)
    }
  }

  const handleDsnTransmit = async () => {
    try {
      const latest = declarations.find(d => d.declaration_type === 'dsn' && d.period === period)
      if (latest) {
        await transmitDsn(latest.id)
        setDsnStep(5)
        toast('success', t('socialDecl.transmitted'))
        loadData()
      }
    } catch (e: any) {
      toast('error', tCommon('common.error'), e.message)
    }
  }

  const handleGenerate = async (fn: () => Promise<any>, label: string) => {
    try {
      await fn()
      toast('success', label)
      loadData()
    } catch (e: any) {
      toast('error', tCommon('common.error'), e.message)
    }
  }

  const handleCalculateCice = async () => {
    try {
      const results = await calculateCice(year)
      setCiceResults(results)
      toast('success', t('socialDecl.ciceCalculated'))
    } catch (e: any) {
      toast('error', tCommon('common.error'), e.message)
    }
  }

  const tabs: { key: Tab; label: string }[] = [
    { key: 'dsn', label: t('socialDecl.dsn') },
    { key: 'dadsu', label: t('socialDecl.dadsU') },
    { key: 'ducs', label: t('socialDecl.ducs') },
    { key: 'aed', label: t('socialDecl.aed') },
    { key: 'dpae', label: t('socialDecl.dpae') },
    { key: 'btp', label: t('socialDecl.btp') },
    { key: 'msa', label: t('socialDecl.msa') },
    { key: 'cice', label: t('socialDecl.cice') },
    { key: 'pasrau', label: t('socialDecl.pasrau') },
    { key: 'other', label: t('socialDecl.other') },
    { key: 'rates', label: t('socialDecl.rates') },
    { key: 'honorarium', label: t('socialDecl.honorarium') },
  ]

  const statusVariant = (status: string): 'success' | 'warning' | 'danger' | 'neutral' | 'primary' => {
    switch (status) {
      case 'accepted': return 'success'
      case 'rejected': return 'danger'
      case 'transmitted': return 'primary'
      case 'generated': return 'warning'
      default: return 'neutral'
    }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.hr') }, { label: t('socialDecl.title') }]} />
      <PageHeader title={t('socialDecl.title')} subtitle={t('socialDecl.subtitle')} />

      <div className="flex flex-wrap gap-2 mb-4">
        {tabs.map(tabItem => (
          <Button key={tabItem.key} variant={tab === tabItem.key ? 'primary' : 'secondary'} onClick={() => setTab(tabItem.key)}>
            {tabItem.label}
          </Button>
        ))}
      </div>

      {loading ? <SkeletonTable /> : (
        <>
          {/* DSN Tab with wizard */}
          {tab === 'dsn' && (
            <Card>
              <div className="flex items-center gap-2 mb-4">
              {[1, 2, 3, 4, 5].map(step => (
                <div key={step} className={`flex items-center gap-1 ${dsnStep >= step ? 'text-blue-600' : 'text-gray-400'}`}>
                  <div className={`w-6 h-6 rounded-full flex items-center justify-center text-xs ${dsnStep >= step ? 'bg-blue-600 text-white' : 'bg-gray-200'}`}>{step}</div>
                  {step < 5 && <div className={`w-8 h-0.5 ${dsnStep > step ? 'bg-blue-600' : 'bg-gray-200'}`} />}
                </div>
              ))}
              </div>

              {dsnStep === 1 && (
                <div className="space-y-4">
                  <div className="flex gap-3">
                    <Select label={t('socialDecl.month')} value={String(month)} onChange={(e) => setMonth(Number(e.target.value))} options={Array.from({ length: 12 }, (_, i) => ({ value: String(i + 1), label: tCommon(`months.${i}`) }))} />
                    <Select label={t('socialDecl.year')} value={String(year)} onChange={(e) => setYear(Number(e.target.value))} options={[year - 1, year, year + 1].map(y => ({ value: String(y), label: String(y) }))} />
                  </div>
                  <Button onClick={handleDsnCheck}><AlertTriangle className="w-4 h-4 mr-2" />{t('socialDecl.anomalyCheck')}</Button>
                </div>
              )}
              {dsnStep === 2 && (
                <div className="space-y-4">
                  {anomalies.length === 0 ? (
                    <p className="text-green-600">{t('socialDecl.noAnomalies')}</p>
                  ) : (
                    <Table headers={[t('socialDecl.employee'), t('socialDecl.field'), t('socialDecl.message')]}>
                      {anomalies.map((a, i) => (
                        <TableRow key={i}>
                          <TableCell className="text-sm">{a.employee_name}</TableCell>
                          <TableCell className="text-xs font-mono">{a.field}</TableCell>
                          <TableCell className="text-xs">{a.message}</TableCell>
                        </TableRow>
                      ))}
                    </Table>
                  )}
                  <Button onClick={handleDsnGenerate}><FileText className="w-4 h-4 mr-2" />{t('socialDecl.generate')}</Button>
                </div>
              )}
              {dsnStep === 3 && (
                <div className="space-y-4">
                  <p className="text-sm">{t('socialDecl.fileReady')}</p>
                  <Button onClick={() => setDsnStep(4)}><Send className="w-4 h-4 mr-2" />{t('socialDecl.transmit')}</Button>
                </div>
              )}
              {dsnStep === 4 && (
                <div className="space-y-4">
                  <p className="text-sm">{t('socialDecl.transmitting')}</p>
                  <Button onClick={handleDsnTransmit}>{t('socialDecl.confirmTransmit')}</Button>
                </div>
              )}
              {dsnStep === 5 && (
                <div className="space-y-4">
                  <p className="text-green-600">{t('socialDecl.transmitted')}</p>
                  <Button variant="secondary" onClick={() => setDsnStep(1)}>{t('socialDecl.newDsn')}</Button>
                </div>
              )}

              <div className="mt-6">
                <h3 className="font-medium mb-2">{t('socialDecl.history')}</h3>
                {declarations.filter(d => d.declaration_type === 'dsn').length === 0 ? (
                  <EmptyState title={t('socialDecl.noHistory')} />
                ) : (
                  <Table headers={[t('socialDecl.number'), t('socialDecl.period'), t('socialDecl.status'), t('socialDecl.date')]}>
                    {declarations.filter(d => d.declaration_type === 'dsn').map(d => (
                      <TableRow key={d.id}>
                        <TableCell className="text-xs font-mono">{d.number}</TableCell>
                        <TableCell className="text-sm">{d.period || '-'}</TableCell>
                        <TableCell><Badge variant={statusVariant(d.status)}>{t(`socialDecl.statuses.${d.status}`)}</Badge></TableCell>
                        <TableCell className="text-xs">{new Date(d.created_at).toLocaleDateString()}</TableCell>
                      </TableRow>
                    ))}
                  </Table>
                )}
              </div>
            </Card>
          )}

          {/* DADS-U */}
          {tab === 'dadsu' && (
            <Card>
              <div className="flex gap-3 mb-4">
                <Select label={t('socialDecl.year')} value={String(year)} onChange={(e) => setYear(Number(e.target.value))} options={[year - 1, year, year + 1].map(y => ({ value: String(y), label: String(y) }))} />
              </div>
              <Button onClick={() => handleGenerate(() => generateDadsU(String(year)), t('socialDecl.generated'))}><FileText className="w-4 h-4 mr-2" />{t('socialDecl.generate')}</Button>
            </Card>
          )}

          {/* DUCS */}
          {tab === 'ducs' && (
            <Card>
              <div className="flex gap-3 mb-4">
                <Select label={t('socialDecl.month')} value={String(month)} onChange={(e) => setMonth(Number(e.target.value))} options={Array.from({ length: 12 }, (_, i) => ({ value: String(i + 1), label: tCommon(`months.${i}`) }))} />
                <Select label={t('socialDecl.year')} value={String(year)} onChange={(e) => setYear(Number(e.target.value))} options={[year - 1, year, year + 1].map(y => ({ value: String(y), label: String(y) }))} />
              </div>
              <Button onClick={() => handleGenerate(() => generateDucs(period), t('socialDecl.generated'))}><FileText className="w-4 h-4 mr-2" />{t('socialDecl.generate')}</Button>
            </Card>
          )}

          {/* AED */}
          {tab === 'aed' && (
            <Card>
              <div className="flex gap-3 mb-4">
                <Select label={t('socialDecl.employee')} value={selectedEmployee} onChange={(e) => setSelectedEmployee(e.target.value)} options={[{ value: '', label: tCommon('common.selectEmployee') }, ...employees.map(emp => ({ value: emp.id, label: emp.name }))]} />
              </div>
              <Button disabled={!selectedEmployee} onClick={() => handleGenerate(() => generateAed(selectedEmployee), t('socialDecl.generated'))}><FileText className="w-4 h-4 mr-2" />{t('socialDecl.generate')}</Button>
            </Card>
          )}

          {/* DPAE */}
          {tab === 'dpae' && (
            <Card>
              <div className="flex gap-3 mb-4">
                <Select label={t('socialDecl.employee')} value={selectedEmployee} onChange={(e) => setSelectedEmployee(e.target.value)} options={[{ value: '', label: tCommon('common.selectEmployee') }, ...employees.map(emp => ({ value: emp.id, label: emp.name }))]} />
              </div>
              <Button disabled={!selectedEmployee} onClick={() => handleGenerate(() => generateDpae(selectedEmployee, ''), t('socialDecl.generated'))}><FileText className="w-4 h-4 mr-2" />{t('socialDecl.generate')}</Button>
            </Card>
          )}

          {/* BTP */}
          {tab === 'btp' && (
            <Card>
              <div className="flex gap-3 mb-4">
                <Select label={t('socialDecl.month')} value={String(month)} onChange={(e) => setMonth(Number(e.target.value))} options={Array.from({ length: 12 }, (_, i) => ({ value: String(i + 1), label: tCommon(`months.${i}`) }))} />
                <Select label={t('socialDecl.year')} value={String(year)} onChange={(e) => setYear(Number(e.target.value))} options={[year - 1, year, year + 1].map(y => ({ value: String(y), label: String(y) }))} />
              </div>
              <div className="flex gap-2">
                <Button onClick={() => handleGenerate(() => generateCibtp(period), t('socialDecl.generated'))}>{t('socialDecl.cibtp')}</Button>
                <Button onClick={() => handleGenerate(() => generateCongesPayesBtp(period), t('socialDecl.generated'))}>{t('socialDecl.congesPayesBtp')}</Button>
              </div>
            </Card>
          )}

          {/* MSA */}
          {tab === 'msa' && (
            <Card>
              <div className="flex gap-3 mb-4">
                <Select label={t('socialDecl.month')} value={String(month)} onChange={(e) => setMonth(Number(e.target.value))} options={Array.from({ length: 12 }, (_, i) => ({ value: String(i + 1), label: tCommon(`months.${i}`) }))} />
                <Select label={t('socialDecl.year')} value={String(year)} onChange={(e) => setYear(Number(e.target.value))} options={[year - 1, year, year + 1].map(y => ({ value: String(y), label: String(y) }))} />
              </div>
              <Button onClick={() => handleGenerate(() => generateDtsMsa(period), t('socialDecl.generated'))}><FileText className="w-4 h-4 mr-2" />{t('socialDecl.generate')}</Button>
            </Card>
          )}

          {/* CICE */}
          {tab === 'cice' && (
            <Card>
              <div className="flex gap-3 mb-4 items-end">
                <Select label={t('socialDecl.year')} value={String(year)} onChange={(e) => setYear(Number(e.target.value))} options={[year - 1, year, year + 1].map(y => ({ value: String(y), label: String(y) }))} />
                <Button onClick={handleCalculateCice}><Calculator className="w-4 h-4 mr-2" />{t('socialDecl.calculateCice')}</Button>
                <Button variant="secondary" onClick={() => handleGenerate(() => generateCiceFile(year), t('socialDecl.generated'))}><Download className="w-4 h-4 mr-2" />{t('socialDecl.generateFile')}</Button>
              </div>
              {ciceConfigs.length > 0 && (
                <div className="mb-4 p-3 bg-gray-50 rounded">
                  <p className="text-xs text-gray-600">{t('socialDecl.smicThreshold')}: {ciceConfigs[0].smic_threshold}x SMIC | {t('socialDecl.rate')}: {ciceConfigs[0].rate}%</p>
                </div>
              )}
              {ciceResults.length > 0 && (
                <Table headers={[t('socialDecl.employee'), t('socialDecl.grossSalary'), t('socialDecl.ciceAmount')]}>
                  {ciceResults.map((r, i) => (
                    <TableRow key={i}>
                      <TableCell className="text-sm">{r.employee_name}</TableCell>
                      <TableCell className="font-mono text-xs">{r.gross_salary.toFixed(2)}</TableCell>
                      <TableCell className="font-mono text-xs font-bold">{r.cice_amount.toFixed(2)}</TableCell>
                    </TableRow>
                  ))}
                </Table>
              )}
            </Card>
          )}

          {/* PASRAU */}
          {tab === 'pasrau' && (
            <Card>
              <div className="flex gap-3 mb-4">
                <Select label={t('socialDecl.year')} value={String(year)} onChange={(e) => setYear(Number(e.target.value))} options={[year - 1, year, year + 1].map(y => ({ value: String(y), label: String(y) }))} />
              </div>
              <Button onClick={() => handleGenerate(() => generatePasrau(year), t('socialDecl.generated'))}><FileText className="w-4 h-4 mr-2" />{t('socialDecl.generate')}</Button>
            </Card>
          )}

          {/* Other */}
          {tab === 'other' && (
            <Card>
              <div className="flex gap-3 mb-4">
                <Select label={t('socialDecl.month')} value={String(month)} onChange={(e) => setMonth(Number(e.target.value))} options={Array.from({ length: 12 }, (_, i) => ({ value: String(i + 1), label: tCommon(`months.${i}`) }))} />
                <Select label={t('socialDecl.year')} value={String(year)} onChange={(e) => setYear(Number(e.target.value))} options={[year - 1, year, year + 1].map(y => ({ value: String(y), label: String(y) }))} />
              </div>
              <div className="flex gap-2">
                <Button onClick={() => handleGenerate(() => generateRefusCdi(period), t('socialDecl.generated'))}>{t('socialDecl.refusCdi')}</Button>
                <Button onClick={() => handleGenerate(() => generateCt2025(period), t('socialDecl.generated'))}>{t('socialDecl.ct2025')}</Button>
              </div>
            </Card>
          )}

          {/* Rates */}
          {tab === 'rates' && (
            <div className="space-y-4">
              <Card>
                <div className="flex items-center justify-between mb-3">
                  <h3 className="font-medium">{t('socialDecl.pasRates')}</h3>
                  <label className="cursor-pointer">
                    <span className="inline-flex items-center px-3 py-1.5 bg-blue-600 text-white rounded text-sm"><Upload className="w-4 h-4 mr-2" />{t('socialDecl.importPas')}</span>
                    <input type="file" accept=".csv" className="hidden" onChange={async (e) => {
                      if (e.target.files?.[0]) { try { await importPasRates(e.target.files[0]); toast('success', t('socialDecl.imported')); loadData() } catch (err: any) { toast('error', tCommon('common.error'), err.message) } }
                    }} />
                  </label>
                </div>
                {pasRates.length === 0 ? <EmptyState title={t('socialDecl.noRates')} /> : (
                  <Table headers={[t('socialDecl.employee'), t('socialDecl.rate'), t('socialDecl.effectiveDate')]}>
                    {pasRates.map((r: any) => (
                      <TableRow key={r.id}>
                        <TableCell className="text-sm">{r.employees?.name || '-'}</TableCell>
                        <TableCell className="font-mono text-xs">{(r.rate * 100).toFixed(2)}%</TableCell>
                        <TableCell className="text-xs">{r.effective_date}</TableCell>
                      </TableRow>
                    ))}
                  </Table>
                )}
              </Card>
              <Card>
                <div className="flex items-center justify-between mb-3">
                  <h3 className="font-medium">{t('socialDecl.atRates')}</h3>
                  <label className="cursor-pointer">
                    <span className="inline-flex items-center px-3 py-1.5 bg-blue-600 text-white rounded text-sm"><Upload className="w-4 h-4 mr-2" />{t('socialDecl.importAt')}</span>
                    <input type="file" accept=".csv" className="hidden" onChange={async (e) => {
                      if (e.target.files?.[0]) { try { await importAtRates(e.target.files[0]); toast('success', t('socialDecl.imported')); loadData() } catch (err: any) { toast('error', tCommon('common.error'), err.message) } }
                    }} />
                  </label>
                </div>
                {atRates.length === 0 ? <EmptyState title={t('socialDecl.noRates')} /> : (
                  <Table headers={[t('socialDecl.employee'), t('socialDecl.rate'), t('socialDecl.bonusMalus'), t('socialDecl.riskCategory')]}>
                    {atRates.map((r: any) => (
                      <TableRow key={r.id}>
                        <TableCell className="text-sm">{r.employees?.name || '-'}</TableCell>
                        <TableCell className="font-mono text-xs">{(r.rate * 100).toFixed(2)}%</TableCell>
                        <TableCell className="font-mono text-xs">{(r.bonus_malus_rate * 100).toFixed(2)}%</TableCell>
                        <TableCell className="text-xs">{r.risk_category || '-'}</TableCell>
                      </TableRow>
                    ))}
                  </Table>
                )}
              </Card>
            </div>
          )}

          {/* Honorarium */}
          {tab === 'honorarium' && (
            <Card>
              <div className="flex items-center justify-between mb-3">
                <h3 className="font-medium">{t('socialDecl.honorarium')}</h3>
                <Button onClick={() => setShowHonorariumForm(true)}><Plus className="w-4 h-4 mr-2" />{t('socialDecl.newHonorarium')}</Button>
              </div>
              {honorariums.length === 0 ? <EmptyState title={t('socialDecl.noHonorarium')} /> : (
                <Table headers={[t('socialDecl.recipientName'), t('socialDecl.period'), t('socialDecl.amount'), t('socialDecl.status'), t('socialDecl.actions')]}>
                  {honorariums.map(h => (
                    <TableRow key={h.id}>
                      <TableCell className="text-sm">{h.recipient_name}</TableCell>
                      <TableCell className="text-xs">{h.period || '-'}</TableCell>
                      <TableCell className="font-mono text-xs">{h.amount.toFixed(2)}</TableCell>
                      <TableCell><Badge variant={h.status === 'accounted' ? 'success' : h.status === 'paid' ? 'primary' : 'neutral'}>{t(`socialDecl.honorariumStatuses.${h.status}`)}</Badge></TableCell>
                      <TableCell>
                        {h.status === 'pending' && <Button size="sm" variant="secondary" onClick={async () => { try { await updateHonorariumRecord(h.id, { status: 'paid' }); toast('success', tCommon('common.saved')); loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }}>{t('socialDecl.markPaid')}</Button>}
                        {h.status === 'paid' && <Button size="sm" variant="secondary" onClick={async () => { try { await generateHonorariumAccounting(h.id); toast('success', t('socialDecl.accounted')); loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }}>{t('socialDecl.generateAccounting')}</Button>}
                      </TableCell>
                    </TableRow>
                  ))}
                </Table>
              )}
            </Card>
          )}
        </>
      )}

      {showHonorariumForm && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <Card className="w-full max-w-md p-6">
            <h3 className="font-medium mb-4">{t('socialDecl.newHonorarium')}</h3>
            <div className="space-y-3">
              <Input label={t('socialDecl.recipientName')} value={honName} onChange={(e) => setHonName(e.target.value)} required />
              <Select label={t('socialDecl.recipientType')} value={honType} onChange={(e) => setHonType(e.target.value)} options={[{ value: 'employee', label: t('socialDecl.types.employee') }, { value: 'external', label: t('socialDecl.types.external') }, { value: 'intern', label: t('socialDecl.types.intern') }]} />
              <Input label={t('socialDecl.period')} value={honPeriod} onChange={(e) => setHonPeriod(e.target.value)} placeholder="2024-01" />
              <Input label={t('socialDecl.amount')} type="number" value={honAmount} onChange={(e) => setHonAmount(e.target.value)} required />
              <div>
                <label className="block text-sm font-medium mb-1">{t('socialDecl.description')}</label>
                <textarea className="w-full px-3 py-2 border rounded text-sm" rows={3} value={honDesc} onChange={(e) => setHonDesc(e.target.value)} />
              </div>
            </div>
            <div className="flex gap-2 mt-4">
              <Button onClick={async () => {
                try {
                  await createHonorariumRecord({
                    tenant_id: null, employee_id: null,
                    recipient_name: honName,
                    recipient_type: honType as any,
                    period: honPeriod || null,
                    amount: parseFloat(honAmount) || 0,
                    description: honDesc || null,
                    accounting_entry_id: null,
                    status: 'pending',
                  })
                  toast('success', tCommon('common.saved'))
                  setShowHonorariumForm(false)
                  setHonName(''); setHonPeriod(''); setHonAmount(''); setHonDesc('')
                  loadData()
                } catch (e: any) { toast('error', tCommon('common.error'), e.message) }
              }} disabled={!honName || !honAmount}>{tCommon('actions.save')}</Button>
              <Button variant="secondary" onClick={() => setShowHonorariumForm(false)}>{tCommon('actions.cancel')}</Button>
            </div>
          </Card>
        </div>
      )}
    </div>
  )
}
