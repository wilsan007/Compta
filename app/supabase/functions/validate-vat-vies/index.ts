// @ts-nocheck — Deno Edge Function
// validate-vat-vies — Vérification numéro TVA intracommunautaire via VIES
// Inspiré de : Pennylane, Sage (validation B2B intra-EU)
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { getCorsHeaders, handleOptions } from "../_shared/cors.ts"

serve(async (req) => {
  const corsHeaders = getCorsHeaders(req)
  if (req.method === "OPTIONS") return handleOptions(corsHeaders)

  try {
    const authHeader = req.headers.get("Authorization") || ""
    const token = authHeader.replace("Bearer ", "")
    if (!token) return new Response(JSON.stringify({ error: "Token requis" }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } })

    const body = await req.json()
    const { vat_number, requester_vat } = body

    if (!vat_number) {
      return new Response(JSON.stringify({ error: "vat_number requis" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // Nettoyer le numéro TVA
    const cleanVat = vat_number.replace(/\s/g, "").toUpperCase()

    // Validation format de base (2 lettres + 2-12 caractères alphanumériques)
    if (!/^[A-Z]{2}[A-Z0-9]{2,12}$/.test(cleanVat)) {
      return new Response(JSON.stringify({ valid: false, error: "Format numéro TVA invalide" }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    const countryCode = cleanVat.substring(0, 2)
    const vatNumber = cleanVat.substring(2)

    // Appel au service VIES (European Commission)
    // VIES SOAP API
    const soapBody = `<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
  <soap:Body>
    <checkVat xmlns="urn:ec.europa.eu:taxud:vies:services:checkVat:types">
      <countryCode>${countryCode}</countryCode>
      <vatNumber>${vatNumber}</vatNumber>
      ${requester_vat ? `<requesterCountryCode>${requester_vat.substring(0, 2)}</requesterCountryCode><requesterVatNumber>${requester_vat.substring(2)}</requesterVatNumber>` : ''}
    </checkVat>
  </soap:Body>
</soap:Envelope>`

    try {
      const viesResponse = await fetch(
        "https://ec.europa.eu/taxation_customs/vies/services/checkVatService",
        {
          method: "POST",
          headers: {
            "Content-Type": "text/xml; charset=utf-8",
            "SOAPAction": "",
          },
          body: soapBody,
        }
      )

      const viesXml = await viesResponse.text()

      // Parser la réponse SOAP (simplifié)
      const isValid = viesXml.includes("<valid>true</valid>")
      const hasFault = viesXml.includes("<faultstring>")

      if (hasFault) {
        const faultMatch = viesXml.match(/<faultstring>(.*?)<\/faultstring>/)
        return new Response(JSON.stringify({
          valid: false,
          vat_number: cleanVat,
          error: faultMatch ? faultMatch[1] : "Erreur VIES",
          api_source: "VIES",
        }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
      }

      // Extraire les informations de l'entreprise
      const nameMatch = viesXml.match(/<name>(.*?)<\/name>/)
      const addressMatch = viesXml.match(/<address>(.*?)<\/address>/)

      return new Response(JSON.stringify({
        valid: isValid,
        vat_number: cleanVat,
        country: countryCode,
        company_name: nameMatch ? nameMatch[1].trim() : null,
        address: addressMatch ? addressMatch[1].trim() : null,
        api_source: "VIES",
        checked_at: new Date().toISOString(),
      }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })

    } catch {
      // VIES peut être indisponible — retourner validation format uniquement
      return new Response(JSON.stringify({
        valid: true,
        vat_number: cleanVat,
        country: countryCode,
        message: "VIES indisponible — validation format uniquement",
        api_source: "local_validation",
      }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

  } catch (err) {
    console.error("validate-vat-vies error:", err)
    return new Response(JSON.stringify({ error: "Erreur interne" }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } })
  }
})
