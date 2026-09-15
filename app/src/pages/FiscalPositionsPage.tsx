import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input } from '@/components/ui'
import { useToast } from '@/lib/toast'
import { getFiscalPositions, createFiscalPosition, updateFiscalPosition, deleteFiscalPosition, getFiscalPositionMappings, createFiscalPositionMapping, deleteFiscalPositionMapping } from '@/lib/queries/misc'
import { getTaxRates } from '@/lib/queries/accounting'
import { Plus, Trash2, Edit2, X, MapPin, ArrowRight } from 'lucide-react'
import type { FiscalPosition, FiscalPositionMapping, TaxRate } from '@/types'

type Tab = 'general' | 'mappings'

export function FiscalPositionsPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [positions, setPositions] = useState<FiscalPosition[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<FiscalPosition | null>(null)
  const [activeTab, setActiveTab] = useState<Tab>('general')
  const [selectedPosition, setSelectedPosition] = useState<FiscalPosition | null>(null)
  const [mappings, setMappings] = useState<FiscalPositionMapping[]>([])
  const [taxRates, setTaxRates] = useState<TaxRate[]>([])

  const [form, setForm] = useState({
    name: '',
    country_code: '',
    country_group_id: '',
    zip_from: '',
    zip_to: '',
    auto_apply: false,
    active: true,
  })

  const [mappingForm, setMappingForm] = useState({
    source_tax_id: '',
    target_tax_id: '',
    source_account_code: '',
    target_account_code: '',
  })

  const load = useCallback(async () => {
    try {
      setLoading(true)
      setPositions(await getFiscalPositions())
    } catch (err: any) { console.error('Error loading fiscal positions:', err)
      toast('error', t('fiscalPositions.title'), t('fiscalPositions.loadError'))
    } finally {
      setLoading(false)
    }
  }, [toast, t])

  useEffect(() => {
    load()
    getTaxRates().then(setTaxRates).catch(() => {})
  }, [load])

  function resetForm() {
    setForm({ name: '', country_code: '', country_group_id: '', zip_from: '', zip_to: '', auto_apply: false, active: true })
    setEditing(null)
    setShowForm(false)
  }

  function startEdit(fp: FiscalPosition) {
    setEditing(fp)
    setForm({
      name: fp.name,
      country_code: fp.country_code || '',
      country_group_id: fp.country_group_id || '',
      zip_from: fp.zip_from || '',
      zip_to: fp.zip_to || '',
      auto_apply: fp.auto_apply,
      active: fp.active,
    })
    setShowForm(true)
  }

  async function handleSubmit() {
    try {
      const payload = {
        name: form.name,
        country_code: form.country_code || null,
        country_group_id: form.country_group_id || null,
        zip_from: form.zip_from || null,
        zip_to: form.zip_to || null,
        auto_apply: form.auto_apply,
        active: form.active,
      }
      if (editing) {
        await updateFiscalPosition(editing.id, payload)
        toast('success', t('fiscalPositions.title'), t('fiscalPositions.updateSuccess'))
      } else {
        await createFiscalPosition(payload)
        toast('success', t('fiscalPositions.title'), t('fiscalPositions.createSuccess'))
      }
      resetForm()
      await load()
    } catch (err: any) { console.error('Error saving fiscal position:', err)
      toast('error', t('fiscalPositions.title'), t('fiscalPositions.saveError'))
    }
  }

  async function handleDelete(id: string) {
    if (!confirm(t('fiscalPositions.deleteConfirm'))) return
    try {
      await deleteFiscalPosition(id)
      toast('success', t('fiscalPositions.title'), t('fiscalPositions.deleteSuccess'))
      await load()
    } catch (err: any) { console.error('Error deleting fiscal position:', err)
    toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError'))
    }
  }

  async function loadMappings(fp: FiscalPosition) {
    setSelectedPosition(fp)
    setActiveTab('mappings')
    try {
      setMappings(await getFiscalPositionMappings(fp.id))
    } catch (err: any) { console.error('Error loading mappings:', err)
    toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError'))
    }
  }

  async function handleCreateMapping() {
    if (!selectedPosition) return
    try {
      await createFiscalPositionMapping({
        fiscal_position_id: selectedPosition.id,
        source_tax_id: mappingForm.source_tax_id || null,
        target_tax_id: mappingForm.target_tax_id || null,
        source_account_code: mappingForm.source_account_code || null,
        target_account_code: mappingForm.target_account_code || null,
      })
      toast('success', t('fiscalPositions.mappingsTitle'), t('fiscalPositions.mappingCreateSuccess'))
      setMappingForm({ source_tax_id: '', target_tax_id: '', source_account_code: '', target_account_code: '' })
      setMappings(await getFiscalPositionMappings(selectedPosition.id))
    } catch (err: any) { console.error('Error creating mapping:', err)
    toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError'))
    }
  }

  async function handleDeleteMapping(id: string) {
    if (!confirm(t('fiscalPositions.mappingDeleteConfirm'))) return
    try {
      await deleteFiscalPositionMapping(id)
      toast('success', t('fiscalPositions.mappingsTitle'), t('fiscalPositions.mappingDeleteSuccess'))
      if (selectedPosition) setMappings(await getFiscalPositionMappings(selectedPosition.id))
    } catch (err: any) { console.error('Error deleting mapping:', err)
    toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError'))
    }
  }

  if (loading) {
    return (
      <div>
        <Breadcrumb items={[{ label: t('title') }, { label: t('home.structure') }, { label: t('fiscalPositions.title') }]} />
        <PageHeader title={t('fiscalPositions.title')} subtitle={t('fiscalPositions.subtitle')} />
        <SkeletonTable rows={5} cols={5} />
      </div>
    )
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('home.structure') }, { label: t('fiscalPositions.title') }]} />
      <PageHeader title={t('fiscalPositions.title')} subtitle={t('fiscalPositions.subtitle')} />

      {showForm && (
        <Card className="mb-4">
          <div className="p-4">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-semibold">{editing ? t('fiscalPositions.edit') : t('fiscalPositions.create')}</h3>
              <Button variant="secondary" onClick={resetForm}><X className="w-4 h-4" /></Button>
            </div>
            <div className="grid grid-cols-3 gap-4">
              <Input label={t('fiscalPositions.name')} value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
              <Input label={t('fiscalPositions.country')} value={form.country_code} onChange={(e) => setForm({ ...form, country_code: e.target.value })} />
              <Input label={t('fiscalPositions.countryGroup')} value={form.country_group_id} onChange={(e) => setForm({ ...form, country_group_id: e.target.value })} />
              <Input label={t('fiscalPositions.zipFrom')} value={form.zip_from} onChange={(e) => setForm({ ...form, zip_from: e.target.value })} />
              <Input label={t('fiscalPositions.zipTo')} value={form.zip_to} onChange={(e) => setForm({ ...form, zip_to: e.target.value })} />
              <div className="flex items-end gap-4">
                <label className="flex items-center gap-2 text-sm">
                  <input type="checkbox" checked={form.auto_apply} onChange={(e) => setForm({ ...form, auto_apply: e.target.checked })} />
                  {t('fiscalPositions.autoApply')}
                </label>
                <label className="flex items-center gap-2 text-sm">
                  <input type="checkbox" checked={form.active} onChange={(e) => setForm({ ...form, active: e.target.checked })} />
                  {t('fiscalPositions.active')}
                </label>
              </div>
              <div className="flex justify-end gap-3 mt-4 col-span-3">
                <Button variant="secondary" onClick={resetForm}>{tCommon('actions.cancel')}</Button>
                <Button onClick={handleSubmit} disabled={!form.name}>{tCommon('actions.save')}</Button>
              </div>
            </div>
          </div>
        </Card>
      )}

      {selectedPosition && (
        <Card className="mb-4">
          <div className="p-4">
            <div className="flex items-center justify-between mb-4">
              <div>
                <h3 className="text-lg font-semibold">{selectedPosition.name}</h3>
                <p className="text-sm text-[var(--color-text-secondary)]">{selectedPosition.country_code || '—'}</p>
              </div>
              <Button variant="secondary" onClick={() => { setSelectedPosition(null); setActiveTab('general') }}><X className="w-4 h-4" /></Button>
            </div>

            <div className="flex gap-1 mb-4 border-b border-[var(--color-border)]">
              {([
                { key: 'general' as Tab, label: t('fiscalPositions.tabGeneral') },
                { key: 'mappings' as Tab, label: t('fiscalPositions.tabMappings') },
              ]).map((tab) => (
                <button
                  key={tab.key}
                  onClick={() => setActiveTab(tab.key)}
                  className={`px-4 py-2 text-sm font-medium border-b-2 transition-colors ${
                    activeTab === tab.key
                      ? 'border-[var(--color-primary)] text-[var(--color-primary)]'
                      : 'border-transparent text-[var(--color-text-secondary)] hover:text-[var(--color-text)]'
                  }`}
                >
                  {tab.label}
                </button>
              ))}
            </div>

            {activeTab === 'mappings' && (
              <div>
                <div className="grid grid-cols-5 gap-3 mb-4">
                  <div>
                    <label className="block text-xs text-[var(--color-text-secondary)] mb-1">{t('fiscalPositions.mappingSourceTax')}</label>
                    <select className="input" value={mappingForm.source_tax_id} onChange={(e) => setMappingForm({ ...mappingForm, source_tax_id: e.target.value })}>
                      <option value="">—</option>
                      {taxRates.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
                    </select>
                  </div>
                  <div>
                    <label className="block text-xs text-[var(--color-text-secondary)] mb-1">{t('fiscalPositions.mappingTargetTax')}</label>
                    <select className="input" value={mappingForm.target_tax_id} onChange={(e) => setMappingForm({ ...mappingForm, target_tax_id: e.target.value })}>
                      <option value="">—</option>
                      {taxRates.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
                    </select>
                  </div>
                  <Input label={t('fiscalPositions.mappingSourceAccount')} value={mappingForm.source_account_code} onChange={(e) => setMappingForm({ ...mappingForm, source_account_code: e.target.value })} />
                  <Input label={t('fiscalPositions.mappingTargetAccount')} value={mappingForm.target_account_code} onChange={(e) => setMappingForm({ ...mappingForm, target_account_code: e.target.value })} />
                  <div className="flex items-end">
                    <Button onClick={handleCreateMapping}><Plus className="w-4 h-4" /> {t('fiscalPositions.mappingAdd')}</Button>
                  </div>
                </div>

                {mappings.length === 0 ? (
                  <EmptyState icon={<ArrowRight className="w-8 h-8" />} title={t('fiscalPositions.mappingEmpty')} />
                ) : (
                  <Table headers={[t('fiscalPositions.mappingSourceTax'), t('fiscalPositions.mappingTargetTax'), t('fiscalPositions.mappingSourceAccount'), t('fiscalPositions.mappingTargetAccount'), '']}>
                    {mappings.map((m) => {
                      const srcTax = taxRates.find((r) => r.id === m.source_tax_id)
                      const tgtTax = taxRates.find((r) => r.id === m.target_tax_id)
                      return (
                        <TableRow key={m.id}>
                          <TableCell className="text-xs">{srcTax?.name || '—'}</TableCell>
                          <TableCell className="text-xs">{tgtTax?.name || '—'}</TableCell>
                          <TableCell className="font-mono text-xs">{m.source_account_code || '—'}</TableCell>
                          <TableCell className="font-mono text-xs">{m.target_account_code || '—'}</TableCell>
                          <TableCell>
                            <button onClick={() => handleDeleteMapping(m.id)} className="p-1 text-[var(--color-text-secondary)] hover:text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
                          </TableCell>
                        </TableRow>
                      )
                    })}
                  </Table>
                )}
              </div>
            )}

            {activeTab === 'general' && (
              <div className="grid grid-cols-2 gap-4">
                <div><span className="text-sm text-[var(--color-text-secondary)]">{t('fiscalPositions.name')}:</span> <span className="font-medium">{selectedPosition.name}</span></div>
                <div><span className="text-sm text-[var(--color-text-secondary)]">{t('fiscalPositions.country')}:</span> <span className="font-medium">{selectedPosition.country_code || '—'}</span></div>
                <div><span className="text-sm text-[var(--color-text-secondary)]">{t('fiscalPositions.zipFrom')}:</span> <span className="font-medium">{selectedPosition.zip_from || '—'}</span></div>
                <div><span className="text-sm text-[var(--color-text-secondary)]">{t('fiscalPositions.zipTo')}:</span> <span className="font-medium">{selectedPosition.zip_to || '—'}</span></div>
                <div><span className="text-sm text-[var(--color-text-secondary)]">{t('fiscalPositions.autoApply')}:</span> <Badge variant={selectedPosition.auto_apply ? 'success' : 'neutral'}>{selectedPosition.auto_apply ? tCommon('common.yes') : tCommon('common.no')}</Badge></div>
                <div><span className="text-sm text-[var(--color-text-secondary)]">{t('fiscalPositions.active')}:</span> <Badge variant={selectedPosition.active ? 'success' : 'neutral'}>{selectedPosition.active ? tCommon('common.yes') : tCommon('common.no')}</Badge></div>
              </div>
            )}
          </div>
        </Card>
      )}

      <div className="flex justify-end mb-3">
        <Button onClick={() => { resetForm(); setShowForm(true) }}>
          <Plus className="w-4 h-4" /> {t('fiscalPositions.create')}
        </Button>
      </div>

      {positions.length === 0 ? (
        <EmptyState icon={<MapPin className="w-8 h-8" />} title={t('fiscalPositions.empty')} description={t('fiscalPositions.emptyDesc')} />
      ) : (
        <Card>
          <Table headers={[t('fiscalPositions.name'), t('fiscalPositions.country'), t('fiscalPositions.zipFrom'), t('fiscalPositions.zipTo'), t('fiscalPositions.autoApply'), t('fiscalPositions.active'), '']}>
            {positions.map((fp) => (
              <TableRow key={fp.id}>
                <TableCell className="font-medium">{fp.name}</TableCell>
                <TableCell className="text-xs">{fp.country_code || '—'}</TableCell>
                <TableCell className="font-mono text-xs">{fp.zip_from || '—'}</TableCell>
                <TableCell className="font-mono text-xs">{fp.zip_to || '—'}</TableCell>
                <TableCell><Badge variant={fp.auto_apply ? 'success' : 'neutral'}>{fp.auto_apply ? tCommon('common.yes') : tCommon('common.no')}</Badge></TableCell>
                <TableCell><Badge variant={fp.active ? 'success' : 'neutral'}>{fp.active ? tCommon('common.yes') : tCommon('common.no')}</Badge></TableCell>
                <TableCell>
                  <div className="flex gap-1">
                    <button onClick={() => loadMappings(fp)} className="p-1 text-[var(--color-text-secondary)] hover:text-[var(--color-primary)]"><ArrowRight className="w-4 h-4" /></button>
                    <button onClick={() => startEdit(fp)} className="p-1 text-[var(--color-text-secondary)] hover:text-[var(--color-primary)]"><Edit2 className="w-4 h-4" /></button>
                    <button onClick={() => handleDelete(fp.id)} className="p-1 text-[var(--color-text-secondary)] hover:text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}
    </div>
  )
}
