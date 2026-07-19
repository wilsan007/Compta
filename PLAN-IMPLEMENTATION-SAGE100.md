# Plan d'Implémentation — Alignement Sage 100 Comptabilité

> Objectif : transformer l'app actuelle (37 pages, schema simplifié) en un clone fonctionnel de Sage 100 Comptabilité (FR) respectant **exactement** la logique métier, les interactions entre modules, et la structure des écrans.
>
> Référence : `sage-100-inventaire-ecrans.md` (104 écrans/fonctionnalités recensés, 82 manquants)

---

## Architecture actuelle

| Couche | Techno | Fichier(s) clé(s) |
|---|---|---|
| Frontend | React 18 + Vite + TypeScript | `app/src/` |
| Routing | React Router v6 | `app/src/App.tsx` |
| UI | TailwindCSS + composants custom | `app/src/components/ui.tsx` |
| Navigation | Sidebar groupée par modules | `app/src/components/Layout.tsx` |
| Data layer | Supabase client direct | `app/src/lib/queries.ts` (935 lignes) |
| Backend | Supabase (PostgreSQL) | `app/supabase-schema.sql` (539 lignes) |
| Auth | Supabase Auth | `app/src/lib/auth.tsx` |

### Tables actuelles (21)
`company_settings`, `users`, `chart_accounts`, `customers`, `suppliers`, `products`, `invoices`, `invoice_lines`, `quotes`, `quote_lines`, `credit_notes`, `credit_note_lines`, `purchase_invoices`, `purchase_invoice_lines`, `bank_accounts`, `bank_transactions`, `bank_rules`, `journal_entries`, `journal_lines`, `vat_returns`, `projects`

### Pages actuelles (37)
Dashboard, Customers, Invoices, Quotes, CreditNotes, RecurringInvoices, Products, Suppliers, PurchaseInvoices, PurchaseCreditNotes, BankAccounts, BankTransactions, BankReconciliation, BankRules, AccountingDashboard, JournalEntries, GeneralLedger, TrialBalance, ChartAccounts, BalanceSheet, CashFlow, VatReturns, JournalsReport, Projects, FixedAssets, Employees, PayRuns, Timesheets, Reports, Settings, Currencies, Workspace, + 4 dashboards (Sales/Purchases/Banking/HR)

---

## PHASE 0 — Restructuration de la navigation (préalable)

### 0.1 Reorganiser la sidebar selon Sage 100

Sage 100 organise son menu en **Structure / Traitement / État** par module. L'app doit adopter une navigation hiérarchique similaire :

```
┌─ ACCUEIL
│  ├─ Tableau de bord
│  └─ Mon espace
│
├─ COMPTABILITÉ
│  ├─ Structure
│  │  ├─ Plan comptable général
│  │  ├─ Plan tiers (clients/fournisseurs/salariés/autres)
│  │  ├─ Plan analytique
│  │  ├─ Codes journaux
│  │  ├─ Modèles de saisie
│  │  ├─ Modèles de règlement
│  │  ├─ Banques & établissements
│  │  ├─ Taux de taxes (TVA)
│  │  ├─ Libellés (bibliothèque)
│  │  ├─ Postes budgétaires
│  │  └─ Cycles de révision
│  │
│  ├─ Traitement
│  │  ├─ Saisie des journaux (journal × période)
│  │  ├─ Saisie par pièce
│  │  ├─ Saisie par lot
│  │  ├─ Saisie des OD analytiques
│  │  ├─ Interrogation & lettrage
│  │  ├─ Interrogation tiers
│  │  ├─ Interrogation analytique
│  │  ├─ Rapprochement bancaire
│  │  ├─ Règlement tiers
│  │  ├─ Relances / recouvrement
│  │  ├─ Réévaluation dettes/créances en devise
│  │  ├─ Révision par cycle
│  │  ├─ Recherche d'écritures
│  │  ├─ Réimputation
│  │  ├─ Écritures d'abonnement
│  │  ├─ Clôture des journaux
│  │  ├─ Fin d'exercice → Nouvel exercice
│  │  ├─ Fin d'exercice → Report à nouveau
│  │  └─ Fin d'exercice → Clôture
│  │
│  ├─ États
│  │  ├─ Brouillard de saisie
│  │  ├─ Journal / Journal centralisé / Journal général
│  │  ├─ Grand-livre des comptes
│  │  ├─ Grand-livre des tiers
│  │  ├─ Balance générale
│  │  ├─ Balance âgée (tiers)
│  │  ├─ Balance analytique
│  │  ├─ Échéancier
│  │  ├─ Déclaration de TVA
│  │  ├─ Bilan
│  │  ├─ Compte de résultat
│  │  ├─ Soldes intermédiaires de gestion (SIG)
│  │  ├─ États analytiques
│  │  ├─ Justificatif de solde
│  │  ├─ État de rapprochement bancaire
│  │  ├─ Contrôle de caisse
│  │  └─ Fichier FEC
│  │
│  └─ Budgets & Reporting
│     ├─ Postes budgétaires
│     ├─ Suivi budgétaire (écarts)
│     └─ Tableaux de bord analytiques
│
├─ GESTION COMMERCIALE
│  ├─ Structure
│  │  ├─ Catalogue articles
│  │  ├─ Tarifs & promotions
│  │  └─ Dépôts & emplacements
│  ├─ Ventes
│  │  ├─ Devis
│  │  ├─ Bon de commande client
│  │  ├─ Préparation de livraison
│  │  ├─ Bon de livraison
│  │  ├─ Facture
│  │  ├─ Avoir / Retour
│  │  └─ Règlements clients
│  ├─ Achats
│  │  ├─ Demande d'achat
│  │  ├─ Commande fournisseur
│  │  ├─ Réception marchandises
│  │  ├─ Facture fournisseur
│  │  └─ Avoir fournisseur
│  ├─ Stock
│  │  ├─ Mouvements / transferts
│  │  ├─ Inventaire
│  │  ├─ Valorisation (CMUP/FIFO)
│  │  └─ Réapprovisionnement
│  └─ Transfert comptable (GesCom → Compta)
│
├─ TRÉSORERIE & FINANCE
│  ├─ Tableau de bord trésorerie
│  ├─ Prévisions de trésorerie
│  ├─ Position consolidée
│  ├─ Moyens de paiement
│  │  ├─ Virements SEPA
│  │  ├─ Prélèvements SEPA
│  │  ├─ Chèques
│  │  ├─ LCR / BOR
│  │  └─ Remises bancaires
│  ├─ Immobilisations
│  │  ├─ Fiches immobilisations
│  │  ├─ Plans d'amortissement
│  │  ├─ Cessions
│  │  └─ Édition tableaux
│  ├─ Automatisation comptable (OCR factures)
│  └─ Recouvrement créances
│     ├─ Tableau de bord créances
│     ├─ Relances automatiques
│     ├─ Pénalités de retard
│     └─ Rapport aging
│
├─ PAIE & RH
│  ├─ Fiches salariés
│  ├─ Bulletins de paie
│  ├─ Déclarations légales (DSN/URSSAF/CNSS)
│  ├─ Contrats
│  ├─ Absences & congés
│  ├─ Pointage / gestion du temps
│  ├─ Variables de paie
│  ├─ Comptabilisation de la paie (OD)
│  └─ RH (formations, compétences)
│
├─ PRODUCTION (optionnel)
│  ├─ Nomenclatures (BOM)
│  ├─ Ordres de fabrication
│  ├─ Gammes opératoires
│  ├─ Planification de capacité
│  └─ MRP / prévision des besoins
│
├─ REPORTING & PILOTAGE
│  ├─ Tableaux de bord financiers
│  ├─ BI Reporting (Excel)
│  ├─ Rapports multi-sociétés
│  └─ Alertes & seuils
│
└─ SYSTÈME
   ├─ Entreprise (paramètres généraux)
   ├─ Exercices & périodes
   ├─ Utilisateurs & rôles
   ├─ Devises
   ├─ Intégrations
   └─ Journaux d'audit
```

### 0.2 Fichiers à modifier
- `app/src/components/Layout.tsx` — restructurer `navGroups` selon le schéma ci-dessus
- `app/src/App.tsx` — ajouter toutes les nouvelles routes

---

## PHASE 1 — Cœur comptable (priorité bloquante)

### 1.1 Base de données — nouvelles tables & migrations

