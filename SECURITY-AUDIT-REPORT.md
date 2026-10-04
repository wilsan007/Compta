# Security Audit Report — Compta ERP

**Date:** 2025-01-20  
**Auditor:** CSO Skill (Automated)  
**Project:** Compta — Multi-tenant SaaS Accounting ERP  
**Stack:** React + TypeScript + Vite + Supabase + i18next  
**Scope:** Full codebase, SQL migrations, Edge Functions, deployment config, mirror daemon  

---

## Executive Summary

| Severity | Count |
|----------|-------|
| CRITICAL | 2 |
| HIGH | 4 |
| MEDIUM | 5 |
| LOW | 3 |
| INFO (positive findings) | 8 |

**Overall posture:** The project demonstrates strong security awareness — RLS policies, tenant isolation, rate limiting, CSP headers, and secrets management are above average for a SaaS of this size. However, two critical vulnerabilities could lead to **cross-tenant data leakage** and must be fixed immediately.

---

## CRITICAL Findings

### C-1: `getOnlinePaymentByToken` — Cross-Tenant Data Leak

| Field | Value |
|-------|-------|
| **Severity** | CRITICAL |
| **Confidence** | High (verified by code trace) |
| **Status** | Open |
| **File** | `app/src/lib/queries/dematerialisation.ts:70-77` |

**Vulnerability:** The function queries `online_payments` **without any `tenant_id` filter**, using a wildcard `ilike` search:

```typescript
export async function getOnlinePaymentByToken(token: string): Promise<OnlinePayment | null> {
  const { data, error } = await supabase
    .from('online_payments')
    .select('*, invoice:invoices(number, total, customer_id)')
    .ilike('payment_url', `%${token}%`)  // ← wildcard, no tenant filter
    .maybeSingle()
  ...
}
```

**Exploit scenario:** An attacker can enumerate payment URLs by trying short token fragments. The `%${token}%` wildcard means even a partial match returns full invoice data (number, total, customer_id) across **all tenants**. RLS may block this if `online_payments` has proper tenant-isolated policies, but the `ilike` query itself bypasses the intended access pattern — and if RLS is not enabled on this table, it's a full cross-tenant leak.

**Remediation:**
1. Use **exact match** (`eq`) on a dedicated `token` column, not `ilike` on `payment_url`
2. Add `tenant_id` filter even if RLS is present (defense-in-depth)
3. Use a cryptographically random token (≥32 chars) instead of URL substring matching

```typescript
export async function getOnlinePaymentByToken(token: string): Promise<OnlinePayment | null> {
  const { data, error } = await supabase
    .from('online_payments')
    .select('*, invoice:invoices(number, total, customer_id)')
    .eq('payment_token', token)  // exact match on dedicated column
    .maybeSingle()
  ...
}
```

### C-2: `current_tenant_id()` Fallback Returns Wrong Tenant

| Field | Value |
|-------|-------|
| **Severity** | CRITICAL |
| **Confidence** | High (verified by SQL trace) |
| **Status** | Open |
| **File** | `app/sql/27_multi_tenant_switching.sql:26-53` |

**Vulnerability:** The `current_tenant_id()` function falls back to `ORDER BY created_at ASC LIMIT 1` when the GUC (`app.active_tenant_id`) is not set. This means:

1. If `set_active_tenant()` RPC fails (network error, timeout), the GUC is never set
2. The fallback returns the **first tenant** the user belongs to — not the one they selected
3. All subsequent RLS-filtered queries return data from the **wrong tenant**

```sql
-- Fallback in current_tenant_id():
(SELECT tenant_id FROM tenant_users
 WHERE auth_id = auth.uid()
   AND status = 'active'
 ORDER BY created_at ASC
 LIMIT 1)
```

**Exploit scenario:** A multi-tenant user (e.g., an accountant serving multiple companies) selects Tenant B, but the `set_active_tenant` RPC fails silently. The client-side `setTenantId()` in `supabase.ts:145` logs the error but continues. The user sees Tenant A's data while believing they're viewing Tenant B — leading to data confusion or intentional exploitation by selecting a tenant, killing the RPC, and browsing another tenant's data.

**Remediation:**
1. Make `setTenantId()` in `supabase.ts` **fail hard** — throw an error if the RPC fails, instead of logging and continuing
2. Add a client-side verification: after `set_active_tenant`, query `current_tenant_id()` and verify it matches
3. Change the fallback to return `NULL` instead of the first tenant — this would block all queries until the tenant is explicitly set

