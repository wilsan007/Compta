import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Select } from '@/components/ui'
import { formatDate } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import { getChartAccounts } from '@/lib/queries/accounting'
import { getFusionLogs, fuseAccounts } from '@/lib/queries/misc'
import { GitMerge, ArrowRight } from 'lucide-react'
import type { ChartAccount, FusionLog } from '@/types'

export function FusionComptesPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [accounts, setAccounts] = useState<ChartAccount[]>([])
  const [logs, setLogs] = useState<FusionLog[]>([])
  const [loading, setLoading] = useState(true)
  const [fusing, setFusing] = useState(false)
  const [sourceCode, setSourceCode] = useState('')
  const [targetCode, setTargetCode] = useState('')

  const load = useCallback(async () => {
    try {
      setLoading(true)
      const [accs, recs] = await Promise.all([getChartAccounts(), getFusionLogs()])
      setAccounts(accs || [])
      setLogs(recs || [])
    } catch (err) {
      console.error('Error loading:', err)
      toast('error', t('fusionComptes.title'), t('fusionComptes.loadError'))
    } finally {
      setLoading(false)
    }
  }, [toast, t])

  useEffect(() => { load() }, [load])

  async function handleFuse() {
    if (!sourceCode || !targetCode) {
      toast('warning', t('fusionComptes.title'), t('fusionComptes.selectBoth'))
      return
    }
    if (sourceCode === targetCode) {
      toast('warning', t('fusionComptes.title'), t('fusionComptes.sameAccount'))
      return
    }
    if (!confirm(t('fusionComptes.confirm', { source: sourceCode, target: targetCode }))) return
    setFusing(true)
    try {
      const log = await fuseAccounts(sourceCode, targetCode)
      toast('success', t('fusionComptes.title'), t('fusionComptes.fuseSuccess', { count: log.lines_moved }))
      setSourceCode('')
      setTargetCode('')
      await load()
    } catch (err: any) {
      toast('error', t('fusionComptes.title'), err.message || t('fusionComptes.fuseError'))
    } finally {
      setFusing(false)
    }
  }

  if (loading) {
    return (
      <div>
        <Breadcrumb items={[{ label: t('title') }, { label: t('home.structure') }, { label: t('fusionComptes.title') }]} />
        <PageHeader title={t('fusionComptes.title')} subtitle={t('fusionComptes.subtitle')} />
        <SkeletonTable rows={6} cols={5} />
      </div>
    )
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('home.structure') }, { label: t('fusionComptes.title') }]} />
      <PageHeader title={t('fusionComptes.title')} subtitle={t('fusionComptes.subtitle')} />

      <Card className="mb-4">
        <div className="p-4">
          <h3 className="text-sm font-semibold mb-3 flex items-center gap-2">
            <GitMerge className="w-4 h-4" /> {t('fusionComptes.newFusion')}
          </h3>
          <div className="grid grid-cols-3 gap-4 items-end">
            <Select
              label={t('fusionComptes.sourceAccount')}
              value={sourceCode}
              onChange={(e) => setSourceCode(e.target.value)}
              options={[{ value: '', label: '—' }, ...accounts.map((a) => ({ value: a.code, label: `${a.code} — ${a.name}` }))]}
            />
            <div className="flex items-end justify-center pb-2">
              <ArrowRight className="w-5 h-5 text-[var(--color-text-secondary)]" />
            </div>
            <Select
              label={t('fusionComptes.targetAccount')}
              value={targetCode}
              onChange={(e) => setTargetCode(e.target.value)}
              options={[{ value: '', label: '—' }, ...accounts.map((a) => ({ value: a.code, label: `${a.code} — ${a.name}` }))]}
            />
          </div>
          <div className="flex justify-end mt-4">
            <Button onClick={handleFuse} disabled={fusing || !sourceCode || !targetCode}>
              <GitMerge className="w-4 h-4" /> {fusing ? tCommon('common.loading') : t('fusionComptes.fuse')}
            </Button>
          </div>
        </div>
      </Card>

      {logs.length === 0 ? (
        <EmptyState icon={<GitMerge className="w-8 h-8" />} title={t('fusionComptes.empty')} description={t('fusionComptes.emptyDesc')} />
      ) : (
        <Card>
          <Table headers={[
            t('fusionComptes.sourceAccount'),
            t('fusionComptes.targetAccount'),
            t('fusionComptes.linesMoved'),
            t('fusionComptes.fusedAt'),
          ]}>
            {logs.map((log) => (
              <TableRow key={log.id}>
                <TableCell className="font-mono font-semibold">{log.source_account_code}</TableCell>
                <TableCell className="font-mono font-semibold">{log.target_account_code}</TableCell>
                <TableCell className="font-mono text-right">{log.lines_moved}</TableCell>
                <TableCell className="text-xs">{formatDate(log.fused_at)}</TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}
    </div>
  )
}
