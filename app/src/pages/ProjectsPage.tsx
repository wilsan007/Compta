import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { getProjects, createProject, updateProject, deleteProject } from '@/lib/queries/accounting'
import { getCustomers } from '@/lib/queries/partners'
import { calculateProjectProfitability } from '@/lib/queries/businessFunctions'
import { formatCurrency } from '@/lib/utils'
import { FolderKanban, Plus, Trash2, X, Calculator } from 'lucide-react'
import type { Project, Customer } from '@/types'
import { useToast } from '@/lib/toast'
import { useStatusLabels } from '@/lib/statusUtils'
import { confirmSync } from '@/lib/confirm'

export function ProjectsPage() {
  const { toast } = useToast()
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { getStatusLabel } = useStatusLabels()
const [projects, setProjects] = useState<Project[]>([])
  const [customers, setCustomers] = useState<Customer[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [p, c] = await Promise.all([getProjects(), getCustomers()])
      setProjects(p)
      setCustomers(c)
    } catch (err: any) { console.error('Failed to load projects:', err)
    toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError'))
    } finally {
      setLoading(false)
    }
  }, [tCommon, toast])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
  if (!confirmSync(t('projects.deleteConfirm'))) return
    try {
      await deleteProject(id)
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    }
  }

  async function handleStatusChange(id: string, status: string) {
    try {
      await updateProject(id, { status: status as any })
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    }
  }

  async function handleProfitability(id: string) {
    try {
      const r: any = await calculateProjectProfitability(id)
      const eac = Number(r?.eac ?? 0)
      const etc = Number(r?.etc ?? 0)
      const cpi = Number(r?.cpi ?? 0)
      const margin = Number(r?.margin ?? 0)
      toast('success', t('projects.title'), `EAC: ${formatCurrency(eac)} • ETC: ${formatCurrency(etc)} • CPI: ${cpi.toFixed(2)} • ${t('projects.profitability')}: ${formatCurrency(margin)}`)
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('projects.title') }]} />
      <PageHeader
        title={t('projects.title')}
        subtitle={t('projects.subtitle')}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('projects.new')}</Button>}
      />

      {loading ? (
        <SkeletonTable rows={4} cols={6} />
      ) : projects.length === 0 ? (
        <EmptyState
          icon={<FolderKanban className="w-8 h-8" />}
          title={t('projects.noProjects')}
          description={t('projects.noProjectsDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('projects.new')}</Button>}
        />
      ) : (
        <Card>
          <Table headers={[t('projects.name'), t('projects.customerName'), t('projects.budget'), t('projects.actualCost'), t('projects.profitability'), t('projects.status'), tCommon('actions')]}>
            {projects.map((p) => {
              const customerName = customers.find(c => c.id === p.customer_id)?.name || t('projects.noCustomer')
              const profit = Number(p.budget) - Number(p.actual_cost)
              const margin = Number(p.budget) > 0 ? (profit / Number(p.budget)) * 100 : 0
              return (
                <TableRow key={p.id}>
                  <TableCell className="font-medium">{p.name}</TableCell>
                  <TableCell className="text-sm">{customerName}</TableCell>
                  <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(p.budget))}</TableCell>
                  <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(p.actual_cost))}</TableCell>
                  <TableCell className="text-right">
                    <span className={`font-mono text-xs font-bold ${profit >= 0 ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>
                      {formatCurrency(profit)} ({margin.toFixed(1)}%)
                    </span>
                  </TableCell>
                  <TableCell>
                    <select
                      value={p.status}
                      onChange={(e) => handleStatusChange(p.id, e.target.value)}
                      className="text-xs border border-[var(--color-border)] rounded px-2 py-1 bg-[var(--color-surface)]"
                    >
                      {['active', 'completed', 'on_hold', 'cancelled'].map((k) => <option key={k} value={k}>{getStatusLabel(k)}</option>)}
                    </select>
                  </TableCell>
                  <TableCell>
                    <div className="flex items-center gap-1">
                      <button onClick={() => handleProfitability(p.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-info)]" title={t('projects.profitability')}>
                        <Calculator className="w-4 h-4" />
                      </button>
                      <button onClick={() => handleDelete(p.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </div>
                  </TableCell>
                </TableRow>
              )
            })}
          </Table>
        </Card>
      )}

      {showForm && (
        <ProjectForm customers={customers} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />
      )}
    </div>
  )
}

function ProjectForm({ customers, onClose, onSaved }: { customers: Customer[]; onClose: () => void; onSaved: () => void }) {
  const [name, setName] = useState('')
  const { toast } = useToast()
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const [description, setDescription] = useState('')
  const [customerId, setCustomerId] = useState('')
  const [budget, setBudget] = useState(0)
  const [startDate, setStartDate] = useState(new Date().toISOString().split('T')[0])
  const [endDate, setEndDate] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await createProject({
        name, description, customer_id: customerId || null,
        status: 'active', budget, actual_cost: 0,
        start_date: startDate, end_date: endDate || null,
      } as any)
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('projects.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label={t('projects.name')} required value={name} onChange={(e) => setName(e.target.value)} />
          <Input label={t('projects.description')} value={description} onChange={(e) => setDescription(e.target.value)} />
          <Select label={t('projects.customer')} value={customerId} onChange={(e) => setCustomerId(e.target.value)} options={[
            { value: '', label: t('projects.noCustomer') },
            ...customers.map(c => ({ value: c.id, label: c.name })),
          ]} />
          <div className="grid grid-cols-3 gap-4">
            <Input label={t('projects.budget')} type="number" step="0.01" value={budget} onChange={(e) => setBudget(Number(e.target.value))} />
            <Input label={t('projects.startDate')} type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)} />
            <Input label={t('projects.endDate')} type="date" value={endDate} onChange={(e) => setEndDate(e.target.value)} />
          </div>
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{t('projects.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : t('projects.createBtn')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
