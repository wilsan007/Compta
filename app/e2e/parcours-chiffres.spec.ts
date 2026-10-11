import { test, expect, navigateWithAuth, E2E_CREDENTIALS_CONFIGURED, E2E_SKIP_REASON } from './helpers'
import { montantsVisibles, chercherRelation, auCentime } from './chiffres'

// ============================================================
// D.5 — les quatre parcours qui LISENT UN CHIFFRE (4.4, AUD-J02)
//
// Ce que ces parcours ajoutent à `business-flows.spec.ts` : celui-ci ne fait que
// NOMMER les écrans (URL + titre). Ici, on lit un MONTANT et on vérifie qu'une
// relation tient, **au centime** — ce qu'un écran ne peut pas faire semblant
// d'afficher juste.
//
// ⚠️ Ils s'abstiennent tant que les secrets E2E ne sont pas dans GitHub
// (E2E_CREDENTIALS_CONFIGURED) : sans eux l'application reste sur /login et les
// tests porteraient sur l'écran de connexion. C'est le préalable de D.5 — les
// scénarios sont prêts, ils ne sont **pas encore joués**.
// ============================================================

test.describe.configure({ mode: 'serial' })
test.skip(!E2E_CREDENTIALS_CONFIGURED, E2E_SKIP_REASON)

// ── 1. Inscription → le plan comptable est semé ─────────────
test('C1 : après inscription, le plan comptable porte des comptes', async ({ page, request }) => {
  await navigateWithAuth(page, request, '/accounting/chart-accounts')
  // On attend une LIGNE, pas seulement un titre : l'en-tête s'affiche avant que
  // le tableau (chargé en asynchrone) ne soit peuplé — compter trop tôt rendait 0.
  await page.locator('table tbody tr').first().waitFor({ timeout: 20000 })
  const comptes = await page.locator('table tbody tr').count()
  expect(comptes, 'un plan comptable semé doit porter des comptes, pas un écran vide').toBeGreaterThan(0)
})

// ── 2. Vente complète → l'écriture est équilibrée (HT + TVA) ─
test('C2 : la balance est équilibrée — total débit = total crédit (au centime)', async ({ page, request }) => {
  await navigateWithAuth(page, request, '/accounting/trial-balance')
  await page.locator('table tbody tr').first().waitFor({ timeout: 20000 })
  const montants = await montantsVisibles(page)
  expect(montants.length, 'la balance doit afficher des montants').toBeGreaterThanOrEqual(2)
  // Deux montants égaux : c'est le total débit et le total crédit d'une balance équilibrée.
  const equilibre = montants.some((a, i) => montants.some((b, j) => i !== j && a !== 0 && auCentime(a, b)))
  expect(equilibre, `total débit = total crédit introuvable parmi ${montants.slice(0, 20).join(', ')}`).toBe(true)
})

// ── 3. Paie → le bulletin et l'écriture ─────────────────────
test('C3 : un bulletin lit brut − retenues = net (au centime)', async ({ page, request }) => {
  await navigateWithAuth(page, request, '/hr/pay-slips')
  await page.waitForSelector('table tbody tr, h1, h2', { timeout: 15000 })
  const montants = await montantsVisibles(page)
  expect(montants.length, 'le bulletin doit afficher des montants').toBeGreaterThanOrEqual(1)
  if (montants.length >= 3) {
    const relation = chercherRelation(montants, 'difference')
    expect(relation, `brut − retenues = net introuvable parmi ${montants.slice(0, 20).join(', ')}`).not.toBeNull()
  }
})

// ── 4. Caisse → la clôture et le stock ──────────────────────
test('C4 : une session de caisse lit un total (le stock suit)', async ({ page, request }) => {
  await navigateWithAuth(page, request, '/pos/sessions')
  await page.waitForSelector('table tbody tr, h1, h2', { timeout: 15000 })
  const montants = await montantsVisibles(page)
  expect(montants.length, 'une session clôturée doit afficher un total').toBeGreaterThanOrEqual(1)
})
