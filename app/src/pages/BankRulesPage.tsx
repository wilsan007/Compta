import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { getBankRules, createBankRule, updateBankRule, deleteBankRule } from '@/lib/queries'
import { Plus, Trash2, X, Power, PowerOff } from 'lucide-react'
import type { BankRule } from '@/types'
import { useToast } from '@/lib/toast'
import { useLegislation } from '@/lib/legislation'

export function BankRulesPage() {
  const { toast } = useToast()
  const { t } = useTranslation('banking')
  const { t: tCommon } = useTranslation('common')
const [rules, setRules] = useState<BankRule[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      setRules(await getBankRules())
    } catch (err) {
      console.error('Failed to load rules:', err)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleToggle(id: string, current: boolean) {
  try {
      await updateBankRule(id, { active: !current })
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.updateError'))
    }
  }

  async function handleDelete(id: string) {
    if (!window.confirm(tCommon('form.confirmDelete'))) return
    try {
      await deleteBankRule(id)
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.deleteError'))
    }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('rules.title') }]} />
      <PageHeader
        title={t('rules.title')}
        subtitle={t('rules.subtitle')}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('rules.new')}</Button>}
      />

      {loading ? (
        <SkeletonTable rows={4} cols={5} />
      ) : rules.length === 0 ? (
        <EmptyState
          icon={<Power className="w-8 h-8" />}
          title={t('rules.noRules')}
          description={t('rules.noRulesDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('rules.new')}</Button>}
        />
      ) : (
        <Card>
          <Table headers={[t('rules.name'), t('rules.condition'), t('rules.category'), t('rules.priority'), tCommon('common.status'), tCommon('table.actions')]}>
            {rules.map((r) => (
              <TableRow key={r.id}>
                <TableCell className="font-medium">{r.name}</TableCell>
                <TableCell className="text-xs">
                  {r.condition_field} {r.condition_operator} "{r.condition_value}"
                </TableCell>
                <TableCell className="text-xs">{r.action_category} ({r.action_account_code || '—'})</TableCell>
                <TableCell className="font-mono text-xs">{r.priority}</TableCell>
                <TableCell>
                  <Badge variant={r.active ? 'success' : 'neutral'}>
                    {r.active ? tCommon('status.active') : tCommon('status.inactive')}
                  </Badge>
                </TableCell>
                <TableCell>
                  <div className="flex items-center gap-1">
                    <button onClick={() => handleToggle(r.id, r.active)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)]" title={r.active ? tCommon('actions.disable') : tCommon('actions.enable')}>
                      {r.active ? <PowerOff className="w-4 h-4 text-[var(--color-danger)]" /> : <Power className="w-4 h-4 text-[var(--color-success)]" />}
                    </button>
                    <button onClick={() => handleDelete(r.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
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
        <RuleForm onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />
      )}
    </div>
  )
}

function RuleForm({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const [name, setName] = useState('')
  const { toast } = useToast()
  const { t } = useTranslation('banking')
  const { t: tCommon } = useTranslation('common')
  const [conditionField, setConditionField] = useState('description')
  const [conditionOperator, setConditionOperator] = useState('contains')
  const [conditionValue, setConditionValue] = useState('')
  const [actionCategory, setActionCategory] = useState('')
  const [actionAccountCode, setActionAccountCode] = useState('')
  const { defaultVatRate } = useLegislation()
  const [actionVatRate, setActionVatRate] = useState(defaultVatRate)
  const [priority, setPriority] = useState(1)
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await createBankRule({
        name, condition_field: conditionField, condition_operator: conditionOperator,
        condition_value: conditionValue, action_category: actionCategory,
        action_account_code: actionAccountCode, action_vat_rate: actionVatRate,
        priority, active: true,
      } as any)
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.createError'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('rules.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label={t('rules.name')} required value={name} onChange={(e) => setName(e.target.value)} />
          <div className="grid grid-cols-3 gap-4">
            <Select label={t('rules.field')} value={conditionField} onChange={(e) => setConditionField(e.target.value)} options={[
              { value: 'description', label: t('rules.fields.description') },
              { value: 'reference', label: t('rules.fields.reference') },
              { value: 'amount', label: t('rules.fields.amount') },
            ]} />
            <Select label={t('rules.operator')} value={conditionOperator} onChange={(e) => setConditionOperator(e.target.value)} options={[
              { value: 'contains', label: t('rules.operators.contains') },
              { value: 'equals', label: t('rules.operators.equals') },
              { value: 'starts_with', label: t('rules.operators.starts_with') },
              { value: 'greater_than', label: t('rules.operators.greater_than') },
              { value: 'less_than', label: t('rules.operators.less_than') },
            ]} />
            <Input label={t('rules.value')} required value={conditionValue} onChange={(e) => setConditionValue(e.target.value)} />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('rules.category')} required value={actionCategory} onChange={(e) => setActionCategory(e.target.value)} placeholder={t('rules.categoryPlaceholder')} />
            <Input label={t('rules.accountCode')} value={actionAccountCode} onChange={(e) => setActionAccountCode(e.target.value)} placeholder={t('rules.accountCodePlaceholder')} />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('rules.vatRate')} type="number" step="0.01" value={actionVatRate} onChange={(e) => setActionVatRate(Number(e.target.value))} />
            <Input label={t('rules.priority')} type="number" value={priority} onChange={(e) => setPriority(Number(e.target.value))} />
          </div>
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : tCommon('actions.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
