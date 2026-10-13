import { Fragment, useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select, Modal } from '@/components/ui'
import { getFixedAssets, createFixedAsset, updateFixedAsset, deleteFixedAsset, getAssetDepreciations, disposeFixedAsset, generateDepreciationEntry, generateDepreciationEntries, getFiscalYears } from '@/lib/queries/accounting'
import { errorMessage, formatCurrency, formatDate } from '@/lib/utils'
import { Building, Plus, Trash2, X, Calculator, ChevronDown, ChevronRight, TrendingDown, PackageX, BookOpen } from 'lucide-react'
import type { FixedAsset, AssetDepreciation, FiscalYear } from '@/types'
import { useToast } from '@/lib/toast'
import { useStatusLabels } from '@/lib/statusUtils'
import { confirmDialog } from '@/lib/confirm'

export function FixedAssetsPage() {
  const { toast } = useToast()
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { getStatusLabel } = useStatusLabels()
  const [assets, setAssets] = useState<FixedAsset[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [showDisposal, setShowDisposal] = useState<FixedAsset | null>(null)
  const [expanded, setExpanded] = useState<Set<string>>(new Set())
  const [depreciations, setDepreciations] = useState<Record<string, AssetDepreciation[]>>({})

  const [showAccounting, setShowAccounting] = useState<FixedAsset | null>(null)
  // W5 (IMMO-02, IMMO-03) : la dotation se demande POUR UN EXERCICE — celui qui
  // est ouvert. Il n'y a plus de calcul « au jour d'aujourd'hui » côté écran.
  const [fiscalYears, setFiscalYears] = useState<FiscalYear[]>([])
  const openYear = fiscalYears.find((y) => y.status === 'open')

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [assets, years] = await Promise.all([getFixedAssets(), getFiscalYears()])
      setAssets(assets)
      setFiscalYears(years || [])
    } catch (err) { console.error('Failed to load fixed assets:', err)
    toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.loadingError'))
    } finally {
      setLoading(false)
    }
  }, [toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  async function toggleExpand(asset: FixedAsset) {
    const next = new Set(expanded)
    if (next.has(asset.id)) {
      next.delete(asset.id)
    } else {
      next.add(asset.id)
      if (!depreciations[asset.id]) {
        try {
          const deps = await getAssetDepreciations(asset.id)
          setDepreciations((prev) => ({ ...prev, [asset.id]: deps }))
        } catch (err) { console.error('Error loading depreciations:', err); toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.loadingError')) }
      }
    }
    setExpanded(next)
  }

  async function handleDelete(id: string) {
  if (!(await confirmDialog(tCommon('form.confirmDelete')))) return
    try {
      await deleteFixedAsset(id)
      await loadData()
    } catch (err) {
      toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.deleteError'))
    }
  }

  async function handleStatusChange(id: string, status: string) {
    try {
      await updateFixedAsset(id, { status: status as any })
      await loadData()
    } catch (err) {
      toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.updateError'))
    }
  }

  async function handleCalculateDepreciation(id: string) {
    if (!openYear) {
      toast('warning', t('fixedAssets.title'), t('fixedAssets.noOpenYear'))
      return
    }
    try {
      // W5 (IMMO-02) : le moteur COMPTABILISE (D 681x / C 28x) au lieu de
      // recalculer une valeur côté écran — c'est ce que faisait l'ancien
      // `calculateDepreciation`, qui n'écrivait aucune écriture.
      await generateDepreciationEntry(id, openYear.id)
      const deps = await getAssetDepreciations(id)
      setDepreciations((prev) => ({ ...prev, [id]: deps }))
      await loadData()
    } catch (err) {
      toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.updateError'))
    }
  }

  async function handleCalculateAll() {
    if (!openYear) {
      toast('warning', t('fixedAssets.title'), t('fixedAssets.noOpenYear'))
      return
    }
    try {
      const verdict = await generateDepreciationEntries(openYear.id)
      if (verdict.echecs.length > 0) {
        // W5 (IMMO-05) : les échecs sont DITS, nommés, avec leur motif. L'ancien
        // lot les avalait (`console.error`) et rendait une liste partielle comme
        // un succès.
        toast(
          'error',
          t('fixedAssets.depreciationFailures', { count: verdict.echecs.length }),
          verdict.echecs.map((e) => `${e.asset} : ${e.message}`).join(' · ').slice(0, 900),
        )
      } else {
        toast('success', t('fixedAssets.recalcComplete'),
          t('fixedAssets.recalcCompleteMsg', { count: verdict.comptabilisees }))
      }
      await loadData()
    } catch (err) {
      toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.updateError'))
    }
  }

  const totalValue = assets.reduce((s, a) => s + Number(a.current_value), 0)
  const totalPurchase = assets.reduce((s, a) => s + Number(a.purchase_value), 0)
  const totalDepreciation = totalPurchase - totalValue

  return (
    <div>
      <Breadcrumb items={[{ label: t('fixedAssets.title') }]} />
      <PageHeader
        title={t('fixedAssets.title')}
        subtitle={t('fixedAssets.subtitle')}
        action={<div className="flex gap-2"><Button variant="secondary" onClick={handleCalculateAll} disabled={!openYear}><Calculator className="w-4 h-4" /> {t('fixedAssets.calculateDepreciation')}</Button><Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('fixedAssets.new')}</Button></div>}
      />

      <div className="grid grid-cols-3 gap-4 mb-6">
        <Card>
          <div className="p-4">
            <p className="text-sm text-[var(--color-text-secondary)]">{t('fixedAssets.totalPurchaseValue')}</p>
            <p className="text-2xl font-bold font-mono">{formatCurrency(totalPurchase)}</p>
          </div>
        </Card>
        <Card>
          <div className="p-4">
            <p className="text-sm text-[var(--color-text-secondary)] flex items-center gap-1"><TrendingDown className="w-4 h-4 text-[var(--color-danger)]" /> {t('fixedAssets.cumulativeDepreciation')}</p>
            <p className="text-2xl font-bold font-mono text-[var(--color-danger)]">{formatCurrency(totalDepreciation)}</p>
          </div>
        </Card>
        <Card>
          <div className="p-4">
            <p className="text-sm text-[var(--color-text-secondary)]">{t('fixedAssets.currentNetValue')}</p>
            <p className="text-2xl font-bold font-mono">{formatCurrency(totalValue)}</p>
          </div>
        </Card>
      </div>

      {loading ? (
        <SkeletonTable rows={4} cols={8} />
      ) : assets.length === 0 ? (
        <EmptyState
          icon={<Building className="w-8 h-8" />}
          title={t('fixedAssets.noAssets')}
          description={t('fixedAssets.noAssetsDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('fixedAssets.new')}</Button>}
        />
      ) : (
        <Card>
          <Table headers={[t('fixedAssets.code'), t('fixedAssets.name'), t('fixedAssets.category'), t('fixedAssets.purchaseDate'), t('fixedAssets.purchaseValue'), t('fixedAssets.netValue'), t('fixedAssets.depreciation'), tCommon('common.status'), tCommon('table.actions')]}>
            {assets.map((a) => {
              const depreciation = Number(a.purchase_value) - Number(a.current_value)
              const isExpanded = expanded.has(a.id)
              const assetDeps = depreciations[a.id] || []
              return (
                // X8 (balayage des routes) : une ligne et son détail dans un fragment —
                // un <div> entre <tbody> et <tr> faisait un DOM invalide.
                <Fragment key={a.id}>
                  <TableRow>
                    <TableCell className="font-mono text-xs">
                      <div className="flex items-center gap-1">
                        <button
                          onClick={() => toggleExpand(a)}
                          aria-label={tCommon(isExpanded ? 'actions.collapse' : 'actions.expand')}
                          title={tCommon(isExpanded ? 'actions.collapse' : 'actions.expand')}
                          className="w-6 h-6 shrink-0 flex items-center justify-center rounded hover:bg-[var(--color-neutral-100)]"
                        >
                          {isExpanded ? <ChevronDown className="w-3.5 h-3.5" /> : <ChevronRight className="w-3.5 h-3.5" />}
                        </button>
                        {a.code || '—'}
                      </div>
                    </TableCell>
                    <TableCell className="font-medium">{a.name}</TableCell>
                    <TableCell className="text-xs">{a.category || '—'}</TableCell>
                    <TableCell className="text-xs">{formatDate(a.purchase_date)}</TableCell>
                    <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(a.purchase_value))}</TableCell>
                    <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(a.current_value))}</TableCell>
                    <TableCell className="font-mono text-xs text-[var(--color-danger)] text-right">{formatCurrency(depreciation)}</TableCell>
                    <TableCell>
                      <select
                        value={a.status}
                        onChange={(e) => handleStatusChange(a.id, e.target.value)}
                        className="text-xs border border-[var(--color-border)] rounded px-2 py-1 bg-[var(--color-surface)]"
                      >
                        {['active', 'disposed', 'fully_depreciated'].map((k) => <option key={k} value={k}>{getStatusLabel(k)}</option>)}
                      </select>
                    </TableCell>
                    <TableCell>
                      <div className="flex gap-1">
                        <button onClick={() => setShowAccounting(a)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]" title={t('assetAccounts.title')}>
                          <BookOpen className="w-4 h-4" />
                        </button>
                        <button onClick={() => handleCalculateDepreciation(a.id)} disabled={!openYear} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)] disabled:opacity-40 disabled:cursor-not-allowed" title={openYear ? t('fixedAssets.calculateDepreciation') : t('fixedAssets.noOpenYear')}>
                          <Calculator className="w-4 h-4" />
                        </button>
                        {a.status === 'active' && (
                          <button onClick={() => setShowDisposal(a)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-warning)]" title={t('fixedAssets.dispose')}>
                            <PackageX className="w-4 h-4" />
                          </button>
                        )}
                        <button onClick={() => handleDelete(a.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" aria-label={tCommon('actions.delete')} title={tCommon('actions.delete')}>
                          <Trash2 className="w-4 h-4" aria-hidden="true" /></button>
                      </div>
                    </TableCell>
                  </TableRow>
                  {isExpanded && (
                    <tr><td colSpan={9} className="p-0">
                    <div className="px-8 py-3 bg-[var(--color-neutral-50)] border-y border-[var(--color-border)]">
                      <h4 className="text-xs font-semibold mb-2 text-[var(--color-text-secondary)]">{t('fixedAssets.depreciationHistory')}</h4>
                      {assetDeps.length === 0 ? (
                        <p className="text-xs text-[var(--color-text-secondary)]">{t('fixedAssets.noDepreciation')}</p>
                      ) : (
                        <Table headers={[tCommon('common.type'), t('fixedAssets.period'), t('fixedAssets.amount'), t('fixedAssets.cumulative'), t('fixedAssets.netBookValue'), t('fixedAssets.entryNumber')]}>
                          {assetDeps.map((d) => (
                            <TableRow key={d.id}>
                              <TableCell className="text-xs">{t(`fixedAssets.depTypes.${d.depreciation_type}`, { defaultValue: d.depreciation_type })}</TableCell>
                              <TableCell className="text-xs">P{d.period} {d.fiscal_year_code || ''}</TableCell>
                              <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(d.amount))}</TableCell>
                              <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(d.cumulative_amount))}</TableCell>
                              <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(d.net_book_value))}</TableCell>
                              <TableCell className="font-mono text-xs">{d.entry_number || '—'}</TableCell>
                            </TableRow>
                          ))}
                        </Table>
                      )}
                    </div>
                    </td></tr>
                  )}
                </Fragment>
              )
            })}
          </Table>
        </Card>
      )}

      {showForm && (
        <AssetForm onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />
      )}

      {showAccounting && (
        <AssetAccountingModal asset={showAccounting} onClose={() => setShowAccounting(null)} onSaved={() => { setShowAccounting(null); loadData() }} />
      )}

      {showDisposal && (
        <DisposalForm asset={showDisposal} onClose={() => setShowDisposal(null)} onSaved={() => { setShowDisposal(null); loadData() }} />
      )}
    </div>
  )
}

