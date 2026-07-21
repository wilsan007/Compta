import { useEffect, useState } from 'react'
import { Card, PageHeader, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Select, Input } from '@/components/ui'
import { formatDate } from '@/lib/utils'
import { getAuditLog } from '@/lib/queries'
import { useTranslation } from 'react-i18next'

export function AuditLogPage() {
  const { t } = useTranslation('settings')
  const [logs, setLogs] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [entityFilter, setEntityFilter] = useState('')
  const [actionFilter, setActionFilter] = useState('')
  const [search, setSearch] = useState('')

  useEffect(() => { load() }, [])

  async function load() {
    try {
      const data = await getAuditLog(entityFilter || undefined, actionFilter || undefined)
      setLogs(data || [])
    } catch (err) {
      console.error('Error loading audit log:', err)
    } finally {
      setLoading(false)
    }
  }

  function handleFilterChange() {
    setTimeout(load, 0)
  }

  const filtered = logs.filter(l => {
    if (!search) return true
    const s = search.toLowerCase()
    return (l.description || '').toLowerCase().includes(s) || (l.entity_number || '').toLowerCase().includes(s) || (l.entity_type || '').toLowerCase().includes(s)
  })

  const actionLabels: Record<string, string> = {
    create: t('auditLog.actions.create'), update: t('auditLog.actions.update'), delete: t('auditLog.actions.delete'),
    login: t('auditLog.actions.login'), logout: t('auditLog.actions.logout'), transfer: t('auditLog.actions.transfer'),
    validate: t('auditLog.actions.validate'), close: t('auditLog.actions.close'), export: t('auditLog.actions.export'),
  }

  if (loading) return <SkeletonTable rows={6} />

  return (
    <div>
      <Breadcrumb items={[{ label: t('auditLog.breadcrumb'), path: '/system/audit-log' }, { label: t('auditLog.breadcrumb2') }]} />
      <PageHeader title={t('auditLog.breadcrumb2')} subtitle={t('auditLog.subtitle2')} />

      <Card className="mb-4">
        <div className="flex flex-wrap items-center gap-3">
          <Select value={entityFilter} onChange={(e) => { setEntityFilter(e.target.value); handleFilterChange() }} options={[
            { value: '', label: t('auditLog.allEntities') },
            { value: 'invoice', label: t('auditLog.entityTypes.invoice') },
            { value: 'purchase_invoice', label: t('auditLog.entityTypes.purchase_invoice') },
            { value: 'journal_entry', label: t('auditLog.entityTypes.journal_entry') },
            { value: 'customer', label: t('auditLog.entityTypes.customer') },
            { value: 'supplier', label: t('auditLog.entityTypes.supplier') },
            { value: 'employee', label: t('auditLog.entityTypes.employee') },
            { value: 'pay_run', label: t('auditLog.entityTypes.pay_run') },
            { value: 'fixed_asset', label: t('auditLog.entityTypes.fixed_asset') },
            { value: 'bank_transaction', label: t('auditLog.entityTypes.bank_transaction') },
          ]} />
          <Select value={actionFilter} onChange={(e) => { setActionFilter(e.target.value); handleFilterChange() }} options={[
            { value: '', label: t('auditLog.allActions') },
            { value: 'create', label: t('auditLog.actions.create') },
            { value: 'update', label: t('auditLog.actions.update') },
            { value: 'delete', label: t('auditLog.actions.delete') },
            { value: 'validate', label: t('auditLog.actions.validate') },
            { value: 'transfer', label: t('auditLog.actions.transfer') },
            { value: 'close', label: t('auditLog.actions.close') },
            { value: 'export', label: t('auditLog.actions.export') },
            { value: 'login', label: t('auditLog.actions.login') },
            { value: 'logout', label: t('auditLog.actions.logout') },
          ]} />
          <div className="flex-1 min-w-[200px]">
            <Input placeholder={t('auditLog.search')} value={search} onChange={(e) => setSearch(e.target.value)} />
          </div>
        </div>
      </Card>

      {filtered.length === 0 ? (
        <EmptyState title={t('auditLog.noEntries')} description={t('auditLog.noEntriesDescription')} />
      ) : (
        <Card>
          <Table headers={[t('auditLog.date'), t('auditLog.user'), t('auditLog.action'), t('auditLog.module'), t('auditLog.number'), t('auditLog.description')]}>
            <tbody>
              {filtered.map((log) => (
                <TableRow key={log.id}>
                  <TableCell className="whitespace-nowrap">{formatDate(log.created_at)}</TableCell>
                  <TableCell>{log.user_id ? log.user_id.slice(0, 8) + '…' : t('auditLog.system')}</TableCell>
                  <TableCell>
                    <span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-gray-100 text-gray-700">
                      {actionLabels[log.action] || log.action}
                    </span>
                  </TableCell>
                  <TableCell className="font-mono text-xs">{log.entity_type}</TableCell>
                  <TableCell className="font-mono text-xs">{log.entity_number || '—'}</TableCell>
                  <TableCell>{log.description || '—'}</TableCell>
                </TableRow>
              ))}
            </tbody>
          </Table>
        </Card>
      )}
    </div>
  )
}
