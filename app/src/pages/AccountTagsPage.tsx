import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input } from '@/components/ui'
import { useToast } from '@/lib/toast'
import { getAccountTags, createAccountTag, updateAccountTag, deleteAccountTag, getAccountTagMappings, createAccountTagMapping, deleteAccountTagMapping } from '@/lib/queries'
import { Plus, Trash2, Edit2, X, Tag, Link2 } from 'lucide-react'
import type { AccountTag, AccountTagMapping } from '@/types'

type Tab = 'list' | 'application'

export function AccountTagsPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [tags, setTags] = useState<AccountTag[]>([])
  const [loading, setLoading] = useState(true)
  const [activeTab, setActiveTab] = useState<Tab>('list')
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<AccountTag | null>(null)
  const [mappings, setMappings] = useState<AccountTagMapping[]>([])
  const [selectedTag, setSelectedTag] = useState<AccountTag | null>(null)

  const [form, setForm] = useState({
    name: '',
    applicability: 'accounts' as 'accounts' | 'taxes' | 'operations',
    color: '',
    country_code: '',
  })

  const [mappingForm, setMappingForm] = useState({
    entity_type: 'account' as 'account' | 'tax' | 'journal_line',
    entity_id: '',
  })

  const load = useCallback(async () => {
    try {
      setLoading(true)
      setTags(await getAccountTags())
    } catch (err) {
      console.error('Error loading account tags:', err)
      toast('error', t('accountTags.title'), t('accountTags.saveError'))
    } finally {
      setLoading(false)
    }
  }, [toast, t])

  useEffect(() => { load() }, [load])

  function resetForm() {
    setForm({ name: '', applicability: 'accounts', color: '', country_code: '' })
    setEditing(null)
    setShowForm(false)
  }

  function startEdit(tag: AccountTag) {
    setEditing(tag)
    setForm({
      name: tag.name,
      applicability: tag.applicability as 'accounts' | 'taxes' | 'operations',
      color: tag.color || '',
      country_code: tag.country_code || '',
    })
    setShowForm(true)
  }

  async function handleSubmit() {
    try {
      const payload = {
        name: form.name,
        applicability: form.applicability,
        color: form.color || null,
        country_code: form.country_code || null,
      }
      if (editing) {
        await updateAccountTag(editing.id, payload)
        toast('success', t('accountTags.title'), t('accountTags.updateSuccess'))
      } else {
        await createAccountTag(payload)
        toast('success', t('accountTags.title'), t('accountTags.createSuccess'))
      }
      resetForm()
      await load()
    } catch (err) {
      console.error('Error saving tag:', err)
      toast('error', t('accountTags.title'), t('accountTags.saveError'))
    }
  }

  async function handleDelete(id: string) {
    if (!confirm(t('accountTags.deleteConfirm'))) return
    try {
      await deleteAccountTag(id)
      toast('success', t('accountTags.title'), t('accountTags.deleteSuccess'))
      await load()
    } catch (err) {
      console.error('Error deleting tag:', err)
    }
  }

  async function loadMappings(tag: AccountTag) {
    setSelectedTag(tag)
    setActiveTab('application')
    try {
      setMappings(await getAccountTagMappings(tag.id))
    } catch (err) {
      console.error('Error loading tag mappings:', err)
    }
  }

  async function handleCreateMapping() {
    if (!selectedTag || !mappingForm.entity_id) return
    try {
      await createAccountTagMapping({
        tag_id: selectedTag.id,
        entity_type: mappingForm.entity_type,
        entity_id: mappingForm.entity_id,
      })
      setMappingForm({ entity_type: 'account', entity_id: '' })
      setMappings(await getAccountTagMappings(selectedTag.id))
      toast('success', t('accountTags.title'), t('accountTags.mappingCreateSuccess'))
    } catch (err) {
      console.error('Error creating tag mapping:', err)
      toast('error', t('accountTags.title'), t('accountTags.saveError'))
    }
  }

  async function handleDeleteMapping(id: string) {
    if (!confirm(t('accountTags.mappingDeleteConfirm'))) return
    try {
      await deleteAccountTagMapping(id)
      if (selectedTag) setMappings(await getAccountTagMappings(selectedTag.id))
      toast('success', t('accountTags.title'), t('accountTags.mappingDeleteSuccess'))
    } catch (err) {
      console.error('Error deleting tag mapping:', err)
    }
  }

  const applicabilityBadge: Record<string, 'success' | 'warning' | 'neutral'> = {
    accounts: 'success',
    taxes: 'warning',
    operations: 'neutral',
  }

  if (loading) {
    return (
      <div>
        <Breadcrumb items={[{ label: t('title') }, { label: t('home.structure') }, { label: t('accountTags.title') }]} />
        <PageHeader title={t('accountTags.title')} subtitle={t('accountTags.subtitle')} />
        <SkeletonTable rows={5} cols={5} />
      </div>
    )
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('home.structure') }, { label: t('accountTags.title') }]} />
      <PageHeader title={t('accountTags.title')} subtitle={t('accountTags.subtitle')} />

      {selectedTag && (
        <Card className="mb-4">
          <div className="p-4">
            <div className="flex items-center justify-between mb-4">
              <div>
                <h3 className="text-lg font-semibold">{selectedTag.name}</h3>
                <p className="text-sm text-[var(--color-text-secondary)]">{selectedTag.applicability}</p>
              </div>
              <Button variant="secondary" onClick={() => { setSelectedTag(null); setActiveTab('list') }}><X className="w-4 h-4" /></Button>
            </div>

            <div className="flex gap-1 mb-4 border-b border-[var(--color-border)]">
              {([
                { key: 'list' as Tab, label: t('accountTags.title') },
                { key: 'application' as Tab, label: t('fiscalPositions.tabMappings') },
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

            {activeTab === 'application' && (
              <div>
                <div className="grid grid-cols-3 gap-3 mb-4">
                  <div>
                    <label className="block text-xs text-[var(--color-text-secondary)] mb-1">{t('accountTags.applicability')}</label>
                    <select className="input" value={mappingForm.entity_type} onChange={(e) => setMappingForm({ ...mappingForm, entity_type: e.target.value as any })}>
                      <option value="account">{tCommon('common.account')}</option>
                      <option value="tax">{t('taxRates.title')}</option>
                      <option value="journal_line">{t('title')}</option>
                    </select>
                  </div>
                  <Input label={tCommon('common.code')} value={mappingForm.entity_id} onChange={(e) => setMappingForm({ ...mappingForm, entity_id: e.target.value })} />
                  <div className="flex items-end">
                    <Button onClick={handleCreateMapping} disabled={!mappingForm.entity_id}><Plus className="w-4 h-4" /> {t('fiscalPositions.mappingAdd')}</Button>
                  </div>
                </div>

                {mappings.length === 0 ? (
                  <EmptyState icon={<Link2 className="w-8 h-8" />} title={t('fiscalPositions.mappingEmpty')} />
                ) : (
                  <Table headers={[t('accountTags.applicability'), tCommon('common.code'), '']}>
                    {mappings.map((m) => (
                      <TableRow key={m.id}>
                        <TableCell className="text-xs">{m.entity_type}</TableCell>
                        <TableCell className="font-mono text-xs">{m.entity_id}</TableCell>
                        <TableCell>
                          <button onClick={() => handleDeleteMapping(m.id)} className="p-1 text-[var(--color-text-secondary)] hover:text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
                        </TableCell>
                      </TableRow>
                    ))}
                  </Table>
                )}
              </div>
            )}
          </div>
        </Card>
      )}

      {showForm && (
        <Card className="mb-4">
          <div className="p-4">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-semibold">{editing ? t('accountTags.edit') : t('accountTags.create')}</h3>
              <Button variant="secondary" onClick={resetForm}><X className="w-4 h-4" /></Button>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <Input label={t('accountTags.name')} value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required />
              <div>
                <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('accountTags.applicability')}</label>
                <select className="input" value={form.applicability} onChange={(e) => setForm({ ...form, applicability: e.target.value as any })}>
                  <option value="accounts">{tCommon('common.accounts')}</option>
                  <option value="taxes">{t('taxRates.title')}</option>
                  <option value="operations">{tCommon('common.operations')}</option>
                </select>
              </div>
              <Input label={t('accountTags.color')} value={form.color} onChange={(e) => setForm({ ...form, color: e.target.value })} placeholder="#3b82f6" />
              <Input label={t('accountTags.country')} value={form.country_code} onChange={(e) => setForm({ ...form, country_code: e.target.value })} />
              <div className="flex justify-end gap-3 mt-4 col-span-2">
                <Button variant="secondary" onClick={resetForm}>{tCommon('actions.cancel')}</Button>
                <Button onClick={handleSubmit} disabled={!form.name}>{tCommon('actions.save')}</Button>
              </div>
            </div>
          </div>
        </Card>
      )}

      <div className="flex justify-end mb-3">
        <Button onClick={() => setShowForm(true)}>
          <Plus className="w-4 h-4" /> {t('accountTags.create')}
        </Button>
      </div>

      {tags.length === 0 ? (
        <EmptyState icon={<Tag className="w-8 h-8" />} title={t('accountTags.empty')} description={t('accountTags.emptyDesc')} />
      ) : (
        <Card>
          <Table headers={[t('accountTags.name'), t('accountTags.applicability'), t('accountTags.color'), t('accountTags.country'), '']}>
            {tags.map((tag) => (
              <TableRow key={tag.id}>
                <TableCell className="font-medium">
                  {tag.color && <span className="inline-block w-3 h-3 rounded-full mr-2" style={{ backgroundColor: tag.color }} />}
                  {tag.name}
                </TableCell>
                <TableCell><Badge variant={applicabilityBadge[tag.applicability] || 'neutral'}>{tag.applicability}</Badge></TableCell>
                <TableCell className="font-mono text-xs">{tag.color || '—'}</TableCell>
                <TableCell className="text-xs">{tag.country_code || '—'}</TableCell>
                <TableCell>
                  <div className="flex gap-1">
                    <button onClick={() => loadMappings(tag)} className="p-1 text-[var(--color-text-secondary)] hover:text-[var(--color-primary)]"><Link2 className="w-4 h-4" /></button>
                    <button onClick={() => startEdit(tag)} className="p-1 text-[var(--color-text-secondary)] hover:text-[var(--color-primary)]"><Edit2 className="w-4 h-4" /></button>
                    <button onClick={() => handleDelete(tag.id)} className="p-1 text-[var(--color-text-secondary)] hover:text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
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
