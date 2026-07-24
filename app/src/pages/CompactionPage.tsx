import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Select } from '@/components/ui'
import { formatDate } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import { getCompactionLogs, createCompactionLog, updateCompactionLog, getFiscalYears } from '@/lib/queries'
import { Archive } from 'lucide-react'
import type { CompactionLog, FiscalYear } from '@/types'

export function CompactionPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [logs, setLogs] = useState<CompactionLog[]>([])
  const [fiscalYears, setFiscalYears] = useState<FiscalYear[]>([])
  const [loading, setLoading] = useState(true)
  const [compacting, setCompacting] = useState(false)
  const [selectedFY, setSelectedFY] = useState('')

  const load = useCallback(async () => {
    try {
      setLoading(true)
      const [recs, fys] = await Promise.all([getCompactionLogs(), getFiscalYears()])
      setLogs(recs || [])
      setFiscalYears(fys || [])
    } catch (err) {
      console.error('Error loading:', err)
      toast('error', t('compaction.title'), t('compaction.loadError'))
    } finally {
      setLoading(false)
    }
  }, [toast, t])

  useEffect(() => { load() }, [load])

  async function handleCompact() {
    if (!selectedFY) {
      toast('warning', t('compaction.title'), t('compaction.selectFY'))
      return
    }
    setCompacting(true)
    try {
      const log = await createCompactionLog({
        fiscal_year_id: selectedFY,
        entries_compacted: 0,
        lines_compacted: 0,
        status: 'in_progress',
        compacted_by: null,
        details: {},
      } as any)
      await updateCompactionLog(log.id, { status: 'completed' })
      toast('success', t('compaction.title'), t('compaction.compactSuccess'))
      setSelectedFY('')
      await load()
    } catch (err: any) {
      toast('error', t('compaction.title'), err.message || t('compaction.compactError'))
    } finally {
      setCompacting(false)
    }
  }

  if (loading) {
    return (
      <div>
        <Breadcrumb items={[{ label: t('title') }, { label: t('home.structure') }, { label: t('compaction.title') }]} />
        <PageHeader title={t('compaction.title')} subtitle={t('compaction.subtitle')} />
        <SkeletonTable rows={6} cols={5} />
      </div>
    )
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('home.structure') }, { label: t('compaction.title') }]} />
      <PageHeader title={t('compaction.title')} subtitle={t('compaction.subtitle')} />

      <Card className="mb-4">
        <div className="p-4 grid grid-cols-3 gap-4 items-end">
          <Select
            label={t('compaction.fiscalYear')}
            value={selectedFY}
            onChange={(e) => setSelectedFY(e.target.value)}
            options={[{ value: '', label: '—' }, ...fiscalYears.map((fy) => ({ value: fy.id, label: fy.code || fy.id }))]}
          />
          <div className="col-span-2 flex justify-end">
            <Button onClick={handleCompact} disabled={compacting || !selectedFY}>
              <Archive className="w-4 h-4" /> {compacting ? tCommon('common.loading') : t('compaction.compact')}
            </Button>
          </div>
        </div>
      </Card>

      {logs.length === 0 ? (
        <EmptyState icon={<Archive className="w-8 h-8" />} title={t('compaction.empty')} description={t('compaction.emptyDesc')} />
      ) : (
        <Card>
          <Table headers={[
            t('compaction.fiscalYear'),
            t('compaction.entriesCompacted'),
            t('compaction.linesCompacted'),
            t('compaction.status'),
            t('compaction.compactedAt'),
          ]}>
            {logs.map((log) => (
              <TableRow key={log.id}>
                <TableCell className="font-mono text-xs">{log.fiscal_year_id?.slice(0, 8) || '—'}</TableCell>
                <TableCell className="font-mono text-right">{log.entries_compacted}</TableCell>
                <TableCell className="font-mono text-right">{log.lines_compacted}</TableCell>
                <TableCell>
                  <Badge variant={log.status === 'completed' ? 'success' : log.status === 'failed' ? 'danger' : 'warning'}>
                    {t(`compaction.statuses.${log.status}`)}
                  </Badge>
                </TableCell>
                <TableCell className="text-xs">{formatDate(log.compacted_at)}</TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}
    </div>
  )
}
