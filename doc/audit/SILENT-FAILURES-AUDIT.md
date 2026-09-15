# Rapport d'audit des failures silencieux — Onusuite/compta

**Date:** 2026-09-14
**Scope:** `app/src/` (426 fichiers TS/TSX) + `app/supabase/functions/` (20 Edge Functions)
**Outils:** Script statique `scripts/audit-silent-failures.mjs` + guard runtime `src/lib/silentFailureGuard.ts`

---

## 1. Résumé exécutif

L'audit a identifié **1 751 findings** répartis sur 10 catégories de failures silencieux:

| Sévérité | Count | Action recommandée |
|----------|-------|--------------------|
| **Error** | 227 | Correction prioritaire (sécurité / données) |
| **Warning** | 971 | Correction planifiée (qualité / observabilité) |
| **Info** | 553 | À évaluer (defense-in-depth) |

**Les 3 risques majeurs:**
1. **108 requêtes UPDATE/DELETE/INSERT sur tables tenant sans filtre `tenant_id`** — risque de fuite cross-tenant si une policy RLS est mal configurée ou désactivée. RLS couvre actuellement, mais c'est une violation du principe defense-in-depth.
2. **102 catch vides** — erreurs totalement avalées, invisibles en production, impossibles à diagnostiquer.
3. **13 `if (error) return null/[]/false` sans logger** — l'appelant reçoit un résultat vide sans savoir qu'une erreur s'est produite (symptôme: "la page est vide" sans explication).

---

## 2. Catégorisation des patterns

### 2.1 Filtres bypass — MISSING_TENANT_FILTER (108 errors, 535 infos)

Requêtes Supabase sur tables tenant-scoped sans filtre applicatif `tenant_id`.

**Errors (UPDATE/DELETE/INSERT sans `tud()`/`ti()`):**

| Fichier | Count | Tables affectées |
|---------|-------|------------------|
| `src/lib/queries/accounting.ts` | 24 | journal_entries, journal_lines |
| `src/lib/queries/projectManagement.ts` | 18 | project_tasks, project_task_assignees |
| `src/lib/queries/projectManagementSprint1.ts` | 14 | project_time_entries, task_comments |
| `src/lib/queries/misc.ts` | 12 | fixed_assets, stock_movements, purchase_credit_notes |
| `src/lib/queries/documents.ts` | 7 | module_documents |
| `src/lib/queries/posAdvanced.ts` | 4 | pos_sessions, pos_ticket_lines, invoice_lines |
| `src/lib/queries/purchaseAdvanced.ts` | 4 | purchase_request_lines, supplier_price_list_lines |
| `supabase/functions/sync-bank-transactions/index.ts` | 3 | bank_connections, bank_transactions |
| `supabase/functions/submit-e-invoice/index.ts` | 2 | invoices |
| `supabase/functions/submit-vat-return/index.ts` | 2 | vat_returns |
| `supabase/functions/transmit-dsn/index.ts` | 2 | dsn_declarations |
| `src/components/project-management/DocView.tsx` | 2 | project_docs |
| `src/lib/analyticDistribution.ts` | 2 | analytic_distribution_lines |
| `src/lib/queries/dematRh.ts` | 2 | rh_knowledge_base |
| `src/lib/queries/payroll.ts` | 2 | journal_lines, collection_reminders |
| + 7 autres fichiers | 8 | diverses |

**Exemple critique** (`src/lib/queries/accounting.ts:996`):
```ts
// ❌ UPDATE sans tud() — si RLS est désactivé, met à jour across tenants
const { error } = await supabase.from('journal_entries').update(updates).eq('id', id)
```
**Correction:**
```ts
// ✅ Avec tud() pour defense-in-depth
const { error } = await tud(supabase.from('journal_entries').update(updates), 'journal_entries', tid).eq('id', id)
```

**Note sur les 535 infos (SELECT):** RLS filtre côté base, donc ces SELECT ne fuient pas de données. Mais en l'absence de filtre applicatif, un bug RLS ou une migration qui désactive temporairement RLS exposerait les données. Recommandation: ajouter `.eq('tenant_id', tid)` pour defense-in-depth.

### 2.2 Erreurs avalées — EMPTY_CATCH (102 errors)

`catch {}` ou `catch (e) {}` avec corps vide. L'erreur est totalement invisible.

