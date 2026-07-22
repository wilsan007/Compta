import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { getAnalyticSections, createAnalyticSection, updateAnalyticSection, deleteAnalyticSection, getAnalyticPlans } from '@/lib/queries'
import { Plus, Pencil, Trash2, X, PieChart } from 'lucide-react'
import type { AnalyticSection, AnalyticPlan } from '@/types'
import { useToast } from '@/lib/toast'

export function AnalyticSectionsPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
const [sections, setSections] = useState<AnalyticSection[]>([])
  const [plans, setPlans] = useState<AnalyticPlan[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<AnalyticSection | null>(null)

  useEffect(() => { load() }, [])

  async function load() {
    try {
      const data = await getAnalyticSections()
      const pl = await getAnalyticPlans().catch(() => [])
      setSections(data || [])
      setPlans(pl || [])
    } catch (err) {
      console.error('Error loading analytic sections:', err)
    } finally {
      setLoading(false)
    }
  }

  function openCreate() { setEditing(null); setShowForm(true) }
  function openEdit(s: AnalyticSection) { setEditing(s); setShowForm(true) }

  async function handleDelete(id: string) {
  if (!window.confirm(t('analyticSections.deleteConfirm'))) return
    try { await deleteAnalyticSection(id); await load() }
    catch (err) { toast('error', tCommon('toast.error'), tCommon('toast.deleteError')) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('analyticSections.breadcrumb') }, { label: t('analyticSections.title') }]} />
      <PageHeader
        title={t('analyticSections.title')}
        subtitle={`${sections.length} ${t('analyticSections.count')}`}
        action={<Button onClick={openCreate}><Plus className="w-4 h-4" /> {t('analyticSections.new')}</Button>}
      />

      {loading ? (
        <SkeletonTable rows={4} cols={5} />
      ) : sections.length === 0 ? (
        <EmptyState
          icon={<PieChart className="w-8 h-8" />}
          title={t('analyticSections.none')}
          description={t('analyticSections.noneDescription')}
          action={<Button onClick={openCreate}><Plus className="w-4 h-4" /> {t('analyticSections.new')}</Button>}
        />
      ) : (
        <Card>
          <Table headers={[tCommon('common.code'), tCommon('common.label'), tCommon('common.type'), t('analyticSections.active'), tCommon('table.actions')]}>
            {sections.map((s) => (
              <TableRow key={s.id}>
                <TableCell className="font-mono font-semibold">{s.code}</TableCell>
                <TableCell>{s.name}</TableCell>
                <TableCell><Badge variant="neutral">{t(`analyticSections.axisLabels.${s.axis || 'other'}`, { defaultValue: s.axis || '—' })}</Badge></TableCell>
                <TableCell><Badge variant={s.active ? 'success' : 'danger'}>{s.active ? tCommon('common.yes') : tCommon('common.no')}</Badge></TableCell>
                <TableCell>
                  <div className="flex gap-2">
                    <button onClick={() => openEdit(s)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]">
                      <Pencil className="w-4 h-4" />
                    </button>
                    <button onClick={() => handleDelete(s.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && (
        <SectionForm
          section={editing}
          sections={sections}
          plans={plans}
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); load() }}
        />
      )}
    </div>
  )
}

function SectionForm({ section, sections, plans, onClose, onSaved }: { section: AnalyticSection | null; sections: AnalyticSection[]; plans: AnalyticPlan[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [activeTab, setActiveTab] = useState('section')
  const [code, setCode] = useState(section?.code || '')
  const [name, setName] = useState(section?.name || '')
  const [axis, setAxis] = useState(section?.axis || 'cost')
  const [active, setActive] = useState(section?.active !== false)
  const [parentId, setParentId] = useState(section?.parent_id || '')
  const [level, setLevel] = useState(String(section?.level || 1))
  const [sectionType, setSectionType] = useState((section as any)?.section_type || 'section')
  const [plan, setPlan] = useState((section as any)?.plan_id || '')
  const [saving, setSaving] = useState(false)

  const parentOptions = sections.filter((s) => s.id !== section?.id)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      const data = { code, name, axis, active, level: Number(level) || 1, parent_id: parentId || undefined, plan_id: plan || undefined, section_type: sectionType }
      if (section) await updateAnalyticSection(section.id, data)
      else await createAnalyticSection(data as any)
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.updateError'))
    } finally {
      setSaving(false)
    }
  }

  const tabs = [
    { id: 'section', label: t('analyticSections.tabs.section') },
    { id: 'complement', label: t('analyticSections.tabs.complement') },
  ]

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '42rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{section ? t('analyticSections.edit') : t('analyticSections.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit}>
          <div className="flex border-b border-[var(--color-border)] px-6">
            {tabs.map((tab) => (
              <button
                key={tab.id}
                type="button"
                onClick={() => setActiveTab(tab.id)}
                className={`px-4 py-2.5 text-sm font-medium border-b-2 transition-colors ${
                  activeTab === tab.id
                    ? 'border-[var(--color-primary)] text-[var(--color-primary)]'
                    : 'border-transparent text-[var(--color-text-secondary)] hover:text-[var(--color-text)]'
                }`}
              >
                {tab.label}
              </button>
            ))}
          </div>

          <div className="p-6 space-y-4">
            {activeTab === 'section' && (
              <>
                <div className="grid grid-cols-2 gap-4">
                  <Input label={tCommon('common.code')} required value={code} onChange={(e) => setCode(e.target.value)} placeholder="A01" />
                  <Input label={tCommon('common.label')} required value={name} onChange={(e) => setName(e.target.value)} placeholder="" />
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <Select label={t('analyticSections.plan')} value={plan} onChange={(e) => setPlan(e.target.value)} options={[
                    { value: '', label: t('analyticSections.defaultPlan') },
                    ...plans.map((p) => ({ value: p.id, label: `${p.code} — ${p.name}` })),
                  ]} />
                  <Select label={t('analyticSections.axis')} value={axis} onChange={(e) => setAxis(e.target.value)} options={[
                    { value: 'cost', label: t('analyticSections.axisLabels.cost') },
                    { value: 'revenue', label: t('analyticSections.axisLabels.revenue') },
                    { value: 'project', label: t('analyticSections.axisLabels.project') },
                    { value: 'department', label: t('analyticSections.axisLabels.department') },
                    { value: 'other', label: t('analyticSections.axisLabels.other') },
                  ]} />
                </div>
                <div>
                  <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('analyticSections.parentSection')}</label>
                  <select className="input" value={parentId} onChange={(e) => setParentId(e.target.value)}>
                    <option value="">{t('analyticSections.noParent')}</option>
                    {parentOptions.map((s) => <option key={s.id} value={s.id}>{s.code} — {s.name}</option>)}
                  </select>
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <Input label={t('analyticSections.level')} type="number" value={level} onChange={(e) => setLevel(e.target.value)} placeholder="1" />
                  <Select label={t('analyticSections.type')} value={sectionType} onChange={(e) => setSectionType(e.target.value)} options={[
                    { value: 'section', label: t('analyticSections.typeSection') },
                    { value: 'total', label: t('analyticSections.typeTotal') },
                  ]} />
                </div>
              </>
            )}

            {activeTab === 'complement' && (
              <>
                <label className="flex items-center gap-2 text-sm">
                  <input type="checkbox" checked={active} onChange={(e) => setActive(e.target.checked)} />
                  {t('analyticSections.active')}
                </label>
                <div className="text-sm text-[var(--color-text-secondary)] p-3 rounded-lg bg-[var(--color-neutral-50)]">
                  {t('analyticSections.complementHint')}
                </div>
              </>
            )}
          </div>

          <div className="flex justify-end gap-3 px-6 py-4 border-t border-[var(--color-border)]">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