function DisposalForm({ asset, onClose, onSaved }: { asset: FixedAsset; onClose: () => void; onSaved: () => void }) {
  const { toast } = useToast()
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const [disposalValue, setDisposalValue] = useState(0)
  const [disposalDate, setDisposalDate] = useState(new Date().toISOString().split('T')[0])
  const [saving, setSaving] = useState(false)

  const gainLoss = Number(disposalValue) - Number(asset.current_value)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await disposeFixedAsset(asset.id, disposalValue, disposalDate)
      onSaved()
    } catch (err) {
      toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.createError'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('fixedAssets.disposal')}: {asset.name}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div className="p-3 rounded-lg bg-[var(--color-neutral-50)] text-sm space-y-1">
            <div className="flex justify-between"><span className="text-[var(--color-text-secondary)]">{t('fixedAssets.purchaseValue')}:</span><span className="font-mono">{formatCurrency(Number(asset.purchase_value))}</span></div>
            <div className="flex justify-between"><span className="text-[var(--color-text-secondary)]">{t('fixedAssets.netBookValue')}:</span><span className="font-mono">{formatCurrency(Number(asset.current_value))}</span></div>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('fixedAssets.disposalPrice')} type="number" step="0.01" required value={disposalValue} onChange={(e) => setDisposalValue(Number(e.target.value))} />
            <Input label={t('fixedAssets.disposalDate')} type="date" required value={disposalDate} onChange={(e) => setDisposalDate(e.target.value)} />
          </div>
          <div className={`p-3 rounded-lg text-sm ${gainLoss >= 0 ? 'bg-[var(--color-success)]/10 text-[var(--color-success)]' : 'bg-[var(--color-danger)]/10 text-[var(--color-danger)]'}`}>
            {gainLoss >= 0 ? t('fixedAssets.capitalGain') : t('fixedAssets.capitalLoss')}: <strong className="font-mono">{formatCurrency(Math.abs(gainLoss))}</strong>
          </div>
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : t('fixedAssets.confirmDisposal')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}

