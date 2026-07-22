import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { getJournals, createJournal, updateJournal, deleteJournal, getBankAccounts, getEntryTemplates, getChartAccounts } from '@/lib/queries'
import { BookCopy, Plus, Pencil, Trash2, X, Search, Lock } from 'lucide-react'
import type { Journal, BankAccount, EntryTemplate, ChartAccount } from '@/types'
import { useToast } from '@/lib/toast'

const journalTypeBadge: Record<string, 'success' | 'warning' | 'danger' | 'neutral' | 'primary'> = {
  purchase: 'warning',
  sale: 'success',
  bank: 'primary',
  cash: 'neutral',
  general: 'danger',
  analytic: 'neutral',
}

export function JournalsPage() {
  const { toast } = useToast()
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
const [journals, setJournals] = useState<Journal[]>([])
  const [bankAccounts, setBankAccounts] = useState<BankAccount[]>([])
  const [templates, setTemplates] = useState<EntryTemplate[]>([])
  const [chartAccounts, setChartAccounts] = useState<ChartAccount[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [filterType, setFilterType] = useState('')
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<Journal | null>(null)

  useEffect(() => {
    loadData()
  }, [])

  async function loadData() {
    try {
      const [j, b, t, ca] = await Promise.all([
        getJournals(),
        getBankAccounts().catch(() => []),
        getEntryTemplates().catch(() => []),
        getChartAccounts().catch(() => []),
      ])
      setJournals(j || [])
      setBankAccounts(b || [])
      setTemplates(t || [])
      setChartAccounts(ca || [])
    } catch (err) {
      console.error('Error loading journals:', err)
    } finally {
      setLoading(false)
    }
  }

  const filtered = journals.filter((j) => {
    const matchSearch = !search ||
      j.code.toLowerCase().includes(search.toLowerCase()) ||
      j.name.toLowerCase().includes(search.toLowerCase())
    const matchType = !filterType || j.type === filterType
    return matchSearch && matchType
  })

  function openCreate() {
  setEditing(null)
    setShowForm(true)
  }

  function openEdit(journal: Journal) {
    setEditing(journal)
    setShowForm(true)
  }

  async function handleDelete(id: string) {
    if (!window.confirm(t('journals.deleteConfirm'))) return
    try {
      await deleteJournal(id)
      await loadData()
    } catch (err) {
      console.error('Error deleting journal:', err)
      toast('error', tCommon('toast.error'), tCommon('toast.deleteError'))
    }
  }

  function getBankName(id: string | null) {
    if (!id) return '—'
    const ba = bankAccounts.find((b) => b.id === id)
    return ba ? ba.name : '—'
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('home.structure') }, { label: t('journals.title') }]} />
      <PageHeader
        title={t('journals.title')}
        subtitle={t('journals.subtitle', { count: journals.length })}
        action={<Button onClick={openCreate}><Plus className="w-4 h-4" /> {t('journals.new')}</Button>}
      />

      <div className="flex gap-3 mb-4">
        <div className="flex-1 relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-text-secondary)]" />
          <input
            className="input pl-10"
            placeholder={t('journals.searchPlaceholder')}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
        <select
          className="input cursor-pointer w-48"
          value={filterType}
          onChange={(e) => setFilterType(e.target.value)}
        >
          <option value="">{t('journals.allTypes')}</option>
          <option value="purchase">{t('journals.types.purchase')}</option>
          <option value="sale">{t('journals.types.sale')}</option>
          <option value="bank">{t('journals.types.bank')}</option>
          <option value="cash">{t('journals.types.cash')}</option>
          <option value="general">{t('journals.types.general')}</option>
          <option value="analytic">{t('journals.types.analytic')}</option>
        </select>
      </div>

      {loading ? (
        <SkeletonTable rows={6} cols={6} />
      ) : filtered.length === 0 ? (
        <EmptyState
          icon={<BookCopy className="w-8 h-8" />}
          title={t('journals.noJournals')}
          description={t('journals.noJournalsDescription')}
          action={<Button onClick={openCreate}><Plus className="w-4 h-4" /> {t('journals.new')}</Button>}
        />
      ) : (
        <Card>
          <Table headers={[t('journals.code'), t('journals.name'), t('journals.type'), t('journals.counterpart'), t('journals.bankAccount'), tCommon('common.status'), tCommon('table.actions')]}>
            {filtered.map((journal) => (
              <TableRow key={journal.id}>
                <TableCell className="font-mono font-semibold">{journal.code}</TableCell>
                <TableCell>{journal.name}</TableCell>
                <TableCell>
                  <Badge variant={journalTypeBadge[journal.type] || 'neutral'}>
                    {t(`journals.types.${journal.type}`, { defaultValue: journal.type })}
                  </Badge>
                </TableCell>
                <TableCell className="font-mono text-xs">{journal.account_counterpart || '—'}</TableCell>
                <TableCell>{getBankName(journal.bank_account_id)}</TableCell>
                <TableCell>
                  {journal.locked ? (
                    <Badge variant="danger"><Lock className="w-3 h-3 inline mr-1" />{t('journals.locked')}</Badge>
                  ) : journal.status === 'active' ? (
                    <Badge variant="success">{tCommon('common.active')}</Badge>
                  ) : (
                    <Badge variant="neutral">{tCommon('common.inactive')}</Badge>
                  )}
                </TableCell>
                <TableCell>
                  <div className="flex gap-2">
                    <button onClick={() => openEdit(journal)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]">
                      <Pencil className="w-4 h-4" />
                    </button>
                    <button onClick={() => handleDelete(journal.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
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
        <JournalForm
          journal={editing}
          bankAccounts={bankAccounts}
          templates={templates}
          chartAccounts={chartAccounts}
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); loadData() }}
        />
      )}
    </div>
  )
}

