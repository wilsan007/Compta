# Cahier des charges — Localisation multi-pays

> **Version** 1.0 — 15 septembre 2026
> **Branche** `commercial-hr-paie` (état : 154 migrations, 1 280 tests)
> **Objet** rendre Onusuite neutre vis-à-vis du pays, livrer Djibouti (privé et public) en premier, puis permettre l'ajout de tout autre pays par de simples données
> **Document amont** plan « Djibouti d'abord » — https://claude.ai/artifact/6bsai1zK5cm2Npc4ZRvWLy
> **Méthode d'inventaire** définition *effective* de chaque fonction SQL (dernière migration qui la redéfinit), `grep` sur `app/src` hors tests, lecture de `00_schema_dump.sql`

---

## Sommaire

- [1. Synthèse](#1-synthèse)
- [2. Principes non négociables](#2-principes-non-négociables)
- [3. Glossaire](#3-glossaire)
- [4. Registre maître](#4-registre-maître)
- [5. PHASE 1 — Refonte du code : neutralité pays](#5-phase-1--refonte-du-code--neutralité-pays)
- [6. PHASE 2 — Préparation et livraison Djibouti](#6-phase-2--préparation-et-livraison-djibouti)
- [7. PHASE 3 — Tous les autres pays](#7-phase-3--tous-les-autres-pays)
- [8. Critères de recette globaux](#8-critères-de-recette-globaux)
- [9. Plan d'exécution](#9-plan-dexécution)
- [Annexe A — Inventaire exhaustif du code en dur](#annexe-a--inventaire-exhaustif-du-code-en-dur)
- [Annexe B — Catalogue des rôles de comptes et de journaux](#annexe-b--catalogue-des-rôles-de-comptes-et-de-journaux)
- [Annexe C — Format de fichiers d'un pack](#annexe-c--format-de-fichiers-dun-pack)
- [Annexe D — Règles du validateur de pack](#annexe-d--règles-du-validateur-de-pack)
- [Annexe E — Règles du garde-fou anti-code-en-dur](#annexe-e--règles-du-garde-fou-anti-code-en-dur)

---

## 1. Synthèse

### 1.1 Constat

Onusuite possède les **fondations** d'une architecture multi-pays (`legislation_packs`, `tax_rates` versionnés, `payroll_tax_grids.country_code`, `LegislationProvider`, `useLocale`), mais le **comportement réel est français** :

| Domaine | Ce qui est en dur aujourd'hui | Volume |
|---|---|---:|
| Comptes comptables dans les fonctions SQL effectives | `411000`, `401000`, `707000`, `607000`, `120000`, `129000`, `421000`… | **17 fonctions** |
| Comptes comptables côté front | écritures de paie, génération d'écritures, TVA, SIG | **34 littéraux / 7 fichiers** |
| Logique par classe de compte (`LIKE '6%'`, `startsWith('7')`) | bilan, compte de résultat, liasse, TVA, tiers | **2 fonctions SQL + 10 appels front** |
| Codes de journaux | `'VT'`, `'AC'`, `'BQ'`, `'OD'`, `'AN'`, `'CA'`, `'ST'`, et `'ACH'` (incohérent) | **≈ 25 occurrences / 12 migrations** |
| Devise `'EUR'` | défauts de colonnes, fonctions, front | **25 colonnes + 4 fonctions + 106 occurrences / 30 fichiers** |
| Pays `'France'` / `'FR'` | défauts de colonnes, fonctions paie/POS | **6 colonnes + 4 fonctions** |
| Formats | `'fr-FR'` en dur (16), `toLocaleString()` sans locale (31), `toFixed(2)` (84), `€` littéral (13), `round(x, 2)` SQL (15 fonctions) | — |
| Paie | `FALLBACK_RATES` français, `151.67` h (3 endroits), 35 h, `v_country_code := 'FR'`, approximation 22 % | — |
| Calendrier | week-end samedi/dimanche en dur | **5 fichiers** |
| Plan comptable | `seed_standard_chart` = PCG français pour **toute** nouvelle société ; `chart_account_templates` vide | — |
| Fonctions françaises non conditionnées | FEC, EDI-TVA, TVS, SEPA, Factur-X, NF525, DSN, CPF, BDES, SIRET, VIES | **36 fichiers + 6 edge functions** |
| Onboarding | Djibouti absent de `COUNTRY_CODE_MAP` / `COUNTRY_CURRENCY_MAP` → EUR | — |

### 1.2 Découpage

| Phase | Objet | Lots | Exigences | Effort |
|---|---|---:|---:|---:|
| **PHASE 1** | Refonte du code : plus aucune règle pays dans le code, la France devient un pack | 11 | 58 | **≈ 48 j** |
| **PHASE 2** | Djibouti : collecte des textes, pack privé, pack entreprises publiques, paie, recette, pilote | 7 | 41 | **≈ 26 j** + délai d'obtention des textes + pilote |
| **PHASE 3** | Procédure d'ajout d'un pays, Maghreb, OHADA, maintenance réglementaire | 4 | 24 | **≈ 15 j** de socle + 5 à 15 j par pays |

### 1.3 Résultat attendu

1. Une société se crée en choisissant **pays → pack → secteur**. Tout (plan, journaux, devise, arrondis, TVA, paie, états, documents, calendrier, modules visibles) découle du pack.
2. **Aucune** valeur propre à un pays ne subsiste dans `app/src` ni dans les fonctions SQL effectives ; un garde-fou CI l'interdit.
3. Un pack ne peut être attribué que s'il est **publié**, et il n'est publiable que s'il passe le validateur (annexe D) et ses jeux d'essai à **0 unité d'écart**.
4. Ajouter un pays = ajouter un dossier `packs/<CODE>/` et ses sources. **Zéro ligne de code.**

---

## 2. Principes non négociables

| # | Principe | Conséquence concrète |
|---|---|---|
| P1 | **Le pays est une donnée** | Le code manipule des *rôles* (`CLIENTS`, `JOURNAL_VENTES`) et des *capacités* (`fec_export`), jamais des numéros ou des codes pays |
| P2 | **Échec explicite plutôt que repli silencieux** | Un rôle non mappé, un taux absent, une grille de paie manquante lèvent une erreur nommée. Plus aucun `COALESCE(x, '411000')`, `?? 'EUR'`, `FALLBACK_RATES` |
| P3 | **Chaque valeur réglementaire est sourcée** | Taux, plafond, barème, compte : référence au texte (intitulé, article, date d'effet). Sans source, le validateur refuse |
| P4 | **Versionné par date d'effet, jamais réécrit** | Un changement de loi = nouvelle ligne `effective_from`. Les documents gardent la version appliquée (snapshot) |
| P5 | **Pack figé par société** | Dès la première écriture validée, le pack et le référentiel ne changent plus. Changer de pays = autre société |
| P6 | **Les migrations historiques ne sont jamais modifiées** | Toute correction = nouvelle migration `155_…` et suivantes qui redéfinit la fonction |
| P7 | **La France est un pack comme les autres** | Aucun traitement privilégié ; c'est le premier client du moteur et le test de non-régression |
| P8 | **Hiérarchie Référentiel → Pays → Secteur** | La valeur la plus spécifique l'emporte ; les 17 pays OHADA partagent un référentiel |

---

## 3. Glossaire

| Terme | Définition |
|---|---|
| **Pack** | Ensemble versionné de données décrivant les règles d'un référentiel, d'un pays ou d'un secteur. Code unique (`PCN-DJ`, `DJ`, `DJ-EP`) |
| **Référentiel** | Pack de niveau 1 : plan comptable, rôles de comptes, gabarits d'états, règles de clôture (`PCG`, `SYSCOHADA`, `CGNC`, `SCF`, `SCE-TN`, `PCN-DJ`) |
| **Couche pays** | Pack de niveau 2, enfant d'un référentiel : devise, formats, fiscalité, paie, déclarations, documents, calendrier, capacités |
| **Couche secteur** | Pack de niveau 3, enfant d'une couche pays : écarts liés au statut (entreprise publique, établissement administratif) |
| **Pack effectif** | Résultat de la fusion Référentiel + Pays + Secteur attribué à une société |
| **Rôle de compte** | Identifiant fonctionnel stable (`CLIENTS`) que chaque référentiel mappe vers un compte de son plan |
| **Rôle de journal** | Idem pour les journaux (`JOURNAL_VENTES` → `VT`) |
| **Capacité** | Fonctionnalité réglementaire propre à un pays, activée ou non par le pack (`fec_export`, `dsn`, `sepa`) |
| **Source** | Référence documentaire d'une valeur (`SRC-DJ-04 : Loi de finances 20xx, art. n`) |
| **Jeu d'essai** | Cas chiffré réel (entrées + résultat attendu) qui doit passer à 0 unité d'écart |
| **Unité mineure** | Nombre de décimales légales de la devise (DJF 0, EUR 2, TND 3) |

---

## 4. Registre maître

### Convention

`LOCp-nn` — `p` = phase (1, 2, 3), `nn` = numéro stable. Sévérité : 🔴 bloque la conformité d'un pays non français · 🟠 produit un résultat faux ou trompeur · 🟡 confort / robustesse.

### Phase 1 — Refonte du code

| Réf | Exigence | Sév. | Localisation principale | Effort |
|---|---|:---:|---|---:|
| **LOC1-01** | Étendre `legislation_packs` (niveau, parent, version, statut, formats avancés) | 🔴 | nouvelle migration 155 | 1 j |
| **LOC1-02** | Tables de données du pack (rôles, journaux, capacités, calendrier, identifiants, sources) | 🔴 | migration 155 | 1 j |
| **LOC1-03** | Fonction de résolution héritée `pack_effective_*` | 🔴 | migration 156 | 1 j |
| **LOC1-04** | Catalogue fermé des rôles de comptes et de journaux | 🔴 | migration 156, annexe B | 0,5 j |
| **LOC1-05** | `resolve_account()` / `resolve_journal()` + surcharge par société | 🔴 | migration 156 | 1 j |
| **LOC1-06** | Réécrire les 4 triggers de ventes/achats/règlements sur les rôles | 🔴 | `137:45`, `137:183`, `108:237`, `108:286` | 1 j |
| **LOC1-07** | Réécrire paie, stock, production, POS sur les rôles | 🔴 | `81:295`, `101:156`, `112:111`, `125:240/255`, `142:22/175` | 1,5 j |
| **LOC1-08** | Réécrire clôture, affectation, amortissements, écarts sur les rôles | 🔴 | `153:34`, `107:267`, `152:586`, `124:98` | 1 j |
| **LOC1-09** | Remplacer les codes de journaux en dur | 🟠 | 12 migrations, `accounting.ts:1976` | 0,5 j |
| **LOC1-10** | Supprimer les comptes en dur côté front | 🔴 | 7 fichiers, annexe A.2 | 1 j |
| **LOC1-11** | Remplacer la logique par classe (`LIKE`, `startsWith`) | 🔴 | `152:89/153`, 10 appels front | 1 j |
| **LOC1-12** | `bootstrap_tenant(p_pack_code, p_sector)` à partir du pack | 🔴 | `02_bootstrap_tenant.sql:21`, `152:1736` | 1,5 j |
| **LOC1-13** | Transformer `seed_standard_chart` en données du pack FR | 🔴 | `03_seed_chart_template.sql` | 0,5 j |
| **LOC1-14** | Supprimer les défauts `'EUR'`/`'France'`/`'FR'`/`'CA3'` des colonnes | 🟠 | 34 colonnes, annexe A.4 | 1 j |
| **LOC1-15** | Verrouillage du pack après première écriture | 🔴 | trigger sur `journal_entries` | 0,5 j |
| **LOC1-16** | Snapshot `pack_code` + `pack_version` sur les documents | 🟠 | 6 tables | 0,5 j |
| **LOC1-17** | Service unique de formatage front piloté par le pack | 🔴 | `utils.ts:20`, `currencyRates.ts:132`, `useLocale.ts` | 1 j |
| **LOC1-18** | Migrer les 97 imports de `formatCurrency` et les formats en dur | 🔴 | annexe A.3 | 2 j |
| **LOC1-19** | Arrondis SQL pilotés par l'unité mineure | 🔴 | 15 fonctions, annexe A.5 | 1 j |
| **LOC1-20** | Vérifier / élargir l'échelle des colonnes monétaires | 🔴 | `numeric(14,2)`/`(15,2)` dans 31 migrations | 1 j |
| **LOC1-21** | Saisie des montants selon la locale et l'unité mineure | 🟠 | champs `type="number" step="0.01"` | 0,5 j |
| **LOC1-22** | Taux de change fixes (parités) | 🟠 | `exchange_rates`, `currencyRates.ts` | 0,5 j |
| **LOC1-23** | `tax_rates` porteur des comptes et des cases de déclaration | 🔴 | `legislation_packs_migration.sql:54`, `109:12` | 1 j |
| **LOC1-24** | Code TVA POS indépendant du pays | 🟠 | `142_fix_pos_triggers.sql:105` | 0,25 j |
| **LOC1-25** | Déclaration de TVA pilotée par gabarit | 🔴 | `accounting.ts:1580-1587`, `VatReturnsPage.tsx` | 1 j |
| **LOC1-26** | Replis TVA en dur en saisie | 🟠 | `JournalSaisiePage.tsx:534`, `SaisieParPiecePage.tsx:177` | 0,25 j |
| **LOC1-27** | Régimes et périodicités de TVA définis par le pack | 🟠 | `company_settings.vat_regime` | 0,5 j |
| **LOC1-28** | Impôt sur les bénéfices et impôts divers par pack | 🟠 | `corporate_tax_grids`, `CorporateTaxCalcPage.tsx` | 0,5 j |
| **LOC1-29** | Retenues à la source, timbre, taxes parafiscales génériques | 🟡 | nouvelle table `pack_other_taxes` | 0,5 j |
| **LOC1-30** | Supprimer `FALLBACK_RATES` et les replis de paie | 🔴 | `payroll.ts:51`, `153:603` | 0,5 j |
| **LOC1-31** | Pays de la paie issu de la société | 🔴 | `153:444`, `114:122` | 0,25 j |
| **LOC1-32** | Durées légales et majorations en paramètres | 🔴 | `payroll.ts:92`, `leavesAbsences.ts:566`, `152:358`, `PayrollCalcPage.tsx:25` | 0,5 j |
| **LOC1-33** | Catégories de cotisations génériques (fin du modèle CSG/CRDS) | 🔴 | `36:…category CHECK`, `114:73` | 1 j |
| **LOC1-34** | Écriture de paie par rôles, chemin unique | 🔴 | `queries/payroll.ts:205`, `misc.ts:38`, `81:295` | 0,5 j |
| **LOC1-35** | Rubriques de bulletin et modèle de bulletin par pack | 🟠 | `payroll_components` | 1 j |
| **LOC1-36** | Organismes sociaux et déclarations sociales par pack | 🟠 | `social_declarations`, `SocialDeclarationsPage.tsx` | 0,5 j |
| **LOC1-37** | Calendrier : jours ouvrés, week-end, jours fériés (dont dates variables) | 🔴 | 5 fichiers, `public_holidays.country` | 1 j |
| **LOC1-38** | Moteur d'états financiers par gabarit | 🔴 | `152:89`, `152:153`, `BalanceSheetPage.tsx`, `SIGPage.tsx`, `LiasseFiscalePage.tsx` | 3 j |
| **LOC1-39** | Contrôle de couverture des gabarits | 🔴 | validateur | 0,5 j |
| **LOC1-40** | Gabarits de déclarations fiscales | 🟠 | `LiasseFiscalePage.tsx`, `EdiTvaPage.tsx` | 1 j |
| **LOC1-41** | Registre des capacités et conditionnement des routes | 🔴 | `App.tsx`, `Sidebar.tsx`, `ModuleHub.tsx` | 1 j |
| **LOC1-42** | Conditionnement des edge functions par capacité | 🔴 | 6 edge functions | 0,5 j |
| **LOC1-43** | Identifiants légaux génériques (fin de `siret`/`vat_number` en dur) | 🔴 | `company_settings`, `customers`, `suppliers` | 1 j |
| **LOC1-44** | Mentions obligatoires et numérotation des documents par pack | 🟠 | `generate-pdf`, `facturX.ts` | 1 j |
| **LOC1-45** | Libellés réglementaires (TVA, SIRET…) issus du pack | 🟠 | `i18n/locales/*` | 0,5 j |
| **LOC1-46** | Référentiel ISO pays/devises complet | 🔴 | `countries.ts` | 0,5 j |
| **LOC1-47** | Onboarding pays → pack → secteur, sans devinette | 🔴 | `OnboardingPage.tsx:82-95`, `OnboardingModal.tsx` | 1 j |
| **LOC1-48** | Corriger le doublon `country_code 'CI'` de SYSCOHADA | 🟠 | `legislation_packs_migration.sql:140` | 0,1 j |
| **LOC1-49** | Import bancaire : devise lue, jamais supposée | 🟠 | `bankParsers.ts` (8 occurrences) | 0,25 j |
| **LOC1-50** | Import Sage : classification des tiers par rôles | 🟡 | `SageImportPage.tsx:113-115` | 0,25 j |
| **LOC1-51** | Format de pack en fichiers (`packs/<CODE>/`) | 🔴 | nouveau dossier, annexe C | 1 j |
| **LOC1-52** | Importeur de pack idempotent | 🔴 | `scripts/pack-import.mjs` | 1 j |
| **LOC1-53** | Validateur de pack (annexe D) | 🔴 | `scripts/pack-validate.mjs` | 1,5 j |
| **LOC1-54** | Cycle de vie : brouillon → validé → publié → archivé | 🟠 | `legislation_packs.status` | 0,5 j |
| **LOC1-55** | Garde-fou CI anti-code-en-dur (annexe E) | 🔴 | `scripts/check-country-neutral.mjs` | 1 j |
| **LOC1-56** | Pack FR reconstruit à l'identique | 🔴 | `packs/PCG`, `packs/FR` | 1 j |
| **LOC1-57** | Pack fictif `ZZ` de preuve de neutralité | 🔴 | `packs/ZZ`, test E2E | 0,5 j |
| **LOC1-58** | Non-régression France chiffrée | 🔴 | `seed_demo_data.sql`, `102_trigger_tests.sql` | 1 j |

### Phase 2 — Djibouti

| Réf | Exigence | Sév. | Effort |
|---|---|:---:|---:|
| **LOC2-01** | Référent expert-comptable et circuit de double validation | 🔴 | — |
| **LOC2-02** | Registre des sources `SRC-DJ-nn` | 🔴 | 0,5 j |
| **LOC2-03** | Collecte des 14 documents officiels | 🔴 | délai externe |
| **LOC2-04** | Fiche d'identité pays DJ (faits établis) | 🔴 | 0,25 j |
| **LOC2-05** | Référentiel `PCN-DJ` : plan comptable complet FR/AR | 🔴 | 2 j |
| **LOC2-06** | Mapping des rôles de comptes `PCN-DJ` | 🔴 | 1 j |
| **LOC2-07** | Journaux et exercice | 🟠 | 0,25 j |
| **LOC2-08** | Règles de clôture et d'affectation du résultat | 🔴 | 0,5 j |
| **LOC2-09** | Gabarits d'états financiers DJ | 🔴 | 2 j |
| **LOC2-10** | Formats DJ (DJF, décimales de prix, arrondi, fr-DJ, ar-DJ) | 🔴 | 0,25 j |
| **LOC2-11** | Parité fixe USD/DJF et devises usuelles | 🟠 | 0,25 j |
| **LOC2-12** | Calendrier DJ (repos hebdomadaire, fériés fixes et variables) | 🔴 | 0,5 j |
| **LOC2-13** | Identifiants légaux DJ et contrôles | 🟠 | 0,25 j |
| **LOC2-14** | Mentions obligatoires des factures et avoirs | 🔴 | 0,5 j |
| **LOC2-15** | TVA DJ : taux datés, exonérations, comptes, cases | 🔴 | 1 j |
| **LOC2-16** | Déclaration de TVA DJ | 🔴 | 1 j |
| **LOC2-17** | Impôt sur les bénéfices et minimum d'imposition | 🔴 | 0,5 j |
| **LOC2-18** | Patente, retenues à la source, droits de timbre | 🟠 | 0,5 j |
| **LOC2-19** | Liasse / déclaration de résultat DJ | 🔴 | 1 j |
| **LOC2-20** | Capacités DJ (désactivation FEC, SEPA, DSN…) | 🔴 | 0,1 j |
| **LOC2-21** | Paramètres légaux de paie DJ | 🔴 | 0,5 j |
| **LOC2-22** | Barème de l'impôt sur les traitements et salaires | 🔴 | 0,5 j |
| **LOC2-23** | Cotisations CNSS par branche et AMU | 🔴 | 0,5 j |
| **LOC2-24** | Rubriques de bulletin DJ (primes, indemnités, avantages) | 🔴 | 1 j |
| **LOC2-25** | Congés, heures supplémentaires, fin de contrat | 🟠 | 1 j |
| **LOC2-26** | Modèle de bulletin DJ | 🔴 | 0,5 j |
| **LOC2-27** | Écriture de paie DJ | 🔴 | 0,25 j |
| **LOC2-28** | Déclarations sociales et fiscales sur salaires DJ | 🔴 | 1 j |
| **LOC2-29** | Couche `DJ-EP` : entreprises publiques à caractère commercial | 🔴 | 1,5 j |
| **LOC2-30** | Couche `DJ-ADM` : établissements administratifs (option) | 🟠 | 8-10 sem. si retenue |
| **LOC2-31** | Paie secteur public (grille indiciaire, option) | 🟡 | 1 j si retenue |
| **LOC2-32** | Traduction arabe des libellés réglementaires | 🟠 | 1 j |
| **LOC2-33** | Documents PDF bilingues FR/AR | 🟡 | 1 j |
| **LOC2-34** | Jeu d'essai DJ-01 : cycle ventes/achats/TVA | 🔴 | 0,5 j |
| **LOC2-35** | Jeu d'essai DJ-02 : bulletins de paie | 🔴 | 0,5 j |
| **LOC2-36** | Jeu d'essai DJ-03 : clôture et états financiers | 🔴 | 0,5 j |
| **LOC2-37** | Jeu d'essai DJ-EP-01 : subventions et dotations | 🔴 | 0,5 j |
| **LOC2-38** | Recette fonctionnelle signée | 🔴 | 2 j |
| **LOC2-39** | Pilote sur 2 à 3 entreprises, une clôture mensuelle complète | 🔴 | 4 sem. calendaires |
| **LOC2-40** | Publication du pack DJ v1.0.0 | 🔴 | 0,1 j |
| **LOC2-41** | Documentation utilisateur Djibouti | 🟡 | 1 j |

### Phase 3 — Autres pays

| Réf | Exigence | Sév. | Effort |
|---|---|:---:|---:|
| **LOC3-01** | Procédure standard d'ajout d'un pays | 🔴 | 0,5 j |
| **LOC3-02** | Kit de collecte documentaire générique | 🟠 | 0,5 j |
| **LOC3-03** | Revalidation des 14 packs existants (taux non sourcés) | 🔴 | 2 j |
| **LOC3-04** | Référentiel `CGNC` (Maroc) | 🔴 | 3 j |
| **LOC3-05** | Couche pays `MA` | 🔴 | 4 j |
| **LOC3-06** | Référentiel `SCE-TN` (Tunisie) | 🔴 | 3 j |
| **LOC3-07** | Couche pays `TN` (3 décimales) | 🔴 | 4 j |
| **LOC3-08** | Référentiel `SCF` (Algérie) | 🔴 | 3 j |
| **LOC3-09** | Couche pays `DZ` | 🔴 | 4 j |
| **LOC3-10** | Référentiel `SYSCOHADA` révisé (système normal) | 🔴 | 4 j |
| **LOC3-11** | Système minimal de trésorerie (SMT) | 🟠 | 2 j |
| **LOC3-12** | Couches pays UEMOA (8 pays, XOF) | 🔴 | 3-5 j / pays |
| **LOC3-13** | Couches pays CEMAC (6 pays, XAF) | 🔴 | 3-5 j / pays |
| **LOC3-14** | Couches pays OHADA hors zones monétaires (Guinée, Comores, RDC) | 🟠 | 3-5 j / pays |
| **LOC3-15** | Couches secteur public par pays | 🟡 | à chiffrer |
| **LOC3-16** | Veille réglementaire et calendrier des lois de finances | 🔴 | 0,5 j |
| **LOC3-17** | Processus de nouvelle version de pack | 🔴 | 0,5 j |
| **LOC3-18** | Notification des sociétés impactées par une nouvelle version | 🟠 | 1 j |
| **LOC3-19** | Rejeu automatique des jeux d'essai à chaque version | 🔴 | 0,5 j |
| **LOC3-20** | Tableau de bord de couverture des packs | 🟡 | 1 j |
| **LOC3-21** | Langues : arabe (MA, TN, DZ), anglais (pays OHADA anglophones du Cameroun) | 🟠 | 1 j / langue |
| **LOC3-22** | Facturation électronique nationale (si obligation locale) | 🟠 | à chiffrer par pays |
| **LOC3-23** | Groupes multi-pays : consolidation et conversion | 🟡 | hors périmètre v1 |
| **LOC3-24** | Transposition d'une société d'un référentiel à un autre | 🟡 | 3 j |

---
## 5. PHASE 1 — Refonte du code : neutralité pays

**Objectif de phase.** À la sortie, la France fonctionne exactement comme aujourd'hui, mais **uniquement** au travers des packs `PCG` + `FR`, et un pack fictif `ZZ` fait tourner le cycle complet sans toucher une ligne de code.

**Règle de migration.** Toutes les corrections SQL se font dans de nouvelles migrations numérotées à partir de `155_`, qui redéfinissent les fonctions (`CREATE OR REPLACE`). Les migrations 01 à 154 ne sont pas modifiées (principe P6).

---

### LOT 1-A — Modèle de données du pack

#### `LOC1-01` — Étendre `legislation_packs`

**Constat.** La table (`legislation_packs_migration.sql:24`) décrit un pays à plat : pas de hiérarchie, pas de version, pas de statut de publication, une seule notion de décimales, pas de règle d'arrondi. Le pack `SYSCOHADA` est à la fois un référentiel et un pays (`country_code 'CI'`).

**Spécification.** Migration `155_pack_model.sql` :

```sql
ALTER TABLE legislation_packs
  ADD COLUMN IF NOT EXISTS level text NOT NULL DEFAULT 'country'
    CHECK (level IN ('referential','country','sector')),
  ADD COLUMN IF NOT EXISTS parent_code text REFERENCES legislation_packs(code),
  ADD COLUMN IF NOT EXISTS sector text
    CHECK (sector IS NULL OR sector IN ('private','public_enterprise','public_administrative','non_profit')),
  ADD COLUMN IF NOT EXISTS version text NOT NULL DEFAULT '0.0.0',          -- semver
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','validated','published','archived')),
  ADD COLUMN IF NOT EXISTS published_at timestamptz,
  ADD COLUMN IF NOT EXISTS validated_by text,                              -- nom de l'expert signataire
  ADD COLUMN IF NOT EXISTS price_decimals int NOT NULL DEFAULT 2,           -- prix unitaires
  ADD COLUMN IF NOT EXISTS quantity_decimals int NOT NULL DEFAULT 3,
  ADD COLUMN IF NOT EXISTS rounding_mode text NOT NULL DEFAULT 'half_up'
    CHECK (rounding_mode IN ('half_up','half_even','down')),
  ADD COLUMN IF NOT EXISTS rounding_level text NOT NULL DEFAULT 'line'
    CHECK (rounding_level IN ('line','document')),                         -- arrondi TVA par ligne ou par total
  ADD COLUMN IF NOT EXISTS number_system text NOT NULL DEFAULT 'latn',      -- chiffres latins imposés
  ADD COLUMN IF NOT EXISTS ui_languages text[] NOT NULL DEFAULT '{fr}',
  ADD COLUMN IF NOT EXISTS document_languages text[] NOT NULL DEFAULT '{fr}',
  ADD COLUMN IF NOT EXISTS week_start int NOT NULL DEFAULT 1,               -- 1 = lundi (ISO)
  ADD COLUMN IF NOT EXISTS weekend_days int[] NOT NULL DEFAULT '{6,7}',     -- ISO : 6 samedi, 7 dimanche
  ADD COLUMN IF NOT EXISTS source_ref text;                                  -- texte fondateur

-- Un pack de niveau pays/secteur doit avoir un parent ; un référentiel n'en a pas
ALTER TABLE legislation_packs ADD CONSTRAINT legislation_packs_hierarchy_chk CHECK (
  (level = 'referential' AND parent_code IS NULL) OR
  (level IN ('country','sector') AND parent_code IS NOT NULL)
);
-- Un pack pays porte un code ISO ; un référentiel n'en porte pas
ALTER TABLE legislation_packs ALTER COLUMN country_code DROP NOT NULL;
ALTER TABLE legislation_packs ADD CONSTRAINT legislation_packs_country_chk CHECK (
  (level = 'referential' AND country_code IS NULL) OR
  (level IN ('country','sector') AND country_code ~ '^[A-Z]{2}$')
);
```

Les colonnes `currency`, `currency_decimals`, `locale`, `date_format`, `fiscal_year_start`, `tax_id_label` existantes sont conservées ; elles n'ont de sens qu'au niveau `country` (contrôlé par le validateur, règle V03).

**Recette.** Insérer un pack `sector` sans parent lève `legislation_packs_hierarchy_chk`. Insérer un référentiel avec `country_code` lève `legislation_packs_country_chk`.

**Effort.** 1 j (avec LOC1-48).

---

#### `LOC1-02` — Tables de données du pack

**Spécification.** Même migration. Toutes les tables sont **globales** (pas de `tenant_id`), en lecture pour tout utilisateur authentifié, écriture par `service_role` uniquement, comme `legislation_packs`.

| Table | Clé | Colonnes principales | Remplace / complète |
|---|---|---|---|
| `pack_sources` | `(pack_code, source_id)` | `title`, `issuer`, `reference` (n° de loi/décret), `article`, `published_on`, `effective_from`, `url`, `file_sha256` | nouveau |
| `pack_account_roles` | `(pack_code, role)` | `account_code`, `source_id` | nouveau |
| `pack_journal_roles` | `(pack_code, role)` | `journal_code`, `journal_name`, `journal_type`, `source_id` | codes `'VT'`… en dur |
| `pack_capabilities` | `(pack_code, capability)` | `enabled bool`, `config jsonb` | nouveau |
| `pack_holidays` | `(pack_code, holiday_date)` | `label`, `label_ar`, `is_variable bool`, `source_id` | `public_holidays.country` |
| `pack_legal_identifiers` | `(pack_code, identifier_type)` | `label`, `label_ar`, `regex`, `checksum_algo`, `required_for` (`company`,`customer_b2b`,`supplier`), `printed_on_invoice bool` | `siret`, `vat_number` |
| `pack_document_rules` | `(pack_code, document_type)` | `mandatory_mentions jsonb`, `numbering_pattern`, `numbering_reset` (`never`,`yearly`), `gapless bool`, `source_id` | nouveau |
| `pack_statement_templates` | `(pack_code, template_code)` | `name`, `kind` (`balance_sheet`,`income_statement`,`cash_flow`,`notes`,`tax_return`,`vat_return`,`social_return`), `periodicity` | `generate_balance_sheet` |
| `pack_statement_lines` | `(pack_code, template_code, line_code)` | `label`, `label_ar`, `parent_line`, `sort_order`, `sign` (`debit`,`credit`,`net`), `account_ranges text[]`, `formula text`, `box_code` | `LIKE '6%'` |
| `pack_other_taxes` | `id` | `pack_code`, `tax_code`, `kind` (`withholding`,`stamp`,`business_license`,`parafiscal`), `rate`, `fixed_amount`, `base`, `account_role`, `effective_from/to`, `source_id` | nouveau |

Les tables existantes reçoivent une colonne `source_id text` : `tax_rates`, `chart_account_templates`, `payroll_tax_grids`, `payroll_tax_grid_lines`, `payroll_legal_parameters`, `corporate_tax_grids`, `corporate_tax_grid_lines`.

`payroll_tax_grids`, `payroll_legal_parameters` et `corporate_tax_grids` reçoivent `pack_code text REFERENCES legislation_packs(code)` ; `country_code` est conservé pour compatibilité puis rendu redondant (rempli par trigger depuis le pack).

**Recette.** `\d` des 10 tables ; les politiques `SELECT` existent ; un `INSERT` en rôle `authenticated` est refusé.

**Effort.** 1 j.

---

#### `LOC1-03` — Résolution héritée

**Constat.** Rien ne fusionne aujourd'hui un référentiel, un pays et un secteur ; `LegislationProvider` charge un pack isolé (`legislation.tsx:34`).

**Spécification.** Migration `156_pack_resolution.sql`.

```sql
-- Chaîne d'ancêtres : secteur → pays → référentiel (profondeur max 3)
CREATE OR REPLACE FUNCTION pack_lineage(p_pack_code text)
RETURNS TABLE(code text, depth int) LANGUAGE sql STABLE AS $$
  WITH RECURSIVE l AS (
    SELECT lp.code, lp.parent_code, 0 AS depth FROM legislation_packs lp WHERE lp.code = p_pack_code
    UNION ALL
    SELECT lp.code, lp.parent_code, l.depth + 1 FROM legislation_packs lp JOIN l ON lp.code = l.parent_code
    WHERE l.depth < 3
  ) SELECT code, depth FROM l;
$$;

-- Pack effectif d'une société (lit tenants.legislation_pack_code)
CREATE OR REPLACE FUNCTION tenant_pack_code(p_tenant_id uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT legislation_pack_code FROM tenants WHERE id = p_tenant_id;
$$;

-- Paramètre de format effectif : premier non NULL en remontant la lignée
CREATE OR REPLACE FUNCTION pack_currency_decimals(p_tenant_id uuid) RETURNS int ...
```

Une vue `v_pack_effective` expose, pour chaque pack publié, les colonnes de format résolues (devise, décimales, locale, week-end, langues). Le front la lit **une fois** via `getActiveLegislationPack()`.

Règle de fusion par table : pour `pack_account_roles`, `pack_journal_roles`, `pack_capabilities`, `pack_legal_identifiers`, `pack_document_rules` → **la ligne du pack le plus profond gagne** (`ORDER BY depth ASC LIMIT 1`). Pour `pack_holidays`, `tax_rates`, `pack_other_taxes` → **union** des lignes de la lignée.

**Recette.** Test SQL : pack `ZZ-SEC` (secteur) → `ZZ` (pays) → `ZZREF` (référentiel) ; un rôle défini dans `ZZREF` et redéfini dans `ZZ-SEC` renvoie la valeur de `ZZ-SEC`.

**Effort.** 1 j.

---

### LOT 1-B — Rôles de comptes et de journaux

#### `LOC1-04` — Catalogue fermé des rôles

**Spécification.** Table `account_role_catalog (role text PRIMARY KEY, family text, normal_side text CHECK IN ('debit','credit'), description text, required_for text[])` et `journal_role_catalog` équivalente. Contenu intégral : **annexe B** (67 rôles de comptes, 8 rôles de journaux).

`required_for` indique les modules qui exigent le rôle (`sales`, `purchases`, `payroll`, `stock`, `pos`, `closing`, `assets`, `fx`). Le validateur n'exige un rôle que si le module correspondant est activé dans les capacités du pack.

Toute nouvelle fonction qui a besoin d'un compte **ajoute un rôle au catalogue** dans la même migration ; elle ne code jamais un numéro.

**Recette.** `pack_account_roles.role` a une clé étrangère vers `account_role_catalog` ; un rôle inconnu est refusé.

**Effort.** 0,5 j.

---

#### `LOC1-05` — `resolve_account()` et `resolve_journal()`

**Constat.** Des résolutions partielles existent déjà mais retombent sur un compte français : `resolve_stock_account` (`125:240`) → `'310000'`, `resolve_variation_account` (`125:255`) → `'603000'`, `COALESCE(c.account_collectif, '411000')` (`137:45`), `COALESCE(p.sale_account_code, pc.sale_account_code, v_defaut_vente)` (`110:95`).

**Spécification.**

```sql
CREATE TABLE IF NOT EXISTS tenant_account_roles (
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  role text NOT NULL REFERENCES account_role_catalog(role),
  account_code text NOT NULL,
  PRIMARY KEY (tenant_id, role)
);
-- RLS : tenant_id = current_tenant_id()

CREATE OR REPLACE FUNCTION resolve_account(
  p_tenant_id uuid,
  p_role text,
  p_context jsonb DEFAULT '{}'::jsonb   -- {product_id, category_id, customer_id, supplier_id, bank_account_id, vat_rate_id, asset_category_id, organism_code}
) RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_code text;
BEGIN
  -- 1. Surcharge au niveau de l'objet métier (ordre fixé par rôle)
  v_code := resolve_account_from_context(p_tenant_id, p_role, p_context);
  -- 2. Surcharge société
  IF v_code IS NULL THEN
    SELECT account_code INTO v_code FROM tenant_account_roles
     WHERE tenant_id = p_tenant_id AND role = p_role;
  END IF;
  -- 3. Pack effectif (lignée)
  IF v_code IS NULL THEN
    SELECT par.account_code INTO v_code
      FROM pack_lineage(tenant_pack_code(p_tenant_id)) l
      JOIN pack_account_roles par ON par.pack_code = l.code AND par.role = p_role
     ORDER BY l.depth LIMIT 1;
  END IF;
  -- 4. Échec explicite (P2)
  IF v_code IS NULL THEN
    RAISE EXCEPTION 'ROLE_NON_MAPPE: le rôle % n''a aucun compte pour la société %', p_role, p_tenant_id
      USING ERRCODE = 'P0001', HINT = 'Paramétrage > Comptes par défaut';
  END IF;
  -- 5. Le compte doit exister dans le plan de la société
  IF NOT EXISTS (SELECT 1 FROM chart_accounts WHERE tenant_id = p_tenant_id AND code = v_code) THEN
    RAISE EXCEPTION 'COMPTE_ABSENT: le rôle % pointe vers % absent du plan', p_role, v_code USING ERRCODE = 'P0001';
  END IF;
  RETURN v_code;
END $$;
```

Ordre de résolution par contexte (`resolve_account_from_context`) :

| Rôle | Ordre |
|---|---|
| `CLIENTS` | `customers.account_collectif` → société → pack |
| `FOURNISSEURS` | `suppliers.account_collectif` → société → pack |
| `VENTES_*` | `products.sale_account_code` → `product_categories.sale_account_code` → société → pack |
| `ACHATS_*` | `products.purchase_account_code` → `product_categories.purchase_account_code` → société → pack |
| `STOCK_*`, `VARIATION_STOCK_*` | `product_categories.stock_account_code` / `variation_account_code` → société → pack |
| `BANQUE` | `bank_accounts.account_code` → société → pack |
| `TVA_COLLECTEE`, `TVA_DEDUCTIBLE_*` | `tax_rates.account_collected` / `account_deductible` du taux appliqué → société → pack |
| `ORGANISME_SOCIAL` | `payroll_tax_grid_lines.account_code` de l'organisme → société → pack |
| `IMMOBILISATIONS`, `AMORTISSEMENTS`, `DOTATIONS_AMORTISSEMENTS` | `fixed_asset_categories.*_account_code` → société → pack |

`resolve_journal(p_tenant_id, p_role)` suit le même schéma sur `tenant_journal_roles` puis `pack_journal_roles`, et renvoie `journals.code` existant de la société.

`resolve_stock_account` et `resolve_variation_account` deviennent des enveloppes de `resolve_account(..., 'STOCK_MARCHANDISES' | 'VARIATION_STOCK_MARCHANDISES', ...)`.

Côté front, `app/src/lib/accountRoles.ts` expose `resolveAccount(role, context)` qui appelle la RPC ; **aucun** calcul local.

**Recette.**
1. Société FR : `resolve_account(t, 'CLIENTS')` = `411000`.
2. Client avec `account_collectif = '411100'` : `resolve_account(t, 'CLIENTS', '{"customer_id": …}')` = `411100`.
3. Suppression du mapping : exception `ROLE_NON_MAPPE`.
4. Mapping vers un compte supprimé du plan : exception `COMPTE_ABSENT`.

**Effort.** 1 j.

---

#### `LOC1-06` — Triggers ventes, achats, règlements

**Constat et spécification.** Nouvelle migration `157_roles_sales_purchases.sql`, qui redéfinit :

| Fonction effective | Défini en | Littéraux | Remplacement |
|---|---|---|---|
| `create_journal_on_invoice_validate` | `137_fix_triggers_constraints.sql:45` | `v_collectif := '411000'` (l. 52), `COALESCE(c.account_collectif,'411000')` (l. 68), `v_defaut_vente := '707000'` (l. 59), `journal_code = 'VT'` (l. 64, 75) | `resolve_account(NEW.tenant_id,'CLIENTS',jsonb_build_object('customer_id',NEW.customer_id))` ; par ligne `resolve_account(…,'VENTES_MARCHANDISES' ou 'PRESTATIONS_SERVICES' selon products.type, {product_id})` ; TVA `resolve_account(…,'TVA_COLLECTEE',{vat_rate_id})` ; `resolve_journal(…,'JOURNAL_VENTES')` |
| `create_journal_on_purchase_invoice_validate` | `137:183` | `'401000'` (l. 190, 206), `'607000'` (l. 197), `'AC'` (l. 202, 213) | `FOURNISSEURS`, `ACHATS_MARCHANDISES`/`SERVICES_EXTERIEURS`, `TVA_DEDUCTIBLE_BIENS_SERVICES` ou `TVA_DEDUCTIBLE_IMMOBILISATIONS`, `JOURNAL_ACHATS` |
| `create_journal_on_customer_payment` | `108_auxiliary_accounts.sql:237` | `'411000'` (l. 243), `'512000'`, `'BQ'` (l. 263) | `CLIENTS`, `BANQUE` avec `{bank_account_id}` ou `CAISSE` selon mode de paiement, `JOURNAL_BANQUE`/`JOURNAL_CAISSE` |
| `create_journal_on_supplier_payment` | `108:286` | `'401000'`, `'411000'`, `'512000'`, `'BQ'` (l. 312) | idem côté fournisseurs |

Les 4 contrôles d'équilibre/solde de `108:349-381` (`jl.account_code = '411000'` / `'401000'`) sont réécrits pour filtrer sur `account_tiers IS NOT NULL AND third_party_id = …` plutôt que sur un numéro.

**Recette.** Rejouer `102_trigger_tests.sql` sur société FR : écritures identiques ligne à ligne à celles d'avant (comparaison `account_code, debit, credit` triée). Rejouer sur société `ZZ` (clients `9100`, ventes `8100`) : écritures sur `9100`/`8100`.

**Effort.** 1 j.

---

#### `LOC1-07` — Paie, stock, production, POS

Migration `158_roles_operations.sql` :

| Fonction effective | Défini en | Littéraux | Rôles |
|---|---|---|---|
| `create_journal_on_payroll_validate` | `81_complete_workflow_triggers.sql:295` | `421`, `421000`, `431`, `431000`, `641`, `641000`, `645`, `645000` | `SALAIRES_BRUTS`, `CHARGES_SOCIALES_PATRONALES`, `PERSONNEL_REMUNERATIONS_DUES`, `ORGANISME_SOCIAL` (une ligne par organisme), `ETAT_IMPOT_SALAIRES`, `JOURNAL_PAIE` |
| `create_journal_on_stock_movement` | `101_stock_valuation_to_gl.sql:156` | `310000`, `603000`, `'ST'` (l. 204) | `STOCK_*`, `VARIATION_STOCK_*` selon `products.type`, `JOURNAL_STOCK` |
| `create_stock_on_manufacturing_complete` | `112_manufacturing_costing.sql:111` | `310000`, `355000`, `601000`, `613000`, `641000`, `713550` | `STOCK_PRODUITS_FINIS`, `STOCK_MATIERES`, `ACHATS_MATIERES`, `SOUS_TRAITANCE`, `SALAIRES_BRUTS`, `PRODUCTION_STOCKEE` |
| `resolve_stock_account` | `125_stock_advanced.sql:240` | `310000` | enveloppe `resolve_account` |
| `resolve_variation_account` | `125:255` | `603000` | enveloppe `resolve_account` |
| `post_pos_session_on_close` | `142_fix_pos_triggers.sql:22` | `531000`, `707000`, `'CA'` (l. 55), `'FR' \|\|` (l. 105) | `CAISSE_POS`, `VENTES_MARCHANDISES`, `JOURNAL_CAISSE` ; code TVA → LOC1-24 |
| `post_pos_session_on_close_multi` | `142:175` | `707000` | `VENTES_MARCHANDISES`, comptes de moyens de paiement via `pos_payment_methods.account_code` sinon `CAISSE_POS` |

**Défauts révélés par l'inventaire (à corriger dans la même migration).** Vérification des littéraux contre le plan de `03_seed_chart_template.sql` :
- `create_stock_on_manufacturing_complete` (`112:111`) écrit sur **`713550`, compte absent du plan** : l'écriture de production stockée pointe vers un compte inexistant. Rôle `PRODUCTION_STOCKEE` → `713500` dans le pack PCG.
- La même fonction utilise **`613000` (locations)** pour la sous-traitance ; en PCG la sous-traitance générale est `611000`. Rôle `SOUS_TRAITANCE` → `611000`, à confirmer par l'expert-comptable du pack FR.
- `create_journal_on_stock_movement` et `resolve_stock_account` utilisent **`310000` (matières premières)** pour tous les stocks, y compris les marchandises (`370000`). Les rôles `STOCK_MARCHANDISES` / `STOCK_MATIERES` / `STOCK_PRODUITS_FINIS` distinguent les trois selon `products.type`.
- `generate_depreciation_entry` (`152:586`) utilise `280000` (amortissements des immobilisations **incorporelles**) et `681000` pour tous les biens ; rôles `AMORTISSEMENTS` / `DOTATIONS_AMORTISSEMENTS` résolus par catégorie d'immobilisation (`281xxx` / `681100` pour les corporelles).

Ces changements modifient les écritures françaises : ils sont exclus de la comparaison à l'identique de LOC1-58 et font l'objet d'une validation explicite (liste des écritures impactées sur la base de démonstration).

**Recette.** Pour chaque fonction, un scénario `102_trigger_tests` FR à l'identique (hors défauts ci-dessus) + le même scénario en `ZZ`.

**Effort.** 1,5 j.

---

#### `LOC1-08` — Clôture, affectation, amortissements, écarts

Migration `159_roles_closing.sql` :

| Fonction effective | Défini en | Littéraux | Rôles |
|---|---|---|---|
| `close_fiscal_year` | `153_fix_carry_forward_and_payroll.sql:34` | `120000`/`129000` (l. 133, 250, 277), `'OD'`, `'AN'` | `RESULTAT_BENEFICE`, `RESULTAT_PERTE`, `JOURNAL_OD`, `JOURNAL_A_NOUVEAUX` ; la sélection des comptes de gestion à solder se fait par `pack_statement_lines` du gabarit `income_statement` (LOC1-38), **plus par classe** |
| `allocate_result` | `107_fiscal_year_close.sql:267` | `106000`, `120000`, `129000`, `457000` | `RESERVE_LEGALE`, `AUTRES_RESERVES`, `REPORT_A_NOUVEAU_CREDITEUR`, `REPORT_A_NOUVEAU_DEBITEUR`, `ASSOCIES_DIVIDENDES_A_PAYER` ; le taux et le plafond de réserve légale deviennent des `pack_other_taxes`/paramètres sourcés, pas des constantes |
| `generate_depreciation_entry` | `152_fix_broken_rpc_functions.sql:586` | `280000`, `681000` | `AMORTISSEMENTS`, `DOTATIONS_AMORTISSEMENTS` avec `{asset_category_id}` |
| `generate_residual_entry` | `124_acc_advanced.sql:98` | `654`, `665`, `666`, `766`, `'OD'` (l. 134) | `PERTES_CREANCES_IRRECOUVRABLES`, `ESCOMPTES_ACCORDES`, `PERTES_CHANGE`, `GAINS_CHANGE`, `JOURNAL_OD` |

Les `'OD'` et `'AN'` de `103:539`, `103:574`, `107:121`, `107:180`, `107:320`, `121:260`, `124:256` sont traités dans LOC1-09.

**Recette.** Clôture d'un exercice FR de démonstration : balance d'ouverture N+1 identique à l'actuelle au centime. Clôture `ZZ` : résultat porté sur le compte mappé `ZZ`.

**Effort.** 1 j.

---

#### `LOC1-09` — Codes de journaux en dur

**Constat.** Occurrences dans les définitions effectives ou encore actives : `137:64/75` (`'VT'`), `137:202/213` (`'AC'`), `101:204` (`'ST'`), `103:539`, `103:574` (`'OD'`), `107:121`, `107:320` (`'OD'`), `107:180` (`'AN'`), `108:144/155` (`'VT'`), `108:195/206` (`'AC'`), `108:263/312` (`'BQ'`), `109:80/91/188/199`, `110:66/77/201/212`, `113:40` et `142:55` (`'CA'`), `121:260` (`'AN'`), `124:134/256` (`'OD'`). Côté front, `accounting.ts:1976` utilise **`'ACH'`** alors que le SQL utilise **`'AC'`** — les écritures générées par ce chemin atterrissent dans un journal qui n'existe pas dans `bootstrap_tenant`.

**Spécification.** Remplacer chaque code par `resolve_journal(tenant, rôle)`. `bootstrap_tenant` crée les journaux depuis `pack_journal_roles` (LOC1-12). Dans le front, `accounting.ts:1974-1978` appelle `resolveJournal('JOURNAL_ACHATS')`.

**Recette.** Garde-fou E03 (annexe E) : zéro code de journal littéral dans les fonctions effectives.

**Effort.** 0,5 j.

---

#### `LOC1-10` — Comptes en dur côté front

| Fichier:ligne | Littéraux | Correction |
|---|---|---|
| `src/lib/queries/payroll.ts:205-209` | `641000`, `645000`, `431000`, `437000`, `421000` | supprimer : l'écriture de paie est produite **uniquement** par le trigger SQL (LOC1-34) |
| `src/lib/queries/misc.ts:38-41` | `641000`, `645000`, `421000`, `431000` | idem, second chemin redondant supprimé |
| `src/lib/queries/accounting.ts:1974-1978` | `411000`, `707000`, `607000`, `401000`, `512000`, journaux `'ACH'`, `'BQ'` | RPC `generate_entry_from_document(p_type, p_id)` qui applique les mêmes rôles que les triggers |
| `src/lib/queries/accounting.ts:1580-1581` | préfixes `4457`, `4456` | LOC1-25 |
| `src/lib/queries/accounting.ts:1586-1587` | préfixes `70`, `60` | LOC1-11 |
| `src/pages/JournalSaisiePage.tsx:534` | `'445660'`, `'445710'` | LOC1-26 |
| `src/pages/SaisieParPiecePage.tsx:177` | `'445660'`, `'445710'` | LOC1-26 |
| `src/pages/SIGPage.tsx:74` | `getSolde('603')` | LOC1-38 (gabarit `SIG`, capacité FR) |
| `src/pages/SageImportPage.tsx:113-115` | préfixes `401`, `411`, `421` | LOC1-50 |
| `src/lib/importConfig.ts:34` | `sample: '512000'` | exemple d'import : lire le compte mappé `BANQUE` du pack actif |
| `src/pages/payroll/PayrollPreparationPage.tsx:354` | `useState('2000')` | valeur vide par défaut (montant sans devise ni pays) |

**Recette.** Garde-fou E01 (annexe E) passe sur `app/src`.

**Effort.** 1 j.

---

#### `LOC1-11` — Logique par classe de compte

**Constat.** La signification d'une classe diffère selon le référentiel : en SYSCOHADA la classe 8 regroupe les charges et produits HAO, en CGNC la classe 3 est l'actif circulant et la classe 4 le passif circulant, en PCG la classe 4 mêle actif et passif. Toute règle `LIKE '4%'` est donc fausse hors PCG.

| Fichier:ligne | Code actuel | Remplacement |
|---|---|---|
| `152_fix_broken_rpc_functions.sql:110-111` (`generate_balance_sheet`) | `LIKE '2%' … '5%'` pour l'actif | gabarit `balance_sheet` (LOC1-38) |
| `152:131` | `LIKE '1%' OR '4%' OR '5%'` pour le passif | idem |
| `152:172` (`generate_profit_loss`) | `LIKE '7%'` | gabarit `income_statement` |
| `152:188` | `LIKE '6%'` | idem |
| `LiasseFiscalePage.tsx:56-57` | `startsWith('7')`, `startsWith('6')` | gabarit `tax_return` |
| `accounting.ts:1586-1587` | `startsWith('70')`, `startsWith('60')` | lignes `CA` / `ACHATS` du gabarit `vat_return` |
| `ThirdPartyAccountsPage.tsx:320` | `startsWith('4')` | `chart_accounts.is_third_party` (nouvelle colonne alimentée par le pack) |
| `ChartAccountsPage.tsx:179` | `startsWith('4')` | idem |
| `JournalsPage.tsx:312` | `startsWith('47') \|\| startsWith('48')` | `chart_accounts.account_nature = 'transitory'` |

**Spécification complémentaire.** `chart_account_templates` et `chart_accounts` reçoivent :

```sql
ADD COLUMN IF NOT EXISTS account_class text,          -- classe au sens du référentiel ('1'…'9')
ADD COLUMN IF NOT EXISTS account_nature text CHECK (account_nature IN
  ('equity','liability','asset_fixed','asset_current','third_party','cash','expense','income',
   'expense_hao','income_hao','transitory','off_balance','analytical')),
ADD COLUMN IF NOT EXISTS is_third_party boolean NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS allow_direct_entry boolean NOT NULL DEFAULT true,
ADD COLUMN IF NOT EXISTS name_ar text;
```

Le `type` existant (`asset`, `liability`, `equity`, `income`, `expense`) reste pour compatibilité ; `account_nature` est la référence.

**Recette.** Garde-fou E02 : zéro `LIKE '<chiffre>%'` sur `account_code` dans les fonctions effectives, zéro `startsWith('<chiffre>')` sur un code de compte dans `src`.

**Effort.** 1 j (hors moteur d'états, LOC1-38).

---

### LOT 1-C — Création de société et données par défaut

#### `LOC1-12` — `bootstrap_tenant` piloté par le pack

**Constat.** `02_bootstrap_tenant.sql:21` : appelle `seed_standard_chart` (PCG), insère `'401000'`, `'411000'`, `'512000'`, `'530000'`, la devise `('EUR','Euro','€',1.0)` (l. 70), `COALESCE(v_tenant.currency,'EUR')` (l. 105), `fiscal_year_start '01-01'` (l. 106). `create_tenant_for_current_user` (`152:1736`) : `COALESCE(p_data->>'currency','EUR')` (l. 1791).

**Spécification.** Migration `160_bootstrap_from_pack.sql` :

```sql
CREATE OR REPLACE FUNCTION bootstrap_tenant(p_tenant_id uuid, p_pack_code text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_pack record;
BEGIN
  SELECT * INTO v_pack FROM v_pack_effective WHERE code = p_pack_code;
  IF v_pack IS NULL OR v_pack.status <> 'published' THEN
    RAISE EXCEPTION 'PACK_NON_PUBLIE: %', p_pack_code USING ERRCODE = 'P0001';
  END IF;
  -- 1. Plan comptable : union ordonnée de la lignée (le plus profond gagne sur le libellé)
  -- 2. tenant_account_roles : vide (la résolution lit le pack) — copie seulement si la société personnalise
  -- 3. Journaux : un par rôle de pack_journal_roles
  -- 4. Devise fonctionnelle : v_pack.currency, taux 1, décimales v_pack.currency_decimals ; devises usuelles (capacité 'common_currencies')
  -- 5. Exercice courant : bornes calculées depuis v_pack.fiscal_year_start
  -- 6. company_settings : currency, country_code, locale depuis le pack ; aucun défaut 'France'
  -- 7. tenants.legislation_pack_code, pack_version_at_creation
END $$;
```

`create_tenant_for_current_user(p_data jsonb)` exige `p_data->>'pack_code'` ; absent → exception `PACK_REQUIS`. La devise n'est plus lue depuis `p_data` : elle vient du pack.

**Recette.**
1. Création `FR` : plan, journaux, devise et exercice identiques à une création actuelle (diff SQL vide).
2. Création `ZZ` : plan `ZZ`, devise `XTS`, exercice selon `fiscal_year_start` de `ZZ`.
3. Création sans pack : exception `PACK_REQUIS`.
4. Création avec pack `draft` : exception `PACK_NON_PUBLIE`.

**Effort.** 1,5 j.

---

#### `LOC1-13` — PCG en données

**Spécification.** Extraire les ≈ 600 comptes de `seed_standard_chart` (`03_seed_chart_template.sql:29` et `00_schema_dump.sql:11518`) vers `packs/PCG/chart.csv` avec `account_class`, `account_nature`, `is_third_party`. La fonction `seed_standard_chart` est redéfinie pour lever `OBSOLETE: utiliser bootstrap_tenant(tenant, pack)`.

**Recette.** `SELECT count(*) FROM chart_account_templates WHERE pack_code='PCG'` = nombre de comptes de l'ancienne fonction ; `EXCEPT` des deux listes vide.

**Effort.** 0,5 j.

---

#### `LOC1-14` — Défauts de colonnes

**Constat.** `00_schema_dump.sql` :

- **`DEFAULT 'EUR'` (25 colonnes)** : `bank_accounts.currency`, `company_settings.currency`, `credit_notes.currency_code`, `customer_payments.currency_code`, `customers.currency`, `customers.currency_code`, `fixed_assets.currency_code`, `invoices.currency_code`, `journal_entries.currency_code`, `journal_entries.functional_currency`, `journals.currency_code`, `legislation_packs.currency`, `online_payments.currency_code`, `partner_bank_accounts.currency_code`, `payment_orders.currency_code`, `price_lists.currency`, `purchase_credit_notes.currency_code`, `purchase_invoices.currency_code`, `sepa_payment_orders.currency`, `supplier_payments.currency_code`, `supplier_price_lists.currency_code`, `suppliers.currency`, `suppliers.currency_code`, `tenants.currency`, `third_party_accounts.currency`.
- **`DEFAULT 'France'` (5)** : `company_settings.country`, `customers.country`, `suppliers.country`, `tenants.country`, `warehouses.country`.
- **`DEFAULT 'CA3'` (2)** : `company_settings.vat_regime`, `tax_rates.type`.
- **`DEFAULT 'FR'` (1)** : `public_holidays.country`.
- **`DEFAULT 'fr-FR'` (1)** : `legislation_packs.locale`.
- **`DEFAULT '01-01'` (2)** : `company_settings.fiscal_year_start`, table l. 2128.

**Spécification.** Migration `161_drop_country_defaults.sql` :

1. `ALTER COLUMN … DROP DEFAULT` sur les 36 colonnes.
2. Trigger générique `BEFORE INSERT` `set_default_currency()` sur les 22 tables de documents et tiers : si `currency_code IS NULL` → devise fonctionnelle de la société (`tenant_functional_currency(NEW.tenant_id)`).
3. Trigger `set_default_country()` sur `customers`, `suppliers`, `warehouses` : si `country IS NULL` → pays du pack de la société.
4. `sepa_payment_orders.currency` : `CHECK (currency = 'EUR')` (le SEPA **est** euro — seule exception légitime, documentée dans l'allowlist E04).
5. `tax_rates.type DEFAULT 'CA3'` : colonne à renommer en `declaration_regime`, sans défaut (LOC1-27).

**Recette.** Insertion d'une facture sans devise dans une société `ZZ` → `XTS`. `SELECT column_default FROM information_schema.columns WHERE column_default ~ '''(EUR|France|FR|CA3|fr-FR)'''` → uniquement l'exception SEPA.

**Effort.** 1 j.

---

#### `LOC1-15` — Verrouillage du pack

**Spécification.**

```sql
CREATE OR REPLACE FUNCTION prevent_pack_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.legislation_pack_code IS DISTINCT FROM OLD.legislation_pack_code
     AND EXISTS (SELECT 1 FROM journal_entries WHERE tenant_id = NEW.id AND status = 'posted') THEN
    RAISE EXCEPTION 'PACK_VERROUILLE: la société a des écritures validées ; créez une nouvelle société ou utilisez la transposition'
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_prevent_pack_change BEFORE UPDATE OF legislation_pack_code ON tenants
  FOR EACH ROW EXECUTE FUNCTION prevent_pack_change();
```

Même règle sur `company_settings.legislation_pack_code`, `company_settings.currency` et `tenants.currency`. Autorisé : passer à une **version** supérieure du même pack (LOC3-17). Côté front, `SettingsPage.tsx` et `CompanySettingsPage.tsx` affichent le pack en lecture seule avec le message du trigger.

**Recette.** Valider une écriture puis tenter de changer le pack → exception ; avant toute écriture → accepté.

**Effort.** 0,5 j.

---

#### `LOC1-16` — Snapshot du pack sur les documents

**Spécification.** `ADD COLUMN pack_code text, pack_version text` sur `journal_entries`, `invoices`, `purchase_invoices`, `credit_notes`, `payslips` (ou table de bulletins effective), `vat_returns`. Trigger `BEFORE INSERT` qui les remplit depuis la société ; colonnes immuables après `status = 'posted'`.

**Recette.** Publier `FR 1.1.0` ; une facture antérieure garde `1.0.0`.

**Effort.** 0,5 j.

---

### LOT 1-D — Monnaie, arrondis, formats

#### `LOC1-17` — Service de formatage unique

**Constat.**
- `src/lib/utils.ts:20` : `formatCurrency(amount, currency = 'EUR')` avec `minimumFractionDigits: 2` → 1 500 DJF affichés `1 500,00 €`.
- `src/lib/currencyRates.ts:132` : `formatCurrencyWithCode(…, locale = 'fr-FR')`.
- `src/hooks/useLocale.ts:18-20` : repli `'fr-FR'` et `'EUR'` si pas de pack.
- `src/lib/utils.ts:10-17` : `LOCALE_MAP` `fr → 'fr-FR'`, repli `'fr-FR'`.

**Spécification.** Nouveau module `src/lib/format/index.ts`, **seul** endroit autorisé à instancier `Intl.NumberFormat` / `Intl.DateTimeFormat` (garde-fou E05) :

```ts
export interface FormatContext {
  locale: string              // pack.locale, ex. 'fr-DJ'
  numberingSystem: string     // pack.number_system, ex. 'latn'
  functionalCurrency: string  // pack.currency
  currencyDecimals: number    // pack.currency_decimals
  priceDecimals: number
  quantityDecimals: number
  timeZone: string            // pack.time_zone (à ajouter en LOC1-01)
}
export function formatMoney(ctx: FormatContext, amount: number, currency?: string): string
  // décimales = currency === functional ? ctx.currencyDecimals : minorUnits(currency)
  // minorUnits(c) = new Intl.NumberFormat('en', {style:'currency', currency:c}).resolvedOptions().maximumFractionDigits
export function formatPrice(ctx, amount, currency?)      // priceDecimals
export function formatQuantity(ctx, qty)
export function formatPercent(ctx, value, decimals?)
export function formatDate(ctx, d), formatDateTime(ctx, d)
export function parseAmount(ctx, input: string): number   // accepte l'espace fine et la virgule de la locale
export function roundMoney(ctx, amount, currency?): number // mode d'arrondi du pack
```

Règles :
1. Aucun paramètre par défaut de devise ni de locale. Contexte absent → **erreur** en développement, affichage du nombre brut + code devise ISO en production (jamais un symbole deviné).
2. `numberingSystem` passé via la locale étendue (`fr-DJ-u-nu-latn`, `ar-DJ-u-nu-latn`).
3. `useLocale()` devient un simple adaptateur React qui construit le `FormatContext` depuis `useLegislation()` ; si `pack` est `null` (utilisateur non rattaché), il renvoie un contexte **neutre** explicite : locale de l'UI, pas de devise.
4. `utils.formatCurrency`, `utils.formatNumber`, `utils.formatDate`, `currencyRates.formatCurrencyWithCode` sont supprimés à la fin de LOC1-18.

**Recette (tests unitaires).**

| Contexte | Appel | Attendu |
|---|---|---|
| `fr-FR`, EUR, 2 | `formatMoney(1234.5)` | `1 234,50 €` |
| `fr-DJ`, DJF, 0 | `formatMoney(1234.5)` | `1 235 Fdj` (arrondi `half_up`) |
| `fr-DJ`, DJF, 0 | `formatMoney(99.99, 'USD')` | `99,99 $US` |
| `fr-TN`, TND, 3 | `formatMoney(1.2345)` | `1,235 DT` |
| `ar-DZ`, DZD, 2, `latn` | `formatMoney(1000)` | chiffres latins, aucun chiffre arabe-indien |
| `fr-DJ` | `parseAmount('1 234')` | `1234` |

Les libellés exacts de symboles dépendent des données CLDR du navigateur ; les tests comparent après normalisation des espaces insécables et vérifient le nombre de décimales et le système de chiffres.

**Effort.** 1 j.

---

#### `LOC1-18` — Migration des usages front

**Constat (hors tests).**

| Motif | Occurrences | Principaux fichiers |
|---|---:|---|
| import de `formatCurrency` depuis `@/lib/utils` | 97 fichiers | ensemble des pages métier |
| `'EUR'` | 106 / 30 fichiers | `countries.ts` (22, légitime : table ISO), `SupplierPaymentsPage.tsx` (9), `CustomerPaymentsPage.tsx` (9), `SaisieParPiecePage.tsx` (8), `JournalSaisiePage.tsx` (8), `bankParsers.ts` (8), `MultiCompanyPage.tsx` (3), `JournalsPage.tsx` (3), `ExchangeRatesPage.tsx` (3) |
| `'fr-FR'` en dur | 16 | `NotificationCenter.tsx:171`, `accounting.ts:421,441,461`, `Nf525AuditPage.tsx:255`, `LandingPage.tsx:243,265`, `ApiWebhooksPage.tsx:247,303`, `currencyRates.ts:132`, `utils.ts:10,17`, `useLocale.ts:7,18` |
| `toLocaleString()` / `toLocaleDateString()` sans argument | 31 | — |
| `toFixed(2)` | 84 | `facturX.ts` (14), `LeaveBalancesPage.tsx` (7), `SocialDeclarationsPage.tsx` (6), `BudgetTrackingPage.tsx` (5), `SaisieParPiecePage.tsx` (4), `JournalSaisiePage.tsx` (4), `FECExportPage.tsx` (4), `EmployeeExitPage.tsx` (4), `BIReportingPage.tsx` (4) |
| `€` littéral dans le code | 13 | `EmployeeExitPage.tsx` (4), `PayrollPreparationPage.tsx` (2), `ManufacturingOrderDetailPage.tsx` (2), `ManufacturingOrdersPage.tsx`, `InventoryPage.tsx`, `payroll.ts:97`, `maeParser.ts`, `LandingPage.tsx` |

Cas particuliers :
- `CustomerPaymentsPage.tsx:99-120` et `SupplierPaymentsPage.tsx` : `currencyCode === 'EUR'` sert à décider « devise fonctionnelle ou non ». Remplacer par `currencyCode === ctx.functionalCurrency` ; `getLatestRate('EUR', currencyCode)` → `getLatestRate(ctx.functionalCurrency, currencyCode)`.
- `JournalSaisiePage.tsx:418` `journal.currency_code || 'EUR'` et `:658` `functional_currency: 'EUR'` → devise fonctionnelle du contexte.
- `accounting.ts:421,441,461` : montant dans un **libellé d'écriture** → `formatMoney` avec le contexte de la société, résolu côté serveur si possible.
- `toFixed(2)` dans `facturX.ts` et `FECExportPage.tsx` : formats d'échange **français** où le point et 2 décimales sont imposés par la norme → conservés, fichiers placés dans l'allowlist E04 et rattachés aux capacités `factur_x` / `fec_export`.
- `toFixed(2)` ailleurs : `roundMoney` pour le calcul, `formatMoney` pour l'affichage.
- `LandingPage.tsx` : page publique, hors société → contexte neutre issu de la langue du navigateur ; tolérée dans l'allowlist.

**Spécification.** Remplacement mécanique fichier par fichier, avec codemod `scripts/codemods/format-context.mjs` pour les 97 imports ; revue manuelle des cas particuliers.

**Recette.** Garde-fous E05 à E08 à zéro hors allowlist. Parcours manuel des 20 écrans les plus utilisés en société `ZZ` (XTS, 3 décimales) : aucun `€`, aucune décimale erronée.

**Effort.** 2 j.

---

#### `LOC1-19` — Arrondis SQL

**Constat.** `round(x, 2)` dans 15 fonctions effectives : `update_task_time_on_time_entry` (`85:405`), `update_project_hours_on_time_entry` (`85:446`), `create_billable_line_on_timesheet_stop` (`85:546`), `calculate_late_payment_penalties` (`103:24`), `calculate_sales_commissions` (`103:83`), `customer_credit_score` (`103:157`), `calculate_project_profitability` (`103:280`), `calculate_provisions` (`103:389`), `post_deferred_charge` (`103:494`), `generate_accounting_annex` (`103:622`), `calculate_inventory_variance` (`103:842`), `generate_balance_sheet` (`152:89`), `generate_profit_loss` (`152:153`), `calculate_production_cost` (`152:1108`), `calculate_payslip` (`153:354`, 17 occurrences dont l. 569-603).

**Spécification.**

```sql
CREATE OR REPLACE FUNCTION round_money(p_tenant_id uuid, p_amount numeric, p_currency text DEFAULT NULL)
RETURNS numeric LANGUAGE sql STABLE AS $$ ... $$;   -- décimales et mode du pack ; devise étrangère → unités mineures ISO (table currencies.decimals)
CREATE OR REPLACE FUNCTION round_price(p_tenant_id uuid, p_amount numeric) ...
CREATE OR REPLACE FUNCTION round_rate(p_value numeric, p_decimals int) ...  -- pourcentages, heures : arrondi technique explicite
```

Classer chaque `round(…, 2)` : **montant** → `round_money` ; **heures, pourcentages, scores** (`85:405`, `85:446`, `103:157`) → `round_rate(x, 2)` explicite (non monétaire, autorisé par E09).

`currencies` reçoit `decimals int NOT NULL` alimenté depuis ISO 4217 (LOC1-46).

Mode `half_even` : implémenté par fonction dédiée (PostgreSQL `round(numeric)` arrondit « half away from zero »).

**Recette.** Tests SQL : `round_money(t_DJ, 1234.5)` = `1235` ; `round_money(t_TN, 1.2345)` = `1.235` (half_up) ; `round_money(t_FR, 2.675)` = `2.68`.

**Effort.** 1 j.

---

#### `LOC1-20` — Échelle des colonnes monétaires

**Constat.** Les migrations déclarent `numeric(15,2)` (102 fois), `numeric(14,2)` (89), `NUMERIC(12,2)` (4) dans 31 fichiers, notamment `25_accounting_features.sql` (23), `21_phase4_payroll_hr.sql` (17), `20_phase3_treasury.sql` (17), `22_phase5_fixed_assets.sql` (16). Une colonne à 2 décimales **tronque** le dinar tunisien (3 décimales) et les prix unitaires à plus de 2 décimales. `00_schema_dump.sql` n'affiche pas les échelles : l'état réel doit être lu sur la base.

**Spécification.**
1. Requête d'inventaire sur la base de référence :
   ```sql
   SELECT table_name, column_name, numeric_precision, numeric_scale
   FROM information_schema.columns
   WHERE table_schema = 'public' AND data_type = 'numeric' AND numeric_scale IS NOT NULL AND numeric_scale < 4
   ORDER BY 1, 2;
   ```
2. Colonnes de **montant** : `ALTER COLUMN … TYPE numeric(20,4)`. Colonnes de **prix unitaire** et **quantité** : `numeric(20,6)`. Colonnes de **taux** : `numeric(9,6)`.
3. Migration `162_widen_money_scale.sql` générée par script depuis l'inventaire, exécutée table par table (verrou `ACCESS EXCLUSIVE` : fenêtre de maintenance) ; recréation des vues dépendantes.
4. La valeur stockée reste arrondie par `round_money` ; l'échelle 4 garantit seulement qu'aucun pays ne soit tronqué.

**Recette.** Requête d'inventaire → plus aucune colonne monétaire avec `numeric_scale < 4`. Facture `TN` à 1,235 TND : relue à 1,235.

**Effort.** 1 j.

---

#### `LOC1-21` — Saisie des montants

**Constat.** Les champs montants utilisent `type="number" step="0.01"` (ou `0.000001` pour les taux, `CustomerPaymentsPage.tsx:170`) : le navigateur refuse la virgule selon la locale système et impose 2 décimales.

**Spécification.** Composant `<MoneyInput currency?>` : `type="text" inputMode="decimal"`, analyse via `parseAmount(ctx)`, `step` dérivé des décimales, affichage formaté hors focus. Remplacement dans les formulaires de documents, paiements, saisie comptable, paie.

**Recette.** En `fr-DJ`, saisir `1 500` → 1500 ; saisir `1500,5` → message « Le franc djiboutien n'a pas de décimales ». En `fr-TN`, `1,235` accepté.

**Effort.** 0,5 j.

---

#### `LOC1-22` — Taux de change fixes

**Constat.** `exchange_rates` et `refresh-exchange-rates` ne connaissent que des cours flottants ; `trigger_exchange_rate_refresh` (`72:58`) contient 6 fois `'EUR'` comme devise pivot.

**Spécification.** Table `pack_fixed_parities (pack_code, base_currency, quote_currency, rate numeric(20,10), effective_from, effective_to, source_id)`. `getLatestRate(from, to)` consulte d'abord les parités fixes du pack effectif. La devise pivot de la tâche planifiée devient la devise fonctionnelle de chaque société (ou USD technique, converti ensuite). Le taux fixe est affiché avec un badge « parité fixe » et non modifiable par l'utilisateur.

**Recette.** Société `ZZ` avec parité `XTS/USD` fixe : un paiement en USD applique la parité, la tâche de rafraîchissement ne l'écrase pas.

**Effort.** 0,5 j.

---
### LOT 1-E — Fiscalité paramétrée

#### `LOC1-23` — `tax_rates` porteur des comptes et des cases

**Constat.** `tax_rates` (`legislation_packs_migration.sql:54`) n'a qu'un `account_code` optionnel, rempli pour la France seulement (`'44571'`). Les comptes par taux et les cases de déclaration vivent dans `vat_account_mapping` (`109_vat_multi_rate.sql:12`), table **par société** seedée avec des codes français `FR20`, `FR10`, `FR055`, `FR021`, `FR0`, `EXO`, `UE` et des cases CA3 `A1`, `A2`, `B2` (l. 32-41) sur un `tenant_id` fictif `00000000-…`.

**Spécification.**

```sql
ALTER TABLE tax_rates
  ADD COLUMN IF NOT EXISTS tax_code text,                       -- stable, ex. 'DJ-STD', 'FR-20'
  ADD COLUMN IF NOT EXISTS tax_kind text NOT NULL DEFAULT 'vat'
    CHECK (tax_kind IN ('vat','sales_tax','excise','other')),
  ADD COLUMN IF NOT EXISTS scope text NOT NULL DEFAULT 'both'
    CHECK (scope IN ('sales','purchases','both')),
  ADD COLUMN IF NOT EXISTS exemption_reason text,                -- mention légale imprimée si taux 0 / exonéré
  ADD COLUMN IF NOT EXISTS account_role_collected text REFERENCES account_role_catalog(role),
  ADD COLUMN IF NOT EXISTS account_role_deductible text REFERENCES account_role_catalog(role),
  ADD COLUMN IF NOT EXISTS account_collected text,               -- surcharge explicite du compte
  ADD COLUMN IF NOT EXISTS account_deductible text,
  ADD COLUMN IF NOT EXISTS declaration_box_base text,            -- case de la base dans le gabarit vat_return
  ADD COLUMN IF NOT EXISTS declaration_box_tax text,
  ADD COLUMN IF NOT EXISTS reverse_charge boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS vat_on_receipts_allowed boolean NOT NULL DEFAULT false;   -- TVA sur encaissements
ALTER TABLE tax_rates ADD CONSTRAINT tax_rates_code_uniq UNIQUE (pack_code, tax_code, effective_from);
```

`vat_account_mapping` devient une table de **surcharge société** uniquement (vide par défaut). Le seed français de `109:32` est déplacé dans `packs/FR/taxes.yaml`. Les lignes à `tenant_id = '00000000-0000-0000-0000-000000000000'` sont supprimées.

Les produits (`products.vat_rate`, `invoice_lines.vat_rate`) référencent désormais `tax_rate_id` (le taux numérique reste en snapshot).

**Recette.** Facture FR à deux taux : écritures TVA identiques à l'actuel. Facture `ZZ` à un taux `ZZ-STD` : compte issu du rôle `TVA_COLLECTEE` de `ZZ`.

**Effort.** 1 j.

---

#### `LOC1-24` — Code TVA du POS

**Constat.** `142_fix_pos_triggers.sql:105` construit le code TVA ainsi : `'FR' || REPLACE(tl.vat_rate::text, '.', '')` → `FR20`, `FR55`. En Djibouti, le code n'existe pas et la ventilation échoue ou tombe sur un compte par défaut.

**Spécification.** Les lignes de ticket portent `tax_rate_id` ; la ventilation groupe par `tax_rate_id` et résout le compte via `resolve_account(…, 'TVA_COLLECTEE', {vat_rate_id})`.

**Recette.** Clôture de caisse `ZZ` avec deux taux : deux lignes de TVA sur les bons comptes.

**Effort.** 0,25 j.

---

#### `LOC1-25` — Déclaration de TVA par gabarit

**Constat.** `accounting.ts:1580-1587` calcule la TVA à déclarer par préfixe : `startsWith('4457')` collectée, `startsWith('4456')` déductible, `startsWith('70')` chiffre d'affaires, `startsWith('60')` achats. `VatReturnsPage.tsx` (route `/reports/vat`, `App.tsx:457`) et `Phase6Pages.tsx:1096` (`vat_rate: 20`) supposent un taux unique français.

**Spécification.** RPC `compute_vat_return(p_tenant_id, p_template_code, p_period_start, p_period_end)` :
1. lit `pack_statement_lines` du gabarit `kind = 'vat_return'` du pack effectif ;
2. pour chaque case : somme des bases et taxes des `journal_lines` rattachées à un `tax_rate_id` dont `declaration_box_base`/`declaration_box_tax` = la case, ou évaluation de `formula` (`"B08 - B12"`) ;
3. retourne `{box_code, label, amount}` arrondis par `round_money`, avec un contrôle : TVA collectée − déductible = solde des comptes des rôles TVA sur la période (écart → alerte bloquante).

La page affiche le formulaire du pays, dans l'ordre et avec les libellés du gabarit. L'export (PDF, EDI) est une capacité.

**Recette.** Période FR de démonstration : montants de la page actuelle = montants du gabarit `FR-CA3` ; période `ZZ` : cases du gabarit `ZZ-VAT`.

**Effort.** 1 j.

---

#### `LOC1-26` — Replis TVA en saisie

**Constat.** `JournalSaisiePage.tsx:534` et `SaisieParPiecePage.tsx:177` : `taxRate.account_deductible || '445660'` et `taxRate.account_collectee || '445710'`.

**Spécification.** Appeler `resolveAccount('TVA_DEDUCTIBLE_BIENS_SERVICES' | 'TVA_COLLECTEE', {vat_rate_id})`. En cas d'erreur `ROLE_NON_MAPPE`, afficher : « Aucun compte de TVA n'est défini pour le taux {nom}. Renseignez-le dans Paramétrage > Taxes. » et bloquer la ligne.

**Effort.** 0,25 j.

---

#### `LOC1-27` — Régimes et périodicités de TVA

**Constat.** `company_settings.vat_regime DEFAULT 'CA3'`, `vat_method DEFAULT 'debit'`, `vat_periodicity DEFAULT 'monthly'` ; `CA3`/`CA12` sont des formulaires français.

**Spécification.** Table `pack_vat_regimes (pack_code, regime_code, label, periodicities text[], template_code, turnover_min, turnover_max, allows_vat_on_receipts, source_id)`. `company_settings.vat_regime` référence `regime_code` du pack effectif (contrôle par trigger), sans défaut ; l'onboarding propose les régimes du pack.

**Effort.** 0,5 j.

---

#### `LOC1-28` — Impôt sur les bénéfices

**Constat.** `corporate_tax_grids` (`36_tax_grids_payroll_corporate.sql`) est indexé par `country_code`, `CorporateTaxCalcPage.tsx` lit le pays mais le calcul et les libellés (IS, acomptes) suivent la logique française.

**Spécification.** `corporate_tax_grids.pack_code` ; lignes typées `bracket` (tranches), `flat_rate`, `minimum_turnover_rate` (minimum assis sur le chiffre d'affaires), `minimum_fixed`, `installment` (acomptes : dates et pourcentages). Le calcul retient `max(impôt calculé, minimum)` si le pack le prévoit. Écriture : `IMPOT_BENEFICES_CHARGE` / `ETAT_IMPOT_BENEFICES`.

**Recette.** Jeux d'essai par pack (Phase 2 et 3).

**Effort.** 0,5 j.

---

#### `LOC1-29` — Autres impôts et taxes

**Spécification.** `pack_other_taxes` (LOC1-02) couvre : retenues à la source sur prestations (appliquées sur facture fournisseur si le fournisseur est non résident ou selon la catégorie), droits de timbre (sur factures ou quittances, montant fixe ou proportionnel), patente/contribution des licences (calcul annuel, rappel d'échéance), taxes parafiscales. Chaque taxe déclare son `account_role` et, si déclarée, sa case de gabarit.

**Effort.** 0,5 j.

---

### LOT 1-F — Paie paramétrée

#### `LOC1-30` — Fin des replis français

**Constat.**
- `src/lib/payroll.ts:4` : « Falls back to hardcoded French 2024-2025 rates if no grid lines provided » ; `FALLBACK_RATES` (l. 51-58) : sécurité sociale 6,98/29,74, santé 0,40/7,28, retraite 11,40/10,93, chômage 0,24/4,28, CSG-CRDS 9,20, majoration 1,25.
- `src/lib/payroll.ts:97` : plafond d'exonération transport « 75€/mois France 2024 ».
- `153_fix_carry_forward_and_payroll.sql:603` : `v_ss_employee := round(v_total_gross * 22.0 / 100, 2); -- approximation légale`.

**Spécification.** Supprimer `FALLBACK_RATES`, la branche d'approximation et le plafond transport en dur. Sans grille active (`status = 'active'`, `pack_code` = pack effectif, période couverte) : exception `GRILLE_PAIE_ABSENTE` côté SQL, erreur typée côté TS, message « Aucune grille de paie en vigueur au {date} pour {pays}. ». Le plafond transport devient un paramètre légal `TRANSPORT_EXEMPTION_CAP` du pack FR.

**Recette.** Test : société `ZZ` sans grille → bulletin refusé avec le message ; aucune valeur française ne peut apparaître.

**Effort.** 0,5 j.

---

#### `LOC1-31` — Pays de la paie

**Constat.** `calculate_payslip` (`153:354`) déclare `v_country_code text := 'FR'` (l. 444). `get_legal_parameter` (`114_payroll_engine.sql:120`) a `p_country_code text DEFAULT 'FR'` (l. 122). `update_tax_grid_timestamp` (`36:250`) contient deux `'FR'`.

**Spécification.** `calculate_payslip` lit `tenant_pack_code(v_tenant_id)` ; `get_legal_parameter(p_tenant_id, p_code, p_date)` résout sur la lignée du pack, **sans** défaut ; paramètre introuvable → exception `PARAMETRE_LEGAL_ABSENT: {code} au {date}`. Revoir `update_tax_grid_timestamp` : supprimer toute référence pays.

**Effort.** 0,25 j.

---

#### `LOC1-32` — Durées légales et majorations

**Constat.**
- `src/lib/payroll.ts:92` : `grossSalary / 151.67` (35 h × 52 / 12).
- `src/lib/queries/leavesAbsences.ts:566` : `salary / 151.67`.
- `calculate_overtime_pay` (`152:327`, l. 358) : `/ 151.67`.
- `src/pages/PayrollCalcPage.tsx:25` : `useState(35)` heures par semaine.
- `FALLBACK_RATES.overtimeRate: 1.25`.

**Spécification.** Paramètres légaux obligatoires de tout pack pays : `LEGAL_WEEKLY_HOURS`, `MONTHLY_HOURS_DIVISOR` (formule ou valeur), `OVERTIME_TIERS` (JSON : `[{"from_hour": 0, "to_hour": 8, "rate": 1.25}, …]`), `NIGHT_WORK_RATE`, `REST_DAY_RATE`, `PUBLIC_HOLIDAY_RATE`, `PAID_LEAVE_DAYS_PER_MONTH`, `PAID_LEAVE_BASIS` (`working_days` / `calendar_days`). Le contrat de travail peut porter un horaire contractuel inférieur ; le taux horaire = salaire de base / (horaire contractuel × `weeks_per_month` du pack).

**Recette.** Pack `ZZ` à 40 h : taux horaire = base / 173,33 ; heures sup majorées selon `OVERTIME_TIERS` de `ZZ`.

**Effort.** 0,5 j.

---

#### `LOC1-33` — Catégories de cotisations génériques

**Constat.** `payroll_tax_grid_lines.category` (`36:71-75`) : `CHECK (category IN ('social_security','health','retirement','unemployment','csg_crds','its','income_tax',…))` ; `114:73-75` ajoute `is_csg_crds` et `csg_type IN ('deductible','non_deductible','crds')` ; `PayrollResult` (`payroll.ts:20-47`) expose des champs nommés `csgCrds`, `unemploymentEmployee`. Ce modèle ne représente ni la CNSS djiboutienne par branche, ni l'AMO marocaine, ni l'IRG algérien.

**Spécification.**

```sql
CREATE TABLE IF NOT EXISTS pack_social_organisms (
  pack_code text REFERENCES legislation_packs(code),
  organism_code text,                  -- 'CNSS', 'AMU', 'URSSAF', 'CNAS'…
  name text, name_ar text,
  declaration_template_code text,      -- gabarit de bordereau
  declaration_periodicity text,        -- 'monthly','quarterly'
  due_day int,                         -- jour limite de dépôt
  account_role text REFERENCES account_role_catalog(role),
  source_id text,
  PRIMARY KEY (pack_code, organism_code)
);
ALTER TABLE payroll_tax_grid_lines
  ADD COLUMN IF NOT EXISTS organism_code text,
  ADD COLUMN IF NOT EXISTS contribution_code text,     -- 'CNSS_PF', 'CNSS_AT', 'AMU'…
  ADD COLUMN IF NOT EXISTS reduces_taxable_base boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS ceiling_parameter text,     -- code du paramètre légal plafond
  ADD COLUMN IF NOT EXISTS floor_parameter text,
  ADD COLUMN IF NOT EXISTS base_rate_percent numeric(9,6) DEFAULT 100; -- assiette partielle (ex. 98,25 %)
-- La contrainte CHECK sur category est remplacée par une FK vers payroll_contribution_categories (table extensible)
```

`csg_type` et `is_csg_crds` sont migrés vers `contribution_code` (`FR_CSG_DED`, `FR_CSG_NON_DED`, `FR_CRDS`) et `reduces_taxable_base`. `PayrollResult` devient :

```ts
interface PayrollResult {
  lines: { code: string; label: string; organism?: string; base: number; rateEmployee?: number; rateEmployer?: number;
           amountEmployee: number; amountEmployer: number; reducesTaxableBase: boolean }[]
  grossTotal: number; taxableBase: number; employeeContributions: number; employerContributions: number
  incomeTax: number; netBeforeTax: number; netPayable: number; employerCost: number
}
```

Les écrans (`PayrollCalcPage.tsx`, `PayrollPreparationPage.tsx`, bulletin PDF) itèrent sur `lines`, sans champ nommé par cotisation.

**Recette.** Bulletin FR de référence : mêmes montants par ligne qu'avant. Bulletin `ZZ` à 2 organismes fictifs : lignes regroupées par organisme.

**Effort.** 1 j.

---

#### `LOC1-34` — Écriture de paie : chemin unique

**Constat.** Trois chemins produisent l'écriture de paie : trigger `create_journal_on_payroll_validate` (`81:295`), `src/lib/queries/payroll.ts:205-209` (inclut `437000`) et `src/lib/queries/misc.ts:38-41` (sans `437000`). Ils ne produisent pas la même écriture.

**Spécification.** Seul le trigger subsiste, réécrit (LOC1-07) : une ligne `SALAIRES_BRUTS` (ou par rubrique si la rubrique a un rôle propre), une ligne `CHARGES_SOCIALES_PATRONALES`, une ligne par `organism_code` au crédit (`ORGANISME_SOCIAL` avec contexte), une ligne `ETAT_IMPOT_SALAIRES`, une ligne `PERSONNEL_AVANCES` si acompte, une ligne `PERSONNEL_REMUNERATIONS_DUES`. Les deux fonctions front sont supprimées ; leurs appelants appellent la validation du lot de paie.

**Recette.** Une validation de lot = une écriture équilibrée ; aucun appel front ne crée de `journal_lines` de paie (recherche `knip` + test).

**Effort.** 0,5 j.

---

#### `LOC1-35` — Rubriques et modèle de bulletin

**Spécification.** `payroll_components` reçoit `pack_code`, `component_code`, `kind` (`earning`, `allowance`, `benefit_in_kind`, `deduction`, `employer_charge`, `info`), `taxable_income bool`, `subject_to_social bool`, `exemption_cap_parameter`, `account_role`, `sort_order`, `printed bool`, `label_ar`. Le modèle de bulletin est un gabarit `pack_statement_templates.kind = 'payslip'` : blocs, ordre, mentions légales obligatoires (identifiants employeur, organisme, période, congés acquis/pris, cumuls).

**Effort.** 1 j.

---

#### `LOC1-36` — Organismes et déclarations sociales

**Constat.** `social_declarations`, `SocialDeclarationsPage.tsx` (6 `toFixed(2)`), `socialDeclarations.ts` et l'edge function `transmit-dsn` sont conçus pour la DSN française.

**Spécification.** Déclaration = gabarit (`kind = 'social_return'`) rattaché à `pack_social_organisms.declaration_template_code` ; génération générique (tableau récapitulatif + export CSV/PDF) ; transmission électronique = capacité (`dsn` pour FR). Échéancier des déclarations calculé depuis `declaration_periodicity` et `due_day`.

**Effort.** 0,5 j.

---

#### `LOC1-37` — Calendrier

**Constat.** Samedi/dimanche en dur : `LeavePlanningPage.tsx:114-115` (`dow === 0 || dow === 6`), `leavesAbsences.ts:380` et `:479` (`getDay()`), `purchaseAdvanced.ts:182` (échéances), `ganttHelpers.ts:157`. `public_holidays.country DEFAULT 'FR'`.

**Spécification.**
- `src/lib/calendar.ts` : `isWeekend(ctx, date)`, `isHoliday(ctx, date)`, `isWorkingDay(ctx, date)`, `addWorkingDays(ctx, date, n)`, `countWorkingDays(ctx, from, to)`, fondés sur `pack.weekend_days` (ISO 1-7) et `pack_holidays` + `public_holidays` de la société (jours propres à l'entreprise).
- Fonctions SQL miroir `is_working_day(p_tenant_id, p_date)` et `count_working_days(…)` pour les calculs de congés et d'échéances.
- `pack_holidays` accepte les fêtes à **date variable** (calendrier lunaire) : une ligne **par année** avec `is_variable = true` ; le validateur (V14) exige la présence de l'année en cours et de la suivante ; un avertissement administrateur signale une date à confirmer après annonce officielle.

**Recette.** Pack `ZZ` avec week-end vendredi-samedi : un congé du jeudi au dimanche compte 2 jours ouvrés (jeudi, dimanche).

**Effort.** 1 j.

---

### LOT 1-G — États financiers et déclarations par gabarit

#### `LOC1-38` — Moteur d'états

**Constat.** `generate_balance_sheet` (`152:89`) et `generate_profit_loss` (`152:153`) classent par `LIKE`, `BalanceSheetPage.tsx` affiche des listes de comptes actif/passif sans rubriques, `SIGPage.tsx:74` lit `'603'`, `LiasseFiscalePage.tsx` filtre classes 6/7, `CashFlowPage.tsx` et `generate_accounting_annex` (`103:622`) suivent le modèle français.

**Spécification.**

RPC `generate_statement(p_tenant_id uuid, p_template_code text, p_fiscal_year_id uuid, p_compare_previous boolean DEFAULT true) RETURNS jsonb` :

1. Charge les lignes du gabarit du pack effectif (`pack_statement_lines`, ordre `sort_order`).
2. Pour une ligne à `account_ranges` (ex. `{'2100-2199','2800-2899:credit'}`) : somme des soldes des comptes dont le code est **dans l'intervalle lexicographique normalisé** (codes complétés à droite à la longueur du plan) ; suffixe `:debit`/`:credit` = ne retenir que les soldes de ce sens (ex. banques créditrices au passif) ; préfixe `-` = soustraire (amortissements).
3. Ligne à `formula` : expression sur `line_code` (`"AA + AB - AC"`), évaluée par un analyseur restreint (opérateurs `+ - * /`, parenthèses, `ABS`, `MAX`, `MIN`), **jamais** par `EXECUTE` de texte.
4. Retourne `{ template, fiscal_year, currency, decimals, lines: [{code, label, label_ar, level, amount_n, amount_n1, box_code}], checks: [...] }`.
5. Contrôles intégrés (`checks`) : total actif = total passif ; résultat du bilan = résultat du compte de résultat ; somme de la balance mouvementée = somme des comptes couverts (LOC1-39).

Front : composant unique `<StatementView template>` utilisé par `BalanceSheetPage`, `ProfitLossPage`, `CashFlowPage`, `SIGPage` (gabarit FR `SIG`, capacité `sig`), `LiasseFiscalePage` (gabarit `tax_return`). Export PDF/Excel via le même JSON.

Les gabarits PCG (bilan, compte de résultat, SIG, liasse 2050-2057 et 2033) sont écrits dans `packs/PCG/statements/` et `packs/FR/statements/` en reproduisant les résultats actuels.

**Recette.** Exercice FR de démonstration : chaque total de l'ancien écran = total de la ligne correspondante du gabarit. Pack `ZZ` : bilan à 3 rubriques équilibré.

**Effort.** 3 j.

---

#### `LOC1-39` — Couverture des gabarits

**Spécification.** Contrôle exécuté par le validateur (V10) sur le plan du référentiel et par `generate_statement` à l'exécution sur le plan de la société :
- chaque compte de bilan (`account_nature` ∉ `expense`, `income`, `*_hao`, `off_balance`, `analytical`) est couvert par **exactement une** ligne feuille du gabarit `balance_sheet`, compte tenu du sens ;
- chaque compte de gestion est couvert par **exactement une** ligne feuille du gabarit `income_statement` ;
- un compte créé par la société hors plan du pack mais mouvementé et non couvert → ligne `checks` bloquante « Le compte 6xxx… n'est rattaché à aucune rubrique ».

**Effort.** 0,5 j.

---

#### `LOC1-40` — Déclarations fiscales par gabarit

**Spécification.** `LiasseFiscalePage` et `EdiTvaPage` deviennent des consommateurs de gabarits (`tax_return`, `vat_return`) avec saisie des cases non calculables (cases « manuelles » marquées `input = true` dans `pack_statement_lines`), historisation de la déclaration déposée (`tax_returns` : pack, version, cases, montant, date de dépôt, pièce jointe). L'EDI est une capacité (`edi_tva` FR).

**Effort.** 1 j.

---

### LOT 1-H — Capacités et identifiants

#### `LOC1-41` — Registre des capacités, routes et menus

**Constat.** Fonctions françaises visibles pour tous : `FECExportPage`, `EdiTvaPage`, `TvsPage`, `SepaTransferPage`, `SepaPaymentsPage`, `EInvoicePage` (Factur-X/Chorus), `Nf525AuditPage`, `CPFPage`, `BdesPage`, `SocialDeclarationsPage` (DSN), `SIGPage`, et 36 fichiers mentionnant SIRET, URSSAF, CSG, CRDS, PMSS, SMIC, DSN, CA3, FEC, Chorus, Factur-X, NAF.

**Spécification.** Catalogue `capability_catalog (capability text PK, module text, description)` ; valeurs initiales :

| Capacité | Écrans / fonctions | FR | ZZ |
|---|---|:---:|:---:|
| `fec_export` | `FECExportPage`, `fecValidator.ts` | ✅ | ❌ |
| `edi_tva` | `EdiTvaPage`, `submit-vat-return` | ✅ | ❌ |
| `tvs` | `TvsPage` | ✅ | ❌ |
| `sepa` | `SepaTransferPage`, `SepaPaymentsPage`, `sepa.ts` | ✅ | ❌ |
| `e_invoicing_fr` | `EInvoicePage`, `facturX.ts`, `submit-e-invoice` | ✅ | ❌ |
| `nf525` | `Nf525AuditPage`, triggers NF525 | ✅ | ❌ |
| `dsn` | `transmit-dsn`, export DSN | ✅ | ❌ |
| `cpf` | `CPFPage` | ✅ | ❌ |
| `bdes` | `BdesPage` | ✅ | ❌ |
| `sig` | `SIGPage` | ✅ | ❌ |
| `siret_lookup` | `verify-siret` | ✅ | ❌ |
| `vies_check` | `validate-vat-vies` | ✅ | ❌ |
| `sage_fr_import` | `SageImportPage`, `sageImport.ts` | ✅ | ✅ (optionnel) |
| `public_budget` | module budgétaire public (Phase 2) | ❌ | ❌ |
| `payroll`, `pos`, `stock`, `manufacturing` | modules génériques | ✅ | ✅ |

`useCapabilities()` (hook) lit les capacités du pack effectif. `App.tsx` enveloppe chaque route concernée dans `<RequireCapability name>` qui affiche « Cette fonction n'est pas disponible pour le pays de votre société. » ; `Sidebar.tsx`, `ModuleHub.tsx`, `CommandPalette` masquent les entrées. Les triggers NF525 testent `tenant_has_capability(tenant, 'nf525')` avant d'écrire.

**Recette.** Société `ZZ` : aucune des 12 capacités françaises n'apparaît dans le menu ; accès direct par URL → message ; aucune ligne `nf525_event_log` créée.

**Effort.** 1 j.

---

#### `LOC1-42` — Edge functions conditionnées

**Spécification.** `supabase/functions/_shared/capabilities.ts` : `requireCapability(tenantId, name)` → HTTP 403 `{ error: 'CAPACITE_INDISPONIBLE', capability }`. Appliqué à `submit-e-invoice`, `submit-vat-return`, `transmit-dsn`, `verify-siret`, `validate-vat-vies`, `request-signature` (si capacité réglementaire). `refresh-exchange-rates` : devise pivot par société (LOC1-22).

**Effort.** 0,5 j.

---

#### `LOC1-43` — Identifiants légaux génériques

**Constat.** `company_settings.siret`, `company_settings.vat_number`, `customers`/`suppliers` avec champs SIRET/TVA ; `02_bootstrap_tenant.sql:95` insère `vat_number, siret`. Les pays cibles utilisent NIF, RCS/RCCM, ICE, IF, RC, NINEA, matricule fiscal, NIS, numéro d'employeur CNSS.

**Spécification.**

```sql
CREATE TABLE IF NOT EXISTS legal_identifiers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  owner_type text NOT NULL CHECK (owner_type IN ('company','customer','supplier','employee','establishment')),
  owner_id uuid,                       -- NULL pour la société
  identifier_type text NOT NULL,       -- référence pack_legal_identifiers.identifier_type
  value text NOT NULL,
  country_code text NOT NULL,          -- pays émetteur (un fournisseur étranger garde ses identifiants)
  valid_from date, valid_to date,
  UNIQUE (tenant_id, owner_type, owner_id, identifier_type, country_code)
);
```

Contrôles : `regex` + `checksum_algo` (`luhn` pour SIRET, `none`, ou algorithme nommé) du pack **du pays émetteur**. `company_settings.siret` et `vat_number` sont migrés en lignes `SIRET` / `TVA_INTRACOM` puis conservés en lecture (vue de compatibilité) le temps de migrer les écrans. Les formulaires société, clients, fournisseurs, salariés affichent dynamiquement les identifiants requis par le pack.

**Recette.** Société `ZZ` : le formulaire demande les identifiants `ZZ` ; un client français garde son SIRET contrôlé par Luhn.

**Effort.** 1 j.

---

#### `LOC1-44` — Mentions et numérotation des documents

**Spécification.** `generate-pdf` et les modèles de documents lisent `pack_document_rules` : liste ordonnée de mentions obligatoires (identifiants, forme juridique, capital, adresse, conditions de paiement, pénalités de retard, mention d'exonération du taux appliqué, mentions en langue(s) requise(s)), avec contrôle **avant validation** du document : mention dont la donnée manque → validation bloquée avec la liste des champs à compléter. Numérotation : motif (`{PREFIX}-{YYYY}-{SEQ:6}`), réinitialisation, continuité sans trou (`gapless`) via séquence transactionnelle.

**Recette.** Pack `ZZ` exigeant `ZZ_TAXID` : une facture sans identifiant client B2B est refusée.

**Effort.** 1 j.

---

#### `LOC1-45` — Libellés réglementaires

**Constat.** Les fichiers `src/i18n/locales/{fr,en,ar}/*.json` contiennent des libellés « TVA », « SIRET », « URSSAF », « CSG », « SMIC » (ex. 5 occurrences dans `ar/accounting.json`).

**Spécification.** Les libellés réglementaires ne viennent plus d'i18n mais du pack (`tax_id_label`, `pack_legal_identifiers.label`, `tax_rates.name`, libellés de gabarits). i18n garde les libellés **fonctionnels** neutres (« Taxe », « Identifiant fiscal »). Hook `useRegulatoryLabel(key)` avec repli neutre.

**Effort.** 0,5 j.

---

### LOT 1-I — Onboarding et référentiels ISO

#### `LOC1-46` — Pays et devises ISO

**Constat.** `countries.ts` : `COUNTRIES` (198 noms français), `COUNTRY_CODE_MAP` (51 entrées, **Djibouti absent**), `COUNTRY_CURRENCY_MAP` (61 entrées, **Djibouti absent**), `getCurrencyForCountry` → `'EUR'` par défaut (l. 321), `CURRENCIES` sans unités mineures, avec doublons (`AUD` ×2, `XCG` libellé « Gourde haïtienne », `VEF` obsolète, `SLL` remplacé par `SLE`).

**Spécification.** Remplacer par `src/lib/iso/countries.json` (ISO 3166-1 : alpha-2, alpha-3, nom FR/EN/AR, devise officielle) et `src/lib/iso/currencies.json` (ISO 4217 : code, unités mineures, nom FR/EN/AR, symbole local), générés par script depuis les données CLDR/ISO et versionnés. `getCurrencyForCountry` retourne `undefined` si inconnu. Table SQL `iso_currencies` synchronisée (alimente `currencies.decimals`, LOC1-19).

**Recette.** `DJ` → `DJF`, 0 ; `TN` → `TND`, 3 ; `XX` → `undefined`.

**Effort.** 0,5 j.

---

#### `LOC1-47` — Onboarding pays → pack → secteur

**Constat.** `OnboardingPage.tsx:48` initialise `country: 'France'` ; `:82-95` devine la devise et le pack par `country_code` ; un pays sans pack laisse `legislation_pack_code: ''` et la société est créée quand même (repli PCG).

**Spécification.**
1. Étape 1 — Pays (liste ISO complète, recherche). Pays sans pack publié : affiché « Bientôt disponible », non sélectionnable, avec proposition de contact.
2. Étape 2 — Pack : liste des packs `published` de niveau `country`/`sector` pour ce pays ; présélection seulement s'il n'y en a qu'un.
3. Étape 3 — Secteur (si plusieurs couches secteur) avec explication de chaque statut.
4. Étape 4 — Récapitulatif non modifiable après création : référentiel, devise et décimales, exercice, langue(s), régime de TVA, modules disponibles.
5. `OnboardingModal.tsx` et `MultiCompanyPage.tsx` réutilisent le même assistant.

**Recette.** Parcours E2E Playwright : création `ZZ` ; tentative sans pack → bouton désactivé.

**Effort.** 1 j.

---

#### `LOC1-48` — Doublon `CI`

**Constat.** `legislation_packs_migration.sql:140` : pack `SYSCOHADA` avec `country_code 'CI'`, `currency 'XOF'` ; `04_seed_legislation_packs.sql:119` : pack `CI` avec `country_code 'CI'`.

**Spécification.** `SYSCOHADA` passe en `level = 'referential'`, `country_code NULL`, `currency NULL` ; `SN`, `CI`, `CM` passent `parent_code = 'SYSCOHADA'`. Les sociétés rattachées à `SYSCOHADA` directement sont listées et rattachées au pays de leur `company_settings.country` après confirmation.

**Effort.** 0,1 j.

---

#### `LOC1-49` — Import bancaire

**Constat.** `bankParsers.ts:47, 112, 126, 237, 259, 275, 343, 407` : devise `'EUR'` supposée quand le relevé ne la précise pas.

**Spécification.** Devise lue dans le fichier ; à défaut, devise du **compte bancaire** de destination (`bank_accounts.currency_code`) ; à défaut, erreur « Devise du relevé introuvable ». CFONB (format français) reste supposé EUR mais uniquement sous capacité `sepa`.

**Effort.** 0,25 j.

---

#### `LOC1-50` — Import Sage

**Constat.** `SageImportPage.tsx:113-115` classe clients/fournisseurs/salariés par préfixes `411`/`401`/`421`.

**Spécification.** Comparer au compte mappé des rôles `CLIENTS`, `FOURNISSEURS`, `PERSONNEL_REMUNERATIONS_DUES` du pack (préfixe = compte collectif sans zéros de fin).

**Effort.** 0,25 j.

---

### LOT 1-J — Outillage des packs

#### `LOC1-51` — Format de fichiers

**Spécification.** Arborescence et schémas en **annexe C**. Les fichiers sont la **source de vérité** ; la base n'est qu'une projection. Revue de code obligatoire sur `packs/**` (CODEOWNERS : responsable conformité du pays).

**Effort.** 1 j (schémas JSON Schema + documentation).

---

#### `LOC1-52` — Importeur

**Spécification.** `node scripts/pack-import.mjs --pack DJ [--dry-run] [--database-url …]` :
1. valide le schéma de chaque fichier (JSON Schema) ;
2. résout les références (`source_id`, rôles, comptes, cases) ;
3. calcule `content_sha256` du pack ;
4. en une transaction : `UPSERT` idempotent de toutes les tables du pack, suppression des lignes absentes des fichiers **seulement** si le pack est `draft` ;
5. refuse de modifier un pack `published` dont le `version` n'a pas changé (règle d'immuabilité) ;
6. affiche le diff (lignes ajoutées/modifiées/supprimées par table).

Intégré au job CI `db-integration` (import de tous les packs sur base vierge) et à `run-sql-migrations.mjs` (import après migrations).

**Effort.** 1 j.

---

#### `LOC1-53` — Validateur

**Spécification.** `node scripts/pack-validate.mjs [--pack DJ] [--strict]` exécute les règles de l'**annexe D** sur les fichiers **et** sur la projection en base (pour les règles qui nécessitent SQL : couverture, jeux d'essai). Sortie : liste `V##  ERREUR|AVERTISSEMENT  fichier:ligne  message`. Code retour non nul si au moins une erreur. En `--strict` (publication), les avertissements sont bloquants.

**Effort.** 1,5 j.

---

#### `LOC1-54` — Cycle de vie

**Spécification.**

| Statut | Qui | Condition d'entrée | Effet |
|---|---|---|---|
| `draft` | développeur / analyste | création | modifiable, non attribuable |
| `validated` | CI | validateur `--strict` vert + jeux d'essai verts | modifiable uniquement en revenant à `draft` |
| `published` | responsable conformité | signature `validated_by` + expert du pays | immuable ; attribuable ; toute modification = nouvelle version |
| `archived` | responsable conformité | version remplacée | reste lisible pour les documents existants ; non attribuable |

Versionnage sémantique : **majeur** = changement de plan ou de rôles (nécessite transposition), **mineur** = nouveaux taux/barèmes datés, **correctif** = libellés, mentions.

**Effort.** 0,5 j.

---

#### `LOC1-55` — Garde-fou anti-code-en-dur

**Spécification.** `node scripts/check-country-neutral.mjs` : règles de l'**annexe E**, exécuté en CI (job `lint-typecheck`) sur `app/src` (hors `__tests__`, hors allowlist) et sur les **définitions effectives** des fonctions SQL (lecture de `pg_proc.prosrc` sur la base du job `db-integration`, pas des fichiers de migration, pour ignorer les versions écrasées). Allowlist `scripts/country-neutral.allow.json` : chaque entrée cite fichier, motif, capacité justificative et date de revue.

**Effort.** 1 j.

---

### LOT 1-K — Non-régression et preuve de neutralité

#### `LOC1-56` — Packs `PCG` et `FR`

**Spécification.** Reconstituer à l'identique : plan (LOC1-13), 67 rôles, 8 journaux, taux de TVA (`legislation_packs_migration.sql:127-134`) et mapping (`109:32-41`), paramètres légaux (`114:35-57`), grilles (`36`, `46`), capacités françaises, gabarits (LOC1-38), jours fériés, identifiants SIRET/TVA intracom/NAF, mentions de facture actuelles. Chaque valeur reçoit une source (`SRC-FR-nn`). Les packs sont publiés en `1.0.0` et toutes les sociétés existantes y sont rattachées (`tenants.legislation_pack_code = 'FR'`, déjà fait par `legislation_packs_migration.sql:156-162`).

**Effort.** 1 j.

---

#### `LOC1-57` — Pack fictif `ZZ`

**Spécification.** `packs/ZZREF` (référentiel), `packs/ZZ` (pays), `packs/ZZ-PUB` (secteur), conçus pour **casser toute hypothèse française** :

| Paramètre | Valeur `ZZ` | Hypothèse cassée |
|---|---|---|
| Devise | `XTS` (code ISO de test) avec `currency_decimals = 3` | EUR, 2 décimales |
| Locale | `ar-EG` avec `number_system = 'latn'` | virgule française, chiffres latins par défaut |
| Plan | comptes à 4 chiffres, clients `9100`, fournisseurs `9200`, ventes `8100`, achats `7100`, banque `5500`, résultat `1900`/`1990` | numéros PCG, classes 6/7 |
| Week-end | vendredi-samedi (`{5,6}`) | samedi-dimanche |
| Exercice | `07-01` | `01-01` |
| TVA | un taux `ZZ-STD` 12,5 % arrondi par document | taux multiples, arrondi par ligne |
| Paie | 40 h, 1 organisme `ZZSS`, barème à 3 tranches | 35 h, CSG, URSSAF |
| Capacités | aucune capacité française | modules FR visibles |

Test E2E `e2e/country-neutral.spec.ts` : onboarding `ZZ` → client → facture → paiement → achat → bulletin → déclaration de TVA → clôture → bilan équilibré, avec vérifications d'écran (aucun `€`, aucun `411`, 3 décimales, week-end respecté) et SQL (comptes `ZZ` uniquement dans `journal_lines`).

**Effort.** 0,5 j.

---

#### `LOC1-58` — Non-régression France

**Spécification.**
1. Avant tout changement : export de référence sur base de démonstration (`seed_demo_data.sql`) — balance, grand livre, bilan, compte de résultat, déclaration TVA, 3 bulletins, clôture — dans `app/sql/fixtures/fr-baseline/*.csv`.
2. Après chaque lot : régénération et `diff` ; écart toléré **0**.
3. `102_trigger_tests.sql` et `105_rls_tests.sql` verts ; 1 280 tests Vitest verts ; E2E existants verts.

**Effort.** 1 j.

---

### Recette de la Phase 1

| # | Critère | Preuve |
|---|---|---|
| R1-1 | Aucune valeur pays dans le code | `check-country-neutral.mjs` = 0 hors allowlist |
| R1-2 | France identique | `diff` baseline = vide |
| R1-3 | Neutralité prouvée | E2E `ZZ` vert |
| R1-4 | Échecs explicites | tests : rôle absent, grille absente, pack non publié, pack verrouillé |
| R1-5 | Packs valides | `pack-validate --strict` vert sur `PCG`, `FR`, `ZZREF`, `ZZ`, `ZZ-PUB` |
| R1-6 | Snapshot | documents portent `pack_code` + `pack_version` |

---
## 6. PHASE 2 — Préparation et livraison Djibouti

**Objectif de phase.** Publier les packs `PCN-DJ` (référentiel), `DJ` (pays, secteur privé) et `DJ-EP` (entreprises publiques), validés par un expert-comptable djiboutien, et les faire tourner en pilote sur une clôture mensuelle réelle.

**Pré-requis.** Phase 1 recettée (R1-1 à R1-6). Sans elle, Djibouti hériterait des comptes, arrondis et replis français.

**Règle absolue de cette phase.** Aucune valeur réglementaire djiboutienne (taux, barème, plafond, numéro de compte, case de formulaire, date limite) n'est saisie sans une source `SRC-DJ-nn` référencée. Les tableaux ci-dessous sont des **gabarits de collecte** : la colonne « Valeur » est remplie à partir des textes officiels, jamais de mémoire ni d'une source secondaire non vérifiée.

---

### LOT 2-A — Gouvernance et collecte

#### `LOC2-01` — Référent et double validation

**Spécification.**

| Rôle | Responsabilité | Livrable |
|---|---|---|
| **Expert-comptable référent DJ** (inscrit à l'ordre professionnel de Djibouti) | valide le plan, les rôles, les états, la fiscalité ; fournit les cas réels | signature de la recette LOC2-38, champ `validated_by` |
| **Référent paie DJ** (gestionnaire de paie ou expert social, peut être le même) | valide barèmes, cotisations, rubriques, bulletins | signature des jeux d'essai paie |
| **Référent secteur public** (si Phase DJ-EP / DJ-ADM) | valide les écarts de statut | signature `DJ-EP-01` |
| **Analyste Onusuite** | saisit les fichiers du pack, référence les sources | `packs/PCN-DJ`, `packs/DJ`, `packs/DJ-EP` |
| **Relecteur Onusuite** (différent de l'analyste) | vérifie chaque valeur contre la source citée (règle des 4 yeux) | approbation de la PR, case « valeur vérifiée contre la source » par fichier |

Toute valeur fait l'objet de deux contrôles indépendants : saisie par l'analyste, vérification par le relecteur **et** validation métier par le référent. Un désaccord est tracé dans `packs/DJ/REVIEW.md` avec la décision finale.

**Recette.** Référents nommés et contrat (ou convention) signé avant LOC2-05.

---

#### `LOC2-02` — Registre des sources

**Spécification.** `packs/DJ/sources.yaml` (et `packs/PCN-DJ/sources.yaml`, `packs/DJ-EP/sources.yaml`) :

```yaml
- id: SRC-DJ-01
  title: "<intitulé exact du texte>"
  issuer: "<autorité émettrice>"
  reference: "<n° de loi / décret / arrêté / circulaire>"
  published_on: "AAAA-MM-JJ"
  published_in: "<Journal officiel n°…>"
  effective_from: "AAAA-MM-JJ"
  file: "sources/SRC-DJ-01.pdf"      # copie conservée hors dépôt public si droits restreints
  file_sha256: "<empreinte>"
  obtained_from: "<service / personne, date>"
  verified_by: "<nom>"
```

Règle V05 : un `source_id` référencé sans entrée → erreur ; une entrée sans `file_sha256` → avertissement (bloquant en `--strict`).

**Effort.** 0,5 j.

---

#### `LOC2-03` — Documents à collecter

| ID | Document | Autorité / origine à solliciter | Alimente | Exigences |
|---|---|---|---|---|
| SRC-DJ-01 | Texte instituant le plan comptable applicable aux entreprises (nomenclature complète, règles de fonctionnement des comptes) | Ministère chargé de l'Économie et des Finances ; ordre professionnel des experts-comptables | Plan, natures de comptes, rôles | LOC2-05, 06 |
| SRC-DJ-02 | Modèles officiels des états financiers (bilan, compte de résultat, tableau des flux, annexes) et seuils de présentation simplifiée éventuels | Idem ; Direction des Impôts et des Domaines | Gabarits d'états | LOC2-09 |
| SRC-DJ-03 | Code général des impôts, version consolidée à jour | Direction des Impôts et des Domaines ; Journal officiel | TVA, IS, patente, retenues, timbre | LOC2-15 à 19 |
| SRC-DJ-04 | Loi de finances de l'exercice en cours **et** de l'exercice précédent | Journal officiel | Taux et barèmes datés | LOC2-15, 17, 18, 22 |
| SRC-DJ-05 | Formulaire de déclaration de TVA et sa notice (cases, périodicité, date limite, régimes) | Direction des Impôts et des Domaines | Gabarit `vat_return` | LOC2-16 |
| SRC-DJ-06 | Formulaire de déclaration de résultat / liasse fiscale et notice | Direction des Impôts et des Domaines | Gabarit `tax_return` | LOC2-19 |
| SRC-DJ-07 | Formulaire et notice de déclaration de l'impôt retenu sur salaires | Direction des Impôts et des Domaines | Gabarit de déclaration | LOC2-28 |
| SRC-DJ-08 | Code du travail en vigueur et textes d'application (durée du travail, heures supplémentaires, congés, préavis, indemnités) | Ministère chargé du Travail ; Journal officiel | Paramètres légaux, rubriques | LOC2-21, 24, 25 |
| SRC-DJ-09 | Texte fixant le salaire minimum en vigueur | Idem | `MINIMUM_WAGE` | LOC2-21 |
| SRC-DJ-10 | Taux, assiettes et plafonds de cotisation par branche ; bordereau de déclaration et calendrier | Caisse Nationale de Sécurité Sociale | Organismes, cotisations, déclaration | LOC2-23, 28 |
| SRC-DJ-11 | Textes relatifs à l'assurance maladie (cotisations, assiettes, parts employeur/salarié) | Organisme gestionnaire | Cotisations | LOC2-23 |
| SRC-DJ-12 | Liste officielle des jours fériés et modalités d'annonce des fêtes à date variable ; jours de repos hebdomadaire | Journal officiel ; communiqué gouvernemental annuel | Calendrier | LOC2-12 |
| SRC-DJ-13 | Règles relatives aux mentions obligatoires sur factures, format du NIF, immatriculation au registre du commerce | CGI ; Office djiboutien de la propriété industrielle et commerciale (registre) | Identifiants, mentions | LOC2-13, 14 |
| SRC-DJ-14 | Textes sur les entreprises publiques et établissements publics : statuts, régime comptable, régime budgétaire, tutelle, contrôle de la Cour des comptes | Ministère des Finances ; Cour des comptes | Couches `DJ-EP`, `DJ-ADM` | LOC2-29, 30 |
| SRC-DJ-15 | Conventions collectives de branche applicables aux pilotes | Ministère du Travail ; organisations professionnelles | Rubriques conventionnelles (couche société) | LOC2-24 |
| SRC-DJ-16 | Trois dossiers réels anonymisés : cycle ventes/achats/TVA d'un mois, 5 bulletins de paie variés, une clôture annuelle avec états déposés | Expert-comptable référent | Jeux d'essai | LOC2-34 à 37 |
| SRC-DJ-17 | Texte ou publication officielle fixant la parité du franc de Djibouti | Banque centrale de Djibouti | Parité fixe | LOC2-04, 11 |
| SRC-DJ-18 | Constitution (langues officielles) | Journal officiel | Langues | LOC2-04, 32 |
| SRC-DJ-19 | Liste des États parties au Traité OHADA | Secrétariat permanent de l'OHADA | Choix du référentiel | LOC2-04 |
| SRC-DJ-20 | Droit des sociétés commerciales (réserve légale, affectation du résultat, approbation des comptes) | Journal officiel | Clôture, affectation | LOC2-08 |

**Recette.** Chaque ligne a un fichier, une empreinte et un vérificateur ; les manques sont listés avec leur impact (exigences bloquées).

---

### LOT 2-B — Référentiel comptable `PCN-DJ`

#### `LOC2-04` — Fiche d'identité pays (faits établis)

Seuls ces éléments sont intégrables avant réception des textes, car ils relèvent de normes internationales ou de faits publics stables. Ils restent néanmoins sourcés.

| Paramètre | Valeur | Source |
|---|---|---|
| Code pays | `DJ` (ISO 3166-1 alpha-2), `DJI` (alpha-3) | ISO 3166 |
| Devise | Franc de Djibouti, `DJF` | ISO 4217 |
| Unités mineures de la devise | **0** | ISO 4217 |
| Parité | 1 USD = 177,721 DJF (régime de caisse d'émission) | Banque centrale de Djibouti — à joindre comme `SRC-DJ-17` |
| Langues officielles | français, arabe | Constitution — `SRC-DJ-18` |
| Appartenance à l'OHADA | **non** | liste des États parties OHADA — `SRC-DJ-19` |
| Locales CLDR | `fr-DJ`, `ar-DJ` | Unicode CLDR |

Conséquence : le pack `DJ` **n'hérite pas** de `SYSCOHADA` ; son parent est `PCN-DJ`.

---

#### `LOC2-05` — Plan comptable `PCN-DJ`

**Spécification.** `packs/PCN-DJ/chart.csv`, une ligne par compte, **intégralité** de la nomenclature du texte `SRC-DJ-01` :

| Colonne | Contenu | Contrôle |
|---|---|---|
| `code` | numéro tel que dans le texte | unique ; longueur cohérente par niveau |
| `name` | libellé français exact du texte | non vide |
| `name_ar` | libellé arabe (texte officiel si existant, sinon traduction validée LOC2-32) | non vide avant publication |
| `parent_code` | compte de niveau supérieur | existe |
| `account_class` | classe du texte | — |
| `account_nature` | nature (LOC1-11) déduite des règles de fonctionnement du texte | valeur du catalogue |
| `type` | compatibilité (`asset`…) | cohérent avec `account_nature` |
| `is_third_party` | compte de tiers | — |
| `allow_direct_entry` | `false` pour les comptes de regroupement | — |
| `source_id` | `SRC-DJ-01` + article/page | obligatoire |

Normalisation : longueur de saisie des comptes société (paramètre `account_code_length` du référentiel, ex. 6) ; les comptes du texte sont complétés à droite par des zéros **à l'affichage et à la création** mais conservés tels quels dans le template.

**Recette.** Nombre de comptes du CSV = nombre de comptes du texte (comptage contradictoire par le relecteur) ; V07 (hiérarchie), V08 (natures) verts.

**Effort.** 2 j.

---

#### `LOC2-06` — Rôles de comptes `PCN-DJ`

**Spécification.** `packs/PCN-DJ/roles.yaml` : les 67 rôles de l'annexe B. Pour chacun : compte du plan, justification (article du texte décrivant l'usage du compte), `source_id`. Rôle sans équivalent dans le texte : décision écrite du référent (compte de rattachement choisi) consignée dans `REVIEW.md`.

**Recette.** V09 : 100 % des rôles requis par les modules actifs sont mappés vers un compte existant et saisissable.

**Effort.** 1 j.

---

#### `LOC2-07` — Journaux et exercice

**Spécification.** `packs/PCN-DJ/journals.yaml` : 8 rôles de journaux avec codes et libellés FR/AR recommandés par le référent. `packs/DJ/manifest.yaml` : `fiscal_year_start` issu du CGI (`SRC-DJ-03`) ; exercices décalés autorisés ou non selon le texte (`allow_custom_fiscal_year`).

**Effort.** 0,25 j.

---

#### `LOC2-08` — Clôture et affectation du résultat

**Spécification.** Paramètres du référentiel : comptes de résultat (rôles), traitement du report à nouveau, réserve légale (taux, plafond, base) selon le droit des sociétés applicable (`SRC-DJ-20` : texte du droit des sociétés commerciales), écritures d'à-nouveaux (comptes de bilan uniquement, contrôle LOC1-39).

**Recette.** Jeu d'essai DJ-03.

**Effort.** 0,5 j.

---

#### `LOC2-09` — Gabarits d'états financiers

**Spécification.** `packs/PCN-DJ/statements/` : `balance_sheet.yaml`, `income_statement.yaml`, `cash_flow.yaml`, `notes.yaml` (et variantes simplifiées si `SRC-DJ-02` en prévoit). Chaque ligne : `line_code` = référence du modèle officiel, libellés FR/AR, `account_ranges` ou `formula`, `sort_order`, `level`. Mise en page PDF reproduisant l'ordre et les intitulés du modèle officiel.

**Recette.** V10 (couverture) vert ; états du jeu d'essai DJ-03 identiques aux états déposés par l'expert, **ligne par ligne, à 0 DJF**.

**Effort.** 2 j.

---

### LOT 2-C — Couche pays `DJ`

#### `LOC2-10` — Formats

| Paramètre | Valeur | Source / décision |
|---|---|---|
| `currency` | `DJF` | ISO 4217 |
| `currency_decimals` | `0` | ISO 4217 |
| `price_decimals` | à décider avec le référent (usage des prix unitaires fractionnaires, ex. carburant, change) | `REVIEW.md` |
| `quantity_decimals` | `3` par défaut | décision produit |
| `rounding_mode` | selon CGI (règle d'arrondi des bases et des impôts) ; à défaut décision du référent | `SRC-DJ-03` |
| `rounding_level` | ligne ou document, selon pratique validée pour la TVA | `SRC-DJ-05` |
| `locale` | `fr-DJ` | CLDR |
| `number_system` | `latn` | décision produit (documents comptables) |
| `ui_languages` | `{fr, ar}` (arabe selon décision LOC2-32) | — |
| `document_languages` | `{fr}` ou `{fr, ar}` selon `SRC-DJ-13` | — |
| `date_format` | `DD/MM/YYYY` | usage fr-DJ |
| `time_zone` | `Africa/Djibouti` | IANA |

**Recette.** Tests LOC1-17 rejoués avec le contexte DJ.

---

#### `LOC2-11` — Parité et devises usuelles

**Spécification.** `pack_fixed_parities` : `USD/DJF = 177.721`, `effective_from` = date de la source `SRC-DJ-17`. Devises usuelles pré-activées à la création (capacité `common_currencies`) : `USD`, `EUR`, `ETB`, `AED`, `SAR`, `CNY` — liste à confirmer avec les pilotes. Écarts de change : rôles `GAINS_CHANGE`/`PERTES_CHANGE`.

**Recette.** Facture en USD : contre-valeur DJF = montant × 177,721 arrondi à l'unité.

---

#### `LOC2-12` — Calendrier

| Élément | Valeur | Source |
|---|---|---|
| `weekend_days` | à renseigner (jours de repos hebdomadaire légaux) | `SRC-DJ-08`, `SRC-DJ-12` |
| `week_start` | à renseigner | idem |
| Jours fériés à date fixe | à renseigner (date, libellé FR/AR) | `SRC-DJ-12` |
| Jours fériés à date variable | à renseigner **par année** (année N et N+1), statut « prévisionnel » jusqu'à l'annonce officielle | `SRC-DJ-12` |

**Spécification complémentaire.** Tâche planifiée annuelle : 60 jours avant la fin de l'année, alerte au responsable du pack si les fériés variables de N+1 ne sont pas saisis ; à l'annonce officielle d'une date différente, mise à jour `patch` du pack et recalcul signalé des congés concernés.

**Effort.** 0,5 j.

---

#### `LOC2-13` — Identifiants légaux

| `identifier_type` | Libellé | Titulaires | Format / contrôle | Imprimé sur facture | Source |
|---|---|---|---|---|---|
| `DJ_NIF` | Numéro d'identification fiscale | société, clients B2B, fournisseurs | à renseigner | à renseigner | `SRC-DJ-13` |
| `DJ_RCS` | Immatriculation au registre du commerce | société | à renseigner | à renseigner | `SRC-DJ-13` |
| `DJ_CNSS_EMPLOYEUR` | Numéro d'employeur | société | à renseigner | bulletin | `SRC-DJ-10` |
| `DJ_CNSS_ASSURE` | Numéro d'assuré | salarié | à renseigner | bulletin | `SRC-DJ-10` |

**Effort.** 0,25 j.

---

#### `LOC2-14` — Mentions obligatoires

**Spécification.** `packs/DJ/documents.yaml` : pour `invoice`, `credit_note`, `quote`, `delivery_note`, `receipt`, `payslip` — liste ordonnée des mentions exigées par `SRC-DJ-13` / `SRC-DJ-03` (identité et identifiants du vendeur et de l'acheteur, date, numéro, désignation, quantités, prix unitaire hors taxe, taux et montant de chaque taxe, total, mention d'exonération, conditions de paiement, langue), numérotation (motif, continuité, réinitialisation). Chaque mention pointe vers son article source.

**Recette.** Facture PDF du pilote contrôlée par le référent ; facture incomplète refusée à la validation.

**Effort.** 0,5 j.

---

#### `LOC2-15` — TVA

Gabarit de collecte `packs/DJ/taxes.yaml` :

| `tax_code` | Nom | Catégorie | Taux | Champ d'application | Compte collecté (rôle) | Compte déductible (rôle) | Case base | Case taxe | Mention d'exonération | `effective_from` | `effective_to` | Source |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `DJ-STD` | à renseigner | `standard` | à renseigner | à renseigner | `TVA_COLLECTEE` | `TVA_DEDUCTIBLE_BIENS_SERVICES` | à renseigner | à renseigner | — | à renseigner | — | `SRC-DJ-03/04` |
| `DJ-…` | taux réduits / spécifiques éventuels | — | — | — | — | — | — | — | — | — | — | — |
| `DJ-EXO` | Exonéré | `exempt` | 0 | liste des opérations exonérées | — | — | à renseigner | — | texte de la mention | — | — | `SRC-DJ-03` |
| `DJ-EXPORT` | Exportations | `zero` | 0 | à renseigner | — | — | à renseigner | — | à renseigner | — | — | `SRC-DJ-03` |

Historique : saisir **aussi** les taux antérieurs encore applicables à des documents des exercices non prescrits, avec leurs dates, pour permettre la reprise d'historique.

Paramètres associés : `vat_on_receipts_allowed`, règles de prorata de déduction, régularisations, seuil d'assujettissement, régimes (`pack_vat_regimes`, LOC1-27).

**Recette.** Jeu d'essai DJ-01.

**Effort.** 1 j.

---

#### `LOC2-16` — Déclaration de TVA

**Spécification.** `packs/DJ/statements/vat_return.yaml` reproduisant **toutes** les cases du formulaire `SRC-DJ-05` : code de case officiel, libellé, calcul (`declaration_box_*` des taux, formule, ou saisie manuelle), contrôles de cohérence du formulaire. Échéance : `due_day` et périodicités par régime. Rappel d'échéance dans le centre de notifications.

**Recette.** Déclaration du mois du jeu d'essai DJ-01 = déclaration déposée, case par case.

**Effort.** 1 j.

---

#### `LOC2-17` — Impôt sur les bénéfices

| Paramètre | Valeur | Source |
|---|---|---|
| Désignation officielle de l'impôt | à renseigner | `SRC-DJ-03` |
| Taux ou barème | à renseigner | `SRC-DJ-04` |
| Minimum d'imposition (assiette, taux, montant plancher) | à renseigner | `SRC-DJ-03/04` |
| Acomptes (dates, pourcentages, base) | à renseigner | `SRC-DJ-03` |
| Réintégrations/déductions courantes à proposer dans l'assistant | à renseigner avec le référent | `SRC-DJ-03` |
| Rôles comptables | `IMPOT_BENEFICES_CHARGE`, `ETAT_IMPOT_BENEFICES` | `PCN-DJ` |

**Effort.** 0,5 j.

---

#### `LOC2-18` — Patente, retenues, timbre

**Spécification.** Une entrée `pack_other_taxes` par impôt identifié dans `SRC-DJ-03/04` : patente (éléments d'assiette, droit fixe/proportionnel, échéance), retenues à la source (opérations visées, taux, déclarant, délai de reversement), droits de timbre (actes et documents visés, montant). Chaque taxe : rôle comptable, déclaration éventuelle, source.

**Effort.** 0,5 j.

---

#### `LOC2-19` — Déclaration de résultat

**Spécification.** `packs/DJ/statements/tax_return.yaml` : tous les tableaux de `SRC-DJ-06`, cases calculées depuis les gabarits d'états (`PCN-DJ`) et cases manuelles. Export PDF conforme à la présentation officielle.

**Recette.** Jeu d'essai DJ-03.

**Effort.** 1 j.

---

#### `LOC2-20` — Capacités

`packs/DJ/capabilities.yaml` : `payroll`, `pos`, `stock`, `manufacturing`, `common_currencies`, `sage_fr_import` (optionnel) activés ; **désactivées** : `fec_export`, `edi_tva`, `tvs`, `sepa`, `e_invoicing_fr`, `nf525`, `dsn`, `cpf`, `bdes`, `sig`, `siret_lookup`, `vies_check`. Toute capacité djiboutienne future (télédéclaration, facture électronique nationale) est ajoutée au catalogue puis activée ici.

**Effort.** 0,1 j.

---

### LOT 2-D — Paie Djibouti

#### `LOC2-21` — Paramètres légaux

Gabarit `packs/DJ/payroll/parameters.yaml` (tous `effective_from` + `source_id`) :

| Code | Signification | Valeur | Source |
|---|---|---|---|
| `LEGAL_WEEKLY_HOURS` | durée légale hebdomadaire | à renseigner | `SRC-DJ-08` |
| `MONTHLY_HOURS_DIVISOR` | diviseur horaire mensuel | à renseigner | `SRC-DJ-08` |
| `OVERTIME_TIERS` | tranches et majorations d'heures supplémentaires | à renseigner | `SRC-DJ-08` |
| `NIGHT_WORK_RATE` | majoration de nuit | à renseigner | `SRC-DJ-08` |
| `REST_DAY_RATE`, `PUBLIC_HOLIDAY_RATE` | majorations repos / férié | à renseigner | `SRC-DJ-08` |
| `MINIMUM_WAGE` | salaire minimum (horaire ou mensuel, préciser) | à renseigner | `SRC-DJ-09` |
| `PAID_LEAVE_DAYS_PER_MONTH`, `PAID_LEAVE_BASIS` | acquisition des congés | à renseigner | `SRC-DJ-08` |
| `PROBATION_*`, `NOTICE_*` | durées d'essai et de préavis par catégorie | à renseigner | `SRC-DJ-08`, `SRC-DJ-15` |
| `SEVERANCE_FORMULA` | indemnité de licenciement | à renseigner | `SRC-DJ-08` |
| Plafonds de cotisation | par branche | à renseigner | `SRC-DJ-10`, `SRC-DJ-11` |

**Effort.** 0,5 j.

---

#### `LOC2-22` — Barème de l'impôt sur les salaires

Gabarit `packs/DJ/payroll/income_tax.yaml` :

| Tranche | Borne basse | Borne haute | Taux | Somme fixe / abattement | Périodicité du barème (mensuel/annuel) | Source |
|---|---|---|---|---|---|---|
| 1 | à renseigner | à renseigner | à renseigner | à renseigner | à renseigner | `SRC-DJ-04` |
| … | | | | | | |

Paramètres associés : assiette imposable (brut − cotisations déductibles selon `reduces_taxable_base`), abattements forfaitaires, prise en compte des charges de famille si prévue, règle d'arrondi de l'assiette et de l'impôt, traitement des avantages en nature et des primes exceptionnelles (annualisation ou non), régularisation annuelle.

**Recette.** Jeu d'essai DJ-02 : impôt de chaque bulletin = bulletin réel.

**Effort.** 0,5 j.

---

#### `LOC2-23` — Cotisations sociales

Gabarit `packs/DJ/payroll/contributions.yaml` :

| `organism_code` | `contribution_code` | Branche | Assiette | Plafond | Taux salarié | Taux employeur | Réduit l'assiette imposable | Source |
|---|---|---|---|---|---|---|---|---|
| `CNSS` | à renseigner par branche | à renseigner | à renseigner | à renseigner | à renseigner | à renseigner | à renseigner | `SRC-DJ-10` |
| organisme maladie | à renseigner | assurance maladie | à renseigner | à renseigner | à renseigner | à renseigner | à renseigner | `SRC-DJ-11` |

`pack_social_organisms` : nom FR/AR, rôle comptable, bordereau, périodicité, date limite.

**Effort.** 0,5 j.

---

#### `LOC2-24` — Rubriques de bulletin

**Spécification.** Catalogue initial `packs/DJ/payroll/components.yaml` construit avec le référent paie : salaire de base, sursalaire, heures supplémentaires par tranche, primes usuelles (ancienneté si légale ou conventionnelle, rendement, logement, transport, panier, responsabilité), avantages en nature (logement, véhicule, nourriture) avec leur règle d'évaluation, indemnités non imposables et leurs plafonds, acomptes, prêts, retenues diverses. Pour chaque rubrique : `kind`, `taxable_income`, `subject_to_social`, plafond d'exonération, rôle comptable, ordre d'impression, libellé FR/AR, source.

**Effort.** 1 j.

---

#### `LOC2-25` — Congés, heures supplémentaires, fin de contrat

**Spécification.** Paramétrage des règles de `LOC2-21` dans les modules existants : acquisition et prise des congés (jours ouvrés/ouvrables selon le calendrier DJ), indemnité de congés, heures supplémentaires issues des feuilles de temps, solde de tout compte (préavis, indemnité compensatrice de congés, indemnité de licenciement, certificat de travail) avec les mentions exigées.

**Effort.** 1 j.

---

#### `LOC2-26` — Modèle de bulletin

**Spécification.** Gabarit `payslip` DJ : en-tête employeur (identifiants DJ), salarié (identifiants, catégorie, ancienneté), période, rubriques groupées (gains, cotisations par organisme, impôt, net), cumuls annuels, congés, mode de paiement, mentions légales ; langue(s) selon LOC2-32.

**Effort.** 0,5 j.

---

#### `LOC2-27` — Écriture de paie

**Spécification.** Mapping `PCN-DJ` des rôles de paie (`SALAIRES_BRUTS`, `CHARGES_SOCIALES_PATRONALES`, `PERSONNEL_REMUNERATIONS_DUES`, `PERSONNEL_AVANCES`, `ORGANISME_SOCIAL` × organismes DJ, `ETAT_IMPOT_SALAIRES`). Rubriques à comptabiliser sur un compte propre (avantages en nature, indemnités) : `account_role` de la rubrique.

**Recette.** Écriture du lot DJ-02 = écriture passée par l'expert.

**Effort.** 0,25 j.

---

#### `LOC2-28` — Déclarations sur salaires

**Spécification.** Gabarits `social_return` (bordereau CNSS, assurance maladie) et `withholding_return` (impôt sur salaires) : périodicité, cases/colonnes du formulaire officiel, récapitulatif par salarié si exigé, export PDF et CSV, échéancier et rappels.

**Recette.** Déclarations du mois DJ-02 = déclarations déposées.

**Effort.** 1 j.

---

### LOT 2-E — Secteur public djiboutien

> **Décision préalable du porteur de projet** : périmètre `DJ-EP` seul, ou `DJ-EP` + `DJ-ADM`. Tant qu'elle n'est pas prise, seul LOC2-29 est engagé.

#### `LOC2-29` — Couche `DJ-EP` : entreprises publiques à caractère commercial

**Spécification.** Pack `DJ-EP` (`level = 'sector'`, `sector = 'public_enterprise'`, parent `DJ`). Contenu attendu selon `SRC-DJ-14` :
- comptes et rôles complémentaires : dotation de l'État, subventions d'équipement (et leur reprise au rythme des amortissements), subventions d'exploitation, comptes de liaison avec la tutelle ;
- écritures automatiques de reprise des subventions d'investissement lors de la dotation aux amortissements (extension de `generate_depreciation_entry` par rôle `REPRISE_SUBVENTIONS_INVESTISSEMENT`, uniquement si le rôle est mappé) ;
- lignes supplémentaires des gabarits d'états (surcharge des lignes du référentiel) ;
- rapports à la tutelle (gabarits `kind = 'notes'`) ;
- identifiants propres (texte de création, tutelle) ;
- capacités : `public_reporting`.

**Recette.** Jeu d'essai DJ-EP-01.

**Effort.** 1,5 j.

---

#### `LOC2-30` — Couche `DJ-ADM` : établissements administratifs (option)

**Spécification fonctionnelle (module Budget public, capacité `public_budget`).**
1. **Budget** : nomenclature budgétaire (titres, chapitres, articles, paragraphes) issue de `SRC-DJ-14` ; budget primitif, décisions modificatives, virements de crédits avec contrôle d'autorisation.
2. **Chaîne de la dépense** : engagement (réservation de crédit, contrôle de disponibilité bloquant), liquidation (service fait, montant exact), ordonnancement (mandat), paiement (par le comptable) ; chaque étape horodatée, signée, avec pièces justificatives.
3. **Chaîne de la recette** : constatation, liquidation, émission du titre, recouvrement.
4. **Séparation ordonnateur / comptable** : rôles utilisateurs incompatibles (contrôle `hasPermission` + RLS), aucun utilisateur ne peut cumuler.
5. **Double comptabilité** : écritures budgétaires et générales synchronisées ; table de passage nomenclature budgétaire → comptes.
6. **Documents de fin d'exercice** : compte administratif (ordonnateur), compte de gestion (comptable), rapprochement des deux.
7. **Contrôle** : exports pour la Cour des comptes selon le format attendu.

**Effort.** 8 à 10 semaines ; cahier des charges détaillé spécifique à rédiger après réception de `SRC-DJ-14`.

---

#### `LOC2-31` — Paie secteur public (option)

**Spécification.** Si les agents relèvent d'un statut à grille indiciaire : table `pack_salary_scales (pack_code, corps, grade, echelon, index, effective_from, source_id)`, paramètre `INDEX_POINT_VALUE`, avancement d'échelon (durées), indemnités statutaires ; traitement = indice × valeur du point.

**Effort.** 1 j.

---

### LOT 2-F — Langue arabe

#### `LOC2-32` — Libellés arabes

**Spécification.** `name_ar` / `label_ar` de tous les éléments visibles du pack : plan, rôles de journaux, taxes, lignes d'états, rubriques de paie, mentions. Traduction par un traducteur spécialisé en terminologie comptable, relue par le référent ; termes officiels du texte source prioritaires. Interface arabe (RTL) déjà disponible dans `src/i18n/locales/ar` : vérifier les écrans du parcours pilote en RTL.

**Effort.** 1 j (hors délai de traduction).

---

#### `LOC2-33` — Documents bilingues

**Spécification.** Modèles PDF (facture, avoir, bulletin, états) en mise en page bilingue FR/AR (colonnes ou blocs), police arabe embarquée, chiffres latins, sens de lecture correct par bloc. Activé par `document_languages = {fr, ar}`.

**Effort.** 1 j.

---

### LOT 2-G — Jeux d'essai, recette, pilote

#### `LOC2-34` à `LOC2-37` — Jeux d'essai

| Réf | Contenu | Entrées | Résultats attendus comparés | Tolérance |
|---|---|---|---|---|
| **LOC2-34** `DJ-01` | un mois d'activité d'une PME commerciale | ≥ 20 factures clients (dont exonérées et en USD), ≥ 15 factures fournisseurs, avoirs, règlements, un relevé bancaire | grand livre, balance, déclaration de TVA, contre-valeurs DJF | **0 DJF** |
| **LOC2-35** `DJ-02` | paie d'un mois | 5 salariés : cadre au-dessus du plafond, employé au salaire minimum, heures supplémentaires multi-tranches, entrée en cours de mois, sortie avec solde de tout compte | chaque ligne de chaque bulletin, écriture de paie, bordereaux | **0 DJF** |
| **LOC2-36** `DJ-03` | clôture annuelle | balance avant inventaire, écritures d'inventaire (amortissements, provisions, stocks) | à-nouveaux, états financiers, impôt sur les bénéfices, déclaration de résultat | **0 DJF** |
| **LOC2-37** `DJ-EP-01` | entreprise publique | subventions d'investissement et d'exploitation, dotation, amortissements | reprise des subventions, états avec rubriques spécifiques | **0 DJF** |

**Spécification.** Chaque jeu d'essai est stocké dans `packs/DJ/fixtures/<id>/` (`input/*.json`, `expected/*.csv`), exécuté par `pack-validate` (règle V18) sur base vierge et en CI à chaque modification du pack ou du moteur.

**Effort.** 2 j.

---

#### `LOC2-38` — Recette fonctionnelle

**Procédure.**
1. Environnement de recette dédié, packs `PCN-DJ 1.0.0-rc.1`, `DJ 1.0.0-rc.1`, `DJ-EP 1.0.0-rc.1` importés.
2. Le référent crée une société et déroule le parcours complet sans assistance, avec la grille de recette ci-dessous.
3. Toute anomalie → fiche `RCT-DJ-nn` (écran, attendu, obtenu, source), correction, nouvelle `rc`.
4. Signature du procès-verbal quand toutes les fiches bloquantes sont closes.

| Domaine | Points contrôlés |
|---|---|
| Création | pays, pack, secteur ; plan conforme ; journaux ; devise sans décimales ; exercice |
| Documents | mentions, numérotation, identifiants, arrondis, contre-valeur USD, PDF FR/AR |
| TVA | ventilation, comptes, déclaration case par case |
| Trésorerie | règlements, rapprochement, écarts de change |
| Stocks | valorisation, écritures |
| Paie | bulletins, cumuls, congés, écriture, déclarations |
| Clôture | inventaire, résultat, affectation, à-nouveaux, états, déclaration de résultat |
| Secteur public | subventions, dotation, états spécifiques |
| Absence de France | aucun menu, libellé, compte, symbole ou règle française visible |

**Effort.** 2 j de support.

---

#### `LOC2-39` — Pilote

**Spécification.** 2 à 3 entreprises volontaires (dont une avec salariés et, si possible, une entreprise publique), accompagnées par le référent, en double run avec leur outil actuel pendant **une clôture mensuelle complète** (TVA et paie déposées). Critère : écarts nuls entre les deux outils ou expliqués par une erreur de l'outil actuel, attestée par le référent. Suivi hebdomadaire, journal des incidents.

**Effort.** 4 semaines calendaires.

---

#### `LOC2-40` — Publication

**Spécification.** Passage `published` de `PCN-DJ`, `DJ`, `DJ-EP` en `1.0.0`, `validated_by` renseigné, PV de recette et bilan du pilote archivés dans `packs/DJ/RELEASE-1.0.0.md`. Pays « Djibouti » sélectionnable dans l'onboarding.

---

#### `LOC2-41` — Documentation utilisateur

**Spécification.** Guide « Démarrer à Djibouti » (création, paramétrage TVA, paie, déclarations, clôture), FAQ, glossaire FR/AR, dans la base de connaissances existante (`KnowledgeBasePage`).

**Effort.** 1 j.

---

### Recette de la Phase 2

| # | Critère | Preuve |
|---|---|---|
| R2-1 | Toutes les valeurs sourcées | V05 vert en `--strict` |
| R2-2 | Jeux d'essai | DJ-01, DJ-02, DJ-03, DJ-EP-01 à 0 DJF |
| R2-3 | Validation métier | PV signé par le référent |
| R2-4 | Pilote | clôture mensuelle en double run sans écart inexpliqué |
| R2-5 | Neutralité maintenue | R1-1 à R1-3 toujours verts |

---
## 7. PHASE 3 — Tous les autres pays

**Objectif de phase.** Industrialiser l'ajout d'un pays (procédure, kit, veille), puis livrer le Maghreb et la zone OHADA **sans modification du code** — seuls des fichiers `packs/**` et, si un besoin fonctionnel nouveau apparaît, une entrée au catalogue des rôles ou des capacités.

**Règle de sortie de code.** Si un pays exige un comportement que le moteur ne sait pas exprimer (ex. nouveau type de calcul d'impôt), ce n'est **pas** traité dans le pack : une exigence `LOC1-xx` complémentaire est ouverte, développée de façon générique, testée sur `ZZ`, puis utilisée par le pays.

---

### LOT 3-A — Industrialisation

#### `LOC3-01` — Procédure standard d'ajout d'un pays

| Étape | Contenu | Livrable | Porte de passage |
|---|---|---|---|
| **E1 Cadrage** | référentiel existant ou nouveau, secteurs visés, langues, capacités spécifiques (télédéclaration, facture électronique nationale) | fiche de cadrage | décision go/no-go |
| **E2 Référents** | expert-comptable et référent paie du pays | conventions signées | LOC2-01 appliqué au pays |
| **E3 Collecte** | kit LOC3-02 | `sources.yaml` complet | 100 % des documents obligatoires ou manques acceptés par écrit |
| **E4 Référentiel** | plan, rôles, journaux, états (si nouveau référentiel) | `packs/<REF>/` | V07-V10 verts |
| **E5 Couche pays** | formats, calendrier, identifiants, mentions, fiscalité, déclarations, capacités | `packs/<CC>/` | V01-V17 verts |
| **E6 Paie** | paramètres, barème, cotisations, rubriques, bulletin, écriture, déclarations | `packs/<CC>/payroll/` | V11-V13 verts |
| **E7 Jeux d'essai** | 3 dossiers réels (cycle, paie, clôture) | `fixtures/` | V18 vert à 0 unité |
| **E8 Écarts moteur** | besoins non exprimables | exigences `LOC1-xx` | développées et testées sur `ZZ` |
| **E9 Recette** | parcours complet par le référent | PV | signature |
| **E10 Pilote** | 1 à 3 entreprises, une clôture mensuelle | bilan | écarts nuls |
| **E11 Publication** | `1.0.0` | `RELEASE-1.0.0.md` | `validated_by` |

**Effort.** 0,5 j (rédaction de `packs/README.md` et des modèles de fiches).

---

#### `LOC3-02` — Kit de collecte générique

**Spécification.** `packs/_template/` : copie vide de l'arborescence de l'annexe C, `sources.yaml` pré-rempli avec les 20 catégories de documents de `LOC2-03` rendues génériques (plan comptable, modèles d'états, CGI, lois de finances N et N-1, formulaires TVA/résultat/retenues, code du travail, salaire minimum, sécurité sociale, assurance maladie, jours fériés, facturation, secteur public, conventions collectives, dossiers réels, parité, langues, organisation régionale, droit des sociétés), et `CHECKLIST.md` à cocher.

**Effort.** 0,5 j.

---

#### `LOC3-03` — Revalidation des packs existants

**Constat.** `04_seed_legislation_packs.sql` a créé 14 packs (`UK`, `US`, `MA`, `DZ`, `TN`, `SN`, `CI`, `CM`, `DE`, `ES`, `IT`, `SA`, `AE`, `EG`) avec des taux de TVA **sans source** et `effective_from` approximatifs (`'2000-01-01'`, `'2010-01-01'`…). `46_seed_tax_grids_and_components.sql` a seedé des grilles `CI` (10 lignes), `CM` (10), `SN` (4), `FR` (4) sans source. Aucun de ces packs n'a de plan comptable, de rôles ni de gabarits.

**Spécification.**
1. Tous ces packs passent en `status = 'draft'` (non attribuables à de nouvelles sociétés).
2. Les sociétés existantes rattachées à l'un d'eux sont listées ; pour chacune, message à l'administrateur : « Le paramétrage de votre pays est en cours de certification. » ; aucune donnée n'est modifiée.
3. Chaque pack est repris selon LOC3-01 lorsque son pays est planifié ; les packs non planifiés (`UK`, `US`, `DE`, `ES`, `IT`, `SA`, `AE`, `EG`) restent en `draft` jusqu'à décision.

**Effort.** 2 j (inventaire, communication, bascule).

---

### LOT 3-B — Maghreb

Éléments de cadrage connus à confirmer par les sources de chaque pays. Les valeurs réglementaires (taux, barèmes, plafonds, cases) sont collectées selon LOC3-02 ; **aucune n'est reprise des seeds existants sans revalidation**.

#### `LOC3-04` / `LOC3-05` — Maroc (`CGNC`, `MA`)

| Élément | Cadrage | Source à joindre |
|---|---|---|
| Référentiel | Code général de normalisation comptable (loi n° 9-88 et textes d'application) | texte de loi, CGNC |
| Plan | codification à 4 chiffres minimum ; classes 1 à 5 de bilan, 6 et 7 de gestion, 8 résultats, 0 comptes spéciaux | CGNC |
| États de synthèse | bilan, compte de produits et charges, état des soldes de gestion, tableau de financement, état des informations complémentaires ; modèle normal et modèle simplifié | CGNC |
| Devise | `MAD`, 2 décimales | ISO 4217 |
| Locale | `fr-MA`, `ar-MA`, chiffres latins | CLDR |
| Identifiants | ICE, IF, RC, numéro de patente/taxe professionnelle, CNSS | CGI, textes CNSS |
| Fiscalité | TVA multi-taux, IS (barème), cotisation minimale, retenues à la source, taxe professionnelle | CGI, loi de finances |
| Paie | IR sur salaires (barème), CNSS (prestations sociales, allocations familiales), AMO, taxe de formation professionnelle | CGI, CNSS |
| Capacités candidates | télédéclaration, facture électronique si obligation en vigueur | DGI |

**Effort.** `CGNC` 3 j, `MA` 4 j (+ jeux d'essai, recette, pilote).

---

#### `LOC3-06` / `LOC3-07` — Tunisie (`SCE-TN`, `TN`)

| Élément | Cadrage | Source à joindre |
|---|---|---|
| Référentiel | système comptable des entreprises (loi n° 96-112 et normes comptables tunisiennes) | texte de loi, NCT |
| Devise | `TND`, **3 décimales (millimes)** — test de vérité de LOC1-17 à LOC1-21 | ISO 4217 |
| Locale | `fr-TN`, `ar-TN`, chiffres latins | CLDR |
| Identifiants | matricule fiscal (avec clé de contrôle), registre national des entreprises, CNSS | textes fiscaux |
| Fiscalité | TVA multi-taux, droit de timbre, retenues à la source, IS et minimum d'impôt, avances et acomptes | code de la TVA, code de l'IRPP et de l'IS |
| Paie | IRPP (barème), CNSS, contributions spécifiques éventuelles | textes fiscaux et sociaux |
| Capacités candidates | facture électronique nationale si applicable | administration fiscale |

**Recette spécifique.** Toute la chaîne (saisie, stockage, TVA, arrondis, PDF) conserve 3 décimales ; test de régression dédié.

**Effort.** `SCE-TN` 3 j, `TN` 4 j.

---

#### `LOC3-08` / `LOC3-09` — Algérie (`SCF`, `DZ`)

| Élément | Cadrage | Source à joindre |
|---|---|---|
| Référentiel | système comptable financier (loi n° 07-11 et textes d'application) | texte de loi, nomenclature |
| Devise | `DZD`, 2 décimales | ISO 4217 |
| Locale | `ar-DZ`, `fr-DZ` ; **chiffres latins imposés** (`number_system = latn`) | CLDR |
| Identifiants | NIF, NIS, RC, article d'imposition, numéro d'employeur | textes fiscaux |
| Fiscalité | TVA multi-taux, IBS, IFU pour les régimes concernés, droits de timbre, retenues | code des impôts directs, code des taxes sur le chiffre d'affaires, loi de finances |
| Paie | IRG sur salaires (barème et abattements), CNAS | textes fiscaux et sociaux |
| États | bilan, compte de résultat par nature et par fonction, tableau des flux de trésorerie, tableau de variation des capitaux propres, annexe | SCF |

**Effort.** `SCF` 3 j, `DZ` 4 j.

---

### LOT 3-C — Zone OHADA

#### `LOC3-10` — Référentiel `SYSCOHADA` révisé

| Élément | Cadrage | Source à joindre |
|---|---|---|
| Texte | Acte uniforme relatif au droit comptable et à l'information financière (révisé en 2017) et système comptable OHADA | Journal officiel OHADA |
| Plan | classes 1 à 9, dont classe 8 « autres charges et autres produits » (HAO) ; codification du plan officiel | SYSCOHADA |
| États (système normal) | bilan, compte de résultat avec soldes intermédiaires, tableau des flux de trésorerie, notes annexes | SYSCOHADA |
| Rôles | mapping des 67 rôles | SYSCOHADA |

**Spécification.** Pack `SYSCOHADA` de niveau `referential` (LOC1-48), sans devise ni fiscalité. Les natures `expense_hao` / `income_hao` sont obligatoires pour la classe 8 et les gabarits les isolent.

**Effort.** 4 j.

---

#### `LOC3-11` — Système minimal de trésorerie

**Spécification.** Couche `SYSCOHADA-SMT` (référentiel enfant ou option du référentiel) : comptabilité de trésorerie (recettes/dépenses), état de fin d'exercice simplifié, seuils d'éligibilité (chiffre d'affaires) portés par la couche pays. Capacité `smt` ; l'onboarding propose SMT si l'entreprise déclare un chiffre d'affaires sous le seuil du pays.

**Effort.** 2 j.

---

#### `LOC3-12` à `LOC3-14` — Couches pays OHADA

| Groupe | Pays (ISO) | Devise | Particularité de la couche |
|---|---|---|---|
| **UEMOA** | Bénin `BJ`, Burkina Faso `BF`, Côte d'Ivoire `CI`, Guinée-Bissau `GW`, Mali `ML`, Niger `NE`, Sénégal `SN`, Togo `TG` | `XOF`, 0 décimale | directives fiscales communautaires sur la TVA : fourchettes communes, taux fixés par chaque État ; paie et identifiants nationaux |
| **CEMAC** | Cameroun `CM`, Centrafrique `CF`, Congo `CG`, Gabon `GA`, Guinée équatoriale `GQ`, Tchad `TD` | `XAF`, 0 décimale | directives CEMAC ; Cameroun bilingue (anglais pour les régions anglophones, LOC3-21) ; Guinée équatoriale : espagnol |
| **Hors zones monétaires** | Guinée `GN`, Comores `KM`, RD Congo `CD` | `GNF` (0), `KMF` (0), `CDF` (2) | parités et devises propres ; RDC : usage répandu de l'USD |

**Spécification.** Une couche par pays, parent `SYSCOHADA`, contenant uniquement : formats, calendrier, identifiants, mentions, fiscalité et déclarations, paie, capacités. Les directives communautaires communes sont factorisées dans un pack **intermédiaire** optionnel (`UEMOA`, `CEMAC`) de niveau `country`-groupe si le moteur de lignée est étendu à 4 niveaux ; à défaut, dupliquées avec la même `source_id` communautaire.

**Effort.** 3 à 5 j par pays + recette et pilote.

---

#### `LOC3-15` — Secteur public par pays

**Spécification.** Même démarche que LOC2-29/30 pour chaque pays demandeur ; chiffrage après cadrage E1.

---

### LOT 3-D — Maintenance réglementaire

#### `LOC3-16` — Veille

**Spécification.** Pour chaque pack publié : `packs/<CC>/WATCH.md` (sources à surveiller, calendrier de la loi de finances, dates habituelles de revalorisation du salaire minimum et des plafonds, annonces des fériés variables) ; tâche planifiée mensuelle qui ouvre un ticket de revue par pays ; revue obligatoire au plus tard 30 jours avant le 1er janvier (ou le début d'exercice fiscal du pays).

**Effort.** 0,5 j.

---

#### `LOC3-17` — Nouvelle version de pack

**Procédure.**
1. Branche `pack/<CC>-<version>` ; modification des fichiers avec nouvelles lignes datées (jamais de réécriture d'une ligne publiée, principe P4).
2. Mise à jour des jeux d'essai concernés + ajout d'un jeu d'essai de **transition** (période à cheval sur la date d'effet).
3. `pack-validate --strict` vert, relecture 4 yeux, validation du référent.
4. Publication : le code du pack ne change pas, seule sa `version` augmente. Le contenu de la version précédente est historisé dans `pack_versions (pack_code, version, content_sha256, published_at, snapshot jsonb)` ; les lignes datées (taux, barèmes) des deux versions coexistent en base.
5. Montée de version des sociétés : automatique pour `minor`/`patch` ; pour `major`, assistant de transposition (LOC3-24) à l'ouverture d'un nouvel exercice.

**Effort.** 0,5 j.

---

#### `LOC3-18` — Notification des sociétés

**Spécification.** À la publication, notification in-app et e-mail (système de notifications existant) aux administrateurs des sociétés du pack : résumé lisible des changements (« Le taux X passe de a % à b % au JJ/MM/AAAA »), généré depuis le diff de l'importeur, avec lien vers la source.

**Effort.** 1 j.

---

#### `LOC3-19` — Rejeu des jeux d'essai

**Spécification.** Job CI `packs-fixtures` : à toute modification de `packs/**`, de `app/sql/**` ou du moteur de paie/états, rejoue **tous** les jeux d'essai de **tous** les packs publiés ; échec = fusion bloquée.

**Effort.** 0,5 j.

---

#### `LOC3-20` — Tableau de bord de couverture

**Spécification.** Page d'administration plateforme : par pack — statut, version, date de dernière revue, pourcentage de valeurs sourcées, jeux d'essai (vert/rouge), capacités, nombre de sociétés, prochaines échéances réglementaires connues.

**Effort.** 1 j.

---

#### `LOC3-21` — Langues supplémentaires

**Spécification.** Arabe complet pour MA, TN, DZ (interface existante + libellés de packs) ; anglais pour les régions anglophones du Cameroun ; espagnol pour la Guinée équatoriale ; portugais pour la Guinée-Bissau. Chaque langue : fichiers `src/i18n/locales/<lng>`, libellés de packs `name_<lng>` (généralisation de `name_ar` en table `pack_translations (pack_code, entity, key, lang, text)`), modèles PDF.

**Effort.** 1 j par langue d'interface + traduction.

---

#### `LOC3-22` — Facturation électronique nationale

**Spécification.** Capacité par pays (`e_invoicing_<cc>`), adaptateur d'edge function implémentant l'interface commune `submitInvoice / getStatus / cancel`, format et protocole selon la plateforme nationale, conservation des preuves. Chiffrage pays par pays après publication des spécifications officielles.

---

#### `LOC3-23` — Groupes multi-pays (hors périmètre v1)

**Cadrage.** Consolidation de sociétés de packs différents : table de correspondance des plans vers un référentiel de consolidation (IFRS ou référentiel du groupe), conversion des devises (cours de clôture / moyen), éliminations intragroupe. Traité dans un cahier des charges séparé.

---

#### `LOC3-24` — Transposition entre référentiels

**Spécification.** Assistant, à l'ouverture d'un exercice uniquement : choix du pack cible, table de correspondance compte à compte pré-remplie par les rôles (même rôle → correspondance proposée), validation manuelle des comptes restants, génération d'une balance d'ouverture dans le nouveau plan avec contrôle d'égalité des totaux, conservation de l'ancien exercice en lecture dans l'ancien pack. Journal de transposition archivé.

**Effort.** 3 j.

---

### Recette de la Phase 3

| # | Critère | Preuve |
|---|---|---|
| R3-1 | Un pays livré sans code | diff de la livraison limité à `packs/**` (hors exigences `LOC1-xx` génériques ouvertes) |
| R3-2 | Jeux d'essai de tous les packs | job `packs-fixtures` vert |
| R3-3 | Maintenance | revue annuelle faite pour chaque pack publié, tableau de bord à jour |
| R3-4 | Neutralité maintenue | R1-1 à R1-3 verts |

---

## 8. Critères de recette globaux

Un pack est **conforme** lorsque, simultanément :

1. **Sourcé** — 100 % des valeurs réglementaires portent une source vérifiée (V05).
2. **Complet** — rôles requis mappés (V09), gabarits couvrants (V10), paramètres légaux obligatoires présents (V11), calendrier des années N et N+1 (V14).
3. **Cohérent** — dates d'effet sans trou ni chevauchement (V06), comptes existants et saisissables (V09), formules de gabarits valides (V10).
4. **Exact** — jeux d'essai réels à 0 unité d'écart (V18).
5. **Validé** — signature du référent du pays et relecture 4 yeux.
6. **Éprouvé** — pilote en double run sans écart inexpliqué.
7. **Isolé** — aucun élément d'un autre pays visible (capacités, libellés, formats), vérifié par le parcours E2E du pays.

L'application est **neutre** lorsque :

1. `check-country-neutral.mjs` = 0 hors allowlist ;
2. le pack `ZZ` passe son E2E complet ;
3. la France est identique à sa baseline.

---

## 9. Plan d'exécution

### 9.1 Ordonnancement

```
PHASE 1 (≈ 48 j)
 S1  LOC1-58 baseline FR ─┬─ LOC1-01/02/03/04/05/48 modèle + résolution
                          │
 S2-3 LOC1-06/07/08/09/10/11 rôles (SQL + front) ── LOC1-55 garde-fou (mode rapport)
 S4  LOC1-12/13/14/15/16 création société ── LOC1-46/47 onboarding
 S5-6 LOC1-17/18/19/20/21/22 formats & arrondis
 S7-8 LOC1-23→29 fiscalité ── LOC1-30→37 paie & calendrier
 S9  LOC1-38/39/40 états ── LOC1-41→45 capacités & identifiants ── LOC1-49/50
 S10 LOC1-51/52/53/54 outillage ── LOC1-56 packs FR ── LOC1-57 pack ZZ
     LOC1-55 garde-fou en mode bloquant ── Recette R1

PHASE 2 (démarre en parallèle pour la collecte)
 dès S1   LOC2-01/02/03 référents & collecte (délai externe)
 après R1 LOC2-04→09 référentiel ── LOC2-10→20 couche pays ── LOC2-21→28 paie
          LOC2-29 DJ-EP ── LOC2-32/33 arabe ── LOC2-34→37 jeux d'essai
          LOC2-38 recette ── LOC2-39 pilote (4 sem.) ── LOC2-40/41 publication

PHASE 3
 après R2 LOC3-01/02/03 industrialisation ── LOC3-16→20 maintenance
          pays dans l'ordre décidé : MA, TN, DZ, puis SYSCOHADA + pays OHADA
```

### 9.2 Dépendances critiques

| Exigence | Dépend de | Raison |
|---|---|---|
| LOC1-06 à LOC1-11 | LOC1-05 | les réécritures appellent `resolve_account` |
| LOC1-12 | LOC1-03, LOC1-13 | le bootstrap lit le pack effectif |
| LOC1-18 | LOC1-17 | le codemod cible le nouveau service |
| LOC1-19 | LOC1-46 | décimales ISO des devises étrangères |
| LOC1-25, LOC1-40 | LOC1-38 | gabarits de déclaration |
| LOC1-08 (`close_fiscal_year`) | LOC1-38 | sélection des comptes de gestion par gabarit |
| LOC1-55 (bloquant) | LOC1-06 à LOC1-50 | sinon la CI est rouge |
| LOC1-57 | tout le lot 1 | preuve finale |
| Phase 2 (hors collecte) | R1 | neutralité acquise |
| LOC2-09, LOC2-16, LOC2-19 | LOC2-03 (SRC-DJ-02, 05, 06) | formulaires officiels |
| LOC2-30 | décision du porteur de projet | périmètre budgétaire |

### 9.3 Charge et calendrier indicatifs

| Phase | Charge | Calendrier (1 développeur + Claude) |
|---|---:|---|
| Phase 1 | ≈ 48 j | 10 semaines |
| Phase 2 — hors pilote | ≈ 26 j | 6 semaines après réception des textes |
| Phase 2 — pilote | — | 4 semaines calendaires |
| Phase 3 — socle | ≈ 15 j | 3 semaines |
| Phase 3 — par pays | 5 à 15 j | 1 à 3 semaines + recette et pilote |

### 9.4 Risques

| Risque | Impact | Parade |
|---|---|---|
| Textes officiels djiboutiens difficiles à obtenir ou non consolidés | Phase 2 bloquée | lancer LOC2-03 dès la semaine 1 ; référent chargé de la collecte ; consolidation manuelle validée |
| Absence de référent qualifié | conformité non garantissable | pas de publication sans signature (règle LOC1-54) |
| Régression France pendant la Phase 1 | clients existants impactés | baseline LOC1-58 rejouée à chaque lot ; déploiement lot par lot |
| Élargissement des colonnes monétaires (LOC1-20) long sur grosses tables | indisponibilité | fenêtre de maintenance, script table par table, répétition sur copie de production |
| Pack publié avec une erreur | calculs faux chez les clients | jeux d'essai bloquants, versionnage, correctif `patch` + notification LOC3-18 |
| Fêtes à date variable annoncées tardivement | congés et échéances faux | statut prévisionnel, alerte, recalcul signalé (LOC2-12) |
| Besoin pays non exprimable par le moteur | code spécifique réintroduit | règle de sortie de code de la Phase 3 : exigence générique testée sur `ZZ` |

---
## Annexe A — Inventaire exhaustif du code en dur

Inventaire du 15 septembre 2026. Chaque ligne renvoie à l'exigence qui la traite.

### A.1 Fonctions SQL effectives contenant des numéros de comptes

Définition effective = dernière migration numérotée (hors `00_`, seeds et tests) qui la déclare.

| # | Fonction | Défini en | Littéraux | Exigence |
|---:|---|---|---|---|
| 1 | `seed_standard_chart` | `03_seed_chart_template.sql:23` | plan PCG complet (≈ 600 comptes) | LOC1-13 |
| 2 | `bootstrap_tenant` | `02_bootstrap_tenant.sql:21` | `401000` `411000` `512000` `530000` + `'EUR'` (l. 70, 105) + `'01-01'` (l. 106) | LOC1-12 |
| 3 | `create_journal_on_payroll_validate` | `81_complete_workflow_triggers.sql:295` | `421` `421000` `431` `431000` `641` `641000` `645` `645000` | LOC1-07, LOC1-34 |
| 4 | `create_journal_on_stock_movement` | `101_stock_valuation_to_gl.sql:156` | `310000` `603000` | LOC1-07 |
| 5 | `allocate_result` | `107_fiscal_year_close.sql:267` | `106000` `120000` `129000` `457000` | LOC1-08 |
| 6 | `create_journal_on_customer_payment` | `108_auxiliary_accounts.sql:237` | `411000` `512000` | LOC1-06 |
| 7 | `create_journal_on_supplier_payment` | `108_auxiliary_accounts.sql:286` | `401000` `411000` `512000` | LOC1-06 |
| 8 | `create_stock_on_manufacturing_complete` | `112_manufacturing_costing.sql:111` | `310000` `355000` `601000` `613000` `641000` `713550` | LOC1-07 |
| 9 | `generate_residual_entry` | `124_acc_advanced.sql:98` | `654` `665` `666` `766` | LOC1-08 |
| 10 | `resolve_stock_account` | `125_stock_advanced.sql:240` | `310000` | LOC1-05 |
| 11 | `resolve_variation_account` | `125_stock_advanced.sql:255` | `603000` | LOC1-05 |
| 12 | `create_journal_on_invoice_validate` | `137_fix_triggers_constraints.sql:45` | `411000` `707000` | LOC1-06 |
| 13 | `create_journal_on_purchase_invoice_validate` | `137_fix_triggers_constraints.sql:183` | `401000` `607000` | LOC1-06 |
| 14 | `post_pos_session_on_close` | `142_fix_pos_triggers.sql:22` | `531000` `707000` | LOC1-07 |
| 15 | `post_pos_session_on_close_multi` | `142_fix_pos_triggers.sql:175` | `707000` | LOC1-07 |
| 16 | `generate_depreciation_entry` | `152_fix_broken_rpc_functions.sql:586` | `280000` `681000` | LOC1-08 |
| 17 | `close_fiscal_year` | `153_fix_carry_forward_and_payroll.sql:34` | `120000` `129000` | LOC1-08 |

Contrôles d'équilibre sur numéros : `108_auxiliary_accounts.sql:349, 361, 371, 381` → LOC1-06.

### A.2 Front : numéros de comptes et classes

| Fichier:ligne | Contenu | Exigence |
|---|---|---|
| `src/lib/queries/payroll.ts:205-209` | `641000` `645000` `431000` `437000` `421000` | LOC1-10, LOC1-34 |
| `src/lib/queries/misc.ts:38-41` | `641000` `645000` `421000` `431000` | LOC1-10, LOC1-34 |
| `src/lib/queries/accounting.ts:1974-1978` | `411000` `707000` `607000` `401000` `512000`, journaux `'ACH'` `'BQ'` | LOC1-09, LOC1-10 |
| `src/lib/queries/accounting.ts:1580-1581` | `startsWith('4457')` `startsWith('4456')` | LOC1-25 |
| `src/lib/queries/accounting.ts:1586-1587` | `startsWith('70')` `startsWith('60')` | LOC1-11, LOC1-25 |
| `src/pages/JournalSaisiePage.tsx:534` | `'445660'` `'445710'` | LOC1-26 |
| `src/pages/SaisieParPiecePage.tsx:177` | `'445660'` `'445710'` | LOC1-26 |
| `src/pages/SIGPage.tsx:74` | `getSolde('603')` | LOC1-38, LOC1-41 |
| `src/pages/LiasseFiscalePage.tsx:56-57` | `startsWith('7')` `startsWith('6')` | LOC1-11, LOC1-40 |
| `src/pages/ThirdPartyAccountsPage.tsx:320` | `startsWith('4')` | LOC1-11 |
| `src/pages/ChartAccountsPage.tsx:179` | `startsWith('4')` | LOC1-11 |
| `src/pages/JournalsPage.tsx:312` | `startsWith('47')` `startsWith('48')` | LOC1-11 |
| `src/pages/SageImportPage.tsx:113-115` | préfixes `401` `411` `421` | LOC1-50 |
| `src/lib/importConfig.ts:34` | `sample: '512000'` | LOC1-10 |
| `src/pages/payroll/PayrollPreparationPage.tsx:354` | `useState('2000')` | LOC1-10 |

### A.3 Front : devises, locales, formats

| Motif | Volume | Exigence |
|---|---:|---|
| `formatCurrency(amount, currency = 'EUR')` (`utils.ts:20`), 2 décimales forcées | 1 définition, 97 fichiers importeurs | LOC1-17, LOC1-18 |
| `formatCurrencyWithCode(…, locale = 'fr-FR')` (`currencyRates.ts:132`) | 1 | LOC1-17 |
| `'EUR'` | 106 / 30 fichiers | LOC1-18 |
| `'fr-FR'` | 16 | LOC1-18 |
| `toLocaleString()` / `toLocaleDateString()` sans locale | 31 | LOC1-18 |
| `toFixed(2)` | 84 | LOC1-18 |
| `€` littéral | 13 | LOC1-18 |
| `bankParsers.ts` devise supposée `'EUR'` (l. 47, 112, 126, 237, 259, 275, 343, 407) | 8 | LOC1-49 |
| `getCurrencyForCountry` → `'EUR'` (`countries.ts:321`), Djibouti absent des tables (l. 201, 255) | — | LOC1-46 |
| `OnboardingPage.tsx:48` `country: 'France'` ; `:82-95` devinette pack/devise | — | LOC1-47 |

### A.4 Base : défauts de colonnes

| Défaut | Colonnes | Exigence |
|---|---|---|
| `'EUR'` | 25 (liste en LOC1-14) | LOC1-14 |
| `'France'` | 5 | LOC1-14 |
| `'CA3'` | 2 | LOC1-14, LOC1-27 |
| `'FR'` | `public_holidays.country` | LOC1-14, LOC1-37 |
| `'fr-FR'` | `legislation_packs.locale` | LOC1-14 |
| `'01-01'` | 2 | LOC1-14 |
| `numeric(15,2)` / `numeric(14,2)` / `numeric(12,2)` | 195 déclarations / 31 migrations (état réel à confirmer via `information_schema`) | LOC1-20 |

### A.5 SQL : arrondis, pays, journaux, paie

| Motif | Occurrences | Exigence |
|---|---|---|
| `round(x, 2)` | 15 fonctions (liste en LOC1-19) | LOC1-19 |
| `'EUR'` dans des fonctions | `bootstrap_tenant`, `trigger_exchange_rate_refresh` (`72:58`, ×6), `notify_bank_reconciliation_needed` (`93:265`), `create_tenant_for_current_user` (`152:1791`) | LOC1-12, LOC1-22 |
| `'FR'` dans des fonctions | `get_legal_parameter` (`114:122`), `calculate_payslip` (`153:444`), `post_pos_session_on_close` (`142:105`), `update_tax_grid_timestamp` (`36:250`) | LOC1-24, LOC1-31 |
| Codes de journaux | ≈ 25 (liste en LOC1-09) | LOC1-09 |
| `LIKE '<classe>%'` | `generate_balance_sheet` (`152:110, 111, 131`), `generate_profit_loss` (`152:172, 188`) | LOC1-11, LOC1-38 |
| `151.67` | `calculate_overtime_pay` (`152:358`) | LOC1-32 |
| Approximation 22 % | `calculate_payslip` (`153:603`) | LOC1-30 |
| Catégories `csg_crds`, colonnes `is_csg_crds`, `csg_type` | `36:71-75`, `114:73-75` | LOC1-33 |
| Mapping TVA français sur tenant fictif | `109_vat_multi_rate.sql:32-41` | LOC1-23 |

### A.6 Paie et calendrier côté front

| Fichier:ligne | Contenu | Exigence |
|---|---|---|
| `src/lib/payroll.ts:4, 51-58` | `FALLBACK_RATES` français | LOC1-30 |
| `src/lib/payroll.ts:92` | `/ 151.67` | LOC1-32 |
| `src/lib/payroll.ts:97` | plafond transport « 75 €/mois France 2024 » | LOC1-30 |
| `src/lib/payroll.ts:20-47` | `PayrollResult` à champs nommés (CSG, chômage…) | LOC1-33 |
| `src/lib/queries/leavesAbsences.ts:566` | `/ 151.67` | LOC1-32 |
| `src/pages/PayrollCalcPage.tsx:25` | `useState(35)` | LOC1-32 |
| `src/pages/Phase6Pages.tsx:1096, 1108` | `vat_rate: 20` | LOC1-25 |
| `src/pages/hr/LeavePlanningPage.tsx:114-115` | week-end `dow === 0 \|\| dow === 6` | LOC1-37 |
| `src/lib/queries/leavesAbsences.ts:380, 479` | `getDay()` week-end | LOC1-37 |
| `src/lib/queries/purchaseAdvanced.ts:182` | `getDay()` échéances | LOC1-37 |
| `src/lib/ganttHelpers.ts:157` | `getDay()` | LOC1-37 |

### A.7 Fonctions françaises non conditionnées

Pages : `FECExportPage`, `EdiTvaPage`, `TvsPage`, `SepaTransferPage`, `SepaPaymentsPage`, `EInvoicePage`, `Nf525AuditPage`, `CPFPage`, `BdesPage`, `SocialDeclarationsPage`, `SIGPage`, `LiasseFiscalePage`, `VatReturnsPage`.
Bibliothèques : `fecValidator.ts`, `facturX.ts`, `sepa.ts`, `sageImport.ts`, `maeParser.ts`.
Edge functions : `submit-e-invoice`, `submit-vat-return`, `transmit-dsn`, `verify-siret`, `validate-vat-vies`.
Fichiers mentionnant SIRET, URSSAF, CSG, CRDS, PMSS, SMIC, DSN, CA3, FEC, Chorus, Factur-X ou NAF : 36.
→ LOC1-41, LOC1-42, LOC1-43, LOC1-45.

### A.8 Reproduire l'inventaire

```bash
# Fonctions SQL effectives avec numéros de comptes : script scripts/inventory/effective-functions.py
# (même logique que check-country-neutral.mjs, règle E01, sur les fichiers)
grep -rnE "'(EUR)'" app/src --include='*.ts' --include='*.tsx' | grep -v __tests__ | wc -l
grep -rnE "toFixed\(2\)" app/src --include='*.ts' --include='*.tsx' | grep -v __tests__ | wc -l
grep -rnE "toLocale(Date)?String\(\)" app/src --include='*.ts' --include='*.tsx' | grep -v __tests__ | wc -l
grep -nE "DEFAULT '(EUR|France|FR|CA3|fr-FR)'::text" app/sql/00_schema_dump.sql | wc -l
```

---

## Annexe B — Catalogue des rôles de comptes et de journaux

La colonne **PCG (pack FR)** reprend le compte utilisé aujourd'hui par le code quand il existe ; ⚠ signale un écart à corriger (LOC1-07) ; « à créer » signale un compte absent de `03_seed_chart_template.sql` à ajouter au pack PCG. Les mappings des autres référentiels sont renseignés dans leur phase, à partir de leurs textes.

### B.1 Rôles de comptes (67)

| # | Rôle | Famille | Sens | Requis par | PCG (pack FR) |
|---:|---|---|:---:|---|---|
| 1 | `CLIENTS` | tiers | D | sales, pos | `411000` |
| 2 | `CLIENTS_DOUTEUX` | tiers | D | sales | `416000` |
| 3 | `CLIENTS_EFFETS_A_RECEVOIR` | tiers | D | sales | `413000` |
| 4 | `CLIENTS_AVANCES_RECUES` | tiers | C | sales | `419100` |
| 5 | `CLIENTS_FACTURES_A_ETABLIR` | tiers | D | closing | `418100` à créer |
| 6 | `FOURNISSEURS` | tiers | C | purchases | `401000` |
| 7 | `FOURNISSEURS_IMMOBILISATIONS` | tiers | C | assets | `404000` |
| 8 | `FOURNISSEURS_AVANCES_VERSEES` | tiers | D | purchases | `409100` |
| 9 | `FOURNISSEURS_FACTURES_NON_PARVENUES` | tiers | C | closing | `408100` |
| 10 | `FOURNISSEURS_EFFETS_A_PAYER` | tiers | C | purchases | `403000` |
| 11 | `TVA_COLLECTEE` | taxes | C | sales, pos | `445710` |
| 12 | `TVA_DEDUCTIBLE_BIENS_SERVICES` | taxes | D | purchases | `445660` |
| 13 | `TVA_DEDUCTIBLE_IMMOBILISATIONS` | taxes | D | assets | `445620` |
| 14 | `TVA_A_DECAISSER` | taxes | C | sales | `445510` |
| 15 | `CREDIT_TVA` | taxes | D | sales | `445670` |
| 16 | `TVA_EN_ATTENTE` | taxes | C | sales | `445800` |
| 17 | `IMPOT_BENEFICES_CHARGE` | taxes | D | closing | `695000` à créer |
| 18 | `ETAT_IMPOT_BENEFICES` | taxes | C | closing | `444000` |
| 19 | `ETAT_RETENUES_A_LA_SOURCE` | taxes | C | purchases | `447000` |
| 20 | `IMPOTS_TAXES_CHARGE` | taxes | D | purchases | `635000` |
| 21 | `ETAT_IMPOT_SALAIRES` | paie | C | payroll | `442000` |
| 22 | `SALAIRES_BRUTS` | paie | D | payroll | `641000` |
| 23 | `CHARGES_SOCIALES_PATRONALES` | paie | D | payroll | `645000` |
| 24 | `PERSONNEL_REMUNERATIONS_DUES` | paie | C | payroll | `421000` |
| 25 | `PERSONNEL_AVANCES` | paie | D | payroll | `425000` |
| 26 | `ORGANISME_SOCIAL` | paie | C | payroll | `431000` (URSSAF), `437000` (autres) par organisme |
| 27 | `BANQUE` | trésorerie | D | sales, purchases | `512000` |
| 28 | `CAISSE` | trésorerie | D | sales | `530000` |
| 29 | `CAISSE_POS` | trésorerie | D | pos | `531000` |
| 30 | `VIREMENTS_INTERNES` | trésorerie | D | sales | `580000` |
| 31 | `MOYENS_PAIEMENT_A_ENCAISSER` | trésorerie | D | sales, pos | `511000` |
| 32 | `VENTES_MARCHANDISES` | gestion | C | sales, pos | `707000` |
| 33 | `VENTES_PRODUITS_FINIS` | gestion | C | sales, manufacturing | `701000` |
| 34 | `PRESTATIONS_SERVICES` | gestion | C | sales | `706000` |
| 35 | `RRR_ACCORDES` | gestion | D | sales | `709000` |
| 36 | `ACHATS_MARCHANDISES` | gestion | D | purchases | `607000` |
| 37 | `ACHATS_MATIERES` | gestion | D | purchases, manufacturing | `601000` |
| 38 | `SERVICES_EXTERIEURS` | gestion | D | purchases | `604000` |
| 39 | `SOUS_TRAITANCE` | gestion | D | manufacturing | `611000` ⚠ code actuel `613000` |
| 40 | `RRR_OBTENUS` | gestion | C | purchases | `609000` |
| 41 | `ESCOMPTES_ACCORDES` | financier | D | sales | `665000` |
| 42 | `ESCOMPTES_OBTENUS` | financier | C | purchases | `765000` |
| 43 | `GAINS_CHANGE` | financier | C | fx | `766000` |
| 44 | `PERTES_CHANGE` | financier | D | fx | `666000` |
| 45 | `ECART_CONVERSION_ACTIF` | financier | D | fx, closing | `476000` à créer |
| 46 | `ECART_CONVERSION_PASSIF` | financier | C | fx, closing | `477000` à créer |
| 47 | `PERTES_CREANCES_IRRECOUVRABLES` | gestion | D | sales | `654000` |
| 48 | `STOCK_MARCHANDISES` | stock | D | stock | `370000` ⚠ code actuel `310000` |
| 49 | `STOCK_MATIERES` | stock | D | stock, manufacturing | `310000` |
| 50 | `STOCK_PRODUITS_FINIS` | stock | D | manufacturing | `355000` |
| 51 | `VARIATION_STOCK_MARCHANDISES` | stock | D | stock | `603700` ⚠ code actuel `603000` |
| 52 | `VARIATION_STOCK_MATIERES` | stock | D | stock | `603100` |
| 53 | `PRODUCTION_STOCKEE` | stock | C | manufacturing | `713500` ⚠ code actuel `713550` (absent du plan) |
| 54 | `IMMOBILISATIONS` | immobilisations | D | assets | par catégorie (`21xxxx`) |
| 55 | `AMORTISSEMENTS` | immobilisations | C | assets | par catégorie (`281xxx`) ⚠ code actuel `280000` |
| 56 | `DOTATIONS_AMORTISSEMENTS` | immobilisations | D | assets | `681100` ⚠ code actuel `681000` |
| 57 | `VALEUR_COMPTABLE_CESSIONS` | immobilisations | D | assets | `675000` |
| 58 | `PRODUITS_CESSIONS` | immobilisations | C | assets | `775000` |
| 59 | `REPRISE_SUBVENTIONS_INVESTISSEMENT` | immobilisations | C | assets (secteur public) | `777000` |
| 60 | `RESULTAT_BENEFICE` | capitaux | C | closing | `120000` |
| 61 | `RESULTAT_PERTE` | capitaux | D | closing | `129000` |
| 62 | `REPORT_A_NOUVEAU_CREDITEUR` | capitaux | C | closing | `110000` |
| 63 | `REPORT_A_NOUVEAU_DEBITEUR` | capitaux | D | closing | `119000` |
| 64 | `RESERVE_LEGALE` | capitaux | C | closing | `106100` |
| 65 | `AUTRES_RESERVES` | capitaux | C | closing | `106800` ⚠ code actuel `106000` |
| 66 | `ASSOCIES_DIVIDENDES_A_PAYER` | capitaux | C | closing | `457000` |
| 67 | `COMPTE_ATTENTE` | divers | D | import, bank | `471000` |

### B.2 Rôles de journaux (8)

| Rôle | Type | PCG (pack FR) — code actuel |
|---|---|---|
| `JOURNAL_VENTES` | sale | `VT` |
| `JOURNAL_ACHATS` | purchase | `AC` (⚠ `ACH` dans `accounting.ts:1976`) |
| `JOURNAL_BANQUE` | bank | `BQ` (un journal par compte bancaire possible) |
| `JOURNAL_CAISSE` | cash | `CA` |
| `JOURNAL_OD` | general | `OD` |
| `JOURNAL_A_NOUVEAUX` | opening | `AN` |
| `JOURNAL_STOCK` | general | `ST` |
| `JOURNAL_PAIE` | general | à créer (aujourd'hui `OD` ou implicite) |

---

## Annexe C — Format de fichiers d'un pack

### C.1 Arborescence

```
packs/
├── README.md                      procédure LOC3-01
├── _template/                     kit LOC3-02
├── _schemas/                      JSON Schema de chaque fichier
├── PCG/                           référentiel
├── FR/                            pays (parent PCG)
├── ZZREF/ ZZ/ ZZ-PUB/             packs de preuve de neutralité
├── PCN-DJ/                        référentiel Djibouti
│   ├── manifest.yaml
│   ├── sources.yaml
│   ├── chart.csv
│   ├── roles.yaml
│   ├── journals.yaml
│   ├── closing.yaml
│   └── statements/
│       ├── balance_sheet.yaml
│       ├── income_statement.yaml
│       ├── cash_flow.yaml
│       └── notes.yaml
├── DJ/                            pays (parent PCN-DJ)
│   ├── manifest.yaml
│   ├── sources.yaml
│   ├── formats.yaml
│   ├── calendar.yaml
│   ├── identifiers.yaml
│   ├── documents.yaml
│   ├── capabilities.yaml
│   ├── currencies.yaml            parités fixes, devises usuelles
│   ├── taxes.yaml                 TVA
│   ├── vat_regimes.yaml
│   ├── corporate_tax.yaml
│   ├── other_taxes.yaml
│   ├── statements/
│   │   ├── vat_return.yaml
│   │   └── tax_return.yaml
│   ├── payroll/
│   │   ├── parameters.yaml
│   │   ├── income_tax.yaml
│   │   ├── contributions.yaml
│   │   ├── organisms.yaml
│   │   ├── components.yaml
│   │   ├── payslip.yaml
│   │   └── declarations.yaml
│   ├── fixtures/
│   │   ├── DJ-01/{input,expected}/
│   │   ├── DJ-02/{input,expected}/
│   │   └── DJ-03/{input,expected}/
│   ├── REVIEW.md                  décisions et désaccords tracés
│   ├── WATCH.md                   veille réglementaire
│   └── RELEASE-1.0.0.md
└── DJ-EP/                         secteur (parent DJ)
    ├── manifest.yaml
    ├── sources.yaml
    ├── chart.csv                  comptes complémentaires
    ├── roles.yaml                 surcharges
    ├── statements/                lignes complémentaires
    └── fixtures/DJ-EP-01/
```

### C.2 `manifest.yaml` (exemple `DJ`, valeurs réglementaires volontairement non renseignées)

```yaml
code: DJ
level: country
parent: PCN-DJ
version: 1.0.0-rc.1
status: draft
country_code: DJ
name: { fr: "Djibouti — secteur privé", ar: "<à traduire>" }
accounting_standard: PCN-DJ
source_ref: SRC-DJ-01
modules: [sales, purchases, bank, stock, pos, manufacturing, payroll, assets, fx, closing]
maintainers:
  analyst: "<nom>"
  reviewer: "<nom>"
  expert: "<nom, n° d'inscription>"
```

### C.3 `formats.yaml`

```yaml
currency: DJF                 # source: ISO 4217
currency_decimals: 0          # source: ISO 4217
price_decimals: null          # décision référent → REVIEW.md
quantity_decimals: 3
rounding_mode: null           # source: SRC-DJ-03
rounding_level: null          # source: SRC-DJ-05
locale: fr-DJ
number_system: latn
ui_languages: [fr, ar]
document_languages: [fr]      # source: SRC-DJ-13
date_format: DD/MM/YYYY
time_zone: Africa/Djibouti
fiscal_year_start: null       # source: SRC-DJ-03
```

Toute valeur `null` fait échouer V11 en `--strict` : le pack ne peut pas être publié incomplet.

### C.4 `taxes.yaml`

```yaml
- tax_code: DJ-STD
  name: { fr: null, ar: null }
  tax_kind: vat
  category: standard
  rate: null
  scope: both
  account_role_collected: TVA_COLLECTEE
  account_role_deductible: TVA_DEDUCTIBLE_BIENS_SERVICES
  declaration_box_base: null
  declaration_box_tax: null
  effective_from: null
  effective_to: null
  source: { id: SRC-DJ-04, article: null }
```

### C.5 `statements/balance_sheet.yaml` (structure)

```yaml
template_code: BS
kind: balance_sheet
name: { fr: "Bilan", ar: null }
source: { id: SRC-DJ-02, page: null }
lines:
  - code: <référence officielle>
    label: { fr: <intitulé officiel>, ar: null }
    level: 1
    side: asset
    account_ranges: []        # ex. ["2100-2199", "-2810-2819"]
    formula: null             # ex. "AB + AC"
    input: false
```

### C.6 `payroll/income_tax.yaml` (structure)

```yaml
code: DJ_ITS
periodicity: null             # monthly | annual
taxable_base: gross_minus_deductible_contributions
rounding: { base: null, tax: null }
brackets:
  - { from: null, to: null, rate: null, fixed: null }
effective_from: null
source: { id: SRC-DJ-04, article: null }
```

---

## Annexe D — Règles du validateur de pack

| Règle | Niveau | Contrôle |
|---|---|---|
| **V01** | erreur | Chaque fichier respecte son JSON Schema |
| **V02** | erreur | `code`, `level`, `parent` cohérents (hiérarchie LOC1-01), parent existant, pas de cycle |
| **V03** | erreur | Paramètres de format présents uniquement au niveau `country` (ou surchargés explicitement au niveau `sector`) |
| **V04** | erreur | `version` semver ; supérieure à la dernière version publiée ; pack publié non modifié sans changement de version |
| **V05** | erreur | Toute valeur réglementaire porte un `source.id` existant dans `sources.yaml` de la lignée ; en `--strict`, chaque source a `file_sha256` et `verified_by` |
| **V06** | erreur | Pour chaque `tax_code`, paramètre légal, barème, cotisation : intervalles `effective_from`/`effective_to` sans trou ni chevauchement depuis la première date |
| **V07** | erreur | Plan : codes uniques, `parent_code` existant, longueur cohérente par niveau, libellés FR non vides ; en `--strict` libellés de toutes les `document_languages` |
| **V08** | erreur | Chaque compte a une `account_nature` du catalogue, cohérente avec `type` |
| **V09** | erreur | Chaque rôle requis par les `modules` du manifeste est mappé ; le compte existe dans le plan de la lignée, `allow_direct_entry = true` ; aucun rôle hors catalogue |
| **V10** | erreur | Gabarits : `line_code` uniques, formules analysables et sans référence circulaire ni inconnue, **couverture** : chaque compte de bilan dans exactement une feuille du bilan, chaque compte de gestion dans exactement une feuille du compte de résultat |
| **V11** | erreur | Aucun `null` dans les champs obligatoires (en `--strict`) ; paramètres légaux obligatoires présents : `LEGAL_WEEKLY_HOURS`, `MONTHLY_HOURS_DIVISOR`, `OVERTIME_TIERS`, `MINIMUM_WAGE`, `PAID_LEAVE_DAYS_PER_MONTH` si module `payroll` |
| **V12** | erreur | Barèmes : tranches contiguës, croissantes, dernière tranche ouverte, taux entre 0 et 100 |
| **V13** | erreur | Cotisations : `organism_code` existant, plafonds référencés existants, chaque organisme a un rôle comptable et un gabarit de déclaration |
| **V14** | erreur | Calendrier : `weekend_days` renseigné ; fériés présents pour l'année en cours et la suivante ; fériés variables marqués |
| **V15** | erreur | Identifiants : `regex` compilable, `checksum_algo` connu, au moins un identifiant `company` |
| **V16** | erreur | Documents : mentions obligatoires référencent des champs existants du modèle de données |
| **V17** | erreur | Capacités : toutes du catalogue ; aucune capacité propre à un autre pays (préfixe pays) activée |
| **V18** | erreur | Jeux d'essai : import sur base vierge, exécution, comparaison des `expected/*.csv` à **0 unité** |
| **V19** | avertissement | Taux de TVA ou paramètre dont la source a plus de 18 mois sans revue (`WATCH.md`) |
| **V20** | avertissement | Libellés arabes (ou autre langue déclarée) manquants hors `--strict` |

---

## Annexe E — Règles du garde-fou anti-code-en-dur

Appliquées par `scripts/check-country-neutral.mjs` à `app/src/**/*.{ts,tsx}` (hors `__tests__`, `test/`, `i18n/locales`) et aux définitions effectives des fonctions (`pg_proc.prosrc`, schéma `public`).

| Règle | Portée | Motif interdit | Remplacement attendu |
|---|---|---|---|
| **E01** | SQL + TS | littéral de 3 à 6 chiffres commençant par une classe comptable et utilisé comme compte : `'[1-9]\d{2,5}'` affecté à une variable ou colonne nommée `*account*`, `*compte*`, `*collectif*` ou passé à `getSolde` | `resolve_account` / `resolveAccount` |
| **E02** | SQL + TS | `account_code LIKE '[0-9]+%'`, `code.startsWith('[0-9]+')`, `left(account_code, n) =` | gabarits, `account_nature`, `is_third_party` |
| **E03** | SQL + TS | `journal_code = '<2-4 lettres>'`, littéral de journal en `INSERT INTO journal_entries` | `resolve_journal` |
| **E04** | SQL + TS | `'EUR'`, `'France'`, `'FR'`, `'fr-FR'`, `'CA3'` hors allowlist | devise fonctionnelle, pack, locale du contexte |
| **E05** | TS | `new Intl.NumberFormat(` / `new Intl.DateTimeFormat(` hors `src/lib/format/` | `formatMoney`, `formatDate` |
| **E06** | TS | `.toLocaleString()` / `.toLocaleDateString()` sans argument, ou avec locale littérale | service de formatage |
| **E07** | TS | `.toFixed(2)` sur un montant | `roundMoney` / `formatMoney` |
| **E08** | TS | caractère `€` ou `$` dans une chaîne de code | `formatMoney` |
| **E09** | SQL | `round(<expr>, 2)` sans commentaire `-- non monétaire` | `round_money` / `round_rate` |
| **E10** | SQL + TS | `151.67`, `35` affecté à `hours*`, `getDay() === 0 \|\| … === 6`, `FALLBACK_` | paramètres légaux, `calendar.ts` |
| **E11** | TS | route ou entrée de menu vers une page du registre des capacités sans `RequireCapability` | LOC1-41 |

**Allowlist** (`scripts/country-neutral.allow.json`) — entrées initiales justifiées :

| Fichier | Règles | Justification |
|---|---|---|
| `src/lib/iso/*.json`, `src/lib/countries.ts` (jusqu'à sa suppression) | E04 | table de référence ISO |
| `src/lib/facturX.ts`, `src/pages/FECExportPage.tsx`, `src/lib/fecValidator.ts` | E04, E07 | formats d'échange français normés — capacités `e_invoicing_fr`, `fec_export` |
| `src/lib/sepa.ts`, `SepaTransferPage.tsx`, `SepaPaymentsPage.tsx`, `sepa_payment_orders.currency` | E04 | SEPA = euro — capacité `sepa` |
| `src/pages/LandingPage.tsx` | E04, E06 | page publique hors société |
| `packs/**` | toutes | données de packs |

Chaque entrée porte `reviewed_on` ; une entrée de plus de 12 mois fait échouer le contrôle jusqu'à revue.

---

*Fin du document.*