function AssetForm({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const { toast } = useToast()
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const [name, setName] = useState('')
  const [code, setCode] = useState('')
  const [category, setCategory] = useState('')
  const [purchaseDate, setPurchaseDate] = useState(new Date().toISOString().split('T')[0])
  const [purchaseValue, setPurchaseValue] = useState(0)
  const [usefulLife, setUsefulLife] = useState(5)
  const [residualValue, setResidualValue] = useState(0)
  const [depMethod, setDepMethod] = useState('straight_line')
  const [accountAsset, setAccountAsset] = useState('')
  const [accountDepreciation, setAccountDepreciation] = useState('')
  const [accountExpenseDep, setAccountExpenseDep] = useState('')
  const [assetJournal, setAssetJournal] = useState('')
  const [currencyCode, setCurrencyCode] = useState('EUR')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await createFixedAsset({
        name, code: code || undefined, category,
        purchase_date: purchaseDate,
        purchase_value: purchaseValue,
        // W5 (IMMO-03) : la valeur nette de départ est la valeur d'acquisition.
        // L'écran la calculait « au jour d'aujourd'hui » (`Date.now()`), avec un
        // plan qui n'était pas celui du moteur : deux vérités pour la même
        // immobilisation. Ce sont les dotations qui font baisser `current_value`.
        current_value: purchaseValue,
        depreciation_method: depMethod,
        useful_life_years: usefulLife,
        residual_value: residualValue,
        account_asset_code: accountAsset || null,
        account_depreciation_code: accountDepreciation || null,
        account_expense_depreciation_code: accountExpenseDep || null,
        journal_id: assetJournal || null,
        currency_code: currencyCode || null,
        status: 'active',
      } as any)
      onSaved()
    } catch (err) {
      toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.createError'))
    } finally {
      setSaving(false)
    }
  }

  // E1 (stk-015) : conteneur de 781 px pour un écran de 720, aucun ancêtre ne
  // défilait et « Créer » était hors écran (top = 720 px, clic expiré). Le
  // `Modal` commun borne la fenêtre à l'écran, garde son pied visible et laisse
  // le corps défiler.
  return (
    <form onSubmit={handleSubmit}>
      <Modal
        open
        onClose={onClose}
        title={t('fixedAssets.new')}
        size="lg"
        footer={
          <div className="flex justify-end gap-3">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.create')}</Button>
          </div>
        }
      >
        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('fixedAssets.name')} required value={name} onChange={(e) => setName(e.target.value)} />
            <Input label={t('fixedAssets.code')} value={code} onChange={(e) => setCode(e.target.value)} placeholder="IMMO-001" />
          </div>
          <Input label={t('fixedAssets.category')} value={category} onChange={(e) => setCategory(e.target.value)} placeholder={t('fixedAssets.categoryPlaceholder')} />
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('fixedAssets.purchaseDate')} type="date" required value={purchaseDate} onChange={(e) => setPurchaseDate(e.target.value)} />
            <Input label={t('fixedAssets.purchaseValue')} type="number" step="0.01" required value={purchaseValue} onChange={(e) => setPurchaseValue(Number(e.target.value))} />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('fixedAssets.usefulLifeYears')} type="number" value={usefulLife} onChange={(e) => setUsefulLife(Number(e.target.value))} />
            <Input label={t('fixedAssets.residualValue')} type="number" step="0.01" value={residualValue} onChange={(e) => setResidualValue(Number(e.target.value))} />
          </div>
          {/* W5 (IMMO-04) : « units_of_production » est RETIRÉE de l'écran comme
              du moteur — la fiche ne porte aucun compteur d'unités produites. */}
          <Select label={t('fixedAssets.depreciationMethod')} value={depMethod} onChange={(e) => setDepMethod(e.target.value)} options={[
            { value: 'straight_line', label: t('fixedAssets.depMethods.straight_line') },
            { value: 'declining_balance', label: t('fixedAssets.depMethods.declining_balance') },
          ]} />
          {/* X5 / C13 (décision D-D) : l'amortissement dérogatoire et la subvention
              d'investissement sont RETIRÉS de la fiche — le moteur d'amortissement
              (260) ne les calcule pas et aucune colonne ne les porte ; les offrir
              faisait échouer toute création. Ils seront implémentés en phase 6. */}
          <div className="space-y-3">
            <h3 className="text-sm font-semibold text-[var(--color-text-secondary)]">{t('assetAccounts.title')}</h3>
            <div className="grid grid-cols-2 gap-4">
              <Input label={t('assetAccounts.accountAsset')} value={accountAsset} onChange={(e) => setAccountAsset(e.target.value)} placeholder="210000" />
              <Input label={t('assetAccounts.accountDepreciation')} value={accountDepreciation} onChange={(e) => setAccountDepreciation(e.target.value)} placeholder="281000" />
              <Input label={t('assetAccounts.accountExpenseDepreciation')} value={accountExpenseDep} onChange={(e) => setAccountExpenseDep(e.target.value)} placeholder="681000" />
              <Input label={t('assetAccounts.journal')} value={assetJournal} onChange={(e) => setAssetJournal(e.target.value)} placeholder="IMMO" />
              <Input label={t('currencyCode')} value={currencyCode} onChange={(e) => setCurrencyCode(e.target.value)} placeholder="EUR" />
            </div>
          </div>
        </div>
      </Modal>
    </form>
  )
}

