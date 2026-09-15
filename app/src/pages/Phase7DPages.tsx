import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { useToast } from '@/lib/toast'
import { getGridTemplates, createGridTemplate, updateGridTemplate, deleteGridTemplate } from '@/lib/queries/misc'
import { getPaymentTemplatesCompta, createPaymentTemplateCompta, updatePaymentTemplateCompta, deletePaymentTemplateCompta } from '@/lib/queries/payroll'
import { getStandardLabels, createStandardLabel, deleteStandardLabel, getAnalyticJournalCodes, createAnalyticJournalCode, updateAnalyticJournalCode, deleteAnalyticJournalCode } from '@/lib/queries/accounting'
import { Plus, Trash2, Edit2 } from 'lucide-react'
import type { GridTemplate, PaymentTemplateCompta, StandardLabel, AnalyticJournalCode } from '@/types'
import { confirmSync } from '@/lib/confirm'

// ============ Grid Templates Page (Modèles de grille) ============
export function GridTemplatesPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [items, setItems] = useState<GridTemplate[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<GridTemplate | null>(null)
  const [form, setForm] = useState({ code: '', name: '', description: '', journal_code: '', default_account: '', columns_config: [] as any[], is_active: true })

  const load = useCallback(async () => {
    try {
      setLoading(true)
      const data = await getGridTemplates()
      setItems(data || [])
    } catch (err) {
      console.error('Error loading grid templates:', err)
      toast('error', t('gridTemplates.title'), t('gridTemplates.loadError'))
    } finally {
      setLoading(false)
    }
  }, [toast, t])

  useEffect(() => { load() }, [load])

  function resetForm() {
    setForm({ code: '', name: '', description: '', journal_code: '', default_account: '', columns_config: [], is_active: true })
    setEditing(null)
    setShowForm(false)
  }

  function startEdit(item: GridTemplate) {
    setEditing(item)
    setForm({ code: item.code, name: item.name, description: item.description || '', journal_code: item.journal_code || '', default_account: item.default_account || '', columns_config: item.columns_config || [], is_active: item.is_active })
    setShowForm(true)
  }

  async function handleSubmit() {
    try {
      if (editing) {
        await updateGridTemplate(editing.id, form)
        toast('success', tCommon('common.success'), tCommon('toast.updated'))
      } else {
        await createGridTemplate(form)
        toast('success', tCommon('common.success'), tCommon('toast.created'))
      }
      resetForm()
      await load()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message)
    }
  }

  async function handleDelete(id: string) {
    if (!confirmSync(tCommon('confirmDelete'))) return
    try {
      await deleteGridTemplate(id)
      await load()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message)
    }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb'), path: '/accounting' }, { label: t('gridTemplates.title') }]} />
      <PageHeader title={t('gridTemplates.title')} subtitle={t('gridTemplates.subtitle')} action={<Button onClick={() => { resetForm(); setShowForm(true) }}><Plus className="w-4 h-4" /> {t('gridTemplates.new')}</Button>} />
      {showForm && (
        <Card className="p-4 mb-4 space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <Input label={t('gridTemplates.code')} value={form.code} onChange={e => setForm({ ...form, code: e.target.value })} />
            <Input label={t('gridTemplates.name')} value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} />
            <Input label={t('gridTemplates.journalCode')} value={form.journal_code} onChange={e => setForm({ ...form, journal_code: e.target.value })} />
            <Input label={t('gridTemplates.defaultAccount')} value={form.default_account} onChange={e => setForm({ ...form, default_account: e.target.value })} />
          </div>
          <Input label={t('gridTemplates.description')} value={form.description} onChange={e => setForm({ ...form, description: e.target.value })} />
          <div className="flex gap-2">
            <Button onClick={handleSubmit}>{editing ? tCommon('actions.save') : tCommon('actions.create')}</Button>
            <Button variant="secondary" onClick={resetForm}>{tCommon('actions.cancel')}</Button>
          </div>
        </Card>
      )}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('gridTemplates.empty')} /> : (
        <Table headers={[t('gridTemplates.code'), t('gridTemplates.name'), t('gridTemplates.journalCode'), t('gridTemplates.defaultAccount'), tCommon('table.actions')]}>
          {items.map(item => (
            <TableRow key={item.id}>
              <TableCell className="font-mono text-xs">{item.code}</TableCell>
              <TableCell>{item.name}</TableCell>
              <TableCell className="font-mono text-xs">{item.journal_code || '-'}</TableCell>
              <TableCell className="font-mono text-xs">{item.default_account || '-'}</TableCell>
              <TableCell>
                <div className="flex gap-2">
                  <button onClick={() => startEdit(item)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]"><Edit2 className="w-4 h-4" /></button>
                  <button onClick={() => handleDelete(item.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
                </div>
              </TableCell>
            </TableRow>
          ))}
        </Table>
      )}
    </div>
  )
}

