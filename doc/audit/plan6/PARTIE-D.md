# Partie D — qualité des écrans, recette, livraison

> Fichier de suivi **exclusif** de la partie D (règle **R4** du
> [plan en 6 parties](../PLAN-6-PARTIES-PARALLELES-2026-10-05.md)).
> `SUIVI-CHANTIERS.md` et `AGENTS.md` ne s'écrivent **que** par la session
> d'intégration.

| | |
|---|---|
| **Branche** | `plan6/d-ecrans` |
| **Worktree** | `.claude/worktrees/plan6-d-ecrans` |
| **Plage de migrations** | `355` → `369` (peu de SQL) |
| **Territoire de fichiers** | balayages transverses de `app/src/pages`, `app/src/components`, `e2e/`, `scripts/qa`, `app/src/__screen__`, job Playwright |
| **Charge** | ≈ 25 j + recette |
| **Départ possible** | tout de suite pour D.1 → D.4 ; **D.5 attend les secrets** |

## Les tâches

| # | Tâche | Repris de | Charge | État |
|---|---|---|---|---|
| D.1 | Vrai dialogue de confirmation à la place de `confirmSync` (100 fichiers), **par module, un lot par jour** | 1.8, AUD-I01 | 4 j | ✅ **tous les usages migrés (05/10)** |
| D.2 | Typer les 80 états d'écran restants (RH, production, trésorerie, immobilisations, CRM) | DAT-02, suite de 2.16 | 5 j | 🟡 **tranches 1–2 (05/10) : 20 états** |
| D.3 | Alignement des colonnes sur 10 écrans | étape 0.5 | 1 j | ✅ **4 restants faits (05/10) — 6 déjà en `main`** |
| D.4 | Lectures du chemin de l'écran (159 fonctions non couvertes) ; immobilisations et tableaux de bord à l'écran | 4.5, 4.11, 4.12 | 5 j | ⬜ |
| D.5 | Playwright sur chaque PR vers `main` ; 4 parcours qui lisent un chiffre | 4.3, 4.4, AUD-J01/J02 | 3 j | ⬜ |
| D.6 | Les 14 parcours à l'écran, 2 sociétés, 4 gabarits ; correction des écarts bloquants ; re-notation des modules | 4.6, 4.7, P0-08 | recette | 🟡 **kit prêt (05/10) — verdict attendu** |
| D.7 | Rejeu sur copie de production (porte G7 sous le vrai propriétaire), relecture des paramètres globaux et de `banks` | 4.8, 4.9 | 2 j | ⬜ |
| D.8 | Contraste : appliquer la décision D-7 | AUD-I05 | 1 j | ⬜ |

## Attend de vous

- Les **secrets E2E dans GitHub** (bloque D.5).
- La **décision `D-7`** (bloque D.8 — le contraste a été audité, pas tranché).
- **Votre présence** pour la recette (D.6).

## La règle qui rend D possible : livrer en premier, par module

> D balaie des écrans que les autres parties modifient aussi. Le plan est
> explicite : **D livre ces balayages par module et en premier**, en lots d'un
> jour, pour que le conflit soit **court**.

Un balayage de 100 fichiers livré d'un bloc produirait des conflits de
plusieurs jours sur des fichiers que A, C et E déplacent. **Un lot par jour**,
c'est la condition.

## D.1 — le dialogue de confirmation, par module

**Cible.** `confirmSync` (= `window.confirm`) → `confirmDialog` (async) de
`@/lib/confirm`. C'est le motif **déjà en place dans ce module**
(`ChartPacksAdminPage.tsx` fait `await confirmDialog({...})`) et le remplacement
que les commentaires de `lib/confirm.tsx` annoncent (« sera remplacé
progressivement par `confirmDialog` »).

**Un motif par module, pas par fichier.** AUD-I01 et le §7 acceptent
`useConfirm` **ou** `confirmDialog`. Comme le module `system` en a déjà un
d'ouvert, le lot continue `confirmDialog` — on ne mélange pas deux motifs d'un
écran à l'autre. Le lot suivant garde la même règle.

