import { useEffect, useState, useMemo } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Select } from '@/components/ui'
import { useLocale } from '@/hooks/useLocale'
import { getSIGData, getFiscalYears } from '@/lib/queries'
import { TrendingUp } from 'lucide-react'
import type { FiscalYear } from '@/types'

export function SIGPage() {
  const { t } = useTranslation('accounting')
  const { formatCurrency } = useLocale()
  const [data, setData] = useState<any[]>([])
  const [years, setYears] = useState<FiscalYear[]>([])
  const [selectedYear, setSelectedYear] = useState('')
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    loadYears()
  }, [])

  async function loadYears() {
    try {
      const fy = await getFiscalYears()
      setYears(fy || [])
    } catch (err) {
      console.error('Error loading fiscal years:', err)
    }
  }

  useEffect(() => {
    loadSIG()
  }, [selectedYear])

  async function loadSIG() {
    setLoading(true)
    try {
      const res = await getSIGData(selectedYear || undefined)
      setData(res)
    } catch (err) {
      console.error('Error loading SIG:', err)
    } finally {
      setLoading(false)
    }
  }

  const sig = useMemo(() => {
    const getSolde = (prefix: string) =>
      data.filter((d) => d.code.startsWith(prefix)).reduce((s, d) => s + d.solde, 0)

    const ventes = getSolde('70')
    const productionStockee = -getSolde('71')
    const immobilisations = -getSolde('72')
    const autresProduits = getSolde('74') + getSolde('75') + getSolde('78') + getSolde('79')
    const achats = getSolde('60')
    const variationsStock = getSolde('603')
    const servicesExt = getSolde('61')
    const autresCharges = getSolde('62') + getSolde('63') + getSolde('65')
    const chargesFinancieres = getSolde('66')
    const chargesExceptionnelles = getSolde('67')
    const dotations = getSolde('68')
    const impots = getSolde('69')

    const margeCommerciale = ventes - achats
    const valeurAjoutee = margeCommerciale + productionStockee + immobilisations - variationsStock - servicesExt
    const ebe = valeurAjoutee + autresProduits - autresCharges - impots
    const resultatExploitation = ebe - dotations
    const resultatFinancier = -chargesFinancieres
    const resultatExceptionnel = -chargesExceptionnelles
    const resultatNet = resultatExploitation + resultatFinancier + resultatExceptionnel

    return [
      { label: t('sig.salesGoods'), value: ventes, isTotal: false },
      { label: t('sig.commercialMargin'), value: margeCommerciale, isTotal: true },
      { label: t('sig.storedProduction'), value: productionStockee, isTotal: false },
      { label: t('sig.immobilizations'), value: immobilisations, isTotal: false },
      { label: t('sig.otherProducts'), value: autresProduits, isTotal: false },
      { label: t('sig.addedValue'), value: valeurAjoutee, isTotal: true },
      { label: t('sig.purchases'), value: -achats, isTotal: false },
      { label: t('sig.stockVariation'), value: -variationsStock, isTotal: false },
      { label: t('sig.externalServices'), value: -servicesExt, isTotal: false },
      { label: t('sig.otherCharges'), value: -autresCharges, isTotal: false },
      { label: t('sig.taxes'), value: -impots, isTotal: false },
      { label: t('sig.ebe'), value: ebe, isTotal: true },
      { label: t('sig.depreciation'), value: -dotations, isTotal: false },
      { label: t('sig.operatingResult'), value: resultatExploitation, isTotal: true },
      { label: t('sig.financialCharges'), value: -chargesFinancieres, isTotal: false },
      { label: t('sig.financialResult'), value: resultatFinancier, isTotal: true },
      { label: t('sig.exceptionalCharges'), value: -chargesExceptionnelles, isTotal: false },
      { label: t('sig.exceptionalResult'), value: resultatExceptionnel, isTotal: true },
      { label: t('sig.netResultFinal'), value: resultatNet, isTotal: true, isFinal: true },
    ]
  }, [data, t])

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('home.states') }, { label: 'SIG' }]} />
      <PageHeader title={t('sig.title')} subtitle={t('sig.subtitle')} />

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-56">
          <Select
            label={t('sig.fiscalYear')}
            value={selectedYear}
            onChange={(e) => setSelectedYear(e.target.value)}
            options={[{ value: '', label: t('sig.all') }, ...years.map((y) => ({ value: y.id, label: y.code }))]}
          />
        </div>
      </div>

      {loading ? (
        <SkeletonTable rows={10} cols={2} />
      ) : data.length === 0 ? (
        <EmptyState
          icon={<TrendingUp className="w-8 h-8" />}
          title={t('sig.noData')}
          description={t('sig.noDataDescription')}
        />
      ) : (
        <Card>
          <Table headers={[t('sig.category'), t('sig.amountCol')]}>
            {sig.map((row, i) => (
              <TableRow key={i}>
                <TableCell className={row.isFinal ? 'font-bold text-base' : row.isTotal ? 'font-semibold' : 'text-sm'}>
                  {row.label}
                </TableCell>
                <TableCell className={`font-mono text-right ${row.isFinal ? 'font-bold text-base' : row.isTotal ? 'font-semibold' : ''} ${row.value >= 0 ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>
                  {formatCurrency(row.value)}
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}
    </div>
  )
}
