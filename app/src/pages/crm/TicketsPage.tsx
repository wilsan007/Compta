import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Button, Table, TableRow, TableCell, Badge, EmptyState, Select, Input } from '@/components/ui'
import { getTickets, createTicket, updateTicketStatus, getCustomers } from '@/lib/queries'
import { useToast } from '@/lib/toast'
import { Plus, X, Ticket, CheckCircle } from 'lucide-react'
import type { ServiceTicket, Customer } from '@/types'

type TicketWithCustomer = ServiceTicket & { customer: { name: string } | null }

const CATEGORIES = ['technical', 'billing', 'delivery', 'product', 'other'] as const
const PRIORITIES = ['low', 'normal', 'high', 'urgent'] as const
const STATUSES = ['open', 'in_progress', 'waiting_customer', 'resolved', 'closed'] as const

export function TicketsPage() {
  const { t } = useTranslation('crm')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [tickets, setTickets] = useState<TicketWithCustomer[]>([])
  const [customers, setCustomers] = useState<Customer[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [filterStatus, setFilterStatus] = useState('')
  const [filterPriority, setFilterPriority] = useState('')

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const [tkData, custs] = await Promise.all([getTickets(), getCustomers()])
      setTickets(tkData || [])
      setCustomers(custs || [])
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { load() }, [load])

  const filtered = tickets.filter(tk => {
    if (filterStatus && tk.status !== filterStatus) return false
    if (filterPriority && tk.priority !== filterPriority) return false
    return true
  })

  async function handleStatusChange(id: string, status: string) {
    try {
      await updateTicketStatus(id, status)
      toast('success', tCommon('toast.success'), tCommon('toast.updated'))
      await load()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    }
  }

  function getPriorityBadge(priority: string): 'neutral' | 'warning' | 'danger' | 'success' {
    if (priority === 'urgent') return 'danger'
    if (priority === 'high') return 'warning'
    if (priority === 'low') return 'success'
    return 'neutral'
  }

  function getStatusBadge(status: string): 'neutral' | 'warning' | 'success' | 'danger' {
    if (status === 'closed' || status === 'resolved') return 'success'
    if (status === 'in_progress') return 'warning'
    if (status === 'waiting_customer') return 'neutral'
    return 'danger'
  }

  return (
    <div className="p-6 max-w-7xl mx-auto">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <Ticket className="w-6 h-6 text-[var(--color-primary)]" />
            {t('tickets.title')}
          </h1>
          <p className="text-sm text-[var(--color-text-secondary)] mt-1">{t('tickets.subtitle')}</p>
        </div>
        <Button onClick={() => setShowForm(true)}>
          <Plus className="w-4 h-4" /> {t('tickets.new')}
        </Button>
      </div>

      <div className="flex items-center gap-4 mb-4">
        <Select value={filterStatus} onChange={(e) => setFilterStatus(e.target.value)} options={[
          { value: '', label: tCommon('filters.all') },
          ...STATUSES.map(s => ({ value: s, label: t(`tickets.${s}`) })),
        ]} />
        <Select value={filterPriority} onChange={(e) => setFilterPriority(e.target.value)} options={[
          { value: '', label: tCommon('filters.all') },
          ...PRIORITIES.map(p => ({ value: p, label: t(`tickets.${p}`) })),
        ]} />
      </div>

      {loading ? (
        <div className="space-y-2">{[1, 2, 3].map(i => <div key={i} className="h-12 rounded animate-pulse bg-[var(--color-neutral-100)]" />)}</div>
      ) : filtered.length === 0 ? (
        <EmptyState icon={<Ticket className="w-8 h-8" />} title={t('tickets.noTickets')} description={t('tickets.noTicketsDescription')} />
      ) : (
        <Table headers={[t('tickets.number'), t('tickets.subject'), t('tickets.customer'), t('tickets.category'), t('tickets.priority'), t('tickets.status'), tCommon('table.actions')]}>
          {filtered.map(tk => (
            <TableRow key={tk.id}>
              <TableCell className="font-mono text-xs">{tk.number}</TableCell>
              <TableCell className="font-medium">{tk.subject}</TableCell>
              <TableCell className="text-xs">{tk.customer?.name || '-'}</TableCell>
              <TableCell className="text-xs">{tk.category ? t(`tickets.${tk.category}`) : '-'}</TableCell>
              <TableCell><Badge variant={getPriorityBadge(tk.priority)}>{t(`tickets.${tk.priority}`)}</Badge></TableCell>
              <TableCell><Badge variant={getStatusBadge(tk.status)}>{t(`tickets.${tk.status}`)}</Badge></TableCell>
              <TableCell>
                {tk.status !== 'closed' && tk.status !== 'resolved' && (
                  <button onClick={() => handleStatusChange(tk.id, 'resolved')} className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-success)]" title={t('tickets.resolved')}>
                    <CheckCircle className="w-4 h-4" />
                  </button>
                )}
              </TableCell>
            </TableRow>
          ))}
        </Table>
      )}

      {showForm && <TicketForm customers={customers} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); load() }} />}
    </div>
  )
}

function TicketForm({ customers, onClose, onSaved }: { customers: Customer[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('crm')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [customerId, setCustomerId] = useState('')
  const [subject, setSubject] = useState('')
  const [description, setDescription] = useState('')
  const [category, setCategory] = useState<ServiceTicket['category']>('technical')
  const [priority, setPriority] = useState<ServiceTicket['priority']>('normal')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!subject || !customerId) return
    setSaving(true)
    try {
      const num = `TK-${Date.now().toString().slice(-6)}`
      await createTicket({
        tenant_id: null,
        number: num,
        customer_id: customerId,
        contact_id: null,
        subject,
        description: description || null,
        category,
        priority,
        status: 'open',
        assigned_to: null,
        sla_due_date: null,
        first_response_at: null,
        resolved_at: null,
        closed_at: null,
        satisfaction_rating: null,
        satisfaction_comment: null,
        tags: null,
      })
      toast('success', tCommon('toast.success'), tCommon('toast.created'))
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('tickets.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Select label={t('tickets.customer')} required value={customerId} onChange={(e) => setCustomerId(e.target.value)} options={[
            { value: '', label: tCommon('select.choose') },
            ...customers.map(c => ({ value: c.id, label: c.name })),
          ]} />
          <Input label={t('tickets.subject')} required value={subject} onChange={(e) => setSubject(e.target.value)} />
          <Input label={t('tickets.description')} value={description} onChange={(e) => setDescription(e.target.value)} />
          <div className="grid grid-cols-2 gap-4">
            <Select label={t('tickets.category')} value={category || ''} onChange={(e) => setCategory(e.target.value as any)} options={CATEGORIES.map(c => ({ value: c, label: t(`tickets.${c}`) }))} />
            <Select label={t('tickets.priority')} value={priority} onChange={(e) => setPriority(e.target.value as any)} options={PRIORITIES.map(p => ({ value: p, label: t(`tickets.${p}`) }))} />
          </div>
          <div className="flex justify-end gap-3 pt-2 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
