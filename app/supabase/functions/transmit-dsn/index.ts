// @ts-nocheck — Deno Edge Function
// transmit-dsn — Transmet la déclaration DSN à la net-entreprises / MSA
// Inspiré de : Silae, PayFit, Sage Paie
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { getCorsHeaders, handleOptions } from "../_shared/cors.ts"
import { forbidden, isTenantMember } from "../_shared/tenantAccess.ts"

serve(async (req) => {
  const corsHeaders = getCorsHeaders(req)
  if (req.method === "OPTIONS") return handleOptions(corsHeaders)

  try {
    const authHeader = req.headers.get("Authorization") || ""
    const token = authHeader.replace("Bearer ", "")
    if (!token) return new Response(JSON.stringify({ error: "Token requis" }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } })

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || serviceRoleKey

    const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: `Bearer ${token}` } } })
    const { data: { user }, error: userErr } = await userClient.auth.getUser()
    if (userErr || !user) return new Response(JSON.stringify({ error: "Non authentifié" }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } })

    const body = await req.json()
    const { dsn_id, xml_content, siret, nom_contact, email_contact, telephone_contact } = body

    if (!dsn_id) {
      return new Response(JSON.stringify({ error: "dsn_id requis" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey)

    // Récupérer la DSN : écran paie (dsn_declarations) ou déclarations sociales (social_declarations)
    let dsnTable = "dsn_declarations"
    let { data: dsn } = await supabase.from("dsn_declarations").select("*").eq("id", dsn_id).maybeSingle()
    if (!dsn) {
      dsnTable = "social_declarations"
      const res = await supabase.from("social_declarations").select("*").eq("id", dsn_id).maybeSingle()
      dsn = res.data
    }

    if (!dsn) {
      return new Response(JSON.stringify({ error: "DSN non trouvée" }), { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }
    if (!(await isTenantMember(supabase, user.id, dsn.tenant_id))) return forbidden(corsHeaders)

    // Récupérer les infos entreprise du tenant de la DSN
    const { data: company, error } = await supabase
      .from("company_settings")
      .select("*")
      .eq("tenant_id", dsn.tenant_id)
      .limit(1)
      .maybeSingle()
    if (error) { console.error('transmit-dsn:', error); }

    const dsnSiret = siret || company?.siret
    if (!dsnSiret) {
      return new Response(JSON.stringify({ error: "SIRET requis pour la transmission DSN" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // Vérifier si la transmission API est configurée
    const dsnApiToken = Deno.env.get("DSN_API_TOKEN")
    const dsnApiUrl = Deno.env.get("DSN_API_URL") || "https://api.net-entreprises.fr"

    if (!dsnApiToken) {
      // LOT7-08 : sans accès configuré, refuser plutôt que simuler.
      // Une simulation enregistrait la déclaration comme transmise alors que rien n'était envoyé.
      return new Response(JSON.stringify({
        success: false,
        code: "NOT_CONFIGURED",
        error: "API net-entreprises non configuré : définissez DSN_API_TOKEN pour activer la transmission. Aucune donnée n'a été transmise.",
      }), { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // Transmission réelle via API net-entreprises
    // Étape 1 : Obtenir un jeton d'authentification
    const authResponse = await fetch(`${dsnApiUrl}/api/comptes/v1/authentification`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        siret: dsnSiret,
        token: dsnApiToken,
      }),
    })

    if (!authResponse.ok) {
      return new Response(JSON.stringify({ error: "Échec authentification net-entreprises" }), { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    const authData = await authResponse.json()
    const bearerToken = authData.access_token

    // Étape 2 : Transmettre le fichier DSN
    const xmlPayload = xml_content || btoa(`DSN_${dsn.period}_${dsnSiret}`)  // Fallback

    const transmitResponse = await fetch(`${dsnApiUrl}/api/espace/v1/televerser`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${bearerToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        fichier: xmlPayload,
        type: "DSN",
        periode: dsn.period,
        nomContact: nom_contact || company?.contact_name,
        emailContact: email_contact || company?.email,
        telephoneContact: telephone_contact || company?.phone,
      }),
    })

    const transmitData = await transmitResponse.json()

    if (transmitResponse.ok) {
      // Colonnes communes aux deux tables de déclaration
      await supabase
        .from(dsnTable)
        .update({
          status: "transmitted",
          transmitted_at: new Date().toISOString(),
          response_code: transmitData.idDepot ? String(transmitData.idDepot) : null,
          response_message: transmitData.accuse ? JSON.stringify(transmitData.accuse).slice(0, 2000) : null,
        })
        .eq("id", dsn_id)
        .eq("tenant_id", dsn.tenant_id)
    }

    return new Response(JSON.stringify({
      success: transmitResponse.ok,
      dsn_id: dsn_id,
      transmission_id: transmitData.idDepot,
      status: transmitResponse.ok ? "transmitted" : "error",
      error: transmitResponse.ok ? null : transmitData.error,
    }), {
      status: transmitResponse.ok ? 200 : 502,
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    })

  } catch (err) {
    console.error("transmit-dsn error:", err)
    return new Response(JSON.stringify({ error: "Erreur interne" }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } })
  }
})
