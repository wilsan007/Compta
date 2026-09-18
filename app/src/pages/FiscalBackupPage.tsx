import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable } from '@/components/ui'
import { getFiscalBackups, createFiscalBackup, deleteFiscalBackup } from '@/lib/queries/accounting'
import { useLocale } from '@/hooks/useLocale'
import { Plus, Trash2, Archive, Download } from 'lucide-react'
import type { FiscalBackup } from '@/types'
import { useToast } from '@/lib/toast'
import { confirmSync } from '@/lib/confirm'

export function FiscalBackupPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatDate } = useLocale()
  const [backups, setBackups] = useState<FiscalBackup[]>([])
  const [loading, setLoading] = useState(true)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const data = await getFiscalBackups()
      setBackups(data || [])
    } catch (err: any) { console.error('Failed to load fiscal backups:', err)
    toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError'))
    } finally {
      setLoading(false)
    }
  }, [toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() {
    try {
      await createFiscalBackup({
        fiscal_year_id: null,
        backup_type: 'manual',
        status: 'pending',
        file_url: null,
        file_size: null,
        created_by: null,
      })
      toast('success', tCommon('common.success'), t('fiscalBackup.create'))
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    }
  }

  async function handleDelete(id: string) {
    if (!confirmSync(tCommon('form.confirmDelete'))) return
    try {
      await deleteFiscalBackup(id)
      toast('success', tCommon('common.success'), tCommon('toast.deleted'))
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    }
  }

  const tableHeaders = [t('fiscalBackup.type'), t('fiscalBackup.status'), t('fiscalBackup.date'), t('fiscalBackup.size'), tCommon('table.actions')]

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb') }, { label: t('etats.breadcrumb', 'États') }, { label: t('fiscalBackup.breadcrumb') }]} />
      <PageHeader
        title={t('fiscalBackup.title')}
        subtitle={t('fiscalBackup.subtitle')}
        action={<Button onClick={handleCreate}><Plus className="w-4 h-4" /> {t('fiscalBackup.create')}</Button>}
      />

      {loading ? (
        <SkeletonTable rows={3} cols={5} />
      ) : backups.length === 0 ? (
        <EmptyState
          icon={<Archive className="w-8 h-8" />}
          title={t('fiscalBackup.noBackups')}
          description={t('fiscalBackup.noBackupsDescription')}
          action={<Button onClick={handleCreate}><Plus className="w-4 h-4" /> {t('fiscalBackup.create')}</Button>}
        />
      ) : (
        <Card>
          <Table headers={tableHeaders}>
            {backups.map((backup) => (
              <TableRow key={backup.id}>
                <TableCell>
                  <Badge variant="neutral">{t(`fiscalBackup.types.${backup.backup_type}`)}</Badge>
                </TableCell>
                <TableCell>
                  <Badge variant={backup.status === 'completed' ? 'success' : backup.status === 'failed' ? 'danger' : 'warning'}>
                    {t(`fiscalBackup.statuses.${backup.status}`)}
                  </Badge>
                </TableCell>
                <TableCell className="text-xs">{formatDate(backup.created_at)}</TableCell>
                <TableCell className="text-xs font-mono">{backup.file_size ? `${(backup.file_size / 1024).toFixed(0)} ${tCommon('common.kb')}` : '—'}</TableCell>
                <TableCell>
                  <div className="flex items-center gap-1">
                    {backup.file_url && (
                      <a href={backup.file_url} target="_blank" rel="noopener noreferrer" className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)]">
                        <Download className="w-4 h-4" />
                      </a>
                    )}
                    <button onClick={() => handleDelete(backup.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" aria-label={tCommon('actions.delete')} title={tCommon('actions.delete')}>
                      <Trash2 className="w-4 h-4" aria-hidden="true" /></button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}
    </div>
  )
}
