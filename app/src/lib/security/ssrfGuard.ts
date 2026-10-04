// LOT5-05 (durci) : Garde SSRF pure et agnostique du runtime pour les URLs de webhook.
//
// Ce module est la SOURCE UNIQUE de vérité côté JavaScript. Il est importé par :
//   - le front (ApiWebhooksPage.tsx) — validation immédiate, UX ;
//   - les tests unitaires (ssrfGuard.test.ts) — couvre tous les bypass.
// La fonction SQL is_allowed_webhook_url (migration 167) et la garde de la
// Edge Function outgoing-webhooks/index.ts DOIVENT rester alignées avec ce fichier.
//
// PÉRIMÈTRE des vérifications SYNCHRONES ici :
//   - protocole HTTPS uniquement ;
//   - hôtes locaux (localhost, .local, .internal) ;
//   - littéraux IP privés/réservés, y compris les encodages qui contournent
//     un simple regex : décimal (2130706433), hex (0x7f000001), octal
//     (0177.0.0.1), abrégé (127.1), et IPv6 IPv4-mapped ([::ffff:169.254.169.254]).
//
// CE QUI N'EST PAS COUVRABLE ICI (uniquement à l'exécution, dans la Edge Function) :
//   - DNS rebinding : un domaine PUBLIC qui résout vers une IP privée
//     (ex. 169.254.169.254.nip.io, ou un domaine attaquant avec un A record 10.x).
//   - Redirections HTTP : une URL publique qui renvoie un 302 vers une IP privée.
//   Ces deux vecteurs exigent de résoudre le DNS et de valider l'IP FINALE au
//   moment du fetch — voir assertPublicWebhookTarget()/safeFetch() dans la Edge Function.

/** Résultat détaillé (utile pour les messages/UX et les tests). */
export interface SsrfCheckResult {
  allowed: boolean
  /** Code stable de la raison de rejet (undefined si allowed). */
  reason?:
    | 'invalid-url'
    | 'not-https'
    | 'local-hostname'
    | 'private-ipv4'
    | 'private-ipv6'
    | 'ambiguous-ip-literal'
}

// ── IPv4 ────────────────────────────────────────────────────────────────────

/**
 * Convertit un hôte qui est un littéral IPv4 dans N'IMPORTE QUEL encodage en
 * forme canonique pointée « a.b.c.d ». Renvoie null si l'hôte n'est pas un
 * littéral IPv4 (c'est alors probablement un nom de domaine).
 *
 * Gère : dotted-decimal (1.2.3.4), dotted-octal (0177.0.0.1), dotted-hex
 * (0x7f.0.0.1), 32 bits unique en décimal (2130706433) / hex (0x7f000001) /
 * octal (017700000001), et formes abrégées (127.1 → 127.0.0.1).
 *
 * NB : dans les runtimes WHATWG (navigateur, Node, Deno), `new URL()` normalise
 * déjà ces formes ; cette fonction est la garde de défense en profondeur pour le
 * code qui manipule un hostname brut (et le miroir de la logique SQL).
 */
export function parseIpv4Literal(host: string): string | null {
  if (host.length === 0) return null
  const rawParts = host.split('.')
  if (rawParts.length === 0 || rawParts.length > 4) return null

  const nums: number[] = []
  for (const part of rawParts) {
    const n = parseIpv4Part(part)
    if (n === null) return null
    nums.push(n)
  }

  // Reconstituer l'entier 32 bits selon le nombre de segments (règle inet_aton).
  // 4 segments : a.b.c.d ; 3 : a.b.(c 16 bits) ; 2 : a.(b 24 bits) ; 1 : (32 bits).
  const last = nums[nums.length - 1]
  const leading = nums.slice(0, -1)
  const maxLast = Math.pow(256, 4 - leading.length)
  if (last >= maxLast) return null
  for (const seg of leading) if (seg > 255) return null

  let value = last
  for (let i = 0; i < leading.length; i++) {
    value += leading[i] * Math.pow(256, 3 - i)
  }
  if (value < 0 || value > 0xffffffff) return null

  return [
    (value >>> 24) & 0xff,
    (value >>> 16) & 0xff,
    (value >>> 8) & 0xff,
    value & 0xff,
  ].join('.')
}

