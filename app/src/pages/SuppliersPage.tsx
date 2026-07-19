import { useEffect, useState } from 'react'
import { Card, PageHeader, Button, SortableTable, TableRow, TableCell, EmptyState, AutoBreadcrumb, SkeletonTable, Input, ConfirmDialog, exportToCSV } from '@/components/ui'
import { getSuppliers, deleteSupplier, createSupplier, updateSupplier } from '@/lib/queries'
import { formatCurrency, formatDate } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import { Package, Plus, Search, Trash2, Edit, Mail, X, Download } from 'lucide-react'
import type { Supplier } from '@/types'

export function SuppliersPage() {
  const { toast } = useToast()
  const [suppliers, setSuppliers] = useState<Supplier[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<Supplier | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<Supplier | null>(null)

  useEffect(() => {
    loadSuppliers()
  }, [])

  async function loadSuppliers() {
    try {
      const data = await getSuppliers()
      setSuppliers(data || [])
    } catch (err) {
      console.error('Error loading suppliers:', err)
    } finally {
      setLoading(false)
    }
  }

  async function handleDelete(id: string) {
    try {
      await deleteSupplier(id)
      setSuppliers(suppliers.filter((s) => s.id !== id))
      toast('success', 'Fournisseur supprimé')
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'Erreur lors de la suppression')
    }
  }

  function handleExportCSV() {
    const headers = ['Nom', 'Contact', 'Email', 'Téléphone', 'Solde', 'Créé le']
    const rows = filtered.map((s) => [s.name || '', s.contact_name || '', s.email || '', s.phone || '', Number(s.balance || 0), s.created_at ? formatDate(s.created_at) : ''])
    exportToCSV(`fournisseurs-${new Date().toISOString().split('T')[0]}.csv`, headers, rows)
    toast('info', 'Export CSV', `${filtered.length} fournisseur(s) exporté(s)`)
  }

  function handleEdit(s: Supplier) {
    setEditing(s)
    setShowForm(true)
  }

  function handleNew() {
    setEditing(null)
    setShowForm(true)
  }

  const filtered = suppliers.filter((s) =>
    s.name?.toLowerCase().includes(search.toLowerCase()) ||
    s.email?.toLowerCase().includes(search.toLowerCase())
  )

  return (
    <div className="animate-fade-in">
      <AutoBreadcrumb />
      <PageHeader
        title="Fournisseurs"
        subtitle={`${suppliers.length} fournisseur(s) au total`}
        action={
          <div className="flex items-center gap-2">
            <Button variant="secondary" onClick={handleExportCSV}><Download className="w-4 h-4" /> Exporter</Button>
            <Button variant="primary" onClick={handleNew}><Plus className="w-4 h-4" /> Nouveau fournisseur</Button>
          </div>
        }
      />

      <Card>
        <div className="mb-4 relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-text-secondary)]" />
          <input
            className="input pl-10"
            placeholder="Rechercher un fournisseur..."
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
            renderRow={(s: any) => (
              <TableRow key={s.id}>
                <TableCell className="font-medium">{s.name}</TableCell>
                <TableCell>{s.contact_name || '—'}</TableCell>
                <TableCell>
                  {s.email ? (
                    <a href={`mailto:${s.email}`} className="text-[var(--color-primary)] hover:underline flex items-center gap-1">
                      <Mail className="w-3 h-3" /> {s.email}
                    </a>
                  ) : '—'}
                </TableCell>
                <TableCell className={Number(s.balance) > 0 ? 'font-medium text-[var(--color-danger)] text-right' : 'text-right'}>
                  {formatCurrency(Number(s.balance) || 0)}
                </TableCell>
                <TableCell>{s.created_at ? formatDate(s.created_at) : '—'}</TableCell>
                <TableCell>
                  <div className="flex items-center gap-2">
                    <button onClick={() => handleEdit(s)} className="p-1.5 rounded text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-100)]" title="Modifier">
                      <Edit className="w-4 h-4" />
                    </button>
                    <button onClick={() => setDeleteTarget(s)} className="p-1.5 rounded text-[var(--color-danger)] hover:bg-[rgba(222,53,11,0.1)]" title="Supprimer">
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </div>
                </TableCell>
              </TableRow>
            )}
          />
        ) : (
          <EmptyState
            icon={<Package className="w-8 h-8" />}
            title="Aucun fournisseur"
            description="Ajoutez votre premier fournisseur pour enregistrer vos achats"
            action={<Button variant="primary" onClick={handleNew}><Plus className="w-4 h-4" /> Ajouter un fournisseur</Button>}
          />
        )}
      </Card>

      {showForm && (
        <SupplierForm
          supplier={editing}
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); loadSuppliers() }}
        />
      )}

      <ConfirmDialog
        open={!!deleteTarget}
        title="Supprimer le fournisseur"
        message={`Voulez-vous vraiment supprimer ${deleteTarget?.name} ? Cette action est irréversible.`}
        confirmLabel="Supprimer"
        onConfirm={() => { if (deleteTarget) handleDelete(deleteTarget.id); setDeleteTarget(null) }}
        onCancel={() => setDeleteTarget(null)}
      />
    </div>
  )
}

function SupplierForm({ supplier, onClose, onSaved }: {
  supplier: Supplier | null
  onClose: () => void
  onSaved: () => void
}) {
  const [name, setName] = useState(supplier?.name || '')
  const { toast } = useToast()
  const [contactName, setContactName] = useState(supplier?.contact_name || '')
  const [email, setEmail] = useState(supplier?.email || '')
  const [phone, setPhone] = useState(supplier?.phone || '')
  const [address, setAddress] = useState(supplier?.address || '')
  const [vatNumber, setVatNumber] = useState(supplier?.vat_number || '')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!name.trim()) { toast('warning', 'Nom requis', 'Le nom est obligatoire'); return }
    setSaving(true)
    try {
      const data = { name, contact_name: contactName, email, phone, address, vat_number: vatNumber }
      if (supplier) {
        await updateSupplier(supplier.id, data)
        toast('success', 'Fournisseur modifié')
      } else {
        await createSupplier(data as any)
        toast('success', 'Fournisseur créé')
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
          <h2 className="text-lg font-semibold">{supplier ? 'Modifier le fournisseur' : 'Nouveau fournisseur'}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label="Nom / Raison sociale" required value={name} onChange={(e) => setName(e.target.value)} placeholder="Tech Supply Co" />
          <Input label="Contact" value={contactName} onChange={(e) => setContactName(e.target.value)} placeholder="Jean Dupont" />
          <Input label="Email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="contact@supplier.fr" />
          <Input label="Téléphone" value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="0612345678" />
          <Input label="Adresse" value={address} onChange={(e) => setAddress(e.target.value)} placeholder="15 rue du Commerce, 75011 Paris" />
          <Input label="N° TVA" value={vatNumber} onChange={(e) => setVatNumber(e.target.value)} placeholder="FR98765432109" />
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button variant="secondary" type="button" onClick={onClose}>Annuler</Button>
            <Button type="submit" loading={saving}>{supplier ? 'Modifier' : 'Créer'}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
