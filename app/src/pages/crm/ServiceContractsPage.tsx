import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Button, Table, TableRow, TableCell, Badge, EmptyState, Select, Input } from '@/components/ui'
import { formatDate } from '@/lib/utils'
import { getServiceContracts, createServiceContract, deleteServiceContract } from '@/lib/queries/crmAdvanced'
import { getCustomers } from '@/lib/queries/partners'
import { useToast } from '@/lib/toast'
import { Plus, X, FileText, Trash2 } from 'lucide-react'
import type { ServiceContract, Customer } from '@/types'
import { nextDocumentNumber } from '@/lib/queries/core'

type ContractWithCustomer = ServiceContract & { customer: { name: string } | null }

const CONTRACT_TYPES = ['support', 'maintenance', 'warranty', 'sla'] as const

export function ServiceContractsPage() {
  const { t } = useTranslation('crm')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [contracts, setContracts] = useState<ContractWithCustomer[]>([])
  const [customers, setCustomers] = useState<Customer[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const [cData, custs] = await Promise.all([getServiceContracts(), getCustomers()])
      setContracts(cData || [])
      setCustomers(custs || [])
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    } finally {
      setLoading(false)
    }
  }, [tCommon, toast])

  useEffect(() => { load() }, [load])

  async function handleDelete(id: string) {
    try {
      await deleteServiceContract(id)
      toast('success', tCommon('toast.success'), tCommon('toast.deleted'))
      await load()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    }
  }

  function getStatusBadge(status: string): 'success' | 'danger' | 'neutral' | 'warning' {
    if (status === 'active') return 'success'
    if (status === 'expired') return 'danger'
    if (status === 'terminated') return 'warning'
    return 'neutral'
  }

  return (
    <div className="p-6 max-w-7xl mx-auto">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <FileText className="w-6 h-6 text-[var(--color-primary)]" />
            {t('contracts.title')}
          </h1>
          <p className="text-sm text-[var(--color-text-secondary)] mt-1">{t('contracts.subtitle')}</p>
        </div>
        <Button onClick={() => setShowForm(true)}>
          <Plus className="w-4 h-4" /> {t('contracts.new')}
        </Button>
      </div>

      {loading ? (
        <div className="space-y-2">{[1, 2, 3].map(i => <div key={i} className="h-12 rounded animate-pulse bg-[var(--color-neutral-100)]" />)}</div>
      ) : contracts.length === 0 ? (
        <EmptyState icon={<FileText className="w-8 h-8" />} title={t('contracts.noContracts')} description={t('contracts.noContractsDescription')} />
      ) : (
        <Table headers={[t('contracts.number'), t('contracts.name'), t('contracts.customer'), t('contracts.type'), t('contracts.startDate'), t('contracts.endDate'), t('contracts.status'), t('contracts.usedTickets'), tCommon('table.actions')]}>
          {contracts.map(c => (
            <TableRow key={c.id}>
              <TableCell className="font-mono text-xs">{c.number}</TableCell>
              <TableCell className="font-medium">{c.name}</TableCell>
              <TableCell className="text-xs">{c.customer?.name || '-'}</TableCell>
              <TableCell className="text-xs">{c.contract_type ? t(`contracts.${c.contract_type}`) : '-'}</TableCell>
              <TableCell className="text-xs">{formatDate(c.start_date)}</TableCell>
              <TableCell className="text-xs">{c.end_date ? formatDate(c.end_date) : '-'}</TableCell>
              <TableCell><Badge variant={getStatusBadge(c.status)}>{t(`contracts.${c.status}`)}</Badge></TableCell>
              <TableCell className="font-mono text-xs">{c.used_tickets}/{c.max_tickets || '∞'}</TableCell>
              <TableCell>
                <button onClick={() => handleDelete(c.id)} className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                  <Trash2 className="w-4 h-4" />
                </button>
              </TableCell>
            </TableRow>
          ))}
        </Table>
      )}

      {showForm && <ContractForm customers={customers} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); load() }} />}
    </div>
  )
}

function ContractForm({ customers, onClose, onSaved }: { customers: Customer[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('crm')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [customerId, setCustomerId] = useState('')
  const [name, setName] = useState('')
  const [contractType, setContractType] = useState<ServiceContract['contract_type']>('support')
  const [startDate, setStartDate] = useState(new Date().toISOString().split('T')[0])
  const [endDate, setEndDate] = useState('')
  const [slaResponse, setSlaResponse] = useState(24)
  const [slaResolution, setSlaResolution] = useState(48)
  const [coverage, setCoverage] = useState<'business_hours' | '24_7'>('business_hours')
  const [maxTickets, setMaxTickets] = useState(0)
  const [amount, setAmount] = useState(0)
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!name || !customerId || !startDate) return
    setSaving(true)
    try {
      const num = await nextDocumentNumber('SC')
      await createServiceContract({
        tenant_id: null,
        number: num,
        customer_id: customerId,
        name,
        contract_type: contractType,
        start_date: startDate,
        end_date: endDate || null,
        status: 'active',
        sla_response_hours: slaResponse,
        sla_resolution_hours: slaResolution,
        coverage,
        max_tickets: maxTickets || null,
        used_tickets: 0,
        amount: amount || null,
        notes: null,
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
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('contracts.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Select label={t('contracts.customer')} required value={customerId} onChange={(e) => setCustomerId(e.target.value)} options={[
            { value: '', label: tCommon('select.choose') },
            ...customers.map(c => ({ value: c.id, label: c.name })),
          ]} />
          <Input label={t('contracts.name')} required value={name} onChange={(e) => setName(e.target.value)} />
          <Select label={t('contracts.type')} value={contractType || ''} onChange={(e) => setContractType(e.target.value as any)} options={CONTRACT_TYPES.map(tp => ({ value: tp, label: t(`contracts.${tp}`) }))} />
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('contracts.startDate')} type="date" required value={startDate} onChange={(e) => setStartDate(e.target.value)} />
            <Input label={t('contracts.endDate')} type="date" value={endDate} onChange={(e) => setEndDate(e.target.value)} />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('contracts.slaResponse')} type="number" value={slaResponse} onChange={(e) => setSlaResponse(Number(e.target.value))} />
            <Input label={t('contracts.slaResolution')} type="number" value={slaResolution} onChange={(e) => setSlaResolution(Number(e.target.value))} />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Select label={t('contracts.coverage')} value={coverage || ''} onChange={(e) => setCoverage(e.target.value as any)} options={[
              { value: 'business_hours', label: t('contracts.businessHours') },
              { value: '24_7', label: t('contracts.24_7') },
            ]} />
            <Input label={t('contracts.maxTickets')} type="number" value={maxTickets} onChange={(e) => setMaxTickets(Number(e.target.value))} />
          </div>
          <Input label={t('contracts.amount')} type="number" step="0.01" value={amount} onChange={(e) => setAmount(Number(e.target.value))} />
          <div className="flex justify-end gap-3 pt-2 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
