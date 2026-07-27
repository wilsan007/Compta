import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Button, Card, SortableTable, Badge, EmptyState, SkeletonTable, Select, PageHeader } from '@/components/ui'
import { getPosSessions, getPosTickets, getPosStats, getPosTerminals } from '@/lib/queries'
import { useToast } from '@/lib/toast'
import { formatCurrency, formatDate } from '@/lib/utils'
import { Clock, Eye } from 'lucide-react'
import type { PosSession, PosTicket, PosTerminal } from '@/types'

type SessionWithTerminal = PosSession & { terminal: { name: string } | null }

export function PosSessionsPage() {
  const { t } = useTranslation('pos')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()

  const [sessions, setSessions] = useState<SessionWithTerminal[]>([])
  const [loading, setLoading] = useState(true)
  const [filterTerminal, setFilterTerminal] = useState('')
  const [selectedSession, setSelectedSession] = useState<SessionWithTerminal | null>(null)
  const [tickets, setTickets] = useState<PosTicket[]>([])
  const [stats, setStats] = useState<{ ticketCount: number; totalRevenue: number; byPaymentMethod: Record<string, number>; totalVat: number } | null>(null)
  const [terminals, setTerminals] = useState<PosTerminal[]>([])

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const [data, terms] = await Promise.all([
        getPosSessions(filterTerminal || undefined),
        getPosTerminals(),
      ])
      setSessions(data)
      setTerminals(terms)
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    } finally {
      setLoading(false)
    }
  }, [filterTerminal])

  useEffect(() => { load() }, [load])

  async function viewSessionDetails(session: SessionWithTerminal) {
    setSelectedSession(session)
    try {
      const ticks = await getPosTickets(session.id)
      setTickets(ticks)
      const s = await getPosStats(session.id)
      setStats(s)
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    }
  }

  function getStatusBadge(status: string): React.ReactNode {
    if (status === 'open') return <Badge variant="success">{t('sessions.open')}</Badge>
    return <Badge variant="neutral">{t('sessions.closed')}</Badge>
  }

  if (loading) {
    return (
      <div className="p-6">
        <PageHeader title={t('sessions.title')} />
        <SkeletonTable rows={5} cols={5} />
      </div>
    )
  }

  return (
    <div className="p-6">
      <PageHeader title={t('sessions.title')} action={
        <Select value={filterTerminal} onChange={e => setFilterTerminal(e.target.value)}
          options={[{ value: '', label: t('sessions.allTerminals') }, ...terminals.map(t => ({ value: t.id, label: t.name }))]} />
      } />

      {sessions.length === 0 ? (
        <EmptyState icon={<Clock className="w-8 h-8" />} title={t('sessions.noSessions')} description={t('sessions.noSessionsDescription')} />
      ) : (
        <Card>
          <SortableTable
            headers={[
              { label: t('sessions.terminal'), key: 'terminal_id', sortable: true },
              { label: t('sessions.user'), key: 'user_email', sortable: true },
              { label: t('sessions.openedAt'), key: 'opened_at', sortable: true },
              { label: t('sessions.closedAt'), key: 'closed_at', sortable: true },
              { label: t('sessions.status'), key: 'status', sortable: true },
              { label: t('sessions.openingAmount'), key: 'opening_amount', sortable: true },
              { label: t('sessions.difference'), key: 'difference', sortable: true },
              { label: '', key: 'actions' },
            ]}
            data={sessions}
            renderRow={(session) => (
              <tr key={session.id} className="border-b border-[var(--color-border)] hover:bg-[var(--color-neutral-50)]">
                <td className="px-4 py-3 text-sm">{session.terminal?.name || '—'}</td>
                <td className="px-4 py-3 text-sm">{session.user_email}</td>
                <td className="px-4 py-3 text-sm">{formatDate(session.opened_at)}</td>
                <td className="px-4 py-3 text-sm">{session.closed_at ? formatDate(session.closed_at) : '—'}</td>
                <td className="px-4 py-3">{getStatusBadge(session.status)}</td>
                <td className="px-4 py-3 text-sm font-mono">{formatCurrency(session.opening_amount)}</td>
                <td className="px-4 py-3 text-sm font-mono">
                  {session.difference !== null ? (
                    <span className={session.difference < 0 ? 'text-[var(--color-danger)]' : 'text-[var(--color-text)]'}>
                      {formatCurrency(session.difference)}
                    </span>
                  ) : '—'}
                </td>
                <td className="px-4 py-3">
                  <Button size="sm" variant="ghost" onClick={() => viewSessionDetails(session)}>
                    <Eye className="w-4 h-4" /> {t('sessions.viewTickets')}
                  </Button>
                </td>
              </tr>
            )}
          />
        </Card>
      )}

      {/* Session Details Modal */}
      {selectedSession && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <Card title={`${t('sessions.title')} — ${selectedSession.terminal?.name || ''}`} className="w-full max-w-3xl max-h-[80vh] overflow-y-auto">
            {stats && (
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
                <div className="card p-4">
                  <p className="text-xs text-[var(--color-text-secondary)]">{t('stats.totalTickets')}</p>
                  <p className="text-xl font-bold">{stats.ticketCount}</p>
                </div>
                <div className="card p-4">
                  <p className="text-xs text-[var(--color-text-secondary)]">{t('stats.totalRevenue')}</p>
                  <p className="text-xl font-bold">{formatCurrency(stats.totalRevenue)}</p>
                </div>
                <div className="card p-4">
                  <p className="text-xs text-[var(--color-text-secondary)]">{t('stats.totalVat')}</p>
                  <p className="text-xl font-bold">{formatCurrency(stats.totalVat)}</p>
                </div>
                <div className="card p-4">
                  <p className="text-xs text-[var(--color-text-secondary)]">{t('stats.averageTicket')}</p>
                  <p className="text-xl font-bold">{formatCurrency(stats.ticketCount > 0 ? stats.totalRevenue / stats.ticketCount : 0)}</p>
                </div>
              </div>
            )}
            <div className="space-y-2">
              {tickets.length === 0 ? (
                <p className="text-center text-sm text-[var(--color-text-secondary)] py-8">{t('sessions.noTickets')}</p>
              ) : (
                tickets.map(ticket => (
                  <div key={ticket.id} className="flex items-center justify-between p-3 rounded-lg border border-[var(--color-border)]">
                    <div>
                      <p className="text-sm font-mono">{ticket.number}</p>
                      <p className="text-xs text-[var(--color-text-secondary)]">{formatDate(ticket.date)}</p>
                    </div>
                    <div className="text-right">
                      <p className="text-sm font-bold">{formatCurrency(ticket.total)}</p>
                      <Badge variant={ticket.status === 'completed' ? 'success' : 'danger'}>
                        {ticket.status}
                      </Badge>
                    </div>
                  </div>
                ))
              )}
            </div>
            <div className="mt-4">
              <Button variant="secondary" onClick={() => setSelectedSession(null)}>{tCommon('actions.close')}</Button>
            </div>
          </Card>
        </div>
      )}
    </div>
  )
}
