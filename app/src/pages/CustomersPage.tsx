import { useEffect, useState } from 'react'
import { Card, PageHeader, Button, SortableTable, TableRow, TableCell, EmptyState, AutoBreadcrumb, SkeletonTable, Input, ConfirmDialog, exportToCSV } from '@/components/ui'
import { getCustomers, deleteCustomer, createCustomer, updateCustomer } from '@/lib/queries'
import { formatCurrency, formatDate } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import { Users, Plus, Search, Trash2, Edit, Mail, X, Download } from 'lucide-react'
import type { Customer } from '@/types'

export function CustomersPage() {
  const { toast } = useToast()
  const [customers, setCustomers] = useState<Customer[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<Customer | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<Customer | null>(null)

  useEffect(() => {
    loadCustomers()
  }, [])

  async function loadCustomers() {
    try {
      const data = await getCustomers()
      setCustomers(data || [])
    } catch (err) {
      console.error('Error loading customers:', err)
    } finally {
      setLoading(false)
    }
  }

  async function handleDelete(id: string) {
    try {
      await deleteCustomer(id)
      setCustomers(customers.filter((c) => c.id !== id))
      toast('success', 'Client supprimé')
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'Erreur lors de la suppression')
    }
  }

  function handleExportCSV() {
    const headers = ['Nom', 'Contact', 'Email', 'Téléphone', 'Solde', 'Créé le']
    const rows = filtered.map((c) => [c.name || '', c.contact_name || '', c.email || '', c.phone || '', Number(c.balance || 0), c.created_at ? formatDate(c.created_at) : ''])
    exportToCSV(`clients-${new Date().toISOString().split('T')[0]}.csv`, headers, rows)
    toast('info', 'Export CSV', `${filtered.length} client(s) exporté(s)`)
  }

  function handleEdit(c: Customer) {
    setEditing(c)
    setShowForm(true)
  }

  function handleNew() {
    setEditing(null)
    setShowForm(true)
  }

  const filtered = customers.filter((c) =>
    c.name?.toLowerCase().includes(search.toLowerCase()) ||
    c.email?.toLowerCase().includes(search.toLowerCase())
  )

  return (
    <div className="animate-fade-in">
      <AutoBreadcrumb />
      <PageHeader
        title="Clients"
        subtitle={`${customers.length} client(s) au total`}
        action={
          <div className="flex items-center gap-2">
            <Button variant="secondary" onClick={handleExportCSV}><Download className="w-4 h-4" /> Exporter</Button>
            <Button variant="primary" onClick={handleNew}><Plus className="w-4 h-4" /> Nouveau client</Button>
          </div>
        }
      />

      <Card>
        <div className="mb-4 relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-text-secondary)]" />
          <input
            className="input pl-10"
            placeholder="Rechercher un client..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>

        {loading ? (
          <SkeletonTable rows={5} cols={6} />
        ) : filtered.length > 0 ? (
          <SortableTable
            headers={[
              { label: 'Nom', key: 'name', sortable: true },
              { label: 'Contact', key: 'contact_name', sortable: true },
              { label: 'Email', key: 'email', sortable: true },
              { label: 'Solde', key: 'balance', sortable: true, className: 'text-right' },
              { label: 'Créé le', key: 'created_at', sortable: true },
              { label: 'Actions' },
            ]}
            data={filtered as any}
            initialSortKey="name"
            renderRow={(c: any) => (
              <TableRow key={c.id}>
                <TableCell className="font-medium">{c.name}</TableCell>
                <TableCell>{c.contact_name || '—'}</TableCell>
                <TableCell>
                  {c.email ? (
                    <a href={`mailto:${c.email}`} className="text-[var(--color-primary)] hover:underline flex items-center gap-1">
                      <Mail className="w-3 h-3" /> {c.email}
                    </a>
                  ) : '—'}
                </TableCell>
                <TableCell className={Number(c.balance) > 0 ? 'font-medium text-[var(--color-warning)] text-right' : 'text-right'}>
                  {formatCurrency(Number(c.balance) || 0)}
                </TableCell>
                <TableCell>{c.created_at ? formatDate(c.created_at) : '—'}</TableCell>
                <TableCell>
                  <div className="flex items-center gap-2">
                    <button onClick={() => handleEdit(c)} className="p-1.5 rounded text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-100)]" title="Modifier">
                      <Edit className="w-4 h-4" />
                    </button>
                    <button onClick={() => setDeleteTarget(c)} className="p-1.5 rounded text-[var(--color-danger)] hover:bg-[rgba(222,53,11,0.1)]" title="Supprimer">
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </div>
                </TableCell>
              </TableRow>
            )}
          />
        ) : (
          <EmptyState
            icon={<Users className="w-8 h-8" />}
            title="Aucun client"
            description="Ajoutez votre premier client pour commencer à facturer"
            action={<Button variant="primary" onClick={handleNew}><Plus className="w-4 h-4" /> Ajouter un client</Button>}
          />
        )}
      </Card>

      {showForm && (
        <CustomerForm
          customer={editing}
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); loadCustomers() }}
        />
      )}

      <ConfirmDialog
        open={!!deleteTarget}
        title="Supprimer le client"
        message={`Voulez-vous vraiment supprimer ${deleteTarget?.name} ? Cette action est irréversible.`}
        confirmLabel="Supprimer"
        onConfirm={() => { if (deleteTarget) handleDelete(deleteTarget.id); setDeleteTarget(null) }}
        onCancel={() => setDeleteTarget(null)}
      />
    </div>
  )
}

function CustomerForm({ customer, onClose, onSaved }: {
  customer: Customer | null
  onClose: () => void
  onSaved: () => void
}) {
  const [name, setName] = useState(customer?.name || '')
  const { toast } = useToast()
  const [contactName, setContactName] = useState(customer?.contact_name || '')
  const [email, setEmail] = useState(customer?.email || '')
  const [phone, setPhone] = useState(customer?.phone || '')
  const [address, setAddress] = useState(customer?.address || '')
  const [vatNumber, setVatNumber] = useState(customer?.vat_number || '')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!name.trim()) { toast('warning', 'Nom requis', 'Le nom est obligatoire'); return }
    setSaving(true)
    try {
      const data = { name, contact_name: contactName, email, phone, address, vat_number: vatNumber }
      if (customer) {
        await updateCustomer(customer.id, data)
        toast('success', 'Client modifié')
      } else {
        await createCustomer(data as any)
        toast('success', 'Client créé')
      }
      onSaved()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{customer ? 'Modifier le client' : 'Nouveau client'}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label="Nom / Raison sociale" required value={name} onChange={(e) => setName(e.target.value)} placeholder="Société ABC" />
          <Input label="Contact" value={contactName} onChange={(e) => setContactName(e.target.value)} placeholder="Jean Dupont" />
          <Input label="Email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="contact@societe.fr" />
          <Input label="Téléphone" value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="0612345678" />
          <Input label="Adresse" value={address} onChange={(e) => setAddress(e.target.value)} placeholder="12 rue de la Paix, 75001 Paris" />
          <Input label="N° TVA" value={vatNumber} onChange={(e) => setVatNumber(e.target.value)} placeholder="FR12345678901" />
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button variant="secondary" type="button" onClick={onClose}>Annuler</Button>
            <Button type="submit" loading={saving}>{customer ? 'Modifier' : 'Créer'}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
