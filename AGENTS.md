# AGENTS.md — Onusuite/compta

## Reste ouvert — au 26 septembre 2026

**Le point d'entrée pour reprendre : [`doc/audit/RESTE-OUVERT-2026-09-26.md`](doc/audit/RESTE-OUVERT-2026-09-26.md)**
(ce qui attend une décision, ce qui vit hors du dépôt, les charges restantes, les
deux échecs encore inscrits au registre de la CI). L'essentiel en six lignes :

* **≈ 147 j restants** : plan correctif **W5 / W7 / W8 + 9 transverses** (≈ 16 j),
  chaînages **L1 → L24** (≈ 116 j), couverture d'audit phase 10 (≈ 15 j).
* **Deux défauts encore rouges au registre** (`app/sql/ci/expected_failures.sql`) :
  `231 M-17-01` (la refacturation des temps — **W8**) et `245 T08` (le CA non
  taxé absent de la CA3 — **W7**). La CI **échoue** si l'un se met à passer : la
  ligne doit être retirée dans le commit du correctif.
* **Décisions qui bloquent** : `D-4` (`generate-pdf` : rebrancher ou supprimer —
  le défaut appliqué est « non déployée »), `D-5` (OCR), `D-7` (contraste),
  `D-10`, `D-11` (localisation), `D-13`.
* **Hors du dépôt** : les secrets et la recette des neuf intégrations (Chorus Pro,
  Yousign, GoCardless, Resend, EFI, SIRENE, VIES, Stripe, Gotenberg) ; la clé
  `sb_secret_…` à tourner ; les secrets E2E ; l'expert-comptable ; les 14
  documents djiboutiens ; les pilotes. Ce qui est **prouvé** en attendant est dit
  dans le tableau B du document.
* **Recette à l'écran (P0-08)** : 14 parcours à passer — un passage obligé, pas
  une charge de développement.
* **Rappel de méthode** : un défaut = un test **rouge avant**, une migration qui
  se **constate** (un numéro ne se réserve pas), le câblage CI et la preuve dans
  **le même commit**. Le travail non commité n'existe pas.

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

### Vagues W2 et W3 — inaltérabilité de la caisse et chemins d'annulation (2026-09-24) ✅
- **W2 / POS-01→04 (250)** : un ticket de caisse « inaltérable » se réécrivait
  (120 € → 12 €, empreinte inchangée), ses lignes se modifiaient et se
  supprimaient, le numéro était attribué par `MAX+1` sans verrou, `created_at`
  venait du client (et un ticket dont le client omettait la société recevait un
  hachage calculé sur NULL, donc une chaîne invalide) ; le statut n'était pas
  contraint, donc une vente pouvait sortir de la clôture en silence. La **250**
  pose la garde d'inaltérabilité (montants, date, numéro, empreinte — pour
  l'appel direct **et** pour le propriétaire de la table), l'unicité
  `(tenant, caisse, numéro)` sous `pg_advisory_xact_lock`, la reprise des
  doublons (numéros **et** empreintes recalculés), et la sortie honnête
  `void_pos_ticket()` (tracée, événement NF-525, refusée après clôture — un
  avoir corrige alors). `cancelPosTicket()` de l'écran passe par cette RPC.
  11 scénarios, **vus rouges avant** (0 vert), **11/11 après**.
- **W3 / S-12, S-13 (251)** : annuler une réception reçue ne remettait ni le
  stock, ni la couche de valorisation, ni l'écriture, et le statut `received`
  était rejouable ; un contrôle qualité en échec rebutait **tout** le reçu
  (10 rebutés pour 3 contrôlés) sur un mouvement sans dépôt (l'article baissait,
  le dépôt non). La **251** contrepasse l'annulation (sortie miroir au même
  coût + écriture inverse au journal ST, l'écriture d'origine restant intacte),
  refuse la réédition d'une réception comme la double contrepassation, et ne
  rebute que la quantité contrôlée (ou rebutée), au dépôt de la réception.
  6 scénarios : 2 verts de non-régression, **4 rouges avant**, **6/6 après**.
- **Contrôles et suites** : `check_anon_grants`, `check_tenant_guard`,
  `check_status_writes`, `check_trigger_reachability`, `check_composite_fks`,
  `check_policy_duplicates`, `check_roles_opposables` verts après les deux
  migrations ; batterie complète (54 suites + 8 contrôles, base neuve
  **223 migrations, 0 erreur**) verte, hors les deux rouges du registre
  (`231 M-17-01`, `245 T08`). `tsc -b` exit 0, `oxlint` 0 avertissement.
