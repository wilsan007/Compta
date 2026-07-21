import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Calculator, Trash2, Check, X, Eye, Clock, Factory, ShoppingCart } from 'lucide-react'
import { Card, Button, Table, TableRow, TableCell, EmptyState, PageHeader, Breadcrumb, SkeletonTable, Badge } from '@/components/ui'
import { useToast } from '@/lib/toast'
import {
  getMRPRuns, runMRPCalculation, deleteMRPRun,
  getMRPProposals, updateMRPProposal, deleteMRPProposal,
  getMRPPendingDocs, deleteMRPPendingDoc,
} from '@/lib/queries'
import { formatDate } from '@/lib/utils'

const proposalTypeIcons: Record<string, any> = { purchase: ShoppingCart, manufacture: Factory, subcontract: Factory }
const proposalStatusVariants: Record<string, 'neutral' | 'success' | 'danger' | 'warning'> = { pending: 'neutral', approved: 'success', rejected: 'danger', converted: 'warning' }

export function MRPPage() {
  const { toast } = useToast()
  const { t } = useTranslation('production')
  const { t: tCommon } = useTranslation('common')
  const [runs, setRuns] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [calculating, setCalculating] = useState(false)
  const [selectedRun, setSelectedRun] = useState<any>(null)
  const [proposals, setProposals] = useState<any[]>([])

  const loadData = useCallback(async () => {
    try { setRuns(await getMRPRuns() || []) }
    catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleCalculate() {
    setCalculating(true)
    try {
      const run = await runMRPCalculation()
      toast('success', t('mrp.mrpCalculated'), t('mrp.proposalsGenerated', { count: run.summary?.products_with_needs || 0 }))
      await loadData()
      setSelectedRun(run)
      setProposals(await getMRPProposals(run.id))
    } catch (err: any) { toast('error', t('mrp.mrpError'), err.message) }
    finally { setCalculating(false) }
  }

  async function handleSelectRun(run: any) {
    setSelectedRun(run)
    try { setProposals(await getMRPProposals(run.id)) }
    catch (err) { console.error('Error:', err) }
  }

  async function handleDeleteRun(id: string) {
    if (!window.confirm(t('mrp.confirmDeleteRun'))) return
    try { await deleteMRPRun(id); await loadData(); setSelectedRun(null) }
    catch (err: any) { toast('error', tCommon('toast.error'), err.message) }
  }

  async function handleApprove(id: string) {
    try { await updateMRPProposal(id, { status: 'approved' }); if (selectedRun) setProposals(await getMRPProposals(selectedRun.id)) }
    catch (err: any) { toast('error', tCommon('toast.error'), err.message) }
  }

  async function handleReject(id: string) {
    try { await updateMRPProposal(id, { status: 'rejected' }); if (selectedRun) setProposals(await getMRPProposals(selectedRun.id)) }
    catch (err: any) { toast('error', tCommon('toast.error'), err.message) }
  }

  async function handleDeleteProposal(id: string) {
    try { await deleteMRPProposal(id); if (selectedRun) setProposals(await getMRPProposals(selectedRun.id)) }
    catch (err: any) { toast('error', tCommon('toast.error'), err.message) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('mrp.title'), path: '/production' }, { label: t('mrp.titleFull') }]} />
      <PageHeader title={t('mrp.titleFull')} subtitle={`${runs.length} ${t('mrp.runsCount')}`}
        action={<Button onClick={handleCalculate} disabled={calculating}><Calculator className="w-4 h-4" /> {calculating ? t('mrp.calculating') : t('mrp.launchCalculation')}</Button>} />

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <div className="lg:col-span-1">
          <Card>
            <h3 className="text-sm font-semibold mb-3 px-4 pt-4">{t('mrp.runsHistory')}</h3>
            {loading ? <SkeletonTable rows={3} cols={2} /> : runs.length === 0 ? (
              <EmptyState icon={<Calculator className="w-8 h-8" />} title={t('mrp.noRuns')} description={t('mrp.createFirstRun')} />
            ) : (
              <div className="divide-y divide-[var(--color-border)]">
                {runs.map((r) => (
                  <button key={r.id} onClick={() => handleSelectRun(r)}
                    className={`w-full text-left px-4 py-3 hover:bg-[var(--color-neutral-50)] transition-colors ${selectedRun?.id === r.id ? 'bg-[var(--color-primary)]/5' : ''}`}>
                    <div className="flex items-center justify-between">
                      <span className="font-mono text-xs">{r.run_number}</span>
                      <Badge variant={r.status === 'completed' ? 'success' : r.status === 'running' ? 'warning' : 'danger'}>{r.status}</Badge>
                    </div>
                    <p className="text-xs text-[var(--color-text-secondary)] mt-1">{formatDate(r.run_date)}</p>
                    {r.summary && (
                      <p className="text-xs text-[var(--color-text-secondary)] mt-0.5">
                        {t('mrp.proposalsSummary', { proposals: (r.summary as any).products_with_needs || 0, units: (r.summary as any).total_net_need || 0 })}
                      </p>
                    )}
                  </button>
                ))}
              </div>
            )}
          </Card>
        </div>

        <div className="lg:col-span-2">
          {selectedRun ? (
            <Card>
              <div className="flex items-center justify-between px-4 pt-4 mb-3">
                <h3 className="text-sm font-semibold">{t('mrp.proposals')} — {selectedRun.run_number}</h3>
                <button onClick={() => handleDeleteRun(selectedRun.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
              </div>
              {proposals.length === 0 ? (
                <EmptyState icon={<ShoppingCart className="w-8 h-8" />} title={t('mrp.noProposals')} description={t('mrp.noProposalsDescription')} />
              ) : (
                <Table headers={[t('mrp.product'), t('mrp.type'), t('mrp.grossNeed'), t('mrp.stock'), t('mrp.openOrders'), t('mrp.netNeed'), t('mrp.suggestedQuantity'), tCommon('common.status'), tCommon('table.actions')]}>
                  {proposals.map((p) => {
                    const Icon = proposalTypeIcons[p.proposal_type] || ShoppingCart
                    return (
                      <TableRow key={p.id}>
                        <TableCell className="text-sm">{p.products?.name || '—'}</TableCell>
                        <TableCell><Badge variant="neutral"><Icon className="w-3 h-3 inline mr-1" />{t(`mrp.proposalTypes.${p.proposal_type}`, { defaultValue: p.proposal_type })}</Badge></TableCell>
                        <TableCell className="font-mono text-xs">{Number(p.gross_need)}</TableCell>
                        <TableCell className="font-mono text-xs">{Number(p.stock_available)}</TableCell>
                        <TableCell className="font-mono text-xs">{Number(p.open_orders)}</TableCell>
                        <TableCell className="font-mono text-xs font-semibold">{Number(p.net_need)}</TableCell>
                        <TableCell className="font-mono text-xs">{Number(p.suggested_quantity)}</TableCell>
                        <TableCell><Badge variant={proposalStatusVariants[p.status] || 'neutral'}>{t(`mrp.proposalStatuses.${p.status}`, { defaultValue: p.status })}</Badge></TableCell>
                        <TableCell>
                          <div className="flex gap-1">
                            {p.status === 'pending' && (
                              <>
                                <button onClick={() => handleApprove(p.id)} className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-success)]"><Check className="w-3.5 h-3.5" /></button>
                                <button onClick={() => handleReject(p.id)} className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><X className="w-3.5 h-3.5" /></button>
                              </>
                            )}
                            <button onClick={() => handleDeleteProposal(p.id)} className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-3.5 h-3.5" /></button>
                          </div>
                        </TableCell>
                      </TableRow>
                    )
                  })}
                </Table>
              )}
            </Card>
          ) : (
            <Card>
              <EmptyState icon={<Eye className="w-8 h-8" />} title={t('mrp.selectRun')} description={t('mrp.selectRunDescription')} />
            </Card>
          )}
        </div>
      </div>
    </div>
  )
}

