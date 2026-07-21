import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Plus, Trash2, Wrench, Download, Upload } from 'lucide-react'
import { Card, Button, Input, Select, Table, TableRow, TableCell, EmptyState, PageHeader, Breadcrumb, SkeletonTable, Badge } from '@/components/ui'
import { useToast } from '@/lib/toast'
import { getToolings, createTooling, deleteTooling, getMachines } from '@/lib/queries'
import { exportToExcel, importFromExcel } from '@/lib/excel-utils'
import type { Tooling, Machine } from '@/types'
import { useStatusLabels } from '@/lib/statusUtils'

export function ToolingsPage() {
  const { t } = useTranslation('production')
  const { toast } = useToast()
  const { getStatusLabel, getStatusVariant } = useStatusLabels()
  const [toolings, setToolings] = useState<Tooling[]>([])
  const [machines, setMachines] = useState<Machine[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)

  const loadData = useCallback(async () => {
    try {
      const [tls, macs] = await Promise.all([getToolings(), getMachines()])
      setToolings(tls || [])
      setMachines(macs || [])
    } catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
    if (!window.confirm(t('toolings.confirmDelete'))) return
    try { await deleteTooling(id); await loadData() }
    catch (err: any) { toast('error', t('common.error'), err.message || 'échec') }
  }

  function handleExport() {
    const rows = toolings.map((t: any) => ({
      code: t.code, nom: t.name, machine: t.machines?.name || '',
      pieces_max: t.max_pieces, compteur_initial: t.initial_counter,
      compteur_actuel: t.current_counter, usure_pct: t.max_pieces > 0 ? Math.round(t.current_counter / t.max_pieces * 100) : 0,
      statut: getStatusLabel(t.status),
    }))
    exportToExcel(rows, 'outillages.xlsx', 'Outillages')
  }

  async function handleImport(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    try {
      const rows = await importFromExcel(file)
      toast('success', t('toolings.import'), t('routings.importSuccess', { count: rows.length }))
    } catch (err: any) { toast('error', t('routings.importError'), err.message) }
  }

  function getWearPercent(t: Tooling): number {
    if (t.max_pieces <= 0) return 0
    return Math.min(100, Math.round((t.current_counter / t.max_pieces) * 100))
  }

  function getWearColor(pct: number): string {
    if (pct > 90) return 'var(--color-danger)'
    if (pct > 70) return 'var(--color-warning)'
    return 'var(--color-success)'
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('toolings.title') }]} />
      <PageHeader title={t('toolings.title')} subtitle={`${toolings.length} outillage(s)`}
        action={
          <div className="flex gap-2">
            <Button variant="secondary" onClick={handleExport}><Download className="w-4 h-4" /> {t('toolings.export')}</Button>
            <label className="inline-flex items-center gap-2 px-3 py-2 text-sm rounded-lg border border-[var(--color-border)] bg-[var(--color-surface)] cursor-pointer hover:bg-[var(--color-neutral-50)]">
              <Upload className="w-4 h-4" /> {t('toolings.import')}
              <input type="file" accept=".xlsx,.xls" className="hidden" onChange={handleImport} />
            </label>
            <Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('toolings.new')}</Button>
          </div>
        } />

      {loading ? <SkeletonTable rows={4} cols={7} /> : toolings.length === 0 ? (
        <EmptyState icon={<Wrench className="w-8 h-8" />} title={t('toolings.noToolings')} description={t('toolings.addFirstTooling')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('toolings.new')}</Button>} />
      ) : (
        <Card>
          <Table headers={['Code', t('toolings.name'), t('toolings.machine'), t('toolings.maxPieces'), t('toolings.initialCounter'), t('toolings.currentCounter'), t('toolings.wear'), t('toolings.status'), t('common.actions')]}>
            {toolings.map((t: any) => {
              const wearPct = getWearPercent(t)
              return (
                <TableRow key={t.id}>
                  <TableCell className="font-mono text-xs">{t.code}</TableCell>
                  <TableCell className="font-medium">{t.name}</TableCell>
                  <TableCell className="text-sm">{t.machines?.name || '—'}</TableCell>
                  <TableCell className="font-mono text-xs">{t.max_pieces}</TableCell>
                  <TableCell className="font-mono text-xs">{t.initial_counter}</TableCell>
                  <TableCell className="font-mono text-xs">{t.current_counter}</TableCell>
                  <TableCell>
                    <div className="flex items-center gap-2">
                      <div className="w-20 h-2 rounded-full bg-[var(--color-neutral-100)] overflow-hidden">
                        <div className="h-full rounded-full transition-all" style={{ width: `${wearPct}%`, backgroundColor: getWearColor(wearPct) }} />
                      </div>
                      <span className="text-xs font-mono" style={{ color: getWearColor(wearPct) }}>{wearPct}%</span>
                    </div>
                  </TableCell>
                  <TableCell><Badge variant={getStatusVariant(t.status)}>{getStatusLabel(t.status)}</Badge></TableCell>
                  <TableCell>
                    <button onClick={() => handleDelete(t.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
                  </TableCell>
                </TableRow>
              )
            })}
          </Table>
        </Card>
      )}

      {showForm && <ToolingFormModal machines={machines} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function ToolingFormModal({ machines, onClose, onSaved }: { machines: Machine[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('production')
  const { toast } = useToast()
  const { getStatusLabel } = useStatusLabels()
  const [code, setCode] = useState('')
  const [name, setName] = useState('')
  const [machineId, setMachineId] = useState('')
  const [maxPieces, setMaxPieces] = useState(0)
  const [initialCounter, setInitialCounter] = useState(0)
  const [currentCounter, setCurrentCounter] = useState(0)
  const [status, setStatus] = useState('active')
  const [notes, setNotes] = useState('')

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!code || !name) { toast('error', t('common.required'), 'Code & ' + t('toolings.name')); return }
    try {
      await createTooling({ code, name, machine_id: machineId || null, max_pieces: maxPieces, initial_counter: initialCounter, current_counter: currentCounter, status: status as any, notes })
      onSaved()
    } catch (err: any) { toast('error', t('common.error'), err.message || 'échec') }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40" onClick={onClose}>
      <div className="bg-[var(--color-surface)] rounded-xl shadow-xl p-6 w-full max-w-md" onClick={(e) => e.stopPropagation()}>
        <h2 className="text-lg font-semibold mb-4">{t('toolings.create')}</h2>
        <form onSubmit={handleSubmit} className="space-y-3">
          <Input label="Code" value={code} onChange={(e) => setCode(e.target.value)} placeholder="OUT-001" required />
          <Input label={t('toolings.name')} value={name} onChange={(e) => setName(e.target.value)} placeholder="Moule injection A" required />
          <Select label={t('toolings.machine')} value={machineId} onChange={(e) => setMachineId(e.target.value)} options={[{ value: '', label: '—' }, ...machines.map((m) => ({ value: m.id, label: m.name }))]} />
          <Input label={t('toolings.maxPieces')} type="number" value={maxPieces} onChange={(e) => setMaxPieces(Number(e.target.value))} />
          <Input label={t('toolings.initialCounter')} type="number" value={initialCounter} onChange={(e) => setInitialCounter(Number(e.target.value))} />
          <Input label={t('toolings.currentCounter')} type="number" value={currentCounter} onChange={(e) => setCurrentCounter(Number(e.target.value))} />
          <Select label={t('toolings.status')} value={status} onChange={(e) => setStatus(e.target.value)} options={[{ value: 'active', label: getStatusLabel('active') }, { value: 'worn', label: getStatusLabel('worn') }, { value: 'inactive', label: getStatusLabel('inactive') }]} />
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
