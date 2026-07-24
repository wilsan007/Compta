import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input } from '@/components/ui'
import { useToast } from '@/lib/toast'
import { getPaymentTerms, createPaymentTerm, updatePaymentTerm, deletePaymentTerm } from '@/lib/queries'
import { Plus, Trash2, Edit2, X, CalendarDays } from 'lucide-react'
import type { PaymentTerm } from '@/types'

export function PaymentTermsPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [terms, setTerms] = useState<PaymentTerm[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<PaymentTerm | null>(null)

  const [form, setForm] = useState({
    code: '',
    name: '',
    type: 'fixed' as PaymentTerm['type'],
    days_1: 30,
    days_2: null as number | null,
    pct_1: 100,
    pct_2: null as number | null,
    end_of_month: false,
    description: '',
    active: true,
  })

  const load = useCallback(async () => {
    try {
      setLoading(true)
      const data = await getPaymentTerms()
      setTerms(data || [])
    } catch (err) {
      console.error('Error loading payment terms:', err)
      toast('error', t('paymentTerms.title'), t('paymentTerms.loadError'))
    } finally {
      setLoading(false)
    }
  }, [toast, t])

  useEffect(() => { load() }, [load])

  function resetForm() {
    setForm({ code: '', name: '', type: 'fixed', days_1: 30, days_2: null, pct_1: 100, pct_2: null, end_of_month: false, description: '', active: true })
    setEditing(null)
    setShowForm(false)
  }

  function startEdit(term: PaymentTerm) {
    setEditing(term)
    setForm({
      code: term.code, name: term.name, type: term.type,
      days_1: term.days_1, days_2: term.days_2, pct_1: term.pct_1, pct_2: term.pct_2,
      end_of_month: term.end_of_month, description: term.description || '', active: term.active,
    })
    setShowForm(true)
  }

  async function handleSubmit() {
    try {
      const payload = { ...form, days_2: form.days_2 || null, pct_2: form.pct_2 || null }
      if (editing) {
        await updatePaymentTerm(editing.id, payload)
        toast('success', t('paymentTerms.title'), t('paymentTerms.updateSuccess'))
      } else {
        await createPaymentTerm(payload as any)
        toast('success', t('paymentTerms.title'), t('paymentTerms.createSuccess'))
      }
      resetForm()
      await load()
    } catch (err) {
      console.error('Error saving payment term:', err)
      toast('error', t('paymentTerms.title'), t('paymentTerms.saveError'))
    }
  }

  async function handleDelete(id: string) {
    if (!confirm(t('paymentTerms.deleteConfirm'))) return
    try {
      await deletePaymentTerm(id)
      toast('success', t('paymentTerms.title'), t('paymentTerms.deleteSuccess'))
      await load()
    } catch (err) {
      console.error('Error deleting payment term:', err)
      toast('error', t('paymentTerms.title'), t('paymentTerms.deleteError'))
    }
  }

  const typeBadge: Record<string, 'success' | 'warning' | 'neutral'> = {
    fixed: 'success', end_of_month: 'warning', split: 'neutral',
  }

  if (loading) {
    return (
      <div>
        <Breadcrumb items={[{ label: t('title') }, { label: t('home.structure') }, { label: t('paymentTerms.title') }]} />
        <PageHeader title={t('paymentTerms.title')} subtitle={t('paymentTerms.subtitle')} />
        <SkeletonTable rows={4} cols={6} />
      </div>
    )
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('home.structure') }, { label: t('paymentTerms.title') }]} />
      <PageHeader title={t('paymentTerms.title')} subtitle={t('paymentTerms.subtitle')} />

      {showForm && (
        <Card className="mb-4">
          <div className="p-4">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-semibold">{editing ? t('paymentTerms.edit') : t('paymentTerms.create')}</h3>
              <Button variant="secondary" onClick={resetForm}><X className="w-4 h-4" /></Button>
            </div>
            <div className="grid grid-cols-3 gap-4">
              <Input label={t('paymentTerms.code')} value={form.code} onChange={(e) => setForm({ ...form, code: e.target.value })} required />
              <Input label={t('paymentTerms.name')} value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required />
              <div>
                <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('paymentTerms.type')}</label>
                <select className="input" value={form.type} onChange={(e) => setForm({ ...form, type: e.target.value as any })}>
                  <option value="fixed">{t('paymentTerms.typeFixed')}</option>
                  <option value="end_of_month">{t('paymentTerms.typeEndOfMonth')}</option>
                  <option value="split">{t('paymentTerms.typeSplit')}</option>
                </select>
              </div>
              <Input label={t('paymentTerms.days1')} type="number" value={form.days_1} onChange={(e) => setForm({ ...form, days_1: Number(e.target.value) })} required />
              <Input label={t('paymentTerms.pct1')} type="number" step="0.01" value={form.pct_1} onChange={(e) => setForm({ ...form, pct_1: Number(e.target.value) })} required />
              {form.type === 'split' && (
                <>
                  <Input label={t('paymentTerms.days2')} type="number" value={form.days_2 || ''} onChange={(e) => setForm({ ...form, days_2: Number(e.target.value) || null })} />
                  <Input label={t('paymentTerms.pct2')} type="number" step="0.01" value={form.pct_2 || ''} onChange={(e) => setForm({ ...form, pct_2: Number(e.target.value) || null })} />
                </>
              )}
              <div className="flex items-end">
                <label className="flex items-center gap-2 text-sm">
                  <input type="checkbox" checked={form.end_of_month} onChange={(e) => setForm({ ...form, end_of_month: e.target.checked })} />
                  {t('paymentTerms.endOfMonth')}
                </label>
              </div>
              <Input label={t('paymentTerms.description')} value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} />
              <div className="flex items-end">
                <label className="flex items-center gap-2 text-sm">
                  <input type="checkbox" checked={form.active} onChange={(e) => setForm({ ...form, active: e.target.checked })} />
                  {tCommon('common.active')}
                </label>
              </div>
            </div>
            <div className="flex justify-end gap-3 mt-4">
              <Button variant="secondary" onClick={resetForm}>{tCommon('actions.cancel')}</Button>
              <Button onClick={handleSubmit} disabled={!form.code || !form.name}>{tCommon('actions.save')}</Button>
            </div>
          </div>
        </Card>
      )}

      <div className="flex justify-end mb-3">
        <Button onClick={() => { resetForm(); setShowForm(true) }}>
          <Plus className="w-4 h-4" /> {t('paymentTerms.create')}
        </Button>
      </div>

      {terms.length === 0 ? (
        <EmptyState icon={<CalendarDays className="w-8 h-8" />} title={t('paymentTerms.empty')} description={t('paymentTerms.emptyDesc')} />
      ) : (
        <Card>
          <Table headers={[
            t('paymentTerms.code'),
            t('paymentTerms.name'),
            t('paymentTerms.type'),
            t('paymentTerms.days'),
            t('paymentTerms.pct'),
            t('paymentTerms.status'),
            '',
          ]}>
            {terms.map((term) => (
              <TableRow key={term.id}>
                <TableCell className="font-mono font-semibold">{term.code}</TableCell>
                <TableCell className="font-medium">{term.name}</TableCell>
                <TableCell><Badge variant={typeBadge[term.type] || 'neutral'}>{t(`paymentTerms.type${term.type === 'end_of_month' ? 'EndOfMonth' : term.type.charAt(0).toUpperCase() + term.type.slice(1)}`)}</Badge></TableCell>
                <TableCell className="text-xs">
                  {term.type === 'split' ? `${term.days_1}j / ${term.days_2}j` : `${term.days_1}j${term.end_of_month ? ' FM' : ''}`}
                </TableCell>
                <TableCell className="text-xs">
                  {term.type === 'split' ? `${term.pct_1}% / ${term.pct_2}%` : `${term.pct_1}%`}
                </TableCell>
                <TableCell><Badge variant={term.active ? 'success' : 'neutral'}>{term.active ? tCommon('common.active') : tCommon('common.inactive')}</Badge></TableCell>
                <TableCell>
                  <div className="flex gap-1">
                    <button onClick={() => startEdit(term)} className="p-1 text-[var(--color-text-secondary)] hover:text-[var(--color-primary)]"><Edit2 className="w-4 h-4" /></button>
                    <button onClick={() => handleDelete(term.id)} className="p-1 text-[var(--color-text-secondary)] hover:text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
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
