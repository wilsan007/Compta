import { useEffect, useState } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getPaymentOrders, createPaymentOrder, updatePaymentOrder, deletePaymentOrder, getBankAccounts, getThirdPartyAccounts } from '@/lib/queries'
import { Plus, Trash2, X, CheckCircle2, Ban, FileText } from 'lucide-react'
import type { PaymentOrder, BankAccount, ThirdPartyAccount } from '@/types'
import { useToast } from '@/lib/toast'

const typeLabels: Record<string, string> = {
  sepa_transfer: 'Virement SEPA',
  check: 'Chèque',
  cash: 'Espèces',
  card: 'Carte',
  other: 'Autre',
}

const statusLabels: Record<string, string> = {
  draft: 'Brouillon',
  approved: 'Approuvé',
  executed: 'Exécuté',
  cancelled: 'Annulé',
}

export function PaymentOrdersPage() {
  const { toast } = useToast()
const [orders, setOrders] = useState<PaymentOrder[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [statusFilter, setStatusFilter] = useState('')

  useEffect(() => { load() }, [])

  async function load() {
  try {
      const data = await getPaymentOrders(statusFilter || undefined)
      setOrders(data || [])
    } catch (err) {
      console.error('Error loading payment orders:', err)
    } finally {
      setLoading(false)
    }
  }

  async function handleStatusChange(id: string, status: string) {
    try { await updatePaymentOrder(id, { status: status as any }); await load() }
    catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
  }

  async function handleDelete(id: string) {
    if (!window.confirm('Supprimer cet ordre de paiement ?')) return
    try { await deletePaymentOrder(id); await load() }
    catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
  }

  const totalAmount = orders.reduce((s, o) => s + Number(o.amount), 0)
  const pendingAmount = orders.filter((o) => o.status === 'draft' || o.status === 'approved').reduce((s, o) => s + Number(o.amount), 0)

  return (
    <div>
      <Breadcrumb items={[{ label: 'Trésorerie' }, { label: 'Ordres de paiement' }]} />
      <PageHeader
        title="Ordres de paiement"
        subtitle={`${orders.length} ordre(s) — ${formatCurrency(totalAmount)} total`}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouvel ordre</Button>}
      />

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-48">
          <Select label="Statut" value={statusFilter} onChange={(e) => { setStatusFilter(e.target.value); }}
            options={[
              { value: '', label: 'Tous' },
              { value: 'draft', label: 'Brouillon' },
              { value: 'approved', label: 'Approuvé' },
              { value: 'executed', label: 'Exécuté' },
              { value: 'cancelled', label: 'Annulé' },
            ]}
          />
        </div>
        <Button variant="secondary" onClick={load}>Actualiser</Button>
        <div className="ml-auto text-sm text-[var(--color-text-secondary)]">
          En attente: <strong className="font-mono">{formatCurrency(pendingAmount)}</strong>
        </div>
      </div>

      {loading ? (
        <SkeletonTable rows={6} cols={7} />
      ) : orders.length === 0 ? (
        <EmptyState
          icon={<FileText className="w-8 h-8" />}
          title="Aucun ordre de paiement"
          description="Créez votre premier ordre de paiement."
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouvel ordre</Button>}
        />
      ) : (
        <Card>
          <Table headers={['N°', 'Type', 'Bénéficiaire', 'Montant', 'Date', 'Statut', 'Actions']}>
            {orders.map((o) => (
              <TableRow key={o.id}>
                <TableCell className="font-mono text-xs">{o.number}</TableCell>
                <TableCell className="text-xs">{typeLabels[o.type] || o.type}</TableCell>
                <TableCell className="text-sm">{o.third_party_name || '—'}</TableCell>
                <TableCell className="font-mono text-right">{formatCurrency(Number(o.amount))}</TableCell>
                <TableCell className="text-xs">{formatDate(o.payment_date)}</TableCell>
                <TableCell>
                  <select
                    value={o.status}
                    onChange={(e) => handleStatusChange(o.id, e.target.value)}
                    className="text-xs border border-[var(--color-border)] rounded px-2 py-1 bg-[var(--color-surface)]"
                  >
                    {Object.entries(statusLabels).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                  </select>
                </TableCell>
                <TableCell>
                  <div className="flex gap-1">
                    {o.status === 'draft' && (
                      <button onClick={() => handleStatusChange(o.id, 'approved')} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-success)]" title="Approuver">
                        <CheckCircle2 className="w-4 h-4" />
                      </button>
                    )}
                    <button onClick={() => handleStatusChange(o.id, 'cancelled')} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-warning)]" title="Annuler">
                      <Ban className="w-4 h-4" />
                    </button>
                    <button onClick={() => handleDelete(o.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && (
        <PaymentOrderForm onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); load() }} />
      )}
    </div>
  )
}

