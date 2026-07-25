// Input sanitization utility for XSS and injection prevention
// Use these functions when processing user input that will be stored in the database
// or displayed in the UI.

/**
 * Sanitize a text input to prevent XSS attacks.
 * - Strips HTML tags
 * - Escapes special characters
 * - Removes null bytes
 * - Trims whitespace
 */
export function sanitizeText(input: string, maxLength: number = 1000): string {
  if (!input || typeof input !== 'string') return ''
  let s = input
  // Remove null bytes
  s = s.replace(/\0/g, '')
  // Strip HTML tags (basic — React already escapes, but defense in depth)
  s = s.replace(/<[^>]*>/g, '')
  // Escape HTML entities
  s = s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#x27;')
  // Trim and limit length
  return s.trim().slice(0, maxLength)
}

/**
 * Sanitize an email address.
 * - Lowercases
 * - Validates format
 * - Limits length
 */
export function sanitizeEmail(email: string): string {
  if (!email || typeof email !== 'string') return ''
  const s = email.trim().toLowerCase().slice(0, 254)
  // Basic email format validation
  if (!/^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$/.test(s)) return ''
  return s
}

/**
 * Sanitize a phone number.
 * - Removes all non-numeric characters except + and spaces
 * - Limits length
 */
export function sanitizePhone(phone: string): string {
  if (!phone || typeof phone !== 'string') return ''
  return phone.replace(/[^0-9+\s()-]/g, '').trim().slice(0, 20)
}

/**
 * Sanitize a numeric input (amounts, quantities).
 * - Removes all non-numeric characters except . and -
 * - Returns a number or null if invalid
 */
export function sanitizeNumber(value: string | number): number | null {
  if (typeof value === 'number') return isFinite(value) ? value : null
  if (!value || typeof value !== 'string') return null
  const cleaned = value.replace(/[^0-9.\-]/g, '')
  const n = parseFloat(cleaned)
  return isFinite(n) ? n : null
}

/**
 * Sanitize a date input (YYYY-MM-DD format).
 * - Validates format
 * - Validates it's a real date
 */
export function sanitizeDate(date: string): string | null {
  if (!date || typeof date !== 'string') return null
  const s = date.trim()
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return null
  const d = new Date(s)
  if (isNaN(d.getTime())) return null
  return s
}

/**
 * Sanitize a filename for safe storage.
 * Uses the same logic as fileSecurity.ts sanitizeFilename.
 */
export function sanitizeFilename(filename: string): string {
  if (!filename || typeof filename !== 'string') return 'unnamed_file'
  let name = filename.replace(/.*[/\\]/, '')
  name = name.replace(/\.\./g, '')
  name = name.replace(/[\x00-\x1f\x7f]/g, '')
  if (name.length > 255) {
    const ext = name.match(/\.[^.]+$/)?.[0] || ''
    name = name.slice(0, 255 - ext.length) + ext
  }
  return name || 'unnamed_file'
}

/**
 * Validate that a tenant_id is a valid UUID format.
 */
export function isValidUUID(uuid: string): boolean {
  if (!uuid || typeof uuid !== 'string') return false
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(uuid)
}

/**
 * Sanitize a URL to prevent javascript: and data: scheme attacks.
 * Only allows http: and https: protocols.
 */
export function sanitizeUrl(url: string): string | null {
  if (!url || typeof url !== 'string') return null
  const s = url.trim()
  // Only allow http/https
  if (/^https?:\/\//i.test(s)) return s
  // Relative URLs are OK
  if (s.startsWith('/') && !s.startsWith('//')) return s
  return null
}

/**
 * Detect and neutralize common SQL injection patterns in string inputs.
 * This is a defense-in-depth measure — Supabase parameterized queries
 * already prevent SQL injection, but this adds an extra layer.
 */
export function detectSqlInjection(input: string): boolean {
  if (!input || typeof input !== 'string') return false
  const patterns = [
    /(\b(OR|AND)\b\s+\d+\s*=\s*\d+)/i,
    /UNION\s+SELECT/i,
    /;\s*(DROP|DELETE|INSERT|UPDATE|ALTER|CREATE)\s/i,
    /--\s*$/,
    /\/\*.*\*\//,
    /\bEXEC(UTE)?\b/i,
    /\bWAITFOR\s+DELAY\b/i,
    /\bBENCHMARK\b/i,
    /\bSLEEP\b\s*\(/i,
  ]
  return patterns.some(p => p.test(input))
}
