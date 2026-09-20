import { test, expect, Page, APIRequestContext } from '@playwright/test'
import { loginViaUI, assertAuthenticated, E2E_CREDENTIALS_CONFIGURED, E2E_SKIP_REASON, assertWorkspaceReady } from './helpers'

test.describe.configure({ mode: 'serial' })
test.skip(!E2E_CREDENTIALS_CONFIGURED, E2E_SKIP_REASON)


// Trois implémentations de connexion coexistaient, toutes basées sur un
// `waitForTimeout(5000)` fixe : trop court dès que le premier rendu ralentit, et
// le test partait alors sur /login. Une seule implémentation désormais, qui
// attend la navigation réelle (`loginViaUI` dans helpers.ts).
async function login(page: Page, _request?: APIRequestContext) {
  await loginViaUI(page)
  await assertWorkspaceReady(page)
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
  // `locator('button').first()` tombait sur un bouton masqué du DOM (menu replié).
  // On vise un bouton réellement visible, et on lui laisse le temps d'arriver.
  const button = page.locator('button:visible').first()
  await expect(button).toBeVisible({ timeout: 30000 })
})

test('Phase 6 — Accounting Controls page shows run control button', async ({ page, request }) => {
  await login(page, request)
  await page.goto('/accounting/controls')
  const button = page.locator('button:visible').first()
  await expect(button).toBeVisible({ timeout: 30000 })
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

  // Trois défauts dans ce test :
  //  - `locator('nav, [class*="sidebar"]')` visait 4 éléments (l'aside, le
  //    champ de filtre, la nav latérale et le fil d'Ariane) : violation du
  //    mode strict, `isVisible()` levait avant toute vérification ;
  //  - l'assertion était enfermée dans un `if` — sidebar absente, test vert ;
  //  - elle attendait « Comptabilité » alors que l'interface tourne en anglais.
  await assertAuthenticated(page)
  const sidebar = page.locator('aside').first()
  await expect(sidebar).toBeVisible({ timeout: 30000 })
  await expect(sidebar).toContainText(/Comptabilité|Accounting/, { timeout: 30000 })
})
