import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable } from '@/components/ui'
import { getFiscalYears, closeFiscalYear } from '@/lib/queries'
import { Lock, AlertTriangle } from 'lucide-react'
import type { FiscalYear } from '@/types'
import { useToast } from '@/lib/toast'

export function FiscalYearClosurePage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
const [years, setYears] = useState<FiscalYear[]>([])
  const [loading, setLoading] = useState(true)
  const [closing, setClosing] = useState(false)
  const [selectedYear, setSelectedYear] = useState('')
  const [targetYear, setTargetYear] = useState('')

  useEffect(() => { load() }, [])

  async function load() {
  try {
      const data = await getFiscalYears()
      setYears(data || [])
      const openYears = (data || []).filter((y) => y.status === 'open')
      if (openYears.length > 0) setSelectedYear(openYears[0].id)
    } catch (err) {
      console.error('Error loading fiscal years:', err)
    } finally {
      setLoading(false)
    }
  }

  async function handleClose() {
    if (!selectedYear || !targetYear) {
      toast('warning', tCommon('common.warning'), t('fiscalYearClosure.selectYearAndTarget'))
      return
    }
    if (selectedYear === targetYear) {
      toast('warning', tCommon('common.warning'), t('fiscalYearClosure.targetMustDiffer'))
      return
    }
    if (!window.confirm(t('fiscalYearClosure.confirmClose'))) return
    setClosing(true)
    try {
      const result = await closeFiscalYear(selectedYear, targetYear)
      toast('success', t('fiscalYearClosure.closed'), t('fiscalYearClosure.openingLinesGenerated', { count: result?.openingLinesCount || 0 }))
      await load()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally {
      setClosing(false)
    }
  }

  const openYears = years.filter((y) => y.status === 'open')
  const selectedYearObj = years.find((y) => y.id === selectedYear)
  const tableHeaders = [t('fiscalYearClosure.code'), t('fiscalYearClosure.label'), t('fiscalYearClosure.status'), t('fiscalYearClosure.actions')]

  if (loading) {
    return (
      <div>
        <Breadcrumb items={[{ label: t('home.breadcrumb') }, { label: t('treatment.breadcrumb') }, { label: t('fiscalYearClosure.breadcrumb') }]} />
        <PageHeader title={t('fiscalYearClosure.title')} subtitle={tCommon('common.loading')} />
        <SkeletonTable rows={4} cols={4} />
      </div>
    )
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb') }, { label: t('treatment.breadcrumb') }, { label: t('fiscalYearClosure.breadcrumb') }]} />
      <PageHeader title={t('fiscalYearClosure.title')} subtitle={t('fiscalYearClosure.subtitle')} />

      {years.length === 0 ? (
        <EmptyState
          icon={<Lock className="w-8 h-8" />}
          title={t('fiscalYearClosure.noYears')}
          description={t('fiscalYearClosure.noYearsDescription')}
        />
      ) : (
        <div className="space-y-4">
          <Card>
            <div className="p-4 space-y-4">
              <h3 className="text-sm font-semibold">{t('fiscalYearClosure.availableYears')}</h3>
              <Table headers={tableHeaders}>
                {years.map((y) => (
                  <TableRow key={y.id}>
                    <TableCell className="font-mono text-sm font-semibold">{y.code}</TableCell>
                    <TableCell className="text-sm">{y.code}</TableCell>
                    <TableCell>
                      <Badge variant={y.status === 'open' ? 'success' : 'danger'}>
                        {y.status === 'open' ? tCommon('common.open') : tCommon('common.closed')}
                      </Badge>
                    </TableCell>
                    <TableCell>
                      {y.status === 'open' && (
                        <Button variant="secondary" onClick={() => setSelectedYear(y.id)}>{t('fiscalYearClosure.select')}</Button>
                      )}
                    </TableCell>
                  </TableRow>
                ))}
              </Table>
            </div>
          </Card>

          {selectedYearObj && (
            <Card>
              <div className="p-4 space-y-4">
                <h3 className="text-sm font-semibold">{t('fiscalYearClosure.closeYear', { code: selectedYearObj.code })}</h3>
                <div className="flex items-center gap-3 p-3 rounded-lg bg-[var(--color-warning)]/10 border border-[var(--color-warning)]/30">
                  <AlertTriangle className="w-5 h-5 text-[var(--color-warning)] flex-shrink-0" />
                  <p className="text-sm text-[var(--color-text-secondary)]">
                    {t('fiscalYearClosure.warningMessage')}
                  </p>
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('fiscalYearClosure.yearToClose')}</label>
                    <select className="input" value={selectedYear} onChange={(e) => setSelectedYear(e.target.value)}>
                      {openYears.map((y) => <option key={y.id} value={y.id}>{y.code}</option>)}
                    </select>
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('fiscalYearClosure.targetYear')}</label>
                    <select className="input" value={targetYear} onChange={(e) => setTargetYear(e.target.value)}>
                      <option value="">{t('fiscalYearClosure.selectPlaceholder')}</option>
                      {years.map((y) => <option key={y.id} value={y.id}>{y.code}</option>)}
                    </select>
                  </div>
                </div>
                <div className="flex justify-end">
                  <Button onClick={handleClose} disabled={closing || !targetYear || selectedYear === targetYear}>
                    <Lock className="w-4 h-4" /> {closing ? t('fiscalYearClosure.closing') : t('fiscalYearClosure.close')}
                  </Button>
                </div>
              </div>
            </Card>
          )}
        </div>
      )}
    </div>
  )
}
