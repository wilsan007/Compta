/* oxlint-disable react/only-export-components -- composants et hooks/constantes associes exportes ensemble */
import { createContext, useContext, type ReactNode } from 'react'
import { useTasks } from '@/hooks/useTasks'

type TaskContextValue = ReturnType<typeof useTasks>

const TaskContext = createContext<TaskContextValue | null>(null)

interface TaskProviderProps {
  projectId?: string
  children: ReactNode
}

export function TaskProvider({ projectId, children }: TaskProviderProps) {
  const tasks = useTasks(projectId)
  return <TaskContext.Provider value={tasks}>{children}</TaskContext.Provider>
}

export function useTaskContext(): TaskContextValue {
  const ctx = useContext(TaskContext)
  if (!ctx) {
    throw new Error('useTaskContext must be used within a TaskProvider')
  }
  return ctx
}
