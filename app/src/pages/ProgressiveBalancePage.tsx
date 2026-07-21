import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Table, TableRow, TableCell, EmptyState, Breadcrumb, Select, SkeletonTable } from '@/components/ui'
import { getThirdPartyAccounts, getJournalEntries } from '@/lib/queries'
import { useLocale } from '@/hooks/useLocale'
import type { ThirdPartyAccount, JournalEntry } from '@/types'

export function ProgressiveBalancePage() {
  const { t } = useTranslation('accounting')
  const { formatCurrency, formatDate } = useLocale()
  const [thirdParties, setThirdParties] = useState<ThirdPartyAccount[]>([])
  const [entries, setEntries] = useState<JournalEntry[]>([])
  const [loading, setLoading] = useState(true)
  const [selectedThirdParty, setSelectedThirdParty] = useState('')

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const tp = await getThirdPartyAccounts()
      setThirdParties(tp || [])
      if (selectedThirdParty) {
        const allEntries = await getJournalEntries()
        const filtered = (allEntries || []).filter((e: any) =>
          e.lines?.some((l: any) => l.third_party_account === selectedThirdParty)
        )
        setEntries(filtered)
      } else {
        setEntries([])
      }
    } catch (err) {
      console.error('Failed to load progressive balance:', err)
    } finally {
      setLoading(false)
    }
  }, [selectedThirdParty])

  useEffect(() => { loadData() }, [loadData])

  const rows: any[] = []
  let cumulative = 0
  entries.forEach((entry: any) => {
    const lines = (entry.lines || []).filter((l: any) => l.third_party_account === selectedThirdParty)
    lines.forEach((line: any) => {
      const debit = Number(line.debit || 0)
      const credit = Number(line.credit || 0)
      cumulative += debit - credit
      rows.push({
        date: entry.date,
        description: line.description || entry.description,
        debit,
        credit,
        balance: debit - credit,
        cumulative,
      })
    })
  })

  const tableHeaders = [
    t('progressiveBalance.date'),
    t('progressiveBalance.description'),
    t('progressiveBalance.debit'),
    t('progressiveBalance.credit'),
    t('progressiveBalance.balance'),
    t('progressiveBalance.cumulativeBalance'),
  ]

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb') }, { label: t('etats.breadcrumb') }, { label: t('progressiveBalance.breadcrumb') }]} />
      <PageHeader
        title={t('progressiveBalance.title')}
        subtitle={t('progressiveBalance.subtitle')}
      />

      <div className="mb-4">
        <Select
          label={t('progressiveBalance.selectThirdParty')}
          value={selectedThirdParty}
          onChange={(e) => setSelectedThirdParty(e.target.value)}
          options={[
            { value: '', label: t('progressiveBalance.selectThirdParty') },
            ...thirdParties.map((tp) => ({ value: tp.code, label: `${tp.code} — ${tp.name}` })),
          ]}
        />
      </div>

      {loading ? (
        <SkeletonTable rows={5} cols={6} />
      ) : !selectedThirdParty || rows.length === 0 ? (
        <EmptyState
          icon={<span className="text-2xl">📊</span>}
          title={t('progressiveBalance.noData')}
          description={t('progressiveBalance.noDataDescription')}
        />
      ) : (
        <Card>
          <Table headers={tableHeaders}>
            {rows.map((row, idx) => (
              <TableRow key={idx}>
                <TableCell className="text-xs">{formatDate(row.date)}</TableCell>
                <TableCell className="text-sm">{row.description}</TableCell>
                <TableCell className="font-mono text-xs text-right">{row.debit > 0 ? formatCurrency(row.debit) : ''}</TableCell>
                <TableCell className="font-mono text-xs text-right">{row.credit > 0 ? formatCurrency(row.credit) : ''}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(row.balance)}</TableCell>
                <TableCell className={`font-mono text-xs text-right font-semibold ${row.cumulative >= 0 ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>
                  {formatCurrency(row.cumulative)}
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}
    </div>
  )
}
