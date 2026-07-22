import { useEffect, useState, useMemo, Fragment } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { formatCurrency, formatDate, evaluateExpression } from '@/lib/utils'
import {
  getJournals, getFiscalYears, getFiscalPeriods, getEntriesForPeriods,
  createSaisieEntry, updateEntryStatusDetail, deleteJournalEntry,
  getChartAccounts, getEntryTemplates, getThirdPartyAccounts, getNextPieceNumber,
  getJournalPeriodBalance, getAnalyticSections,
} from '@/lib/queries'
import {
  Plus, Trash2, X, PenTool, Printer, Lock, CheckCircle2, ChevronDown, ChevronRight, Wand2,
} from 'lucide-react'
import type { Journal, FiscalYear, FiscalPeriod, JournalEntry, ChartAccount, EntryTemplate, ThirdPartyAccount, AnalyticSection } from '@/types'
import { useToast } from '@/lib/toast'

const statusDetailBadge: Record<string, 'success' | 'warning' | 'danger'> = {
  open: 'success',
  printed: 'warning',
  closed: 'danger',
}

type StatusFilter = 'all' | 'opened' | 'not_opened' | 'not_printed' | 'printed' | 'closed'

const STATUS_FILTERS: { key: StatusFilter }[] = [
  { key: 'all' },
  { key: 'opened' },
  { key: 'not_opened' },
  { key: 'not_printed' },
  { key: 'printed' },
  { key: 'closed' },
]

// Derive a status for a (journal × période) cell from its entries
function cellStatus(cellEntries: JournalEntry[]): 'empty' | 'open' | 'printed' | 'closed' {
  if (cellEntries.length === 0) return 'empty'
  if (cellEntries.every((e) => e.status_detail === 'closed')) return 'closed'
  if (cellEntries.every((e) => e.status_detail === 'printed' || e.status_detail === 'closed')) return 'printed'
  return 'open'
}

function matchesFilter(status: 'empty' | 'open' | 'printed' | 'closed', filter: StatusFilter): boolean {
  switch (filter) {
    case 'all': return true
    case 'opened': return status !== 'empty'
    case 'not_opened': return status === 'empty'
    case 'not_printed': return status === 'open' || status === 'empty'
    case 'printed': return status === 'printed' || status === 'closed'
    case 'closed': return status === 'closed'
    default: return true
  }
}

