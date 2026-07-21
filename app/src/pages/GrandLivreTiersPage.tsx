import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Button } from '@/components/ui'
import { useLocale } from '@/hooks/useLocale'
import { getThirdPartyAccounts, getGrandLivreTiers } from '@/lib/queries'
import { BookOpen } from 'lucide-react'
import type { ThirdPartyAccount } from '@/types'

export function GrandLivreTiersPage() {
  const { t } = useTranslation('accounting')
  const { formatCurrency, formatDate } = useLocale()
  const [tiers, setTiers] = useState<ThirdPartyAccount[]>([])
  const [selectedTiers, setSelectedTiers] = useState('')
  const [movements, setMovements] = useState<any[]>([])
  const [loading, setLoading] = useState(false)
  const [, setLoadingTiers] = useState(true)
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')

  useEffect(() => { loadTiers() }, [])

  async function loadTiers() {
    try {
      const data = await getThirdPartyAccounts()
      setTiers(data || [])
    } catch (err) {
      console.error('Error loading tiers:', err)
    } finally {
      setLoadingTiers(false)
    }
  }

  async function loadMovements() {
    if (!selectedTiers) return
    setLoading(true)
    try {
      const data = await getGrandLivreTiers(selectedTiers, dateFrom || undefined, dateTo || undefined)
      setMovements(data || [])
    } catch (err) {
      console.error('Error loading grand livre tiers:', err)
    } finally {
      setLoading(false)
    }
  }

  const totalDebit = movements.reduce((s, m) => s + Number(m.debit), 0)
  const totalCredit = movements.reduce((s, m) => s + Number(m.credit), 0)
  const solde = totalDebit - totalCredit
  const selectedTp = tiers.find((tp) => tp.code === selectedTiers)

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('home.states') }, { label: t('grandLivreTiers.title') }]} />
      <PageHeader title={t('grandLivreTiers.title')} subtitle={t('grandLivreTiers.subtitle')} />

      <Card className="mb-4">
        <div className="p-4 grid grid-cols-4 gap-3 items-end">
          <div className="col-span-2">
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('grandLivreTiers.thirdPartyAccount')}</label>
            <select className="input" value={selectedTiers} onChange={(e) => setSelectedTiers(e.target.value)}>
              <option value="">{t('grandLivreTiers.selectPlaceholder')}</option>
              {tiers.map((tp) => <option key={tp.id} value={tp.code}>{tp.code} — {tp.name}</option>)}
            </select>
          </div>
          <Input label={t('grandLivreTiers.dateFrom')} type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} />
          <Input label={t('grandLivreTiers.dateTo')} type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} />
        </div>
        <div className="px-4 pb-4">
          <Button onClick={loadMovements} disabled={loading || !selectedTiers}>
            {loading ? t('grandLivreTiers.loading') : t('grandLivreTiers.display')}
          </Button>
        </div>
      </Card>

      {!selectedTiers ? (
        <EmptyState
          icon={<BookOpen className="w-8 h-8" />}
          title={t('grandLivreTiers.selectThirdParty')}
          description={t('grandLivreTiers.selectThirdPartyDescription')}
        />
      ) : loading ? (
        <SkeletonTable rows={6} cols={6} />
      ) : movements.length === 0 ? (
        <EmptyState
          icon={<BookOpen className="w-8 h-8" />}
          title={t('grandLivreTiers.noMovements')}
          description={t('grandLivreTiers.noMovementsDescription', { code: selectedTiers, name: selectedTp?.name || '' })}
        />
      ) : (
        <div className="space-y-4">
          <div className="grid grid-cols-3 gap-4">
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('grandLivreTiers.totalDebit')}</p>
              <p className="text-lg font-bold font-mono text-[var(--color-success)]">{formatCurrency(totalDebit)}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('grandLivreTiers.totalCredit')}</p>
              <p className="text-lg font-bold font-mono text-[var(--color-danger)]">{formatCurrency(totalCredit)}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{solde >= 0 ? t('grandLivreTiers.balanceDebit') : t('grandLivreTiers.balanceCredit')}</p>
              <p className="text-lg font-bold font-mono">{formatCurrency(Math.abs(solde))}</p>
            </div>
          </div>

          <Card title={`${selectedTiers} — ${selectedTp?.name || ''}`}>
            <Table headers={[t('entries.date'), t('grandLivreTiers.pieceNumber'), t('grandLivreTiers.journal'), t('grandLivreTiers.description'), t('grandLivreTiers.debit'), t('grandLivreTiers.credit'), t('grandLivreTiers.balance')]}>
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
