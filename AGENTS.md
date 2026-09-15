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