/** Parse un segment IPv4 en décimal, hex (0x…) ou octal (0…). null si invalide. */
function parseIpv4Part(part: string): number | null {
  if (part.length === 0) return null
  let n: number
  if (/^0x[0-9a-f]+$/i.test(part)) {
    n = parseInt(part.slice(2), 16)
  } else if (/^0[0-7]+$/.test(part)) {
    n = parseInt(part, 8)
  } else if (/^[0-9]+$/.test(part)) {
    n = parseInt(part, 10)
  } else {
    return null
  }
  return Number.isFinite(n) ? n : null
}

/** Vrai si l'IPv4 pointée « a.b.c.d » est privée, réservée, loopback ou link-local. */
export function isPrivateOrReservedIpv4(dotted: string): boolean {
  const parts = dotted.split('.').map(Number)
  if (parts.length !== 4 || parts.some((p) => !Number.isInteger(p) || p < 0 || p > 255)) {
    return true // par prudence, un littéral IPv4 malformé est bloqué
  }
  const [a, b] = parts
  if (a === 0) return true // 0.0.0.0/8 « ce réseau »
  if (a === 10) return true // 10.0.0.0/8 privé
  if (a === 127) return true // 127.0.0.0/8 loopback
  if (a === 169 && b === 254) return true // 169.254.0.0/16 link-local (métadonnées cloud !)
  if (a === 172 && b >= 16 && b <= 31) return true // 172.16.0.0/12 privé
  if (a === 192 && b === 168) return true // 192.168.0.0/16 privé
  if (a === 100 && b >= 64 && b <= 127) return true // 100.64.0.0/10 CGNAT
  if (a === 192 && b === 0) return true // 192.0.0.0/24 + 192.0.2.0/24 (TEST-NET-1)
  if (a >= 224) return true // 224.0.0.0/4 multicast + 240.0.0.0/4 réservé + 255.255.255.255
  return false
}

// ── IPv6 ────────────────────────────────────────────────────────────────────

/**
 * Parse un hôte IPv6 (déjà sans crochets) en 16 octets. Gère la compression
 * « :: » et la notation IPv4-mapped « ::ffff:1.2.3.4 ». null si non-IPv6.
 */
export function parseIpv6(host: string): Uint8Array | null {
  if (!host.includes(':')) return null
  let str = host

  // Notation IPv4 embarquée en fin (::ffff:1.2.3.4) → convertir en 2 groupes hex.
  const lastColon = str.lastIndexOf(':')
  const tail = str.slice(lastColon + 1)
  if (tail.includes('.')) {
    const v4 = parseIpv4Literal(tail)
    if (v4 === null) return null
    const o = v4.split('.').map(Number)
    const hexTail = ((o[0] << 8) | o[1]).toString(16) + ':' + ((o[2] << 8) | o[3]).toString(16)
    str = str.slice(0, lastColon + 1) + hexTail
  }

  const halves = str.split('::')
  if (halves.length > 2) return null

  const head = halves[0].length ? halves[0].split(':') : []
  const back = halves.length === 2 && halves[1].length ? halves[1].split(':') : []

  const groups: number[] = []
  const pushGroup = (g: string): boolean => {
    if (!/^[0-9a-f]{1,4}$/i.test(g)) return false
    groups.push(parseInt(g, 16))
    return true
  }

  for (const g of head) if (!pushGroup(g)) return null
  if (halves.length === 2) {
    const fill = 8 - head.length - back.length
    if (fill < 0) return null
    for (let i = 0; i < fill; i++) groups.push(0)
    for (const g of back) if (!pushGroup(g)) return null
  }
  if (groups.length !== 8) return null

  const bytes = new Uint8Array(16)
  for (let i = 0; i < 8; i++) {
    bytes[i * 2] = (groups[i] >> 8) & 0xff
    bytes[i * 2 + 1] = groups[i] & 0xff
  }
  return bytes
}

