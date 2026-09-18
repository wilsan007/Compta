// LOT7-01 : `playwright` n'est pas déclaré dans package.json — l'import ne marchait
// que par dépendance transitive de `@playwright/test`, qui ré-exporte `chromium`.
import { chromium } from '@playwright/test';

const BASE = 'http://localhost:5173';
const OUT = '/Users/awalehosman/Desktop/Projet Saas/compta/app/public/screenshots';

async function dismissWelcome(page: any) {
  try {
    const closeBtn = page.locator('button:has-text("×"), button:has-text("Close"), button:has-text("Fermer"), button:has-text("Skip"), button:has-text("Passer"), [aria-label="close"], [aria-label="Close"]').first();
    if (await closeBtn.isVisible({ timeout: 2000 })) {
      await closeBtn.click();
      await page.waitForTimeout(1000);
      console.log('  Dismissed welcome modal');
    }
  } catch {}
  await page.keyboard.press('Escape');
  await page.waitForTimeout(500);
  try {
    const overlay = page.locator('.fixed.inset-0, .modal-overlay, [class*="overlay"]').first();
    if (await overlay.isVisible({ timeout: 1000 })) {
      await overlay.click({ position: { x: 10, y: 10 } });
      await page.waitForTimeout(500);
    }
  } catch {}
}

async function screenshot(page: any, url: string, name: string) {
  console.log(`Screenshot: ${name}...`);
  await page.goto(`${BASE}${url}`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(3000);
  await dismissWelcome(page);
  await page.waitForTimeout(1000);
  await page.screenshot({ path: `${OUT}/${name}.png`, fullPage: false });
  console.log(`  -> ${name}.png`);
}

async function main() {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await context.newPage();

  console.log('Navigating to login...');
  await page.goto(`${BASE}/login`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(2000);

  const emailInput = page.locator('input[type="email"]');
  const passwordInput = page.locator('input[type="password"]');
  await emailInput.fill('admin@demo.dj');
  await passwordInput.fill('Admin123!');
  
  const submitBtn = page.locator('button[type="submit"]');
  await submitBtn.click();
  
  console.log('Waiting for login...');
  try {
    await page.waitForURL('**/home**', { timeout: 15000 });
    console.log('Login successful, URL:', page.url());
  } catch {
    try {
      await page.waitForURL('**/select-tenant**', { timeout: 5000 });
      console.log('At tenant selection...');
      await page.waitForTimeout(2000);
      const tenantBtn = page.locator('button, a').filter({ hasText: /test|entreprise/i }).first();
      if (await tenantBtn.isVisible()) {
        await tenantBtn.click();
        await page.waitForTimeout(3000);
      }
    } catch {
      console.log('Login may have failed. URL:', page.url());
      await page.screenshot({ path: `${OUT}/debug-login.png` });
    }
  }
  await page.waitForTimeout(3000);
  await dismissWelcome(page);
  console.log('Current URL:', page.url());

  // 1. Comptabilité - Journal Entries table
  await screenshot(page, '/accounting/journal-entries', 'comptabilite');
  // 2. Comptabilité - Saisie form in action
  await screenshot(page, '/accounting/treatment/journal-entry', 'comptabilite-saisie');
  // 3. Commercial - Sales Orders table
  await screenshot(page, '/sales/orders', 'commercial');
  // 4. Commercial - Invoices table
  await screenshot(page, '/sales/invoices', 'commercial-factures');
  // 5. Project Management - Kanban
  await screenshot(page, '/project-management/kanban', 'projet-kanban');
  // 6. Project Management - Table view
  await screenshot(page, '/project-management/tasks', 'projet-tableau');
  // 7. Production - Manufacturing Orders table
  await screenshot(page, '/stock/manufacturing', 'production');
  // 8. Production - Dashboard
  await screenshot(page, '/production/dashboard', 'production-dashboard');

  await browser.close();
  console.log('Done! All screenshots saved to:', OUT);
}

main().catch(e => { console.error(e); process.exit(1); });
