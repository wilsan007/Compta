import { useState, useEffect, useCallback, useRef } from 'react'
import { useTranslation } from 'react-i18next'
import { Play, Square, Clock, Plus, Trash2, DollarSign } from 'lucide-react'
import { useToast } from '@/lib/toast'
import { useTaskContext } from '@/contexts/TaskContext'
import {
  getTimeEntries,
  startTimeTimer,
  stopTimeTimer,
  addManualTimeEntry,
  deleteTimeEntry,
} from '@/lib/queries/projectManagementSprint1'
import type { TimeEntry } from '@/types/projectManagement'

interface TaskTimerProps {
  taskId: string
  taskTitle: string
}

export function TaskTimer({ taskId, taskTitle }: TaskTimerProps) {
  const { t } = useTranslation('taskManagement')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { refetch } = useTaskContext()
  const [entries, setEntries] = useState<TimeEntry[]>([])
  const [running, setRunning] = useState(false)
  const [elapsed, setElapsed] = useState(0)
  const [showManual, setShowManual] = useState(false)
  const [loading, setLoading] = useState(true)
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null)

  const loadEntries = useCallback(async () => {
    try {
      const data = await getTimeEntries(taskId)
      setEntries(data)
      const active = data.find((e) => !e.end_time)
      if (active) {
        setRunning(true)
        setElapsed(Math.floor((Date.now() - new Date(active.start_time).getTime()) / 1000))
      }
    } catch (err: any) {
      console.error("catch:", err)
      // ignore
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError'))
    } finally {
      setLoading(false)
    }
  }, [taskId, tCommon, toast])

  useEffect(() => {
    loadEntries().catch(err => console.error('loadEntries:', err))
  }, [loadEntries])

  useEffect(() => {
    if (running) {
      timerRef.current = setInterval(() => {
        setElapsed((prev) => prev + 1)
      }, 1000)
    } else if (timerRef.current) {
      clearInterval(timerRef.current)
      timerRef.current = null
    }
    return () => {
      if (timerRef.current) clearInterval(timerRef.current)
    }
  }, [running])

  const handleStart = useCallback(async () => {
    try {
      await startTimeTimer({ task_id: taskId })
      setRunning(true)
      setElapsed(0)
    } catch (err: any) {
      console.error("catch:", err)
      // ignore
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError'))
    }
  }, [taskId, tCommon, toast])

  const handleStop = useCallback(async () => {
    const active = entries.find((e) => !e.end_time)
    if (!active) return
    try {
      await stopTimeTimer(active.id)
      setRunning(false)
      if (timerRef.current) clearInterval(timerRef.current)
      await loadEntries()
      await refetch()
    } catch (err: any) {
      console.error("catch:", err)
      // ignore
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError'))
    }
  }, [entries, loadEntries, refetch, tCommon, toast])

  const handleDelete = useCallback(
    async (id: string) => {
      try {
        await deleteTimeEntry(id)
        await loadEntries()
        await refetch()
      } catch (err: any) {
        console.error("catch:", err)
        // ignore
        toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError'))
      }
    },
    [loadEntries, refetch, tCommon, toast]
  )

  const formatDuration = (seconds: number) => {
    const h = Math.floor(seconds / 3600)
    const m = Math.floor((seconds % 3600) / 60)
    const s = seconds % 60
    return `${h.toString().padStart(2, '0')}:${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`
  }

  const totalSeconds = entries.reduce((sum, e) => sum + (e.duration_seconds || 0), 0)
  const billableSeconds = entries.filter((e) => e.is_billable).reduce((sum, e) => sum + (e.duration_seconds || 0), 0)

  if (loading) return null

  return (
    <div className="rounded-lg border border-[var(--color-border)] bg-[var(--color-surface)] p-4 space-y-3">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Clock className="w-4 h-4 text-[var(--color-primary)]" />
          <h3 className="text-sm font-semibold">{t('timeTracking.title')}</h3>
        </div>
        <span className="text-xs text-[var(--color-text-secondary)]">{taskTitle}</span>
      </div>

      <div className="flex items-center gap-3">
        <button
          onClick={running ? handleStop : handleStart}
          className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
            running
              ? 'bg-red-500 text-white hover:bg-red-600'
              : 'bg-green-500 text-white hover:bg-green-600'
          }`}
        >
          {running ? <Square className="w-3.5 h-3.5" /> : <Play className="w-3.5 h-3.5" />}
          {running ? t('timeTracking.stopTimer') : t('timeTracking.startTimer')}
        </button>
        {running && (
          <span className="font-mono text-lg tabular-nums text-[var(--color-primary)]">
            {formatDuration(elapsed)}
          </span>
        )}
        <button
          onClick={() => setShowManual(!showManual)}
          className="ml-auto flex items-center gap-1 px-2 py-1 text-xs text-[var(--color-text-secondary)] hover:text-[var(--color-text)] transition-colors"
        >
          <Plus className="w-3 h-3" />
          {t('timeTracking.addManual')}
        </button>
      </div>

      {showManual && (
        <ManualEntryForm
          taskId={taskId}
          onSaved={async () => {
            setShowManual(false)
            await loadEntries()
            await refetch()
          }}
        />
      )}

      <div className="grid grid-cols-2 gap-2 text-xs">
        <div className="rounded-md bg-[var(--color-neutral-100)] p-2">
          <span className="text-[var(--color-text-secondary)]">{t('timeTracking.totalTime')}</span>
          <p className="font-semibold">{formatDuration(totalSeconds)}</p>
        </div>
        <div className="rounded-md bg-[var(--color-neutral-100)] p-2">
          <span className="text-[var(--color-text-secondary)]">{t('timeTracking.billableHours')}</span>
          <p className="font-semibold">{formatDuration(billableSeconds)}</p>
        </div>
      </div>

      {entries.length > 0 && (
        <div className="space-y-1 max-h-40 overflow-y-auto">
          {entries.slice(0, 10).map((entry) => (
            <div
              key={entry.id}
              className="flex items-center justify-between text-xs py-1 px-2 rounded hover:bg-[var(--color-neutral-100)]"
            >
              <div className="flex items-center gap-2">
                {entry.is_billable && <DollarSign className="w-3 h-3 text-green-500" />}
                <span className="text-[var(--color-text-secondary)]">
                  {new Date(entry.start_time).toLocaleDateString()}
                </span>
                <span className="font-mono">{formatDuration(entry.duration_seconds)}</span>
              </div>
              {!entry.end_time && (
                <span className="text-green-500 text-[10px]">{t('timeTracking.running')}</span>
              )}
              {entry.end_time && (
                <button
                  onClick={() => handleDelete(entry.id)}
                  className="text-red-400 hover:text-red-600 transition-colors" aria-label={tCommon('actions.delete')} title={tCommon('actions.delete')}>
                  <Trash2 className="w-3 h-3" aria-hidden="true" /></button>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

function ManualEntryForm({ taskId, onSaved }: { taskId: string; onSaved: () => void }) {
  const { t } = useTranslation('taskManagement')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [hours, setHours] = useState('1')
  const [description, setDescription] = useState('')
  const [billable, setBillable] = useState(false)
  const [saving, setSaving] = useState(false)

  const handleSave = async () => {
    const h = parseFloat(hours) || 0
    if (h <= 0) return
    setSaving(true)
    try {
      const now = new Date()
      const start = new Date(now.getTime() - h * 3600 * 1000)
      await addManualTimeEntry({
        task_id: taskId,
        start_time: start.toISOString(),
        end_time: now.toISOString(),
        duration_seconds: Math.floor(h * 3600),
        description: description || null,
        is_billable: billable,
      })
      onSaved()
    } catch (err: any) {
      console.error("catch:", err)
      // ignore
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="flex flex-wrap items-end gap-2 p-2 rounded-md bg-[var(--color-neutral-100)]">
      <div>
        <label className="text-[10px] text-[var(--color-text-secondary)]">{t('timeTracking.duration')}</label>
        <input
          type="number"
          step="0.5"
          min="0.5"
          value={hours}
          onChange={(e) => setHours(e.target.value)}
          className="w-20 px-2 py-1 text-xs rounded border border-[var(--color-border)] bg-[var(--color-surface)]"
        />
      </div>
      <div className="flex-1 min-w-[120px]">
        <label className="text-[10px] text-[var(--color-text-secondary)]">{t('timeTracking.description')}</label>
        <input
          type="text"
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          placeholder={t('timeTracking.descriptionPlaceholder')}
          className="w-full px-2 py-1 text-xs rounded border border-[var(--color-border)] bg-[var(--color-surface)]"
        />
      </div>
      <label className="flex items-center gap-1 text-xs">
        <input type="checkbox" checked={billable} onChange={(e) => setBillable(e.target.checked)} />
        {t('timeTracking.billable')}
      </label>
      <button
        onClick={handleSave}
        disabled={saving}
        className="px-3 py-1 text-xs rounded bg-[var(--color-primary)] text-white hover:opacity-90 disabled:opacity-50"
      >
        {t('actions.save')}
      </button>
    </div>
  )
}