```typescript
// supabase.ts — fail hard
export async function setTenantId(id: string | null) {
  _tenantId = id
  if (id) {
    const { error } = await supabase.rpc('set_active_tenant', { p_tenant_id: id })
    if (error) {
      throw new Error(`SECURITY: set_active_tenant failed for tenant ${id}: ${error.message}`)
    }
    // Verify the tenant was actually set
    const { data: verifyId, error: verifyErr } = await supabase.rpc('current_tenant_id')
    if (verifyErr || verifyId !== id) {
      throw new Error(`SECURITY: Tenant verification failed. Expected ${id}, got ${verifyId}`)
    }
  }
}
```

---

## HIGH Findings

### H-1: `tenant_users` UPDATE Policy Allows Self-Role-Escalation

| Field | Value |
|-------|-------|
| **Severity** | HIGH |
| **Confidence** | High (verified by SQL policy) |
| **Status** | Open |
| **File** | `app/sql/multi_tenant_migration.sql:105-113` |

**Vulnerability:** The RLS UPDATE policy on `tenant_users` allows any user to update their own row (`auth_id = auth.uid()`), with no restriction on which columns can be changed:

```sql
CREATE POLICY "tenant_update_tenant_users" ON tenant_users
  FOR UPDATE USING (
    (tenant_id = current_tenant_id() AND current_user_role() = 'admin')
    OR auth_id = auth.uid()
  )
  WITH CHECK (
    (tenant_id = current_tenant_id() AND current_user_role() = 'admin')
    OR auth_id = auth.uid()
  );
```

**Exploit scenario:** A `viewer` user can update their own `role` column to `admin` via the Supabase client SDK. The `WITH CHECK` clause only verifies `auth_id = auth.uid()` — it does not prevent changing the `role` field.

**Remediation:**
1. Add a column-level restriction or a trigger that prevents non-admins from changing `role`, `permissions`, or `status`
2. Better: restrict self-update to only `last_login` and `accepted_at` columns

```sql
CREATE OR REPLACE FUNCTION prevent_role_escalation()
RETURNS TRIGGER AS $$
BEGIN
  -- If the user is not an admin, they cannot change role/permissions/status
  IF auth.uid() = NEW.auth_id AND current_user_role() != 'admin' THEN
    IF NEW.role IS DISTINCT FROM OLD.role THEN
      RAISE EXCEPTION 'Cannot change own role';
    END IF;
    IF NEW.permissions IS DISTINCT FROM OLD.permissions THEN
      RAISE EXCEPTION 'Cannot change own permissions';
    END IF;
    IF NEW.status IS DISTINCT FROM OLD.status THEN
      RAISE EXCEPTION 'Cannot change own status';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER prevent_role_escalation
  BEFORE UPDATE ON tenant_users
  FOR EACH ROW EXECUTE FUNCTION prevent_role_escalation();
```

### H-2: `can_perform()` SQL Function Missing Auditor Role

| Field | Value |
|-------|-------|
| **Severity** | HIGH |
| **Confidence** | High (verified by SQL + TS comparison) |
| **Status** | Open |
| **File** | `app/sql/multi_tenant_migration.sql:177-197` |

**Vulnerability:** The SQL `can_perform()` function handles `admin`, `accountant`, `manager`, `viewer`, and `custom` roles — but **not** `auditor`. The client-side `canPerform()` in `auth.tsx:322` correctly handles `auditor` (returns `action === 'select'`), but the SQL function falls through to `ELSE false`.

**Impact:** Auditors cannot read any data at the RLS level despite the client allowing SELECT. This is a functionality bug, but it also means that if the SQL function is later "fixed" by adding `auditor` to the `WHEN` clause without proper restrictions, it could accidentally grant more permissions than intended.

**Remediation:**
```sql
CREATE OR REPLACE FUNCTION can_perform(p_table text, p_action text)
RETURNS boolean
LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT CASE
    WHEN current_user_role() = 'admin' THEN true
    WHEN current_user_role() = 'accountant' AND p_action IN ('select', 'insert', 'update') THEN true
    WHEN current_user_role() = 'accountant' AND p_action = 'delete' AND p_table IN ('journal_entries', 'journal_lines', 'invoice_lines', 'quote_lines', 'credit_note_lines') THEN true
    WHEN current_user_role() = 'manager' AND p_action = 'select' THEN true
    WHEN current_user_role() = 'manager' AND p_action IN ('insert', 'update') AND p_table IN ('invoices', 'invoice_lines', 'quotes', 'quote_lines', 'credit_notes', 'credit_note_lines', 'customers', 'products', 'delivery_notes', 'delivery_note_lines', 'sales_orders', 'sales_order_lines', 'purchase_orders', 'purchase_order_lines') THEN true
    WHEN current_user_role() = 'viewer' AND p_action = 'select' THEN true
    WHEN current_user_role() = 'auditor' AND p_action = 'select' THEN true
    WHEN current_user_role() = 'custom' THEN
      COALESCE((current_user_permissions() -> p_table ->> p_action)::boolean, false)
    ELSE false
  END
$$;
```

