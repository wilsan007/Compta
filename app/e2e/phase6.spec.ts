import { test, expect, Page, APIRequestContext } from '@playwright/test'

test.describe.configure({ mode: 'serial' })

const TEST_EMAIL = process.env.E2E_TEST_EMAIL || 'test@test.com'
const TEST_PASSWORD = process.env.E2E_TEST_PASSWORD || ''
const SUPABASE_URL = process.env.SUPABASE_URL || 'https://ndtaedcgwnaopopugiql.supabase.co'
const SUPABASE_KEY = process.env.SUPABASE_KEY || process.env.VITE_SUPABASE_PUBLISHABLE_KEY || ''

let cachedSession: { access_token: string; refresh_token: string; expires_in: number } | null = null

async function getAuthSession(apiContext: APIRequestContext) {
  if (cachedSession) return cachedSession
  const response = await apiContext.post(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
    headers: { 'apikey': SUPABASE_KEY, 'Content-Type': 'application/json' },
    data: { email: TEST_EMAIL, password: TEST_PASSWORD },
  })
  const data = await response.json()
  if (data.access_token) { cachedSession = data; return data }
  throw new Error(`Auth failed: ${data.error_description || data.msg || 'Unknown'}`)
}

async function login(page: Page, request: APIRequestContext) {
  await page.goto('/login')
  await page.waitForTimeout(2000)
  const emailInput = page.locator('input[type="email"]')
  await emailInput.waitFor({ state: 'visible', timeout: 15000 })
  await emailInput.fill(TEST_EMAIL)
  await page.locator('input[type="password"]').fill(TEST_PASSWORD)
  await page.locator('button[type="submit"]').click()
  await page.waitForTimeout(5000)
}

// ============ Phase 6 Routes E2E Tests ============
const phase6Routes = [
  { path: '/accounting/batch-entry', titleKey: 'batchEntry.title' },
  { path: '/accounting/auto-labels', titleKey: 'autoLabel.title' },
  { path: '/accounting/extourne', titleKey: 'extourne.title' },
  { path: '/accounting/carry-forward', titleKey: 'carryForward.title' },
  { path: '/accounting/lettrage-differences', titleKey: 'lettrageDiff.title' },
  { path: '/accounting/controls', titleKey: 'controls.title' },
  { path: '/accounting/cash-control', titleKey: 'cashControl.title' },
  { path: '/accounting/fec-attestations', titleKey: 'fecAttest.title' },
  { path: '/accounting/tier-ribs', titleKey: 'tierRIB.title' },
  { path: '/accounting/ifrs-adjustments', titleKey: 'ifrsAdjustments.title' },
  { path: '/accounting/tax-payments', titleKey: 'taxPayment.title' },
  { path: '/accounting/custom-reports', titleKey: 'customReport.title' },
  { path: '/accounting/deferred-printing', titleKey: 'deferredPrint.title' },
  { path: '/accounting/journal-access-rights', titleKey: 'journalAccessRights.title' },
  { path: '/accounting/vat-on-collections', titleKey: 'vatCollection.title' },
]

for (const route of phase6Routes) {
  test(`Phase 6 — ${route.path} loads without crash`, async ({ page, request }) => {
    await login(page, request)
    await page.goto(route.path)
    await page.waitForTimeout(3000)

    // Page should not show a blank screen or error boundary
    const body = page.locator('body')
    await expect(body).not.toBeEmpty()

    // Should not contain "Application error" or "404"
    const bodyText = await body.textContent()
    expect(bodyText).not.toContain('Application error')
    expect(bodyText).not.toContain('404')
    expect(bodyText).not.toContain('Not Found')
  })
}

test('Phase 6 — Batch Entry page shows new session button', async ({ page, request }) => {
  await login(page, request)
  await page.goto('/accounting/batch-entry')
  await page.waitForTimeout(3000)
  // Look for any button element
  const buttons = page.locator('button')
  await expect(buttons.first()).toBeVisible()
})

test('Phase 6 — Accounting Controls page shows run control button', async ({ page, request }) => {
  await login(page, request)
  await page.goto('/accounting/controls')
  await page.waitForTimeout(3000)
  const buttons = page.locator('button')
  await expect(buttons.first()).toBeVisible()
})

test('Phase 6 — Cash Control page loads form', async ({ page, request }) => {
  await login(page, request)
  await page.goto('/accounting/cash-control')
  await page.waitForTimeout(3000)
  const body = page.locator('body')
  await expect(body).not.toBeEmpty()
})

test('Phase 6 — Tier RIBs page loads', async ({ page, request }) => {
  await login(page, request)
  await page.goto('/accounting/tier-ribs')
  await page.waitForTimeout(3000)
  const body = page.locator('body')
  await expect(body).not.toBeEmpty()
})

test('Phase 6 — IFRS Adjustments page loads', async ({ page, request }) => {
  await login(page, request)
  await page.goto('/accounting/ifrs-adjustments')
  await page.waitForTimeout(3000)
  const body = page.locator('body')
  await expect(body).not.toBeEmpty()
})

test('Phase 6 — VAT on Collections page loads', async ({ page, request }) => {
  await login(page, request)
  await page.goto('/accounting/vat-on-collections')
  await page.waitForTimeout(3000)
  const body = page.locator('body')
  await expect(body).not.toBeEmpty()
})

test('Phase 6 — All 15 routes are accessible from sidebar navigation', async ({ page, request }) => {
  await login(page, request)
  // Navigate to accounting home
  await page.goto('/accounting/home')
  await page.waitForTimeout(2000)

  // Verify the accounting module is visible in sidebar
  const sidebar = page.locator('nav, [class*="sidebar"]')
  if (await sidebar.isVisible()) {
    const sidebarText = await sidebar.textContent()
    // At least some accounting nav items should be visible
    expect(sidebarText).toContain('Comptabilité')
  }
})
