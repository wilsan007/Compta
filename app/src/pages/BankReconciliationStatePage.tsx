import { useCallback, useEffect, useMemo, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { useNavigate } from 'react-router-dom'
import { AlertTriangle, ArrowLeft, CheckCircle, Link2, Unlink, Wand2 } from 'lucide-react'
import { Badge, Breadcrumb, Button, Card, EmptyState, Input, Modal, PageHeader, Select, SkeletonTable, Table, TableCell, TableRow } from '@/components/ui'
import {
  getBankAccounts, getBankReconciliationState, reconcileBankStatementLine,
  unreconcileBankStatementLine, postBankStatementLine,
  type BankReconciliationState, type BankStatementEcart,
} from '@/lib/queries/banking'
import { getChartAccounts } from '@/lib/queries/accounting'
import { updateStatementBalance } from '@/lib/queries/misc'
import { formatCurrency, formatDate } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import type { BankAccount, ChartAccount } from '@/types'

// R-09 : l'état de rapprochement d'un compte à une date. La fonction
// `get_bank_reconciliation_state` existait depuis la 196 et AUCUN écran ne l'appelait ;
// `is_balanced` y est vrai dès que le pointage est cohérent (c'est un contrôle
// d'intégrité, pas un état) — l'information utile est la liste des écarts, des deux
// côtés, et la comparaison au solde de clôture du relevé importé. Le pointage et la
// comptabilisation passent par les RPC de la 223 : elles écrivent les deux côtés.

const today = () => new Date().toISOString().split('T')[0]
const abs = (value: unknown) => Math.abs(Number(value) || 0)
const daysApart = (a: string, b: string) => Math.abs(new Date(a).getTime() - new Date(b).getTime())

export function BankReconciliationStatePage() {
  const { t } = useTranslation('banking')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const navigate = useNavigate()

  const [accounts, setAccounts] = useState<BankAccount[]>([])
  const [chart, setChart] = useState<ChartAccount[]>([])
  const [accountId, setAccountId] = useState('')
  const [date, setDate] = useState(today())
  const [state, setState] = useState<BankReconciliationState | null>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)

  // Référentiels : chargés une fois
  useEffect(() => {
    let cancelled = false
    Promise.all([getBankAccounts(), getChartAccounts()])
      .then(([list, allAccounts]) => {
        if (cancelled) return
        setAccounts(list)
        setChart(allAccounts)
        setAccountId((current) => current || list[0]?.id || '')
      })
      .catch((err: any) => { if (!cancelled) toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadingError')) })
    return () => { cancelled = true }
  }, [toast, tCommon])

  const loadState = useCallback(async () => {
    if (!accountId || !date) { setState(null); setLoading(false); return }
    setLoading(true)
    try {
      setState(await getBankReconciliationState(accountId, date))
    } catch (err: any) {
      setState(null)
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadingError'))
    } finally {
      setLoading(false)
    }
  }, [accountId, date, toast, tCommon])

  useEffect(() => { loadState() }, [loadState])

  // Écriture du compte candidate pour une ligne de relevé : même montant, sens
  // contraire (un encaissement au relevé débite le compte), la plus proche en date.
  function candidatesFor(tx: BankStatementEcart) {
    const wanted = abs(tx.raw_amount)
    return (state?.ledger_unmatched_transactions || [])
      .filter((line) => tx.type === 'credit' ? Number(line.debit) === wanted : Number(line.credit) === wanted)
      .slice()
      .sort((a, b) => daysApart(a.date, tx.date) - daysApart(b.date, tx.date))
  }

  // Comptes de charge / produit proposés pour « Comptabiliser »
  const counterpartOptions = useMemo(() => chart
    .filter((a) => a.type === 'expense' || a.type === 'income')
    .map((a) => ({ value: a.code, label: `${a.code} — ${a.name}` }))
    .sort((a, b) => a.value.localeCompare(b.value)), [chart])

  function defaultCounterpart(tx: BankStatementEcart | null) {
    const wanted = tx && tx.type === 'credit' ? '768000' : '627000'
    if (counterpartOptions.some((o) => o.value === wanted)) return wanted
    const fallback = tx && tx.type === 'credit'
      ? counterpartOptions.find((o) => o.value.startsWith('7'))
      : counterpartOptions.find((o) => o.value.startsWith('6'))
    return fallback?.value || counterpartOptions[0]?.value || ''
  }

  const selected = accounts.find((a) => a.id === accountId)
  const matchTypeLabel = (code: string | null) => code ? t(`state.matchTypes.${code}`, { defaultValue: code }) : '—'

  // --- Actions -------------------------------------------------------------
  const [pointTx, setPointTx] = useState<BankStatementEcart | null>(null)
  const [pointLine, setPointLine] = useState('')
  const [postTx, setPostTx] = useState<BankStatementEcart | null>(null)
  const [postAccount, setPostAccount] = useState('')
  const [postLabel, setPostLabel] = useState('')
  const [closingAmount, setClosingAmount] = useState('')
  const [closingDate, setClosingDate] = useState(today())

  async function handlePoint() {
    if (!pointTx || !pointLine) return
    setSaving(true)
    try {
      await reconcileBankStatementLine(pointTx.id, pointLine)
      toast('success', tCommon('common.success'), t('state.pointDone'))
      setPointTx(null); setPointLine('')
      await loadState()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setSaving(false) }
  }

  async function handleUnpoint(id: string) {
    setSaving(true)
    try {
      await unreconcileBankStatementLine(id)
      toast('success', tCommon('common.success'), t('state.unpointDone'))
      await loadState()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setSaving(false) }
  }

  async function handlePost() {
    if (!postTx) return
    setSaving(true)
    try {
      await postBankStatementLine(postTx.id, postAccount, postLabel)
      toast('success', tCommon('common.success'), t('state.postDone'))
      setPostTx(null); setPostLabel('')
      await loadState()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setSaving(false) }
  }

  async function handleClosingSave() {
    if (!accountId || !closingAmount || !closingDate) return
    setSaving(true)
    try {
      await updateStatementBalance(accountId, Number(closingAmount), closingDate)
      toast('success', tCommon('common.success'), t('state.closingSaved'))
      await loadState()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setSaving(false) }
  }

  function openPoint(tx: BankStatementEcart) {
    setPointTx(tx)
    setPointLine(candidatesFor(tx)[0]?.id || '')
  }

  function openPost(tx: BankStatementEcart) {
    setPostTx(tx)
    setPostAccount(defaultCounterpart(tx))
    setPostLabel(tx.label || '')
  }

  const integrityBadge = state?.is_balanced
    ? <Badge variant="success">{t('state.integrityOk')}</Badge>
    : <Badge variant="danger">{t('state.integrityBroken')}</Badge>

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('state.title') }]} />
      <PageHeader
        title={t('state.title')}
        subtitle={t('state.subtitle')}
        action={(
          <Button variant="secondary" onClick={() => navigate('/banking/reconciliation')}>
            <ArrowLeft className="w-4 h-4" /> {t('reconciliation.title')}
          </Button>
        )}
      />

      <div className="mb-4 flex flex-wrap items-end gap-3">
        <Select label={t('state.account')} value={accountId} onChange={(e) => setAccountId(e.target.value)}
          className="max-w-xs" options={accounts.map((a) => ({ value: a.id, label: a.name }))} />
        <Input label={t('state.date')} type="date" value={date} onChange={(e) => setDate(e.target.value)} className="max-w-xs" />
      </div>

      {loading ? (
        <SkeletonTable rows={6} cols={5} />
      ) : !state ? (
        <EmptyState icon={<AlertTriangle className="w-8 h-8" />} title={t('state.noAccount')} description={t('state.noAccountDesc')} />
      ) : (
        <>
          <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
            <Card><div className="p-4">
              <p className="text-sm text-[var(--color-text-secondary)]">{t('state.statementBalance')}</p>
              <p className="text-2xl font-bold font-mono">{formatCurrency(Number(state.statement_balance), selected?.currency)}</p>
              <p className="text-xs text-[var(--color-text-secondary)] mt-1">{t('state.statementHint')}</p>
            </div></Card>
            <Card><div className="p-4">
              <p className="text-sm text-[var(--color-text-secondary)]">{t('state.accountingBalance')}</p>
              <p className="text-2xl font-bold font-mono">{formatCurrency(Number(state.accounting_balance), selected?.currency)}</p>
              <p className="text-xs text-[var(--color-text-secondary)] mt-1">{t('state.accountingHint', { account: state.account_code || '—' })}</p>
            </div></Card>
            <Card><div className="p-4">
              <p className="text-sm text-[var(--color-text-secondary)]">{t('state.difference')}</p>
              <p className="text-2xl font-bold font-mono">{formatCurrency(Number(state.difference), selected?.currency)}</p>
              <p className="text-xs text-[var(--color-text-secondary)] mt-1">
                {t('state.explainedDifference', { amount: formatCurrency(Number(state.explained_difference), selected?.currency) })}
              </p>
            </div></Card>
            <Card><div className="p-4">
              <p className="text-sm text-[var(--color-text-secondary)]">{t('state.reconciliation')}</p>
              <p className="text-2xl font-bold">
                {state.is_reconciled
                  ? <span className="text-[var(--color-success)]">{t('state.reconciled')}</span>
                  : t('state.ecarts', { count: state.unmatched_count + state.ledger_unmatched_count })}
              </p>
              <p className="mt-1">{integrityBadge}</p>
            </div></Card>
          </div>

          <Card className="mb-6">
            <div className="p-4">
              <h3 className="text-sm font-semibold">{t('state.closingBalance')}</h3>
              <p className="text-xs text-[var(--color-text-secondary)] mt-1">{t('state.closingHint')}</p>
              {state.statement_closing_balance != null && (
                <div className="flex items-center gap-3 mt-3">
                  <span className="font-mono font-semibold">{formatCurrency(Number(state.statement_closing_balance))}</span>
                  <span className="text-xs text-[var(--color-text-secondary)]">
                    {state.closing_date ? formatDate(state.closing_date) : ''}
                  </span>
                  <Badge variant={state.closing_matches ? 'success' : 'danger'}>
                    {state.closing_matches
                      ? t('state.closingMatches')
                      : t('state.closingGap', { amount: formatCurrency(Number(state.closing_difference || 0)) })}
                  </Badge>
                </div>
              )}
              <div className="mt-3 flex flex-wrap items-end gap-3">
                <Input label={t('state.closingAmount')} type="number" step="0.01" value={closingAmount}
                  onChange={(e) => setClosingAmount(e.target.value)} />
                <Input label={t('state.closingDate')} type="date" value={closingDate}
                  onChange={(e) => setClosingDate(e.target.value)} />
                <Button onClick={handleClosingSave} loading={saving} disabled={!closingAmount}>
                  {t('state.saveClosing')}
                </Button>
              </div>
            </div>
          </Card>

          {/* Écarts côté relevé : à pointer ou à comptabiliser */}
          <h3 className="text-sm font-semibold mb-2">{t('state.statementEcartsTitle', { count: state.unmatched_count })}</h3>
          {state.unmatched_transactions.length === 0 ? (
            <Card className="mb-6">
              <EmptyState icon={<CheckCircle className="w-8 h-8" />}
                title={t('state.noStatementEcarts')} description={t('state.noStatementEcartsDesc')} />
            </Card>
          ) : (
            <Card className="mb-6">
              <Table headers={[t('state.date'), t('state.label'), t('state.amount'), t('state.action')]}>
                {state.unmatched_transactions.map((tx) => (
                  <TableRow key={tx.id}>
                    <TableCell>{formatDate(tx.date)}</TableCell>
                    <TableCell className="max-w-xs truncate">
                      {tx.label || '—'}{tx.reference ? ` · ${tx.reference}` : ''}
                    </TableCell>
                    <TableCell className={`font-mono ${tx.type === 'credit' ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>
                      {tx.type === 'credit' ? '+' : '−'}{formatCurrency(abs(tx.raw_amount))}
                    </TableCell>
                    <TableCell>
                      <div className="flex gap-2">
                        <Button size="sm" onClick={() => openPoint(tx)}>
                          <Link2 className="w-3 h-3" /> {t('state.point')}
                        </Button>
                        <Button size="sm" variant="secondary" onClick={() => openPost(tx)}>
                          <Wand2 className="w-3 h-3" /> {t('state.post')}
                        </Button>
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </Table>
            </Card>
          )}

          {/* Écarts côté compte 512x : l'autre moitié de l'état */}
          <h3 className="text-sm font-semibold mb-2">{t('state.ledgerEcartsTitle', { count: state.ledger_unmatched_count })}</h3>
          {state.ledger_unmatched_transactions.length === 0 ? (
            <Card className="mb-6">
              <EmptyState icon={<CheckCircle className="w-8 h-8" />}
                title={t('state.noLedgerEcarts')} description={t('state.noLedgerEcartsDesc')} />
            </Card>
          ) : (
            <Card className="mb-6">
              <Table headers={[t('state.date'), t('state.entry'), t('state.label'), t('state.debit'), t('state.credit')]}>
                {state.ledger_unmatched_transactions.map((line) => (
                  <TableRow key={line.id}>
                    <TableCell>{formatDate(line.date)}</TableCell>
                    <TableCell className="font-mono text-xs">{line.entry_number || '—'}</TableCell>
                    <TableCell className="max-w-xs truncate">{line.label || line.entry_label || '—'}</TableCell>
                    <TableCell className="font-mono">{Number(line.debit) ? formatCurrency(Number(line.debit)) : '—'}</TableCell>
                    <TableCell className="font-mono">{Number(line.credit) ? formatCurrency(Number(line.credit)) : '—'}</TableCell>
                  </TableRow>
                ))}
              </Table>
            </Card>
          )}

          {/* Pointages effectués : de quoi les défaire */}
          <h3 className="text-sm font-semibold mb-2">{t('state.pairsTitle', { count: state.reconciled_count })}</h3>
          {state.reconciled_transactions.length === 0 ? (
            <Card>
              <EmptyState icon={<Unlink className="w-8 h-8" />}
                title={t('state.noPairs')} description={t('state.noPairsDesc')} />
            </Card>
          ) : (
            <Card>
              <Table headers={[t('state.date'), t('state.label'), t('state.amount'), t('state.entry'), t('state.matchType'), t('state.action')]}>
                {state.reconciled_transactions.map((pair) => (
                  <TableRow key={pair.id}>
                    <TableCell>{formatDate(pair.date)}</TableCell>
                    <TableCell className="max-w-xs truncate">{pair.label || '—'}</TableCell>
                    <TableCell className={`font-mono ${pair.type === 'credit' ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>
                      {pair.type === 'credit' ? '+' : '−'}{formatCurrency(abs(pair.raw_amount))}
                    </TableCell>
                    <TableCell className="font-mono text-xs">{pair.entry_number || '—'}</TableCell>
                    <TableCell><Badge variant="neutral">{matchTypeLabel(pair.match_type)}</Badge></TableCell>
                    <TableCell>
                      <Button size="sm" variant="secondary" onClick={() => handleUnpoint(pair.id)}>
                        <Unlink className="w-3 h-3" /> {t('state.unpoint')}
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
              </Table>
            </Card>
          )}
        </>
      )}

      {/* Pointage : les écritures du compte de même montant, sens contraire */}
      <Modal open={!!pointTx} onClose={() => setPointTx(null)} title={t('state.pointTitle')}>
        {pointTx && (
          <div className="p-4 space-y-4">
            <p className="text-sm">
              {formatDate(pointTx.date)} · {pointTx.label || '—'} · {formatCurrency(abs(pointTx.raw_amount))}
            </p>
            {candidatesFor(pointTx).length === 0 ? (
              <p className="text-sm text-[var(--color-warning-text)]">{t('state.noCandidate')}</p>
            ) : (
              <Select label={t('state.candidate')} value={pointLine} onChange={(e) => setPointLine(e.target.value)}
                options={candidatesFor(pointTx).map((line) => ({
                  value: line.id,
                  label: `${formatDate(line.date)} · ${line.entry_number || '—'} · ${formatCurrency(Number(line.debit) || Number(line.credit))} · ${line.label || ''}`,
                }))} />
            )}
            <div className="flex justify-end gap-3 pt-2 border-t border-[var(--color-border)]">
              <Button variant="secondary" onClick={() => setPointTx(null)}>{tCommon('actions.cancel')}</Button>
              <Button onClick={handlePoint} loading={saving} disabled={!pointLine}>{t('state.point')}</Button>
            </div>
          </div>
        )}
      </Modal>

      {/* Comptabilisation : charge au débit, produit au crédit, contrepartie 512x */}
      <Modal open={!!postTx} onClose={() => setPostTx(null)} title={t('state.postTitle')}>
        {postTx && (
          <div className="p-4 space-y-4">
            <p className="text-sm">
              {formatDate(postTx.date)} · {postTx.label || '—'} · {formatCurrency(abs(postTx.raw_amount))}
            </p>
            <Select label={t('state.counterpart')} value={postAccount} onChange={(e) => setPostAccount(e.target.value)}
              options={counterpartOptions} required />
            <Input label={t('state.label')} value={postLabel} onChange={(e) => setPostLabel(e.target.value)} />
            <p className="text-xs text-[var(--color-text-secondary)]">
              {t('state.postHint', { account: state?.account_code || '—' })}
            </p>
            <div className="flex justify-end gap-3 pt-2 border-t border-[var(--color-border)]">
              <Button variant="secondary" onClick={() => setPostTx(null)}>{tCommon('actions.cancel')}</Button>
              <Button onClick={handlePost} loading={saving} disabled={!postAccount}>{t('state.post')}</Button>
            </div>
          </div>
        )}
      </Modal>
    </div>
  )
}