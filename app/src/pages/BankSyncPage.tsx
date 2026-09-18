import { useEffect, useState, useCallback } from 'react'
import { useNavigate } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Select } from '@/components/ui'
import { getBankConnections, createBankConnection, updateBankConnection, deleteBankConnection, syncBankConnection, getBankAccounts, getBankTransactions } from '@/lib/queries/banking'
import { formatCurrency, formatDate } from '@/lib/utils'
import { RefreshCw, Plus, Trash2, X, Zap, Link2, AlertCircle } from 'lucide-react'
import type { BankConnection, BankAccount, BankTransaction } from '@/types'
import { useToast } from '@/lib/toast'
import { confirmSync } from '@/lib/confirm'

const statusVariant: Record<string, 'success' | 'warning' | 'danger' | 'neutral'> = {
  active: 'success',
  pending: 'warning',
  error: 'danger',
  expired: 'neutral',
}

export function BankSyncPage() {
  const { toast } = useToast()
  const { t } = useTranslation('banking')
  const { t: tCommon } = useTranslation('common')
  const navigate = useNavigate()
  const [connections, setConnections] = useState<BankConnection[]>([])
  const [accounts, setAccounts] = useState<BankAccount[]>([])
  const [transactions, setTransactions] = useState<BankTransaction[]>([])
  const [loading, setLoading] = useState(true)
  const [activeTab, setActiveTab] = useState('connections')
  const [showForm, setShowForm] = useState(false)
  const [syncing, setSyncing] = useState<string | null>(null)
  const [filterAccount, setFilterAccount] = useState('')

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [conns, accs, txns] = await Promise.all([
        getBankConnections(),
        getBankAccounts(),
        getBankTransactions(filterAccount || undefined),
      ])
      setConnections(conns)
      setAccounts(accs)
      setTransactions(txns.filter((tx: any) => tx.source === 'auto'))
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally {
      setLoading(false)
    }
  }, [filterAccount, toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  async function handleSync(connectionId: string) {
    setSyncing(connectionId)
    try {
      await syncBankConnection(connectionId)
      toast('success', tCommon('common.success'), t('bankSync.syncSuccess'))
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('common.error'), t('bankSync.syncError') + ': ' + (err.message || ''))
    } finally {
      setSyncing(null)
    }
  }

  async function handleDelete(id: string) {
    if (!confirmSync(tCommon('form.confirmDelete'))) return
    try {
      await deleteBankConnection(id)
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.deleteError'))
    }
  }

  const accountName = (id: string | null) => accounts.find(a => a.id === id)?.name || '—'

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('bankSync.title') }]} />
      <PageHeader
        title={t('bankSync.title')}
        subtitle={t('bankSync.subtitle')}
        action={activeTab === 'connections' ? <Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('bankSync.connections.connectBank')}</Button> : undefined}
      />

      <div className="flex border-b border-[var(--color-border)] mb-6">
        {['connections', 'transactions', 'settings'].map((tab) => (
          <button
            key={tab}
            onClick={() => setActiveTab(tab)}
            className={`px-4 py-2.5 text-sm font-medium border-b-2 transition-colors ${
              activeTab === tab
                ? 'border-[var(--color-primary)] text-[var(--color-primary)]'
                : 'border-transparent text-[var(--color-text-secondary)] hover:text-[var(--color-text)]'
            }`}
          >
            {t(`bankSync.tabs.${tab}`)}
          </button>
        ))}
      </div>

      {loading ? (
        <SkeletonTable rows={4} cols={5} />
      ) : activeTab === 'connections' ? (
        connections.length === 0 ? (
          <EmptyState
            icon={<Link2 className="w-8 h-8" />}
            title={t('bankSync.connections.noConnections')}
            description={t('bankSync.connections.noConnectionsDesc')}
            action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('bankSync.connections.connectBank')}</Button>}
          />
        ) : (
          <Card>
            <Table headers={[
              t('bankSync.connections.provider'),
              t('accounts.title'),
              t('bankSync.connections.status'),
              t('bankSync.connections.lastSync'),
              t('bankSync.connections.nextSync'),
              tCommon('table.actions'),
            ]}>
              {connections.map((conn) => (
                <TableRow key={conn.id}>
                  <TableCell className="font-medium capitalize">{conn.provider}</TableCell>
                  <TableCell className="text-xs">{accountName(conn.bank_account_id)}</TableCell>
                  <TableCell>
                    <Badge variant={statusVariant[conn.status] || 'neutral'}>
                      {t(`bankSync.connections.status${conn.status.charAt(0).toUpperCase() + conn.status.slice(1)}`)}
                    </Badge>
                    {conn.error_message && (
                      <p className="text-xs text-[var(--color-danger)] mt-1 flex items-center gap-1">
                        <AlertCircle className="w-3 h-3" /> {conn.error_message}
                      </p>
                    )}
                  </TableCell>
                  <TableCell className="text-xs">{conn.last_sync_at ? formatDate(conn.last_sync_at) : '—'}</TableCell>
                  <TableCell className="text-xs">{conn.next_sync_at ? formatDate(conn.next_sync_at) : '—'}</TableCell>
                  <TableCell>
                    <div className="flex items-center gap-1">
                      <button
                        onClick={() => handleSync(conn.id)}
                        disabled={syncing === conn.id}
                        className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)] disabled:opacity-50"
                        title={t('bankSync.connections.syncNow')}
                      >
                        <RefreshCw className={`w-4 h-4 ${syncing === conn.id ? 'animate-spin' : ''}`} />
                      </button>
                      <button
                        onClick={() => handleDelete(conn.id)}
                        className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"
                      >
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </Table>
          </Card>
        )
      ) : activeTab === 'transactions' ? (
        <>
          <div className="mb-4 flex items-center gap-3">
            <Select value={filterAccount} onChange={(e) => setFilterAccount(e.target.value)} className="max-w-xs" options={[
              { value: '', label: t('reconciliation.allAccounts') },
              ...accounts.map(a => ({ value: a.id, label: a.name })),
            ]} />
          </div>
          {transactions.length === 0 ? (
            <EmptyState
              icon={<Zap className="w-8 h-8" />}
              title={t('transactions.noTransactions')}
              description={t('transactions.noTransactionsDescription')}
            />
          ) : (
            <Card>
              <Table headers={[
                t('transactions.date'),
                t('transactions.description'),
                t('transactions.amount'),
                t('bankSync.autoSynced'),
                tCommon('table.actions'),
              ]}>
                {transactions.map((tx) => (
                  <TableRow key={tx.id}>
                    <TableCell className="text-xs">{formatDate(tx.date)}</TableCell>
                    <TableCell className="text-sm max-w-xs truncate">{tx.description}</TableCell>
                    <TableCell className={`font-mono text-xs ${tx.type === 'credit' ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>
                      {tx.type === 'credit' ? '+' : '-'}{formatCurrency(Number(tx.amount))}
                    </TableCell>
                    <TableCell><Badge variant="primary">{t('bankSync.autoSynced')}</Badge></TableCell>
                    <TableCell>
                      <Button size="sm" onClick={() => navigate('/banking/reconciliation')}>
                        {t('bankSync.reconcile')}
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
              </Table>
            </Card>
          )}
        </>
      ) : (
        <SettingsTab connections={connections} onUpdate={loadData} />
      )}

      {showForm && (
        <ConnectionForm
          accounts={accounts}
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); loadData() }}
        />
      )}
    </div>
  )
}

function SettingsTab({ connections, onUpdate }: { connections: BankConnection[]; onUpdate: () => void }) {
  const { t } = useTranslation('banking')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()

  async function handleUpdateFrequency(id: string, frequency: string) {
    try {
      await updateBankConnection(id, { sync_frequency: frequency })
      toast('success', tCommon('common.success'), t('bankSync.settings.syncFrequency') + ' → ' + frequency)
      onUpdate()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || '')
    }
  }

  return (
    <Card>
      <div className="p-6 space-y-4">
        <h3 className="text-sm font-semibold">{t('bankSync.settings.syncFrequency')}</h3>
        {connections.length === 0 ? (
          <p className="text-sm text-[var(--color-text-secondary)]">{t('bankSync.connections.noConnections')}</p>
        ) : (
          connections.map((conn) => (
            <div key={conn.id} className="flex items-center justify-between p-3 rounded-lg bg-[var(--color-neutral-50)]">
              <div>
                <p className="text-sm font-medium capitalize">{conn.provider}</p>
                <p className="text-xs text-[var(--color-text-secondary)]">{conn.sync_frequency}</p>
              </div>
              <Select
                value={conn.sync_frequency}
                onChange={(e) => handleUpdateFrequency(conn.id, e.target.value)}
                options={[
                  { value: 'hourly', label: t('bankSync.settings.hourly') },
                  { value: 'daily', label: t('bankSync.settings.daily') },
                  { value: 'weekly', label: t('bankSync.settings.weekly') },
                  { value: 'manual', label: t('bankSync.settings.manual') },
                ]}
              />
            </div>
          ))
        )}
      </div>
    </Card>
  )
}

function ConnectionForm({ accounts, onClose, onSaved }: { accounts: BankAccount[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('banking')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [provider, setProvider] = useState('gocardless')
  const [bankAccountId, setBankAccountId] = useState('')
  const [syncFrequency, setSyncFrequency] = useState('daily')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await createBankConnection({
        provider,
        provider_connection_id: null,
        bank_account_id: bankAccountId || null,
        status: 'pending',
        last_sync_at: null,
        sync_frequency: syncFrequency,
        next_sync_at: null,
        error_message: null,
        metadata: null,
      } as any)
      toast('success', tCommon('common.success'), t('bankSync.connections.connectBank'))
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.createError'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('bankSync.connections.connectBank')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Select label={t('bankSync.connections.provider')} value={provider} onChange={(e) => setProvider(e.target.value)} options={[
            { value: 'gocardless', label: 'GoCardless' },
            { value: 'plaid', label: 'Plaid' },
            { value: 'saltedge', label: 'Salt Edge' },
            { value: 'manual', label: t('bankSync.settings.manual') },
          ]} />
          <Select label={t('accounts.title')} value={bankAccountId} onChange={(e) => setBankAccountId(e.target.value)} options={[
            { value: '', label: t('thirdParty.none') || '—' },
            ...accounts.map(a => ({ value: a.id, label: a.name })),
          ]} />
          <Select label={t('bankSync.settings.syncFrequency')} value={syncFrequency} onChange={(e) => setSyncFrequency(e.target.value)} options={[
            { value: 'hourly', label: t('bankSync.settings.hourly') },
            { value: 'daily', label: t('bankSync.settings.daily') },
            { value: 'weekly', label: t('bankSync.settings.weekly') },
            { value: 'manual', label: t('bankSync.settings.manual') },
          ]} />
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button variant="secondary" type="button" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
