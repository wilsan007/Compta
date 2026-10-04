import { describe, it, expect } from 'vitest'
import {
  isAllowedWebhookUrl,
  checkWebhookUrl,
  parseIpv4Literal,
  isPrivateOrReservedIpv4,
  parseIpv6,
  isPrivateOrReservedIpv6,
} from '@/lib/security/ssrfGuard'

// ============================================================================
// LOT5-05 (durci) : Garde SSRF — couverture des VRAIS bypass avant prod.
// Chaque bloc « BYPASS » correspond à une technique de contournement réelle
// documentée (SSRF filter bypass). Un test rouge ici = trou exploitable.
// ============================================================================

describe('SSRF guard — cas nominaux (doivent passer)', () => {
  it('accepte une URL HTTPS publique', () => {
    expect(isAllowedWebhookUrl('https://example.com/webhook')).toBe(true)
    expect(isAllowedWebhookUrl('https://api.slack.com/hooks/abc')).toBe(true)
    expect(isAllowedWebhookUrl('https://hooks.example.co.uk:8443/x?y=1')).toBe(true)
  })

  it('accepte une IPv4 PUBLIQUE littérale', () => {
    expect(isAllowedWebhookUrl('https://1.1.1.1/webhook')).toBe(true)
    expect(isAllowedWebhookUrl('https://8.8.8.8/webhook')).toBe(true)
  })

  it('accepte une IPv6 PUBLIQUE littérale', () => {
    expect(isAllowedWebhookUrl('https://[2606:4700:4700::1111]/webhook')).toBe(true)
  })
})

describe('SSRF guard — rejets de base (LOT5-05 historique)', () => {
  it('rejette non-HTTPS', () => {
    expect(isAllowedWebhookUrl('http://example.com/webhook')).toBe(false)
    expect(checkWebhookUrl('http://example.com').reason).toBe('not-https')
    expect(isAllowedWebhookUrl('ftp://example.com/x')).toBe(false)
    expect(isAllowedWebhookUrl('file:///etc/passwd')).toBe(false)
  })

  it('rejette localhost / .local / .internal', () => {
    expect(isAllowedWebhookUrl('https://localhost:3000/hook')).toBe(false)
    expect(isAllowedWebhookUrl('https://myapp.local/hook')).toBe(false)
    expect(isAllowedWebhookUrl('https://svc.internal/hook')).toBe(false)
  })

  it('rejette les plages IPv4 privées/réservées en notation pointée', () => {
    for (const ip of [
      '127.0.0.1', '127.0.1.5', '10.0.0.1', '192.168.1.1',
      '169.254.169.254', '172.16.0.1', '172.31.255.255', '0.0.0.0',
    ]) {
      expect(isAllowedWebhookUrl(`https://${ip}/webhook`)).toBe(false)
    }
  })

  it('rejette IPv6 loopback / ULA / link-local en notation standard', () => {
    expect(isAllowedWebhookUrl('https://[::1]/webhook')).toBe(false)
    expect(isAllowedWebhookUrl('https://[fd00::1]/webhook')).toBe(false)
    expect(isAllowedWebhookUrl('https://[fe80::1]/webhook')).toBe(false)
  })

  it('rejette une URL invalide ou vide', () => {
    expect(isAllowedWebhookUrl('not-a-url')).toBe(false)
    expect(isAllowedWebhookUrl('')).toBe(false)
  })
})

// ── Les VRAIS bypass ────────────────────────────────────────────────────────

describe('BYPASS 1 — encodage IPv4 (décimal / hex / octal / abrégé)', () => {
  it('rejette 127.0.0.1 en entier décimal 32 bits (2130706433)', () => {
    expect(isAllowedWebhookUrl('https://2130706433/webhook')).toBe(false)
  })
  it('rejette 127.0.0.1 en hexadécimal (0x7f000001)', () => {
    expect(isAllowedWebhookUrl('https://0x7f000001/webhook')).toBe(false)
  })
  it('rejette 127.0.0.1 en octal pointé (0177.0.0.1)', () => {
    expect(isAllowedWebhookUrl('https://0177.0.0.1/webhook')).toBe(false)
  })
  it('rejette la forme abrégée 127.1', () => {
    expect(isAllowedWebhookUrl('https://127.1/webhook')).toBe(false)
  })
  it('rejette 169.254.169.254 (métadonnées cloud) en décimal (2852039166)', () => {
    expect(isAllowedWebhookUrl('https://2852039166/webhook')).toBe(false)
  })
  it('rejette hex mixte 0x7f.0.0.1', () => {
    expect(isAllowedWebhookUrl('https://0x7f.0.0.1/webhook')).toBe(false)
  })
})

