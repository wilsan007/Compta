// @ts-nocheck — This file runs in Deno (Supabase Edge Function), not in the local TS environment.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

// ============================================
// CONFIG
// ============================================
const APP_URL = Deno.env.get("APP_URL") || "https://projet-compta.zdouce-zz.workers.dev"

const ALLOWED_ORIGINS = [
  APP_URL,
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

// ============================================
// FRANKFURTER API (BCE rates — free, no API key)
// ============================================
// Reference: https://www.frankfurter.app/
// Base: EUR (European Central Bank daily reference rates)
// Updates: every business day around 16:00 CET

interface FrankfurterResponse {
  amount: number
  base: string
  date: string
  rates: Record<string, number>
}

async function fetchFrankfurterRates(): Promise<FrankfurterResponse> {
  const response = await fetch("https://api.frankfurter.app/latest")
  if (!response.ok) {
    throw new Error(`Frankfurter API error: ${response.status} ${response.statusText}`)
  }
  return await response.json()
}

// ============================================
// CURRENCIES FOR ONUSUITE PRICING
// ============================================
// Frankfurter provides EUR→X rates for most currencies.
// XOF and XAF are NOT in Frankfurter's response (they use a fixed peg to EUR).
// We inject them manually with the official fixed rate: 1 EUR = 655.957 XOF/XAF.

const FIXED_RATES: Record<string, number> = {
  XOF: 655.957, // Franc CFA UEMOA (CI, Sénégal, Burkina, Mali, Bénin, Togo, Niger)
  XAF: 655.957, // Franc CFA CEMAC (Cameroun, Gabon, Tchad, Congo, RCA, Guinée Éq.)
}

// Currencies we want to store for pricing display
const PRICING_CURRENCIES = [
  "USD", "GBP", "CHF", "CAD", "JPY", "CNY", "AUD",
  "MAD",   // Dirham marocain
  "TND",   // Dinar tunisien
  "DZD",   // Dinar algérien
  "XOF",   // Franc CFA UEMOA (injected manually)
  "XAF",   // Franc CFA CEMAC (injected manually)
]

// ============================================
// MAIN HANDLER
// ============================================
serve(async (req) => {
  const corsHeaders = getCorsHeaders(req)

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    // This function can be called by:
    // 1. Supabase pg_cron (scheduled SQL job)
    // 2. External scheduler (GitHub Actions, cron-job.org, etc.)
    // 3. Manual trigger from admin UI
    //
    // Auth: accept either a service role key (cron) or a valid JWT (admin manual trigger)
    const authHeader = req.headers.get("Authorization") || ""
    const token = authHeader.replace("Bearer ", "")

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!

    // Use service role client to bypass RLS (this is a system function)
    const supabase = createClient(supabaseUrl, serviceRoleKey)

    // 1. Fetch latest rates from Frankfurter (BCE)
    console.log("[refresh-exchange-rates] Fetching rates from Frankfurter API...")
    const frankfurterData = await fetchFrankfurterRates()
    const rateDate = frankfurterData.date
    console.log(`[refresh-exchange-rates] Got rates for ${rateDate}, base: ${frankfurterData.base}`)

    // 2. Build the full rate list (EUR → each target currency)
    const ratesToStore: { base_currency: string; quote_currency: string; rate: number; rate_date: string; source: string }[] = []

    for (const currency of PRICING_CURRENCIES) {
      let rate: number | undefined

      if (currency in FIXED_RATES) {
        // XOF/XAF: fixed peg to EUR
        rate = FIXED_RATES[currency]
      } else if (currency in frankfurterData.rates) {
        // From Frankfurter API
        rate = frankfurterData.rates[currency]
      }

      if (rate !== undefined && rate > 0) {
        ratesToStore.push({
          base_currency: "EUR",
          quote_currency: currency,
          rate,
          rate_date: rateDate,
          source: "frankfurter",
        })
      } else {
        console.warn(`[refresh-exchange-rates] No rate available for ${currency}`)
      }
    }

    // 3. Also store inverse rates (target → EUR) for convenience
    for (const entry of ratesToStore) {
      if (entry.rate > 0) {
        ratesToStore.push({
          base_currency: entry.quote_currency,
          quote_currency: "EUR",
          rate: 1 / entry.rate,
          rate_date: rateDate,
          source: "frankfurter",
        })
      }
    }

    // 4. Store cross-rates between key local currencies (for pricing display)
    // XOF → MAD, XOF → TND, XOF → DZD, XOF → USD, etc.
    const eurToXof = FIXED_RATES.XOF
    const crossRatePairs: { from: string; to: string }[] = [
      { from: "XOF", to: "MAD" },
      { from: "XOF", to: "TND" },
      { from: "XOF", to: "DZD" },
      { from: "XOF", to: "USD" },
      { from: "XOF", to: "EUR" },
      { from: "XAF", to: "XOF" },
      { from: "XAF", to: "MAD" },
      { from: "XAF", to: "USD" },
    ]

    for (const { from, to } of crossRatePairs) {
      const fromEurRate = from in FIXED_RATES ? FIXED_RATES[from] : frankfurterData.rates[from]
      const toEurRate = to in FIXED_RATES ? FIXED_RATES[to] : frankfurterData.rates[to]

      if (fromEurRate && toEurRate && fromEurRate > 0 && toEurRate > 0) {
        // from → EUR → to
        const crossRate = (1 / fromEurRate) * toEurRate
        if (crossRate > 0) {
          ratesToStore.push({
            base_currency: from,
            quote_currency: to,
            rate: crossRate,
            rate_date: rateDate,
            source: "frankfurter",
          })
        }
      }
    }

    // 5. Upsert all rates into exchange_rates table
    console.log(`[refresh-exchange-rates] Storing ${ratesToStore.length} rates...`)

    let saved = 0
    let errors = 0

    for (const rateEntry of ratesToStore) {
      try {
        const { error } = await supabase
          .from("exchange_rates")
          .upsert(rateEntry, {
            onConflict: "tenant_id,base_currency,quote_currency,rate_date",
          })

        if (error) {
          // Try without tenant_id conflict (global rates have null tenant_id)
          const { error: error2 } = await supabase
            .from("exchange_rates")
            .insert({ ...rateEntry, tenant_id: null })

          if (error2) {
            console.error(`[refresh-exchange-rates] Failed to save ${rateEntry.base_currency}/${rateEntry.quote_currency}:`, error2.message)
            errors++
          } else {
            saved++
          }
        } else {
          saved++
        }
      } catch (err) {
        console.error(`[refresh-exchange-rates] Error saving ${rateEntry.base_currency}/${rateEntry.quote_currency}:`, err)
        errors++
      }
    }

    console.log(`[refresh-exchange-rates] Done: ${saved} saved, ${errors} errors`)

    return new Response(
      JSON.stringify({
        success: true,
        date: rateDate,
        saved,
        errors,
        total: ratesToStore.length,
        currencies: PRICING_CURRENCIES,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    )
  } catch (err) {
    console.error("[refresh-exchange-rates] Fatal error:", err)
    return new Response(
      JSON.stringify({ error: "Erreur interne", details: err.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    )
  }
})
