// @ts-nocheck — This file runs in Deno (Supabase Edge Function), not in the local TS environment.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { sendEmailViaResend, buildEmailTemplate } from "../_shared/email.ts"
import { getCorsHeaders, handleOptions } from "../_shared/cors.ts"
import { forbidden, isTenantMember } from "../_shared/tenantAccess.ts"
import { checkRateLimit, getClientIp } from "../_shared/rateLimit.ts"

// ============================================
// MAIN HANDLER
// ============================================
serve(async (req) => {
  const corsHeaders = getCorsHeaders(req)

  if (req.method === "OPTIONS") {
    return handleOptions(corsHeaders)
  }

  // Rate limit: max 30 emails per minute per IP
  const clientIp = getClientIp(req)
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
      tenant_id = null,
    } = body

    // Pas de relais d'e-mails arbitraires : l'appelant doit appartenir au tenant et le
    // destinataire doit être un utilisateur ou un salarié de ce tenant.
    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey)
    if (!(await isTenantMember(supabaseAdmin, user.id, tenant_id))) return forbidden(corsHeaders)
    const [{ data: tuMatch }, { data: empMatch }, { data: tenantRow }] = await Promise.all([
      supabaseAdmin.from("tenant_users").select("id").eq("tenant_id", tenant_id).ilike("email", to_email || "").limit(1),
      supabaseAdmin.from("employees").select("id").eq("tenant_id", tenant_id).ilike("email", to_email || "").limit(1),
      supabaseAdmin.from("tenants").select("name").eq("id", tenant_id).maybeSingle(),
    ])
    if (!(tuMatch?.length || empMatch?.length)) return forbidden(corsHeaders)
    const reqOrigin = req.headers.get("Origin")
    const safeActionUrl = action_url && reqOrigin && String(action_url).startsWith(reqOrigin + "/") ? action_url : null

    if (!to_email || !title) {
      return new Response(
        JSON.stringify({ error: "to_email et title requis" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    // Build email from shared template
    const template = buildEmailTemplate({
      locale,
      tenantName: tenantRow?.name || tenant_name,
      title,
      message: message || "",
      actionUrl: safeActionUrl,
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
        tenant_id: tenant_id,
      })
    } catch (err) {
      console.error("catch:", err)
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
