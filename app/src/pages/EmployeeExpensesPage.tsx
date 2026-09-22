import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Badge } from '@/components/ui'
import { getMyExpenseReports, createMyExpenseReport, submitMyExpenseReport, deleteMyExpenseReport, getExpenseCategories, getExpenseReportLines, addExpenseReportLine } from '@/lib/queries/sprintDE'
import { formatDate, formatCurrency } from '@/lib/utils'
import { Receipt, Plus, X, Send, Trash2, ChevronRight } from 'lucide-react'
import { useToast } from '@/lib/toast'
import { confirmSync } from '@/lib/confirm'

const statusColors: Record<string, 'neutral' | 'warning' | 'success' | 'danger'> = {
  draft: 'neutral',
  submitted: 'warning',
  approved: 'success',
  rejected: 'danger',
  reimbursed: 'success',
}

export function EmployeeExpensesPage() {
  const { toast } = useToast()
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const [reports, setReports] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [selectedReport, setSelectedReport] = useState<any>(null)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const data = await getMyExpenseReports()
      setReports(data || [])
    } catch (err: any) {
      console.error(err)
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setLoading(false) }
  }, [toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  async function handleSubmit(id: string) {
    try { await submitMyExpenseReport(id); await loadData(); toast('success', tCommon('common.success'), tCommon('common.saved')) }
    catch (err: any) { toast('error', tCommon('common.error'), err.message) }
  }

  async function handleDelete(id: string) {
    if (!confirmSync(tCommon('form.confirmDelete'))) return
    try { await deleteMyExpenseReport(id); await loadData(); toast('success', tCommon('common.success'), tCommon('toast.deleted')) }
    catch (err: any) { toast('error', tCommon('common.error'), err.message) }
  }

  if (selectedReport) {
    return <ExpenseReportDetail report={selectedReport} onClose={() => { setSelectedReport(null); loadData() }} />
  }

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('groups.hr') }, { label: t('expenses.title') }]} />
      <PageHeader
        title={t('expenses.title')}
        subtitle={t('expenses.subtitle')}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('expenses.new')}</Button>}
      />

      {loading ? (
        <SkeletonTable rows={4} cols={5} />
      ) : reports.length === 0 ? (
        <EmptyState
          icon={<Receipt className="w-8 h-8" />}
          title={t('expenses.noRecords')}
          description={t('expenses.noRecordsDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('expenses.new')}</Button>}
        />
      ) : (
        <Card>
          <Table headers={[
            t('expenses.period'),
            t('expenses.amount'),
            t('expenses.status'),
            'Paie',
            t('expenses.submittedAt'),
            tCommon('table.actions'),
          ]}>
            {reports.map((r) => (
              <TableRow key={r.id} onClick={() => setSelectedReport(r)}>
                <TableCell className="text-sm font-medium">{r.period || '—'}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(r.total_ttc || 0)}</TableCell>
                <TableCell><Badge variant={statusColors[r.status] || 'neutral'}>{t(`expenses.statuses.${r.status}`)}</Badge></TableCell>
                <TableCell>{(r.payroll_integrated || r.payroll_variable_id) ? <Badge variant="success">Intégré</Badge> : <Badge variant="neutral">Non intégré</Badge>}</TableCell>
                <TableCell className="text-xs">{r.submitted_at ? formatDate(r.submitted_at) : '—'}</TableCell>
                <TableCell>
                  <div className="flex gap-1">
                    {r.status === 'draft' && (
                      <>
                        <button onClick={(e) => { e.stopPropagation(); handleSubmit(r.id) }} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-success)]" title={t('expenses.submit')}>
                          <Send className="w-4 h-4" />
                        </button>
                        <button onClick={(e) => { e.stopPropagation(); handleDelete(r.id) }} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" title={tCommon('actions.delete')}>
                          <Trash2 className="w-4 h-4" />
                        </button>
                      </>
                    )}
                    <ChevronRight className="w-4 h-4 text-[var(--color-text-secondary)]" />
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && (
        <ExpenseReportForm
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); loadData() }}
        />
      )}
    </div>
  )
}

