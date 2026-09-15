/* oxlint-disable react/only-export-components -- composants et hooks/constantes associes exportes ensemble */
import { createContext, useContext, type ReactNode } from 'react'
import { useProjects } from '@/hooks/useProjects'

type ProjectContextValue = ReturnType<typeof useProjects>

const ProjectContext = createContext<ProjectContextValue | null>(null)

interface ProjectProviderProps {
  children: ReactNode
}

export function ProjectProvider({ children }: ProjectProviderProps) {
  const projects = useProjects()
  return <ProjectContext.Provider value={projects}>{children}</ProjectContext.Provider>
}

export function useProjectContext(): ProjectContextValue {
  const ctx = useContext(ProjectContext)
  if (!ctx) {
    throw new Error('useProjectContext must be used within a ProjectProvider')
  }
  return ctx
}
