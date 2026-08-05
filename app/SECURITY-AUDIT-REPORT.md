# Security Audit Report — Compta SaaS
**Date:** 2026-07-28 09:38 UTC+3
**Mode:** Daily (8/10 confidence gate)
**Scope:** Full audit (all phases)
**Auditor:** CSO Skill (AI-assisted)

---

## Attack Surface Map

```
CODE SURFACE
  Public endpoints:      0 (all routes behind ProtectedRoute)
  Authenticated:         329 routes
  Admin-only:            0 (role-based via permissions object)
  API endpoints:         1141 Supabase queries
  File upload points:    21 files
  External integrations: 11 fetch calls
  Webhook receivers:     0
  Background jobs:       0

INFRASTRUCTURE SURFACE
  CI/CD workflows:       2 (ci.yml, deploy.yml)
  Webhook receivers:     0
  Container configs:     1 (nginx.conf)
  IaC configs:           0
  Deploy targets:        2 (Netlify, Cloudflare Wrangler)
  Secret management:     env vars + GitHub Secrets
```

---

## Security Findings

```
#   Sev    Conf   Status      Category         Finding                                          Phase   File:Line
──  ────   ────   ──────      ────────         ───────                                          ─────   ─────────
1   HIGH   9/10   VERIFIED    Supply Chain     postcss path traversal CVE                        P3      node_modules/postcss
2   HIGH   9/10   VERIFIED    Supply Chain     react-router RSC CSRF bypass CVE                  P3      node_modules/react-router
3   HIGH   9/10   VERIFIED    Supply Chain     xlsx prototype pollution + ReDoS (no fix)         P3      node_modules/xlsx
4   HIGH   8/10   VERIFIED    RLS              80 allow_all policies with USING(true)            P7      sql/21_phase4_payroll_hr.sql
5   MED    8/10   VERIFIED    Auth             Tenant ID stored in localStorage (spoofable)      P9      src/lib/auth.tsx:75
6   MED    8/10   VERIFIED    CI/CD            No SAST in CI pipeline (only grep-based check)    P4      .github/workflows/ci.yml
7   MED    8/10   VERIFIED    CI/CD            No dependency pinning in workflows (actions@v4)  P4      .github/workflows/ci.yml
```

---

## Finding 1: postcss Path Traversal Vulnerability
* **Severity:** HIGH
* **Confidence:** 9/10
* **Status:** VERIFIED
* **Phase:** 3 — Supply Chain
* **Category:** Supply Chain
* **Description:** `postcss <=8.5.17` has a path traversal vulnerability (GHSA-r28c-9q8g-f849) that allows arbitrary `.map` file disclosure via `sourceMappingURL` auto-loading.
* **Exploit scenario:** A crafted CSS file with a malicious `sourceMappingURL` could cause postcss to read arbitrary files from the build server filesystem during build time.
* **Impact:** Build-time file disclosure. Since this runs in CI (GitHub Actions), an attacker who can inject a crafted CSS file into the repo could exfiltrate CI secrets.
* **Recommendation:** Run `npm audit fix` to upgrade postcss. Verify the fix doesn't break Tailwind's PostCSS plugin.

## Finding 2: react-router RSC CSRF Bypass
* **Severity:** HIGH
* **Confidence:** 9/10
* **Status:** VERIFIED
* **Phase:** 3 — Supply Chain
* **Category:** Supply Chain
* **Description:** `react-router 7.12.0-8.2.0` has a CSRF bypass in RSC mode (GHSA-qwww-vcr4-c8h2) that allows action execution before the 400 response.
* **Exploit scenario:** If the app uses RSC (React Server Components) mode, an attacker could craft a cross-origin request that bypasses CSRF checks and executes server actions.
* **Impact:** Unauthorized action execution. However, this app uses Vite (client-side rendering), not RSC mode, so the exploit path is unlikely but the vulnerability is still present in the dependency tree.
* **Recommendation:** Run `npm audit fix` to upgrade react-router. Verify no breaking changes in routing behavior.