```sql
-- ============================================
-- 1. CODES JOURNAUX (référentiel central)
-- ============================================
create table if not exists journals (
  id uuid primary key default uuid_generate_v4(),
  code text not null unique,           -- ex: ACH, VTE, BQ, CAI, OD
  name text not null,                   -- ex: "Journal des achats"
  type text not null check (type in ('purchase', 'sale', 'bank', 'cash', 'general', 'analytic')),
  account_counterpart text,             -- compte de contrepartie (ex: 401 pour achats)
  bank_account_id uuid references bank_accounts(id) on delete set null,
  default_entry_template_id uuid,       -- modèle de saisie par défaut
  status text default 'active' check (status in ('active', 'inactive')),
  locked boolean default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ============================================
-- 2. EXERCICES & PÉRIODES FISCALES
-- ============================================
create table if not exists fiscal_years (
  id uuid primary key default uuid_generate_v4(),
  code text not null unique,            -- ex: EX2025
  start_date date not null,
  end_date date not null,
  status text default 'open' check (status in ('open', 'closed', 'locked')),
  closed_at timestamptz,
  closed_by uuid references users(id),
  created_at timestamptz default now()
);

create table if not exists fiscal_periods (
  id uuid primary key default uuid_generate_v4(),
  fiscal_year_id uuid references fiscal_years(id) on delete cascade,
  period_number int not null,           -- 1 à 12
  period_label text not null,           -- "Janvier 2025"
  start_date date not null,
  end_date date not null,
  status text default 'open' check (status in ('open', 'closed', 'locked')),
  created_at timestamptz default now()
);

-- ============================================
-- 3. MODÈLES DE SAISIE
-- ============================================
create table if not exists entry_templates (
  id uuid primary key default uuid_generate_v4(),
  name text not null,                   -- ex: "Achat marchandises TTC"
  journal_code text references journals(code),
  description text,
  -- Lignes pré-définies du modèle
  template_lines jsonb,                 -- [{account_general, account_tiers, label, debit_pct, credit_pct}]
  is_default boolean default false,
  active boolean default true,
  created_at timestamptz default now()
);

-- ============================================
-- 4. PLAN TIERS UNIFIÉ
-- ============================================
create table if not exists third_party_accounts (
  id uuid primary key default uuid_generate_v4(),
  code text not null unique,            -- compte collectif ex: 411000
  account_general_code text references chart_accounts(code),
  type text not null check (type in ('customer', 'supplier', 'employee', 'other')),
  name text not null,
  -- Lien vers la table métier correspondante
  customer_id uuid references customers(id) on delete set null,
  supplier_id uuid references suppliers(id) on delete set null,
  employee_id uuid references users(id) on delete set null,
  balance numeric(15,2) default 0,
  lettrage_code text,                   -- code de lettrage en cours
  currency text default 'EUR',
  active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ============================================
-- 5. PLAN ANALYTIQUE
-- ============================================
create table if not exists analytic_sections (
  id uuid primary key default uuid_generate_v4(),
  code text not null unique,            -- ex: A100, B200
  name text not null,
  parent_id uuid references analytic_sections(id),
  axis text,                            -- axe analytique (ex: "Service", "Projet")
  level int default 1,
  active boolean default true,
  created_at timestamptz default now()
);

-- ============================================
-- 6. BUDGETS
-- ============================================
create table if not exists budgets (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  fiscal_year_id uuid references fiscal_years(id) on delete cascade,
  account_code text references chart_accounts(code),
  analytic_section_id uuid references analytic_sections(id) on delete set null,
  period_1 numeric(15,2) default 0,
  period_2 numeric(15,2) default 0,
  period_3 numeric(15,2) default 0,
  period_4 numeric(15,2) default 0,
  period_5 numeric(15,2) default 0,
  period_6 numeric(15,2) default 0,
  period_7 numeric(15,2) default 0,
  period_8 numeric(15,2) default 0,
  period_9 numeric(15,2) default 0,
  period_10 numeric(15,2) default 0,
  period_11 numeric(15,2) default 0,
  period_12 numeric(15,2) default 0,
  total numeric(15,2) generated always as (
    period_1 + period_2 + period_3 + period_4 + period_5 + period_6 +
    period_7 + period_8 + period_9 + period_10 + period_11 + period_12
  ) stored,
  created_at timestamptz default now()
);

-- ============================================
-- 7. LIBELLÉS (bibliothèque)
-- ============================================
create table if not exists standard_labels (
  id uuid primary key default uuid_generate_v4(),
  label text not null unique,
  category text,                        -- ex: "vente", "achat", "banque", "od"
  created_at timestamptz default now()
);
```

### 1.2 Migration des tables existantes — journal_entries & journal_lines

```sql
-- ALTER journal_entries : ajouter les colonnes Sage 100
alter table journal_entries add column if not exists journal_code text references journals(code);
alter table journal_entries add column if not exists fiscal_period_id uuid references fiscal_periods(id);
alter table journal_entries add column if not exists piece_number text;          -- N° pièce
alter table journal_entries add column if not exists invoice_ref text;           -- N° facture
alter table journal_entries add column if not exists entry_template_id uuid references entry_templates(id);
alter table journal_entries add column if not exists status_detail text default 'open'
  check (status_detail in ('open', 'printed', 'closed'));  -- remplace 'draft'/'posted'
alter table journal_entries add column if not exists validated_by uuid references users(id);
alter table journal_entries add column if not exists validated_at timestamptz;

-- ALTER journal_lines : ajouter les colonnes Sage 100
alter table journal_lines add column if not exists account_general text;        -- compte général (ex: 401000)
alter table journal_lines add column if not exists account_tiers text;          -- compte tiers (ex: 411CLI001)
alter table journal_lines add column if not exists third_party_id uuid references third_party_accounts(id);
alter table journal_lines add column if not exists lettrage_code text;          -- code de lettrage
alter table journal_lines add column if not exists lettrage_date date;
alter table journal_lines add column if not exists piece_number text;           -- N° pièce (peut différer par ligne)
alter table journal_lines add column if not exists reference text;              -- référence libre
alter table journal_lines add column if not exists analytic_section_id uuid references analytic_sections(id);
alter table journal_lines add column if not exists analytic_amount numeric(15,2); -- montant ventilé
alter table journal_lines add column if not exists running_balance numeric(15,2); -- solde progressif (banque/caisse)
alter table journal_lines add column if not exists reconciled boolean default false;
alter table journal_lines add column if not exists line_date date;              -- date de la ligne (peut différer de l'entête)

-- Index pour les nouvelles colonnes
create index if not exists idx_journal_entries_journal_code on journal_entries(journal_code);
create index if not exists idx_journal_entries_period on journal_entries(fiscal_period_id);
create index if not exists idx_journal_entries_piece on journal_entries(piece_number);
create index if not exists idx_journal_lines_account_general on journal_lines(account_general);
create index if not exists idx_journal_lines_account_tiers on journal_lines(account_tiers);
create index if not exists idx_journal_lines_lettrage on journal_lines(lettrage_code);
create index if not exists idx_journal_lines_analytic on journal_lines(analytic_section_id);
```

### 1.3 Écrans à créer / refondre — Phase 1

#### 1.3.1 — `JournalsPage` (Codes journaux) — **NOUVEAU**
- **Route** : `/accounting/structure/journals`
- **Table** : `journals`
- **UI** : liste tableau (Code, Nom, Type, Contrepartie, Banque, Statut) + formulaire CRUD
- **Interactions** :
  - Un journal est lié à 0..1 `bank_accounts` (type = bank/cash)
  - Un journal a un `default_entry_template_id` → `entry_templates`
  - Utilisé dans `Saisie des journaux` comme filtre principal
  - Le `type` détermine le comportement de la saisie (contrepartie automatique, etc.)

#### 1.3.2 — `FiscalYearsPage` (Exercices & périodes) — **NOUVEAU**
- **Route** : `/system/fiscal-years`
- **Tables** : `fiscal_years`, `fiscal_periods`
- **UI** : liste exercices + dépliage des 12 périodes (mois) avec statut open/closed/locked
- **Interactions** :
  - La création d'un exercice génère automatiquement 12 `fiscal_periods`
  - La clôture d'une période bloque la saisie sur les journaux pour cette période
  - La clôture d'exercice déclenche : report à nouveau → nouvel exercice → états de clôture
  - `journal_entries.fiscal_period_id` doit pointer vers une période ouverte

#### 1.3.3 — `EntryTemplatesPage` (Modèles de saisie) — **NOUVEAU**
- **Route** : `/accounting/structure/entry-templates`
- **Table** : `entry_templates`
- **UI** : liste modèles + éditeur de lignes pré-définies (jsonb éditable visuellement)
- **Interactions** :
  - Sélectionnable dans `Saisie des journaux` → pré-remplit les lignes
  - Lié à un `journal_code` (un modèle par journal en général)
  - Les pourcentages de débit/crédit permettent le calcul automatique

