import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, SortableTable, TableRow, TableCell, EmptyState, AutoBreadcrumb, SkeletonTable, Input, ConfirmDialog, exportToCSV } from '@/components/ui'
import { getSuppliers, deleteSupplier, createSupplier, updateSupplier } from '@/lib/queries'
import { formatCurrency, formatDate } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import { Package, Plus, Search, Trash2, Edit, Mail, X, Download } from 'lucide-react'
import type { Supplier } from '@/types'

export function SuppliersPage() {
  const { toast } = useToast()
  const { t } = useTranslation('purchases')
  const { t: tCommon } = useTranslation('common')
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
      toast('success', t('suppliers.deleted'))
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.deleteError'))
    }
  }

  function handleExportCSV() {
    const headers = [t('suppliers.name'), t('suppliers.contact'), t('suppliers.email'), t('suppliers.phone'), t('suppliers.balance'), t('suppliers.createdAt')]
    const rows = filtered.map((s) => [s.name || '', s.contact_name || '', s.email || '', s.phone || '', Number(s.balance || 0), s.created_at ? formatDate(s.created_at) : ''])
    exportToCSV(`fournisseurs-${new Date().toISOString().split('T')[0]}.csv`, headers, rows)
    toast('info', tCommon('toast.exportCSV'), tCommon('toast.exportedCount', { count: filtered.length }))
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
        title={t('suppliers.title')}
        subtitle={`${suppliers.length} ${t('suppliers.suppliersTotal')}`}
        action={
          <div className="flex items-center gap-2">
            <Button variant="secondary" onClick={handleExportCSV}><Download className="w-4 h-4" /> {tCommon('actions.export')}</Button>
            <Button variant="primary" onClick={handleNew}><Plus className="w-4 h-4" /> {t('suppliers.new')}</Button>
          </div>
        }
      />

      <Card>
        <div className="mb-4 relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-text-secondary)]" />
          <input
            className="input pl-10"
            placeholder={t('suppliers.searchPlaceholder')}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>

        {loading ? (
          <SkeletonTable rows={5} cols={6} />
        ) : filtered.length > 0 ? (
          <SortableTable
            headers={[
              { label: t('suppliers.name'), key: 'name', sortable: true },
              { label: t('suppliers.contact'), key: 'contact_name', sortable: true },
              { label: t('suppliers.email'), key: 'email', sortable: true },
              { label: t('suppliers.balance'), key: 'balance', sortable: true, className: 'text-right' },
              { label: t('suppliers.createdAt'), key: 'created_at', sortable: true },
              { label: tCommon('table.actions') },
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
                    <button onClick={() => handleEdit(s)} className="p-1.5 rounded text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-100)]" title={tCommon('actions.edit')}>
                      <Edit className="w-4 h-4" />
                    </button>
                    <button onClick={() => setDeleteTarget(s)} className="p-1.5 rounded text-[var(--color-danger)] hover:bg-[rgba(222,53,11,0.1)]" title={tCommon('actions.delete')}>
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
            title={t('suppliers.noSuppliers')}
            description={t('suppliers.noSuppliersDescription')}
            action={<Button variant="primary" onClick={handleNew}><Plus className="w-4 h-4" /> {t('suppliers.add')}</Button>}
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
        title={t('suppliers.deleteTitle')}
        message={t('suppliers.deleteConfirm', { name: deleteTarget?.name })}
        confirmLabel={tCommon('actions.delete')}
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
  const { t } = useTranslation('purchases')
  const { t: tCommon } = useTranslation('common')
  const [contactName, setContactName] = useState(supplier?.contact_name || '')
  const [email, setEmail] = useState(supplier?.email || '')
  const [phone, setPhone] = useState(supplier?.phone || '')
  const [address, setAddress] = useState(supplier?.address || '')
  const [vatNumber, setVatNumber] = useState(supplier?.vat_number || '')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!name.trim()) { toast('warning', tCommon('toast.warning'), t('suppliers.nameRequired')); return }
    setSaving(true)
    try {
      const data = { name, contact_name: contactName, email, phone, address, vat_number: vatNumber }
      if (supplier) {
        await updateSupplier(supplier.id, data)
        toast('success', t('suppliers.updated'))
      } else {
        await createSupplier(data as any)
        toast('success', t('suppliers.created'))
      }
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
          <h2 className="text-lg font-semibold">{supplier ? t('suppliers.edit') : t('suppliers.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label={t('suppliers.nameLabel')} required value={name} onChange={(e) => setName(e.target.value)} placeholder={t('suppliers.placeholders.name')} />
          <Input label={t('suppliers.contact')} value={contactName} onChange={(e) => setContactName(e.target.value)} placeholder={t('suppliers.placeholders.contactName')} />
          <Input label={t('suppliers.email')} type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder={t('suppliers.placeholders.email')} />
          <Input label={t('suppliers.phone')} value={phone} onChange={(e) => setPhone(e.target.value)} placeholder={t('suppliers.placeholders.phone')} />
          <Input label={t('suppliers.address')} value={address} onChange={(e) => setAddress(e.target.value)} placeholder={t('suppliers.placeholders.address')} />
          <Input label={t('suppliers.vatNumber')} value={vatNumber} onChange={(e) => setVatNumber(e.target.value)} placeholder={t('suppliers.placeholders.vatNumber')} />
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button variant="secondary" type="button" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" loading={saving}>{supplier ? tCommon('actions.save') : tCommon('actions.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
