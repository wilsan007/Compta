import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Plus, Trash2, Cog, Download, Upload } from 'lucide-react'
import { Card, Button, Input, Select, Table, TableRow, TableCell, EmptyState, PageHeader, Breadcrumb, SkeletonTable, Badge } from '@/components/ui'
import { useToast } from '@/lib/toast'
import { getMachines, createMachine, deleteMachine, getWorkCenters, createWorkCenter, deleteWorkCenter } from '@/lib/queries'
import { exportToExcel, importFromExcel } from '@/lib/excel-utils'
import type { Machine, WorkCenter } from '@/types'
import { useStatusLabels } from '@/lib/statusUtils'

export function MachinesPage() {
  const { t } = useTranslation('production')
  const { toast } = useToast()
  const { getStatusLabel, getStatusVariant } = useStatusLabels()
  const [machines, setMachines] = useState<Machine[]>([])
  const [workCenters, setWorkCenters] = useState<WorkCenter[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [showWcForm, setShowWcForm] = useState(false)

  const loadData = useCallback(async () => {
    try {
      const [macs, wcs] = await Promise.all([getMachines(), getWorkCenters()])
      setMachines(macs || [])
      setWorkCenters(wcs || [])
    } catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
    if (!window.confirm(t('machines.confirmDelete'))) return
    try { await deleteMachine(id); await loadData() }
    catch (err: any) { toast('error', t('common.error'), err.message || 'échec') }
  }

  async function handleDeleteWc(id: string) {
    if (!window.confirm(t('machines.confirmDeleteWorkCenter'))) return
    try { await deleteWorkCenter(id); await loadData() }
    catch (err: any) { toast('error', t('common.error'), err.message || 'échec') }
  }

  function handleExport() {
    const rows = machines.map((m: any) => ({
      code: m.code, nom: m.name, centre: m.work_centers?.name || '',
      capacite_h: m.capacity_per_hour, statut: getStatusLabel(m.status),
    }))
    exportToExcel(rows, 'machines.xlsx', 'Machines')
  }

  async function handleImport(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    try {
      const rows = await importFromExcel(file)
      toast('success', t('machines.import'), t('routings.importSuccess', { count: rows.length }))
    } catch (err: any) { toast('error', t('routings.importError'), err.message) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('machines.title') }]} />
      <PageHeader title={t('machines.machinesAndToolings')} subtitle={`${machines.length} machine(s)`}
        action={
          <div className="flex gap-2">
            <Button variant="secondary" onClick={handleExport}><Download className="w-4 h-4" /> {t('machines.export')}</Button>
            <label className="inline-flex items-center gap-2 px-3 py-2 text-sm rounded-lg border border-[var(--color-border)] bg-[var(--color-surface)] cursor-pointer hover:bg-[var(--color-neutral-50)]">
              <Upload className="w-4 h-4" /> {t('machines.import')}
              <input type="file" accept=".xlsx,.xls" className="hidden" onChange={handleImport} />
            </label>
            <Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('machines.new')}</Button>
          </div>
        } />

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 mb-4">
        <Card className="lg:col-span-2">
          {loading ? <SkeletonTable rows={4} cols={5} /> : machines.length === 0 ? (
            <EmptyState icon={<Cog className="w-8 h-8" />} title={t('machines.noMachines')} description={t('machines.addFirstMachine')}
              action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('machines.new')}</Button>} />
          ) : (
            <Table headers={[t('common.code'), t('machines.name'), t('machines.workCenter'), t('machines.capacityPerHour'), t('machines.status'), t('common.actions')]}>
              {machines.map((m: any) => (
                <TableRow key={m.id}>
                  <TableCell className="font-mono text-xs">{m.code}</TableCell>
                  <TableCell className="font-medium">{m.name}</TableCell>
                  <TableCell className="text-sm">{m.work_centers?.name || '—'}</TableCell>
                  <TableCell className="font-mono text-xs">{Number(m.capacity_per_hour)}</TableCell>
                  <TableCell><Badge variant={getStatusVariant(m.status)}>{getStatusLabel(m.status)}</Badge></TableCell>
                  <TableCell>
                    <button onClick={() => handleDelete(m.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
                  </TableCell>
                </TableRow>
              ))}
            </Table>
          )}
        </Card>

        <Card>
          <div className="flex items-center justify-between mb-3">
            <h3 className="text-sm font-semibold">{t('machines.workCenters')}</h3>
            <button onClick={() => setShowWcForm(true)} className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)]"><Plus className="w-4 h-4" /></button>
          </div>
          {workCenters.length === 0 ? (
            <p className="text-xs text-[var(--color-text-secondary)]">{t('machines.noWorkCenters')}</p>
          ) : (
            <Table headers={[t('common.code'), t('machines.name'), t('machines.capHDay'), t('machines.costH'), '']}>
              {workCenters.map((wc) => (
                <TableRow key={wc.id}>
                  <TableCell className="font-mono text-xs">{wc.code}</TableCell>
                  <TableCell className="text-sm">{wc.name}</TableCell>
                  <TableCell className="font-mono text-xs">{Number(wc.capacity_hours_per_day)}h</TableCell>
                  <TableCell className="font-mono text-xs">{Number(wc.cost_per_hour)}</TableCell>
                  <TableCell><button onClick={() => handleDeleteWc(wc.id)} className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-3.5 h-3.5" /></button></TableCell>
                </TableRow>
              ))}
            </Table>
          )}
        </Card>
      </div>

      {showForm && <MachineFormModal workCenters={workCenters} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
      {showWcForm && <WorkCenterFormModal onClose={() => setShowWcForm(false)} onSaved={() => { setShowWcForm(false); loadData() }} />}
    </div>
  )
}