**Effet sur la mesure du suivi** (à régénérer par l'intégration, R4/R6) :
`confirmSync` **100 → 93** ; `useConfirm` / `confirmDialog` **4 → 11**.

### Lot 1 — module `system` (Paramètres), 05/10

7 écrans, 9 appels, tous routés sous `/settings` ou `/system` :

| Écran | Appels |
|---|---|
| `pages/settings/ApiWebhooksPage.tsx` | 3 |
| `pages/settings/TwoFactorPage.tsx` | 1 |
| `pages/settings/EmailTemplatesPage.tsx` | 1 |
| `pages/CurrenciesPage.tsx` | 1 |
| `pages/TeamPage.tsx` | 1 |
| `pages/TaxGridSettingsPage.tsx` | 1 |
| `pages/FiscalYearsPage.tsx` | 1 |

`LeaveRulesPage.tsx` (sous `pages/settings/` mais routé `/hr/leave-rules`) est
du module **hr** : il n'est pas dans ce lot.

**Preuve.** `tsc -b --noEmit` ✅ · `oxlint` **0** sur les 7 fichiers ✅ ·
Vitest **1661 / 1699** (38 sautés) ✅.

### Lot 2 — module `hr`, 05/10

16 écrans, 17 appels, tous routés `/hr/*` (dont `settings/LeaveRulesPage`, routé
`/hr/leave-rules`) : `EmployeesPage` · `PayRunsPage` · `TimesheetsPage` ·
`PaySlipsPage` · `PayrollAccountingPage` · `LeaveRequestsPage` ·
`settings/LeaveRulesPage` · `ContractsPage` · `LegalDeclarationsPage` ·
`WorkHardshipPage` · `CareerHistoryPage` · `CPFPage` · `EmployeeDocumentsPage` ·
`EmployeeExpensesPage` · `payroll/PayrollPreparationPage` ·
`payroll/SepaPaymentsPage`.

Tous `tCommon('form.confirmDelete')` **sauf** `SepaPaymentsPage`
(`t('sepa.confirmTransmit')`).

**Preuve.** `grep confirmSync` = 0 sur le module ✅ · `tsc -b --noEmit` ✅ ·
`oxlint` **0** sur les 16 fichiers ✅ · Vitest **1661 / 1699** (38 sautés) ✅.

### Lot 3 — module `accounting`, 05/10

30 écrans, 41 appels, routés `/accounting/*` : `AccountTags` · `AnalyticPlans` ·
`AnalyticSections` · `BankReconciliationRules` · `Brouillard` ·
`BudgetCommitments` · `Budgets` · `ChartAccounts` · `CurrencyRevaluation` ·
`DistributionGrills` · `EdiTva` · `EntryTemplates` · `FiscalBackup` ·
`FiscalPositions` · `FiscalYearClosure` · `FixedAssets` · `FusionComptes` ·
`JournalClosure` · `JournalEntries` · `JournalSaisie` (3 appels, dont 1
**positif** ligne 531) · `Journals` · `Lettrage` · `PaymentTerms` ·
`PlanReporting` · `RecurringEntries` · `Regularization` · `ReminderLevels` ·
`RevisionCycles` · `TaxRates` · `Tvs`.

**Preuve.** `grep confirmSync` = 0 sur le module ✅ · `tsc -b --noEmit` ✅ ·
`oxlint` **0** sur les 30 fichiers ✅ · Vitest **1661 / 1699** (38 sautés) ✅.

### Lot 4 — les modules restants, 05/10

Lots 1 → 3 faits, D.1 termine **tout le reste** (la fenêtre « un lot par jour »
est levée à la demande du chef de produit) : 41 écrans/composants + 5 mocks.

| Module | Écrans / composants |
|---|---|
| `treasury` | `BankRules`, `BankSync`, `BankTransactions`, `PaymentOrders` |
| `commercial` | `CreditNotes`, `CustomerPayments`, `DeliveryNotes`, `Invoices`, `PurchaseCreditNotes`, `PurchaseInvoices`, `PurchaseOrders`, `Quotes`, `SalesOrders`, `SupplierPayments`, `PriceLists` |
| `stock` | `Products`, `StockReservations`, `Warehouses`, `GoodsReceipt`, `components/StockPhantomsPanel` |
| `production` | `BOM`, `Machines`, `ManufacturingOrders`, `Routings`, `Toolings`, `SubcontractingPages`, `Forecasts`, `Planning`, `MRPPages` |
| `projectManagement` | `Projects`, `components/project-management/DocView`, `.../DynamicTable`, `components/documents/DocumentList` |
| `reporting` + lots divers | `VatReturns`, `ComplementaryPages`, `Phase2Pages` → `Phase7DPages`, `components/PartnerBankAccountsModal` |

**Deux cas profonds** hors de la règle uniforme (l'argument imbrique
`formatCurrency(...)`) traités à la main : `PurchaseOrdersPage`
(`budgetExceedConfirm`) et `PurchaseInvoicesPage` (`budgetExceedWarning`).

**Un défaut de typage corrigé** — `DynamicTable.handleDeleteTask` était un
`useCallback` **non `async`** ; `tsc` l'a attrapé (la relecture, non). Devenu `async`.

**Preuve.** `grep confirmSync app/src` = **0 hors la définition** ✅ ·
`tsc -b --noEmit` ✅ · `oxlint` **0** sur les 46 fichiers ✅ ·
Vitest **1661 / 1699** (38 sautés) ✅ · mesure : `confirmSync` **100 → 1**,
`useConfirm`/`confirmDialog` **4 → 103**.

### D.1 — terminé (~100 fichiers)

Tous les appels `confirmSync` (le `window.confirm` déguisé) sont passés au vrai
dialogue `confirmDialog`. Le suivi tombe de **100 → 1** : le `1` est la
définition morte ci-dessous, hors de mon territoire.

### Demande hors territoire (R3)

`app/src/lib/confirm.tsx` (§2 ne le met pas dans le territoire de D) porte encore
la définition devenue morte :

```ts
export function confirmSync(message: string): boolean { return window.confirm(message) }
```

**Demande à l'intégration :** la **supprimer** (le suivi passerait à
`confirmSync` = 0) et poser la **garde CI qui interdit `confirmSync`**, comme
1.8 / AUD-I01 le demandent. Aucun usage restant (mesuré : `grep confirmSync
app/src` = cette seule ligne).

