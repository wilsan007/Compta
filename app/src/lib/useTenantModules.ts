import { useState, useEffect, useCallback } from 'react'
import { getTenantEnabledModules, updateTenantModules } from '@/lib/queries'

const ALL_MODULES = [
  'home',
  'accounting',
  'commercial',
  'treasury',
  'stock',
  'production',
  'hr',
  'dashboards',
  'reporting',
  'system',
]

const DEFAULT_MODULES = [...ALL_MODULES]

let cachedModules: string[] | null = null
let cachePromise: Promise<string[]> | null = null

export function useTenantModules() {
  const [modules, setModules] = useState<string[]>(cachedModules || DEFAULT_MODULES)
  const [loading, setLoading] = useState(!cachedModules)

  const refresh = useCallback(async () => {
    if (cachePromise) {
      const result = await cachePromise
      setModules(result)
      setLoading(false)
      return result
    }
    setLoading(true)
    cachePromise = getTenantEnabledModules()
    try {
      const result = await cachePromise
      cachedModules = result
      setModules(result)
      return result
    } catch {
      cachedModules = DEFAULT_MODULES
      setModules(DEFAULT_MODULES)
      return DEFAULT_MODULES
    } finally {
      cachePromise = null
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    if (cachedModules) {
      setModules(cachedModules)
      setLoading(false)
      return
    }
    refresh()
  }, [refresh])

  const saveModules = useCallback(async (tenantId: string, newModules: string[]) => {
    const { success, error } = await updateTenantModules(tenantId, newModules)
    if (success) {
      cachedModules = newModules
      setModules(newModules)
    }
    return { success, error }
  }, [])

  const isModuleEnabled = useCallback(
    (moduleId: string) => modules.includes(moduleId),
    [modules],
  )

  return { modules, loading, refresh, saveModules, isModuleEnabled, allModules: ALL_MODULES }
}

export function invalidateModuleCache() {
  cachedModules = null
  cachePromise = null
}

export { ALL_MODULES, DEFAULT_MODULES }
