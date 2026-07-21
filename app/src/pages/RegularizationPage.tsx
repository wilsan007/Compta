import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { getRegularizationEntries, createRegularizationEntry, updateRegularizationEntry, deleteRegularizationEntry } from '@/lib/queries'
import { useLocale } from '@/hooks/useLocale'
import { Plus, Trash2, Pencil, Zap, Undo2 } from 'lucide-react'
import type { RegularizationEntry } from '@/types'
import { useToast } from '@/lib/toast'

export function RegularizationPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatCurrency, formatDate } = useLocale()
  const [entries, setEntries] = useState<RegularizationEntry[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<RegularizationEntry | null>(null)
  const [filterType, setFilterType] = useState('')

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const data = await getRegularizationEntries(filterType || undefined)
      setEntries(data || [])
    } catch (err) {
      console.error('Failed to load regularization entries:', err)
    } finally {
      setLoading(false)
    }
  }, [filterType])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
    if (!window.confirm(t('regularization.deleteConfirm'))) return
    try {
      await deleteRegularizationEntry(id)
      toast('success', tCommon('common.success'), t('regularization.deleteSuccess'))
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    }
  }

  function handleEdit(entry: RegularizationEntry) {
    setEditing(entry)
    setShowForm(true)
  }

  function handleCreate() {
    setEditing(null)
    setShowForm(true)
  }

  const tableHeaders = [
    t('regularization.type'),
    t('regularization.account'),
    t('regularization.description'),
    t('regularization.startDate'),
    t('regularization.endDate'),
    t('regularization.amount'),
    t('regularization.remainingAmount'),
    t('regularization.status'),
    tCommon('common.table.actions'),
  ]

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb') }, { label: t('treatment.breadcrumb') }, { label: t('regularization.breadcrumb') }]} />
      <PageHeader
        title={t('regularization.title')}
        subtitle={t('regularization.subtitle')}
        action={<Button onClick={handleCreate}><Plus className="w-4 h-4" /> {t('regularization.new')}</Button>}
      />

      <div className="mb-4 flex items-center gap-3">
        <Select
          label={t('regularization.filterByType')}
          value={filterType}
          onChange={(e) => setFilterType(e.target.value)}
          options={[
            { value: '', label: t('regularization.all') },
            { value: 'CCA', label: t('regularization.types.CCA') },
            { value: 'PCA', label: t('regularization.types.PCA') },
            { value: 'PRC', label: t('regularization.types.PRC') },
            { value: 'CRC', label: t('regularization.types.CRC') },
          ]}
        />
      </div>

      {loading ? (
        <SkeletonTable rows={4} cols={9} />
      ) : entries.length === 0 ? (
        <EmptyState
          icon={<Zap className="w-8 h-8" />}
          title={t('regularization.noEntries')}
          description={t('regularization.noEntriesDescription')}
          action={<Button onClick={handleCreate}><Plus className="w-4 h-4" /> {t('regularization.new')}</Button>}
        />
      ) : (
        <Card>
          <Table headers={tableHeaders}>
            {entries.map((entry) => (
              <TableRow key={entry.id}>
                <TableCell>
                  <Badge variant="neutral">{entry.type}</Badge>
                </TableCell>
                <TableCell className="font-mono text-xs">{entry.account_code}</TableCell>
                <TableCell className="text-sm">{entry.description}</TableCell>
                <TableCell className="text-xs">{formatDate(entry.start_date)}</TableCell>
                <TableCell className="text-xs">{formatDate(entry.end_date)}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(entry.amount))}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(entry.remaining_amount))}</TableCell>
                <TableCell>
                  <Badge variant={entry.status === 'pending' ? 'warning' : entry.status === 'regularized' ? 'success' : 'neutral'}>
                    {t(`regularization.statuses.${entry.status}`)}
                  </Badge>
                </TableCell>
                <TableCell>
                  <div className="flex items-center gap-1">
                    <button
                      onClick={() => handleEdit(entry)}
                      className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]"
                      title={tCommon('common.actions.edit')}
                    >
                      <Pencil className="w-4 h-4" />
                    </button>
                    <button
                      onClick={() => handleDelete(entry.id)}
                      className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"
                      title={t('regularization.delete')}
                    >
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
        <RegularizationForm
          editing={editing}
          onClose={() => { setShowForm(false); setEditing(null) }}
          onSaved={() => { setShowForm(false); setEditing(null); loadData() }}
        />
      )}
    </div>
  )
}