## D.2 — typer les états d'écran (suite de 2.16)

**Méthode 2.16** : nommer le type d'un état depuis sa fonction de requête —
`useState<Awaited<ReturnType<typeof FN>>>` (ou `[number]` pour l'élément).

**Ce que la mesure dit d'abord.** L'audit du 02/10
([ETAT-DES-LIEUX-TYPAGE-ETATS-TRANCHE-2](../ETAT-DES-LIEUX-TYPAGE-ETATS-TRANCHE-2-2026-10-02.md))
a montré que le lot « 85 états » était une **hypothèse** et que **son lot de
défauts produits est vide**. D.2 est donc de l'**hygiène** de typage (faire
baisser le plafond `any`), pas la fermeture de défauts annoncés.

### Tranche 1 — 05/10 (11 états, 7 écrans)

| Écran | États typés |
|---|---|
| `EmployeeExpensesPage` | `selectedReport` |
| `EmployeeExitPage` | `processes`, `selectedProcess` |
| `ManagerExpenseApprovalsPage` | `reports`, `selectedReport`, `lines` |
| `crm/CampaignsPage` | `stats` |
| `TreasuryDashboardPage` | `data` |
| `TreasuryForecastPage` | `data` |
| `HRDashboardPage` | `timesheets`, `dashData` |

**Défaut révélé ET fermé** — `HRDashboardPage` : la garde
`dashData?.medical?.overdue > 0` ne **couvrait pas** la lecture
`dashData.medical.overdue` qui suivait (accès **non chaîné**). `tsc` l'a attrapé
dès que l'état a été typé ; corrigé en `(… ?? 0) > 0` + `dashData?.medical?.overdue`.

