# Plan d'Implémentation Trilingue (FR / EN / AR)

## Vue d'ensemble

**Objectif:** Rendre l'application 100% trilingue — Français, Anglais, Arabe — jusqu'au moindre détail (onglets, labels, boutons, messages d'erreur, toasts, placeholders, tooltips, en-têtes de tableaux, états, etc.).

**Stack technique:**
- `i18next` + `react-i18next` pour la gestion des traductions
- Support RTL (right-to-left) pour l'arabe
- Persistance de la langue via `localStorage` + préférence utilisateur en BDD
- Formatage locale-aware (dates, devises, nombres) via `Intl`

**Ampleur estimée:**
- 105 pages à internationaliser
- 8 composants partagés
- 10 fichiers lib (notamment `queries.ts` 204KB, `utils.ts`, `countries.ts`)
- ~3000-5000 chaînes de caractères à extraire et traduire
- Navigation complète (`Layout.tsx` 581 lignes)

---

## Architecture cible

```
app/src/
├── i18n/
│   ├── index.ts              # Configuration i18next
│   ├── locales/
│   │   ├── fr/
│   │   │   ├── common.json      # Chaînes communes (boutons, actions, statuts)
│   │   │   ├── nav.json         # Navigation, menus, breadcrumbs
│   │   │   ├── auth.json        # Login, signup, onboarding
│   │   │   ├── sales.json       # Ventes: factures, devis, avoirs, commandes
│   │   │   ├── purchases.json   # Achats: factures, fournisseurs, commandes
│   │   │   ├── accounting.json  # Comptabilité: journaux, grand livre, balance
│   │   │   ├── banking.json     # Banque: comptes, transactions, rapprochement
│   │   │   ├── treasury.json    # Trésorerie: prévisions, paiements
│   │   │   ├── stock.json       # Stock: entrepôts, mouvements, inventaire
│   │   │   ├── production.json  # Production: gammes, machines, OF, MRP
│   │   │   ├── hr.json          # RH: employés, paie, congés, contrats
│   │   │   ├── reports.json     # Rapports: bilan, compte de résultat, TVA
│   │   │   ├── settings.json    # Paramètres: société, utilisateurs, intégrations
│   │   │   └── errors.json      # Messages d'erreur, validations
│   │   ├── en/
│   │   │   └── (même structure)
│   │   └── ar/
│   │       └── (même structure)
│   ├── hooks/
│   │   └── useLocale.ts       # Hook pour formatage locale-aware
│   └── types.ts               # Types pour les namespaces
├── components/
│   └── LanguageSwitcher.tsx   # Sélecteur de langue FR/EN/AR
```

---

## Phases et répartition des agents

### Phase 0: Infrastructure i18n (SÉQUENTIEL — fondation)

> ⚠️ **Bloquant** — tout dépend de cette phase. Aucun autre agent ne peut démarrer avant.

**Agent-0: Architecte i18n**

| Tâche | Détail |
|-------|--------|
| Installer dépendances | `i18next`, `react-i18next`, `i18next-browser-languagedetector` |
| Créer `src/i18n/index.ts` | Config i18next avec namespaces, fallback, détection langue |
| Créer structure dossiers | `src/i18n/locales/{fr,en,ar}/*.json` (12 namespaces × 3 langues = 36 fichiers) |
| Créer fichiers JSON squelettes | Tous les fichiers avec clés vides `{}` |
| Wrapper App avec `I18nextProvider` | Modifier `main.tsx` pour injecter i18n |
| Créer `LanguageSwitcher.tsx` | Composant dropdown FR/EN/AR avec drapeaux |
| Créer `useLocale.ts` | Hook retournant `formatCurrency`, `formatDate`, `formatNumber` basés sur langue active |
| Support RTL | Ajouter logique `dir="rtl"` sur `<html>` quand langue = ar |
| Persistance | `localStorage` + sync avec BDD (table `user_preferences`) |
| TypeScript types | Types pour auto-complétion des clés de traduction |

**Livrable:** Infrastructure i18n fonctionnelle, app démarre sans casser, `useTranslation()` utilisable partout.

---

### Phase 1: Extraction & Traduction (PARALLÈLE — 12 groupes)

> 🚀 **12 agents en parallèle** après Phase 0. Chaque agent prend un module métier.

#### Groupe A — Modules communs (3 agents parallèles)

| Agent | Namespace | Fichiers à traiter | Clés estimées |
|-------|-----------|-------------------|---------------|
| **Agent-A1: Commun** | `common.json` | `ui.tsx`, `utils.ts` (translateStatus), `toast.tsx`, `ProtectedRoute.tsx` | ~200 |
| **Agent-A2: Navigation** | `nav.json` | `Layout.tsx` (581 lignes), `CommandPalette.tsx` | ~150 |
| **Agent-A3: Auth** | `auth.json` | `LoginPage.tsx`, `SignupPage.tsx`, `OnboardingPage.tsx`, `AcceptInvitationPage.tsx`, `OnboardingModal.tsx` | ~120 |

#### Groupe B — Modules métier (9 agents parallèles)

| Agent | Namespace | Fichiers à traiter | Clés estimées |
|-------|-----------|-------------------|---------------|
| **Agent-B1: Ventes** | `sales.json` | `InvoicesPage.tsx`, `QuotesPage.tsx`, `CreditNotesPage.tsx`, `RecurringInvoicesPage.tsx`, `SalesOrdersPage.tsx`, `DeliveryNotesPage.tsx`, `CustomerPaymentsPage.tsx`, `SalesDashboardPage.tsx` | ~400 |
| **Agent-B2: Achats** | `purchases.json` | `PurchaseInvoicesPage.tsx`, `PurchaseCreditNotesPage.tsx`, `PurchaseOrdersPage.tsx`, `GoodsReceiptPage.tsx`, `SupplierPaymentsPage.tsx`, `SuppliersPage.tsx`, `PurchasesDashboardPage.tsx`, `SupplierInvoiceAutomationPage.tsx` | ~350 |
| **Agent-B3: Comptabilité** | `accounting.json` | `AccountingDashboardPage.tsx`, `AccountingHomePage.tsx`, `JournalEntriesPage.tsx`, `JournalSaisiePage.tsx` (34KB!), `GeneralLedgerPage.tsx`, `TrialBalancePage.tsx`, `ChartAccountsPage.tsx`, `JournalsPage.tsx`, `EntryTemplatesPage.tsx`, `ThirdPartyAccountsPage.tsx`, `PaymentGenerationPage.tsx`, `LettragePage.tsx`, `SearchEntriesPage.tsx`, `JournalClosurePage.tsx`, `FiscalYearClosurePage.tsx`, `BrouillardPage.tsx`, `AgedBalancePage.tsx`, `EcheancierPage.tsx`, `GrandLivreTiersPage.tsx`, `FECExportPage.tsx`, `SIGPage.tsx`, `AnalyticBalancePage.tsx`, `AnalyticSectionsPage.tsx`, `BudgetsPage.tsx`, `BudgetCommitmentsPage.tsx` | ~800 |
| **Agent-B4: Banque** | `banking.json` | `BankAccountsPage.tsx`, `BankTransactionsPage.tsx`, `BankReconciliationPage.tsx`, `BankRulesPage.tsx`, `BankingDashboardPage.tsx` | ~200 |
| **Agent-B5: Trésorerie** | `treasury.json` | `TreasuryDashboardPage.tsx`, `TreasuryForecastPage.tsx`, `PaymentOrdersPage.tsx`, `CollectionDashboardPage.tsx` | ~150 |
| **Agent-B6: Stock** | `stock.json` | `WarehousesPage.tsx`, `StockQuantitiesPage.tsx`, `StockMovementsPage.tsx`, `InventoryPage.tsx`, `ReorderPage.tsx`, `PriceListsPage.tsx`, `GescomTransferPage.tsx`, `BOMPage.tsx`, `ProductsPage.tsx` | ~300 |
| **Agent-B7: Production** | `production.json` | `ProductionDashboardPage.tsx`, `RoutingsPage.tsx`, `MachinesPage.tsx`, `ToolingsPage.tsx`, `ManufacturingOrdersPage.tsx`, `ManufacturingOrderDetailPage.tsx` (21KB), `SubcontractingPages.tsx`, `MRPPages.tsx`, `ForecastsPage.tsx`, `PlanningPage.tsx`, `ComplementaryPages.tsx` | ~500 |
| **Agent-B8: RH** | `hr.json` | `HRDashboardPage.tsx`, `EmployeesPage.tsx`, `PayRunsPage.tsx`, `PaySlipsPage.tsx`, `PayrollAccountingPage.tsx`, `TimesheetsPage.tsx`, `LeaveRequestsPage.tsx`, `ContractsPage.tsx`, `LegalDeclarationsPage.tsx`, `TrainingPage.tsx` | ~350 |
| **Agent-B9: Rapports & Settings** | `reports.json` + `settings.json` | `ReportsPage.tsx`, `BalanceSheetPage.tsx`, `CashFlowPage.tsx`, `VatReturnsPage.tsx`, `JournalsReportPage.tsx`, `FinancialDashboardPage.tsx`, `BIReportingPage.tsx`, `BudgetTrackingPage.tsx`, `SettingsPage.tsx`, `DataExportPage.tsx`, `ImportPage.tsx`, `TeamPage.tsx`, `CurrenciesPage.tsx`, `FiscalYearsPage.tsx`, `AuditLogPage.tsx`, `WorkspacePage.tsx`, `DashboardPage.tsx`, `ProjectsPage.tsx`, `FixedAssetsPage.tsx` | ~500 |

#### Groupe C — Traduction (3 agents parallèles, après extraction)

> Une fois les clés extraites en français par les agents B, 3 agents traducteurs travaillent en parallèle.

| Agent | Langue | Source |
|-------|--------|--------|
| **Agent-C1: Traducteur EN** | Anglais | Tous les `fr/*.json` → `en/*.json` |
| **Agent-C2: Traducteur AR** | Arabe | Tous les `fr/*.json` → `ar/*.json` |
| **Agent-C3: Traducteur EN+AR (errors & common)** | EN + AR | Focus sur `common.json`, `errors.json`, `nav.json` en priorité |

---

### Phase 2: Intégration & Refactoring (PARALLÈLE — après Phase 1)

> 🔄 Les mêmes agents B1-B9 reprennent leurs fichiers pour **remplacer** les chaînes hardcoded par des appels `t('namespace:key')`.

**Pour chaque page:**
1. Remplacer tous les string literals par `t('module.key')`
2. Remplacer `formatCurrency()` / `formatDate()` par versions locale-aware via `useLocale()`
3. Remplacer `translateStatus()` par `t('common:status.' + status)`
4. Remplacer les labels de navigation par `t('nav:...')`
5. Remplacer les messages de toast par `t('module:toast.success')` etc.
6. Remplacer les placeholders, tooltips, aria-labels
7. Remplacer les en-têtes de tableaux, titres de modales, boutons d'action

**Ordre de traitement (parallèle, mêmes groupes que Phase 1):**
1. Agent-A1 → `ui.tsx`, `utils.ts`, `toast.tsx`, `ProtectedRoute.tsx`
2. Agent-A2 → `Layout.tsx`, `CommandPalette.tsx`
3. Agent-A3 → Pages auth
4. Agents B1-B9 → Leurs pages respectives (en parallèle)

---

### Phase 3: QA & Validation (PARALLÈLE — après Phase 2)

#### 3a. Agents QA (3 agents en parallèle, un par langue)

| Agent | Langue | Vérifications |
|-------|--------|---------------|
| **QA-FR** | Français | Aucune régression vs version actuelle |
| **QA-EN** | Anglais | Toutes les clés traduites, pas de texte FR restant |
| **QA-AR** | Arabe | Toutes les clés traduites, RTL fonctionnel, pas de texte FR restant |

**Checklist QA par agent:**
- [ ] Aucune chaîne hardcoded restante (grep de strings françaises dans le code)
- [ ] Aucune clé de traduction manquante (i18next debug mode)
- [ ] Pas de clé `undefined` ou `[object Object]` affichée
- [ ] Formatage des dates correct selon locale
- [ ] Formatage des devises correct selon locale
- [ ] Boutons, labels, placeholders tous traduits
- [ ] Messages d'erreur et de succès traduits
- [ ] En-têtes de tableaux traduits
- [ ] Tooltips et aria-labels traduits
- [ ] Breadcrumbs traduits
- [ ] Titres de pages traduits

#### 3b. Agent Cohérence (1 agent)

| Vérification | Détail |
|-------------|--------|
| **Cohérence terminologique** | Même terme traduit de la même façon partout (ex: "facture" = "invoice" partout en EN, "فاتورة" partout en AR) |
| **Cohérence des statuts** | `translateStatus` utilise bien les clés i18n |
| **Cohérence navigation** | Les labels du menu correspondent aux titres de pages |
| **Cohérence des namespaces** | Pas de doublons de clés entre namespaces |
| **Cohérence RTL** | Layout, modales, tables, formulaires s'affichent correctement en RTL |

#### 3c. Agent Validation Technique (1 agent)

| Vérification | Détail |
|-------------|--------|
| **Build TypeScript** | `tsc -b` passe sans erreur |
| **Build Vite** | `vite build` réussit |
| **Lint** | `oxlint` passe |
| **Runtime** | App démarre, changement de langue fonctionne sans reload |
| **Persistance** | La langue choisie persiste après reload |
| **Performance** | Pas de lag visible au changement de langue |
| **Bundle size** | Fichiers de traduction chargés en lazy par namespace |

---

### Phase 4: Corrections & Boucle (Itératif)

> Si QA ou Validation échouent → retour à l'agent concerné pour correction → re-QA.

**Flux de correction:**
```
QA-Agent détecte problème
  → Identifie l'agent responsable (par namespace)
    → Agent corrige
      → QA-Agent re-valide
        → Si OK → ✅ Validé
        → Si KO → 🔁 Boucle de correction
```

**Critères de sortie:**
- 0 chaîne hardcoded française restante
- 0 clé de traduction manquante dans les 3 langues
- Build TypeScript + Vite réussit
- App fonctionnelle dans les 3 langues
- RTL correct en arabe
- Formatage locale-aware opérationnel

---

## Diagramme de flux des agents

```
Phase 0 (SÉQUENTIEL)
  ┌─────────────────────────────┐
  │     Agent-0: Architecte      │
  │  (infra i18n, dépendances)   │
  └──────────────┬──────────────┘
                 │
     ┌───────────▼───────────┐
     │   VALIDATION GATE 0   │  ← Agent-Val: infra OK? build OK?
     └───────────┬───────────┘
                 │
Phase 1 (PARALLÈLE — 12 agents)
     ┌───────────┼───────────────────────────────────┐
     │           │                                   │
  ┌──▼──┐  ┌────▼────┐  ┌────▼────┐  ┌───▼───┐  ┌───▼───┐
  │A1   │  │A2       │  │A3       │  │B1..B9 │  │       │
  │Comm │  │Nav      │  │Auth     │  │Modules│  │       │
  └──┬──┘  └────┬────┘  └────┬────┘  └───┬───┘  └───┬───┘
     │           │            │           │          │
     └───────────┴────────────┴───────────┴──────────┘
                 │
     ┌───────────▼───────────┐
     │   VALIDATION GATE 1   │  ← Agent-Val: toutes clés extraites?
     └───────────┬───────────┘
                 │
Phase 1b (PARALLÈLE — 3 agents traducteurs)
     ┌───────────┼───────────┐
     │           │           │
  ┌──▼──┐   ┌───▼───┐  ┌───▼───┐
  │C1   │   │C2     │  │C3     │
  │EN   │   │AR     │  │EN+AR  │
  └──┬──┘   └───┬───┘  └───┬───┘
     └──────────┴──────────┘
                 │
     ┌───────────▼───────────┐
     │   VALIDATION GATE 1b  │  ← Agent-Val: 36 fichiers JSON complets?
     └───────────┬───────────┘
                 │
Phase 2 (PARALLÈLE — 12 agents, mêmes que Phase 1)
     ┌───────────┼───────────────────────────────────┐
     │           │                                   │
  ┌──▼──┐  ┌────▼────┐  ┌────▼────┐  ┌───▼───┐  ┌───▼───┐
  │A1   │  │A2       │  │A3       │  │B1..B9 │  │       │
  │Refac│  │Refac    │  │Refac    │  │Refac  │  │       │
  └──┬──┘  └────┬────┘  └────┬────┘  └───┬───┘  └───┬───┘
     └───────────┴────────────┴───────────┴──────────┘
                 │
     ┌───────────▼───────────┐
     │   VALIDATION GATE 2   │  ← Agent-Val: 0 string hardcoded? build OK?
     └───────────┬───────────┘
                 │
Phase 3 (PARALLÈLE — 5 agents QA)
     ┌───────────┼───────────────────────┐
     │           │                       │
  ┌──▼──┐  ┌───▼───┐  ┌───▼───┐  ┌───▼───────┐  ┌───▼───────┐
  │QA-FR│  │QA-EN  │  │QA-AR  │  │Cohérence  │  │Val Tech   │
  └──┬──┘  └───┬───┘  └───┬───┘  └───┬───────┘  └───┬───────┘
     └──────────┴──────────┴───────────┴───────────┘
                 │
     ┌───────────▼───────────┐
     │   VALIDATION GATE 3   │  ← Tous QA passent?
     └───────────┬───────────┘
                 │
           ┌─────▼─────┐
           │  ÉCHEC ?  │
           └─────┬─────┘
            OUI  │  NON
     ┌──────────┘  └──────────┐
     │                        │
Phase 4 (Boucle)          ✅ TERMINÉ
     │
     ▼
  Agent concerné corrige
     │
     ▼
  Retour Phase 3 (re-QA)
```

---

## Détails techniques clés

### 1. Configuration i18next

```typescript
// src/i18n/index.ts
import i18n from 'i18next'
import { initReactI18next } from 'react-i18next'
import LanguageDetector from 'i18next-browser-languagedetector'

// Import lazy des namespaces
const resources = {
  fr: {
    common: () => import('./locales/fr/common.json'),
    nav: () => import('./locales/fr/nav.json'),
    // ... 12 namespaces
  },
  en: { /* ... */ },
  ar: { /* ... */ },
}

i18n
  .use(LanguageDetector)
  .use(initReactI18next)
  .init({
    fallbackLng: 'fr',
    supportedLngs: ['fr', 'en', 'ar'],
    ns: ['common', 'nav', 'auth', 'sales', 'purchases', 'accounting',
         'banking', 'treasury', 'stock', 'production', 'hr', 'reports', 'settings', 'errors'],
    defaultNS: 'common',
    interpolation: { escapeValue: false },
    detection: {
      order: ['localStorage', 'navigator'],
      lookupLocalStorage: 'i18nextLng',
      caches: ['localStorage'],
    },
  })
```

### 2. Hook useLocale

```typescript
// src/i18n/hooks/useLocale.ts
import { useTranslation } from 'react-i18next'

const LOCALE_MAP = {
  fr: 'fr-FR',
  en: 'en-US',
  ar: 'ar-MA', // ou ar-SA selon préférence
}

export function useLocale() {
  const { i18n } = useTranslation()
  const locale = LOCALE_MAP[i18n.language] || 'fr-FR'

  return {
    locale,
    formatCurrency: (amount: number, currency = 'EUR') =>
      new Intl.NumberFormat(locale, { style: 'currency', currency, minimumFractionDigits: 2 }).format(amount),
    formatDate: (date: string | Date) =>
      new Intl.DateTimeFormat(locale, { day: '2-digit', month: '2-digit', year: 'numeric' }).format(date),
    formatNumber: (num: number) =>
      new Intl.NumberFormat(locale).format(num),
  }
}
```

### 3. Support RTL

```typescript
// Dans Layout.tsx ou un hook dédié
useEffect(() => {
  const dir = i18n.language === 'ar' ? 'rtl' : 'ltr'
  document.documentElement.dir = dir
  document.documentElement.lang = i18n.language
}, [i18n.language])
```

CSS additions nécessaires:
```css
[dir="rtl"] .sidebar { /* ajustements miroir */ }
[dir="rtl"] table { direction: rtl; }
[dir="rtl"] .modal { /* ajustements */ }
```

### 4. Structure des clés de traduction (exemple)

```json
// fr/common.json
{
  "status": {
    "draft": "Brouillon",
    "sent": "Envoyée",
    "paid": "Payée",
    "overdue": "En retard",
    "cancelled": "Annulée"
  },
  "actions": {
    "save": "Enregistrer",
    "cancel": "Annuler",
    "delete": "Supprimer",
    "edit": "Modifier",
    "create": "Créer",
    "search": "Rechercher",
    "export": "Exporter",
    "import": "Importer",
    "close": "Fermer",
    "confirm": "Confirmer",
    "back": "Retour",
    "next": "Suivant",
    "previous": "Précédent"
  },
  "table": {
    "empty": "Aucune donnée",
    "loading": "Chargement...",
    "results": "{{count}} résultat(s)",
    "actions": "Actions",
    "all": "Tous"
  },
  "toast": {
    "success": "Opération réussie",
    "error": "Une erreur est survenue",
    "warning": "Attention",
    "info": "Information"
  }
}
```

```json
// en/common.json
{
  "status": {
    "draft": "Draft",
    "sent": "Sent",
    "paid": "Paid",
    "overdue": "Overdue",
    "cancelled": "Cancelled"
  },
  "actions": {
    "save": "Save",
    "cancel": "Cancel",
    "delete": "Delete",
    "edit": "Edit",
    "create": "Create",
    "search": "Search",
    "export": "Export",
    "import": "Import",
    "close": "Close",
    "confirm": "Confirm",
    "back": "Back",
    "next": "Next",
    "previous": "Previous"
  }
}
```

```json
// ar/common.json
{
  "status": {
    "draft": "مسودة",
    "sent": "مرسلة",
    "paid": "مدفوعة",
    "overdue": "متأخرة",
    "cancelled": "ملغاة"
  },
  "actions": {
    "save": "حفظ",
    "cancel": "إلغاء",
    "delete": "حذف",
    "edit": "تعديل",
    "create": "إنشاء",
    "search": "بحث",
    "export": "تصدير",
    "import": "استيراد",
    "close": "إغلاق",
    "confirm": "تأكيد",
    "back": "رجوع",
    "next": "التالي",
    "previous": "السابق"
  }
}
```

---

## Estimation des efforts

| Phase | Agents | Durée estimée | Parallélisme |
|-------|--------|---------------|--------------|
| Phase 0: Infrastructure | 1 | 1 session | Séquentiel |
| Phase 1: Extraction FR | 12 | 3-4 sessions | 12 en parallèle |
| Phase 1b: Traduction EN/AR | 3 | 2-3 sessions | 3 en parallèle |
| Phase 2: Refactoring | 12 | 4-5 sessions | 12 en parallèle |
| Phase 3: QA & Validation | 5 | 2 sessions | 5 en parallèle |
| Phase 4: Corrections | variable | 1-2 sessions | Itératif |
| **Total** | **~33 agents** | **~13-17 sessions** | |

---

## Checklist finale de validation

- [ ] `npm run build` réussit sans erreur TypeScript
- [ ] `oxlint` passe sans warning
- [ ] Aucune chaîne française hardcoded dans le code (grep vérifié)
- [ ] Les 36 fichiers JSON de traduction sont complets (12 namespaces × 3 langues)
- [ ] Aucune clé de traduction manquante (i18next debug mode sans warning)
- [ ] Changement de langue fonctionne instantanément sans reload
- [ ] La langue persiste après reload (localStorage)
- [ ] RTL correct en arabe (layout, tables, modales, formulaires)
- [ ] Formatage des dates adapté à la locale
- [ ] Formatage des devises adapté à la locale
- [ ] Formatage des nombres adapté à la locale
- [ ] LanguageSwitcher visible et accessible depuis toutes les pages
- [ ] Navigation (sidebar) entièrement traduite
- [ ] Breadcrumbs traduits
- [ ] Titres de pages traduits
- [ ] Tous les formulaires traduits (labels, placeholders, boutons)
- [ ] Tous les tableaux traduits (en-têtes, statuts, actions)
- [ ] Tous les messages toast traduits
- [ ] Tous les messages d'erreur traduits
- [ ] Tous les tooltips et aria-labels traduits
- [ ] Pages d'authentification traduites (login, signup, onboarding)
- [ ] Modales traduites
- [ ] Composant AIAssistant traduit
- [ ] CommandPalette traduit
- [ ] Cohérence terminologique vérifiée (glossaire respecté)
