import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getLegalDeclarations, createLegalDeclaration, updateLegalDeclaration, deleteLegalDeclaration } from '@/lib/queries'
import { ShieldCheck, Plus, Trash2, X, Send } from 'lucide-react'
import type { LegalDeclaration } from '@/types'
import { useToast } from '@/lib/toast'

const typeLabels: Record<string, string> = { dsn: 'DSN', urssaf: 'URSSAF', dgt: 'DGT', ifrs: 'IFRS', other: 'Autre' }
const statusLabels: Record<string, string> = { pending: 'En attente', submitted: 'Transmise', late: 'En retard', cancelled: 'Annulée' }
const statusBadge: Record<string, 'neutral' | 'success' | 'warning' | 'danger'> = { pending: 'warning', submitted: 'success', late: 'danger', cancelled: 'neutral' }
const monthLabels = ['Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Jun', 'Jul', 'Aoû', 'Sep', 'Oct', 'Nov', 'Déc']

export function LegalDeclarationsPage() {
  const { toast } = useToast()
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
const [declarations, setDeclarations] = useState<LegalDeclaration[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [statusFilter, setStatusFilter] = useState('')

  const loadData = useCallback(async () => {
    try { setDeclarations(await getLegalDeclarations(statusFilter || undefined)) }
    catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [statusFilter])

  useEffect(() => { loadData() }, [loadData])

  async function handleSubmit(id: string) {
  try { await updateLegalDeclaration(id, { status: 'submitted', submission_date: new Date().toISOString().split('T')[0] }); await loadData() }
    catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
  }

  async function handleDelete(id: string) {
    if (!window.confirm(tCommon('form.confirmDelete'))) return
    try { await deleteLegalDeclaration(id); await loadData() }
    catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
  }

  const pendingCount = declarations.filter((d) => d.status === 'pending').length
  const lateCount = declarations.filter((d) => d.status === 'late').length

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.hr') }, { label: t('declarations.title') }]} />
      <PageHeader title={t('declarations.title')} subtitle={t('declarations.subtitle')}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('declarations.new')}</Button>} />

      <div className="grid grid-cols-3 gap-4 mb-6">
        <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">{t('declarations.statuses.pending')}</p><p className="text-2xl font-bold text-[var(--color-warning)]">{pendingCount}</p></div></Card>
        <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">{t('declarations.statuses.late')}</p><p className="text-2xl font-bold text-[var(--color-danger)]">{lateCount}</p></div></Card>
        <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">{t('declarations.statuses.submitted')}</p><p className="text-2xl font-bold text-[var(--color-success)]">{declarations.filter((d) => d.status === 'submitted').length}</p></div></Card>
      </div>

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-48">
          <Select label={t('declarations.status')} value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} options={[
            { value: '', label: tCommon('table.all') }, { value: 'pending', label: t('declarations.statuses.pending') }, { value: 'submitted', label: t('declarations.statuses.submitted') },
            { value: 'late', label: t('declarations.statuses.late') }, { value: 'cancelled', label: t('declarations.statuses.cancelled') },
          ]} />
        </div>
      </div>

      {loading ? <SkeletonTable rows={4} cols={6} /> : declarations.length === 0 ? (
        <EmptyState icon={<ShieldCheck className="w-8 h-8" />} title={t('declarations.noDeclarations')} description={t('declarations.noDeclarationsDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('declarations.new')}</Button>} />
      ) : (
        <Card>
          <Table headers={[t('payRuns.number'), t('declarations.type'), t('declarations.period'), t('declarations.dueDate'), t('declarations.amount'), t('declarations.status'), tCommon('table.actions')]}>
            {declarations.map((d) => (
              <TableRow key={d.id}>
                <TableCell className="font-mono text-xs">{d.number}</TableCell>
                <TableCell className="text-xs">{t(`declarations.types.${d.declaration_type}`) || typeLabels[d.declaration_type] || d.declaration_type}</TableCell>
                <TableCell className="text-xs">{monthLabels[d.period_month - 1]} {d.period_year}</TableCell>
                <TableCell className="text-xs">{formatDate(d.due_date)}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(d.amount))}</TableCell>
                <TableCell><Badge variant={statusBadge[d.status] || 'neutral'}>{t(`declarations.statuses.${d.status}`) || statusLabels[d.status] || d.status}</Badge></TableCell>
                <TableCell>
                  <div className="flex gap-1">
                    {d.status === 'pending' && (
                      <button onClick={() => handleSubmit(d.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-success)]" title={t('declarations.submit')}><Send className="w-4 h-4" /></button>
                    )}
                    <button onClick={() => handleDelete(d.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && <DeclarationForm onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function DeclarationForm({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const [declarationType, setDeclarationType] = useState('dsn')
  const { toast } = useToast()
  const [periodMonth, setPeriodMonth] = useState(new Date().getMonth() + 1)
  const [periodYear, setPeriodYear] = useState(new Date().getFullYear())
  const [dueDate, setDueDate] = useState('')
  const [amount, setAmount] = useState(0)
  const [notes, setNotes] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      const number = `${declarationType.toUpperCase()}-${periodYear}-${String(periodMonth).padStart(2, '0')}`
      await createLegalDeclaration({ number, declaration_type: declarationType as any, period_month: periodMonth, period_year: periodYear, due_date: dueDate, submission_date: null, amount, status: 'pending', notes: notes || null } as any)
      onSaved()
    } catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('declarations.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Select label={t('declarations.type')} value={declarationType} onChange={(e) => setDeclarationType(e.target.value)} options={[
            { value: 'dsn', label: t('declarations.types.dsn') }, { value: 'urssaf', label: t('declarations.types.urssaf') }, { value: 'dgt', label: 'DGT' },
            { value: 'ifrs', label: 'IFRS' }, { value: 'other', label: t('declarations.types.other') },
          ]} />
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('declarations.period')}</label>
              <select className="input" value={periodMonth} onChange={(e) => setPeriodMonth(Number(e.target.value))}>
                {monthLabels.map((m, i) => <option key={i} value={i + 1}>{m}</option>)}
              </select>
            </div>
            <Input label={t('declarations.period')} type="number" required value={periodYear} onChange={(e) => setPeriodYear(Number(e.target.value))} />
          </div>
          <Input label={t('declarations.dueDate')} type="date" required value={dueDate} onChange={(e) => setDueDate(e.target.value)} />
          <Input label={t('declarations.amount')} type="number" step="0.01" value={amount} onChange={(e) => setAmount(Number(e.target.value))} />
          <Input label={tCommon('common.notes')} value={notes} onChange={(e) => setNotes(e.target.value)} />
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
