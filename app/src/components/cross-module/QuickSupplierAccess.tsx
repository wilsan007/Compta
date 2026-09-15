import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Link } from 'react-router-dom'
import { QuickAccessModal } from './QuickAccessModal'
import { Button, Input, EmptyState, Table, TableRow, TableCell, Badge } from '@/components/ui'
import { getSuppliers, createSupplier } from '@/lib/queries/partners'
import { useToast } from '@/lib/toast'
import { useModuleAwareAccess } from './useModuleAwareAccess'
import { Truck, Plus, ExternalLink, Search } from 'lucide-react'
import type { Supplier } from '@/types'

interface QuickSupplierAccessProps {
  onClose: () => void
  onSaved?: (supplier: Supplier) => void
  forceInline?: boolean
}

/**
 * Cross-module Quick Access for Suppliers.
 * - If commercial module is active → link to /sales/suppliers
 * - If commercial module is NOT active → inline mini-CRUD
 */
export function QuickSupplierAccess({ onClose, onSaved, forceInline }: QuickSupplierAccessProps) {
  const { t } = useTranslation('crossModule')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { getAccessStrategy } = useModuleAwareAccess()

  const strategy = forceInline ? 'inline' : getAccessStrategy('commercial')
  const [suppliers, setSuppliers] = useState<Supplier[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [search, setSearch] = useState('')

  const [name, setName] = useState('')
  const [email, setEmail] = useState('')
  const [phone, setPhone] = useState('')
  const [saving, setSaving] = useState(false)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      setSuppliers(await getSuppliers())
    } catch (err: any) { console.error("catch:", err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError'))
      /* ignore */
    } finally {
      setLoading(false)
    }
  }, [tCommon, toast])

  useEffect(() => {
    if (strategy === 'inline') loadData().catch(err => console.error('loadData:', err))
  }, [strategy, loadData])

  async function handleSave(e: React.FormEvent) {
    e.preventDefault()
    if (!name.trim()) return
    setSaving(true)
    try {
      const sup = await createSupplier({
        name: name.trim(),
        email: email.trim(),
        phone: phone.trim(),
        address: '',
        city: '',
        postal_code: '',
        country: '',
        vat_number: '',
        contact_name: '',
        balance: 0,
        payment_terms: '',
        currency: 'EUR',
        active: true,
      } as Omit<Supplier, 'id' | 'created_at' | 'updated_at'>)
      toast('success', tCommon('common.success'), t('supplier.created'))
      onSaved?.(sup)
      await loadData()
      setShowForm(false)
      setName(''); setEmail(''); setPhone('')
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || t('supplier.createError'))
    } finally {
      setSaving(false)
    }
  }

  const filtered = suppliers.filter((s) =>
    !search || s.name.toLowerCase().includes(search.toLowerCase()) || s.email.toLowerCase().includes(search.toLowerCase()),
  )

  if (strategy === 'full' && !forceInline) {
    return (
      <QuickAccessModal title={t('supplier.title')} onClose={onClose}>
        <EmptyState
          icon={<Truck className="w-8 h-8" />}
          title={t('supplier.moduleActive')}
          description={t('supplier.moduleActiveDescription')}
          action={
            <Link to="/sales/suppliers" onClick={onClose}>
              <Button><ExternalLink className="w-4 h-4" /> {t('supplier.goToSuppliers')}</Button>
            </Link>
          }
        />
      </QuickAccessModal>
    )
  }

  return (
    <QuickAccessModal title={t('supplier.title')} onClose={onClose}>
      <div className="space-y-4">
        <div className="flex items-center gap-2">
          <div className="relative flex-1">
            <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-[var(--color-text-tertiary)]" />
            <input
              type="text"
              placeholder={t('supplier.search')}
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="w-full pl-9 pr-3 py-2 text-sm border border-[var(--color-border)] rounded-lg bg-[var(--color-surface)] outline-none focus:border-[var(--color-primary)]"
            />
          </div>
          <Button size="sm" onClick={() => setShowForm(!showForm)}>
            <Plus className="w-4 h-4" /> {t('supplier.add')}
          </Button>
        </div>

        {showForm && (
          <form onSubmit={handleSave} className="space-y-3 p-4 rounded-lg border border-[var(--color-border)] bg-[var(--color-neutral-50)]">
            <Input label={t('supplier.name')} required value={name} onChange={(e) => setName(e.target.value)} />
            <div className="grid grid-cols-2 gap-3">
              <Input label={t('supplier.email')} type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
              <Input label={t('supplier.phone')} value={phone} onChange={(e) => setPhone(e.target.value)} />
            </div>
            <div className="flex justify-end gap-2">
              <Button type="button" variant="secondary" size="sm" onClick={() => setShowForm(false)}>{tCommon('actions.cancel')}</Button>
              <Button type="submit" size="sm" disabled={saving}>{saving ? '...' : tCommon('actions.save')}</Button>
            </div>
          </form>
        )}

        {loading ? (
          <p className="text-sm text-[var(--color-text-secondary)] text-center py-8">{tCommon('common.loading')}</p>
        ) : filtered.length === 0 ? (
          <EmptyState
            icon={<Truck className="w-8 h-8" />}
            title={t('supplier.noSuppliers')}
            description={t('supplier.noSuppliersDescription')}
            action={<Button size="sm" onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('supplier.add')}</Button>}
          />
        ) : (
          <Table headers={[t('supplier.name'), t('supplier.email'), tCommon('common.status')]}>
            {filtered.slice(0, 20).map((s) => (
              <TableRow key={s.id}>
                <TableCell className="font-medium">{s.name}</TableCell>
                <TableCell className="text-sm">{s.email || '—'}</TableCell>
                <TableCell>
                  <Badge variant={s.active ? 'success' : 'neutral'}>
                    {s.active ? tCommon('status.active') : tCommon('status.inactive')}
                  </Badge>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        )}
      </div>
    </QuickAccessModal>
  )
}
