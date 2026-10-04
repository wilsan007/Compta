// @ts-nocheck — Deno Edge Function
// verify-iban — Vérification IBAN (format + clé de contrôle)
// Inspiré de : Pennylane, Stripe, GoCardless
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
    const { iban } = body

    if (!iban) {
      return new Response(JSON.stringify({ error: "iban requis" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // Nettoyer l'IBAN
    const cleanIban = iban.replace(/\s/g, "").toUpperCase()

    // Validation format de base
    if (!/^[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}$/.test(cleanIban)) {
      return new Response(JSON.stringify({ valid: false, error: "Format IBAN invalide" }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // Extraction du code pays
    const countryCode = cleanIban.substring(0, 2)
    const checkDigits = cleanIban.substring(2, 4)
    const bban = cleanIban.substring(4)

    // Longueurs IBAN par pays (principaux)
    const ibanLengths: Record<string, number> = {
      FR: 27, DE: 22, ES: 24, IT: 27, GB: 22, BE: 16, NL: 18, PT: 25,
      AT: 20, CH: 21, LU: 20, IE: 22, PL: 28, SE: 24, DK: 18, FI: 18,
      NO: 15, CZ: 24, SK: 24, HU: 28, RO: 24, BG: 22, HR: 21, SI: 19,
      EE: 20, LV: 21, LT: 20, MT: 31, CY: 28, GR: 27,
    }

    const expectedLength = ibanLengths[countryCode]
    if (expectedLength && cleanIban.length !== expectedLength) {
      return new Response(JSON.stringify({
        valid: false,
        error: `Longueur IBAN invalide pour ${countryCode}. Attendu: ${expectedLength}, Reçu: ${cleanIban.length}`,
      }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // Vérification de la clé de contrôle (algorithme ISO 13616)
    // 1. Déplacer les 4 premiers caractères à la fin
    const rearranged = bban + cleanIban.substring(0, 4)

    // 2. Convertir les lettres en nombres (A=10, B=11, ..., Z=35)
    let numericString = ""
    for (const char of rearranged) {
      if (/[A-Z]/.test(char)) {
        numericString += (char.charCodeAt(0) - 55).toString()
      } else {
        numericString += char
      }
    }

    // 3. Calculer modulo 97 (doit être 1)
    // Utiliser BigInt pour gérer les grands nombres
    let remainder = BigInt(0)
    for (let i = 0; i < numericString.length; i++) {
      remainder = (remainder * BigInt(10) + BigInt(numericString[i])) % BigInt(97)
    }

    const isValid = remainder === BigInt(1)

    // Extraction du code banque (France: 5 premiers chiffres du BBAN)
    let bankCode = ""
    let branchCode = ""
    if (countryCode === "FR" && bban.length >= 5) {
      bankCode = bban.substring(0, 5)
      branchCode = bban.substring(5, 10)
    }

    return new Response(JSON.stringify({
      valid: isValid,
      iban: cleanIban,
      country: countryCode,
      check_digits: checkDigits,
      bban: bban,
      bank_code: bankCode || null,
      branch_code: branchCode || null,
      length: cleanIban.length,
      expected_length: expectedLength || null,
      error: isValid ? null : "Clé de contrôle IBAN invalide (mod 97)",
    }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })

  } catch (err) {
    console.error("verify-iban error:", err)
    return new Response(JSON.stringify({ error: "Erreur interne" }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } })
  }
})
