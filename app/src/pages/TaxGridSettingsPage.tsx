import { useState, useEffect } from 'react'
import { useTranslation } from 'react-i18next'
import { useToast } from '@/lib/toast'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, Input, Select } from '@/components/ui'
import { getPayrollTaxGrids, getPayrollTaxGridLines, createPayrollTaxGrid, deletePayrollTaxGrid, getCorporateTaxGrids, getCorporateTaxGridLines, createCorporateTaxGrid, deleteCorporateTaxGrid } from '@/lib/queries/accounting'
import type { PayrollTaxGrid, PayrollTaxGridLine, CorporateTaxGrid, CorporateTaxGridLine } from '@/types'
import { Plus, Trash2, FileText, AlertCircle } from 'lucide-react'

export function TaxGridSettingsPage() {
  const { t } = useTranslation('settings')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [tab, setTab] = useState<'payroll' | 'corporate'>('payroll')
  const [payrollGrids, setPayrollGrids] = useState<PayrollTaxGrid[]>([])
  const [corporateGrids, setCorporateGrids] = useState<CorporateTaxGrid[]>([])
  const [selectedGridId, setSelectedGridId] = useState<string | null>(null)
  const [payrollLines, setPayrollLines] = useState<PayrollTaxGridLine[]>([])
  const [corporateLines, setCorporateLines] = useState<CorporateTaxGridLine[]>([])
  const [loading, setLoading] = useState(true)
  const [showCreateForm, setShowCreateForm] = useState(false)

  useEffect(() => {
    loadData().catch(err => console.error('loadData:', err))
  }, [])

  async function loadData() {
    setLoading(true)
    try {
      const [pg, cg] = await Promise.all([
        getPayrollTaxGrids().catch(() => []),
        getCorporateTaxGrids().catch(() => []),
      ])
      setPayrollGrids(pg as PayrollTaxGrid[])
      setCorporateGrids(cg as CorporateTaxGrid[])
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (selectedGridId && tab === 'payroll') {
      getPayrollTaxGridLines(selectedGridId).then(setPayrollLines).catch(() => setPayrollLines([]))
    } else if (selectedGridId && tab === 'corporate') {
      getCorporateTaxGridLines(selectedGridId).then(setCorporateLines).catch(() => setCorporateLines([]))
    }
  }, [selectedGridId, tab])

  async function handleDeleteGrid(id: string, isPlatform: boolean) {
    if (isPlatform) return
    if (!confirm(t('taxGrids.confirmDelete'))) return
    try {
      if (tab === 'payroll') {
        await deletePayrollTaxGrid(id)
        setPayrollGrids((prev) => prev.filter((g) => g.id !== id))
      } else {
        await deleteCorporateTaxGrid(id)
        setCorporateGrids((prev) => prev.filter((g) => g.id !== id))
      }
      if (selectedGridId === id) setSelectedGridId(null)
    } catch (err: any) { console.error('Failed to delete grid:', err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError'))
    }
  }

  const tabs = [
    { id: 'payroll' as const, label: t('taxGrids.payrollTab') },
    { id: 'corporate' as const, label: t('taxGrids.corporateTab') },
  ]

  const grids = tab === 'payroll' ? payrollGrids : corporateGrids
  const lines = tab === 'payroll' ? payrollLines : corporateLines

  return (
    <div className="animate-fade-in">
      <Breadcrumb items={[{ label: t('title') }, { label: t('taxGrids.title') }]} />
      <PageHeader title={t('taxGrids.title')} subtitle={t('taxGrids.subtitle')} />

      <div className="flex items-center gap-1 mb-6 border-b border-[var(--color-border)]">
        {tabs.map((tb) => (
          <button
            key={tb.id}
            onClick={() => { setTab(tb.id); setSelectedGridId(null) }}
            className={`flex items-center gap-2 px-4 py-2.5 text-sm font-medium border-b-2 transition-colors ${
              tab === tb.id
                ? 'border-[var(--color-primary)] text-[var(--color-primary)]'
                : 'border-transparent text-[var(--color-text-secondary)] hover:text-[var(--color-text)]'
            }`}
          >
            {tb.label}
          </button>
        ))}
      </div>

      {loading ? (
        <Card><div className="p-8 text-center text-[var(--color-text-secondary)]">{t('taxGrids.loading')}</div></Card>
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Grid list */}
          <div className="lg:col-span-1 space-y-4">
            <div className="flex items-center justify-between">
              <h3 className="text-sm font-semibold text-[var(--color-text)]">{t('taxGrids.gridsList')}</h3>
              <Button variant="primary" size="sm" onClick={() => setShowCreateForm(!showCreateForm)}>
                <Plus className="w-4 h-4" /> {t('taxGrids.new')}
              </Button>
            </div>

            {showCreateForm && (
              <CreateGridForm
                tab={tab}
                onCancel={() => setShowCreateForm(false)}
                onCreated={() => { setShowCreateForm(false); loadData() }}
              />
            )}

            {grids.length > 0 ? (
              <div className="space-y-2">
                {grids.map((grid) => {
                  const isPlatform = (grid as any).source === 'platform'
                  const isSelected = selectedGridId === grid.id
                  return (
                    <div
                      key={grid.id}
                      onClick={() => setSelectedGridId(grid.id)}
                      className={`p-3 rounded-lg border cursor-pointer transition-colors ${
                        isSelected
                          ? 'border-[var(--color-primary)] bg-[rgba(0,108,209,0.05)]'
                          : 'border-[var(--color-border)] hover:border-[var(--color-neutral-300)]'
                      }`}
                    >
                      <div className="flex items-start justify-between">
                        <div className="flex-1 min-w-0">
                          <p className="text-sm font-medium text-[var(--color-text)] truncate">{grid.name}</p>
                          <p className="text-xs text-[var(--color-text-secondary)] mt-0.5">
                            {grid.country_code} · {(grid as any).grid_type || (grid as any).tax_type}
                          </p>
                          <div className="flex items-center gap-2 mt-1.5">
                            <Badge variant={grid.status === 'active' ? 'success' : grid.status === 'archived' ? 'neutral' : 'warning'}>
                              {t(`taxGrids.status.${grid.status}`)}
                            </Badge>
                            {isPlatform && (
                              <Badge variant="primary">{t('taxGrids.platform')}</Badge>
                            )}
                            {(grid as any).is_default && (
                              <Badge variant="primary">{t('taxGrids.default')}</Badge>
                            )}
                          </div>
                        </div>
                        {!isPlatform && (
                          <button
                            onClick={(e) => { e.stopPropagation(); handleDeleteGrid(grid.id, false) }}
                            className="text-[var(--color-text-secondary)] hover:text-[var(--color-danger)] p-1"
                          >
                            <Trash2 className="w-4 h-4" />
                          </button>
                        )}
                      </div>
                    </div>
                  )
                })}
              </div>
            ) : (
              <EmptyState
                icon={<FileText className="w-8 h-8" />}
                title={t('taxGrids.noGrids')}
                description={t('taxGrids.noGridsDescription')}
              />
            )}
          </div>

          {/* Grid details / lines */}
          <div className="lg:col-span-2">
            {selectedGridId ? (
              <Card title={t('taxGrids.linesTitle')} subtitle={t('taxGrids.linesSubtitle')}>
                {lines.length > 0 ? (
                  <Table headers={[
                    t('taxGrids.colLabel'),
                    t('taxGrids.colType'),
                    t('taxGrids.colCategory'),
                    t('taxGrids.colBase'),
                    t('taxGrids.colRate'),
                    t('taxGrids.colBracket'),
                  ]}>
                    {lines.map((line) => (
                      <TableRow key={line.id}>
                        <TableCell className="font-medium">{line.label}</TableCell>
                        <TableCell>
                          <Badge variant="neutral">{t(`taxGrids.lineType.${line.line_type}`)}</Badge>
                        </TableCell>
                        <TableCell className="text-sm">
                          {tab === 'payroll'
                            ? String(t(`taxGrids.category.${(line as PayrollTaxGridLine).category}`, (line as PayrollTaxGridLine).category))
                            : '—'}
                        </TableCell>
                        <TableCell className="text-sm">{String(t(`taxGrids.baseType.${line.base_type}`, line.base_type))}</TableCell>
                        <TableCell className="font-mono text-sm">
                          {tab === 'payroll'
                            ? `${(line as PayrollTaxGridLine).rate_employee}% / ${(line as PayrollTaxGridLine).rate_employer}%`
                            : `${(line as CorporateTaxGridLine).rate}%`}
                        </TableCell>
                        <TableCell className="text-xs text-[var(--color-text-secondary)]">
                          {line.line_type === 'bracket'
                            ? `${line.min_amount} - ${line.max_amount ?? '∞'}`
                            : '—'}
                        </TableCell>
                      </TableRow>
                    ))}
                  </Table>
                ) : (
                  <EmptyState
                    icon={<AlertCircle className="w-8 h-8" />}
                    title={t('taxGrids.noLines')}
                    description={t('taxGrids.noLinesDescription')}
                  />
                )}
              </Card>
            ) : (
              <Card>
                <EmptyState
                  icon={<FileText className="w-8 h-8" />}
                  title={t('taxGrids.selectGrid')}
                  description={t('taxGrids.selectGridDescription')}
                />
              </Card>
            )}
          </div>
        </div>
      )}
    </div>
  )
}

