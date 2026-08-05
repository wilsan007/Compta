// @ts-nocheck — This file runs in Deno (Supabase Edge Function), not in the local TS environment.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { sendEmailViaResend, buildEmailTemplate } from "../_shared/email.ts"

// ============================================
// CONFIG
// ============================================
const APP_URL = Deno.env.get("APP_URL") || "https://projet-compta.zdouce-zz.workers.dev"

const ALLOWED_ORIGINS = [
  APP_URL,
  "http://localhost:5173",
  "http://localhost:4173",
]

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
// RATE LIMITING
// ============================================
interface RateLimitEntry { count: number; resetAt: number }
const rateLimitMap = new Map<string, RateLimitEntry>()
function checkRateLimit(key: string, max: number, windowMs: number): boolean {
  const now = Date.now()
  const entry = rateLimitMap.get(key)
  if (!entry || now > entry.resetAt) {
    rateLimitMap.set(key, { count: 1, resetAt: now + windowMs })
    return true
  }
  if (entry.count >= max) return false
  entry.count++
  return true
}

// ============================================
// MAIN HANDLER
// ============================================
serve(async (req) => {
  const corsHeaders = getCorsHeaders(req)

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  // Rate limit: max 30 emails per minute per IP
  const clientIp = req.headers.get("X-Forwarded-For")?.split(",")[0].trim() || "unknown"
  if (!checkRateLimit(`ip:${clientIp}`, 30, 60_000)) {
    return new Response(
      JSON.stringify({ error: "Trop de requêtes" }),
      { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    )
  }

  try {
    // Auth: verify JWT
    const authHeader = req.headers.get("Authorization") || ""
    const token = authHeader.replace("Bearer ", "")
    if (!token) {
      return new Response(
        JSON.stringify({ error: "Token requis" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || serviceRoleKey

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    })

    const { data: { user }, error: userErr } = await userClient.auth.getUser()
    if (userErr || !user) {
      return new Response(
        JSON.stringify({ error: "Non authentifié" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    const body = await req.json()
    const {
      to_email,
      to_name,
      notification_type,
      title,
      message,
      action_url,
      locale = "en",
      tenant_name = "",
    } = body

    if (!to_email || !title) {
      return new Response(
        JSON.stringify({ error: "to_email et title requis" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    // Build email from shared template
    const template = buildEmailTemplate({
      locale,
      tenantName: tenant_name,
      title,
      message: message || "",
      actionUrl: action_url || null,
    })

    // Send via shared Resend module
    const emailResult = await sendEmailViaResend({
      to: to_email,
      subject: template.subject,
      html: template.html,
    })

    if (!emailResult.success) {
      return new Response(
        JSON.stringify({ error: "Erreur envoi email", details: emailResult.error }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    // Log to notification_email_queue
    const supabase = createClient(supabaseUrl, serviceRoleKey)
    try {
      await supabase.from("notification_email_queue").insert({
        recipient_email: to_email,
        recipient_name: to_name || null,
        notification_type: notification_type || "generic",
        subject: template.subject,
        status: "sent",
        resend_id: emailResult.id || null,
        sent_at: new Date().toISOString(),
      })
    } catch {
      // Queue logging failure should not block the response
    }

    return new Response(
      JSON.stringify({ success: true, email_id: emailResult.id }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    )
  } catch (err) {
    console.error("send-notification-email error:", err)
    return new Response(
      JSON.stringify({ error: "Erreur interne" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    )
  }
})
