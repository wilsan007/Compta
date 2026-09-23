# Reste à faire : plan complet au 22 septembre 2026

> **Objet** : tout ce qui reste à faire pour que le produit soit juste, déployé, prouvé et vendable à Djibouti, **dans l'ordre où le faire**.
> **Point de départ** : vagues V1, V2 et V3 du [plan correctif](PLAN-CORRECTIF-AUDIT-2026-09-21.md) exécutées ; lots A à G traités ; registre des défauts connus vide ; liste blanche PostgREST vide.
> **Branche** : `commercial-hr-paie`, phase 1 commitée (`fix(compta): phase 1 du reste-à-faire — résultat, acomptes, amortissements, reports`). **Production** : **schéma à la migration 227 depuis le 23/09** (déployée le 23/09 au soir — voir P0-07).
> **Sources** : [plan correctif](PLAN-CORRECTIF-AUDIT-2026-09-21.md) (§ 6, journal des vagues), [suivi](SUIVI-CAHIER-CORRECTIF.md), [cahier de localisation](../localisation/CAHIER-DES-CHARGES-LOCALISATION.md), [plan de perfection](PLAN-PERFECTION-9.5.md), mesures relevées dans le dépôt le 22/09.

> **Avancement du 23/09 (fin de journée)** — **phase 1 close** :
> - **R-09 ✅** l'état de rapprochement devient un écran (223) et le pointage écrit les **deux** côtés ; **R-10 ✅** lecteur OFX (SGML et XML), contrôle de devise, solde de clôture repris à l'import, fixtures de relevés réels — et **deux lecteurs faux** (CFONB 120 : dates, montants et libellés ; MT940 : date de valeur) corrigés, trouvés par ces fixtures (§ 4.2). **La phase 1 est close, R-15 et R-16 compris** : les deux sessions parallèles ont livré et sont commitées (`f948fe9` pour la TVA autoliquidée — migration **197** —, `d980c5a` pour le contrôle des clés i18n) ; vérifié le 23/09 au soir : 197 rejouée 7/7, job CI « i18n (parité fr/en/ar + clés utilisées) » vert, `toast.loadError` 0 occurrence dans `src/`.
> - **P0-06 reprise et prolongée** sur la copie de production : les **13 migrations 214 → 226** puis la **227** (garde de société, autre session) passent sans erreur — **34 suites SQL vertes** (179 et 218 échouent sous le rôle `postgres` non superutilisateur à cause de `session_replication_role` ; elles passent sous `supabase_admin`), `plpgsql_check` 0 erreur, contrôle de trigger atteignable OK. Chaîne complète rejouée **sur base neuve : 202 migrations, 0 erreur**.
> - **Réserve de méthode, mesurée** : la copie de répétition restaure les fonctions mais **pas leurs ACL** (restauration sous un rôle non propriétaire). `ci/check_tenant_guard` y signale donc **14 fonctions sans garde de société** qui n'en manquent pas en production : `pg_proc.proacl` relu **sur le cloud** montre `create_invoice_atomic` refusé à `anon` et `seed_vat_accounts` refusé à `anon` et `authenticated`, exactement l'état voulu par les migrations. **Le contrôle doit être lu sur la production après déploiement (P0-09), jamais sur la copie.**
> - **P0-07 ✅ le 23/09 au soir** : sauvegarde (`prod-20260923-avant-deploiement`, restaurée et vérifiée), puis les **29 migrations 189 → 227 appliquées à la production sans aucune erreur**. Contrôles : 369 tables, 343 fonctions, 1 788 policies, `plpgsql_check` 0 erreur, trigger atteignable OK, **garde de société OK** (81 fonctions, aucune exposée sans contrôle), **96/96 RPC de l'écran présentes**. **P0-09 ✅** : inscription réelle sur le cloud — 712 comptes, 10 journaux, 1 exercice, 1 utilisateur + fiche salarié, puis société et utilisateur supprimés. **P0-08 reste 👤** : les 14 parcours à l'écran, après déploiement du front.
> - **Plan de retour arrière** : restauration testée ; **piège mesuré** — une restauration ne rend pas les ACL (`pg_dump` + `ALTER DEFAULT PRIVILEGES` de l'image re-accordent `anon`/`authenticated` à la création) : rejouer `sql/78_revoke_anon_and_rls_verification.sql` après toute restauration.
> - **Mesure avant déploiement (cloud, schéma 188)** : **254 fonctions publiques exécutables par `anon`** (dont 211 `SECURITY DEFINER`) ; après déploiement **286 sur 343** — la hausse vient des 69 fonctions créées par les 189 → 227, chacune révoquée ou gardée selon son usage (le contrôle de garde, lui, est passé de « 14 exposées » sur la copie à **0 sur le cloud**).
>
> **Avancement du 22/09 (après-midi)** — phase 0, étapes P0-01 à P0-05 :
> - P0-01 ✅ lot I (i18n) et 197 (TVA) intégrés ; P0-02/03 ✅ V3 commitée seule (`0dd4e1a`), instantané rejoué seul (181 migrations) ; P0-04 ✅ 200-202 (`af5b5cb`), puis `2dc9bb8` (plafonds knip et tables non lues, dépassés depuis 187), `d980c5a` (lot I), `f948fe9` (197), `3a4f30b` (UX-03 : `window.confirm` de l'écran de plans) ;
> - P0-05 ⏳ poussé ; premier run : tout vert sauf UX-03 (corrigé en `3a4f30b`) et la 189, qui dépasse 15 min en CI : le correctif de performance des états est dans la copie de travail de la session V2 (« lancer v2 »), à commiter ;
> - **P0-06 ✅ faite le 23/09** sur copie de production fraîche (conteneur `prod_copy_20260923`, sauvegarde `~/onusuite-backups/prod-20260923-avant-migration`) : les **15 migrations 189 → 213 passent sans erreur** sous le rôle `postgres`, `plpgsql_check` 0 erreur, 12 suites vertes, inscription France et Djibouti réussies (712 comptes, pack FR provisoire pour DJ), facture de bout en bout équilibrée. **Deux défauts trouvés, invisibles en CI** : (1) `bootstrap_tenant` exécutable par `anon` en prod — dérive de la 183, corrigée par la **215** ; (2) le numéro légal reprenait le **libellé libre** de l'exercice (`FAC-FY2026-000001`, `FAC-EX2024-000001` selon les sociétés) — corrigé par la **216**, qui impose l'année. **D-12 tranchée** : aucun numéro existant au format `FAC-<année>-nnnnnn` (les actuels sont à 3 chiffres), la séquence peut démarrer à 1.
> - P0-07 ✅ (déployée le 23/09 au soir, 189 → 227, 0 erreur) · P0-09 ✅ (AUD-B00 sur le cloud) · **P0-08 👤** (14 parcours à l'écran, à faire après déploiement du front)
>
> **Contrôle indépendant du 23/09** — 215 et 216 rejouées par mes soins sur base neuve de CI (stubs + instantané + **191 migrations, 0 erreur**) : **215** rouge → verte → **idempotente** (droit `anon` rendu à la main puis révoqué ; `authenticated` et `service_role` conservés) ; **216** 4 scénarios sur 4 verts. Mais **la 216 laissait un défaut de même nature** : `posting_number` — le numéro d'écriture, **exporté au FEC comme numéro de pièce** (`FECExportPage.tsx:32`) — concaténait encore le libellé libre de l'exercice. Mesuré en clair sur la copie de production : `AN-EX2024-000001`, `BQ-EX2024-000001`, `OD-EX2024-000001`, `VT-EX2024-000001` à côté de `VT-2026-000342`. Corrigé par la **217** (même fonction `fiscal_year_number_segment` que la 216 ; `sql/217_posting_number_year_tests.sql`, **P01 à P05 vus rouges avant** : `OD-FY2026-000001`, `OD-Exercice courant-000001`). Les numéros déjà attribués ne sont pas touchés, comme en 216 — un FEC déposé y renvoie. **Deuxième défaut trouvé en chemin** : les types générés étaient restés en arrière depuis la **214** (`purchase_order_lines.line_order` absent), ce qui fait échouer l'étape CI « Vérifier que les types sont à jour » — régénérés et commités. **Nuance sur D-12** : la mesure confirme qu'aucun numéro existant n'est au format `FAC-<année>-nnnnnn` (les anciens sont à 3 chiffres, `FAC-2024-001`), donc pas de collision de chaîne ; mais pour une société reprise qui a déjà `FAC-2024-001` à `FAC-2024-005`, la séquence repart à `FAC-2024-000001` — « numéro 1 » réutilisé dans le même exercice, à défaut de collision. C'est l'option (a) de D-12 (reprendre après le plus grand numéro) qui l'évite ; elle reste à trancher.
> **Avancement du 22/09 (soirée)** — phase 1, dettes des vagues V1 à V3 :
> - **R-01 ✅** amortissements, écarts de lettrage et reports d'avance réparés (migration **211**) : les trois fonctions inséraient leur en-tête en `posted` (refusé depuis la 187) ; elles écrivent désormais en brouillard puis valident, avec les comptes du plan (`681200`/`281000`, `486000`, `487000`), et l'écart de lettrage produit une écriture **équilibrée** (charge d'écart + contrepartie de tiers). `post_deferred_charge` attend l'identifiant de `regularization_entries` : l'écran l'envoyait, la fonction cherchait dans `journal_entries` — 16 scénarios dans `sql/211_asset_deferred_tests.sql`, 2 tests d'écran ;
> - **R-02 ✅** affectation du résultat obligatoire avant la clôture suivante (écran, garde dans `close_fiscal_year`, 19 scénarios de la 179, 3 tests d'écran) ;
> - **R-03 ✅** factures d'acompte en 4191 et déduction sur la facture finale (210, 12 scénarios) ;
> - **R-04 ✅** paiement de la paie (migration **212**) : `post_payroll_payment` verse le net (D 421 par salarié, auxiliaire, **lettré**), les organismes (431), l'impôt (447) et les acomptes (425), par périmètre idempotent ; le lot ne passe à « payé » que quand tout est versé. Deux défauts de plus corrigés : statut `processing` refusé par `pay_runs` et statut `processed` inexistant écrit par l'intégration des acomptes — 9 scénarios (`sql/212_payroll_payment_tests.sql`, 9 rouges avant), 2 tests d'écran ;
> - **R-08 ✅** fenêtre de règlement partagée (date, montant, mode, compte bancaire) pour « Marquer payée » dans les ventes et les achats, au lieu du virement implicite en 512000/BQ — tests d'écran des deux pages mis à jour ; décision **D-10** à confirmer formellement ;
> - **R-05 ✅** avoirs sans article : contrepassation au prorata des comptes de la facture d'origine (migration **213**) — le chiffre d'affaires par activité était faux, 6 scénarios dont 4 rouges avant ;
> - **R-06 ✅** réception partielle : l'allocation suit l'ordre de saisie des lignes (`line_order`, migration **214**) et non plus l'ordre aléatoire des uuid — 3 scénarios ;
> - **P0-05 ⏳** performance de la 189 : cause trouvée et mesurée. Les états financiers (bilan, balance, compte de résultat, tendance) sont réécrits — écritures du périmètre figées, lignes lues par `journal_id` — et ils sont **SECURITY DEFINER** (comme le bilan) : 0,8 s pour la balance et 0,1 s pour le compte de résultat à 100 000 écritures. Le dépassement de 15 min venait des **contrôles du fichier de test** : sous RLS, avec des statistiques pas encore rafraîchies après le chargement, le planificateur estime « 1 ligne » pour la société et part en boucle imbriquée (**39 s** pour un seul contrôle à 20 000 écritures, contre 99 ms avec des statistiques à jour). Le fichier fait désormais `ANALYZE` après son chargement et fige les écritures avant de lire les lignes. **Mesure du 22/09 au soir sur base neuve : 100 000 écritures en 2 min 20 (validation 1 min, clôtures 3,2 s et 2,4 s), 7 scénarios verts** — contre plus de 15 min avant.
>
> Chaîne complète rejouée sur base neuve le 22/09 au soir : **189 migrations, 0 erreur** ; 23 suites SQL, `plpgsql_check` (0 erreur), tsc, oxlint, i18n, knip (66/67), build Vite et **1 407 tests** unitaires au vert.

Légende : 🔴 bloquant · 🟠 résultat faux ou trompeur · 🟡 confort ou robustesse · 👤 action ou décision de votre part · ⏳ en cours dans une autre session

---

## Sommaire

- [0. Où on en est](#0-où-on-en-est)
- [1. Règles de travail (valables pour toute la suite)](#1-règles-de-travail-valables-pour-toute-la-suite)
- [2. PHASE 0 — Sécuriser et déployer l'acquis](#2-phase-0--sécuriser-et-déployer-lacquis)
- [3. Ce qui ne dépend que de vous](#3-ce-qui-ne-dépend-que-de-vous)
- [4. PHASE 1 — Dettes connues des vagues V1 à V3](#4-phase-1--dettes-connues-des-vagues-v1-à-v3)
- [5. PHASE 2 (V4) — Sécurité, ergonomie, preuve de bout en bout](#5-phase-2-v4--sécurité-ergonomie-preuve-de-bout-en-bout)
- [6. PHASE 3 — Modules jamais audités par exécution](#6-phase-3--modules-jamais-audités-par-exécution)
- [7. PHASE 4 (V5, lot K phase 1) — Localisation : neutralité du code](#7-phase-4-v5-lot-k-phase-1--localisation--neutralité-du-code)
- [8. PHASE 5 (V5, lot K phase 2) — Localisation : Djibouti](#8-phase-5-v5-lot-k-phase-2--localisation--djibouti)
- [9. PHASE 6 (après V5) — Localisation : autres pays](#9-phase-6-après-v5--localisation--autres-pays)
- [10. Recette finale](#10-recette-finale)
- [11. Calendrier, charge et chemin critique](#11-calendrier-charge-et-chemin-critique)

### Correspondance avec les vagues du plan correctif

| Vague du plan correctif | Phase de ce document | État |
|---|---|---|
| V1 (lots A, B, E01, C10, D07) | — | ✅ commitée, en prod |
| V2 (lots C, D) | — | ✅ commitée ; lot D pas en prod |
| V3 (lots E, F, G) | Phase 0 (commit, déploiement) + Phase 1 (dettes restantes) | ✅ faite, **non commitée** |
| **V4** (lots H, I, J) | **Phase 2** | ⬜ |
| — (non prévu par le plan) | Phase 3 : modules jamais audités | ⬜ |
| **V5** (lot K = cahier LOC) | **Phase 4** (LOC phase 1, neutralité, ≈ 48 j) + **Phase 5** (LOC phase 2, Djibouti, ≈ 26 j + textes + pilote) | ⬜ amorcée (201, 191) |
| après V5 | Phase 6 : autres pays (LOC phase 3) | ⬜ |

---

## 0. Où on en est

### 0.1 Ce qui est fait

| Vague | Contenu | État | Commit | En production ? |
|---|---|---|---|:---:|
| V1 | Inscription, RPC composées, `post_journal_entry`, compte de résultat (183–186) | ✅ | `646c4c9` | ✅ (jusqu'à 188) |
| V2 lot C | Noyau de saisie strict (187) | ✅ | `766608f` | ✅ |
| Resync prod | Alignement prod ↔ dépôt, runner TLS vérifié (188) | ✅ | `47c70fd` | ✅ |
| V2 lot D | Clôture, bilan, balance, résultat, test de propriété 100 000 écritures (189) | ✅ | `11e2b7f` | ❌ |
| V3 lots E, F, G | Ventes, paie, achats, stock, caisse, banque (190–196) | ✅ vérifié, **non commité** | — | ❌ |
| Plans par pays (session prod) | `mirror_*` en uuid (200), plan comptable par pays FR/DJ et écran admin CSV (201), tests (202) | ✅ indexé, **non commité** | — | ❌ |

**Mesures au 22/09 sur base neuve (rejeu 187 → 202)** : 183/183 migrations ; `plpgsql_check` 0 erreur ; suites SQL 102, 105, 166, 168, 170, 173, 175, 177 vertes ; 178 (23), 179 (17), 180 (22), 181 (7), 182 (8), 192 (15), 202 (13) entièrement vertes ; registre `expected_failures.sql` **vide** ; PostgREST **1 489 requêtes acceptées, aucune tolérée** ; `tsc -b` 0 ; oxlint 0 ; **1 400 tests unitaires** ; parité i18n ; build.

### 0.2 Ce qui est en cours ailleurs

| Session | Sujet | À surveiller |
|---|---|---|
| ✅ « Séparer TVA FR20 et autoliquidation » | terminée : migration **197** commitée (`f948fe9`), 7/7 verte — R-15 | — |
| ✅ « Détecter les clés i18n manquantes » | terminée : `check-i18n-usage.mjs` + étape CI (`d980c5a`) — R-16 | — |
| ⏳ session en cours (copie de travail **non commitée**, 23/09) | `formatCurrency` à la place de `… €` codé en dur (4 pages : sortie de salarié, ordres de fabrication, préparation de paie) et **mode strict dans `tsconfig.test.json` (SOC-03)** | Elle a ajouté `t('settings.api.rateLimit')` dans `ApiDocsPage.tsx` **sans créer la clé** : `check-i18n-usage.mjs` est **rouge** dans la copie de travail (vert à `HEAD`). À corriger avant son commit, sinon la CI tombe. |
| « Migration PostgreSQL 17 production » | 200 à 209 réservés ; migrations exécutées en prod : **136 à 188, ne plus jamais les modifier** | Elle a indexé ses fichiers dans l'index git **partagé** |
| « lancer v2 » | Lot D commité ; a pris 200+ un temps, puis y a renoncé | — |

### 0.3 Ce qui n'a jamais été vérifié

- **L'affichage réel dans le navigateur** : depuis V1, aucun écran modifié n'a été ouvert dans l'application, qui pointe sur le cloud (où 189 et suivantes ne sont pas déployées) et exige vos identifiants.
- **Les e2e** : les 5 fichiers de `app/e2e/` ne remplissent aucun formulaire et ne lisent aucun montant. Ils vérifient seulement que du texte s'affiche.
- **189 à 202 sur une copie de prod** : la prod diverge historiquement du schéma CI (115 migrations modifiées après exécution, cf. 188). Rien ne garantit que les reprises de données de 190, 192, 195 et 201 passent sur les vraies données.

---

## 1. Règles de travail (valables pour toute la suite)

1. **Rouge avant vert.** Tout correctif commence par un scénario (SQL `*_tests.sql` ou test d'écran) **vu en échec sur le code actuel**, puis vu vert sans modification. Un contrôle qui n'a jamais échoué ne prouve rien (cf. les cinq garde-fous faussement verts de la mémoire du projet).
2. **Ne jamais modifier une migration exécutée en production** (136 à 188 à ce jour, puis tout ce qui sera déployé). Une correction = une nouvelle migration.
3. **Numérotation** : faire `ls app/sql | sort -n | tail` juste avant de créer un fichier ; plages réservées : 190-199 (V3 et ses suites), 200-209 (session prod). Prendre **210+** pour la suite, ou se coordonner.
4. **Typecheck** : `npm run typecheck` (`tsc -b`). **`npx tsc --noEmit -p .` ne vérifie rien** : le `tsconfig.json` racine a `files: []`.
5. **Commits** : l'index git est partagé entre sessions. Commiter avec un index privé (`GIT_INDEX_FILE`), puis vérifier l'instantané seul avant `update-ref` (mémoire « Index git partagé entre sessions »).
6. **Chaîne de vérification complète** avant chaque commit touchant la base : rejeu sur base neuve → `plpgsql_check` → toutes les suites → `generate-db-types` → `check-embeds` (PostgREST réel) → typecheck, oxlint, vitest, i18n, build.
7. **Avant tout déploiement SQL** : répétition sur copie de prod (§ 2, P0-06).

---

## 2. PHASE 0 — Sécuriser et déployer l'acquis

**Objectif** : que tout le travail de V2 et V3 soit commité, passe la CI, soit répété sur une copie de prod, déployé, puis vérifié à l'écran. **Charge** : 2 à 3 jours, dont une fenêtre de déploiement.

### P0-01 — Intégrer les deux tâches parallèles ⏳ 🔴

| | |
|---|---|
| Quoi | Récupérer le résultat des sessions « TVA FR20/AUTOLIQ » et « clés i18n » quand elles se terminent |
| Risques | Conflits sur `src/i18n/locales/*/*.json`, `ci.yml`, `sql/ci/expected_failures.sql` ; numéro de migration de la session TVA |
| Vérifier | La migration TVA passe G10 (`192_purchases_treasury_tests.sql` : tout compte des écritures automatiques présent au plan semé) et 102, 178 à 182, 192 ; le nouveau contrôle i18n passe sur les écrans refaits en V3 (`InvoicesPage`, `PurchaseInvoicesPage`, `PurchaseCreditNotesPage`, `BankStatementImportPage`) |
| Fini quand | Les deux branches sont fusionnées dans la copie de travail et la chaîne complète (règle 6) est verte |

### P0-02 — Commiter V3 avec un index privé 🔴

Fichiers **à inclure** (V3 seulement) :
- `app/sql/190` à `196` ; `app/sql/192_purchases_treasury_tests.sql` ; modifications de `102_trigger_tests.sql`, `180_…`, `181_…`, `sql/ci/expected_failures.sql` (sections 180/181 vidées) ;
- `app/.embeds-allowlist.json` (liste vide) ;
- `src/lib/queries/{sales,misc,banking,stock,catalogAdvanced,socialDeclarations,accounting}.ts` (dans `accounting.ts` : **seulement les blocs AUD-G08**, les blocs V2 sont déjà commités) ;
- `src/lib/fileSecurity.ts` ; `src/pages/{InvoicesPage,QuotesPage,CreditNotesPage,PurchaseInvoicesPage,PurchaseCreditNotesPage,BankStatementImportPage}.tsx` ;
- `src/types/index.ts` (**seulement les blocs V3** : `CreditStatus`, `InvoiceLine.vat_code/vat_amount`, `Invoice.transferred_entry_id`, `PurchaseInvoice.supplier_reference/approval_status/transferred_entry_id`, `PurchaseInvoiceLine`, `PurchaseCreditNote.status`) ;
- `src/types/database-generated.ts` (à régénérer **après** commit de la session prod, voir P0-04) ;
- `src/i18n/locales/{fr,en,ar}/{sales,purchases,accounting}.json` (clés V3) ;
- tests : `SalesDocumentForms.test.tsx`, `PurchaseDocumentForms.test.tsx`, `server-posted-documents.test.ts`, `bank-statement-import.test.ts` ;
- `.github/workflows/ci.yml` (étape 192 seulement) ; `doc/audit/PLAN-CORRECTIF-AUDIT-2026-09-21.md` (section V3) et ce fichier.

Fichiers **à exclure** (session prod) : `200`, `201`, `202`, `ChartPacksAdminPage.tsx`, `chartPacks.ts`, `chart-packs-csv.test.ts`, `OnboardingCountries.test.tsx`, `OnboardingPage.tsx`, `countries.ts`, `App.tsx`, `SearchableSelect.tsx`, `locales/*/auth.json`, `locales/*/settings.json`.

Procédure : `GIT_INDEX_FILE=/tmp/idx-v3 git read-tree HEAD` → `git add` des seuls fichiers V3 (`git add -p` pour `accounting.ts`, `types/index.ts`, `ci.yml`) → `git write-tree` → `git commit-tree` → **P0-03** → `git update-ref`.

Message suggéré : `fix(compta): vague V3 du plan correctif — ventes, paie, achats, stock, caisse, banque (190-196)`.

### P0-03 — Vérifier l'instantané V3 seul 🔴

| | |
|---|---|
| Quoi | Extraire l'arbre du commit dans un dossier temporaire (`git worktree add` sur le commit) et y rejouer la chaîne complète **sans** les fichiers 200-202 |
| Attendu | 181 migrations (jusqu'à 196) ; mêmes résultats qu'en § 0.1, sauf 202 absent ; `database-generated.ts` identique à celui régénéré sur cette base |
| Piège | Si `database-generated.ts` a été régénéré avec 200-202 appliquées, il contiendra `chart_pack_status` : le régénérer sur l'instantané V3 seul avant le commit |

### P0-04 — Commit de la session prod (200-202) 🔴

Appartient à la session « Migration PostgreSQL 17 production ». À faire **après** V3 (ou avant, mais pas mélangé). Ensuite : régénérer `database-generated.ts` sur la chaîne complète et le commiter.

### P0-05 — Pousser et obtenir une CI verte 🔴

| Job | Attendu | Attention |
|---|---|---|
| `lint-typecheck` | vert | — |
| `i18n-check` | vert | le nouveau contrôle de la tâche i18n peut ajouter des échecs sur d'autres écrans |
| `unit-tests` | 1 400+ tests | — |
| `db-integration` | toutes les suites, dont **189 (≈ 70 s, 100 000 écritures)** et **192** | premier passage réel de 190-196 en CI (PostgreSQL 16 du service GitHub) |
| `build` / `deploy` | `deploy.yml` n'est déclenché que si la CI réussit | ne pas déployer le front **avant** la base (P0-07) : le nouveau front appelle `convert_quote_to_invoice`, `post_payroll_journal`, `create_purchase_invoice_atomic` avec lignes, etc. |

### P0-06 — Répétition sur copie de prod de 189 → 202 🔴

Méthode : celle du 21/09 (mémoire « Répétition prod 21/09 », script `rebuild.sh`), soit `pg_dump` 17 en verify-full, restauration dans `supabase/postgres:17.6.1.143`, migrations jouées sous le rôle `postgres` **non superutilisateur**.

Vérifications **spécifiques aux reprises de données** (à faire avant, puis après) :

| Migration | Reprise | Requête de contrôle avant | Ce qui peut casser |
|---|---|---|---|
| 189 | index NF525, réécriture clôture | `SELECT count(*) FROM journal_entries` (durée de l'index) | durée de verrouillage sur une grosse table |
| 190 | création des comptes 512x/530x et des journaux BQn/CAn pour chaque `bank_accounts` existant | `SELECT tenant_id, count(*) FROM bank_accounts GROUP BY 1 HAVING count(*) > 1` | journal `BQ` déjà utilisé avec une autre contrepartie ; comptes `5121nn` déjà présents avec un autre libellé |
| 190 | nouvelle contrainte `credit_notes_status_check` (draft, validated, applied) | `SELECT DISTINCT status FROM credit_notes` | un statut hors liste en prod fait **échouer** la migration |
| 190 | index uniques partiels sur `document_number_sequences` | `SELECT tenant_id, prefix, count(*) FROM document_number_sequences GROUP BY 1,2 HAVING count(*) > 1` | doublon, échec de l'index |
| 192 | `supplier_reference := number` sur les factures d'achat existantes | — | aucun (colonne nouvelle) |
| 192 | contrainte `purchase_credit_notes_status_check` | `SELECT DISTINCT status FROM purchase_credit_notes` | statut hors liste |
| 192 | suppression de `bank_accounts_calculated_balance_nonneg` | — | aucun |
| 195 | contrainte `purchase_orders_status_check` (draft, confirmed, partial, received, cancelled) | `SELECT DISTINCT status FROM purchase_orders` | **un statut `sent` ou autre en prod fait échouer la migration** : prévoir la reprise dans une migration 197+ si nécessaire |
| 201 | pack DJ, `chart_pack_status`, `tenants.chart_pack_code` | voir la session prod | — |

Après les migrations :
- `plpgsql_check` sur la copie : 0 erreur ;
- suites 178 à 182, 192, 202 **sur la copie** (elles créent leurs propres sociétés de test) ;
- inscription d'une société FR et d'une société DJ (plan provisoire) par `create_tenant_for_current_user` ;
- sur une société réelle copiée : créer une facture avec lignes, la valider (numéro `FAC-<exercice>-000001` si la société n'a pas encore de séquence par exercice ; vérifier qu'il n'y a **pas de collision** avec des numéros existants au même format : `SELECT number FROM invoices WHERE number ~ '^FAC-\d{4}-\d{6}$'`) ;
- `check-embeds` contre un PostgREST branché sur la copie.

**Point à trancher avant déploiement** 👤 : des factures existantes en prod pourraient déjà porter des numéros au format `FAC-2026-000001` (compteur libre de `get_next_document_number`). Si c'est le cas, faire démarrer la séquence par exercice **après le plus grand numéro existant**, par une reprise dans une migration 197+.

### P0-07 — Déploiement en production ✅ (23/09 au soir)

1. Sauvegarde complète (`~/onusuite-backups`, comme le 21/09) et **test de restauration** de cette sauvegarde.
2. Fenêtre annoncée (les triggers de 190 et 192 changent le comportement de la saisie).
3. Runner : `DATABASE_URL` du pooler, `PGSSLROOTCERT=prod-ca-2021.crt`, TLS vérifié.
4. Ordre : 189 → 190 → … → 196 → (197+ éventuelles) → 200 → 201. Arrêt à la première erreur.
5. Contrôle immédiat : `sql_migrations_tracker`, `plpgsql_check`, inscription de test, facture de test **dans une société de test** puis suppression de la société.
6. Déploiement du front **seulement après** (P0-05).
7. **Plan de retour arrière** écrit avant la fenêtre : restauration de la sauvegarde, et front à la version précédente.

**Fait le 23/09 au soir** — fenêtre ouverte par vous, déploiement exécuté par mes soins :

1. **Sauvegarde** `~/onusuite-backups/prod-20260923-avant-deploiement` (7,9 Mo, 6 652 entrées, 182 migrations tracées) et **test de restauration réussi** dans un conteneur `supabase/postgres:17.6.1.143` : **362 tables, 3 sociétés, 10 factures, 22 écritures, 1 777 policies** — conforme à la production de départ.
2. **Rôle de connexion** : `postgres` du pooler, `PGSSLROOTCERT` sur le `ca.crt` de la sauvegarde, TLS vérifié (`verify-full`).
3. **Migrations** : les **29 en attente — 189 → 197, 200, 201, 210 → 227** — appliquées **sans une seule erreur** (« 29 succès, 0 erreurs »), chacune dans sa transaction, arrêt prévu à la première erreur. Le front n'a **pas** été déployé (la branche `commercial-hr-paie` ne déclenche pas `deploy.yml`, réservé à `main`/`master` : c'est le bon ordre).
4. **Contrôles immédiats sur le cloud** : 211 migrations tracées toutes `success` ; **369 tables** (362), **343 fonctions** (274), **1 788 policies** (1 777) ; `plpgsql_check` **0 erreur** (31 avertissements, les mêmes que sur base neuve) ; contrôle de trigger atteignable **OK** ; **garde de société OK — 81 fonctions examinées, 72 gardées, 9 inscrites, aucune exposée sans contrôle** (la 227 tient sur la production) ; **les 96 RPC appelées par l'écran existent toutes** en base (vérifié nom par nom) → le front peut être déployé sans appel manquant.
5. **AUD-B00** (P0-09) et le détail de la société de test : voir plus bas.
6. **Plan de retour arrière** : restaurer `prod-20260923-avant-deploiement` (testé), remettre le front à la version précédente. **Piège mesuré** : une restauration rend les **données** fidèlement mais **pas les ACL** — `pg_dump` décrit l'état final des droits (par exemple `REVOKE ALL … FROM PUBLIC; GRANT ALL … TO service_role;`) et le `ALTER DEFAULT PRIVILEGES` de l'image Supabase re-accorde `anon`/`authenticated` à la création : sur la copie restaurée, `seed_vat_accounts` et `create_invoice_atomic` redeviennent exécutables par `anon`, alors que la production les refuse. Après une restauration, **rejouer `sql/78_revoke_anon_and_rls_verification.sql`** (le `REVOKE … FROM anon` global) avant de rouvrir, sinon la base de secours est plus permissive que celle qu'elle remplace.

### P0-08 — Vérification à l'écran (jamais faite depuis V1) 🔴

Sur l'application pointant vers la base à jour, avec un compte de test. Chaque ligne : ce qu'on fait → ce qu'on doit voir.

| Écran | Parcours | Attendu |
|---|---|---|
| Inscription | Créer une société France, puis Djibouti | plan semé ; pour DJ : plan provisoire signalé ; autre pays refusé (`PAYS_NON_DISPONIBLE`) |
| Factures | Nouvelle facture 2 lignes (20 % et 5,5 %) → Valider → Envoyer | brouillon `BROUILLON-FAC-…`, puis `FAC-2026-000001` ; badge « Comptabilisé » ; écriture VT équilibrée |
| Factures | « Envoyer » un brouillon | la facture est validée d'abord (numéro définitif), puis envoyée |
| Factures | « Marquer payée » | règlement `REG-…`, facture payée, 411 lettré ; le bouton n'apparaît pas sur un brouillon |
| Devis | Nouveau devis → Convertir en facture | lignes et TVA reprises ; devis « transformé » |
| Avoirs | Avoir sur facture → Valider | `AV-2026-000001`, facture soldée ou réduite, lettrage |
| Factures d'achat | Nouvelle facture (référence fournisseur + lignes) → Approuver → Marquer payée | `ACH-2026-000001`, écriture AC, décaissement `DEC-…`, 401 lettré ; **tous les libellés traduits** (fr/en/ar) |
| Avoirs fournisseur | Nouveau → Valider | `AVF-…`, écriture AC inverse |
| Paie | Lot approuvé → « Générer l'écriture de paie » → passer à « payé » | une seule écriture PAIE, équilibrée ; message clair si un bulletin est incohérent |
| Import de relevé | Fichier MT940 / CAMT.053 / CFONB réel | « n opérations importées, m doublons écartés » ; lignes pointées automatiquement |
| Stock | Inventaire en baisse puis en hausse | stock dépôt = stock article ; écriture ST |
| Caisse | Session avec 2 tickets → clôture | stock du magasin seul décrémenté, une fois |
| Clôture (V2) | Exercice complet → clôture → bilan / compte de résultat | équilibrés, à-nouveaux corrects, bandeau rouge absent |
| Tout | Changer de langue (fr → en → ar) | aucune clé brute affichée ; arabe en RTL |

Livrable : captures d'écran jointes au suivi, et chaque écart devient un scénario rouge.

**Ce qui est levé, ce qui reste.** Les prérequis sont en place : la base est déployée (227), les **96 RPC** de l'écran existent, l'inscription réelle passe et provisionne (P0-09), les 34 suites SQL passent sur les données de production. Il reste à **déployer le front** sur cette base, puis à faire les 14 parcours ci-dessus à la main — c'est la seule partie qui ne peut pas être automatisée ici : elle demande un navigateur, un compte et des captures. Le contrôle « Import de relevé » peut être fait avec les **six relevés de `app/src/lib/__tests__/fixtures/`** (R-10) ; « Tout → changer de langue » se lit sur les mêmes écrans.

### P0-09 — AUD-B00 sur le cloud ✅ (23/09 au soir)

Après déploiement : créer une société de test par l'inscription réelle, compter comptes, journaux, exercices et paramètres, puis supprimer la société. Consigner le résultat dans le suivi.

**Fait sur la production déployée**, par le chemin réel : un utilisateur d'authentification est créé (API admin, adresse de test sans boîte → confirmation directe au lieu du courriel), il se connecte par mot de passe, puis appelle `create_tenant_for_current_user` — la RPC que l'onboarding appelle.

| Contrôle | Résultat |
|---|---|
| Réponse du provisionnement | `success: true`, `chart_pack_code: FR`, `chart_provisional: false` |
| Plan comptable | **712 comptes** |
| Journaux | **10** |
| Exercices | **1** |
| Séquences de numérotation | 0 — créées au premier document (attendu) |
| Utilisateur + fiche salarié | 1 + 1 |
| Suppression | société supprimée (`DELETE 1`, retour à **3** sociétés, **0** compte résiduel), utilisateur supprimé (HTTP 200) |

**Un faux positif, écarté en le poursuivant** : un premier appel avec `country: "FR"` — le **code** au lieu du **nom** — répond `PAYS_NON_DISPONIBLE` (« Le pays FR n'est pas encore disponible ») alors que la France l'est. `normalize_country_code` cherche par `legislation_packs.country_name` et n'accepte le code que par son second paramètre, que la RPC laisse à `NULL`. L'application envoie toujours le nom (`createTenantForUser` met `country: 'France'` par défaut, `OnboardingPage` aussi), donc **il n'y a pas de défaut en production** ; mais le message est trompeur pour un appelant direct. À reprendre le jour où l'API publique créera des sociétés : passer `p_data ->> 'country'` **aussi** en second argument.

---

## 3. Ce qui ne dépend que de vous

### 3.1 Actions

| # | Action | Pourquoi | Urgence |
|---|---|---|---|
| 👤-1 | **Faire tourner la clé `sb_secret_…`** dans le tableau de bord Supabase (suivi C8 / F1 / AUD-H05) | clé secrète restée en clair dans l'historique git (`setup-pg-cron.sql`) | 🔴 immédiate |
| 👤-2 | Renseigner les secrets E2E dans GitHub (`E2E_SUPABASE_URL`, `E2E_SUPABASE_KEY`, `E2E_TEST_EMAIL`, `E2E_TEST_PASSWORD`) sur un **projet Supabase de test**, jamais la prod | sans eux, les e2e s'abstiennent | 🔴 avant V4 |
| 👤-3 | Ouvrir la fenêtre de déploiement (P0-07) | — | 🔴 |
| 👤-4 | Désigner l'**expert-comptable référent** (Djibouti et revue des états financiers) | condition de la recette finale et du lot K | 🔴 |
| 👤-5 | Lancer la **collecte des 14 documents officiels djiboutiens** (LOC2-03) : code général des impôts, loi de finances en cours, textes TVA, barème ITS, taux CNSS/AMU, code du travail, plan comptable national, modèles de liasse, etc. | délai externe le plus long du projet | 🔴 dès maintenant |
| 👤-6 | Identifier **2 à 3 entreprises pilotes** à Djibouti | LOC2-39 : une clôture mensuelle complète | 🟠 |

### 3.2 Décisions encore ouvertes

| # | Question | Options | Qui en dépend |
|---|---|---|---|
| D-3 | Affectation du résultat (plan § 5, n° 3) | ✅ **tranchée le 22/09** : écran d'affectation obligatoire avant de clore l'exercice suivant | R-02, fait |
| D-4 | `generate-pdf` (AUD-H03, SSRF prouvée) | (a) supprimer le paramètre `html`, (b) Gotenberg durci, (c) **retirer la fonction** (aucun appelant) | H03 |
| D-5 | Import OCR via OpenAI (AUD-H04) | garder avec consentement explicite par société, remplacer, ou retirer | H04 |
| D-6 | Rôles utilisateurs (7 politiques RLS sur 2 296 regardent le rôle) | **généraliser le rôle dans la RLS** (chantier), ou documenter que les rôles ne sont qu'un confort d'affichage | H08 |
| D-7 | Contraste H2 / H3 (18 + 20 usages juste sous 4,5:1) | éclaircir les **fonds** des pastilles et des zones grises | I05 |
| D-8 | Trop-payé fournisseur en 4091 : j'ai appliqué la décision n° 1 par symétrie | confirmer ou préférer le refus | déjà en place |
| D-9 | Factures d'acompte (R-03) | ✅ **tranchée le 22/09** : acompte en 4191 et imputation sur la facture finale (norme) | R-03, fait |
| D-10 | « Marquer payée » sans choix de banque (R-08) | ✅ **implémentée le 22/09** : fenêtre de règlement (date, montant, mode, compte bancaire) — reste à confirmer formellement | R-08, fait |
| D-11 | Localisation (cahier LOC) | périmètre secteur public (couche `DJ-EP` seule, ou aussi `DJ-ADM` : 8 à 10 semaines) ; arabe dès la v1 ; groupes multi-pays hors v1 | phase 5 |
| D-12 | Numérotation existante en prod (P0-06) | ✅ **tranchée et vérifiée le 23/09 : option (a)**, reprendre après le plus grand numéro existant — migration **218** ; preuve sur données de production : la société reprise `…0001` (EX2024, aucune séquence) passe de `FAC-2024-000001` (déjà pris) à **`FAC-2024-000006`** | 218, fait |
| D-13 | Périmètre de la séparation des tâches (H06) | **appliquée le 24/09, à confirmer** : la règle porte sur les écritures **saisies** ; une écriture produite par un document (facture, achat, paie, caisse, stock) est validée avec le document — l'y soumettre rendrait la facturation impossible dès que l'option est cochée, puisque la fonction du document crée et valide d'un seul mouvement | 232, fait |

---

## 4. PHASE 1 — Dettes connues des vagues V1 à V3

Chaque ligne suit le protocole : **scénario rouge → migration 210+ → vert → preuve dans le suivi**. Effort en jours de développement.

### 4.1 Comptabilité générale

#### R-01 ✅ Amortissements, écarts résiduels et charges constatées d'avance
- **Constat (V2)** : `generate_depreciation_entry`, `generate_residual_entry` et `post_deferred_charge` créent l'en-tête directement en `posted` (refusé depuis la 187) et imputent des comptes fictifs `6_____`. `post_deferred_charge` est appelée par `src/lib/queries/businessFunctions.ts:301`.
- **Fait (211)** : écriture en brouillard puis validation — les triggers de la 187 (équilibre, exercice, comptes du plan, permission) s'appliquent ; comptes réels (`681200`/`281000` par défaut, ceux de l'immobilisation s'ils sont renseignés ; `486000`/`487000` et le compte de charge/produit de la régularisation) ; l'écart de lettrage passe une écriture **équilibrée** (charge ou produit d'écart + contrepartie du compte de tiers du groupe) ; dotation linéaire avec **prorata temporis** en jours la première année, plafonnée à la base amortissable, écrite dans l'historique `asset_depreciations` et reflétée dans la valeur nette ; idempotence par référence (`AMORT:`, `ECART:`, `DEFER:`) ; `post_deferred_charge` prend désormais l'identifiant de `regularization_entries` (ce que l'écran envoyait déjà) ; l'écran « Immobilisations » porte le bouton « Générer l'écriture d'amortissement » dans l'exercice ouvert.
- **Preuve** : `sql/211_asset_deferred_tests.sql` — 16 scénarios, rouges avant la migration (14/16) et verts après ; `src/pages/__tests__/FixedAssetDepreciation.test.tsx` (2 tests).
- **Repris le 23/09 (226)** : l'historique inscrivait `net_book_value = base amortissable − cumul`, retranchant la valeur résiduelle une seconde fois — 8 000 contre 10 000 sur la fiche, 0 contre 2 000 au terme du plan. La VNC est la valeur d'acquisition moins le cumul, comme `fixed_assets.current_value` ; les lignes déjà écrites sont reprises. Preuve : `sql/226_asset_net_book_value_tests.sql` — A08 et A09 **vus rouges avant**, A10n (sans résiduelle) vert d'emblée ; 211 reste 16/16.
- **Effort** : 1,5 j (fait).

#### R-02 ✅ Affectation du résultat (`allocate_result`)
- **Constat** : non réécrite en V2, faute de décision (D-3).
- **Fait (189)** : décision n° 3 retenue — écran d'affectation obligatoire. `fiscal_years` mémorise `closing_result`, `result_allocated_at` et `result_allocation_entry_id` ; `allocate_result` passe l'écriture dans l'exercice suivant (D 120/129 → 1061 réserves, 110 report à nouveau, 457 dividende ; une perte s'affecte en 119 ou sur les réserves/report créditeur — dividende refusé) ; `close_fiscal_year` **refuse** de clôturer N+1 tant que le résultat de N n'est pas affecté ; l'écran de clôture propose l'affectation et bloque le bouton.
- **Preuve** : `sql/179_closing_and_statements_tests.sql` — scénarios D10/D11 (échec hors registre avant, verts après) ; `src/pages/__tests__/FiscalYearClosureAllocation.test.tsx` (3 tests).
- **Effort** : 1 j (fait).

#### R-03 ✅ Factures d'acompte comptabilisées en ventes
- **Constat (lecture de code, à prouver par un scénario)** : `createAdvanceInvoice` (`misc.ts`) crée une facture `invoice_type = 'advance'` dont la ligne sans article est comptabilisée en 707000 par le trigger de validation. Or un acompte reçu se comptabilise en **4191** (avec TVA si prestation de services), puis s'impute sur la facture finale.
- **Fait (210)** : décision D-9 retenue (norme) — facture d'acompte : D 411 TTC / C 4191 HT / C 4457 TVA ; facture finale : ligne négative rattachée à l'acompte (`advance_invoice_id`), déduction plafonnée au solde, lettrage 4191 quand l'acompte est entièrement déduit ; l'écran de facture propose les acomptes validés du client et refuse une déduction supérieure au total.
- **Preuve** : `sql/210_advance_invoices_tests.sql` — 12 scénarios ; tests d'écran `SalesDocumentForms.test.tsx`.
- **Effort** : 1,5 j (fait, dépendait de D-9).

#### R-04 ✅ Paiement des salaires non généré
- **Constat** : la 191 comptabilise la paie (charges et dettes), pas son **paiement** : pas d'écriture D 421 / C 512 au versement des salaires, ni D 431 / C 512 au paiement des organismes, ni pour les acomptes sur salaire (425).
- **Fait (212)** : `post_payroll_payment(lot, compte bancaire, date, périmètre)` construit le règlement depuis les bulletins, avec les comptes de `payroll_account_mapping` : **net** D 421 par salarié (auxiliaire `employee_number`) / C 512x puis **lettrage** du 421 salarié par salarié (l'écriture de paie porte désormais le même auxiliaire), **social** D 431, **tax** D 447, **advances** D 425 — chaque périmètre idempotent par référence `PAYPAY-<lot>-<périmètre>` ; le lot ne passe à « payé » que lorsque tous les périmètres dus sont versés, et la réponse liste les périmètres restants. Écran des campagnes : bouton « Payer la paie ». Au passage, deux défauts trouvés par les scénarios : `pay_runs` n'acceptait pas le statut `processing` (pourtant écrit par l'intégration des acomptes, donc tout passage à `processing` échouait) et `integrate_salary_advances_on_payrun` écrivait `processed`, absent de `salary_advances_status_check` (l'acompte est maintenant marqué `deducted`, sans doublon).
- **Preuve** : `sql/212_payroll_payment_tests.sql` — P08 à P16, **9 scénarios vus rouges** avant la migration (dont P12 : contrainte de statut) et verts après ; `src/pages/__tests__/PayrollPayment.test.tsx` (2 tests).
- **Repris le 23/09 (224)**, deux défauts mesurés : (1) le corps du versement lisait `pay_runs WHERE id = …` **sans filtre de société**, en SECURITY DEFINER donc hors RLS — la garde `payroll.pay` de la 220 s'évalue dans la société de l'**appelant** : un administrateur de A payait la paie d'un lot de B **dans les livres de B** et recevait ses montants ; (2) le périmètre « social » débitait la somme des trois rôles (`employee_contrib`, `csg_crds`, `employer_contrib_payable`) sur le **seul** compte du premier — invisible avec le mapping par défaut, faux dès qu'une société sépare ses comptes (431000 = −1 460, 437000 = +1 260, 438600 = +200). Preuve : `sql/224_payroll_payment_scope_tests.sql` — P17 et P18 **vus rouges avant**, P19 (mapping par défaut, une ligne 431000 de 3 720) vert d'emblée ; 212 reste 9/9 et 220 5/5.
- **Effort** : 1,5 j (fait).

#### R-05 ✅ Avoirs sans article : comptes par défaut
- **Constat** : un avoir client sans article est imputé en 707000 (709000 s'il n'a pas de ligne) ; un avoir fournisseur en 609000. Pour un avoir sur facture, la contrepassation des **comptes de la facture d'origine** est plus juste.
- **Fait (213)** : quand l'avoir est rattaché à une facture et que ses lignes ne portent pas d'article (ou qu'il n'a aucune ligne), les comptes de produits (classe 7) / charges (classe 6) de l'**écriture d'origine** sont contre-passés **au prorata** de leurs montants, la dernière ligne absorbant le centime d'arrondi (`prorata_source_accounts`) ; la TVA reste ventilée par taux quand l'avoir a des lignes, sinon en une ligne. Sans facture d'origine, l'avoir reste une remise commerciale (709000 / 609000).
- **Preuve** : `sql/213_credit_note_accounts_tests.sql` — 6 scénarios. **3 mesurés rouges** avant la migration (E23 : 500 en 709000 au lieu de 300/200 ; E23c ; A10), 6 verts après ; E23d (ligne présente mais sans article) et E23b/A10b (avoir hors facture → remise) couvrent les branches voisines. Non-régression vérifiée sur la 197 : la garde des avoirs fournisseur conserve le traitement de la TVA autoliquidée (V06 et les 7 scénarios de la 197 au vert).
- **Effort** : 1 j (fait).

#### R-06 ✅ Allocation du reçu entre lignes de commande du même article
- **Constat** : `quantity_received` (195) solde les lignes dans l'ordre de leur `id` (uuid, donc arbitraire).
- **Fait (214)** : `purchase_order_lines.line_order` ajouté et repris pour les lignes existantes (ordre des uuid, celui qu'elles suivaient déjà) ; attribué automatiquement à toute nouvelle ligne qui n'en porte pas (`order` d'insertion), pour que la règle tienne quelle que soit la porte d'entrée ; l'allocation d'une réception partielle suit désormais `line_order` ; l'écran envoie l'ordre des lignes converties (demande d'achat, échéancier de livraison).
- **Preuve** : `sql/214_purchase_receipt_order_tests.sql` — 3 scénarios (G06b : uuid plus petit saisi en second, c'est bien la ligne `line_order` 1 qui est servie ; G06c ; G06d), **3 vus rouges** avant (colonne absente, allocation par uuid). Exécution vérifiée : la 214 s'applique après la 213 sans la contredire, et la suite 192 (qui lit `quantity_received`) reste verte.
- **Repris le 23/09 (225)** : rien n'empêchait deux lignes d'une commande de porter le **même** ordre, or la règle « les lignes précédentes sont celles d'ordre inférieur » suppose un ordre **total** — deux lignes de 3 en ordre 1, réception de 4 → `quantity_received` rendait 3 et 3, soit **6 reçus sur 4 livrés**, et la commande se soldait. L'ancien tri par uuid ne pouvait pas double-compter : c'était une régression de la 214. Renumérotation de l'existant, index unique `(société, commande, ordre)`, attribution aussi à la mise à jour qui efface l'ordre, et `id` qui départage une égalité résiduelle. Preuve : `sql/225_purchase_line_order_unique_tests.sql` — G06e, G06f, G06g **vus rouges avant**, 3/3 verts après ; 214 reste 3/3.
- **Effort** : 0,25 j (fait).

### 4.2 Trésorerie et banque

#### R-07 ✅ Modèle `bank_transactions` à double sens
- **Constat** : la table contenait à la fois les **reflets des règlements saisis** (`source = customer_payment / supplier_payment`) et les **lignes de relevé** (`import`, `manual`…). `update_bank_balance_on_transaction` ajoutait les deux à `calculated_balance`, qui comptait donc **deux fois** une opération importée et saisie. La source par défaut `manual` était ambiguë.
- **Fait (222)** : `kind ∈ {book, statement}`, non nul, défaut `statement` (tout ce qui n'est pas un reflet de règlement est une ligne de relevé — la règle que `is_statement_line` codait en creux, désormais écrite), reprenne des lignes existantes par leur source. Le solde `calculated_balance` est celui des **mouvements de trésorerie saisis** (`kind = 'book'`) et il est **recalculé** (jamais incrémenté) à chaque insertion, mise à jour **ou suppression** — et sur l'ancien compte si la ligne en change. Les deux portes d'entrée écrivent leur nature : reflets de règlement en `book`, import normé et import PDF en `statement`. `statement_line_ledger_match`, `auto_reconcile_by_score` et `get_bank_reconciliation_state` lisent `kind` au lieu de déduire la nature de la source ; `is_statement_line` est **supprimée** (aucune référence résiduelle vérifiée en base).
- **Ce que R-07 laisse volontairement à R-09/R-10** : `statement_balance` (solde de **clôture** lu dans le relevé) reste à alimenter par le lecteur — c'est R-10 ; et ce que l'écran d'état **montre** (dont `is_balanced`, qui est vrai par construction) est R-09.
- **Preuve** : `sql/222_bank_transaction_kind_tests.sql` — **G12a à G12e vus rouges avant avec les valeurs fautives** : G12b `solde=240` (double comptage de la même opération saisie puis importée), G12c `solde=80` (figé après suppression), G12e `solde=500` (une ligne de relevé gonflait le solde des mouvements saisis) ; verts après (`120`, `0`, `0`), et G12a prouve la nature explicite (`kind=book`). G12d (pointage d'une ligne de relevé contre l'écriture du compte) était vert avant et le reste : non-régression de la 196.
- **Effort** : 1,5 j (fait).

#### R-08 ✅ « Marquer payée » sans choix du mode ni du compte bancaire
- **Constat** : les deux boutons enregistrent un règlement « virement » sans compte bancaire, donc en 512000/BQ.
- **Fait** : fenêtre de règlement partagée (`src/components/PaymentDialog.tsx`) — date, montant, mode (virement, chèque, carte, espèces, prélèvement, autre), compte bancaire (512000 par défaut, signalé) et référence, avec mention de l'excédent porté en avance client (4191) ; ventes et achats branchés dessus, le numéro de règlement restant attribué par le serveur ; clés fr/en/ar.
- **Preuve** : tests d'écran `SalesDocumentForms.test.tsx` et `PurchaseDocumentForms.test.tsx` (flux complet : ouverture de la fenêtre puis enregistrement).
- **Repris le 23/09** : les deux tests soumettaient la fenêtre **avec ses valeurs par défaut** — ils seraient restés verts si le compte bancaire choisi avait cessé d'être transmis, c'est-à-dire précisément la régression que R-08 doit empêcher. Réécrits : date, montant, mode, compte et référence sont saisis puis vérifiés à l'arrivée du règlement (**vu rouge** en supprimant `bank_account_id` de `InvoicesPage`). Au passage, le libellé de l'excédent était lu dans le namespace `sales` : l'écran des achats annonçait une « avance client (4191) » là où la 192 impute en **409100** — l'appelant fournit désormais son texte (clés fr/en/ar dans `purchases`).
- **Reste à confirmer** : décision **D-10** — la fenêtre est l'option implémentée ; l'autre option était de garder le raccourci en 512000/BQ.
- **Effort** : 0,75 j (fait).

#### R-09 ✅ Écran de rapprochement bancaire non branché sur l'état de la 196
- **Constat** : `get_bank_reconciliation_state` est réécrite et testée (G04), mais **aucun écran ne l'appelle**. `is_balanced` est vrai par construction dès que les pointages sont cohérents ; l'information utile est la liste des écarts.
- **Vérification du constat, sur le code** : exact, et **plus grave que décrit**. (1) **0 appel** de la fonction dans `src/` — confirmé. (2) Le pointage de l'écran « Rapprochement bancaire » (`updateBankTransaction({ reconciled, matched })`) n'écrivait que les drapeaux de la **ligne de relevé** : ni `reconciled_entry_id`, ni `journal_lines.reconciled`. Or l'état de rapprochement lit **ces deux colonnes** — le pointage fait à la main ne changeait donc **rien** à l'état et laissait les écarts des deux côtés. (3) `bank_accounts.statement_balance` (solde de **clôture** du relevé) n'était alimenté par aucun écran : `updateStatementBalance` (misc.ts) existait depuis la vague #70, jamais appelé — la comparaison prévue au plan était impossible, faute de donnée.
- **Fait (223)** : l'état expose les écarts des **deux** côtés (`ledger_unmatched_transactions` : chèques émis non débités, remises non créditées), les paires pointées, les compteurs, et **`is_reconciled`** — la seule réponse qui vaille à « est-ce rapproché ? », distincte d'`is_balanced` (contrôle d'**intégrité** des paires, vrai aussi quand un écart subsiste ; il passe à `false` dès qu'une paire est incohérente). Le solde de clôture du relevé est comparé aux lignes importées jusqu'à **sa** date (`closing_difference`, `closing_matches`) : une clôture qui ne colle pas à ses propres lignes signale un import incomplet. Deux RPC de mutation et une de comptabilisation : `reconcile_bank_statement_line` (paire juste exigée : même société, même compte du plan, même montant, **sens contraire**, écriture validée, lignes non pointées) et `unreconcile_bank_statement_line` écrivent et défont les **deux** côtés ; `post_bank_statement_line` comptabilise une ligne non pointée (frais, agios) — écriture en **brouillard puis validée** (les gardes de la 187 s'appliquent), contrepartie **627000** au débit / **768000** au crédit (ou le compte 6/7 choisi, `661000` compris), puis pointage des deux côtés, avec **refus explicite** d'une seconde comptabilisation. Les mutations sont gardées (`journal_entry.update`, `journal_entry.post`) ; la lecture reste ouverte, comme la 220 l'a établi pour cette même fonction. Écrans : nouvelle page `/banking/reconciliation-state` (soldes, écart de solde et son explication, état, solde de clôture, **écarts du relevé** avec « Pointer » et « Comptabiliser », **écarts du compte 512x**, pointages avec « Dépointer »), route + entrée de navigation + clés fr/en/ar, et un bouton depuis l'écran de rapprochement.
- **Preuve** : `sql/223_bank_reconciliation_state_tests.sql` — **R09a à R09j vus rouges avant** (colonnes et RPC absentes), **11/11 verts après**, dont les deux plus parlants : R09b montre que le drapeau d'un seul côté laisse **les deux** écarts (1 relevé / 1 écriture) quand la RPC les fait tomber (0/0, réconcilié) ; R09g mesure 67 annoncés contre 70 importés → écart −3 signalé. Non-régression : 192 (15/15), 222 (5/5), 220 (5/5). `src/pages/__tests__/BankReconciliationState.test.tsx` (5 tests : lecture des deux côtés, pointage sur l'écriture de même montant sens contraire, comptabilisation, dépointage, solde de clôture). Chaîne complète rejouée sur base neuve : **198 migrations, 0 erreur**, `plpgsql_check` 0 erreur, déclencheurs atteignables OK, 1 418 tests, tsc, oxlint, i18n, knip 66/66, build.
- **Effort** : 1,5 j (fait).

#### R-10 ✅ Relevés : OFX, devise, et deux lecteurs faux sur des fichiers réels
- **Constat** : `BankStatementFormat` prévoyait `ofx` sans aucun lecteur ; la devise lue dans le relevé n'était ni contrôlée ni comparée à celle du compte (LOC1-49) ; les fixtures de relevés réels demandées par AUD-G03 n'existaient pas.
- **Fait (front, sans migration)** :
  1. **Lecteur OFX** (`parseOfx`) — les **deux générations** : OFX 1.x **SGML** (balises de valeur non fermées, en-tête `OFXHEADER:`) et OFX 2.x **XML** bien formé. Devise `CURDEF`/`CURSYM`, solde de clôture `LEDGERBAL/BALAMT` daté par `DTASOF`, `FITID` comme référence, `NAME`+`MEMO` comme libellé, `CHECKNUM` en repli. Le signe de `TRNAMT` fait foi ; `TRNTYPE` ne tranche que sur un montant positif (certains exports inversent la convention). Une opération sans date exploitable est **écartée avec un avertissement** au lieu d'être datée du jour. La détection reconnaît désormais un fichier OFX SGML (avant : « format non reconnu »).
  2. **Contrôle de devise** : `importBankStatement` compare la devise du relevé à celle du compte et **refuse** (`BankStatementCurrencyError`, code `bank_statement_currency_mismatch`) — sinon des montants d'unités différentes étaient comparés au solde du compte. Le refus ne porte que sur une devise **réellement lue dans le fichier** : un nouveau champ `currencyFromFile` distingue « le relevé l'annonce » de « le lecteur est retombé sur EUR ». Sans lui, un relevé CFONB ou MT940 muet sur sa devise aurait été refusé sur un compte en **DJF**, et un relevé EUR sur un compte USD accepté.
  3. **Solde de clôture repris sur le compte** : `statement_balance`, `statement_balance_date` et `reconciliation_diff` sont écrits à l'import (l'équivalent de `updateStatementBalance`, qui existait depuis la vague #70 sans appelant) dès que le relevé porte un solde **et** de quoi le dater — c'est cette donnée qui rend l'état de rapprochement (223) comparable à la banque. L'écran l'annonce.
  4. **Relevés réels anonymisés** dans `app/src/lib/__tests__/fixtures/` (CFONB 120, MT940, CAMT.053, CAMT.053 en USD, OFX 1.x, OFX 2.x) + `README.md` (provenance, anonymisation, positions de la norme). Les six fichiers décrivent **les mêmes trois opérations** : le lecteur qui s'écarte est visible.
- **Deux défauts trouvés par ces fichiers, invisibles avec des chaînes fabriquées** :
  - **CFONB 120** : le lecteur lisait une date ISO de 8 chiffres là où la norme écrit 6 (`JJMMAA`), un « sens » dans une colonne 105 qui n'existe pas (105-120 = la **référence**) et un libellé sur la zone du numéro d'écriture et des drapeaux. Il ignorait l'**échelle** (position 20) et le fait que le montant est signé par son **14e caractère** (13 chiffres + 1 spécificateur qui porte le signe et l'unité). Sur un fichier réel, il perdait donc dates, montants et libellés — et datait du **jour** un mouvement sans date. Réécrit d'après la brochure CFONB (01 ancien solde, 04 mouvement, **05 complément de libellé**, 07 nouveau solde, 08 toléré), avec `parseCfonbDate` (pivot à 60) et `parseCfonbAmount`.
  - **MT940** : la date de valeur est `MMDD` dans la norme ; le lecteur n'en sautait que 6 chiffres, donc sur `:61:2501010102D120,00NCHG` il lisait **102 au lieu de 120** — sans le moindre avertissement. La date de valeur n'est plus consommée que si le caractère suivant est bien un sens (`C`/`D`), `RC`/`RD` sont reconnus, et un solde sans devise (`:60F:C2501011000,00`) ne fait plus croire à une devise « 100 ». `:60M:`/`:62M:` (soldes intermédiaires) sont acceptés. CAMT.053 : le libellé tombe en repli sur `Ustrd` (le plus courant) avant le texte concaténé du bloc.
- **Preuve** : `src/lib/__tests__/bankParsers-formats.test.ts` (**23 tests** : détection des 5 formats, mêmes 3 opérations dans les 6 fichiers, signe OFX, dates OFX et CFONB, spécificateur de signe CFONB, montant MT940 `0102D120,00` = 120) et `bank-statement-import.test.ts` (**8 tests**, dont refus USD/EUR — rien n'est écrit, ni ligne, ni trace, ni solde —, relevé muet accepté sur un compte **DJF**, solde de clôture repris avec son écart, OFX de bout en bout). 1 446 tests au total. `tsc`, `oxlint`, i18n, knip, build verts. **Le chantier a été fait sans migration** : les lecteurs et l'import sont côté front.
- **Effort** : 1 j (fait).

### 4.3 Ventes, achats, caisse

#### R-11 ✅ Documents provisoires imprimables
- **Constat** : un brouillon pouvait être téléchargé avec son numéro `BROUILLON-FAC-…`, sans mention.
- **Vérification du constat, sur le code** : **il n'existe aucun PDF de facture** dans l'application — aucune route d'impression, `SharedDocumentPage` n'en parle pas, la fonction `generate-pdf` n'a aucun appelant. Le seul chemin « imprimable » est le bouton de téléchargement de `InvoicesPage`, qui écrit un **`.txt`** nommé d'après le numéro, **sans condition de statut**. Le « filigrane » du plan ne pouvait donc pas être posé : ce que l'on peut garantir, c'est que le document dit ce qu'il est et que son nom l'annonce. Factur-X : le bouton était masqué à l'écran sur un brouillon, mais `generateFacturX`/`generateUBL` acceptaient n'importe quelle facture — un appel direct produisait un XML au numéro provisoire.
- **Fait (front, sans migration)** : `isDraftDocument` (statut de validation autre que `validated` ; `validation_status` absent — donnée ancienne — compté comme provisoire, par prudence) ; le téléchargement d'un brouillon porte la mention **`PRO FORMA — document provisoire, non valable comme facture`** et son fichier s'appelle `PRO-FORMA-<numéro>.txt` ; `generateFacturX` et `generateUBL` **refusent** un document provisoire (la garde est dans la génération, pas seulement dans le bouton) ; le bouton de l'écran porte la garde défensive avec un message. Clés fr/en/ar.
- **Preuve** : `src/lib/__tests__/facturX.test.ts` et `src/pages/__tests__/DraftDocumentPolicy.test.tsx` — **4 des 6 scénarios vus rouges avant** (le XML était produit et le `.txt` ne portait aucune mention), verts après ; les 2 scénarios de non-régression (facture validée) étaient verts d'emblée. 1 413 tests au total.
- **Effort** : 0,5 j (fait).

#### R-12 ✅ Factures créées par l'API publique ou l'OCR sans lignes
- **Constat** : `public-api` (`POST /v1/invoices`) insérait l'en-tête seul ; `ocr-invoice-import` « crée probablement des factures d'achat sans ligne (à vérifier) ». Depuis 190/192, une pièce sans ligne n'est **ni validable ni approuvable**.
- **Vérification du constat, sur le code** : la seconde moitié était **fausse** — `ocr-invoice-import` (120 lignes) **ne crée aucune facture** : elle appelle OpenAI, fait correspondre un fournisseur et renvoie `extracted_data` (dont `items`) à l'appelant. Il n'y avait donc rien à corriger de ce côté, et l'écrire évite une correction inutile. La première moitié est exacte, et le défaut est plus grave qu'un manque de fonctionnalité : l'intégration créait une pièce **inutilisable**, et l'appelant ne l'apprenait qu'en essayant de la valider dans l'interface.
- **Pourquoi une fonction dédiée, et pas les RPC existantes** : l'API publique s'authentifie par clé (clé `service_role`), donc `current_tenant_id()` y vaut NULL (`tenant_users.auth_id = auth.uid()` ne peut pas être vrai sans JWT) — `create_invoice_atomic` (147, réécrite par 184) lève « Aucun tenant actif ». La société est donc **passée explicitement**, et la fonction n'est ouverte qu'à `service_role` : un jeton utilisateur ne peut pas créer une facture chez une autre société en l'appelant.
- **Fait (221 + API)** : `create_invoice_service(p_tenant, p_invoice, p_lines)` — au moins une ligne **exigée** (refus explicite sinon, aucune pièce laissée derrière), lignes insérées par l'helper interne réutilisé de la 184, puis **totaux recalculés depuis les lignes** par les triggers de la 190 (`invoice_line_compute`, `invoice_guard`) : un appelant ne peut pas annoncer un total qui ne correspond pas à ce qu'il envoie. `public-api` appelle cette RPC, refuse en 400 sans ligne, et renvoie la facture **avec ses lignes**. Contrat publié dans `openapi.json` (`InvoiceCreate`, `lines` en `minItems: 1`, mention que les totaux sont recalculés et que la société vient de la clé).
- **Preuve** : `sql/221_invoice_api_tests.sql` — **V01 à V04 vus rouges avant** (fonction absente), verts après : la facture créée par l'API porte ses **2 lignes**, se **valide** et reçoit son numéro légal `FAC-2026-000001` (HT 250 / TVA 45 / TTC 295) ; sans ligne, refus « Au moins une ligne est requise » et **aucune facture créée** ; un total annoncé de 9 999 est **écrasé** par celui des lignes (100/20/120) ; `anon` et `authenticated` ne peuvent pas exécuter la fonction.
- **Effort** : 1 j (fait).

#### R-13 ✅ Caisse (POS) : TVA mono-compte et écart de caisse
- **Constat** : la clôture créditait **une seule ligne dure `445710`** avec `SUM(pos_tickets.vat_total)`, alors que `pos_ticket_lines.vat_rate` porte le taux de chaque ligne : une session mêlant 20 % et 10 % déclarait tout en 20 %, et la CA3 était fausse. Et l'écart de comptage — colonnes `expected_amount`/`difference` depuis la 54 — n'était **jamais comptabilisé** ; pire, l'attendu de l'écran additionnait tous les tickets sans regarder le moyen de paiement (`posAdvanced.ts:70-74`), donc était faux dès qu'un ticket était réglé par carte.
- **Fait (219)** : la TVA se ventile **par taux** via `vat_account_mapping` (direction `collected`, correspondance canonique du taux — société puis ligne partagée —, puis autre code du même taux, régimes particuliers `AUTOLIQ`/`UE`/`EXO` en dernier, repli `445710`) ; le total crédité reste celui du ticket, l'écart d'arrondi étant absorbé par le taux le plus élevé. Aucun compte nouveau en dur : `445710` est déjà exigé du plan (`chart_required_accounts`, 201), ce qui garde la neutralité des packs pays (LOC1). L'attendu est **recalculé par le serveur sur les espèces seules** (`ppm.type = 'cash'`), écrit dans la session, et l'écart est comptabilisé : manquant D `658000` / C compte de caisse, excédent D compte de caisse / C `758000`. Le trigger passe en **`BEFORE UPDATE`** pour que l'appelant (l'écran de clôture) reçoive l'écart du serveur, et non celui qu'il a proposé.
- **Preuve** : `sql/219_pos_vat_cash_tests.sql` — **G13a à G13d vus rouges avant** (`repli=30.00`, toute la TVA sur le compte unique ; `attendu` et `écart` vides, jamais calculés), verts après (20 → `445711`, 10 → `445712`, repli 0 ; manquant 5 → D 658 / C caisse ; excédent 3 → C 758 ; carte exclue de l'attendu, taux 7,7 % au repli). G09 (192, clôture POS) reste vert. **Deux erreurs de ma part trouvées par les tests** : un appariement par code TVA envoyait la TVA à 7,7 % sur le compte de 20 % (`vat_code_for_rate` retombe sur `FR20`) — supprimé ; et un tri par code TVA choisissait `AUTOLIQ` → `445790` pour 20 %, envoyant une vente au comptoir en autoliquidation — corrigé par la priorité au code canonique du taux.
- **Répétition sur copie de production** : la 219 s'applique sans erreur, et **les 124 sociétés (sur 124) portent déjà** `445711`, `445712`, `445710`, `658000`, `758000` et `530000` — aucun plan à compléter, aucune clôture de caisse ne peut échouer sur un compte absent.
- **Effort** : 0,75 j (fait).

#### R-14 ✅ Devis : numéros « perdus »
- **Constat** : le numéro `DEV-…` est attribué à la création ; un devis supprimé laisse un trou (légal pour un devis, à documenter).
- **Fait (218, documentation)** : la règle est écrite au lieu d'être implicite — `COMMENT ON COLUMN quotes.number` et l'en-tête de la 218 : un devis est numéroté **à sa création** (`quote_assign_number`, 190) et non à sa validation, parce qu'il n'est pas une pièce comptable ; un brouillon supprimé laisse donc un trou dans la suite `DEV`, ce qui est **licite pour un devis**. Le devis créé hors exercice garde une suite propre au préfixe, sans année (hors exercice, il n'y a pas d'année à porter).
- **Preuve** : aucune — c'est un livrable de documentation, et le dire fait partie de la preuve (le plan le chiffrait ainsi : 0,1 j).
- **Effort** : 0,1 j (fait).

### 4.4 Qualité transversale

#### R-15 ✅ TVA : `FR20` et `AUTOLIQ` sur les mêmes comptes
- **Fait (197, `f948fe9`)** par la session parallèle : comptes propres — AUTOLIQ → 445790 (due) / 445668 (déductible), UE → 445200 / 445667 —, libellés portés par le paramétrage (les comptes du 20 % s'intitulaient « TVA collectée AUTOLIQ » pour toutes les sociétés), drapeau `reverse_charge`, écriture d'achat autoliquidé D déductible / C due, et `calculate_vat_ca3` corrigée : elle additionnait les factures « paid »/« sent » alors qu'une facture validée reste `draft` — la déclaration valait **0**.
- **Vérifié le 23/09** : `sql/197_vat_reverse_charge_tests.sql` rejoué **7/7** sur base neuve, 192 (15/15) et 102 restent verts ; CI verte sur le commit.
- **Reste** : la lecture de la CA3 elle-même (cases, TVA sur encaissements) est couverte par **M-10** (phase 3), pas par R-15.

#### R-16 ✅ Clés de traduction manquantes
- **Fait (`d980c5a`)** : `scripts/check-i18n-usage.mjs` analyse le code au compilateur TypeScript et refuse toute clé littérale `t('…')` absente en fr ; étape CI « Lot I : clés i18n utilisées dans le code » dans le job i18n.
- **Vérifié le 23/09** : `toast.loadError` — le point connu — **0 occurrence** dans `src/` ; job i18n vert sur les 8 derniers runs.

#### R-17 ✅ Droits sur les nouvelles RPC
- **Constat** : `post_payroll_journal`, `convert_quote_to_invoice` et `get_bank_reconciliation_state` ne vérifiaient que la société, pas le rôle (`has_permission`). C'est le cas de presque toute l'application (D-6).
- **Vérification du constat, sur le code** : sur les trois, **une seule était un vrai trou**. (1) `has_permission('journal_entry.post')` sur les RPC qui valident des écritures est **déjà en place par construction** : `journal_entry_guard` (187) refuse tout `INSERT` dont le statut n'est pas `draft`, donc le seul chemin vers `posted` est un `UPDATE`, gardé par `enforce_journal_entry_permissions` (154) — cela couvre déjà la paie, les avoirs, la TVA, les amortissements, la clôture POS. (2) `get_bank_reconciliation_state` est une **lecture** `STABLE` : un contrôle de rôle y est sans objet ; ses manques sont R-07/R-09. (3) `convert_quote_to_invoice` crée une facture **en brouillon** et ne valide rien ; aucune clé commerciale n'existe dans `has_permission`, l'ajouter bloquerait tout le monde sauf l'administrateur — dépendance de H08/D-6.
- **Fait (220)** : la porte de la paie est gardée — `payroll.post` sur `post_payroll_journal`, `payroll.pay` sur le versement ; le socle du rôle `accountant` gagne ces deux clés (sinon la garde bloquerait le comptable : c'est le défaut exact que la 165 avait corrigé pour la validation des écritures). `payroll_post_run` **n'est pas** gardée : elle est appelée en interne par le passage à « payé » (191) et par le versement (212) — y mettre la garde casserait des flux légitimes. Le corps du versement est **renommé** (`payroll_payment_inner`) puis enveloppé dans la garde — recopier 300 lignes aurait fait diverger deux versions —, et l'ancien nom est **révoqué** de `anon` et `authenticated` : sans cela il resterait exposé par PostgREST et la garde serait contournable.
- **Preuve** : `sql/220_payroll_permission_tests.sql` — **P02 à P05 vus rouges avant**, et le détail rouge est le constat lui-même : le comptable n'avait **aucun** droit de paie (`droits=f`) tout en réussissant l'écriture (la clé métier manquait, l'effet passait par le trigger) ; un lecteur était bloqué par le trigger d'écriture **seulement** — sur un lot déjà comptabilisé, le chemin idempotent le laissait passer sans aucune vérification, et le message parlait de `journal_entry.post`, pas de la paie ; un administrateur révoqué recevait « Lot de paie introuvable » au lieu d'un refus de droit. **5/5 verts après**. 181 (7/7), 212 (9/9) et 166 restent verts.
- **Effort** : 0,5 j (fait).

**Total phase 1** : ≈ 15 j. **Fait au 23/09 : R-01 à R-17, sans exception** (R-15 et R-16 livrés par les sessions parallèles et vérifiés ici). **La phase 1 est close.**

---

## 5. PHASE 2 (V4) — Sécurité, ergonomie, preuve de bout en bout

Reprise des lots H, I, J du plan correctif, mis à jour avec les mesures du 22/09.

### 5.1 Lot H — Sécurité

| Réf | Constat | À faire | Test / preuve | Effort |
|---|---|---|---|---:|
| **H02** ✅ | **Aucune politique ne manquait — c'est le test qui ne prouvait rien sur ces 7 tables.** Mesuré le 23/09 sur base neuve (202 migrations) : `crm_campaign_recipients`, `distribution_grill_lines`, **`invoice_lines`**, `pick_list_lines`, `project_task_tags`, `purchase_request_lines`, `service_ticket_messages`. Toutes portent une politique qui passe par le **parent** (`EXISTS` sur `invoices`, `pick_lists`…) ; or le semeur remplit les uuid obligatoires par `gen_random_uuid()`, donc la ligne fille pointait vers un parent inexistant : invisible à sa propre société, et son `leak_count = 0` était vrai **pour la mauvaise raison**. | fait : le test recolle chaque clé étrangère simple vers la ligne semée dans la table parente de la **même** société, et **échoue** désormais dès qu'une table alimentée reste invisible à sa société | **rouge vu d'abord** (7 tables à 0), puis **340 tables, 340 alimentées, 340 visibles, 0 fuite** — en-tête `x-tenant-id` falsifié compris. L'insertion est elle aussi gardée par le parent (`WITH CHECK` sur `invoices`), donc une société ne peut pas rattacher une ligne au document d'une autre. | 0,5 j (fait) |
| **H03** 🔴 | `generate-pdf` : SSRF en lecture prouvée (I1), `html` fourni par le client, interpolation sans échappement (I3), déployée `--no-verify-jwt`, aucun appelant (I2) | selon D-4 ; à défaut : **retirer de `deploy-all-functions.sh`** et supprimer la fonction du projet | test : appel sans jeton → 401 ; `<iframe>` interne → refus | 0,5 à 1 j |
| **H04** 🟠 | `ocr-invoice-import` envoie des factures à OpenAI (I4) | selon D-5 : consentement par société, désactivé par défaut, mention dans la documentation et le registre RGPD | test : société sans consentement → refus | 0,5 j |
| **H05** 🔴 👤 | clé `sb_secret_…` en clair | rotation (👤-1), puis `gitleaks` sur tout l'historique | job `security-audit` vert | — |
| **H06** ✅ | **En écrivant le scénario, le contrôle s'est révélé creux** : `check_segregation_of_duties` compare l'auteur d'une écriture au valideur, mais **`journal_entries.created_by` n'est jamais renseigné** — aucun défaut de colonne, aucun trigger, et `post_journal_entry` (seul chemin de saisie de l'application) ne l'écrit pas. La fonction rendait donc `true` sans rien comparer : **même avec `enforce_segregation = true`, l'auteur validait sa propre écriture**. `validated_by` et `validated_at` n'étaient écrits par aucune fonction : ni l'auteur ni le valideur n'étaient enregistrés. | fait (**232**) : l'auteur est posé à l'insertion, le valideur et sa date à la validation ; la séparation porte sur les écritures **saisies** (décision **D-13**), reconnues par la pile d'appel (`PG_CONTEXT`) et non par une déclaration — toute fonction génératrice, même future, donne une écriture automatique ; saisir et valider d'un seul geste est refusé quand l'option est active, sinon la règle se contourne en cochant « comptabilisée » à la saisie | `232_segregation_tests.sql` : **T01, T02, T03, T05 vus rouges**, **8/8 verts** après, dont trois non-régressions (option inactive, validation par un tiers, facture qui produit toujours son écriture) ; **37 suites SQL** restent vertes | 0,5 j (fait) |
| **H07** ✅ | tests en rôle `authenticated` | fait en V1 (A04) | — | — |
| **H08** 🔴 | les rôles ne protègent rien (7 politiques sur 2 296) | selon D-6 : politiques par rôle sur les tables sensibles (écritures, factures, paie, paramètres, utilisateurs) **ou** documentation explicite | 105 étendu : `viewer` ne peut ni insérer ni supprimer une facture par PostgREST | 3 à 6 j |
| **H09** ✅ | **Mesuré, pas supposé : 332 des 389 fonctions de `public` étaient exécutables par `anon`** — le visiteur non connecté, dont la clé voyage dans le bundle — dont **231 `SECURITY DEFINER`** et **75 des 96 RPC de l'écran**. Prouvé en les appelant sans jeton : `auto_revoke_expired_auditors()`, `generate_recurring_tasks()` et `cleanup_expired_idempotency()` **s'exécutaient** (SECURITY DEFINER, elles écrivent). La 78 avait bien révoqué `anon` — 149 migrations l'ont défait, fonction par fonction. | fait (**228**) : `REVOKE EXECUTE … FROM PUBLIC, anon` sur tout le schéma, **deux exceptions inscrites et justifiées** (`current_tenant_id()`, appelée par les politiques RLS des référentiels lus à l'inscription ; `available_signup_countries()`), `authenticated` intact | contrôle CI **`sql/ci/check_anon_grants.sql`** (le nom prévu, `check_definer_grants`, ne décrivait pas ce qu'il fait) **vu rouge — 387 fonctions hors registre — puis vert** ; suite `228_function_grants_tests.sql` **5 scénarios rouges avant, 7/7 verts après** ; anon passe de **332 à 2** fonctions, `authenticated` reste à **362**, les **33 autres suites SQL restent vertes**. **Mesure qui change la conclusion du plan** : `ALTER DEFAULT PRIVILEGES … REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC` **ne fait rien** (la fonction créée ensuite a `proacl = NULL`, donc EXECUTE à PUBLIC) — le droit PUBLIC ne se retire pas d'avance, seul le contrôle CI tient dans la durée. | 1 j (fait) |
| **H10** 🟠 | `outgoing-webhooks` : file en mémoire dans une fonction Edge (audit Gemini du 12/09) | file persistante (table + cron) ; vérifier que le garde SSRF 167/168 s'applique | test SSRF | 1 j |
| **H11** ✅ | **Revérifié, et le défaut était l'inverse de celui annoncé** : le maillon précédent est bien comparé (154) — c'est la **continuité des identifiants** qui était fausse. `v_last_id` était écrasé par l'identifiant courant **avant** le test, qui se lisait donc `id <> id + 1`, vrai pour toute ligne : trois événements intacts rendaient « 3 sauts, chaîne **invalide** », `after_id = before_id`, `missing_count = -1`. Le journal fiscal d'une société saine se déclarait altéré **à chaque vérification**. | fait (**233**) : la continuité se mesure contre la ligne précédente, et `chain_valid` ne dépend plus des sauts — **mesuré** : une transaction annulée consomme son numéro de séquence (4519 → 4521 sans aucune suppression), donc un saut arrive en exploitation normale. Ce qui prouve une altération reste le chaînage ; les sauts sont comptés, détaillés et expliqués. | `233_nf525_chain_tests.sql` : **T01, T02, T03, T05 vus rouges** sur la version d'avant, **6/6 verts** après — dont une chaîne réellement altérée (maillon supprimé, contenu retouché, triggers neutralisés pour se mettre dans la peau d'un accès direct à la base) et l'**inaltérabilité** du journal par le chemin normal, refusée même sous rôle privilégié. **Limite dite** : supprimer le dernier maillon ne casse aucun chaînage — seul un ancrage extérieur le verrait. | 0,5 j (fait) |

### 5.2 Lot I — Ergonomie et i18n

| Réf | Constat (mesuré le 22/09) | À faire | Effort |
|---|---|---|---:|
| **I01** 🟠 | `confirmSync` (= `window.confirm`) dans **85 fichiers** (remesuré le 23/09 : 82 le 22/09, le compte **monte**) ; `window.prompt` **9 fois** (ex. motif d'avoir dans `InvoicesPage`) | migrer vers `useConfirm` / une vraie fenêtre ; règle CI interdisant `confirmSync` et `window.prompt` | 2 j |
| **I02** 🟡 | champs factices de `ChartAccountsPage` (lignes 617–633 au 21/09) | brancher sur des colonnes réelles ou retirer | 0,25 j |
| **I03** 🟠 | sélecteur d'exercice et de dates : fait sur bilan et compte de résultat (V2) | étendre à SIG, balance, grand livre, FEC, TVA | 0,5 j |
| **I04** 🟠 | messages SQL bruts à l'écran (« violates check constraint… ») | traduire les erreurs métier des triggers (codes `check_violation` + message) en clés i18n fr/en/ar ; les nouveaux messages de 190–196 sont en français seulement | 1 j |
| **I05** 🟡 👤 | contraste H2/H3 (D-7) | éclaircir les fonds ; vider `app/.contrast-allowlist.json` | 0,5 j |
| **I06** ✅ | clés i18n manquantes | fait (R-16, `d980c5a`) : contrôle CI des clés utilisées | — |
| **I07** 🟡 | libellés codés en dur dans les pages modifiées : « Comptabilisé », « Non comptabilisé », « Compta », « Rapprochement 3 voies » | clés i18n | 0,25 j |
| **I08** 🟠 | arabe : revue par un locuteur natif (plan § 3) | 👤 relecteur ; RTL vérifié écran par écran (P0-08) | 1 j + relecture |

### 5.3 Lot J — Qualité, CI, preuve de bout en bout

| Réf | Constat (22/09) | À faire | Effort |
|---|---|---|---:|
| **J01** 🔴 | e2e seulement sur planification, déclenchement manuel ou étiquette `run-e2e` | e2e sur **toute PR vers `main`** ; secrets 👤-2 | 0,25 j |
| **J02** 🔴 | les 5 fichiers e2e ne vérifient **aucun chiffre** (ils cherchent du texte) | 4 parcours qui lisent les montants à l'écran : (1) inscription → plan semé ; (2) devis → facture → validation → encaissement → lettrage → avoir, avec les soldes 411, 7xx, 4457x, 512 ; (3) lot de paie → écriture PAIE, D 641/645 = C 421/431/447 ; (4) exercice complet → clôture → bilan et compte de résultat équilibrés → à-nouveaux. **Plus (5)** : facture d'achat → approbation → décaissement ; **(6)** import de relevé → pointage | 4 j |
| **J03** ✅ | règles comptables testées en SQL | acquis ; garder les tests unitaires pour la logique pure | — |
| **J04** ✅ | liste blanche PostgREST vide | acquis en V3 ; **ajouter** : la CI refuse toute nouvelle entrée sans date de décision | 0,25 j |
| **J05** ✅ | types générés contrôlés en CI | acquis | — |
| **J06** 🟠 | test de propriété 100 000 écritures en CI à chaque push (≈ 70 s) | le passer en **nocturne** avec seuils de durée ; garder une version 10 000 écritures par push | 0,5 j |
| **J07** 🟠 | `any` : **1 581** occurrences (mesure du 22/09) | plafond CI décroissant ; zéro `any` dans `lib/queries/accounting.ts` et `sales.ts` | 2 j |
| **J08** 🟡 | `select('*')` : **445** occurrences ; agrégats rapatriés côté client (`getTrialBalanceFiltered`, `runAccountingControl`) | colonnes explicites sur les listes volumineuses ; agrégats par RPC SQL | 2 j |
| **J09** 🟠 | tests d'écran : 6 fichiers seulement pour **198 pages** | un test par écran qui écrit en comptabilité (≈ 25 écrans) | 3 j |
| **J10** 🟡 | `check-knip-ceiling`, `check-unused-tables` : plafonds, pas objectifs | abaisser à chaque lot | continu |

**Total phase 2** : ≈ 30 à 35 j selon D-6.

---

## 6. PHASE 3 — Modules jamais audités par exécution

> **Mesure du 24/09** : [couverture d'audit par module](COUVERTURE-AUDIT-PAR-MODULE-2026-09-24.md).
> Sur 341 tables métier, **80 sont traversées par un scénario (23 %)** ; sur les **67 qui portent
> une logique SQL**, **43 le sont (64 %)**. Les **20 fonctions Edge n'ont aucun test**.
> **16 des 20 modules ci-dessous n'ont jamais vu un scénario chiffré.**

L'audit du 21/09 et les vagues V1 à V3 ont couvert saisie, clôture, ventes, achats, paie (FR), stock, caisse et banque. Les modules ci-dessous existent (198 pages, 21 fonctions Edge) mais **n'ont jamais été vérifiés en exécutant un scénario chiffré**. Chacun suit la même méthode : scénario SQL ou e2e qui lit les chiffres → défauts inscrits au registre → correctifs rouge puis vert.

| # | Module | Ce qu'il faut vérifier | Effort audit |
|---|---|---|---:|
| M-01 | **Multi-devises** | facture en USD : écriture en devise de tenue au taux du jour, écart de change au règlement (666/766), réévaluation de clôture ; `invoices.currency_code/exchange_rate` sont-ils seulement lus par les triggers ? | 1 j |
| M-02 | **Immobilisations** | acquisition → plan d'amortissement → dotations (R-01) → cession (675/775) | 1 j |
| M-03 | **Analytique** | répartition `analytic_distribution` sur les écritures générées ; balance analytique = balance générale sur les classes 6/7 | 0,5 j |
| M-04 | **Budgets** | réalisé = mouvements des comptes (hors à-nouveaux et clôture), engagements libérés à la facturation | 0,5 j |
| M-05 | **Notes de frais** | validation → écriture 625x / 421 ; TVA récupérable | 0,5 j |
| M-06 | ✅ **Commandes → livraisons** (24/09) | La double sortie du 12/09 n'existe plus (STK-01 + index unique). **Trouvé à l'exécution** : livrer une commande confirmée échouait **toujours** — `release_stock_on_delivery` écrivait un statut de réservation que la contrainte CHECK refuse. Réexpédier un BL annulé rendait un code d'index. Migration **230**, tests **230** (5 scénarios). Reste : livraisons → factures, reliquats. | 0,5 j restant |
| M-07 | **Réceptions et contrôle qualité** (achats) | double entrée signalée le 12/09 : **revérifier** ; rapprochement 3 voies avec reliquats | 0,5 j |
| M-08 | ✅ **Production, rebuts et reclôture** (24/09) | **Trouvé à l'exécution** : `qty_scrapped` n'était lue par aucun code — les rebuts entraient en stock comme des pièces bonnes et le coût unitaire était sous-évalué ; et reclôturer un OF doublait le stock sans doubler l'écriture, seul déclencheur à ne pas renseigner `reference_id`. Migration **229**, tests **229** (6 scénarios). Reste : OF multi-niveaux, écarts de coût. | 0,5 j restant |
| M-09 | **Lots et numéros de série** | `check_tracking_on_sm` lève si `lot_id` est nul pour un article suivi : aucun écran ne le renseigne ? | 0,5 j |
| M-10 | **Déclaration de TVA** (`submit-vat-return`, `EdiTvaPage`) | CA3 depuis les écritures, cases correctes, autoliquidation séparée (R-15), TVA sur encaissements | 1 j |
| M-11 | **FEC** | conformité à l'arrêté (18 colonnes, `EcritureNum` = `posting_number` depuis la 187), contrôle par l'outil de la DGFiP (Test Compta Demat) | 0,5 j |
| M-12 | **DSN / déclarations sociales** (`transmit-dsn`) | française : à vérifier ; **hors sujet pour Djibouti** (capacité à désactiver, LOC2-20) | 0,5 j |
| M-13 | **Facturation électronique** (`submit-e-invoice`, `facturX.ts`) | Factur-X conforme (profil, numéro définitif), refus sur brouillon | 0,5 j |
| M-14 | **Relances de paiement** (`cron-payment-reminders`) | ne relancer que les factures validées non payées | 0,25 j |
| M-15 | **Stripe** (`handle-stripe-webhook`) | vérification de signature, idempotence, écriture comptable de l'abonnement | 0,5 j |
| M-16 | **Synchronisation bancaire** (`sync-bank-transactions`) | lignes importées en `statement`, pointage 196, pas de doublon avec l'import de fichier | 0,5 j |
| M-17 | ⏳ **Temps passés** (24/09) | **Trouvé à l'exécution** : un temps de la société B pouvait viser le projet de la société A, et son nom partait dans une notification de B (famille 227/H02) ; montant libellé « € » en dur. Migration **231**, tests **231** (6 scénarios). **`M-17-01` reste rouge au registre** : les heures facturables n'atteignent aucune facture — `create_billable_line` ne crée qu'une notification. Reste : CRM, tâches, et la refacturation elle-même. | 1 j restant |
| M-18 | **Utilisateurs et invitations** (`create-user`, `auth-signup`) | un utilisateur invité ne voit que sa société ; rôle appliqué (lié à H08) | 0,5 j |
| M-19 | **Import Sage** (`SageImportPage`) | reprise d'un FEC ou d'une balance : équilibre, comptes créés, tiers | 0,5 j |
| M-20 | **Miroir** (`mirror-daemon`, 200) | après la 200 : écrits par un démon authentifié seulement | 0,25 j |

**Total audit** : ≈ 12 j, **plus les correctifs** qu'il révélera (estimation prudente : autant).

> **Relevé du 24/09 — les trois premiers modules audités.** M-06, M-08 et M-17 ont été
> pris en premier parce qu'ils sont les seuls ponts entre la gestion (production,
> livraison, projets) et le grand livre. Ils ont rendu **six défauts**, dont un
> **bloquant** (aucune commande confirmée ne pouvait passer à « livrée ») et un de
> **sécurité** (nom de projet d'une société visible depuis une autre). Aucun n'était
> visible sans exécuter un scénario chiffré : les 34 suites SQL existantes ne
> traversaient ni les rebuts, ni une reclôture, ni le cycle de réservation.
>
> Deux enseignements pour la suite de la phase 3 :
> - **chiffrer 0,5 j par module était optimiste** — trois modules ont pris une session
>   à eux seuls, correctifs compris ;
> - **les chemins d'annulation sont le gisement**. Les trois défauts d'idempotence
>   viennent du même motif : un statut `cancelled` permis par la contrainte CHECK,
>   qu'aucun déclencheur ne traite. `goods_receipts` porte le même motif et n'a pas
>   encore été vérifié (M-07).

---

## 7. PHASE 4 (V5, lot K phase 1) — Localisation : neutralité du code

Le détail de chaque exigence se trouve dans le [cahier de localisation](../localisation/CAHIER-DES-CHARGES-LOCALISATION.md) (§ 5, annexes A à E). Ce tableau indique **ce qui a déjà avancé** depuis sa rédaction et **ce qui reste**.

### 7.1 Déjà amorcé (ne pas refaire)

| Exigence | Avancée | Par |
|---|---|---|
| LOC1-12, LOC1-47 (création de société par pays, onboarding) | inscription refusée hors FR/DJ, plan provisoire DJ, `tenants.chart_pack_code` | 201 (session prod) |
| LOC1-13 (plan FR en données) | écran admin d'import CSV de plan, `chart_pack_status` | 201 |
| LOC1-34 (écriture de paie par rôles, chemin unique) | chemin unique `payroll_post_run` ; comptes par rubrique dans `payroll_account_mapping` (à migrer vers `resolve_account`) | 191 |
| LOC1-06 (triggers ventes/achats/règlements) | réécrits en V3, mais **encore sur comptes en dur** (707000, 419100, 409100, 609000, 530000…) | 190, 192 |
| LOC1-49 (devise du relevé) | lecteurs branchés ; devise pas encore contrôlée | V3 (R-10) |
| Garde-fou « comptes au plan » | G10 : tout compte littéral des écritures automatiques est au plan semé ; `chart_required_accounts` bloque la publication d'un plan incomplet | V3, 201 |

### 7.2 Reste à faire, dans l'ordre du cahier

| Lot | Exigences | Contenu | Effort (cahier) |
|---|---|---|---:|
| 1-A | LOC1-01 à 03 | modèle de données du pack (niveau, parent, version, statut), résolution héritée | 3 j |
| 1-B | LOC1-04 à 11 | **67 rôles de comptes, 8 rôles de journaux** (annexe B) ; `resolve_account()` / `resolve_journal()` ; réécriture sur rôles de **tous** les triggers, dont ceux de V3 (190–196) et `payroll_account_mapping` ; plus aucune logique par classe (`LIKE '6%'`) | 8 j |
| 1-C | LOC1-12 à 16 | `bootstrap_tenant(pack, secteur)` ; défauts `'EUR'`/`'France'` retirés de 34 colonnes ; verrouillage du pack après la première écriture ; pack et version figés sur chaque document | 4 j |
| 1-D | LOC1-17 à 22 | formatage unique par pack (97 imports de `formatCurrency`) ; arrondis SQL par unité mineure (DJF sans décimale) ; échelle des colonnes monétaires ; saisie localisée ; parités fixes | 6 j |
| 1-E | LOC1-23 à 29 | TVA portée par le pack (comptes et cases) ; code TVA POS neutre ; déclaration par gabarit ; régimes ; IS ; retenues à la source, timbre | 5 j |
| 1-F | LOC1-30 à 36 | paie paramétrée : fin des replis FR, pays de paie issu de la société, durées légales, **catégories de cotisations génériques (fin du modèle CSG/CRDS)**, rubriques et modèle de bulletin par pack, organismes | 5 j |
| 1-G | LOC1-37 à 40 | calendrier (week-end, fériés variables) ; **moteur d'états financiers par gabarit** (bilan, compte de résultat, SIG, liasse) ; contrôle de couverture | 5,5 j |
| 1-H | LOC1-41 à 45 | capacités par pays (routes, menus, fonctions Edge : FEC, SEPA, DSN désactivés hors FR) ; identifiants légaux génériques ; mentions obligatoires et numérotation par pack ; libellés réglementaires | 4 j |
| 1-I | LOC1-46 à 50 | référentiel ISO complet ; doublon `CI` SYSCOHADA ; import Sage par rôles | 2 j |
| 1-J | LOC1-51 à 55 | packs en fichiers (`packs/<CODE>/`, annexe C) ; importeur idempotent ; **validateur** (annexe D) ; cycle de vie ; **garde-fou CI anti-code-en-dur** (annexe E) | 5 j |
| 1-K | LOC1-56 à 58 | pack FR reconstruit à l'identique ; **pack fictif `ZZ`** qui prouve la neutralité (e2e complet sur un pays inventé) ; non-régression France chiffrée | 2,5 j |

**Recette de l'étape 1** : garde-fou anti-code-en-dur vert ; pack `ZZ` complet de bout en bout (inscription, vente, achat, paie, clôture, états) ; suites 102, 178 à 182, 189, 192 identiques pour la France.

**Total étape 1** : ≈ 48 j (cahier).

---

## 8. PHASE 5 (V5, lot K phase 2) — Localisation : Djibouti

**Règle absolue** : aucune valeur fiscale ou sociale djiboutienne saisie de mémoire. Chaque valeur porte une source `SRC-DJ-nn` et est validée deux fois (développeur + expert-comptable référent).

| Lot | Exigences | Contenu | Dépend de | Effort |
|---|---|---|---|---:|
| 2-A Gouvernance | LOC2-01 à 04 | référent (👤-4), registre des sources, **collecte des 14 documents** (👤-5), fiche d'identité pays | — | 1 j + délai externe |
| 2-B Plan comptable | LOC2-05 à 09 | `PCN-DJ` complet FR/AR (via l'écran CSV de la 201) ; rôles de comptes ; journaux ; clôture et affectation ; **gabarits d'états financiers DJ** | étape 1 (1-B, 1-G) | 6 j |
| 2-C Couche pays | LOC2-10 à 20 | DJF sans décimale ; parité USD/DJF ; calendrier ; identifiants (NIF, RCCM) ; mentions de facture ; **TVA DJ** (taux datés, exonérations, comptes, cases) ; déclaration de TVA ; IS et minimum ; patente, retenues, timbre ; liasse ; capacités (FEC, SEPA, DSN désactivés) | 1-D, 1-E, 1-H | 7 j |
| 2-D Paie | LOC2-21 à 28 | paramètres légaux ; **barème ITS** ; **CNSS et AMU** par branche ; rubriques ; congés, heures supplémentaires, fin de contrat ; modèle de bulletin ; écriture de paie ; déclarations | 1-F | 5,5 j |
| 2-E Secteur public | LOC2-29 à 31 | `DJ-EP` (entreprises publiques) ; `DJ-ADM` en option (8 à 10 semaines, D-11) | 2-B | 1,5 j (+ option) |
| 2-F Arabe | LOC2-32, 33 | libellés réglementaires en arabe ; PDF bilingues | I08 | 2 j |
| 2-G Recette | LOC2-34 à 41 | jeux d'essai DJ-01 (ventes/achats/TVA), DJ-02 (paie), DJ-03 (clôture), DJ-EP-01 ; recette signée ; **pilote 2 à 3 entreprises, une clôture mensuelle complète** (👤-6) ; publication du pack DJ v1.0.0 ; documentation utilisateur | tout | 6 j + 4 semaines de pilote |

**Bascule** : à la publication du plan DJ, la 201 bascule automatiquement les sociétés DJ au plan provisoire **sans écriture validée**. Celles qui ont déjà des écritures sont listées et demandent une **transposition** (LOC3-24, à anticiper pour les pilotes).

**Total étape 2** : ≈ 26 j + délai de collecte + 4 semaines de pilote.

---

## 9. PHASE 6 (après V5) — Localisation : autres pays

Hors du chemin critique de la v1 djiboutienne. Détail : cahier § 7.

| Bloc | Exigences | Effort |
|---|---|---:|
| Industrialisation | LOC3-01, 02, 16 à 20 (procédure, kit de collecte, veille, versions de pack, notification, rejeu automatique, tableau de couverture) | 4 j |
| Revalidation des 14 packs existants (taux non sourcés) | LOC3-03 | 2 j |
| Maghreb | LOC3-04 à 09 (Maroc CGNC, Tunisie SCE et 3 décimales, Algérie SCF) | 21 j |
| OHADA | LOC3-10 à 14 (SYSCOHADA révisé, SMT, UEMOA ×8, CEMAC ×6, hors zones) | 6 j + 3 à 5 j par pays |
| Divers | LOC3-15, 21 à 24 (secteur public, langues, facturation électronique nationale, groupes multi-pays, transposition de référentiel) | à chiffrer |

---

## 10. Recette finale

Le projet est terminé quand **toutes** les conditions suivantes sont vraies, chacune prouvée par une exécution datée dans le suivi :

1. `sql/ci/expected_failures.sql` ne contient aucune ligne `INSERT` (**vrai au 22/09**, à maintenir).
2. `db-integration` vert sur base neuve : suites 102, 105, 166, 168, 170, 173, 175, 177, 178 à 182, 189, 192, 202 et celles des phases 1 à 5.
3. `npm run db:embeds` sans liste blanche (**vrai au 22/09**, à maintenir).
4. e2e verts sur la PR finale vers `main`, dont les **6 parcours chiffrés** de J02.
5. Test de propriété à 100 000 écritures dans ses seuils (nocturne).
6. **Répétition sur copie de prod** de toutes les migrations non déployées, puis déploiement sans erreur.
7. Une société réelle créée par l'inscription tient **un exercice complet** : factures, achats, paie **et son paiement**, banque rapprochée, clôture, à-nouveaux. Bilan et compte de résultat **revus par l'expert-comptable**.
8. Garde-fou anti-code-en-dur vert ; pack `ZZ` complet de bout en bout.
9. Pack **DJ publié**, jeux d'essai DJ-01 à DJ-03 à 0 écart, **pilote validé**.
10. Clé Supabase tournée, `generate-pdf` traitée, sujet OCR/OpenAI tranché, rôles opposables ou documentés.
11. Aucune clé de traduction brute à l'écran en fr, en et ar ; arabe relu.

---

## 11. Calendrier, charge et chemin critique

### 11.1 Charge (une personne, jours de développement)

| Phase | Contenu | Charge | Délai externe |
|---|---|---:|---|
| 0 | Sécuriser, répéter, déployer, vérifier à l'écran | 2–3 j | fenêtre de déploiement |
| 1 | Dettes V1–V3 (R-01 à R-17) | ≈ 15 j | décisions D-3, D-9, D-10 |
| 2 | **V4** — H, I, J | ≈ 30–35 j | D-4, D-5, D-6 ; secrets E2E |
| 3 | Audit des modules non vérifiés + correctifs | ≈ 12 j + ≈ 12 j | — |
| 4 | **V5** — localisation étape 1 (neutralité) | ≈ 48 j | — |
| 5 | **V5** — Djibouti | ≈ 26 j | **collecte des textes**, référent, **pilote 4 semaines** |
| **Total jusqu'au pack DJ publié** | | **≈ 145–150 j** | |
| 6 | Autres pays | ≈ 35 j + 3–5 j/pays | textes de chaque pays |

### 11.2 Ordre recommandé et parallélisme

```
Semaine 1      PHASE 0 (commit, CI, répétition prod, déploiement, écran)
               👤 rotation de clé, secrets E2E, collecte DJ lancée, référent désigné
Semaines 2-4   PHASE 1 (dettes)  ─┐
                                  ├─ en parallèle si deux personnes :
Semaines 2-8   PHASE 2 (V4)      ─┘   H et J d'abord (sécurité, preuve), I ensuite
Semaines 5-7   PHASE 3 (audit des modules restants)
Semaines 6-15  PHASE 4 (neutralité) ── peut commencer dès la fin de la phase 1
Semaines 12-18 PHASE 5 (Djibouti)   ── démarre quand 1-B, 1-D, 1-E, 1-F, 1-G sont livrés
                                       ET que les textes sont collectés
Semaines 19-22 Pilote DJ (4 semaines calendaires), puis publication v1.0.0
```

### 11.3 Chemin critique

1. **Collecte des textes djiboutiens** (👤-5) : c'est elle qui fixe la date de la v1 DJ, pas le code. À lancer **cette semaine**.
2. **Rôles de comptes (1-B)** : tout le reste de la localisation en dépend, et il réécrit les triggers de 187 à 196. Ne pas multiplier les comptes en dur d'ici là.
3. **Répétition sur copie de prod** avant chaque déploiement : la prod a déjà divergé une fois du schéma CI.
4. **Preuve e2e chiffrée (J02)** : sans elle, aucune note ne peut dépasser le plafond « condition 3 » du barème 9,5.

### 11.4 Trajectoire de note attendue

| Module | 21/09 | Après V1–V3 (estimé) | Après phases 0–3 | Après Djibouti |
|---|:---:|:---:|:---:|:---:|
| Saisie et invariants | 4,5 | 8,5 | 9,0 | 9,5 |
| Clôture et états | 1,5 | 8,5 | 9,0 | 9,5 |
| Ventes | 3 | 8,5 | 9,0 | 9,5 |
| Achats | 5 | 8,5 | 9,0 | 9,5 |
| Trésorerie et banque | 4,5 | 7,5 | 9,0 | 9,5 |
| Stock et production | 6 | 8,0 | 9,5 | 9,5 |
| Paie | 3 | 6,0 (FR, sans paiement) | 6,5 | 9,5 |
| Sécurité | 7,5 | 7,5 | 9,5 | 9,5 |
| Ergonomie et i18n | 6 | 6,5 | 9,5 | 9,5 |
| Qualité et CI | 6 | 8,0 | 9,5 | 9,5 |
| Localisation Djibouti | 1 | 1,5 | 2 | 9,5 |

Les notes « après V1–V3 » sont des estimations : **aucune n'est prouvée tant que P0-08 (écran) et J02 (e2e chiffrés) ne sont pas faits.**