#### 1.3.4 — `ThirdPartyAccountsPage` (Plan tiers unifié) — **NOUVEAU**
- **Route** : `/accounting/structure/third-party`
- **Table** : `third_party_accounts`
- **UI** : liste unifiée (Code, Type, Nom, Compte général, Solde, Lettrage) + filtres par type
- **Interactions** :
  - Synchro automatique : création client → création `third_party_accounts` (type=customer)
  - Synchro automatique : création fournisseur → création `third_party_accounts` (type=supplier)
  - Le `account_general_code` détermine la classe (411 clients, 401 fournisseurs)
  - Utilisé dans `Interrogation tiers` et `Lettrage`
  - Le solde est calculé depuis `journal_lines` (sum débit - sum crédit où `account_tiers` = code)

#### 1.3.5 — `JournalSaisiePage` (Saisie des journaux — REFONTE COMPLÈTE) — **REFONTE**
- **Route** : `/accounting/treatment/journal-entry` (remplace `/accounting/journal-entries`)
- **Tables** : `journals`, `fiscal_periods`, `journal_entries`, `journal_lines`, `entry_templates`, `third_party_accounts`, `chart_accounts`
- **UI — écran principal (liste journaux × période)** :
  ```
  ┌─────────────────────────────────────────────────────────┐
  │  Période : [Janvier 2025 ▼]   Exercice : [EX2025 ▼]     │
  ├─────────────────────────────────────────────────────────┤
  │ Code  │ Nom               │ Type   │ Statut    │ Actions │
  │ ACH   │ Journal Achats    │ Achat  │ Ouvert    │ Saisir  │
  │ VTE   │ Journal Ventes    │ Vente  │ Ouvert    │ Saisir  │
  │ BQ    │ SALAAM BANK       │ Banque │ Ouvert    │ Saisir  │
  │ CAI   │ Fond de caisse    │ Caisse │ Ouvert    │ Saisir  │
  │ OD    │ Opérations div.   │ Général│ Ouvert    │ Saisir  │
  └─────────────────────────────────────────────────────────┘
  ```
- **UI — écran de saisie (après clic "Saisir")** :
  ```
  ┌───────────────────────────────────────────────────────────────┐
  │  Journal : ACH - Journal des Achats    Période : Janvier 2025 │
  │  Statut : Ouvert                                               │
  ├───────────────────────────────────────────────────────────────┤
  │  Modèle : [Achat marchandises TTC ▼]    [Appliquer]           │
  ├──────┬──────────┬───────────┬──────────┬──────────┬───────────┤
  │ Jour │N° pièce  │N° facture │Référence │Cpte gén. │Cpte tiers │
  │ 15   │ACH-0001  │F2025-001  │          │607000    │401FOU001  │
  ├──────┼──────────┼───────────┼──────────┼──────────┼───────────┤
  │ Libellé                    │ Débit     │ Crédit    │ Solde     │
  │ Achat marchandises         │ 1 200,00  │           │ 1 200,00  │
  │ TVA déductible 20%         │   240,00  │           │ 1 440,00  │
  │ Fournisseur ABC            │           │ 1 440,00  │    0,00   │
  ├────────────────────────────┼───────────┼───────────┼───────────┤
  │ TOTAUX                     │ 1 440,00  │ 1 440,00  │ Équilibré │
  └────────────────────────────┴───────────┴───────────┴───────────┘
  │  [Équilibrer]  [Enregistrer]  [Imprimer]  [Clôturer]         │
  └───────────────────────────────────────────────────────────────┘
  ```
  - Pour les journaux de banque/caisse : bandeau **Ancien solde / Mouvements / Nouveau solde**
  - Le solde progressif (`running_balance`) est calculé ligne par ligne
- **Logique métier** :
  1. L'utilisateur sélectionne un journal + une période → filtre les écritures existantes
  2. Saisie ligne par ligne : Jour, N° pièce, N° facture, Référence, Compte général, Compte tiers, Libellé, Débit, Crédit
  3. Le compte général est un autocomplete sur `chart_accounts`
  4. Le compte tiers est un autocomplete sur `third_party_accounts` (filtre selon le compte général)
  5. Bouton **Équilibrer** : calcule la différence débit/crédit et ajoute une ligne de contrepartie
  6. Si modèle de saisie sélectionné → pré-remplit les lignes avec les pourcentages
  7. **Enregistrer** : valide que débit = crédit, sauvegarde `journal_entries` + `journal_lines`
  8. **Imprimer** : passe le statut à `printed`, génère le brouillard
  9. **Clôturer** : passe le statut à `closed`, bloque les modifications
  10. Suppression impossible si statut = `closed` ou si ligne lettrée/rapprochée

#### 1.3.6 — `LettragePage` (Interrogation & lettrage) — **NOUVEAU**
- **Route** : `/accounting/treatment/lettrage`
- **Tables** : `journal_lines`, `third_party_accounts`
- **UI** :
  - Sélection d'un compte tiers → affichage de toutes les écritures non lettrées
  - Tableau : Date, N° pièce, Libellé, Débit, Crédit, Solde, Code lettrage
  - Sélection de 2+ lignes → bouton **Lettrer** (affecte un code unique, ex: "A001")
  - Bouton **Délettrer** sur lignes lettrées
  - Lettrage automatique : matching par montant (débit = crédit) ou par date + référence
- **Logique métier** :
  1. Le code de lettrage est incrémental (A001, A002, ... B001 après rotation)
  2. Une fois lettrées, les lignes ne peuvent plus être supprimées/modifiées
  3. Le lettrage alimente : balance âgée, échéancier, recouvrement, TVA sur encaissement
  4. Le solde du compte tiers = sum des lignes non lettrées

#### 1.3.7 — `SearchEntriesPage` (Recherche d'écritures) — **NOUVEAU**
- **Route** : `/accounting/treatment/search`
- **Tables** : `journal_entries` + `journal_lines` (jointure)
- **UI** : formulaire de recherche multi-critères (journal, période, date, compte, tiers, montant, libellé, N° pièce) + résultats en tableau
- **Interactions** : clic sur une ligne → ouverture de l'écriture dans `JournalSaisiePage`

#### 1.3.8 — `JournalClosurePage` (Clôture des journaux) — **NOUVEAU**
- **Route** : `/accounting/treatment/journal-closure`
- **Tables** : `journals`, `fiscal_periods`, `journal_entries`
- **UI** : tableau journaux × périodes avec statut (Ouvert/Clôturé) + action de clôture
- **Logique métier** :
  - Clôture partielle : bloque la saisie mais permet l'édition
  - Clôture totale : bloque tout (saisie + édition + suppression)
  - Vérification : toutes les écritures doivent être équilibrées avant clôture

#### 1.3.9 — `FiscalYearClosurePage` (Fin d'exercice) — **NOUVEAU**
- **Route** : `/accounting/treatment/fiscal-year-closure`
- **Tables** : `fiscal_years`, `journal_entries`, `journal_lines`, `chart_accounts`
- **Workflow en 3 étapes** :
  1. **Nouvel exercice** : création `fiscal_years` + 12 `fiscal_periods`
  2. **Report à nouveau** : génération d'écritures d'ouverture (comptes de bilan reportés en solde, comptes de tiers reportés en détail)
  3. **Clôture** : clôture de l'ancien exercice, génération des écritures de résultat
- **Interactions** :
  - Vérifie que tous les journaux sont clôturés
  - Génère les états de clôture (bilan, compte de résultat, SIG)
  - Les comptes de gestion (classe 6/7) sont soldés → compte 129/120000

### 1.4 États (éditions) à créer — Phase 1

#### 1.4.1 — `BrouillardPage` — **NOUVEAU**
- **Route** : `/accounting/states/brouillard`
- **Logique** : liste toutes les écritures statut `open` (non imprimées), triées par date de saisie
- **Colonnes** : N° saisie, Date, Journal, N° pièce, Compte, Libellé, Débit, Crédit

#### 1.4.2 — `AgedBalancePage` (Balance âgée) — **NOUVEAU**
- **Route** : `/accounting/states/aged-balance`
- **Logique** : par compte tiers, calcul des créances/dettes par tranche d'âge (0-30j, 31-60j, 61-90j, 90j+)
- **Source** : `journal_lines` non lettrées + `third_party_accounts`
- **Filtres** : type tiers (client/fournisseur), date de référence