- **Numéros** : `245`→`249` étaient déjà pris (TVA, cumuls de paie, seconde
  passe des clés composites). W2 prend **250**, W3 prend **251** ; les vagues
  suivantes prennent le premier numéro libre **au moment de leur exécution**
  (252 est déjà pris par le socle des chaînages, `252_chain_socle.sql`) — un
  numéro se constate dans le dépôt, il ne se réserve pas.
- Preuves : `doc/audit/VAGUE-W2-W3-2026-09-24.md` (mesures d'entrée, batteries,
  limites dites).
- ⚠️ **Incident de session, et ce qu'il apprend** : une synchronisation externe
  (iCloud/Desktop) a remplacé le dossier `app/sql` par un état antérieur —
  fichiers **non suivis** perdus (`237`→`249`, `ci/check_composite_fks.sql`,
  `ci/check_roles_opposables.sql`) et quatre modifications non commitées
  perdues avec eux. Tout a été restauré depuis les checkpoints de l'éditeur
  (`5e37af8` pour les fichiers suivis, `e876c08` pour les non suivis), mais la
  leçon est celle du plan (`AUD-X02`) : **le travail non commité n'existe pas**.

### Dettes de W2/W3 soldées, et le plan par phases (2026-09-24) ✅
- **`253` — annulation d'un BL expédié** (le pendant de la 251 côté vente) : sortie
  miroir au coût que la comptabilité a sorti, écriture inverse au journal ST,
  l'écriture d'origine intacte, refus de la double contrepassation. Le coût de la
  sortie d'origine n'est pas toujours posé (la comptabilité dérive le CUMP) :
  recopier `0` ne créait ni couche ni écriture — mesuré, puis corrigé dans la
  même migration avant son commit. 5 scénarios, **T02/T03/T05 rouges avant**.
- **`254` — une seule vérité de valorisation** : la comptabilité sort au **CUMP**
  pendant que les couches consommaient en **FIFO** (100 € d'écart mesuré sur un
  cas de 100@10 + 100@14). Les couches portent désormais le CUMP, la quantité
  consommée reste FIFO. Le TEST 3 de `173` est **réécrit** dans le même commit —
  doctrine changée, test non vidé. 5 scénarios, 3 rouges avant.
