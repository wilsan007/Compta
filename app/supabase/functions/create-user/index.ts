import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    const { email, password, name, role, permissions, tenant_id, invited_by } = await req.json()

    if (!email || !tenant_id) {
      return new Response(
        JSON.stringify({ error: "email et tenant_id requis" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      )
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!

    const supabase = createClient(supabaseUrl, serviceRoleKey)

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

    // 3. If no existing auth user, create one with password
    if (!authId) {
      if (!password || password.length < 6) {
        return new Response(
          JSON.stringify({ error: "Le mot de passe doit contenir au moins 6 caractères" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        )
      }

      const { data: authData, error: authError } = await supabase.auth.admin.createUser({
        email,
        password,
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

    // 4. Insert tenant_users row with status 'active'
    const { error: tuError } = await supabase
      .from("tenant_users")
      .insert({
        tenant_id,
        auth_id: authId,
        email,
        name,
        role: role || "viewer",
        permissions: permissions || {},
        status: "active",
        accepted_at: new Date().toISOString(),
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

    return new Response(
      JSON.stringify({
        success: true,
        auth_id: authId,
        email,
        existing_user: isExistingUser,
        message: isExistingUser
          ? "Utilisateur existant ajouté à cette entreprise (mot de passe inchangé)"
          : "Nouvel utilisateur créé"
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    )
  } catch (err) {
    return new Response(
      JSON.stringify({ error: err.message || "Erreur interne" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    )
  }
})