#### 1.4.3 — `EcheancierPage` (Échéancier) — **NOUVEAU**
- **Route** : `/accounting/states/echeancier`
- **Logique** : prévision des échéances de règlement par tiers, basée sur les conditions de paiement
- **Source** : `invoices.due_date`, `purchase_invoices.due_date`, `journal_lines` non lettrées

#### 1.4.4 — `GrandLivreTiersPage` (Grand-livre des tiers) — **NOUVEAU**
- **Route** : `/accounting/states/general-ledger-tiers`
- **Logique** : même principe que `GeneralLedgerPage` mais filtré par `account_tiers` au lieu de `account_general`
- **Colonnes** : Date, N° pièce, Journal, Libellé, Débit, Crédit, Solde progressif, Code lettrage

#### 1.4.5 — `FECExportPage` (Fichier FEC) — **NOUVEAU**
- **Route** : `/accounting/states/fec`
- **Logique** : export au format FEC (Fichier des Écritures Comptables) — norme DGFIP
- **Format** : 18 colonnes fixes (JournalCode, JournalLib, EcritureNum, EcritureDate, CompteNum, CompteLib, CompAuxNum, CompAuxLib, PieceRef, PieceDate, EcritureLib, Debit, Credit, EcritureLet, DateLet, ValidDate, Montantdevise, Idevise)
- **Source** : `journal_entries` + `journal_lines` jointes, filtrées par exercice

#### 1.4.6 — `SIGPage` (Soldes intermédiaires de gestion) — **NOUVEAU**
- **Route** : `/accounting/states/sig`
- **Logique** : calcul des SIG depuis les comptes de gestion (classe 6/7)
  - Marge commerciale, Production de l'exercice, VA, EBE, Résultat d'exploitation, Résultat financier, Résultat exceptionnel, Résultat net

#### 1.4.7 — `AnalyticBalancePage` (Balance analytique) — **NOUVEAU**
- **Route** : `/accounting/states/analytic-balance`
- **Logique** : balance par section analytique (`analytic_sections`)
- **Source** : `journal_lines.analytic_section_id` + `analytic_amount`

### 1.5 Refonte des pages existantes — Phase 1

#### 1.5.1 — `JournalEntriesPage` → devient `JournalSaisiePage` (refonte complète)
- Voir section 1.3.5 ci-dessus

#### 1.5.2 — `GeneralLedgerPage` (enrichissement)
- Ajouter filtre par journal, par période, par exercice
- Ajouter colonnes : N° pièce, Code lettrage, Compte tiers
- Ajouter solde progressif par compte

#### 1.5.3 — `TrialBalancePage` (enrichissement)
- Ajouter filtre par période/exercice
- Ajouter colonnes : solde période, solde cumulé, variation
- Ajouter option balance à 4 colonnes / 6 colonnes / 8 colonnes

#### 1.5.4 — `ChartAccountsPage` (enrichissement)
- Ajouter type de compte : général / tiers / analytique
- Ajouter lien vers `third_party_accounts` pour les comptes collectifs (411, 401, 421, etc.)
- Ajouter gestion hiérarchique (comptes parents/enfants)

#### 1.5.5 — `VatReturnsPage` (enrichissement)
- Calcul automatique depuis les écritures (comptes 4456x / 4457x)
- Lien avec le lettrage pour TVA sur encaissement
- Génération de la déclaration (CA3 / CA12)

---

## PHASE 2 — Modules financiers

### 2.1 Base de données — Phase 2

```sql
-- ============================================
-- 8. IMMOBILISATIONS (enrichissement)
-- ============================================
create table if not exists fixed_assets (
  id uuid primary key default uuid_generate_v4(),
  code text not null unique,            -- code immobilisation
  name text not null,
  asset_type text check (asset_type in ('building', 'vehicle', 'it_equipment', 'furniture', 'intangible', 'other')),
  account_asset text references chart_accounts(code),    -- compte d'immobilisation (classe 2)
  account_depreciation text references chart_accounts(code), -- compte d'amortissement (28xxx)
  account_expense text references chart_accounts(code),  -- compte de dotation (68xxx)
  acquisition_date date not null,
  acquisition_value numeric(15,2) not null,
  residual_value numeric(15,2) default 0,
  depreciation_method text check (depreciation_method in ('linear', 'declining', 'exceptional', 'none')),
  depreciation_duration int,             -- durée en années
  depreciation_start_date date,
  annual_depreciation numeric(15,2),
  accumulated_depreciation numeric(15,2) default 0,
  net_book_value numeric(15,2),
  status text default 'active' check (status in ('active', 'disposed', 'fully_depreciated')),
  disposal_date date,
  disposal_value numeric(15,2),
  site text,                             -- multi-sites
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ============================================
-- 9. MOYENS DE PAIEMENT
-- ============================================
create table if not exists payment_orders (
  id uuid primary key default uuid_generate_v4(),
  reference text not null unique,
  type text not null check (type in ('sepa_transfer', 'sepa_direct_debit', 'check', 'lcr_bor')),
  direction text not null check (direction in ('outgoing', 'incoming')),
  bank_account_id uuid references bank_accounts(id) on delete cascade,
  -- Bénéficiaire / débiteur
  third_party_id uuid references third_party_accounts(id) on delete set null,
  third_party_name text,
  third_party_iban text,
  third_party_bic text,
  amount numeric(15,2) not null,
  value_date date,
  status text default 'draft' check (status in ('draft', 'generated', 'sent', 'acknowledged', 'rejected', 'processed')),
  sepa_xml text,                        -- contenu SEPA généré
  remise_number text,                   -- n° de remise bancaire
  journal_code text references journals(code),
  journal_entry_id uuid references journal_entries(id) on delete set null,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ============================================
-- 10. RECOUVREMENT / RELANCES
-- ============================================
create table if not exists collection_cases (
  id uuid primary key default uuid_generate_v4(),
  customer_id uuid references customers(id) on delete cascade,
  third_party_code text,
  invoice_id uuid references invoices(id) on delete set null,
  amount_due numeric(15,2) not null,
  due_date date not null,
  days_overdue int generated always as (current_date - due_date) stored,
  reminder_level int default 0,         -- 0=aucune, 1=1ère relance, 2=2ème, 3=mise en demeure
  last_reminder_date date,
  promise_to_pay_date date,
  promise_to_pay_amount numeric(15,2),
  status text default 'open' check (status in ('open', 'promised', 'paid', 'litigation', 'closed')),
  litigation boolean default false,
  notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists reminder_templates (
  id uuid primary key default uuid_generate_v4(),
  level int not null,                   -- 1, 2, 3
  name text not null,
  subject text,
  body text,
  include_penalties boolean default true,
  penalty_rate numeric(5,2) default 0,
  created_at timestamptz default now()
);

-- ============================================
-- 11. AUTOMATISATION COMPTABLE (OCR)
-- ============================================
create table if not exists supplier_invoice_uploads (
  id uuid primary key default uuid_generate_v4(),
  file_name text not null,
  file_url text not null,               -- URL Supabase Storage
  file_type text,                       -- pdf, jpg, png
  status text default 'pending' check (status in ('pending', 'processing', 'extracted', 'validated', 'rejected')),
  -- Données extraites par OCR
  extracted_supplier text,
  extracted_invoice_number text,
  extracted_date date,
  extracted_amount_ht numeric(15,2),
  extracted_vat numeric(15,2),
  extracted_ttc numeric(15,2),
  -- Validation
  suggested_accounts jsonb,             -- suggestions de comptes
  validated_supplier_id uuid references suppliers(id),
  validated_purchase_invoice_id uuid references purchase_invoices(id),
  processed_at timestamptz,
  created_at timestamptz default now()
);
```

### 2.2 Écrans à créer — Phase 2

#### 2.2.1 — `TreasuryDashboardPage` (refonte) — **REFONTE**
- **Route** : `/treasury/dashboard`
- **UI** : position consolidée multi-comptes, graphique flux, prévisions à 30/60/90j
- **Source** : `bank_accounts.balance` + `journal_lines` futures (échéancier) + `payment_orders` en cours

#### 2.2.2 — `TreasuryForecastPage` — **NOUVEAU**
- **Route** : `/treasury/forecast`
- **Logique** : projection des flux futurs basée sur les échéances (factures clients/fournisseurs non réglées)
- **UI** : tableau par jour/semaine/mois avec entrées/sorties prévisionnelles + solde projeté

#### 2.2.3 — `PaymentOrdersPage` (Moyens de paiement) — **NOUVEAU**
- **Route** : `/treasury/payment-orders`
- **Table** : `payment_orders`
- **UI** : liste des ordres de paiement + génération SEPA XML + suivi remises
- **Interactions** :
  - Génération d'un virement → création `payment_orders` + `journal_entries` (comptabilisation)
  - Génération SEPA XML (format XML ISO 20022)
  - Suivi des accusés de réception bancaires
  - Lien avec `bank_transactions` (rapprochement)