// ============ Payment Templates Compta Page (Modèles de règlement compta) ============
export function PaymentTemplatesComptaPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [items, setItems] = useState<PaymentTemplateCompta[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<PaymentTemplateCompta | null>(null)
  const [form, setForm] = useState({ code: '', name: '', description: '', payment_method: 'transfer', day_count: 30, end_of_month: false, is_active: true })

  const load = useCallback(async () => {
    try {
      setLoading(true)
      const data = await getPaymentTemplatesCompta()
      setItems(data || [])
    } catch (err) {
      console.error('Error loading payment templates:', err)
      toast('error', t('paymentTemplatesCompta.title'), t('paymentTemplatesCompta.loadError'))
    } finally {
      setLoading(false)
    }
  }, [toast, t])

  useEffect(() => { load() }, [load])

  function resetForm() {
    setForm({ code: '', name: '', description: '', payment_method: 'transfer', day_count: 30, end_of_month: false, is_active: true })
    setEditing(null)
    setShowForm(false)
  }

  function startEdit(item: PaymentTemplateCompta) {
    setEditing(item)
    setForm({ code: item.code, name: item.name, description: item.description || '', payment_method: item.payment_method, day_count: item.day_count, end_of_month: item.end_of_month, is_active: item.is_active })
    setShowForm(true)
  }

  async function handleSubmit() {
    try {
      if (editing) {
        await updatePaymentTemplateCompta(editing.id, form)
        toast('success', tCommon('common.success'), tCommon('toast.updated'))
      } else {
        await createPaymentTemplateCompta(form)
        toast('success', tCommon('common.success'), tCommon('toast.created'))
      }
      resetForm()
      await load()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message)
    }
  }

  async function handleDelete(id: string) {
    if (!confirmSync(tCommon('confirmDelete'))) return
    try {
      await deletePaymentTemplateCompta(id)
      await load()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message)
    }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb'), path: '/accounting' }, { label: t('paymentTemplatesCompta.title') }]} />
      <PageHeader title={t('paymentTemplatesCompta.title')} subtitle={t('paymentTemplatesCompta.subtitle')} action={<Button onClick={() => { resetForm(); setShowForm(true) }}><Plus className="w-4 h-4" /> {t('paymentTemplatesCompta.new')}</Button>} />
      {showForm && (
        <Card className="p-4 mb-4 space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <Input label={t('paymentTemplatesCompta.code')} value={form.code} onChange={e => setForm({ ...form, code: e.target.value })} />
            <Input label={t('paymentTemplatesCompta.name')} value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} />
            <Select label={t('paymentTemplatesCompta.method')} value={form.payment_method} onChange={e => setForm({ ...form, payment_method: e.target.value })}
              options={[{ value: 'transfer', label: t('paymentTemplatesCompta.methods.transfer') }, { value: 'check', label: t('paymentTemplatesCompta.methods.check') }, { value: 'cash', label: t('paymentTemplatesCompta.methods.cash') }, { value: 'direct_debit', label: t('paymentTemplatesCompta.methods.direct_debit') }]} />
            <Input label={t('paymentTemplatesCompta.dayCount')} type="number" value={String(form.day_count)} onChange={e => setForm({ ...form, day_count: Number(e.target.value) })} />
          </div>
          <Input label={t('paymentTemplatesCompta.description')} value={form.description} onChange={e => setForm({ ...form, description: e.target.value })} />
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={form.end_of_month} onChange={e => setForm({ ...form, end_of_month: e.target.checked })} />
            {t('paymentTemplatesCompta.endOfMonth')}
          </label>
          <div className="flex gap-2">
            <Button onClick={handleSubmit}>{editing ? tCommon('actions.save') : tCommon('actions.create')}</Button>
            <Button variant="secondary" onClick={resetForm}>{tCommon('actions.cancel')}</Button>
          </div>
        </Card>
      )}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('paymentTemplatesCompta.empty')} /> : (
        <Table headers={[t('paymentTemplatesCompta.code'), t('paymentTemplatesCompta.name'), t('paymentTemplatesCompta.method'), t('paymentTemplatesCompta.dayCount'), tCommon('table.actions')]}>
          {items.map(item => (
            <TableRow key={item.id}>
              <TableCell className="font-mono text-xs">{item.code}</TableCell>
              <TableCell>{item.name}</TableCell>
              <TableCell>{t(`paymentTemplatesCompta.methods.${item.payment_method}`, { defaultValue: item.payment_method })}</TableCell>
              <TableCell className="font-mono text-xs">{item.day_count}</TableCell>
              <TableCell>
                <div className="flex gap-2">
                  <button onClick={() => startEdit(item)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]"><Edit2 className="w-4 h-4" /></button>
                  <button onClick={() => handleDelete(item.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
                </div>
              </TableCell>
            </TableRow>
          ))}
        </Table>
      )}
    </div>
  )
}

