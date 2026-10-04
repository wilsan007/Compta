import { useState, useEffect, useCallback } from 'react'
import { getTasks } from '@/lib/queries/projectManagement'

interface WorkloadInfo {
  count: number
  totalEffort: number
  isOverloaded: boolean
}

export function useWorkloadAlert(assigneeName: string | null) {
  const [workload, setWorkload] = useState<WorkloadInfo>({ count: 0, totalEffort: 0, isOverloaded: false })
  const [loading, setLoading] = useState(false)

  const checkWorkload = useCallback(async () => {
    if (!assigneeName) {
      setWorkload({ count: 0, totalEffort: 0, isOverloaded: false })
      return
    }
    setLoading(true)
    try {
      const allTasks = await getTasks()
      const assigneeTasks = allTasks.filter(
        (t) => t.assignee === assigneeName && t.status !== 'done' && t.status !== 'canceled'
      )
      const count = assigneeTasks.length
      const totalEffort = assigneeTasks.reduce((sum, t) => sum + Number(t.effort_estimate_h || 0), 0)
      const isOverloaded = count >= 10 || totalEffort >= 40
      setWorkload({ count, totalEffort, isOverloaded })
    } catch {
      setWorkload({ count: 0, totalEffort: 0, isOverloaded: false })
    } finally {
      setLoading(false)
    }
  }, [assigneeName])

  useEffect(() => {
    checkWorkload()
  }, [checkWorkload])

  return { workload, loading, refetch: checkWorkload }
}
