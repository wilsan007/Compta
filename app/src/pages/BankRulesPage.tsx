import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { getBankRules, createBankRule, updateBankRule, deleteBankRule } from '@/lib/queries'
import { Plus, Trash2, X, Power, PowerOff } from 'lucide-react'
import type { BankRule } from '@/types'
import { useToast } from '@/lib/toast'

export function BankRulesPage() {
  const { toast } = useToast()
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
      toast('error', 'Erreur', err.message || 'échec')
    }
  }

  async function handleDelete(id: string) {
    if (!window.confirm('Supprimer cette règle ?')) return
    try {
      await deleteBankRule(id)
      await loadData()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: 'Banque' }, { label: 'Règles' }]} />
      <PageHeader
        title="Règles bancaires"
        subtitle="Automatisez la catégorisation des transactions"
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouvelle règle</Button>}
      />

      {loading ? (
        <SkeletonTable rows={4} cols={5} />
      ) : rules.length === 0 ? (
        <EmptyState
          icon={<Power className="w-8 h-8" />}
          title="Aucune règle"
          description="Créez des règles pour catégoriser automatiquement vos transactions."
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouvelle règle</Button>}
        />
      ) : (
        <Card>
          <Table headers={['Nom', 'Condition', 'Catégorie', 'Priorité', 'Statut', 'Actions']}>
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
                    {r.active ? 'Active' : 'Inactive'}
                  </Badge>
                </TableCell>
                <TableCell>
                  <div className="flex items-center gap-1">
                    <button onClick={() => handleToggle(r.id, r.active)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)]" title={r.active ? 'Désactiver' : 'Activer'}>
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
  const [conditionField, setConditionField] = useState('description')
  const [conditionOperator, setConditionOperator] = useState('contains')
  const [conditionValue, setConditionValue] = useState('')
  const [actionCategory, setActionCategory] = useState('')
  const [actionAccountCode, setActionAccountCode] = useState('')
  const [actionVatRate, setActionVatRate] = useState(20)
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
      toast('error', 'Erreur', err.message || 'échec')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">Nouvelle règle bancaire</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label="Nom de la règle" required value={name} onChange={(e) => setName(e.target.value)} />
          <div className="grid grid-cols-3 gap-4">
            <Select label="Champ" value={conditionField} onChange={(e) => setConditionField(e.target.value)} options={[
              { value: 'description', label: 'Description' },
              { value: 'reference', label: 'Référence' },
              { value: 'amount', label: 'Montant' },
            ]} />
            <Select label="Opérateur" value={conditionOperator} onChange={(e) => setConditionOperator(e.target.value)} options={[
              { value: 'contains', label: 'Contient' },
              { value: 'equals', label: 'Égal à' },
              { value: 'starts_with', label: 'Commence par' },
              { value: 'greater_than', label: 'Supérieur à' },
              { value: 'less_than', label: 'Inférieur à' },
            ]} />
            <Input label="Valeur" required value={conditionValue} onChange={(e) => setConditionValue(e.target.value)} />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label="Catégorie" required value={actionCategory} onChange={(e) => setActionCategory(e.target.value)} placeholder="Ex: Ventes" />
            <Input label="Code compte" value={actionAccountCode} onChange={(e) => setActionAccountCode(e.target.value)} placeholder="Ex: 707000" />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label="TVA (%)" type="number" step="0.01" value={actionVatRate} onChange={(e) => setActionVatRate(Number(e.target.value))} />
            <Input label="Priorité" type="number" value={priority} onChange={(e) => setPriority(Number(e.target.value))} />
          </div>
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>Annuler</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : 'Créer'}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
