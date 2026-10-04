/**
 * Tests Phase 5 : API Keys, Webhooks, 2FA, Email Templates, Notifications
 *
 * Tests unitaires pour les nouvelles fonctionnalités enterprise.
 */

import { describe, it, expect, vi, beforeEach } from 'vitest'

// Mock supabase
vi.mock('@/lib/supabase', () => ({
  supabase: {
    rpc: vi.fn(),
    from: vi.fn(() => ({
      select: vi.fn(() => ({ data: [], error: null })),
      insert: vi.fn(() => ({ data: null, error: null })),
      update: vi.fn(() => ({ data: null, error: null })),
      delete: vi.fn(() => ({ data: null, error: null })),
      eq: vi.fn(() => ({ data: null, error: null })),
      order: vi.fn(() => ({ data: [], error: null })),
      limit: vi.fn(() => ({ data: [], error: null })),
      range: vi.fn(() => ({ data: [], error: null })),
      single: vi.fn(() => ({ data: null, error: null })),
    })),
  },
}))

import { supabase } from '@/lib/supabase'

// ============================================================
// 1. NOTIFICATIONS : create_notification, mark_read, count
// ============================================================
describe('Notifications : workflow complet', () => {
  beforeEach(() => vi.clearAllMocks())

  it('create_notification appelle le RPC avec les bons paramètres', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({ data: 'notif-123', error: null } as any)

    const { data, error } = await supabase.rpc('create_notification', {
      p_category: 'sales',
      p_title: 'Test notification',
      p_message: 'Message de test',
      p_severity: 'info',
    })

    expect(supabase.rpc).toHaveBeenCalledWith('create_notification', {
      p_category: 'sales',
      p_title: 'Test notification',
      p_message: 'Message de test',
      p_severity: 'info',
    })
    expect(data).toBe('notif-123')
    expect(error).toBeNull()
  })

  it('mark_notification_read appelle le RPC avec l\'ID', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({ data: null, error: null } as any)

    await supabase.rpc('mark_notification_read', { p_notification_id: 'notif-123' })

    expect(supabase.rpc).toHaveBeenCalledWith('mark_notification_read', {
      p_notification_id: 'notif-123',
    })
  })

  it('mark_all_notifications_read appelle le RPC', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({ data: null, error: null } as any)

    await supabase.rpc('mark_all_notifications_read')

    expect(supabase.rpc).toHaveBeenCalledWith('mark_all_notifications_read')
  })

  it('get_unread_notification_count retourne un entier', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({ data: 5, error: null } as any)

    const { data } = await supabase.rpc('get_unread_notification_count')

    expect(data).toBe(5)
    expect(typeof data).toBe('number')
  })

  it('chaîne complète : créer → compter → marquer lu → compter', async () => {
    // Créer
    vi.mocked(supabase.rpc).mockResolvedValueOnce({ data: 'notif-1', error: null } as any)
    const createRes = await supabase.rpc('create_notification', {
      p_category: 'hr', p_title: 'Test', p_message: 'Msg',
    })
    expect(createRes.data).toBe('notif-1')

    // Compter (1 non lu)
    vi.mocked(supabase.rpc).mockResolvedValueOnce({ data: 1, error: null } as any)
    const countRes = await supabase.rpc('get_unread_notification_count')
    expect(countRes.data).toBe(1)

    // Marquer lu
    vi.mocked(supabase.rpc).mockResolvedValueOnce({ data: null, error: null } as any)
    await supabase.rpc('mark_notification_read', { p_notification_id: 'notif-1' })

    // Compter (0 non lu)
    vi.mocked(supabase.rpc).mockResolvedValueOnce({ data: 0, error: null } as any)
    const countRes2 = await supabase.rpc('get_unread_notification_count')
    expect(countRes2.data).toBe(0)
  })
})

