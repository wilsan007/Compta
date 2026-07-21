import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Calendar, Trash2, Zap, PackageX, CheckCircle2, Clock } from 'lucide-react'
import { Card, Button, Table, TableRow, TableCell, EmptyState, PageHeader, Breadcrumb, SkeletonTable, Badge } from '@/components/ui'
import { useToast } from '@/lib/toast'
import { getPlanningSlots, deletePlanningSlot, checkMaterialAvailability, autoScheduleMOs } from '@/lib/queries'

const statusVariants: Record<string, 'neutral' | 'warning' | 'success'> = { planned: 'neutral', scheduled: 'warning', in_progress: 'warning', completed: 'success' }

export function PlanningPage() {
  const { toast } = useToast()
  const { t } = useTranslation('production')
  const { t: tCommon } = useTranslation('common')
  const [slots, setSlots] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [scheduling, setScheduling] = useState(false)

  const loadData = useCallback(async () => {
    try { setSlots(await getPlanningSlots() || []) }
    catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
    if (!window.confirm(t('planning.confirmDelete'))) return
    try { await deletePlanningSlot(id); await loadData() }
    catch (err: any) { toast('error', tCommon('toast.error'), err.message) }
  }

  async function handleMaterialCheck(id: string) {
    try {
      const result = await checkMaterialAvailability(id)
      if (result.available) { toast('success', t('planning.materialsAvailable'), t('planning.allComponentsInStock')) }
      else { toast('warning', t('planning.materialsMissing'), t('planning.componentsMissing', { count: result.missing.length })) }
      await loadData()
    } catch (err: any) { toast('error', tCommon('toast.error'), err.message) }
  }

  async function handleAutoSchedule() {
    setScheduling(true)
    try {
      const count = await autoScheduleMOs()
      toast('success', t('planning.schedulingDone'), t('planning.ofScheduled', { count }))
      await loadData()
    } catch (err: any) { toast('error', tCommon('toast.error'), err.message) }
    finally { setScheduling(false) }
  }

  const minDate = slots.length > 0 ? Math.min(...slots.map((s) => new Date(s.planned_start || Date.now()).getTime())) : Date.now()
  const maxDate = slots.length > 0 ? Math.max(...slots.map((s) => new Date(s.planned_end || Date.now()).getTime())) : Date.now() + 86400000
  const totalRange = Math.max(1, maxDate - minDate)

  function getBarStyle(start: string | null, end: string | null) {
    if (!start || !end) return {}
    const s = new Date(start).getTime()
    const e = new Date(end).getTime()
    const left = ((s - minDate) / totalRange) * 100
    const width = Math.max(2, ((e - s) / totalRange) * 100)
    return { left: `${left}%`, width: `${width}%` }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('planning.title'), path: '/production' }, { label: t('planning.titleFull') }]} />
      <PageHeader title={t('planning.titleFull')} subtitle={`${slots.length} ${t('planning.slotsCount')}`}
        action={<Button onClick={handleAutoSchedule} disabled={scheduling}><Zap className="w-4 h-4" /> {scheduling ? '...' : t('planning.autoSchedule')}</Button>} />

      {loading ? <SkeletonTable rows={4} cols={6} /> : slots.length === 0 ? (
        <EmptyState icon={<Calendar className="w-8 h-8" />} title={t('planning.noSlotsPlanned')} description={t('planning.noSlotsDescription')}
          action={<Button onClick={handleAutoSchedule} disabled={scheduling}><Zap className="w-4 h-4" /> {t('planning.autoSchedule')}</Button>} />
      ) : (
        <>
          <Card className="mb-4">
            <h3 className="text-sm font-semibold px-4 pt-4 mb-3">{t('planning.ganttChart')}</h3>
            <div className="px-4 pb-4 space-y-2">
              {slots.map((s) => (
                <div key={s.id} className="relative h-8 bg-[var(--color-neutral-50)] rounded">
                  <div
                    className={`absolute h-8 rounded flex items-center px-2 text-xs text-white ${s.status === 'completed' ? 'bg-[var(--color-success)]' : s.status === 'in_progress' ? 'bg-[var(--color-warning)]' : 'bg-[var(--color-primary)]'} ${!s.material_available ? 'ring-2 ring-[var(--color-danger)]' : ''}`}
                    style={getBarStyle(s.planned_start, s.planned_end)}
                  >
                    <span className="truncate">{s.manufacturing_orders?.number || '—'} · {s.machines?.name || '—'}</span>
                  </div>
                </div>
              ))}
            </div>
          </Card>

          <Card>
            <Table headers={[t('planning.of'), t('planning.operation'), t('planning.machine'), t('planning.start'), t('planning.end'), t('planning.duration'), t('planning.materials'), tCommon('common.status'), tCommon('table.actions')]}>
              {slots.map((s) => {
                const duration = s.planned_start && s.planned_end
                  ? Math.round((new Date(s.planned_end).getTime() - new Date(s.planned_start).getTime()) / 60000)
                  : 0
                return (
                  <TableRow key={s.id}>
                    <TableCell className="font-mono text-xs">{s.manufacturing_orders?.number || '—'}</TableCell>
                    <TableCell className="text-sm">{s.routing_operations?.name || '—'}</TableCell>
                    <TableCell className="text-sm">{s.machines?.name || '—'}</TableCell>
                    <TableCell className="text-xs">{s.planned_start ? new Date(s.planned_start).toLocaleString('fr-FR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }) : '—'}</TableCell>
                    <TableCell className="text-xs">{s.planned_end ? new Date(s.planned_end).toLocaleString('fr-FR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }) : '—'}</TableCell>
                    <TableCell className="font-mono text-xs">{duration > 0 ? `${duration}min` : '—'}</TableCell>
                    <TableCell>
                      {s.material_available ? (
                        <Badge variant="success"><CheckCircle2 className="w-3 h-3 inline mr-1" />{t('planning.ok')}</Badge>
                      ) : (
                        <Badge variant="danger"><PackageX className="w-3 h-3 inline mr-1" />{t('planning.missing')}</Badge>
                      )}
                    </TableCell>
                    <TableCell><Badge variant={statusVariants[s.status] || 'neutral'}>{t(`planning.statuses.${s.status}`, { defaultValue: s.status })}</Badge></TableCell>
                    <TableCell>
                      <div className="flex gap-1">
                        <button onClick={() => handleMaterialCheck(s.id)} className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)]" title={t('planning.checkMaterials')}><Clock className="w-3.5 h-3.5" /></button>
                        <button onClick={() => handleDelete(s.id)} className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-3.5 h-3.5" /></button>
                      </div>
                    </TableCell>
                  </TableRow>
                )
              })}
            </Table>
          </Card>
        </>
      )}
    </div>
  )
}
