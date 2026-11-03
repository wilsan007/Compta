import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { getActionsForTasks } from '@/lib/queries/projectManagement'
import { buildActionMatrix } from '@/lib/actionColumns'
import type { ProjectTask, TaskAction } from '@/types/projectManagement'

// Les actions de toutes les lignes du tableau, lues par paquets et non tâche par
// tâche. Quand une tâche apparaît, seules ses actions sont lues ; quand elle
// disparaît, ses actions sont retirées sans nouvelle lecture.
export function useTaskActionMatrix(orderedTasks: Pick<ProjectTask, 'id'>[], enabled = true) {
  const [actions, setActions] = useState<TaskAction[]>([])
  const [error, setError] = useState<string | null>(null)
  const loadedRef = useRef(new Set<string>())

  // Clé stable : l'ordre d'affichage ou une modification de cellule ne relance rien.
  const idsKey = useMemo(() => orderedTasks.map((t) => t.id).sort().join('|'), [orderedTasks])

  useEffect(() => {
    if (!enabled) return
    const ids = idsKey ? idsKey.split('|') : []
    const present = new Set(ids)
    for (const id of loadedRef.current) if (!present.has(id)) loadedRef.current.delete(id)
    setActions((prev) => (prev.every((a) => present.has(a.task_id)) ? prev : prev.filter((a) => present.has(a.task_id))))

    const missing = ids.filter((id) => !loadedRef.current.has(id))
    if (missing.length === 0) return

    let cancelled = false
    getActionsForTasks(missing)
      .then((rows) => {
        if (cancelled) return
        for (const id of missing) loadedRef.current.add(id)
        setError(null)
        setActions((prev) => {
          // deux lectures qui se chevauchent ne doivent pas doubler une action
          const seen = new Set(prev.map((a) => a.id))
          return [...prev, ...rows.filter((a) => !seen.has(a.id))]
        })
      })
      .catch((err: Error) => {
        if (!cancelled) setError(err.message || 'actions')
      })
    return () => {
      cancelled = true
    }
  }, [idsKey, enabled])

  const matrix = useMemo(
    () => buildActionMatrix(orderedTasks.map((t) => t.id), actions),
    [orderedTasks, actions]
  )

  const patchAction = useCallback((actionId: string, patch: Partial<TaskAction>) => {
    setActions((prev) => prev.map((a) => (a.id === actionId ? { ...a, ...patch } : a)))
  }, [])

  const appendAction = useCallback((action: TaskAction) => {
    setActions((prev) => (prev.some((a) => a.id === action.id) ? prev : [...prev, action]))
    loadedRef.current.add(action.task_id)
  }, [])

  return { matrix, error, patchAction, appendAction }
}