#### 2.2.4 — `FixedAssetsPage` (refonte complète) — **REFONTE**
- **Route** : `/treasury/fixed-assets` (déplacer depuis `/accounting/fixed-assets`)
- **Table** : `fixed_assets`
- **UI** : liste immobilisations + fiche détaillée avec tableau d'amortissement
- **Interactions** :
  - Calcul automatique des dotations annuelles (linéaire/dégressif)
  - Génération des écritures de dotation → `journal_entries` + `journal_lines`
  - Cession : génération écriture de cession + calcul plus/moins-value
  - Édition tableau d'amortissement par immobilisation

#### 2.2.5 — `SupplierInvoiceAutomationPage` — **NOUVEAU**
- **Route** : `/treasury/invoice-automation`
- **Table** : `supplier_invoice_uploads`
- **UI** : drag & drop de factures + tableau de bord de traitement + validation
- **Workflow** :
  1. Upload fichier → `supplier_invoice_uploads` (status=pending)
  2. Traitement OCR → extraction données (status=extracted)
  3. Validation utilisateur → création `purchase_invoices` + `journal_entries` (status=validated)
  4. Archivage numérique (Supabase Storage)

#### 2.2.6 — `CollectionDashboardPage` (Recouvrement) — **NOUVEAU**
- **Route** : `/treasury/collection`
- **Tables** : `collection_cases`, `customers`, `invoices`
- **UI** : tableau de bord créances (aging, montants, retards) + actions de relance
- **Interactions** :
  - Génération automatique des `collection_cases` depuis factures impayées
  - Envoi relances (niveau 1/2/3) via `reminder_templates`
  - Calcul pénalités de retard
  - Suivi promesses de paiement
  - Export vers recouvrement externe

---

## PHASE 3 — Gestion commerciale & production

### 3.1 Base de données — Phase 3

```sql
-- ============================================
-- 12. COMMANDES CLIENT / FOURNISSEUR
-- ============================================
create table if not exists sales_orders (
  id uuid primary key default uuid_generate_v4(),
  number text not null unique,
  customer_id uuid references customers(id) on delete set null,
  customer_name text,
  date date not null default current_date,
  status text default 'draft' check (status in ('draft', 'confirmed', 'delivered', 'invoiced', 'cancelled')),
  subtotal numeric(15,2) default 0,
  vat_total numeric(15,2) default 0,
  total numeric(15,2) default 0,
  quote_id uuid references quotes(id) on delete set null,
  delivery_id uuid,
  invoice_id uuid references invoices(id) on delete set null,
  notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists sales_order_lines (
  id uuid primary key default uuid_generate_v4(),
  sales_order_id uuid references sales_orders(id) on delete cascade,
  product_id uuid references products(id) on delete set null,
  description text not null,
  quantity numeric(15,2) default 1,
  unit_price numeric(15,2) default 0,
  vat_rate numeric(5,2) default 20.0,
  total numeric(15,2) default 0,
  vat_total numeric(15,2) default 0,
  line_order int default 0,
  created_at timestamptz default now()
);

create table if not exists purchase_orders (
  id uuid primary key default uuid_generate_v4(),
  number text not null unique,
  supplier_id uuid references suppliers(id) on delete set null,
  supplier_name text,
  date date not null default current_date,
  expected_date date,
  status text default 'draft' check (status in ('draft', 'confirmed', 'received', 'invoiced', 'cancelled')),
  subtotal numeric(15,2) default 0,
  vat_total numeric(15,2) default 0,
  total numeric(15,2) default 0,
  notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists purchase_order_lines (
  id uuid primary key default uuid_generate_v4(),
  purchase_order_id uuid references purchase_orders(id) on delete cascade,
  product_id uuid references products(id) on delete set null,
  description text not null,
  quantity numeric(15,2) default 1,
  unit_price numeric(15,2) default 0,
  vat_rate numeric(5,2) default 20.0,
  total numeric(15,2) default 0,
  vat_total numeric(15,2) default 0,
  line_order int default 0,
  created_at timestamptz default now()
);

-- ============================================
-- 13. BONS DE LIVRAISON
-- ============================================
create table if not exists delivery_notes (
  id uuid primary key default uuid_generate_v4(),
  number text not null unique,
  customer_id uuid references customers(id) on delete set null,
  customer_name text,
  date date not null default current_date,
  status text default 'draft' check (status in ('draft', 'delivered', 'invoiced')),
  sales_order_id uuid references sales_orders(id) on delete set null,
  notes text,
  created_at timestamptz default now()
);

create table if not exists delivery_note_lines (
  id uuid primary key default uuid_generate_v4(),
  delivery_note_id uuid references delivery_notes(id) on delete cascade,
  product_id uuid references products(id) on delete set null,
  description text not null,
  quantity numeric(15,2) default 1,
  line_order int default 0,
  created_at timestamptz default now()
);

-- ============================================
-- 14. STOCK MULTI-DÉPÔTS
-- ============================================
create table if not exists warehouses (
  id uuid primary key default uuid_generate_v4(),
  code text not null unique,
  name text not null,
  address text,
  city text,
  active boolean default true,
  created_at timestamptz default now()
);

create table if not exists stock_movements (
  id uuid primary key default uuid_generate_v4(),
  product_id uuid references products(id) on delete cascade,
  warehouse_id uuid references warehouses(id) on delete cascade,
  type text not null check (type in ('in', 'out', 'transfer', 'adjustment')),
  quantity numeric(15,2) not null,
  reference text,                       -- n° document source
  source_type text,                     -- 'delivery', 'receipt', 'order', 'manual'
  source_id uuid,
  unit_cost numeric(15,2),              -- coût unitaire (pour valorisation)
  movement_date date not null default current_date,
  created_at timestamptz default now()
);

create table if not exists stock_quantities (
  id uuid primary key default uuid_generate_v4(),
  product_id uuid references products(id) on delete cascade,
  warehouse_id uuid references warehouses(id) on delete cascade,
  quantity numeric(15,2) default 0,
  reserved numeric(15,2) default 0,     -- quantité réservée (commandes en cours)
  valuation_method text default 'cmup' check (valuation_method in ('cmup', 'fifo', 'lifo')),
  unit_cost numeric(15,2) default 0,
  unique(product_id, warehouse_id)
);

-- ============================================
-- 15. TARIFS & PROMOTIONS
-- ============================================
create table if not exists price_lists (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  type text check (type in ('sale', 'purchase')),
  currency text default 'EUR',
  active boolean default true,
  created_at timestamptz default now()
);

create table if not exists price_list_lines (
  id uuid primary key default uuid_generate_v4(),
  price_list_id uuid references price_lists(id) on delete cascade,
  product_id uuid references products(id) on delete cascade,
  min_quantity numeric(15,2) default 1,
  unit_price numeric(15,2) not null,
  discount_pct numeric(5,2) default 0,
  created_at timestamptz default now()
);

-- ============================================
-- 16. PRODUCTION (BOM, OF, MRP)
-- ============================================
create table if not exists bill_of_materials (
  id uuid primary key default uuid_generate_v4(),
  product_id uuid references products(id) on delete cascade,
  name text not null,
  version int default 1,
  active boolean default true,
  created_at timestamptz default now()
);

create table if not exists bom_lines (
  id uuid primary key default uuid_generate_v4(),
  bom_id uuid references bill_of_materials(id) on delete cascade,
  component_product_id uuid references products(id) on delete cascade,
  quantity numeric(15,2) not null,
  unit text,
  line_order int default 0,
  created_at timestamptz default now()
);

create table if not exists manufacturing_orders (
  id uuid primary key default uuid_generate_v4(),
  number text not null unique,
  bom_id uuid references bill_of_materials(id),
  product_id uuid references products(id),
  quantity numeric(15,2) not null,
  status text default 'planned' check (status in ('planned', 'released', 'in_progress', 'completed', 'cancelled')),
  planned_start_date date,
  planned_end_date date,
  actual_start_date date,
  actual_end_date date,
  warehouse_id uuid references warehouses(id),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
```

### 3.2 Écrans à créer — Phase 3

#### 3.2.1 — Workflow commercial complet (Ventes)
```
Devis → Bon de commande → Préparation livraison → Bon de livraison → Facture → Avoir (si retour)
                                                              ↓
                                                        Règlement client
```