function CreateGridForm({ tab, onCancel, onCreated }: { tab: 'payroll' | 'corporate'; onCancel: () => void; onCreated: () => void }) {
  const { t } = useTranslation('settings')
  const { t: tCommon } = useTranslation('common')
  const [name, setName] = useState('')
  const [countryCode, setCountryCode] = useState('')
  const [gridType, setGridType] = useState('')
  const [description, setDescription] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const payrollTypes = [
    { value: 'composite', label: t('taxGrids.gridType.composite') },
    { value: 'its', label: t('taxGrids.gridType.its') },
    { value: 'employer_contribution', label: t('taxGrids.gridType.employer_contribution') },
    { value: 'employee_contribution', label: t('taxGrids.gridType.employee_contribution') },
    { value: 'income_tax', label: t('taxGrids.gridType.income_tax') },
    { value: 'other_deduction', label: t('taxGrids.gridType.other_deduction') },
  ]

  const corporateTypes = [
    { value: 'corporate_income_tax', label: t('taxGrids.taxType.corporate_income_tax') },
    { value: 'minimum_tax', label: t('taxGrids.taxType.minimum_tax') },
    { value: 'turnover_tax', label: t('taxGrids.taxType.turnover_tax') },
    { value: 'withholding_tax', label: t('taxGrids.taxType.withholding_tax') },
  ]

  const types = tab === 'payroll' ? payrollTypes : corporateTypes

  async function handleCreate() {
    if (!name.trim() || !countryCode.trim() || !gridType) {
      setError(t('taxGrids.requiredFields'))
      return
    }
    setSaving(true)
    setError(null)
    try {
      if (tab === 'payroll') {
        await createPayrollTaxGrid({
          country_code: countryCode,
          grid_type: gridType as any,
          name: name.trim(),
          description: description.trim() || null,
          effective_from: new Date().toISOString().split('T')[0],
          effective_to: null,
          status: 'draft',
          source: 'manual',
          file_url: null,
          is_default: false,
        })
      } else {
        await createCorporateTaxGrid({
          country_code: countryCode,
          tax_type: gridType as any,
          name: name.trim(),
          description: description.trim() || null,
          effective_from: new Date().toISOString().split('T')[0],
          effective_to: null,
          status: 'draft',
          source: 'manual',
          file_url: null,
          is_default: false,
        })
      }
      onCreated()
    } catch (err: any) {
      setError(err.message || t('taxGrids.createError'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <Card>
      <div className="space-y-3">
        <Input label={t('taxGrids.name')} value={name} onChange={(e) => setName(e.target.value)} placeholder={t('taxGrids.namePlaceholder')} />
        <div className="grid grid-cols-2 gap-3">
          <Input label={t('taxGrids.countryCode')} value={countryCode} onChange={(e) => setCountryCode(e.target.value.toUpperCase())} placeholder="FR, SN, MA..." />
          <Select label={t('taxGrids.type')} value={gridType} onChange={(e) => setGridType(e.target.value)} options={types} />
        </div>
        <Input label={t('taxGrids.description')} value={description} onChange={(e) => setDescription(e.target.value)} />
        {error && <p className="text-sm text-[var(--color-danger)]">{error}</p>}
        <div className="flex justify-end gap-2">
          <Button variant="secondary" size="sm" onClick={onCancel}>{t('taxGrids.cancel')}</Button>
          <Button variant="primary" size="sm" onClick={handleCreate} disabled={saving}>
            {saving ? tCommon('actions.saving') : t('taxGrids.create')}
          </Button>
        </div>
      </div>
    </Card>
  )
}
