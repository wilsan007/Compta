import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getCollectionDashboard, createCollectionReminder, getCustomers } from '@/lib/queries'
import { AlertTriangle, Plus, X, Mail } from 'lucide-react'
import type { Customer } from '@/types'
import { useToast } from '@/lib/toast'

export function CollectionDashboardPage() {
  const { t } = useTranslation('treasury')
const [data, setData] = useState<any>(null)
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [customers, setCustomers] = useState<Customer[]>([])

  useEffect(() => { load() }, [])

  async function load() {
    try {
      const [res, custs] = await Promise.all([getCollectionDashboard(), getCustomers()])
      setData(res)
      setCustomers(custs || [])
    } catch (err) {
      console.error('Error loading collection dashboard:', err)
    } finally {
      setLoading(false)
    }
  }

  if (loading) {
    return (
      <div>
        <Breadcrumb items={[{ label: t('title') }, { label: t('collections.title') }]} />
        <PageHeader title={t('collections.title')} subtitle={t('dashboard.subtitle')} />
        <SkeletonTable rows={6} cols={6} />
      </div>
    )
  }

  const { overdueInvoices, totalOverdue, totalDue, reminders } = data || {}

  const buckets = [
    { label: '0-30j', count: 0, amount: 0 },
    { label: '31-60j', count: 0, amount: 0 },
    { label: '61-90j', count: 0, amount: 0 },
    { label: '>90j', count: 0, amount: 0 },
  ]

  for (const inv of overdueInvoices || []) {
    const d = inv.daysOverdue
    if (d <= 30) { buckets[0].count++; buckets[0].amount += Number(inv.total) }
    else if (d <= 60) { buckets[1].count++; buckets[1].amount += Number(inv.total) }
    else if (d <= 90) { buckets[2].count++; buckets[2].amount += Number(inv.total) }
    else { buckets[3].count++; buckets[3].amount += Number(inv.total) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('collections.title') }]} />
      <PageHeader
        title={t('collections.title')}
        subtitle={t('collections.subtitle')}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('collections.new')}</Button>}
      />

      <div className="grid grid-cols-4 gap-4 mb-6">
        <Card>
          <div className="p-4">
            <p className="text-sm text-[var(--color-text-secondary)] mb-1">{t('collections.totalDue')}</p>
            <p className="text-2xl font-bold font-mono">{formatCurrency(totalDue || 0)}</p>
          </div>
        </Card>
        <Card>
          <div className="p-4">
            <p className="text-sm text-[var(--color-text-secondary)] mb-1 flex items-center gap-1"><AlertTriangle className="w-4 h-4 text-[var(--color-danger)]" /> {t('collections.overdue')}</p>
            <p className="text-2xl font-bold font-mono text-[var(--color-danger)]">{formatCurrency(totalOverdue || 0)}</p>
          </div>
        </Card>
        <Card>
          <div className="p-4">
            <p className="text-sm text-[var(--color-text-secondary)] mb-1">{t('collections.pendingInvoices')}</p>
            <p className="text-2xl font-bold">{overdueInvoices?.length || 0}</p>
          </div>
        </Card>
        <Card>
          <div className="p-4">
            <p className="text-sm text-[var(--color-text-secondary)] mb-1">{t('collections.remindersSent')}</p>
            <p className="text-2xl font-bold">{reminders?.length || 0}</p>
          </div>
        </Card>
      </div>

      <div className="grid grid-cols-4 gap-4 mb-6">
        {buckets.map((b) => (
          <Card key={b.label}>
            <div className="p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{b.label}</p>
              <p className="text-lg font-bold font-mono">{formatCurrency(b.amount)}</p>
              <p className="text-xs text-[var(--color-text-secondary)] mt-1">{t('collections.invoiceCount', { count: b.count })}</p>
            </div>
          </Card>
        ))}
      </div>

      <div className="grid grid-cols-2 gap-6">
        <Card title={t('collections.unpaidInvoices')}>
          {(overdueInvoices || []).length === 0 ? (
            <EmptyState icon={<AlertTriangle className="w-8 h-8" />} title={t('collections.noUnpaid')} description={t('collections.noUnpaidDesc')} />
          ) : (
            <Table headers={[t('collections.number'), t('collections.customer'), t('collections.amount'), t('collections.dueDate'), t('collections.daysLate')]}>
              {(overdueInvoices || []).slice(0, 15).map((inv: any) => (
                <TableRow key={inv.id}>
                  <TableCell className="font-mono text-xs">{inv.number}</TableCell>
                  <TableCell className="text-sm">{inv.customer_name}</TableCell>
                  <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(inv.total))}</TableCell>
                  <TableCell className="text-xs">{formatDate(inv.due_date)}</TableCell>
                  <TableCell className={`text-xs font-semibold ${inv.daysOverdue > 0 ? 'text-[var(--color-danger)]' : 'text-[var(--color-text-secondary)]'}`}>
                    {inv.daysOverdue > 0 ? `${inv.daysOverdue} ${t('collections.days')}` : '—'}
                  </TableCell>
                </TableRow>
              ))}
            </Table>
          )}
        </Card>

        <Card title={t('collections.recentReminders')}>
          {(reminders || []).length === 0 ? (
            <EmptyState icon={<Mail className="w-8 h-8" />} title={t('collections.noReminders')} description={t('collections.noRemindersDesc')} />
          ) : (
            <Table headers={[t('collections.number'), t('collections.level'), t('collections.date'), t('collections.amount'), t('collections.status')]}>
              {(reminders || []).slice(0, 10).map((r: any) => (
                <TableRow key={r.id}>
                  <TableCell className="font-mono text-xs">{r.number}</TableCell>
                  <TableCell className="text-xs">{r.reminder_level === 1 ? t('collections.reminderLevel1') : r.reminder_level === 2 ? t('collections.reminderLevel2') : r.reminder_level === 3 ? t('collections.reminderLevel3') : t('collections.levelN', { level: r.reminder_level })}</TableCell>
                  <TableCell className="text-xs">{formatDate(r.reminder_date)}</TableCell>
                  <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(r.amount))}</TableCell>
                  <TableCell>
                    <Badge variant={r.status === 'paid' ? 'success' : r.status === 'cancelled' ? 'danger' : 'warning'}>
                      {r.status === 'paid' ? t('collections.statusPaid') : r.status === 'cancelled' ? t('collections.statusCancelled') : r.status === 'draft' ? t('collections.statusDraft') : t('collections.statusSent')}
                    </Badge>
                  </TableCell>
                </TableRow>
              ))}
            </Table>
          )}
        </Card>
      </div>

      {showForm && (
        <ReminderForm customers={customers} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); load() }} />
      )}
    </div>
  )
}

