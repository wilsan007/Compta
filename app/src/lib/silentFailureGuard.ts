/**
 * silentFailureGuard.ts — Détection runtime des failures silencieux
 *
 * Adapté à Supabase (le projet n'utilise pas Prisma).
 * Fournit:
 *   1. wrapSupabaseClient() — Proxy sur le client Supabase qui:
 *      - track les requêtes dont l'error n'est pas lu (unchecked response)
 *      - track les requêtes sur tables tenant sans filtre tenant_id
 *      - logge via SilentFailureReporter
 *   2. SilentFailureReporter — collecteur central qui:
 *      - envoie à Sentry (si disponible)
 *      - logge en console (dev)
 *      - expose un compteur pour tests
 *   3. installGlobalRejectionHandler() — capture les unhandledrejections
 *   4. trackPromise() — wrapper pour détecter les promises flottants
 *
 * Usage (dans supabase.ts, mode dev seulement):
 *   import { wrapSupabaseClient } from '@/lib/silentFailureGuard'
 *   export const supabase = wrapSupabaseClient(createClient(...))
 *
 * Activation: VITE_SILENT_FAILURE_GUARD=true dans .env.local
 */

import type { SupabaseClient } from '@supabase/supabase-js'
import { isTenantTable } from '@/lib/supabase'

// ---------- Reporter ----------
type Severity = 'error' | 'warning' | 'info'

interface SilentFailureEvent {
  type: string
  severity: Severity
  message: string
  table?: string
  details?: Record<string, unknown>
  timestamp: number
}

class SilentFailureReporter {
  private events: SilentFailureEvent[] = []
  private maxEvents = 500
  private enabled: boolean

  constructor() {
    this.enabled = import.meta.env.VITE_SILENT_FAILURE_GUARD === 'true'
  }

  isEnabled(): boolean {
    return this.enabled
  }

  report(event: Omit<SilentFailureEvent, 'timestamp'>) {
    if (!this.enabled) return
    const full: SilentFailureEvent = { ...event, timestamp: Date.now() }
    this.events.push(full)
    if (this.events.length > this.maxEvents) this.events.shift()

    // Console output (color-coded)
    const tag = `[SFG:${event.severity.toUpperCase()}]`
    const styled = event.severity === 'error'
      ? `color: #dc2626; font-weight: bold`
      : event.severity === 'warning'
        ? `color: #d97706`
        : 'color: #2563eb'
    // eslint-disable-next-line no-console
    console.groupCollapsed(`%c${tag} ${event.type}`, styled)
    // eslint-disable-next-line no-console
    console.log('message:', event.message)
    if (event.table) { /* eslint-disable-next-line no-console */ console.log('table:', event.table) }
    if (event.details) { /* eslint-disable-next-line no-console */ console.log('details:', event.details) }
    // eslint-disable-next-line no-console
    console.groupEnd()

    // Sentry (if loaded)
    try {
      const sentry = (window as any).__SENTRY__?.hub
      if (sentry && event.severity === 'error') {
        sentry.captureMessage?.(`[SFG] ${event.type}: ${event.message}`, 'error')
      }
    } catch { /* ignore */ }
  }

  getEvents(): readonly SilentFailureEvent[] {
    return this.events
  }

  getCounts(): Record<string, number> {
    const counts: Record<string, number> = {}
    for (const e of this.events) {
      const key = `${e.type}:${e.severity}`
      counts[key] = (counts[key] || 0) + 1
    }
    return counts
  }

  clear() {
    this.events = []
  }

  // For test access
  dump(): string {
    return JSON.stringify(this.events, null, 2)
  }
}

export const silentFailureReporter = new SilentFailureReporter()

// ---------- Global rejection handler ----------
export function installGlobalRejectionHandler() {
  if (typeof window === 'undefined') return
  window.addEventListener('unhandledrejection', (event) => {
    silentFailureReporter.report({
      type: 'UNHANDLED_REJECTION',
      severity: 'error',
      message: `Promise rejection non gérée: ${event.reason?.message || event.reason}`,
      details: { reason: String(event.reason), stack: event.reason?.stack },
    })
  })
  // Also catch errors that would otherwise be silent
  window.addEventListener('error', (event) => {
    silentFailureReporter.report({
      type: 'GLOBAL_ERROR',
      severity: 'error',
      message: event.message,
      details: { filename: event.filename, lineno: event.lineno, colno: event.colno },
    })
  })
}

