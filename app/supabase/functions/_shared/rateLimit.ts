// Shared rate limiting utility for Supabase Edge Functions
// Two-layer protection: IP-based (anti-DDoS) + User-based (anti-abuse)
//
// Usage:
//   import { checkRateLimit, getClientIp, MAX_BODY_SIZE, validateBodySize } from "../_shared/rateLimit.ts"
//
//   const ip = getClientIp(req)
//   const allowed = checkRateLimit(`ip:${ip}`, 30, 60_000) // 30 req/min per IP
//   if (!allowed) return 429 response
//
//   const userId = user.id
//   const userAllowed = checkRateLimit(`user:${userId}`, 10, 60_000) // 10 req/min per user
//   if (!userAllowed) return 429 response

interface RateLimitEntry {
  count: number
  resetAt: number
}

const rateLimitMap = new Map<string, RateLimitEntry>()

// Clean up expired entries every 5 minutes to prevent memory leak
let lastCleanup = Date.now()
function cleanupExpired() {
  const now = Date.now()
  if (now - lastCleanup < 300_000) return // 5 min
  lastCleanup = now
  for (const [key, entry] of rateLimitMap) {
    if (now > entry.resetAt) rateLimitMap.delete(key)
  }
}

/**
 * Check if a request is allowed under the rate limit.
 * @param key - Unique key (e.g. `ip:1.2.3.4` or `user:uuid`)
 * @param maxRequests - Maximum requests in the window
 * @param windowMs - Time window in milliseconds
 * @returns true if allowed, false if rate limited
 */
export function checkRateLimit(
  key: string,
  maxRequests: number,
  windowMs: number,
): boolean {
  cleanupExpired()
  const now = Date.now()
  const entry = rateLimitMap.get(key)
  if (!entry || now > entry.resetAt) {
    rateLimitMap.set(key, { count: 1, resetAt: now + windowMs })
    return true
  }
  if (entry.count >= maxRequests) return false
  entry.count++
  return true
}

/**
 * Extract client IP from request headers.
 * Handles X-Forwarded-For, X-Real-IP, and CF-Connecting-IP (Cloudflare).
 */
export function getClientIp(req: Request): string {
  const xff = req.headers.get("X-Forwarded-For")
  if (xff) return xff.split(",")[0].trim()
  const xreal = req.headers.get("X-Real-IP")
  if (xreal) return xreal.trim()
  const cfip = req.headers.get("CF-Connecting-IP")
  if (cfip) return cfip.trim()
  return "unknown"
}

/** Maximum request body size (100 KB by default) */
export const MAX_BODY_SIZE = 100 * 1024

/**
 * Validate that the request body is not too large.
 * Call this before parsing the body to prevent memory exhaustion.
 */
export async function validateBodySize(req: Request, maxSize: number = MAX_BODY_SIZE): Promise<{ ok: boolean; error?: string }> {
  const contentLength = req.headers.get("Content-Length")
  if (contentLength && parseInt(contentLength, 10) > maxSize) {
    return { ok: false, error: `Body too large (max ${maxSize} bytes)` }
  }
  // Clone and check actual size (Content-Length can be missing or spoofed)
  const clone = req.clone()
  const text = await clone.text()
  if (text.length > maxSize) {
    return { ok: false, error: `Body too large (max ${maxSize} bytes)` }
  }
  return { ok: true }
}

/**
 * Create a standard 429 response with CORS headers.
 */
export function rateLimitResponse(corsHeaders: Record<string, string>, retryAfter: number = 60): Response {
  return new Response(
    JSON.stringify({ error: "Trop de requêtes. Réessayez plus tard." }),
    {
      status: 429,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json",
        "Retry-After": String(retryAfter),
      },
    },
  )
}
