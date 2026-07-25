// Client-side rate limiter for expensive operations (AI calls, exports, imports)
// Prevents users from accidentally (or intentionally) flooding the server with requests

const clientRateMap = new Map<string, { count: number; resetAt: number }>()

/**
 * Check if a client-side operation is allowed under the rate limit.
 * @param key - Operation key (e.g. 'ai-import', 'bank-parse', 'export')
 * @param maxRequests - Maximum requests in the window
 * @param windowMs - Time window in milliseconds
 * @returns true if allowed, false if rate limited
 */
export function checkClientRateLimit(key: string, maxRequests: number, windowMs: number): boolean {
  const now = Date.now()
  const entry = clientRateMap.get(key)
  if (!entry || now > entry.resetAt) {
    clientRateMap.set(key, { count: 1, resetAt: now + windowMs })
    return true
  }
  if (entry.count >= maxRequests) return false
  entry.count++
  return true
}

/**
 * Get remaining requests for a given key.
 */
export function getRemainingRequests(key: string, maxRequests: number): number {
  const entry = clientRateMap.get(key)
  if (!entry || Date.now() > entry.resetAt) return maxRequests
  return Math.max(0, maxRequests - entry.count)
}

/**
 * Get seconds until the rate limit window resets.
 */
export function getRateLimitResetSeconds(key: string): number {
  const entry = clientRateMap.get(key)
  if (!entry) return 0
  return Math.max(0, Math.ceil((entry.resetAt - Date.now()) / 1000))
}

// Pre-configured limits for common operations
export const CLIENT_LIMITS = {
  aiImport: { max: 5, windowMs: 60_000 },      // 5 AI imports per minute
  bankParse: { max: 10, windowMs: 60_000 },     // 10 bank parses per minute
  export: { max: 3, windowMs: 60_000 },          // 3 exports per minute
  import: { max: 5, windowMs: 60_000 },          // 5 imports per minute
  createUser: { max: 5, windowMs: 60_000 },      // 5 user creations per minute
} as const
