import { useState, useCallback, useEffect } from 'react'
import type { TaskFilters, TaskStatus, TaskPriority } from '@/types/projectManagement'
import { emptyTaskFilters } from '@/types/projectManagement'

const STORAGE_KEY = 'pm_task_filters'

export function useTaskFilters() {
  const [filters, setFilters] = useState<TaskFilters>(() => {
    try {
      const stored = localStorage.getItem(STORAGE_KEY)
      if (stored) return { ...emptyTaskFilters, ...JSON.parse(stored) }
    } catch (err) {
      console.error("catch:", err)
      // ignore
    }
    return emptyTaskFilters
  })

  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(filters))
    } catch (err) {
      console.error("catch:", err)
      // ignore
    }
  }, [filters])

  const setSearch = useCallback((search: string) => {
    setFilters((f) => ({ ...f, search }))
  }, [])

  const toggleStatus = useCallback((status: TaskStatus) => {
    setFilters((f) => ({
      ...f,
      status: f.status.includes(status)
        ? f.status.filter((s) => s !== status)
        : [...f.status, status],
    }))
  }, [])

  const togglePriority = useCallback((priority: TaskPriority) => {
    setFilters((f) => ({
      ...f,
      priority: f.priority.includes(priority)
        ? f.priority.filter((p) => p !== priority)
        : [...f.priority, priority],
    }))
  }, [])

  const toggleAssignee = useCallback((assignee: string) => {
    setFilters((f) => ({
      ...f,
      assignee: f.assignee.includes(assignee)
        ? f.assignee.filter((a) => a !== assignee)
        : [...f.assignee, assignee],
    }))
  }, [])

  const toggleProject = useCallback((projectId: string) => {
    setFilters((f) => ({
      ...f,
      project: f.project.includes(projectId)
        ? f.project.filter((p) => p !== projectId)
        : [...f.project, projectId],
    }))
  }, [])

  const toggleTag = useCallback((tagId: string) => {
    setFilters((f) => ({
      ...f,
      tags: f.tags.includes(tagId)
        ? f.tags.filter((t) => t !== tagId)
        : [...f.tags, tagId],
    }))
  }, [])

  const setDateRange = useCallback((dateFrom: string, dateTo: string) => {
    setFilters((f) => ({ ...f, dateFrom, dateTo }))
  }, [])

  const reset = useCallback(() => {
    setFilters(emptyTaskFilters)
  }, [])

  const hasActiveFilters =
    filters.search !== '' ||
    filters.status.length > 0 ||
    filters.priority.length > 0 ||
    filters.assignee.length > 0 ||
    filters.project.length > 0 ||
    filters.tags.length > 0 ||
    filters.dateFrom !== '' ||
    filters.dateTo !== ''

  return {
    filters,
    setFilters,
    setSearch,
    toggleStatus,
    togglePriority,
    toggleAssignee,
    toggleProject,
    toggleTag,
    setDateRange,
    reset,
    hasActiveFilters,
  }
}