/** Vrai si l'IPv6 est loopback, non-spécifiée, ULA, link-local, ou IPv4-mapped-privée. */
export function isPrivateOrReservedIpv6(bytes: Uint8Array): boolean {
  // ::  (non-spécifiée) et ::1 (loopback)
  const allZeroTo15 = bytes.slice(0, 15).every((b) => b === 0)
  if (allZeroTo15 && (bytes[15] === 0 || bytes[15] === 1)) return true

  // IPv4-mapped ::ffff:a.b.c.d  → octets 0..9 = 0, 10..11 = 0xff
  const mappedPrefix =
    bytes.slice(0, 10).every((b) => b === 0) && bytes[10] === 0xff && bytes[11] === 0xff
  if (mappedPrefix) {
    const v4 = `${bytes[12]}.${bytes[13]}.${bytes[14]}.${bytes[15]}`
    return isPrivateOrReservedIpv4(v4)
  }
  // IPv4-compatible ::a.b.c.d (déprécié) → traiter comme l'IPv4 embarquée
  if (bytes.slice(0, 12).every((b) => b === 0) && (bytes[12] || bytes[13] || bytes[14] || bytes[15])) {
    const v4 = `${bytes[12]}.${bytes[13]}.${bytes[14]}.${bytes[15]}`
    return isPrivateOrReservedIpv4(v4)
  }

  const first = bytes[0]
  if ((first & 0xfe) === 0xfc) return true // fc00::/7 ULA (fc/fd)
  if (first === 0xfe && (bytes[1] & 0xc0) === 0x80) return true // fe80::/10 link-local
  if (first === 0xff) return true // ff00::/8 multicast
  return false
}

// ── Point d'entrée synchrone ─────────────────────────────────────────────────

/** Version détaillée : renvoie la raison du rejet. */
export function checkWebhookUrl(raw: string): SsrfCheckResult {
  let u: URL
  try {
    u = new URL(raw)
  } catch {
    return { allowed: false, reason: 'invalid-url' }
  }
  if (u.protocol !== 'https:') return { allowed: false, reason: 'not-https' }

  // `new URL` normalise déjà les littéraux IPv4 encodés ; on retire les crochets IPv6.
  const host = u.hostname.toLowerCase().replace(/^\[|\]$/g, '')
  if (host.length === 0) return { allowed: false, reason: 'local-hostname' }

  if (host === 'localhost' || host.endsWith('.local') || host.endsWith('.internal')) {
    return { allowed: false, reason: 'local-hostname' }
  }

  // Littéral IPv6 (avec « : ») ?
  if (host.includes(':')) {
    const bytes = parseIpv6(host)
    if (bytes === null) return { allowed: false, reason: 'ambiguous-ip-literal' }
    return isPrivateOrReservedIpv6(bytes)
      ? { allowed: false, reason: 'private-ipv6' }
      : { allowed: true }
  }

  // Littéral IPv4 (dans un encodage quelconque) ?
  const v4 = parseIpv4Literal(host)
  if (v4 !== null) {
    return isPrivateOrReservedIpv4(v4)
      ? { allowed: false, reason: 'private-ipv4' }
      : { allowed: true }
  }

  // Sinon : nom de domaine. La validation de l'IP résolue (DNS rebinding) se fait
  // à l'exécution dans la Edge Function ; ici on autorise.
  return { allowed: true }
}

/** API historique conservée : booléen simple. */
export function isAllowedWebhookUrl(raw: string): boolean {
  return checkWebhookUrl(raw).allowed
}
