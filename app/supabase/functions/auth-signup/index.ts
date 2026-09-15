// @ts-nocheck — This file runs in Deno (Supabase Edge Function), not in the local TS environment.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { sendEmailViaResend, buildSignupConfirmationEmail } from "../_shared/email.ts"
import { getCorsHeaders, handleOptions } from "../_shared/cors.ts"
import { checkRateLimit, getClientIp } from "../_shared/rateLimit.ts"

// ============================================
// CORS (SEC-07: utilise shared cors.ts — pas de domaine de test en dur)
// ============================================

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
    return handleOptions(corsHeaders)
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

    // SEC-07: Check if user already exists — use targeted search instead of listUsers()
    // listUsers() is paginated and won't find users beyond the first page (1000 users)
    const { data: existingUser, error: lookupErr } = await supabase
      .from("profiles")
      .select("id, email")
      .eq("email", email)
      .maybeSingle()
    if (lookupErr) {
      console.error("User lookup error:", lookupErr.message)
    } else if (existingUser) {
      return new Response(
        JSON.stringify({ error: "An account already exists with this email. Please log in." }),
        { status: 409, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      )
    }

    // 2. Create user with email_confirm=false (no Supabase email sent)
    const { data: _userData, error: createErr } = await supabase.auth.admin.createUser({
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
    const appUrl = Deno.env.get("APP_URL") || "http://localhost:5173"
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
            tenant_id: null, // Pas de tenant lors du signup — créé ultérieurement
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
