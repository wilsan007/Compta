import { useState, useEffect, useCallback, useRef } from 'react'
import { getTenantEnabledModules, updateTenantModules } from '@/lib/queries/misc'

const ALL_MODULES = [
  'home',
  'accounting',
  'commercial',
  'treasury',
  'stock',
  'production',
  'hr',
  'projectManagement',
  'dashboards',
  'reporting',
  'system',
]

const DEFAULT_MODULES = [...ALL_MODULES]
const STORAGE_KEY = 'compta-enabled-modules'

function readSessionCache(): string[] | null {
  try {
    const raw = sessionStorage.getItem(STORAGE_KEY)
    if (raw) {
      const parsed = JSON.parse(raw)
      if (Array.isArray(parsed) && parsed.length > 0) return parsed
    }
  } catch (err) {
    console.error("catch:", err)
    // ignore
  }
  return null
}

function writeSessionCache(modules: string[]) {
  try {
    sessionStorage.setItem(STORAGE_KEY, JSON.stringify(modules))
  } catch (err) {
    console.error("catch:", err)
    // ignore
  }
}

let cachedModules: string[] | null = readSessionCache()
let cachePromise: Promise<string[]> | null = null
let resetCounter = 0

// Pub/sub: all hook instances subscribe so they stay in sync
const subscribers = new Set<(modules: string[], resetCount: number) => void>()

function broadcastModules(modules: string[]) {
  cachedModules = modules
  writeSessionCache(modules)
  subscribers.forEach((fn) => fn(modules, resetCounter))
}

export function useTenantModules() {
  // Fail closed: default to NO modules until the confirmed list is loaded.
  // Returning ALL_MODULES during loading/error would let users bypass module
  // access controls (ModuleGuard / useModuleAccess decide in the browser).
  const [modules, setModules] = useState<string[]>(cachedModules || [])
  const [loading, setLoading] = useState(!cachedModules)
  const lastResetCount = useRef(resetCounter)

  const refresh = useCallback(async () => {
    if (cachePromise) {
      const result = await cachePromise
      broadcastModules(result)
      return result
    }
    setLoading(true)
    cachePromise = getTenantEnabledModules()
    try {
      const result = await cachePromise
      broadcastModules(result)
      return result
    } catch (err) {
      // Fail closed: no module access on error.
      console.error('useTenantModules cache:', err)
      broadcastModules([])
      return []
    } finally {
      cachePromise = null
      setLoading(false)
    }
  }, [])

  // Subscribe to module changes from other instances
  useEffect(() => {
    const handler = (newModules: string[], resetCount: number) => {
      setModules(newModules)
      setLoading(false)
      if (resetCount > lastResetCount.current) {
        lastResetCount.current = resetCount
        refresh()
      }
    }
    subscribers.add(handler)
    // Sync immediately if cache already exists
    if (cachedModules) {
      setModules(cachedModules)
      setLoading(false)
    }
    return () => {
      subscribers.delete(handler)
    }
  }, [refresh])

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
      broadcastModules(newModules)
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
  try {
    sessionStorage.removeItem(STORAGE_KEY)
  } catch (err) {
    console.error("catch:", err)
    // ignore
  }
}

export function resetModuleCache() {
  cachedModules = null
  cachePromise = null
  resetCounter++
  try {
    sessionStorage.removeItem(STORAGE_KEY)
  } catch (err) {
    console.error("catch:", err)
    // ignore
  }
  // Fail closed on reset: subscribers will re-fetch and confirm the real list.
  subscribers.forEach((fn) => fn([], resetCounter))
}

export { ALL_MODULES, DEFAULT_MODULES }
