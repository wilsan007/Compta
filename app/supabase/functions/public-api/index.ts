// @ts-nocheck — Deno Edge Function
// public-api — API publique REST pour intégrations tierces
// Inspiré de : Stripe API, Pennylane API, QuickBooks API, Xero API
//
// Authentification : API Key (header X-API-Key)
// Rate limiting : 100 req/min par clé
// Format : JSON
//
// Endpoints :
//   GET  /v1/invoices          — Liste des factures
//   GET  /v1/invoices/:id      — Détail d'une facture
//   POST /v1/invoices          — Créer une facture
//   GET  /v1/customers         — Liste des clients
//   GET  /v1/customers/:id     — Détail d'un client
//   GET  /v1/suppliers         — Liste des fournisseurs
//   GET  /v1/products          — Liste des produits
//   GET  /v1/journal-entries   — Liste des écritures
//   GET  /v1/vat-returns       — Déclarations TVA
//   GET  /v1/pay-slips         — Bulletins de paie
//   GET  /v1/balance-sheet     — Bilan
//   GET  /v1/profit-loss       — Compte de résultat
//   GET  /v1/trial-balance     — Balance générale
//   GET  /v1/health            — Statut de l'API
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const RATE_LIMIT_WINDOW = 60_000  // 1 minute
const RATE_LIMIT_MAX = 100        // 100 requests per minute

// SEC-01 : Hash SHA-256 des clés API avant recherche en base
async function sha256(input: string): Promise<string> {
  const data = new TextEncoder().encode(input)
  const hashBuffer = await crypto.subtle.digest("SHA-256", data)
  return Array.from(new Uint8Array(hashBuffer))
    .map(b => b.toString(16).padStart(2, "0"))
    .join("")
}

// Rate limit store (in-memory, per instance)
const rateLimitMap = new Map<string, { count: number; resetAt: number }>()

function checkRate(apiKey: string): boolean {
  const now = Date.now()
  const entry = rateLimitMap.get(apiKey)
  if (!entry || now > entry.resetAt) {
    rateLimitMap.set(apiKey, { count: 1, resetAt: now + RATE_LIMIT_WINDOW })
    return true
  }
  if (entry.count >= RATE_LIMIT_MAX) return false
  entry.count++
  return true
}

function json(data: any, status = 200, rateLimitRemaining?: number) {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, X-API-Key, Idempotency-Key",
    "X-RateLimit-Limit": RATE_LIMIT_MAX.toString(),
    "X-RateLimit-Remaining": (rateLimitRemaining ?? 99).toString(),
  }
  return new Response(JSON.stringify(data), { status, headers })
}

// API-01 : Format d'erreur uniforme
function errorResponse(code: string, message: string, status: number, details?: any) {
  return json({ error: { code, message, details } }, status)
}

// API-01 : Journal des appels
async function logApiCall(
  authClient: any,
  apiKeyId: string,
  tenantId: string,
  method: string,
  path: string,
  status: number,
  idempotencyKey?: string
) {
  try {
    await authClient.from("api_call_logs").insert({
      api_key_id: apiKeyId,
      tenant_id: tenantId,
      method,
      path,
      status,
      idempotency_key: idempotencyKey,
      called_at: new Date().toISOString(),
    })
  } catch (err) {
    console.error("catch:", err)
    // Non bloquant
  }
}

// API-01 : Idempotence
async function checkIdempotency(
  authClient: any,
  key: string,
  tenantId: string
): Promise<any | null> {
  const { data } = await authClient
    .from("idempotency_records")
    .select("response, status")
    .eq("idempotency_key", key)
    .eq("tenant_id", tenantId)
    .single()
  return data
}

