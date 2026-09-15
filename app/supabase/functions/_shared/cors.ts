// Shared CORS utility for Supabase Edge Functions
// SEC-07: CORS allowlist configurable via environment variables
//
// Usage:
//   import { getCorsHeaders, handleOptions } from "../_shared/cors.ts"
//
//   const corsHeaders = getCorsHeaders(req)
//   if (req.method === "OPTIONS") return handleOptions(corsHeaders)

/**
 * Get the list of allowed origins from environment variables.
 * Falls back to localhost for development.
 *
 * Set ALLOWED_ORIGINS env var as a comma-separated list:
 *   ALLOWED_ORIGINS=https://onusuite.com,https://app.onusuite.com
 */
function getAllowedOrigins(): string[] {
  const envOrigins = Deno.env.get("ALLOWED_ORIGINS")
  if (envOrigins) {
    return envOrigins.split(",").map((o) => o.trim()).filter(Boolean)
  }

  // SEC-07: No hardcoded production domain — require explicit configuration
  const appUrl = Deno.env.get("APP_URL")
  const origins = [
    "http://localhost:5173",
    "http://localhost:4173",
  ]
  if (appUrl) origins.push(appUrl)
  return origins
}

/**
 * Get CORS headers for a request, validating the Origin against the allowlist.
 */
export function getCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") || ""
  const allowedOrigins = getAllowedOrigins()
  const allowedOrigin = allowedOrigins.includes(origin) ? origin : ""

  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type, x-tenant-id",
    "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
  }
}

/**
 * Handle CORS preflight (OPTIONS) request.
 */
export function handleOptions(corsHeaders: Record<string, string>): Response {
  return new Response(null, {
    status: 204,
    headers: corsHeaders,
  })
}
