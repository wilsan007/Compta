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
| D.2 | Typer les 80 états d'écran restants (RH, production, trésorerie, immobilisations, CRM) | DAT-02, suite de 2.16 | 5 j | ⬜ |
| D.3 | Alignement des colonnes sur 10 écrans | étape 0.5 | 1 j | ⬜ |
| D.4 | Lectures du chemin de l'écran (159 fonctions non couvertes) ; immobilisations et tableaux de bord à l'écran | 4.5, 4.11, 4.12 | 5 j | ⬜ |
| D.5 | Playwright sur chaque PR vers `main` ; 4 parcours qui lisent un chiffre | 4.3, 4.4, AUD-J01/J02 | 3 j | ⬜ |
| D.6 | Les 14 parcours à l'écran, 2 sociétés, 4 gabarits ; correction des écarts bloquants ; re-notation des modules | 4.6, 4.7, P0-08 | recette | ⬜ |
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

## D.3 — reprise gelée

Voir [REPRISE-2-ALIGNEMENT-COLONNES.md](REPRISE-2-ALIGNEMENT-COLONNES.md) :
10 écrans, l'instantané `f5cda2f`. **Mesurer d'abord** — `CreditNotesPage.tsx`
a bougé depuis le gel, le patch peut ne plus s'appliquer tel quel.

## Journal

| Date | Lot | Module | Ce qui est fait | Batterie | Commit |
|---|---|---|---|---|---|
| 05/10 | D.1 · lot 1 | `system` | 7 écrans (`ApiWebhooks`, `TwoFactor`, `EmailTemplates`, `Currencies`, `Team`, `TaxGridSettings`, `FiscalYears`) : `confirmSync` → `confirmDialog`, 9 appels | tsc ✅ · oxlint 0 · Vitest 1661/1699 | `2a01631` |
| 05/10 | D.1 · lot 2 | `hr` | 16 écrans : `confirmSync` → `confirmDialog`, 17 appels | grep 0 · tsc ✅ · oxlint 0 · Vitest 1661/1699 | `1b60cbb` |
| 05/10 | D.1 · lot 3 | `accounting` | 30 écrans : `confirmSync` → `confirmDialog`, 41 appels | grep 0 · tsc ✅ · oxlint 0 · Vitest 1661/1699 | `f9b9079` |
| 05/10 | D.1 · lot 4 | modules restants | 41 fichiers + 5 mocks : `confirmSync` → `confirmDialog` | grep 0 · tsc ✅ · oxlint 0 · Vitest 1661/1699 | `HASH_LOT4` |