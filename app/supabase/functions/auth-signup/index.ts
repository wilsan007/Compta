// @ts-nocheck — This file runs in Deno (Supabase Edge Function), not in the local TS environment.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { sendEmailViaResend, buildSignupConfirmationEmail } from "../_shared/email.ts"

// ============================================
// INLINE RATE LIMITING
// ============================================
interface RateLimitEntry { count: number; resetAt: number }
const rateLimitMap = new Map<string, RateLimitEntry>()
let lastCleanup = Date.now()
function cleanupExpired() {
  const now = Date.now()
  if (now - lastCleanup < 300_000) return
  lastCleanup = now
  for (const [key, entry] of rateLimitMap) {
    if (now > entry.resetAt) rateLimitMap.delete(key)
  }
}
function checkRateLimit(key: string, maxRequests: number, windowMs: number): boolean {
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
function getClientIp(req: Request): string {
  const xff = req.headers.get("X-Forwarded-For")
  if (xff) return xff.split(",")[0].trim()
  const xreal = req.headers.get("X-Real-IP")
  if (xreal) return xreal.trim()
  const cfip = req.headers.get("CF-Connecting-IP")
  if (cfip) return cfip.trim()
  return "unknown"
}

// ============================================
// CORS
// ============================================
const APP_URL = Deno.env.get("APP_URL") || "https://projet-compta.zdouce-zz.workers.dev"
const ALLOWED_ORIGINS = [APP_URL, "http://localhost:5173", "http://localhost:4173"]

function getCorsHeaders(req: Request) {
  const origin = req.headers.get("Origin") || ""
  const allowedOrigin = ALLOWED_ORIGINS.includes(origin) ? origin : ""
  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  }
}

// ============================================
// VALIDATION
// ============================================
function validateEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
}

function validatePassword(pw: string): string | null {
  if (!pw || pw.length < 8) return "Password must be at least 8 characters"
  if (!/[A-Z]/.test(pw)) return "Password must contain at least one uppercase letter"
  if (!/[a-z]/.test(pw)) return "Password must contain at least one lowercase letter"
  if (!/[0-9]/.test(pw)) return "Password must contain at least one digit"
  return null
}

// ============================================
// MAIN HANDLER
// ============================================
serve(async (req) => {
  const corsHeaders = getCorsHeaders(req)

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  // Rate limit: max 3 signups per minute per IP
  const clientIp = getClientIp(req)
  if (!checkRateLimit(`signup:${clientIp}`, 3, 60_000)) {
    return new Response(
      JSON.stringify({ error: "Too many signup attempts. Please try again later." }),
      { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json", "Retry-After": "60" } },
    )
  }

  try {
    const { email, password, locale } = await req.json()

    if (!email || !password) {
      return new Response(
        JSON.stringify({ error: "Email and password are required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      )
    }

    if (!validateEmail(email)) {
      return new Response(
        JSON.stringify({ error: "Invalid email address" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      )
    }

    const pwError = validatePassword(password)
    if (pwError) {
      return new Response(
        JSON.stringify({ error: pwError }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      )
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!

    const supabase = createClient(supabaseUrl, serviceRoleKey)

    // 1. Check if user already exists
    const { data: existingUsers, error: listErr } = await supabase.auth.admin.listUsers()
    if (listErr) {
      console.error("listUsers error:", listErr.message)
    } else {
      const exists = existingUsers.users.find(u => u.email === email)
      if (exists) {
        return new Response(
          JSON.stringify({ error: "An account already exists with this email. Please log in." }),
          { status: 409, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        )
      }
    }

    // 2. Create user with email_confirm=false (no Supabase email sent)
    const { data: userData, error: createErr } = await supabase.auth.admin.createUser({
      email,
      password,
      email_confirm: false,
    })

    if (createErr) {
      console.error("createUser error:", createErr.message)
      return new Response(
        JSON.stringify({ error: createErr.message }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      )
    }

    // 3. Generate signup confirmation link
    const appUrl = Deno.env.get("APP_URL") || APP_URL
    const redirectTo = `${appUrl}/onboarding`

    const { data: linkData, error: linkError } = await supabase.auth.admin.generateLink({
      type: "signup",
      email,
      password,
      options: { emailRedirectTo: redirectTo },
    })

    let emailSent = false
    if (linkError) {
      console.error("generateLink error:", linkError.message)
    } else if (linkData?.properties?.action_link) {
      // 4. Send confirmation email via Resend
      const name = email.split("@")[0]
      const template = buildSignupConfirmationEmail({
        email,
        name,
        locale: locale || "en",
        confirmationUrl: linkData.properties.action_link,
      })

      const emailResult = await sendEmailViaResend({
        to: email,
        subject: template.subject,
        html: template.html,
      })
      emailSent = emailResult.success

      // 5. Log to email queue
      if (emailResult.success) {
        try {
          await supabase.from("notification_email_queue").insert({
            recipient_email: email,
            recipient_name: name,
            notification_type: "signup_confirmation",
            subject: template.subject,
            status: "sent",
            resend_id: emailResult.id || null,
            sent_at: new Date().toISOString(),
          })
        } catch { /* queue logging failure is non-blocking */ }
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        needsConfirmation: true,
        email_sent: emailSent,
        message: "Account created. Please check your email to confirm your account.",
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    )
  } catch (err) {
    console.error("auth-signup error:", err)
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    )
  }
})
