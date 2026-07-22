import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Button, exportToCSV } from '@/components/ui'
import { getTrialBalanceFiltered, getChartAccounts, getJournals } from '@/lib/queries'
import { formatCurrency } from '@/lib/utils'
import { Scale, Download } from 'lucide-react'
import type { ChartAccount, Journal } from '@/types'

export function TrialBalancePage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')

  const [balances, setBalances] = useState<any[]>([])
  const [accounts, setAccounts] = useState<ChartAccount[]>([])
  const [journals, setJournals] = useState<Journal[]>([])
  const [loading, setLoading] = useState(true)
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')
  const [journalCode, setJournalCode] = useState('')

  useEffect(() => { loadRef() }, [])

  async function loadRef() {
    try {
      const [accs, jrnls] = await Promise.all([getChartAccounts(), getJournals()])
      setAccounts(accs || [])
      setJournals(jrnls || [])
    } catch (err) {
      console.error('Error loading ref data:', err)
    } finally {
      setLoading(false)
    }
  }

  async function loadBalance() {
    setLoading(true)
    try {
      const tb = await getTrialBalanceFiltered({
        dateFrom: dateFrom || undefined,
        dateTo: dateTo || undefined,
        journalCode: journalCode || undefined,
      })
      setBalances(tb)
    } catch (err) {
      console.error('Error loading trial balance:', err)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { loadBalance() }, [])

  const accountMap = new Map(accounts.map((a) => [a.code, a]))

  const enriched = balances.map((b) => {
    const acc = accountMap.get(b.account_code)
    const solde = b.total_debit - b.total_credit
    return {
      ...b,
      type: acc?.type || 'expense',
      solde_debiteur: solde > 0 ? solde : 0,
      solde_crediteur: solde < 0 ? Math.abs(solde) : 0,
    }
  })

  const totalDebit = enriched.reduce((s, b) => s + b.total_debit, 0)
  const totalCredit = enriched.reduce((s, b) => s + b.total_credit, 0)
  const totalSoldeDeb = enriched.reduce((s, b) => s + b.solde_debiteur, 0)
  const totalSoldeCred = enriched.reduce((s, b) => s + b.solde_crediteur, 0)

  const grouped = enriched.reduce((acc, b) => {
    const cls = b.account_code.charAt(0)
    if (!acc[cls]) acc[cls] = []
    acc[cls].push(b)
    return acc
  }, {} as Record<string, any[]>)

  const sortedClasses = Object.keys(grouped).sort()

  function handleExportCSV() {
    const headers = [t('chartAccounts.code'), t('chartAccounts.name'), t('chartAccounts.type'), t('entries.totalDebit'), t('entries.totalCredit'), t('trialBalance.closingDebit'), t('trialBalance.closingCredit')]
    const rows = enriched.map((b) => [
      b.account_code,
      accountMap.get(b.account_code)?.name || '',
      b.type || '',
      b.total_debit || 0,
      b.total_credit || 0,
      b.solde_debiteur || 0,
      b.solde_crediteur || 0,
    ])
    exportToCSV(`trial-balance-${new Date().toISOString().split('T')[0]}.csv`, headers, rows)
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('home.states') }, { label: t('trialBalance.title') }]} />
      <PageHeader title={t('trialBalance.title')} subtitle={t('trialBalance.subtitle')} />

      <Card className="mb-4">
        <div className="p-4 flex gap-3 items-end">
          <Input label={t('generalLedger.from')} type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} />
          <Input label={t('generalLedger.to')} type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} />
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('closure.journal')}</label>
            <select className="input" value={journalCode} onChange={(e) => setJournalCode(e.target.value)}>
              <option value="">{tCommon('common.all')}</option>
              {journals.map((j) => <option key={j.id} value={j.code}>{j.code} — {j.name}</option>)}
            </select>
          </div>
          <Button onClick={loadBalance} disabled={loading}>{tCommon('common.refresh')}</Button>
          {balances.length > 0 && (
            <Button variant="secondary" onClick={handleExportCSV}>
              <Download className="w-4 h-4" /> {t('trialBalance.exportCSV')}
            </Button>
          )}
        </div>
      </Card>

      {loading ? (
        <SkeletonTable rows={10} cols={7} />
      ) : balances.length === 0 ? (
        <EmptyState
          icon={<Scale className="w-8 h-8" />}
          title={t('trialBalance.noData')}
          description={t('entries.noEntriesDescription')}
        />
      ) : (
        <div className="space-y-6">
          <div className="grid grid-cols-4 gap-4">
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('trialBalance.periodDebit')}</p>
              <p className="text-lg font-bold font-mono">{formatCurrency(totalDebit)}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('trialBalance.periodCredit')}</p>
              <p className="text-lg font-bold font-mono">{formatCurrency(totalCredit)}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('trialBalance.closingDebit')}</p>
              <p className="text-lg font-bold font-mono text-[var(--color-success)]">{formatCurrency(totalSoldeDeb)}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('trialBalance.closingCredit')}</p>
              <p className="text-lg font-bold font-mono text-[var(--color-danger)]">{formatCurrency(totalSoldeCred)}</p>
            </div>
          </div>

          {sortedClasses.map((cls) => (
            <Card key={cls} title={t(`trialBalance.classLabels.${cls}`, { defaultValue: `Classe ${cls}` })}>
              <Table headers={[t('chartAccounts.code'), t('chartAccounts.name'), t('chartAccounts.type'), t('entries.totalDebit'), t('entries.totalCredit'), t('trialBalance.closingDebit'), t('trialBalance.closingCredit')]}>
                {grouped[cls].map((b: any) => (
                  <TableRow key={b.account_code}>
                    <TableCell className="font-mono font-semibold">{b.account_code}</TableCell>
                    <TableCell>{accountMap.get(b.account_code)?.name || '—'}</TableCell>
                    <TableCell>
                      <Badge variant="neutral">{t(`chartAccounts.types.${b.type}`, { defaultValue: b.type })}</Badge>
                    </TableCell>
                    <TableCell className="font-mono text-right">{formatCurrency(b.total_debit)}</TableCell>
                    <TableCell className="font-mono text-right">{formatCurrency(b.total_credit)}</TableCell>
                    <TableCell className="font-mono text-[var(--color-success)] text-right">{b.solde_debiteur > 0 ? formatCurrency(b.solde_debiteur) : ''}</TableCell>
                    <TableCell className="font-mono text-[var(--color-danger)] text-right">{b.solde_crediteur > 0 ? formatCurrency(b.solde_crediteur) : ''}</TableCell>
                  </TableRow>
                ))}
              </Table>
            </Card>
          ))}

          <Card title={t('trialBalance.total')}>
            <Table headers={['', '', '', t('entries.totalDebit'), t('entries.totalCredit'), t('trialBalance.closingDebit'), t('trialBalance.closingCredit')]}>
              <TableRow>
                <TableCell colSpan={3} className="font-bold">{t('trialBalance.total').toUpperCase()}</TableCell>
                <TableCell className="font-mono font-bold text-right">{formatCurrency(totalDebit)}</TableCell>
                <TableCell className="font-mono font-bold text-right">{formatCurrency(totalCredit)}</TableCell>
                <TableCell className="font-mono font-bold text-[var(--color-success)] text-right">{formatCurrency(totalSoldeDeb)}</TableCell>
                <TableCell className="font-mono font-bold text-[var(--color-danger)] text-right">{formatCurrency(totalSoldeCred)}</TableCell>
              </TableRow>
            </Table>
          </Card>
        </div>
      )}
    </div>
  )
}
