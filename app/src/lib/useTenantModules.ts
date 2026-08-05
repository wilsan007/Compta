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
  } catch {
    // ignore
  }
  return null
}

function writeSessionCache(modules: string[]) {
  try {
    sessionStorage.setItem(STORAGE_KEY, JSON.stringify(modules))
  } catch {
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
  const [modules, setModules] = useState<string[]>(cachedModules || DEFAULT_MODULES)
  const [loading, setLoading] = useState(!cachedModules)
  let lastResetCount = resetCounter

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
    } catch {
      broadcastModules(DEFAULT_MODULES)
      return DEFAULT_MODULES
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
      if (resetCount > lastResetCount) {
        lastResetCount = resetCount
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
  } catch {
    // ignore
  }
}

export function resetModuleCache() {
  cachedModules = null
  cachePromise = null
  resetCounter++
  try {
    sessionStorage.removeItem(STORAGE_KEY)
  } catch {
    // ignore
  }
  subscribers.forEach((fn) => fn(DEFAULT_MODULES, resetCounter))
}

export { ALL_MODULES, DEFAULT_MODULES }
