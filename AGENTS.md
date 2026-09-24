# AGENTS.md — Onusuite/compta

## À faire plus tard (rappels)

### Stripe — Webhooks et paiements
- **Statut:** En attente — l'utilisateur traitera Stripe plus tard
- **À configurer quand l'utilisateur sera prêt:**
  1. Créer un compte Stripe (si pas déjà fait)
  2. Récupérer `STRIPE_WEBHOOK_SECRET` depuis Dashboard Stripe > Developers > Webhooks
  3. Ajouter le secret dans Supabase Dashboard > Settings > Edge Functions > Secrets
  4. L'Edge Function `handle-stripe-webhook` est déjà déployée sur le cloud — elle attend juste le secret
  5. Configurer les webhooks Stripe pour pointer vers: `https://ndtaedcgwnaopopugiql.supabase.co/functions/v1/handle-stripe-webhook`
  6. Tester avec un événement Stripe de test

### Resend — Emails transactionnels
- **Statut:** En attente — `RESEND_API_KEY` à ajouter
- **À configurer:**
  1. Créer un compte sur https://resend.com
  2. Générer une clé API sur https://resend.com/api-keys
  3. Ajouter `RESEND_API_KEY` dans Supabase Dashboard > Settings > Edge Functions > Secrets
  4. L'Edge Function `send-notification-email` est déjà déployée

### Sentry — Monitoring d'erreurs
- **Statut:** Code prêt, DSN à configurer
- **À configurer:**
  1. Créer un projet sur https://sentry.io
  2. Copier le DSN
  3. Ajouter `VITE_SENTRY_DSN=<dsn>` dans `app/.env.local` (local) et variables d'environnement de production

## État du projet (2026-09-09)

### Edge Functions — 20/20 déployées sur le cloud
- Projet Supabase: `ndtaedcgwnaopopugiql` (compta, West Europe)
- Toutes les fonctions sont déployées et actives
- Secrets configurés: `APP_URL`, `CRON_SECRET`, `OPENAI_API_KEY`, `RESEND_FROM`
- Secrets manquants: `RESEND_API_KEY` (Resend), `STRIPE_WEBHOOK_SECRET` (Stripe — plus tard)

### pg_cron — Configuré sur le cloud
- `payment-reminders-daily` — 9h tous les jours
- `refresh-exchange-rates-daily` — 6h tous les jours
- `revoke-expired-auditors-daily` — 0h tous les jours

### Base de données (2026-09-11)
- 377 tables sur le cloud (toutes avec RLS activé)
- 225 fonctions, 389 triggers, 1 779 policies RLS
- 138 migrations déployées et marquées (100–129)
- 5 vues (toutes avec `security_invoker=true` + filtre `current_tenant_id()`)
- Tables ajoutées: `profiles`, `webhook_endpoints`, `webhook_delivery_logs`, et 70+ tables Vague 2/3
- Fonction ajoutée: `auth_email_exists(p_email text)`
- Migration: `supabase/migrations/0001_add_missing_tables.sql`
- Seed data: `supabase/seed_business_data.sql` (5 clients, 3 fournisseurs, 5 produits, 5 factures, 5 écritures, 5 employés, 3 projets, 12 tâches)

### Vague W1 — isolation et droits (2026-09-24) ✅
- **ISO-01 (236)** : 18 fonctions `SECURITY DEFINER` filtraient mal la société
  (`UPDATE … WHERE id = …` sans `tenant_id`) : A modifiait les données de B.
  17 scénarios, contrôle `ci/check_tenant_guard.sql` (règle 2, 137 fonctions
  écrivantes examinées).
