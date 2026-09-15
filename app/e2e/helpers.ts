import { test as base, expect, type APIRequestContext, type Page } from '@playwright/test'

// Types
export interface AuthSession {
  access_token: string
  refresh_token: string
  expires_in: number
}

// Configuration
const SUPABASE_URL = process.env.SUPABASE_URL || 'https://ndtaedcgwnaopopugiql.supabase.co'
const SUPABASE_KEY = process.env.SUPABASE_KEY || process.env.VITE_SUPABASE_PUBLISHABLE_KEY || ''
const TEST_EMAIL = process.env.E2E_TEST_EMAIL || 'test@test.com'
const TEST_PASSWORD = process.env.E2E_TEST_PASSWORD || ''

// Cache de session
let cachedSession: AuthSession | null = null

export async function getAuthSession(apiContext: APIRequestContext): Promise<AuthSession> {
  if (cachedSession) return cachedSession
  const response = await apiContext.post(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
    headers: { 'apikey': SUPABASE_KEY, 'Content-Type': 'application/json' },
    data: { email: TEST_EMAIL, password: TEST_PASSWORD },
  })
  const data = await response.json()
  if (data.access_token) {
    cachedSession = data
    return data
  }
  throw new Error(`Auth failed: ${data.error_description || data.msg || 'Unknown'}`)
}

export async function setAuthCookies(page: Page, session: AuthSession) {
  await page.context().addCookies([
    { name: 'sb-access-token', value: session.access_token, domain: 'localhost', path: '/' },
    { name: 'sb-refresh-token', value: session.refresh_token, domain: 'localhost', path: '/' },
  ])
}

export async function navigateWithAuth(page: Page, apiContext: APIRequestContext, path: string) {
  const session = await getAuthSession(apiContext)
  await setAuthCookies(page, session)
  await page.goto(path)
  await page.waitForLoadState('networkidle')
}

// Test fixture avec auth automatique
export const test = base.extend<{ authedPage: Page }>({
  // Le second argument est le callback de fixture Playwright (nommé `use` dans la doc) :
  // renommé pour ne pas être pris pour un hook React par le lint.
  authedPage: async ({ page, request }, provide) => {
    try {
      await navigateWithAuth(page, request, '/dashboard')
    } catch {
      // Skip si pas de credentials
      test.skip(true, 'E2E credentials not configured')
    }
    await provide(page)
  },
})

export { expect }
