import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { getRecurringEntries, createRecurringEntry, updateRecurringEntry, deleteRecurringEntry, generateRecurringEntry, getJournals } from '@/lib/queries'
import { useLocale } from '@/hooks/useLocale'
import { RefreshCw, Plus, Trash2, Pencil, Play, Pause, Zap } from 'lucide-react'
import type { RecurringEntry, RecurringEntryLine, Journal } from '@/types'
import { useToast } from '@/lib/toast'

export function RecurringEntriesPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatCurrency, formatDate } = useLocale()
  const [entries, setEntries] = useState<RecurringEntry[]>([])
  const [journals, setJournals] = useState<Journal[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<RecurringEntry | null>(null)
  const [generatingId, setGeneratingId] = useState<string | null>(null)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [entriesData, journalsData] = await Promise.all([getRecurringEntries(), getJournals()])
      setEntries(entriesData || [])
      setJournals(journalsData || [])
    } catch (err) {
      console.error('Failed to load recurring entries:', err)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
    if (!window.confirm(t('recurring.deleteConfirm'))) return
    try {
      await deleteRecurringEntry(id)
      toast('success', tCommon('common.success'), t('recurring.deleteSuccess'))
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    }
  }

  async function handleGenerate(id: string) {
    if (!window.confirm(t('recurring.generateConfirm'))) return
    setGeneratingId(id)
    try {
      await generateRecurringEntry(id)
      toast('success', tCommon('common.success'), t('recurring.generateSuccess'))
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally {
      setGeneratingId(null)
    }
  }

  async function handleToggleStatus(entry: RecurringEntry) {
    const newStatus = entry.status === 'active' ? 'paused' : 'active'
    try {
      await updateRecurringEntry(entry.id, { status: newStatus })
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    }
  }

  function handleEdit(entry: RecurringEntry) {
    setEditing(entry)
    setShowForm(true)
  }

  function handleCreate() {
    setEditing(null)
    setShowForm(true)
  }

  const tableHeaders = [t('recurring.name'), t('recurring.journal'), t('recurring.frequency'), t('recurring.nextGeneration'), t('recurring.totalDebit'), t('recurring.status'), tCommon('common.table.actions')]

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb') }, { label: t('treatment.breadcrumb') }, { label: t('recurring.breadcrumb') }]} />
      <PageHeader
        title={t('recurring.title')}
        subtitle={t('recurring.subtitle')}
        action={<Button onClick={handleCreate}><Plus className="w-4 h-4" /> {t('recurring.new')}</Button>}
      />

      {loading ? (
        <SkeletonTable rows={4} cols={7} />
      ) : entries.length === 0 ? (
        <EmptyState
          icon={<RefreshCw className="w-8 h-8" />}
          title={t('recurring.noEntries')}
          description={t('recurring.noEntriesDescription')}
          action={<Button onClick={handleCreate}><Plus className="w-4 h-4" /> {t('recurring.new')}</Button>}
        />
      ) : (
        <Card>
          <Table headers={tableHeaders}>
            {entries.map((entry) => (
              <TableRow key={entry.id}>
                <TableCell className="font-medium">{entry.name}</TableCell>
                <TableCell className="font-mono text-xs">{entry.journal_code || entry.journal_id}</TableCell>
                <TableCell>
                  <Badge variant="neutral">{t(`recurring.frequencies.${entry.frequency}`)}</Badge>
                </TableCell>
                <TableCell className="text-xs">{formatDate(entry.next_generation_date)}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(entry.total_debit))}</TableCell>
                <TableCell>
                  <Badge variant={entry.status === 'active' ? 'success' : entry.status === 'paused' ? 'warning' : 'neutral'}>
                    {t(`recurring.statuses.${entry.status}`)}
                  </Badge>
                </TableCell>
                <TableCell>
                  <div className="flex items-center gap-1">
                    <button
                      onClick={() => handleGenerate(entry.id)}
                      disabled={generatingId === entry.id || entry.status !== 'active'}
                      className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)]"
                      title={t('recurring.generate')}
                    >
                      {generatingId === entry.id ? <RefreshCw className="w-4 h-4 animate-spin" /> : <Zap className="w-4 h-4" />}
                    </button>
                    <button
                      onClick={() => handleToggleStatus(entry)}
                      className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-warning)]"
                      title={entry.status === 'active' ? t('recurring.pause') : t('recurring.resume')}
                    >
                      {entry.status === 'active' ? <Pause className="w-4 h-4" /> : <Play className="w-4 h-4" />}
                    </button>
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
                      title={tCommon('common.actions.delete')}
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
        <RecurringEntryForm
          journals={journals}
          editing={editing}
          onClose={() => { setShowForm(false); setEditing(null) }}
          onSaved={() => { setShowForm(false); setEditing(null); loadData() }}
        />
      )}
    </div>
  )
}