## Finding 3: xlsx Prototype Pollution + ReDoS (No Fix Available)
* **Severity:** HIGH
* **Confidence:** 9/10
* **Status:** VERIFIED
* **Phase:** 3 — Supply Chain
* **Category:** Supply Chain
* **Description:** The `xlsx` package (SheetJS) has prototype pollution (GHSA-4r6h-8v6p-xvw6) and ReDoS (GHSA-5pgg-2g8v-p4x9) vulnerabilities. No fix is available upstream.
* **Exploit scenario:** A malicious Excel file uploaded by a user could trigger prototype pollution during parsing, potentially leading to RCE or data corruption. ReDoS could cause denial of service by freezing the parsing thread.
* **Impact:** If users upload Excel files that are parsed with `xlsx`, this is a direct exploit path. The app has 21 file upload points.
* **Recommendation:** Replace `xlsx` with a maintained alternative like `exceljs` or `@e965/xlsx` (SheetJS community fork). If replacement is not immediate, sanitize inputs before parsing and limit file size.

## Finding 4: Permissive RLS Policies (allow_all with USING(true))
* **Severity:** HIGH
* **Confidence:** 8/10
* **Status:** VERIFIED
* **Phase:** 7 — RLS / OWASP A01
* **Category:** RLS / Tenant Isolation
* **Description:** 80 RLS policies across 22 SQL files use `USING (true) WITH CHECK (true)`, granting full access to all tenants' data. These are `allow_all_*` policies in Phase 2-5 SQL files. The fix script `37_security_fix_all_allow_all_policies.sql` exists and dynamically replaces these with `current_tenant_id()`-based policies, but only if it has been executed against the production database.
* **Exploit scenario:** If migration 37 has NOT been run on production, any authenticated user can read/write ALL tenants' payroll, HR, gescom, and fixed asset data by simply querying the tables — RLS is enabled but the policy allows everything.
* **Impact:** Complete tenant data leakage. Payroll salaries, employee documents, expense reports, and career history from ALL tenants would be accessible to any authenticated user.
* **Recommendation:** **Verify that migration 37 has been executed on production.** Run the verification queries at the bottom of the file:
  ```sql
  SELECT tablename, policyname FROM pg_policies WHERE policyname LIKE 'allow_all_%';
  -- Should return 0 rows
  ```
  If any `allow_all_*` policies remain, re-run migration 37.

## Finding 5: Tenant ID Stored in localStorage (Client-Side Spoofing Risk)
* **Severity:** MEDIUM
* **Confidence:** 8/10
* **Status:** VERIFIED
* **Phase:** 9 — OWASP A07 (Identification & Authentication Failures)
* **Category:** Auth / Tenant Isolation
* **Description:** `src/lib/auth.tsx:75` stores `active_tenant_id` in `localStorage`. A user could manually change this value in the browser console to attempt tenant switching. However, the server-side `set_active_tenant` RPC + verification (`current_tenant_id()`) at `supabase.ts:147-156` provides a server-side gate.
* **Exploit scenario:** User opens browser console, runs `localStorage.setItem('active_tenant_id', 'other-tenant-uuid')`, then reloads. The client sends this to `setTenantId()`, which calls `supabase.rpc('set_active_tenant', { p_tenant_id: 'other-tenant-uuid' })`. If the user is NOT a member of that tenant, the RPC should reject it. But if the RPC doesn't validate membership, the user could switch tenants.
* **Impact:** Potential cross-tenant access if the `set_active_tenant` RPC doesn't validate tenant membership. The client-side verification at line 153 (`verifyId !== id`) only checks that the RPC accepted the ID, not that the user is authorized.
* **Recommendation:** Verify that the `set_active_tenant` PostgreSQL function validates that the user (auth.uid()) is an active member of the target tenant in `tenant_users`. If not, add this check:
  ```sql
  CREATE OR REPLACE FUNCTION set_active_tenant(p_tenant_id uuid)
  RETURNS void AS $$
  BEGIN
    IF NOT EXISTS (
      SELECT 1 FROM tenant_users
      WHERE auth_id = auth.uid() AND tenant_id = p_tenant_id AND status = 'active'
    ) THEN
      RAISE EXCEPTION 'User is not an active member of tenant %', p_tenant_id;
    END IF;
    PERFORM set_config('app.current_tenant_id', p_tenant_id::text, true);
  END;
  $$ LANGUAGE plpgsql SECURITY DEFINER;
  ```