// ============ Standard Labels Page (Libellés / bibliothèque) ============
export function StandardLabelsPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [items, setItems] = useState<StandardLabel[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ code: '', label: '', category: 'general', is_active: true })

  const load = useCallback(async () => {
    try {
      setLoading(true)
      const data = await getStandardLabels()
      setItems(data || [])
    } catch (err) {
      console.error('Error loading standard labels:', err)
      toast('error', t('standardLabels.title'), t('standardLabels.loadError'))
    } finally {
      setLoading(false)
    }
  }, [toast, t])

  useEffect(() => { load() }, [load])

  function resetForm() {
    setForm({ code: '', label: '', category: 'general', is_active: true })
    setShowForm(false)
  }

  async function handleSubmit() {
    try {
      await createStandardLabel(form as any)
      toast('success', tCommon('common.success'), tCommon('toast.created'))
      resetForm()
      await load()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message)
    }
  }

  async function handleDelete(id: string) {
    if (!confirmSync(tCommon('confirmDelete'))) return
    try {
      await deleteStandardLabel(id)
      await load()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message)
    }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb'), path: '/accounting' }, { label: t('standardLabels.title') }]} />
      <PageHeader title={t('standardLabels.title')} subtitle={t('standardLabels.subtitle')} action={<Button onClick={() => { resetForm(); setShowForm(true) }}><Plus className="w-4 h-4" /> {t('standardLabels.new')}</Button>} />
      {showForm && (
        <Card className="p-4 mb-4 space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <Input label={t('standardLabels.code')} value={form.code} onChange={e => setForm({ ...form, code: e.target.value })} />
            <Input label={t('standardLabels.label')} value={form.label} onChange={e => setForm({ ...form, label: e.target.value })} />
          </div>
          <Select label={t('standardLabels.category')} value={form.category} onChange={e => setForm({ ...form, category: e.target.value })}
            options={[{ value: 'general', label: t('standardLabels.categories.general') }, { value: 'invoice', label: t('standardLabels.categories.invoice') }, { value: 'payment', label: t('standardLabels.categories.payment') }, { value: 'journal', label: t('standardLabels.categories.journal') }]} />
          <div className="flex gap-2">
            <Button onClick={handleSubmit}>{tCommon('actions.create')}</Button>
            <Button variant="secondary" onClick={resetForm}>{tCommon('actions.cancel')}</Button>
          </div>
        </Card>
      )}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('standardLabels.empty')} /> : (
        <Table headers={[t('standardLabels.code'), t('standardLabels.label'), t('standardLabels.category'), tCommon('table.actions')]}>
          {items.map(item => (
            <TableRow key={item.id}>
              <TableCell className="font-mono text-xs">{item.code}</TableCell>
              <TableCell>{item.label}</TableCell>
              <TableCell><Badge variant="neutral">{t(`standardLabels.categories.${item.category}`, { defaultValue: item.category })}</Badge></TableCell>
              <TableCell>
                <button onClick={() => handleDelete(item.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
              </TableCell>
            </TableRow>
          ))}
        </Table>
      )}
    </div>
  )
}