### H-3: Mirror Daemon — Credentials in Plaintext Config

| Field | Value |
|-------|-------|
| **Severity** | HIGH |
| **Confidence** | High (verified by code) |
| **Status** | Open |
| **File** | `app/mirror-daemon/daemon.mjs:27,35,48` |

**Vulnerability:** The daemon reads `config.json` which may contain `supabaseKey` and `encryptionKey` in plaintext. While `.gitignore` excludes `config.json`, the file exists on disk with no file permission restrictions.

```javascript
const config = JSON.parse(readFileSync(configPath, 'utf-8'))
const supabaseKey = process.env.SUPABASE_KEY || process.env.VITE_SUPABASE_PUBLISHABLE_KEY || config.supabaseKey
const ENC_KEY = config.encryptionKey || process.env.MIRROR_ENCRYPTION_KEY || ''
```

**Impact:** If an attacker gains filesystem access, they can read the Supabase key and encryption key directly from `config.json`.

**Remediation:**
1. **Remove `config.supabaseKey` and `config.encryptionKey` fallback** — require env vars only
2. Set file permissions: `chmod 600 config.json` (documented in install script)
3. Use OS keychain (macOS Keychain, Windows Credential Manager) for credentials
4. At minimum, add a startup warning if credentials come from config file

### H-4: PostgREST Filter Injection in `applyPromotion`

| Field | Value |
|-------|-------|
| **Severity** | HIGH |
| **Confidence** | Medium (depends on productId validation) |
| **Status** | Open |
| **File** | `app/src/lib/queries/catalogAdvanced.ts:185` |

**Vulnerability:** The `productId` is interpolated directly into a PostgREST `.or()` filter:

```typescript
let q = supabase.from('promotions')
  .select('*')
  .eq('active', true)
  .lte('start_date', now)
  .gte('end_date', now)
  .or(`product_id.eq.${productId},product_id.is.null`)
```

**Exploit scenario:** If `productId` contains PostgREST filter syntax (e.g., `xyz,tenant_id.eq.TARGET_TENANT_UUID`), the `.or()` filter could be manipulated to leak data from other tenants or bypass filters.

**Remediation:**
1. Validate `productId` is a UUID before interpolation
2. Use parameterized query builders instead of string interpolation

```typescript
import { validate as isUuid } from 'uuid'

if (!isUuid(productId)) throw new Error('Invalid product ID')
let q = supabase.from('promotions')
  .select('*')
  .eq('active', true)
  .lte('start_date', now)
  .gte('end_date', now)
  .or(`product_id.eq.${productId},product_id.is.null`)
```

---

## MEDIUM Findings

### M-1: `console.log` Leaks Tenant ID to Browser Console

| Field | Value |
|-------|-------|
| **Severity** | MEDIUM |
| **Confidence** | High (verified by code) |
| **Status** | Open |
| **File** | `app/src/lib/queries/accounting.ts:1119-1121` |

```typescript
console.log('[searchEntries] criteria:', JSON.stringify(criteria), 'tenant_id:', tid)
const { data, error } = await query.limit(200)
console.log('[searchEntries] result count:', data?.length, 'error:', error?.message)
```

**Impact:** Tenant IDs are exposed in the browser console. In a shared/screen-sharing scenario, this leaks internal identifiers.

**Remediation:** Remove these debug log statements or gate behind a `import.meta.env.DEV` check.

### M-2: CSP Allows `'unsafe-inline'` for Scripts (Netlify)

| Field | Value |
|-------|-------|
| **Severity** | MEDIUM |
| **Confidence** | High (verified by config) |
| **Status** | Open |
| **File** | `netlify.toml:17` |

```
Content-Security-Policy = "default-src 'self'; script-src 'self' 'unsafe-inline'; ..."
```

The nginx config (`deploy/nginx.conf:32`) is stricter: `script-src 'self'` (no unsafe-inline). The Netlify config should match.

**Remediation:** Remove `'unsafe-inline'` from `script-src` in `netlify.toml`. If inline scripts are needed, use nonces or hashes.

