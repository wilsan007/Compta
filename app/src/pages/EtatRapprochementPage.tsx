import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { formatCurrency } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import { getBankAccounts, getChartAccounts, generateEtatRapprochement, getEtatsRapprochement } from '@/lib/queries'
import { Scale, Search } from 'lucide-react'
import type { BankAccount, ChartAccount, EtatRapprochement } from '@/types'

export function EtatRapprochementPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [bankAccounts, setBankAccounts] = useState<BankAccount[]>([])
  const [accounts, setAccounts] = useState<ChartAccount[]>([])
  const [records, setRecords] = useState<EtatRapprochement[]>([])
  const [loading, setLoading] = useState(true)
  const [generating, setGenerating] = useState(false)

  const [accountCode, setAccountCode] = useState('')
  const [bankAccountId, setBankAccountId] = useState('')
  const [periodStart, setPeriodStart] = useState('')
  const [periodEnd, setPeriodEnd] = useState('')

  const load = useCallback(async () => {
    try {
      setLoading(true)
      const [banks, accs, recs] = await Promise.all([
        getBankAccounts(),
        getChartAccounts(),
        getEtatsRapprochement(),
      ])
      setBankAccounts(banks || [])
      setAccounts(accs || [])
      setRecords(recs || [])
    } catch (err) {
      console.error('Error loading:', err)
      toast('error', t('etatRapprochement.title'), t('etatRapprochement.loadError'))
    } finally {
      setLoading(false)
    }
  }, [toast, t])

  useEffect(() => { load() }, [load])

  async function handleGenerate() {
    if (!accountCode || !periodStart || !periodEnd) {
      toast('warning', t('etatRapprochement.title'), t('etatRapprochement.fillFields'))
      return
    }
    setGenerating(true)
    try {
      await generateEtatRapprochement(accountCode, bankAccountId || null, periodStart, periodEnd)
      toast('success', t('etatRapprochement.title'), t('etatRapprochement.generateSuccess'))
      await load()
    } catch (err) {
      console.error('Error generating:', err)
      toast('error', t('etatRapprochement.title'), t('etatRapprochement.generateError'))
    } finally {
      setGenerating(false)
    }
  }

  if (loading) {
    return (
      <div>
        <Breadcrumb items={[{ label: t('title') }, { label: t('home.states') }, { label: t('etatRapprochement.title') }]} />
        <PageHeader title={t('etatRapprochement.title')} subtitle={t('etatRapprochement.subtitle')} />
        <SkeletonTable rows={6} cols={7} />
      </div>
    )
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('home.states') }, { label: t('etatRapprochement.title') }]} />
      <PageHeader title={t('etatRapprochement.title')} subtitle={t('etatRapprochement.subtitle')} />

      <Card className="mb-4">
        <div className="p-4 grid grid-cols-5 gap-4">
          <Select
            label={t('etatRapprochement.account')}
            value={accountCode}
            onChange={(e) => setAccountCode(e.target.value)}
            options={[{ value: '', label: '—' }, ...accounts.map((a) => ({ value: a.code, label: `${a.code} — ${a.name}` }))]}
          />
          <Select
            label={t('etatRapprochement.bankAccount')}
            value={bankAccountId}
            onChange={(e) => setBankAccountId(e.target.value)}
            options={[{ value: '', label: '—' }, ...bankAccounts.map((b) => ({ value: b.id, label: b.name || b.bank_name || b.id }))]}
          />
          <Input label={t('etatRapprochement.periodStart')} type="date" value={periodStart} onChange={(e) => setPeriodStart(e.target.value)} />
          <Input label={t('etatRapprochement.periodEnd')} type="date" value={periodEnd} onChange={(e) => setPeriodEnd(e.target.value)} />
          <div className="flex items-end">
            <Button onClick={handleGenerate} disabled={generating || !accountCode}>
              <Search className="w-4 h-4" /> {generating ? tCommon('common.loading') : t('etatRapprochement.generate')}
            </Button>
          </div>
        </div>
      </Card>

      {records.length === 0 ? (
        <EmptyState icon={<Scale className="w-8 h-8" />} title={t('etatRapprochement.empty')} description={t('etatRapprochement.emptyDesc')} />
      ) : (
        <Card>
          <Table headers={[
            t('etatRapprochement.account'),
            t('etatRapprochement.periodStart'),
            t('etatRapprochement.periodEnd'),
            t('etatRapprochement.bankBalance'),
            t('etatRapprochement.bookBalance'),
            t('etatRapprochement.difference'),
            t('etatRapprochement.generatedAt'),
          ]}>
            {records.map((rec) => (
              <TableRow key={rec.id}>
                <TableCell className="font-mono font-semibold">{rec.account_code}</TableCell>
                <TableCell className="text-xs">{rec.period_start}</TableCell>
                <TableCell className="text-xs">{rec.period_end}</TableCell>
                <TableCell className="font-mono text-right">{formatCurrency(rec.bank_balance)}</TableCell>
                <TableCell className="font-mono text-right">{formatCurrency(rec.book_balance)}</TableCell>
                <TableCell className="font-mono text-right font-semibold">
                  <span className={Math.abs(rec.difference) < 0.01 ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}>
                    {formatCurrency(rec.difference)}
                  </span>
                </TableCell>
                <TableCell className="text-xs">{new Date(rec.generated_at).toLocaleDateString()}</TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}
    </div>
  )
}