async function storeIdempotency(
  authClient: any,
  key: string,
  tenantId: string,
  response: any,
  status: number
) {
  await authClient.from("idempotency_records").insert({
    idempotency_key: key,
    tenant_id: tenantId,
    response,
    status,
    expires_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
  })
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, X-API-Key",
      },
    })
  }

  try {
    // Authentification par API Key
    const apiKey = req.headers.get("X-API-Key")
    if (!apiKey) {
      return json({ error: "X-API-Key requis", docs: "https://docs.onusuite.com/api" }, 401)
    }

    // Rate limiting
    if (!checkRate(apiKey)) {
      return json({ error: "Rate limit exceeded", limit: RATE_LIMIT_MAX, window: "60s" }, 429)
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!

    // Vérifier la clé API en base (SEC-01 : hash SHA-256, jamais en clair)
    const hashedKey = await sha256(apiKey)
    const authClient = createClient(supabaseUrl, serviceRoleKey)
    const { data: keyData, error: keyErr } = await authClient
      .from("api_keys")
      .select("id, tenant_id, active, permissions")
      .eq("key_hash", hashedKey)
      .eq("active", true)
      .single()

    if (keyErr || !keyData) {
      return json({ error: "Clé API invalide" }, 401)
    }

    // Créer un client avec le tenant de la clé API
    const tenantId = keyData.tenant_id
    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      global: { headers: { "x-tenant-id": tenantId } }
    })

    // Router la requête
    const url = new URL(req.url)
    const path = url.pathname.replace(/^\/functions\/v1\/public-api/, "")
    const segments = path.split("/").filter(Boolean)
    const method = req.method

    // GET /v1/health
    if (segments[0] === "health" || path === "/health") {
      return json({ status: "ok", version: "v1", tenant: tenantId, timestamp: new Date().toISOString() })
    }

    // GET /v1/invoices
    if (segments[0] === "invoices" && method === "GET") {
      const page = parseInt(url.searchParams.get("page") || "1")
      const limit = Math.min(parseInt(url.searchParams.get("limit") || "50"), 100)
      const status = url.searchParams.get("status")

      let query = supabase.from("invoices").select("*").eq("tenant_id", tenantId).range((page - 1) * limit, page * limit - 1)
      if (status) query = query.eq("status", status)

      const { data, error } = await query
      if (error) return json({ error: error.message }, 400)
      return json({ data, page, limit })
    }

    // GET /v1/invoices/:id
    if (segments[0] === "invoices" && segments[1] && method === "GET") {
      const { data, error } = await supabase
        .from("invoices")
        .select("*, invoice_lines(*)")
        .eq("id", segments[1])
        .eq("tenant_id", tenantId)
        .single()
      if (error) return json({ error: error.message }, 404)
      return json({ data })
    }

    // POST /v1/invoices
    if (segments[0] === "invoices" && method === "POST") {
      // API-01 : Idempotence
      const idempotencyKey = req.headers.get("Idempotency-Key")
      if (idempotencyKey) {
        const existing = await checkIdempotency(authClient, idempotencyKey, tenantId)
        if (existing) {
          await logApiCall(authClient, keyData.id, tenantId, method, path, existing.status, idempotencyKey)
          return json(existing.response, existing.status)
        }
      }

      const body = await req.json()
      // R-12 : une facture sans ligne n'est ni validable ni approuvable (190).
      // L'API insérait auparavant l'en-tête seul : tout ce qu'une intégration
      // créait était une pièce inutilisable, découvert seulement en essayant de
      // la valider dans l'interface. Le refus est donc explicite, à la porte.
      const { lines, ...invoice } = body || {}
      if (!Array.isArray(lines) || lines.length === 0) {
        await logApiCall(authClient, keyData.id, tenantId, method, path, 400, idempotencyKey || undefined)
        return errorResponse(
          "VALIDATION_ERROR",
          "Au moins une ligne est requise (champ « lines ») : une facture sans ligne n'est ni validable ni approuvable",
          400
        )
      }

      // RPC composée : la société est passée explicitement (l'API s'authentifie
      // par clé, service_role, donc current_tenant_id() y vaut NULL), au moins une
      // ligne est exigée côté serveur aussi, et les totaux sont recalculés depuis
      // les lignes — l'appelant ne peut pas annoncer un total qui ne correspond
      // pas à ce qu'il envoie.
      const { data: created, error } = await supabase.rpc("create_invoice_service", {
        p_tenant: tenantId,
        p_invoice: invoice,
        p_lines: lines,
      })
      if (error || !created?.success) {
        const message = error?.message || created?.error || "Création impossible"
        await logApiCall(authClient, keyData.id, tenantId, method, path, 400, idempotencyKey || undefined)
        return errorResponse("VALIDATION_ERROR", message, 400)
      }

      const { data, error: readErr } = await supabase
        .from("invoices")
        .select("*, invoice_lines(*)")
        .eq("id", created.invoice_id)
        .eq("tenant_id", tenantId)
        .single()
      if (readErr) {
        await logApiCall(authClient, keyData.id, tenantId, method, path, 400, idempotencyKey || undefined)
        return errorResponse("VALIDATION_ERROR", readErr.message, 400)
      }

      if (idempotencyKey) {
        await storeIdempotency(authClient, idempotencyKey, tenantId, { data }, 201)
      }
      await logApiCall(authClient, keyData.id, tenantId, method, path, 201, idempotencyKey || undefined)
      return json({ data }, 201)
    }

    // GET /v1/customers
    if (segments[0] === "customers" && method === "GET") {
      const page = parseInt(url.searchParams.get("page") || "1")
      const limit = Math.min(parseInt(url.searchParams.get("limit") || "50"), 100)
      const { data, error } = await supabase
        .from("customers")
        .select("*")
        .eq("tenant_id", tenantId)
        .range((page - 1) * limit, page * limit - 1)
      if (error) return json({ error: error.message }, 400)
      return json({ data, page, limit })
    }

    // GET /v1/customers/:id
    if (segments[0] === "customers" && segments[1] && method === "GET") {
      const { data, error } = await supabase
        .from("customers")
        .select("*")
        .eq("id", segments[1])
        .eq("tenant_id", tenantId)
        .single()
      if (error) return json({ error: error.message }, 404)
      return json({ data })
    }

    // GET /v1/suppliers
    if (segments[0] === "suppliers" && method === "GET") {
      const page = parseInt(url.searchParams.get("page") || "1")
      const limit = Math.min(parseInt(url.searchParams.get("limit") || "50"), 100)
      const { data, error } = await supabase
        .from("suppliers")
        .select("*")
        .eq("tenant_id", tenantId)
        .range((page - 1) * limit, page * limit - 1)
      if (error) return json({ error: error.message }, 400)
      return json({ data, page, limit })
    }

    // GET /v1/products
    if (segments[0] === "products" && method === "GET") {
      const page = parseInt(url.searchParams.get("page") || "1")
      const limit = Math.min(parseInt(url.searchParams.get("limit") || "50"), 100)
      const { data, error } = await supabase
        .from("products")
        .select("*")
        .eq("tenant_id", tenantId)
        .range((page - 1) * limit, page * limit - 1)
      if (error) return json({ error: error.message }, 400)
      return json({ data, page, limit })
    }

    // GET /v1/journal-entries
    if (segments[0] === "journal-entries" && method === "GET") {
      const page = parseInt(url.searchParams.get("page") || "1")
      const limit = Math.min(parseInt(url.searchParams.get("limit") || "50"), 100)
      const { data, error } = await supabase
        .from("journal_entries")
        .select("*, journal_lines(*)")
        .eq("tenant_id", tenantId)
        .range((page - 1) * limit, page * limit - 1)
      if (error) return json({ error: error.message }, 400)
      return json({ data, page, limit })
    }

    // GET /v1/vat-returns
    if (segments[0] === "vat-returns" && method === "GET") {
      const { data, error } = await supabase.from("vat_returns").select("*").eq("tenant_id", tenantId).limit(50)
      if (error) return json({ error: error.message }, 400)
      return json({ data })
    }

    // GET /v1/pay-slips
    if (segments[0] === "pay-slips" && method === "GET") {
      const { data, error } = await supabase.from("pay_slips").select("*").eq("tenant_id", tenantId).limit(50)
      if (error) return json({ error: error.message }, 400)
      return json({ data })
    }

    // GET /v1/balance-sheet?fiscal_year_id=...
    if (segments[0] === "balance-sheet" && method === "GET") {
      const fyId = url.searchParams.get("fiscal_year_id")
      if (!fyId) return json({ error: "fiscal_year_id requis" }, 400)
      const { data, error } = await supabase.rpc("generate_balance_sheet", { p_fiscal_year_id: fyId })
      if (error) return json({ error: error.message }, 400)
      return json({ data })
    }

    // GET /v1/profit-loss?fiscal_year_id=...
    if (segments[0] === "profit-loss" && method === "GET") {
      const fyId = url.searchParams.get("fiscal_year_id")
      if (!fyId) return json({ error: "fiscal_year_id requis" }, 400)
      const { data, error } = await supabase.rpc("generate_profit_loss", { p_fiscal_year_id: fyId })
      if (error) return json({ error: error.message }, 400)
      return json({ data })
    }

    // GET /v1/trial-balance?from=...&to=...
    if (segments[0] === "trial-balance" && method === "GET") {
      const from = url.searchParams.get("from")
      const to = url.searchParams.get("to")
      const { data, error } = await supabase.rpc("generate_trial_balance", {
        p_from_date: from, p_to_date: to
      })
      if (error) return json({ error: error.message }, 400)
      return json({ data })
    }

    // 404
    return json({ error: "Endpoint non trouvé", path, method, docs: "https://docs.onusuite.com/api" }, 404)

  } catch (err) {
    console.error("public-api error:", err)
    return json({ error: "Erreur interne" }, 500)
  }
})
