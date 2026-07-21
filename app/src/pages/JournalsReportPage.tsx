import { Fragment, useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, SkeletonTable, Breadcrumb, Table, TableRow, TableCell, Input, Button } from '@/components/ui'
import { getJournalsReport } from '@/lib/queries'
import { useLocale } from '@/hooks/useLocale'
import { Search } from 'lucide-react'
import type { JournalEntry } from '@/types'

export function JournalsReportPage() {
  const { t } = useTranslation('accounting')
  const { formatCurrency, formatDate } = useLocale()
  const [entries, setEntries] = useState<JournalEntry[]>([])
  const [loading, setLoading] = useState(true)
  const [startDate, setStartDate] = useState('')
  const [endDate, setEndDate] = useState('')
  const [expanded, setExpanded] = useState<Set<string>>(new Set())

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      setEntries(await getJournalsReport(startDate || undefined, endDate || undefined))
    } catch (err) {
      console.error('Failed to load journals report:', err)
    } finally {
      setLoading(false)
    }
  }, [startDate, endDate])

  useEffect(() => { loadData() }, [loadData])

  function toggleExpand(id: string) {
    setExpanded(prev => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  const totalDebit = entries.reduce((s, e) => s + Number(e.total_debit), 0)
  const totalCredit = entries.reduce((s, e) => s + Number(e.total_credit), 0)

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.reports') }, { label: t('journalsReport.title') }]} />
      <PageHeader title={t('journalsReport.title')} subtitle={t('journalsReport.subtitle')} />

      <div className="mb-4 flex items-center gap-3">
        <Input type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)} placeholder={t('journalsReport.startDate')} />
        <Input type="date" value={endDate} onChange={(e) => setEndDate(e.target.value)} placeholder={t('journalsReport.endDate')} />
        <Button variant="secondary" onClick={loadData}><Search className="w-4 h-4" /> {t('journalsReport.filter')}</Button>
        <span className="text-sm text-[var(--color-text-secondary)]">{t('journalsReport.entriesCount', { count: entries.length })}</span>
      </div>

      {loading ? (
        <SkeletonTable rows={6} cols={5} />
      ) : (
        <>
          <div className="grid grid-cols-2 gap-4 mb-4">
            <Card>
              <div className="p-4">
                <p className="text-sm text-[var(--color-text-secondary)]">{t('journalsReport.totalDebit')}</p>
                <p className="text-xl font-bold font-mono">{formatCurrency(totalDebit)}</p>
              </div>
            </Card>
            <Card>
              <div className="p-4">
                <p className="text-sm text-[var(--color-text-secondary)]">{t('journalsReport.totalCredit')}</p>
                <p className="text-xl font-bold font-mono">{formatCurrency(totalCredit)}</p>
              </div>
            </Card>
          </div>

          <Card>
            <Table headers={['', t('journalsReport.number'), t('journalsReport.date'), t('journalsReport.description'), t('journalsReport.debit'), t('journalsReport.credit'), t('journalsReport.status')]}>
              {entries.map((e) => (
                <Fragment key={e.id}>
                  <TableRow onClick={() => toggleExpand(e.id)}>
                    <TableCell className="w-8">
                      {expanded.has(e.id) ? '▼' : '▶'}
                    </TableCell>
                    <TableCell className="font-mono text-xs font-semibold">{e.number}</TableCell>
                    <TableCell className="text-xs">{formatDate(e.date)}</TableCell>
                    <TableCell className="text-sm">{e.description}</TableCell>
                    <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(e.total_debit))}</TableCell>
                    <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(e.total_credit))}</TableCell>
                    <TableCell className="text-xs">{e.status === 'posted' ? `✅ ${t('journalsReport.posted')}` : `⏸ ${t('journalsReport.draft')}`}</TableCell>
                  </TableRow>
                  {expanded.has(e.id) && e.journal_lines?.map((line) => (
                    <tr key={line.id} className="bg-[var(--color-neutral-50)]">
                      <TableCell />
                      <TableCell className="font-mono text-xs">{line.account_code}</TableCell>
                      <TableCell className="text-xs" colSpan={2}>{line.account_name} — {line.description || ''}</TableCell>
                      <TableCell className="font-mono text-xs text-right">{Number(line.debit) > 0 ? formatCurrency(Number(line.debit)) : ''}</TableCell>
                      <TableCell className="font-mono text-xs text-right">{Number(line.credit) > 0 ? formatCurrency(Number(line.credit)) : ''}</TableCell>
                      <TableCell />
                    </tr>
                  ))}
                </Fragment>
              ))}
              {entries.length === 0 && (
                <TableRow><TableCell colSpan={7} className="text-center text-[var(--color-text-secondary)]">{t('journalsReport.noEntries')}</TableCell></TableRow>
              )}
            </Table>
          </Card>
        </>
      )}
    </div>
  )
}
