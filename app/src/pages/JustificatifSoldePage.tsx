import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Select } from '@/components/ui'
import { formatCurrency } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import { getChartAccounts, getThirdPartyAccounts, getFiscalPeriods, generateJustificatifSolde, getJustificatifsSolde } from '@/lib/queries'
import { FileText, Search } from 'lucide-react'
import type { ChartAccount, ThirdPartyAccount, FiscalPeriod, JustificatifSolde } from '@/types'

export function JustificatifSoldePage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [accounts, setAccounts] = useState<ChartAccount[]>([])
  const [thirdParties, setThirdParties] = useState<ThirdPartyAccount[]>([])
  const [periods, setPeriods] = useState<FiscalPeriod[]>([])
  const [records, setRecords] = useState<JustificatifSolde[]>([])
  const [loading, setLoading] = useState(true)
  const [generating, setGenerating] = useState(false)

  const [accountCode, setAccountCode] = useState('')
  const [thirdPartyCode, setThirdPartyCode] = useState('')
  const [periodId, setPeriodId] = useState('')

  const load = useCallback(async () => {
    try {
      setLoading(true)
      const [accs, tp, fps, recs] = await Promise.all([
        getChartAccounts(),
        getThirdPartyAccounts(),
        getFiscalPeriods(),
        getJustificatifsSolde(),
      ])
      setAccounts(accs || [])
      setThirdParties(tp || [])
      setPeriods(fps || [])
      setRecords(recs || [])
    } catch (err) {
      console.error('Error loading:', err)
      toast('error', t('justificatifSolde.title'), t('justificatifSolde.loadError'))
    } finally {
      setLoading(false)
    }
  }, [toast, t])

  useEffect(() => { load() }, [load])

  async function handleGenerate() {
    if (!accountCode) {
      toast('warning', t('justificatifSolde.title'), t('justificatifSolde.selectAccount'))
      return
    }
    setGenerating(true)
    try {
      await generateJustificatifSolde(accountCode, thirdPartyCode || null, periodId || null)
      toast('success', t('justificatifSolde.title'), t('justificatifSolde.generateSuccess'))
      await load()
    } catch (err) {
      console.error('Error generating:', err)
      toast('error', t('justificatifSolde.title'), t('justificatifSolde.generateError'))
    } finally {
      setGenerating(false)
    }
  }

  if (loading) {
    return (
      <div>
        <Breadcrumb items={[{ label: t('title') }, { label: t('home.states') }, { label: t('justificatifSolde.title') }]} />
        <PageHeader title={t('justificatifSolde.title')} subtitle={t('justificatifSolde.subtitle')} />
        <SkeletonTable rows={6} cols={6} />
      </div>
    )
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('home.states') }, { label: t('justificatifSolde.title') }]} />
      <PageHeader title={t('justificatifSolde.title')} subtitle={t('justificatifSolde.subtitle')} />

      <Card className="mb-4">
        <div className="p-4 grid grid-cols-4 gap-4">
          <Select
            label={t('justificatifSolde.account')}
            value={accountCode}
            onChange={(e) => setAccountCode(e.target.value)}
            options={[{ value: '', label: '—' }, ...accounts.map((a) => ({ value: a.code, label: `${a.code} — ${a.name}` }))]}
          />
          <Select
            label={t('justificatifSolde.thirdParty')}
            value={thirdPartyCode}
            onChange={(e) => setThirdPartyCode(e.target.value)}
            options={[{ value: '', label: '—' }, ...thirdParties.map((tp) => ({ value: tp.code, label: `${tp.code} — ${tp.name}` }))]}
          />
          <Select
            label={t('justificatifSolde.period')}
            value={periodId}
            onChange={(e) => setPeriodId(e.target.value)}
            options={[{ value: '', label: '—' }, ...periods.map((p) => ({ value: p.id, label: p.period_label }))]}
          />
          <div className="flex items-end">
            <Button onClick={handleGenerate} disabled={generating || !accountCode}>
              <Search className="w-4 h-4" /> {generating ? tCommon('common.loading') : t('justificatifSolde.generate')}
            </Button>
          </div>
        </div>
      </Card>

      {records.length === 0 ? (
        <EmptyState icon={<FileText className="w-8 h-8" />} title={t('justificatifSolde.empty')} description={t('justificatifSolde.emptyDesc')} />
      ) : (
        <Card>
          <Table headers={[
            t('justificatifSolde.account'),
            t('justificatifSolde.thirdParty'),
            t('justificatifSolde.openingBalance'),
            t('justificatifSolde.totalDebit'),
            t('justificatifSolde.totalCredit'),
            t('justificatifSolde.closingBalance'),
            t('justificatifSolde.generatedAt'),
          ]}>
            {records.map((rec) => (
              <TableRow key={rec.id}>
                <TableCell className="font-mono font-semibold">{rec.account_code}</TableCell>
                <TableCell className="text-xs">{rec.third_party_code || '—'}</TableCell>
                <TableCell className="font-mono text-right">{formatCurrency(rec.opening_balance)}</TableCell>
                <TableCell className="font-mono text-right text-[var(--color-success)]">{formatCurrency(rec.total_debit)}</TableCell>
                <TableCell className="font-mono text-right text-[var(--color-danger)]">{formatCurrency(rec.total_credit)}</TableCell>
                <TableCell className="font-mono text-right font-semibold">{formatCurrency(rec.closing_balance)}</TableCell>
                <TableCell className="text-xs">{new Date(rec.generated_at).toLocaleDateString()}</TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}
    </div>
  )
}
