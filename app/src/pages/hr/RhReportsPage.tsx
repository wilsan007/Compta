import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, SkeletonTable, Breadcrumb, Input, Select } from '@/components/ui'
import { Plus, Trash2, Play, BarChart3 } from 'lucide-react'
import { getRhReports, createRhReport, deleteRhReport, calculateReportData, getEffectifEvolution, getSalaryAnalysis, getAbsenceStats, getTurnoverRate, getCostByCenter } from '@/lib/queries/sprintH'
import { formatDate } from '@/lib/utils'
import { useToast } from '@/lib/toast'

export function RhReportsPage() {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const { toast } = useToast()
  const [tab, setTab] = useState<'preset' | 'saved' | 'create'>('preset')
  const [reports, setReports] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [statsData, setStatsData] = useState<any>(null)
  const [activeReport, setActiveReport] = useState<string | null>(null)
  const [newReport, setNewReport] = useState({ name: '', report_type: 'effectifs', chart_type: 'bar' })

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const r = await getRhReports()
      setReports(r)
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setLoading(false) }
  }, [toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  async function handleGenerate(type: string) {
    setActiveReport(type)
    try {
      let data: any
      switch (type) {
        case 'effectifs': data = await getEffectifEvolution(12); break
        case 'remuneration': data = await getSalaryAnalysis('department'); break
        case 'absenteeism': data = await getAbsenceStats('department'); break
        case 'turnover': data = await getTurnoverRate('year'); break
        case 'costs': data = await getCostByCenter('year'); break
        default: data = null
      }
      setStatsData(data)
      toast('success', tCommon('common.success'), tCommon('common.saved'))
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    }
  }

  async function handleCalculate(reportId: string) {
    try {
      await calculateReportData(reportId)
      toast('success', tCommon('common.success'), tCommon('common.saved'))
      loadData().catch(err => console.error('loadData:', err))
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    }
  }

  async function handleDelete(id: string) {
    try {
      await deleteRhReport(id)
      toast('success', tCommon('common.success'), tCommon('common.saved'))
      loadData().catch(err => console.error('loadData:', err))
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    }
  }

  async function handleCreate(e: React.FormEvent) {
    e.preventDefault()
    try {
      await createRhReport({ ...newReport, parameters: {}, data: null, data_calculated_at: null, created_by: null, shared: false } as any)
      toast('success', tCommon('common.success'), tCommon('common.saved'))
      setNewReport({ name: '', report_type: 'effectifs', chart_type: 'bar' })
      loadData().catch(err => console.error('loadData:', err))
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    }
  }

  const reportTypes = [
    { key: 'effectifs', label: t('reports.effectifs', 'Évolution des effectifs') },
    { key: 'remuneration', label: t('reports.remuneration', 'Analyse rémunérations') },
    { key: 'absenteeism', label: t('reports.absenteeism', "Taux d'absentéisme") },
    { key: 'turnover', label: t('reports.turnover', 'Taux de rotation') },
    { key: 'costs', label: t('reports.costs', 'Coûts par centre') },
  ]

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('groups.hr') }, { label: t('reports.title', 'Rapports RH') }]} />
      <PageHeader title={t('reports.title', 'Rapports RH')} subtitle={t('reports.subtitle', 'Reportings et statistiques')} />

      <div className="flex gap-2 mb-4">
        <Button variant={tab === 'preset' ? 'primary' : 'ghost'} onClick={() => setTab('preset')}>{t('reports.preset', 'Rapports pré-paramétrés')}</Button>
        <Button variant={tab === 'saved' ? 'primary' : 'ghost'} onClick={() => setTab('saved')}>{t('reports.saved', 'Rapports sauvegardés')}</Button>
        <Button variant={tab === 'create' ? 'primary' : 'ghost'} onClick={() => setTab('create')}>{t('reports.create', 'Créer un rapport')}</Button>
      </div>

      {loading ? <SkeletonTable rows={4} cols={4} /> : tab === 'preset' ? (
        <div className="space-y-4">
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {reportTypes.map(rt => (
              <Card key={rt.key}>
                <div className="p-4">
                  <div className="flex items-center justify-between mb-3">
                    <BarChart3 className="w-6 h-6 text-[var(--color-primary)]" />
                    <Button size="sm" variant="ghost" onClick={() => handleGenerate(rt.key)}><Play className="w-3 h-3" /> {t('reports.generate', 'Générer')}</Button>
                  </div>
                  <p className="text-sm font-medium">{rt.label}</p>
                </div>
              </Card>
            ))}
          </div>
          {activeReport && statsData && (
            <Card>
              <h3 className="text-sm font-semibold p-4 border-b border-[var(--color-border)]">{reportTypes.find(r => r.key === activeReport)?.label}</h3>
              <div className="p-4">
                {Array.isArray(statsData) ? (
                  <Table headers={activeReport === 'effectifs' ? ['Mois', 'Entrées', 'Sorties', 'Net'] : ['Clé', 'Valeur']}>
                    {statsData.map((item: any, i: number) => activeReport === 'effectifs' ? (
                      <TableRow key={i}>
                        <TableCell className="text-sm">{item.month}</TableCell>
                        <TableCell className="font-mono text-xs">{item.hires}</TableCell>
                        <TableCell className="font-mono text-xs">{item.exits}</TableCell>
                        <TableCell className="font-mono text-xs font-bold">{item.net}</TableCell>
                      </TableRow>
                    ) : (
                      <TableRow key={i}>
                        <TableCell className="text-sm">{Object.keys(item)[0]}</TableCell>
                        <TableCell className="font-mono text-xs">{String(Object.values(item)[0])}</TableCell>
                      </TableRow>
                    ))}
                  </Table>
                ) : typeof statsData === 'object' ? (
                  <Table headers={['Catégorie', 'Valeur']}>
                    {Object.entries(statsData).map(([key, val]: [string, any]) => (
                      <TableRow key={key}>
                        <TableCell className="text-sm">{key}</TableCell>
                        <TableCell className="font-mono text-xs">{typeof val === 'object' ? JSON.stringify(val) : val}</TableCell>
                      </TableRow>
                    ))}
                  </Table>
                ) : null}
              </div>
            </Card>
          )}
        </div>
      ) : tab === 'saved' ? (
        <Card>
          <Table headers={[t('reports.name', 'Nom'), t('reports.type', 'Type'), t('reports.created', 'Créé le'), tCommon('table.actions')]}>
            {reports.map(r => (
              <TableRow key={r.id}>
                <TableCell className="text-sm font-medium">{r.name}</TableCell>
                <TableCell className="text-xs">{r.report_type}</TableCell>
                <TableCell className="text-xs">{formatDate(r.created_at)}</TableCell>
                <TableCell>
                  <div className="flex gap-1">
                    <Button size="sm" variant="ghost" onClick={() => handleCalculate(r.id)} ariaLabel={tCommon('actions.start')}><Play className="w-3 h-3" aria-hidden="true" /></Button>
                    <Button size="sm" variant="danger" onClick={() => handleDelete(r.id)} ariaLabel={tCommon('actions.delete')}><Trash2 className="w-3 h-3" aria-hidden="true" /></Button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
            {reports.length === 0 && <TableRow><TableCell colSpan={4} className="text-center text-[var(--color-text-secondary)] text-sm">{t('reports.noReports', 'Aucun rapport sauvegardé')}</TableCell></TableRow>}
          </Table>
        </Card>
      ) : (
        <Card>
          <form onSubmit={handleCreate} className="p-4 space-y-3">
            <div>
              <label className="text-xs text-[var(--color-text-secondary)]">{t('reports.name', 'Nom')}</label>
              <Input value={newReport.name} onChange={e => setNewReport({ ...newReport, name: e.target.value })} required />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="text-xs text-[var(--color-text-secondary)]">{t('reports.type', 'Type')}</label>
                <Select value={newReport.report_type} onChange={e => setNewReport({ ...newReport, report_type: e.target.value })} options={[
                  { value: 'effectifs', label: t('reports.effectifs', 'Effectifs') },
                  { value: 'remuneration', label: t('reports.remuneration', 'Rémunérations') },
                  { value: 'absenteeism', label: t('reports.absenteeism', 'Absentéisme') },
                  { value: 'turnover', label: t('reports.turnover', 'Turnover') },
                  { value: 'costs', label: t('reports.costs', 'Coûts') },
                  { value: 'custom', label: t('reports.custom', 'Personnalisé') },
                ]} />
              </div>
              <div>
                <label className="text-xs text-[var(--color-text-secondary)]">{t('reports.chartType', 'Type de graphique')}</label>
                <Select value={newReport.chart_type} onChange={e => setNewReport({ ...newReport, chart_type: e.target.value })} options={[
                  { value: 'bar', label: 'Bar' },
                  { value: 'line', label: 'Line' },
                  { value: 'pie', label: 'Pie' },
                  { value: 'table', label: 'Table' },
                ]} />
              </div>
            </div>
            <Button type="submit"><Plus className="w-4 h-4" /> {t('reports.save', 'Sauvegarder')}</Button>
          </form>
        </Card>
      )}
    </div>
  )
}
