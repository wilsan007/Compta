import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Button } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getChartAccounts, getJournals, getGeneralLedgerFiltered, getThirdPartyAccounts } from '@/lib/queries'
import { BookOpen } from 'lucide-react'
import type { ChartAccount, Journal, ThirdPartyAccount } from '@/types'

export function GeneralLedgerPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const [accounts, setAccounts] = useState<ChartAccount[]>([])
  const [journals, setJournals] = useState<Journal[]>([])
  const [thirdParties, setThirdParties] = useState<ThirdPartyAccount[]>([])
  const [movements, setMovements] = useState<any[]>([])
  const [loading, setLoading] = useState(false)
  const [loadingRef, setLoadingRef] = useState(true)
  const [selectedAccount, setSelectedAccount] = useState('')
  const [journalCode, setJournalCode] = useState('')
  const [tiersCode, setTiersCode] = useState('')
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')

  useEffect(() => { loadRef() }, [])

  async function loadRef() {
    try {
      const [accs, jrnls, tp] = await Promise.all([getChartAccounts(), getJournals(), getThirdPartyAccounts().catch(() => [])])
      setAccounts(accs || [])
      setJournals(jrnls || [])
      setThirdParties(tp || [])
    } catch (err) {
      console.error('Error loading ref data:', err)
    } finally {
      setLoadingRef(false)
    }
  }

  async function loadMovements() {
    if (!selectedAccount) return
    setLoading(true)
    try {
      let data = await getGeneralLedgerFiltered(selectedAccount, {
        journalCode: journalCode || undefined,
        dateFrom: dateFrom || undefined,
        dateTo: dateTo || undefined,
      })
      if (tiersCode && data) {
        data = data.filter((m: any) => m.third_party_account === tiersCode || m.journal_entries?.journal_lines?.some((l: any) => l.third_party_account === tiersCode))
      }
      setMovements(data || [])
    } catch (err) {
      console.error('Error loading general ledger:', err)
    } finally {
      setLoading(false)
    }
  }

  const totalDebit = movements.reduce((s, m) => s + Number(m.debit), 0)
  const totalCredit = movements.reduce((s, m) => s + Number(m.credit), 0)
  const solde = totalDebit - totalCredit
  const selectedAcc = accounts.find((a) => a.code === selectedAccount)

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('home.states') }, { label: t('generalLedger.title') }]} />
      <PageHeader title={t('generalLedger.title')} subtitle={t('generalLedger.subtitle')} />

      <Card className="mb-4">
        <div className="p-4 grid grid-cols-4 gap-3 items-end">
          <div className="col-span-2">
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('generalLedger.selectAccount')}</label>
            <select className="input" value={selectedAccount} onChange={(e) => setSelectedAccount(e.target.value)}>
              <option value="">{t('generalLedger.selectAccount')}</option>
              {accounts.map((a) => <option key={a.id} value={a.code}>{a.code} — {a.name}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('closure.journal')}</label>
            <select className="input" value={journalCode} onChange={(e) => setJournalCode(e.target.value)}>
              <option value="">{tCommon('common.all')}</option>
              {journals.map((j) => <option key={j.id} value={j.code}>{j.code} — {j.name}</option>)}
            </select>
          </div>
          <div className="grid grid-cols-2 gap-2">
            <Input label={t('generalLedger.from')} type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} />
            <Input label={t('generalLedger.to')} type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} />
          </div>
        </div>
        <div className="p-4 pt-0">
          <div className="w-80">
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('generalLedger.thirdParty')}</label>
            <select className="input" value={tiersCode} onChange={(e) => setTiersCode(e.target.value)}>
              <option value="">{tCommon('common.all')}</option>
              {thirdParties.map((tp) => <option key={tp.id} value={tp.code}>{tp.code} — {tp.name}</option>)}
            </select>
          </div>
        </div>
        <div className="px-4 pb-4">
          <Button onClick={loadMovements} disabled={loading || !selectedAccount}>
            {loading ? tCommon('common.loading') : tCommon('common.display')}
          </Button>
        </div>
      </Card>

      {!selectedAccount ? (
        <EmptyState
          icon={<BookOpen className="w-8 h-8" />}
          title={t('generalLedger.selectAccount')}
          description={t('generalLedger.subtitle')}
        />
      ) : loading || loadingRef ? (
        <SkeletonTable rows={6} cols={7} />
      ) : movements.length === 0 ? (
        <EmptyState
          icon={<BookOpen className="w-8 h-8" />}
          title={t('generalLedger.noMovements')}
          description={t('generalLedger.noMovementsDescription', { code: selectedAccount, name: selectedAcc?.name || '' })}
        />
      ) : (
        <div className="space-y-4">
          <div className="grid grid-cols-3 gap-4">
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('entries.totalDebit')}</p>
              <p className="text-lg font-bold font-mono text-[var(--color-success)]">{formatCurrency(totalDebit)}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('entries.totalCredit')}</p>
              <p className="text-lg font-bold font-mono text-[var(--color-danger)]">{formatCurrency(totalCredit)}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{solde >= 0 ? t('generalLedger.debitBalance') : t('generalLedger.creditBalance')}</p>
              <p className="text-lg font-bold font-mono">{formatCurrency(Math.abs(solde))}</p>
            </div>
          </div>

          <Card title={`${selectedAccount} — ${selectedAcc?.name || ''}`}>
            <Table headers={[t('entries.date'), t('saisie.pieceNumber'), t('closure.journal'), t('entries.description'), t('entries.debit'), t('entries.credit'), t('entries.balance')]}>
              {(() => {
                let runningBalance = 0
                return movements.map((m) => {
                  runningBalance += Number(m.debit) - Number(m.credit)
                  const je = m.journal_entries
                  return (
                    <TableRow key={m.id}>
                      <TableCell className="text-xs">{je?.date ? formatDate(je.date) : '—'}</TableCell>
                      <TableCell className="font-mono text-xs">{je?.piece_number || je?.number || '—'}</TableCell>
                      <TableCell className="font-mono text-xs">{je?.journal_code}</TableCell>
                      <TableCell className="max-w-xs truncate text-sm">{m.description || je?.description || ''}</TableCell>
                      <TableCell className="font-mono text-xs text-right">{Number(m.debit) > 0 ? formatCurrency(Number(m.debit)) : ''}</TableCell>
                      <TableCell className="font-mono text-xs text-right">{Number(m.credit) > 0 ? formatCurrency(Number(m.credit)) : ''}</TableCell>
                      <TableCell className="font-mono text-xs font-semibold text-right">{formatCurrency(runningBalance)}</TableCell>
                    </TableRow>
                  )
                })
              })()}
            </Table>
          </Card>
        </div>
      )}
    </div>
  )
}
