import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, EmptyState, AutoBreadcrumb, Select, Input } from '@/components/ui'
import { getCompanySettings } from '@/lib/queries'
import { useToast } from '@/lib/toast'
import { Building2, Plus, Check } from 'lucide-react'

interface Entity {
  id: string
  name: string
  siret: string
  vatNumber: string
  type: 'holding' | 'subsidiary' | 'independent'
  status: 'active' | 'inactive'
  currency: string
  country: string
}

export function MultiCompanyPage() {
  const { t } = useTranslation('features')
  const { toast } = useToast()
  const [entities, setEntities] = useState<Entity[]>([])
  const [activeEntity, setActiveEntity] = useState<string>('')
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ name: '', siret: '', vatNumber: '', type: 'subsidiary', currency: 'EUR', country: 'FR' })

  useEffect(() => {
    loadData()
  }, [])

  async function loadData() {
    try {
      const comp = await getCompanySettings().catch(() => null)
      if (comp) {
        const primary: Entity = {
          id: comp.id,
          name: comp.legal_name || comp.name,
          siret: comp.siret || '',
          vatNumber: comp.vat_number || '',
          type: 'holding',
          status: 'active',
          currency: comp.currency || 'EUR',
          country: comp.country || 'FR',
        }
        setEntities([primary])
        setActiveEntity(comp.id)
      }
    } catch (err) {
      console.error('Error loading company data:', err)
    } finally {
      setLoading(false)
    }
  }

  function handleAddEntity() {
    if (!form.name.trim()) return
    const newEntity: Entity = {
      id: `ent-${Date.now()}`,
      name: form.name,
      siret: form.siret,
      vatNumber: form.vatNumber,
      type: form.type as any,
      status: 'active',
      currency: form.currency,
      country: form.country,
    }
    setEntities([...entities, newEntity])
    setForm({ name: '', siret: '', vatNumber: '', type: 'subsidiary', currency: 'EUR', country: 'FR' })
    setShowForm(false)
    toast('success', t('multiCompany.addEntity'), form.name)
  }

  function handleSwitch(id: string) {
    setActiveEntity(id)
    const ent = entities.find((e) => e.id === id)
    if (ent) {
      toast('info', t('multiCompany.switchTo'), ent.name)
    }
  }

  return (
    <div className="animate-fade-in">
      <AutoBreadcrumb />
      <PageHeader title={t('multiCompany.title')} subtitle={t('multiCompany.subtitle')} />

      <Card className="mb-4">
        <div className="p-4">
          <p className="text-sm text-[var(--color-text-secondary)] mb-4">{t('multiCompany.intro')}</p>
          <Button onClick={() => setShowForm(!showForm)}>
            <Plus className="w-4 h-4" /> {t('multiCompany.addEntity')}
          </Button>
        </div>
      </Card>

      {showForm && (
        <Card className="mb-4">
          <div className="p-4">
            <div className="grid md:grid-cols-3 gap-4">
              <div>
                <Input label={t('multiCompany.name')} value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
              </div>
              <div>
                <Input label={t('multiCompany.siret')} value={form.siret} onChange={(e) => setForm({ ...form, siret: e.target.value })} />
              </div>
              <div>
                <Input label={t('multiCompany.vatNumber')} value={form.vatNumber} onChange={(e) => setForm({ ...form, vatNumber: e.target.value })} />
              </div>
              <div>
                <Select
                  label={t('multiCompany.type')}
                  value={form.type}
                  onChange={(e) => setForm({ ...form, type: e.target.value })}
                  options={[
                    { value: 'holding', label: t('multiCompany.holding') },
                    { value: 'subsidiary', label: t('multiCompany.subsidiary') },
                    { value: 'independent', label: t('multiCompany.independent') },
                  ]}
                />
              </div>
              <div>
                <Input label={t('multiCompany.currency')} value={form.currency} onChange={(e) => setForm({ ...form, currency: e.target.value })} />
              </div>
              <div>
                <Input label={t('multiCompany.country')} value={form.country} onChange={(e) => setForm({ ...form, country: e.target.value })} />
              </div>
            </div>
            <div className="mt-4 flex gap-2">
              <Button onClick={handleAddEntity} disabled={!form.name.trim()}>
                <Check className="w-4 h-4" /> {t('multiCompany.addEntity')}
              </Button>
              <Button variant="secondary" onClick={() => setShowForm(false)}>Cancel</Button>
            </div>
          </div>
        </Card>
      )}

      {loading ? (
        <Card><div className="p-8 text-center text-[var(--color-text-secondary)]">...</div></Card>
      ) : entities.length === 0 ? (
        <EmptyState
          icon={<Building2 className="w-8 h-8" />}
          title={t('multiCompany.noEntities')}
          description={t('multiCompany.noEntitiesDesc')}
        />
      ) : (
        <Card>
          <div className="p-4">
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-[var(--color-border)]">
                    <th className="text-left p-2 text-[var(--color-text-secondary)] font-medium">{t('multiCompany.name')}</th>
                    <th className="text-left p-2 text-[var(--color-text-secondary)] font-medium">{t('multiCompany.siret')}</th>
                    <th className="text-left p-2 text-[var(--color-text-secondary)] font-medium">{t('multiCompany.vatNumber')}</th>
                    <th className="text-left p-2 text-[var(--color-text-secondary)] font-medium">{t('multiCompany.type')}</th>
                    <th className="text-left p-2 text-[var(--color-text-secondary)] font-medium">{t('multiCompany.status')}</th>
                    <th className="text-left p-2 text-[var(--color-text-secondary)] font-medium">{t('multiCompany.currency')}</th>
                    <th className="text-right p-2 text-[var(--color-text-secondary)] font-medium">{t('multiCompany.actions')}</th>
                  </tr>
                </thead>
                <tbody>
                  {entities.map((e) => (
                    <tr key={e.id} className={`border-b border-[var(--color-border)] last:border-0 ${activeEntity === e.id ? 'bg-[var(--color-primary)]/5' : ''}`}>
                      <td className="p-2 font-medium">
                        {activeEntity === e.id && <Check className="w-4 h-4 inline mr-1 text-[var(--color-primary)]" />}
                        {e.name}
                      </td>
                      <td className="p-2 font-mono text-xs">{e.siret || '—'}</td>
                      <td className="p-2 font-mono text-xs">{e.vatNumber || '—'}</td>
                      <td className="p-2">{t(`multiCompany.${e.type}`)}</td>
                      <td className="p-2">
                        <span className={`px-2 py-0.5 rounded-full text-xs ${e.status === 'active' ? 'bg-[var(--color-success)]/10 text-[var(--color-success)]' : 'bg-[var(--color-neutral-200)] text-[var(--color-text-secondary)]'}`}>
                          {t(`multiCompany.${e.status}`)}
                        </span>
                      </td>
                      <td className="p-2">{e.currency}</td>
                      <td className="p-2 text-right">
                        {activeEntity !== e.id && (
                          <Button variant="secondary" size="sm" onClick={() => handleSwitch(e.id)}>
                            {t('multiCompany.switchTo')}
                          </Button>
                        )}
                        {activeEntity === e.id && (
                          <span className="text-xs text-[var(--color-primary)] font-medium">{t('multiCompany.currentlyActive')}</span>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </Card>
      )}
    </div>
  )
}
