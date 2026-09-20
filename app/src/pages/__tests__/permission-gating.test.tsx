/**
 * LOT7-01 / arbitrage du 18/09 — les actions affichées suivent le rôle.
 *
 * On vérifie le comportement que verrait l'utilisateur (le bouton est là ou non),
 * pas la présence d'un appel à `usePermission`.
 *
 * Rappel porté par ces tests : ce filtrage est un confort d'interface. Il ne
 * protège rien tant que la RLS ignore le rôle (7 politiques sur 2 296).
 */
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import '@testing-library/jest-dom/vitest'
import { MemoryRouter } from 'react-router-dom'
import { hasPermission } from '@/lib/queries/misc'

const mockChain: any = {
  select: vi.fn(() => mockChain),
  eq: vi.fn(() => mockChain),
  order: vi.fn(() => mockChain),
  range: vi.fn(() => Promise.resolve({ data: [], error: null })),
  limit: vi.fn(() => mockChain),
  then: vi.fn((resolve: any) => Promise.resolve({ data: [], error: null }).then(resolve)),
}

vi.mock('@/lib/supabase', () => ({
  supabase: { from: vi.fn(() => mockChain), auth: { getSession: vi.fn() }, channel: vi.fn(), removeChannel: vi.fn() },
  getCachedTenantId: vi.fn(() => 'tid'),
  isTenantTable: vi.fn(() => true),
}))
vi.mock('@/lib/toast', () => ({ useToast: vi.fn(() => ({ toast: vi.fn() })) }))
vi.mock('react-i18next', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react-i18next')>()
  return { ...actual, useTranslation: vi.fn(() => ({ t: (k: string) => k, i18n: { language: 'fr', changeLanguage: vi.fn() } })) }
})

const role = { current: 'admin' as string }
vi.mock('@/lib/auth', () => ({
  useAuth: () => ({
    user: { role: role.current, permissions: {} },
    canPerform: (table: string, action: any) =>
      hasPermission({ role: role.current, permissions: {} } as any, table, action),
  }),
}))

async function renderEmployees(r: string) {
  role.current = r
  const { EmployeesPage } = await import('@/pages/EmployeesPage')
  render(<MemoryRouter><EmployeesPage /></MemoryRouter>)
  await waitFor(() => expect(screen.getAllByText('employees.title').length).toBeGreaterThan(0))
}

describe('actions conditionnées par le rôle', () => {
  beforeEach(() => { vi.clearAllMocks() })

  it("un admin voit le bouton de création", async () => {
    await renderEmployees('admin')
    expect(screen.getAllByText('employees.new').length).toBeGreaterThan(0)
  })

  it("un viewer ne voit pas le bouton de création", async () => {
    await renderEmployees('viewer')
    expect(screen.queryAllByText('employees.new')).toHaveLength(0)
  })

  it("la matrice reste la seule source : accountant ne supprime pas un employé", () => {
    const acc = { role: 'accountant', permissions: {} } as any
    expect(hasPermission(acc, 'employees', 'delete')).toBe(false)
    expect(hasPermission(acc, 'journal_entries', 'delete')).toBe(true)
  })

  it("un rôle custom suit ses permissions déclarées", () => {
    const custom = { role: 'custom', permissions: { invoices: ['select', 'insert'] } } as any
    expect(hasPermission(custom, 'invoices', 'insert')).toBe(true)
    expect(hasPermission(custom, 'invoices', 'delete')).toBe(false)
    expect(hasPermission(custom, 'quotes', 'select')).toBe(false)
  })
})
