import { useRef, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, AutoBreadcrumb } from '@/components/ui'
import { parseSageFile, type SageParseResult } from '@/lib/sageImport'
import { createChartAccount, createJournalEntry } from '@/lib/queries'
import { useToast } from '@/lib/toast'
import { Upload, FileUp, Database, CheckCircle2, AlertTriangle, RotateCcw } from 'lucide-react'

export function SageImportPage() {
  const { t } = useTranslation('features')
  const { toast } = useToast()
  const fileInputRef = useRef<HTMLInputElement>(null)
  const [fileName, setFileName] = useState('')
  const [content, setContent] = useState('')
  const [result, setResult] = useState<SageParseResult | null>(null)
  const [analyzing, setAnalyzing] = useState(false)
  const [importing, setImporting] = useState(false)
  const [imported, setImported] = useState(false)

  function handleFileSelect(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    setFileName(file.name)
    setResult(null)
    setImported(false)
    const reader = new FileReader()
    reader.onload = () => setContent(String(reader.result || ''))
    reader.readAsText(file)
  }

  function handleAnalyze() {
    if (!content) {
      toast('error', t('sageImport.noFile'))
      return
    }
    setAnalyzing(true)
    try {
      const parsed = parseSageFile(content)
      setResult(parsed)
    } finally {
      setAnalyzing(false)
    }
  }

  async function handleImport() {
    if (!result) return
    setImporting(true)
    try {
      for (const acc of result.accounts) {
        try {
          await createChartAccount({
            code: acc.code,
            name: acc.name,
            type: acc.type,
            balance: 0,
            vat_rate: '',
            description: '',
            parent_id: null,
          } as any)
        } catch { /* skip duplicates */ }
      }

      for (const entry of result.entries) {
        const totalDebit = entry.lines.reduce((s, l) => s + l.debit, 0)
        const totalCredit = entry.lines.reduce((s, l) => s + l.credit, 0)
        try {
          await createJournalEntry({
            number: entry.number,
            date: entry.date,
            description: entry.description,
            reference: entry.piece_number,
            status: 'draft',
            total_debit: totalDebit,
            total_credit: totalCredit,
            journal_code: entry.journal_code,
            piece_number: entry.piece_number,
            lines: entry.lines.map((l, i) => ({
              journal_id: '',
              account_code: l.account_code,
              account_name: l.account_name,
              account_general: l.account_code,
              account_tiers: l.account_tiers || null,
              debit: l.debit,
              credit: l.credit,
              description: l.description,
              line_order: i,
              lettrage_code: l.lettrage_code || null,
            })),
          } as any)
        } catch { /* skip errors */ }
      }

      setImported(true)
      toast('success', t('sageImport.importSuccess'), t('sageImport.importSuccessDesc', {
        accounts: result.accounts.length,
        entries: result.entries.length,
      }))
    } catch (err: any) {
      toast('error', t('sageImport.importError'), err.message)
    } finally {
      setImporting(false)
    }
  }

  function handleReset() {
    setFileName('')
    setContent('')
    setResult(null)
    setImported(false)
    if (fileInputRef.current) fileInputRef.current.value = ''
  }

  const totalLines = result?.entries.reduce((s, e) => s + e.lines.length, 0) ?? 0

  return (
    <div className="animate-fade-in">
      <AutoBreadcrumb />
      <PageHeader title={t('sageImport.title')} subtitle={t('sageImport.subtitle')} />

      <Card className="mb-4">
        <div className="p-4">
          <div className="flex items-start gap-3 mb-4 text-sm text-[var(--color-text-secondary)]">
            <Database className="w-5 h-5 text-[var(--color-primary)] flex-shrink-0 mt-0.5" />
            <p>{t('sageImport.intro')}</p>
          </div>

          <input
            ref={fileInputRef}
            type="file"
            accept=".txt,.csv,.fec"
            className="hidden"
            onChange={handleFileSelect}
          />
          <div
            onClick={() => fileInputRef.current?.click()}
            className="border-2 border-dashed border-[var(--color-border)] rounded-lg p-8 text-center cursor-pointer hover:border-[var(--color-primary)] transition-colors"
          >
            <Upload className="w-8 h-8 mx-auto mb-2 text-[var(--color-text-secondary)]" />
            <p className="text-sm text-[var(--color-text-secondary)]">
              {fileName || t('sageImport.dropFile')}
            </p>
          </div>

          <div className="flex gap-3 mt-4 flex-wrap">
            <Button onClick={handleAnalyze} disabled={!content || analyzing}>
              <FileUp className="w-4 h-4" /> {analyzing ? t('sageImport.analyzing') : t('sageImport.analyze')}
            </Button>
            {result && result.detectedFormat === 'fec' && !imported && (
              <Button variant="primary" onClick={handleImport} disabled={importing}>
                <Database className="w-4 h-4" /> {importing ? t('sageImport.importing') : t('sageImport.import')}
              </Button>
            )}
            {(result || fileName) && (
              <Button variant="secondary" onClick={handleReset}>
                <RotateCcw className="w-4 h-4" /> {t('sageImport.reset')}
              </Button>
            )}
          </div>
        </div>
      </Card>

      {result && result.detectedFormat === 'unknown' && (
        <div className="p-3 rounded-lg bg-[var(--color-danger)]/10 border border-[var(--color-danger)]/30 text-sm text-[var(--color-danger)] flex items-center gap-2">
          <AlertTriangle className="w-4 h-4" /> {t('sageImport.unrecognized')}
        </div>
      )}

      {imported && (
        <div className="p-3 rounded-lg bg-[var(--color-success)]/10 border border-[var(--color-success)]/30 text-sm text-[var(--color-success)] flex items-center gap-2 mb-4">
          <CheckCircle2 className="w-4 h-4" /> {t('sageImport.importSuccess')}
        </div>
      )}

      {result && result.detectedFormat === 'fec' && (
        <div className="space-y-4">
          <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('sageImport.format')}</p>
              <p className="text-lg font-bold uppercase">{result.detectedFormat}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('sageImport.delimiter')}</p>
              <p className="text-lg font-bold">{result.detectedDelimiter}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('sageImport.accountsFound')}</p>
              <p className="text-lg font-bold">{result.accounts.length}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('sageImport.entriesFound')}</p>
              <p className="text-lg font-bold">{result.entries.length}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('sageImport.linesFound')}</p>
              <p className="text-lg font-bold">{totalLines}</p>
            </div>
          </div>

          {result.errors.length > 0 && (
            <Card>
              <div className="p-4">
                <h3 className="text-sm font-semibold mb-2 flex items-center gap-2 text-[var(--color-warning)]">
                  <AlertTriangle className="w-4 h-4" /> {t('sageImport.parseErrors', { count: result.errors.length })}
                </h3>
                <div className="max-h-40 overflow-y-auto text-sm">
                  {result.errors.slice(0, 30).map((err, i) => (
                    <div key={i} className="py-1 border-b border-[var(--color-border)] last:border-0">{err}</div>
                  ))}
                </div>
              </div>
            </Card>
          )}

          <Card>
            <div className="p-4">
              <h3 className="text-sm font-semibold mb-3">{t('sageImport.preview')} — {t('sageImport.importAccounts')}</h3>
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-[var(--color-border)]">
                      <th className="text-left p-2 text-[var(--color-text-secondary)] font-medium">{t('sageImport.code')}</th>
                      <th className="text-left p-2 text-[var(--color-text-secondary)] font-medium">{t('sageImport.name')}</th>
                      <th className="text-left p-2 text-[var(--color-text-secondary)] font-medium">{t('sageImport.type')}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {result.accounts.slice(0, 15).map((acc) => (
                      <tr key={acc.code} className="border-b border-[var(--color-border)] last:border-0">
                        <td className="p-2 font-mono">{acc.code}</td>
                        <td className="p-2">{acc.name}</td>
                        <td className="p-2">{acc.type}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          </Card>

          <Card>
            <div className="p-4">
              <h3 className="text-sm font-semibold mb-3">{t('sageImport.preview')} — {t('sageImport.importEntries')}</h3>
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-[var(--color-border)]">
                      <th className="text-left p-2 text-[var(--color-text-secondary)] font-medium">{t('sageImport.journal')}</th>
                      <th className="text-left p-2 text-[var(--color-text-secondary)] font-medium">{t('sageImport.number')}</th>
                      <th className="text-left p-2 text-[var(--color-text-secondary)] font-medium">{t('sageImport.date')}</th>
                      <th className="text-right p-2 text-[var(--color-text-secondary)] font-medium">{t('sageImport.debit')}</th>
                      <th className="text-right p-2 text-[var(--color-text-secondary)] font-medium">{t('sageImport.credit')}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {result.entries.slice(0, 15).map((e, i) => {
                      const d = e.lines.reduce((s, l) => s + l.debit, 0)
                      const c = e.lines.reduce((s, l) => s + l.credit, 0)
                      return (
                        <tr key={i} className="border-b border-[var(--color-border)] last:border-0">
                          <td className="p-2 font-mono">{e.journal_code}</td>
                          <td className="p-2">{e.number}</td>
                          <td className="p-2">{e.date}</td>
                          <td className="p-2 text-right font-mono">{d.toFixed(2)}</td>
                          <td className="p-2 text-right font-mono">{c.toFixed(2)}</td>
                        </tr>
                      )
                    })}
                  </tbody>
                </table>
              </div>
            </div>
          </Card>
        </div>
      )}
    </div>
  )
}
