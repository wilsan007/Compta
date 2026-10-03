import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Select, Button } from '@/components/ui'
import { errorMessage, formatCurrency, formatDate } from '@/lib/utils'
import { getTreasuryForecast } from '@/lib/queries/accounting'
import { cashFlowForecast } from '@/lib/queries/businessFunctions'
import { TrendingUp, TrendingDown, Calendar } from 'lucide-react'
import { useToast } from '@/lib/toast'

export function TreasuryForecastPage() {
  const { t } = useTranslation('treasury')
  const { toast } = useToast()
  const { t: tCommon } = useTranslation('common')
  const [data, setData] = useState<any>(null)
  const [loading, setLoading] = useState(true)
  const [horizon, setHorizon] = useState('90')
  const [forecastLoading, setForecastLoading] = useState(false)

  // oxlint-disable-next-line react-hooks/exhaustive-deps -- chargement volontairement limite aux valeurs listees
  useEffect(() => { load() }, [horizon])

  async function load() {
    setLoading(true)
    try {
      const res = await getTreasuryForecast(Number(horizon))
      setData(res)
    } catch (err) {
      console.error('Error loading treasury forecast:', err)
      toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.loadingError'))
    } finally {
      setLoading(false)
    }
  }

  async function handleCashFlowForecast() {
    setForecastLoading(true)
    try {
      const result = await cashFlowForecast(Number(horizon) || 90)
      // ⚠️ CETTE LIGNE LISAIT `net_flow` ET `projected_balance` — DEUX CLÉS
      // QUE LA FONCTION NE REND PAS. Le repli `?? result` tombait donc sur
      // l'objet entier, `typeof net` n'était jamais 'number', et le bouton
      // annonçait 0 €. Un bouton qui confirme toujours 0 est pire qu'un
      // bouton mort : il donne raison à tort.
      const net = Number(result?.net_forecast ?? 0)
      toast('success', tCommon('common.success'), t('forecast.cashFlowResult', { amount: net, days: horizon }))
    } catch (err) {
      toast('error', tCommon('common.error'), errorMessage(err) || tCommon('common.error'))
    } finally {
      setForecastLoading(false)
    }
  }

  const netFlow = (data?.totalIncoming || 0) - (data?.totalOutgoing || 0)
  const projectedBalance = (data?.currentBalance || 0) + netFlow

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('forecast.title') }]} />
      <PageHeader title={t('forecast.title')} subtitle={t('forecast.subtitle')} />

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-48">
          <Select
            label={t('forecast.horizon')}
            value={horizon}
            onChange={(e) => setHorizon(e.target.value)}
            options={[
              { value: '30', label: t('forecast.days30') },
              { value: '60', label: t('forecast.days60') },
              { value: '90', label: t('forecast.days90') },
              { value: '180', label: t('forecast.days180') },
            ]}
          />
        </div>
        <Button onClick={handleCashFlowForecast} disabled={forecastLoading}>
          <TrendingUp className="w-4 h-4" /> {t('forecast.runForecast')}
        </Button>
      </div>

      {loading ? (
        <SkeletonTable rows={8} cols={5} />
      ) : !data || data.timeline.length === 0 ? (
        <EmptyState
          icon={<Calendar className="w-8 h-8" />}
          title={t('forecast.noForecast')}
          description={t('forecast.noForecastDesc')}
        />
      ) : (
        <div className="space-y-4">
          <div className="grid grid-cols-4 gap-4">
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('forecast.currentBalance')}</p>
              <p className="text-lg font-bold font-mono">{formatCurrency(data.currentBalance)}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1 flex items-center gap-1"><TrendingUp className="w-3 h-3 text-[var(--color-success)]" /> {t('forecast.incoming')}</p>
              <p className="text-lg font-bold font-mono text-[var(--color-success)]">{formatCurrency(data.totalIncoming)}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1 flex items-center gap-1"><TrendingDown className="w-3 h-3 text-[var(--color-danger)]" /> {t('forecast.outgoing')}</p>
              <p className="text-lg font-bold font-mono text-[var(--color-danger)]">{formatCurrency(data.totalOutgoing)}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('forecast.projectedBalance')}</p>
              <p className={`text-lg font-bold font-mono ${projectedBalance >= 0 ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>
                {formatCurrency(projectedBalance)}
              </p>
            </div>
          </div>

          {/* L'ENGAGEMENT DE PRODUCTION (L19). La 420 le calcule ; sans ces
              cartes, le module production ↔ trésorerie restait invisible pour
              la seule personne qui décide. Et « net avec production » est
              affiché À CÔTÉ du net historique, jamais à sa place : les
              chiffres que tous les écrans montrent ne bougent pas sans
              décision produit. */}
          {(data.productionCommitment > 0 || data.productionMaterialCommitment > 0) && (
            <Card title={t('forecast.productionCommitment')}>
              <div className="grid grid-cols-5 gap-4">
                <div className="card p-4">
                  <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('forecast.materialToBuy')}</p>
                  <p className="text-lg font-bold font-mono">{formatCurrency(data.productionMaterialCommitment)}</p>
                </div>
                <div className="card p-4">
                  <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('forecast.workshopLabor')}</p>
                  <p className="text-lg font-bold font-mono">{formatCurrency(data.productionLaborCommitment)}</p>
                </div>
                <div className="card p-4">
                  <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('forecast.commitmentTotal')}</p>
                  <p className="text-lg font-bold font-mono">{formatCurrency(data.productionCommitment)}</p>
                </div>
                {/* Le net du MOTEUR, puis le même net tenant l'atelier : les
                    deux côte à côte, sinon `net_with_production` n'est qu'un
                    chiffre que personne ne peut comparer à rien. */}
                <div className="card p-4">
                  <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('forecast.netForecast')}</p>
                  <p className={`text-lg font-bold font-mono ${(data.netForecast ?? 0) >= 0 ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>
                    {formatCurrency(data.netForecast)}
                  </p>
                </div>
                <div className="card p-4">
                  <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('forecast.netWithProduction')}</p>
                  <p className={`text-lg font-bold font-mono ${data.netWithProduction >= 0 ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>
                    {formatCurrency(data.netWithProduction)}
                  </p>
                </div>
              </div>
            </Card>
          )}

          <Card title={t('forecast.timeline')}>
            <Table headers={[t('forecast.date'), t('forecast.reference'), t('forecast.type'), t('forecast.amount'), t('forecast.cumulativeBalance')]}>
              {data.timeline.map((e: any, i: number) => (
                <TableRow key={i}>
                  <TableCell className="text-xs">{formatDate(e.date)}</TableCell>
                  <TableCell className="font-mono text-xs">{e.reference}</TableCell>
                  <TableCell>
                    <Badge variant={e.type === 'in' ? 'success' : 'danger'}>
                      {e.type === 'in' ? t('forecast.incomingType') : t('forecast.outgoingType')}
                    </Badge>
                  </TableCell>
                  <TableCell className={`font-mono text-xs text-right ${e.type === 'in' ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>
                    {e.type === 'in' ? '+' : '−'}{formatCurrency(e.amount)}
                  </TableCell>
                  <TableCell className={`font-mono text-xs font-semibold text-right ${e.runningBalance >= 0 ? '' : 'text-[var(--color-danger)]'}`}>
                    {formatCurrency(e.runningBalance)}
                  </TableCell>
                </TableRow>
              ))}
            </Table>
          </Card>
        </div>
      )}
    </div>
  )
}
