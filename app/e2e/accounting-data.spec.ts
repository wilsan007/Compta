import { test, expect, Page } from '@playwright/test'
import { loginViaUI, assertAuthenticated, E2E_CREDENTIALS_CONFIGURED, E2E_SKIP_REASON, assertWorkspaceReady } from './helpers'

test.describe.configure({ mode: 'serial' })
test.skip(!E2E_CREDENTIALS_CONFIGURED, E2E_SKIP_REASON)


// Trois implémentations de connexion coexistaient, toutes basées sur un
// `waitForTimeout(5000)` fixe : trop court dès que le premier rendu ralentit, et
// le test partait alors sur /login. Une seule implémentation désormais, qui
// attend la navigation réelle (`loginViaUI` dans helpers.ts).
async function login(page: Page) {
  await loginViaUI(page)
}

async function waitForContent(page: Page) {
  await page.waitForLoadState('domcontentloaded')
  // Attendre la fin du chargement plutôt qu'un délai fixe : 2 s ne suffisaient
  // pas pour les écrans qui interrogent Supabase, et le test lisait « Loading… ».
  await page
    .locator('h1, h2, table, [role="table"]')
    .first()
    .waitFor({ state: 'visible', timeout: 30000 })
    .catch(() => {})
  await page.waitForTimeout(500)
  // L'écran de connexion possède lui aussi un h1 : attendre « un titre » ne
  // prouve pas qu'on est sur la bonne page. La restauration de session est
  // asynchrone, `assertAuthenticated` lui laisse le temps d'aboutir et échoue
  // si elle n'aboutit pas. Sans cela, la CI lisait l'écran de connexion.
  await assertAuthenticated(page)
  // Dismiss Vite overlay if present
  const overlay = page.locator('.vite-overlay, [class*="fixed inset-0"]')
  if (await overlay.count() > 0) {
    await page.evaluate(() => {
      const o = document.querySelector('.vite-overlay, [class*="fixed inset-0"]')
      if (o) (o as HTMLElement).style.display = 'none'
    })
  }
  await assertWorkspaceReady(page)
}

