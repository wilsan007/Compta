import '@testing-library/jest-dom/vitest'
import { vi, afterEach } from 'vitest'
import { cleanup } from '@testing-library/react'

afterEach(() => {
  cleanup()
})

function createChainableMock() {
  const mock: any = vi.fn(() => mock)
  mock.select = vi.fn(() => mock)
  mock.insert = vi.fn(() => mock)
  mock.update = vi.fn(() => mock)
  mock.delete = vi.fn(() => mock)
  mock.eq = vi.fn(() => mock)
  mock.neq = vi.fn(() => mock)
  mock.order = vi.fn(() => mock)
  mock.single = vi.fn(() => mock)
  mock.limit = vi.fn(() => mock)
  mock.range = vi.fn(() => mock)
  mock.in = vi.fn(() => mock)
  mock.gte = vi.fn(() => mock)
  mock.lte = vi.fn(() => mock)
  mock.like = vi.fn(() => mock)
  mock.ilike = vi.fn(() => mock)
  mock.or = vi.fn(() => mock)
  mock.not = vi.fn(() => mock)
  mock.is = vi.fn(() => mock)
  mock.count = vi.fn(() => mock)
  return mock
}

// Mock supabase module
vi.mock('@/lib/supabase', () => ({
  supabase: {
    from: vi.fn(() => createChainableMock()),
    auth: {
      getSession: vi.fn(),
      signInWithPassword: vi.fn(),
      signOut: vi.fn(),
    },
    channel: vi.fn(),
    removeChannel: vi.fn(),
  },
  getCachedTenantId: vi.fn(() => 'test-tenant-id'),
  isTenantTable: vi.fn(() => true),
}))

// Mock toast
vi.mock('@/lib/toast', () => ({
  useToast: vi.fn(() => ({
    toast: vi.fn(),
  })),
}))

// Mock useLocale
vi.mock('@/hooks/useLocale', () => ({
  useLocale: vi.fn(() => ({
    locale: 'fr',
    formatDate: (d: string) => new Date(d).toLocaleDateString('fr-FR'),
    formatCurrency: (n: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(n),
  })),
}))
