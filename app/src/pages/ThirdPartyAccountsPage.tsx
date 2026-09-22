import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Card, PageHeader, Button, SortableTable, TableRow, TableCell, Badge, EmptyState, AutoBreadcrumb, SkeletonTable, Input, Select, ConfirmDialog, exportToCSV } from '@/components/ui'
import { getThirdPartyAccounts, createThirdPartyAccount, updateThirdPartyAccount, deleteThirdPartyAccount, getChartAccounts } from '@/lib/queries/accounting'
import { getCustomers, getSuppliers } from '@/lib/queries/partners'
import { Users2, Plus, Pencil, Trash2, X, Search, Link2, MoreVertical, Settings, FilePlus2, Wallet, FileBarChart, Download, Landmark } from 'lucide-react'
import { formatCurrency } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import { useTranslation } from 'react-i18next'
import type { ThirdPartyAccount, Customer, Supplier, ChartAccount } from '@/types'
import { PartnerBankAccountsModal } from '@/components/PartnerBankAccountsModal'

const typeBadge: Record<string, 'success' | 'warning' | 'danger' | 'neutral' | 'primary'> = {
  customer: 'success',
  supplier: 'warning',
  employee: 'primary',
  other: 'neutral',
}

export function ThirdPartyAccountsPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const navigate = useNavigate()
  const [accounts, setAccounts] = useState<ThirdPartyAccount[]>([])
  const { toast } = useToast()
  const [customers, setCustomers] = useState<Customer[]>([])
  const [suppliers, setSuppliers] = useState<Supplier[]>([])
  const [chartAccounts, setChartAccounts] = useState<ChartAccount[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [filterType, setFilterType] = useState('')
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<ThirdPartyAccount | null>(null)
  const [openMenuId, setOpenMenuId] = useState<string | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<ThirdPartyAccount | null>(null)

  useEffect(() => {
    loadData().catch(err => console.error('loadData:', err))
  // oxlint-disable-next-line react-hooks/exhaustive-deps -- chargement volontairement limite aux valeurs listees
  }, [])

  async function loadData() {
    try {
      const [a, c, s, ca] = await Promise.all([
        getThirdPartyAccounts(),
        getCustomers().catch(() => []),
        getSuppliers().catch(() => []),
        getChartAccounts().catch(() => []),
      ])
      setAccounts(a || [])
      setCustomers(c || [])
      setSuppliers(s || [])
      setChartAccounts(ca || [])
    } catch (err: any) {
      console.error('Error loading third party accounts:', err)
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadingError'))
    } finally {
      setLoading(false)
    }
  }

  const filtered = accounts.filter((a) => {
    const matchSearch = !search ||
      a.code.toLowerCase().includes(search.toLowerCase()) ||
      a.name.toLowerCase().includes(search.toLowerCase())
    const matchType = !filterType || a.type === filterType
    return matchSearch && matchType
  })

  function openCreate() {
    setEditing(null)
    setShowForm(true)
  }

  function openEdit(a: ThirdPartyAccount) {
    setEditing(a)
    setShowForm(true)
  }

  async function handleDelete(id: string) {
    try {
      await deleteThirdPartyAccount(id)
      toast('success', t('thirdParty.deleted'))
      await loadData()
    } catch (err: any) {
      toast('error', t('thirdParty.deleteError'), err.message || '')
    }
  }

  function handleExportCSV() {
    const headers = [t('thirdParty.code'), t('thirdParty.name'), t('thirdParty.type'), t('thirdParty.generalAccount'), t('thirdParty.linkedTo'), t('thirdParty.balance'), t('thirdParty.lettrage'), t('thirdParty.siret'), t('thirdParty.vatIntra'), t('thirdParty.iban')]
    const rows = filtered.map((a) => [
      a.code,
      a.name,
      t(`thirdParty.types.${a.type}`) || a.type,
      a.account_general_code || '',
      getLinkedName(a),
      Number(a.balance || 0),
      a.lettrage_code || '',
      a.siret || '',
      a.vat_intra || '',
      a.iban || '',
    ])
    exportToCSV(`plan-tiers-${new Date().toISOString().split('T')[0]}.csv`, headers, rows)
    toast('info', t('thirdParty.exportCSV'), t('thirdParty.exported', { count: filtered.length }))
  }

  function getLinkedName(a: ThirdPartyAccount) {
    if (a.customer_id) {
      const c = customers.find((x) => x.id === a.customer_id)
      return c ? c.name : '—'
    }
    if (a.supplier_id) {
      const s = suppliers.find((x) => x.id === a.supplier_id)
      return s ? s.name : '—'
    }
    return '—'
  }

  function handleSaisirFacture(a: ThirdPartyAccount) {
    setOpenMenuId(null)
    navigate(a.type === 'supplier' ? '/purchases/invoices' : '/sales/invoices')
  }

  function handleReglerFacture(_a: ThirdPartyAccount) {
    setOpenMenuId(null)
    navigate('/accounting/payment-generation')
  }

  function handleGenererReleves(_a: ThirdPartyAccount) {
    setOpenMenuId(null)
    navigate('/accounting/states/general-ledger-tiers')
  }

  return (
    <div>
      <AutoBreadcrumb />
      <PageHeader
        title={t('thirdParty.title')}
        subtitle={t('thirdParty.subtitle', { count: accounts.length })}
        action={
          <div className="flex flex-row items-center gap-2">
            <Button variant="secondary" onClick={handleExportCSV}><Download className="w-4 h-4" /> {t('thirdParty.export')}</Button>
            <Button onClick={openCreate}><Plus className="w-4 h-4" /> {t('thirdParty.new')}</Button>
          </div>
        }
      />

      <div className="flex gap-3 mb-4">
        <div className="flex-1 relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-text-secondary)]" />
          <input
            className="input pl-10"
            placeholder={t('thirdParty.searchPlaceholder')}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
        <select
          className="input cursor-pointer w-40"
          value={filterType}
          onChange={(e) => setFilterType(e.target.value)}
        >
          <option value="">{t('thirdParty.allTypes')}</option>
          <option value="customer">{t('thirdParty.customers')}</option>
          <option value="supplier">{t('thirdParty.suppliers')}</option>
          <option value="employee">{t('thirdParty.employees')}</option>
          <option value="other">{t('thirdParty.others')}</option>
        </select>
      </div>

      {loading ? (
        <SkeletonTable rows={6} cols={6} />
      ) : filtered.length === 0 ? (
        <EmptyState
          icon={<Users2 className="w-8 h-8" />}
          title={t('thirdParty.noThirdParty')}
          description={t('thirdParty.noThirdPartyDescription')}
          action={<Button onClick={openCreate}><Plus className="w-4 h-4" /> {t('thirdParty.new')}</Button>}
        />
      ) : (
        <Card>
          <SortableTable
            headers={[
              { label: t('thirdParty.code'), key: 'code', sortable: true },
              { label: t('thirdParty.name'), key: 'name', sortable: true },
              { label: t('thirdParty.type'), key: 'type', sortable: true },
              { label: t('thirdParty.generalAccount'), key: 'account_general_code', sortable: true },
              { label: t('thirdParty.linkedTo') },
              { label: t('thirdParty.balance'), key: 'balance', sortable: true, className: 'text-right' },
              { label: t('thirdParty.lettrage'), key: 'lettrage_code', sortable: true },
              { label: t('thirdParty.vatIntra'), key: 'vat_intra', sortable: true },
              { label: t('thirdParty.actions') },
            ]}
            data={filtered as ThirdPartyAccount[]}
            initialSortKey="code"
            renderRow={(a: ThirdPartyAccount) => (
              <TableRow key={a.id}>
                <TableCell className="font-mono font-semibold">{a.code}</TableCell>
                <TableCell>{a.name}</TableCell>
                <TableCell><Badge variant={typeBadge[a.type] || 'neutral'}>{t(`thirdParty.types.${a.type}`) || a.type}</Badge></TableCell>
                <TableCell className="font-mono text-xs">{a.account_general_code || '—'}</TableCell>
                <TableCell className="text-xs">
                  {a.customer_id || a.supplier_id ? (
                    <span className="flex items-center gap-1 text-[var(--color-primary)]"><Link2 className="w-3 h-3" />{getLinkedName(a)}</span>
                  ) : '—'}
                </TableCell>
                <TableCell className="font-mono text-right">{formatCurrency(Number(a.balance) || 0)}</TableCell>
                <TableCell className="font-mono text-xs">{a.lettrage_code || '—'}</TableCell>
                <TableCell className="font-mono text-xs">{a.vat_intra || '—'}</TableCell>
                <TableCell>
                  <div className="relative flex gap-2">
                    <button onClick={() => openEdit(a)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]" title={t('thirdParty.editAccount')}>
                      <Pencil className="w-4 h-4" />
                    </button>
                    <button onClick={() => setDeleteTarget(a)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" title={t('thirdParty.deleteConfirmLabel')}>
                      <Trash2 className="w-4 h-4" />
                    </button>
                    <button
                      onClick={() => setOpenMenuId(openMenuId === a.id ? null : a.id)}
                      className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]"
                      title={t('thirdParty.whatToDo')}
                    >
                      <MoreVertical className="w-4 h-4" />
                    </button>
                    {openMenuId === a.id && (
                      <div className="absolute right-0 top-full mt-1 z-20 w-56 rounded-lg border border-[var(--color-border)] bg-[var(--color-surface)] shadow-lg py-1">
                        <p className="px-3 py-1.5 text-xs text-[var(--color-text-secondary)]">{t('thirdParty.whatToDoFor', { code: a.code })}</p>
                        <button onClick={() => { setOpenMenuId(null); openEdit(a) }} className="w-full flex items-center gap-2 px-3 py-2 text-sm text-left hover:bg-[var(--color-neutral-100)]">
                          <Settings className="w-4 h-4" /> {t('thirdParty.manageAccount')}
                        </button>
                        <button onClick={() => handleSaisirFacture(a)} className="w-full flex items-center gap-2 px-3 py-2 text-sm text-left hover:bg-[var(--color-neutral-100)]">
                          <FilePlus2 className="w-4 h-4" /> {t('thirdParty.enterInvoice')}
                        </button>
                        <button onClick={() => handleReglerFacture(a)} className="w-full flex items-center gap-2 px-3 py-2 text-sm text-left hover:bg-[var(--color-neutral-100)]">
                          <Wallet className="w-4 h-4" /> {t('thirdParty.payInvoice')}
                        </button>
                        <button onClick={() => handleGenererReleves(a)} className="w-full flex items-center gap-2 px-3 py-2 text-sm text-left hover:bg-[var(--color-neutral-100)]">
                          <FileBarChart className="w-4 h-4" /> {t('thirdParty.generateStatements')}
                        </button>
                      </div>
                    )}
                  </div>
                </TableCell>
              </TableRow>
            )}
          />
        </Card>
      )}

      {showForm && (
        <ThirdPartyForm
          account={editing}
          accounts={accounts}
          customers={customers}
          suppliers={suppliers}
          chartAccounts={chartAccounts}
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); loadData() }}
        />
      )}

      <ConfirmDialog
        open={!!deleteTarget}
        title={t('thirdParty.delete')}
        message={t('thirdParty.deleteConfirm', { code: deleteTarget?.code, name: deleteTarget?.name })}
        confirmLabel={t('thirdParty.deleteConfirmLabel')}
        onConfirm={() => { if (deleteTarget) handleDelete(deleteTarget.id); setDeleteTarget(null) }}
        onCancel={() => setDeleteTarget(null)}
      />
    </div>
  )
}