### M-3: Client-Side Rate Limiting is Bypassable

| Field | Value |
|-------|-------|
| **Severity** | MEDIUM |
| **Confidence** | High (architectural) |
| **Status** | Accepted risk (mitigated by server-side rate limiting) |
| **File** | `app/src/lib/clientRateLimit.ts` |

The client-side rate limiter can be bypassed by modifying browser JavaScript. However, all edge functions have server-side rate limiting, so this is defense-in-depth, not the primary control. **No action needed** — just document that server-side rate limiting is the authoritative control.

### M-4: `window.location.href` Redirect in Auth Flow

| Field | Value |
|-------|-------|
| **Severity** | MEDIUM |
| **Confidence** | Medium |
| **Status** | Open |
| **File** | `app/src/lib/auth.tsx:183` |

```typescript
if (window.location.pathname !== '/accept-invitation') {
  window.location.href = '/accept-invitation'
}
```

**Impact:** Uses `window.location.href` instead of React Router's `navigate()`. This causes a full page reload and could be exploited in redirect attacks if the path is manipulated via URL parameters.

**Remediation:** Use `navigate('/accept-invitation', { replace: true })` from React Router.

### M-5: Mirror Daemon SQL Dump Uses String Escaping (Not Parameterized)

| Field | Value |
|-------|-------|
| **Severity** | MEDIUM |
| **Confidence** | Medium |
| **Status** | Accepted risk (local file only) |
| **File** | `app/mirror-daemon/daemon.mjs:194-201` |

The `escapeSqlValue()` function does basic SQL escaping for the local SQL dump file. Since this file is written to disk (not executed against the database), the risk is low. However, if the generated SQL file is imported into a database carelessly, SQL injection could occur if the source data was malicious.

**Remediation:** Document that the SQL dump is for backup purposes only and should be imported into a clean database, not appended to a production one.

---

## LOW Findings

### L-1: No File Upload Validation on Import Pages

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Confidence** | Medium |
| **Status** | Open |
| **File** | `app/src/pages/ImportPage.tsx`, `app/src/pages/SageImportPage.tsx` |

File imports (CSV, Excel) are processed client-side. While the edge functions have body size limits, the client-side parsing could be exploited with malformed files (zip bombs, XXE in XML, formula injection in CSV).

**Remediation:** Add file type validation, size limits, and sanitize CSV/Excel content before processing.

### L-2: No CSRF Protection on Edge Functions

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Confidence** | Medium |
| **Status** | Accepted risk (JWT-based auth) |
| **File** | All edge functions in `app/supabase/functions/` |

Edge functions rely on JWT Bearer tokens, not cookies, so traditional CSRF is not applicable. However, if the Supabase SDK ever switches to cookie-based auth, CSRF protection would be needed.

### L-3: No Account Lockout After Failed Attempts

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Confidence** | High |
| **Status** | Open |
| **File** | `app/src/lib/auth.tsx:222-249` |

The client-side rate limiter (5 attempts per minute) is bypassable. Supabase Auth has built-in rate limiting, but there's no explicit account lockout policy.

**Remediation:** Configure Supabase Auth rate limits in the dashboard. Consider adding CAPTCHA after 3 failed attempts (Turnstile integration available via `turnstile-spin` skill).

---

## Positive Findings (INFO)

| # | Finding | Details |
|---|---------|---------|
| P-1 | **No XSS vectors** | Zero `dangerouslySetInnerHTML`, zero `eval()`, zero `innerHTML =` assignments found |
| P-2 | **Comprehensive RLS** | 62+ SQL files with RLS policies, dynamic allow_all replacement, tenant isolation via `current_tenant_id()` |
| P-3 | **Security headers** | Both nginx and Netlify configs include HSTS, X-Frame-Options DENY, CSP, COOP/CORP/COEP, nosniff |
| P-4 | **Secrets management** | `.env` files gitignored, `.env.example` has no real secrets, `config.json` excluded from git |
| P-5 | **Edge function security** | JWT verification, IP + user rate limiting, body size validation, CORS allowlist, role-based authorization |
| P-6 | **Password policy** | Minimum 8 chars, 1 uppercase, 1 lowercase, 1 digit — enforced both client-side and server-side |
| P-7 | **Tenant isolation in queries** | `ti()` and `tud()` helpers force `tenant_id` on all CRUD operations |
| P-8 | **Audit log immutability** | RLS policy on `audit_log` prevents UPDATE/DELETE by client users |