| Écran | Route | Statut | Table |
|---|---|---|---|
| `SalesOrdersPage` | `/sales/orders` | **NOUVEAU** | `sales_orders` + `sales_order_lines` |
| `DeliveryNotesPage` | `/sales/delivery-notes` | **NOUVEAU** | `delivery_notes` + `delivery_note_lines` |
| `CustomerPaymentsPage` | `/sales/payments` | **NOUVEAU** | `payment_orders` (direction=incoming) |

**Interactions clés** :
- Devis accepté → génère `sales_orders` (status=confirmed)
- Commande confirmée → génère `delivery_notes` (préparation/picking)
- Bon de livraison livré → génère `invoices` (status=draft)
- Facture payée → génère `payment_orders` + `journal_entries` (règlement)
- Avoir généré depuis facture → `credit_notes`

#### 3.2.2 — Workflow achats complet
```
Demande d'achat → Commande fournisseur → Réception marchandises → Facture fournisseur → Avoir (si retour)
                                                                    ↓
                                                              Règlement fournisseur
```

| Écran | Route | Statut | Table |
|---|---|---|---|
| `PurchaseOrdersPage` | `/purchases/orders` | **NOUVEAU** | `purchase_orders` + `purchase_order_lines` |
| `GoodsReceiptPage` | `/purchases/goods-receipt` | **NOUVEAU** | `delivery_notes` (type incoming) |
| `SupplierPaymentsPage` | `/purchases/payments` | **NOUVEAU** | `payment_orders` (direction=outgoing) |

#### 3.2.3 — Stock & inventaire

| Écran | Route | Statut | Table |
|---|---|---|---|
| `WarehousesPage` | `/stock/warehouses` | **NOUVEAU** | `warehouses` |
| `StockMovementsPage` | `/stock/movements` | **NOUVEAU** | `stock_movements` |
| `StockQuantitiesPage` | `/stock/quantities` | **NOUVEAU** | `stock_quantities` |
| `InventoryPage` | `/stock/inventory` | **NOUVEAU** | `stock_movements` (type=adjustment) |
| `ReorderPage` | `/stock/reorder` | **NOUVEAU** | `stock_quantities` (filtre quantity <= reorder_level) |

#### 3.2.4 — Production (optionnel)

| Écran | Route | Statut | Table |
|---|---|---|---|
| `BOMPage` | `/production/bom` | **NOUVEAU** | `bill_of_materials` + `bom_lines` |
| `ManufacturingOrdersPage` | `/production/orders` | **NOUVEAU** | `manufacturing_orders` |

#### 3.2.5 — Transfert comptable GesCom → Compta
- **Route** : `/commercial/transfer-to-accounting`
- **Logique** : génère des `journal_entries` depuis les documents commerciaux (factures de vente/achat, règlements)
- **Mapping** :
  - Facture de vente → journal VTE (débit 411xxx / crédit 707xxx + 4457xxx)
  - Facture d'achat → journal ACH (débit 607xxx + 4456xxx / crédit 401xxx)
  - Règlement client → journal BQ (débit 512xxx / crédit 411xxx)
  - Règlement fournisseur → journal BQ (débit 401xxx / crédit 512xxx)

---

## PHASE 4 — Paie & RH complète

### 4.1 Base de données — Phase 4

```sql
-- ============================================
-- 17. PAIE & RH
-- ============================================
create table if not exists employees (
  id uuid primary key default uuid_generate_v4(),
  matricule text not null unique,
  first_name text not null,
  last_name text not null,
  social_security_number text,
  birth_date date,
  hire_date date not null,
  end_date date,
  contract_type text check (contract_type in ('cdi', 'cdd', 'apprentice', 'intern', 'freelance')),
  position text,
  department text,
  monthly_gross_salary numeric(15,2),
  hourly_rate numeric(15,2),
  bank_iban text,
  bank_bic text,
  address text,
  phone text,
  email text,
  status text default 'active' check (status in ('active', 'inactive', 'terminated')),
  third_party_account_id uuid references third_party_accounts(id),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists pay_runs (
  id uuid primary key default uuid_generate_v4(),
  number text not null unique,
  period_month int not null,
  period_year int not null,
  status text default 'draft' check (status in ('draft', 'calculated', 'validated', 'paid', 'accounted')),
  pay_date date,
  total_gross numeric(15,2) default 0,
  total_charges numeric(15,2) default 0,
  total_net numeric(15,2) default 0,
  journal_entry_id uuid references journal_entries(id) on delete set null,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists pay_slips (
  id uuid primary key default uuid_generate_v4(),
  pay_run_id uuid references pay_runs(id) on delete cascade,
  employee_id uuid references employees(id) on delete cascade,
  gross_salary numeric(15,2),
  overtime_hours numeric(5,2) default 0,
  overtime_amount numeric(15,2) default 0,
  bonuses numeric(15,2) default 0,
  -- Cotisations
  social_security_employee numeric(15,2) default 0,
  social_security_employer numeric(15,2) default 0,
  retirement_employee numeric(15,2) default 0,
  retirement_employer numeric(15,2) default 0,
  unemployment_employee numeric(15,2) default 0,
  unemployment_employer numeric(15,2) default 0,
  income_tax numeric(15,2) default 0,
  -- Net
  total_deductions numeric(15,2) default 0,
  net_salary numeric(15,2) default 0,
  -- Variables de paie
  variables jsonb,                       -- [{code, label, amount, type: gain/retention}]
  status text default 'draft' check (status in ('draft', 'validated', 'paid')),
  created_at timestamptz default now()
);

create table if not exists leave_requests (
  id uuid primary key default uuid_generate_v4(),
  employee_id uuid references employees(id) on delete cascade,
  type text not null check (type in ('annual', 'sick', 'maternity', 'paternity', 'unpaid', 'other')),
  start_date date not null,
  end_date date not null,
  days numeric(5,2) not null,
  status text default 'pending' check (status in ('pending', 'approved', 'rejected')),
  approved_by uuid references users(id),
  notes text,
  created_at timestamptz default now()
);

create table if not exists time_entries (
  id uuid primary key default uuid_generate_v4(),
  employee_id uuid references employees(id) on delete cascade,
  date date not null,
  hours numeric(5,2) not null,
  project_id uuid references projects(id) on delete set null,
  task_description text,
  type text default 'regular' check (type in ('regular', 'overtime', 'training', 'meeting')),
  created_at timestamptz default now()
);

create table if not exists legal_declarations (
  id uuid primary key default uuid_generate_v4(),
  type text not null check (type in ('dsn', 'urssaf', 'cnss', 'dap')),
  period_month int,
  period_year int,
  status text default 'draft' check (status in ('draft', 'generated', 'submitted', 'acknowledged')),
  file_url text,
  submitted_date date,
  created_at timestamptz default now()
);
```

### 4.2 Écrans à créer / refondre — Phase 4

| Écran | Route | Statut | Description |
|---|---|---|---|
| `EmployeesPage` (refonte) | `/hr/employees` | **REFONTE** | Fiche complète (matricule, contrat, salaire, charges, IBAN) |
| `PayRunsPage` (refonte) | `/hr/pay-runs` | **REFONTE** | Génération par période, calcul automatique, édition bulletins |
| `PaySlipsPage` | `/hr/pay-slips` | **NOUVEAU** | Bulletin de paie détaillé (variables, cotisations, net) |
| `LeaveRequestsPage` | `/hr/leave` | **NOUVEAU** | Demandes de congés + workflow approbation |
| `TimeTrackingPage` | `/hr/time-tracking` | **NOUVEAU** | Pointage quotidien + heures par projet |
| `LegalDeclarationsPage` | `/hr/declarations` | **NOUVEAU** | DSN, URSSAF, CNSS — génération + suivi |
| `PayrollAccountingPage` | `/hr/payroll-accounting` | **NOUVEAU** | Comptabilisation OD de paie → `journal_entries` |
| `ContractsPage` | `/hr/contracts` | **NOUVEAU** | Gestion contrats (CDI/CDD/apprentissage) |
| `TrainingPage` | `/hr/training` | **NOUVEAU** | Formations, compétences, entretiens |

**Comptabilisation de la paie (OD de paie)** :
```
Débit : 641xxx (rémunérations)        = salaire brut
Débit : 645xxx (charges patronales)   = charges employeur
Crédit : 431xxx (sécurité sociale)    = cotisations salariales + patronales SS
Crédit : 437xxx (autres cotisations)  = retraite, chômage, etc.
Crédit : 442xxx (impôt sur salaire)   = ITS/IRPP
Crédit : 421xxx (net à payer)         = salaire net
```

---

## PHASE 5 — Reporting & BI

