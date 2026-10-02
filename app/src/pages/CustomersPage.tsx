import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, SortableTable, TableRow, TableCell, EmptyState, AutoBreadcrumb, SkeletonTable, Input, Select, ConfirmDialog, exportToCSV } from '@/components/ui'
import { getCustomers, deleteCustomer, createCustomer, updateCustomer } from '@/lib/queries/partners'
import { getCustomerBalances, getCompanySettings } from '@/lib/queries/accounting'
import { getPaymentTerms } from '@/lib/queries/payroll'
import { getSalesRepresentatives, getFiscalPositions } from '@/lib/queries/misc'
import { verifySiret, type SiretCheck } from '@/lib/queries/verifications'
import { VerificationLine } from '@/components/VerificationLine'
import { ISO_COUNTRIES, normalizeCountryCode } from '@/lib/countries'
import { hasSiret, isSiretValid } from '@/lib/siret'
import { formatCurrency, formatDate } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import { Users, Plus, Search, Trash2, Edit, Mail, X, Download, Contact as ContactIcon } from 'lucide-react'
import type { Customer, PaymentTerm, SalesRepresentative, FiscalPosition } from '@/types'
import { PartnerContactsModal } from '@/pages/PartnerContactsModal'
import { usePermission } from '@/hooks/usePermission'