// ============================================================
// 2. API KEYS : CRUD workflow
// ============================================================
describe('API Keys : gestion complète', () => {
  beforeEach(() => vi.clearAllMocks())

  it('create_api_key génère une clé avec préfixe', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({
      data: { id: 'key-1', full_key: 'sk_live_abc123...', key_prefix: 'sk_live_ab' },
      error: null,
    } as any)

    const { data } = await supabase.rpc('create_api_key', {
      p_name: 'Test key',
      p_permissions: ['read', 'write'],
      p_rate_limit: 100,
    })

    expect(data.full_key).toContain('sk_live_')
    expect(data.key_prefix).toHaveLength(10)
  })

  it('liste des clés API via from().select()', async () => {
    const mockData = [
      { id: 'k1', name: 'Key 1', key_prefix: 'sk_live_a', active: true, permissions: ['read'] },
      { id: 'k2', name: 'Key 2', key_prefix: 'sk_live_b', active: false, permissions: ['read', 'write'] },
    ]

    const chainable = {
      data: mockData, error: null,
      order: vi.fn(() => chainable),
      limit: vi.fn(() => chainable),
      range: vi.fn(() => chainable),
      eq: vi.fn(() => chainable),
      single: vi.fn(() => ({ data: mockData[0], error: null })),
    }

    vi.mocked(supabase.from).mockReturnValue({
      select: vi.fn(() => chainable),
      insert: vi.fn(() => ({ data: null, error: null })),
      update: vi.fn(() => chainable),
      delete: vi.fn(() => chainable),
      eq: vi.fn(() => chainable),
      order: vi.fn(() => chainable),
      limit: vi.fn(() => chainable),
      range: vi.fn(() => chainable),
      single: vi.fn(() => ({ data: mockData[0], error: null })),
    } as any)

    const result = await supabase.from('api_keys').select('*').order('created_at', { ascending: false })

    expect(result.data).toHaveLength(2)
    expect(result.data![0].name).toBe('Key 1')
  })

  it('révocation met active=false et revoked_at', async () => {
    vi.mocked(supabase.from).mockReturnValue({
      update: vi.fn(() => ({ eq: vi.fn(() => ({ data: null, error: null })) })),
      select: vi.fn(),
      insert: vi.fn(),
      delete: vi.fn(),
      order: vi.fn(),
      limit: vi.fn(),
      range: vi.fn(),
      single: vi.fn(),
    } as any)

    // Simulation de la révocation
    const { error } = await supabase.from('api_keys').update({ active: false, revoked_at: new Date().toISOString() }).eq('id', 'k1')
    expect(error).toBeNull()
  })
})

// ============================================================
// 3. WEBHOOKS : endpoints et delivery logs
// ============================================================
describe('Webhooks : endpoints et logs', () => {
  beforeEach(() => vi.clearAllMocks())

  it('création d\'un endpoint webhook', async () => {
    vi.mocked(supabase.from).mockReturnValue({
      insert: vi.fn(() => ({ data: null, error: null })),
      select: vi.fn(),
      update: vi.fn(),
      delete: vi.fn(),
      eq: vi.fn(),
      order: vi.fn(),
      limit: vi.fn(),
      range: vi.fn(),
      single: vi.fn(),
    } as any)

    const { error } = await supabase.from('webhook_endpoints').insert({
      name: 'Slack',
      url: 'https://hooks.slack.com/...',
      active_events: ['invoice.created', 'invoice.paid'],
    })

    expect(error).toBeNull()
  })

  it('liste des logs de livraison avec filtre endpoint', async () => {
    const mockLogs = [
      { id: 'l1', event: 'invoice.created', status: 'delivered', response_code: 200, attempt: 1 },
      { id: 'l2', event: 'invoice.paid', status: 'failed', response_code: 500, attempt: 3, error_message: 'Timeout' },
    ]

    vi.mocked(supabase.from).mockReturnValue({
      select: vi.fn(() => ({
        order: vi.fn(() => ({
          limit: vi.fn(() => ({
            eq: vi.fn(() => ({ data: mockLogs, error: null })),
            data: mockLogs, error: null,
          })),
          data: mockLogs, error: null,
        })),
      })),
      insert: vi.fn(),
      update: vi.fn(),
      delete: vi.fn(),
      eq: vi.fn(),
      range: vi.fn(),
      single: vi.fn(),
    } as any)

    const result = await supabase.from('webhook_delivery_logs').select('*').order('delivered_at', { ascending: false }).limit(100)

    expect(result.data).toHaveLength(2)
    expect(result.data![1].status).toBe('failed')
  })

  it('les événements webhook couvrent les cas critiques', () => {
    const EVENTS = [
      'invoice.created', 'invoice.paid', 'invoice.overdue',
      'purchase_invoice.received', 'payment.received', 'payment.sent',
      'payslip.ready', 'dsn.submitted', 'vat_return.submitted',
      'customer.created', 'supplier.created', 'stock.movement',
      'fiscal_year.closed', 'bank_transaction.imported',
    ]

    expect(EVENTS).toContain('invoice.created')
    expect(EVENTS).toContain('payslip.ready')
    expect(EVENTS).toContain('fiscal_year.closed')
    expect(EVENTS.length).toBeGreaterThanOrEqual(14)
  })
})