function ExpenseReportForm({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [period, setPeriod] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await createMyExpenseReport({ period } as any)
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
          <h2 className="text-lg font-semibold">{t('expenses.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label={t('expenses.period')} type="month" value={period} onChange={(e) => setPeriod(e.target.value)} required />
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}

function ExpenseReportDetail({ report, onClose }: { report: any; onClose: () => void }) {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [lines, setLines] = useState<any[]>([])
  const [categories, setCategories] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showLineForm, setShowLineForm] = useState(false)
  const [categoryId, setCategoryId] = useState('')
  const [date, setDate] = useState('')
  const [amount, setAmount] = useState('')
  const [vatRate, setVatRate] = useState('20')
  const [description, setDescription] = useState('')
  const [savingLine, setSavingLine] = useState(false)

  const loadLines = useCallback(async () => {
    setLoading(true)
    try {
      const [l, cats] = await Promise.all([getExpenseReportLines(report.id), getExpenseCategories(true)])
      setLines(l || [])
      setCategories(cats || [])
    } catch (err: any) {
      console.error(err)
    toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadingError'))
    } finally { setLoading(false) }
  }, [report.id, tCommon, toast])

  useEffect(() => { loadLines() }, [loadLines])

  async function handleAddLine(e: React.FormEvent) {
    e.preventDefault()
    setSavingLine(true)
    try {
      const amountNum = Number(amount)
      const vatNum = Number(vatRate)
      const ht = amountNum / (1 + vatNum / 100)
      await addExpenseReportLine(report.id, {
        category_id: categoryId,
        date,
        amount_ht: ht,
        amount_ttc: amountNum,
        vat_rate: vatNum,
        description,
        ceiling_exceeded: false,
      } as any)
      toast('success', tCommon('common.success'), tCommon('common.saved'))
      setShowLineForm(false)
      setCategoryId(''); setDate(''); setAmount(''); setVatRate('20'); setDescription('')
      await loadLines()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setSavingLine(false) }
  }

  const totalTtc = lines.reduce((s, l) => s + (l.amount_ttc || 0), 0)

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h2 className="text-lg font-semibold">{t('expenses.title')} — {report.period}</h2>
          <p className="text-sm text-[var(--color-text-secondary)]">{t('expenses.totalTtc')}: {formatCurrency(totalTtc)}</p>
        </div>
        <Button variant="secondary" onClick={onClose}>{tCommon('actions.close')}</Button>
      </div>

      {report.status === 'draft' && (
        <div className="mb-4">
          <Button onClick={() => setShowLineForm(!showLineForm)}><Plus className="w-4 h-4" /> {t('expenses.addLine')}</Button>
        </div>
      )}

      {showLineForm && (
        <Card className="mb-4">
          <form onSubmit={handleAddLine} className="p-4 space-y-3">
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('expenses.category')}</label>
                <select className="input" value={categoryId} onChange={(e) => setCategoryId(e.target.value)} required>
                  <option value="">—</option>
                  {categories.map((c) => <option key={c.id} value={c.id}>{c.code} — {c.label}</option>)}
                </select>
              </div>
              <Input label={t('expenses.date')} type="date" value={date} onChange={(e) => setDate(e.target.value)} required />
              <Input label={t('expenses.amountTtc')} type="number" value={amount} onChange={(e) => setAmount(e.target.value)} required />
              <Input label={t('expenses.vatRate')} type="number" value={vatRate} onChange={(e) => setVatRate(e.target.value)} />
            </div>
            <Input label={t('expenses.description')} value={description} onChange={(e) => setDescription(e.target.value)} />
            <div className="flex justify-end gap-3">
              <Button type="button" variant="secondary" onClick={() => setShowLineForm(false)}>{tCommon('actions.cancel')}</Button>
              <Button type="submit" disabled={savingLine}>{savingLine ? '...' : tCommon('actions.save')}</Button>
            </div>
          </form>
        </Card>
      )}

      {loading ? (
        <SkeletonTable rows={3} cols={5} />
      ) : lines.length === 0 ? (
        <EmptyState icon={<Receipt className="w-8 h-8" />} title={t('expenses.noLines')} description={t('expenses.noLinesDescription')} />
      ) : (
        <Card>
          <Table headers={[
            t('expenses.date'),
            t('expenses.category'),
            t('expenses.description'),
            t('expenses.amountHt'),
            t('expenses.amountTtc'),
          ]}>
            {lines.map((l) => (
              <TableRow key={l.id}>
                <TableCell className="text-xs">{formatDate(l.date)}</TableCell>
                <TableCell className="text-sm">{l.expense_categories?.label || '—'}</TableCell>
                <TableCell className="text-sm">{l.description || '—'}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(l.amount_ht || 0)}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(l.amount_ttc || 0)}</TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}
    </div>
  )
}
