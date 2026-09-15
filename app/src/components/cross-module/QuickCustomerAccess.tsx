import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Link } from 'react-router-dom'
import { QuickAccessModal } from './QuickAccessModal'
import { Button, Input, EmptyState, Table, TableRow, TableCell, Badge } from '@/components/ui'
import { getCustomers, createCustomer } from '@/lib/queries/partners'
import { useToast } from '@/lib/toast'
import { useModuleAwareAccess } from './useModuleAwareAccess'
import { Users, Plus, ExternalLink, Search } from 'lucide-react'
import type { Customer } from '@/types'

interface QuickCustomerAccessProps {
  onClose: () => void
  onSaved?: (customer: Customer) => void
  forceInline?: boolean
}

/**
 * Cross-module Quick Access for Customers.
 * - If commercial module is active → link to /sales/customers
 * - If commercial module is NOT active → inline mini-CRUD
 */
export function QuickCustomerAccess({ onClose, onSaved, forceInline }: QuickCustomerAccessProps) {
  const { t } = useTranslation('crossModule')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { getAccessStrategy } = useModuleAwareAccess()

  const strategy = forceInline ? 'inline' : getAccessStrategy('commercial')
  const [customers, setCustomers] = useState<Customer[]>([])
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
      setCustomers(await getCustomers())
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
      const cust = await createCustomer({
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
        credit_limit: 0,
        payment_terms: '',
        currency: 'EUR',
        active: true,
      } as Omit<Customer, 'id' | 'created_at' | 'updated_at'>)
      toast('success', tCommon('common.success'), t('customer.created'))
      onSaved?.(cust)
      await loadData()
      setShowForm(false)
      setName(''); setEmail(''); setPhone('')
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || t('customer.createError'))
    } finally {
      setSaving(false)
    }
  }

  const filtered = customers.filter((c) =>
    !search || c.name.toLowerCase().includes(search.toLowerCase()) || c.email.toLowerCase().includes(search.toLowerCase()),
  )

  if (strategy === 'full' && !forceInline) {
    return (
      <QuickAccessModal title={t('customer.title')} onClose={onClose}>
        <EmptyState
          icon={<Users className="w-8 h-8" />}
          title={t('customer.moduleActive')}
          description={t('customer.moduleActiveDescription')}
          action={
            <Link to="/sales/customers" onClick={onClose}>
              <Button><ExternalLink className="w-4 h-4" /> {t('customer.goToCustomers')}</Button>
            </Link>
          }
        />
      </QuickAccessModal>
    )
  }

  return (
    <QuickAccessModal title={t('customer.title')} onClose={onClose}>
      <div className="space-y-4">
        <div className="flex items-center gap-2">
          <div className="relative flex-1">
            <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-[var(--color-text-tertiary)]" />
            <input
              type="text"
              placeholder={t('customer.search')}
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="w-full pl-9 pr-3 py-2 text-sm border border-[var(--color-border)] rounded-lg bg-[var(--color-surface)] outline-none focus:border-[var(--color-primary)]"
            />
          </div>
          <Button size="sm" onClick={() => setShowForm(!showForm)}>
            <Plus className="w-4 h-4" /> {t('customer.add')}
          </Button>
        </div>

        {showForm && (
          <form onSubmit={handleSave} className="space-y-3 p-4 rounded-lg border border-[var(--color-border)] bg-[var(--color-neutral-50)]">
            <Input label={t('customer.name')} required value={name} onChange={(e) => setName(e.target.value)} />
            <div className="grid grid-cols-2 gap-3">
              <Input label={t('customer.email')} type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
              <Input label={t('customer.phone')} value={phone} onChange={(e) => setPhone(e.target.value)} />
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
            icon={<Users className="w-8 h-8" />}
            title={t('customer.noCustomers')}
            description={t('customer.noCustomersDescription')}
            action={<Button size="sm" onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('customer.add')}</Button>}
          />
        ) : (
          <Table headers={[t('customer.name'), t('customer.email'), tCommon('common.status')]}>
            {filtered.slice(0, 20).map((c) => (
              <TableRow key={c.id}>
                <TableCell className="font-medium">{c.name}</TableCell>
                <TableCell className="text-sm">{c.email || '—'}</TableCell>
                <TableCell>
                  <Badge variant={c.active ? 'success' : 'neutral'}>
                    {c.active ? tCommon('status.active') : tCommon('status.inactive')}
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
