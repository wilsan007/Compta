import { useEffect, useState } from 'react'
import { Card, PageHeader, Badge, EmptyState, Breadcrumb, SkeletonTable, Select } from '@/components/ui'
import {
  getFiscalYears, getJournalPeriodStatus,
  closeJournalPeriod, reopenJournalPeriod,
  closeFiscalPeriod, reopenFiscalPeriod,
} from '@/lib/queries'
import { Lock, Unlock, AlertTriangle } from 'lucide-react'
import type { FiscalYear, FiscalPeriod, Journal } from '@/types'
import { useToast } from '@/lib/toast'

interface ClosureEntry {
  id: string
  journal_code: string
  fiscal_period_id: string
  status_detail: string | null
  total_debit: number
  total_credit: number
}

export function JournalClosurePage() {
  const { toast } = useToast()
const [fiscalYears, setFiscalYears] = useState<FiscalYear[]>([])
  const [selectedYear, setSelectedYear] = useState('')
  const [journals, setJournals] = useState<Journal[]>([])
  const [periods, setPeriods] = useState<FiscalPeriod[]>([])
  const [entries, setEntries] = useState<ClosureEntry[]>([])
  const [loading, setLoading] = useState(true)
  const [loadingMatrix, setLoadingMatrix] = useState(false)
  const [actionLoading, setActionLoading] = useState<string | null>(null)

  useEffect(() => {
    loadFiscalYears()
  }, [])

  async function loadFiscalYears() {
    try {
      const fy = await getFiscalYears()
      setFiscalYears(fy || [])
      if (fy && fy.length > 0) setSelectedYear(fy[0].id)
    } catch (err) {
      console.error('Error loading fiscal years:', err)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (selectedYear) loadMatrix()
  }, [selectedYear])

  async function loadMatrix() {
    setLoadingMatrix(true)
    try {
      const data = await getJournalPeriodStatus(selectedYear)
      setJournals(data.journals)
      setPeriods(data.periods)
      setEntries(data.entries as ClosureEntry[])
    } catch (err) {
      console.error('Error loading closure matrix:', err)
    } finally {
      setLoadingMatrix(false)
    }
  }

  function getCellStatus(journalCode: string, periodId: string): { status: string; balanced: boolean; entryCount: number; totalDebit: number; totalCredit: number } {
    const cellEntries = entries.filter(
      (e) => e.journal_code === journalCode && e.fiscal_period_id === periodId
    )
    if (cellEntries.length === 0) {
      return { status: 'empty', balanced: true, entryCount: 0, totalDebit: 0, totalCredit: 0 }
    }
    const allClosed = cellEntries.every((e) => e.status_detail === 'closed')
    const totalD = cellEntries.reduce((s, e) => s + Number(e.total_debit), 0)
    const totalC = cellEntries.reduce((s, e) => s + Number(e.total_credit), 0)
    return {
      status: allClosed ? 'closed' : 'open',
      balanced: Math.abs(totalD - totalC) < 0.01,
      entryCount: cellEntries.length,
      totalDebit: totalD,
      totalCredit: totalC,
    }
  }

  async function handleCloseJournal(journalCode: string, periodId: string) {
  const cell = getCellStatus(journalCode, periodId)
    if (cell.entryCount === 0) {
      toast('info', 'Information', 'Aucune écriture à clôturer pour ce journal et cette période.')
      return
    }
    if (!cell.balanced) {
      toast('info', 'Information', 'Les écritures ne sont pas équilibrées. Impossible de clôturer.')
      return
    }
    if (!confirm(`Clôturer le journal ${journalCode} pour cette période ? La saisie sera bloquée.`)) return
    setActionLoading(`${journalCode}-${periodId}`)
    try {
      await closeJournalPeriod(journalCode, periodId)
      await loadMatrix()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    } finally {
      setActionLoading(null)
    }
  }

  async function handleReopenJournal(journalCode: string, periodId: string) {
    if (!confirm(`Réouvrir le journal ${journalCode} pour cette période ?`)) return
    setActionLoading(`${journalCode}-${periodId}`)
    try {
      await reopenJournalPeriod(journalCode, periodId)
      await loadMatrix()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    } finally {
      setActionLoading(null)
    }
  }

  async function handleClosePeriod(periodId: string) {
    const period = periods.find((p) => p.id === periodId)
    if (!period) return
    const periodEntries = entries.filter((e) => e.fiscal_period_id === periodId)
    const allClosed = periodEntries.length > 0 && periodEntries.every((e) => e.status_detail === 'closed')
    if (periodEntries.length > 0 && !allClosed) {
      toast('info', 'Information', 'Tous les journaux doivent être clôturés avant de clôturer la période.')
      return
    }
    if (!confirm(`Clôturer la période ${period.period_label} ? La saisie sera bloquée pour tous les journaux.`)) return
    setActionLoading(`period-${periodId}`)
    try {
      await closeFiscalPeriod(periodId)
      await loadMatrix()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    } finally {
      setActionLoading(null)
    }
  }

  async function handleReopenPeriod(periodId: string) {
    if (!window.confirm('Réouvrir cette période ?')) return
    setActionLoading(`period-${periodId}`)
    try {
      await reopenFiscalPeriod(periodId)
      await loadMatrix()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    } finally {
      setActionLoading(null)
    }
  }

  const selectedYearObj = fiscalYears.find((y) => y.id === selectedYear)

  if (loading) {
    return (
      <div>
        <Breadcrumb items={[{ label: 'Comptabilité' }, { label: 'Traitement' }, { label: 'Clôture des journaux' }]} />
        <PageHeader title="Clôture des journaux" subtitle="Chargement..." />
        <SkeletonTable rows={6} cols={6} />
      </div>
    )
  }

  return (
    <div>
      <Breadcrumb items={[{ label: 'Comptabilité' }, { label: 'Traitement' }, { label: 'Clôture des journaux' }]} />
      <PageHeader
        title="Clôture des journaux"
        subtitle="Gestion des clôtures par journal et par période"
      />

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-56">
          <Select
            label="Exercice"
            value={selectedYear}
            onChange={(e) => setSelectedYear(e.target.value)}
            options={fiscalYears.map((y) => ({ value: y.id, label: y.code }))}
          />
        </div>
        {selectedYearObj && (
          <Badge variant={selectedYearObj.status === 'open' ? 'success' : 'danger'}>
            {selectedYearObj.status === 'open' ? 'Exercice ouvert' : 'Exercice clôturé'}
          </Badge>
        )}
      </div>

      {!selectedYear || journals.length === 0 ? (
        <EmptyState
          icon={<Lock className="w-8 h-8" />}
          title="Aucune donnée"
          description="Sélectionnez un exercice ou créez des journaux et périodes."
        />
      ) : loadingMatrix ? (
        <SkeletonTable rows={6} cols={8} />
      ) : (
        <div className="space-y-4">
          {/* Period status bar */}
          <Card>
            <div className="p-4">
              <h3 className="text-sm font-semibold mb-3">Statut des périodes</h3>
              <div className="flex flex-wrap gap-2">
                {periods.map((period) => (
                  <div key={period.id} className="flex items-center gap-2 px-3 py-2 rounded-lg border border-[var(--color-border)]">
                    <span className="text-sm font-medium">{period.period_label}</span>
                    <Badge variant={period.status === 'open' ? 'success' : 'danger'}>
                      {period.status === 'open' ? 'Ouverte' : 'Clôturée'}
                    </Badge>
                    {period.status === 'open' ? (
                      <button
                        onClick={() => handleClosePeriod(period.id)}
                        disabled={actionLoading === `period-${period.id}`}
                        className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"
                        title="Clôturer la période"
                      >
                        <Lock className="w-3.5 h-3.5" />
                      </button>
                    ) : (
                      <button
                        onClick={() => handleReopenPeriod(period.id)}
                        disabled={actionLoading === `period-${period.id}`}
                        className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-success)]"
                        title="Réouvrir la période"
                      >
                        <Unlock className="w-3.5 h-3.5" />
                      </button>
                    )}
                  </div>
                ))}
              </div>
            </div>
          </Card>

          {/* Journal × Period matrix */}
          <Card>
            <div className="overflow-x-auto">
              <table className="app-table min-w-[760px]">
                <thead>
                  <tr className="border-b border-[var(--color-border)] bg-[var(--color-neutral-50)]">
                    <th className="text-left text-xs font-semibold text-[var(--color-text-secondary)] uppercase px-3 py-2 sticky left-0 bg-[var(--color-neutral-50)]">
                      Journal
                    </th>
                    {periods.map((p) => (
                      <th key={p.id} className="text-center text-xs font-semibold text-[var(--color-text-secondary)] uppercase px-2 py-2 min-w-[100px]">
                        {p.period_label}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-[var(--color-border)]">
                  {journals.map((journal) => (
                    <tr key={journal.id} className="hover:bg-[var(--color-neutral-50)]">
                      <td className="px-3 py-2 sticky left-0 bg-white">
                        <div className="font-mono text-xs font-semibold">{journal.code}</div>
                        <div className="text-xs text-[var(--color-text-secondary)] truncate max-w-[120px]">{journal.name}</div>
                      </td>
                      {periods.map((period) => {
                        const cell = getCellStatus(journal.code, period.id)
                        const cellKey = `${journal.code}-${period.id}`
                        const isClosed = cell.status === 'closed'
                        const periodClosed = period.status !== 'open'
                        return (
                          <td key={period.id} className="px-2 py-2 text-center">
                            {cell.entryCount === 0 ? (
                              <span className="text-xs text-[var(--color-text-secondary)]">—</span>
                            ) : (
                              <div className="flex flex-col items-center gap-1">
                                <Badge variant={isClosed ? 'danger' : 'success'}>
                                  {isClosed ? 'Clôturé' : 'Ouvert'}
                                </Badge>
                                {!cell.balanced && (
                                  <span title="Écritures non équilibrées">
                                    <AlertTriangle className="w-3.5 h-3.5 text-[var(--color-danger)]" />
                                  </span>
                                )}
                                <span className="text-xs text-[var(--color-text-secondary)]">{cell.entryCount} écr.</span>
                                {!periodClosed && (
                                  <button
                                    onClick={() => isClosed
                                      ? handleReopenJournal(journal.code, period.id)
                                      : handleCloseJournal(journal.code, period.id)}
                                    disabled={actionLoading === cellKey}
                                    className={`p-1 rounded hover:bg-[var(--color-neutral-100)] ${isClosed ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}
                                    title={isClosed ? 'Réouvrir' : 'Clôturer'}
                                  >
                                    {isClosed ? <Unlock className="w-3 h-3" /> : <Lock className="w-3 h-3" />}
                                  </button>
                                )}
                              </div>
                            )}
                          </td>
                        )
                      })}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </Card>

          {/* Summary */}
          <Card>
            <div className="p-4">
              <h3 className="text-sm font-semibold mb-3">Résumé</h3>
              <div className="grid grid-cols-4 gap-4">
                <div>
                  <p className="text-xs text-[var(--color-text-secondary)]">Journaux actifs</p>
                  <p className="text-lg font-semibold">{journals.length}</p>
                </div>
                <div>
                  <p className="text-xs text-[var(--color-text-secondary)]">Périodes</p>
                  <p className="text-lg font-semibold">{periods.length}</p>
                </div>
                <div>
                  <p className="text-xs text-[var(--color-text-secondary)]">Écritures total</p>
                  <p className="text-lg font-semibold">{entries.length}</p>
                </div>
                <div>
                  <p className="text-xs text-[var(--color-text-secondary)]">Écritures clôturées</p>
                  <p className="text-lg font-semibold">{entries.filter((e) => e.status_detail === 'closed').length}</p>
                </div>
              </div>
            </div>
          </Card>
        </div>
      )}
    </div>
  )
}