function ReminderForm({ customers, onClose, onSaved }: { customers: Customer[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('treasury')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
const [customerId, setCustomerId] = useState('')
  const [reminderLevel, setReminderLevel] = useState<1 | 2 | 3>(1)
  const [amount, setAmount] = useState(0)
  const [reminderDate, setReminderDate] = useState(new Date().toISOString().split('T')[0])
  const [dueDate, setDueDate] = useState('')
  const [notes, setNotes] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      const number = `REL-${new Date().getFullYear()}-${String(Date.now()).slice(-6)}`
      await createCollectionReminder({
        number, customer_id: customerId || null, third_party_id: null, invoice_id: null,
        reminder_level: reminderLevel, reminder_date: reminderDate,
        due_date: dueDate || null, amount, status: 'draft', notes: notes || null,
      } as any)
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('error'), err.message || tCommon('error'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('collections.form.title')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('collections.form.customer')}</label>
            <select className="input" value={customerId} onChange={(e) => setCustomerId(e.target.value)} required>
              <option value="">{t('collections.form.selectPlaceholder')}</option>
              {customers.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
          </div>
          <Select label={t('collections.form.reminderLevel')} value={String(reminderLevel)} onChange={(e) => setReminderLevel(Number(e.target.value) as 1 | 2 | 3)} options={[
            { value: '1', label: t('collections.reminderLevel1') },
            { value: '2', label: t('collections.reminderLevel2') },
            { value: '3', label: t('collections.reminderLevel3') },
          ]} />
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('collections.form.amount')} type="number" step="0.01" required value={amount} onChange={(e) => setAmount(Number(e.target.value))} />
            <Input label={t('collections.form.reminderDate')} type="date" required value={reminderDate} onChange={(e) => setReminderDate(e.target.value)} />
          </div>
          <Input label={t('collections.form.dueDate')} type="date" value={dueDate} onChange={(e) => setDueDate(e.target.value)} />
          <Input label={t('collections.form.notes')} value={notes} onChange={(e) => setNotes(e.target.value)} />
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>{t('collections.form.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : t('collections.form.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
