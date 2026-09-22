import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, SkeletonTable, Breadcrumb, Table, TableRow, TableCell, Button, Select } from '@/components/ui'
import { getBalanceSheet, getFiscalYears } from '@/lib/queries/accounting'
import { generateBalanceSheet } from '@/lib/queries/businessFunctions'
import { formatCurrency } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import type { FiscalYear } from '@/types'

export function BalanceSheetPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [data, setData] = useState<{ assets: any[]; liabilities: any[]; equity: any[]; unclassified: any[]; gap: number } | null>(null)
  const [loading, setLoading] = useState(true)
  const [years, setYears] = useState<FiscalYear[]>([])
  const [selectedYear, setSelectedYear] = useState('')
  const [generating, setGenerating] = useState(false)

  useEffect(() => {
    getFiscalYears().then((fy) => {
      setYears(fy || [])
      // Exercice ouvert qui couvre la date du jour, sinon le premier ouvert, sinon le plus récent
      const today = new Date().toISOString().slice(0, 10)
      const list = fy || []
      const pick = list.find((y) => y.status === 'open' && y.start_date <= today && today <= y.end_date)
        ?? list.find((y) => y.status === 'open')
        ?? list[0]
      if (pick) setSelectedYear(pick.id)
      else setLoading(false)
    }).catch((err: any) => {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadingError'))
      setLoading(false)
    })
  }, [toast, tCommon])

  // AUD-D08 : le bilan affiché est celui de l'exercice sélectionné (auparavant toujours le plus récent)
  const loadData = useCallback(async () => {
    if (!selectedYear) return
    setLoading(true)
    try {
      setData(await getBalanceSheet({ fiscalYearId: selectedYear }))
    } catch (err: any) { console.error('Failed to load balance sheet:', err)
    toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadingError'))
    } finally {
      setLoading(false)
    }
  }, [selectedYear, toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  async function handleGenerate() {
    if (!selectedYear) return
    setGenerating(true)
    try {
      await generateBalanceSheet(selectedYear)
      toast('success', tCommon('common.success'), t('balanceSheet.generated'))
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally {
      setGenerating(false)
    }
  }

  const totalAssets = (data?.assets || []).reduce((s, a) => s + (a.debit - a.credit), 0)
  const totalLiabilities = (data?.liabilities || []).reduce((s, l) => s + (l.credit - l.debit), 0)
  const totalEquity = (data?.equity || []).reduce((s, e) => s + (e.credit - e.debit), 0)

  return (
    <div>
      <Breadcrumb items={[{ label: t('balanceSheet.breadcrumb') }, { label: t('balanceSheet.title') }]} />
      <PageHeader title={t('balanceSheet.title')} subtitle={t('balanceSheet.subtitle')} action={
        <div className="flex items-center gap-2">
          <Select
            value={selectedYear}
            onChange={(e) => setSelectedYear(e.target.value)}
            options={years.map((y) => ({ value: y.id, label: y.code }))}
          />
          <Button onClick={handleGenerate} disabled={generating || !selectedYear}>
            {generating ? tCommon('common.loading') : t('balanceSheet.generate')}
          </Button>
        </div>
      } />

      {!loading && data && data.gap !== 0 && (
        <div role="alert" className="mb-4 rounded-lg border border-[var(--color-danger)] bg-[var(--color-danger)]/10 px-4 py-3 text-sm text-[var(--color-danger)]">
          {t('balanceSheet.unbalanced', {
            assets: formatCurrency(totalAssets),
            liabilities: formatCurrency(totalLiabilities + totalEquity),
            gap: formatCurrency(data.gap),
          })}
        </div>
      )}

      {loading ? (
        <SkeletonTable rows={6} cols={3} />
      ) : (
        <div className="grid grid-cols-2 gap-6">
          <div>
            <h3 className="text-sm font-semibold mb-3">{t('balanceSheet.assets')}</h3>
            <Card>
              <Table headers={[t('balanceSheet.code'), t('balanceSheet.account'), t('balanceSheet.amount')]}>
                {(data?.assets || []).map((a) => (
                  <TableRow key={a.code}>
                    <TableCell className="font-mono text-xs">{a.code}</TableCell>
                    <TableCell className="text-sm">{a.name}</TableCell>
                    <TableCell className="font-mono text-right">{formatCurrency(a.debit - a.credit)}</TableCell>
                  </TableRow>
                ))}
                <TableRow>
                  <TableCell /><TableCell className="font-bold">{t('balanceSheet.totalAssets')}</TableCell>
                  <TableCell className="font-mono text-right font-bold text-base">{formatCurrency(totalAssets)}</TableCell>
                </TableRow>
              </Table>
            </Card>
          </div>
          <div>
            <h3 className="text-sm font-semibold mb-3">{t('balanceSheet.liabilities')}</h3>
            <Card>
              <Table headers={[t('balanceSheet.code'), t('balanceSheet.account'), t('balanceSheet.amount')]}>
                {(data?.liabilities || []).map((l) => (
                  <TableRow key={l.code}>
                    <TableCell className="font-mono text-xs">{l.code}</TableCell>
                    <TableCell className="text-sm">{l.name}</TableCell>
                    <TableCell className="font-mono text-right">{formatCurrency(l.credit - l.debit)}</TableCell>
                  </TableRow>
                ))}
                {(data?.equity || []).map((e) => (
                  <TableRow key={e.code}>
                    <TableCell className="font-mono text-xs">{e.code}</TableCell>
                    <TableCell className="text-sm">{e.name}</TableCell>
                    <TableCell className="font-mono text-right">{formatCurrency(e.credit - e.debit)}</TableCell>
                  </TableRow>
                ))}
                <TableRow>
                  <TableCell /><TableCell className="font-bold">{t('balanceSheet.totalLiabilitiesEquity')}</TableCell>
                  <TableCell className="font-mono text-right font-bold text-base">{formatCurrency(totalLiabilities + totalEquity)}</TableCell>
                </TableRow>
              </Table>
            </Card>
          </div>
          {(data?.unclassified || []).length > 0 && (
            <div className="col-span-2">
              <h3 className="text-sm font-semibold mb-1">{t('balanceSheet.unclassified')}</h3>
              <p className="text-xs text-[var(--color-text-secondary)] mb-3">{t('balanceSheet.unclassifiedHint')}</p>
              <Card>
                <Table headers={[t('balanceSheet.code'), t('balanceSheet.account'), t('balanceSheet.amount')]}>
                  {(data?.unclassified || []).map((u) => (
                    <TableRow key={u.code}>
                      <TableCell className="font-mono text-xs">{u.code}</TableCell>
                      <TableCell className="text-sm">{u.name}</TableCell>
                      <TableCell className="font-mono text-right">{formatCurrency(u.debit - u.credit)}</TableCell>
                    </TableRow>
                  ))}
                </Table>
              </Card>
            </div>
          )}
        </div>
      )}
    </div>
  )
}
