import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Button, Table, TableRow, TableCell, Badge, EmptyState } from '@/components/ui'
import { formatDate } from '@/lib/utils'
import { getTickets, getKbArticles, getServiceContracts } from '@/lib/queries'
import { useToast } from '@/lib/toast'
import { Ticket, BookOpen, FileText, Plus } from 'lucide-react'
import type { ServiceTicket, KnowledgeBaseArticle, ServiceContract } from '@/types'

type Tab = 'tickets' | 'knowledgeBase' | 'contracts'

export function CustomerPortalPage() {
  const { t } = useTranslation('crm')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [tab, setTab] = useState<Tab>('tickets')
  const [tickets, setTickets] = useState<ServiceTicket[]>([])
  const [articles, setArticles] = useState<KnowledgeBaseArticle[]>([])
  const [contracts, setContracts] = useState<ServiceContract[]>([])
  const [loading, setLoading] = useState(true)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const [tkData, kbData, scData] = await Promise.all([
        getTickets(),
        getKbArticles(undefined, 'published'),
        getServiceContracts(),
      ])
      setTickets(tkData || [])
      setArticles((kbData || []).filter(a => a.is_public))
      setContracts((scData || []).filter(c => c.status === 'active'))
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { load() }, [load])

  function getStatusBadge(status: string): 'neutral' | 'warning' | 'success' | 'danger' {
    if (status === 'closed' || status === 'resolved') return 'success'
    if (status === 'in_progress') return 'warning'
    if (status === 'waiting_customer') return 'neutral'
    return 'danger'
  }

  return (
    <div className="p-6 max-w-5xl mx-auto">
      <div className="mb-6">
        <h1 className="text-2xl font-bold">{t('portal.title')}</h1>
      </div>

      <div className="flex gap-2 mb-6 border-b border-[var(--color-border)]">
        <button onClick={() => setTab('tickets')} className={`px-4 py-2 text-sm font-medium border-b-2 ${tab === 'tickets' ? 'border-[var(--color-primary)] text-[var(--color-primary)]' : 'border-transparent text-[var(--color-text-secondary)]'}`}>
          <Ticket className="w-4 h-4 inline mr-2" />{t('portal.myTickets')}
        </button>
        <button onClick={() => setTab('knowledgeBase')} className={`px-4 py-2 text-sm font-medium border-b-2 ${tab === 'knowledgeBase' ? 'border-[var(--color-primary)] text-[var(--color-primary)]' : 'border-transparent text-[var(--color-text-secondary)]'}`}>
          <BookOpen className="w-4 h-4 inline mr-2" />{t('portal.knowledgeBase')}
        </button>
        <button onClick={() => setTab('contracts')} className={`px-4 py-2 text-sm font-medium border-b-2 ${tab === 'contracts' ? 'border-[var(--color-primary)] text-[var(--color-primary)]' : 'border-transparent text-[var(--color-text-secondary)]'}`}>
          <FileText className="w-4 h-4 inline mr-2" />{t('portal.myContracts')}
        </button>
      </div>

      {loading ? (
        <div className="space-y-2">{[1, 2, 3].map(i => <div key={i} className="h-12 rounded animate-pulse bg-[var(--color-neutral-100)]" />)}</div>
      ) : tab === 'tickets' ? (
        tickets.length === 0 ? (
          <EmptyState icon={<Ticket className="w-8 h-8" />} title={t('tickets.noTickets')} description={t('tickets.noTicketsDescription')} action={<Button><Plus className="w-4 h-4" /> {t('portal.createTicket')}</Button>} />
        ) : (
          <Table headers={[t('tickets.number'), t('tickets.subject'), t('tickets.priority'), t('tickets.status'), t('tickets.resolvedAt')]}>
            {tickets.map(tk => (
              <TableRow key={tk.id}>
                <TableCell className="font-mono text-xs">{tk.number}</TableCell>
                <TableCell className="font-medium">{tk.subject}</TableCell>
                <TableCell className="text-xs">{t(`tickets.${tk.priority}`)}</TableCell>
                <TableCell><Badge variant={getStatusBadge(tk.status)}>{t(`tickets.${tk.status}`)}</Badge></TableCell>
                <TableCell className="text-xs">{tk.resolved_at ? formatDate(tk.resolved_at) : '-'}</TableCell>
              </TableRow>
            ))}
          </Table>
        )
      ) : tab === 'knowledgeBase' ? (
        articles.length === 0 ? (
          <EmptyState icon={<BookOpen className="w-8 h-8" />} title={t('knowledgeBase.noArticles')} description={t('knowledgeBase.noArticlesDescription')} />
        ) : (
          <Table headers={[t('knowledgeBase.title'), t('knowledgeBase.category'), t('knowledgeBase.views')]}>
            {articles.map(a => (
              <TableRow key={a.id}>
                <TableCell className="font-medium">{a.title}</TableCell>
                <TableCell className="text-xs">{a.category ? t(`knowledgeBase.${a.category}`) : '-'}</TableCell>
                <TableCell className="font-mono text-xs">{a.views}</TableCell>
              </TableRow>
            ))}
          </Table>
        )
      ) : contracts.length === 0 ? (
        <EmptyState icon={<FileText className="w-8 h-8" />} title={t('contracts.noContracts')} description={t('contracts.noContractsDescription')} />
      ) : (
        <Table headers={[t('contracts.number'), t('contracts.name'), t('contracts.type'), t('contracts.endDate'), t('contracts.usedTickets')]}>
          {contracts.map(c => (
            <TableRow key={c.id}>
              <TableCell className="font-mono text-xs">{c.number}</TableCell>
              <TableCell className="font-medium">{c.name}</TableCell>
              <TableCell className="text-xs">{c.contract_type ? t(`contracts.${c.contract_type}`) : '-'}</TableCell>
              <TableCell className="text-xs">{c.end_date ? formatDate(c.end_date) : '-'}</TableCell>
              <TableCell className="font-mono text-xs">{c.used_tickets}/{c.max_tickets || '∞'}</TableCell>
            </TableRow>
          ))}
        </Table>
      )}
    </div>
  )
}
