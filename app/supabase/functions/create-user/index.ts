// @ts-nocheck — This file runs in Deno (Supabase Edge Function), not in the local TS environment.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const ALLOWED_ORIGINS = [
  Deno.env.get("APP_URL") || "https://projet-compta.zdouce-zz.workers.dev",
  "http://localhost:5173",
  "http://localhost:4173",
]

function getCorsHeaders(req: Request) {
  const origin = req.headers.get("Origin") || ""
  const allowedOrigin = ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0]
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

const VALID_ROLES = ["admin", "accountant", "manager", "viewer", "custom"]

serve(async (req) => {
  const corsHeaders = getCorsHeaders(req)

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
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

    // ============================================
    // AUTHORIZATION: Verify caller is admin of the target tenant
    // ============================================
    const { email, name, role, permissions, tenant_id, invited_by, locale } = await req.json()

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
    const { data: callerTenantUser, error: callerErr } = await supabase
      .from("tenant_users")
      .select("id, role, status, tenant_id")
      .eq("auth_id", user.id)
      .eq("status", "active")
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
      .select("id, status")
      .eq("tenant_id", tenant_id)
      .eq("email", email)
      .maybeSingle()

    if (existingTenantUser) {
      return new Response(
        JSON.stringify({ error: "Cet email est déjà enregistré dans cette entreprise." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      )
    }

    // 2. Check if auth user already exists with this email
    const { data: existingUsers, error: listError } = await supabase.auth.admin.listUsers()

    let authId: string | null = null
    let isExistingUser = false

    if (!listError && existingUsers) {
      const found = existingUsers.users.find((u: any) => u.email === email)
      if (found) {
        authId = found.id
        isExistingUser = true
      }
    }

    // 3. If no existing auth user, create one WITHOUT password (magic link flow)
    if (!authId) {
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
      })

    if (tuError) {
      // Only rollback auth user if we created it (not if it pre-existed)
      if (!isExistingUser) {
        await supabase.auth.admin.deleteUser(authId!)
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

    return new Response(
      JSON.stringify({
        success: true,
        auth_id: authId,
        email,
        existing_user: isExistingUser,
        email_sent: !otpError,
        message: isExistingUser
          ? "Utilisateur existant ajouté à cette entreprise. Email d'invitation envoyé."
          : "Utilisateur créé. Email d'invitation envoyé."
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