- **ISO-02 (237 + 249)** : 408 clés étrangères mono-colonnes reliaient deux
  tables cloisonnées — A référençait une ligne de B que la RLS lui cachait.
  Générateur `scripts/generate-composite-fks.mjs` (clés composites
  `(tenant_id, colonne)`, `ON DELETE SET NULL (colonne)` sur 200 d'entre elles) ;
  2 clés nées **après** la 237 (241 en ajoute une, 244 en recrée une
  mono-colonne) reprises par la **249**. Contrôle `ci/check_composite_fks.sql` :
  410 clés composites, 0 mono-colonne.
- **ISO-03 / ISO-04 (238)** : 495 couples (table, commande) portaient deux
  politiques RLS permissives — la plus large gagnait et les 57 gardes
  `can_perform` étaient annulées. 506 politiques en trop et 12 index en double
  retirés ; registre gelé de `ci/check_policy_duplicates.sql` vidé.
- **PERM-01 / décision D-6 (239)** : un `viewer` créait une facture et
  supprimait un client par appel direct. Le rôle devient opposable sur **41
  tables sensibles** (123 politiques gardées par `can_perform`) ; les **257
  autres** tables écrites restent sous la garde de société et le nombre est
  **publié** par `ci/check_roles_opposables.sql` à chaque exécution.
- **Suites adaptées** : 236 (fabrication d'état hostile par désactivation des
  seuls déclencheurs de clés étrangères, T02 inversé et retiré du registre),
  105 (recollage des clés composites par `unnest … WITH ORDINALITY` — la
  couverture passe de 333 à **340 tables visibles sur 340**).
- Preuves : `doc/audit/VAGUE-W1-ISO02-04-PERM01-2026-09-24.md`.

### Bugs corrigés
- `auth-signup/index.ts:108` — `APP_URL` non défini → fallback string
- `create-user/index.ts:450` — `otpError` non défini → `emailSent`
- `tenant_users` trigger `revoke_expired_auditors` — récursion infinie corrigée (trigger supprimé, remplacé par pg_cron)
- `current_tenant_id()` — passé en SECURITY DEFINER pour bypass RLS sur `tenant_users`

### Sécurité
- RLS activé sur 377/377 tables du cloud (100%)
- Isolation multi-tenant vérifiée: tenant 1 voit ses données, tenant 2 ne voit pas les données du tenant 1
- `current_tenant_id()` vérifie l'appartenance via `tenant_users` + `auth.uid()`
- Aucune table avec `tenant_id` sans RLS
- Migration 94 déployée: 6 problèmes Advisor corrigés
  - `sql_migrations_tracker`: RLS activé + policy service_role uniquement
  - 5 vues (`balance_sheet`, `trial_balance`, `general_ledger`, `vat_summary`, `rls_audit`): `security_invoker=true` + filtre `current_tenant_id()`
  - Grants excessifs révoqués sur les vues (SELECT uniquement pour authenticated)
  - `rls_audit` restreint à service_role uniquement
- 1 779 policies RLS en production
- 0 deadlocks, 0 conflits, taux de rollback 3.49% (normal pour RLS)

### Storage Supabase
- 7 buckets configurés (local + cloud): `project-docs`, `accounting-docs`, `hr-docs`, `commercial-docs`, `general-docs`, `employee-documents`, `tax-grid-sources`
- Uploads/downloads testés avec succès sur local et cloud

### Real-time
- 9 tables activées pour real-time (local + cloud): customers, suppliers, invoices, journal_entries, employees, projects, project_tasks, stock_movements, bank_accounts
- Subscription WebSocket testée sur le cloud (status: SUBSCRIBED)

### Frontend (2026-09-11)
- 1240 tests unitaires passent (Vitest), 13 skipped
- TypeScript: `tsc -b --noEmit` → exit 0 (strict mode)
- Build Vite: réussi
- Bundle splitting: react-vendor, supabase, i18n, pdf, xlsx, charts, date-fns, utils
- **Chunk index: 26.49 ko gzip** (objectif < 250 ko ✅)
- Traductions chargées dynamiquement par langue (fr/en/ar en chunks séparés)
- 267 lazy-loaded routes
- ErrorBoundary avec Sentry intégré (lazy-loaded)
- 0 `window.confirm` dans src/ (remplacés par `confirmSync` de `@/lib/confirm`)
- CI: check anti-`window.confirm` dans `.github/workflows/ci.yml`
- 10 parcours E2E Playwright (`e2e/business-flows.spec.ts`)
- Hooks d'accessibilité: `useConfirm`, `useFocusTrap`, `useAnnouncement`, `useKeyboardEntry`
- `ConfirmProvider` intégré dans `App.tsx`
- xlsx et pdfjs-dist chargés dynamiquement (imports `import()`)
- Pages publiques lazy-loaded (Landing, Login, Terms, Privacy)
- OpenAPI spec publiée (`openapi.json`)
- API publique: idempotence (`Idempotency-Key`), journal des appels, format d'erreur uniforme
- Edge Functions `public-api` et `outgoing-webhooks` déployées sur le cloud

### Monitoring
- Sentry installé (`@sentry/react` v10.68.0)
- `AppErrorBoundary` capture les erreurs React et envoie à Sentry
- 35 `console.error` dans les Edge Functions pour le logging
- Logs Edge Functions visibles via Dashboard Supabase > Functions > Logs