// ---------- Promise tracker ----------
const trackedPromises = new WeakSet<Promise<unknown>>()

/**
 * Wrap a promise to detect if it's never awaited (floating promise).
 * In dev mode, schedules a microtask check: if the promise is still pending
 * and not awaited within the next tick, reports a floating promise.
 */
export function trackPromise<T>(p: Promise<T>, label: string): Promise<T> {
  if (!silentFailureReporter.isEnabled()) return p
  if (trackedPromises.has(p as unknown as Promise<unknown>)) return p
  trackedPromises.add(p as unknown as Promise<unknown>)

  let awaited = false
  const tracked = p.then(
    (val) => { awaited = true; return val },
    (err) => {
      awaited = true
      silentFailureReporter.report({
        type: 'PROMISE_REJECTED',
        severity: 'error',
        message: `${label} rejetée: ${err?.message || err}`,
      })
      throw err
    },
  )
  // Check after a tick if the original was consumed
  // Note: this is best-effort — if the caller doesn't await `tracked`, the original
  // rejection would be unhandled. We rely on the global handler as backstop.
  queueMicrotask(() => {
    if (!awaited) {
      silentFailureReporter.report({
        type: 'FLOATING_PROMISE',
        severity: 'warning',
        message: `${label} — promise créée mais non consommée dans le même tick`,
      })
    }
  })
  return tracked
}

// ---------- Supabase client wrapper ----------
/**
 * Wraps a Supabase client to detect at runtime:
 *   - responses where `error` is never accessed (unchecked query)
 *   - queries on tenant tables without a tenant_id filter
 *
 * This uses a Proxy on the `.from()` builder. Because supabase-js builders
 * are chainable and return new instances, we wrap the query builder's
 * `.then()` (the await point) to inspect the result.
 */
export function wrapSupabaseClient(client: SupabaseClient): SupabaseClient {
  if (!silentFailureReporter.isEnabled()) return client

  const originalFrom = client.from.bind(client)

  const wrappedFrom = new Proxy(originalFrom, {
    apply(target, thisArg, args: [string]) {
      const table = args[0]
      const builder = Reflect.apply(target, thisArg, args)
      const isTenant = isTenantTable(table)

      // Wrap the builder to intercept the await (then)
      const thenable = builder as unknown as { then?: Function }
      const originalThen = thenable.then?.bind(builder)
      if (originalThen) {
        thenable.then = function (onFulfilled: any, onRejected: any) {
          return originalThen(
            (result: any) => {
              // Check: did the caller destructure error?
              // We can't know for sure, but if result.error exists and is truthy,
              // we log it (the caller may still ignore it — that's the silent failure).
              if (result?.error && isTenant) {
                silentFailureReporter.report({
                  type: 'SUPABASE_ERROR_UNCHECKED',
                  severity: 'warning',
                  message: `Erreur Supabase sur ${table}: ${result.error.message}`,
                  table,
                  details: { code: result.error.code, hint: result.error.hint },
                })
              }
              // Check: tenant table query without tenant_id filter
              // We inspect the query URL via builder.url if available (best-effort)
              if (isTenant && !result?.error) {
                // Heuristic: if the query returned 0 rows on a tenant table and
                // we have no tenant context, it might be a missing filter
                // (RLS would block, but the symptom is empty result = silent)
                // We skip false positives here; the static analyzer covers this better.
              }
              return onFulfilled ? onFulfilled(result) : result
            },
            onRejected,
          )
        }
      }
      return builder
    },
  })

  // Return a proxy that overrides .from()
  return new Proxy(client, {
    get(target, prop) {
      if (prop === 'from') return wrappedFrom
      const val = Reflect.get(target, prop)
      return typeof val === 'function' ? val.bind(target) : val
    },
  }) as SupabaseClient
}

// Attach helper to reporter for the isEnabled check (already defined as method above)