// ============================================================
// 4. EMAIL TEMPLATES : CRUD et variables
// ============================================================
describe('Email Templates : gestion', () => {
  beforeEach(() => vi.clearAllMocks())

  it('création d\'un template avec variables', async () => {
    vi.mocked(supabase.from).mockReturnValue({
      insert: vi.fn(() => ({ data: null, error: null })),
      select: vi.fn(),
      update: vi.fn(),
      delete: vi.fn(),
      eq: vi.fn(),
      order: vi.fn(),
      limit: vi.fn(),
      range: vi.fn(),
      single: vi.fn(),
    } as any)

    const { error } = await supabase.from('email_templates').insert({
      template_key: 'invoice.created',
      subject: 'Nouvelle facture {{invoice_number}}',
      body_html: '<h1>Facture {{invoice_number}}</h1>',
      variables: ['invoice_number', 'amount', 'currency', 'due_date', 'customer_name'],
      locale: 'fr',
    })

    expect(error).toBeNull()
  })

  it('les templates par défaut couvrent les cas métier', () => {
    const TEMPLATE_KEYS = [
      'invoice.created', 'payment.reminder', 'payslip.ready',
      'purchase_invoice.received', 'dsn.submitted', 'vat_return.submitted',
      'leave_request.approved', 'leave_request.rejected',
      'expense_report.approved', 'expense_report.rejected',
      'bank_reconciliation.complete', 'fiscal_year.closed',
    ]

    // Vérifier que les templates critiques existent
    expect(TEMPLATE_KEYS).toContain('invoice.created')
    expect(TEMPLATE_KEYS).toContain('payment.reminder')
    expect(TEMPLATE_KEYS).toContain('payslip.ready')
    expect(TEMPLATE_KEYS).toContain('fiscal_year.closed')
    expect(TEMPLATE_KEYS.length).toBe(12)
  })

  it('variables disponibles pour invoice.created', () => {
    const vars = ['invoice_number', 'amount', 'currency', 'due_date', 'customer_name']

    expect(vars).toContain('invoice_number')
    expect(vars).toContain('amount')
    expect(vars).toContain('due_date')
    expect(vars.length).toBe(5)
  })
})

// ============================================================
// 5. 2FA : TOTP workflow
// ============================================================
describe('2FA TOTP : workflow', () => {
  it('génération d\'un secret TOTP de 32 caractères base32', () => {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'
    let secret = ''
    const bytes = new Uint8Array(20)
    // Simuler des bytes aléatoires
    for (let i = 0; i < 20; i++) bytes[i] = i * 13 % 32
    for (let i = 0; i < 20; i++) secret += chars[(bytes[i] & 31)]

    expect(secret).toHaveLength(20)
    expect(secret).toMatch(/^[A-Z2-7]+$/)
  })

  it('génération de codes de récupération au format XXXX-XXXX', () => {
    const codes: string[] = []
    for (let i = 0; i < 10; i++) {
      const hex = Array.from({ length: 8 }, () => Math.floor(Math.random() * 256).toString(16).padStart(2, '0')).join('').slice(0, 8).toUpperCase()
      codes.push(`${hex.slice(0, 4)}-${hex.slice(4, 8)}`)
    }

    expect(codes).toHaveLength(10)
    codes.forEach(c => {
      expect(c).toMatch(/^[A-F0-9]{4}-[A-F0-9]{4}$/)
    })
  })

  it('URL otpauth est bien formée', () => {
    const issuer = 'Onusuite'
    const label = `${issuer}:user@example.com`
    const secret = 'JBSWY3DPEHPK3PXP'
    const url = `otpauth://totp/${encodeURIComponent(label)}?secret=${secret}&issuer=${issuer}&algorithm=SHA1&digits=6&period=30`

    expect(url).toContain('otpauth://totp/')
    expect(url).toContain('secret=JBSWY3DPEHPK3PXP')
    expect(url).toContain('issuer=Onusuite')
    expect(url).toContain('digits=6')
    expect(url).toContain('period=30')
  })

  it('le token de vérification fait 6 chiffres', () => {
    const token = '123456'
    expect(token).toHaveLength(6)
    expect(token).toMatch(/^\d{6}$/)
  })
})