function RecurringEntryForm({ journals, editing, onClose, onSaved }: {
  journals: Journal[]
  editing: RecurringEntry | null
  onClose: () => void
  onSaved: () => void
}) {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatCurrency } = useLocale()

  const [name, setName] = useState(editing?.name || '')
  const [description, setDescription] = useState(editing?.description || '')
  const [journalId, setJournalId] = useState(editing?.journal_id || journals[0]?.id || '')
  const [frequency, setFrequency] = useState(editing?.frequency || 'monthly')
  const [dayOfMonth, setDayOfMonth] = useState(editing?.day_of_month || 1)
  const [startDate, setStartDate] = useState(editing?.start_date || new Date().toISOString().slice(0, 10))
  const [endDate, setEndDate] = useState(editing?.end_date || '')
  const [lines, setLines] = useState<RecurringEntryLine[]>(editing?.lines || [{ account_code: '', description: '', debit: 0, credit: 0 }])
  const [saving, setSaving] = useState(false)

  const totalDebit = lines.reduce((s, l) => s + Number(l.debit || 0), 0)
  const totalCredit = lines.reduce((s, l) => s + Number(l.credit || 0), 0)

  function addLine() {
    setLines([...lines, { account_code: '', description: '', debit: 0, credit: 0 }])
  }

  function updateLine(idx: number, field: keyof RecurringEntryLine, value: string | number) {
    setLines(lines.map((l, i) => i === idx ? { ...l, [field]: value } : l))
  }

  function removeLine(idx: number) {
    setLines(lines.filter((_, i) => i !== idx))
  }

  async function handleSave() {
    if (!name || !journalId || lines.length === 0) {
      toast('warning', tCommon('common.warning'), tCommon('common.fillRequired'))
      return
    }
    if (Math.abs(totalDebit - totalCredit) > 0.01) {
      toast('warning', tCommon('common.warning'), tCommon('common.unbalanced'))
      return
    }
    setSaving(true)
    try {
      const selectedJournal = journals.find(j => j.id === journalId)
      const payload = {
        name,
        description: description || null,
        journal_id: journalId,
        journal_code: selectedJournal?.code || null,
        frequency,
        day_of_month: dayOfMonth,
        start_date: startDate,
        end_date: endDate || null,
        next_generation_date: startDate,
        lines,
        status: editing?.status || 'active',
        total_debit: totalDebit,
        total_credit: totalCredit,
      } as Omit<RecurringEntry, 'id' | 'tenant_id' | 'created_at' | 'updated_at'>

      if (editing) {
        await updateRecurringEntry(editing.id, payload)
      } else {
        await createRecurringEntry(payload)
      }
      toast('success', tCommon('common.success'), t('recurring.saveSuccess'))
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally {
      setSaving(false)
    }
  }

  const lineHeaders = [t('recurring.account'), t('recurring.description'), t('recurring.debit'), t('recurring.credit'), '']

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4 overflow-y-auto">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '48rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{editing ? t('recurring.edit') : t('recurring.create')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]">✕</button>
        </div>
        <div className="p-6 space-y-4 max-h-[70vh] overflow-y-auto">
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('recurring.name')} value={name} onChange={(e) => setName(e.target.value)} required />
            <Select
              label={t('recurring.journal')}
              value={journalId}
              onChange={(e) => setJournalId(e.target.value)}
              options={journals.map(j => ({ value: j.id, label: `${j.code} — ${j.name}` }))}
              required
            />
            <Select
              label={t('recurring.frequency')}
              value={frequency}
              onChange={(e) => setFrequency(e.target.value as any)}
              options={[
                { value: 'weekly', label: t('recurring.frequencies.weekly') },
                { value: 'monthly', label: t('recurring.frequencies.monthly') },
                { value: 'quarterly', label: t('recurring.frequencies.quarterly') },
                { value: 'yearly', label: t('recurring.frequencies.yearly') },
              ]}
            />
            <Input label={t('recurring.dayOfMonth')} type="number" value={dayOfMonth} onChange={(e) => setDayOfMonth(Number(e.target.value))} />
            <Input label={t('recurring.startDate')} type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)} required />
            <Input label={t('recurring.endDate')} type="date" value={endDate} onChange={(e) => setEndDate(e.target.value)} />
          </div>
          <Input label={t('recurring.description')} value={description} onChange={(e) => setDescription(e.target.value)} />

          <div>
            <div className="flex items-center justify-between mb-2">
              <h3 className="text-sm font-semibold">{t('recurring.lines')}</h3>
              <Button variant="secondary" size="sm" onClick={addLine}><Plus className="w-3 h-3" /> {t('recurring.addLine')}</Button>
            </div>
            <Table headers={lineHeaders}>
              {lines.map((line, idx) => (
                <TableRow key={idx}>
                  <TableCell>
                    <input
                      className="input text-xs"
                      placeholder="401000"
                      value={line.account_code}
                      onChange={(e) => updateLine(idx, 'account_code', e.target.value)}
                    />
                  </TableCell>
                  <TableCell>
                    <input
                      className="input text-xs"
                      value={line.description}
                      onChange={(e) => updateLine(idx, 'description', e.target.value)}
                    />
                  </TableCell>
                  <TableCell>
                    <input
                      className="input text-xs text-right"
                      type="number"
                      value={line.debit}
                      onChange={(e) => updateLine(idx, 'debit', Number(e.target.value))}
                    />
                  </TableCell>
                  <TableCell>
                    <input
                      className="input text-xs text-right"
                      type="number"
                      value={line.credit}
                      onChange={(e) => updateLine(idx, 'credit', Number(e.target.value))}
                    />
                  </TableCell>
                  <TableCell>
                    {lines.length > 1 && (
                      <button onClick={() => removeLine(idx)} className="p-1 text-[var(--color-danger)] hover:bg-[var(--color-neutral-100)] rounded">
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    )}
                  </TableCell>
                </TableRow>
              ))}
            </Table>
            <div className="flex justify-end gap-6 mt-2 text-sm">
              <span className="text-[var(--color-text-secondary)]">{t('recurring.totalDebit')}: <strong className="font-mono">{formatCurrency(totalDebit)}</strong></span>
              <span className="text-[var(--color-text-secondary)]">{t('recurring.totalCredit')}: <strong className="font-mono">{formatCurrency(totalCredit)}</strong></span>
            </div>
          </div>
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
