// @ts-nocheck — Deno Edge Function
// verify-siret — Vérification SIRET via API SIRENE (INSEE)
// Inspiré de : Pennylane, Sage (vérification automatique des tiers)
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
    const { siret } = body

    if (!siret) {
      return new Response(JSON.stringify({ error: "siret requis" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // Validation format SIRET (14 chiffres)
    const cleanSiret = siret.replace(/\s/g, "")
    if (!/^\d{14}$/.test(cleanSiret)) {
      return new Response(JSON.stringify({ valid: false, error: "SIRET doit contenir 14 chiffres" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // Algorithme de Luhn (clé de contrôle SIRET)
    let sum = 0
    for (let i = 0; i < 14; i++) {
      let digit = parseInt(cleanSiret[i])
      if (i % 2 === 0) {
        digit *= 2
        if (digit > 9) digit -= 9
      }
      sum += digit
    }

    if (sum % 10 !== 0) {
      return new Response(JSON.stringify({ valid: false, error: "SIRET invalide (clé de contrôle incorrecte)" }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // Extraire SIREN (9 premiers chiffres)
    const siren = cleanSiret.substring(0, 9)
    const nic = cleanSiret.substring(9)

    // Appel API SIRENE (INSEE)
    const sireneToken = Deno.env.get("SIRENE_API_TOKEN")
    if (sireneToken) {
      const sireneResponse = await fetch(
        `https://api.insee.fr/entreprises/sirene/V3/siret/${cleanSiret}`,
        {
          headers: {
            "Authorization": `Bearer ${sireneToken}`,
            "Accept": "application/json",
          },
        }
      )

      if (sireneResponse.ok) {
        const sireneData = await sireneResponse.json()
        const etablissement = sireneData.etablissement

        return new Response(JSON.stringify({
          valid: true,
          siret: cleanSiret,
          siren: siren,
          nic: nic,
          company_name: etablissement.uniteLegale?.denominationUniteLegale || "",
          legal_form: etablissement.uniteLegale?.categorieJuridiqueUniteLegale || "",
          address: {
            street: etablissement.adresseEtablissement?.numeroVoieEtablissement + " " + etablissement.adresseEtablissement?.typeVoieEtablissement + " " + etablissement.adresseEtablissement?.libelleVoieEtablissement,
            city: etablissement.adresseEtablissement?.libelleCommuneEtablissement,
            postal_code: etablissement.adresseEtablissement?.codePostalEtablissement,
            country: "France",
          },
          activity: etablissement.uniteLegale?.activitePrincipaleUniteLegale || "",
          active: etablissement.uniteLegale?.etatAdministratifUniteLegale === "A",
          api_source: "INSEE SIRENE",
        }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
      }
    }

    // Fallback : validation format uniquement
    return new Response(JSON.stringify({
      valid: true,
      siret: cleanSiret,
      siren: siren,
      nic: nic,
      message: "SIRET valide (format). API SIRENE non configurée pour vérification complète.",
      api_source: "local_validation",
    }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })

  } catch (err) {
    console.error("verify-siret error:", err)
    return new Response(JSON.stringify({ error: "Erreur interne" }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } })
  }
})
