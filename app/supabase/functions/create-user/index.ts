// @ts-nocheck — This file runs in Deno (Supabase Edge Function), not in the local TS environment.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { sendEmailViaResend, buildInvitationEmail } from "../_shared/email.ts"
import { getCorsHeaders, handleOptions } from "../_shared/cors.ts"
import { checkRateLimit, getClientIp, validateBodySize, rateLimitResponse } from "../_shared/rateLimit.ts"

function validateEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
}

const VALID_ROLES = ["admin", "accountant", "manager", "viewer", "custom", "auditor"]

serve(async (req) => {
  const corsHeaders = getCorsHeaders(req)

  if (req.method === "OPTIONS") {
    return handleOptions(corsHeaders)
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
    const body = await req.json()
    const { email, name, role, permissions, tenant_id, invited_by, locale, valid_from, valid_until } = body

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
    const { data: existingTenantUser, error } = await supabase
      .from("tenant_users")
      .select("id, status, auth_id")
      .eq("tenant_id", tenant_id)
      .eq("email", email)
      .maybeSingle()
    if (error) { console.error('create-user:', error); }

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

        // Send invitation email via Resend API (unified email system)
        // Generate magic link token without sending Supabase's default email
        const appUrl = Deno.env.get("APP_URL") || "https://projet-compta.zdouce-zz.workers.dev"
        const redirectTo = `${appUrl}/accept-invitation?tenant=${tenant_id}`

        const { data: linkData, error: linkError } = await supabase.auth.admin.generateLink({
          type: "magiclink",
          email,
          options: { emailRedirectTo: redirectTo },
        })

        let emailSent = false
        if (linkError) {
          console.error("Failed to generate magic link for re-invitation:", linkError.message)
        } else if (linkData?.properties?.action_link) {
          // Fetch tenant name and inviter name for the email template
          const { data: tenantData, error } = await supabase
            .from("tenants")
            .select("name")
            .eq("id", tenant_id)
            .single()
          if (error) { console.error('create-user:', error); }
          const tenantName = tenantData?.name || tenant_id

          // Fetch inviter name
          let inviterName: string | undefined
          if (invited_by) {
            const { data: inviterData, error: inviterErr } = await supabase
              .from("tenant_users")
              .select("name")
              .eq("auth_id", invited_by)
              .eq("tenant_id", tenant_id)
              .maybeSingle()
            if (inviterErr) { console.error('create-user:', inviterErr); }
            inviterName = inviterData?.name || undefined
          }

          // Build modules list from module_roles
          const moduleRoles = body?.module_roles || {}
          const moduleNames = Object.keys(moduleRoles)
          const modules = moduleNames.length > 0 ? moduleNames.join(", ") : undefined

          const template = buildInvitationEmail({
            email,
            name,
            tenantName,
            locale: locale || "en",
            magicLinkUrl: linkData.properties.action_link,
            isReinvitation: true,
            inviterName,
            role: role || undefined,
            modules,
          })

          const emailResult = await sendEmailViaResend({
            to: email,
            subject: template.subject,
            html: template.html,
          })
          emailSent = emailResult.success

          // Log to email queue
          if (emailResult.success) {
            try {
              await supabase.from("notification_email_queue").insert({
                tenant_id,
                recipient_email: email,
                recipient_name: name,
                notification_type: "invitation_pending",
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
            email,
            existing_user: true,
            reactivated: true,
            email_sent: emailSent,
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

    // 5. Send invitation email via Resend API (unified email system)
    // Generate magic link token without sending Supabase's default email
    const appUrl = Deno.env.get("APP_URL") || "https://projet-compta.zdouce-zz.workers.dev"
    const redirectTo = `${appUrl}/accept-invitation?tenant=${tenant_id}`

    const { data: linkData, error: linkError } = await supabase.auth.admin.generateLink({
      type: "magiclink",
      email,
      options: { emailRedirectTo: redirectTo },
    })

    let emailSent = false
    if (linkError) {
      console.error("Failed to generate magic link:", linkError.message)
    } else if (linkData?.properties?.action_link) {
      // Fetch tenant name and inviter name for the email template
      const { data: tenantData, error } = await supabase
        .from("tenants")
        .select("name")
        .eq("id", tenant_id)
        .single()
      if (error) { console.error('create-user:', error); }
      const tenantName = tenantData?.name || tenant_id

      // Fetch inviter name
      let inviterName: string | undefined
      if (invited_by) {
        const { data: inviterData, error: inviterErr } = await supabase
          .from("tenant_users")
          .select("name")
          .eq("auth_id", invited_by)
          .eq("tenant_id", tenant_id)
          .maybeSingle()
        if (inviterErr) { console.error('create-user:', inviterErr); }
        inviterName = inviterData?.name || undefined
      }

      // Build modules list from module_roles
      const moduleRoles = body?.module_roles || {}
      const moduleNames = Object.keys(moduleRoles)
      const modules = moduleNames.length > 0 ? moduleNames.join(", ") : undefined

      const template = buildInvitationEmail({
        email,
        name,
        tenantName,
        locale: locale || "en",
        magicLinkUrl: linkData.properties.action_link,
        inviterName,
        role: role || undefined,
        modules,
      })

      const emailResult = await sendEmailViaResend({
        to: email,
        subject: template.subject,
        html: template.html,
      })
      emailSent = emailResult.success

      // Log to email queue
      if (emailResult.success) {
        try {
          await supabase.from("notification_email_queue").insert({
            tenant_id,
            recipient_email: email,
            recipient_name: name,
            notification_type: "invitation_pending",
            subject: template.subject,
            status: "sent",
            resend_id: emailResult.id || null,
            sent_at: new Date().toISOString(),
          })
        } catch { /* queue logging failure is non-blocking */ }
      }
    }

    const message = existingUser
      ? "Utilisateur existant ajouté à cette entreprise. Email d'invitation envoyé."
      : "Utilisateur créé. Email d'invitation envoyé."

    return new Response(
      JSON.stringify({
        success: true,
        email,
        existing_user: existingUser,
        email_sent: emailSent,
        message,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    )
  } catch (err) {
    console.error("create-user error:", err)
    return new Response(
      JSON.stringify({ error: "Erreur interne du serveur", details: String(err) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    )
  }
})