- **`255` — l'avoir d'un ticket de caisse clôturé** : la 250 refusait d'annuler
  après clôture et renvoyait vers « un avoir » qui n'existait pas. Le schéma
  interdit les montants négatifs sur `pos_tickets` (`*_nonneg`) : l'avoir est une
  **pièce commerciale** (`credit_notes`), créée puis validée quand elle peut
  l'être, avec les lignes de la vente ; le stock revient au CUMP, la vente passe à
  `refunded` (montants et empreinte intacts) et l'événement NF-525 est écrit.
  5 scénarios (dont une vente sans client : refusée — un avoir crédite quelqu'un).
- **Formulaire de contrôle qualité** : `quantity_checked` / `quantity_rejected` et
  le statut « partiel » sont exposés (fr / en / ar).
- **Le reste à faire et le plan par phases** :
  `doc/audit/RESTE-A-FAIRE-ET-PLAN-PHASES-2026-09-24.md` — **≈ 169 j restants**
  (34 défauts du plan correctif + 25 lots de chaînages + la couverture d'audit),
  en **10 phases**, avec les charges, les dépendances, les critères de sortie et
  les décisions qui bloquent.
- ⚠️ **Mesuré le 24/09 sur base neuve** : le socle des chaînages
  (`252_chain_socle.sql`, session parallèle) fait **échouer la suite 105**
  (`permission denied for table chain_traces_2026_09`) — les partitions
  `domain_events_*` / `chain_traces_*` sont à traiter (GRANT + RLS) avant son
  commit, sinon la CI tombe sur l'isolation.

### Vagues W4 et W9 — la paie, puis le chaînage de l'absence (2026-09-26) ✅
- **W4 / RH-05 → RH-10 (256)** : quatre conventions mensuelles contradictoires
  (retard `weekly_hours × 4,33`, congé sans solde `/ 30`, heures sup `/ 151,67`,
  front `/ 21`), un import qui échouait cinq mois sur douze (`-31` refusé par
  PostgreSQL, 22008), une note de frais entrée en paie pour 0 (`Number(exp.amount)`,
  colonne inexistante), sans TVA ni écriture, un congé à cheval sur deux mois omis,
  et des titres-restaurant doublés au réimport. **Un** diviseur par société
  (`payroll_legal_parameters`, défaut calculé `35 × 52 / 12` et `5 × 52 / 12`),
  index unique `(société, salarié, période, type, source, source_id)`, notes de
  frais au grand livre (D charge HT + D TVA / C 421). 8/8 scénarios, 17 tests
  Vitest. [Preuve](doc/audit/VAGUE-W4-2026-09-26.md)
- **W9 / TRV-01 → TRV-16 (263, 264, 265, 266)** : les quatre sources d'absence
  (congé approuvé, arrêt de maladie, arrêt de travail, pointage d'absence —
  `timesheets.absence_type` existait depuis la 104 et **n'était écrite par
  personne**) ne se parlaient pas ; rien ne lisait l'absence en aval ; **deux**
  chemins de retenue existaient pour la même journée, dont un **inerte** (il
  écrivait `unpaid_absence_deduction`, un type qu'aucun moteur de bulletin ne
  lit) ; `leave_rules.affects_pay` n'était lu par personne. La **263** pose le
  registre `employee_absence_days` (un jour, un salarié, une vérité), le journal
  des conflits, le recalcul idempotent et l'API de lecture ; la **264** rend le
  registre opposable (pointage, heures supplémentaires, temps projet, frais,
  tâches) et pose le contrôle quotidien ; la **265** ramène la paie à **un seul**
  chemin (une retenue par journée, identifiant `day_uid` déterministe,
  contre-passation d'un élément déjà intégré, régularisation d'une période close,
  et rattachement au classeur des éléments posés avant lui) ; la **266** traverse
  cinq modules en **34 assertions** (une absence d'un jour apparaît **une fois**
  dans la paie, la DSN, le coût projet et le plafond). Base neuve **231
  migrations, 0 erreur** ; **63/63 suites**, 8/8 contrôles ; front `tsc` 0,
  `oxlint` 0, i18n fr/en/ar, **Vitest 1 474**. Le **T04 de la 256** est réécrit
  dans le même commit (doctrine changée : la retenue est indexée sur la journée,
  pas sur le document source). [Preuve](doc/audit/VAGUE-W9-2026-09-26.md)
- **Cohérence UI ↔ base, sur cette vague** : quatre écritures de
  `leave_balances` retirées du front (elles doublaient le déclencheur), le
  cinquième diviseur `/ 21` de la provision de congés ramené sur
  `payroll_divisors()`, une seule liste de types de congé pour les trois écrans
  (`special` était offert et refusé par la base), `affects_pay` et
  `requires_justification` enfin exposés dans l'écran des règles, et un écran
  **`/hr/absence-anomalies`** (TRV-16) qui lit le contrôle sans rien réparer tout
  seul.

### Vague W6 — les fonctions Edge et les écrans placebos (2026-09-26) ✅
- **Les deux baselines gelées par W0 sont à ZÉRO** : `check-written-columns`
  **20 → 0** et `check-unchecked-writes` **25 → 0** (notes réécrites, le plafond
  ne peut toujours que baisser).
- **`257` — les colonnes que les fonctions croyaient écrire** : `cron-payment-reminders`
  écrivait trois colonnes absentes de `collection_reminders` (la relance n'était
  jamais tracée), `request-signature` cinq absentes de `electronic_signatures`
  (la demande n'était **jamais enregistrée**), `submit-e-invoice` quatre
  `e_invoice_*` absentes d'`invoices` (**double envoi**), `sync-bank-transactions`
  un `provider_transaction_id` absent, `handle-stripe-webhook` un `metadata`
  absent, et le front `leave_requests.manager_comment` /
  `bank_transactions.matched_line_id`. La migration pose les colonnes réelles
  **avec leurs garanties** (unicité `(société, compte)` sur
  `provider_transaction_id`, clé composite `matched_line_id` →
  `journal_lines`, énumérations élargies de `collection_reminders` — le niveau 4
  « procédure de recouvrement » **ne pouvait pas être enregistré**) et aligne le
  code là où un équivalent existait (`http_status` → `response_code`,
  `provider_requisition_id` → `provider_connection_id`, `link_url`/`user_id` →
  `metadata`). 8/8 scénarios, **8 rouges avant**.
- **`258` — une relance de paiement part une fois** : `.single()` sur une
  recherche vide interrompait **tout le cron** dès la première facture (`EF-01`),
  et l'enregistrement raté sans lecture d'erreur faisait **relancer le client
  tous les jours**, niveaux « mise en demeure » compris (`EF-02`). Reprise des
  doublons (ramenés à une, `cancelled` avec la raison — aucune suppression),
  unicité partielle `(société, facture, niveau)`, `claim_collection_reminder()`
  (prise **avant** l'envoi, `NULL` si déjà prouvé, reprise possible d'un échec) et
  `finalize_collection_reminder()` (un seul chemin « envoyée »/« en échec »,
  réservé au `service_role`). 5/5 scénarios.
- **`259` — un écran ne peut plus tamponner un succès** : `submitEdiTva`
  fabriquait `EDI-<Date.now()>` et `syncBankConnection` tamponnait
  `last_sync_at` **sans rien transmettre** ; `EInvoicePage` ne soumettait rien.
  Les trois écrans passent par les fonctions Edge (et **lèvent** sans
  confirmation) ; la base refuse à `anon`/`authenticated` tout changement de
  `vat_returns.edi_status`, `invoices.e_invoice_status` et
  `bank_connections.last_sync_at`. 3/3 scénarios.
- **Erreurs lues partout** : les 7 écritures muettes d'`outgoing-webhooks`
  (dont le journal de livraison qui écrivait `http_status` au lieu de
  `response_code`), les 5 des fonctions d'e-mail (`try { await } catch {}` ne
  suffisait pas : PostgREST **ne lève pas**, il rend `{ error }`) et les 13
  écritures du front attribuées à d'autres vagues — `throw` quand la donnée est
  indispensable, `console.error` explicite quand l'écriture est réellement
  best-effort.
- **Cohérence UI ↔ backend, vérifiée** : nouveau
  `app/src/lib/__tests__/edge-wiring.test.ts` (8 tests) — chaque écran appelle la
  fonction Edge attendue, lève sans confirmation, et **aucune écriture directe**
  de `edi_status`/`e_invoice_status`/`last_sync_at` ne subsiste dans `src/`
  (miroir statique de la porte SQL). Relevé : 8 fonctions Edge appelées par le
  front ; restent sans appelant `request-signature`, `validate-vat-vies`,
  `verify-iban`, `verify-siret`, `generate-pdf` (phase 10 — fonctions sans porte
  d'entrée, pas placebos).
- Base neuve **234 migrations, 0 erreur** ; **66/66 suites**, 8/8 contrôles ;
  `check_plpgsql` **rejoué localement** (0 erreur, 34 avertissements) ;
  `tsc` 0, `oxlint` 0, parité i18n fr/en/ar, **Vitest 1 488**, **32 tests Edge**
  (`npm run edge:test` — Deno requis, sinon `npx -y deno test …`).
  [Preuve](doc/audit/VAGUE-W6-2026-09-26.md)
- **Seconde passe — tout ce qui restait ouvert est fermé** :
  - **« un jeton, une réponse » exécuté** : harnais Deno
    (`app/supabase/functions/__tests__/`, `serve` et le client Supabase
    remplacés, ni base ni réseau) → **30 tests**, dont le contrat d'entrée des
    **20 fonctions**. Deux **défauts réels** en sont tombés :
    **`refresh-exchange-rates` lisait le jeton sans jamais le comparer**
    (n'importe qui déclenchait la mise à jour des taux → la clé de service est
    désormais exigée, celle que pg_cron envoie déjà) et
    **`ai-import-mapping` refusait tous les appels du front** (la fonction exige
    un jeton, `aiImportMapping.ts` n'en envoyait aucun : le repli IA n'a
    **jamais** pu fonctionner) ;
  - **les cinq fonctions sans appelant ont une porte d'entrée** :
    `verify-siret` et `validate-vat-vies` dans **Paramètres → Société**,
    `verify-iban` dans **Comptes tiers → Banques**, `request-signature` dans
    **Documents du salarié** — chacune dit ce qu'elle a vérifié et **où** (« à la
    source » INSEE/VIES, ou « format et clé seulement ») ; `generate-pdf` reste
    **non déployée** (défaut de la décision `D-4`) et son code est durci (HTML
    client refusé — SSRF `AUD-H03`, valeurs échappées, 2 tests) ;
  - **le déploiement cesse d'être tout en `--no-verify-jwt`** :
    `deploy-all-functions.sh` distingue **13 fonctions à JWT vérifié par la
    passerelle**, **6 points d'entrée publics** (garde propre) et **1 non
    déployée**.

### Bugs corrigés
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