**Top fichiers:**
- `src/pages/Phase6Pages.tsx` — 15 occurrences
- `src/pages/Phase2Pages.tsx` — 11 occurrences
- `src/pages/Phase4Pages.tsx` — 10 occurrences
- `src/pages/Phase3Pages.tsx` — 7 occurrences
- `src/pages/Phase5Pages.tsx` — 4 occurrences
- `src/components/` — 15 occurrences (QuickAccess, NotificationCenter, etc.)

**Pattern typique:**
```ts
// ❌ Erreur avalée — l'utilisateur voit une page vide sans savoir pourquoi
const loadData = useCallback(async () => {
  setLoading(true)
  try { setItems(await getProspects() || []) } catch { } finally { setLoading(false) }
}, [])
```

### 2.3 Erreurs avalées avec console — CONSOLE_ONLY_CATCH (223 warnings)

`catch` qui ne fait que `console.error(err)` sans notification UI ni rethrow. En production, `console.error` est invisible pour l'utilisateur et souvent noyé dans le bruit.

**Top fichiers:**
- `src/pages/TaxRatesPage.tsx` — 5
- `src/pages/ManufacturingOrderDetailPage.tsx` — 5
- `src/pages/SubcontractingPages.tsx` — 4
- `src/pages/settings/LeaveRulesPage.tsx` — 4
- `src/pages/MRPPages.tsx` — 3
- `src/pages/ComplementaryPages.tsx` — 3

**Pattern typique:**
```ts
// ⚠️ L'utilisateur ne sait pas que le chargement a échoué
} catch (err) { console.error('Error:', err) }
```
**Correction:**
```ts
// ✅ Notification UI + log
} catch (err) {
  console.error('Error:', err)
  toast('error', 'Erreur de chargement', 'Impossible de charger les données')
}
```

### 2.4 Erreurs avalées avec fallback — SWALLOWED_ERROR_RETURN (13 errors)

`if (error) return null/[]/false` sans logger. L'appelant reçoit un résultat vide sans savoir qu'une erreur s'est produite.

**Exemples:**
- `src/lib/queries/admin.ts:66` — `if (error) return false`
- `src/lib/queries/payroll.ts:667` — `if (error) return null`
- `src/lib/queries/misc.ts:578` — `if (error) return []`
- `src/lib/currencyRates.ts:26,41` — `if (error || !data) return null`
- `src/lib/pdfBankParser.ts:298,429` — `if (error || !data) return null`

### 2.5 Casts `as any` — AS_ANY_CAST (580 warnings)

Court-circuitent le typage TypeScript. Risque: accès à propriétés inexistantes → `undefined` silencieux → bugs difficiles à tracer.

**Top patterns:**
- `(user as any)?.module_roles` — 6 occurrences (le type `user` ne déclare pas `module_roles`)
- `e.target.value as any` dans les selects — plusieurs occurrences
- `data as any` passé aux fonctions de query — plusieurs occurrences

**Recommandation:** Définir les types manquants (ex: étendre le type `User` avec `module_roles`, `guest_permissions`) plutôt que caster.

### 2.6 Promises non attendues — FLOATING_PROMISE (107 warnings)

Appels de fonctions async sans `await`. Si la promise rejette, c'est une `unhandledrejection` silencieuse (ou captée par le handler global trop tard).

**Top fichiers:**
- `src/pages/` — majorité (loadData() dans useEffect sans await)
- `src/components/cross-module/Quick*Access.tsx` — 8 occurrences

**Pattern typique:**
```ts
// ⚠️ loadData() est async mais pas awaité — si elle rejette, unhandledrejection
useEffect(() => {
  if (open) loadData()  // pas de await, pas de .catch
}, [open])
```
**Note:** Dans un `useEffect`, on ne peut pas `await` directement. La correction est d'ajouter un `.catch` ou d'utiliser le guard runtime `trackPromise()`.

### 2.7 Spread de valeur possiblement undefined — UNDEFINED_SPREAD (18 infos)

`{ ...data, foo: 1 }` où `data` pourrait être `null` (ex: résultat Supabase). `...null` en JS ne throw pas mais spread rien — résultat: objet partiellement peuplé silencieusement.

**Exemples:**
- `src/lib/queries/accounting.ts:2154` — `.insert({ ...entry, tenant_id: tid })`
- `src/lib/queries/core.ts:39` — `return { ...payload, tenant_id: tid }`

### 2.8 Déstructuration Supabase sans error — UNCHECKED_SUPABASE (61 warnings)

`const { data } = await supabase.from(...)` sans déstructurer `error`. L'erreur est ignorée.

