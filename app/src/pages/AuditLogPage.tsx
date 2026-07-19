import { useEffect, useState } from 'react'
import { Card, PageHeader, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Select, Input } from '@/components/ui'
import { formatDate } from '@/lib/utils'
import { getAuditLog } from '@/lib/queries'

export function AuditLogPage() {
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
    create: 'Création', update: 'Modification', delete: 'Suppression',
    login: 'Connexion', logout: 'Déconnexion', transfer: 'Transfert',
    validate: 'Validation', close: 'Clôture', export: 'Export',
  }

  if (loading) return <SkeletonTable rows={6} />

  return (
    <div>
      <Breadcrumb items={[{ label: 'Système', path: '/system/audit-log' }, { label: 'Journal d\'audit' }]} />
      <PageHeader title="Journal d'audit" subtitle="Traçabilité des actions utilisateur" />

      <Card className="mb-4">
        <div className="flex flex-wrap items-center gap-3">
          <Select value={entityFilter} onChange={(e) => { setEntityFilter(e.target.value); handleFilterChange() }} options={[
            { value: '', label: 'Toutes les entités' },
            { value: 'invoice', label: 'Factures' },
            { value: 'purchase_invoice', label: 'Factures d\'achat' },
            { value: 'journal_entry', label: 'Écritures' },
            { value: 'customer', label: 'Clients' },
            { value: 'supplier', label: 'Fournisseurs' },
            { value: 'employee', label: 'Employés' },
            { value: 'pay_run', label: 'Campagnes de paie' },
            { value: 'fixed_asset', label: 'Immobilisations' },
            { value: 'bank_transaction', label: 'Transactions bancaires' },
          ]} />
          <Select value={actionFilter} onChange={(e) => { setActionFilter(e.target.value); handleFilterChange() }} options={[
            { value: '', label: 'Toutes les actions' },
            { value: 'create', label: 'Création' },
            { value: 'update', label: 'Modification' },
            { value: 'delete', label: 'Suppression' },
            { value: 'validate', label: 'Validation' },
            { value: 'transfer', label: 'Transfert' },
            { value: 'close', label: 'Clôture' },
            { value: 'export', label: 'Export' },
            { value: 'login', label: 'Connexion' },
            { value: 'logout', label: 'Déconnexion' },
          ]} />
          <div className="flex-1 min-w-[200px]">
            <Input placeholder="Rechercher..." value={search} onChange={(e) => setSearch(e.target.value)} />
          </div>
        </div>
      </Card>

      {filtered.length === 0 ? (
        <EmptyState title="Aucune entrée" description="Le journal d'audit est vide." />
      ) : (
        <Card>
          <Table headers={['Date', 'Utilisateur', 'Action', 'Entité', 'N°', 'Description']}>
            <tbody>
              {filtered.map((log) => (
                <TableRow key={log.id}>
                  <TableCell className="whitespace-nowrap">{formatDate(log.created_at)}</TableCell>
                  <TableCell>{log.user_id ? log.user_id.slice(0, 8) + '…' : 'Système'}</TableCell>
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
