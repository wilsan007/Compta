import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, EmptyState, Breadcrumb, SkeletonTable, Select } from '@/components/ui'
import { getFiscalYears, getFECData, getCompanySettings } from '@/lib/queries'
import { validateFECData, generateFECFileName, downloadFEC, type FECValidationResult } from '@/lib/fecValidator'
import { useToast } from '@/lib/toast'
import { Download, FileText, ShieldCheck, AlertTriangle, CheckCircle2, XCircle } from 'lucide-react'
import type { FiscalYear, CompanySettings } from '@/types'

function escapeFECField(value: any): string {
  if (value === null || value === undefined) return ''
  return String(value).replace(/"/g, '""')
}

function generateFECText(entries: any[]): string {
  const lines: string[] = []
  const header = [
    'JournalCode', 'JournalLib', 'EcritureNum', 'EcritureDate', 'CompteNum',
    'CompteLib', 'CompAuxNum', 'CompAuxLib', 'PieceRef', 'PieceDate',
    'EcritureLib', 'Debit', 'Credit', 'EcritureLet', 'DateLet',
    'ValidDate', 'Montantdevise', 'Idevise',
  ]
  lines.push(header.join('|'))

  for (const entry of entries) {
    const je = entry
    for (const line of je.journal_lines || []) {
      const row = [
        escapeFECField(je.journal_code),
        escapeFECField('Journal'),
        escapeFECField(je.number),
        escapeFECField(je.date?.replace(/-/g, '')),
        escapeFECField(line.account_general || line.account_code),
        escapeFECField(line.account_name || ''),
        escapeFECField(line.account_tiers || ''),
        escapeFECField(''),
        escapeFECField(je.piece_number || je.number),
        escapeFECField(je.date?.replace(/-/g, '')),
        escapeFECField(line.description || je.description),
        escapeFECField(Number(line.debit).toFixed(2)),
        escapeFECField(Number(line.credit).toFixed(2)),
        escapeFECField(line.lettrage_code || ''),
        escapeFECField(''),
        escapeFECField(je.date?.replace(/-/g, '')),
        '',
        '',
      ]
      lines.push(row.join('|'))
    }
  }

  return lines.join('\n')
}

export function FECExportPage() {
  const { t } = useTranslation('features')
  const { toast } = useToast()
  const [years, setYears] = useState<FiscalYear[]>([])
  const [company, setCompany] = useState<CompanySettings | null>(null)
  const [selectedYear, setSelectedYear] = useState('')
  const [loading, setLoading] = useState(false)
  const [entries, setEntries] = useState<any[]>([])
  const [validation, setValidation] = useState<FECValidationResult | null>(null)

  useEffect(() => { loadYears() }, [])

  async function loadYears() {
    try {
      const [data, comp] = await Promise.all([
        getFiscalYears(),
        getCompanySettings().catch(() => null),
      ])
      setYears(data || [])
      setCompany(comp)
    } catch (err) {
      console.error('Error loading fiscal years:', err)
    }
  }

  async function loadFEC() {
    if (!selectedYear) return
    setLoading(true)
    setValidation(null)
    try {
      const data = await getFECData(selectedYear)
      setEntries(data || [])
      setValidation(validateFECData(data || []))
    } catch (err) {
      console.error('Error loading FEC data:', err)
    } finally {
      setLoading(false)
    }
  }

  function handleExport() {
    const year = years.find((y) => y.id === selectedYear)
    const fecText = generateFECText(entries)
    const endYear = (year?.end_date || year?.code || '').replace(/-/g, '').substring(0, 8) || 'exercice'
    const filename = generateFECFileName(company?.siret || company?.vat_number || '', endYear)
    downloadFEC(fecText, filename)
    toast('success', t('fec.exported'), t('fec.exportedDesc', { filename }))
  }

  const stats = validation?.stats

  return (
    <div>
      <Breadcrumb items={[{ label: 'Comptabilité' }, { label: 'États' }, { label: t('fec.title') }]} />
      <PageHeader title={t('fec.title')} subtitle={t('fec.subtitle')} />

      <Card className="mb-4">
        <div className="p-4 flex gap-3 items-end flex-wrap">
          <div className="w-56">
            <Select
              label={t('fec.fiscalYear')}
              value={selectedYear}
              onChange={(e) => setSelectedYear(e.target.value)}
              options={[{ value: '', label: t('fec.selectYear') }, ...years.map((y) => ({ value: y.id, label: y.code }))]}
            />
          </div>
          <Button onClick={loadFEC} disabled={loading || !selectedYear}>
            <ShieldCheck className="w-4 h-4" /> {loading ? t('fec.validating') : t('fec.validate')}
          </Button>
          {entries.length > 0 && validation?.isValid && (
            <Button variant="secondary" onClick={handleExport}>
              <Download className="w-4 h-4" /> {t('fec.export')}
            </Button>
          )}
        </div>
      </Card>

      {loading ? (
        <SkeletonTable rows={4} cols={4} />
      ) : years.length === 0 ? (
        <EmptyState
          icon={<FileText className="w-8 h-8" />}
          title={t('fec.noYears')}
          description={t('fec.noYearsDesc')}
        />
      ) : entries.length === 0 ? (
        <EmptyState
          icon={<FileText className="w-8 h-8" />}
          title={t('fec.noData')}
          description={t('fec.subtitle')}
        />
      ) : (
        <div className="space-y-4">
          {validation && (
            <div className={`p-3 rounded-lg border text-sm flex items-center gap-2 ${validation.isValid ? 'bg-[var(--color-success)]/10 border-[var(--color-success)]/30 text-[var(--color-success)]' : 'bg-[var(--color-danger)]/10 border-[var(--color-danger)]/30 text-[var(--color-danger)]'}`}>
              {validation.isValid ? <CheckCircle2 className="w-4 h-4" /> : <XCircle className="w-4 h-4" />}
              {validation.isValid ? t('fec.valid') : t('fec.invalid')}
            </div>
          )}

          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('fec.totalEntries')}</p>
              <p className="text-lg font-bold">{stats?.totalEntries ?? 0}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('fec.totalLines')}</p>
              <p className="text-lg font-bold">{stats?.totalLines ?? 0}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('fec.totalDebit')}</p>
              <p className="text-lg font-bold font-mono">{(stats?.totalDebit ?? 0).toFixed(2)}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('fec.totalCredit')}</p>
              <p className="text-lg font-bold font-mono">{(stats?.totalCredit ?? 0).toFixed(2)}</p>
            </div>
          </div>

          {validation && validation.errors.length > 0 && (
            <Card>
              <div className="p-4">
                <h3 className="text-sm font-semibold mb-2 flex items-center gap-2 text-[var(--color-danger)]">
                  <XCircle className="w-4 h-4" /> {t('fec.errors')} ({validation.errors.length})
                </h3>
                <div className="max-h-56 overflow-y-auto text-sm">
                  {validation.errors.map((err, i) => (
                    <div key={i} className="py-1.5 border-b border-[var(--color-border)] last:border-0 flex gap-2">
                      <span className="font-mono text-xs text-[var(--color-text-secondary)] w-16 flex-shrink-0">{t('fec.line')} {err.line}</span>
                      <span className="font-medium w-28 flex-shrink-0">{err.field}</span>
                      <span>{err.message}</span>
                    </div>
                  ))}
                </div>
              </div>
            </Card>
          )}

          {validation && validation.warnings.length > 0 && (
            <Card>
              <div className="p-4">
                <h3 className="text-sm font-semibold mb-2 flex items-center gap-2 text-[var(--color-warning)]">
                  <AlertTriangle className="w-4 h-4" /> {t('fec.warnings')} ({validation.warnings.length})
                </h3>
                <div className="max-h-40 overflow-y-auto text-sm">
                  {validation.warnings.slice(0, 50).map((w, i) => (
                    <div key={i} className="py-1.5 border-b border-[var(--color-border)] last:border-0 flex gap-2">
                      <span className="font-mono text-xs text-[var(--color-text-secondary)] w-16 flex-shrink-0">{t('fec.line')} {w.line}</span>
                      <span className="font-medium w-28 flex-shrink-0">{w.field}</span>
                      <span>{w.message}</span>
                    </div>
                  ))}
                </div>
              </div>
            </Card>
          )}

          <Card>
            <div className="p-4">
              <h3 className="text-sm font-semibold mb-2">{t('fec.stats')}</h3>
              <pre className="text-xs font-mono overflow-x-auto bg-[var(--color-neutral-50)] p-3 rounded-lg max-h-96">
                {generateFECText(entries.slice(0, 5))}
              </pre>
            </div>
          </Card>
        </div>
      )}
    </div>
  )
}
