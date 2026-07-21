import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input } from '@/components/ui'
import { getTvsDeclarations, createTvsDeclaration, deleteTvsDeclaration } from '@/lib/queries'
import { useLocale } from '@/hooks/useLocale'
import { Plus, Trash2, Car } from 'lucide-react'
import type { TvsDeclaration } from '@/types'
import { useToast } from '@/lib/toast'

export function TvsPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatCurrency } = useLocale()
  const [decls, setDecls] = useState<TvsDeclaration[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const data = await getTvsDeclarations()
      setDecls(data || [])
    } catch (err) {
      console.error('Failed to load TVS declarations:', err)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
    if (!window.confirm(t('tvs.deleteConfirm'))) return
    try {
      await deleteTvsDeclaration(id)
      toast('success', tCommon('common.success'), t('tvs.deleteSuccess'))
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    }
  }

  const tableHeaders = [
    t('tvs.fiscalYear'),
    t('tvs.registration'),
    t('tvs.co2'),
    t('tvs.amountCo2'),
    t('tvs.amountAge'),
    t('tvs.amountTotal'),
    t('tvs.status'),
    tCommon('common.table.actions'),
  ]

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb') }, { label: t('etats.breadcrumb') }, { label: t('tvs.breadcrumb') }]} />
      <PageHeader
        title={t('tvs.title')}
        subtitle={t('tvs.subtitle')}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('tvs.new')}</Button>}
      />

      {loading ? (
        <SkeletonTable rows={3} cols={8} />
      ) : decls.length === 0 ? (
        <EmptyState
          icon={<Car className="w-8 h-8" />}
          title={t('tvs.noDeclarations')}
          description={t('tvs.noDeclarationsDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('tvs.new')}</Button>}
        />
      ) : (
        <Card>
          <Table headers={tableHeaders}>
            {decls.map((decl) => (
              <TableRow key={decl.id}>
                <TableCell className="text-sm font-medium">{decl.fiscal_year}</TableCell>
                <TableCell className="font-mono text-xs">{decl.vehicle_registration}</TableCell>
                <TableCell className="text-center text-xs">{decl.co2_emissions || '—'} g/km</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(decl.amount_co2))}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(decl.amount_age))}</TableCell>
                <TableCell className="font-mono text-xs text-right font-semibold">{formatCurrency(Number(decl.amount_total))}</TableCell>
                <TableCell>
                  <Badge variant={decl.status === 'paid' ? 'success' : decl.status === 'filed' ? 'warning' : 'neutral'}>
                    {t(`tvs.statuses.${decl.status}`)}
                  </Badge>
                </TableCell>
                <TableCell>
                  <button onClick={() => handleDelete(decl.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                    <Trash2 className="w-4 h-4" />
                  </button>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && <TvsForm onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function TvsForm({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [fiscalYear, setFiscalYear] = useState(new Date().getFullYear())
  const [registration, setRegistration] = useState('')
  const [co2, setCo2] = useState(0)
  const [firstRegDate, setFirstRegDate] = useState('')
  const [saving, setSaving] = useState(false)

  const amountCo2 = co2 > 0 ? Math.round(co2 * 2) : 0
  const currentYear = new Date().getFullYear()
  const vehicleAge = firstRegDate ? currentYear - new Date(firstRegDate).getFullYear() : 0
  const amountAge = vehicleAge > 0 ? Math.min(vehicleAge * 25, 500) : 0
  const amountTotal = amountCo2 + amountAge

  async function handleSave() {
    if (!registration) {
      toast('warning', tCommon('common.warning'), tCommon('common.fillRequired'))
      return
    }
    setSaving(true)
    try {
      await createTvsDeclaration({
        fiscal_year: Number(fiscalYear),
        vehicle_registration: registration,
        vehicle_type: null,
        co2_emissions: Number(co2) || null,
        first_registration_date: firstRegDate || null,
        amount_co2: amountCo2,
        amount_age: amountAge,
        amount_total: amountTotal,
        status: 'draft',
      })
      toast('success', tCommon('common.success'), t('tvs.saveSuccess'))
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
          <h2 className="text-lg font-semibold">{t('tvs.create')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]">✕</button>
        </div>
        <div className="p-6 space-y-4">
          <Input label={t('tvs.fiscalYear')} type="number" value={fiscalYear} onChange={(e) => setFiscalYear(Number(e.target.value))} required />
          <Input label={t('tvs.registration')} value={registration} onChange={(e) => setRegistration(e.target.value)} required />
          <Input label={t('tvs.co2')} type="number" value={co2} onChange={(e) => setCo2(Number(e.target.value))} />
          <Input label={t('tvs.firstRegistration')} type="date" value={firstRegDate} onChange={(e) => setFirstRegDate(e.target.value)} />
          <div className="flex justify-end gap-6 text-sm border-t border-[var(--color-border)] pt-4">
            <span className="text-[var(--color-text-secondary)]">{t('tvs.amountCo2')}: <strong className="font-mono">{amountCo2.toFixed(2)}</strong></span>
            <span className="text-[var(--color-text-secondary)]">{t('tvs.amountAge')}: <strong className="font-mono">{amountAge.toFixed(2)}</strong></span>
            <span className="text-[var(--color-primary)]">{t('tvs.amountTotal')}: <strong className="font-mono">{amountTotal.toFixed(2)}</strong></span>
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
