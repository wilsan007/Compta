import { useCallback, useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Input, Select, Badge, EmptyState, Breadcrumb, Skeleton } from '@/components/ui'
import { errorMessage } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import { confirmSync } from '@/lib/confirm'
import {
  getCustomFieldDefinitions,
  createCustomFieldDefinition,
  deleteCustomFieldDefinition,
  getCustomFieldValues,
  setCustomFieldValue,
  getProjectOptions,
  FIELD_TYPES,
  type CustomFieldDefinition,
  type ProjectOption,
} from '@/lib/queries/customFields'
import { ListPlus, Plus, Trash2, SlidersHorizontal } from 'lucide-react'

// Premier module branché (documenté dans la migration 706) : les projets.
const MODULE = 'projects'
const ENTITY = 'project'

export function CustomFieldsPage() {
  const { t } = useTranslation('settings')
  const { t: tNav } = useTranslation('nav')
  const { toast } = useToast()

  const [definitions, setDefinitions] = useState<CustomFieldDefinition[]>([])
  const [projects, setProjects] = useState<ProjectOption[]>([])
  const [projectId, setProjectId] = useState('')
  const [values, setValues] = useState<Record<string, string>>({})
  const [loading, setLoading] = useState(true)

  const [key, setKey] = useState('')
  const [label, setLabel] = useState('')
  const [fieldType, setFieldType] = useState<string>('text')
  const [options, setOptions] = useState('')

  const loadDefinitions = useCallback(async () => {
    try {
      const [defs, projs] = await Promise.all([
        getCustomFieldDefinitions(MODULE, ENTITY),
        getProjectOptions(),
      ])
      setDefinitions(defs)
      setProjects(projs)
      setProjectId((cur) => (cur && projs.some((p) => p.id === cur) ? cur : (projs[0]?.id ?? '')))
    } catch (err) {
      toast('error', t('customFields.title'), errorMessage(err))
    } finally {
      setLoading(false)
    }
  }, [toast, t])

  const loadValues = useCallback(async (recordId: string) => {
    if (!recordId) { setValues({}); return }
    try {
      const rows = await getCustomFieldValues(recordId)
      const map: Record<string, string> = {}
      for (const r of rows) map[r.definition_id] = String(r.value ?? '')
      setValues(map)
    } catch (err) {
      toast('error', t('customFields.title'), errorMessage(err))
    }
  }, [toast, t])

  useEffect(() => { loadDefinitions() }, [loadDefinitions])
  useEffect(() => { loadValues(projectId) }, [projectId, loadValues])

  async function handleCreate() {
    if (!key.trim() || !label.trim()) return
    try {
      await createCustomFieldDefinition({
        module: MODULE,
        entity: ENTITY,
        fieldKey: key.trim(),
        label: label.trim(),
        fieldType,
        options: fieldType === 'select' ? options.split(',').map((o) => o.trim()).filter(Boolean) : [],
      })
      setKey(''); setLabel(''); setOptions('')
      await loadDefinitions()
    } catch (err) {
      toast('error', t('customFields.title'), errorMessage(err))
    }
  }

  async function handleDelete(id: string) {
    if (!confirmSync(t('customFields.confirmDelete'))) return
    try {
      await deleteCustomFieldDefinition(id)
      await loadDefinitions()
    } catch (err) {
      toast('error', t('customFields.title'), errorMessage(err))
    }
  }

  async function handleSave() {
    if (!projectId) return
    try {
      for (const d of definitions) {
        const raw = values[d.id] ?? ''
        if (raw === '') continue
        let value: unknown = raw
        if (d.field_type === 'number') value = Number(raw)
        else if (d.field_type === 'boolean') value = raw === 'true'
        await setCustomFieldValue(d.id, projectId, value)
      }
      toast('success', t('customFields.saved'), '')
    } catch (err) {
      toast('error', t('customFields.title'), errorMessage(err))
    }
  }

  function renderInput(d: CustomFieldDefinition) {
    const v = values[d.id] ?? ''
    const onChange = (val: string) => setValues((cur) => ({ ...cur, [d.id]: val }))
    if (d.field_type === 'boolean') {
      return (
        <Select label={d.label} value={v} onChange={(e) => onChange(e.target.value)}>
          <option value="">—</option>
          <option value="true">{t('customFields.yes')}</option>
          <option value="false">{t('customFields.no')}</option>
        </Select>
      )
    }
    if (d.field_type === 'select') {
      return (
        <Select label={d.label} value={v} onChange={(e) => onChange(e.target.value)}>
          <option value="">—</option>
          {d.options.map((o) => <option key={o} value={o}>{o}</option>)}
        </Select>
      )
    }
    return (
      <Input
        label={d.label}
        type={d.field_type === 'number' ? 'number' : d.field_type === 'date' ? 'date' : 'text'}
        value={v}
        onChange={(e) => onChange(e.target.value)}
      />
    )
  }

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('groups.system') }, { label: t('customFields.title') }]} />
      <PageHeader title={t('customFields.title')} subtitle={t('customFields.subtitle')} />

      {loading ? (
        <Skeleton className="h-40 w-full" />
      ) : (
        <div className="space-y-6">
          <Card>
            <div className="flex items-center gap-2 mb-3">
              <SlidersHorizontal className="w-5 h-5 text-[var(--color-primary)]" aria-hidden="true" />
              <h3 className="font-semibold">{t('customFields.definitions')}</h3>
            </div>
            <div className="grid grid-cols-1 md:grid-cols-5 gap-2 mb-4">
              <Input label={t('customFields.key')} value={key} onChange={(e) => setKey(e.target.value)} placeholder="affaire_ref" />
              <Input label={t('customFields.label')} value={label} onChange={(e) => setLabel(e.target.value)} />
              <Select label={t('customFields.type')} value={fieldType} onChange={(e) => setFieldType(e.target.value)}>
                {FIELD_TYPES.map((ft) => <option key={ft} value={ft}>{t(`customFields.types.${ft}`)}</option>)}
              </Select>
              <Input label={t('customFields.options')} value={options}
                onChange={(e) => setOptions(e.target.value)} disabled={fieldType !== 'select'} />
              <div className="flex items-end">
                <Button onClick={handleCreate} disabled={!key.trim() || !label.trim()}>
                  <Plus className="w-4 h-4 mr-1" aria-hidden="true" />{t('customFields.create')}
                </Button>
              </div>
            </div>

            {definitions.length === 0 ? (
              <EmptyState icon={<ListPlus className="w-8 h-8" aria-hidden="true" />} title={t('customFields.empty')} />
            ) : (
              <ul className="divide-y divide-[var(--color-border)]">
                {definitions.map((d) => (
                  <li key={d.id} className="flex items-center justify-between py-2">
                    <div>
                      <span className="font-medium">{d.label}</span>{' '}
                      <span className="text-xs font-mono text-[var(--color-text-secondary)]">{d.field_key}</span>{' '}
                      <Badge variant="neutral">{t(`customFields.types.${d.field_type}`)}</Badge>
                    </div>
                    <button
                      type="button"
                      onClick={() => handleDelete(d.id)}
                      aria-label={t('customFields.remove')}
                      title={t('customFields.remove')}
                      className="text-[var(--color-danger)] min-w-[24px] min-h-[24px]"
                    >
                      <Trash2 className="w-4 h-4" aria-hidden="true" />
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </Card>

          {definitions.length > 0 && projects.length > 0 && (
            <Card>
              <h3 className="font-semibold mb-3">{t('customFields.values')}</h3>
              <div className="mb-4 max-w-md">
                <Select label={t('customFields.record')} value={projectId} onChange={(e) => setProjectId(e.target.value)}>
                  {projects.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
                </Select>
              </div>
              <div className="grid grid-cols-1 md:grid-cols-3 gap-2 mb-4">
                {definitions.map((d) => <div key={d.id}>{renderInput(d)}</div>)}
              </div>
              <Button onClick={handleSave} disabled={!projectId}>{t('customFields.save')}</Button>
            </Card>
          )}
        </div>
      )}
    </div>
  )
}

