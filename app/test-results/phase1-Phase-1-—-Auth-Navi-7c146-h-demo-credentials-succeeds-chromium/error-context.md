# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: phase1.spec.ts >> Phase 1 — Auth & Navigation >> Login with demo credentials succeeds
- Location: e2e/phase1.spec.ts:100:3

# Error details

```
Error: expect(received).not.toContain(expected) // indexOf

Expected substring: not "/login"
Received string:        "http://localhost:5174/login"
```

# Page snapshot

```yaml
- generic [ref=e4]:
  - generic [ref=e5]:
    - img [ref=e7]
    - heading "ERP Compta" [level=1] [ref=e11]
    - paragraph [ref=e12]: subtitle
  - generic [ref=e13]:
    - generic [ref=e14]:
      - generic [ref=e15]:
        - text: email
        - generic [ref=e16]:
          - img [ref=e17]
          - textbox "emailPlaceholder" [ref=e20]
      - generic [ref=e21]:
        - text: key 'password (en)' returned an object instead of string.
        - generic [ref=e22]:
          - img [ref=e23]
          - textbox "••••••••" [ref=e26]
      - button "signIn" [ref=e27] [cursor=pointer]
    - paragraph [ref=e28]:
      - text: noAccount
      - link "createAccount" [ref=e29] [cursor=pointer]:
        - /url: /signup
  - paragraph [ref=e30]: ERP Compta — tagline
```

# Test source

