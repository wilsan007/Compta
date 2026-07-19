# Sage.com - Analyse Complète de l'Écosystème, UI/UX, Modules et Workflows

> Document de référence compilé à partir de scraping approfondi de sage.com, pages de documentation, design system, et ressources partenaires.
> Date: Juillet 2026

---

## TABLE DES MATIÈRES

1. [Vue d'ensemble de l'écosystème Sage](#1-vue-densemble-de-lécosystème-sage)
2. [Produits Sage - Catalogue complet](#2-produits-sage---catalogue-complet)
3. [Architecture modulaire par produit](#3-architecture-modulaire-par-produit)
4. [Structure de navigation et UI/UX](#4-structure-de-navigation-et-uiux)
5. [Design System Sage](#5-design-system-sage)
6. [Dashboards et Workspaces](#6-dashboards-et-workspaces)
7. [Workflows et process flows](#7-workflows-et-process-flows)
8. [Sage Copilot - IA intégrée](#8-sage-copilot---ia-intégrée)
9. [Modules détaillés par produit](#9-modules-détaillés-par-produit)
10. [Recommandations pour notre application](#10-recommandations-pour-notre-application)

---

## 1. VUE D'ENSEMBLE DE L'ÉCOSYSTÈME SAGE

Sage est un leader mondial des logiciels de comptabilité, finance, RH et paie pour les PME. L'écosystème Sage couvre:

- **Comptabilité et finances** (Sage Accounting, Sage 50, Sage Intacct, Sage X3)
- **Paie et RH** (Sage Payroll, Sage HR, Sage People)
- **ERP et gestion d'entreprise** (Sage X3, Sage 100, Sage 300)
- **CRM** (Sage CRM intégré)
- **Intelligence artificielle** (Sage Copilot - intégré dans tous les plans)
- **Plateforme cloud** (Sage Business Cloud)
- **Durabilité** (Sage Earth Carbon Accounting)

### Marchés ciblés
- **Micro-entreprises / Auto-entrepreneurs** → Sage Accounting Start
- **Petites entreprises** → Sage Accounting Standard, Sage 50
- **Entreprises moyennes** → Sage 100, Sage Intacct
- **Grandes entreprises / Multi-entités** → Sage X3, Sage Intacct
- **Industries spécifiques** → Manufacturing, Distribution, Construction, Food & Beverage

---

## 2. PRODUITS SAGE - CATALOGUE COMPLET

### 2.1 Sage Accounting (Cloud - UK/Europe)
- **Cible**: Petites entreprises, auto-entrepreneurs
- **Déploiement**: 100% Cloud (web + mobile app)
- **Plans**: Start, Standard, Plus
- **IA**: Sage Copilot inclus dans tous les plans
- **Paie intégrée**: Sage Payroll inclus sans coût supplémentaire
- **Carbon**: Sage Earth Carbon Accounting inclus

### 2.2 Sage 50 Accounts (Desktop + Cloud)
- **Cible**: Petites et moyennes entreprises
- **Déploiement**: Desktop avec composants cloud
- **Éditions**: Complete, Premium, Quantum
- **Modules**: GL, AR, AP, Bank Rec, Inventory, Sales Order, Purchase Order, Job Cost
- **Paie**: Module séparé (Sage 50 Payroll)

### 2.3 Sage 100 (ERP - US)
- **Cible**: PME en croissance
- **Déploiement**: On-premise ou cloud-hosted
- **Éditions**: Standard, Advanced, Premium
- **Modules core**: GL, AP, AR, Bank Rec, Paperless Office, Credit Card Processing
- **Modules avancés**: Purchase Order, Sales Order, Inventory Management, Returns, BOM, Bar Coding
- **Add-ons**: Production, IRP, Payroll, Time Track, Job Costing, Fixed Assets, Sage CRM

### 2.4 Sage Intacct (Cloud ERP - US/Global)
- **Cible**: PME, organisations multi-entités
- **Déploiement**: 100% Cloud SaaS
- **Modules core**: AP, AR, Cash Management, General Ledger, Order Management, Purchasing, Reports, Dashboards
- **Modules additionnels**: Consolidations, Project Accounting, Spend Management, Budgeting & Forecasting, Fixed Assets, Time & Expense, Revenue Recognition, Inventory, Dynamic Allocations, Grant Tracking, ICRW, IVE
- **Multi-entité**: Consolidation de centaines d'entités, multi-devises

### 2.5 Sage X3 (ERP Enterprise)
- **Cible**: Entreprises moyennes à grandes, industries productiques
- **Déploiement**: Cloud, Private Cloud, On-premise
- **Plateformes**: Finance, Distribution (incl. Finance), Manufacturing (incl. Distribution + Finance)
- **Modules**: Financial Management, Supply Chain Management, Manufacturing, Project Management, Reporting & Business Analytics
- **Multi**: Multi-company, multi-site, multi-currency, multi-ledger, multi-legislation, multi-language
- **Industries**: Manufacturing, Distribution, Food & Beverage, Chemicals, Pharmaceuticals

### 2.6 Sage Payroll (Cloud)
- **Cible**: Petites et moyennes entreprises
- **Plans**: Essentials, Standard, Premium
- **Intégration**: Automatique avec Sage Accounting
- **Conformité**: HMRC recognised, RTI, Auto-enrolment
- **RH inclus**: HR Essentials, Core HR, Leave Management, Timesheets, Shift Scheduling, Expenses, Performance Management, Recruitment

### 2.7 Sage HR
- **Cible**: Gestion RH intégrée
- **Modules**: Employee records, Leave management, Onboarding, Performance, Recruitment, Timesheets, Shift scheduling, Expenses, Documents, E-signatures, Company directory, Announcements

### 2.8 Sage People (HR Enterprise)
- **Cible**: Entreprises moyennes à grandes
- **Déploiement**: Cloud (Salesforce platform)

### 2.9 Sage CRM
- **Intégration**: Intégré avec Sage 100, Sage 300, Sage X3
- **Modules**: Sales opportunities, Marketing, Customer service, Pipeline management

### 2.10 Sage Copilot (IA)
- **Disponibilité**: Sage Accounting, Sage Active, Sage Intacct, Sage 50, Sage for Accountants, Sage X3
- **Fonctionnalités**: Automation, Business insights, Compliance & accuracy, Conversational AI, Anomaly detection, Forecasting

### 2.11 Sage Earth (Carbon Accounting)
- **Intégration**: Inclus dans tous les plans Sage Accounting
- **Fonctionnalités**: Carbon footprint tracking, Emissions estimation, Sustainability reporting

---

## 3. ARCHITECTURE MODULAIRE PAR PRODUIT

### 3.1 Sage Accounting (Cloud) - Modules Menu

#### Navigation principale (onglets/barre de menu)
```
┌─────────────────────────────────────────────────────────────────┐
│  [Logo]  Home  Sales  Purchases  Banking  Reporting  Settings  │
│                                          [?] [Profile] [Bell]  │
└─────────────────────────────────────────────────────────────────┘
```

**Onglet HOME (Dashboards)**
- Main Company Dashboard
- Customer Dashboard
- Supplier Dashboard
- Item Dashboard
- Financial Dashboard
- My Workspace (personnalisable)

**Onglet SALES (Customers)**
- Lists: Customers, Products/Services (vente)
- Transactions: Quotes & Estimates, Sales Invoices, Sales Credits, Quick Entries, Recurring Invoices
- Reports: Customer reports, Sales reports
- Fonctionnalités: Invoicing, Chase Debt, Customer statements, Late Payment charges, Cash Register, Opayo Integration, Foreign Trade, Invoice payments

**Onglet PURCHASES (Suppliers/Vendors)**
- Lists: Suppliers, Products/Services (achat)
- Transactions: Purchase Invoices, Purchase Credits, Quick Entries
- Reports: Supplier reports, Purchase reports
- Fonctionnalités: Batch invoices, Supplier statements, Manage payments, CIS/subcontractors, Supplier price lists, Purchase order processing, Foreign Trade

**Onglet BANKING**
- Lists: Bank accounts, Credit cards, Cash accounts
- Transactions: Bank payments, Bank receipts, Bank transfers, Recurring entries, Cheques
- Reports: Bank reports, Reconciliation reports
- Fonctionnalités: Bank feeds, Bank rules, Bank reconciliation, Create refunds from bank feeds, Receipts and Payments Day Book

**Onglet REPORTING**
- Essential Reports: Profit & Loss, Balance Sheet, Trial Balance, Cash Flow Statement, Cash Flow Forecast
- Detailed Reports: General Ledger, Nominal Activity, Audit Trail
- Cash Reports: Cash flow, Money in/out
- Advanced Reports (Standard/Plus): Custom analysis types (project, department), Tag-based comparisons, Saved customised reports
- Export: Excel, CSV, PDF
- Tax: VAT Return, GST/HST Return, Tax Returns

**Onglet SETTINGS**
- About your Business (company details)
- Financial Settings: Chart of Accounts, Currencies, Record & Transaction Settings
- Invoicing & Business: Templates and Logos, Document Preferences
- Connect: Bank feeds, Stripe, PayPal, Paya, GoCardless
- Customise: Navigation & Data Grids, Personalise
- Opening Balances
- User Management: Users, Access rights, Roles
- Card Payments
- Tax settings

**Onglet JOURNALS**
- New Journal
- Journal list
- Recurring journals

**Onglet PRODUCTS & SERVICES**
- Products (stock items): Track quantity and revenue
- Services (non-stock items)
- Advanced Inventory: Stock movements, Stock adjustments, Import stock balances

**Onglet PROJECTS** (Standard/Plus)
- Project tracking
- Project profitability
- Time tracking (add-on)

### 3.2 Sage 50 - Modules (Vue Enhanced)

```
┌──────────────────────────────────────────────────────────────┐
│  [Navigation Bar - Left side]                                │
│                                                              │
│  📊 My Dashboard (customizable)                              │
│  👥 Customers & Sales                                        │
│  🏢 Vendors & Purchases                                      │
│  📦 Inventory & Services                                     │
│  👤 Employees & Payroll (includes Time Slips)                │
│  📁 Projects                                                 │
│  🏦 Banking                                                  │
│  🏛️ Company (includes Accounts)                             │
└──────────────────────────────────────────────────────────────┘
```

**Vue Classic - Modules**
- General Accounting
- Vendors and Purchases
- Customers and Sales
- Payroll
- Inventory and Services
- Projects
- Time and Billing (Premium only)
- My Business (Reports Center + Daily Business Manager)

**Chaque module contient:**
- Icônes organisées en diagrammes de flux de tâches (task flow diagrams)
- Record windows (fenêtres d'enregistrement)
- Transaction windows (fenêtres de transaction)
- Reports spécifiques au module

### 3.3 Sage 100 - Modules complets

**Core Financials**
- General Ledger: Budgets illimités, périodes multiples, reporting détaillé
- Accounts Payable: Gestion vendors, ACH/checks/electronic, tax calculations, PO links
- Accounts Receivable: Billing, invoicing, collections, credit checks, recurring invoices, commission tracking
- Bank Reconciliation: Rapprochement bancaire, bank feeds automatisés
- Paperless Office: Documents électroniques
- Credit Card Processing & E-invoicing: Payments électroniques, click-to-pay
- Visual Integrator: Intégration de données entre systèmes
- Custom Office: Champs personnalisés, écrans personnalisés, workflows
- Sage CRM: Gestion relations clients, sales opportunities, marketing

**Advanced Modules**
- Purchase Order: Procurement automatisé, vendor performance, PO tracking
- Sales Order: Order entry, fulfillment, invoicing, backorders, credit limits
- Inventory Management: Stock levels, lot/serial/location tracking, reorder points
- Purchasing: Vendor relationships, POs, approvals, cost tracking
- Returns: Product returns tracking, reasons, credits/replacements
- RMA: Return Merchandise Authorization
- Bill of Materials (BOM): Product structures, component requirements, production costs
- Mobility for Bar Coding: Barcode scanning, mobile data capture, warehouse operations

**Add-on Modules**
- Production: Shop floor operations, labor/materials tracking, work orders
- Inventory Requirements Planning (IRP): Demand analysis, replenishment automation
- Payroll: Employee payments, tax compliance, direct deposits, W-2 e-filing
- Time Track: Employee hours, PTO, sick leave, job costing integration
- Job Costing: Project expenses, revenue, profitability, estimated vs actual
- Sage Fixed Assets: Asset tracking, depreciation automation, tax reporting

### 3.4 Sage Intacct - Modules complets

**Core Modules**
- Accounts Payable
- Accounts Receivable
- Cash Management
- General Ledger
- Order Management
- Purchasing
- Reports
- Dashboards

**Additional Modules**
- Global & Domestic Consolidations: Multi-entité, multi-devises
- Project Accounting: Coûts projet, temps, expenses, billing
- Spend Management: Budget controls, spending tracking, multi-dimensional reporting
- Planning, Budgeting & Forecasting: Budgets, scénarios what-if, formulas
- Fixed Assets Management: Asset tracking, depreciation automatique
- Time and Expense Management: Time tracking, expense tracking, real-time visibility
- Revenue Recognition: Reconnaissance de revenus automatisée
- Inventory Management: Gestion d'inventaire
- Dynamic Allocations: Allocations dynamiques
- Grant Tracking and Billing: Suivi de subventions
- Interactive Custom Report Writer (ICRW): Reports personnalisés interactifs
- Interactive Visual Explorer (IVE): Visualisation de données interactive

### 3.5 Sage X3 - Modules complets

**Financial Management**
- General Ledger
- Accounts Payable / Accounts Receivable / Cash
- Cash Management
- Cost Accounting
- Expenditures
- Budget and Commitments
- Financial Reporting
- Fixed Asset Management

**Supply Chain Management**
- Inventory Management
- Sales Management
- Customer Service
- Purchasing
- Advanced Purchasing Costs Management
- Logistics
- Inter-company/inter-site transactions
- Mobile Automation (handheld devices)

**Manufacturing**
- Production Planning
- Scheduling
- Work Orders
- Bill of Materials (BOM) - multi-BOMs
- Shop Floor Control
- Quality Management
- Material Requirements Planning (MRP)
- Master Production Scheduling (MPS)

**Project Management**
- Project breakdown structures
- Project cost breakdown structures
- Budget tracking
- Multi-level project management

**Reporting and Business Analytics**
- Business Intelligence
- Custom reports
- Dashboards
- Data visualization

**User Workspace**
- Landing pages par rôle
- Mega Menu
- Sitemap
- Bookmarks
- Navigation trail (breadcrumb)

**Administration and Support**
- User management
- Security
- Customization
- APIs & Web services

**Cloud Connectivity**
- GraphQL APIs
- Low-code platform
- Upgrade-safe customizations

---

## 4. STRUCTURE DE NAVIGATION ET UI/UX

### 4.1 Sage Business Cloud Accounting - Navigation

```
┌──────────────────────────────────────────────────────────────────────┐
│  [Logo Sage]  Home  Sales  Purchases  Banking  Reporting  Settings   │
│                                              [?]  [👤 Profile]  [🔔] │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  (a) Main navigation = row of tabs → major areas                     │
│  (b) Profile menu = edit profile, feedback, sign out                 │
│  (c) Subscription/business account management                        │
│  (d) Quick links to task views in each section                       │
│  (e) Question mark = contextual help guide                           │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

**Trois zones de navigation principales:**
1. **Dashboard / Workspace** - Vue d'ensemble personnalisable
2. **Menu Bar** - Navigation horizontale par onglets (Home, Sales, Purchases, Banking, Reporting, Settings)
3. **Banner Bar** - Profil, notifications, aide, gestion abonnement

**Dashboards disponibles (menu Home):**
1. Main Company Dashboard (vue d'ensemble financière)
2. Customer Dashboard (infos clients, ventes, créances)
3. Supplier Dashboard (infos fournisseurs, achats, dettes)
4. Item Dashboard (produits, stock, ventes par produit)
5. Financial Dashboard (santé financière, P&L, balance sheet, cash flow)
6. My Workspace (personnalisable avec widgets)

### 4.2 Sage 50 - Navigation

```
┌────────────────────────────────────────────────────────────────────┐
│  [Menu Bar: File | Edit | View | Tasks | Analyze | Report | Help] │
├────────────┬───────────────────────────────────────────────────────┤
│            │                                                       │
│ Navigation │   Main Work Area                                      │
│ Bar        │                                                       │
│            │   Three view modes:                                   │
│ 📊 My      │   1. List display                                     │
│    Dashboard│   2. Process map (workflow visuel avec icônes)       │
│ 👥 Customers│   3. Dashboard (KPIs, graphiques)                    │
│ 🏢 Vendors │                                                       │
│ 📦 Inventory│                                                       │
│ 👤 Employees│                                                       │
│ 📁 Projects │                                                       │
│ 🏦 Banking  │                                                       │
│ 🏛️ Company │                                                       │
│            │                                                       │
├────────────┴───────────────────────────────────────────────────────┤
│  [Status Bar]                                                      │
└────────────────────────────────────────────────────────────────────┘
```

**Navigation Bar (gauche):**
- Modules organisés par domaine fonctionnel
- Chaque module = page avec icônes de tâches
- Click-droit pour définir une page par défaut
- Customizable: masquer/afficher modules

**Process Maps:**
- Diagrammes de flux visuels montrant le processus comptable
- Icônes cliquables pour accéder directement à une étape
- Navigation visuelle entre modules liés

### 4.3 Sage Intacct - Navigation

```
┌──────────────────────────────────────────────────────────────────────┐
│  [Sage Intacct]  [Search bar]                    [🔔] [👤 User menu] │
├──────────────────────────────────────────────────────────────────────┤
│  Dashboards | Company | General Ledger | Accounts Receivable |      │
│  Accounts Payable | Cash Management | Purchasing | Order Entry |    │
│  Time & Expenses | Projects | Inventory | Fixed Assets | Platform  │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Dashboard Area (customizable grid)                                  │
│  ┌─────────┬─────────┬─────────┐                                    │
│  │ Card    │ Card    │ Card    │  ← Performance cards (KPIs)        │
│  ├─────────┴─────────┼─────────┤                                    │
│  │ Chart             │ Report  │  ← Charts & Reports                │
│  ├───────────────────┼─────────┤                                    │
│  │ List/Approvals    │ Links   │  ← Action lists & Smart links      │
│  └───────────────────┴─────────┘                                    │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

**Menu principal (navigation horizontale en haut):**
- Dashboards
- Company
- General Ledger
- Accounts Receivable
- Accounts Payable
- Cash Management
- Purchasing
- Order Entry
- Time & Expenses
- Projects
- Inventory
- Fixed Assets
- Platform Services

**Sous-navigation par module:**
- All (vue d'ensemble)
- Lists (listes d'enregistrements)
- Transactions (transactions)
- Reports (rapports spécifiques)

### 4.4 Sage X3 - Navigation

```
┌──────────────────────────────────────────────────────────────────────┐
│  [Sage X3]  [Mega Menu ▼]  [Search]  [Breadcrumb Trail]  [👤] [🔔] │
├────────────┬─────────────────────────────────────────────────────────┤
│            │                                                         │
│  Landing   │   Main Work Area                                        │
│  Pages     │                                                         │
│  (left     │   ┌─────────────────────────────────────────────┐      │
│  panel)    │   │                                             │      │
│            │   │  Selected function/page content              │      │
│  - Role1   │   │                                             │      │
│  - Role2   │   │                                             │      │
│  - Role3   │   │                                             │      │
│  + New...  │   └─────────────────────────────────────────────┘      │
│            │                                                         │
├────────────┴─────────────────────────────────────────────────────────┤
│  [Sitemap]  [Bookmarks]                                   [Status]   │
└──────────────────────────────────────────────────────────────────────┘
```

**Éléments de navigation Sage X3:**
1. **Landing Pages** (panneau gauche) - Pages d'accueil par rôle avec KPIs et processus métier
2. **Mega Menu** (en-tête) - Accès à toutes les fonctions via menu hiérarchique (Common data → Products category → Products)
3. **Sitemap** (bas de page) - Carte complète de tous les menus et entrées, recherche avec CTRL+F
4. **Navigation Trail** - Breadcrumb trail pour revenir aux pages précédentes
5. **Bookmarks** - Ajout d'items aux favoris depuis le sitemap
6. **Short-cut keys**:
   - ESC + F11 = Full Screen
   - ESC + F6 = Field/screen name, data type info
   - ESC + F1 = Help contextuel
   - ESC + F7 = Direct Call / Search / History

---

## 5. DESIGN SYSTEM SAGE

### 5.1 Couleurs

**Philosophie**: Les couleurs sont utilisées avec parcimonie pour garder les utilisateurs concentrés. La couleur met en évidence les informations importantes, attire l'attention sur les actions, et améliore la lisibilité.

**Palettes:**

| Palette | Usage |
|---------|-------|
| **Neutral** | Texte et bordures, drop-shadows, composants d'interface |
| **Primary** | Éléments cliquables, états sélectionnés |
| **Success** | Actions positives, confirmations (vert) |
| **Warning** | Avertissements, attention requise (jaune) |
| **Danger** | Erreurs, suppressions, alertes critiques (rouge) |
| **Supporting** | Accents visuels secondaires |

**Tokens de couleur pour texte:**
- `t-sage--color-primary-300`
- `t-sage--color-grey-600`
- `t-sage--color-red-600`
- `t-sage--color-mercury-500`
- `t-sage--color-yellow-400`
- `t-sage--color-green-600`
- `t-sage--color-purple-600`

### 5.2 Typographie

**Système**: Échelle modulaire major second (facteur 1.125), base 14px (desktop) / 16px (mobile)

| Type Spec | Weight | Kerning | Desktop (size/line) | Mobile (size/line) | Usage |
|-----------|--------|---------|---------------------|---------------------|-------|
| H1 | 700 | -0.6px | 40px / 48px | 40px / 48px | Titres principaux |
| H2 | 700 | -0.5px | 32px / 40px | 32px / 40px | Titres de section |
| H3 | 700 | -0.15px | 28px / 32px | 28px / 32px | Sous-titres |
| H4 | 600 | -0.15px | 24px / 32px | 24px / 32px | Titres de carte |
| H5 | 600 | 0px | 18px / 28px | 18px / 28px | Titres secondaires |
| H6 | 600 | 0px | 16px / 28px | 16px / 28px | Labels importants |
| Body | 400 | 0px | 16px / 24px | 16px / 24px | Texte courant |
| Small | 400 | 0px | 14px / 20px | 14px / 20px | Texte secondaire |
| Caption | 400 | 0px | 12px / 16px | 12px / 16px | Légendes, métadonnées |

**Classes CSS**: `t-sage-` prefix pour les styles typographiques

### 5.3 Espacement (Spacing)

| Token | Valeur | Usage |
|-------|--------|-------|
| 2xs | 4px | Micro-espacement (stacks de contenu) |
| xs | 8px | Espacement minimal (listes, paragraphes) |
| sm | 16px | Espacement standard entre éléments |
| md | 24px | Espacement au niveau carte |
| lg | 32px | Espacement au niveau panneau |
| xl | 48px | Espacement au niveau application (page heading) |

**Tiers d'espacement:**
- **Application-level**: 48px (éléments fondamentaux de page, page heading)
- **Panel-level**: 32px (groupes d'éléments, panneaux)
- **Card-level**: 24px (composants carte, groupes de contenu)
- **Stack-level**: 8px (blocs de paragraphes, items de liste)

### 5.4 Composants UI

**Composants principaux:**
- **Nav** - Navigation hiérarchique verticale avec items de menu imbriqués (SageNav)
- **Cards** - Conteneurs de contenu avec espacement card-level
- **Buttons** - Actions primaires, secondaires, tertiaires
- **Forms** - Champs de saisie, labels, validation
- **Tables/Data Grids** - Grilles de données avec tri, filtrage, pagination
- **Charts** - Graphiques (line, bar, pie, combo)
- **Performance Cards** - Cartes KPI avec valeur unique
- **Lists** - Listes d'enregistrements avec actions
- **Approvals** - Composants d'approbation intégrés au dashboard
- **Smart Links** - Liens de navigation rapide
- **Message Boards** - Messages administrateur
- **Calendars** - Composants calendrier
- **RSS Feeds** - Flux d'actualités
- **Attachments** - Conteneurs de pièces jointes

**Technologies:**
- Rails et React (composants disponibles dans les deux)
- Design tokens: CSS, SCSS, JSON
- Style Dictionary + Tokens Studio
- Figma pour la documentation de design

---

## 6. DASHBOARDS ET WORKSPACES

### 6.1 Sage Accounting - Dashboards

**Main Company Dashboard:**
- Vue d'ensemble financière
- Cash flow graphique
- Income vs Expenses
- Quick stats: bank balance, overdue invoices, bills to pay
- Liens rapides vers actions courantes

**Customer Dashboard:**
- Top customers (graphique)
- Aged debtors (créances par ancienneté)
- Total owed, overdue amounts
- Customer activity feed
- Quick actions: new invoice, chase debt

**Supplier Dashboard:**
- Top suppliers (graphique)
- Aged creditors (dettes par ancienneté)
- Total owed to suppliers
- Supplier activity feed
- Quick actions: new purchase invoice, make payment

**Item Dashboard:**
- Top selling products
- Stock levels alerts (low stock)
- Stock valuation
- Sales by product
- Quick actions: new product, adjust stock

**Financial Dashboard:**
- Profit & Loss summary
- Balance sheet snapshot
- Cash flow statement & forecast
- Income vs Expenses graph
- Drill-down vers reports détaillés
- VAT liability overview
- Carbon emissions estimate

**My Workspace:**
- Widgets personnalisables ("What do you need to do today?")
- Bouton "Customise" pour ajouter/retirer widgets
- Widgets: tasks, reminders, quick links, to-do lists
- Organisation en colonnes (1 ou 2 selon taille écran)

### 6.2 Sage Intacct - Dashboards

**Structure des dashboards:**
- Grille personnalisable (colonnes ajustables)
- Drag & drop pour repositionner les composants
- Filtrage par dimensions
- Refresh par composant ou global (F5)
- Drill-down depuis graphiques vers données détaillées
- Vue collapsible par composant

**Types de composants:**

| Type | Composants |
|------|-----------|
| **Performance Cards** | KPI unique (Cash Balance, DSO, Revenue, Margin, Expenses) |
| **Charts** | Line, Bar, Pie, Combo - tendances, comparaisons |
| **Reports** | Financial reports, memorized reports, custom reports |
| **Lists** | Listes d'enregistrements (AP invoices, customers, etc.) |
| **Records** | Enregistrement unique fréquemment consulté |
| **Queries** | Listes personnalisées avec requêtes |
| **Approvals** | Approvals AP, expenses, journal entries - approbation directe |
| **Smart Links** | Liens de navigation rapide vers pages |
| **General** | Calendars, message boards, news feeds, shortcuts, billboards |
| **Collaborate** | Commentaires et collaboration intégrés |

**Dashboards par rôle (exemples):**

| Rôle | Cards | Charts | Reports | Lists |
|------|-------|--------|---------|-------|
| **CFO** | Cash, Revenue, Margin | 12-month revenue, Cash flows | P&L, Balance Sheet | Overdue invoices, Payments |
| **Controller** | Close progress, Open entries | Dept variances, AP/AR trends | Exceptions, Accruals | Unposted entries, Bank rec errors |
| **Ops Manager** | Budget left, Open POs | Expenses vs budget, Pipeline | Budget details | Pending expenses, Vendor bills |
| **Project Manager** | Utilization, Margin, WIP | Revenue by project, Hours by staff | Project results, Unbilled | Timecards for approval, Change orders |
| **Grant Manager** | Grant balance, Budget vs spend | Expenses, Funding mix | Activities by program | Pending approvals, Due reports |

**Best practices Intacct dashboards:**
- Limiter à 8-12 composants
- Top: 2-4 performance cards (pulse metrics)
- Middle: 1-2 charts (tendances)
- Bottom: Action lists ou deep-dive reports
- Utiliser trend charts plutôt que stats ponctuelles
- Color code pour les KPIs
- Lises limitées à top 10 items
- Mise à jour trimestrielle

### 6.3 Sage 50 - Dashboard

**My Dashboard (Quantum uniquement):**
- Personnalisable par rôle (AR manager voit customers/invoices, etc.)
- Sections ajoutables par zone fonctionnelle
- Réorganisation (Move Up/Down)
- Renommage des sections
- Affichage en 1 ou 2 colonnes selon taille écran
- Onglets additionnels possibles (Add new tab)
- Définir comme page par défaut
- Sécurité: sections basées sur les permissions utilisateur

**Business Dashboards (v28+):**
- Données clés business en un coup d'œil
- Aged debtors/creditors
- Top customers
- Stock movements
- Accès depuis navigation bar

**Process Maps:**
- Vue visuelle du workflow par module
- Icônes cliquables pour chaque étape du processus
- Navigation directe vers l'étape souhaitée
- Exemple Suppliers: Purchase Order → Receive Goods → Invoice → Pay → Reconcile

---

## 7. WORKFLOWS ET PROCESS FLOWS

### 7.1 Sales Process (Order to Cash)

```
Sales Order → Sales Shipment → Sales Invoice → Sales Credit Note
                                         ↗
Sales Order → Sales Shipment → Sales Invoice → Sales Return Request
                                                         ↓
                                            Sales Return Receipt
                                                     and/or
                                            Sales Credit Note
```

**Étapes détaillées:**
1. **Order Entry** - Création de la commande client
2. **Credit Review** - Vérification du crédit client
3. **Order Fulfillment** - Préparation/expédition
4. **Shipping** - Livraison
5. **Invoicing & Billing** - Facturation
6. **Accounts Receivable** - Suivi des créances
7. **Payment Collection** - Encaissement
8. **Cash Application** - Rapprochement
9. **Reporting** - Reporting et analyse

**Rôles impliqués:**
- Sales administrators: Sales orders, return requests
- Inventory operators: Sales shipments, return receipts
- AR clerks: Invoices, credit notes

### 7.2 Purchase Process (Procure to Pay)

```
Purchase Requisition → Purchase Order → Goods Receipt → Purchase Invoice
                                                         ↓
                                                    Payment
                                                         ↓
                                                  Bank Reconciliation
```

### 7.3 Banking Process

```
Connect Bank Account → Import Bank Statement (Bank Feed)
                              ↓
                    Bank Rules (auto-categorization)
                              ↓
                    Bank Reconciliation
                              ↓
                    Match Transactions
                              ↓
                    Clear/Post to Ledger
```

### 7.4 Payroll Process

```
Employee Setup → Time Tracking → Pay Run Processing
                                      ↓
                              Calculate Wages/Tax/NI/Pension
                                      ↓
                              Review & Approve
                                      ↓
                              Submit RTI to HMRC
                                      ↓
                              Post Salary Journal → Sage Accounting
                                      ↓
                              Generate Payslips → Employee Self-Service
```

### 7.5 VAT/Tax Process

```
Record Transactions → VAT Calculation → VAT Return
                                             ↓
                                    Sage Copilot Review (anomaly check)
                                             ↓
                                    Submit to HMRC
                                             ↓
                                    Pay VAT
```

### 7.6 Period End / Month-End Close

```
Reconcile Bank Accounts
        ↓
Post Adjusting Journals (accruals, prepayments, depreciation)
        ↓
Review Aged Debtors/Creditors
        ↓
VAT Return Submission
        ↓
Run Management Reports (P&L, Balance Sheet, Trial Balance)
        ↓
Close Period
        ↓
Sage Copilot: Track close activities across AR, AP, GL, Cash
```

### 7.7 Workflow Sage X3 - Inter-company

```
Purchase Order (Site A) → Goods Receipt (Site A) → Inter-site Transfer
                                                         ↓
                                                    Goods Receipt (Site B)
                                                         ↓
                                                    Sales Order (Site B)
                                                         ↓
                                                    Sales Shipment (Site B)
                                                         ↓
                                                    Sales Invoice (Site B)
```

**Automatisation inter-company:**
- Transactions inter-site automatisées
- Transactions inter-company automatisées (purchases et sales)
- Génération automatique d'écritures de journal inter-sites

---

## 8. SAGE COPILOT - IA INTÉGRÉE

### 8.1 Vue d'ensemble

Sage Copilot est un assistant IA génératif intégré dans les produits Sage. Disponible dans:
- Sage Accounting (tous les plans)
- Sage Active
- Sage Intacct
- Sage 50
- Sage for Accountants
- Sage X3

### 8.2 Fonctionnalités par produit

**Sage Accounting:**
- **Invoicing**: Création d'emails d'envoi de factures/notes de crédit/devis
- **Chasing Payment**: Suivi des retards de paiement, relances automatiques
- **Reports**: Automatisation de la création, planification et envoi de reports
- **Admin/AP**: Création automatique de POs, upload de factures fournisseurs, paiement suppliers
- **VAT Assistant**: Alertes deadlines, vérification des books, calcul du VAT, soumission HMRC
- **Cash Flow**: Détection d'opportunités d'économies, amélioration du cash flow
- **Carbon**: Suivi des émissions de carbone

**Sage Intacct:**
- **Month-end close**: Suivi et gestion des activités de clôture (AR, AP, GL, Cash)
- **Variance Analysis**: Comparaison GL vs sub-ledgers, détection de discrepancies
- **Financial Monitoring**: Analyse de patterns, highlight de tendances
- **Budget Variances**: Détection en temps réel des écarts budgétaires
- **Q&A**: Réponses aux questions financières avec IA formée à la comptabilité

**Sage X3:**
- **Operational Support**: Support contextuel pour tâches opérationnelles
- **Anomaly Detection**: Détection d'anomalies et d'erreurs
- **Opportunity Identification**: Identification d'opportunités
- **Actionable Insights**: Insights actionnables pour décisions

### 8.3 Capacités transversales

| Catégorie | Fonctionnalités |
|-----------|----------------|
| **Automation** | Payment reminders, invoice drafting, expense categorization, bank reconciliations, tax calculations |
| **Business Insights** | Data analysis, tailored recommendations, performance monitoring, growth opportunities |
| **Compliance & Accuracy** | Regulatory issue flagging, anomaly detection, error prevention |
| **Conversational AI** | Questions across products, contextual search, continuous learning |
| **Dashboards** | Real-time insights, trend spotting, risk/opportunity alerts |

### 8.4 Impact mesuré

- **Temps économisé**: 5+ heures par semaine
- **Paiement plus rapide**: 7 jours plus tôt
- **Précision**: Détection d'anomalies IA, réduction des erreurs
- **Productivité**: 40,000+ early adopters dans 5 marchés (UK, US, France, Spain, Germany)

---

## 9. MODULES DÉTAILLÉS PAR PRODUIT

### 9.1 Sage Accounting - Features détaillées

**Invoicing:**
- Create and send invoices
- Track invoice status (sent, viewed, unpaid, overdue)
- Recurring invoices (batch management: activate/deactivate/cancel)
- Sort, search, filter recurring invoices
- Move and reorder lines in sales invoices
- Quick approval for quotes and estimates (one-click approve/reject)
- Invoice payments (Opayo/Paya/PayPal/Stripe)
- Customise: logo, layout, colour theme, font
- Mobile checkout
- AI-personalised invoices

**Customers:**
- Customer records with addresses and contacts
- Inactive accounts
- Customer statements (with delivery status tracking)
- Late Payment charges
- Chase Debt
- Communications history
- Customer price lists
- Invoice disputes
- Contra entries
- Batch changes
- Export contacts (importable format)
- Bulk update via file import

**Suppliers:**
- Supplier records with addresses and contacts
- Inactive accounts
- Batch invoices / Purchase invoices
- Supplier statements
- Manage payments
- Communications history
- CIS and subcontractors
- Supplier invoice disputes
- Contra entries
- Memorise and recall
- Supplier price lists
- Purchase order processing
- Recurring purchase orders
- Foreign Trade

**Inventory / Products & Services:**
- Product records (stock items: track quantity and revenue)
- Service records (non-stock items)
- Advanced Inventory: stock movements, stock adjustments
- Import stock balances
- Stock Movements Summary report
- Stock Movements Detailed report
- Reorder points

**Banking:**
- Bank statement import (bank feeds)
- Bank rules (auto-categorization)
- Bank reconciliation
- Create refunds from bank feeds
- Account types: Chequing, Savings, Credit Card, Cash on Hand, Loan, Other
- Receipts and Payments Day Book report
- Unallocated Receipts or Payments report
- Recurring entries
- Bank transfers

**Reporting:**
- Essential: P&L, Balance Sheet, Trial Balance, Cash Flow Statement, Cash Flow Forecast
- Detailed: General Ledger, Nominal Activity, Audit Trail
- Cash: Cash flow, Money in/out by period/ledger/bank account
- Debtors and Creditors: ageing periods, amount per customer, total owed
- Smart reporting: drill from ledger account balance to nominal activity
- Advanced (Standard/Plus): Custom analysis types (project, department), tag comparisons, saved reports
- Export: Excel, CSV, PDF
- Bulk edit transactions (up to 20 at a time)

**VAT/Tax:**
- VAT calculation and submission
- VAT Return creation and reconciliation
- MTD (Making Tax Digital) ready
- Sage Copilot VAT assistant

**Projects (Standard/Plus):**
- Project tracking
- Project profitability analysis
- Time tracking (add-on)

**Multi-currency (Plus):**
- Foreign currency rates
- Foreign trade (sales and purchases)

**Budgeting (Plus):**
- Create, edit, manage budgets
- Budget reports
- Track business performance vs budget

**Settings & Configuration:**
- Company details (About your Business)
- Chart of Accounts
- Currencies
- Record and Transaction Settings
- Templates and Logos / Document Preferences
- Bank feeds connection
- Payment integrations: Stripe, PayPal, Paya, GoCardless
- Navigation & Data Grids personalisation
- Opening Balances
- User Management (users, access rights, roles)
- Tax settings

### 9.2 Sage Payroll - Features détaillées

**Pay Run Processing:**
- Weekly, two-weekly, four-weekly, monthly payrolls
- Automated calculations: wages, tax, NI, pension contributions
- Pay run corrections (completed pay runs)
- FPS adjustment submission to HMRC
- Negative payments and deductions
- Minimum wage validation
- Process up to 150 employees

**Tax & Compliance:**
- HMRC recognised software
- RTI electronic submissions
- Auto-enrolment: assess, enrol, pension schemes (NOW, NEST, People's Pensions)
- Salary sacrifice pension schemes
- Student/Postgraduate loans
- Attachment of earnings
- Statutory payments (sick, maternity)
- BIK (Benefit in Kind) processing
- Automatic HMRC notices retrieval (P6, P9 tax codes)
- Employment verification (proof of income)

**HR Essentials (all plans):**
- Employee self-service: payslips, P60s online + mobile app
- Time-off reports
- Emergency contacts
- Right to Work document storage
- Up to 3 leave policies
- Shared company calendar
- Company-wide announcements
- HR reports (headcount, gender, length of service)
- Employee self-update personal details

**Core HR & Leave Management (Standard+):**
- HR dashboard (personalised)
- Digital company directory
- Announcements
- Employee self-service portal
- E-signature and documents
- Onboarding (digital, automated)

**Timesheets (Standard+):**
- Employee hour tracking and submission
- Manager approval workflow
- Clock in/out via dashboard or mobile app
- Timesheet approval status reports

**Shift Scheduling (Premium):**
- Drag-and-drop shift planning
- Employee shift visibility
- Schedule groups, areas, templates
- Automated ad hoc updates

**Expenses:**
- Receipt capture via mobile app
- Expense reports and submission
- Manager approval
- Automatic receipt-to-expense conversion
- Expense insights

**Performance Management (add-on):**
- Goals and OKRs
- 1-to-1 scheduling
- 360° and fast feedback
- Employee satisfaction surveys

**Recruitment (add-on):**
- Job posting
- Candidate tracking
- Position filling

**Integration:**
- Automatic posting of salary journals to Sage Accounting
- Sage HR integration
- Multi-user functionality

**Plans:**

| Feature | Essentials | Standard | Premium |
|---------|-----------|----------|---------|
| Payroll + HR Essentials | ✅ | ✅ | ✅ |
| Core HR + Leave Management | ❌ | ✅ | ✅ |
| Timesheets | ❌ | ✅ | ✅ |
| Shift Scheduling | ❌ | ❌ | ✅ |
| Expenses | ❌ | ❌ | ✅ |
| Performance Management | Add-on | Add-on | Add-on |
| Recruitment | Add-on | Add-on | Add-on |
| Sage Copilot | ✅ | ✅ | ✅ |

---

## 10. RECOMMANDATIONS POUR NOTRE APPLICATION

### 10.1 Architecture de navigation recommandée

Inspirée de Sage mais améliorée pour plus de fluidité:

```
┌──────────────────────────────────────────────────────────────────────────┐
│  [Logo]  Tableau de bord  Ventes  Achats  Banque  Reports  Paramètres    │
│                                                    [AI] [?] [👤] [🔔]   │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Zone principale de travail                                              │
│                                                                          │
├──────────────────────────────────────────────────────────────────────────┤
│  [Status / Quick Actions Bar]                                           │
└──────────────────────────────────────────────────────────────────────────┘
```

### 10.2 Modules à implémenter (priorité par phase)

**Phase 1 - MVP (Core):**
1. Tableau de bord (Dashboard personnalisable avec widgets)
2. Ventes/Customers (Invoicing, Quotes, Customer records)
3. Achats/Suppliers (Purchase invoices, Supplier records)
4. Banque/Banking (Bank feeds, Reconciliation, Bank rules)
5. Reports (P&L, Balance Sheet, Trial Balance, Cash Flow)
6. Paramètres (Company settings, Chart of Accounts, User management)
7. TVA/Tax (VAT return, Tax calculations)

**Phase 2 - Extension:**
8. Produits & Services (Stock items, Service items, Stock movements)
9. Journaux (Journal entries, Recurring journals)
10. Projets (Project tracking, Profitability)
11. Paie/Payroll (Pay runs, HMRC submissions, Auto-enrolment)
12. RH/HR (Employee records, Leave management, Self-service)

**Phase 3 - Avancé:**
13. AI Assistant (inspiré de Sage Copilot)
14. Multi-devises
15. Budgets & Forecasting
16. Performance Management
17. Carbon Accounting
18. Mobile App

### 10.3 UI/UX - Améliorations par rapport à Sage

**Garder de Sage (familiers pour les utilisateurs):**
- Navigation par onglets horizontaux (Home, Sales, Purchases, Banking, Reporting, Settings)
- Dashboards multiples par domaine (Company, Customer, Supplier, Items, Financial)
- Workspace personnalisable avec widgets
- Process maps visuels pour les workflows
- Performance cards pour KPIs
- Code couleur: Success (vert), Warning (jaune), Danger (rouge), Primary (action)
- Espacement: 4/8/16/24/32/48px
- Typographie: échelle modulaire 1.125

**Améliorer par rapport à Sage:**
- **Onboarding guidé** - Tours interactifs, tooltips contextuels (Sage manque d'onboarding pour nouveaux utilisateurs)
- **Navigation adaptative** - Menu qui s'adapte au rôle et aux habitudes de l'utilisateur
- **AI proactive** - Suggestions contextuelles, détection d'anomalies en temps réel
- **Mobile-first** - Contrairement à Sage 50 (desktop-only), notre app doit être mobile-first
- **Recherche globale** - Barre de recherche intelligente (Sage X3 a ESC+F7 mais pas intuitif)
- **Workflows visuels** - Process maps interactifs avec progression visuelle
- **Notifications intelligentes** - Pas juste des alertes, mais des actions suggérées
- **Collaboration intégrée** - Commentaires et partage directement dans l'app
- **Dark mode** - Non disponible chez Sage
- **Personnalisation avancée** - Layouts sauvegardables, vues par rôle personnalisables

### 10.4 Design System recommandé

**Couleurs:**
```
Primary:    #0066CC (bleu action - similaire Sage Primary)
Success:    #00875A (vert confirmation)
Warning:    #FFA500 (orange attention)
Danger:     #DE350B (rouge critique)
Neutral:    #6B778C (gris texte secondaire)
Background: #F4F5F7 (gris très clair fond)
Surface:    #FFFFFF (blanc cartes)
Text:       #172B4D (bleu foncé texte principal)
```

**Typographie:**
```
Font family: Inter (ou système similaire)
H1: 32px / 700 / -0.5px
H2: 24px / 700 / -0.15px
H3: 20px / 600 / 0px
H4: 16px / 600 / 0px
Body: 16px / 400 / 0px
Small: 14px / 400 / 0px
Caption: 12px / 400 / 0px
```

**Spacing:**
```
2xs: 4px
xs: 8px
sm: 16px
md: 24px
lg: 32px
xl: 48px
```

**Border radius:**
```
sm: 4px (inputs, buttons)
md: 8px (cards)
lg: 12px (panels)
full: 9999px (pills, avatars)
```

**Shadows:**
```
sm: 0 1px 2px rgba(0,0,0,0.05)
md: 0 4px 6px rgba(0,0,0,0.07)
lg: 0 10px 15px rgba(0,0,0,0.1)
```

### 10.5 Workflows à implémenter

**Sales (Order to Cash):**
```
Quote/Estimate → [Approve] → Sales Invoice → [Send] → [Viewed] → [Paid] → Bank Rec
                                                    ↓
                                              [Overdue] → Chase (AI)
```

**Purchases (Procure to Pay):**
```
Purchase Order → [Receive] → Purchase Invoice → [Approve] → Payment → Bank Rec
```

**Banking:**
```
Bank Feed Import → Auto-categorize (Bank Rules) → Match → Reconcile → Post to Ledger
```

**Payroll:**
```
Timesheet → Pay Run → [Review] → [Approve] → Submit HMRC → Post Journal → Payslips
```

**Period End:**
```
Reconcile → Adjusting Journals → Review Aged D/C → VAT Return → Reports → Close Period
```

### 10.6 Fonctionnalités IA à intégrer

Inspiré de Sage Copilot mais amélioré:

1. **Assistant conversationnel** - Q&A sur données financières
2. **Automatisation d'emails** - Relances, envoi de factures
3. **Détection d'anomalies** - Alertes en temps réel
4. **Catégorisation automatique** - Bank rules + IA
5. **Prévisions de cash flow** - ML-based forecasting
6. **Suggestions proactives** - "Vous avez 3 factures en retard"
7. **Reconnaissance de documents** - OCR pour factures/reçus
8. **Analyse de tendances** - Patterns dans les données
9. **Alertes de conformité** - Deadlines TVA, échéances
10. **Insights business** - Top clients, marges, opportunités

---

## ANNEXE A: Structure complète des menus Sage Business Cloud Accounting

```
HOME
├── Main Dashboard
├── Customer Dashboard
├── Supplier Dashboard
├── Item Dashboard
├── Financial Dashboard
└── My Workspace

SALES (Customers)
├── Lists
│   ├── Customers
│   └── Products & Services (sales)
├── Transactions
│   ├── Quotes & Estimates
│   ├── Sales Invoices
│   ├── Sales Credits
│   ├── Quick Entries
│   └── Recurring Invoices
└── Reports
    ├── Customer reports
    └── Sales reports

PURCHASES (Suppliers)
├── Lists
│   ├── Suppliers
│   └── Products & Services (purchases)
├── Transactions
│   ├── Purchase Invoices
│   ├── Purchase Credits
│   └── Quick Entries
└── Reports
    ├── Supplier reports
    └── Purchase reports

BANKING
├── Lists
│   ├── Bank Accounts
│   ├── Credit Cards
│   └── Cash Accounts
├── Transactions
│   ├── Bank Payments
│   ├── Bank Receipts
│   ├── Bank Transfers
│   └── Recurring Entries
└── Reports
    ├── Bank reports
    └── Reconciliation reports

REPORTING
├── Essential Reports
│   ├── Profit & Loss
│   ├── Balance Sheet
│   ├── Trial Balance
│   ├── Cash Flow Statement
│   └── Cash Flow Forecast
├── Detailed Reports
│   ├── General Ledger
│   ├── Nominal Activity
│   └── Audit Trail
├── Cash Reports
│   ├── Cash flow
│   └── Money in/out
├── Tax Returns
│   └── VAT Return / GST/HST Return
└── More
    └── All reports

JOURNALS
├── New Journal
├── Journal List
└── Recurring Journals

PRODUCTS & SERVICES
├── Products (stock)
├── Services (non-stock)
└── Advanced Inventory
    ├── Stock Movements
    └── Stock Adjustments

PROJECTS (Standard/Plus)
├── Project Tracking
├── Project Profitability
└── Time Tracking (add-on)

SETTINGS
├── About your Business
├── Financial Settings
│   ├── Chart of Accounts
│   ├── Currencies
│   └── Record & Transaction Settings
├── Invoicing & Business
│   ├── Templates and Logos
│   └── Document Preferences
├── Connect
│   ├── Bank Feeds
│   ├── Stripe
│   ├── PayPal
│   ├── Paya
│   └── GoCardless
├── Customise
│   ├── Navigation & Data Grids
│   └── Personalise
├── Opening Balances
├── User Management
│   ├── Users
│   ├── Access Rights
│   └── Roles
├── Card Payments
└── Tax Settings
```

## ANNEXE B: Structure complète des menus Sage Intacct

```
DASHBOARDS
├── All Dashboards
├── Create New Dashboard
└── Dashboard Templates (by role)

COMPANY
├── All
├── Lists
│   ├── Entities
│   ├── Departments
│   ├── Locations
│   ├── Dimensions
│   └── Custom Fields
├── Transactions
│   ├── Journal Entries
│   └── Recurring Journals
└── Reports

GENERAL LEDGER
├── All
├── Lists
│   ├── Accounts
│   └── Account Groups
├── Transactions
│   ├── Journal Entries
│   └── Recurring Journals
├── Reports
│   ├── Financial Reports
│   ├── Balance Sheet
│   ├── P&L
│   ├── Trial Balance
│   └── Custom Reports (ICRW)
└── Periods

ACCOUNTS RECEIVABLE
├── All
├── Lists
│   ├── Customers
│   └── AR Accounts
├── Transactions
│   ├── Invoices
│   ├── Credit Memos
│   ├── Payments
│   └── Adjustments
├── Reports
└── Approvals

ACCOUNTS PAYABLE
├── All
├── Lists
│   ├── Vendors
│   └── AP Accounts
├── Transactions
│   ├── Purchase Invoices
│   ├── Credit Memos
│   ├── Payments
│   └── Adjustments
├── Reports
└── Approvals

CASH MANAGEMENT
├── All
├── Lists
│   ├── Bank Accounts
│   └── Cash Accounts
├── Transactions
│   ├── Deposits
│   ├── Withdrawals
│   ├── Transfers
│   └── Reconciliation
├── Reports
└── Bank Feeds

PURCHASING
├── All
├── Lists
│   ├── Purchase Orders
│   └── Requisitions
├── Transactions
│   ├── PO Entry
│   ├── Goods Receipt
│   └── Invoice Matching
└── Reports

ORDER ENTRY
├── All
├── Lists
│   ├── Sales Orders
│   └── Quotes
├── Transactions
│   ├── Order Entry
│   ├── Fulfillment
│   └── Invoicing
└── Reports

TIME & EXPENSES
├── All
├── Timesheets
├── Expense Reports
├── Approvals
└── Reports

PROJECTS
├── All
├── Lists
│   ├── Projects
│   └── Tasks
├── Transactions
│   ├── Project Billing
│   └── Project Costs
└── Reports

INVENTORY
├── All
├── Lists
│   ├── Items
│   ├── Warehouses
│   └── Bins
├── Transactions
│   ├── Adjustments
│   ├── Transfers
│   └── Counts
└── Reports

FIXED ASSETS
├── All
├── Lists
│   ├── Assets
│   └── Depreciation Schedules
├── Transactions
│   ├── Acquisitions
│   ├── Disposals
│   └── Depreciation Runs
└── Reports

PLATFORM SERVICES
├── Custom Fields
├── Custom Applications
├── APIs
├── Web Services
└── Integrations
```

## ANNEXE C: Structure complète des menus Sage X3

```
MEGA MENU (top navigation)
├── Common Data
│   ├── Products
│   ├── Business Partners
│   ├── Companies
│   └── Sites
├── Financials
│   ├── General Ledger
│   ├── Accounts Payable
│   ├── Accounts Receivable
│   ├── Cash Management
│   ├── Budget & Commitments
│   ├── Fixed Assets
│   └── Financial Reporting
├── Purchasing
│   ├── Purchase Orders
│   ├── Requisitions
│   ├── Goods Receipt
│   └── Supplier Management
├── Sales
│   ├── Sales Orders
│   ├── Shipments
│   ├── Invoices
│   ├── Credit Notes
│   └── Customer Management
├── Inventory
│   ├── Stock Management
│   ├── Movements
│   ├── Transfers
│   ├── Counts
│   └── Valuation
├── Manufacturing
│   ├── Production Planning
│   ├── Work Orders
│   ├── BOM Management
│   ├── Shop Floor Control
│   └── Quality Management
├── Projects
│   ├── Project Setup
│   ├── Cost Tracking
│   ├── Billing
│   └── Project Reports
├── Reporting
│   ├── Business Intelligence
│   ├── Custom Reports
│   ├── Dashboards
│   └── Data Visualization
└── Administration
    ├── Users & Security
    ├── Customization
    ├── APIs & Web Services
    └── System Configuration

LANDING PAGES (left panel - by role)
├── CFO Dashboard
├── Controller Dashboard
├── Operations Manager
├── Production Manager
├── Sales Manager
├── Purchasing Manager
└── + New... (add custom landing page)

SITEMAP (bottom of page)
└── Complete hierarchical map of all menus and entries
    └── Searchable with CTRL+F
    └── Add items to bookmarks
```

---

*Document compilé à partir de: sage.com (produits, features), help-sage50.na.sage.com (modules, navigation), intacct.com (dashboards, components), sage.kajabi.com (design system), pkfscs.co.uk (Intacct modules), randgroup.com (Sage 100 modules), rklesolutions.com (X3 navigation), sageu.com (training curriculum), sage.com blogs (enhancements, Copilot), scribd.com (practitioner guide), thefunaccountant.com (workspace, dashboards), documentation.eu.erp.sage.com (sales process), ineasysteps.com (Sage 50 TOC)*
