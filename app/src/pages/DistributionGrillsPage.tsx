import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input } from '@/components/ui'
import { getDistributionGrills, createDistributionGrill, deleteDistributionGrill } from '@/lib/queries'
import { Plus, Trash2, Grid3x3 } from 'lucide-react'
import type { DistributionGrill, DistributionGrillLine } from '@/types'
import { useToast } from '@/lib/toast'

export function DistributionGrillsPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [grills, setGrills] = useState<DistributionGrill[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const data = await getDistributionGrills()
      setGrills(data || [])
    } catch (err) {
      console.error('Failed to load distribution grills:', err)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
    if (!window.confirm(t('grills.deleteConfirm'))) return
    try {
      await deleteDistributionGrill(id)
      toast('success', tCommon('common.success'), t('grills.deleteSuccess'))
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    }
  }

  const tableHeaders = [t('grills.name'), t('grills.account'), t('grills.lines'), t('grills.total'), tCommon('common.table.actions')]

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb') }, { label: t('structure.breadcrumb') }, { label: t('grills.breadcrumb') }]} />
      <PageHeader
        title={t('grills.title')}
        subtitle={t('grills.subtitle')}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('grills.new')}</Button>}
      />

      {loading ? (
        <SkeletonTable rows={3} cols={5} />
      ) : grills.length === 0 ? (
        <EmptyState
          icon={<Grid3x3 className="w-8 h-8" />}
          title={t('grills.noGrills')}
          description={t('grills.noGrillsDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('grills.new')}</Button>}
        />
      ) : (
        <Card>
          <Table headers={tableHeaders}>
            {grills.map((grill) => {
              const total = (grill.lines || []).reduce((s, l) => s + Number(l.percentage || 0), 0)
              return (
                <TableRow key={grill.id}>
                  <TableCell className="font-medium text-sm">{grill.name}</TableCell>
                  <TableCell className="font-mono text-xs">{grill.account_code}</TableCell>
                  <TableCell className="text-xs">{(grill.lines || []).length} {t('grills.linesCount')}</TableCell>
                  <TableCell>
                    <Badge variant={Math.abs(total - 100) < 0.01 ? 'success' : 'danger'}>{total}%</Badge>
                  </TableCell>
                  <TableCell>
                    <button onClick={() => handleDelete(grill.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </TableCell>
                </TableRow>
              )
            })}
          </Table>
        </Card>
      )}

      {showForm && <GrillForm onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function GrillForm({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [name, setName] = useState('')
  const [accountCode, setAccountCode] = useState('')
  const [lines, setLines] = useState<DistributionGrillLine[]>([{ id: '', grill_id: '', section_code: '', percentage: 0, created_at: '' }])
  const [saving, setSaving] = useState(false)

  const total = lines.reduce((s, l) => s + Number(l.percentage || 0), 0)

  function addLine() {
    setLines([...lines, { id: '', grill_id: '', section_code: '', percentage: 0, created_at: '' }])
  }

  function updateLine(idx: number, field: keyof DistributionGrillLine, value: string | number) {
    setLines(lines.map((l, i) => i === idx ? { ...l, [field]: value } : l))
  }

  async function handleSave() {
    if (!name || !accountCode || lines.length === 0) {
      toast('warning', tCommon('common.warning'), tCommon('common.fillRequired'))
      return
    }
    if (Math.abs(total - 100) > 0.01) {
      toast('warning', tCommon('common.warning'), t('grills.mustSum100'))
      return
    }
    setSaving(true)
    try {
      await createDistributionGrill({
        name,
        description: null,
        account_code: accountCode,
        journal_code: null,
        active: true,
        lines: lines.map(l => ({ section_code: l.section_code, percentage: Number(l.percentage) })),
      })
      toast('success', tCommon('common.success'), t('grills.saveSuccess'))
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4 overflow-y-auto">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '40rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('grills.create')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]">✕</button>
        </div>
        <div className="p-6 space-y-4 max-h-[70vh] overflow-y-auto">
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('grills.name')} value={name} onChange={(e) => setName(e.target.value)} required />
            <Input label={t('grills.account')} value={accountCode} onChange={(e) => setAccountCode(e.target.value)} required />
          </div>
          <div>
            <div className="flex items-center justify-between mb-2">
              <h3 className="text-sm font-semibold">{t('grills.lines')}</h3>
              <Button variant="secondary" size="sm" onClick={addLine}><Plus className="w-3 h-3" /> {t('grills.addLine')}</Button>
            </div>
            <Table headers={[t('grills.section'), t('grills.percentage'), '']}>
              {lines.map((line, idx) => (
                <TableRow key={idx}>
                  <TableCell>
                    <input className="input text-xs" placeholder="A001" value={line.section_code} onChange={(e) => updateLine(idx, 'section_code', e.target.value)} />
                  </TableCell>
                  <TableCell>
                    <input className="input text-xs text-right w-24" type="number" value={line.percentage} onChange={(e) => updateLine(idx, 'percentage', Number(e.target.value))} />
                  </TableCell>
                  <TableCell>
                    {lines.length > 1 && (
                      <button onClick={() => setLines(lines.filter((_, i) => i !== idx))} className="p-1 text-[var(--color-danger)]">
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    )}
                  </TableCell>
                </TableRow>
              ))}
            </Table>
            <div className="text-right mt-2 text-sm">
              <span className={Math.abs(total - 100) < 0.01 ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}>
                {t('grills.total')}: {total}%
              </span>
            </div>
          </div>
        </div>
        <div className="flex justify-end gap-3 px-6 py-4 border-t border-[var(--color-border)]">
          <Button variant="secondary" onClick={onClose}>{tCommon('common.actions.cancel')}</Button>
          <Button onClick={handleSave} disabled={saving}>{saving ? tCommon('common.saving') : tCommon('common.actions.save')}</Button>
        </div>
      </div>
    </div>
  )
}
