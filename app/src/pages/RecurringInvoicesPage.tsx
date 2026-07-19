import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Select } from '@/components/ui'
import { getRecurringInvoices, toggleRecurringInvoice, getInvoices } from '@/lib/queries'
import { formatCurrency, formatDate } from '@/lib/utils'
import { RefreshCw, Power, PowerOff } from 'lucide-react'
import type { Invoice } from '@/types'
import { useToast } from '@/lib/toast'

export function RecurringInvoicesPage() {
  const { toast } = useToast()
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
      toast('error', 'Erreur', err.message || 'échec')
    }
  }

  async function handleFrequencyChange(id: string, frequency: string) {
    try {
      await toggleRecurringInvoice(id, true, frequency)
      await loadData()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    }
  }

  async function handleAddToRecurring(invoiceId: string, frequency: string) {
    try {
      await toggleRecurringInvoice(invoiceId, true, frequency)
      setShowAddModal(false)
      await loadData()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    }
  }

  const nonRecurring = allInvoices.filter(inv => !inv.recurring)

  return (
    <div>
      <Breadcrumb items={[{ label: 'Ventes' }, { label: 'Factures récurrentes' }]} />
      <PageHeader
        title="Factures récurrentes"
        subtitle="Automatisez vos factures périodiques"
        action={<Button onClick={() => setShowAddModal(true)}><RefreshCw className="w-4 h-4" /> Activer la récurrence</Button>}
      />

      {loading ? (
        <SkeletonTable rows={4} cols={6} />
      ) : recurring.length === 0 ? (
        <EmptyState
          icon={<RefreshCw className="w-8 h-8" />}
          title="Aucune facture récurrente"
          description="Activez la récurrence sur une facture existante pour l'automatiser."
          action={<Button onClick={() => setShowAddModal(true)}><RefreshCw className="w-4 h-4" /> Activer la récurrence</Button>}
        />
      ) : (
        <Card>
          <Table headers={['Numéro', 'Client', 'Date', 'Montant', 'Fréquence', 'Statut', 'Actions']}>
            {recurring.map((inv) => (
              <TableRow key={inv.id}>
                <TableCell className="font-mono font-semibold">{inv.number}</TableCell>
                <TableCell>{inv.customer_name || 'N/A'}</TableCell>
                <TableCell>{formatDate(inv.date)}</TableCell>
                <TableCell className="font-mono text-right">{formatCurrency(Number(inv.total))}</TableCell>
                <TableCell>
                  <select
                    value={inv.recurring_frequency || 'monthly'}
                    onChange={(e) => handleFrequencyChange(inv.id, e.target.value)}
                    className="text-xs border border-[var(--color-border)] rounded px-2 py-1 bg-[var(--color-surface)]"
                  >
                    <option value="weekly">Hebdomadaire</option>
                    <option value="monthly">Mensuel</option>
                    <option value="quarterly">Trimestriel</option>
                    <option value="yearly">Annuel</option>
                  </select>
                </TableCell>
                <TableCell>
                  <Badge variant="success">
                    <span className="flex items-center gap-1">
                      <Power className="w-3 h-3" /> Active
                    </span>
                  </Badge>
                </TableCell>
                <TableCell>
                  <button onClick={() => handleToggle(inv.id, true)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" title="Désactiver">
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

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">Activer la récurrence</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]">✕</button>
        </div>
        <div className="p-6 space-y-4">
          {invoices.length === 0 ? (
            <p className="text-sm text-[var(--color-text-secondary)]">Aucune facture non-récurrente disponible. Toutes vos factures ont déjà la récurrence activée.</p>
          ) : (
            <>
              <Select
                label="Facture"
                required
                value={selectedId}
                onChange={(e) => setSelectedId(e.target.value)}
                options={[
                  { value: '', label: 'Sélectionner une facture' },
                  ...invoices.map(i => ({ value: i.id, label: `${i.number} - ${i.customer_name || 'N/A'} - ${formatCurrency(Number(i.total))}` })),
                ]}
              />
              <Select
                label="Fréquence"
                value={frequency}
                onChange={(e) => setFrequency(e.target.value)}
                options={[
                  { value: 'weekly', label: 'Hebdomadaire' },
                  { value: 'monthly', label: 'Mensuel' },
                  { value: 'quarterly', label: 'Trimestriel' },
                  { value: 'yearly', label: 'Annuel' },
                ]}
              />
              <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
                <Button variant="secondary" onClick={onClose}>Annuler</Button>
                <Button onClick={() => selectedId && onAdd(selectedId, frequency)} disabled={!selectedId}>
                  Activer
                </Button>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  )
}