function ThirdPartyForm({ account, accounts, customers, suppliers, chartAccounts, onClose, onSaved }: {
  account: ThirdPartyAccount | null
  accounts: ThirdPartyAccount[]
  customers: Customer[]
  suppliers: Supplier[]
  chartAccounts: ChartAccount[]
  onClose: () => void
  onSaved: () => void
}) {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const [activeTab, setActiveTab] = useState('fiche')
  const { toast } = useToast()
  const [code, setCode] = useState(account?.code || '')
  const [name, setName] = useState(account?.name || '')
  const [type, setType] = useState<ThirdPartyAccount['type']>(account?.type || 'customer')
  const [accountGeneralCode, setAccountGeneralCode] = useState(account?.account_general_code || '')
  const [customerId, setCustomerId] = useState(account?.customer_id || '')
  const [supplierId, setSupplierId] = useState(account?.supplier_id || '')
  const [currency, setCurrency] = useState(account?.currency || 'EUR')
  const [active, setActive] = useState(account?.active ?? true)
  const [address, setAddress] = useState(account?.address || '')
  const [postalCode, setPostalCode] = useState(account?.postal_code || '')
  const [city, setCity] = useState(account?.city || '')
  const [country, setCountry] = useState(account?.country || 'France')
  const [siret, setSiret] = useState(account?.siret || '')
  const [vatIntra, setVatIntra] = useState(account?.vat_intra || '')
  const [iban, setIban] = useState(account?.iban || '')
  const [bic, setBic] = useState(account?.bic || '')
  const [bankCode, setBankCode] = useState(account?.bank_code || '')
  const [branchCode, setBranchCode] = useState(account?.branch_code || '')
  const [accountNumber, setAccountNumber] = useState(account?.bank_account_number || '')
  const [key, setKey] = useState(account?.bank_key || '')
  const [echeanceModel, setEcheanceModel] = useState(account?.echeance_model || '')
  const [paymentCondition, setPaymentCondition] = useState(account?.payment_condition || '')
  const [paymentMode, setPaymentMode] = useState(account?.payment_mode || '')
  const [encoursAutorise, setEncoursAutorise] = useState(account?.encours_autorise != null ? String(account.encours_autorise) : '')
  const [relanceNiveau, setRelanceNiveau] = useState(account?.relance_niveau || '')
  const [relanceModel, setRelanceModel] = useState(account?.relance_model || '')
  const [delaiPaiement, setDelaiPaiement] = useState(account?.delai_paiement || '')
  const [escompte, setEscompte] = useState(account?.escompte != null ? String(account.escompte) : '')
  const [contactName, setContactName] = useState(account?.contact_name || '')
  const [zoneGeo, setZoneGeo] = useState(account?.zone_geo || '')
  const [categorie, setCategorie] = useState(account?.categorie || '')
  const [saving, setSaving] = useState(false)
  const [showPartnerBankModal, setShowPartnerBankModal] = useState(false)

  const tierAccounts = chartAccounts.filter((a) => a.code.startsWith('4'))

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      const data = {
        code: code.toUpperCase(),
        name,
        type,
        account_general_code: accountGeneralCode || null,
        customer_id: customerId || null,
        supplier_id: supplierId || null,
        employee_id: null,
        balance: account?.balance || 0,
        lettrage_code: account?.lettrage_code || null,
        currency,
        active,
        address,
        postal_code: postalCode,
        city,
        country,
        siret,
        vat_intra: vatIntra,
        iban,
        bic,
        bank_code: bankCode,
        branch_code: branchCode,
        bank_account_number: accountNumber,
        bank_key: key,
        echeance_model: echeanceModel,
        payment_condition: paymentCondition,
        payment_mode: paymentMode,
        encours_autorise: encoursAutorise ? Number(encoursAutorise) : null,
        relance_niveau: relanceNiveau,
        relance_model: relanceModel,
        delai_paiement: delaiPaiement,
        escompte: escompte ? Number(escompte) : null,
        contact_name: contactName,
        zone_geo: zoneGeo,
        categorie,
      }
      if (account) {
        await updateThirdPartyAccount(account.id, data)
        toast('success', t('thirdParty.updated'))
      } else {
        await createThirdPartyAccount(data as Omit<ThirdPartyAccount, 'id' | 'created_at' | 'updated_at'>)
        toast('success', t('thirdParty.saved'))
      }
      onSaved()
    } catch (err: any) {
      toast('error', t('thirdParty.saveError'), err.message || '')
    } finally {
      setSaving(false)
    }
  }

  const tabs = [
    { id: 'fiche', label: t('thirdParty.tabs.fiche') },
    { id: 'banques', label: t('thirdParty.tabs.banques') },
    { id: 'modeles', label: t('thirdParty.tabs.modeles') },
    { id: 'complement', label: t('thirdParty.tabs.complement') },
    { id: 'statistiques', label: t('thirdParty.tabs.statistiques') },
    { id: 'free', label: t('thirdParty.tabs.freeInfo') },
  ]

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '42rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{account ? t('thirdParty.edit') : t('thirdParty.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit}>
          <div className="flex border-b border-[var(--color-border)] px-6 overflow-x-auto">
            {tabs.map((tab) => (
              <button
                key={tab.id}
                type="button"
                onClick={() => setActiveTab(tab.id)}
                className={`px-4 py-2.5 text-sm font-medium border-b-2 transition-colors whitespace-nowrap ${
                  activeTab === tab.id
                    ? 'border-[var(--color-primary)] text-[var(--color-primary)]'
                    : 'border-transparent text-[var(--color-text-secondary)] hover:text-[var(--color-text)]'
                }`}
              >
                {tab.label}
              </button>
            ))}
          </div>

          <div className="p-6 space-y-4 max-h-[60vh] overflow-y-auto">
            {activeTab === 'fiche' && (
              <>
                <div className="grid grid-cols-2 gap-4">
                  <Input label={t('thirdParty.code')} required value={code} onChange={(e) => setCode(e.target.value)} placeholder="Ex: 411CLI001" />
                  <Input label={t('thirdParty.name')} required value={name} onChange={(e) => setName(e.target.value)} placeholder="Ex: Client ABC SARL" />
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <Select label={t('thirdParty.type')} value={type} onChange={(e) => setType(e.target.value as ThirdPartyAccount['type'])} options={[
                    { value: 'customer', label: t('thirdParty.types.customer') },
                    { value: 'supplier', label: t('thirdParty.types.supplier') },
                    { value: 'employee', label: t('thirdParty.types.employee') },
                    { value: 'other', label: t('thirdParty.types.other') },
                  ]} />
                  <Select label={t('thirdParty.generalAccountClass4')} value={accountGeneralCode} onChange={(e) => setAccountGeneralCode(e.target.value)} options={[
                    { value: '', label: t('thirdParty.none') },
                    ...tierAccounts.map((a) => ({ value: a.code, label: `${a.code} — ${a.name}` })),
                  ]} />
                </div>
                <Input label={t('thirdParty.address')} value={address} onChange={(e) => setAddress(e.target.value)} placeholder="12 rue du Commerce" />
                <div className="grid grid-cols-3 gap-4">
                  <Input label={t('thirdParty.postalCode')} value={postalCode} onChange={(e) => setPostalCode(e.target.value)} placeholder="75001" />
                  <Input label={t('thirdParty.city')} value={city} onChange={(e) => setCity(e.target.value)} placeholder="Paris" />
                  <Input label={t('thirdParty.country')} value={country} onChange={(e) => setCountry(e.target.value)} placeholder="France" />
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <Input label={t('thirdParty.siret')} value={siret} onChange={(e) => setSiret(e.target.value)} placeholder="123 456 789 00012" />
                  <Input label={t('thirdParty.vatIntra')} value={vatIntra} onChange={(e) => setVatIntra(e.target.value)} placeholder="FR12345678901" />
                </div>
                {type === 'customer' && (
                  <Select label={t('thirdParty.linkedCustomer')} value={customerId} onChange={(e) => setCustomerId(e.target.value)} options={[
                    { value: '', label: t('thirdParty.none') },
                    ...customers
                      .filter((c) => !accounts.some((a) => a.customer_id === c.id && a.id !== account?.id))
                      .map((c) => ({ value: c.id, label: c.name })),
                  ]} />
                )}
                {type === 'supplier' && (
                  <Select label={t('thirdParty.linkedSupplier')} value={supplierId} onChange={(e) => setSupplierId(e.target.value)} options={[
                    { value: '', label: t('thirdParty.none') },
                    ...suppliers
                      .filter((s) => !accounts.some((a) => a.supplier_id === s.id && a.id !== account?.id))
                      .map((s) => ({ value: s.id, label: s.name })),
                  ]} />
                )}
              </>
            )}

            {activeTab === 'banques' && (
              <>
                <Input label={t('thirdParty.iban')} value={iban} onChange={(e) => setIban(e.target.value)} placeholder="FR76 1234 5678 9012 3456 7890 123" />
                <Input label={t('thirdParty.bic')} value={bic} onChange={(e) => setBic(e.target.value)} placeholder="ABCDEFGHXXX" />
                <div className="grid grid-cols-4 gap-4">
                  <Input label={t('thirdParty.bankCode')} value={bankCode} onChange={(e) => setBankCode(e.target.value)} placeholder="12345" />
                  <Input label={t('thirdParty.branchCode')} value={branchCode} onChange={(e) => setBranchCode(e.target.value)} placeholder="67890" />
                  <Input label={t('thirdParty.accountNumber')} value={accountNumber} onChange={(e) => setAccountNumber(e.target.value)} placeholder="12345678901" />
                  <Input label={t('thirdParty.key')} value={key} onChange={(e) => setKey(e.target.value)} placeholder="23" />
                </div>
                <p className="text-xs text-[var(--color-text-secondary)]">{t('thirdParty.multiRibHint')}</p>
                {account && (type === 'customer' || type === 'supplier') && (
                  <div className="pt-4 border-t border-[var(--color-border)]">
                    <Button type="button" variant="secondary" onClick={() => setShowPartnerBankModal(true)}>
                      <Landmark className="w-4 h-4" /> {t('partnerBankAccounts.title', { ns: 'banking' })}
                    </Button>
                  </div>
                )}
              </>
            )}

            {activeTab === 'modeles' && (
              <>
                <Input label={t('thirdParty.echeanceModel')} value={echeanceModel} onChange={(e) => setEcheanceModel(e.target.value)} placeholder="" />
                <Input label={t('thirdParty.paymentCondition')} value={paymentCondition} onChange={(e) => setPaymentCondition(e.target.value)} placeholder="30 jours fin de mois" />
                <Input label={t('thirdParty.paymentMode')} value={paymentMode} onChange={(e) => setPaymentMode(e.target.value)} placeholder="Virement" />
              </>
            )}

            {activeTab === 'complement' && (
              <>
                <div className="grid grid-cols-2 gap-4">
                  <Input label={t('thirdParty.encoursAutorise')} type="number" value={encoursAutorise} onChange={(e) => setEncoursAutorise(e.target.value)} placeholder="10000" />
                  <Input label={t('thirdParty.relanceNiveau')} value={relanceNiveau} onChange={(e) => setRelanceNiveau(e.target.value)} placeholder="1" />
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <Input label={t('thirdParty.relanceModel')} value={relanceModel} onChange={(e) => setRelanceModel(e.target.value)} placeholder="" />
                  <Input label={t('thirdParty.delaiPaiement')} value={delaiPaiement} onChange={(e) => setDelaiPaiement(e.target.value)} placeholder="30" />
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <Input label={t('thirdParty.escompte')} type="number" value={escompte} onChange={(e) => setEscompte(e.target.value)} placeholder="0" />
                  <Input label={t('thirdParty.contactName')} value={contactName} onChange={(e) => setContactName(e.target.value)} placeholder={t('thirdParty.placeholders.contactName')} />
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <Input label={t('thirdParty.currency')} value={currency} onChange={(e) => setCurrency(e.target.value)} />
                  <div className="flex items-end">
                    <label className="flex items-center gap-2 text-sm">
                      <input type="checkbox" checked={active} onChange={(e) => setActive(e.target.checked)} />
                      {t('thirdParty.active')}
                    </label>
                  </div>
                </div>
              </>
            )}

            {activeTab === 'statistiques' && (
              <>
                <div className="grid grid-cols-2 gap-4">
                  <Input label={t('thirdParty.zoneGeo')} value={zoneGeo} onChange={(e) => setZoneGeo(e.target.value)} placeholder="Île-de-France" />
                  <Input label={t('thirdParty.categorie')} value={categorie} onChange={(e) => setCategorie(e.target.value)} placeholder="PME" />
                </div>
              </>
            )}

            {activeTab === 'free' && (
              <>
                <div className="space-y-3">
                  {Array.from({ length: 5 }, (_, i) => (
                    <div key={i} className="grid grid-cols-2 gap-4">
                      <Input label={t('thirdParty.freeFieldLabel', { n: i + 1 })} value="" onChange={() => {}} placeholder="" />
                      <Input label={t('thirdParty.freeFieldValue', { n: i + 1 })} value="" onChange={() => {}} placeholder="" />
                    </div>
                  ))}
                </div>
                <p className="text-xs text-[var(--color-text-secondary)]">{t('thirdParty.freeInfoHint')}</p>
              </>
            )}
          </div>

          <div className="flex justify-end gap-3 px-6 py-4 border-t border-[var(--color-border)]">
            <Button variant="secondary" onClick={onClose}>{t('thirdParty.cancel')}</Button>
            <Button type="submit" disabled={saving}>{t('thirdParty.save')}</Button>
          </div>
        </form>
      </div>

      {showPartnerBankModal && account && (type === 'customer' || type === 'supplier') && (
        <PartnerBankAccountsModal
          partnerType={type as 'customer' | 'supplier'}
          partnerId={account.id}
          onClose={() => setShowPartnerBankModal(false)}
        />
      )}
    </div>
  )
}
