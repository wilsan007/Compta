import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, AutoBreadcrumb, SkeletonTable, Input, Select, ConfirmDialog } from '@/components/ui'
import { Tag, Plus, Trash2, Edit2, X } from 'lucide-react'
import { useToast } from '@/lib/toast'
import {
  getPartnerCategories, createPartnerCategory, updatePartnerCategory, deletePartnerCategory,
} from '@/lib/queries'
import type { PartnerCategory } from '@/types'

export function PartnerCategoriesPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [categories, setCategories] = useState<PartnerCategory[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<PartnerCategory | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<PartnerCategory | null>(null)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const data = await getPartnerCategories()
      setCategories(data || [])
    } catch { } finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
    try {
      await deletePartnerCategory(id)
      toast('success', tCommon('common.success'), t('partnerCategories.deleted'))
      await loadData()
    } catch (e: any) { toast('error', tCommon('common.error'), e.message) }
  }

  const colorClass: Record<string, string> = {
    blue: 'bg-blue-100 text-blue-700',
    green: 'bg-green-100 text-green-700',
    red: 'bg-red-100 text-red-700',
    yellow: 'bg-yellow-100 text-yellow-700',
    purple: 'bg-purple-100 text-purple-700',
    gray: 'bg-gray-100 text-gray-700',
  }

  return (
    <div>
      <AutoBreadcrumb />
      <PageHeader
        title={t('partnerCategories.title')}
        subtitle={t('partnerCategories.subtitle')}
        action={<Button onClick={() => { setEditing(null); setShowForm(true) }}><Plus className="w-4 h-4" /> {t('partnerCategories.new')}</Button>}
      />

      {loading ? <SkeletonTable rows={4} cols={4} /> : categories.length === 0 ? (
        <EmptyState
          icon={<Tag className="w-8 h-8" />}
          title={t('partnerCategories.empty')}
          description={t('partnerCategories.emptyDescription')}
          action={<Button onClick={() => { setEditing(null); setShowForm(true) }}><Plus className="w-4 h-4" /> {t('partnerCategories.new')}</Button>}
        />
      ) : (
        <Card>
          <Table headers={[t('partnerCategories.colName'), t('partnerCategories.colColor'), t('partnerCategories.colParent'), tCommon('common.actions')]}>
            {categories.map((c) => {
              const parent = categories.find((p) => p.id === c.parent_id)
              return (
                <TableRow key={c.id}>
                  <TableCell className="font-medium">
                    <span className={`inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full text-xs ${colorClass[c.color || 'gray'] || colorClass.gray}`}>
                      <Tag className="w-3 h-3" /> {c.name}
                    </span>
                  </TableCell>
                  <TableCell><Badge>{c.color || 'gray'}</Badge></TableCell>
                  <TableCell className="text-xs">{parent?.name || '—'}</TableCell>
                  <TableCell>
                    <div className="flex gap-1">
                      <Button variant="secondary" size="sm" onClick={() => { setEditing(c); setShowForm(true) }}><Edit2 className="w-3 h-3" /></Button>
                      <Button variant="danger" size="sm" onClick={() => setDeleteTarget(c)}><Trash2 className="w-3 h-3" /></Button>
                    </div>
                  </TableCell>
                </TableRow>
              )
            })}
          </Table>
        </Card>
      )}

      {showForm && (
        <CategoryForm
          category={editing}
          categories={categories}
          onClose={() => { setShowForm(false); setEditing(null) }}
          onSaved={() => { setShowForm(false); setEditing(null); loadData() }}
        />
      )}

      <ConfirmDialog
        open={!!deleteTarget}
        title={t('partnerCategories.delete')}
        message={t('partnerCategories.deleteConfirm', { name: deleteTarget?.name })}
        confirmLabel={tCommon('actions.delete')}
        onConfirm={() => { if (deleteTarget) handleDelete(deleteTarget.id); setDeleteTarget(null) }}
        onCancel={() => setDeleteTarget(null)}
      />
    </div>
  )
}

function CategoryForm({ category, categories, onClose, onSaved }: {
  category: PartnerCategory | null
  categories: PartnerCategory[]
  onClose: () => void
  onSaved: () => void
}) {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [name, setName] = useState(category?.name || '')
  const [color, setColor] = useState(category?.color || 'blue')
  const [parentId, setParentId] = useState(category?.parent_id || '')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      const data = { name, color, parent_id: parentId || null }
      if (category) {
        await updatePartnerCategory(category.id, data)
        toast('success', tCommon('common.success'), t('partnerCategories.updated'))
      } else {
        await createPartnerCategory(data as any)
        toast('success', tCommon('common.success'), t('partnerCategories.created'))
      }
      onSaved()
    } catch (e: any) {
      toast('error', tCommon('common.error'), e.message)
    } finally { setSaving(false) }
  }

  const availableParents = categories.filter((c) => c.id !== category?.id)

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{category ? t('partnerCategories.edit') : t('partnerCategories.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label={t('partnerCategories.colName')} required value={name} onChange={e => setName(e.target.value)} />
          <Select label={t('partnerCategories.colColor')} value={color} onChange={e => setColor(e.target.value)}
            options={[
              { value: 'blue', label: '🔵 Blue' },
              { value: 'green', label: '🟢 Green' },
              { value: 'red', label: '🔴 Red' },
              { value: 'yellow', label: '🟡 Yellow' },
              { value: 'purple', label: '🟣 Purple' },
              { value: 'gray', label: '⚪ Gray' },
            ]} />
          <Select label={t('partnerCategories.colParent')} value={parentId} onChange={e => setParentId(e.target.value)}
            options={[{ value: '', label: t('partnerCategories.noParent') }, ...availableParents.map((c) => ({ value: c.id, label: c.name }))]} />
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button variant="secondary" type="button" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