// ============ Pending Docs Page ============

export function MRPPendingDocsPage() {
  const { toast } = useToast()
  const { t } = useTranslation('production')
  const { t: tCommon } = useTranslation('common')
  const [docs, setDocs] = useState<any[]>([])
  const [loading, setLoading] = useState(true)

  const loadData = useCallback(async () => {
    try { setDocs(await getMRPPendingDocs() || []) }
    catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
    try { await deleteMRPPendingDoc(id); await loadData() }
    catch (err: any) { toast('error', tCommon('toast.error'), err.message) }
  }

  const docStatusVariants: Record<string, 'neutral' | 'success' | 'danger'> = { pending: 'neutral', processed: 'success', cancelled: 'danger' }

  return (
    <div>
      <Breadcrumb items={[{ label: t('mrp.title'), path: '/production' }, { label: t('mrp.title') }, { label: t('pendingDocs.title') }]} />
      <PageHeader title={t('pendingDocs.title')} subtitle={`${docs.length} ${t('pendingDocs.count')}`} />
      {loading ? <SkeletonTable rows={4} cols={5} /> : docs.length === 0 ? (
        <EmptyState icon={<Clock className="w-8 h-8" />} title={t('pendingDocs.noDocs')} description={t('pendingDocs.noDocsDescription')} />
      ) : (
        <Card>
          <Table headers={[t('pendingDocs.type'), t('pendingDocs.product'), t('pendingDocs.quantity'), tCommon('common.status'), tCommon('common.date'), tCommon('table.actions')]}>
            {docs.map((d) => (
              <TableRow key={d.id}>
                <TableCell className="text-sm">{t(`pendingDocs.docTypes.${d.doc_type}`, { defaultValue: d.doc_type })}</TableCell>
                <TableCell className="text-sm">{d.products?.name || '—'}</TableCell>
                <TableCell className="font-mono text-xs">{Number(d.quantity)}</TableCell>
                <TableCell><Badge variant={docStatusVariants[d.status] || 'neutral'}>{d.status}</Badge></TableCell>
                <TableCell className="text-xs">{formatDate(d.created_at)}</TableCell>
                <TableCell><button onClick={() => handleDelete(d.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button></TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}
    </div>
  )
}
