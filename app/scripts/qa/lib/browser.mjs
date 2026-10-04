// ============================================================
// qa/lib/browser.mjs — le lancement du navigateur, en un seul endroit
//
// Playwright exige le build exact de Chromium qu'il embarque ; si la machine
// n'a pas ce build (mise à jour de Playwright sans téléchargement), le
// navigateur du système fait le même travail — c'est ce que la configuration
// Playwright du dépôt fait déjà avec PW_CHANNEL.
// ============================================================
import { chromium } from '@playwright/test'

export async function launchBrowser() {
  const channel = process.env.QA_BROWSER_CHANNEL
  if (channel) return chromium.launch({ channel })
  try {
    return await chromium.launch()
  } catch (e) {
    const msg = String(e?.message || e)
    if (!/Executable doesn't exist/.test(msg)) throw e
    console.log('[navigateur] build Playwright absent — repli sur le Chrome du système')
    return chromium.launch({ channel: 'chrome' })
  }
}