function RegularizationForm({ editing, onClose, onSaved }: {
  editing: RegularizationEntry | null
  onClose: () => void
  onSaved: () => void
}) {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()

  const [type, setType] = useState(editing?.type || 'CCA')
  const [accountCode, setAccountCode] = useState(editing?.account_code || type === 'CCA' ? '486000' : type === 'PCA' ? '487000' : '')
  const [thirdPartyCode, setThirdPartyCode] = useState(editing?.third_party_code || '')
  const [description, setDescription] = useState(editing?.description || '')
  const [invoiceNumber, setInvoiceNumber] = useState(editing?.invoice_number || '')
  const [invoiceDate, setInvoiceDate] = useState(editing?.invoice_date || '')
  const [invoiceAmount, setInvoiceAmount] = useState(editing?.invoice_amount || 0)
  const [startDate, setStartDate] = useState(editing?.start_date || new Date().toISOString().slice(0, 10))
  const [endDate, setEndDate] = useState(editing?.end_date || '')
  const [amount, setAmount] = useState(editing?.amount || 0)
  const [saving, setSaving] = useState(false)

  function handleTypeChange(newType: string) {
    setType(newType as any)
    if (!editing) {
      if (newType === 'CCA') setAccountCode('486000')
      else if (newType === 'PCA') setAccountCode('487000')
      else if (newType === 'PRC') setAccountCode('151000')
      else setAccountCode('')
    }
  }

  async function handleSave() {
    if (!description || !accountCode || !startDate || !endDate || !amount) {
      toast('warning', tCommon('common.warning'), tCommon('common.fillRequired'))
      return
    }
    setSaving(true)
    try {
      const payload = {
        type: type as 'CCA' | 'PCA' | 'PRC' | 'CRC',
        fiscal_year_id: editing?.fiscal_year_id || null,
        account_code: accountCode,
        third_party_code: thirdPartyCode || null,
        description,
        invoice_number: invoiceNumber || null,
        invoice_date: invoiceDate || null,
        invoice_amount: Number(invoiceAmount) || 0,
        start_date: startDate,
        end_date: endDate,
        amount: Number(amount) || 0,
        status: editing?.status || 'pending' as const,
        journal_id: editing?.journal_id || null,
        journal_code: editing?.journal_code || null,
      }

      if (editing) {
        await updateRegularizationEntry(editing.id, payload)
      } else {
        await createRegularizationEntry(payload)
      }
      toast('success', tCommon('common.success'), t('regularization.saveSuccess'))
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4 overflow-y-auto">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '40rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{editing ? t('regularization.edit') : t('regularization.create')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]">✕</button>
        </div>
        <div className="p-6 space-y-4 max-h-[70vh] overflow-y-auto">
          <div className="grid grid-cols-2 gap-4">
            <Select
              label={t('regularization.type')}
              value={type}
              onChange={(e) => handleTypeChange(e.target.value)}
              options={[
                { value: 'CCA', label: t('regularization.types.CCA') },
                { value: 'PCA', label: t('regularization.types.PCA') },
                { value: 'PRC', label: t('regularization.types.PRC') },
                { value: 'CRC', label: t('regularization.types.CRC') },
              ]}
              required
            />
            <Input label={t('regularization.account')} value={accountCode} onChange={(e) => setAccountCode(e.target.value)} required />
            <Input label={t('regularization.thirdParty')} value={thirdPartyCode} onChange={(e) => setThirdPartyCode(e.target.value)} />
            <Input label={t('regularization.invoiceNumber')} value={invoiceNumber} onChange={(e) => setInvoiceNumber(e.target.value)} />
            <Input label={t('regularization.invoiceDate')} type="date" value={invoiceDate} onChange={(e) => setInvoiceDate(e.target.value)} />
            <Input label={t('regularization.invoiceAmount')} type="number" value={invoiceAmount} onChange={(e) => setInvoiceAmount(Number(e.target.value))} />
            <Input label={t('regularization.startDate')} type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)} required />
            <Input label={t('regularization.endDate')} type="date" value={endDate} onChange={(e) => setEndDate(e.target.value)} required />
            <Input label={t('regularization.amount')} type="number" value={amount} onChange={(e) => setAmount(Number(e.target.value))} required />
          </div>
          <Input label={t('regularization.description')} value={description} onChange={(e) => setDescription(e.target.value)} required />
        </div>
        <div className="flex justify-end gap-3 px-6 py-4 border-t border-[var(--color-border)]">
          <Button variant="secondary" onClick={onClose}>{tCommon('common.actions.cancel')}</Button>
          <Button onClick={handleSave} disabled={saving}>
            {saving ? tCommon('common.saving') : tCommon('common.actions.save')}
          </Button>
        </div>
      </div>
    </div>
  )
}
