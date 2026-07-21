import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input } from '@/components/ui'
import { getBankReconciliationRules, createBankReconciliationRule, deleteBankReconciliationRule } from '@/lib/queries'
import { Plus, Trash2, Zap } from 'lucide-react'
import type { BankReconciliationRule } from '@/types'
import { useToast } from '@/lib/toast'

export function BankReconciliationRulesPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [rules, setRules] = useState<BankReconciliationRule[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const data = await getBankReconciliationRules()
      setRules(data || [])
    } catch (err) {
      console.error('Failed to load bank recon rules:', err)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
    if (!window.confirm(t('bankRecon.deleteConfirm'))) return
    try {
      await deleteBankReconciliationRule(id)
      toast('success', tCommon('common.success'), t('bankRecon.deleteSuccess'))
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    }
  }

  const tableHeaders = [t('bankRecon.name'), t('bankRecon.afbCode'), t('bankRecon.counterpart'), t('bankRecon.priority'), t('bankRecon.status'), tCommon('common.table.actions')]

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb') }, { label: t('treatment.breadcrumb') }, { label: t('bankRecon.breadcrumb') }]} />
      <PageHeader
        title={t('bankRecon.title')}
        subtitle={t('bankRecon.subtitle')}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('bankRecon.new')}</Button>}
      />

      {loading ? (
        <SkeletonTable rows={4} cols={6} />
      ) : rules.length === 0 ? (
        <EmptyState
          icon={<Zap className="w-8 h-8" />}
          title={t('bankRecon.noRules')}
          description={t('bankRecon.noRulesDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('bankRecon.new')}</Button>}
        />
      ) : (
        <Card>
          <Table headers={tableHeaders}>
            {rules.map((rule) => (
              <TableRow key={rule.id}>
                <TableCell className="font-medium text-sm">{rule.name}</TableCell>
                <TableCell className="font-mono text-xs">{rule.afb_code}</TableCell>
                <TableCell className="font-mono text-xs">{rule.counterpart_account || '—'}</TableCell>
                <TableCell className="text-center text-xs">{rule.priority}</TableCell>
                <TableCell>
                  <Badge variant={rule.active ? 'success' : 'neutral'}>{rule.active ? t('bankRecon.active') : t('bankRecon.inactive')}</Badge>
                </TableCell>
                <TableCell>
                  <button onClick={() => handleDelete(rule.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                    <Trash2 className="w-4 h-4" />
                  </button>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && <RuleForm onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function RuleForm({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [name, setName] = useState('')
  const [afbCode, setAfbCode] = useState('')
  const [matchPattern, setMatchPattern] = useState('')
  const [counterpartAccount, setCounterpartAccount] = useState('')
  const [priority, setPriority] = useState(100)
  const [saving, setSaving] = useState(false)

  async function handleSave() {
    if (!name || !afbCode) {
      toast('warning', tCommon('common.warning'), tCommon('common.fillRequired'))
      return
    }
    setSaving(true)
    try {
      await createBankReconciliationRule({
        name, afb_code: afbCode, description: null,
        match_pattern: matchPattern || null,
        counterpart_account: counterpartAccount || null,
        journal_code: null, priority: Number(priority), active: true,
      })
      toast('success', tCommon('common.success'), t('bankRecon.saveSuccess'))
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('bankRecon.create')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]">✕</button>
        </div>
        <div className="p-6 space-y-4">
          <Input label={t('bankRecon.name')} value={name} onChange={(e) => setName(e.target.value)} required />
          <Input label={t('bankRecon.afbCode')} value={afbCode} onChange={(e) => setAfbCode(e.target.value)} required />
          <Input label={t('bankRecon.matchPattern')} value={matchPattern} onChange={(e) => setMatchPattern(e.target.value)} />
          <Input label={t('bankRecon.counterpart')} value={counterpartAccount} onChange={(e) => setCounterpartAccount(e.target.value)} />
          <Input label={t('bankRecon.priority')} type="number" value={priority} onChange={(e) => setPriority(Number(e.target.value))} />
        </div>
        <div className="flex justify-end gap-3 px-6 py-4 border-t border-[var(--color-border)]">
          <Button variant="secondary" onClick={onClose}>{tCommon('common.actions.cancel')}</Button>
          <Button onClick={handleSave} disabled={saving}>{saving ? tCommon('common.saving') : tCommon('common.actions.save')}</Button>
        </div>
      </div>
    </div>
  )
}
