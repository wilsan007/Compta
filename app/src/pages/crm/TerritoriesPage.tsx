import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Button, Table, TableRow, TableCell, Badge, EmptyState, Select, Input } from '@/components/ui'
import { getTerritories, createTerritory, deleteTerritory, getSalesRepresentatives } from '@/lib/queries'
import { useToast } from '@/lib/toast'
import { Plus, X, MapPin, Trash2 } from 'lucide-react'
import type { CrmTerritory, SalesRepresentative } from '@/types'

export function TerritoriesPage() {
  const { t } = useTranslation('crm')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [territories, setTerritories] = useState<CrmTerritory[]>([])
  const [reps, setReps] = useState<SalesRepresentative[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const [territoriesData, repsData] = await Promise.all([getTerritories(), getSalesRepresentatives()])
      setTerritories(territoriesData || [])
      setReps(repsData || [])
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { load() }, [load])

  async function handleDelete(id: string) {
    try {
      await deleteTerritory(id)
      toast('success', tCommon('toast.success'), tCommon('toast.deleted'))
      await load()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    }
  }

  function getRepName(repId: string | null): string {
    if (!repId) return '-'
    const rep = reps.find(r => r.id === repId)
    return rep?.name || '-'
  }

  return (
    <div className="p-6 max-w-7xl mx-auto">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <MapPin className="w-6 h-6 text-[var(--color-primary)]" />
            {t('territories.title')}
          </h1>
          <p className="text-sm text-[var(--color-text-secondary)] mt-1">{t('territories.subtitle')}</p>
        </div>
        <Button onClick={() => setShowForm(true)}>
          <Plus className="w-4 h-4" /> {t('territories.new')}
        </Button>
      </div>

      {loading ? (
        <div className="space-y-2">{[1, 2, 3].map(i => <div key={i} className="h-12 rounded animate-pulse bg-[var(--color-neutral-100)]" />)}</div>
      ) : territories.length === 0 ? (
        <EmptyState icon={<MapPin className="w-8 h-8" />} title={t('territories.noTerritories')} description={t('territories.noTerritoriesDescription')} />
      ) : (
        <Table headers={[t('territories.name'), t('territories.code'), t('territories.salesRep'), t('territories.regions'), tCommon('table.status'), tCommon('table.actions')]}>
          {territories.map(terr => (
            <TableRow key={terr.id}>
              <TableCell className="font-medium">{terr.name}</TableCell>
              <TableCell className="font-mono text-xs">{terr.code || '-'}</TableCell>
              <TableCell className="text-xs">{getRepName(terr.sales_rep_id)}</TableCell>
              <TableCell className="text-xs">{(terr.regions || []).join(', ') || '-'}</TableCell>
              <TableCell><Badge variant={terr.active ? 'success' : 'neutral'}>{terr.active ? tCommon('status.active') : tCommon('status.inactive')}</Badge></TableCell>
              <TableCell>
                <button onClick={() => handleDelete(terr.id)} className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                  <Trash2 className="w-4 h-4" />
                </button>
              </TableCell>
            </TableRow>
          ))}
        </Table>
      )}

      {showForm && <TerritoryForm reps={reps} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); load() }} />}
    </div>
  )
}

function TerritoryForm({ reps, onClose, onSaved }: { reps: SalesRepresentative[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('crm')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [name, setName] = useState('')
  const [code, setCode] = useState('')
  const [salesRepId, setSalesRepId] = useState('')
  const [regionsInput, setRegionsInput] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!name) return
    setSaving(true)
    try {
      const regions = regionsInput.split(',').map(r => r.trim()).filter(Boolean)
      await createTerritory({
        tenant_id: null,
        name,
        code: code || null,
        parent_id: null,
        sales_rep_id: salesRepId || null,
        regions: regions.length > 0 ? regions : null,
        active: true,
      })
      toast('success', tCommon('toast.success'), tCommon('toast.created'))
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '28rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('territories.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label={t('territories.name')} required value={name} onChange={(e) => setName(e.target.value)} />
          <Input label={t('territories.code')} value={code} onChange={(e) => setCode(e.target.value)} />
          <Select label={t('territories.salesRep')} value={salesRepId} onChange={(e) => setSalesRepId(e.target.value)} options={[
            { value: '', label: tCommon('select.choose') },
            ...reps.map(r => ({ value: r.id, label: r.name })),
          ]} />
          <Input label={t('territories.regions')} placeholder="Region1, Region2" value={regionsInput} onChange={(e) => setRegionsInput(e.target.value)} />
          <div className="flex justify-end gap-3 pt-2 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