function AssetAccountingModal({ asset, onClose, onSaved }: { asset: FixedAsset; onClose: () => void; onSaved: () => void }) {
  const { toast } = useToast()
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const [accountAsset, setAccountAsset] = useState(asset.account_asset_code || '')
  const [accountDepreciation, setAccountDepreciation] = useState(asset.account_depreciation_code || '')
  const [accountExpenseDep, setAccountExpenseDep] = useState(asset.account_expense_depreciation_code || '')
  const [assetJournal, setAssetJournal] = useState(asset.journal_id || '')
  const [saving, setSaving] = useState(false)
  // R-01 : la dotation se comptabilise dans l'exercice ouvert
  const [fiscalYears, setFiscalYears] = useState<FiscalYear[]>([])
  const [generating, setGenerating] = useState(false)
  const openYear = fiscalYears.find((y) => y.status === 'open')

  useEffect(() => {
    getFiscalYears().then((years) => setFiscalYears(years || [])).catch(() => setFiscalYears([]))
  }, [])

  async function handleGenerateEntry() {
    if (!openYear) {
      toast('warning', t('assetAccounts.title'), t('assetAccounts.noOpenYear'))
      return
    }
    setGenerating(true)
    try {
      await generateDepreciationEntry(asset.id, openYear.id)
      toast('success', t('assetAccounts.title'), t('assetAccounts.entryGenerated'))
      onSaved()
    } catch (err) {
      toast('error', tCommon('toast.error'), errorMessage(err) || t('assetAccounts.entryError'))
    } finally {
      setGenerating(false)
    }
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await updateFixedAsset(asset.id, {
        account_asset_code: accountAsset || null,
        account_depreciation_code: accountDepreciation || null,
        account_expense_depreciation_code: accountExpenseDep || null,
        journal_id: assetJournal || null,
      } as any)
      toast('success', t('assetAccounts.title'), t('assetAccounts.saved'))
      onSaved()
    } catch (err) {
      toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.updateError'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('assetAccounts.title')}: {asset.name}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div className="p-3 rounded-lg bg-[var(--color-neutral-50)] text-sm space-y-1">
            <div className="flex justify-between"><span className="text-[var(--color-text-secondary)]">{t('fixedAssets.code')}:</span><span className="font-mono">{asset.code || '—'}</span></div>
            <div className="flex justify-between"><span className="text-[var(--color-text-secondary)]">{t('fixedAssets.purchaseValue')}:</span><span className="font-mono">{formatCurrency(Number(asset.purchase_value))}</span></div>
            <div className="flex justify-between"><span className="text-[var(--color-text-secondary)]">{t('fixedAssets.netBookValue')}:</span><span className="font-mono">{formatCurrency(Number(asset.current_value))}</span></div>
          </div>
          <Input label={t('assetAccounts.accountAsset')} value={accountAsset} onChange={(e) => setAccountAsset(e.target.value)} placeholder="210000" />
          <Input label={t('assetAccounts.accountDepreciation')} value={accountDepreciation} onChange={(e) => setAccountDepreciation(e.target.value)} placeholder="281000" />
          <Input label={t('assetAccounts.accountExpenseDepreciation')} value={accountExpenseDep} onChange={(e) => setAccountExpenseDep(e.target.value)} placeholder="681000" />
          <Input label={t('assetAccounts.journal')} value={assetJournal} onChange={(e) => setAssetJournal(e.target.value)} placeholder="IMMO" />
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button variant="secondary" type="button" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button variant="secondary" type="button" loading={generating} disabled={!openYear} onClick={handleGenerateEntry}>
              <Calculator className="w-4 h-4" aria-hidden="true" /> {t('assetAccounts.generateDepreciationEntry')}
            </Button>
            <Button type="submit" loading={saving}>{t('assetAccounts.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
