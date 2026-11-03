import { useState, useEffect, useCallback, useMemo } from 'react'
import { GANTT_COLOR_PALETTE } from '@/lib/ganttColors'
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

  const refetch = useCallback(async (silent = false) => {
    if (!silent) setLoading(true)
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
      if (!silent) setLoading(false)
    }
  }, [])

  // Après une écriture qui se propage en base (dates décalées, progression
  // remontée), on relit sans repasser par l'écran de chargement.
  const refreshSilently = useCallback(() => refetch(true), [refetch])

  useEffect(() => {
    refetch()
  }, [refetch])

  // Une couleur par projet, la même dans toutes les vues : celle du projet si
  // elle est posée, sinon une couleur de la palette attribuée dans l'ordre de
  // CRÉATION (stable : un projet ajouté ne repeint pas les autres). L'ancien
  // repli peignait tous les projets sans couleur du même bleu.
  const projectColorMap = useMemo(() => {
    const map = new Map<string, string>()
    const byCreation = [...projects].sort((a, b) =>
      String(a.created_at || '').localeCompare(String(b.created_at || '')) || a.id.localeCompare(b.id)
    )
    byCreation.forEach((p, i) => {
      // `#0066cc` est la valeur PAR DÉFAUT de la colonne : posée sur tout projet
      // créé sans choix, elle peignait tous les projets du même bleu (mesuré le
      // 25/10). Seule une couleur réellement choisie l'emporte sur la palette.
      const own = typeof p.color === 'string' && /^#[0-9a-f]{6}$/i.test(p.color) && p.color.toLowerCase() !== '#0066cc' ? p.color : null
      map.set(p.id, own ?? GANTT_COLOR_PALETTE[i % 30])
    })
    return map
  }, [projects])

  return {
    projects,
    loading,
    error,
    refetch,
    refreshSilently,
    projectColorMap,
    customerNames,
  }
}