---

## Remediation Roadmap

### Phase 1: Immediate (this week)
1. **Fix C-1**: Add `tenant_id` filter + exact token match to `getOnlinePaymentByToken`
2. **Fix C-2**: Make `setTenantId()` fail hard with verification
3. **Fix H-1**: Add trigger to prevent self-role-escalation on `tenant_users`
4. **Fix H-4**: Validate `productId` as UUID before PostgREST filter interpolation

### Phase 2: Short-term (this month)
5. **Fix H-2**: Add `auditor` role to SQL `can_perform()` function
6. **Fix H-3**: Remove config.json credential fallback in mirror daemon
7. **Fix M-1**: Remove debug `console.log` statements or gate behind `DEV` mode
8. **Fix M-2**: Remove `'unsafe-inline'` from Netlify CSP `script-src`
9. **Fix M-4**: Replace `window.location.href` with React Router `navigate()`

### Phase 3: Medium-term (next quarter)
10. **Fix L-1**: Add file upload validation on import pages
11. **Fix L-3**: Configure Supabase Auth rate limits + optional CAPTCHA
12. Add automated security tests (RLS policy tests, tenant isolation tests)
13. Set up dependency vulnerability scanning (`npm audit --production` in CI)

---

## Incident Response Playbook

### Leaked Secrets Scenario

1. **Identify** which secret was leaked (Supabase service role key, OpenAI API key, encryption key)
2. **Rotate** immediately:
   - Supabase: Dashboard → Settings → API → Reset keys
   - OpenAI: Dashboard → API Keys → Revoke + create new
   - Encryption key: Re-encrypt all mirror daemon files with new key
3. **Audit** access logs for the compromised period
4. **Notify** affected tenants if their data was accessed
5. **Post-mortem**: Document how the leak occurred and prevent recurrence

### Cross-Tenant Data Leak Scenario

1. **Identify** the vulnerability (C-1 or C-2)
2. **Patch** the code immediately and deploy
3. **Audit** Supabase logs for any queries that accessed cross-tenant data
4. **Notify** affected tenants
5. **Review** all similar code patterns for the same vulnerability class

---

## Appendix: Files Reviewed

| File | Lines | Focus |
|------|-------|-------|
| `app/src/lib/supabase.ts` | 164 | Tenant isolation, set_active_tenant |
| `app/src/lib/auth.tsx` | 343 | Auth flow, rate limiting, role checks |
| `app/src/lib/queries/core.ts` | 51 | Tenant ID caching, ti/tud helpers |
| `app/src/lib/queries/misc.ts` | 2614 | Tenant management, user invitation |
| `app/src/lib/queries/dematerialisation.ts` | 156 | Online payments (C-1 found here) |
| `app/src/lib/queries/accounting.ts` | ~2000 | Search entries, journal queries |
| `app/src/lib/queries/catalogAdvanced.ts` | ~500 | Promotions (H-4 found here) |
| `app/src/lib/clientRateLimit.ts` | 51 | Client-side rate limiting |
| `app/src/components/ProtectedRoute.tsx` | 131 | Route guards, role checks |
| `app/src/pages/LoginPage.tsx` | 106 | Login form |
| `app/src/pages/SignupPage.tsx` | 163 | Signup with password validation |
| `app/supabase/functions/create-user/index.ts` | 411 | User creation edge function |
| `app/supabase/functions/ai-import-mapping/index.ts` | 339 | AI import mapping edge function |
| `app/supabase/functions/parse-bank-statement/index.ts` | 603 | Bank statement parser edge function |
| `app/mirror-daemon/daemon.mjs` | 833 | Mirror sync daemon |
| `app/sql/multi_tenant_migration.sql` | 475 | Multi-tenant RLS setup |
| `app/sql/27_multi_tenant_switching.sql` | 118 | Tenant switching fix |
| `app/sql/24_security_fix_rls_policies.sql` | 301 | RLS policy fixes |
| `app/sql/37_security_fix_all_allow_all_policies.sql` | 244 | Dynamic RLS fix |
| `app/deploy/nginx.conf` | 62 | Nginx security headers |
| `app/public/_headers` | 23 | Cloudflare Pages headers |
| `netlify.toml` | 93 | Netlify config + headers + redirects |
| `.gitignore` (root + app) | 88 | Secrets exclusion |
| `app/.env.example` | 20 | Env template (no real secrets) |
| `wrangler.jsonc` | 7 | Cloudflare Workers config |

---

*Report generated by CSO Security Audit Skill — Version 1.0*