**Exemples:**
- `src/lib/queries/core.ts:17` — `const { data } = await supabase.from('tenant_users').select(...)`
- `src/lib/auth.tsx:174` — `const { data: pendingInvite } = await supabase...`

### 2.9 Catch retourne valeur par défaut — CATCH_RETURN_DEFAULT (4 errors)

`catch { return [] }` ou `catch { return null }` sans logger.

- `src/lib/pdfBankParser.ts:285` — `catch { return [] }`
- `src/lib/useTenantModules.ts:75` — `catch { return [] }`
- `src/lib/utils.ts:69` — `catch { return null }`
- `supabase/functions/parse-bank-statement/index.ts:97` — `catch { return false }`

### 2.10 Optional chain sur await — OPTIONAL_CHAIN_SWALLOW (0)

Aucun finding — bonne pratique respectée.

---

## 3. Outils implémentés

### 3.1 Détection statique — `scripts/audit-silent-failures.mjs`

Script Node.js ESM qui scanne 426 fichiers et détecte 10 catégories de patterns.

**Usage:**
```bash
npm run audit:silent          # rapport humain
npm run audit:silent:json     # JSON pour CI/intégration
node scripts/audit-silent-failures.mjs --severity=error  # que les errors
```

**Exit code:** 1 si au moins 1 finding de niveau error → intégrable en CI.

**Règle verify:** `scripts/verify-rules/14-silent-failures.rule` — s'exécute via `npm run verify`.

### 3.2 Détection runtime — `src/lib/silentFailureGuard.ts`

Wrapper Supabase + reporter qui détecte à l'exécution:

1. **`wrapSupabaseClient(client)`** — Proxy sur `.from()` qui intercepte les réponses et reporte les `error` non vérifiés sur tables tenant.
2. **`SilentFailureReporter`** — collecteur central (console colorée + Sentry + compteur pour tests).
3. **`installGlobalRejectionHandler()`** — capture `unhandledrejection` et `error` globaux.
4. **`trackPromise(p, label)`** — wrap une promise, reporte si elle rejette ou si elle n'est pas consommée dans le tick.

**Activation:** `VITE_SILENT_FAILURE_GUARD=true` dans `.env.local` (désactivé par défaut pour éviter le bruit en production).

**Tests:** `src/lib/__tests__/silentFailureGuard.test.ts` — 8 tests passants.

**Intégration recommandée dans `src/lib/supabase.ts`:**
```ts
import { wrapSupabaseClient, installGlobalRejectionHandler } from '@/lib/silentFailureGuard'

export const supabase = wrapSupabaseClient(createClient(supabaseUrl, supabaseKey, {...}))
installGlobalRejectionHandler()
```

---

## 4. Recommandations priorisées

### P0 — Critique (sécurité / intégrité données)

1. **Corriger les 108 UPDATE/DELETE/INSERT sans filtre tenant** (MISSING_TENANT_FILTER errors)
   - Ajouter `tud()` sur tous les UPDATE/DELETE de tables tenant
   - Ajouter `ti()` sur tous les INSERT de tables tenant
   - Vérifier particulièrement les Edge Functions (`submit-e-invoice`, `submit-vat-return`, `transmit-dsn`, `sync-bank-transactions`) qui utilisent la service_role (RLS bypassée!)
   - **⚠️ Les Edge Functions avec service_role n'ont PAS de RLS — le filtre tenant est OBLIGATOIRE**

2. **Corriger les 13 `if (error) return null/[]` sans logger** (SWALLOWED_ERROR_RETURN)
   - Ajouter au minimum `console.error(error)` avant le return
   - Idéalement: propager l'erreur ou retourner `{ data, error }` pour que l'appelant décide

### P1 — Élevé (observabilité / debuggabilité)

3. **Remplacer les 102 catch vides** (EMPTY_CATCH)
   - Ajouter `console.error(err)` minimum
   - Pour les pages: ajouter `toast('error', ...)` pour informer l'utilisateur
   - Pattern suggéré: créer un helper `safeLoad(fn, fallback)` qui logge + retourne fallback

4. **Améliorer les 223 console-only catch** (CONSOLE_ONLY_CATCH)
   - Ajouter `toast('error', ...)` pour les erreurs visibles par l'utilisateur
   - Pour les erreurs de fond (loadData): au moins setter un state `error` pour afficher un ErrorState

5. **Activer le guard runtime en dev** (`VITE_SILENT_FAILURE_GUARD=true`)
   - Détectera les unhandledrejections et les erreurs Supabase non vérifiées en temps réel
   - Intégrer `wrapSupabaseClient` + `installGlobalRejectionHandler` dans `supabase.ts`

