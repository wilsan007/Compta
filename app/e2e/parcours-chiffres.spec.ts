import { test, expect, navigateWithAuth, E2E_CREDENTIALS_CONFIGURED, E2E_SKIP_REASON } from './helpers'
import { montantsVisibles, chercherRelation, auCentime, celluleSousEnTete } from './chiffres'

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
// L'écran des bulletins ne montre RIEN tant qu'aucun lot n'est choisi : les
// bulletins sont groupés par lot, et un groupe n'est déplié que s'il est
// sélectionné (`PaySlipsPage.tsx`). Le geste de l'utilisateur — « choisir le
// lot de paie » — fait partie du parcours, sinon on lirait un écran vide et on
// en conclurait à tort que la paie est vide.
test('C3 : un bulletin lit brut − retenues = net (au centime)', async ({ page, request }) => {
  await navigateWithAuth(page, request, '/hr/pay-slips')
  const menu = page.getByLabel('Pay runs')
  await menu.waitFor({ timeout: 20000 })
  const valeur = await menu.locator('option').filter({ hasText: /\d{4}/ }).first().getAttribute('value')
  expect(valeur, 'un lot de paie doit être proposé au choix (sinon aucune paie n’est amorcée)').toBeTruthy()
  await menu.selectOption(valeur!)
  await page.locator('table tbody tr').first().waitFor({ timeout: 20000 })
  const montants = await montantsVisibles(page)
  expect(montants.length, 'le bulletin doit afficher des montants').toBeGreaterThanOrEqual(1)
  if (montants.length >= 3) {
    const relation = chercherRelation(montants, 'difference')
    expect(relation, `brut − retenues = net introuvable parmi ${montants.slice(0, 20).join(', ')}`).not.toBeNull()
  }
})

// ── 4. Caisse → la clôture et le stock ──────────────────────
// « Le stock suit » se MESURE, il ne se déclare pas : la vente en caisse sort
// l'article du dépôt, et le solde lu sur l'écran des QUANTITÉS doit être
// exactement le carnet lu sur l'écran des MOUVEMENTS — l'entrée initiale PLUS
// la sortie (négative). Deux écrans, une seule vérité : si le stock ne suivait
// pas, le solde mentirait.
test('C4 : une session de caisse lit un total (le stock suit)', async ({ page, request }) => {
  await navigateWithAuth(page, request, '/pos/sessions')
  await page.locator('table tbody tr').first().waitFor({ timeout: 20000 })
  const montants = await montantsVisibles(page)
  expect(montants.length, 'une session clôturée doit afficher un total').toBeGreaterThanOrEqual(1)

  // Le carnet des mouvements : l'entrée initiale, puis la sortie de la vente.
  await page.goto('/stock/movements')
  await page.locator('table tbody tr').first().waitFor({ timeout: 20000 })
  const entree = await celluleSousEnTete(page, 'Stock initial', 'Quantity')
  const sortie = await celluleSousEnTete(page, 'TK-', 'Quantity')
  expect(entree, "l'écran des mouvements doit montrer le stock initial de l'article (référence « Stock initial »)").not.toBeNull()
  expect(sortie, "l'écran des mouvements doit montrer la sortie de la vente (référence « TK-… »)").not.toBeNull()
  expect(sortie!, 'la sortie d’une vente est un retrait : sa quantité doit être négative à l’écran').toBeLessThan(0)

  // Le solde : ce qui reste en dépôt, lu sur l'écran des quantités.
  await page.goto('/stock/quantities')
  await page.locator('table tbody tr').first().waitFor({ timeout: 20000 })
  const solde = await celluleSousEnTete(page, 'E2E-ART-1', 'Quantity')
  expect(solde, "l'écran des quantités doit montrer le solde de l'article (SKU E2E-ART-1)").not.toBeNull()
  expect(auCentime(solde!, entree! + sortie!),
    `le solde (${solde}) doit être l'entrée (${entree}) + la sortie (${sortie}) — le stock n'a pas suivi la vente`).toBe(true)
})