export function JournalSaisiePage() {
  const { toast } = useToast()
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
const [journals, setJournals] = useState<Journal[]>([])
  const [fiscalYears, setFiscalYears] = useState<FiscalYear[]>([])
  const [periods, setPeriods] = useState<FiscalPeriod[]>([])
  const [selectedYear, setSelectedYear] = useState('')
  const [selectedPeriod, setSelectedPeriod] = useState('')
  const [entries, setEntries] = useState<JournalEntry[]>([])
  const [loading, setLoading] = useState(true)
  const [showSaisie, setShowSaisie] = useState(false)
  const [activeJournal, setActiveJournal] = useState<Journal | null>(null)
  const [activePeriod, setActivePeriod] = useState<FiscalPeriod | null>(null)
  const [expanded, setExpanded] = useState<Set<string>>(new Set())
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all')

  useEffect(() => {
    loadInitial()
  }, [])

  async function loadInitial() {
    try {
      const [j, fy] = await Promise.all([
        getJournals(),
        getFiscalYears(),
      ])
      setJournals(j || [])
      setFiscalYears(fy || [])
      if (fy && fy.length > 0) {
        setSelectedYear(fy[0].id)
      }
    } catch (err) {
      console.error('Error loading saisie data:', err)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (selectedYear) {
      loadPeriods(selectedYear)
    }
  }, [selectedYear])

  async function loadPeriods(yearId: string) {
    try {
      const p = await getFiscalPeriods(yearId)
      setPeriods(p || [])
      const openPeriod = p?.find((per) => per.status === 'open')
      setSelectedPeriod(openPeriod?.id || p?.[0]?.id || '')
      await loadEntries(p || [])
    } catch (err) {
      console.error('Error loading periods:', err)
    }
  }

  async function loadEntries(periodList?: FiscalPeriod[]) {
    const ps = periodList || periods
    if (!ps.length) return
    try {
      const all = await getEntriesForPeriods(ps.map((p) => p.id))
      setEntries(all || [])
    } catch (err) {
      console.error('Error loading entries:', err)
    }
  }

  function toggleExpand(id: string) {
  setExpanded((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  async function handleDelete(id: string) {
    if (!window.confirm(tCommon('form.confirmDelete'))) return
    try {
      await deleteJournalEntry(id)
      await loadEntries()
    } catch (err) {
      toast('error', tCommon('toast.error'), t('saisie.deleteError'))
    }
  }

  async function handlePrint(id: string) {
    try {
      await updateEntryStatusDetail(id, 'printed')
      await loadEntries()
    } catch (err) {
      toast('error', tCommon('toast.error'), t('saisie.statusChangeError'))
    }
  }

  async function handleClose(id: string) {
    if (!window.confirm(t('saisie.closeConfirm'))) return
    try {
      await updateEntryStatusDetail(id, 'closed')
      await loadEntries()
    } catch (err) {
      toast('error', tCommon('toast.error'), t('saisie.closeError'))
    }
  }

  const selectedYearObj = fiscalYears.find((y) => y.id === selectedYear)
  const selectedPeriodObj = periods.find((p) => p.id === selectedPeriod)

  // Build the Journal × Période grid (one row per journal × period), like Sage 100
  const gridRows = useMemo(() => {
    const rows: { period: FiscalPeriod; journal: Journal; count: number; status: ReturnType<typeof cellStatus> }[] = []
    const shownPeriods = selectedPeriod ? periods.filter((p) => p.id === selectedPeriod) : periods
    for (const period of shownPeriods) {
      for (const journal of journals) {
        const cellEntries = entries.filter((e) => e.journal_code === journal.code && e.fiscal_period_id === period.id)
        const status = cellStatus(cellEntries)
        if (!matchesFilter(status, statusFilter)) continue
        rows.push({ period, journal, count: cellEntries.length, status })
      }
    }
    return rows
  }, [periods, journals, entries, selectedPeriod, statusFilter])

  if (loading) {
    return (
      <div>
        <Breadcrumb items={[{ label: t('saisie.title') }]} />
        <PageHeader title={t('saisie.title')} subtitle={tCommon('common.loading')} />
        <SkeletonTable rows={6} cols={6} />
      </div>
    )
  }

  if (showSaisie && activeJournal && activePeriod) {
    return (
      <SaisieForm
        journal={activeJournal}
        period={activePeriod}
        fiscalYear={selectedYearObj!}
        onClose={() => { setShowSaisie(false); setActiveJournal(null); setActivePeriod(null) }}
        onSaved={() => { setShowSaisie(false); setActiveJournal(null); setActivePeriod(null); loadEntries() }}
      />
    )
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('saisie.title') }]} />
      <PageHeader
        title={t('saisie.title')}
        subtitle={`${journals.length} ${t('saisie.journalsCount')} — ${gridRows.length} ${t('saisie.rowsShown')}`}
      />

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-56">
          <Select
            label={t('saisie.fiscalYear')}
            value={selectedYear}
            onChange={(e) => setSelectedYear(e.target.value)}
            options={fiscalYears.map((y) => ({ value: y.id, label: y.code }))}
          />
        </div>
        <div className="w-56">
          <Select
            label={t('saisie.period')}
            value={selectedPeriod}
            onChange={(e) => setSelectedPeriod(e.target.value)}
            options={[{ value: '', label: t('saisie.allPeriods') }, ...periods.map((p) => ({ value: p.id, label: p.period_label }))]}
          />
        </div>
        {selectedPeriodObj && (
          <Badge variant={selectedPeriodObj.status === 'open' ? 'success' : 'danger'}>
            {selectedPeriodObj.status === 'open' ? t('saisie.periodOpen') : t('saisie.periodClosed')}
          </Badge>
        )}
      </div>

      {journals.length === 0 ? (
        <EmptyState
          icon={<PenTool className="w-8 h-8" />}
          title={t('saisie.noJournals')}
          description={t('saisie.noJournalsDescription')}
        />
      ) : (
        <div className="flex gap-4">
          {/* Left status filter panel (Sage 100 style) */}
          <div className="w-52 shrink-0">
            <Card>
              <div className="p-2">
                {STATUS_FILTERS.map((f) => (
                  <button
                    key={f.key}
                    onClick={() => setStatusFilter(f.key)}
                    className={`w-full text-left px-3 py-2 rounded text-sm mb-0.5 transition-colors ${
                      statusFilter === f.key
                        ? 'bg-[var(--color-primary)] text-white font-medium'
                        : 'hover:bg-[var(--color-neutral-100)] text-[var(--color-text-primary)]'
                    }`}
                  >
                    {t(`saisie.statusFilters.${f.key}`)}
                  </button>
                ))}
              </div>
            </Card>
          </div>

          {/* Journal × Période grid */}
          <div className="flex-1 min-w-0">
            <Card>
              <Table headers={[t('saisie.position'), t('saisie.period'), t('saisie.code'), t('saisie.journalName'), t('saisie.entries'), tCommon('table.actions')]}>
                {gridRows.map(({ period, journal, count, status }) => {
                  const periodOpen = period.status === 'open'
                  return (
                    <TableRow key={`${period.id}-${journal.id}`}>
                      <TableCell>
                        {status === 'empty' ? (
                          <span className="text-[var(--color-text-secondary)] text-xs">—</span>
                        ) : (
                          <Badge variant={statusDetailBadge[status] || 'success'}>
                            {t(`saisie.statusDetailLabels.${status}`, { defaultValue: status })}
                          </Badge>
                        )}
                      </TableCell>
                      <TableCell className="text-xs">{period.period_label}</TableCell>
                      <TableCell className="font-mono font-semibold">{journal.code}</TableCell>
                      <TableCell>{journal.name}</TableCell>
                      <TableCell className="font-mono text-sm">{count}</TableCell>
                      <TableCell>
                        <Button
                          size="sm"
                          onClick={() => { setActiveJournal(journal); setActivePeriod(period); setShowSaisie(true) }}
                          disabled={!periodOpen}
                        >
                          <PenTool className="w-3 h-3" /> {t('saisie.enter')}
                        </Button>
                      </TableCell>
                    </TableRow>
                  )
                })}
              </Table>
            </Card>
          </div>
        </div>
      )}

      {entries.length > 0 && (
        <div className="mt-6">
          <h3 className="text-sm font-semibold text-[var(--color-text-secondary)] uppercase mb-3">{t('saisie.periodEntries')}</h3>
          <Card>
            <Table headers={['', t('saisie.number'), tCommon('common.date'), t('saisie.journal'), tCommon('common.description'), tCommon('common.status'), t('saisie.debit'), t('saisie.credit'), tCommon('table.actions')]}>
              {entries.map((entry) => (
                <Fragment key={entry.id}>
                  <TableRow onClick={() => toggleExpand(entry.id)}>
                    <TableCell className="w-8">
                      {entry.journal_lines && entry.journal_lines.length > 0
                        ? (expanded.has(entry.id) ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />)
                        : <span className="w-4 inline-block" />}
                    </TableCell>
                    <TableCell className="font-mono text-xs">{entry.piece_number || entry.number}</TableCell>
                    <TableCell className="text-xs">{formatDate(entry.date)}</TableCell>
                    <TableCell className="font-mono text-xs">{entry.journal_code}</TableCell>
                    <TableCell className="max-w-xs truncate text-sm">{entry.description}</TableCell>
                    <TableCell>
                      <Badge variant={statusDetailBadge[entry.status_detail || 'open'] || 'warning'}>
                        {t(`saisie.statusDetailLabels.${entry.status_detail || 'open'}`, { defaultValue: entry.status_detail || 'open' })}
                      </Badge>
                    </TableCell>
                    <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(entry.total_debit))}</TableCell>
                    <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(entry.total_credit))}</TableCell>
                    <TableCell>
                      <div className="flex gap-1">
                        {entry.status_detail !== 'closed' && (
                          <>
                            <button onClick={(e) => { e.stopPropagation(); handlePrint(entry.id) }} title={t('saisie.print')} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]">
                              <Printer className="w-3.5 h-3.5" />
                            </button>
                            <button onClick={(e) => { e.stopPropagation(); handleClose(entry.id) }} title={t('saisie.close')} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                              <Lock className="w-3.5 h-3.5" />
                            </button>
                            <button onClick={(e) => { e.stopPropagation(); handleDelete(entry.id) }} title={tCommon('actions.delete')} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                              <Trash2 className="w-3.5 h-3.5" />
                            </button>
                          </>
                        )}
                      </div>
                    </TableCell>
                  </TableRow>
                  {expanded.has(entry.id) && entry.journal_lines && entry.journal_lines.map((line) => (
                    <TableRow key={line.id} onClick={() => {}}>
                      <TableCell />
                      <TableCell className="font-mono text-xs text-[var(--color-text-secondary)]">{line.account_general || line.account_code}</TableCell>
                      <TableCell colSpan={2} className="text-xs text-[var(--color-text-secondary)]">
                        {line.account_tiers && <span className="font-mono">[{line.account_tiers}] </span>}
                        {line.description || ''}
                      </TableCell>
                      <TableCell />
                      <TableCell />
                      <TableCell className="font-mono text-xs text-right">{Number(line.debit) > 0 ? formatCurrency(Number(line.debit)) : ''}</TableCell>
                      <TableCell className="font-mono text-xs text-right">{Number(line.credit) > 0 ? formatCurrency(Number(line.credit)) : ''}</TableCell>
                      <TableCell />
                    </TableRow>
                  ))}
                </Fragment>
              ))}
            </Table>
          </Card>
        </div>
      )}
    </div>
  )
}

