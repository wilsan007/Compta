// @ts-nocheck — This file runs in Deno (Supabase Edge Function), not in the local TS environment.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { checkRateLimit, getClientIp, rateLimitResponse, validateBodySize } from "../_shared/rateLimit.ts"

const ALLOWED_ORIGINS = [
  Deno.env.get("APP_URL") || "https://projet-compta.zdouce-zz.workers.dev",
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

function validatePassword(pw: string): string | null {
  if (!pw || pw.length < 8) return "Le mot de passe doit contenir au moins 8 caractères"
  if (!/[A-Z]/.test(pw)) return "Le mot de passe doit contenir au moins une majuscule"
  if (!/[a-z]/.test(pw)) return "Le mot de passe doit contenir au moins une minuscule"
  if (!/[0-9]/.test(pw)) return "Le mot de passe doit contenir au moins un chiffre"
  return null
}

function validateEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
}

const VALID_ROLES = ["admin", "accountant", "manager", "viewer", "custom", "auditor"]

serve(async (req) => {
  const corsHeaders = getCorsHeaders(req)

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  // ============================================
  // RATE LIMITING: IP-based (anti-DDoS) + user-based (anti-abuse)
  // ============================================
  const clientIp = getClientIp(req)
  if (!checkRateLimit(`ip:${clientIp}`, 20, 60_000)) {
    return rateLimitResponse(corsHeaders, 60)
  }

  // Validate body size (max 10 KB for user creation)
  const bodyCheck = await validateBodySize(req, 10 * 1024)
  if (!bodyCheck.ok) {
    return new Response(
      JSON.stringify({ error: bodyCheck.error }),
      { status: 413, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    )
  }

  try {
    // ============================================
    // AUTHENTICATION: Verify JWT from Authorization header
    // ============================================
    const authHeader = req.headers.get("Authorization") || ""
    const token = authHeader.replace("Bearer ", "")
    if (!token) {
      return new Response(
        JSON.stringify({ error: "Token d'authentification requis" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      )
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") || serviceRoleKey

    // Create client with user's JWT to verify identity
    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    })

    // Get the authenticated user's session
    const { data: { user }, error: userErr } = await userClient.auth.getUser()
    if (userErr || !user) {
      return new Response(
        JSON.stringify({ error: "Utilisateur non authentifié" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      )
    }

    // Per-user rate limit: max 5 user creations per minute
    if (!checkRateLimit(`user:${user.id}`, 5, 60_000)) {
      return rateLimitResponse(corsHeaders, 60)
    }

    // ============================================
    // AUTHORIZATION: Verify caller is admin of the target tenant
    // ============================================
    const { email, name, role, permissions, tenant_id, invited_by, locale, valid_from, valid_until } = await req.json()

    if (!email || !tenant_id) {
      return new Response(
        JSON.stringify({ error: "email et tenant_id requis" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      )
    }

    if (!validateEmail(email)) {
      return new Response(
        JSON.stringify({ error: "Format d'email invalide" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      )
    }

    if (role && !VALID_ROLES.includes(role)) {
      return new Response(
        JSON.stringify({ error: "Rôle invalide" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      )
    }

    // Use service role client for privileged operations
    const supabase = createClient(supabaseUrl, serviceRoleKey)

    // Verify caller is an active admin in the SAME tenant
    // SECURITY: Filter by tenant_id to avoid maybeSingle() failure for multi-tenant users
    const { data: callerTenantUser, error: callerErr } = await supabase
      .from("tenant_users")
      .select("id, role, status, tenant_id")
      .eq("auth_id", user.id)
      .eq("status", "active")
      .eq("tenant_id", tenant_id)
      .maybeSingle()

    if (callerErr || !callerTenantUser) {
      return new Response(
        JSON.stringify({ error: "Utilisateur non trouvé dans le système multi-tenant" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      )
    }

    if (callerTenantUser.role !== "admin") {
      return new Response(
        JSON.stringify({ error: "Seuls les administrateurs peuvent ajouter des utilisateurs" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      )
    }

    // CRITICAL: Admin can only add users to their OWN tenant
    if (callerTenantUser.tenant_id !== tenant_id) {
      return new Response(
        JSON.stringify({ error: "Vous ne pouvez ajouter des utilisateurs qu'à votre propre entreprise" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      )
    }

    // 1. Check if user already exists in this tenant
    const { data: existingTenantUser } = await supabase
      .from("tenant_users")
      .select("id, status, auth_id")
      .eq("tenant_id", tenant_id)
      .eq("email", email)
      .maybeSingle()

    if (existingTenantUser) {
      // User already has a row in this tenant
      if (existingTenantUser.status === "active") {
        return new Response(
          JSON.stringify({ error: "Cet email est déjà enregistré et actif dans cette entreprise." }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        )
      }

      if (existingTenantUser.status === "pending") {
        return new Response(
          JSON.stringify({ error: "Cet email a déjà une invitation en attente dans cette entreprise." }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        )
      }

      // status === 'revoked' — re-invite: reactivate with new role
      if (existingTenantUser.status === "revoked") {
        const { error: reactivateErr } = await supabase
          .from("tenant_users")
          .update({
            role: role || "viewer",
            permissions: permissions || {},
            status: "pending",
            accepted_at: null,
            last_login: null,
            invited_by: invited_by || null,
            invited_at: new Date().toISOString(),
            valid_from: valid_from || null,
            valid_until: valid_until || null,
          })
          .eq("id", existingTenantUser.id)

        if (reactivateErr) {
          return new Response(
            JSON.stringify({ error: reactivateErr.message }),
            { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
          )
        }

        // Send magic link invitation email
        const appUrl = Deno.env.get("APP_URL") || "https://projet-compta.zdouce-zz.workers.dev"
        const redirectTo = `${appUrl}/accept-invitation`
        const otpOptions: Record<string, any> = { emailRedirectTo: redirectTo }
        if (locale && ["fr", "en", "ar"].includes(locale)) {
          otpOptions.lang = locale
        }
        const { error: otpError } = await supabase.auth.signInWithOtp({
          email,
          options: otpOptions,
        })

        if (otpError) {
          console.error("Failed to send re-invitation email:", otpError.message)
        }

        return new Response(
          JSON.stringify({
            success: true,
            email,
            existing_user: true,
            reactivated: true,
            email_sent: !otpError,
            message: "Utilisateur réactivé. Email d'invitation envoyé.",
          }),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        )
      }
    }

    // 2. Check if auth user already exists with this email
    // If yes, link them to this tenant (multi-tenant: same user, multiple tenants)
    // If no, create a new auth user
    let authId: string
    let existingUser = false

    // Check if user already exists in auth.users via RPC (avoids listing all users)
    const { data: emailExists, error: rpcErr } = await supabase
      .rpc("auth_email_exists", { p_email: email })

    if (rpcErr) {
      return new Response(
        JSON.stringify({ error: "Erreur lors de la vérification de l'email" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      )
    }

    if (emailExists) {
      // User already has an auth account — look up their auth_id via tenant_users
      // SECURITY: Do NOT use listUsers() — it returns ALL users across ALL tenants (email enumeration)
      const { data: authUser, error: authLookupErr } = await supabase
        .from("tenant_users")
        .select("auth_id")
        .eq("email", email)
        .not("auth_id", "is", null)
        .limit(1)

      if (authLookupErr || !authUser || authUser.length === 0) {
        // User exists in auth.users but has no tenant_users record with auth_id
        // They may have signed up independently. Send a magic link to link them.
        // Do NOT enumerate all users to find their auth_id.
        return new Response(
          JSON.stringify({ error: "Cet email existe déjà dans le système mais n'est pas lié à un tenant. L'utilisateur doit d'abord se connecter avec son compte existant, puis accepter l'invitation." }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        )
      }
      authId = authUser[0].auth_id!
      existingUser = true
    } else {
      // 3. Create new auth user WITHOUT password (magic link flow)
      const { data: authData, error: authError } = await supabase.auth.admin.createUser({
        email,
        email_confirm: true,
        user_metadata: { name, role, tenant_id },
      })

      if (authError) {
        return new Response(
          JSON.stringify({ error: authError.message }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        )
      }
      authId = authData.user.id
    }

    // 4. Insert tenant_users row with status 'pending' (awaiting acceptance)
    const { error: tuError } = await supabase
      .from("tenant_users")
      .insert({
        tenant_id,
        auth_id: authId,
        email,
        name,
        role: role || "viewer",
        permissions: permissions || {},
        status: "pending",
        accepted_at: null,
        last_login: null,
        invited_by: invited_by || null,
        valid_from: valid_from || null,
        valid_until: valid_until || null,
      })

    if (tuError) {
      // Only rollback auth user creation if we actually created a new one
      if (!existingUser) {
        await supabase.auth.admin.deleteUser(authId)
      }
      return new Response(
        JSON.stringify({ error: tuError.message }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      )
    }

    // 5. Send magic link invitation email (with locale if provided)
    const appUrl = Deno.env.get("APP_URL") || "https://projet-compta.zdouce-zz.workers.dev"
    const redirectTo = `${appUrl}/accept-invitation`
    const otpOptions: Record<string, any> = { emailRedirectTo: redirectTo }
    if (locale && ["fr", "en", "ar"].includes(locale)) {
      otpOptions.lang = locale
    }
    const { error: otpError } = await supabase.auth.signInWithOtp({
      email,
      options: otpOptions,
    })

    if (otpError) {
      console.error("Failed to send invitation email:", otpError.message)
    }

    const message = existingUser
      ? "Utilisateur existant ajouté à cette entreprise. Email d'invitation envoyé."
      : "Utilisateur créé. Email d'invitation envoyé."

    return new Response(
      JSON.stringify({
        success: true,
        email,
        existing_user: existingUser,
        email_sent: !otpError,
        message,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    )
  } catch (err) {
    return new Response(
      JSON.stringify({ error: "Erreur interne du serveur" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    )
  }
})
