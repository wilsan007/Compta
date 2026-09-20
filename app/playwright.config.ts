import { defineConfig, devices } from '@playwright/test'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

// Les tests lisent SUPABASE_KEY / E2E_TEST_* dans l'environnement. En local la
// clé publiable est déjà dans .env : sans ce chargement, la suite s'abstenait
// alors que de quoi tourner était sur le disque. Aucune dépendance ajoutée, et
// une variable déjà définie dans l'environnement garde la main.
const configDir = path.dirname(fileURLToPath(import.meta.url))
for (const file of ['.env', '.env.local']) {
  const full = path.resolve(configDir, file)
  if (!fs.existsSync(full)) continue
  for (const line of fs.readFileSync(full, 'utf-8').split('\n')) {
    const match = /^\s*([A-Z0-9_]+)\s*=\s*(.*)$/.exec(line)
    if (!match) continue
    const key = match[1]
    if (process.env[key] !== undefined) continue
    process.env[key] = match[2].trim().replace(/^["']|["']$/g, '')
  }
}

export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  // Playwright applique 30 s par test par défaut. Les attentes de cette suite
  // vont jusqu'à 30 s à elles seules — sur un runner GitHub qui interroge
  // Supabase à distance, le budget était épuisé avant même que l'assertion soit
  // évaluée, et les pages lentes échouaient sur un #root encore vide.
  // Constaté au premier passage réel de la CI le 20/09/2026.
  timeout: process.env.CI ? 120_000 : 60_000,
  expect: { timeout: process.env.CI ? 20_000 : 10_000 },
  reporter: 'html',
  use: {
    baseURL: 'http://localhost:5174',
    // `main.tsx` enregistre un service worker (`public/sw.js`) qui met en cache
    // la coquille de l'application. Un test peut alors recevoir une page servie
    // depuis le cache d'un test précédent. Les tests ne portent pas sur le mode
    // hors ligne : on l'empêche de s'enregistrer, pour que chaque test parte
    // d'un état propre.
    serviceWorkers: 'block',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'], channel: process.env.PW_CHANNEL },
    },
  ],
  webServer: {
    command: 'npm run dev -- --port 5174',
    url: 'http://localhost:5174',
    reuseExistingServer: !process.env.CI,
    timeout: 30000,
  },
})