// ============ Analytic Journal Codes Page (Codes journaux analytiques) ============
export function AnalyticJournalCodesPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [items, setItems] = useState<AnalyticJournalCode[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<AnalyticJournalCode | null>(null)
  const [form, setForm] = useState({ code: '', name: '', description: '', type: 'analytic', is_active: true })

  const load = useCallback(async () => {
    try {
      setLoading(true)
      const data = await getAnalyticJournalCodes()
      setItems(data || [])
    } catch (err) {
      console.error('Error loading analytic journal codes:', err)
      toast('error', t('analyticJournalCodes.title'), t('analyticJournalCodes.loadError'))
    } finally {
      setLoading(false)
    }
  }, [toast, t])

  useEffect(() => { load() }, [load])

  function resetForm() {
    setForm({ code: '', name: '', description: '', type: 'analytic', is_active: true })
    setEditing(null)
    setShowForm(false)
  }

  function startEdit(item: AnalyticJournalCode) {
    setEditing(item)
    setForm({ code: item.code, name: item.name, description: item.description || '', type: item.type, is_active: item.is_active })
    setShowForm(true)
  }

  async function handleSubmit() {
    try {
      if (editing) {
        await updateAnalyticJournalCode(editing.id, form)
        toast('success', tCommon('common.success'), tCommon('toast.updated'))
      } else {
        await createAnalyticJournalCode(form)
        toast('success', tCommon('common.success'), tCommon('toast.created'))
      }
      resetForm()
      await load()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message)
    }
  }

  async function handleDelete(id: string) {
    if (!confirmSync(tCommon('confirmDelete'))) return
    try {
      await deleteAnalyticJournalCode(id)
      await load()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message)
    }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb'), path: '/accounting' }, { label: t('analyticJournalCodes.title') }]} />
      <PageHeader title={t('analyticJournalCodes.title')} subtitle={t('analyticJournalCodes.subtitle')} action={<Button onClick={() => { resetForm(); setShowForm(true) }}><Plus className="w-4 h-4" /> {t('analyticJournalCodes.new')}</Button>} />
      {showForm && (
        <Card className="p-4 mb-4 space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <Input label={t('analyticJournalCodes.code')} value={form.code} onChange={e => setForm({ ...form, code: e.target.value })} />
            <Input label={t('analyticJournalCodes.name')} value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} />
          </div>
          <Input label={t('analyticJournalCodes.description')} value={form.description} onChange={e => setForm({ ...form, description: e.target.value })} />
          <div className="flex gap-2">
            <Button onClick={handleSubmit}>{editing ? tCommon('actions.save') : tCommon('actions.create')}</Button>
            <Button variant="secondary" onClick={resetForm}>{tCommon('actions.cancel')}</Button>
          </div>
        </Card>
      )}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('analyticJournalCodes.empty')} /> : (
        <Table headers={[t('analyticJournalCodes.code'), t('analyticJournalCodes.name'), t('analyticJournalCodes.type'), tCommon('table.actions')]}>
          {items.map(item => (
            <TableRow key={item.id}>
              <TableCell className="font-mono text-xs">{item.code}</TableCell>
              <TableCell>{item.name}</TableCell>
              <TableCell><Badge variant="primary">{item.type}</Badge></TableCell>
              <TableCell>
                <div className="flex gap-2">
                  <button onClick={() => startEdit(item)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]"><Edit2 className="w-4 h-4" /></button>
                  <button onClick={() => handleDelete(item.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
                </div>
              </TableCell>
            </TableRow>
          ))}
        </Table>
      )}
    </div>
  )
}