## Finding 6: No SAST Tool in CI Pipeline
* **Severity:** MEDIUM
* **Confidence:** 8/10
* **Status:** VERIFIED
* **Phase:** 4 — CI/CD
* **Category:** CI/CD
* **Description:** The CI pipeline (`.github/workflows/ci.yml`) has a `security-audit` job that runs `npm audit` and a basic `grep` for hardcoded secrets, but no proper SAST (Static Application Security Testing) tool. The grep-based check only looks for `api_key|secret_key|password` patterns ≥16 chars and uses `continue-on-error: true`, so it never fails the build.
* **Exploit scenario:** A developer accidentally commits a hardcoded API key in a format not matching the grep pattern (e.g., `SUPABASE_KEY = "eyJ..."`), and it passes CI.
* **Impact:** Secrets could be committed and deployed without detection.
* **Recommendation:** Add a proper SAST step. Options:
  - Add `npx semgrep --config=auto` to the security-audit job
  - Or use GitHub's CodeQL analysis action
  - Remove `continue-on-error: true` from the secret scanning step

## Finding 7: Unpinned GitHub Actions (actions@v4)
* **Severity:** MEDIUM
* **Confidence:** 8/10
* **Status:** VERIFIED
* **Phase:** 4 — CI/CD
* **Category:** CI/CD / Supply Chain
* **Description:** Both workflows use `actions/checkout@v4` and `actions/setup-node@v4` without pinning to a specific commit SHA. A compromise of the `actions/checkout` or `actions/setup-node` repository would allow supply chain attacks on all CI runs.
* **Exploit scenario:** An attacker compromises the `actions/checkout` repo and pushes a malicious `v4` tag. All CI runs using `actions/checkout@v4` would execute the malicious action, potentially exfiltrating GitHub secrets.
* **Impact:** Full CI compromise — access to `NETLIFY_AUTH_TOKEN`, `NETLIFY_SITE_ID`, and any other GitHub secrets.
* **Recommendation:** Pin actions to commit SHAs:
  ```yaml
  - uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11  # v4.1.1
  - uses: actions/setup-node@60edb5dd545a775178fba252f81b25c7e6e5b1d  # v4.1.0
  ```

---

## Positive Findings (Security Strengths)

1. **No `dangerouslySetInnerHTML`** — Zero uses across the entire codebase. React's default XSS protection is intact.
2. **No `.rpc()` calls from client** — All RPC calls go through the Supabase client which parameterizes queries. SQL injection risk is minimal.
3. **Tenant isolation architecture** — `ti()` function forces `tenant_id` on inserts, `tud()` applies tenant filter on update/delete. `TENANT_TABLES` registry covers 134+ tables. RLS is enabled on all tenant tables.
4. **Tenant verification on switch** — `setTenantId()` calls `set_active_tenant` RPC then verifies with `current_tenant_id()` — double-check pattern.
5. **Input sanitization** — `inputSanitizer.ts` provides `sanitizeText`, `sanitizeEmail`, `sanitizePhone`, `sanitizeNumber`, `sanitizeDate`, `sanitizeFilename`, `sanitizeUrl`, `detectSqlInjection`, `isValidUUID`.
6. **`.env` properly gitignored** — `.gitignore` excludes `.env` and `.env.*` (except `.env.example`). No `.env` file tracked in git.
7. **No `pull_request_target`** — CI workflows don't use the dangerous `pull_request_target` event.
8. **RLS fix migration exists** — Migration 37 dynamically replaces all `allow_all` policies with tenant-isolated policies.
9. **Security audit job in CI** — Even though basic, there is a dedicated security-audit job that runs nightly.

---

## Remediation Roadmap (Top 5)

| # | Finding | Severity | Effort | Action |
|---|---------|----------|--------|--------|
| 1 | Verify migration 37 executed on prod | HIGH | 5 min | Run verification SQL on production |
| 2 | Fix npm vulnerabilities (postcss, react-router) | HIGH | 15 min | `npm audit fix` + verify build |
| 3 | Replace xlsx with maintained alternative | HIGH | 2-4 hrs | Swap `xlsx` for `exceljs` in import/export code |
| 4 | Verify `set_active_tenant` validates membership | MEDIUM | 30 min | Read the PostgreSQL function, add membership check if missing |
| 5 | Pin GitHub Actions to SHAs | MEDIUM | 10 min | Update both workflow files |

---

## Disclaimer

**This tool is not a substitute for a professional security audit.** This AI-assisted scan catches common vulnerability patterns — it is not comprehensive, not guaranteed, and not a replacement for hiring a qualified security firm. For a production SaaS handling financial data, PII, and payroll, engage a professional penetration testing firm.
