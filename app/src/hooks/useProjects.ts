import { useState, useEffect, useCallback } from 'react'
import { getProjects } from '@/lib/queries/accounting'
import { getCustomers } from '@/lib/queries/partners'
import type { Project } from '@/types'

export interface ProjectWithMeta extends Project {
  color: string
  display_order: string
  progress: number
  manager_id: string | null
  allow_subtasks: boolean
  allow_recurrent_tasks: boolean
  allow_milestones: boolean
  allow_task_dependencies: boolean
  allow_timesheets: boolean
  allow_billable: boolean
  privacy_visibility: string
  alias_name: string | null
  allocated_hours: number
  total_hours_spent: number
  remaining_hours: number
}

export function useProjects() {
  const [projects, setProjects] = useState<ProjectWithMeta[]>([])
  const [customerNames, setCustomerNames] = useState<Map<string, string>>(new Map())
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const refetch = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const [data, customers] = await Promise.all([getProjects(), getCustomers()])
      setProjects(data as unknown as ProjectWithMeta[])
      const cMap = new Map<string, string>()
      customers.forEach((c) => cMap.set(c.id, c.name))
      setCustomerNames(cMap)
    } catch (err: any) {
      setError(err.message || 'Failed to load projects')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    refetch()
  }, [refetch])

  const projectColorMap = new Map<string, string>()
  for (const p of projects) {
    projectColorMap.set(p.id, p.color || '#0066cc')
  }

  return {
    projects,
    loading,
    error,
    refetch,
    projectColorMap,
    customerNames,
  }
}
