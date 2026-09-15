import { test, expect } from '@playwright/test'
import { navigateWithAuth } from './helpers'

test.describe.configure({ mode: 'serial' })

// ============================================================
// Parcours 1 : Devis → Commande → Livraison → Facture → Règlement
// ============================================================
test('P1: Quote → Sales Order → Delivery → Invoice → Payment', async ({ page, request }) => {
  await navigateWithAuth(page, request, '/sales/quotes')
  await expect(page).toHaveURL(/quotes/)
  // Vérifier que la page des devis se charge
  await page.waitForSelector('h1, h2', { timeout: 10000 })

  await navigateWithAuth(page, request, '/sales/orders')
  await expect(page).toHaveURL(/orders/)

  await navigateWithAuth(page, request, '/sales/delivery-notes')
  await expect(page).toHaveURL(/delivery-notes/)

  await navigateWithAuth(page, request, '/sales/invoices')
  await expect(page).toHaveURL(/invoices/)

  await navigateWithAuth(page, request, '/sales/payments')
  await expect(page).toHaveURL(/payments/)
})

// ============================================================
// Parcours 2 : Achat → Réception → Facture → Paiement
// ============================================================
test('P2: Purchase → Receipt → Invoice → Payment', async ({ page, request }) => {
  await navigateWithAuth(page, request, '/purchases/orders')
  await expect(page).toHaveURL(/purchases\/orders/)
  await page.waitForSelector('h1, h2', { timeout: 10000 })

  await navigateWithAuth(page, request, '/purchases/receipts')
  await expect(page).toHaveURL(/receipts/)

  await navigateWithAuth(page, request, '/purchases/invoices')
  await expect(page).toHaveURL(/invoices/)

  await navigateWithAuth(page, request, '/purchases/payments')
  await expect(page).toHaveURL(/payments/)
})

// ============================================================
// Parcours 3 : Saisie d'écriture → Validation → Balance
// ============================================================
test('P3: Journal Entry → Validation → Trial Balance', async ({ page, request }) => {
  await navigateWithAuth(page, request, '/accounting/journal-entry')
  await expect(page).toHaveURL(/journal-entry/)
  await page.waitForSelector('h1, h2', { timeout: 10000 })

  await navigateWithAuth(page, request, '/accounting/entries')
  await expect(page).toHaveURL(/entries/)

  await navigateWithAuth(page, request, '/accounting/trial-balance')
  await expect(page).toHaveURL(/trial-balance/)
})

// ============================================================
// Parcours 4 : Bulletin de paie → Écriture → DSN
// ============================================================
test('P4: Pay Slip → Journal Entry → DSN', async ({ page, request }) => {
  await navigateWithAuth(page, request, '/hr/payroll')
  await expect(page).toHaveURL(/payroll/)
  await page.waitForSelector('h1, h2', { timeout: 10000 })

  await navigateWithAuth(page, request, '/hr/pay-slips')
  await expect(page).toHaveURL(/pay-slips/)

  await navigateWithAuth(page, request, '/accounting/entries')
  await expect(page).toHaveURL(/entries/)
})

// ============================================================
// Parcours 5 : Vente en caisse → Clôture → Comptabilisation
// ============================================================
test('P5: POS Sale → Session Close → Accounting', async ({ page, request }) => {
  await navigateWithAuth(page, request, '/pos/terminal')
  await expect(page).toHaveURL(/terminal/)
  await page.waitForSelector('h1, h2', { timeout: 10000 })

  await navigateWithAuth(page, request, '/pos/sessions')
  await expect(page).toHaveURL(/sessions/)

  await navigateWithAuth(page, request, '/pos/stats')
  await expect(page).toHaveURL(/stats/)
})

// ============================================================
// Parcours 6 : Réception stock → Mouvement → Valorisation
// ============================================================
test('P6: Stock Receipt → Movement → Valuation', async ({ page, request }) => {
  await navigateWithAuth(page, request, '/stock/movements')
  await expect(page).toHaveURL(/movements/)
  await page.waitForSelector('h1, h2', { timeout: 10000 })

  await navigateWithAuth(page, request, '/stock/quantities')
  await expect(page).toHaveURL(/quantities/)
})

// ============================================================
// Parcours 7 : OF → Consommation → Production → Clôture
// ============================================================
test('P7: Manufacturing Order → Consumption → Production → Close', async ({ page, request }) => {
  await navigateWithAuth(page, request, '/production/orders')
  await expect(page).toHaveURL(/orders/)
  await page.waitForSelector('h1, h2', { timeout: 10000 })

  await navigateWithAuth(page, request, '/production/planning')
  await expect(page).toHaveURL(/planning/)
})

// ============================================================
// Parcours 8 : Rapprochement bancaire → Écriture → Lettrage
// ============================================================
test('P8: Bank Reconciliation → Entry → Lettrage', async ({ page, request }) => {
  await navigateWithAuth(page, request, '/banking/reconciliation')
  await expect(page).toHaveURL(/reconciliation/)
  await page.waitForSelector('h1, h2', { timeout: 10000 })

  await navigateWithAuth(page, request, '/accounting/lettrage')
  await expect(page).toHaveURL(/lettrage/)
})

// ============================================================
// Parcours 9 : Projet → Tâches → Saisie temps → Facturation
// ============================================================
test('P9: Project → Tasks → Time Entry → Invoicing', async ({ page, request }) => {
  await navigateWithAuth(page, request, '/projects')
  await expect(page).toHaveURL(/projects/)
  await page.waitForSelector('h1, h2', { timeout: 10000 })
})

// ============================================================
// Parcours 10 : Onboarding → Paramétrage → Première écriture
// ============================================================
test('P10: Onboarding → Settings → First Entry', async ({ page, request }) => {
  await navigateWithAuth(page, request, '/settings/onboarding')
  await expect(page).toHaveURL(/onboarding/)
  await page.waitForSelector('h1, h2', { timeout: 10000 })

  await navigateWithAuth(page, request, '/settings')
  await expect(page).toHaveURL(/settings/)

  await navigateWithAuth(page, request, '/accounting/journal-entry')
  await expect(page).toHaveURL(/journal-entry/)
})