export function CustomersPage() {
  const { toast } = useToast()
  const { t } = useTranslation('sales')
  const { canCreate, canDelete } = usePermission('customers')
  const { t: tCommon } = useTranslation('common')
  const [customers, setCustomers] = useState<Customer[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<Customer | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<Customer | null>(null)
  const [contactsTarget, setContactsTarget] = useState<Customer | null>(null)

  useEffect(() => {
    loadCustomers().catch(err => console.error('loadCustomers:', err))
  // oxlint-disable-next-line react-hooks/exhaustive-deps -- chargement volontairement limite aux valeurs listees
  }, [])

  async function loadCustomers() {
    try {
      // A3 (313) : le « Solde dû » est celui du 411 au grand livre. La colonne
      // `customers.balance` n'est tenue par rien (elle valait 0,00 EUR partout
      // pendant que le 411 portait 540,00 EUR) : on ne la lit plus.
      const [data, balances] = await Promise.all([getCustomers(), getCustomerBalances()])
      const parClient = new Map(balances.map((b) => [b.customer_id, Number(b.balance) || 0]))
      setCustomers((data || []).map((c) => ({ ...c, balance: parClient.get(c.id) ?? 0 })))
    } catch (err: any) { console.error('Error loading customers:', err)
    toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadingError'))
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
            {canCreate && <Button variant="primary" onClick={handleNew}><Plus className="w-4 h-4" /> {t('customers.new')}</Button>}
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
                <TableCell className={Number(c.balance) > 0 ? 'font-medium text-[var(--color-warning-text)] text-right' : 'text-right'}>
                  {formatCurrency(Number(c.balance) || 0)}
                </TableCell>
                <TableCell>{c.created_at ? formatDate(c.created_at) : '—'}</TableCell>
                <TableCell>
                  <div className="flex items-center gap-2">
                    <button onClick={() => setContactsTarget(c)} className="p-1.5 rounded text-[var(--color-primary)] hover:bg-[var(--color-neutral-100)]" title={t('customers.contacts')}>
                      <ContactIcon className="w-4 h-4" />
                    </button>
                    <button onClick={() => handleEdit(c)} className="p-1.5 rounded text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-100)]" title={tCommon('actions.edit')}>
                      <Edit className="w-4 h-4" />
                    </button>
                    {canDelete && <button onClick={() => setDeleteTarget(c)} className="p-1.5 rounded text-[var(--color-danger)] hover:bg-[rgba(222,53,11,0.1)]" title={tCommon('actions.delete')}>
                      <Trash2 className="w-4 h-4" />
                    </button>}
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
            action={canCreate ? <Button variant="primary" onClick={handleNew}><Plus className="w-4 h-4" /> {t('customers.createFirst')}</Button> : undefined}
          />
        )}
      </Card>

      {showForm && (
        <CustomerForm
          customer={editing}
          clients={customers}
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

      {contactsTarget && (
        <PartnerContactsModal
          partnerType="customer"
          partnerId={contactsTarget.id}
          partnerName={contactsTarget.name}
          onClose={() => setContactsTarget(null)}
        />
      )}
    </div>
  )
}

function CustomerForm({ customer, clients, onClose, onSaved }: {
  customer: Customer | null
  /** A4 (318) — « Société parente » devient une liste : les clients de la société. */
  clients: Customer[]
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
  const [isCompany, setIsCompany] = useState(customer?.is_company ?? true)
  const [parentId, setParentId] = useState(customer?.parent_id || '')
  const [salesRepId, setSalesRepId] = useState(customer?.sales_rep_id || '')
  const [accountTiers, setAccountTiers] = useState(customer?.account_tiers || '')
  const [accountCollectif, setAccountCollectif] = useState(customer?.account_collectif || '411000')
  // A4 (318) : l'identité et l'adresse du tiers — absentes de la fiche (ven-001).
  const [siret, setSiret] = useState(customer?.siret || '')
  const [city, setCity] = useState(customer?.city || '')
  const [postalCode, setPostalCode] = useState(customer?.postal_code || '')
  const [country, setCountry] = useState(normalizeCountryCode(customer?.country) || '')
  const [paymentTermId, setPaymentTermId] = useState(customer?.payment_term_id || '')
  const [terms, setTerms] = useState<PaymentTerm[]>([])
  const [reps, setReps] = useState<SalesRepresentative[]>([])
  // B3 (ven-009) : la position fiscale du client — déduite du pays et du n° de
  // TVA par la base (323) quand elle est laissée vide, choisissable à la main.
  const [fiscalPositions, setFiscalPositions] = useState<FiscalPosition[]>([])
  const [fiscalPositionId, setFiscalPositionId] = useState(customer?.fiscal_position_id || '')
  const [siretCheck, setSiretCheck] = useState<SiretCheck | null>(null)
  const [checkingSiret, setCheckingSiret] = useState(false)
  const [saving, setSaving] = useState(false)

  // Les listes du formulaire : conditions de paiement, commerciaux, et le pays
  // de la société proposé quand le champ pays est laissé vide.
  useEffect(() => {
    getPaymentTerms().then(setTerms).catch(err => console.error('getPaymentTerms:', err))
    getSalesRepresentatives().then(setReps).catch(err => console.error('getSalesRepresentatives:', err))
    getFiscalPositions().then(setFiscalPositions).catch(err => console.error('getFiscalPositions:', err))
    if (customer) return
    getCompanySettings()
      .then(cs => {
        const code = normalizeCountryCode(cs?.country_code || cs?.country)
        if (code) setCountry(code)
      })
      .catch(err => console.error('getCompanySettings:', err))
  // oxlint-disable-next-line react-hooks/exhaustive-deps -- chargement unique a l'ouverture
  }, [])

  async function handleCheckSiret() {
    setCheckingSiret(true)
    try {
      setSiretCheck(await verifySiret(siret.trim()))
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.error'))
    } finally {
      setCheckingSiret(false)
    }
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!name.trim()) { toast('warning', tCommon('form.requiredField'), t('customers.name')); return }
    // A4 (318) : un SIRET dont la clé de Luhn est fausse n'est pas enregistré.
    // La clé de contrôle se vérifie au clavier ; la vérification à la source
    // (INSEE) reste un bouton, jamais une obligation.
    if (hasSiret(siret) && !isSiretValid(siret)) {
      toast('warning', tCommon('form.requiredField'), t('customers.siretInvalid'))
      return
    }
    const code = normalizeCountryCode(country)
    if (country.trim() && !code) {
      toast('warning', tCommon('toast.warning'), t('customers.countryInvalid'))
      return
    }
    const terme = terms.find((x) => x.id === paymentTermId)
    setSaving(true)
    try {
      const data = {
        name, contact_name: contactName, email, phone, address, vat_number: vatNumber,
        is_company: isCompany, parent_id: parentId || null, sales_rep_id: salesRepId || null,
        account_tiers: accountTiers || null, account_collectif: accountCollectif || '411000',
        // A4 (318) — l'identité du tiers. `payment_terms` (texte) reste tenu :
        // l'échéance d'une facture née d'un bon de livraison le lit.
        siret: siret.trim() || null, city: city || '', postal_code: postalCode || '',
        country: code, payment_term_id: paymentTermId || null,
        // B3 (323) : un choix explicite de position fiscale est respecté ; laissé
        // vide, la base le déduit du pays et du n° de TVA.
        fiscal_position_id: fiscalPositionId || null,
        payment_terms: terme ? terme.name : '',
      }
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
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label={t('customers.name')} required value={name} onChange={(e) => setName(e.target.value)} placeholder={t('customers.placeholders.name')} />
          <Input label={t('customers.contactName')} value={contactName} onChange={(e) => setContactName(e.target.value)} placeholder={t('customers.placeholders.contactName')} />
          <Input label={t('customers.email')} type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder={t('customers.placeholders.email')} />
          <Input label={t('customers.phone')} value={phone} onChange={(e) => setPhone(e.target.value)} placeholder={t('customers.placeholders.phone')} />
          <Input label={t('customers.address')} value={address} onChange={(e) => setAddress(e.target.value)} placeholder={t('customers.placeholders.address')} />
          <Input label={t('customers.zipCode')} value={postalCode} onChange={(e) => setPostalCode(e.target.value)} placeholder="75001" />
          <Input label={t('customers.city')} value={city} onChange={(e) => setCity(e.target.value)} placeholder={t('customers.placeholders.city')} />
          <Select
            label={t('customers.country')}
            value={country}
            onChange={(e) => setCountry(e.target.value)}
            options={[{ value: '', label: t('customers.countryUnset') }, ...ISO_COUNTRIES.map((c) => ({ value: c.code, label: `${c.name} (${c.code})` }))]}
          />
          <Input label={t('customers.siret')} value={siret} onChange={(e) => setSiret(e.target.value)} placeholder="732 829 320 00074" />
          {hasSiret(siret) && (
            <VerificationLine
              busy={checkingSiret}
              disabled={!siret.trim()}
              onCheck={handleCheckSiret}
              result={siretCheck}
              labels={{
                check: t('customers.checkSiret'),
                checking: t('customers.checkingSiret'),
                atSource: t('customers.siretAtSource'),
                formatOnly: t('customers.siretFormatOnly'),
                invalid: t('customers.siretInvalidKey', { reason: '{{reason}}' }),
              }}
            />
          )}
          <Input label={t('customers.vatNumber')} value={vatNumber} onChange={(e) => setVatNumber(e.target.value)} placeholder="FR12345678901" />
          <Select
            label={t('customers.fiscalPosition')}
            value={fiscalPositionId}
            onChange={(e) => setFiscalPositionId(e.target.value)}
            options={[{ value: '', label: t('customers.fiscalPositionAuto') }, ...fiscalPositions.map((p) => ({ value: p.id, label: p.name }))]}
          />
          <Select
            label={t('customers.paymentTerms')}
            value={paymentTermId}
            onChange={(e) => setPaymentTermId(e.target.value)}
            options={[{ value: '', label: t('customers.paymentTermsUnset') }, ...terms.map((x) => ({ value: x.id, label: x.name }))]}
          />
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={isCompany} onChange={(e) => setIsCompany(e.target.checked)} />
            {t('customers.isCompany')}
          </label>
          <Select
            label={t('customers.parentId')}
            value={parentId}
            onChange={(e) => setParentId(e.target.value)}
            options={[
              { value: '', label: t('customers.parentIdUnset') },
              ...clients.filter((c) => c.id !== customer?.id).map((c) => ({ value: c.id, label: c.name })),
            ]}
          />
          <Select
            label={t('customers.salesRepId')}
            value={salesRepId}
            onChange={(e) => setSalesRepId(e.target.value)}
            options={[
              { value: '', label: t('customers.salesRepIdUnset') },
              ...reps.map((r) => ({ value: r.id, label: r.name })),
            ]}
          />
          <Input label={t('customers.accountTiers')} value={accountTiers} onChange={(e) => setAccountTiers(e.target.value)} placeholder="CLI00001" />
          <Input label={t('customers.accountCollectif')} value={accountCollectif} onChange={(e) => setAccountCollectif(e.target.value)} placeholder="411000" />
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button variant="secondary" type="button" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" loading={saving}>{customer ? tCommon('actions.edit') : tCommon('actions.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
