import { useState, useEffect, useCallback, useRef } from 'react'
import {
  getTasks,
  createTask,
  updateTask,
  deleteTask,
  duplicateTask,
  createSubTask,
  toggleAction,
  addActionColumn,
  addDetailedAction,
  getTaskDocuments,
  uploadTaskDocument,
  getTaskComments,
  addTaskComment,
  getTaskActionAttachments,
  setTaskAssignee as setTaskAssigneeQuery,
} from '@/lib/queries/projectManagement'
import type { ProjectTask, TaskCreateInput, TaskUpdateInput, TaskFilters } from '@/types/projectManagement'
import { emptyTaskFilters } from '@/types/projectManagement'

export function useTasks(projectId?: string) {
  const [tasks, setTasks] = useState<ProjectTask[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [filters, setFilters] = useState<TaskFilters>(emptyTaskFilters)
  const reqIdRef = useRef(0)

  const refetch = useCallback(async () => {
    const reqId = ++reqIdRef.current
    setLoading(true)
    setError(null)
    try {
      const data = await getTasks(projectId)
      if (reqId !== reqIdRef.current) return
      setTasks(data)
    } catch (err: any) {
      if (reqId !== reqIdRef.current) return
      setError(err.message || 'Failed to load tasks')
    } finally {
      if (reqId === reqIdRef.current) setLoading(false)
    }
  }, [projectId])

  useEffect(() => {
    refetch()
  }, [refetch])

  // Optimistic update helper
  const optimisticUpdate = useCallback((id: string, patch: Partial<ProjectTask>) => {
    setTasks((prev) => prev.map((t) => (t.id === id ? { ...t, ...patch } : t)))
  }, [])

  const handleCreateTask = useCallback(
    async (task: TaskCreateInput): Promise<ProjectTask> => {
      const created = await createTask(task)
      setTasks((prev) => [...prev, created])
      return created
    },
    []
  )

  const handleUpdateTask = useCallback(
    async (id: string, updates: TaskUpdateInput): Promise<ProjectTask> => {
      optimisticUpdate(id, updates)
      try {
        const updated = await updateTask(id, updates)
        setTasks((prev) => prev.map((t) => (t.id === id ? updated : t)))
        return updated
      } catch (err) {
        await refetch()
        throw err
      }
    },
    [optimisticUpdate, refetch]
  )

  const handleDeleteTask = useCallback(
    async (id: string): Promise<void> => {
      const prev = tasks
      setTasks((prevTasks) => prevTasks.filter((t) => t.id !== id && t.parent_id !== id))
      try {
        await deleteTask(id)
        await refetch()
      } catch (err) {
        setTasks(prev)
        throw err
      }
    },
    [tasks, refetch]
  )

  const handleDuplicateTask = useCallback(
    async (id: string): Promise<ProjectTask> => {
      const duplicated = await duplicateTask(id)
      setTasks((prev) => [...prev, duplicated])
      return duplicated
    },
    []
  )

  const handleCreateSubTask = useCallback(
    async (parentId: string, title: string, projId?: string | null): Promise<ProjectTask> => {
      const subtask = await createSubTask(parentId, title, projId)
      setTasks((prev) => [...prev, subtask])
      return subtask
    },
    []
  )

  const handleToggleAction = useCallback(
    async (actionId: string, isDone: boolean): Promise<{ action: import('@/types/projectManagement').TaskAction; progress: number }> => {
      const result = await toggleAction(actionId, isDone)
      optimisticUpdate(result.action.task_id, { progress: result.progress })
      return result
    },
    [optimisticUpdate]
  )

  const handleAddActionColumn = useCallback(
    async (taskId: string, title: string, weightPercentage?: number) => {
      return addActionColumn(taskId, title, weightPercentage)
    },
    []
  )

  const handleAddDetailedAction = useCallback(
    async (
      taskId: string,
      title: string,
      weightPercentage: number,
      dueDate: string | null,
      notes: string | null
    ) => {
      return addDetailedAction(taskId, title, weightPercentage, dueDate, notes)
    },
    []
  )

  const handleSetAssignee = useCallback(
    async (taskId: string, employeeId: string | null, employeeName: string | null) => {
      optimisticUpdate(taskId, { assignee_id: employeeId, assignee: employeeName })
      try {
        await setTaskAssigneeQuery(taskId, employeeId, employeeName)
      } catch (err) {
        await refetch()
        throw err
      }
    },
    [optimisticUpdate, refetch]
  )

  // Filtered tasks (client-side filtering)
  const filteredTasks = tasks.filter((task) => {
    if (filters.search) {
      const q = filters.search.toLowerCase()
      if (!task.title.toLowerCase().includes(q) && !(task.assignee?.toLowerCase().includes(q))) {
        return false
      }
    }
    if (filters.status.length > 0 && !filters.status.includes(task.status)) return false
    if (filters.priority.length > 0 && !filters.priority.includes(task.priority)) return false
    if (filters.assignee.length > 0 && (!task.assignee || !filters.assignee.includes(task.assignee))) return false
    if (filters.project.length > 0 && (!task.project_id || !filters.project.includes(task.project_id))) return false
    if (filters.tags.length > 0 && (!task.tags || !task.tags.some((tag) => filters.tags.includes(tag.id)))) return false
    if (filters.dateFrom && task.due_date && task.due_date < filters.dateFrom) return false
    if (filters.dateTo && task.due_date && task.due_date > filters.dateTo) return false
    return true
  })

  return {
    tasks: filteredTasks,
    allTasks: tasks,
    loading,
    error,
    filters,
    setFilters,
    refetch,
    createTask: handleCreateTask,
    updateTask: handleUpdateTask,
    deleteTask: handleDeleteTask,
    duplicateTask: handleDuplicateTask,
    createSubTask: handleCreateSubTask,
    toggleAction: handleToggleAction,
    setAssignee: handleSetAssignee,
    addActionColumn: handleAddActionColumn,
    addDetailedAction: handleAddDetailedAction,
    getTaskDocuments,
    uploadTaskDocument,
    getTaskComments,
    addTaskComment,
    getTaskActionAttachments,
  }
}
