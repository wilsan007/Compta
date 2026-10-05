import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { errorMessage } from '@/lib/utils'
import {
  getUomCategories, createUomCategory, deleteUomCategory,
  getUoms, createUom, deleteUom, convertUom,
  type Uom, type UomCategory,
} from '@/lib/queries/stock'
import { Plus, Trash2, X, Ruler } from 'lucide-react'
import { useToast } from '@/lib/toast'
import { confirmSync } from '@/lib/confirm'

// STK-07 / E.3 : les unités de mesure. La base les portait depuis la 125
// (`uom_categories`, `uoms`, `convert_uom`) sans qu'aucun écran ne les lise.
export function StockUomsPage() {
  const { t } = useTranslation('stock')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [categories, setCategories] = useState<UomCategory[]>([])
  const [uoms, setUoms] = useState<Uom[]>([])
  const [loading, setLoading] = useState(true)
  const [newCategory, setNewCategory] = useState('')
  const [showForm, setShowForm] = useState(false)
  const [fromId, setFromId] = useState('')
  const [toId, setToId] = useState('')
  const [qty, setQty] = useState(1)
  const [result, setResult] = useState<number | null>(null)

  const loadData = useCallback(async () => {
    try {
      const [cats, us] = await Promise.all([getUomCategories(), getUoms()])
      setCategories(cats || [])
      setUoms(us || [])
    } catch (err) { console.error('Error:', err); toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.loadingError')) }
    finally { setLoading(false) }
  }, [tCommon, toast])

  useEffect(() => { loadData() }, [loadData])

  const catName = (id: string) => categories.find((c) => c.id === id)?.name ?? '—'

  async function handleAddCategory() {
    if (!newCategory.trim()) return
    try { await createUomCategory({ name: newCategory.trim() }); setNewCategory(''); await loadData() }
    catch (err) { toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.error')) }
  }

  async function handleDeleteCategory(id: string) {
    if (!confirmSync(t('uoms.confirmDeleteCategory'))) return
    try { await deleteUomCategory(id); await loadData() }
    catch (err) { toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.error')) }
  }

  async function handleDeleteUom(id: string) {
    if (!confirmSync(t('uoms.confirmDelete'))) return
    try { await deleteUom(id); await loadData() }
    catch (err) { toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.error')) }
  }

  async function handleConvert() {
    if (!fromId || !toId) return
    try { setResult(await convertUom(qty, fromId, toId)) }
    catch (err) { setResult(null); toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.error')) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('title'), path: '/stock' }, { label: t('uoms.title') }]} />
      <PageHeader title={t('uoms.title')} subtitle={t('uoms.subtitle')} />

      {loading ? <SkeletonTable rows={3} cols={4} /> : (
        <div className="space-y-6">
          <Card>
            <div className="p-4 border-b border-[var(--color-border)] flex items-center justify-between">
              <h3 className="font-semibold">{t('uoms.categories')}</h3>
              <div className="flex items-end gap-2">
                <Input label={t('uoms.categoryName')} value={newCategory} onChange={(e) => setNewCategory(e.target.value)} />
                <Button onClick={handleAddCategory}><Plus className="w-4 h-4" /> {tCommon('actions.add')}</Button>
              </div>
            </div>
            {categories.length === 0 ? (
              <EmptyState icon={<Ruler className="w-8 h-8" />} title={t('uoms.noCategories')} description={t('uoms.noCategoriesDescription')} />
            ) : (
              <Table headers={[t('uoms.categoryName'), tCommon('common.actions')]}>
                {categories.map((c) => (
                  <TableRow key={c.id}>
                    <TableCell className="text-sm">{c.name}</TableCell>
                    <TableCell>
                      <button onClick={() => handleDeleteCategory(c.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" aria-label={tCommon('actions.delete')} title={tCommon('actions.delete')}><Trash2 className="w-4 h-4" aria-hidden="true" /></button>
                    </TableCell>
                  </TableRow>
                ))}
              </Table>
            )}
          </Card>

          <Card>
            <div className="p-4 border-b border-[var(--color-border)] flex items-center justify-between">
              <h3 className="font-semibold">{t('uoms.units')}</h3>
              <Button onClick={() => setShowForm(true)} disabled={categories.length === 0}><Plus className="w-4 h-4" /> {t('uoms.new')}</Button>
            </div>
            {uoms.length === 0 ? (
              <EmptyState icon={<Ruler className="w-8 h-8" />} title={t('uoms.noUnits')} description={t('uoms.noUnitsDescription')} />
            ) : (
              <Table headers={[t('uoms.code'), t('uoms.name'), t('uoms.category'), t('uoms.factor'), t('uoms.rounding'), tCommon('common.actions')]}>
                {uoms.map((u) => (
                  <TableRow key={u.id}>
                    <TableCell className="font-mono text-xs">{u.code}</TableCell>
                    <TableCell className="text-sm">{u.name}</TableCell>
                    <TableCell className="text-sm">{catName(u.category_id)}</TableCell>
                    <TableCell className="font-mono text-xs">{Number(u.factor)}</TableCell>
                    <TableCell className="font-mono text-xs">{Number(u.rounding ?? 0.01)}</TableCell>
                    <TableCell>
                      <button onClick={() => handleDeleteUom(u.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" aria-label={tCommon('actions.delete')} title={tCommon('actions.delete')}><Trash2 className="w-4 h-4" aria-hidden="true" /></button>
                    </TableCell>
                  </TableRow>
                ))}
              </Table>
            )}
          </Card>

          <Card>
            <div className="p-4 border-b border-[var(--color-border)]"><h3 className="font-semibold">{t('uoms.converter')}</h3></div>
            <div className="p-4 flex items-end gap-3 flex-wrap">
              <div className="w-32"><Input label={t('uoms.quantity')} type="number" step="0.01" value={qty} onChange={(e) => setQty(Number(e.target.value))} /></div>
              <div className="w-48"><Select label={t('uoms.from')} value={fromId} onChange={(e) => setFromId(e.target.value)} options={[{ value: '', label: t('uoms.select') }, ...uoms.map((u) => ({ value: u.id, label: `${u.code} — ${u.name}` }))]} /></div>
              <div className="w-48"><Select label={t('uoms.to')} value={toId} onChange={(e) => setToId(e.target.value)} options={[{ value: '', label: t('uoms.select') }, ...uoms.map((u) => ({ value: u.id, label: `${u.code} — ${u.name}` }))]} /></div>
              <Button onClick={handleConvert} disabled={!fromId || !toId}>{t('uoms.convert')}</Button>
              {result !== null && <div className="text-sm font-semibold px-3 py-2 rounded bg-[var(--color-success)]/10 text-[var(--color-success)]">= {result}</div>}
            </div>
          </Card>
        </div>
      )}

      {showForm && <UomForm categories={categories} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function UomForm({ categories, onClose, onSaved }: { categories: UomCategory[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('stock')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [code, setCode] = useState('')
  const [name, setName] = useState('')
  const [categoryId, setCategoryId] = useState(categories[0]?.id ?? '')
  const [factor, setFactor] = useState(1)
  const [isBase, setIsBase] = useState(false)
  const [rounding, setRounding] = useState(0.01)
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!categoryId) { toast('error', tCommon('toast.error'), t('uoms.selectCategory')); return }
    setSaving(true)
    try {
      await createUom({ code, name, category_id: categoryId, factor, is_base: isBase, rounding })
      onSaved()
    } catch (err) { toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.error')) }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('uoms.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('uoms.code')} required value={code} onChange={(e) => setCode(e.target.value)} placeholder="KG" />
            <Input label={t('uoms.name')} required value={name} onChange={(e) => setName(e.target.value)} />
          </div>
          <Select label={t('uoms.category')} value={categoryId} onChange={(e) => setCategoryId(e.target.value)} options={categories.map((c) => ({ value: c.id, label: c.name }))} />
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('uoms.factor')} type="number" step="0.0001" required value={factor} onChange={(e) => setFactor(Number(e.target.value))} />
            <Input label={t('uoms.rounding')} type="number" step="0.0001" value={rounding} onChange={(e) => setRounding(Number(e.target.value))} />
          </div>
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={isBase} onChange={(e) => setIsBase(e.target.checked)} />
            {t('uoms.isBase')}
          </label>
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
