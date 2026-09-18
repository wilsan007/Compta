import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input } from '@/components/ui'
import { useToast } from '@/lib/toast'
import { getTaxRates, createTaxRate, updateTaxRate, deleteTaxRate, getTaxGroups, createTaxGroup, deleteTaxGroup, getTaxRepartitionLines, createTaxRepartitionLine, deleteTaxRepartitionLine } from '@/lib/queries/accounting'
import { Plus, Trash2, Edit2, X, Percent, FileText, BookOpen, Layers, Split } from 'lucide-react'
import type { TaxRate, TaxGroup, TaxRepartitionLine } from '@/types'

type Tab = 'list' | 'rubrics' | 'accounting' | 'groups' | 'repartition'

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
    amount_type: 'percent' as TaxRate['amount_type'],
    type_tax_use: 'none' as TaxRate['type_tax_use'],
    sequence: 10,
    parent_tax_id: '' as string,
    tax_exigibility: 'on_invoice' as TaxRate['tax_exigibility'],
    cash_basis_transition_account: '',
    price_include: false,
    include_base_amount: false,
    is_base_affected: true,
    analytic: false,
    fixed_amount: '' as string,
  })
  const [groups, setGroups] = useState<TaxGroup[]>([])
  const [repartitionLines, setRepartitionLines] = useState<TaxRepartitionLine[]>([])
  const [selectedTaxForRepartition, setSelectedTaxForRepartition] = useState<string>('')
  const [showGroupForm, setShowGroupForm] = useState(false)
  const [groupForm, setGroupForm] = useState({ name: '', country_code: '' })
  const [repartitionForm, setRepartitionForm] = useState({ document_type: 'invoice' as 'invoice' | 'refund', repartition_type: 'base' as 'base' | 'tax', factor: 100, account_code: '', tag_ids: '' })

  const load = useCallback(async () => {
    try {
      setLoading(true)
      const data = await getTaxRates()
      setRates(data || [])
    } catch (err: any) { console.error('Error loading tax rates:', err)
      toast('error', t('taxRates.title'), t('taxRates.loadError'))
    } finally {
      setLoading(false)
    }
  }, [toast, t])

  useEffect(() => { load() }, [load])
  // oxlint-disable-next-line react-hooks/exhaustive-deps -- chargement volontairement limite aux valeurs listees
  useEffect(() => { if (activeTab === 'groups') loadGroups() }, [activeTab])

  function resetForm() {
    setForm({
      name: '', category: 'standard', rate: 0, account_code: '',
      account_collectee: '', account_deductible: '', type: 'CA3', mode: 'debits',
      is_default: false, effective_from: new Date().toISOString().slice(0, 10),
      effective_to: '', pack_code: 'FR',
      amount_type: 'percent', type_tax_use: 'none', sequence: 10, parent_tax_id: '',
      tax_exigibility: 'on_invoice', cash_basis_transition_account: '',
      price_include: false, include_base_amount: false, is_base_affected: true,
      analytic: false, fixed_amount: '',
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
      amount_type: rate.amount_type || 'percent',
      type_tax_use: rate.type_tax_use || 'none',
      sequence: rate.sequence || 10,
      parent_tax_id: rate.parent_tax_id || '',
      tax_exigibility: rate.tax_exigibility || 'on_invoice',
      cash_basis_transition_account: rate.cash_basis_transition_account || '',
      price_include: rate.price_include || false,
      include_base_amount: rate.include_base_amount || false,
      is_base_affected: rate.is_base_affected ?? true,
      analytic: rate.analytic || false,
      fixed_amount: rate.fixed_amount != null ? String(rate.fixed_amount) : '',
    })
    setShowForm(true)
  }

  async function handleSubmit() {
    try {
      const payload = {
        ...form,
        effective_to: form.effective_to || null,
        parent_tax_id: form.parent_tax_id || null,
        fixed_amount: form.fixed_amount ? Number(form.fixed_amount) : null,
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
    } catch (err: any) { console.error('Error saving tax rate:', err)
      toast('error', t('taxRates.title'), t('taxRates.saveError'))
    }
  }

  async function loadGroups() {
    try {
      setGroups(await getTaxGroups())
    } catch (err: any) { console.error('Error loading tax groups:', err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError')) }
  }

  async function handleCreateGroup() {
    try {
      await createTaxGroup({ name: groupForm.name, country_code: groupForm.country_code || null })
      toast('success', t('taxRates.groupsTitle'), t('taxRates.groupCreateSuccess'))
      setGroupForm({ name: '', country_code: '' })
      setShowGroupForm(false)
      await loadGroups()
    } catch (err: any) { console.error('Error creating tax group:', err)
      toast('error', t('taxRates.groupsTitle'), t('taxRates.groupSaveError'))
    }
  }

  async function handleDeleteGroup(id: string) {
    if (!confirm(t('taxRates.groupDeleteConfirm'))) return
    try {
      await deleteTaxGroup(id)
      toast('success', t('taxRates.groupsTitle'), t('taxRates.groupDeleteSuccess'))
      await loadGroups()
    } catch (err: any) { console.error('Error deleting tax group:', err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError')) }
  }

  async function loadRepartition(taxId: string) {
    setSelectedTaxForRepartition(taxId)
    try {
      setRepartitionLines(await getTaxRepartitionLines(taxId))
    } catch (err: any) { console.error('Error loading repartition lines:', err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError')) }
  }

  async function handleCreateRepartition() {
    if (!selectedTaxForRepartition) return
    try {
      await createTaxRepartitionLine({
        tax_id: selectedTaxForRepartition,
        document_type: repartitionForm.document_type,
        repartition_type: repartitionForm.repartition_type,
        factor: repartitionForm.factor,
        account_code: repartitionForm.account_code || null,
        tag_ids: repartitionForm.tag_ids ? repartitionForm.tag_ids.split(',').map((s) => s.trim()) : null,
      })
      toast('success', t('taxRates.repartitionTitle'), t('taxRates.repartitionCreateSuccess'))
      setRepartitionForm({ document_type: 'invoice', repartition_type: 'base', factor: 100, account_code: '', tag_ids: '' })
      await loadRepartition(selectedTaxForRepartition)
    } catch (err: any) { console.error('Error creating repartition line:', err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError')) }
  }

  async function handleDeleteRepartition(id: string) {
    if (!confirm(t('taxRates.repartitionDeleteConfirm'))) return
    try {
      await deleteTaxRepartitionLine(id)
      toast('success', t('taxRates.repartitionTitle'), t('taxRates.repartitionDeleteSuccess'))
      if (selectedTaxForRepartition) await loadRepartition(selectedTaxForRepartition)
    } catch (err: any) { console.error('Error deleting repartition line:', err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError')) }
  }

  async function handleDelete(id: string) {
    if (!confirm(t('taxRates.deleteConfirm'))) return
    try {
      await deleteTaxRate(id)
      toast('success', t('taxRates.title'), t('taxRates.deleteSuccess'))
      await load()
    } catch (err: any) { console.error('Error deleting tax rate:', err)
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
          { key: 'groups' as Tab, label: t('taxRates.tabGroups'), icon: Layers },
          { key: 'repartition' as Tab, label: t('taxRates.tabRepartition'), icon: Split },
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
                  <Button variant="secondary" onClick={resetForm} ariaLabel={tCommon('actions.close')}><X className="w-4 h-4" aria-hidden="true" /></Button>
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

                {/* Sprint 3: Advanced Tax Fields */}
                <div>
                  <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('taxRates.amountType')}</label>
                  <select className="input" value={form.amount_type} onChange={(e) => setForm({ ...form, amount_type: e.target.value as any })}>
                    <option value="percent">{t('taxRates.amountTypePercent')}</option>
                    <option value="fixed">{t('taxRates.amountTypeFixed')}</option>
                    <option value="group">{t('taxRates.amountTypeGroup')}</option>
                    <option value="division">{t('taxRates.amountTypeDivision')}</option>
                  </select>
                </div>
                <div>
                  <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('taxRates.typeTaxUse')}</label>
                  <select className="input" value={form.type_tax_use} onChange={(e) => setForm({ ...form, type_tax_use: e.target.value as any })}>
                    <option value="none">{t('taxRates.typeTaxUseNone')}</option>
                    <option value="sale">{t('taxRates.typeTaxUseSale')}</option>
                    <option value="purchase">{t('taxRates.typeTaxUsePurchase')}</option>
                  </select>
                </div>
                <Input label={t('taxRates.sequence')} type="number" value={form.sequence} onChange={(e) => setForm({ ...form, sequence: Number(e.target.value) })} />
                {form.amount_type === 'fixed' && (
                  <Input label={t('taxRates.fixedAmount')} type="number" step="0.01" value={form.fixed_amount} onChange={(e) => setForm({ ...form, fixed_amount: e.target.value })} />
                )}
                {form.amount_type === 'group' && (
                  <div>
                    <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('taxRates.parentTax')}</label>
                    <select className="input" value={form.parent_tax_id} onChange={(e) => setForm({ ...form, parent_tax_id: e.target.value })}>
                      <option value="">—</option>
                      {rates.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
                    </select>
                  </div>
                )}
                <div>
                  <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('taxRates.taxExigibility')}</label>
                  <select className="input" value={form.tax_exigibility} onChange={(e) => setForm({ ...form, tax_exigibility: e.target.value as any })}>
                    <option value="on_invoice">{t('taxRates.taxExigibilityOnInvoice')}</option>
                    <option value="on_payment">{t('taxRates.taxExigibilityOnPayment')}</option>
                  </select>
                </div>
                {form.tax_exigibility === 'on_payment' && (
                  <Input label={t('taxRates.cashBasisTransitionAccount')} value={form.cash_basis_transition_account} onChange={(e) => setForm({ ...form, cash_basis_transition_account: e.target.value })} />
                )}
                <div className="flex flex-col gap-2 col-span-3">
                  <label className="flex items-center gap-2 text-sm">
                    <input type="checkbox" checked={form.price_include} onChange={(e) => setForm({ ...form, price_include: e.target.checked })} />
                    {t('taxRates.priceInclude')}
                  </label>
                  <label className="flex items-center gap-2 text-sm">
                    <input type="checkbox" checked={form.include_base_amount} onChange={(e) => setForm({ ...form, include_base_amount: e.target.checked })} />
                    {t('taxRates.includeBaseAmount')}
                  </label>
                  <label className="flex items-center gap-2 text-sm">
                    <input type="checkbox" checked={form.is_base_affected} onChange={(e) => setForm({ ...form, is_base_affected: e.target.checked })} />
                    {t('taxRates.isBaseAffected')}
                  </label>
                  <label className="flex items-center gap-2 text-sm">
                    <input type="checkbox" checked={form.analytic} onChange={(e) => setForm({ ...form, analytic: e.target.checked })} />
                    {t('taxRates.analyticRequired')}
                  </label>
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

      {/* Tab: Groups */}
      {activeTab === 'groups' && (
        <div>
          <div className="flex items-center justify-between mb-4">
            <div>
              <h3 className="text-lg font-semibold">{t('taxRates.groupsTitle')}</h3>
              <p className="text-sm text-[var(--color-text-secondary)]">{t('taxRates.groupsDesc')}</p>
            </div>
            <Button onClick={() => setShowGroupForm(true)}><Plus className="w-4 h-4" /> {t('taxRates.groupCreate')}</Button>
          </div>

          {showGroupForm && (
            <Card className="mb-4">
              <div className="p-4">
                <div className="flex items-center justify-between mb-4">
                  <h3 className="text-lg font-semibold">{t('taxRates.groupCreate')}</h3>
                  <Button variant="secondary" onClick={() => setShowGroupForm(false)}><X className="w-4 h-4" /></Button>
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <Input label={t('taxRates.groupName')} value={groupForm.name} onChange={(e) => setGroupForm({ ...groupForm, name: e.target.value })} />
                  <Input label={t('taxRates.groupCountry')} value={groupForm.country_code} onChange={(e) => setGroupForm({ ...groupForm, country_code: e.target.value })} />
                </div>
                <div className="flex justify-end gap-3 mt-4">
                  <Button onClick={handleCreateGroup} disabled={!groupForm.name}>{tCommon('actions.save')}</Button>
                </div>
              </div>
            </Card>
          )}

          {groups.length === 0 ? (
            <EmptyState icon={<Layers className="w-8 h-8" />} title={t('taxRates.groupEmpty')} description={t('taxRates.groupEmptyDesc')} />
          ) : (
            <Card>
              <Table headers={[t('taxRates.groupName'), t('taxRates.groupCountry'), '']}>
                {groups.map((g) => (
                  <TableRow key={g.id}>
                    <TableCell className="font-medium">{g.name}</TableCell>
                    <TableCell className="text-xs">{g.country_code || '—'}</TableCell>
                    <TableCell>
                      <button onClick={() => handleDeleteGroup(g.id)} className="p-1 text-[var(--color-text-secondary)] hover:text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
                    </TableCell>
                  </TableRow>
                ))}
              </Table>
            </Card>
          )}
        </div>
      )}

      {/* Tab: Repartition */}
      {activeTab === 'repartition' && (
        <div>
          <div className="mb-4">
            <h3 className="text-lg font-semibold">{t('taxRates.repartitionTitle')}</h3>
            <p className="text-sm text-[var(--color-text-secondary)]">{t('taxRates.repartitionDesc')}</p>
          </div>

          <div className="mb-4">
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('taxRates.name')}</label>
            <select className="input" value={selectedTaxForRepartition} onChange={(e) => loadRepartition(e.target.value)}>
              <option value="">—</option>
              {rates.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
            </select>
          </div>

          {selectedTaxForRepartition && (
            <>
              <Card className="mb-4">
                <div className="p-4">
                  <h4 className="text-sm font-semibold mb-3">{t('taxRates.repartitionAdd')}</h4>
                  <div className="grid grid-cols-5 gap-3">
                    <div>
                      <label className="block text-xs text-[var(--color-text-secondary)] mb-1">{t('taxRates.repartitionType')}</label>
                      <select className="input" value={repartitionForm.repartition_type} onChange={(e) => setRepartitionForm({ ...repartitionForm, repartition_type: e.target.value as any })}>
                        <option value="base">{t('taxRates.repartitionTypeBase')}</option>
                        <option value="tax">{t('taxRates.repartitionTypeTax')}</option>
                      </select>
                    </div>
                    <div>
                      <label className="block text-xs text-[var(--color-text-secondary)] mb-1">{t('taxRates.repartitionInvoice')}</label>
                      <select className="input" value={repartitionForm.document_type} onChange={(e) => setRepartitionForm({ ...repartitionForm, document_type: e.target.value as any })}>
                        <option value="invoice">{t('taxRates.repartitionInvoice')}</option>
                        <option value="refund">{t('taxRates.repartitionRefund')}</option>
                      </select>
                    </div>
                    <Input label={t('taxRates.repartitionFactor')} type="number" step="0.01" value={repartitionForm.factor} onChange={(e) => setRepartitionForm({ ...repartitionForm, factor: Number(e.target.value) })} />
                    <Input label={t('taxRates.repartitionAccount')} value={repartitionForm.account_code} onChange={(e) => setRepartitionForm({ ...repartitionForm, account_code: e.target.value })} />
                    <Input label={t('taxRates.repartitionTags')} value={repartitionForm.tag_ids} onChange={(e) => setRepartitionForm({ ...repartitionForm, tag_ids: e.target.value })} />
                  </div>
                  <div className="flex justify-end mt-3">
                    <Button onClick={handleCreateRepartition}><Plus className="w-4 h-4" /> {t('taxRates.repartitionAdd')}</Button>
                  </div>
                </div>
              </Card>

              {repartitionLines.length === 0 ? (
                <EmptyState icon={<Split className="w-8 h-8" />} title={t('taxRates.repartitionEmpty')} />
              ) : (
                <Card>
                  <Table headers={[t('taxRates.repartitionType'), t('taxRates.repartitionInvoice'), t('taxRates.repartitionFactor'), t('taxRates.repartitionAccount'), t('taxRates.repartitionTags'), '']}>
                    {repartitionLines.map((line) => (
                      <TableRow key={line.id}>
                        <TableCell className="text-xs">{line.repartition_type === 'base' ? t('taxRates.repartitionTypeBase') : t('taxRates.repartitionTypeTax')}</TableCell>
                        <TableCell className="text-xs">{line.document_type === 'invoice' ? t('taxRates.repartitionInvoice') : t('taxRates.repartitionRefund')}</TableCell>
                        <TableCell className="font-mono text-xs">{line.factor}%</TableCell>
                        <TableCell className="font-mono text-xs">{line.account_code || '—'}</TableCell>
                        <TableCell className="text-xs">{line.tag_ids?.join(', ') || '—'}</TableCell>
                        <TableCell>
                          <button onClick={() => handleDeleteRepartition(line.id)} className="p-1 text-[var(--color-text-secondary)] hover:text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
                        </TableCell>
                      </TableRow>
                    ))}
                  </Table>
                </Card>
              )}
            </>
          )}
        </div>
      )}
    </div>
  )
}
