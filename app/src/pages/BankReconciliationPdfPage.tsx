import { useState, useEffect, useRef } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, Select } from '@/components/ui'
import { useLocale } from '@/hooks/useLocale'
import { useToast } from '@/lib/toast'
import { getBankAccounts, createBankTransaction, autoMatchBankTransactions, getBanks, getCompanyCountry } from '@/lib/queries/banking'
import { validateTemplateResult } from '@/lib/queries/misc'
import { extractPdfText, parseBankStatement, getAvailableTemplates, getLearnedTemplates, parseWithLearnedTemplate, parseWithAI, parseWithBankTemplate, type ParsedBankTransaction, type AIParseResult } from '@/lib/pdfBankParser'
import { validateFileUpload, FILE_PROFILES } from '@/lib/fileSecurity'
import { Upload, FileText, Zap, CheckCircle, XCircle, AlertTriangle, Loader2, Eye, EyeOff, Sparkles, ThumbsUp, Edit3 } from 'lucide-react'
import type { BankAccount, Bank } from '@/types'

export function BankReconciliationPdfPage() {
  const { t } = useTranslation('banking')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatCurrency, formatDate } = useLocale()

  const [accounts, setAccounts] = useState<BankAccount[]>([])
  const [banks, setBanks] = useState<Bank[]>([])
  const [selectedBank, setSelectedBank] = useState('')
  const [selectedAccount, setSelectedAccount] = useState('')
  const [selectedTemplate, setSelectedTemplate] = useState('ai')
  const [learnedTemplates, setLearnedTemplates] = useState<{ id: string; name: string }[]>([])
  const [parsing, setParsing] = useState(false)
  const [aiMode, setAiMode] = useState(true)
  const [parseResult, setParseResult] = useState<AIParseResult | null>(null)
  const [importing, setImporting] = useState(false)
  const [showRawText, setShowRawText] = useState(false)
  const [importedCount, setImportedCount] = useState(0)
  const [validating, setValidating] = useState(false)
  const [validated, setValidated] = useState(false)
  const [showCorrectionField, setShowCorrectionField] = useState(false)
  const [correctionNotes, setCorrectionNotes] = useState('')
  const fileRef = useRef<HTMLInputElement>(null)

  const builtinTemplates = getAvailableTemplates()

  const loadAccounts = async () => {
    try {
      const accs = await getBankAccounts()
      setAccounts(accs || [])
    } catch (err: any) { console.error('Failed to load bank accounts:', err)
    toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadingError'))
    }
  }

  const loadBanks = async () => {
    try {
      const countryCode = await getCompanyCountry()
      const bankList = await getBanks(countryCode || undefined)
      setBanks(bankList || [])
    } catch (err: any) { console.error('Failed to load banks:', err)
    toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadingError'))
    }
  }

  const loadLearnedTemplates = async () => {
    try {
      const learned = await getLearnedTemplates()
      setLearnedTemplates(learned)
    } catch (err: any) { console.error('Failed to load learned templates:', err)
    toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadingError'))
    }
  }

  useEffect(() => {
    loadAccounts().catch(err => console.error('loadAccounts:', err))
    loadBanks().catch(err => console.error('loadBanks:', err))
    loadLearnedTemplates().catch(err => console.error('loadLearnedTemplates:', err))
  // oxlint-disable-next-line react-hooks/exhaustive-deps -- chargement volontairement limite aux valeurs listees
  }, [])

  async function handleFileUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    if (!selectedAccount) {
      toast('warning', tCommon('common.warning'), t('pdfReconciliation.selectAccount'))
      return
    }
    // SECURITY: Validate file before processing
    const validation = await validateFileUpload(file, FILE_PROFILES.pdf)
    if (!validation.ok) {
      toast('error', tCommon('common.error'), validation.error || 'Invalid file')
      e.target.value = ''
      return
    }

    setParsing(true)
    setParseResult(null)
    setImportedCount(0)
    setValidated(false)
    try {
      const rawText = await extractPdfText(file)
      let result: AIParseResult
      if (aiMode || selectedTemplate === 'ai') {
        const bank = banks.find(b => b.id === selectedBank)
        result = await parseWithAI(rawText, bank?.name, selectedBank || undefined)
        await loadLearnedTemplates()
      } else if (selectedBank && selectedTemplate === 'bank_template') {
        const learned = await parseWithBankTemplate(rawText, selectedBank)
        result = learned ? { ...learned } : await parseWithAI(rawText, banks.find(b => b.id === selectedBank)?.name, selectedBank)
      } else if (selectedTemplate.startsWith('db_')) {
        const learned = await parseWithLearnedTemplate(rawText, selectedTemplate)
        result = learned ? { ...learned } : parseBankStatement(rawText, 'generic')
      } else {
        const r = parseBankStatement(rawText, selectedTemplate)
        result = { ...r }
      }
      setParseResult(result)
      if (result.transactions.length === 0) {
        toast('warning', tCommon('common.warning'), t('pdfReconciliation.noTransactions'))
      } else {
        toast('success', tCommon('common.success'), t('pdfReconciliation.parsed', { count: result.transactions.length }))
      }
    } catch (err: any) {
      console.error('PDF parse error:', err)
      toast('error', tCommon('common.error'), t('pdfReconciliation.parseError') + ': ' + (err.message || ''))
    } finally {
      setParsing(false)
    }
  }

  async function handleImportAndReconcile() {
    if (!parseResult || !selectedAccount) return
    setImporting(true)
    try {
      let count = 0
      for (const tx of parseResult.transactions) {
        await createBankTransaction({
          account_id: selectedAccount,
          date: tx.date,
          description: tx.description,
          reference: tx.reference,
          type: tx.type,
          amount: tx.amount,
          category: 'import',
          reconciled: false,
          matched: false,
          matched_line_id: null,
          invoice_id: null,
          purchase_invoice_id: null,
        })
        count++
      }
      setImportedCount(count)
      toast('success', tCommon('common.success'), t('pdfReconciliation.imported', { count }))

      const matchResult = await autoMatchBankTransactions(selectedAccount)
      toast('success', tCommon('common.success'), t('pdfReconciliation.autoMatched', { matched: matchResult.matched, unmatched: matchResult.unmatched }))
    } catch (err: any) {
      console.error('Import error:', err)
      toast('error', tCommon('common.error'), t('pdfReconciliation.importError') + ': ' + (err.message || ''))
    } finally {
      setImporting(false)
    }
  }

  function handleReset() {
    setParseResult(null)
    setImportedCount(0)
    setValidated(false)
    if (fileRef.current) fileRef.current.value = ''
  }

  async function handleValidate(hadCorrections: boolean) {
    if (!parseResult?.templateId) return
    // If corrections needed but no notes yet, show the correction field first
    if (hadCorrections && !showCorrectionField) {
      setShowCorrectionField(true)
      return
    }
    setValidating(true)
    try {
      const notes = hadCorrections ? correctionNotes.trim() : undefined
      const updated = await validateTemplateResult(parseResult.templateId, hadCorrections, notes)
      setValidated(true)
      setShowCorrectionField(false)
      if (updated.validation_status === 'validated') {
        toast('success', tCommon('common.success'), t('pdfReconciliation.templateValidated'))
      } else if (hadCorrections) {
        toast('info', tCommon('common.info'), t('pdfReconciliation.correctionsRecorded'))
      } else {
        toast('success', tCommon('common.success'), t('pdfReconciliation.validationRecorded', { count: updated.consecutive_successes }))
      }
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || 'Validation failed')
    } finally {
      setValidating(false)
    }
  }

  const totalDebit = parseResult?.transactions.filter(t => t.type === 'debit').reduce((s, t) => s + t.amount, 0) || 0
  const totalCredit = parseResult?.transactions.filter(t => t.type === 'credit').reduce((s, t) => s + t.amount, 0) || 0

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('pdfReconciliation.title') }]} />
      <PageHeader title={t('pdfReconciliation.title')} subtitle={t('pdfReconciliation.subtitle')} />

      <Card className="mb-4">
        <div className="p-4 space-y-4">
          <div className="flex items-end gap-4 flex-wrap">
            <div className="flex-1 min-w-[200px]">
              <Select
                label={t('pdfReconciliation.account')}
                value={selectedAccount}
                onChange={(e) => setSelectedAccount(e.target.value)}
                options={[
                  { value: '', label: t('pdfReconciliation.selectAccount') },
                  ...accounts.map(a => ({ value: a.id, label: `${a.name} (${a.account_number})` })),
                ]}
              />
            </div>
            <div className="flex-1 min-w-[200px]">
              <Select
                label={t('pdfReconciliation.selectBank')}
                value={selectedBank}
                onChange={(e) => setSelectedBank(e.target.value)}
                options={[
                  { value: '', label: t('pdfReconciliation.selectBankPlaceholder') },
                  ...banks.map(b => ({ value: b.id, label: b.name })),
                ]}
              />
            </div>
            <div className="flex-1 min-w-[200px]">
              <Select
                label={t('pdfReconciliation.template')}
                value={selectedTemplate}
                onChange={(e) => { setSelectedTemplate(e.target.value); setAiMode(e.target.value === 'ai') }}
                options={[
                  { value: 'ai', label: `🤖 ${t('pdfReconciliation.aiAutoDetect')}` },
                  ...(selectedBank ? [{ value: 'bank_template', label: t('pdfReconciliation.useBankTemplate') }] : []),
                  ...builtinTemplates.map(tpl => ({ value: tpl.id, label: tpl.name })),
                  ...(learnedTemplates.length > 0
                    ? [{ value: '__learned__', label: '── ' + t('pdfReconciliation.learnedTemplates') + ' ──' }, ...learnedTemplates.map(tpl => ({ value: tpl.id, label: tpl.name }))]
                    : []),
                ]}
              />
            </div>
            <div>
              <Button disabled={parsing || !selectedAccount} onClick={() => fileRef.current?.click()}>
                <label className="flex items-center gap-2 cursor-pointer">
                  {parsing ? <Loader2 className="w-4 h-4 animate-spin" /> : (aiMode ? <Sparkles className="w-4 h-4" /> : <Upload className="w-4 h-4" />)}
                  {parsing ? t('pdfReconciliation.parsing') : (aiMode ? t('pdfReconciliation.aiParsing') : t('pdfReconciliation.upload'))}
                </label>
              </Button>
              <input ref={fileRef} type="file" className="hidden" onChange={handleFileUpload} accept=".pdf" />
            </div>
          </div>

          <div className="flex items-center gap-2 text-xs text-[var(--color-text-secondary)] bg-[var(--color-neutral-50)] rounded-lg p-3">
            {aiMode ? <Sparkles className="w-4 h-4 flex-shrink-0 text-[var(--color-primary)]" /> : <AlertTriangle className="w-4 h-4 flex-shrink-0" />}
            <span>{aiMode ? t('pdfReconciliation.aiHelpText') : t('pdfReconciliation.helpText')}</span>
          </div>
        </div>
      </Card>

      {parseResult && (
        <>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-4">
            <Card>
              <div className="p-4">
                <p className="text-sm text-[var(--color-text-secondary)]">{t('pdfReconciliation.transactionsFound')}</p>
                <p className="text-2xl font-bold">{parseResult.transactions.length}</p>
              </div>
            </Card>
            <Card>
              <div className="p-4">
                <p className="text-sm text-[var(--color-text-secondary)]">{t('pdfReconciliation.totalCredit')}</p>
                <p className="text-2xl font-bold font-mono text-[var(--color-success)]">{formatCurrency(totalCredit)}</p>
              </div>
            </Card>
            <Card>
              <div className="p-4">
                <p className="text-sm text-[var(--color-text-secondary)]">{t('pdfReconciliation.totalDebit')}</p>
                <p className="text-2xl font-bold font-mono text-[var(--color-danger)]">{formatCurrency(totalDebit)}</p>
              </div>
            </Card>
            <Card>
              <div className="p-4">
                <p className="text-sm text-[var(--color-text-secondary)]">{t('pdfReconciliation.accountNumber')}</p>
                <p className="text-lg font-mono">{parseResult.accountNumber || '—'}</p>
              </div>
            </Card>
          </div>

          {parseResult.warnings.length > 0 && (
            <div className="mb-4 p-3 rounded-lg bg-[rgba(255,149,0,0.08)] border border-[var(--color-warning)]">
              <div className="flex items-start gap-2">
                <AlertTriangle className="w-4 h-4 text-[var(--color-warning)] flex-shrink-0 mt-0.5" />
                <div className="text-sm text-[var(--color-text-secondary)]">
                  {parseResult.warnings.map((w, i) => <p key={i}>{w}</p>)}
                </div>
              </div>
            </div>
          )}

          {parseResult.transactions.length > 0 && (
            <div className="mb-4 flex items-center gap-3">
              <Button onClick={handleImportAndReconcile} disabled={importing}>
                {importing ? <Loader2 className="w-4 h-4 animate-spin" /> : <Zap className="w-4 h-4" />}
                {importing ? t('pdfReconciliation.importing') : t('pdfReconciliation.importAndReconcile')}
              </Button>
              {importedCount > 0 && (
                <Badge variant="success">
                  <CheckCircle className="w-3 h-3 mr-1" />
                  {t('pdfReconciliation.imported', { count: importedCount })}
                </Badge>
              )}
              <Button variant="ghost" onClick={handleReset}>
                <XCircle className="w-4 h-4" /> {t('pdfReconciliation.reset')}
              </Button>
              <Button variant="ghost" onClick={() => setShowRawText(!showRawText)}>
                {showRawText ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                {showRawText ? t('pdfReconciliation.hideRaw') : t('pdfReconciliation.showRaw')}
              </Button>
            </div>
          )}

          {showRawText && parseResult.rawText && (
            <Card className="mb-4">
              <div className="p-4">
                <p className="text-sm font-medium mb-2">{t('pdfReconciliation.rawText')}</p>
                <pre className="text-xs font-mono max-h-64 overflow-y-auto whitespace-pre-wrap bg-[var(--color-neutral-50)] p-3 rounded">
                  {parseResult.rawText}
                </pre>
              </div>
            </Card>
          )}

          {parseResult.transactions.length > 0 ? (
            <Card>
              <Table headers={[
                t('pdfReconciliation.date'),
                t('pdfReconciliation.description'),
                t('pdfReconciliation.reference'),
                t('pdfReconciliation.type'),
                t('pdfReconciliation.amount'),
              ]}>
                {parseResult.transactions.map((tx: ParsedBankTransaction, i: number) => (
                  <TableRow key={i}>
                    <TableCell className="text-xs">{formatDate(tx.date)}</TableCell>
                    <TableCell className="max-w-xs truncate text-sm">{tx.description}</TableCell>
                    <TableCell className="text-xs font-mono">{tx.reference || '—'}</TableCell>
                    <TableCell>
                      <Badge variant={tx.type === 'credit' ? 'success' : 'danger'}>
                        {tx.type === 'credit' ? t('transactions.types.credit') : t('transactions.types.debit')}
                      </Badge>
                    </TableCell>
                    <TableCell className={`font-mono text-sm ${tx.type === 'credit' ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>
                      {tx.type === 'credit' ? '+' : '-'}{formatCurrency(tx.amount)}
                    </TableCell>
                  </TableRow>
                ))}
              </Table>
            </Card>
          ) : (
            <EmptyState
              icon={<FileText className="w-8 h-8" />}
              title={t('pdfReconciliation.noTransactions')}
              description={t('pdfReconciliation.noTransactionsDesc')}
            />
          )}

          {/* Validation section — only for AI-parsed results with a template ID */}
          {parseResult.templateId && parseResult.transactions.length > 0 && !validated && (
            <Card className="mt-4">
              <div className="p-4">
                <div className="flex items-center gap-2 mb-3">
                  <Sparkles className="w-5 h-5 text-[var(--color-primary)]" />
                  <h3 className="text-sm font-semibold">{t('pdfReconciliation.validateTitle')}</h3>
                </div>
                <p className="text-sm text-[var(--color-text-secondary)] mb-4">{t('pdfReconciliation.validateDesc')}</p>

                {showCorrectionField ? (
                  <div className="space-y-3">
                    <textarea
                      className="w-full text-sm border rounded-lg p-3 min-h-[80px] bg-[var(--color-bg)]"
                      placeholder={t('pdfReconciliation.correctionPlaceholder')}
                      value={correctionNotes}
                      onChange={(e) => setCorrectionNotes(e.target.value)}
                    />
                    <div className="flex items-center gap-3">
                      <Button variant="primary" onClick={() => handleValidate(true)} disabled={validating || !correctionNotes.trim()}>
                        {validating ? <Loader2 className="w-4 h-4 animate-spin" /> : <CheckCircle className="w-4 h-4" />}
                        {t('pdfReconciliation.submitCorrections')}
                      </Button>
                      <Button variant="ghost" onClick={() => setShowCorrectionField(false)}>
                        {t('pdfReconciliation.cancel')}
                      </Button>
                    </div>
                  </div>
                ) : (
                  <div className="flex items-center gap-3">
                    <Button variant="primary" onClick={() => handleValidate(false)} disabled={validating}>
                      {validating ? <Loader2 className="w-4 h-4 animate-spin" /> : <ThumbsUp className="w-4 h-4" />}
                      {t('pdfReconciliation.dataCorrect')}
                    </Button>
                    <Button variant="secondary" onClick={() => handleValidate(true)} disabled={validating}>
                      <Edit3 className="w-4 h-4" />
                      {t('pdfReconciliation.dataNeedsCorrections')}
                    </Button>
                  </div>
                )}
              </div>
            </Card>
          )}

          {validated && parseResult.templateId && (
            <div className="mt-4 p-3 rounded-lg bg-[rgba(34,197,94,0.08)] border border-[var(--color-success)]">
              <div className="flex items-center gap-2">
                <CheckCircle className="w-4 h-4 text-[var(--color-success)]" />
                <span className="text-sm text-[var(--color-text-secondary)]">{t('pdfReconciliation.validationComplete')}</span>
              </div>
            </div>
          )}
        </>
      )}

      {!parseResult && !parsing && (
        <EmptyState
          icon={<FileText className="w-8 h-8" />}
          title={t('pdfReconciliation.noFile')}
          description={t('pdfReconciliation.noFileDesc')}
        />
      )}
    </div>
  )
}
