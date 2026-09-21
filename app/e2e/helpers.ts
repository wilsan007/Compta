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
export const TEST_EMAIL = process.env.E2E_TEST_EMAIL || 'test@test.com'
export const TEST_PASSWORD = process.env.E2E_TEST_PASSWORD || ''

// ------------------------------------------------------------
// Sans identifiants, l'application reste sur /login : les tests de route ne
// vérifient plus que l'écran de connexion, et passent au vert sans rien prouver.
// Les fichiers de test s'abstiennent explicitement dans ce cas.
// ------------------------------------------------------------
export const E2E_CREDENTIALS_CONFIGURED = Boolean(SUPABASE_KEY && TEST_PASSWORD)

export const E2E_SKIP_REASON =
  "Identifiants e2e absents (SUPABASE_KEY et E2E_TEST_PASSWORD). Sans eux l'application " +
  "reste sur /login : les tests porteraient sur l'écran de connexion, pas sur les routes visées."

/**
 * Échoue si la page est restée sur l'écran de connexion.
 * À appeler après chaque `login()` : une authentification silencieusement cassée
 * rendait auparavant toute la suite verte.
 */
export async function assertAuthenticated(page: Page) {
  const passwordField = page.locator('input[type="password"]')
  // L'application restaure la session de façon asynchrone : juste après une
  // navigation, elle peut afficher brièvement l'écran de connexion. On laisse
  // ce laps de temps se résorber — si l'authentification est réellement
  // cassée, le champ ne disparaît pas et le test échoue quand même.
  await passwordField.first().waitFor({ state: 'detached', timeout: 10000 }).catch(() => {})
  if (await passwordField.count() > 0) {
    throw new Error(
      `Session non authentifiée : ${page.url()} affiche l'écran de connexion. ` +
      `Le test porterait sur /login et non sur la route visée.`
    )
  }
}

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

/**
 * Échoue si l'application a renvoyé sur l'assistant de création de société.
 * Un compte sans société y est redirigé (`ProtectedRoute.tsx:49`) : la route
 * visée n'est alors jamais rendue, et un test qui se contente de lire du texte
 * passerait au vert contre l'assistant.
 */
export async function assertWorkspaceReady(page: Page) {
  if (new URL(page.url()).pathname.startsWith('/onboarding')) {
    throw new Error(
      `Le compte ${TEST_EMAIL} n'est rattaché à aucune société : l'application redirige ` +
      `vers /onboarding. Rattachez-le à une société contenant des données, sinon les tests ` +
      `porteraient sur l'assistant de création et non sur la route visée.`
    )
  }
}

/**
 * @deprecated Ne fonctionne pas : supabase-js v2 range la session dans
 * `localStorage` sous la clé `sb-<ref>-auth-token`, jamais dans des cookies
 * `sb-access-token` / `sb-refresh-token`. L'application ne les lisait donc
 * jamais et retombait sur /login — c'est ce qui rendait `business-flows.spec.ts`
 * incapable de s'authentifier, même avec des identifiants valides.
 * Conservé pour ne pas casser un import existant ; utiliser `loginViaUI`.
 */
export async function setAuthCookies(page: Page, session: AuthSession) {
  await page.context().addCookies([
    { name: 'sb-access-token', value: session.access_token, domain: 'localhost', path: '/' },
    { name: 'sb-refresh-token', value: session.refresh_token, domain: 'localhost', path: '/' },
  ])
}

/**
 * Connexion par le formulaire : c'est supabase-js lui-même qui persiste la
 * session, dans le format qu'il attend. Idempotent — ne refait rien si la
 * session est déjà établie dans ce contexte de navigation.
 */
export async function loginViaUI(page: Page) {
  await page.goto('/login')
  const passwordField = page.locator('input[type="password"]')
  // Déjà connecté : l'application ne sert pas le formulaire
  if (await passwordField.count() === 0) return

  await page.locator('input[type="email"]').waitFor({ state: 'visible', timeout: 15000 })
  await page.locator('input[type="email"]').fill(TEST_EMAIL)
  await passwordField.fill(TEST_PASSWORD)
  await page.locator('button[type="submit"]').click()
  await page.waitForURL((u) => !u.pathname.startsWith('/login'), { timeout: 20000 })
  await assertAuthenticated(page)

  // Chaque navigation des tests passe par `page.goto`, donc par un rechargement
  // complet : l'application relit alors la session dans `localStorage`, où
  // supabase-js la range sous `sb-<ref>-auth-token`. Tant que cette écriture
  // n'a pas eu lieu, le rechargement repart déconnecté et l'application renvoie
  // sur /login. En local l'écart est imperceptible ; sur un runner GitHub il
  // suffisait à faire échouer la suite. On attend donc la persistance réelle,
  // pas seulement la redirection à l'écran.
  await page.waitForFunction(
    () => {
      try {
        return Object.keys(window.localStorage).some((k) => /^sb-.+-auth-token$/.test(k))
      } catch {
        return false
      }
    },
    undefined,
    { timeout: 20000 },
  )
}

export async function navigateWithAuth(page: Page, _apiContext: APIRequestContext, path: string) {
  await loginViaUI(page)
  await page.goto(path)
  await page.waitForLoadState('domcontentloaded')
  await assertAuthenticated(page)
  await assertWorkspaceReady(page)
}

// Test fixture avec auth automatique
export const test = base.extend<{ authedPage: Page }>({
  // Le second argument est le callback de fixture Playwright (nommé `use` dans la doc) :
  // renommé pour ne pas être pris pour un hook React par le lint.
  authedPage: async ({ page, request }, provide) => {
    // Avant : un try/catch avalait toute erreur en `skip`. Une authentification
    // cassée devenait ainsi indiscernable d'une absence d'identifiants.
    test.skip(!E2E_CREDENTIALS_CONFIGURED, E2E_SKIP_REASON)
    await navigateWithAuth(page, request, '/dashboard')
    await provide(page)
  },
})

export { expect }