### P2 — Moyen (qualité / typage)

6. **Réduire les 580 `as any`** (AS_ANY_CAST)
   - Priorité: `(user as any)?.module_roles` → étendre le type User (6 occurrences)
   - `e.target.value as any` → typer correctement les selects
   - `data as any` → aligner les types entre queries et composants

7. **Sécuriser les 107 floating promises** (FLOATING_PROMISE)
   - Dans les useEffect: ajouter `.catch(err => console.error(err))` ou utiliser `trackPromise()`
   - Vérifier les QuickAccess components (8 occurrences)

8. **Vérifier les 61 déstructurations Supabase sans error** (UNCHECKED_SUPABASE)
   - Toujours déstructurer `{ data, error }` et vérifier `error`

### P3 — Bas (defense-in-depth)

9. **Ajouter `.eq('tenant_id', tid)` sur les 535 SELECT** (MISSING_TENANT_FILTER infos)
   - RLS couvre, mais defense-in-depth recommandée
   - Bonus: réduit la taille des payloads (filtre applicatif)

10. **Vérifier la nullabilité des 18 spreads** (UNDEFINED_SPREAD)
    - Ajouter `if (!data) return ...` avant `{ ...data, ... }`

---

## 5. Plan de remédiation suggéré

| Phase | Catégorie | Effort estimé | Impact |
|-------|----------|---------------|--------|
| 1 | P0: Edge Functions tenant filter (12 findings) | 2-3h | Sécurité critique |
| 2 | P0: Queries tenant filter (96 findings) | 1-2j | Sécurité |
| 3 | P1: Swallowed error returns (13) | 2-3h | Debuggabilité |
| 4 | P1: Empty catch → helper safeLoad (102) | 1j | Observabilité |
| 5 | P1: Console-only catch → toast (223) | 1-2j | UX |
| 6 | P2: as any → types (580) | 2-3j | Typage |
| 7 | P2: Floating promises (107) | 1j | Stabilité |
| 8 | P3: SELECT tenant filter (535) | 1j | Defense-in-depth |

**Helper suggéré pour P4 (réduit la duplication):**
```ts
// src/lib/safeLoad.ts
export async function safeLoad<T>(fn: () => Promise<T>, fallback: T, label?: string): Promise<T> {
  try { return await fn() }
  catch (err) {
    console.error(`[safeLoad${label ? ': ' + label : ''}]`, err)
    return fallback
  }
}
// Usage: setItems(await safeLoad(() => getProspects(), [], 'prospects'))
```

---

## 6. Vérification

- ✅ `npx tsc -b --noEmit` — exit 0
- ✅ `npx vitest run` — 1248 tests passants (8 nouveaux pour le guard runtime)
- ✅ Script `audit-silent-failures.mjs` fonctionnel
- ✅ Guard runtime `silentFailureGuard.ts` testé
- ✅ Règle verify `14-silent-failures.rule` créée

## 7. Fichiers créés/modifiés

| Fichier | Type | Description |
|---------|------|-------------|
| `app/scripts/audit-silent-failures.mjs` | Nouveau | Script de détection statique (10 catégories) |
| `app/scripts/verify-rules/14-silent-failures.rule` | Nouveau | Règle CI pour `npm run verify` |
| `app/src/lib/silentFailureGuard.ts` | Nouveau | Guard runtime (Supabase wrapper + reporter) |
| `app/src/lib/__tests__/silentFailureGuard.test.ts` | Nouveau | 8 tests du guard runtime |
| `app/package.json` | Modifié | Scripts `audit:silent` et `audit:silent:json` |

---

## 8. Note sur Prisma vs Supabase

La demande initiale mentionnait une "extension Prisma" pour la détection runtime. Ce projet utilise **Supabase** (PostgREST + Postgres), pas Prisma. L'approche a été adaptée:

- **Prisma extension** → **Proxy Supabase** (`wrapSupabaseClient`) qui intercepte `.from()` et inspecte les réponses
- **Prisma middleware** → **Proxy sur le query builder** qui wrap `.then()` (point d'await)
- **`siteFilter`** → **`tenant_id` filter** (équivalent multi-tenant via `tud()`/`ti()` helpers + RLS)

Le guard runtime offre les mêmes garanties qu'une extension Prisma: détection des erreurs non vérifiées, des requêtes sans filtre tenant, et des unhandledrejections.
