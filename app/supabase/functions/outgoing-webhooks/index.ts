// @ts-nocheck — Deno Edge Function
// outgoing-webhooks — Envoie des webhooks sortants vers URLs enregistrées
// ASY-01 : File d'attente persistée en PostgreSQL (plus de mémoire volatile)
//
// Flow :
//   1. POST /outgoing-webhooks → insère dans webhook_delivery_queue
//   2. pg_cron ou retry manuel → POST /outgoing-webhooks?process=1
//   3. La fonction traite les entries pending/retry de la queue
//
// Événements supportés :
//   invoice.created, invoice.paid, invoice.overdue
//   customer.created, customer.updated
//   supplier.created, supplier.updated
//   journal_entry.posted
//   payslip.created, payslip.validated
//   vat_return.submitted
//   dsn.transmitted
//   payment.received
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const MAX_RETRIES = 3
const RETRY_DELAYS_MS = [1000, 5000, 30000]  // 1s, 5s, 30s

// LOT5-05 : Validation SSRF conforme à la spec
// - HTTPS uniquement
// - Bloque localhost, .local, .internal
// - Bloque plages IP privées (127.x, 10.x, 192.168.x, 169.254.x, 0.x, 172.16-31.x)
// - Bloque IPv6 loopback/ULA/link-local
function isAllowedWebhookUrl(raw: string): boolean {
  let u: URL
  try { u = new URL(raw) } catch (e) { console.error('isAllowedWebhookUrl: invalid URL:', e); return false }
  if (u.protocol !== 'https:') return false
  const h = u.hostname.toLowerCase().replace(/^\[|\]$/g, '')
  if (h === 'localhost' || h.endsWith('.local') || h.endsWith('.internal')) return false
  if (/^(127\.|10\.|192\.168\.|169\.254\.|0\.)/.test(h)) return false
  if (/^172\.(1[6-9]|2\d|3[01])\./.test(h)) return false
  if (h === '::1' || h.startsWith('fd') || h.startsWith('fe80:')) return false
  return true
}

function generateSignature(payload: string, secret: string): Promise<string> {
  if (!secret) return Promise.resolve("sha256=none")
  const key = new TextEncoder().encode(secret)
  const msg = new TextEncoder().encode(payload)
  return crypto.subtle.importKey("raw", key, { name: "HMAC", hash: "SHA-256" }, false, ["sign"])
    .then(cryptoKey => crypto.subtle.sign("HMAC", cryptoKey, msg))
    .then(sig => "sha256=" + Array.from(new Uint8Array(sig)).map(b => b.toString(16).padStart(2, "0")).join(""))
    .catch(() => "sha256=error")
}

async function deliverWebhook(url: string, event: string, payload: any, tenantId: string, secret: string): Promise<{ ok: boolean; status: number; response_body: string }> {
  try {
    const body = JSON.stringify({
      event,
      tenant_id: tenantId,
      timestamp: new Date().toISOString(),
      data: payload,
    })

    const signature = await generateSignature(body, secret)

    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Webhook-Event": event,
        "X-Webhook-Signature": signature,
        "X-Webhook-Timestamp": Math.floor(Date.now() / 1000).toString(),
        "User-Agent": "Onusuite-Webhook/1.0",
      },
      body,
    })

    const response_body = await response.text().catch(() => "")
    return { ok: response.ok, status: response.status, response_body: response_body.slice(0, 500) }
  } catch (err) {
    return { ok: false, status: 0, response_body: String(err).slice(0, 500) }
  }
}

