import { useEffect, useState, useMemo } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Breadcrumb, Input, Select } from '@/components/ui'
import { formatCurrency } from '@/lib/utils'
import {
  getAuthorizedJournals, getFiscalYears, getFiscalPeriods, getChartAccounts,
  getThirdPartyAccounts, getEntryTemplates, getTaxRates,
  getNextPieceNumber, createSaisieEntry, applyAutoLabelRules, calculateVAT,
  calculateEcheance,
} from '@/lib/queries'
import {
  Plus, Trash2, CheckCircle2, Wand2, Calculator, RefreshCw, Layers,
} from 'lucide-react'
import type { Journal, FiscalYear, FiscalPeriod, ChartAccount, ThirdPartyAccount, EntryTemplate, TaxRate } from '@/types'
import { useToast } from '@/lib/toast'
import { CurrencySelector } from '@/components/CurrencySelector'
import { AnalyticDistributionEditor } from '@/components/AnalyticDistributionEditor'
import { getLatestRate } from '@/lib/currencyRates'

interface LineDraft {
  account_general: string
  account_name: string
  account_tiers: string
  description: string
  debit: string
  credit: string
  vat_code: string
  vat_amount: string
  echeance_date: string
  analytic_section: string
  quantity: string
}

function blankLine(): LineDraft {
  return {
    account_general: '', account_name: '', account_tiers: '', description: '',
    debit: '', credit: '', vat_code: '', vat_amount: '', echeance_date: '',
    analytic_section: '', quantity: '',
  }
}