function MachineFormModal({ workCenters, onClose, onSaved }: { workCenters: WorkCenter[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('production')
  const { toast } = useToast()
  const { getStatusLabel } = useStatusLabels()
  const [code, setCode] = useState('')
  const [name, setName] = useState('')
  const [workCenterId, setWorkCenterId] = useState('')
  const [capacity, setCapacity] = useState(0)
  const [status, setStatus] = useState('active')
  const [purchaseDate, setPurchaseDate] = useState('')
  const [notes, setNotes] = useState('')

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!code || !name) { toast('error', t('common.required'), 'Code & ' + t('machines.name')); return }
    try {
      await createMachine({ code, name, work_center_id: workCenterId || null, capacity_per_hour: capacity, status: status as any, purchase_date: purchaseDate || null, notes })
      onSaved()
    } catch (err: any) { toast('error', t('common.error'), err.message || 'échec') }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40" onClick={onClose}>
      <div className="bg-[var(--color-surface)] rounded-xl shadow-xl p-6 w-full max-w-md" onClick={(e) => e.stopPropagation()}>
        <h2 className="text-lg font-semibold mb-4">{t('machines.create')}</h2>
        <form onSubmit={handleSubmit} className="space-y-3">
          <Input label={t('common.code')} value={code} onChange={(e) => setCode(e.target.value)} placeholder="MAC-001" required />
          <Input label={t('machines.name')} value={name} onChange={(e) => setName(e.target.value)} placeholder={t('machines.namePlaceholder')} required />
          <Select label={t('machines.workCenter')} value={workCenterId} onChange={(e) => setWorkCenterId(e.target.value)} options={[{ value: '', label: '—' }, ...workCenters.map((wc) => ({ value: wc.id, label: wc.name }))]} />
          <Input label={t('machines.capacityPerHour')} type="number" step="0.01" value={capacity} onChange={(e) => setCapacity(Number(e.target.value))} />
          <Select label={t('machines.status')} value={status} onChange={(e) => setStatus(e.target.value)} options={[{ value: 'active', label: getStatusLabel('active') }, { value: 'maintenance', label: getStatusLabel('maintenance') }, { value: 'inactive', label: getStatusLabel('inactive') }]} />
          <Input label={t('machines.maintenanceDate')} type="date" value={purchaseDate} onChange={(e) => setPurchaseDate(e.target.value)} />
          <Input label={t('common.description')} value={notes} onChange={(e) => setNotes(e.target.value)} />
          <div className="flex gap-2 justify-end pt-2">
            <Button type="button" variant="secondary" onClick={onClose}>{t('common.cancel')}</Button>
            <Button type="submit">{t('common.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}

function WorkCenterFormModal({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('production')
  const { toast } = useToast()
  const [code, setCode] = useState('')
  const [name, setName] = useState('')
  const [capacity, setCapacity] = useState(8)
  const [costPerHour, setCostPerHour] = useState(0)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!code || !name) { toast('error', t('common.required'), 'Code & ' + t('machines.name')); return }
    try {
      await createWorkCenter({ code, name, capacity_hours_per_day: capacity, cost_per_hour: costPerHour, active: true })
      onSaved()
    } catch (err: any) { toast('error', t('common.error'), err.message || 'échec') }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40" onClick={onClose}>
      <div className="bg-[var(--color-surface)] rounded-xl shadow-xl p-6 w-full max-w-sm" onClick={(e) => e.stopPropagation()}>
        <h2 className="text-lg font-semibold mb-4">{t('machines.workCenter')}</h2>
        <form onSubmit={handleSubmit} className="space-y-3">
          <Input label={t('common.code')} value={code} onChange={(e) => setCode(e.target.value)} placeholder="CC-001" required />
          <Input label={t('machines.name')} value={name} onChange={(e) => setName(e.target.value)} placeholder={t('machines.workCenterPlaceholder')} required />
          <Input label={t('machines.capHDay')} type="number" step="0.1" value={capacity} onChange={(e) => setCapacity(Number(e.target.value))} />
          <Input label={t('machines.costH')} type="number" step="0.01" value={costPerHour} onChange={(e) => setCostPerHour(Number(e.target.value))} />
          <div className="flex gap-2 justify-end pt-2">
            <Button type="button" variant="secondary" onClick={onClose}>{t('common.cancel')}</Button>
            <Button type="submit">{t('common.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
