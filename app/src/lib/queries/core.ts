import { supabase, getCachedTenantId, isTenantTable } from '@/lib/supabase'

// ============ Document numbering ============
// LOT4-10 : numérotation continue par tenant et préfixe (RPC get_next_document_number,
// migration 146) — format PREFIXE-AAAA-NNNNNN. Ne jamais dériver un numéro de Date.now().
export async function nextDocumentNumber(prefix: string): Promise<string> {
  const { data, error } = await supabase.rpc('get_next_document_number', { p_prefix: prefix })
  if (error) throw error
  return data as string
}

// ============ Tenant Helper ============
// RLS policies filter at the DB level, but we also filter at the app level
// for performance (smaller payloads) and defense-in-depth.
let _cachedTenantId: string | null = null

export async function getTenantId(): Promise<string | null> {
  // Check global cache first (set by auth.tsx on login)
  const global = getCachedTenantId()
  if (global) { _cachedTenantId = global; return global }
  // Check local cache
  if (_cachedTenantId) return _cachedTenantId
  // Fetch from DB
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return null
  // User may belong to multiple tenants — pick the one from localStorage or the first
  const { data, error } = await supabase
    .from('tenant_users')
    .select('tenant_id')
    .eq('auth_id', session.user.id)
    .eq('status', 'active')
  if (error) { console.error('getTenantId:', error); return null }
  if (data && data.length > 0) {
    const stored = localStorage.getItem('active_tenant_id')
    const match = data.find(tu => tu.tenant_id === stored)
    const tid = match?.tenant_id || data[0].tenant_id
    _cachedTenantId = tid
    return tid
  }
  return null
}

export function clearTenantCache() {
  _cachedTenantId = null
}

// Helper: add tenant_id to an insert payload if the table is tenant-scoped
// SECURITY: Always force tenant_id to the authenticated user's tenant — never trust client-supplied tenant_id
export function ti<T extends Record<string, any>>(payload: T, table: string, tid: string | null): T {
  if (tid && isTenantTable(table)) return { ...(payload || {}), tenant_id: tid } as T
  return payload
}

// Helper: apply tenant filter to update/delete query builders
// Usage: tud(supabase.from('invoices').update(...), 'invoices', tid).eq('id', id)
export function tud<T extends { eq: (col: string, val: any) => T }>(q: T, table: string, tid: string | null): T {
  if (tid && isTenantTable(table)) return q.eq('tenant_id', tid)
  return q
}


// ============ Pagination (LOT7-03) ============
// `supabase/config.toml` fixe `max_rows = 1000` : toute requête PostgREST non paginée est
// tronquée à 1 000 lignes SANS erreur ni avertissement. Un `.limit(100000)` ne change rien,
// PostgREST rabote toujours à max_rows. La seule sortie est de boucler sur `.range()`.
//
// Mécanique : `PostgrestTransformBuilder.range()` fait `searchParams.set('offset'|'limit')`
// et retourne `this` ; `PostgrestBuilder.then()` déclenche un fetch neuf à chaque `await`.
// Un même builder peut donc être re-`range()` puis ré-attendu. Pour les cas où l'appelant
// préfère repartir d'un builder neuf (mock, requête réutilisée ailleurs), une fabrique
// `() => builder` est acceptée.
//
// ATTENTION : la pagination n'a de sens que sur un tri TOTAL. Sans `ORDER BY` déterministe,
// PostgreSQL est libre de renvoyer les lignes dans un ordre différent d'une page à l'autre —
// des lignes sont alors sautées ou dupliquées. Ajouter `.order('id')` (en dernier critère)
// sur toute requête paginée dont le tri n'est pas déjà unique.
export const PAGE_SIZE = 1000

// Garde-fou : au-delà, on préfère lever plutôt que de saturer la mémoire du navigateur.
// Une requête qui dépasse ce seuil doit être remplacée par une agrégation SQL (RPC).
const MAX_ROWS_DEFAULT = 200_000

type PageResponse<T> = { data: T[] | null; error: unknown }

export interface RangeableQuery<T> {
  range(from: number, to: number): PromiseLike<PageResponse<T>>
}

export async function fetchAllRows<T>(
  source: RangeableQuery<T> | (() => RangeableQuery<T>),
  options: { pageSize?: number; maxRows?: number; label?: string } = {}
): Promise<T[]> {
  const pageSize = options.pageSize ?? PAGE_SIZE
  const maxRows = options.maxRows ?? MAX_ROWS_DEFAULT
  const label = options.label ?? 'fetchAllRows'
  const rows: T[] = []

  for (let from = 0; ; from += pageSize) {
    const query = typeof source === 'function' ? source() : source
    const { data, error } = await query.range(from, from + pageSize - 1)
    if (error) throw error
    const page = data ?? []
    for (const row of page) rows.push(row)
    if (page.length < pageSize) break
    if (rows.length >= maxRows) {
      throw new Error(
        `${label} : plus de ${maxRows} lignes rapatriées. Utiliser une agrégation SQL (RPC) plutôt qu'un chargement complet côté navigateur.`
      )
    }
  }

  return rows
}