### 5.1 Écrans à créer — Phase 5

| Écran | Route | Statut | Description |
|---|---|---|---|
| `FinancialDashboardPage` (refonte) | `/reporting/financial` | **REFONTE** | KPIs temps réel (CA, marge, trésorerie, BFR) |
| `BIReportingPage` | `/reporting/bi` | **NOUVEAU** | Rapports personnalisés, export Excel, multi-sociétés |
| `BudgetTrackingPage` | `/reporting/budget` | **NOUVEAU** | Suivi budgétaire (réalisé vs budget, écarts) |
| `AuditLogPage` | `/system/audit-log` | **NOUVEAU** | Journal d'audit (qui a fait quoi, quand) |

---

## Tableau récapitulatif — Nouvelles tables

| Phase | Table | Module | Priorité |
|---|---|---|---|
| 1 | `journals` | Comptabilité | **Bloquante** |
| 1 | `fiscal_years` | Comptabilité | **Bloquante** |
| 1 | `fiscal_periods` | Comptabilité | **Bloquante** |
| 1 | `entry_templates` | Comptabilité | **Bloquante** |
| 1 | `third_party_accounts` | Comptabilité | **Bloquante** |
| 1 | `analytic_sections` | Comptabilité | Haute |
| 1 | `budgets` | Comptabilité | Haute |
| 1 | `standard_labels` | Comptabilité | Moyenne |
| 2 | `fixed_assets` (refonte) | Immobilisations | Haute |
| 2 | `payment_orders` | Moyens de paiement | Haute |
| 2 | `collection_cases` | Recouvrement | Moyenne |
| 2 | `reminder_templates` | Recouvrement | Moyenne |
| 2 | `supplier_invoice_uploads` | Automatisation | Moyenne |
| 3 | `sales_orders` + lines | GesCom | Haute |
| 3 | `purchase_orders` + lines | GesCom | Haute |
| 3 | `delivery_notes` + lines | GesCom | Haute |
| 3 | `warehouses` | Stock | Moyenne |
| 3 | `stock_movements` | Stock | Haute |
| 3 | `stock_quantities` | Stock | Haute |
| 3 | `price_lists` + lines | Tarifs | Moyenne |
| 3 | `bill_of_materials` + lines | Production | Optionnel |
| 3 | `manufacturing_orders` | Production | Optionnel |
| 4 | `employees` (refonte) | Paie | Haute |
| 4 | `pay_runs` (refonte) | Paie | Haute |
| 4 | `pay_slips` | Paie | Haute |
| 4 | `leave_requests` | RH | Moyenne |
| 4 | `time_entries` | RH | Moyenne |
| 4 | `legal_declarations` | Paie | Moyenne |

**Total : ~28 nouvelles tables + 2 tables modifiées (journal_entries, journal_lines)**

---

## Tableau récapitulatif — Nouvelles pages

| Phase | Page | Route | Type | Priorité |
|---|---|---|---|---|
| 0 | Layout (refonte nav) | — | Refonte | **Bloquante** |
| 1 | `JournalsPage` | `/accounting/structure/journals` | Nouveau | **Bloquante** |
| 1 | `FiscalYearsPage` | `/system/fiscal-years` | Nouveau | **Bloquante** |
| 1 | `EntryTemplatesPage` | `/accounting/structure/entry-templates` | Nouveau | **Bloquante** |
| 1 | `ThirdPartyAccountsPage` | `/accounting/structure/third-party` | Nouveau | **Bloquante** |
| 1 | `JournalSaisiePage` | `/accounting/treatment/journal-entry` | Refonte | **Bloquante** |
| 1 | `LettragePage` | `/accounting/treatment/lettrage` | Nouveau | **Bloquante** |
| 1 | `SearchEntriesPage` | `/accounting/treatment/search` | Nouveau | Haute |
| 1 | `JournalClosurePage` | `/accounting/treatment/journal-closure` | Nouveau | Haute |
| 1 | `FiscalYearClosurePage` | `/accounting/treatment/fiscal-year-closure` | Nouveau | Haute |
| 1 | `BrouillardPage` | `/accounting/states/brouillard` | Nouveau | Haute |
| 1 | `AgedBalancePage` | `/accounting/states/aged-balance` | Nouveau | Haute |
| 1 | `EcheancierPage` | `/accounting/states/echeancier` | Nouveau | Haute |
| 1 | `GrandLivreTiersPage` | `/accounting/states/general-ledger-tiers` | Nouveau | Haute |
| 1 | `FECExportPage` | `/accounting/states/fec` | Nouveau | Moyenne |
| 1 | `SIGPage` | `/accounting/states/sig` | Nouveau | Moyenne |
| 1 | `AnalyticBalancePage` | `/accounting/states/analytic-balance` | Nouveau | Moyenne |
| 1 | `GeneralLedgerPage` | `/accounting/states/general-ledger` | Refonte | Haute |
| 1 | `TrialBalancePage` | `/accounting/states/trial-balance` | Refonte | Haute |
| 1 | `ChartAccountsPage` | `/accounting/structure/chart-accounts` | Refonte | Haute |
| 1 | `VatReturnsPage` | `/accounting/states/vat` | Refonte | Haute |
| 1 | `AnalyticSectionsPage` | `/accounting/structure/analytic` | Nouveau | Moyenne |
| 1 | `BudgetsPage` | `/accounting/structure/budgets` | Nouveau | Moyenne |
| 2 | `TreasuryDashboardPage` | `/treasury/dashboard` | Refonte | Haute |
| 2 | `TreasuryForecastPage` | `/treasury/forecast` | Nouveau | Haute |
| 2 | `PaymentOrdersPage` | `/treasury/payment-orders` | Nouveau | Haute |
| 2 | `FixedAssetsPage` | `/treasury/fixed-assets` | Refonte | Haute |
| 2 | `SupplierInvoiceAutomationPage` | `/treasury/invoice-automation` | Nouveau | Moyenne |
| 2 | `CollectionDashboardPage` | `/treasury/collection` | Nouveau | Moyenne |
| 3 | `SalesOrdersPage` | `/sales/orders` | Nouveau | Haute |
| 3 | `DeliveryNotesPage` | `/sales/delivery-notes` | Nouveau | Haute |
| 3 | `CustomerPaymentsPage` | `/sales/payments` | Nouveau | Haute |
| 3 | `PurchaseOrdersPage` | `/purchases/orders` | Nouveau | Haute |
| 3 | `GoodsReceiptPage` | `/purchases/goods-receipt` | Nouveau | Haute |
| 3 | `SupplierPaymentsPage` | `/purchases/payments` | Nouveau | Haute |
| 3 | `WarehousesPage` | `/stock/warehouses` | Nouveau | Moyenne |
| 3 | `StockMovementsPage` | `/stock/movements` | Nouveau | Haute |
| 3 | `StockQuantitiesPage` | `/stock/quantities` | Nouveau | Haute |
| 3 | `InventoryPage` | `/stock/inventory` | Nouveau | Moyenne |
| 3 | `ReorderPage` | `/stock/reorder` | Nouveau | Moyenne |
| 3 | `PriceListsPage` | `/commercial/price-lists` | Nouveau | Moyenne |
| 3 | `GescomTransferPage` | `/commercial/transfer` | Nouveau | Haute |
| 3 | `BOMPage` | `/production/bom` | Nouveau | Optionnel |
| 3 | `ManufacturingOrdersPage` | `/production/orders` | Nouveau | Optionnel |
| 4 | `EmployeesPage` | `/hr/employees` | Refonte | Haute |
| 4 | `PayRunsPage` | `/hr/pay-runs` | Refonte | Haute |
| 4 | `PaySlipsPage` | `/hr/pay-slips` | Nouveau | Haute |
| 4 | `LeaveRequestsPage` | `/hr/leave` | Nouveau | Moyenne |
| 4 | `TimeTrackingPage` | `/hr/time-tracking` | Nouveau | Moyenne |
| 4 | `LegalDeclarationsPage` | `/hr/declarations` | Nouveau | Moyenne |
| 4 | `PayrollAccountingPage` | `/hr/payroll-accounting` | Nouveau | Haute |
| 4 | `ContractsPage` | `/hr/contracts` | Nouveau | Moyenne |
| 4 | `TrainingPage` | `/hr/training` | Nouveau | Bas |
| 5 | `FinancialDashboardPage` | `/reporting/financial` | Refonte | Moyenne |
| 5 | `BIReportingPage` | `/reporting/bi` | Nouveau | Moyenne |
| 5 | `BudgetTrackingPage` | `/reporting/budget` | Nouveau | Moyenne |
| 5 | `AuditLogPage` | `/system/audit-log` | Nouveau | Bas |

