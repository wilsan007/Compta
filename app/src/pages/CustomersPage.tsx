import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, SortableTable, TableRow, TableCell, EmptyState, AutoBreadcrumb, SkeletonTable, Input, ConfirmDialog, exportToCSV } from '@/components/ui'
import { getCustomers, deleteCustomer, createCustomer, updateCustomer } from '@/lib/queries'
import { formatCurrency, formatDate } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import { Users, Plus, Search, Trash2, Edit, Mail, X, Download } from 'lucide-react'
import type { Customer } from '@/types'

export function CustomersPage() {
  const { toast } = useToast()
  const { t } = useTranslation('sales')
  const { t: tCommon } = useTranslation('common')
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
      toast('success', t('customers.title'), tCommon('toast.deleted'))
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.deleteError'))
    }
  }

  function handleExportCSV() {
    const headers = [t('customers.name'), t('customers.contactName'), t('customers.email'), t('customers.phone'), t('customers.outstandingBalance'), tCommon('table.total')]
    const rows = filtered.map((c) => [c.name || '', c.contact_name || '', c.email || '', c.phone || '', Number(c.balance || 0), c.created_at ? formatDate(c.created_at) : ''])
    exportToCSV(`clients-${new Date().toISOString().split('T')[0]}.csv`, headers, rows)
    toast('info', tCommon('actions.export'), `${filtered.length} ${t('customers.title').toLowerCase()} ${tCommon('toast.exported').toLowerCase()}`)
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
        title={t('customers.title')}
        subtitle={`${customers.length} ${t('customers.title').toLowerCase()}`}
        action={
          <div className="flex items-center gap-2">
            <Button variant="secondary" onClick={handleExportCSV}><Download className="w-4 h-4" /> {tCommon('actions.export')}</Button>
            <Button variant="primary" onClick={handleNew}><Plus className="w-4 h-4" /> {t('customers.new')}</Button>
          </div>
        }
      />

      <Card>
        <div className="mb-4 relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-text-secondary)]" />
          <input
            className="input pl-10"
            placeholder={t('customers.searchPlaceholder')}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>

        {loading ? (
          <SkeletonTable rows={5} cols={6} />
        ) : filtered.length > 0 ? (
          <SortableTable
            headers={[
              { label: t('customers.name'), key: 'name', sortable: true },
              { label: t('customers.contactName'), key: 'contact_name', sortable: true },
              { label: t('customers.email'), key: 'email', sortable: true },
              { label: t('customers.outstandingBalance'), key: 'balance', sortable: true, className: 'text-right' },
              { label: tCommon('table.total'), key: 'created_at', sortable: true },
              { label: tCommon('table.actions') },
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
                    <button onClick={() => handleEdit(c)} className="p-1.5 rounded text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-100)]" title={tCommon('actions.edit')}>
                      <Edit className="w-4 h-4" />
                    </button>
                    <button onClick={() => setDeleteTarget(c)} className="p-1.5 rounded text-[var(--color-danger)] hover:bg-[rgba(222,53,11,0.1)]" title={tCommon('actions.delete')}>
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
            title={t('customers.noCustomers')}
            description={t('customers.noCustomersDescription')}
            action={<Button variant="primary" onClick={handleNew}><Plus className="w-4 h-4" /> {t('customers.createFirst')}</Button>}
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
        title={tCommon('actions.delete')}
        message={`${tCommon('form.confirmDelete')} ${deleteTarget?.name} ?`}
        confirmLabel={tCommon('actions.delete')}
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
  const { t } = useTranslation('sales')
  const { t: tCommon } = useTranslation('common')
  const [contactName, setContactName] = useState(customer?.contact_name || '')
  const [email, setEmail] = useState(customer?.email || '')
  const [phone, setPhone] = useState(customer?.phone || '')
  const [address, setAddress] = useState(customer?.address || '')
  const [vatNumber, setVatNumber] = useState(customer?.vat_number || '')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!name.trim()) { toast('warning', tCommon('form.requiredField'), t('customers.name')); return }
    setSaving(true)
    try {
      const data = { name, contact_name: contactName, email, phone, address, vat_number: vatNumber }
      if (customer) {
        await updateCustomer(customer.id, data)
        toast('success', t('customers.title'), tCommon('toast.updated'))
      } else {
        await createCustomer(data as any)
        toast('success', t('customers.title'), tCommon('toast.created'))
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
          <h2 className="text-lg font-semibold">{customer ? t('customers.edit') : t('customers.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label={t('customers.name')} required value={name} onChange={(e) => setName(e.target.value)} placeholder={t('customers.placeholders.name')} />
          <Input label={t('customers.contactName')} value={contactName} onChange={(e) => setContactName(e.target.value)} placeholder={t('customers.placeholders.contactName')} />
          <Input label={t('customers.email')} type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder={t('customers.placeholders.email')} />
          <Input label={t('customers.phone')} value={phone} onChange={(e) => setPhone(e.target.value)} placeholder={t('customers.placeholders.phone')} />
          <Input label={t('customers.address')} value={address} onChange={(e) => setAddress(e.target.value)} placeholder={t('customers.placeholders.address')} />
          <Input label={t('customers.vatNumber')} value={vatNumber} onChange={(e) => setVatNumber(e.target.value)} placeholder="FR12345678901" />
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button variant="secondary" type="button" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" loading={saving}>{customer ? tCommon('actions.edit') : tCommon('actions.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
