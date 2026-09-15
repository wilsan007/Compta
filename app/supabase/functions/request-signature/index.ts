// @ts-nocheck — Deno Edge Function
// request-signature — Demande de signature électronique (Universign / Yousign)
// Inspiré de : DocuSign, Yousign, Universign
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
    const { document_id, document_url, signers, provider = "yousign", tenant_id } = body

    if (!document_url || !signers || !Array.isArray(signers) || signers.length === 0) {
      return new Response(JSON.stringify({ error: "document_url et signers requis" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey)
    if (!(await isTenantMember(supabase, user.id, tenant_id))) return forbidden(corsHeaders)

    if (provider === "yousign") {
      const yousignKey = Deno.env.get("YOUSIGN_API_KEY")
      const yousignBase = Deno.env.get("YOUSIGN_API_URL") || "https://api-sandbox.yousign.app/v3"

      if (!yousignKey) {
        // LOT7-08 : sans accès configuré, refuser plutôt que simuler.
        // Une simulation enregistrait l'envoi comme effectué alors que rien n'était transmis.
        return new Response(JSON.stringify({
          success: false,
          code: "NOT_CONFIGURED",
          error: "Yousign non configuré : définissez YOUSIGN_API_KEY pour activer la transmission. Aucune donnée n'a été transmise.",
        }), { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } })
      }

      // Créer une procédure de signature Yousign
      const yousignResponse = await fetch(`${yousignBase}/signature_requests`, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${yousignKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          name: `Signature - ${new Date().toISOString()}`,
          documents: [{ url: document_url }],
          signers: signers.map((s: any) => ({
            info: {
              first_name: s.first_name,
              last_name: s.last_name,
              email: s.email,
              phone_number: s.phone,
            },
            signature_level: s.level || "electronic_signature",
          })),
        }),
      })

      const yousignData = await yousignResponse.json()
      if (!yousignResponse.ok) {
        return new Response(JSON.stringify({ error: "Erreur Yousign", details: yousignData }), { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } })
      }

      await supabase.from("electronic_signatures").insert({
        tenant_id: tenant_id || null,
        document_id: document_id || null,
        provider: "yousign",
        provider_signature_id: yousignData.id,
        status: "pending",
        signers: signers,
        initiated_at: new Date().toISOString(),
      })

      return new Response(JSON.stringify({
        success: true,
        provider: "yousign",
        signature_id: yousignData.id,
        status: "pending",
        signers: signers.length,
      }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    if (provider === "universign") {
      const universignKey = Deno.env.get("UNIVERSIGN_API_KEY")
      if (!universignKey) {
        return new Response(JSON.stringify({ success: false, code: "NOT_CONFIGURED", error: "Universign non configuré" }), { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } })
      }

      // LOT7-08 : l'intégration Universign n'est pas implémentée — ne pas répondre « succès »
      return new Response(JSON.stringify({ success: false, code: "NOT_IMPLEMENTED", error: "Signature Universign non disponible : utilisez Yousign." }), { status: 501, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    return new Response(JSON.stringify({ error: "Provider non reconnu" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } })

  } catch (err) {
    console.error("request-signature error:", err)
    return new Response(JSON.stringify({ error: "Erreur interne" }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } })
  }
})