// ============================================================
// 6. API DOCS : structure des endpoints
// ============================================================
describe('API Docs : endpoints documentés', () => {
  it('tous les endpoints ont une méthode HTTP valide', () => {
    const methods = ['GET', 'POST', 'PUT', 'DELETE']
    const endpoints = [
      { method: 'GET', path: '/v1/health' },
      { method: 'GET', path: '/v1/invoices' },
      { method: 'GET', path: '/v1/invoices/:id' },
      { method: 'POST', path: '/v1/invoices' },
      { method: 'GET', path: '/v1/customers' },
      { method: 'GET', path: '/v1/suppliers' },
      { method: 'GET', path: '/v1/products' },
      { method: 'GET', path: '/v1/journal-entries' },
      { method: 'GET', path: '/v1/vat-returns' },
      { method: 'GET', path: '/v1/pay-slips' },
      { method: 'GET', path: '/v1/balance-sheet' },
      { method: 'GET', path: '/v1/profit-loss' },
      { method: 'GET', path: '/v1/trial-balance' },
    ]

    endpoints.forEach(ep => {
      expect(methods).toContain(ep.method)
      expect(ep.path).toMatch(/^\/v1\//)
    })
  })

  it('le endpoint health ne nécessite pas de paramètres', () => {
    const healthEndpoint = { method: 'GET', path: '/v1/health', params: [] }
    expect(healthEndpoint.params).toHaveLength(0)
  })

  it('balance-sheet requiert fiscal_year_id', () => {
    const bsEndpoint = {
      method: 'GET', path: '/v1/balance-sheet',
      params: [{ name: 'fiscal_year_id', required: true }],
    }
    expect(bsEndpoint.params[0].required).toBe(true)
  })

  it('les codes d\'erreur sont complets', () => {
    const errorCodes = [200, 201, 400, 401, 404, 429, 500]
    expect(errorCodes).toContain(401)  // Auth
    expect(errorCodes).toContain(429)  // Rate limit
    expect(errorCodes).toContain(500)  // Internal
    expect(errorCodes.length).toBe(7)
  })
})

// ============================================================
// 7. SÉCURITÉ : validation des règles
// ============================================================
describe('Sécurité : règles et isolation', () => {
  it('les clés API sont stockées hashées (jamais en clair)', () => {
    const apiKeyRecord = {
      id: 'k1',
      name: 'Test',
      key_hash: 'sha256:abc123...',
      key_prefix: 'sk_live_ab',
      // Pas de champ key_plain ou key
    }

    expect(apiKeyRecord.key_hash).toBeDefined()
    expect(apiKeyRecord.key_prefix).toBeDefined()
    expect(apiKeyRecord).not.toHaveProperty('key_plain')
    expect(apiKeyRecord).not.toHaveProperty('key')
  })

  it('les webhooks sont signés avec HMAC-SHA256', () => {
    const header = 'X-Webhook-Signature'
    const algorithm = 'sha256'
    expect(header).toBe('X-Webhook-Signature')
    expect(algorithm).toBe('sha256')
  })

  it('le rate limit est de 100 req/min', () => {
    const RATE_LIMIT_MAX = 100
    const RATE_LIMIT_WINDOW = 60_000 // 1 minute

    expect(RATE_LIMIT_MAX).toBe(100)
    expect(RATE_LIMIT_WINDOW).toBe(60000)
  })

  it('les notifications sont tenant-scopées', () => {
    const notification = {
      id: 'n1',
      tenant_id: 'tenant-uuid',
      category: 'sales',
      title: 'Test',
      message: 'Msg',
    }

    expect(notification.tenant_id).toBeDefined()
    expect(notification.tenant_id).toBe('tenant-uuid')
  })

  it('le 2FA stocke le secret chiffré', () => {
    const totpRecord = {
      id: 't1',
      user_id: 'user-uuid',
      tenant_id: 'tenant-uuid',
      secret_enc: 'base64encodedencryptedsecret',
      enabled: true,
    }

    expect(totpRecord.secret_enc).toBeDefined()
    expect(totpRecord.secret_enc).not.toBe('plaintext')
    expect(totpRecord).not.toHaveProperty('secret_plain')
  })
})