function PaymentOrderForm({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const [type, setType] = useState<'sepa_transfer' | 'check' | 'cash' | 'card' | 'other'>('sepa_transfer')
  const { toast } = useToast()
  const [bankAccountId, setBankAccountId] = useState('')
  const [thirdPartyId, setThirdPartyId] = useState('')
  const [thirdPartyName, setThirdPartyName] = useState('')
  const [thirdPartyIban, setThirdPartyIban] = useState('')
  const [amount, setAmount] = useState(0)
  const [paymentDate, setPaymentDate] = useState(new Date().toISOString().split('T')[0])
  const [reference, setReference] = useState('')
  const [description, setDescription] = useState('')
  const [saving, setSaving] = useState(false)
  const [bankAccounts, setBankAccounts] = useState<BankAccount[]>([])
  const [tiers, setTiers] = useState<ThirdPartyAccount[]>([])

  useEffect(() => { loadRef() }, [])

  async function loadRef() {
    try {
      const [ba, tp] = await Promise.all([getBankAccounts(), getThirdPartyAccounts()])
      setBankAccounts(ba || [])
      setTiers(tp || [])
    } catch (err) { console.error('Error loading ref:', err) }
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      const number = `PAY-${new Date().getFullYear()}-${String(Date.now()).slice(-6)}`
      await createPaymentOrder({
        number, type, status: 'draft',
        bank_account_id: bankAccountId || null,
        third_party_id: thirdPartyId || null,
        third_party_name: thirdPartyName || null,
        third_party_iban: thirdPartyIban || null,
        amount, payment_date: paymentDate,
        reference: reference || null,
        description: description || null,
        remise_number: null,
      } as any)
      onSaved()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">Nouvel ordre de paiement</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Select label="Type" value={type} onChange={(e) => setType(e.target.value as any)} options={[
            { value: 'sepa_transfer', label: 'Virement SEPA' },
            { value: 'check', label: 'Chèque' },
            { value: 'cash', label: 'Espèces' },
            { value: 'card', label: 'Carte' },
            { value: 'other', label: 'Autre' },
          ]} />
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">Compte bancaire</label>
            <select className="input" value={bankAccountId} onChange={(e) => setBankAccountId(e.target.value)}>
              <option value="">— Sélectionner —</option>
              {bankAccounts.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">Bénéficiaire (tiers)</label>
            <select className="input" value={thirdPartyId} onChange={(e) => {
              setThirdPartyId(e.target.value)
              const tp = tiers.find((t) => t.id === e.target.value)
              setThirdPartyName(tp?.name || '')
            }}>
              <option value="">— Sélectionner —</option>
              {tiers.map((t) => <option key={t.id} value={t.id}>{t.code} — {t.name}</option>)}
            </select>
          </div>
          <Input label="IBAN (optionnel)" value={thirdPartyIban} onChange={(e) => setThirdPartyIban(e.target.value)} placeholder="FR76..." />
          <div className="grid grid-cols-2 gap-4">
            <Input label="Montant" type="number" step="0.01" required value={amount} onChange={(e) => setAmount(Number(e.target.value))} />
            <Input label="Date de paiement" type="date" required value={paymentDate} onChange={(e) => setPaymentDate(e.target.value)} />
          </div>
          <Input label="Référence" value={reference} onChange={(e) => setReference(e.target.value)} />
          <Input label="Description" value={description} onChange={(e) => setDescription(e.target.value)} />
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>Annuler</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : 'Créer'}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
