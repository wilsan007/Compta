import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { getJournals, createJournal, updateJournal, deleteJournal, getBankAccounts, getEntryTemplates } from '@/lib/queries'
import { BookCopy, Plus, Pencil, Trash2, X, Search, Lock } from 'lucide-react'
import type { Journal, BankAccount, EntryTemplate } from '@/types'
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
      const [j, b, t] = await Promise.all([
        getJournals(),
        getBankAccounts().catch(() => []),
        getEntryTemplates().catch(() => []),
      ])
      setJournals(j || [])
      setBankAccounts(b || [])
      setTemplates(t || [])
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
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); loadData() }}
        />
      )}
    </div>
  )
}

function JournalForm({ journal, bankAccounts, templates, onClose, onSaved }: {
  journal: Journal | null
  bankAccounts: BankAccount[]
  templates: EntryTemplate[]
  onClose: () => void
  onSaved: () => void
}) {
  const [code, setCode] = useState(journal?.code || '')
  const { toast } = useToast()
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const [name, setName] = useState(journal?.name || '')
  const [type, setType] = useState<Journal['type']>(journal?.type || 'general')
  const [accountCounterpart, setAccountCounterpart] = useState(journal?.account_counterpart || '')
  const [bankAccountId, setBankAccountId] = useState(journal?.bank_account_id || '')
  const [defaultTemplateId, setDefaultTemplateId] = useState(journal?.default_entry_template_id || '')
  const [status, setStatus] = useState<Journal['status']>(journal?.status || 'active')
  const [saving, setSaving] = useState(false)

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

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{journal ? t('journals.edit') : t('journals.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('journals.code')} required value={code} onChange={(e) => setCode(e.target.value)} placeholder="ACH" />
            <Select label={t('journals.type')} value={type} onChange={(e) => setType(e.target.value as Journal['type'])} options={[
              { value: 'purchase', label: t('journals.types.purchase') },
              { value: 'sale', label: t('journals.types.sale') },
              { value: 'bank', label: t('journals.types.bank') },
              { value: 'cash', label: t('journals.types.cash') },
              { value: 'general', label: t('journals.types.general') },
              { value: 'analytic', label: t('journals.types.analytic') },
            ]} />
          </div>
          <Input label={t('journals.name')} required value={name} onChange={(e) => setName(e.target.value)} placeholder={t('journals.namePlaceholder')} />
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('journals.counterpartAccount')} value={accountCounterpart} onChange={(e) => setAccountCounterpart(e.target.value)} placeholder="401000" />
            <Select label={tCommon('common.status')} value={status} onChange={(e) => setStatus(e.target.value as Journal['status'])} options={[
              { value: 'active', label: tCommon('common.active') },
              { value: 'inactive', label: tCommon('common.inactive') },
            ]} />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Select label={t('journals.linkedBankAccount')} value={bankAccountId} onChange={(e) => setBankAccountId(e.target.value)} options={[
              { value: '', label: t('journals.none') },
              ...bankAccounts.map((b) => ({ value: b.id, label: `${b.name} (${b.bank_name})` })),
            ]} />
            <Select label={t('journals.defaultTemplate')} value={defaultTemplateId} onChange={(e) => setDefaultTemplateId(e.target.value)} options={[
              { value: '', label: t('journals.none') },
              ...templates.map((t) => ({ value: t.id, label: t.name })),
            ]} />
          </div>
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('common.saving') : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
