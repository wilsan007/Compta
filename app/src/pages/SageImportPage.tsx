import { useRef, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, AutoBreadcrumb } from '@/components/ui'
import { parseSageFile, type SageParseResult } from '@/lib/sageImport'
import { parseMaeFile, type MaeParseResult } from '@/lib/maeParser'
import { createChartAccount, createJournalEntry, createThirdPartyAccount, updateChartAccount, getChartAccounts, getThirdPartyAccounts } from '@/lib/queries'
import { useToast } from '@/lib/toast'
import { Upload, FileUp, Database, CheckCircle2, AlertTriangle, RotateCcw } from 'lucide-react'

type UnifiedResult = SageParseResult | MaeParseResult

export function SageImportPage() {
  const { t } = useTranslation('features')
  const { toast } = useToast()
  const fileInputRef = useRef<HTMLInputElement>(null)
  const [fileName, setFileName] = useState('')
  const [content, setContent] = useState('')
  const [binaryData, setBinaryData] = useState<ArrayBuffer | null>(null)
  const [result, setResult] = useState<UnifiedResult | null>(null)
  const [analyzing, setAnalyzing] = useState(false)
  const [importing, setImporting] = useState(false)
  const [imported, setImported] = useState(false)

  function handleFileSelect(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    setFileName(file.name)
    setResult(null)
    setImported(false)
    setContent('')
    setBinaryData(null)

    const isMae = file.name.toLowerCase().endsWith('.mae')
    const reader = new FileReader()
    if (isMae) {
      reader.onload = () => setBinaryData(reader.result as ArrayBuffer)
      reader.readAsArrayBuffer(file)
    } else {
      reader.onload = () => setContent(String(reader.result || ''))
      reader.readAsText(file)
    }
  }

  function handleAnalyze() {
    if (!content && !binaryData) {
      toast('error', t('sageImport.noFile'))
      return
    }
    setAnalyzing(true)
    try {
      if (binaryData) {
        const parsed = parseMaeFile(binaryData)
        setResult(parsed)
      } else {
        const parsed = parseSageFile(content)
        setResult(parsed)
      }
    } finally {
      setAnalyzing(false)
    }
  }

  async function handleImport() {
    if (!result) return
    setImporting(true)
    const importErrors: string[] = []
    try {
      let accountsCreated = 0
      let accountsSkipped = 0
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
          accountsCreated++
        } catch (err: any) {
          accountsSkipped++
          console.error(`[Import] Account ${acc.code} failed:`, err?.message || err)
          importErrors.push(`Compte ${acc.code}: ${err?.message || 'erreur'}`)
        }
      }
      console.log(`[Import] Accounts: ${accountsCreated} created, ${accountsSkipped} skipped`)

      let entriesCreated = 0
      let entriesSkipped = 0
      let tiersCreated = 0
      if ('detectedFormat' in result) {
        // FEC format — entries have lines array

        // Collect unique third-party accounts from FEC lines
        const tiersMap = new Map<string, { code: string; name: string; generalCode: string; type: 'customer' | 'supplier' | 'employee' | 'other' }>()
        for (const entry of result.entries) {
          for (const line of entry.lines) {
            if (line.account_tiers) {
              const tiersCode = line.account_tiers
              if (!tiersMap.has(tiersCode)) {
                const generalCode = line.account_code
                let tierType: 'customer' | 'supplier' | 'employee' | 'other' = 'other'
                if (generalCode.startsWith('401') || tiersCode.startsWith('401')) tierType = 'supplier'
                else if (generalCode.startsWith('411') || tiersCode.startsWith('411')) tierType = 'customer'
                else if (generalCode.startsWith('421') || tiersCode.startsWith('421')) tierType = 'employee'
                tiersMap.set(tiersCode, {
                  code: tiersCode,
                  name: line.account_tiers_name || tiersCode,
                  generalCode,
                  type: tierType,
                })
              }
            }
          }
        }

        // Create third-party accounts
        const existingTiers = await getThirdPartyAccounts().catch(() => [])
        const existingTiersCodes = new Set((existingTiers || []).map((t) => t.code))
        for (const [, tier] of tiersMap) {
          if (existingTiersCodes.has(tier.code)) continue
          try {
            await createThirdPartyAccount({
              code: tier.code,
              name: tier.name,
              type: tier.type,
              account_general_code: tier.generalCode,
              customer_id: null,
              supplier_id: null,
              employee_id: null,
              balance: 0,
              lettrage_code: null,
              currency: 'EUR',
              active: true,
            } as any)
            tiersCreated++
          } catch (err: any) {
            console.error(`[Import] Third party ${tier.code} failed:`, err?.message || err)
            importErrors.push(`Tiers ${tier.code}: ${err?.message || 'erreur'}`)
          }
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
            entriesCreated++
          } catch (err: any) {
            entriesSkipped++
            console.error(`[Import] Entry ${entry.journal_code}#${entry.number} failed:`, err?.message || err)
            importErrors.push(`Écriture ${entry.journal_code}#${entry.number}: ${err?.message || 'erreur'}`)
          }
        }

        // Calculate and update chart account balances from all journal lines
        const balanceMap = new Map<string, number>()
        for (const entry of result.entries) {
          for (const line of entry.lines) {
            const code = line.account_code
            const current = balanceMap.get(code) || 0
            balanceMap.set(code, current + line.debit - line.credit)
          }
        }
        const existingAccounts = await getChartAccounts().catch(() => [])
        const accountByCode = new Map((existingAccounts || []).map((a) => [a.code, a]))
        for (const [code, balance] of balanceMap) {
          const acc = accountByCode.get(code)
          if (acc) {
            try {
              await updateChartAccount(acc.id, { balance } as any)
            } catch (err: any) {
              console.error(`[Import] Balance update for ${code} failed:`, err?.message || err)
            }
          }
        }
      } else {
        // MAE format — flat entries, group by journal+number
        const grouped = new Map<string, { entry: typeof result.entries[0]; debit: number; credit: number }>()
        for (const e of result.entries) {
          const key = `${e.journal_code}#${e.number}`
          const existing = grouped.get(key)
          if (existing) {
            existing.debit += e.debit
            existing.credit += e.credit
          } else {
            grouped.set(key, { entry: e, debit: e.debit, credit: e.credit })
          }
        }
        for (const [, { entry, debit, credit }] of grouped) {
          try {
            await createJournalEntry({
              number: entry.number,
              date: entry.date,
              description: entry.description,
              reference: entry.piece_number,
              status: 'draft',
              total_debit: debit,
              total_credit: credit,
              journal_code: entry.journal_code,
              piece_number: entry.piece_number,
              lines: [{
                journal_id: '',
                account_code: entry.account_code,
                account_name: '',
                account_general: entry.account_code,
                account_tiers: null,
                debit: entry.debit,
                credit: entry.credit,
                description: entry.description,
                line_order: 0,
                lettrage_code: null,
              }],
            } as any)
            entriesCreated++
          } catch (err: any) {
            entriesSkipped++
            console.error(`[Import] MAE entry ${entry.journal_code}#${entry.number} failed:`, err?.message || err)
            importErrors.push(`Écriture ${entry.journal_code}#${entry.number}: ${err?.message || 'erreur'}`)
          }
        }
      }
      console.log(`[Import] Entries: ${entriesCreated} created, ${entriesSkipped} skipped`)

      if (importErrors.length > 0) {
        toast('error', 'Erreurs d\'import', `${importErrors.length} erreur(s) — voir console (F12). ${accountsCreated} comptes, ${tiersCreated} tiers et ${entriesCreated} écritures importés.`)
      } else {
        toast('success', t('sageImport.importSuccess'), `${accountsCreated} comptes, ${tiersCreated} comptes tiers, ${entriesCreated} écritures importés.`)
      }

      setImported(true)
    } catch (err: any) {
      toast('error', t('sageImport.importError'), err.message)
    } finally {
      setImporting(false)
    }
  }

  function handleReset() {
    setFileName('')
    setContent('')
    setBinaryData(null)
    setResult(null)
    setImported(false)
    if (fileInputRef.current) fileInputRef.current.value = ''
  }

  const isFec = result && 'detectedFormat' in result
  const isMae = result && !('detectedFormat' in result)
  const totalLines = isFec
    ? (result as SageParseResult).entries.reduce((s, e) => s + e.lines.length, 0)
    : result?.entries.length ?? 0

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
            accept=".txt,.csv,.fec,.mae"
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
            <Button onClick={handleAnalyze} disabled={(!content && !binaryData) || analyzing}>
              <FileUp className="w-4 h-4" /> {analyzing ? t('sageImport.analyzing') : t('sageImport.analyze')}
            </Button>
            {result && (isFec || isMae) && !imported && (
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

      {result && isFec && (result as SageParseResult).detectedFormat === 'unknown' && (
        <div className="p-3 rounded-lg bg-[var(--color-danger)]/10 border border-[var(--color-danger)]/30 text-sm text-[var(--color-danger)] flex items-center gap-2">
          <AlertTriangle className="w-4 h-4" /> {t('sageImport.unrecognized')}
        </div>
      )}

      {result && isMae && (result as MaeParseResult).fileType === 'ini' && (
        <Card className="mb-4">
          <div className="p-4 space-y-3">
            <div className="flex items-center gap-2 text-[var(--color-warning)]">
              <AlertTriangle className="w-5 h-5" />
              <h3 className="text-sm font-semibold">{t('sageImport.maeDetected')}</h3>
            </div>
            <p className="text-sm text-[var(--color-text-secondary)]">
              {t('sageImport.maeDescription')}
            </p>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
              <div className="card p-3">
                <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('sageImport.sqlServer')}</p>
                <p className="text-sm font-mono font-bold">{(result as MaeParseResult).connectionInfo?.server || '—'}</p>
              </div>
              <div className="card p-3">
                <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('sageImport.database')}</p>
                <p className="text-sm font-mono font-bold">{(result as MaeParseResult).connectionInfo?.database || '—'}</p>
              </div>
              <div className="card p-3">
                <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('sageImport.creator')}</p>
                <p className="text-sm font-mono font-bold">{(result as MaeParseResult).connectionInfo?.creator || '—'}</p>
              </div>
              <div className="card p-3">
                <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('sageImport.type')}</p>
                <p className="text-sm font-mono font-bold">{(result as MaeParseResult).connectionInfo?.type || '—'}</p>
              </div>
            </div>
            <div className="p-3 rounded-lg bg-[var(--color-info)]/10 border border-[var(--color-info)]/30 text-sm text-[var(--color-text-secondary)]">
              <p className="font-semibold mb-1">{t('sageImport.importInstructions')}</p>
              <ul className="list-disc list-inside space-y-1">
                <li>{t('sageImport.step1')}</li>
                <li>{t('sageImport.step2')}</li>
                <li>{t('sageImport.step3')}</li>
              </ul>
            </div>
          </div>
        </Card>
      )}

      {result && isMae && (result as MaeParseResult).fileType === 'binary' && (result as MaeParseResult).accounts.length === 0 && (result as MaeParseResult).errors.length > 0 && (
        <div className="p-3 rounded-lg bg-[var(--color-danger)]/10 border border-[var(--color-danger)]/30 text-sm text-[var(--color-danger)] flex items-center gap-2">
          <AlertTriangle className="w-4 h-4" /> {t('sageImport.unrecognized')}
        </div>
      )}

      {imported && (
        <div className="p-3 rounded-lg bg-[var(--color-success)]/10 border border-[var(--color-success)]/30 text-sm text-[var(--color-success)] flex items-center gap-2 mb-4">
          <CheckCircle2 className="w-4 h-4" /> {t('sageImport.importSuccess')}
        </div>
      )}

      {result && (isFec || (isMae && (result as MaeParseResult).fileType === 'binary')) && (isMae || (result as SageParseResult).detectedFormat === 'fec') && (
        <div className="space-y-4">
          <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('sageImport.format')}</p>
              <p className="text-lg font-bold uppercase">{isMae ? 'MAE' : (result as SageParseResult).detectedFormat}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{isMae ? 'Version' : t('sageImport.delimiter')}</p>
              <p className="text-lg font-bold">{isMae ? (result as MaeParseResult).detectedVersion : (result as SageParseResult).detectedDelimiter}</p>
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
                      const d = isFec ? (e as any).lines.reduce((s: number, l: any) => s + l.debit, 0) : (e as any).debit
                      const c = isFec ? (e as any).lines.reduce((s: number, l: any) => s + l.credit, 0) : (e as any).credit
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