export function SaisieParPiecePage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()

  const [journals, setJournals] = useState<Journal[]>([])
  const [fiscalYears, setFiscalYears] = useState<FiscalYear[]>([])
  const [periods, setPeriods] = useState<FiscalPeriod[]>([])
  const [accounts, setAccounts] = useState<ChartAccount[]>([])
  const [thirdParties, setThirdParties] = useState<ThirdPartyAccount[]>([])
  const [templates, setTemplates] = useState<EntryTemplate[]>([])
  const [taxRates, setTaxRates] = useState<TaxRate[]>([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)

  const [selectedJournal, setSelectedJournal] = useState('')
  const [selectedYear, setSelectedYear] = useState('')
  const [selectedPeriod, setSelectedPeriod] = useState('')
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10))
  const [pieceNumber, setPieceNumber] = useState('')
  const [invoiceRef, setInvoiceRef] = useState('')
  const [description, setDescription] = useState('')
  const [selectedTemplate, setSelectedTemplate] = useState('')
  const [lines, setLines] = useState<LineDraft[]>([blankLine(), blankLine()])
  const [currencyCode, setCurrencyCode] = useState('EUR')
  const [exchangeRate, setExchangeRate] = useState(1.0)
  const [rateLoading, setRateLoading] = useState(false)
  const [showAnalyticDist, setShowAnalyticDist] = useState<number | null>(null)

  useEffect(() => { loadRef() }, [])

  async function loadRef() {
    try {
      const currentUserId = localStorage.getItem('auth_user_id') || undefined
      const [jls, fys, accs, tp, tmpls, txs] = await Promise.all([
        getAuthorizedJournals(currentUserId),
        getFiscalYears(),
        getChartAccounts(),
        getThirdPartyAccounts(),
        getEntryTemplates(),
        getTaxRates(),
      ])
      setJournals(jls || [])
      setFiscalYears(fys || [])
      setAccounts(accs || [])
      setThirdParties(tp || [])
      setTemplates(tmpls || [])
      setTaxRates(txs || [])
      if (fys && fys.length > 0) {
        setSelectedYear(fys[0].id)
      }
    } catch (err) {
      console.error('Error loading ref data:', err)
      toast('error', t('saisieParPiece.title'), t('saisieParPiece.loadError'))
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (selectedYear) {
      getFiscalPeriods(selectedYear).then(setPeriods).catch(() => {})
    }
  }, [selectedYear])

  useEffect(() => {
    if (selectedJournal) {
      getNextPieceNumber(selectedJournal).then(setPieceNumber).catch(() => {})
    }
  }, [selectedJournal])

  const selectedJournalObj = journals.find((j) => j.code === selectedJournal)

  const totalDebit = useMemo(() => lines.reduce((s, l) => s + (Number(l.debit) || 0), 0), [lines])
  const totalCredit = useMemo(() => lines.reduce((s, l) => s + (Number(l.credit) || 0), 0), [lines])
  const isBalanced = Math.abs(totalDebit - totalCredit) < 0.01 && totalDebit > 0

  function updateLine(idx: number, field: keyof LineDraft, value: string) {
    setLines((prev) => prev.map((l, i) => (i === idx ? { ...l, [field]: value } : l)))
  }

  function addLine() { setLines([...lines, blankLine()]) }

  function removeLine(idx: number) {
    if (lines.length > 2) setLines(lines.filter((_, i) => i !== idx))
  }

  function applyTemplate() {
    const tmpl = templates.find((t) => t.id === selectedTemplate)
    if (!tmpl || !tmpl.template_lines) return
    const newLines: LineDraft[] = tmpl.template_lines.map((tl: any) => ({
      account_general: tl.account_general || '',
      account_name: accounts.find((a) => a.code === tl.account_general)?.name || '',
      account_tiers: tl.account_tiers || '',
      description: tl.label || '',
      debit: tl.amount_type === 'fixed' ? String(tl.fixed_amount ?? '') : (tl.debit_pct ? String(tl.debit_pct) : ''),
      credit: tl.amount_type === 'fixed' ? String(tl.fixed_amount ?? '') : (tl.credit_pct ? String(tl.credit_pct) : ''),
      vat_code: tl.vat_code || '', vat_amount: '', echeance_date: '',
      analytic_section: tl.analytic_section || '', quantity: '',
    }))
    setLines(newLines.length > 0 ? newLines : [blankLine()])
  }

  async function handleAccountBlur(idx: number) {
    const line = lines[idx]
    if (!line.account_general) return
    const account = accounts.find((a) => a.code === line.account_general)
    if (account) {
      updateLine(idx, 'account_name', account.name)
      // Auto-label
      if (!line.description) {
        const autoLabel = await applyAutoLabelRules(selectedJournal, line.account_general, line.account_tiers, pieceNumber, date)
        if (autoLabel) updateLine(idx, 'description', autoLabel)
      }
      // Auto-echeance for tiers accounts
      if (account.saisie_echeance && line.account_tiers) {
        const tp = thirdParties.find((tp) => tp.code === line.account_tiers)
        if (tp?.payment_term_id) {
          const echeance = await calculateEcheance(date, tp.payment_term_id)
          if (echeance) updateLine(idx, 'echeance_date', echeance)
        }
      }
    }
  }

  function handleCalculateVAT(idx: number) {
    const line = lines[idx]
    const taxRate = taxRates.find((tr) => String(tr.rate) === line.vat_code)
    if (!taxRate || (!line.debit && !line.credit)) {
      toast('warning', t('saisieParPiece.vatCalc'), t('saisieParPiece.vatSelectRate'))
      return
    }
    const amount = Number(line.debit) || Number(line.credit) || 0
    const isDebit = Boolean(line.debit)
    const { ht, tva, ttc } = calculateVAT(amount, taxRate.rate, 'ht')

    // Update current line to HT
    updateLine(idx, 'vat_amount', String(tva))

    // Add TVA line
    const vatAccount = isDebit ? (taxRate.account_deductible || '445660') : (taxRate.account_collectee || '445710')
    const vatLine = blankLine()
    vatLine.account_general = vatAccount
    vatLine.account_name = taxRate.name
    vatLine.description = `TVA ${taxRate.rate}%`
    vatLine.vat_code = line.vat_code
    if (isDebit) { vatLine.debit = String(tva) } else { vatLine.credit = String(tva) }

    // Add TTC line (contrepartie)
    const ttcLine = blankLine()
    ttcLine.account_general = selectedJournalObj?.account_counterpart || ''
    ttcLine.account_name = 'Contrepartie'
    ttcLine.description = line.description || 'TTC'
    if (isDebit) { ttcLine.credit = String(ttc) } else { ttcLine.debit = String(ttc) }

    setLines((prev) => {
      const newLines = [...prev]
      newLines.splice(idx + 1, 0, vatLine, ttcLine)
      return newLines
    })
    toast('success', t('saisieParPiece.vatCalc'), t('saisieParPiece.vatCalcSuccess', { ht, tva, ttc }))
  }

  function equilibrate() {
    const diff = totalDebit - totalCredit
    if (Math.abs(diff) < 0.01) return
    const lastEmpty = lines.findIndex((l) => !l.debit && !l.credit)
    if (diff > 0) {
      if (lastEmpty >= 0) {
        updateLine(lastEmpty, 'credit', String(diff.toFixed(2)))
      } else {
        setLines([...lines, blankLine()])
        setTimeout(() => updateLine(lines.length, 'credit', String(diff.toFixed(2))), 0)
      }
    } else {
      if (lastEmpty >= 0) {
        updateLine(lastEmpty, 'debit', String(Math.abs(diff).toFixed(2)))
      } else {
        setLines([...lines, blankLine()])
        setTimeout(() => updateLine(lines.length, 'debit', String(Math.abs(diff).toFixed(2))), 0)
      }
    }
  }

  async function handleSubmit() {
    if (!selectedJournal || !selectedPeriod) {
      toast('warning', t('saisieParPiece.title'), t('saisieParPiece.selectJournalPeriod'))
      return
    }
    if (!isBalanced) {
      toast('warning', t('saisieParPiece.title'), t('saisie.notBalanced'))
      return
    }
    setSaving(true)
    try {
      const totalD = lines.reduce((s, l) => s + (Number(l.debit) || 0), 0)
      const totalC = lines.reduce((s, l) => s + (Number(l.credit) || 0), 0)
      const entryLines = lines
        .filter((l) => l.account_general || l.debit || l.credit)
        .map((l, idx) => ({
          account_code: l.account_general,
          account_general: l.account_general,
          account_tiers: l.account_tiers || null,
          account_name: l.account_name,
          description: l.description,
          debit: Number(l.debit) || 0,
          credit: Number(l.credit) || 0,
          line_order: idx + 1,
          line_date: date,
          vat_code: l.vat_code || null,
          vat_amount: Number(l.vat_amount) || 0,
          echeance_date: l.echeance_date || null,
          quantity: Number(l.quantity) || null,
          analytic_section: l.analytic_section || null,
        }))
      await createSaisieEntry({
        number: pieceNumber || `${selectedJournal}-${date}-${Date.now()}`,
        journal_code: selectedJournal,
        date,
        description,
        fiscal_period_id: selectedPeriod,
        piece_number: pieceNumber || null,
        invoice_ref: invoiceRef || null,
        entry_template_id: selectedTemplate || null,
        status: 'draft',
        status_detail: 'open',
        total_debit: totalD,
        total_credit: totalC,
        currency_code: currencyCode,
        functional_currency: 'EUR',
        exchange_rate: exchangeRate,
        exchange_rate_date: date,
        lines: entryLines as any,
      })
      toast('success', t('saisieParPiece.title'), t('saisieParPiece.saveSuccess'))
      // Reset for next piece
      setLines([blankLine(), blankLine()])
      setDescription('')
      setInvoiceRef('')
      if (selectedJournal) getNextPieceNumber(selectedJournal).then(setPieceNumber)
    } catch (err) {
      console.error('Error saving entry:', err)
      toast('error', t('saisieParPiece.title'), t('saisieParPiece.saveError'))
    } finally {
      setSaving(false)
    }
  }

  if (loading) {
    return (
      <div>
        <Breadcrumb items={[{ label: t('title') }, { label: t('home.processing') }, { label: t('saisieParPiece.title') }]} />
        <PageHeader title={t('saisieParPiece.title')} subtitle={t('saisieParPiece.subtitle')} />
        <Card><div className="p-8 text-center text-[var(--color-text-secondary)]">{tCommon('common.loading')}</div></Card>
      </div>
    )
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('home.processing') }, { label: t('saisieParPiece.title') }]} />
      <PageHeader title={t('saisieParPiece.title')} subtitle={t('saisieParPiece.subtitle')} />

      {/* Selection bar */}
      <Card className="mb-4">
        <div className="p-4 grid grid-cols-4 gap-4">
          <Select
            label={t('saisie.journal')}
            value={selectedJournal}
            onChange={(e) => setSelectedJournal(e.target.value)}
            options={[{ value: '', label: t('saisieParPiece.selectJournal') }, ...journals.map((j) => ({ value: j.code, label: `${j.code} — ${j.name}` }))]}
          />
          <Select
            label={t('saisie.fiscalYear')}
            value={selectedYear}
            onChange={(e) => setSelectedYear(e.target.value)}
            options={fiscalYears.map((y) => ({ value: y.id, label: y.code }))}
          />
          <Select
            label={t('saisie.period')}
            value={selectedPeriod}
            onChange={(e) => setSelectedPeriod(e.target.value)}
            options={[{ value: '', label: t('saisie.allPeriods') }, ...periods.map((p) => ({ value: p.id, label: p.period_label }))]}
          />
          <Input label={tCommon('common.date')} type="date" required value={date} onChange={(e) => setDate(e.target.value)} />
        </div>
      </Card>

      {/* Currency header */}
      <Card className="mb-4">
        <div className="p-4 grid grid-cols-3 gap-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('saisie.currency')}</label>
            <CurrencySelector value={currencyCode} onChange={(v) => { setCurrencyCode(v); if (v === 'EUR') setExchangeRate(1.0) }} />
          </div>
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('saisie.exchangeRate')}</label>
            <div className="flex gap-1">
              <input className="input" type="number" step="0.000001" value={exchangeRate} onChange={(e) => setExchangeRate(Number(e.target.value))} disabled={currencyCode === 'EUR'} />
              <button type="button" onClick={async () => {
                if (currencyCode === 'EUR') return
                setRateLoading(true)
                try { const r = await getLatestRate('EUR', currencyCode); if (r) setExchangeRate(r.rate) } catch {} finally { setRateLoading(false) }
              }} disabled={rateLoading || currencyCode === 'EUR'} className="p-2 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)]" title={t('saisie.refreshRate')}>
                <RefreshCw className={`w-4 h-4 ${rateLoading ? 'animate-spin' : ''}`} />
              </button>
            </div>
          </div>
          <div className="flex items-end text-xs text-[var(--color-text-secondary)]">
            {currencyCode !== 'EUR' && exchangeRate > 0 && (
              <span>1 EUR = {exchangeRate.toFixed(4)} {currencyCode}</span>
            )}
          </div>
        </div>
      </Card>

      {/* Piece header */}
      <Card className="mb-4">
        <div className="p-4 grid grid-cols-4 gap-4">
          <Input label={t('saisie.pieceNumber')} value={pieceNumber} onChange={(e) => setPieceNumber(e.target.value)} placeholder={t('saisie.auto')} />
          <Input label={t('saisie.invoiceNumber')} value={invoiceRef} onChange={(e) => setInvoiceRef(e.target.value)} placeholder={tCommon('form.optional')} />
          <Input label={tCommon('common.description')} value={description} onChange={(e) => setDescription(e.target.value)} placeholder={t('saisie.entryObject')} />
          <div className="flex items-end gap-2">
            <div className="flex-1">
              <Select
                label={t('saisie.entryTemplate')}
                value={selectedTemplate}
                onChange={(e) => setSelectedTemplate(e.target.value)}
                options={[{ value: '', label: t('saisie.none') }, ...templates.filter((t) => !t.journal_code || t.journal_code === selectedJournal).map((t) => ({ value: t.id, label: t.name }))]}
              />
            </div>
            <Button variant="secondary" onClick={applyTemplate} disabled={!selectedTemplate}>
              <Wand2 className="w-4 h-4" />
            </Button>
          </div>
        </div>
      </Card>

      {/* Entry grid */}
      <Card>
        <div className="p-4">
          <div className="border border-[var(--color-border)] rounded-lg overflow-hidden">
            <table className="app-table min-w-[1100px]">
              <thead>
                <tr className="border-b border-[var(--color-border)] bg-[var(--color-neutral-50)]">
                  <th className="text-left text-xs font-semibold text-[var(--color-text-secondary)] uppercase px-2 py-2">{t('saisie.accountGeneral')}</th>
                  <th className="text-left text-xs font-semibold text-[var(--color-text-secondary)] uppercase px-2 py-2 w-32">{t('saisie.accountThirdParty')}</th>
                  <th className="text-left text-xs font-semibold text-[var(--color-text-secondary)] uppercase px-2 py-2">{tCommon('common.label')}</th>
                  <th className="text-right text-xs font-semibold text-[var(--color-text-secondary)] uppercase px-2 py-2 w-28">{t('saisie.debit')}</th>
                  <th className="text-right text-xs font-semibold text-[var(--color-text-secondary)] uppercase px-2 py-2 w-28">{t('saisie.credit')}</th>
                  <th className="text-left text-xs font-semibold text-[var(--color-text-secondary)] uppercase px-2 py-2 w-24">{t('saisie.vatCode')}</th>
                  <th className="text-left text-xs font-semibold text-[var(--color-text-secondary)] uppercase px-2 py-2 w-32">{t('saisieParPiece.echeance')}</th>
                  <th className="text-left text-xs font-semibold text-[var(--color-text-secondary)] uppercase px-2 py-2 w-20">{t('saisieParPiece.quantity')}</th>
                  <th className="w-20" />
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--color-border)]">
                {lines.map((line, idx) => (
                  <tr key={idx}>
                    <td className="px-1 py-1.5">
                      <input
                        className="input text-xs py-1 w-32"
                        list="chart-accounts"
                        value={line.account_general}
                        onChange={(e) => updateLine(idx, 'account_general', e.target.value)}
                        onBlur={() => handleAccountBlur(idx)}
                        placeholder="411000"
                      />
                    </td>
                    <td className="px-1 py-1.5">
                      <input
                        className="input text-xs py-1 w-28"
                        list="third-parties"
                        value={line.account_tiers}
                        onChange={(e) => updateLine(idx, 'account_tiers', e.target.value)}
                        placeholder="C-DUPONT"
                      />
                    </td>
                    <td className="px-1 py-1.5">
                      <input
                        className="input text-xs py-1"
                        value={line.description}
                        onChange={(e) => updateLine(idx, 'description', e.target.value)}
                      />
                    </td>
                    <td className="px-1 py-1.5">
                      <input
                        className="input text-xs py-1 w-24 text-right font-mono"
                        type="text"
                        value={line.debit}
                        onChange={(e) => updateLine(idx, 'debit', e.target.value)}
                        placeholder="0.00"
                      />
                    </td>
                    <td className="px-1 py-1.5">
                      <input
                        className="input text-xs py-1 w-24 text-right font-mono"
                        type="text"
                        value={line.credit}
                        onChange={(e) => updateLine(idx, 'credit', e.target.value)}
                        placeholder="0.00"
                      />
                    </td>
                    <td className="px-1 py-1.5">
                      <select
                        className="input text-xs py-1 w-20"
                        value={line.vat_code}
                        onChange={(e) => updateLine(idx, 'vat_code', e.target.value)}
                      >
                        <option value="">—</option>
                        {taxRates.map((tr) => (
                          <option key={tr.id} value={tr.rate}>{tr.rate}% — {tr.name}</option>
                        ))}
                      </select>
                    </td>
                    <td className="px-1 py-1.5">
                      <input
                        className="input text-xs py-1 w-28"
                        type="date"
                        value={line.echeance_date}
                        onChange={(e) => updateLine(idx, 'echeance_date', e.target.value)}
                      />
                    </td>
                    <td className="px-1 py-1.5">
                      <input
                        className="input text-xs py-1 w-16 text-right"
                        type="number"
                        step="0.01"
                        value={line.quantity}
                        onChange={(e) => updateLine(idx, 'quantity', e.target.value)}
                        placeholder="1"
                      />
                    </td>
                    <td className="px-1 py-1.5">
                      <div className="flex gap-1">
                        {line.vat_code && (line.debit || line.credit) && (
                          <button
                            onClick={() => handleCalculateVAT(idx)}
                            className="p-1 text-[var(--color-text-secondary)] hover:text-[var(--color-primary)]"
                            title={t('saisieParPiece.calculateVAT')}
                          >
                            <Calculator className="w-3.5 h-3.5" />
                          </button>
                        )}
                        <button
                          type="button"
                          onClick={() => setShowAnalyticDist(idx)}
                          className="p-1 text-[var(--color-text-secondary)] hover:text-[var(--color-primary)]"
                          title={t('analyticDistribution.open')}
                        >
                          <Layers className="w-3.5 h-3.5" />
                        </button>
                        {lines.length > 2 && (
                          <button
                            onClick={() => removeLine(idx)}
                            className="p-1 text-[var(--color-text-secondary)] hover:text-[var(--color-danger)]"
                          >
                            <Trash2 className="w-3.5 h-3.5" />
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
              <tfoot>
                <tr className="border-t-2 border-[var(--color-border)] bg-[var(--color-neutral-50)]">
                  <td colSpan={3} className="px-2 py-2">
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
                  <td colSpan={8} className="px-2 py-2 text-sm font-medium">
                    {isBalanced ? (
                      <span className="text-[var(--color-success)]">✓ {t('saisie.balanced')}</span>
                    ) : (
                      <span className="text-[var(--color-danger)]">Δ {formatCurrency(Math.abs(totalDebit - totalCredit))}</span>
                    )}
                  </td>
                  <td className="px-2 py-2 text-right text-sm text-[var(--color-text-secondary)]">
                    {t('saisie.difference')}: {formatCurrency(totalDebit - totalCredit)}
                  </td>
                </tr>
              </tfoot>
            </table>
          </div>

          <div className="flex justify-end gap-3 pt-4">
            <Button variant="secondary" onClick={() => { setLines([blankLine(), blankLine()]); setDescription(''); setInvoiceRef('') }}>
              {tCommon('actions.cancel')}
            </Button>
            <Button onClick={handleSubmit} disabled={saving || !isBalanced || !selectedJournal || !selectedPeriod}>
              {saving ? t('saisie.saving') : t('saisie.saveEntry')}
            </Button>
          </div>
        </div>
      </Card>

      {showAnalyticDist !== null && (
        <AnalyticDistributionEditor
          journalLineId={null}
          lineAmount={Number(lines[showAnalyticDist]?.debit || lines[showAnalyticDist]?.credit || 0)}
          onClose={() => setShowAnalyticDist(null)}
        />
      )}

      {/* Datalists for autocomplete */}
      <datalist id="chart-accounts">
        {accounts.map((a) => (<option key={a.id} value={a.code}>{a.name}</option>))}
      </datalist>
      <datalist id="third-parties">
        {thirdParties.map((tp) => (<option key={tp.id} value={tp.code}>{tp.name}</option>))}
      </datalist>
    </div>
  )
}
