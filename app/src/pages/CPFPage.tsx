import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { getCpfAccounts, createCpfAccount, deleteCpfAccount, getEmployees } from '@/lib/queries/payroll'
import { formatCurrency, formatDate } from '@/lib/utils'
import { Wallet, Plus, Trash2, X } from 'lucide-react'
import type { Employee, CpfAccount } from '@/types'
import { useToast } from '@/lib/toast'
import { confirmSync } from '@/lib/confirm'

export function CPFPage() {
  const { toast } = useToast()
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const [accounts, setAccounts] = useState<any[]>([])
  const [employees, setEmployees] = useState<Employee[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [filterEmp, setFilterEmp] = useState('')

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [cpfs, emps] = await Promise.all([getCpfAccounts(), getEmployees()])
      setAccounts(cpfs || [])
      setEmployees(emps || [])
    } catch (err: any) {
      console.error(err)
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setLoading(false) }
  }, [tCommon, toast])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
    if (!confirmSync(tCommon('form.confirmDelete'))) return
    try { await deleteCpfAccount(id); await loadData() }
    catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
  }

  const filtered = filterEmp ? accounts.filter((a) => a.employee_id === filterEmp) : accounts

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.hr') }, { label: t('cpf.title') }]} />
      <PageHeader
        title={t('cpf.title')}
        subtitle={t('cpf.subtitle')}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('cpf.new')}</Button>}
      />

      <div className="mb-4 flex items-end gap-3">
        <div className="w-64">
          <Select label={t('cpf.employee')} value={filterEmp} onChange={(e) => setFilterEmp(e.target.value)} options={[
            { value: '', label: tCommon('table.all') },
            ...employees.map((e) => ({ value: e.id, label: e.name })),
          ]} />
        </div>
        <span className="text-sm text-[var(--color-text-secondary)]">{filtered.length} {t('cpf.title').toLowerCase()}</span>
      </div>

      {loading ? (
        <SkeletonTable rows={4} cols={5} />
      ) : filtered.length === 0 ? (
        <EmptyState
          icon={<Wallet className="w-8 h-8" />}
          title={t('cpf.noAccounts')}
          description={t('cpf.noAccountsDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('cpf.new')}</Button>}
        />
      ) : (
        <Card>
          <Table headers={[
            t('cpf.employee'),
            t('cpf.balanceHours'),
            t('cpf.balanceAmount'),
            t('cpf.updatedAt'),
            tCommon('table.actions'),
          ]}>
            {filtered.map((a) => (
              <TableRow key={a.id}>
                <TableCell className="text-sm font-medium">
                  {a.employees ? `${a.employees.first_name} ${a.employees.last_name}` : '—'}
                </TableCell>
                <TableCell className="font-mono text-xs text-right">{a.balance_hours ?? 0}h</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(a.balance_amount) || 0)}</TableCell>
                <TableCell className="text-xs">{a.updated_at ? formatDate(a.updated_at) : '—'}</TableCell>
                <TableCell>
                  <button onClick={() => handleDelete(a.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                    <Trash2 className="w-4 h-4" />
                  </button>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && (
        <CpfForm
          employees={employees}
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); loadData() }}
        />
      )}
    </div>
  )
}

function CpfForm({ employees, onClose, onSaved }: { employees: Employee[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [employeeId, setEmployeeId] = useState('')
  const [balanceHours, setBalanceHours] = useState(0)
  const [balanceAmount, setBalanceAmount] = useState(0)
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!employeeId) { toast('error', tCommon('common.error'), t('cpf.selectEmployee')); return }
    setSaving(true)
    try {
      await createCpfAccount({
        employee_id: employeeId,
        balance_hours: balanceHours,
        balance_amount: balanceAmount,
        history: [],
      } as unknown as Omit<CpfAccount, 'id' | 'created_at' | 'updated_at'>)
      toast('success', tCommon('common.success'), tCommon('common.saved'))
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('cpf.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('cpf.employee')}</label>
            <select className="input" value={employeeId} onChange={(e) => setEmployeeId(e.target.value)} required>
              <option value="">{tCommon('form.selectPlaceholder') || '—'}</option>
              {employees.map((e) => <option key={e.id} value={e.id}>{e.name}</option>)}
            </select>
          </div>
          <Input label={t('cpf.balanceHours')} type="number" step="0.5" value={balanceHours} onChange={(e) => setBalanceHours(Number(e.target.value))} />
          <Input label={t('cpf.balanceAmount')} type="number" step="0.01" value={balanceAmount} onChange={(e) => setBalanceAmount(Number(e.target.value))} />
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