interface LineDraft {
  jour: string
  account_general: string
  account_name: string
  account_tiers: string
  description: string
  debit: string
  credit: string
  piece_number: string
  invoice_number: string
  reference: string
  vat_code: string
  analytic_section: string
}

function blankLine(overrides: Partial<LineDraft> = {}): LineDraft {
  return {
    jour: '', account_general: '', account_name: '', account_tiers: '', description: '',
    debit: '', credit: '', piece_number: '', invoice_number: '', reference: '',
    vat_code: '', analytic_section: '', ...overrides,
  }
}

function SaisieForm({
  journal, period, fiscalYear, onClose, onSaved,
}: {
  journal: Journal
  period: FiscalPeriod
  fiscalYear: FiscalYear
  onClose: () => void
  onSaved: () => void
}) {
  const [accounts, setAccounts] = useState<ChartAccount[]>([])
  const { toast } = useToast()
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const [templates, setTemplates] = useState<EntryTemplate[]>([])
  const [thirdParties, setThirdParties] = useState<ThirdPartyAccount[]>([])
  const [analyticSections, setAnalyticSections] = useState<AnalyticSection[]>([])
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10))
  const [description, setDescription] = useState('')
  const [pieceNumber, setPieceNumber] = useState('')
  const [invoiceRef, setInvoiceRef] = useState('')
  const [selectedTemplate, setSelectedTemplate] = useState('')
  const [lines, setLines] = useState<LineDraft[]>([blankLine(), blankLine()])
  const [saving, setSaving] = useState(false)
  const [searchAccount] = useState('')
  const isBankOrCash = journal.type === 'bank' || journal.type === 'cash'
  const [balance, setBalance] = useState({ ancienSolde: 0, mouvementDebit: 0, mouvementCredit: 0, nouveauSolde: 0 })

  useEffect(() => {
    loadFormData()
    if (isBankOrCash) {
      getJournalPeriodBalance(journal.code, journal.account_counterpart, period.start_date, period.end_date)
        .then(setBalance)
        .catch(() => {})
    }
  }, [])

  async function loadFormData() {
    try {
      const [accs, tmpls, tp, sections] = await Promise.all([
        getChartAccounts(),
        getEntryTemplates(),
        getThirdPartyAccounts(),
        getAnalyticSections().catch(() => []),
        getNextPieceNumber(journal.code),
      ])
      setAccounts(accs || [])
      setTemplates(tmpls || [])
      setThirdParties(tp || [])
      setAnalyticSections(sections || [])
      setPieceNumber(tmpls ? '' : '')
    } catch (err) {
      console.error('Error loading form data:', err)
    }
  }

  useEffect(() => {
    getNextPieceNumber(journal.code).then(setPieceNumber).catch(() => {})
  }, [journal.code])

  function addLine() {
    setLines([...lines, blankLine()])
  }

  function removeLine(idx: number) {
    setLines(lines.filter((_, i) => i !== idx))
  }

  function updateLine(idx: number, field: keyof LineDraft, value: string) {
    setLines(lines.map((l, i) => {
      if (i !== idx) return l
      let processedValue = value
      if (field === 'debit' || field === 'credit') {
        const evaluated = evaluateExpression(value)
        if (evaluated !== null) {
          processedValue = String(evaluated)
        }
      }
      const updated = { ...l, [field]: processedValue }
      if (field === 'account_general') {
        const acc = accounts.find((a) => a.code === value)
        updated.account_name = acc?.name || ''
      }
      return updated
    }))
  }

  function applyTemplate() {
    const tmpl = templates.find((t) => t.id === selectedTemplate)
    if (!tmpl || !tmpl.template_lines) return
    const newLines: LineDraft[] = tmpl.template_lines.map((tl: any) => blankLine({
      account_general: tl.account_general || '',
      account_name: accounts.find((a) => a.code === tl.account_general)?.name || '',
      account_tiers: tl.account_tiers || '',
      description: tl.label || '',
      debit: tl.amount_type === 'fixed' ? String(tl.fixed_amount ?? '') : (tl.debit_pct ? String(tl.debit_pct) : ''),
      credit: tl.amount_type === 'fixed' ? String(tl.fixed_amount ?? '') : (tl.credit_pct ? String(tl.credit_pct) : ''),
      vat_code: tl.vat_code || '',
      analytic_section: tl.analytic_section || '',
    }))
    setLines(newLines.length > 0 ? newLines : [blankLine()])
  }

  function equilibrate() {
    const totalD = lines.reduce((s, l) => s + (Number(l.debit) || 0), 0)
    const totalC = lines.reduce((s, l) => s + (Number(l.credit) || 0), 0)
    const diff = totalD - totalC
    if (Math.abs(diff) < 0.01) return
    if (diff > 0) {
      const lastEmpty = lines.findIndex((l) => !l.credit && !l.debit)
      if (lastEmpty >= 0) {
        updateLine(lastEmpty, 'credit', String(diff.toFixed(2)))
      } else {
        setLines([...lines, blankLine({ account_general: journal.account_counterpart || '', description: 'Contrepartie', credit: String(diff.toFixed(2)) })])
      }
    } else {
      const lastEmpty = lines.findIndex((l) => !l.debit && !l.credit)
      if (lastEmpty >= 0) {
        updateLine(lastEmpty, 'debit', String(Math.abs(diff).toFixed(2)))
      } else {
        setLines([...lines, blankLine({ account_general: journal.account_counterpart || '', description: 'Contrepartie', debit: String(Math.abs(diff).toFixed(2)) })])
      }
    }
  }

  const totalDebit = lines.reduce((s, l) => s + (Number(l.debit) || 0), 0)
  const totalCredit = lines.reduce((s, l) => s + (Number(l.credit) || 0), 0)
  const isBalanced = Math.abs(totalDebit - totalCredit) < 0.01 && totalDebit > 0

  const filteredAccounts = useMemo(() => {
    if (!searchAccount) return accounts
    return accounts.filter((a) => a.code.includes(searchAccount) || a.name.toLowerCase().includes(searchAccount.toLowerCase()))
  }, [accounts, searchAccount])

  async function handleSubmit(e?: React.FormEvent) {
    e?.preventDefault()
    if (!isBalanced) {
      toast('info', tCommon('toast.info'), t('saisie.notBalanced'))
      return
    }
    setSaving(true)
    try {
      const linesData = lines
        .filter((l) => l.account_general && (Number(l.debit) > 0 || Number(l.credit) > 0))
        .map((l, idx) => {
          // Compute the line date from the per-line "Jour" (day number) within the period month
          let lineDate = date
          const dayNum = parseInt(l.jour, 10)
          if (!isNaN(dayNum) && dayNum >= 1 && dayNum <= 31) {
            const base = new Date(period.start_date)
            const dd = String(dayNum).padStart(2, '0')
            const mm = String(base.getMonth() + 1).padStart(2, '0')
            lineDate = `${base.getFullYear()}-${mm}-${dd}`
          }
          const ref = [l.invoice_number, l.reference].filter(Boolean).join(' / ') || null
          return {
            account_code: l.account_general,
            account_name: l.account_name,
            account_general: l.account_general,
            account_tiers: l.account_tiers || null,
            debit: Number(l.debit) || 0,
            credit: Number(l.credit) || 0,
            description: l.description,
            piece_number: l.piece_number || pieceNumber,
            reference: ref,
            line_order: idx,
            line_date: lineDate,
            vat_code: l.vat_code || null,
            analytic_section: l.analytic_section || null,
          }
        })
      await createSaisieEntry({
        number: `${journal.code}-${Date.now().toString().slice(-6)}`,
        date,
        description: description || `Saisie ${journal.code}`,
        journal_code: journal.code,
        fiscal_period_id: period.id,
        piece_number: pieceNumber || null,
        invoice_ref: invoiceRef || null,
        entry_template_id: selectedTemplate || null,
        status: 'draft',
        status_detail: 'open',
        total_debit: totalDebit,
        total_credit: totalCredit,
        lines: linesData,
      })
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.createError'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div>
      <Breadcrumb items={[
        { label: t('saisie.title') },
        { label: `${journal.code} — ${period.period_label}` },
      ]} />
      <PageHeader
        title={t('saisie.saisieTitle', { code: journal.code, name: journal.name })}
        subtitle={t('saisie.saisieSubtitle', { period: period.period_label, year: fiscalYear.code, status: period.status === 'open' ? t('saisie.open') : t('saisie.closed') })}
        action={<Button variant="secondary" onClick={onClose}><X className="w-4 h-4" /> {tCommon('actions.back')}</Button>}
      />

      {isBankOrCash && (
        <Card className="mb-4">
          <div className="p-4 grid grid-cols-3 gap-4">
            <div className="rounded-lg bg-[var(--color-neutral-50)] p-3">
              <p className="text-xs text-[var(--color-text-secondary)] uppercase mb-1">{t('saisie.previousBalance')}</p>
              <p className="text-lg font-bold font-mono">{formatCurrency(balance.ancienSolde)}</p>
            </div>
            <div className="rounded-lg bg-[var(--color-neutral-50)] p-3">
              <p className="text-xs text-[var(--color-text-secondary)] uppercase mb-1">{t('saisie.movements')}</p>
              <div className="text-sm font-mono">
                <span className="text-[var(--color-success)]">+{formatCurrency(balance.mouvementDebit)}</span>
                {' / '}
                <span className="text-[var(--color-danger)]">-{formatCurrency(balance.mouvementCredit)}</span>
              </div>
            </div>
            <div className="rounded-lg bg-[var(--color-neutral-50)] p-3">
              <p className="text-xs text-[var(--color-text-secondary)] uppercase mb-1">{t('saisie.newBalance')}</p>
              <p className="text-lg font-bold font-mono text-[var(--color-primary)]">{formatCurrency(balance.nouveauSolde)}</p>
            </div>
          </div>
        </Card>
      )}

      <Card className="mb-4">
        <div className="p-4 grid grid-cols-4 gap-4">
          <Input label={tCommon('common.date')} type="date" required value={date} onChange={(e) => setDate(e.target.value)} />
          <Input label={t('saisie.pieceNumber')} value={pieceNumber} onChange={(e) => setPieceNumber(e.target.value)} placeholder={t('saisie.auto')} />
          <Input label={t('saisie.invoiceNumber')} value={invoiceRef} onChange={(e) => setInvoiceRef(e.target.value)} placeholder={tCommon('form.optional')} />
          <Input label={tCommon('common.description')} value={description} onChange={(e) => setDescription(e.target.value)} placeholder={t('saisie.entryObject')} />
        </div>
      </Card>

      <Card className="mb-4">
        <div className="p-4 flex items-end gap-3">
          <div className="flex-1">
            <Select
              label={t('saisie.entryTemplate')}
              value={selectedTemplate}
              onChange={(e) => setSelectedTemplate(e.target.value)}
              options={[
                { value: '', label: t('saisie.none') },
                ...templates.filter((t) => !t.journal_code || t.journal_code === journal.code).map((t) => ({ value: t.id, label: t.name })),
              ]}
            />
          </div>
          <Button variant="secondary" onClick={applyTemplate} disabled={!selectedTemplate}>
            <Wand2 className="w-4 h-4" /> {t('saisie.applyTemplate')}
          </Button>
        </div>
      </Card>

      <Card>
        <div className="p-4">
          <div className="border border-[var(--color-border)] rounded-lg overflow-hidden">
            <table className="app-table min-w-[960px]">
              <thead>
                <tr className="border-b border-[var(--color-border)] bg-[var(--color-neutral-50)]">
                  <th className="text-left text-xs font-semibold text-[var(--color-text-secondary)] uppercase px-2 py-2 w-14">{t('saisie.day')}</th>
                  <th className="text-left text-xs font-semibold text-[var(--color-text-secondary)] uppercase px-2 py-2 w-24">{t('saisie.pieceNumber')}</th>
                  <th className="text-left text-xs font-semibold text-[var(--color-text-secondary)] uppercase px-2 py-2 w-24">{t('saisie.invoiceNumber')}</th>
                  <th className="text-left text-xs font-semibold text-[var(--color-text-secondary)] uppercase px-2 py-2 w-24">{tCommon('common.reference')}</th>
                  <th className="text-left text-xs font-semibold text-[var(--color-text-secondary)] uppercase px-2 py-2">{t('saisie.accountGeneral')}</th>
                  <th className="text-left text-xs font-semibold text-[var(--color-text-secondary)] uppercase px-2 py-2">{t('saisie.accountThirdParty')}</th>
                  <th className="text-left text-xs font-semibold text-[var(--color-text-secondary)] uppercase px-2 py-2">{tCommon('common.label')}</th>
                  <th className="text-right text-xs font-semibold text-[var(--color-text-secondary)] uppercase px-2 py-2 w-28">{t('saisie.debit')}</th>
                  <th className="text-right text-xs font-semibold text-[var(--color-text-secondary)] uppercase px-2 py-2 w-28">{t('saisie.credit')}</th>
                  <th className="text-left text-xs font-semibold text-[var(--color-text-secondary)] uppercase px-2 py-2 w-24">{t('saisie.vatCode')}</th>
                  <th className="text-left text-xs font-semibold text-[var(--color-text-secondary)] uppercase px-2 py-2 w-32">{t('saisie.analyticSection')}</th>
                  <th className="w-10" />
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--color-border)]">
                {lines.map((line, idx) => (
                  <tr key={idx}>
                    <td className="px-1 py-1.5">
                      <input
                        className="input text-xs py-1 w-12 text-center"
                        value={line.jour}
                        onChange={(e) => updateLine(idx, 'jour', e.target.value)}
                        placeholder="J"
                      />
                    </td>
                    <td className="px-1 py-1.5">
                      <input
                        className="input text-xs py-1 w-22"
                        value={line.piece_number}
                        onChange={(e) => updateLine(idx, 'piece_number', e.target.value)}
                        placeholder={t('saisie.auto')}
                      />
                    </td>
                    <td className="px-1 py-1.5">
                      <input
                        className="input text-xs py-1 w-22"
                        value={line.invoice_number}
                        onChange={(e) => updateLine(idx, 'invoice_number', e.target.value)}
                      />
                    </td>
                    <td className="px-1 py-1.5">
                      <input
                        className="input text-xs py-1 w-22"
                        value={line.reference}
                        onChange={(e) => updateLine(idx, 'reference', e.target.value)}
                      />
                    </td>
                    <td className="px-2 py-1.5">
                      <select
                        className="input text-xs py-1 w-32"
                        value={line.account_general}
                        onChange={(e) => updateLine(idx, 'account_general', e.target.value)}
                      >
                        <option value="">—</option>
                        {filteredAccounts.map((a) => (
                          <option key={a.id} value={a.code}>{a.code} — {a.name}</option>
                        ))}
                      </select>
                    </td>
                    <td className="px-2 py-1.5">
                      <select
                        className="input text-xs py-1 w-32"
                        value={line.account_tiers}
                        onChange={(e) => updateLine(idx, 'account_tiers', e.target.value)}
                      >
                        <option value="">—</option>
                        {thirdParties.map((t) => (
                          <option key={t.id} value={t.code}>{t.code} — {t.name}</option>
                        ))}
                      </select>
                    </td>
                    <td className="px-2 py-1.5">
                      <input
                        className="input text-xs py-1"
                        value={line.description}
                        onChange={(e) => updateLine(idx, 'description', e.target.value)}
                        placeholder={tCommon('common.label')}
                      />
                    </td>
                    <td className="px-2 py-1.5">
                      <input
                        type="number"
                        step="0.01"
                        className="input text-xs py-1 text-right font-mono w-28"
                        value={line.debit}
                        onChange={(e) => updateLine(idx, 'debit', e.target.value)}
                      />
                    </td>
                    <td className="px-2 py-1.5">
                      <input
                        type="number"
                        step="0.01"
                        className="input text-xs py-1 text-right font-mono w-28"
                        value={line.credit}
                        onChange={(e) => updateLine(idx, 'credit', e.target.value)}
                      />
                    </td>
                    <td className="px-1 py-1.5">
                      <select
                        className="input text-xs py-1 w-24"
                        value={line.vat_code}
                        onChange={(e) => updateLine(idx, 'vat_code', e.target.value)}
                      >
                        <option value="">—</option>
                        <option value="0">{t('saisie.vatRates.rate0')}</option>
                        <option value="5.5">{t('saisie.vatRates.rate55')}</option>
                        <option value="10">{t('saisie.vatRates.rate10')}</option>
                        <option value="20">{t('saisie.vatRates.rate20')}</option>
                      </select>
                    </td>
                    <td className="px-1 py-1.5">
                      <select
                        className="input text-xs py-1 w-32"
                        value={line.analytic_section}
                        onChange={(e) => updateLine(idx, 'analytic_section', e.target.value)}
                      >
                        <option value="">—</option>
                        {analyticSections.map((s) => (
                          <option key={s.id} value={s.code}>{s.code} — {s.name}</option>
                        ))}
                      </select>
                    </td>
                    <td className="px-1 py-1.5">
                      {lines.length > 2 && (
                        <button type="button" onClick={() => removeLine(idx)} className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                          <X className="w-3.5 h-3.5" />
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
              <tfoot>
                <tr className="border-t-2 border-[var(--color-border)] bg-[var(--color-neutral-50)]">
                  <td colSpan={6} className="px-2 py-2">
                    <button type="button" onClick={addLine} className="text-sm text-[var(--color-primary)] hover:underline flex items-center gap-1">
                      <Plus className="w-3 h-3" /> {t('saisie.addLine')}
                    </button>
                  </td>
                  <td className="px-2 py-2 text-right">
                    <button type="button" onClick={equilibrate} className="text-sm text-[var(--color-primary)] hover:underline flex items-center gap-1 ml-auto">
                      <CheckCircle2 className="w-3 h-3" /> {t('saisie.balanc')}
                    </button>
                  </td>
                  <td className="px-2 py-2 text-right font-mono font-semibold text-sm">{formatCurrency(totalDebit)}</td>
                  <td className="px-2 py-2 text-right font-mono font-semibold text-sm">{formatCurrency(totalCredit)}</td>
                  <td colSpan={3} />
                </tr>
                <tr className="bg-[var(--color-neutral-50)]">
                  <td colSpan={9} className="px-2 py-2 text-sm font-medium">
                    {isBalanced ? (
                      <span className="text-[var(--color-success)]">✓ {t('saisie.balanced')}</span>
                    ) : (
                      <span className="text-[var(--color-danger)]">Δ {formatCurrency(Math.abs(totalDebit - totalCredit))}</span>
                    )}
                  </td>
                  <td colSpan={3} className="px-2 py-2 text-right text-sm text-[var(--color-text-secondary)]">
                    {t('saisie.difference')}: {formatCurrency(totalDebit - totalCredit)}
                  </td>
                </tr>
              </tfoot>
            </table>
          </div>

          <div className="flex justify-end gap-3 pt-4">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button onClick={() => handleSubmit()} disabled={saving || !isBalanced}>
              {saving ? t('saisie.saving') : t('saisie.saveEntry')}
            </Button>
          </div>
        </div>
      </Card>
    </div>
  )
}
