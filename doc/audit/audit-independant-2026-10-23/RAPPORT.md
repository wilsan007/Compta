# Audit indépendant exécuté — 23/10/2026 (branche `integration/plan6-b`)

Méthode : **rien n'est pris dans les documents ni dans le code écrit**. Une base PostgreSQL 16 neuve a été
reconstruite (stubs + schéma + `run-sql-migrations.mjs`), PostgREST réel + passerelle JWT du banc, front Vite
réel, navigateur Chromium (Playwright). Tous les chiffres ci-dessous sont **mesurés ce jour**.

## 1. Mesures

| Contrôle | Résultat mesuré |
|---|---|
| Base neuve | 437 migrations, 0 erreur · 412 tables · 748 fonctions |
| Suites SQL (ordre de la CI) | **266 fichiers, 0 échec** · 1 787 verdicts verts · 1 rouge = auto-test du registre (attendu) |
| Contrôles SQL (G1–G7, tenant guard, anon, FKs composites…) | verts (17/17) |
| Scénarios « chemin de l'écran » (PostgREST réel) | 16 fichiers, **150 verdicts verts, 0 rouge** |
| Vitest | 1 662 verts, 38 ignorés (78 fichiers) |
| tsc / oxlint / i18n / 13 contrôles de dépôt | 0 erreur |
| Edge Functions (Deno) | 46/46 |
| Build prod + scan de secrets | OK |
| Playwright e2e | 77/78 — l'échec (C4) exige un article `E2E-ART-1` absent de ma base : non vérifié |
| Balayage navigateur — 354 routes, société remplie, desktop | 0 page cassée, 0 incident ; 17 défauts mineurs |
| Balayage navigateur — 354 routes, société vide (Djibouti), desktop + mobile | 0 page cassée ; 26 défauts mineurs |
| Fenêtres « Nouveau » testées (107 routes) : ouverture, envoi à vide, envoi rempli | 104 ouvertes · 0 erreur 5xx · 0 erreur JS · validations OK · 76 créations 2xx |
| Grand livre | débit = crédit, 0 écriture validée déséquilibrée |
| Isolation / rôles par l'API | A≠B (lecture, modif, suppression, création), anonyme, lecteur : tout refusé |

## 2. Défaut majeur trouvé (contredit « registre vide »)

**Création refusée par l'écran sur ~22 tables** (« You are not allowed to perform this action », HTTP 403).
Cause : `ti()` (`src/lib/queries/core.ts:49`) n'ajoute `tenant_id` que si la table est dans `TENANT_TABLES`
(`src/lib/supabase.ts:50`) ; ces tables n'y sont pas, n'ont ni défaut ni déclencheur, et la RLS exige
`tenant_id = current_tenant_id()`. Reproduit dans l'interface (stock : cycles de comptage, coûts d'approche,
règles de réapprovisionnement, unités ; modèles d'e-mail ; séquences CRM ; scoring ; champs personnalisés ;
recrutement) et par l'API pour les 24 tables de `p403b.mjs`. Correctif : les ajouter à `TENANT_TABLES`
(ou poser un déclencheur `set_tenant_id`) + un test de contrôle.

## 3. Défauts mineurs

- `/project-management/my-tasks` : 4 onglets au panneau identique ; cibles tactiles < 24 px (mind-map, box, guide) ; icônes sans libellé.
- `/sales/quotes`, `/accounting/treatment/recurring-entries` : champs de fenêtre sans nom accessible.
- Notes de frais `/hr/my-expenses`, `/employee/expenses` : un compte non salarié peut ouvrir le formulaire puis reçoit « employee_id manquant ».
- `/treasury/payment-orders`, `/purchases/requests` : envoi à vide crée un enregistrement.
- Un balayage de harnais affiche ~122 s sur 35 routes `/settings/*` et `/project-management/*` : artefact (la page se charge en < 3 s à la main).

## 4. Non vérifié (honnêteté)

Intégrations externes (Stripe, Resend, Chorus Pro, Yousign, GoCardless, Gotenberg/PDF D-4, DPA), temps réel
(absent de mon banc), `plpgsql_check` (installation impossible, réseau), inscription/onboarding réels (la
passerelle n'a pas de GoTrue), mobile sur société remplie, parcours caisse au clavier, signature expert paie
(D-G), recette papier P0-08, production.

## 5. Notes sur 10

| Module | Note |
|---|---|
| Socle base, chaînages, intégrité | 9,5 |
| Sécurité & isolation (RLS, rôles, anonyme) | 9,5 |
| Qualité de code & CI (tsc, lint, tests, build) | 9,5 |
| Comptabilité (89 écrans) | 8,5 |
| Ventes | 8,5 |
| Tableaux de bord / Reporting / Rapports | 8,5 |
| Projets | 8,5 |
| Banque & Trésorerie | 8 |
| Achats | 8 |
| Production | 8 |
| Caisse (POS) | 7,5 |
| RH & Paie (+ portail salarié) | 7 |
| Accès / onboarding / portail | 7 |
| CRM | 6,5 |
| Paramètres & Système | 6 |
| Stock | 5,5 |
| **Moyenne générale** | **7,8** |