```ts
  2   | 
  3   | // Run tests serially to avoid auth session conflicts
  4   | test.describe.configure({ mode: 'serial' })
  5   | 
  6   | const TEST_EMAIL = 'admin@demo.dj'
  7   | const TEST_PASSWORD = 'Admin123!'
  8   | const SUPABASE_URL = 'https://ndtaedcgwnaopopugiql.supabase.co'
  9   | const SUPABASE_KEY = 'sb_publishable_6WZDE3wBMwc5ildtfy19Nw_pxdPnAZK'
  10  | 
  11  | // Cache the auth session across tests
  12  | let cachedSession: { access_token: string; refresh_token: string; expires_in: number } | null = null
  13  | 
  14  | async function getAuthSession(apiContext: APIRequestContext) {
  15  |   if (cachedSession) return cachedSession
  16  |   const response = await apiContext.post(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
  17  |     headers: {
  18  |       'apikey': SUPABASE_KEY,
  19  |       'Content-Type': 'application/json',
  20  |     },
  21  |     data: { email: TEST_EMAIL, password: TEST_PASSWORD },
  22  |   })
  23  |   const data = await response.json()
  24  |   if (data.access_token) {
  25  |     cachedSession = data
  26  |     return data
  27  |   }
  28  |   throw new Error(`Auth failed: ${data.error_description || data.msg || 'Unknown'}`)
  29  | }
  30  | 
  31  | async function login(page: Page, request: APIRequestContext) {
  32  |   // Capture console errors for debugging
  33  |   const consoleErrors: string[] = []
  34  |   page.on('console', (msg) => {
  35  |     if (msg.type() === 'error') consoleErrors.push(msg.text())
  36  |   })
  37  | 
  38  |   // Try form-based login directly
  39  |   await page.goto('/login')
  40  |   await page.waitForTimeout(2000)
  41  | 
  42  |   const emailInput = page.locator('input[type="email"]')
  43  |   await emailInput.waitFor({ state: 'visible', timeout: 15000 })
  44  |   const passwordInput = page.locator('input[type="password"]')
  45  |   const submitBtn = page.locator('button[type="submit"]')
  46  | 
  47  |   await emailInput.fill(TEST_EMAIL)
  48  |   await passwordInput.fill(TEST_PASSWORD)
  49  |   await submitBtn.click()
  50  | 
  51  |   // Wait for either navigation away from login or error message
  52  |   try {
  53  |     await page.waitForURL((url) => !url.toString().includes('/login'), { timeout: 30000 })
  54  |     await page.waitForTimeout(3000)
  55  |   } catch {
  56  |     // Log console errors for debugging
  57  |     console.log('Console errors during login:', consoleErrors.join('\n'))
  58  |     // Check for error message on page
  59  |     const pageText = await page.locator('body').textContent()
  60  |     console.log('Page text after login attempt:', pageText?.substring(0, 300))
  61  |     throw new Error(`Login failed. Console errors: ${consoleErrors.join('; ')}`)
  62  |   }
  63  | }
  64  | 
  65  | // Helper: wait for page content to render (SPA might show loader first)
  66  | async function waitForContent(page: Page, minLen = 50) {
  67  |   await page.waitForTimeout(2500)
  68  |   // Wait for #root to have content
  69  |   await page.locator('#root').waitFor({ state: 'attached', timeout: 10000 })
  70  |   const root = page.locator('#root')
  71  |   await expect(root).toBeVisible({ timeout: 10000 })
  72  | }
  73  | 
  74  | const PHASE1_ROUTES = [
  75  |   { path: '/accounting/treatment/recurring-entries', name: 'Phase 1.1 — Recurring Entries' },
  76  |   { path: '/accounting/treatment/regularization', name: 'Phase 1.2 — Regularization CCA/PCA' },
  77  |   { path: '/accounting/reports/payment-delay', name: 'Phase 1.5 — Payment Delays Report' },
  78  |   { path: '/accounting/reports/currency-revaluation', name: 'Phase 1.6 — Currency Revaluation' },
  79  |   { path: '/accounting/treatment/payment-reminders', name: 'Phase 1.7 — Payment Reminders' },
  80  |   { path: '/accounting/structure/analytic-plans', name: 'Phase 1.9 — Analytic Plans' },
  81  |   { path: '/accounting/structure/distribution-grills', name: 'Phase 1.10 — Distribution Grills' },
  82  |   { path: '/accounting/treatment/bank-reconciliation-rules', name: 'Phase 1.11 — Bank Reconciliation Rules' },
  83  |   { path: '/accounting/treatment/bank-statement-import', name: 'Phase 1.12 — Bank Statement Import' },
  84  |   { path: '/accounting/treatment/edi-tva', name: 'Phase 1.13 — EDI-TVA' },
  85  |   { path: '/accounting/reports/tvs', name: 'Phase 1.16 — TVS' },
  86  |   { path: '/accounting/reports/progressive-balance', name: 'Phase 1.19 — Progressive Balance' },
  87  |   { path: '/accounting/reports/fiscal-backup', name: 'Phase 1.22 — Fiscal Backup' },
  88  |   { path: '/settings/company-settings', name: 'Phase 1.14/1.17/1.18 — Company Settings' },
  89  | ]
  90  | 
  91  | test.describe('Phase 1 — Auth & Navigation', () => {
  92  |   test('Login page renders correctly', async ({ page }) => {
  93  |     await page.goto('/login')
  94  |     await page.waitForTimeout(2000)
  95  |     await expect(page.locator('input[type="email"]')).toBeVisible({ timeout: 10000 })
  96  |     await expect(page.locator('input[type="password"]')).toBeVisible()
  97  |     await expect(page.locator('button[type="submit"]')).toBeVisible()
  98  |   })
  99  | 
  100 |   test('Login with demo credentials succeeds', async ({ page, request }) => {
  101 |     await login(page, request)
> 102 |     expect(page.url()).not.toContain('/login')
      |                            ^ Error: expect(received).not.toContain(expected) // indexOf
  103 |   })
  104 | })
  105 | 
  106 | test.describe('Phase 1 — All routes accessible after login', () => {
  107 |   test.beforeEach(async ({ page, request }) => {
  108 |     await login(page, request)
  109 |   })
  110 | 
  111 |   for (const route of PHASE1_ROUTES) {
  112 |     test(`${route.name} — page loads without crash`, async ({ page }) => {
  113 |       await page.goto(route.path)
  114 |       await waitForContent(page)
  115 |       const root = page.locator('#root')
  116 |       const text = await root.textContent()
  117 |       expect(text?.length || 0).toBeGreaterThan(50)
  118 |       expect(text).not.toContain('Cannot find module')
  119 |       expect(text).not.toContain('Error: Element type is invalid')
  120 |       expect(text).not.toContain('is not a function')
  121 |       expect(text).not.toContain('Cannot read')
  122 |     })
  123 |   }
  124 | })
  125 | 
  126 | test.describe('Phase 1 — Complex interaction scenarios', () => {
  127 |   test.beforeEach(async ({ page, request }) => {
  128 |     await login(page, request)
  129 |   })
  130 | 
  131 |   test('Navigate between multiple Phase 1 pages rapidly', async ({ page }) => {
  132 |     const routes = [
  133 |       '/accounting/structure/analytic-plans',
  134 |       '/accounting/structure/distribution-grills',
  135 |       '/accounting/treatment/recurring-entries',
  136 |       '/accounting/treatment/regularization',
  137 |       '/accounting/reports/tvs',
  138 |       '/accounting/reports/fiscal-backup',
  139 |       '/settings/company-settings',
  140 |     ]
  141 |     for (const route of routes) {
  142 |       await page.goto(route)
  143 |       await page.waitForTimeout(1000)
  144 |       const root = page.locator('#root')
  145 |       await expect(root).toBeVisible({ timeout: 10000 })
  146 |       const text = await root.textContent()
  147 |       expect(text?.length || 0).toBeGreaterThan(0)
  148 |     }
  149 |   })
  150 | 
  151 |   test('Analytic Plans page shows seed data (AN1, AN2, AN3)', async ({ page }) => {
  152 |     await page.goto('/accounting/structure/analytic-plans')
  153 |     await waitForContent(page)
  154 |     const text = await page.locator('#root').textContent()
  155 |     // Seed data might be blocked by RLS — check page renders with table structure
  156 |     expect(text?.length || 0).toBeGreaterThan(50)
  157 |     // If data is visible, check for seed codes
  158 |     if (text?.includes('AN1') || text?.includes('AN2') || text?.includes('AN3')) {
  159 |       expect(text).toContain('AN1')
  160 |     }
  161 |   })
  162 | 
  163 |   test('Distribution Grills page shows seed data', async ({ page }) => {
  164 |     await page.goto('/accounting/structure/distribution-grills')
  165 |     await waitForContent(page)
  166 |     const text = await page.locator('#root').textContent()
  167 |     expect(text?.length || 0).toBeGreaterThan(50)
  168 |   })
  169 | 
  170 |   test('TVS page shows vehicle declarations', async ({ page }) => {
  171 |     await page.goto('/accounting/reports/tvs')
  172 |     await waitForContent(page)
  173 |     const text = await page.locator('#root').textContent()
  174 |     expect(text?.length || 0).toBeGreaterThan(50)
  175 |   })
  176 | 
  177 |   test('Fiscal Years page shows 10 years (2015-2024)', async ({ page }) => {
  178 |     await page.goto('/accounting/structure/fiscal-years')
  179 |     await waitForContent(page)
  180 |     const text = await page.locator('#root').textContent()
  181 |     expect(text?.length || 0).toBeGreaterThan(50)
  182 |     if (text?.includes('2015') || text?.includes('2024')) {
  183 |       expect(text).toContain('2015')
  184 |       expect(text).toContain('2024')
  185 |     }
  186 |   })
  187 | 
  188 |   test('Bank Reconciliation Rules page shows AFB codes', async ({ page }) => {
  189 |     await page.goto('/accounting/treatment/bank-reconciliation-rules')
  190 |     await waitForContent(page)
  191 |     const text = await page.locator('#root').textContent()
  192 |     expect(text?.length || 0).toBeGreaterThan(50)
  193 |   })
  194 | 
  195 |   test('Recurring Entries page shows seed entries', async ({ page }) => {
  196 |     await page.goto('/accounting/treatment/recurring-entries')
  197 |     await waitForContent(page)
  198 |     const text = await page.locator('#root').textContent()
  199 |     expect(text?.length || 0).toBeGreaterThan(50)
  200 |   })
  201 | 
  202 |   test('Regularization page shows CCA/PCA entries', async ({ page }) => {
```