import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, EmptyState, AutoBreadcrumb, Input, Badge } from '@/components/ui'
import { useToast } from '@/lib/toast'
import { getActiveLegislationPack, getActiveCorporateTaxGrid, getCorporateTaxGridLines } from '@/lib/queries/accounting'
import { calculateCorporateTax, type CorporateTaxResult } from '@/lib/taxCalculator'
import { Calculator, Building2, Globe } from 'lucide-react'
import type { CorporateTaxGridLine, LegislationPack } from '@/types'

export function CorporateTaxCalcPage() {
  const { t } = useTranslation('features')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [loading, setLoading] = useState(true)
  const [result, setResult] = useState<CorporateTaxResult | null>(null)
  const [isLines, setIsLines] = useState<CorporateTaxGridLine[]>([])
  const [minTaxLines, setMinTaxLines] = useState<CorporateTaxGridLine[]>([])
  const [legislationPack, setLegislationPack] = useState<LegislationPack | null>(null)
  const [usingGrid, setUsingGrid] = useState(false)

  const [profit, setProfit] = useState(100000)
  const [turnover, setTurnover] = useState(500000)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const pack = await getActiveLegislationPack().catch(() => null)
      setLegislationPack(pack)

      if (pack?.country_code) {
        const isGrid = await getActiveCorporateTaxGrid(pack.country_code, 'corporate_income_tax').catch(() => undefined)
        if (isGrid) {
          const lines = await getCorporateTaxGridLines(isGrid.id).catch(() => [])
          if (lines.length > 0) {
            setIsLines(lines)
            setUsingGrid(true)
            const minGrid = await getActiveCorporateTaxGrid(pack.country_code, 'minimum_tax').catch(() => undefined)
            if (minGrid) {
              const minLines = await getCorporateTaxGridLines(minGrid.id).catch(() => [])
              setMinTaxLines(minLines)
            }
            return
          }
        }
      }
      setUsingGrid(false)
    } catch (err: any) {
      console.error('Error loading corporate tax data:', err)
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadingError'))
    } finally {
      setLoading(false)
    }
  }, [tCommon, toast])

  useEffect(() => {
    loadData().catch(err => console.error('loadData:', err))
  }, [loadData])

  function handleCalculate() {
    if (!usingGrid || isLines.length === 0) return
    setResult(calculateCorporateTax(profit, turnover, isLines, minTaxLines.length > 0 ? minTaxLines : undefined))
  }

  return (
    <div className="animate-fade-in">
      <AutoBreadcrumb />
      <PageHeader title={t('corporateTax.title')} subtitle={t('corporateTax.subtitle')} />

      <Card className="mb-4">
        <div className="p-4">
          <div className="flex items-center gap-2 mb-4">
            <p className="text-sm text-[var(--color-text-secondary)]">{t('corporateTax.intro')}</p>
            {legislationPack && (
              <Badge variant={usingGrid ? 'success' : 'warning'}>
                <Globe className="w-3 h-3 mr-1 inline" />
                {legislationPack.country_name}
                {usingGrid ? ' — ' + t('corporateTax.gridLoaded') : ' — ' + t('corporateTax.noGrid')}
              </Badge>
            )}
          </div>
          <div className="grid md:grid-cols-2 gap-4">
            <div>
              <Input
                label={t('corporateTax.turnover')}
                type="number"
                value={String(turnover)}
                onChange={(e) => setTurnover(Number(e.target.value))}
              />
            </div>
            <div>
              <Input
                label={t('corporateTax.profit')}
                type="number"
                value={String(profit)}
                onChange={(e) => setProfit(Number(e.target.value))}
              />
            </div>
          </div>
          <div className="mt-4">
            <Button onClick={handleCalculate} disabled={!usingGrid}>
              <Calculator className="w-4 h-4" /> {t('corporateTax.calculate')}
            </Button>
          </div>
        </div>
      </Card>

      {loading ? (
        <Card><div className="p-8 text-center text-[var(--color-text-secondary)]">...</div></Card>
      ) : !usingGrid ? (
        <EmptyState
          icon={<Building2 className="w-8 h-8" />}
          title={t('corporateTax.noGrid')}
          description={t('corporateTax.noGridDesc')}
        />
      ) : result ? (
        <Card>
          <div className="p-4">
            <h3 className="text-sm font-semibold mb-4">{t('corporateTax.results')}</h3>
            <div className="grid md:grid-cols-2 gap-6">
              <div className="space-y-2">
                <h4 className="text-xs font-semibold uppercase text-[var(--color-text-secondary)]">
                  {t('corporateTax.taxableBase')}
                </h4>
                <Row label={t('corporateTax.turnover')} value={formatNum(result.taxableBase)} />
                <Row label={t('corporateTax.profit')} value={formatNum(result.taxableBase)} bold />
              </div>
              <div className="space-y-2">
                <h4 className="text-xs font-semibold uppercase text-[var(--color-text-secondary)]">
                  {t('corporateTax.taxCalculation')}
                </h4>
                <Row label={t('corporateTax.isTax')} value={formatNum(result.taxAmount)} />
                {result.minimumTax > 0 && (
                  <Row label={t('corporateTax.minimumTax')} value={formatNum(result.minimumTax)} />
                )}
                <Row label={t('corporateTax.finalTax')} value={formatNum(result.finalTax)} bold highlight />
                <div className="pt-2 border-t border-[var(--color-border)]">
                  <Row label={t('corporateTax.afterTaxProfit')} value={formatNum(result.afterTaxProfit)} bold />
                </div>
              </div>
            </div>
            {result.breakdown.length > 0 && (
              <div className="mt-4 pt-4 border-t border-[var(--color-border)]">
                <h4 className="text-xs font-semibold uppercase text-[var(--color-text-secondary)] mb-2">
                  {t('corporateTax.breakdown')}
                </h4>
                <div className="space-y-1">
                  {result.breakdown.map((b, i) => (
                    <div key={i} className="flex justify-between text-sm">
                      <span className="text-[var(--color-text-secondary)]">
                        {b.label} ({b.rate}%)
                      </span>
                      <span className="font-mono">{formatNum(b.amount)}</span>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        </Card>
      ) : null}
    </div>
  )
}

function formatNum(n: number): string {
  return n.toFixed(2)
}

function Row({ label, value, bold, highlight }: { label: string; value: string; bold?: boolean; highlight?: boolean }) {
  return (
    <div
      className={`flex justify-between items-center py-1 ${bold ? 'font-bold' : ''} ${highlight ? 'text-[var(--color-primary)] text-lg' : ''}`}
    >
      <span className="text-sm text-[var(--color-text-secondary)]">{label}</span>
      <span className="font-mono">{value}</span>
    </div>
  )
}
