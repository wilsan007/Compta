import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Badge } from '@/components/ui'
import { getExpenseCategories, createExpenseCategory, updateExpenseCategory } from '@/lib/queries/sprintDE'
import { Tag, Plus, X, Edit2 } from 'lucide-react'
import { useToast } from '@/lib/toast'

export function ExpenseCategoriesPage() {
  const { toast } = useToast()
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const [records, setRecords] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [editRecord, setEditRecord] = useState<any>(null)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const cats = await getExpenseCategories()
      setRecords(cats || [])
    } catch (err: any) {
      console.error(err)
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setLoading(false) }
  }, [toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.hr') }, { label: t('expenseCategories.title') }]} />
      <PageHeader
        title={t('expenseCategories.title')}
        subtitle={t('expenseCategories.subtitle')}
        action={<Button onClick={() => { setEditRecord(null); setShowForm(true) }}><Plus className="w-4 h-4" /> {t('expenseCategories.new')}</Button>}
      />

      {loading ? (
        <SkeletonTable rows={4} cols={7} />
      ) : records.length === 0 ? (
        <EmptyState
          icon={<Tag className="w-8 h-8" />}
          title={t('expenseCategories.noRecords')}
          description={t('expenseCategories.noRecordsDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('expenseCategories.new')}</Button>}
        />
      ) : (
        <Card>
          <Table headers={[
            t('expenseCategories.code'),
            t('expenseCategories.label'),
            t('expenseCategories.accountCode'),
            t('expenseCategories.vatRate'),
            t('expenseCategories.maxAmount'),
            t('expenseCategories.active'),
            tCommon('table.actions'),
          ]}>
            {records.map((r) => (
              <TableRow key={r.id}>
                <TableCell className="font-mono text-xs">{r.code}</TableCell>
                <TableCell className="text-sm font-medium">{r.label}</TableCell>
                <TableCell className="font-mono text-xs">{r.account_code || '—'}</TableCell>
                <TableCell className="font-mono text-xs text-right">{r.vat_rate}%</TableCell>
                <TableCell className="font-mono text-xs text-right">{r.max_amount || '—'}</TableCell>
                <TableCell>{r.active ? <Badge variant="success">{tCommon('common.yes')}</Badge> : <Badge variant="neutral">{tCommon('common.no')}</Badge>}</TableCell>
                <TableCell>
                  <button onClick={() => { setEditRecord(r); setShowForm(true) }} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-info)]">
                    <Edit2 className="w-4 h-4" />
                  </button>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && (
        <ExpenseCategoryForm
          record={editRecord}
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); loadData() }}
        />
      )}
    </div>
  )
}

function ExpenseCategoryForm({ record, onClose, onSaved }: { record: any; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [code, setCode] = useState(record?.code || '')
  const [label, setLabel] = useState(record?.label || '')
  const [accountCode, setAccountCode] = useState(record?.account_code || '')
  const [vatRate, setVatRate] = useState(record?.vat_rate ?? 20)
  const [maxAmount, setMaxAmount] = useState(record?.max_amount ?? '')
  const [maxMonthly, setMaxMonthly] = useState(record?.max_monthly ?? '')
  const [requiresReceipt, setRequiresReceipt] = useState(record?.requires_receipt ?? true)
  const [active, setActive] = useState(record?.active ?? true)
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      const data = {
        code, label,
        account_code: accountCode || null,
        vat_rate: Number(vatRate),
        max_amount: maxAmount ? Number(maxAmount) : null,
        max_monthly: maxMonthly ? Number(maxMonthly) : null,
        requires_receipt: requiresReceipt,
        active,
      }
      if (record) {
        await updateExpenseCategory(record.id, data)
      } else {
        await createExpenseCategory(data as any)
      }
      toast('success', tCommon('common.success'), tCommon('common.saved'))
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{record ? t('expenseCategories.edit') : t('expenseCategories.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label={t('expenseCategories.code')} value={code} onChange={(e) => setCode(e.target.value)} required />
          <Input label={t('expenseCategories.label')} value={label} onChange={(e) => setLabel(e.target.value)} required />
          <Input label={t('expenseCategories.accountCode')} value={accountCode} onChange={(e) => setAccountCode(e.target.value)} />
          <Input label={t('expenseCategories.vatRate')} type="number" value={vatRate} onChange={(e) => setVatRate(Number(e.target.value))} />
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('expenseCategories.maxAmount')} type="number" value={maxAmount} onChange={(e) => setMaxAmount(e.target.value)} />
            <Input label={t('expenseCategories.maxMonthly')} type="number" value={maxMonthly} onChange={(e) => setMaxMonthly(e.target.value)} />
          </div>
          <div className="flex gap-6">
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={requiresReceipt} onChange={(e) => setRequiresReceipt(e.target.checked)} />
              {t('expenseCategories.requiresReceipt')}
            </label>
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={active} onChange={(e) => setActive(e.target.checked)} />
              {t('expenseCategories.active')}
            </label>
          </div>
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