**Total : ~57 pages (40 nouvelles + 12 refontes + 5 optionnelles)**

---

## Logique métier — Interactions entre modules

### Flux de données principal (Sage 100)

```
                    ┌──────────────────────────────────────────────┐
                    │              RÉFÉRENTIELS (Structure)         │
                    │  Plan comptable │ Plan tiers │ Codes journaux│
                    │  Modèles saisie │ Plan analy. │ Exercices    │
                    └──────────────┬───────────────────────────────┘
                                   │
                    ┌──────────────▼───────────────────────────────┐
                    │           SAISIE (Traitement)                 │
                    │  Saisie journaux │ Saisie par pièce │ Lot     │
                    │  Modèles → pré-remplissage                     │
                    └──────────────┬───────────────────────────────┘
                                   │
                    ┌──────────────▼───────────────────────────────┐
                    │         ÉCRITURES COMPTABLES                   │
                    │  journal_entries + journal_lines              │
                    │  (journal_code × période × N° pièce)          │
                    │  (compte général + compte tiers séparés)      │
                    └──────┬───────────────┬──────────────┬────────┘
                           │               │              │
                    ┌──────▼──────┐ ┌──────▼───────┐ ┌────▼──────────┐
                    │  LETTRAGE   │ │ RAPPROCHEMENT│ │  CLÔTURE      │
                    │  (tiers)    │ │  (banque)    │ │  (journaux/   │
                    │  → solde    │ │  → bank_txns │ │   exercice)   │
                    └──────┬──────┘ └──────┬───────┘ └────┬──────────┘
                           │               │              │
                    ┌──────▼───────────────▼──────────────▼──────────┐
                    │              ÉTATS (Éditions)                   │
                    │  Brouillard │ Journal │ Grand-livre │ Balance   │
                    │  Balance âgée │ Échéancier │ TVA │ Bilan │ SIG │
                    │  FEC │ Analytique │ Budgétaire                  │
                    └─────────────────────────────────────────────────┘
```

### Interactions inter-modules

| Source | Cible | Trigger | Action |
|---|---|---|---|
| Création client/fournisseur | `third_party_accounts` | Auto | Création compte tiers lié |
| Facture de vente (GesCom) | `journal_entries` | Transfert compta | Écriture journal VTE |
| Facture d'achat (GesCom) | `journal_entries` | Transfert compta | Écriture journal ACH |
| Règlement client/fournisseur | `journal_entries` + `payment_orders` | Validation | Écriture journal BQ + ordre SEPA |
| Lettrage | `journal_lines.lettrage_code` | Manuel/Auto | Blocage modification ligne |
| Rapprochement bancaire | `journal_lines.reconciled` + `bank_transactions` | Manuel/Auto | Lettrage banque |
| Clôture journal | `journal_entries.status_detail` | Manuel | Blocage saisie/édition |
| Clôture exercice | `fiscal_years.status` + nouvelles écritures | Workflow | Report à nouveau + soldes |
| Dotation immobilisation | `journal_entries` | Calcul auto | Écriture dotation annuelle |
| Comptabilisation paie | `journal_entries` | Validation pay_run | OD de paie (641/645/431/421) |
| Stock mouvement | `stock_movements` + `stock_quantities` | Réception/livraison | Mise à jour quantités + valorisation |
| Commande → Livraison → Facture | `sales_orders` → `delivery_notes` → `invoices` | Workflow | Enchaînement automatique |
| Recouvrement | `collection_cases` | Facture impayée | Génération auto + relances |

---

## Ordre d'implémentation recommandé

### Sprint 1 (Phase 0 + 1.1 — Fondations)
1. Refonte navigation `Layout.tsx` + routes `App.tsx`
2. Création tables : `journals`, `fiscal_years`, `fiscal_periods`, `entry_templates`, `third_party_accounts`, `analytic_sections`, `standard_labels`
3. Migration `journal_entries` + `journal_lines` (ALTER + nouvelles colonnes)
4. Pages CRUD : `JournalsPage`, `FiscalYearsPage`, `EntryTemplatesPage`, `ThirdPartyAccountsPage`

### Sprint 2 (Phase 1.3 — Saisie & lettrage)
5. Refonte `JournalSaisiePage` (écran principal de saisie journal × période)
6. `LettragePage` (interrogation & lettrage manuel/auto)
7. `SearchEntriesPage` (recherche multi-critères)
8. `JournalClosurePage` (clôture journaux × périodes)

### Sprint 3 (Phase 1.4 — États)
9. `BrouillardPage`, `AgedBalancePage`, `EcheancierPage`
10. `GrandLivreTiersPage`, refonte `GeneralLedgerPage` + `TrialBalancePage`
11. `SIGPage`, `AnalyticBalancePage`, `FECExportPage`
12. Refonte `ChartAccountsPage` + `VatReturnsPage`

### Sprint 4 (Phase 1.5 — Clôture)
13. `FiscalYearClosurePage` (nouvel exercice + report à nouveau + clôture)
14. `AnalyticSectionsPage`, `BudgetsPage`

### Sprint 5 (Phase 2 — Trésorerie & finance)
15. `TreasuryDashboardPage` + `TreasuryForecastPage`
16. `PaymentOrdersPage` (SEPA, chèques, remises)
17. Refonte `FixedAssetsPage` (amortissements, cessions, dotations)
18. `SupplierInvoiceAutomationPage` (OCR)
19. `CollectionDashboardPage` (recouvrement, relances)

### Sprint 6 (Phase 3 — GesCom)
20. `SalesOrdersPage` + `DeliveryNotesPage` + `CustomerPaymentsPage`
21. `PurchaseOrdersPage` + `GoodsReceiptPage` + `SupplierPaymentsPage`
22. `WarehousesPage` + `StockMovementsPage` + `StockQuantitiesPage`
23. `InventoryPage` + `ReorderPage` + `PriceListsPage`
24. `GescomTransferPage` (transfert comptable)
25. (Optionnel) `BOMPage` + `ManufacturingOrdersPage`

### Sprint 7 (Phase 4 — Paie & RH)
26. Refonte `EmployeesPage` (fiche complète)
27. Refonte `PayRunsPage` + `PaySlipsPage` (calcul paie)
28. `PayrollAccountingPage` (OD de paie)
29. `LeaveRequestsPage` + `TimeTrackingPage`
30. `LegalDeclarationsPage` + `ContractsPage`

### Sprint 8 (Phase 5 — Reporting & BI)
31. `FinancialDashboardPage` (refonte)
32. `BIReportingPage` + `BudgetTrackingPage`
33. `AuditLogPage`

---

## Fichiers à modifier/créer — Résumé

### À modifier (existants)
| Fichier | Phase | Changement |
|---|---|---|
| `app/supabase-schema.sql` | 1-4 | +28 tables, ALTER journal_entries/lines |
| `app/src/components/Layout.tsx` | 0 | Refonte navGroups (Structure/Traitement/État) |
| `app/src/App.tsx` | 0-5 | +57 routes |
| `app/src/lib/queries.ts` | 1-4 | +28 sections de queries |
| `app/src/types/index.ts` | 1-4 | +28 types TypeScript |
| `app/src/pages/JournalEntriesPage.tsx` | 1 | Refonte → `JournalSaisiePage` |
| `app/src/pages/GeneralLedgerPage.tsx` | 1 | Enrichissement filtres + colonnes |
| `app/src/pages/TrialBalancePage.tsx` | 1 | Enrichissement (4/6/8 colonnes) |
| `app/src/pages/ChartAccountsPage.tsx` | 1 | Ajout type compte + lien tiers |
| `app/src/pages/VatReturnsPage.tsx` | 1 | Calcul auto depuis écritures |
| `app/src/pages/FixedAssetsPage.tsx` | 2 | Refonte complète (amortissements) |
| `app/src/pages/EmployeesPage.tsx` | 4 | Refonte (fiche complète) |
| `app/src/pages/PayRunsPage.tsx` | 4 | Refonte (génération + calcul) |
| `app/src/pages/DashboardPage.tsx` | 5 | Refonte (KPIs Sage 100) |

### À créer (nouveaux) — ~40 fichiers de pages + types + queries
- Pages : voir tableau récapitulatif ci-dessus
- Types : `app/src/types/index.ts` (étendre avec tous les nouveaux types)
- Queries : `app/src/lib/queries.ts` (étendre avec toutes les nouvelles fonctions CRUD)
- Migrations SQL : `app/supabase-migrations/` (un fichier par phase)
