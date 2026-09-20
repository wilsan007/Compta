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
  reporter: 'html',
  use: {
    baseURL: 'http://localhost:5174',
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
