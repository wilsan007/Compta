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

// LOT5-05 (durci) : Garde SSRF — MIROIR de src/lib/security/ssrfGuard.ts.
// Toute évolution de la logique doit être répercutée dans les deux fichiers + la
// fonction SQL is_allowed_webhook_url (migration 167).
//
// Deux niveaux :
//   1. isAllowedWebhookUrl(raw)  — synchrone : protocole, hôtes locaux, littéraux
//      IP privés y compris encodés (décimal/hex/octal, IPv6 IPv4-mapped).
//   2. assertPublicHost(host)    — async : résout le DNS et valide l'IP RÉELLE.
//      C'est le SEUL niveau qui bloque le DNS rebinding (domaine public → IP privée).
//   3. safeFetch(url)            — suit les redirections en re-validant CHAQUE saut.

function parseIpv4Part(part: string): number | null {
  if (part.length === 0) return null
  let n: number
  if (/^0x[0-9a-f]+$/i.test(part)) n = parseInt(part.slice(2), 16)
  else if (/^0[0-7]+$/.test(part)) n = parseInt(part, 8)
  else if (/^[0-9]+$/.test(part)) n = parseInt(part, 10)
  else return null
  return Number.isFinite(n) ? n : null
}

function parseIpv4Literal(host: string): string | null {
  if (host.length === 0) return null
  const rawParts = host.split('.')
  if (rawParts.length === 0 || rawParts.length > 4) return null
  const nums: number[] = []
  for (const part of rawParts) {
    const n = parseIpv4Part(part)
    if (n === null) return null
    nums.push(n)
  }
  const last = nums[nums.length - 1]
  const leading = nums.slice(0, -1)
  if (last >= Math.pow(256, 4 - leading.length)) return null
  for (const seg of leading) if (seg > 255) return null
  let value = last
  for (let i = 0; i < leading.length; i++) value += leading[i] * Math.pow(256, 3 - i)
  if (value < 0 || value > 0xffffffff) return null
  return [(value >>> 24) & 0xff, (value >>> 16) & 0xff, (value >>> 8) & 0xff, value & 0xff].join('.')
}

function isPrivateOrReservedIpv4(dotted: string): boolean {
  const p = dotted.split('.').map(Number)
  if (p.length !== 4 || p.some((x) => !Number.isInteger(x) || x < 0 || x > 255)) return true
  const [a, b] = p
  if (a === 0 || a === 10 || a === 127) return true
  if (a === 169 && b === 254) return true
  if (a === 172 && b >= 16 && b <= 31) return true
  if (a === 192 && b === 168) return true
  if (a === 100 && b >= 64 && b <= 127) return true
  if (a === 192 && b === 0) return true
  if (a >= 224) return true
  return false
}

function parseIpv6(host: string): Uint8Array | null {
  if (!host.includes(':')) return null
  let str = host
  const lastColon = str.lastIndexOf(':')
  const tail = str.slice(lastColon + 1)
  if (tail.includes('.')) {
    const v4 = parseIpv4Literal(tail)
    if (v4 === null) return null
    const o = v4.split('.').map(Number)
    str = str.slice(0, lastColon + 1) + ((o[0] << 8) | o[1]).toString(16) + ':' + ((o[2] << 8) | o[3]).toString(16)
  }
  const halves = str.split('::')
  if (halves.length > 2) return null
  const head = halves[0].length ? halves[0].split(':') : []
  const back = halves.length === 2 && halves[1].length ? halves[1].split(':') : []
  const groups: number[] = []
  const push = (g: string): boolean => {
    if (!/^[0-9a-f]{1,4}$/i.test(g)) return false
    groups.push(parseInt(g, 16)); return true
  }
  for (const g of head) if (!push(g)) return null
  if (halves.length === 2) {
    const fill = 8 - head.length - back.length
    if (fill < 0) return null
    for (let i = 0; i < fill; i++) groups.push(0)
    for (const g of back) if (!push(g)) return null
  }
  if (groups.length !== 8) return null
  const bytes = new Uint8Array(16)
  for (let i = 0; i < 8; i++) { bytes[i * 2] = (groups[i] >> 8) & 0xff; bytes[i * 2 + 1] = groups[i] & 0xff }
  return bytes
}

function isPrivateOrReservedIpv6(bytes: Uint8Array): boolean {
  const zeroTo15 = bytes.slice(0, 15).every((b) => b === 0)
  if (zeroTo15 && (bytes[15] === 0 || bytes[15] === 1)) return true
  const mapped = bytes.slice(0, 10).every((b) => b === 0) && bytes[10] === 0xff && bytes[11] === 0xff
  if (mapped) return isPrivateOrReservedIpv4(`${bytes[12]}.${bytes[13]}.${bytes[14]}.${bytes[15]}`)
  if (bytes.slice(0, 12).every((b) => b === 0) && (bytes[12] || bytes[13] || bytes[14] || bytes[15])) {
    return isPrivateOrReservedIpv4(`${bytes[12]}.${bytes[13]}.${bytes[14]}.${bytes[15]}`)
  }
  const first = bytes[0]
  if ((first & 0xfe) === 0xfc) return true
  if (first === 0xfe && (bytes[1] & 0xc0) === 0x80) return true
  if (first === 0xff) return true
  return false
}