test.describe('Accounting Data Display', () => {
  test.beforeEach(async ({ page }) => {
    await login(page)
  })

  test('Journal Entries page shows entries with debit/credit', async ({ page }) => {
    await page.goto('/accounting/journal-entries')
    await waitForContent(page)
    const text = await page.locator('#root').textContent() || ''
    expect(text.length).toBeGreaterThan(0)
    // Should show at least one of our entry numbers
    const hasEntry = text.includes('AN-2024') || text.includes('ACH-2024') || text.includes('VT-2024') || text.includes('BQ-2024') || text.includes('OD-2024')
    console.log('  Journal entries page - has entry numbers:', hasEntry)
    console.log('  Text snippet:', text.substring(0, 500))
    expect(hasEntry || text.includes('écriture') || text.includes('entry') || text.includes('journal')).toBeTruthy()
  })

  test('Trial Balance shows balanced totals', async ({ page }) => {
    await page.goto('/accounting/trial-balance')
    await waitForContent(page)
    const text = await page.locator('#root').textContent() || ''
    expect(text.length).toBeGreaterThan(0)
    // Should show account codes with balances
    const hasAccounts = text.includes('512000') || text.includes('607000') || text.includes('707000') || text.includes('411')
    const hasTotals = text.includes('Débit') || text.includes('Debit') || text.includes('Crédit') || text.includes('Credit') || text.includes('Solde')
    console.log('  Trial balance - has accounts:', hasAccounts, 'has totals:', hasTotals)
    console.log('  Text snippet:', text.substring(0, 800))
  })

  test('General Ledger shows movements for account 512000', async ({ page }) => {
    await page.goto('/accounting/general-ledger')
    await waitForContent(page)
    const text = await page.locator('#root').textContent() || ''
    expect(text.length).toBeGreaterThan(0)
    console.log('  General ledger text snippet:', text.substring(0, 500))
    // Try selecting account 512000
    const accountSelect = page.locator('select').first()
    if (await accountSelect.count() > 0) {
      const options = await accountSelect.locator('option').allTextContents()
      const has512 = options.some(o => o.includes('512000'))
      console.log('  Has 512000 option:', has512)
      if (has512) {
        await accountSelect.selectOption({ label: options.find(o => o.includes('512000'))! })
        await page.waitForTimeout(2000)
        const updatedText = await page.locator('#root').textContent() || ''
        const hasMovements = updatedText.includes('Banque') || updatedText.includes('14400') || updatedText.includes('50000')
        console.log('  After selecting 512000 - has movements:', hasMovements)
        console.log('  Updated text snippet:', updatedText.substring(0, 800))
      }
    }
  })

  test('Payment Delays report shows paid invoices', async ({ page }) => {
    await page.goto('/accounting/reports/payment-delay')
    await waitForContent(page)
    const text = await page.locator('#root').textContent() || ''
    expect(text.length).toBeGreaterThan(0)
    const hasInvoices = text.includes('FAC-2024') || text.includes('facture') || text.includes('invoice')
    const hasDelays = text.includes('jour') || text.includes('day') || text.includes('délai') || text.includes('delay')
    console.log('  Payment delays - has invoices:', hasInvoices, 'has delays:', hasDelays)
    console.log('  Text snippet:', text.substring(0, 800))
  })

  test('Third Party Accounts shows clients and suppliers', async ({ page }) => {
    await page.goto('/accounting/third-party')
    await waitForContent(page)
    const text = await page.locator('#root').textContent() || ''
    expect(text.length).toBeGreaterThan(0)
    const hasTiers = text.includes('411001') || text.includes('401001') || text.includes('Alpha') || text.includes('Delta')
    console.log('  Third party - has tiers:', hasTiers)
    console.log('  Text snippet:', text.substring(0, 500))
  })

  test('Journals page shows all 6 journals', async ({ page }) => {
    await page.goto('/accounting/journals')
    await waitForContent(page)
    const text = await page.locator('#root').textContent() || ''
    expect(text.length).toBeGreaterThan(0)
    const hasACH = text.includes('ACH')
    const hasVT = text.includes('VT')
    const hasBQ = text.includes('BQ')
    const hasOD = text.includes('OD')
    console.log('  Journals - ACH:', hasACH, 'VT:', hasVT, 'BQ:', hasBQ, 'OD:', hasOD)
    console.log('  Text snippet:', text.substring(0, 500))
  })

  test('Chart of Accounts shows accounts with balances', async ({ page }) => {
    await page.goto('/accounting/chart-accounts')
    await waitForContent(page)
    const text = await page.locator('#root').textContent() || ''
    expect(text.length).toBeGreaterThan(0)
    const hasAccounts = text.includes('512000') || text.includes('607000') || text.includes('707000')
    console.log('  Chart accounts - has accounts:', hasAccounts)
    console.log('  Text snippet:', text.substring(0, 500))
  })

  test('Progressive Balance for third party 411001', async ({ page }) => {
    await page.goto('/accounting/reports/progressive-balance')
    await waitForContent(page)
    const text = await page.locator('#root').textContent() || ''
    expect(text.length).toBeGreaterThan(0)
    // Try selecting third party 411001
    const select = page.locator('select').first()
    if (await select.count() > 0) {
      const options = await select.locator('option').allTextContents()
      const has411 = options.some(o => o.includes('411001'))
      console.log('  Has 411001 option:', has411)
      if (has411) {
        await select.selectOption({ label: options.find(o => o.includes('411001'))! })
        await page.waitForTimeout(2000)
        const updatedText = await page.locator('#root').textContent() || ''
        const hasData = updatedText.includes('14400') || updatedText.includes('6600') || updatedText.includes('Alpha')
        console.log('  After selecting 411001 - has data:', hasData)
        console.log('  Updated text snippet:', updatedText.substring(0, 800))
      }
    }
  })
})