function JournalForm({ journal, bankAccounts, templates, chartAccounts, onClose, onSaved }: {
  journal: Journal | null
  bankAccounts: BankAccount[]
  templates: EntryTemplate[]
  chartAccounts: ChartAccount[]
  onClose: () => void
  onSaved: () => void
}) {
  const [code, setCode] = useState(journal?.code || '')
  const { toast } = useToast()
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const [activeTab, setActiveTab] = useState('complement')
  const [name, setName] = useState(journal?.name || '')
  const [type, setType] = useState<Journal['type']>(journal?.type || 'general')
  const [accountCounterpart, setAccountCounterpart] = useState(journal?.account_counterpart || '')
  const [bankAccountId, setBankAccountId] = useState(journal?.bank_account_id || '')
  const [defaultTemplateId, setDefaultTemplateId] = useState(journal?.default_entry_template_id || '')
  const [status, setStatus] = useState<Journal['status']>(journal?.status || 'active')
  const [racinesAutorisees, setRacinesAutorisees] = useState((journal as any)?.racines_autorisees || '')
  const [compteAttente, setCompteAttente] = useState((journal as any)?.compte_attente || '')
  const [numerotation, setNumerotation] = useState((journal as any)?.numerotation || 'manual')
  const [reconciliationMode, setReconciliationMode] = useState((journal as any)?.reconciliation_mode || 'manual')
  const [saving, setSaving] = useState(false)

  const isTreasury = type === 'bank' || type === 'cash'

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      const data = {
        code: code.toUpperCase(),
        name,
        type,
        account_counterpart: accountCounterpart || null,
        bank_account_id: bankAccountId || null,
        default_entry_template_id: defaultTemplateId || null,
        status,
        locked: journal?.locked || false,
        racines_autorisees: racinesAutorisees || null,
        compte_attente: compteAttente || null,
        numerotation: numerotation || 'manual',
        reconciliation_mode: isTreasury ? (reconciliationMode || 'manual') : null,
      }
      if (journal) {
        await updateJournal(journal.id, data)
      } else {
        await createJournal(data as any)
      }
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.createError'))
    } finally {
      setSaving(false)
    }
  }

  const tabs = [
    { id: 'complement', label: t('journals.tabs.complement') },
    ...(isTreasury ? [{ id: 'banque', label: t('journals.tabs.banque') }] : []),
    { id: 'modele', label: t('journals.tabs.modele') },
    { id: 'droits', label: t('journals.tabs.droits') },
  ]

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '42rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{journal ? t('journals.edit') : t('journals.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit}>
          <div className="flex border-b border-[var(--color-border)] px-6">
            {tabs.map((tab) => (
              <button
                key={tab.id}
                type="button"
                onClick={() => setActiveTab(tab.id)}
                className={`px-4 py-2.5 text-sm font-medium border-b-2 transition-colors ${
                  activeTab === tab.id
                    ? 'border-[var(--color-primary)] text-[var(--color-primary)]'
                    : 'border-transparent text-[var(--color-text-secondary)] hover:text-[var(--color-text)]'
                }`}
              >
                {tab.label}
              </button>
            ))}
          </div>

          <div className="p-6 space-y-4">
            {activeTab === 'complement' && (
              <>
                <div className="grid grid-cols-2 gap-4">
                  <Input label={t('journals.code')} required value={code} onChange={(e) => setCode(e.target.value)} placeholder="ACH" />
                  <Input label={t('journals.name')} required value={name} onChange={(e) => setName(e.target.value)} placeholder={t('journals.namePlaceholder')} />
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <Select label={t('journals.type')} value={type} onChange={(e) => setType(e.target.value as Journal['type'])} options={[
                    { value: 'purchase', label: t('journals.types.purchase') },
                    { value: 'sale', label: t('journals.types.sale') },
                    { value: 'bank', label: t('journals.types.bank') },
                    { value: 'cash', label: t('journals.types.cash') },
                    { value: 'general', label: t('journals.types.general') },
                    { value: 'analytic', label: t('journals.types.analytic') },
                  ]} />
                  <Select label={tCommon('common.status')} value={status} onChange={(e) => setStatus(e.target.value as Journal['status'])} options={[
                    { value: 'active', label: tCommon('common.active') },
                    { value: 'inactive', label: tCommon('common.inactive') },
                  ]} />
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <Select label={t('journals.counterpartAccount')} value={accountCounterpart} onChange={(e) => setAccountCounterpart(e.target.value)} options={[
                    { value: '', label: t('journals.none') },
                    ...chartAccounts.map((a) => ({ value: a.code, label: `${a.code} — ${a.name}` })),
                  ]} />
                  <Select label={t('journals.compteAttente')} value={compteAttente} onChange={(e) => setCompteAttente(e.target.value)} options={[
                    { value: '', label: t('journals.none') },
                    ...chartAccounts.filter((a) => a.code.startsWith('47') || a.code.startsWith('48')).map((a) => ({ value: a.code, label: `${a.code} — ${a.name}` })),
                  ]} />
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <Input label={t('journals.racinesAutorisees')} value={racinesAutorisees} onChange={(e) => setRacinesAutorisees(e.target.value)} placeholder="401, 411, 512" />
                  <Select label={t('journals.numerotation')} value={numerotation} onChange={(e) => setNumerotation(e.target.value)} options={[
                    { value: 'manual', label: t('journals.numerotationManual') },
                    { value: 'auto', label: t('journals.numerotationAuto') },
                    { value: 'continuous', label: t('journals.numerotationContinuous') },
                  ]} />
                </div>
              </>
            )}

            {activeTab === 'banque' && isTreasury && (
              <>
                <Select label={t('journals.linkedBankAccount')} value={bankAccountId} onChange={(e) => setBankAccountId(e.target.value)} options={[
                  { value: '', label: t('journals.none') },
                  ...bankAccounts.map((b) => ({ value: b.id, label: `${b.name} (${b.bank_name})` })),
                ]} />
                <Input label={t('journals.rib')} value="" onChange={() => {}} placeholder="FR76 1234 5678 9012 3456 7890 123" />
                <Select label={t('journals.reconciliationMode')} value={reconciliationMode} onChange={(e) => setReconciliationMode(e.target.value)} options={[
                  { value: 'manual', label: t('journals.reconciliationManual') },
                  { value: 'auto', label: t('journals.reconciliationAuto') },
                ]} />
              </>
            )}

            {activeTab === 'modele' && (
              <>
                <Select label={t('journals.defaultTemplate')} value={defaultTemplateId} onChange={(e) => setDefaultTemplateId(e.target.value)} options={[
                  { value: '', label: t('journals.none') },
                  ...templates.map((tpl) => ({ value: tpl.id, label: tpl.name })),
                ]} />
                {defaultTemplateId && (() => {
                  const tpl = templates.find((t) => t.id === defaultTemplateId)
                  if (!tpl) return null
                  return (
                    <div className="text-sm space-y-2 p-3 rounded-lg bg-[var(--color-neutral-50)] border border-[var(--color-border)]">
                      <p className="font-medium text-[var(--color-text)]">{tpl.name}</p>
                      {tpl.description && <p className="text-xs text-[var(--color-text-secondary)]">{tpl.description}</p>}
                      <div className="flex gap-3 text-xs text-[var(--color-text-secondary)]">
                        <span>{t('journals.templateLines')}: <strong>{tpl.template_lines?.length || 0}</strong></span>
                        {tpl.journal_code && <span>{t('journals.templateJournal')}: <strong className="font-mono">{tpl.journal_code}</strong></span>}
                        {tpl.is_default && <span className="text-[var(--color-primary)] font-medium">{t('journals.templateIsDefault')}</span>}
                      </div>
                    </div>
                  )
                })()}
                <div className="text-sm text-[var(--color-text-secondary)] p-3 rounded-lg bg-[var(--color-neutral-50)]">
                  {t('journals.templateHint')}
                </div>
              </>
            )}

            {activeTab === 'droits' && (
              <>
                <div className="text-sm text-[var(--color-text-secondary)] mb-2">{t('journals.authorizedUsers')}</div>
                <div className="space-y-2 max-h-48 overflow-y-auto">
                  <label className="flex items-center gap-2 text-sm p-2 rounded border border-[var(--color-border)]">
                    <input type="checkbox" defaultChecked />
                    <span>Admin</span>
                  </label>
                  <label className="flex items-center gap-2 text-sm p-2 rounded border border-[var(--color-border)]">
                    <input type="checkbox" defaultChecked />
                    <span>Comptable</span>
                  </label>
                  <label className="flex items-center gap-2 text-sm p-2 rounded border border-[var(--color-border)]">
                    <input type="checkbox" />
                    <span>Gestionnaire</span>
                  </label>
                </div>
                <p className="text-xs text-[var(--color-text-secondary)]">{t('journals.rightsHint')}</p>
              </>
            )}
          </div>

          <div className="flex justify-end gap-3 px-6 py-4 border-t border-[var(--color-border)]">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('common.saving') : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
