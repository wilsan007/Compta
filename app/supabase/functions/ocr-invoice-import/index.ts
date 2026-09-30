// @ts-nocheck — Deno Edge Function
// ocr-invoice-import — OCR factures fournisseurs via OpenAI Vision
// Inspiré de : Pennylane, Sage, QuickBooks (scan de factures)
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { getCorsHeaders, handleOptions } from "../_shared/cors.ts"
import { forbidden, isTenantMember } from "../_shared/tenantAccess.ts"
import { ocrConsent, tenantFromRequest } from "../_shared/ocrConsent.ts"

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
    const openaiKey = Deno.env.get("OPENAI_API_KEY")

    const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: `Bearer ${token}` } } })
    const { data: { user }, error: userErr } = await userClient.auth.getUser()
    if (userErr || !user) return new Response(JSON.stringify({ error: "Non authentifié" }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } })

    const body = await req.json()
    const { file_url, file_base64, mime_type = "image/png", _document_type = "purchase_invoice" } = body
    const safeMime = ["image/png", "image/jpeg", "image/webp"].includes(mime_type) ? mime_type : "image/png"

    if (!file_url && !file_base64) {
      return new Response(JSON.stringify({ error: "file_url ou file_base64 requis" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // ─────────────────────────────────────────────────────────────
    // D-5 (migration 318) — LE CONSENTEMENT, AVANT TOUTE SORTIE DE DONNÉES.
    //
    // L'ordre n'est pas cosmétique : le contrôle doit passer AVANT l'appel au
    // prestataire, sinon la donnée est déjà partie. C'est aussi pourquoi la
    // société est lue sur l'en-tête `x-tenant-id` que l'application joint à
    // chaque requête, et non devinée.
    // ─────────────────────────────────────────────────────────────
    const supabase = createClient(supabaseUrl, serviceRoleKey)

    const tenantId = tenantFromRequest(req)
    if (!tenantId) {
      return new Response(JSON.stringify({
        error: "Société non précisée (en-tête x-tenant-id absent) : l'OCR ne peut pas savoir à qui appartient le document.",
        code: "TENANT_REQUIRED",
      }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    if (!(await isTenantMember(supabase, user.id, tenantId))) return forbidden(corsHeaders)

    const consentement = await ocrConsent(supabase, tenantId)
    if (!consentement.granted) {
      return new Response(JSON.stringify({
        error: "L'envoi à un prestataire d'OCR n'est pas autorisé pour cette société. Donnez votre consentement dans Paramètres → Société ; le document n'a pas été transmis.",
        code: "OCR_CONSENT_REQUIRED",
        motif: consentement.motif,
      }), { status: 409, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // Si pas de clé OpenAI, retourner une erreur
    if (!openaiKey) {
      return new Response(JSON.stringify({ error: "OPENAI_API_KEY non configuré" }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // Préparer l'image
    const imageUrl = file_base64 ? `data:${safeMime};base64,${file_base64}` : file_url

    // Appeler OpenAI GPT-4o pour l'OCR
    const openaiResponse = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${openaiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        messages: [
          {
            role: "system",
            content: "Tu es un assistant expert en extraction de données de factures. Extrais les informations de la facture et renvoie-les au format JSON avec ces champs: supplier_name, supplier_siret, supplier_vat, supplier_address, invoice_number, invoice_date, due_date, subtotal, vat_total, total, currency, items (array of {description, quantity, unit_price, vat_rate, total}). Réponds UNIQUEMENT avec le JSON, sans texte additionnel."
          },
          {
            role: "user",
            content: [
              { type: "text", text: "Extrais toutes les informations de cette facture." },
              { type: "image_url", image_url: { url: imageUrl } }
            ]
          }
        ],
        max_tokens: 2000,
        temperature: 0,
      }),
    })

    const ocrData = await openaiResponse.json()
    if (!openaiResponse.ok) {
      return new Response(JSON.stringify({ error: "Erreur OpenAI", details: ocrData }), { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // Parser le résultat
    let extractedData
    try {
      const content = ocrData.choices[0]?.message?.content || ""
      extractedData = JSON.parse(content)
    } catch {
      // Si le JSON n'est pas valide, retourner le texte brut
      return new Response(JSON.stringify({
        success: false,
        raw_text: ocrData.choices[0]?.message?.content,
        error: "Format JSON non reconnu"
      }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // Tenter de faire correspondre avec un fournisseur existant — de la SOCIÉTÉ
    // de l'appelant, celle que le consentement vient de nommer. (Avant D-5, la
    // recherche balayait TOUTES les sociétés de l'utilisateur : le document
    // n'était rattaché à aucune d'elles.)
    const tenantIds = [tenantId]
    if (extractedData.supplier_name) {
      const { data: supplier, error } = await supabase
        .from("suppliers")
        .select("id, name, siret, vat_number")
        .in("tenant_id", tenantIds)
        .ilike("name", `%${extractedData.supplier_name}%`)
        .limit(1)
        .single()
      if (error) { console.error('ocr-invoice-import:', error); }

      if (supplier) {
        extractedData.matched_supplier_id = supplier.id
        extractedData.matched_supplier_name = supplier.name
      }
    }

    return new Response(JSON.stringify({
      success: true,
      extracted_data: extractedData,
      confidence: "high",
      model: "gpt-4o-mini",
    }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })

  } catch (err) {
    console.error("ocr-invoice-import error:", err)
    return new Response(JSON.stringify({ error: "Erreur interne" }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } })
  }
})
