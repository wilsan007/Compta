import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, SortableTable, TableRow, TableCell, EmptyState, AutoBreadcrumb, SkeletonTable, Input, Select, ConfirmDialog, exportToCSV, Modal } from '@/components/ui'
import { getSuppliers, deleteSupplier, createSupplier, updateSupplier } from '@/lib/queries/partners'
import { getSupplierBalances, getCompanySettings } from '@/lib/queries/accounting'
import { getPaymentTerms } from '@/lib/queries/payroll'
import { getSalesRepresentatives } from '@/lib/queries/misc'
import { verifySiret, type SiretCheck } from '@/lib/queries/verifications'
import { VerificationLine } from '@/components/VerificationLine'
import { ISO_COUNTRIES, normalizeCountryCode } from '@/lib/countries'
import { hasSiret, isSiretValid } from '@/lib/siret'
import { errorMessage, formatCurrency, formatDate } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import { Package, Plus, Search, Trash2, Edit, Mail, Download, Contact as ContactIcon } from 'lucide-react'
import type { Supplier, PaymentTerm, SalesRepresentative } from '@/types'
import { PartnerContactsModal } from '@/pages/PartnerContactsModal'
import { usePermission } from '@/hooks/usePermission'

export function SuppliersPage() {
  const { toast } = useToast()
  const { t } = useTranslation('purchases')
  const { canCreate, canDelete } = usePermission('suppliers')
  const { t: tCommon } = useTranslation('common')
  const [suppliers, setSuppliers] = useState<Supplier[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<Supplier | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<Supplier | null>(null)
  const [contactsTarget, setContactsTarget] = useState<Supplier | null>(null)

  useEffect(() => {
    loadSuppliers().catch(err => console.error('loadSuppliers:', err))
  // oxlint-disable-next-line react-hooks/exhaustive-deps -- chargement volontairement limite aux valeurs listees
  }, [])

  async function loadSuppliers() {
    try {
// A3 (313) : le solde dû d'un fournisseur est celui de son 401 au grand
      // livre — `suppliers.balance` n'est tenue par rien.
      const [data, balances] = await Promise.all([getSuppliers(), getSupplierBalances()])
      const parFournisseur = new Map(balances.map((b) => [b.supplier_id, Number(b.balance) || 0]))
      setSuppliers((data || []).map((s) => ({ ...s, balance: parFournisseur.get(s.id) ?? 0 })))
    } catch (err) { console.error('Error loading suppliers:', err)
    toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.loadingError'))
    } finally {
      setLoading(false)
    }
  }

  async function handleDelete(id: string) {
    try {
      await deleteSupplier(id)
      setSuppliers(suppliers.filter((s) => s.id !== id))
      toast('success', t('suppliers.deleted'))
    } catch (err) {
      toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.deleteError'))
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
            {canCreate && <Button variant="primary" onClick={handleNew}><Plus className="w-4 h-4" /> {t('suppliers.new')}</Button>}
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
                    <button onClick={() => setContactsTarget(s)} className="p-1.5 rounded text-[var(--color-primary)] hover:bg-[var(--color-neutral-100)]" title={t('suppliers.contacts')}>
                      <ContactIcon className="w-4 h-4" />
                    </button>
                    <button onClick={() => handleEdit(s)} className="p-1.5 rounded text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-100)]" title={tCommon('actions.edit')}>
                      <Edit className="w-4 h-4" />
                    </button>
                    {canDelete && <button onClick={() => setDeleteTarget(s)} className="p-1.5 rounded text-[var(--color-danger)] hover:bg-[rgba(222,53,11,0.1)]" title={tCommon('actions.delete')}>
                      <Trash2 className="w-4 h-4" />
                    </button>}
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
            action={canCreate ? <Button variant="primary" onClick={handleNew}><Plus className="w-4 h-4" /> {t('suppliers.add')}</Button> : undefined}
          />
        )}
      </Card>

      {showForm && (
        <SupplierForm
          supplier={editing}
          fournisseurs={suppliers}
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

      {contactsTarget && (
        <PartnerContactsModal
          partnerType="supplier"
          partnerId={contactsTarget.id}
          partnerName={contactsTarget.name}
          onClose={() => setContactsTarget(null)}
        />
      )}
    </div>
  )
}

function SupplierForm({ supplier, fournisseurs, onClose, onSaved }: {
  supplier: Supplier | null
  /** A4 (318) — « Société parente » devient une liste : les fournisseurs. */
  fournisseurs: Supplier[]
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
  const [isCompany, setIsCompany] = useState(supplier?.is_company ?? true)
  const [parentId, setParentId] = useState(supplier?.parent_id || '')
  const [salesRepId, setSalesRepId] = useState(supplier?.sales_rep_id || '')
  const [accountTiers, setAccountTiers] = useState(supplier?.account_tiers || '')
  const [accountCollectif, setAccountCollectif] = useState(supplier?.account_collectif || '401000')
  // A4 (318) : l'identité et l'adresse du tiers — absentes de la fiche (ach-002).
  const [siret, setSiret] = useState(supplier?.siret || '')
  const [city, setCity] = useState(supplier?.city || '')
  const [postalCode, setPostalCode] = useState(supplier?.postal_code || '')
  const [country, setCountry] = useState(normalizeCountryCode(supplier?.country) || '')
  const [paymentTermId, setPaymentTermId] = useState(supplier?.payment_term_id || '')
  const [terms, setTerms] = useState<PaymentTerm[]>([])
  const [reps, setReps] = useState<SalesRepresentative[]>([])
  const [siretCheck, setSiretCheck] = useState<SiretCheck | null>(null)
  const [checkingSiret, setCheckingSiret] = useState(false)
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    getPaymentTerms().then(setTerms).catch(err => console.error('getPaymentTerms:', err))
    getSalesRepresentatives().then(setReps).catch(err => console.error('getSalesRepresentatives:', err))
    if (supplier) return
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
    if (!name.trim()) { toast('warning', tCommon('toast.warning'), t('suppliers.nameRequired')); return }
    // A4 (318) : un SIRET dont la clé de Luhn est fausse n'est pas enregistré.
    if (hasSiret(siret) && !isSiretValid(siret)) {
      toast('warning', tCommon('toast.warning'), t('suppliers.siretInvalid'))
      return
    }
    const code = normalizeCountryCode(country)
    if (country.trim() && !code) {
      toast('warning', tCommon('toast.warning'), t('suppliers.countryInvalid'))
      return
    }
    const terme = terms.find((x) => x.id === paymentTermId)
    setSaving(true)
    try {
      const data = {
        name, contact_name: contactName, email, phone, address, vat_number: vatNumber,
        is_company: isCompany, parent_id: parentId || null, sales_rep_id: salesRepId || null,
        account_tiers: accountTiers || null, account_collectif: accountCollectif || '401000',
        // A4 (318) — l'identité du tiers.
        siret: siret.trim() || null, city: city || '', postal_code: postalCode || '',
        country: code, payment_term_id: paymentTermId || null,
        payment_terms: terme ? terme.name : '',
      }
      if (supplier) {
        await updateSupplier(supplier.id, data)
        toast('success', t('suppliers.updated'))
      } else {
        await createSupplier(data as any)
        toast('success', t('suppliers.created'))
      }
      onSaved()
    } catch (err) {
      toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.createError'))
    } finally {
      setSaving(false)
    }
  }

  // E1 (ach-001) : cette fenêtre était plus haute que l'écran et rien ne
  // défilait — « Créer » finissait à 840 px pour un écran de 720, donc clic
  // impossible. Elle passe au `Modal` commun : cadre borné à l'écran, pied fixe,
  // et au passage le piège à focus, Échap et le verrou de défilement.
  return (
    <form onSubmit={handleSubmit}>
      <Modal
        open
        onClose={onClose}
        title={supplier ? t('suppliers.edit') : t('suppliers.new')}
        footer={
          <div className="flex justify-end gap-3">
            <Button variant="secondary" type="button" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" loading={saving}>{supplier ? tCommon('actions.save') : tCommon('actions.create')}</Button>
          </div>
        }
      >
        <div className="space-y-4">
          <Input label={t('suppliers.nameLabel')} required value={name} onChange={(e) => setName(e.target.value)} placeholder={t('suppliers.placeholders.name')} />
          <Input label={t('suppliers.contact')} value={contactName} onChange={(e) => setContactName(e.target.value)} placeholder={t('suppliers.placeholders.contactName')} />
          <Input label={t('suppliers.email')} type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder={t('suppliers.placeholders.email')} />
          <Input label={t('suppliers.phone')} value={phone} onChange={(e) => setPhone(e.target.value)} placeholder={t('suppliers.placeholders.phone')} />
          <Input label={t('suppliers.address')} value={address} onChange={(e) => setAddress(e.target.value)} placeholder={t('suppliers.placeholders.address')} />
          <Input label={t('suppliers.zipCode')} value={postalCode} onChange={(e) => setPostalCode(e.target.value)} placeholder="75001" />
          <Input label={t('suppliers.city')} value={city} onChange={(e) => setCity(e.target.value)} placeholder={t('suppliers.placeholders.city')} />
          <Select
            label={t('suppliers.country')}
            value={country}
            onChange={(e) => setCountry(e.target.value)}
            options={[{ value: '', label: t('suppliers.countryUnset') }, ...ISO_COUNTRIES.map((c) => ({ value: c.code, label: `${c.name} (${c.code})` }))]}
          />
          <Input label={t('suppliers.siret')} value={siret} onChange={(e) => setSiret(e.target.value)} placeholder="732 829 320 00074" />
          {hasSiret(siret) && (
            <VerificationLine
              busy={checkingSiret}
              disabled={!siret.trim()}
              onCheck={handleCheckSiret}
              result={siretCheck}
              labels={{
                check: t('suppliers.checkSiret'),
                checking: t('suppliers.checkingSiret'),
                atSource: t('suppliers.siretAtSource'),
                formatOnly: t('suppliers.siretFormatOnly'),
                invalid: t('suppliers.siretInvalidKey', { reason: '{{reason}}' }),
              }}
            />
          )}
          <Input label={t('suppliers.vatNumber')} value={vatNumber} onChange={(e) => setVatNumber(e.target.value)} placeholder={t('suppliers.placeholders.vatNumber')} />
          <Select
            label={t('suppliers.paymentTerms')}
            value={paymentTermId}
            onChange={(e) => setPaymentTermId(e.target.value)}
            options={[{ value: '', label: t('suppliers.paymentTermsUnset') }, ...terms.map((x) => ({ value: x.id, label: x.name }))]}
          />
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={isCompany} onChange={(e) => setIsCompany(e.target.checked)} />
            {t('suppliers.isCompany')}
          </label>
          <Select
            label={t('suppliers.parentId')}
            value={parentId}
            onChange={(e) => setParentId(e.target.value)}
            options={[
              { value: '', label: t('suppliers.parentIdUnset') },
              ...fournisseurs.filter((f) => f.id !== supplier?.id).map((f) => ({ value: f.id, label: f.name })),
            ]}
          />
          <Select
            label={t('suppliers.salesRepId')}
            value={salesRepId}
            onChange={(e) => setSalesRepId(e.target.value)}
            options={[
              { value: '', label: t('suppliers.salesRepIdUnset') },
              ...reps.map((r) => ({ value: r.id, label: r.name })),
            ]}
          />
          <Input label={t('suppliers.accountTiers')} value={accountTiers} onChange={(e) => setAccountTiers(e.target.value)} placeholder="FOU00001" />
          <Input label={t('suppliers.accountCollectif')} value={accountCollectif} onChange={(e) => setAccountCollectif(e.target.value)} placeholder="401000" />
        </div>
      </Modal>
    </form>
  )
}
