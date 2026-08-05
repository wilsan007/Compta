import { useCallback } from 'react'
import { useTenantModules } from '@/lib/useTenantModules'

/**
 * Hook that determines how to access a shared entity (employees, customers, etc.)
 * based on whether the owning module is enabled.
 *
 * - 'full'  → the owning module is active; show a link to the full module page
 * - 'inline' → the owning module is NOT active; show an inline mini-CRUD
 */
export function useModuleAwareAccess() {
  const { isModuleEnabled } = useTenantModules()

  const getAccessStrategy = useCallback(
    (ownerModule: string): 'full' | 'inline' => {
      return isModuleEnabled(ownerModule) ? 'full' : 'inline'
    },
    [isModuleEnabled],
  )

  return { getAccessStrategy, isModuleEnabled }
}