**Preuve.** `tsc -b --noEmit` ✅ · `oxlint` **0** sur les 7 ✅ ·
Vitest **1661 / 1699** (38 sautés) ✅ · plafond `any` de production **936 → 925**
(`.any-ceiling.json` est régénéré par l'intégration — règle R6, laissé au gel ici).

### Tranche 2 — 05/10 (9 états, 5 écrans)

| Écran | États typés |
|---|---|
| `hr/DocumentManagementPage` | `stats` |
| `ExpenseCategoriesPage` | `records`, `editRecord` |
| `MRPPages` | `runs`, `selectedRun`, `proposals` |
| `employee/EmployeeProfilePage` | `profile`, `alerts` |
| `DataExportPage` | `mirrorStatus` |

**Preuve.** `tsc -b --noEmit` ✅ · `oxlint` **0** sur les 5 ✅ ·
Vitest **1661 / 1699** (38 sautés) ✅ · plafond `any` de production **936 → 916**
(**20 `any`** en moins sur les deux tranches).

> **Dit** : plusieurs de ces états sont nommés depuis des requêtes dont le **type
> de retour n'est pas encore déclaré** — l'état est nommé et le `any` explicite
> disparaît, mais la sécurité ne progresse vraiment que là où la requête est déjà
> typée (p. ex. `getRhDashboardData`, qui a révélé le défaut de la tranche 1).
> La **« voie C »** de 2.16 — déclarer le type de retour des requêtes **avant** de
> nommer les états — reste à faire.

**Suite** — les états restants (document, RH, immobilisations, production, CRM),
puis la « voie C » de 2.16 (déclarer le type de retour des fonctions de requête
avant de nommer les états).

## D.3 — alignement des colonnes (reprise gelée)

Voir [REPRISE-2-ALIGNEMENT-COLONNES.md](REPRISE-2-ALIGNEMENT-COLONNES.md) :
10 écrans, l'instantané `f5cda2f`.

**Mesuré le 05/10** — le gel est **à moitié déjà dans `main`** : `BOMPage`,
`CreditNotesPage`, `FixedAssetsPage`, `QuotesPage`, `SearchEntriesPage` ont déjà
`<Fragment>` ; `ChartAccountsPage` aussi (son `<div key={i}>` est une grille de
formulaire, hors table). **Il restait 4 écrans :**

| Écran | Correction |
|---|---|
| `LettragePage` | `<div key={code}>` → `<Fragment key={code}>` |
| `PurchaseCreditNotesPage` | `<div key={cn.id}>` → `<Fragment key={cn.id}>` |
| `PriceListsPage` | idem + ligne dépliée `<div>` → `<tr><td colSpan={5}>` |
| `RoutingsPage` | idem + ligne dépliée `<div>` → `<tr><td colSpan={6}>` |

Le défaut : un `<div>` dans `<tbody>` (HTML invalide) — React le rend **hors du
tableau** et **désaligne les colonnes**. Corrigé **au mot près** du gel `f5cda2f`.

**Preuve.** `grep '<div key'` sur les 4 = **0** ✅ · `tsc -b --noEmit` ✅ ·
`oxlint` **0** sur les 4 ✅ · Vitest **1661 / 1699** (38 sautés) ✅.

> **Non joué ici :** la suite d'écrans (`npx vitest run src/__screen__/` + job
> `screen-path`) exige le banc PostgreSQL/PostgREST (`SCREEN_RIG`), absent du
> poste. À rejouer par l'intégration, seule à avoir la base.

## D.6 — la recette (P0-08) : industrialisée, pas laissée à la main

**Le constat du plan d'origine** : les 14 parcours P0-08 « demandent un
navigateur, un compte et des captures » — 🔴 *non automatisable*. C'est vrai du
**verdict** ; c'est faux de tout le reste. D.6 est donc traité en deux temps.

### Ce que le kit fixe (et ne décide pas)

Un générateur — `app/scripts/qa/recette.mjs`, **sans aucune dépendance** — fige
le **référentiel** des 14 parcours (recopié de `RESTE-A-FAIRE` § P0-08, la seule
source qui fait foi) et en tire trois artefacts :