// ASY-01 : Traiter la queue depuis PostgreSQL
async function processQueue(supabase: any) {
  // Récupérer les entries pending/retry qui sont prêtes à être traitées
  const { data: pending, error } = await supabase
    .from("webhook_delivery_queue")
    .select("id, url, event, payload, tenant_id, secret, attempts, next_retry_at")
    .in("status", ["pending", "retry"])
    .or(`next_retry_at.is.null,next_retry_at.lte.${new Date().toISOString()}`)
    .order("created_at", { ascending: true })
    .limit(50)

  if (error) { console.error("outgoing-webhooks fetch pending:", error); return 0 }
  if (!pending || pending.length === 0) return 0

  let processed = 0
  for (const item of pending) {
    // LOT5-05 : Vérifier SSRF avant l'envoi
    if (!isAllowedWebhookUrl(item.url)) {
      await supabase.from("webhook_delivery_queue").update({
        status: "blocked",
        last_error: "URL bloquée (protection SSRF)",
        updated_at: new Date().toISOString(),
      }).eq("id", item.id)
      continue
    }

    const result = await deliverWebhook(item.url, item.event, item.payload, item.tenant_id, item.secret)

    if (result.ok) {
      // Succès → marquer comme delivered
      await supabase.from("webhook_delivery_queue").update({
        status: "delivered",
        http_status: result.status,
        response_body: result.response_body,
        delivered_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      }).eq("id", item.id)

      // Logger dans webhook_delivery_logs
      await supabase.from("webhook_delivery_logs").insert({
        tenant_id: item.tenant_id,
        url: item.url,
        event: item.event,
        status: "delivered",
        attempt: item.attempts + 1,
        http_status: result.status,
      })
    } else {
      const newAttempts = item.attempts + 1
      if (newAttempts < MAX_RETRIES) {
        // Retry → programmer le prochain essai
        const retryDelay = RETRY_DELAYS_MS[newAttempts - 1] || 30000
        const nextRetry = new Date(Date.now() + retryDelay).toISOString()
        await supabase.from("webhook_delivery_queue").update({
          attempts: newAttempts,
          status: "retry",
          next_retry_at: nextRetry,
          last_error: result.response_body,
          http_status: result.status,
          updated_at: new Date().toISOString(),
        }).eq("id", item.id)

        await supabase.from("webhook_delivery_logs").insert({
          tenant_id: item.tenant_id,
          url: item.url,
          event: item.event,
          status: "retry",
          attempt: newAttempts,
          http_status: result.status,
        })
      } else {
        // Échec définitif
        await supabase.from("webhook_delivery_queue").update({
          status: "failed",
          attempts: newAttempts,
          last_error: result.response_body,
          http_status: result.status,
          updated_at: new Date().toISOString(),
        }).eq("id", item.id)

        await supabase.from("webhook_delivery_logs").insert({
          tenant_id: item.tenant_id,
          url: item.url,
          event: item.event,
          status: "failed",
          attempt: newAttempts,
          http_status: result.status,
        })
      }
    }
    processed++
  }
  return processed
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405, headers: { "Content-Type": "application/json" }
    })
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    const supabase = createClient(supabaseUrl, serviceRoleKey)

    const url = new URL(req.url)
    const isProcessMode = url.searchParams.get("process") === "1"

    // ASY-01 : Mode process — traiter la queue (appelé par pg_cron)
    if (isProcessMode) {
      const processed = await processQueue(supabase)
      return new Response(JSON.stringify({
        success: true,
        processed,
        processed_at: new Date().toISOString(),
      }), {
        status: 200, headers: { "Content-Type": "application/json" }
      })
    }

    // Mode normal — recevoir un événement et l'insérer dans la queue
    const body = await req.json()
    const { event, _entity_type, _entity_id, tenant_id, payload } = body

    if (!event || !tenant_id) {
      return new Response(JSON.stringify({ error: "event et tenant_id requis" }), {
        status: 400, headers: { "Content-Type": "application/json" }
      })
    }

    // Récupérer les webhooks enregistrés pour ce tenant et cet événement
    const { data: webhooks, error } = await supabase
      .from("webhook_endpoints")
      .select("id, url, secret, active_events")
      .eq("tenant_id", tenant_id)
      .eq("active", true)

    if (error || !webhooks) {
      return new Response(JSON.stringify({ error: "Erreur récupération webhooks" }), {
        status: 500, headers: { "Content-Type": "application/json" }
      })
    }

    let queued = 0
    for (const webhook of webhooks) {
      const activeEvents = webhook.active_events || []
      if (activeEvents.length > 0 && !activeEvents.includes(event) && !activeEvents.includes("*")) {
        continue
      }

      // ASY-01 : Insérer dans la queue PostgreSQL (persistant)
      const { error: insertError } = await supabase.from("webhook_delivery_queue").insert({
        tenant_id,
        endpoint_id: webhook.id,
        url: webhook.url,
        event,
        payload,
        secret: webhook.secret || "",
        status: "pending",
        attempts: 0,
      })

      if (!insertError) queued++
    }

    // ASY-01 : Traiter immédiatement les entries pending (best-effort)
    // Les retries seront gérés par pg_cron qui appelle ?process=1
    if (queued > 0) {
      processQueue(supabase).catch(err => console.error("processQueue error:", err))
    }

    return new Response(JSON.stringify({
      success: true,
      event,
      queued,
      processed_at: new Date().toISOString(),
    }), {
      status: 200, headers: { "Content-Type": "application/json" }
    })

  } catch (err) {
    console.error("outgoing-webhooks error:", err)
    return new Response(JSON.stringify({ error: "Erreur interne" }), {
      status: 500, headers: { "Content-Type": "application/json" }
    })
  }
})
