import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, EmptyState, SkeletonTable, Select, StatCard, PageHeader } from '@/components/ui'
import { getPosTerminals, getPosTickets } from '@/lib/queries'
import { useToast } from '@/lib/toast'
import { formatCurrency } from '@/lib/utils'
import { BarChart3, TrendingUp, Receipt, DollarSign } from 'lucide-react'
import type { PosTerminal, PosTicket } from '@/types'

export function PosStatsPage() {
  const { t } = useTranslation('pos')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()

  const [terminals, setTerminals] = useState<PosTerminal[]>([])
  const [selectedTerminal, setSelectedTerminal] = useState('')
  const [period, setPeriod] = useState('today')
  const [tickets, setTickets] = useState<PosTicket[]>([])
  const [loading, setLoading] = useState(true)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const terms = await getPosTerminals()
      setTerminals(terms)
      const now = new Date()
      let startDate = new Date(now)
      if (period === 'today') startDate.setHours(0, 0, 0, 0)
      else if (period === 'thisWeek') { startDate.setDate(now.getDate() - now.getDay()); startDate.setHours(0, 0, 0, 0) }
      else if (period === 'thisMonth') { startDate = new Date(now.getFullYear(), now.getMonth(), 1) }
      const ticks = await getPosTickets(undefined, startDate.toISOString().split('T')[0])
      setTickets(ticks)
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    } finally {
      setLoading(false)
    }
  }, [period])

  useEffect(() => { load() }, [load])

  const filteredTickets = selectedTerminal
    ? tickets.filter(t => t.terminal_id === selectedTerminal)
    : tickets

  const totalRevenue = filteredTickets.reduce((sum, t) => sum + (t.status === 'completed' ? Number(t.total) : 0), 0)
  const totalVat = filteredTickets.reduce((sum, t) => sum + (t.status === 'completed' ? Number(t.vat_total) : 0), 0)
  const ticketCount = filteredTickets.filter(t => t.status === 'completed').length
  const avgTicket = ticketCount > 0 ? totalRevenue / ticketCount : 0

  const byPaymentMethod: Record<string, number> = {}
  filteredTickets.filter(t => t.status === 'completed').forEach(t => {
    const method = t.payment_method || 'unknown'
    byPaymentMethod[method] = (byPaymentMethod[method] || 0) + Number(t.total)
  })

  const byTerminal: Record<string, number> = {}
  filteredTickets.filter(t => t.status === 'completed').forEach(t => {
    const tid = t.terminal_id
    byTerminal[tid] = (byTerminal[tid] || 0) + Number(t.total)
  })

  if (loading) {
    return (
      <div className="p-6">
        <PageHeader title={t('stats.title')} />
        <SkeletonTable rows={5} cols={4} />
      </div>
    )
  }

  return (
    <div className="p-6">
      <PageHeader title={t('stats.title')} action={
        <div className="flex gap-2">
          <Select value={selectedTerminal} onChange={e => setSelectedTerminal(e.target.value)}
            options={[{ value: '', label: t('sessions.allTerminals') }, ...terminals.map(t => ({ value: t.id, label: t.name }))]} />
          <Select value={period} onChange={e => setPeriod(e.target.value)}
            options={[
              { value: 'today', label: t('stats.today') },
              { value: 'thisWeek', label: t('stats.thisWeek') },
              { value: 'thisMonth', label: t('stats.thisMonth') },
            ]} />
        </div>
      } />

      {filteredTickets.length === 0 ? (
        <EmptyState icon={<BarChart3 className="w-8 h-8" />} title={t('stats.noData')} />
      ) : (
        <>
          <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
            <StatCard label={t('stats.totalRevenue')} value={formatCurrency(totalRevenue)} icon={<DollarSign className="w-5 h-5" />} color="success" />
            <StatCard label={t('stats.totalTickets')} value={String(ticketCount)} icon={<Receipt className="w-5 h-5" />} color="primary" />
            <StatCard label={t('stats.averageTicket')} value={formatCurrency(avgTicket)} icon={<TrendingUp className="w-5 h-5" />} color="primary" />
            <StatCard label={t('stats.totalVat')} value={formatCurrency(totalVat)} icon={<DollarSign className="w-5 h-5" />} color="warning" />
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <Card title={t('stats.byPaymentMethod')}>
              <div className="space-y-3">
                {Object.entries(byPaymentMethod).map(([method, amount]) => (
                  <div key={method} className="flex items-center justify-between">
                    <span className="text-sm capitalize">{method}</span>
                    <span className="text-sm font-medium">{formatCurrency(amount)}</span>
                  </div>
                ))}
              </div>
            </Card>

            <Card title={t('stats.revenueByTerminal')}>
              <div className="space-y-3">
                {Object.entries(byTerminal).map(([tid, amount]) => {
                  const terminal = terminals.find(t => t.id === tid)
                  return (
                    <div key={tid} className="flex items-center justify-between">
                      <span className="text-sm">{terminal?.name || tid}</span>
                      <span className="text-sm font-medium">{formatCurrency(amount)}</span>
                    </div>
                  )
                })}
              </div>
            </Card>
          </div>
        </>
      )}
    </div>
  )
}
