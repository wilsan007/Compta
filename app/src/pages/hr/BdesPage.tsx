import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Select } from '@/components/ui'
import { getBdesIndicators, calculateBdesIndicators, generateBdesReport, generateSocialReport } from '@/lib/queries'
import type { BdesIndicator } from '@/types'
import { useToast } from '@/lib/toast'
import { Calculator, Download, FileText } from 'lucide-react'

type Category = 'effectifs' | 'remuneration' | 'formation' | 'conditions_travail' | 'hygiene_securite' | 'relations_sociales' | 'egalite_f_h'

export function BdesPage() {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const { toast } = useToast()
  const [loading, setLoading] = useState(true)
  const [year, setYear] = useState(new Date().getFullYear())
  const [indicators, setIndicators] = useState<BdesIndicator[]>([])
  const [category, setCategory] = useState<Category | 'all'>('all')

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const data = await getBdesIndicators(year)
      setIndicators(data)
    } catch (e: any) {
      toast('error', tCommon('common.error'), e.message)
    } finally {
      setLoading(false)
    }
  }, [year, toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  const handleCalculate = async () => {
    try {
      await calculateBdesIndicators(year)
      toast('success', t('bdes.calculated'))
      loadData()
    } catch (e: any) {
      toast('error', tCommon('common.error'), e.message)
    }
  }

  const handleGenerateReport = async () => {
    try {
      await generateBdesReport(year)
      toast('success', t('bdes.reportGenerated'))
    } catch (e: any) {
      toast('error', tCommon('common.error'), e.message)
    }
  }

  const handleGenerateSocialReport = async () => {
    try {
      await generateSocialReport(year)
      toast('success', t('bdes.socialReportGenerated'))
    } catch (e: any) {
      toast('error', tCommon('common.error'), e.message)
    }
  }

  const categories: { key: Category | 'all'; label: string }[] = [
    { key: 'all', label: t('bdes.allCategories') },
    { key: 'effectifs', label: t('bdes.categories.effectifs') },
    { key: 'remuneration', label: t('bdes.categories.remuneration') },
    { key: 'formation', label: t('bdes.categories.formation') },
    { key: 'conditions_travail', label: t('bdes.categories.conditions_travail') },
    { key: 'hygiene_securite', label: t('bdes.categories.hygiene_securite') },
    { key: 'relations_sociales', label: t('bdes.categories.relations_sociales') },
    { key: 'egalite_f_h', label: t('bdes.categories.egalite_f_h') },
  ]

  const filtered = category === 'all' ? indicators : indicators.filter(i => i.category === category)

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.hr') }, { label: t('bdes.title') }]} />
      <PageHeader title={t('bdes.title')} subtitle={t('bdes.subtitle')} />

      <div className="flex gap-3 mb-4 items-end">
        <Select label={t('bdes.year')} value={String(year)} onChange={(e) => setYear(Number(e.target.value))} options={[year - 2, year - 1, year, year + 1].map(y => ({ value: String(y), label: String(y) }))} />
        <Button onClick={handleCalculate}><Calculator className="w-4 h-4 mr-2" />{t('bdes.calculate')}</Button>
        <Button variant="secondary" onClick={handleGenerateReport}><Download className="w-4 h-4 mr-2" />{t('bdes.generateReport')}</Button>
        <Button variant="secondary" onClick={handleGenerateSocialReport}><FileText className="w-4 h-4 mr-2" />{t('bdes.generateSocialReport')}</Button>
      </div>

      <div className="flex flex-wrap gap-2 mb-4">
        {categories.map(cat => (
          <Button key={cat.key} variant={category === cat.key ? 'primary' : 'secondary'} onClick={() => setCategory(cat.key)}>
            {cat.label}
          </Button>
        ))}
      </div>

      {loading ? <SkeletonTable /> : filtered.length === 0 ? (
        <EmptyState title={t('bdes.noIndicators')} description={t('bdes.noIndicatorsDescription')} />
      ) : (
        <Card>
          <Table headers={[t('bdes.indicatorName'), t('bdes.indicatorValue'), t('bdes.previousYear'), t('bdes.target'), t('bdes.unit')]}>
            {filtered.map(ind => (
              <TableRow key={ind.id}>
                <TableCell className="text-sm font-medium">{ind.indicator_name}</TableCell>
                <TableCell className="font-mono text-xs font-bold">{ind.indicator_value?.toFixed(2) || '-'}</TableCell>
                <TableCell className="font-mono text-xs text-gray-500">{ind.previous_year_value?.toFixed(2) || '-'}</TableCell>
                <TableCell className="font-mono text-xs">{ind.target_value?.toFixed(2) || '-'}</TableCell>
                <TableCell className="text-xs"><Badge variant="neutral">{ind.indicator_unit || '-'}</Badge></TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}
    </div>
  )
}
