import { getEmployees } from '@/lib/queries/payroll'
import { getTenantId } from '@/lib/queries/core'
import type { Employee } from '@/types'

// Chaque ligne du tableau des tâches monte un sélecteur de responsable, et chacun
// lisait la liste des employés : 60 lignes = 60 requêtes identiques. Les lignes
// partagent maintenant une seule lecture. Le cache est clé par société : un changement
// de société ne doit jamais resservir la liste de la précédente. Il est court, et
// `force` le contourne (après la création d'un employé depuis le sélecteur).
const TTL_MS = 30_000

let cache: { tenantId: string | null; at: number; promise: Promise<Employee[]> } | null = null

export async function getEmployeesShared(options: { force?: boolean } = {}): Promise<Employee[]> {
  const tenantId = await getTenantId()
  const now = Date.now()
  if (!options.force && cache && cache.tenantId === tenantId && now - cache.at < TTL_MS) {
    return cache.promise
  }
  const promise = getEmployees()
  cache = { tenantId, at: now, promise }
  // un échec ne doit pas rester en cache : la ligne suivante réessaie
  promise.catch(() => {
    if (cache?.promise === promise) cache = null
  })
  return promise
}

export function resetEmployeesSharedCache(): void {
  cache = null
}
