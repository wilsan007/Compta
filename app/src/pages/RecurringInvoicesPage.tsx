import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Select } from '@/components/ui'
import { getRecurringInvoices, toggleRecurringInvoice, getInvoices } from '@/lib/queries'
import { formatCurrency, formatDate } from '@/lib/utils'
import { RefreshCw, Power, PowerOff } from 'lucide-react'
import type { Invoice } from '@/types'
import { useToast } from '@/lib/toast'

export function RecurringInvoicesPage() {
  const { toast } = useToast()
  const { t } = useTranslation('sales')
  const { t: tCommon } = useTranslation('common')
const [recurring, setRecurring] = useState<Invoice[]>([])
  const [allInvoices, setAllInvoices] = useState<Invoice[]>([])
  const [loading, setLoading] = useState(true)
  const [showAddModal, setShowAddModal] = useState(false)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [rec, inv] = await Promise.all([getRecurringInvoices(), getInvoices()])
      setRecurring(rec)
      setAllInvoices(inv)
    } catch (err) {
      console.error('Failed to load recurring invoices:', err)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleToggle(id: string, current: boolean) {
  try {
      await toggleRecurringInvoice(id, !current)
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.updateError'))
    }
  }

  async function handleFrequencyChange(id: string, frequency: string) {
    try {
      await toggleRecurringInvoice(id, true, frequency)
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.updateError'))
    }
  }

  async function handleAddToRecurring(invoiceId: string, frequency: string) {
    try {
      await toggleRecurringInvoice(invoiceId, true, frequency)
      setShowAddModal(false)
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.updateError'))
    }
  }

  const nonRecurring = allInvoices.filter(inv => !inv.recurring)

  return (
    <div>
      <Breadcrumb items={[{ label: t('recurring.title') }]} />
      <PageHeader
        title={t('recurring.title')}
        subtitle={t('recurring.subtitle')}
        action={<Button onClick={() => setShowAddModal(true)}><RefreshCw className="w-4 h-4" /> {t('recurring.enable')}</Button>}
      />

      {loading ? (
        <SkeletonTable rows={4} cols={6} />
      ) : recurring.length === 0 ? (
        <EmptyState
          icon={<RefreshCw className="w-8 h-8" />}
          title={t('recurring.noRecurring')}
          description={t('recurring.noRecurringDescription')}
          action={<Button onClick={() => setShowAddModal(true)}><RefreshCw className="w-4 h-4" /> {t('recurring.enable')}</Button>}
        />
      ) : (
        <Card>
          <Table headers={[t('invoices.number'), t('invoices.customer'), t('invoices.date'), t('invoices.total'), t('recurring.frequency'), t('invoices.status'), tCommon('table.actions')]}>
            {recurring.map((inv) => (
              <TableRow key={inv.id}>
                <TableCell className="font-mono font-semibold">{inv.number}</TableCell>
                <TableCell>{inv.customer_name || '—'}</TableCell>
                <TableCell>{formatDate(inv.date)}</TableCell>
                <TableCell className="font-mono text-right">{formatCurrency(Number(inv.total))}</TableCell>
                <TableCell>
                  <select
                    value={inv.recurring_frequency || 'monthly'}
                    onChange={(e) => handleFrequencyChange(inv.id, e.target.value)}
                    className="text-xs border border-[var(--color-border)] rounded px-2 py-1 bg-[var(--color-surface)]"
                  >
                    <option value="weekly">{t('recurring.weekly')}</option>
                    <option value="monthly">{t('recurring.monthly')}</option>
                    <option value="quarterly">{t('recurring.quarterly')}</option>
                    <option value="yearly">{t('recurring.yearly')}</option>
                  </select>
                </TableCell>
                <TableCell>
                  <Badge variant="success">
                    <span className="flex items-center gap-1">
                      <Power className="w-3 h-3" /> {tCommon('status.active')}
                    </span>
                  </Badge>
                </TableCell>
                <TableCell>
                  <button onClick={() => handleToggle(inv.id, true)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" title={t('recurring.disable')}>
                    <PowerOff className="w-4 h-4" />
                  </button>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showAddModal && (
        <AddRecurringModal
          invoices={nonRecurring}
          onClose={() => setShowAddModal(false)}
          onAdd={handleAddToRecurring}
        />
      )}
    </div>
  )
}

function AddRecurringModal({ invoices, onClose, onAdd }: {
  invoices: Invoice[]
  onClose: () => void
  onAdd: (invoiceId: string, frequency: string) => void
}) {
  const [selectedId, setSelectedId] = useState('')
  const [frequency, setFrequency] = useState('monthly')
  const { t } = useTranslation('sales')
  const { t: tCommon } = useTranslation('common')

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('recurring.enable')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]">✕</button>
        </div>
        <div className="p-6 space-y-4">
          {invoices.length === 0 ? (
            <p className="text-sm text-[var(--color-text-secondary)]">{t('recurring.noNonRecurring')}</p>
          ) : (
            <>
              <Select
                label={t('invoices.title')}
                required
                value={selectedId}
                onChange={(e) => setSelectedId(e.target.value)}
                options={[
                  { value: '', label: tCommon('form.selectOption') },
                  ...invoices.map(i => ({ value: i.id, label: `${i.number} - ${i.customer_name || '—'} - ${formatCurrency(Number(i.total))}` })),
                ]}
              />
              <Select
                label={t('recurring.frequency')}
                value={frequency}
                onChange={(e) => setFrequency(e.target.value)}
                options={[
                  { value: 'weekly', label: t('recurring.weekly') },
                  { value: 'monthly', label: t('recurring.monthly') },
                  { value: 'quarterly', label: t('recurring.quarterly') },
                  { value: 'yearly', label: t('recurring.yearly') },
                ]}
              />
              <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
                <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
                <Button onClick={() => selectedId && onAdd(selectedId, frequency)} disabled={!selectedId}>
                  {t('recurring.enable')}
                </Button>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  )
}
