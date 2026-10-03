import { test, expect, Page } from '@playwright/test'
import { loginViaUI, assertAuthenticated, E2E_CREDENTIALS_CONFIGURED, E2E_SKIP_REASON, assertWorkspaceReady } from './helpers'

// ============================================================
// E1 (recette /qa du 29/09/2026) — ach-001 et stk-015
//
// Les fenêtres de création étaient plus hautes que l'écran et RIEN ne défilait :
//   ach-001 : « Créer » du fournisseur à top = 804 px pour 720 px de haut ;
//   stk-015 : conteneur de 781 px, `getBoundingClientRect()` de « Créer »
//             à top = 720 ; le clic expirait (« Timeout 5000ms »).
// Sur un portable courant, créer un fournisseur ou une immobilisation était
// donc impossible — il fallait agrandir la fenêtre à 1280×1000.
//
// Contrat vérifié ici, à 1280×720 : le bouton qui valide est DANS l'écran, et il
// répond au clic. Échap et le focus piégé sont couverts par `Modal` (LOT7-07).
// ============================================================
test.use({ locale: 'fr-FR' })
test.describe.configure({ mode: 'serial' })
test.skip(!E2E_CREDENTIALS_CONFIGURED, E2E_SKIP_REASON)

// Deux réglages de départ, avant toute navigation :
//  - le navigateur de test est en en-US : sans `i18nextLng`, l'application
//    démarre en anglais et les libellés attendus (« Nouveau fournisseur »,
//    « Créer ») n'existent pas. La recette du 29/09 s'est faite en français.
//  - le guide d'accueil s'ouvre sur un compte qui ne l'a jamais fermé et son
//    fond intercepte les clics (Layout.tsx:103, `compta-onboarded`) : on part
//    d'une page déjà « vue », comme un utilisateur qui revient.
async function preparerPage(page: Page) {
  await page.addInitScript(() => {
    window.localStorage.setItem('i18nextLng', 'fr')
    window.localStorage.setItem('compta-onboarded', 'true')
  })
}

// Le guide d'accueil s'ouvre à la première connexion d'un compte et son fond
// intercepte les clics de la page : sans le fermer, le test échoue sur un
// élément « intercepté » et non sur ce qu'il veut mesurer.
async function fermerLeGuide(page: Page) {
  for (const nom of ['Passer', 'Fermer', 'Ignorer']) {
    const bouton = page.getByRole('button', { name: nom, exact: true })
    if (await bouton.count() > 0) {
      await bouton.first().click().catch(() => {})
      await page.waitForTimeout(300)
      return
    }
  }
}

async function verifierFenetre(page: Page, cible: { route: string; ouvrir: string; valider: string }) {
  await page.goto(cible.route)
  await assertAuthenticated(page)
  await fermerLeGuide(page)

  await page.getByRole('button', { name: cible.ouvrir }).first().click()

  // Le bouton de validation est cherché dans le formulaire (le même repère avant
  // et après correctif : la fenêtre n'avait pas encore `role="dialog"`).
  const valider = page.locator('form').getByRole('button', { name: cible.valider }).last()
  await valider.waitFor({ state: 'visible' })

  const boite = await valider.boundingBox()
  const fenetre = page.viewportSize()!
  expect(boite, `« ${cible.valider} » doit exister à l'écran`).not.toBeNull()
  expect(boite!.y, `« ${cible.valider} » commence ${boite!.y} px du haut de l'écran`).toBeGreaterThanOrEqual(0)
  expect(
    boite!.y + boite!.height,
    `« ${cible.valider} » finit à ${Math.round(boite!.y + boite!.height)} px pour un écran de ${fenetre.height} px`,
  ).toBeLessThanOrEqual(fenetre.height)

  // Et il doit répondre au clic sans défilement préalable : c'est l'action qui
  // échouait à la recette.
  await valider.click({ timeout: 2000 })
}

// Les deux dimensions demandées par le plan : le portable courant (1280×720,
// celle de la recette) et un téléphone (375×812). Le contrat est le même.
test.describe('à 1280×720', () => {
  test.use({ viewport: { width: 1280, height: 720 } })

  test('ach-001 : « Créer » du fournisseur est atteignable', async ({ page }) => {
    await preparerPage(page)
    await loginViaUI(page)
    await assertWorkspaceReady(page)
    await verifierFenetre(page, { route: '/purchases/suppliers', ouvrir: 'Nouveau fournisseur', valider: 'Créer' })
  })

  test('stk-015 : « Créer » de l’immobilisation est atteignable', async ({ page }) => {
    await preparerPage(page)
    await loginViaUI(page)
    await assertWorkspaceReady(page)
    await verifierFenetre(page, { route: '/accounting/fixed-assets', ouvrir: 'Nouvelle immobilisation', valider: 'Créer' })
  })
})

test.describe('à 375×812', () => {
  test.use({ viewport: { width: 375, height: 812 } })

  test('ach-001 : « Créer » du fournisseur est atteignable', async ({ page }) => {
    await preparerPage(page)
    await loginViaUI(page)
    await assertWorkspaceReady(page)
    await verifierFenetre(page, { route: '/purchases/suppliers', ouvrir: 'Nouveau fournisseur', valider: 'Créer' })
  })

  test('stk-015 : « Créer » de l’immobilisation est atteignable', async ({ page }) => {
    await preparerPage(page)
    await loginViaUI(page)
    await assertWorkspaceReady(page)
    await verifierFenetre(page, { route: '/accounting/fixed-assets', ouvrir: 'Nouvelle immobilisation', valider: 'Créer' })
  })
})
