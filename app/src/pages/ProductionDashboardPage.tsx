import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Factory, Clock, CheckCircle2, AlertTriangle, Truck, ClipboardList, ArrowRight } from 'lucide-react'
import { Card, StatCard, Table, TableRow, TableCell, EmptyState, PageHeader, Breadcrumb, SkeletonTable, Badge } from '@/components/ui'
import { getManufacturingOrders, getSTOrders, getMRPProposals, getMRPRuns } from '@/lib/queries'
import { formatDate } from '@/lib/utils'
import { Link } from 'react-router-dom'

const statusVariants: Record<string, 'neutral' | 'warning' | 'success' | 'danger'> = {
  planned: 'neutral', in_progress: 'warning', completed: 'success', cancelled: 'danger',
}

export function ProductionDashboardPage() {
  const { t } = useTranslation('production')
  const [mos, setMOs] = useState<any[]>([])
  const [stOrders, setSTOrders] = useState<any[]>([])
  const [mrpProposals, setMRPProposals] = useState<any[]>([])
  const [loading, setLoading] = useState(true)

  const loadData = useCallback(async () => {
    try {
      const [allMOs, allST, allRuns] = await Promise.all([
        getManufacturingOrders(),
        getSTOrders().catch(() => []),
        getMRPRuns().catch(() => []),
      ])
      setMOs(allMOs || [])
      setSTOrders(allST || [])

      const latestRun = (allRuns as any[])[0]
      if (latestRun) {
        try { setMRPProposals(await getMRPProposals(latestRun.id)) } catch { setMRPProposals([]) }
      }
    } catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  const now = new Date()
  const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1)

  const inProgress = mos.filter((m) => m.status === 'in_progress')
  const planned = mos.filter((m) => m.status === 'planned')
  const completedThisMonth = mos.filter((m) => m.status === 'completed' && m.end_date && new Date(m.end_date) >= startOfMonth)
  const delayed = mos.filter((m) => m.status !== 'completed' && m.end_date && new Date(m.end_date) < now)
  const stInProgress = stOrders.filter((s) => s.status === 'sent' || s.status === 'in_progress')
  const pendingProposals = mrpProposals.filter((p) => p.status === 'pending' || p.status === 'proposed')

  const statusCounts: Record<string, number> = {}
  for (const m of mos) { statusCounts[m.status] = (statusCounts[m.status] || 0) + 1 }
  const maxStatusCount = Math.max(1, ...Object.values(statusCounts))

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }]} />
      <PageHeader title={t('dashboard.title')} subtitle={t('dashboard.subtitle')} />

      {loading ? (
        <div className="space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-6 gap-4">
            {[...Array(6)].map((_, i) => <div key={i} className="card p-6 animate-pulse"><div className="h-16 bg-[var(--color-neutral-100)] rounded" /></div>)}
          </div>
          <SkeletonTable rows={5} cols={4} />
        </div>
      ) : (
        <>
          <div className="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-6 gap-4 mb-6">
            <StatCard label={t('dashboard.ofInProgress')} value={String(inProgress.length)} icon={<Factory className="w-5 h-5" />} color="primary" />
            <StatCard label={t('dashboard.ofPlanned')} value={String(planned.length)} icon={<Clock className="w-5 h-5" />} color="warning" />
            <StatCard label={t('dashboard.ofCompletedMonth')} value={String(completedThisMonth.length)} icon={<CheckCircle2 className="w-5 h-5" />} color="success" />
            <StatCard label={t('dashboard.stInProgress')} value={String(stInProgress.length)} icon={<Truck className="w-5 h-5" />} color="primary" />
            <StatCard label={t('dashboard.mrpProposals')} value={String(pendingProposals.length)} icon={<ClipboardList className="w-5 h-5" />} color="warning" />
            <StatCard label={t('dashboard.productionDelays')} value={String(delayed.length)} icon={<AlertTriangle className="w-5 h-5" />} color="danger" />
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
            <Card>
              <div className="p-4">
                <h3 className="text-sm font-semibold mb-4">{t('dashboard.ofByStatus')}</h3>
                {Object.keys(statusCounts).length === 0 ? (
                  <p className="text-sm text-[var(--color-text-secondary)] py-8 text-center">{t('dashboard.noData')}</p>
                ) : (
                  <div className="space-y-3">
                    {Object.entries(statusCounts).map(([status, count]) => (
                      <div key={status}>
                        <div className="flex items-center justify-between text-xs mb-1">
                          <span>{t('manufacturing.statuses.' + status) || status}</span>
                          <span className="font-mono font-semibold">{count}</span>
                        </div>
                        <div className="h-6 bg-[var(--color-neutral-50)] rounded relative overflow-hidden">
                          <div
                            className={`h-6 rounded flex items-center px-2 text-xs text-white ${status === 'completed' ? 'bg-[var(--color-success)]' : status === 'in_progress' ? 'bg-[var(--color-warning)]' : status === 'planned' ? 'bg-[var(--color-primary)]' : 'bg-[var(--color-danger)]'}`}
                            style={{ width: `${(count / maxStatusCount) * 100}%` }}
                          >
                            {count}
                          </div>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </Card>

            <Card>
              <div className="p-4">
                <h3 className="text-sm font-semibold mb-4">{t('dashboard.productionAlerts')}</h3>
                {delayed.length === 0 && stInProgress.length === 0 && pendingProposals.length === 0 ? (
                  <p className="text-sm text-[var(--color-text-secondary)] py-8 text-center">{t('dashboard.noAlerts')}</p>
                ) : (
                  <div className="space-y-2">
                    {delayed.length > 0 && (
                      <div className="flex items-center gap-2 p-3 rounded-lg bg-[var(--color-danger)]/10 border border-[var(--color-danger)]/30">
                        <AlertTriangle className="w-4 h-4 text-[var(--color-danger)]" />
                        <span className="text-sm">{t('dashboard.ofDelayed', { count: delayed.length })}</span>
                      </div>
                    )}
                    {pendingProposals.length > 0 && (
                      <div className="flex items-center gap-2 p-3 rounded-lg bg-[var(--color-warning)]/10 border border-[var(--color-warning)]/30">
                        <ClipboardList className="w-4 h-4 text-[var(--color-warning)]" />
                        <span className="text-sm">{t('dashboard.mrpProposalsPending', { count: pendingProposals.length })}</span>
                      </div>
                    )}
                    {stInProgress.length > 0 && (
                      <div className="flex items-center gap-2 p-3 rounded-lg bg-[var(--color-primary)]/10 border border-[var(--color-primary)]/30">
                        <Truck className="w-4 h-4 text-[var(--color-primary)]" />
                        <span className="text-sm">{t('dashboard.stOrdersInProgress', { count: stInProgress.length })}</span>
                      </div>
                    )}
                  </div>
                )}
              </div>
            </Card>
          </div>

          <Card>
            <div className="p-4">
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-sm font-semibold">{t('dashboard.ofInProgressTop10')}</h3>
                <Link to="/production/manufacturing" className="text-xs text-[var(--color-primary)] hover:underline flex items-center gap-1">
                  {t('dashboard.viewAll')} <ArrowRight className="w-3 h-3" />
                </Link>
              </div>
              {inProgress.length === 0 ? (
                <EmptyState icon={<Factory className="w-8 h-8" />} title={t('dashboard.noOfInProgress')} description={t('dashboard.noOfInProgressDescription')} />
              ) : (
                <Table headers={[t('manufacturing.number'), t('manufacturing.product'), t('manufacturing.quantity'), t('manufacturing.startDate'), t('manufacturing.endDate'), t('manufacturing.status')]}>
                  {inProgress.slice(0, 10).map((mo) => (
                    <TableRow key={mo.id}>
                      <TableCell className="font-mono text-xs">
                        <Link to={`/production/of/${mo.id}`} className="text-[var(--color-primary)] hover:underline">{mo.number}</Link>
                      </TableCell>
                      <TableCell className="text-sm">{mo.products?.name || '—'}</TableCell>
                      <TableCell className="font-mono text-xs">{Number(mo.quantity)}</TableCell>
                      <TableCell className="text-xs">{mo.start_date ? formatDate(mo.start_date) : '—'}</TableCell>
                      <TableCell className="text-xs">
                        {mo.end_date ? (
                          <span className={new Date(mo.end_date) < now ? 'text-[var(--color-danger)] font-semibold' : ''}>{formatDate(mo.end_date)}</span>
                        ) : '—'}
                      </TableCell>
                      <TableCell><Badge variant={statusVariants[mo.status] || 'neutral'}>{t('manufacturing.statuses.' + mo.status) || mo.status}</Badge></TableCell>
                    </TableRow>
                  ))}
                </Table>
              )}
            </div>
          </Card>
        </>
      )}
    </div>
  )
}