/** Vrai si l'IP (v4 pointée ou v6 littérale sans crochets) est privée/réservée. */
function isPrivateOrReservedIp(ip: string): boolean {
  const host = ip.toLowerCase().replace(/^\[|\]$/g, '')
  if (host.includes(':')) {
    const b = parseIpv6(host)
    return b === null ? true : isPrivateOrReservedIpv6(b)
  }
  const v4 = parseIpv4Literal(host)
  return v4 === null ? true : isPrivateOrReservedIpv4(v4)
}

function isAllowedWebhookUrl(raw: string): boolean {
  let u: URL
  try { u = new URL(raw) } catch (e) { console.error('isAllowedWebhookUrl: invalid URL:', e); return false }
  if (u.protocol !== 'https:') return false
  const h = u.hostname.toLowerCase().replace(/^\[|\]$/g, '')
  if (h.length === 0) return false
  if (h === 'localhost' || h.endsWith('.local') || h.endsWith('.internal')) return false
  if (h.includes(':')) {
    const b = parseIpv6(h)
    return b === null ? false : !isPrivateOrReservedIpv6(b)
  }
  const v4 = parseIpv4Literal(h)
  if (v4 !== null) return !isPrivateOrReservedIpv4(v4)
  return true // nom de domaine — l'IP résolue est validée par assertPublicHost()
}

/**
 * Résout le DNS de l'hôte et vérifie que TOUTES les IP résolues sont publiques.
 * Bloque le DNS rebinding : un domaine public dont le A record pointe en interne.
 * Renvoie false si aucune résolution ou si une seule IP est privée/réservée.
 */
async function assertPublicHost(host: string): Promise<boolean> {
  const clean = host.toLowerCase().replace(/^\[|\]$/g, '')
  // Hôte déjà littéral IP → pas de DNS, on classe directement.
  if (clean.includes(':') || parseIpv4Literal(clean) !== null) {
    return !isPrivateOrReservedIp(clean)
  }
  let addrs: string[] = []
  try {
    const [a, aaaa] = await Promise.allSettled([
      Deno.resolveDns(clean, 'A'),
      Deno.resolveDns(clean, 'AAAA'),
    ])
    if (a.status === 'fulfilled') addrs = addrs.concat(a.value)
    if (aaaa.status === 'fulfilled') addrs = addrs.concat(aaaa.value)
  } catch (e) {
    console.error('assertPublicHost: DNS error for', clean, e)
    return false
  }
  if (addrs.length === 0) return false // pas de résolution → refuser (fail-closed)
  return addrs.every((ip) => !isPrivateOrReservedIp(ip))
}

/**
 * fetch durci : refuse les cibles non publiques et suit les redirections en
 * re-validant l'URL ET l'IP résolue à chaque saut (bloque les 302 → IP privée).
 */
async function safeFetch(startUrl: string, init: RequestInit, maxHops = 3): Promise<Response> {
  let url = startUrl
  for (let hop = 0; hop <= maxHops; hop++) {
    if (!isAllowedWebhookUrl(url)) throw new Error('URL bloquée (protection SSRF)')
    if (!(await assertPublicHost(new URL(url).hostname))) {
      throw new Error('Hôte résolu vers une IP privée (protection SSRF)')
    }
    const res = await fetch(url, { ...init, redirect: 'manual' })
    if (res.status >= 300 && res.status < 400) {
      const loc = res.headers.get('location')
      if (!loc) return res
      url = new URL(loc, url).toString() // saut suivant re-validé en tête de boucle
      continue
    }
    return res
  }
  throw new Error('Trop de redirections (protection SSRF)')
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

    // LOT5-05 (durci) : safeFetch valide DNS + redirections à chaque saut.
    const response = await safeFetch(url, {
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

// ASY-01 / H10 : traiter la queue depuis PostgreSQL.
// Le lot est PRIS par claim_webhook_batch (migration 234) : FOR UPDATE SKIP
// LOCKED, statut « sending », et aucune tentative consommée. La lecture directe
// d'avant interrogeait une colonne de retard qui n'existe pas dans la table
// (elle porte next_attempt_at) : la requête échouait et plus rien n'était
// jamais livré. Sans verrou, l'appel qui suit une insertion et celui du cron
// pouvaient en outre livrer deux fois le même événement.
async function processQueue(supabase: any) {
  const { data: pending, error } = await supabase.rpc("claim_webhook_batch", { p_batch_size: 50 })

  if (error) { console.error("outgoing-webhooks claim batch:", error); return 0 }
  if (!pending || pending.length === 0) return 0

  let processed = 0
  for (const item of pending) {
    // LOT5-05 (durci) : Vérifier SSRF avant l'envoi — sync (URL/littéraux) + DNS résolu.
    let blockReason = ""
    if (!isAllowedWebhookUrl(item.url)) {
      blockReason = "URL bloquée (protection SSRF)"
    } else {
      try {
        const host = new URL(item.url).hostname
        if (!(await assertPublicHost(host))) {
          blockReason = "Hôte résolu vers une IP privée (protection SSRF)"
        }
      } catch (e) {
        blockReason = "URL invalide (protection SSRF)"
        console.error("SSRF pre-check error:", e)
      }
    }
    if (blockReason) {
      await supabase.from("webhook_delivery_queue").update({
        status: "blocked",
        last_error: blockReason,
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
          next_attempt_at: nextRetry,
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
