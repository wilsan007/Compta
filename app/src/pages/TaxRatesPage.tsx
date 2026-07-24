import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input } from '@/components/ui'
import { useToast } from '@/lib/toast'
import { getTaxRates, createTaxRate, updateTaxRate, deleteTaxRate } from '@/lib/queries'
import { Plus, Trash2, Edit2, X, Percent, FileText, BookOpen } from 'lucide-react'
import type { TaxRate } from '@/types'

type Tab = 'list' | 'rubrics' | 'accounting'

export function TaxRatesPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [rates, setRates] = useState<TaxRate[]>([])
  const [loading, setLoading] = useState(true)
  const [activeTab, setActiveTab] = useState<Tab>('list')
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<TaxRate | null>(null)

  const [form, setForm] = useState({
    name: '',
    category: 'standard' as TaxRate['category'],
    rate: 0,
    account_code: '',
    account_collectee: '',
    account_deductible: '',
    type: 'CA3',
    mode: 'debits',
    is_default: false,
    effective_from: new Date().toISOString().slice(0, 10),
    effective_to: '',
    pack_code: 'FR',
  })

  const load = useCallback(async () => {
    try {
      setLoading(true)
      const data = await getTaxRates()
      setRates(data || [])
    } catch (err) {
      console.error('Error loading tax rates:', err)
      toast('error', t('taxRates.title'), t('taxRates.loadError'))
    } finally {
      setLoading(false)
    }
  }, [toast, t])

  useEffect(() => { load() }, [load])

  function resetForm() {
    setForm({
      name: '', category: 'standard', rate: 0, account_code: '',
      account_collectee: '', account_deductible: '', type: 'CA3', mode: 'debits',
      is_default: false, effective_from: new Date().toISOString().slice(0, 10),
      effective_to: '', pack_code: 'FR',
    })
    setEditing(null)
    setShowForm(false)
  }

  function startEdit(rate: TaxRate) {
    setEditing(rate)
    setForm({
      name: rate.name,
      category: rate.category,
      rate: rate.rate,
      account_code: rate.account_code || '',
      account_collectee: rate.account_collectee || '',
      account_deductible: rate.account_deductible || '',
      type: rate.type || 'CA3',
      mode: rate.mode || 'debits',
      is_default: rate.is_default,
      effective_from: rate.effective_from,
      effective_to: rate.effective_to || '',
      pack_code: rate.pack_code,
    })
    setShowForm(true)
  }

  async function handleSubmit() {
    try {
      const payload = {
        ...form,
        effective_to: form.effective_to || null,
      }
      if (editing) {
        await updateTaxRate(editing.id, payload)
        toast('success', t('taxRates.title'), t('taxRates.updateSuccess'))
      } else {
        await createTaxRate(payload as any)
        toast('success', t('taxRates.title'), t('taxRates.createSuccess'))
      }
      resetForm()
      await load()
    } catch (err) {
      console.error('Error saving tax rate:', err)
      toast('error', t('taxRates.title'), t('taxRates.saveError'))
    }
  }

  async function handleDelete(id: string) {
    if (!confirm(t('taxRates.deleteConfirm'))) return
    try {
      await deleteTaxRate(id)
      toast('success', t('taxRates.title'), t('taxRates.deleteSuccess'))
      await load()
    } catch (err) {
      console.error('Error deleting tax rate:', err)
      toast('error', t('taxRates.title'), t('taxRates.deleteError'))
    }
  }

  const categoryBadge: Record<string, 'success' | 'warning' | 'neutral' | 'danger'> = {
    standard: 'danger', intermediate: 'warning', reduced: 'success', super_reduced: 'success', zero: 'neutral', exempt: 'neutral',
  }

  if (loading) {
    return (
      <div>
        <Breadcrumb items={[{ label: t('title') }, { label: t('home.structure') }, { label: t('taxRates.title') }]} />
        <PageHeader title={t('taxRates.title')} subtitle={t('taxRates.subtitle')} />
        <SkeletonTable rows={6} cols={7} />
      </div>
    )
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('home.structure') }, { label: t('taxRates.title') }]} />
      <PageHeader title={t('taxRates.title')} subtitle={t('taxRates.subtitle')} />

      {/* Tabs */}
      <div className="flex gap-1 mb-4 border-b border-[var(--color-border)]">
        {([
          { key: 'list' as Tab, label: t('taxRates.tabList'), icon: Percent },
          { key: 'rubrics' as Tab, label: t('taxRates.tabRubrics'), icon: FileText },
          { key: 'accounting' as Tab, label: t('taxRates.tabAccounting'), icon: BookOpen },
        ]).map((tab) => (
          <button
            key={tab.key}
            onClick={() => setActiveTab(tab.key)}
            className={`px-4 py-2 text-sm font-medium border-b-2 transition-colors flex items-center gap-2 ${
              activeTab === tab.key
                ? 'border-[var(--color-primary)] text-[var(--color-primary)]'
                : 'border-transparent text-[var(--color-text-secondary)] hover:text-[var(--color-text)]'
            }`}
          >
            <tab.icon className="w-4 h-4" />
            {tab.label}
          </button>
        ))}
      </div>

      {/* Tab: List */}
      {activeTab === 'list' && (
        <div>
          {showForm && (
            <Card className="mb-4">
              <div className="p-4">
                <div className="flex items-center justify-between mb-4">
                  <h3 className="text-lg font-semibold">{editing ? t('taxRates.edit') : t('taxRates.create')}</h3>
                  <Button variant="secondary" onClick={resetForm}><X className="w-4 h-4" /></Button>
                </div>
                <div className="grid grid-cols-3 gap-4">
                  <Input label={t('taxRates.name')} value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required />
                  <div>
                    <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('taxRates.category')}</label>
                    <select className="input" value={form.category} onChange={(e) => setForm({ ...form, category: e.target.value as any })}>
                      <option value="standard">{t('taxRates.catStandard')}</option>
                      <option value="intermediate">{t('taxRates.catIntermediate')}</option>
                      <option value="reduced">{t('taxRates.catReduced')}</option>
                      <option value="super_reduced">{t('taxRates.catSuperReduced')}</option>
                      <option value="zero">{t('taxRates.catZero')}</option>
                      <option value="exempt">{t('taxRates.catExempt')}</option>
                    </select>
                  </div>
                  <Input label={t('taxRates.rate')} type="number" step="0.001" value={form.rate} onChange={(e) => setForm({ ...form, rate: Number(e.target.value) })} required />
                  <Input label={t('taxRates.accountCode')} value={form.account_code} onChange={(e) => setForm({ ...form, account_code: e.target.value })} />
                  <Input label={t('taxRates.accountCollectee')} value={form.account_collectee} onChange={(e) => setForm({ ...form, account_collectee: e.target.value })} />
                  <Input label={t('taxRates.accountDeductible')} value={form.account_deductible} onChange={(e) => setForm({ ...form, account_deductible: e.target.value })} />
                  <div>
                    <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('taxRates.type')}</label>
                    <select className="input" value={form.type} onChange={(e) => setForm({ ...form, type: e.target.value })}>
                      <option value="CA3">CA3</option>
                      <option value="CA12">CA12</option>
                    </select>
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('taxRates.mode')}</label>
                    <select className="input" value={form.mode} onChange={(e) => setForm({ ...form, mode: e.target.value })}>
                      <option value="debits">{t('taxRates.modeDebits')}</option>
                      <option value="encaissements">{t('taxRates.modeEncaissements')}</option>
                    </select>
                  </div>
                  <Input label={t('taxRates.effectiveFrom')} type="date" value={form.effective_from} onChange={(e) => setForm({ ...form, effective_from: e.target.value })} />
                  <Input label={t('taxRates.effectiveTo')} type="date" value={form.effective_to} onChange={(e) => setForm({ ...form, effective_to: e.target.value })} />
                  <div className="flex items-end">
                    <label className="flex items-center gap-2 text-sm">
                      <input type="checkbox" checked={form.is_default} onChange={(e) => setForm({ ...form, is_default: e.target.checked })} />
                      {t('taxRates.isDefault')}
                    </label>
                  </div>
                </div>
                <div className="flex justify-end gap-3 mt-4">
                  <Button variant="secondary" onClick={resetForm}>{tCommon('actions.cancel')}</Button>
                  <Button onClick={handleSubmit} disabled={!form.name || form.rate < 0}>{tCommon('actions.save')}</Button>
                </div>
              </div>
            </Card>
          )}

          <div className="flex justify-end mb-3">
            <Button onClick={() => { resetForm(); setShowForm(true) }}>
              <Plus className="w-4 h-4" /> {t('taxRates.create')}
            </Button>
          </div>

          {rates.length === 0 ? (
            <EmptyState icon={<Percent className="w-8 h-8" />} title={t('taxRates.empty')} description={t('taxRates.emptyDesc')} />
          ) : (
            <Card>
              <Table headers={[
                t('taxRates.name'),
                t('taxRates.category'),
                t('taxRates.rate'),
                t('taxRates.accountCollectee'),
                t('taxRates.accountDeductible'),
                t('taxRates.type'),
                t('taxRates.mode'),
                '',
              ]}>
                {rates.map((rate) => (
                  <TableRow key={rate.id}>
                    <TableCell className="font-medium">{rate.name}{rate.is_default && <Badge variant="warning" >{t('taxRates.defaultBadge')}</Badge>}</TableCell>
                    <TableCell><Badge variant={categoryBadge[rate.category] || 'neutral'}>{t(`taxRates.cat${rate.category.charAt(0).toUpperCase() + rate.category.slice(1)}`)}</Badge></TableCell>
                    <TableCell className="font-mono font-semibold">{rate.rate.toFixed(3)}%</TableCell>
                    <TableCell className="font-mono text-xs">{rate.account_collectee || '—'}</TableCell>
                    <TableCell className="font-mono text-xs">{rate.account_deductible || '—'}</TableCell>
                    <TableCell><Badge variant="neutral">{rate.type || 'CA3'}</Badge></TableCell>
                    <TableCell className="text-xs">{rate.mode === 'debits' ? t('taxRates.modeDebits') : t('taxRates.modeEncaissements')}</TableCell>
                    <TableCell>
                      <div className="flex gap-1">
                        <button onClick={() => startEdit(rate)} className="p-1 text-[var(--color-text-secondary)] hover:text-[var(--color-primary)]"><Edit2 className="w-4 h-4" /></button>
                        <button onClick={() => handleDelete(rate.id)} className="p-1 text-[var(--color-text-secondary)] hover:text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </Table>
            </Card>
          )}
        </div>
      )}

      {/* Tab: Rubrics */}
      {activeTab === 'rubrics' && (
        <Card>
          <div className="p-4">
            <h3 className="text-lg font-semibold mb-4">{t('taxRates.rubricsTitle')}</h3>
            <p className="text-sm text-[var(--color-text-secondary)] mb-4">{t('taxRates.rubricsDesc')}</p>
            <Table headers={[t('taxRates.rubricCode'), t('taxRates.rubricName'), t('taxRates.rubricRate'), t('taxRates.rubricBase')]}>
              {[
                { code: '01', name: t('taxRates.rubric01'), rate: '20%', base: 'Base HT' },
                { code: '02', name: t('taxRates.rubric02'), rate: '5.5%', base: 'Base HT' },
                { code: '03', name: t('taxRates.rubric03'), rate: '10%', base: 'Base HT' },
                { code: '04', name: t('taxRates.rubric04'), rate: '2.1%', base: 'Base HT' },
                { code: '05', name: t('taxRates.rubric05'), rate: '0%', base: 'Base HT' },
              ].map((r) => (
                <TableRow key={r.code}>
                  <TableCell className="font-mono">{r.code}</TableCell>
                  <TableCell>{r.name}</TableCell>
                  <TableCell className="font-mono">{r.rate}</TableCell>
                  <TableCell className="text-xs">{r.base}</TableCell>
                </TableRow>
              ))}
            </Table>
          </div>
        </Card>
      )}

      {/* Tab: Accounting Info */}
      {activeTab === 'accounting' && (
        <Card>
          <div className="p-4">
            <h3 className="text-lg font-semibold mb-4">{t('taxRates.accountingTitle')}</h3>
            <p className="text-sm text-[var(--color-text-secondary)] mb-4">{t('taxRates.accountingDesc')}</p>
            <Table headers={[t('taxRates.name'), t('taxRates.accountCollectee'), t('taxRates.accountDeductible'), t('taxRates.type')]}>
              {rates.filter((r) => r.account_collectee || r.account_deductible).map((rate) => (
                <TableRow key={rate.id}>
                  <TableCell className="font-medium">{rate.name}</TableCell>
                  <TableCell className="font-mono text-xs">{rate.account_collectee || '—'}</TableCell>
                  <TableCell className="font-mono text-xs">{rate.account_deductible || '—'}</TableCell>
                  <TableCell><Badge variant="neutral">{rate.type || 'CA3'}</Badge></TableCell>
                </TableRow>
              ))}
            </Table>
          </div>
        </Card>
      )}
    </div>
  )
}