| Artefact | Rôle |
|---|---|
| `recette/parcours.json` | le référentiel **machine-lisible** — base du futur scénario Playwright (D.5) |
| `recette/PROCES-VERBAL-P0-08.md` | le **PV à signer** : 14 parcours × verdict, matrice 2 états × 4 gabarits, critères de sortie |
| `recette/CERTIFICAT-RECETTE.html` | le **certificat** : imprimable, daté, **empreint (SHA-256)**, re-notation des modules |

```bash
node app/scripts/qa/recette.mjs          # écrit les trois artefacts
```

Le certificat agrège les **notes de module** si `app/.qa-out/findings.json`
existe (tournée de l'essaim `/qa`) ; sinon il écrit « non mesuré » et nomme la
commande — **jamais un faux vert**.

### Pourquoi cela reste « vous »

D.6 **attend votre présence** pour une seule chose : le **verdict et la
signature** (le 👤 de P0-08). Ce qui ne se délègue pas, c'est dire « ce parcours
me convient » et « cet écart est **bloquant** ». Le kit ne remplace pas cette
décision — il la **réduit à une heure** : arriver avec les 112 passages cadrés,
les chiffres déjà lus, et n'avoir qu'à valider et signer.

### L'angle marketing (choisi, pas imposé)

Le certificat est aussi un **argument** : là où l'usage veut qu'une recette se
perde dans un mail ou un tableur, celle-ci produit un **document vérifiable** —
daté, empreint, signable. Même réflexe de preuve que le **certificat
d'intégrité** (P1) : *la preuve, pas la promesse*. **Sans complication** : le
kit n'ajoute ni service, ni dépendance, ni étape — il **range** ce qui existait.

### État
- [x] le référentiel des 14 parcours est figé et machine-lisible ;
- [x] le PV et le certificat se génèrent (empreinte stable `ce92316f…`) ;
- [ ] les 14 verdicts + la signature (**vous**) ;
- [ ] les écarts bloquants corrigés (moi, à votre verdict) — le « 4.7 ».

## Journal

| Date | Lot | Module | Ce qui est fait | Batterie | Commit |
|---|---|---|---|---|---|
| 05/10 | D.1 · lot 1 | `system` | 7 écrans (`ApiWebhooks`, `TwoFactor`, `EmailTemplates`, `Currencies`, `Team`, `TaxGridSettings`, `FiscalYears`) : `confirmSync` → `confirmDialog`, 9 appels | tsc ✅ · oxlint 0 · Vitest 1661/1699 | `2a01631` |
| 05/10 | D.1 · lot 2 | `hr` | 16 écrans : `confirmSync` → `confirmDialog`, 17 appels | grep 0 · tsc ✅ · oxlint 0 · Vitest 1661/1699 | `1b60cbb` |
| 05/10 | D.1 · lot 3 | `accounting` | 30 écrans : `confirmSync` → `confirmDialog`, 41 appels | grep 0 · tsc ✅ · oxlint 0 · Vitest 1661/1699 | `f9b9079` |
| 05/10 | D.1 · lot 4 | modules restants | 41 fichiers + 5 mocks : `confirmSync` → `confirmDialog` | grep 0 · tsc ✅ · oxlint 0 · Vitest 1661/1699 | `8f57910` |
| 05/10 | D.3 | écrans | 4 écrans : `<div key>` → `<Fragment>` (+ `<tr><td colSpan>`), reprise `f5cda2f` (6 déjà en `main`) | tsc ✅ · oxlint 0 · Vitest 1661/1699 | `10a51bb` |
| 05/10 | D.2 · tranche 1 | RH/trésorerie/CRM | 11 états typés depuis les requêtes (méthode 2.16) + 1 défaut de narrowing fermé | tsc ✅ · oxlint 0 · Vitest 1661/1699 · any 936→925 | `e3ea341` |
| 05/10 | D.2 · tranche 2 | RH/employee/trésorerie | 9 états typés (5 écrans) | tsc ✅ · oxlint 0 · Vitest 1661/1699 · any 936→916 (cumul 20) | `HASH_D2T2` |
| 05/10 | D.6 | recette | kit P0-08 : référentiel 14 parcours + PV + certificat (empreinte `ce92316f…`, 112 passages) | script OK · oxlint 0 | `56892d6` |