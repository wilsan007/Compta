import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, EmptyState, Breadcrumb, SkeletonTable, Select } from '@/components/ui'
import { getFiscalYears, getFECExport } from '@/lib/queries/accounting'
import { validateFECData, generateFECFileName, generateFECText, downloadFEC, type FECExport, type FECValidationResult } from '@/lib/fecValidator'
import { useToast } from '@/lib/toast'
import { Download, FileText, ShieldCheck, AlertTriangle, CheckCircle2, XCircle } from 'lucide-react'
import type { FiscalYear } from '@/types'
import { errorMessage } from '@/lib/utils'

export function FECExportPage() {
  const { t } = useTranslation('features')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [years, setYears] = useState<FiscalYear[]>([])
  const [selectedYear, setSelectedYear] = useState('')
  const [loading, setLoading] = useState(false)
  const [fec, setFec] = useState<FECExport | null>(null)
  const [validation, setValidation] = useState<FECValidationResult | null>(null)

  // oxlint-disable-next-line react-hooks/exhaustive-deps -- chargement volontairement limite aux valeurs listees
  useEffect(() => { loadYears() }, [])

  async function loadYears() {
    try {
      setYears((await getFiscalYears()) || [])
    } catch (err) {
      console.error('Error loading fiscal years:', err)
      toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.loadingError'))
    }
  }

  async function loadFEC() {
    if (!selectedYear) return
    setLoading(true)
    setValidation(null)
    try {
      const data = await getFECExport(selectedYear)
      setFec(data)
      setValidation(validateFECData(data))
    } catch (err) {
      console.error('Error loading FEC data:', err)
      toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.loadingError'))
    } finally {
      setLoading(false)
    }
  }

  // M1 : export refusé tant que le contrôle rend une erreur (majeure comprise) ;
  // nom réglementaire {SIREN}FEC{date de clôture}.txt
  function handleExport() {
    if (!fec || !validation?.isValid) return
    const year = years.find((y) => y.id === selectedYear)
    try {
      const filename = generateFECFileName(fec.siren || '', year?.end_date || '')
      downloadFEC(generateFECText(fec.rows), filename)
      toast('success', t('fec.exported'), t('fec.exportedDesc', { filename }))
    } catch (err) {
      toast('error', tCommon('toast.error'), errorMessage(err))
    }
  }

  const rowCount = fec?.rows.length ?? 0

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
          {rowCount > 0 && validation?.isValid && (
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
      ) : rowCount === 0 ? (
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
                <h3 className="text-sm font-semibold mb-2 flex items-center gap-2 text-[var(--color-warning-text)]">
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
                {fec ? generateFECText(fec.rows.slice(0, 5)) : ''}
              </pre>
            </div>
          </Card>
        </div>
      )}
    </div>
  )
}
