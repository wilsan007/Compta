import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable } from '@/components/ui'
import { getFiscalYears, closeFiscalYear, allocateResult, pendingResultAllocations, type ResultAllocationLine } from '@/lib/queries/accounting'
import { formatCurrency } from '@/lib/utils'
import { Lock, AlertTriangle, Plus, Trash2 } from 'lucide-react'
import type { FiscalYear } from '@/types'
import { useToast } from '@/lib/toast'
import { confirmSync } from '@/lib/confirm'

// Décision n° 3 : l'affectation du résultat est obligatoire avant de clôturer l'exercice suivant.
// Comptes proposés : bénéfice → réserves, report à nouveau, dividendes, compte de l'exploitant ;
// perte → report à nouveau débiteur, imputation sur report créditeur ou réserves.
const PROFIT_ACCOUNTS = ['106100', '106800', '110000', '457000', '108000'] as const
const LOSS_ACCOUNTS = ['119000', '110000', '106800', '108000'] as const

function ResultAllocationCard({ year, nextYear, onDone }: { year: FiscalYear; nextYear?: FiscalYear; onDone: () => Promise<void> }) {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const result = Number(year.closing_result) || 0
  const profit = result > 0
  const total = Math.abs(result)
  const accounts: readonly string[] = profit ? PROFIT_ACCOUNTS : LOSS_ACCOUNTS
  const [lines, setLines] = useState<ResultAllocationLine[]>([{ account: profit ? '110000' : '119000', amount: total }])
  const [date, setDate] = useState(nextYear?.start_date ?? '')
  const [saving, setSaving] = useState(false)

  const allocated = Math.round(lines.reduce((s, l) => s + (Number(l.amount) || 0), 0) * 100) / 100
  const remaining = Math.round((total - allocated) * 100) / 100

  function update(i: number, patch: Partial<ResultAllocationLine>) {
    setLines((prev) => prev.map((l, j) => (j === i ? { ...l, ...patch } : l)))
  }

  async function submit() {
    setSaving(true)
    try {
      await allocateResult(year.id, lines.filter((l) => Number(l.amount) > 0), date || null)
      toast('success', tCommon('common.success'), t('fiscalYearClosure.allocation.done', { code: year.code }))
      await onDone()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <Card>
      <div className="p-4 space-y-4" data-testid="result-allocation">
        <div>
          <h3 className="text-sm font-semibold">{t('fiscalYearClosure.allocation.title', { code: year.code })}</h3>
          <p className="text-sm text-[var(--color-text-secondary)] mt-1">
            {t(profit ? 'fiscalYearClosure.allocation.introProfit' : 'fiscalYearClosure.allocation.introLoss', { amount: formatCurrency(total) })}
          </p>
        </div>
        <div className="space-y-2">
          {lines.map((l, i) => (
            <div key={i} className="grid grid-cols-[1fr_12rem_auto] gap-2 items-end">
              <div>
                <label htmlFor={`alloc-account-${i}`} className="block text-xs text-[var(--color-text-secondary)] mb-1">{t('fiscalYearClosure.allocation.account')}</label>
                <select id={`alloc-account-${i}`} className="input" value={l.account} onChange={(e) => update(i, { account: e.target.value })}>
                  {accounts.map((a) => <option key={a} value={a}>{a} — {t(`fiscalYearClosure.allocation.accounts.${a}`)}</option>)}
                </select>
              </div>
              <div>
                <label htmlFor={`alloc-amount-${i}`} className="block text-xs text-[var(--color-text-secondary)] mb-1">{t('fiscalYearClosure.allocation.amount')}</label>
                <input id={`alloc-amount-${i}`} className="input text-right font-mono" type="number" min="0" step="0.01"
                  value={l.amount} onChange={(e) => update(i, { amount: Number(e.target.value) })} />
              </div>
              <Button variant="secondary" aria-label={t('fiscalYearClosure.allocation.removeLine')} disabled={lines.length === 1}
                onClick={() => setLines((prev) => prev.filter((_, j) => j !== i))}>
                <Trash2 className="w-4 h-4" />
              </Button>
            </div>
          ))}
          <Button variant="secondary" onClick={() => setLines((prev) => [...prev, { account: accounts[0], amount: Math.max(remaining, 0) }])}>
            <Plus className="w-4 h-4" /> {t('fiscalYearClosure.allocation.addLine')}
          </Button>
        </div>
        <div className="grid grid-cols-2 gap-4 items-end">
          <div>
            <label htmlFor="alloc-date" className="block text-xs text-[var(--color-text-secondary)] mb-1">{t('fiscalYearClosure.allocation.date')}</label>
            <input id="alloc-date" className="input" type="date" value={date}
              min={nextYear?.start_date} max={nextYear?.end_date} onChange={(e) => setDate(e.target.value)} />
          </div>
          <p className={`text-sm font-mono text-right ${remaining === 0 ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`} role="status">
            {t('fiscalYearClosure.allocation.remaining', { amount: formatCurrency(remaining) })}
          </p>
        </div>
        <div className="flex justify-end">
          <Button onClick={submit} disabled={saving || remaining !== 0 || !nextYear}>
            {saving ? t('fiscalYearClosure.allocation.saving') : t('fiscalYearClosure.allocation.submit')}
          </Button>
        </div>
      </div>
    </Card>
  )
}

export function FiscalYearClosurePage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
const [years, setYears] = useState<FiscalYear[]>([])
  const [loading, setLoading] = useState(true)
  const [closing, setClosing] = useState(false)
  const [selectedYear, setSelectedYear] = useState('')
  const [targetYear, setTargetYear] = useState('')
  const [closureResult, setClosureResult] = useState<any>(null)

  // oxlint-disable-next-line react-hooks/exhaustive-deps -- chargement volontairement limite aux valeurs listees
  useEffect(() => { load() }, [])

  async function load() {
  try {
      const data = await getFiscalYears()
      setYears(data || [])
      const openYears = (data || []).filter((y) => y.status === 'open')
      if (openYears.length > 0) setSelectedYear(openYears[0].id)
    } catch (err: any) { console.error('Error loading fiscal years:', err)
    toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadingError'))
    } finally {
      setLoading(false)
    }
  }

  async function handleClose() {
    if (!selectedYear || !targetYear) {
      toast('warning', tCommon('common.warning'), t('fiscalYearClosure.selectYearAndTarget'))
      return
    }
    if (selectedYear === targetYear) {
      toast('warning', tCommon('common.warning'), t('fiscalYearClosure.targetMustDiffer'))
      return
    }
    if (!confirmSync(t('fiscalYearClosure.confirmClose'))) return
    setClosing(true)
    try {
      const result = await closeFiscalYear(selectedYear, targetYear)
      setClosureResult(result)
      toast('success', t('fiscalYearClosure.closed'), t('fiscalYearClosure.resultComputed', {
        defaultValue: 'Résultat de l\'exercice : {{amount}}',
        amount: formatCurrency(Number(result?.result) || 0),
      }))
      await load()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally {
      setClosing(false)
    }
  }

  const openYears = years.filter((y) => y.status === 'open')
  const selectedYearObj = years.find((y) => y.id === selectedYear)
  const pending = pendingResultAllocations(years)
  const nextOf = (y: FiscalYear) => years.find((n) => n.start_date === addDay(y.end_date))
  // La clôture est bloquée tant qu'un exercice antérieur attend l'affectation de son résultat
  const blocking = selectedYearObj ? pending.filter((p) => p.end_date < selectedYearObj.start_date) : []
  const tableHeaders = [t('fiscalYearClosure.code'), t('fiscalYearClosure.label'), t('fiscalYearClosure.status'), t('fiscalYearClosure.actions')]

  if (loading) {
    return (
      <div>
        <Breadcrumb items={[{ label: t('home.breadcrumb') }, { label: t('treatment.breadcrumb') }, { label: t('fiscalYearClosure.breadcrumb') }]} />
        <PageHeader title={t('fiscalYearClosure.title')} subtitle={tCommon('common.loading')} />
        <SkeletonTable rows={4} cols={4} />
      </div>
    )
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb') }, { label: t('treatment.breadcrumb') }, { label: t('fiscalYearClosure.breadcrumb') }]} />
      <PageHeader title={t('fiscalYearClosure.title')} subtitle={t('fiscalYearClosure.subtitle')} />

      {years.length === 0 ? (
        <EmptyState
          icon={<Lock className="w-8 h-8" />}
          title={t('fiscalYearClosure.noYears')}
          description={t('fiscalYearClosure.noYearsDescription')}
        />
      ) : (
        <div className="space-y-4">
          {pending.length > 0 && (
            <ResultAllocationCard key={pending[0].id} year={pending[0]} nextYear={nextOf(pending[0])} onDone={load} />
          )}
          <Card>
            <div className="p-4 space-y-4">
              <h3 className="text-sm font-semibold">{t('fiscalYearClosure.availableYears')}</h3>
              <Table headers={tableHeaders}>
                {years.map((y) => (
                  <TableRow key={y.id}>
                    <TableCell className="font-mono text-sm font-semibold">{y.code}</TableCell>
                    <TableCell className="text-sm">{y.code}</TableCell>
                    <TableCell>
                      <Badge variant={y.status === 'open' ? 'success' : 'danger'}>
                        {y.status === 'open' ? tCommon('status.open') : tCommon('status.closed')}
                      </Badge>
                    </TableCell>
                    <TableCell>
                      {y.status === 'open' && (
                        <Button variant="secondary" onClick={() => setSelectedYear(y.id)}>{t('fiscalYearClosure.select')}</Button>
                      )}
                    </TableCell>
                  </TableRow>
                ))}
              </Table>
            </div>
          </Card>

          {selectedYearObj && (
            <Card>
              <div className="p-4 space-y-4">
                <h3 className="text-sm font-semibold">{t('fiscalYearClosure.closeYear', { code: selectedYearObj.code })}</h3>

                {/* ACC-05 : résultat de la clôture atomique (RPC close_fiscal_year) */}
                {closureResult && (
                  <div className="p-4 rounded-lg bg-[var(--color-success)]/10 border border-[var(--color-success)]/30 space-y-3">
                    <h4 className="text-sm font-semibold text-[var(--color-success)]">{t('fiscalYearClosure.resultTitle')}</h4>
                    <div className="grid grid-cols-2 md:grid-cols-3 gap-4 text-sm">
                      <div>
                        <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('fiscalYearClosure.resultAmount')}</p>
                        <p className={`font-mono font-bold ${(closureResult.result || 0) >= 0 ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>
                          {formatCurrency(Number(closureResult.result) || 0)}
                        </p>
                      </div>
                      <div>
                        <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('fiscalYearClosure.resultAccount', { defaultValue: 'Compte de résultat' })}</p>
                        <p className="font-mono font-bold">{closureResult.result_account || '—'}</p>
                      </div>
                      <div>
                        <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('fiscalYearClosure.closeEntry', { defaultValue: 'Écriture de clôture' })}</p>
                        <p className="font-mono text-xs">{closureResult.close_entry_id ? String(closureResult.close_entry_id).slice(0, 8) : '—'}</p>
                      </div>
                      <div>
                        <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('fiscalYearClosure.carryForwardEntry', { defaultValue: 'Écriture d\'à-nouveaux' })}</p>
                        <p className="font-mono text-xs">{closureResult.carry_forward_entry_id ? String(closureResult.carry_forward_entry_id).slice(0, 8) : '—'}</p>
                      </div>
                      <div className="md:col-span-2">
                        <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('fiscalYearClosure.integrityHash', { defaultValue: 'Empreinte d\'intégrité' })}</p>
                        <p className="font-mono text-xs break-all">{closureResult.hash || '—'}</p>
                      </div>
                    </div>
                  </div>
                )}
                {blocking.length > 0 && (
                  <div role="alert" className="flex items-center gap-3 p-3 rounded-lg bg-[var(--color-danger)]/10 border border-[var(--color-danger)]/30">
                    <AlertTriangle className="w-5 h-5 text-[var(--color-danger)] flex-shrink-0" />
                    <p className="text-sm text-[var(--color-danger)]">
                      {t('fiscalYearClosure.allocation.blocking', { codes: blocking.map((b) => b.code).join(', ') })}
                    </p>
                  </div>
                )}
                <div className="flex items-center gap-3 p-3 rounded-lg bg-[var(--color-warning)]/10 border border-[var(--color-warning)]/30">
                  <AlertTriangle className="w-5 h-5 text-[var(--color-warning)] flex-shrink-0" />
                  <p className="text-sm text-[var(--color-text-secondary)]">
                    {t('fiscalYearClosure.warningMessage')}
                  </p>
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label htmlFor="closure-year" className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('fiscalYearClosure.yearToClose')}</label>
                    <select id="closure-year" className="input" value={selectedYear} onChange={(e) => setSelectedYear(e.target.value)}>
                      {openYears.map((y) => <option key={y.id} value={y.id}>{y.code}</option>)}
                    </select>
                  </div>
                  <div>
                    <label htmlFor="closure-target-year" className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('fiscalYearClosure.targetYear')}</label>
                    <select id="closure-target-year" className="input" value={targetYear} onChange={(e) => setTargetYear(e.target.value)}>
                      <option value="">{t('fiscalYearClosure.selectPlaceholder')}</option>
                      {years.map((y) => <option key={y.id} value={y.id}>{y.code}</option>)}
                    </select>
                  </div>
                </div>
                <div className="flex justify-end">
                  <Button onClick={handleClose} disabled={closing || !targetYear || selectedYear === targetYear || blocking.length > 0}>
                    <Lock className="w-4 h-4" /> {closing ? t('fiscalYearClosure.closing') : t('fiscalYearClosure.close')}
                  </Button>
                </div>
              </div>
            </Card>
          )}
        </div>
      )}
    </div>
  )
}

// Lendemain d'une date ISO (AAAA-MM-JJ), sans décalage de fuseau
function addDay(iso: string): string {
  const d = new Date(`${iso}T00:00:00Z`)
  d.setUTCDate(d.getUTCDate() + 1)
  return d.toISOString().slice(0, 10)
}