describe('BYPASS 2 — IPv6 IPv4-mapped / compatible', () => {
  it('rejette ::ffff:169.254.169.254 (mapped, forme pointée)', () => {
    expect(isAllowedWebhookUrl('https://[::ffff:169.254.169.254]/webhook')).toBe(false)
  })
  it('rejette ::ffff:a9fe:a9fe (mapped, forme hex — 169.254.169.254)', () => {
    expect(isAllowedWebhookUrl('https://[::ffff:a9fe:a9fe]/webhook')).toBe(false)
  })
  it('rejette ::ffff:7f00:1 (mapped, 127.0.0.1)', () => {
    expect(isAllowedWebhookUrl('https://[::ffff:7f00:1]/webhook')).toBe(false)
  })
  it('rejette la forme longue 0:0:0:0:0:ffff:a9fe:a9fe', () => {
    expect(isAllowedWebhookUrl('https://[0:0:0:0:0:ffff:a9fe:a9fe]/webhook')).toBe(false)
  })
  it('rejette :: (non-spécifiée)', () => {
    expect(isAllowedWebhookUrl('https://[::]/webhook')).toBe(false)
  })
  it('rejette une ULA en fc.. autant que fd..', () => {
    expect(isAllowedWebhookUrl('https://[fc00::1]/webhook')).toBe(false)
    expect(isAllowedWebhookUrl('https://[fdff::abcd]/webhook')).toBe(false)
  })
  it('rejette tout le /10 link-local (fea0::, febf::)', () => {
    expect(isAllowedWebhookUrl('https://[fea0::1]/webhook')).toBe(false)
    expect(isAllowedWebhookUrl('https://[febf::1]/webhook')).toBe(false)
  })
})

describe('BYPASS 3 — plages « oubliées » (CGNAT, multicast, broadcast)', () => {
  it('rejette 100.64.0.0/10 (CGNAT)', () => {
    expect(isAllowedWebhookUrl('https://100.64.0.1/webhook')).toBe(false)
    expect(isAllowedWebhookUrl('https://100.127.255.255/webhook')).toBe(false)
  })
  it('accepte 100.63.x et 100.128.x (hors CGNAT, publics)', () => {
    expect(isAllowedWebhookUrl('https://100.63.0.1/webhook')).toBe(true)
    expect(isAllowedWebhookUrl('https://100.128.0.1/webhook')).toBe(true)
  })
  it('rejette multicast 224.0.0.0/4 et broadcast 255.255.255.255', () => {
    expect(isAllowedWebhookUrl('https://224.0.0.1/webhook')).toBe(false)
    expect(isAllowedWebhookUrl('https://255.255.255.255/webhook')).toBe(false)
  })
})

describe('BYPASS 4 — userinfo / casse / crédentials embarqués', () => {
  it('ignore le userinfo et bloque quand même l’hôte privé', () => {
    expect(isAllowedWebhookUrl('https://user:pass@127.0.0.1/webhook')).toBe(false)
    // userinfo trompeur : l’hôte réel est interne
    expect(isAllowedWebhookUrl('https://expected.com@169.254.169.254/webhook')).toBe(false)
  })
  it('insensible à la casse du hostname', () => {
    expect(isAllowedWebhookUrl('https://LOCALHOST/webhook')).toBe(false)
    expect(isAllowedWebhookUrl('https://Svc.INTERNAL/webhook')).toBe(false)
  })
})

// ── Fonctions unitaires (aide au diagnostic quand un cas ci-dessus casse) ────

describe('parseIpv4Literal', () => {
  it('normalise les encodages', () => {
    expect(parseIpv4Literal('2130706433')).toBe('127.0.0.1')
    expect(parseIpv4Literal('0x7f000001')).toBe('127.0.0.1')
    expect(parseIpv4Literal('0177.0.0.1')).toBe('127.0.0.1')
    expect(parseIpv4Literal('127.1')).toBe('127.0.0.1')
    expect(parseIpv4Literal('1.2.3.4')).toBe('1.2.3.4')
  })
  it('renvoie null pour un nom de domaine', () => {
    expect(parseIpv4Literal('example.com')).toBeNull()
    expect(parseIpv4Literal('api.slack.com')).toBeNull()
  })
  it('renvoie null pour un littéral hors plage', () => {
    expect(parseIpv4Literal('256.1.1.1')).toBeNull()
    expect(parseIpv4Literal('999999999999')).toBeNull()
  })
})

describe('isPrivateOrReservedIpv4', () => {
  it('classe correctement', () => {
    expect(isPrivateOrReservedIpv4('127.0.0.1')).toBe(true)
    expect(isPrivateOrReservedIpv4('169.254.169.254')).toBe(true)
    expect(isPrivateOrReservedIpv4('8.8.8.8')).toBe(false)
    expect(isPrivateOrReservedIpv4('1.1.1.1')).toBe(false)
  })
})

describe('parseIpv6 / isPrivateOrReservedIpv6', () => {
  it('parse la compression et le mapped', () => {
    expect(parseIpv6('::1')).not.toBeNull()
    expect(parseIpv6('::ffff:169.254.169.254')).not.toBeNull()
    expect(parseIpv6('example.com')).toBeNull()
  })
  it('classe le mapped privé', () => {
    const b = parseIpv6('::ffff:169.254.169.254')!
    expect(isPrivateOrReservedIpv6(b)).toBe(true)
  })
  it('laisse passer une IPv6 publique', () => {
    const b = parseIpv6('2606:4700:4700::1111')!
    expect(isPrivateOrReservedIpv6(b)).toBe(false)
  })
})
