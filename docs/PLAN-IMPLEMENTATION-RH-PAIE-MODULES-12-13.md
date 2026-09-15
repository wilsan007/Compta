# Plan d'Implémentation — RH & Paie (Modules 12 + 13)

> **Source** : SAGE-100-REFERENCE-COMPLETE.md (Sections 12 et 13)
> **Exclu** : Module 14 — Sage Espace Employés (traité dans un plan séparé)
> **i18n** : Toutes nouvelles pages doivent utiliser `useTranslation` (fr, en, ar)

---

## Contexte

### Déjà implémenté (pages UI + queries + types + SQL) ✅

| Fonctionnalité | Page | Route |
|---|---|---|
| Fiches personnel | `EmployeesPage` | `/hr/employees` |
| Préparation paie | `PayRunsPage` | `/hr/pay-runs` |
| Bulletins de salaire | `PaySlipsPage` | `/hr/pay-slips` |
| Passation comptable | `PayrollAccountingPage` | `/hr/payroll-accounting` |
| Composants de paie | `PayrollComponentsPage` | `/hr/payroll-components` |
| Modèles de bulletins | `PayrollTemplatesPage` | `/hr/payroll-templates` |
| Acomptes | `SalaryAdvancesPage` | `/hr/salary-advances` |
| Rappels de salaire | `PayRecallsPage` | `/hr/pay-recalls` |
| DSN | `DSNPage` | `/hr/dsn` |
| DPAE | `DPAEPage` | `/hr/dpae` |
| Veille juridique | `LegalWatchPage` | `/hr/legal-watch` |
| Archivage paie | `PayrollArchivePage` | `/hr/payroll-archives` |
| Notes de frais (admin) | `ExpenseReportsPage` | `/hr/expense-reports` |
| Entretiens (admin) | `InterviewsPage` | `/hr/interviews` |
| Demandes de congés (admin) | `LeaveRequestsPage` | `/hr/leave-requests` |
| Contrats | `ContractsPage` | `/hr/contracts` |
| Déclarations légales | `LegalDeclarationsPage` | `/hr/declarations` |
| Feuilles de temps | `TimesheetsPage` | `/hr/timesheets` |
| Calcul de paie | `PayrollCalcPage` | `/hr/payroll-calc` |
| Dashboard RH | `HRDashboardPage` | `/dashboard/hr` |

### Types + Queries + SQL existants MAIS sans page UI ❌

| Fonctionnalité | Type | Queries | SQL Table | Page UI |
|---|---|---|---|---|
| **Pénibilité** | `WorkHardship` ✅ | `getWorkHardship`, `createWorkHardship` ✅ | `work_hardship` ✅ | ❌ |
| **Suivi carrières** | `CareerHistory` ✅ | `getCareerHistory`, `createCareerHistory` ✅ | `career_history` ✅ | ❌ |
| **CPF** | `CpfAccount` ✅ | `getCpfAccounts`, `updateCpfAccount` ✅ | `cpf_accounts` ✅ | ❌ |
| **Documents employés** | `EmployeeDocument` ✅ | `getEmployeeDocuments`, `createEmployeeDocument` ✅ | `employee_documents` ✅ | ❌ |

### Totalement manquant (types + queries + SQL + pages) ❌

Voir détail dans les sprints ci-dessous.

---

## Sommaire

1. [Sprint A — Pages manquantes pour queries existantes](#sprint-a--pages-manquantes-pour-queries-existantes)
2. [Sprint B — Fonctionnalités Paie avancées (Module 12)](#sprint-b--fonctionnalités-paie-avancées)
3. [Sprint C — Déclarations sociales spécifiques (Module 12)](#sprint-c--déclarations-sociales-spécifiques)
4. [Sprint D — Dématérialisation RH (Module 13)](#sprint-d--dématérialisation-rh)
5. [Sprint E — Extension des pages existantes](#sprint-e--extension-des-pages-existantes)
6. [Sprint F — i18n](#sprint-f--i18n)

---

## Sprint A — Pages manquantes pour queries existantes

> **Prérequis** : Aucun — les tables SQL, types et queries existent déjà
> **Effort** : Faible (création de pages UI uniquement)
> **Fichiers créés** : 4 | **Fichiers modifiés** : 2

### A.1 — Page : WorkHardshipPage (Pénibilité)

**Fichier : `@/pages/hr/WorkHardshipPage.tsx`** (nouveau)

**Structure :**
- **Table** : Employé, Type d'exposition, Niveau (low/medium/high), Date début, Date fin, Points C3P, Notes, Actions
- **Bouton "Nouvelle exposition"** : modal avec formulaire
  - Employé (select)
  - Type d'exposition (select : bruit, posture, produits chimiques, manutention, vibrations, températures extrêmes, autres)
  - Niveau d'exposition (low/medium/high)
  - Date de début / fin
  - Points (nombre décimal)
  - Notes
- **Cartes de synthèse** par type d'exposition : nb employés exposés, niveau moyen, total points
- **Filtres** : employé, type, niveau
- **Export Excel** pour déclaration C3P

### A.2 — Page : CareerHistoryPage (Suivi des carrières)

**Fichier : `@/pages/hr/CareerHistoryPage.tsx`** (nouveau)

**Structure :**
- **Table** : Employé, Date, Événement, Ancien poste, Nouveau poste, Ancien salaire, Nouveau salaire, Notes
- **Type d'événement** : embauche, promotion, transfert, changement salaire, départ
- **Bouton "Nouvel événement"** : modal avec formulaire
  - Employé (select)
  - Type d'événement (select)
  - Date
  - Poste / département
  - Salaire
  - Notes
- **Vue timeline par employé** : sélectionner un employé → afficher sa chronologie de carrière
- **Filtres** : employé, type d'événement, période

### A.3 — Page : CPFPage (Compte Personnel de Formation)

**Fichier : `@/pages/hr/CPFPage.tsx`** (nouveau)

**Structure :**
- **Table** : Employé, Solde CPF (heures), Montant (€), Dernière mise à jour
- **Bouton "Mettre à jour le solde"** : modal avec formulaire
  - Employé (select)
  - Solde heures
  - Montant
- **Section "Historique des utilisations"** : table des formations utilisant le CPF
  - Employé, Formation, Heures consommées, Date
- **Alertes** : CPF avec solde important non utilisé, CPF expirant
- **Filtres** : employé, période

### A.4 — Page : EmployeeDocumentsPage (Coffre-fort documents RH)

**Fichier : `@/pages/hr/EmployeeDocumentsPage.tsx`** (nouveau)

**Structure :**
- **Table** : Employé, Type document, Fichier, Distribué le, Accusé de réception, Date, Actions
- **Types** : bulletin de paie, contrat, DPAE, DSN, certificat, autre
- **Bouton "Déposer un document"** : modal avec formulaire
  - Employé (select)
  - Type de document (select)
  - Fichier (upload vers Supabase Storage)
  - Nom du fichier (auto-rempli)
- **Bouton "Distribution en lot"** : sélectionner un pay_run → distribuer automatiquement les bulletins
- **Bouton "Télécharger"** : télécharge le document
- **Bouton "Supprimer"**
- **Filtres** : employé, type, période
- **Statistiques** : nb documents par type, taux d'accusé de réception

### A.5 — Queries manquantes à ajouter

```typescript
// Compléter les queries existantes avec les CRUD manquants :
export async function updateWorkHardship(id, updates)
export async function deleteWorkHardship(id)
export async function createCareerHistory(c)  // existe déjà
export async function updateCareerHistory(id, updates)
export async function deleteCareerHistory(id)
export async function createCpfAccount(data)  // create manquant
export async function deleteCpfAccount(id)
export async function deleteEmployeeDocument(id)
export async function distributePaySlips(payRunId)
// Pour chaque pay_slip du pay_run, créer un employee_document de type 'payslip'
```

### A.6 — Routes App.tsx

```tsx
<Route path="/hr/hardship" element={<WorkHardshipPage />} />
<Route path="/hr/career" element={<CareerHistoryPage />} />
<Route path="/hr/cpf" element={<CPFPage />} />
<Route path="/hr/employee-documents" element={<EmployeeDocumentsPage />} />
```

---

## Sprint B — Fonctionnalités Paie avancées

> **Prérequis** : Sprint A
> **Effort** : Important
> **Fichiers créés** : 4 | **Fichiers modifiés** : 4

### B.1 — SQL

```sql
-- Étendre employees avec données RH complètes (état civil, etc.)
alter table employees add column if not exists first_name text;
alter table employees add column if not exists last_name text;
alter table employees add column if not exists birth_date date;
alter table employees add column if not exists birth_place text;
alter table employees add column if not exists nationality text;
alter table employees add column if not exists social_security_number text;
alter table employees add column if not exists address text;
alter table employees add column if not exists postal_code text;
alter table employees add column if not exists city text;
alter table employees add column if not exists country text default 'FR';
alter table employees add column if not exists emergency_contact_name text;
alter table employees add column if not exists emergency_contact_phone text;
alter table employees add column if not exists bank_iban text;
alter table employees add column if not exists bank_bic text;
alter table employees add column if not exists marital_status text;
alter table employees add column if not exists dependents_count int default 0;
alter table employees add column if not exists transport_mode text;
alter table employees add column if not exists transport_cost decimal(15,2) default 0;
alter table employees add column if not exists meal_voucher_count int default 0;
alter table employees add column if not exists meal_voucher_value decimal(15,2) default 0;
alter table employees add column if not exists manager_id uuid;
alter table employees add column if not exists exit_date date;
alter table employees add column if not exists exit_reason text;

-- Table des titres restaurant (paramétrage)
create table if not exists meal_voucher_config (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  voucher_value decimal(15,2) not null default 3.50,  -- valeur unitaire
  employer_share decimal(5,2) default 60,              -- % employeur
  employee_share decimal(5,2) default 40,              -- % salarié
  eligible_days text[] default '{1,2,3,4,5}',          -- jours éligibles (1=lun...5=ven)
  max_per_month int default 20,
  active boolean default true,
  created_at timestamptz default now()
);
alter table meal_voucher_config enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_meal_voucher_config') THEN
    CREATE POLICY "allow_all_meal_voucher_config" ON meal_voucher_config FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- Table des éléments variables de paie (collecte mensuelle)
create table if not exists payroll_variable_elements (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  employee_id uuid not null references employees(id) on delete cascade,
  pay_run_id uuid,                   -- lié à un pay_run ou null si non encore intégré
  period text not null,              -- '2024-01'
  element_type text not null,        -- 'overtime', 'bonus', 'commission', 'absence', 'meal_voucher', 'transport', 'other'
  description text,
  quantity decimal(15,3),            -- nb heures, nb jours, nb titres...
  unit_price decimal(15,2),
  amount decimal(15,2) not null default 0,
  source text,                       -- 'manual', 'timesheet', 'leave_request', 'expense_report', 'import'
  source_id uuid,                    -- ID de la source (timesheet_id, etc.)
  integrated boolean default false,  -- intégré dans le bulletin ?
  created_at timestamptz default now()
);
alter table payroll_variable_elements enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_payroll_variable_elements') THEN
    CREATE POLICY "allow_all_payroll_variable_elements" ON payroll_variable_elements FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- Table du solde de tout compte (sortie salarié)
create table if not exists final_settlements (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  employee_id uuid not null references employees(id) on delete cascade,
  exit_date date not null,
  exit_reason text,
  -- Indemnité compensatrice de congés payés
  cp_acquired decimal(5,2) default 0,
  cp_taken decimal(5,2) default 0,
  cp_remaining decimal(5,2) default 0,
  cp_indemnity decimal(15,2) default 0,
  -- Indemnité compensatrice de RTT
  rtt_acquired decimal(5,2) default 0,
  rtt_taken decimal(5,2) default 0,
  rtt_remaining decimal(5,2) default 0,
  rtt_indemnity decimal(15,2) default 0,
  -- Primes sur la période
  bonus_amount decimal(15,2) default 0,
  -- Acomptes à déduire
  advance_deduction decimal(15,2) default 0,
  -- Heures sup non payées
  overtime_hours decimal(15,3) default 0,
  overtime_amount decimal(15,2) default 0,
  -- Total
  total_gross decimal(15,2) default 0,
  total_deductions decimal(15,2) default 0,
  total_net decimal(15,2) default 0,
  -- Documents générés
  work_certificate_url text,         -- certificat de travail
  settlement_receipt_url text,       -- reçu pour solde de tout compte
  pole_emploi_attestation_url text,  -- attestation Pôle Emploi
  -- DSN fin de contrat
  dsn_exit_id uuid,                  -- lien vers dsn_declarations
  status text default 'draft' check (status in ('draft', 'calculated', 'validated', 'paid')),
  created_at timestamptz default now()
);
alter table final_settlements enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_final_settlements') THEN
    CREATE POLICY "allow_all_final_settlements" ON final_settlements FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- Étendre pay_slips avec type
alter table pay_slips add column if not exists slip_type text default 'normal' check (slip_type in ('normal', 'advance', 'recall', 'exit'));
```

### B.2 — Types TypeScript

```typescript
export interface MealVoucherConfig {
  id: string
  tenant_id: string | null
  voucher_value: number
  employer_share: number
  employee_share: number
  eligible_days: string[]
  max_per_month: number
  active: boolean
  created_at: string
}

export interface PayrollVariableElement {
  id: string
  tenant_id: string | null
  employee_id: string
  pay_run_id: string | null
  period: string
  element_type: 'overtime' | 'bonus' | 'commission' | 'absence' | 'meal_voucher' | 'transport' | 'other'
  description: string | null
  quantity: number | null
  unit_price: number | null
  amount: number
  source: 'manual' | 'timesheet' | 'leave_request' | 'expense_report' | 'import'
  source_id: string | null
  integrated: boolean
  created_at: string
}

export interface FinalSettlement {
  id: string
  tenant_id: string | null
  employee_id: string
  exit_date: string
  exit_reason: string | null
  cp_acquired: number
  cp_taken: number
  cp_remaining: number
  cp_indemnity: number
  rtt_acquired: number
  rtt_taken: number
  rtt_remaining: number
  rtt_indemnity: number
  bonus_amount: number
  advance_deduction: number
  overtime_hours: number
  overtime_amount: number
  total_gross: number
  total_deductions: number
  total_net: number
  work_certificate_url: string | null
  settlement_receipt_url: string | null
  pole_emploi_attestation_url: string | null
  dsn_exit_id: string | null
  status: 'draft' | 'calculated' | 'validated' | 'paid'
  created_at: string
}

// Étendre Employee avec les nouveaux champs
// Étendre PaySlip avec slip_type
```

### B.3 — Page : PayrollPreparationPage (Assistant de préparation)

**Fichier : `@/pages/hr/PayrollPreparationPage.tsx`** (nouveau)

**Structure :**
- **Étape 1 : Sélection de la période**
  - Mois/année, pay_run existant ou nouveau
- **Étape 2 : Report des éléments constants**
  - Liste des employés actifs avec salaire de base
  - Checkbox pour inclure/exclure un employé
- **Étape 3 : Saisie des éléments variables**
  - Pour chaque employé : table des éléments variables
  - Bouton "Importer depuis les timesheets approuvés"
  - Bouton "Importer depuis les congés" (déduction jours non travaillés)
  - Bouton "Importer depuis les notes de frais approuvées"
  - Saisie manuelle : heures sup, primes, commissions, absences
  - Calcul automatique des titres restaurant (basé sur le config)
  - Calcul automatique des frais de transport
- **Étape 4 : Calcul et prévisualisation**
  - Table récapitulative : brut, cotisations, net, employeur
  - Alertes : anomalies, écarts par rapport au mois précédent
  - Bouton "Calcul à l'envers" pour un employé (input net → output brut)
- **Étape 5 : Validation**
  - Génération des bulletins (pay_slips)
  - Marquage des éléments variables comme `integrated = true`

### B.4 — Page : MealVouchersPage (Titres restaurant)

**Fichier : `@/pages/hr/MealVouchersPage.tsx`** (nouveau)

**Structure :**
- **Onglet 1 : "Paramétrage"**
  - Configuration : valeur du titre, part employeur/salarié, jours éligibles, max/mois
- **Onglet 2 : "Calcul mensuel"**
  - Sélection du mois
  - Table : Employé, Jours travaillés, Nb titres, Valeur unitaire, Part employeur, Part salarié, Total
  - Calcul automatique basé sur les timesheets et le paramétrage
  - Bouton "Générer les éléments variables" → crée des `payroll_variable_elements` de type `meal_voucher`
- **Onglet 3 : "Export commande"**
  - Export CSV/Excel pour commande auprès du fournisseur (Edenred, Sodexo, etc.)

### B.5 — Page : EmployeeExitPage (Assistant de sortie)

**Fichier : `@/pages/hr/EmployeeExitPage.tsx`** (nouveau)

**Structure :**
- **Étape 1 : Sélection de l'employé**
- **Étape 2 : Date et motif de sortie**
- **Étape 3 : Calcul du solde de tout compte**
  - Récupération automatique des congés payés (acquis - pris = restant)
  - Récupération des RTT
  - Récupération des acomptes non déduits
  - Récupération des heures sup non payées
  - Saisie des primes sur la période
  - Calcul automatique du total brut, déductions, net
- **Étape 4 : Documents de sortie**
  - Certificat de travail (génération PDF)
  - Reçu pour solde de tout compte (génération PDF)
  - Attestation Pôle Emploi / France Travail (génération PDF)
- **Étape 5 : Déclarations**
  - Génération automatique d'une DSN fin de contrat
- **Étape 6 : Validation**
  - Mise à jour du statut employé → 'inactive'
  - Définition de `exit_date` et `exit_reason`
  - Génération du bulletin de sortie (pay_slip avec `slip_type = 'exit'`)
  - Archivage des documents dans `employee_documents`

### B.6 — Queries

```typescript
// ============ Meal Vouchers ============
export async function getMealVoucherConfig()
export async function updateMealVoucherConfig(id, updates)
export async function calculateMealVouchers(month, year)
// Pour chaque employé actif : nb jours travaillés × valeur du titre
export async function generateMealVoucherElements(payRunId, month, year)
// Crée des payroll_variable_elements de type 'meal_voucher'

// ============ Variable Elements ============
export async function getVariableElements(payRunId?, employeeId?, period?)
export async function createVariableElement(data)
export async function updateVariableElement(id, updates)
export async function deleteVariableElement(id)
export async function importTimesheetElements(payRunId, month, year)
// Récupère les timesheets approuvés et crée des éléments variables
export async function importLeaveElements(payRunId, month, year)
// Récupère les congés approuvés et crée des déductions
export async function importExpenseElements(payRunId, month, year)
// Récupère les notes de frais approuvées et crée des éléments

// ============ Reverse Calculation ============
export function calculateGrossFromNet(targetNet, components, employeeProfile)
// Logique : itération pour trouver le brut qui donne le net souhaité

// ============ Final Settlement ============
export async function getFinalSettlements()
export async function createFinalSettlement(employeeId, exitDate, exitReason)
export async function calculateFinalSettlement(id)
// Calcule automatiquement le solde de tout compte
export async function validateFinalSettlement(id)
// Valide + génère les documents + met à jour l'employé
export async function generateExitDocuments(id)
// Génère certificat de travail, reçu, attestation Pôle Emploi
```

### B.7 — Extension des pages existantes

**`PayRunsPage.tsx`** (modifier) :
- Ajouter bouton "Assistant de préparation" → redirige vers `PayrollPreparationPage`
- Ajouter colonne "Type" pour distinguer les pay_runs normaux / sortie

**`PaySlipsPage.tsx`** (modifier) :
- Ajouter colonne "Type" (normal, acompte, rappel, sortie)
- Ajouter bouton "Bulletin de sortie" sur les employés inactifs

**`PayrollCalcPage.tsx`** (modifier) :
- Ajouter mode "Calcul à l'envers" : input net souhaité → output brut
- Ajouter gestion détaillée des titres restaurant (basé sur le config)
- Ajouter gestion des frais de transport (forfait mobilité durable)

**`EmployeesPage.tsx`** (modifier) :
- Ajouter tous les nouveaux champs dans le formulaire (état civil, coords, RIB, etc.)
- Ajouter bouton "Assistant de sortie" sur les employés actifs
- Ajouter section "Manager" (select parmi les autres employés)

---

## Sprint C — Déclarations sociales spécifiques

> **Prérequis** : Sprint B
> **Effort** : Moyen
> **Fichiers créés** : 1 | **Fichiers modifiés** : 3

### C.1 — SQL

```sql
-- Table générique pour toutes les déclarations sociales
create table if not exists social_declarations (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  number text not null,
  declaration_type text not null check (declaration_type in (
    'dsn', 'dads_u', 'ducs', 'aed', 'dts_msa', 'cibtp', 'conges_payes_btp',
    'cice', 'refus_cdi', 'ct2025', 'other'
  )),
  period_month int,
  period_year int,
  period text,                       -- '2024-01'
  due_date date,
  status text default 'draft' check (status in ('draft', 'generated', 'transmitted', 'accepted', 'rejected')),
  file_url text,                     -- fichier généré (XML, CSV, PDF)
  generated_at timestamptz,
  transmitted_at timestamptz,
  response_code text,
  response_message text,
  amount decimal(15,2),              -- montant déclaré (si applicable)
  notes text,
  created_at timestamptz default now()
);
alter table social_declarations enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_social_declarations') THEN
    CREATE POLICY "allow_all_social_declarations" ON social_declarations FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- Table de paramétrage CICE
create table if not exists cice_config (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  year int not null,
  smic_threshold decimal(15,2) default 2.5,  -- multiple du SMIC
  rate decimal(5,2) default 6,               -- taux CICE %
  eligible_salary_cap decimal(15,2),          -- plafond
  active boolean default true,
  created_at timestamptz default now()
);
alter table cice_config enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_cice_config') THEN
    CREATE POLICY "allow_all_cice_config" ON cice_config FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
```

### C.2 — Types TypeScript

```typescript
export interface SocialDeclaration {
  id: string
  tenant_id: string | null
  number: string
  declaration_type: 'dsn' | 'dads_u' | 'ducs' | 'aed' | 'dts_msa' | 'cibtp' | 'conges_payes_btp' | 'cice' | 'refus_cdi' | 'ct2025' | 'other'
  period_month: number | null
  period_year: number | null
  period: string | null
  due_date: string | null
  status: 'draft' | 'generated' | 'transmitted' | 'accepted' | 'rejected'
  file_url: string | null
  generated_at: string | null
  transmitted_at: string | null
  response_code: string | null
  response_message: string | null
  amount: number | null
  notes: string | null
  created_at: string
}

export interface CiceConfig {
  id: string
  tenant_id: string | null
  year: number
  smic_threshold: number
  rate: number
  eligible_salary_cap: number | null
  active: boolean
  created_at: string
}
```

### C.3 — Page : SocialDeclarationsPage

**Fichier : `@/pages/hr/SocialDeclarationsPage.tsx`** (nouveau)

**Structure :**
- **Onglet "DSN"** (existant + améliorations) :
  - IntuiDSN : wizard visuel étape par étape pour la DSN
  - Vérification des anomalies avant transmission
  - Suivi des retours (accepté/rejeté) avec codes d'erreur
  - Historique des transmissions
- **Onglet "DADS-U"** :
  - Génération du fichier DADS-U (format XML)
  - Téléchargement
  - Historique
- **Onglet "DUCS"** :
  - Génération de la DUCS URSSAF
  - Téléchargement
- **Onglet "AED"** :
  - Attestation employeur (génération à la demande pour un employé)
  - Téléchargement PDF
- **Onglet "BTP"** :
  - CIBTP : génération + téléchargement
  - Congés Payés BTP : génération + téléchargement
- **Onglet "MSA"** :
  - DTS-MSA : génération + téléchargement (secteur agricole)
- **Onglet "CICE"** :
  - Paramétrage (table cice_config)
  - Calcul du CICE pour l'année
  - Génération du fichier
- **Onglet "Autres"** :
  - Déclaration de refus de CDI
  - CT2025
  - Gestion des honoraires

### C.4 — Queries

```typescript
export async function getSocialDeclarations(type?, period?)
export async function createSocialDeclaration(data)
export async function updateSocialDeclaration(id, updates)
export async function generateDADSU(period)
export async function generateDUCS(period)
export async function generateAED(employeeId)
export async function generateDTSMSA(period)
export async function generateCIBTP(period)
export async function generateCongesPayesBTP(period)
export async function generateRefusCDI(period)
export async function generateCT2025(period)
export async function getCiceConfig(year?)
export async function updateCiceConfig(id, updates)
export async function calculateCICE(year)
// Calcule le CICE pour tous les employés éligibles
```

### C.5 — Extension des pages existantes

**`LegalDeclarationsPage.tsx`** (modifier) :
- Ajouter liens vers les nouveaux onglets (DADS-U, DUCS, AED, BTP, MSA, CICE, autres)
- Ou rediriger vers `SocialDeclarationsPage`

**`DSNPage.tsx`** (modifier) :
- Ajouter IntuiDSN : wizard visuel étape par étape
  - Étape 1 : Sélection de la période
  - Étape 2 : Vérification des données (anomalies, manquants)
  - Étape 3 : Génération du fichier
  - Étape 4 : Transmission
  - Étape 5 : Suivi du retour
- Ajouter contrôle des anomalies (validation des données avant transmission)
- Ajouter suivi des retours avec codes d'erreur Net-Entreprises
- Ajouter historique des transmissions

**`PayrollArchivePage.tsx`** (modifier) :
- Ajouter bouton "Passation comptable CSV" : export des écritures de paie au format CSV avec ordonnancement
- Ajouter bouton "Régularisation brut" : régularisation des données de type brut sans impact sur les cotisations

---

## Sprint D — Dématérialisation RH

> **Prérequis** : Sprint A (EmployeeDocumentsPage doit exister)
> **Effort** : Important
> **Fichiers créés** : 3 | **Fichiers modifiés** : 3

### D.1 — SQL

```sql
-- Étendre employee_documents avec champs de dématérialisation
alter table employee_documents add column if not exists file_size bigint;
alter table employee_documents add column if not exists mime_type text;
alter table employee_documents add column if not exists period text;               -- '2024-01' pour bulletin
alter table employee_documents add column if not exists uploaded_by uuid;
alter table employee_documents add column if not exists visible_to_employee boolean default true;
alter table employee_documents add column if not exists requires_acknowledgment boolean default false;
alter table employee_documents add column if not exists e_signed boolean default false;
alter table employee_documents add column if not exists e_signed_at timestamptz;
alter table employee_documents add column if not exists e_signature_hash text;

-- Table des requêtes RH (formulaires personnalisés)
create table if not exists rh_requests (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  employee_id uuid not null references employees(id) on delete cascade,
  request_type text not null,        -- 'document_copy', 'certificate', 'leave_info', 'salary_change', 'address_change', 'other'
  subject text not null,
  description text,
  status text default 'pending' check (status in ('pending', 'in_progress', 'resolved', 'rejected')),
  assigned_to uuid,                  -- user RH assigné
  response text,
  resolved_at timestamptz,
  created_at timestamptz default now()
);
alter table rh_requests enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_rh_requests') THEN
    CREATE POLICY "allow_all_rh_requests" ON rh_requests FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- Table de la base de connaissances RH
create table if not exists rh_knowledge_base (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  title text not null,
  content text not null,
  category text,                     -- 'paie', 'conges', 'contrats', 'droit', 'procedure', 'other'
  tags text[],
  author_id uuid,
  published boolean default false,
  views int default 0,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
alter table rh_knowledge_base enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_rh_knowledge_base') THEN
    CREATE POLICY "allow_all_rh_knowledge_base" ON rh_knowledge_base FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- Table de pilotage de l'activité documentaire
create table if not exists document_distribution_logs (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  batch_id uuid,                     -- identifiant de lot
  employee_document_id uuid references employee_documents(id) on delete cascade,
  employee_id uuid not null references employees(id) on delete cascade,
  document_type text,
  period text,
  distributed_at timestamptz,
  acknowledged_at timestamptz,
  status text default 'distributed' check (status in ('distributed', 'acknowledged', 'bounced', 'failed')),
  created_at timestamptz default now()
);
alter table document_distribution_logs enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_document_distribution_logs') THEN
    CREATE POLICY "allow_all_document_distribution_logs" ON document_distribution_logs FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
```

### D.2 — Types TypeScript

```typescript
// Étendre EmployeeDocument avec les nouveaux champs

export interface RhRequest {
  id: string
  tenant_id: string | null
  employee_id: string
  request_type: 'document_copy' | 'certificate' | 'leave_info' | 'salary_change' | 'address_change' | 'other'
  subject: string
  description: string | null
  status: 'pending' | 'in_progress' | 'resolved' | 'rejected'
  assigned_to: string | null
  response: string | null
  resolved_at: string | null
  created_at: string
}

export interface RhKnowledgeBaseArticle {
  id: string
  tenant_id: string | null
  title: string
  content: string
  category: string | null
  tags: string[]
  author_id: string | null
  published: boolean
  views: number
  created_at: string
  updated_at: string
}

export interface DocumentDistributionLog {
  id: string
  tenant_id: string | null
  batch_id: string | null
  employee_document_id: string
  employee_id: string
  document_type: string
  period: string | null
  distributed_at: string | null
  acknowledged_at: string | null
  status: 'distributed' | 'acknowledged' | 'bounced' | 'failed'
  created_at: string
}
```

### D.3 — Page : DocumentManagementPage (Gestion documentaire RH)

**Fichier : `@/pages/hr/DocumentManagementPage.tsx`** (nouveau)

**Structure :**
- **Onglet 1 : "Documents"**
  - Table : Employé, Type, Titre, Période, Visible employé, Accusé réception, Signé, Date, Actions
  - Bouton "Déposer un document" (upload + sélection employé)
  - Bouton "Dépôt manuel hors bulletin" (avec ou sans annexes)
  - Bouton "Synchroniser bulletins d'un mois précédent" (dépôt manuel rétroactif)
- **Onglet 2 : "Distribution bulletins"**
  - Sélection d'un pay_run
  - Bouton "Contrôle de lot" : vérification avant envoi (cohérence, nb destinataires, doublons)
  - Bouton "Distribuer" → distribue tous les bulletins dans les coffres-forts
  - Table de suivi : Employé, Bulletin distribué, Accusé de réception, Date distribution
  - Bouton "Relancer" pour les non-accusés
- **Onglet 3 : "Pilotage documentaire"**
  - Cartes : nb documents totaux, nb bulletins distribués, taux d'accusé de réception, nb e-signatures
  - Graphique : distribution par type, par mois
  - Table : documents non accusés (relance possible)
  - Indicateurs en temps réel sur l'activité et le contenu de la plateforme
- **Onglet 4 : "e-Signature"**
  - Table des documents en attente de signature : Employé, Document, Date demande, Statut
  - Bouton "Envoyer demande de signature" (sélection document + employé)
  - Suivi des signatures en temps réel (hash + timestamp)

### D.4 — Page : RhRequestsPage (Relation RH-Salariés)

**Fichier : `@/pages/hr/RhRequestsPage.tsx`** (nouveau)

**Structure :**
- **Table** : Employé, Type de demande, Sujet, Statut, Assigné à, Date, Actions
- **Types de demande** : copie de document, certificat, information congés, changement salaire, changement adresse, autre
- **Bouton "Nouvelle demande"** : modal (employé, type, sujet, description)
- **Bouton "Assigner"** : assigner à un gestionnaire RH
- **Bouton "Traiter"** : modal avec réponse + changement de statut
- **Règles d'attribution automatique** : selon le type de demande, assigner au bon interlocuteur RH
- **Suivi en temps réel** du traitement des requêtes
- **Filtres** : statut, type, employé, période
- **Statistiques** : nb requêtes en attente, temps moyen de traitement, taux de résolution

### D.5 — Page : RhKnowledgeBasePage (Base de connaissances RH)

**Fichier : `@/pages/hr/RhKnowledgeBasePage.tsx`** (nouveau)

**Structure :**
- **Vue articles** : cards avec titre, catégorie, vues, extrait
- **Recherche full-text** : barre de recherche
- **Filtres** : catégorie (paie, congés, contrats, droit, procédures), tags
- **CRUD complet** : création/édition d'articles avec éditeur de texte riche
- **Publication** : brouillon → publié
- **Système de vues** : compteur automatique

### D.6 — Queries

```typescript
// ============ Document Management ============
export async function uploadEmployeeDocument(employeeId, file, metadata)
export async function distributePaySlips(payRunId)
// Pour chaque pay_slip du pay_run : créer employee_document + distribution_log
export async function controlBatchBeforeDiffusion(payRunId)
// Vérification : cohérence des bulletins, nb destinataires, doublons
export async function getDistributionLogs(batchId?)
export async function sendDistributionReminders(batchId)
// Relance les employés qui n'ont pas accusé réception

// ============ e-Signature ============
export async function requestESignature(documentId, employeeId)
export async function signDocument(documentId)
// Génère un hash du document + timestamp

// ============ Document Stats ============
export async function getDocumentStats()
// nb par type, nb distribués, nb accusés, nb signés

// ============ RH Requests ============
export async function getRhRequests(status?, type?)
export async function createRhRequest(data)
export async function updateRhRequest(id, updates)
export async function assignRhRequest(id, assignedTo)
export async function resolveRhRequest(id, response)

// ============ Knowledge Base ============
export async function getRhKnowledgeBase(category?, search?)
export async function createRhKnowledgeBaseArticle(data)
export async function updateRhKnowledgeBaseArticle(id, updates)
export async function deleteRhKnowledgeBaseArticle(id)
export async function incrementArticleViews(id)
```

### D.7 — Extension des pages existantes

**`EmployeeDocumentsPage.tsx`** (modifier, créé au Sprint A) :
- Ajouter colonnes : taille fichier, type MIME, visible employé, accusé réception, e-signé
- Ajouter bouton "Envoyer pour signature"
- Ajouter bouton "Accuser réception" (côté RH)
- Ajouter section "Distribution en lot" avec contrôle de lot
- Ajouter section "Statistiques" avec indicateurs

**`PaySlipsPage.tsx`** (modifier) :
- Ajouter bouton "Distribuer les bulletins" sur chaque pay_run
- Ajouter colonne "Distribué" (✓/✗) sur chaque bulletin
- Ajouter colonne "Accusé de réception"

**`PayrollArchivePage.tsx`** (modifier) :
- Ajouter mention du double archivage (employeur + salarié)
- Ajouter conformité aux normes AFNOR Z42-013 et NF Z42-025
- Ajouter conformité RGPD
- Ajouter conformité Art. L3243-2 du Code du travail

---

## Sprint E — Extension des pages existantes

> **Prérequis** : Sprints A, B, C, D
> **Effort** : Faible
> **Fichiers modifiés** : 5

### E.1 — Extension EmployeesPage

**Fichier : `@/pages/EmployeesPage.tsx`** (modifier)
- Ajouter tous les nouveaux champs dans le formulaire :
  - État civil : prénom, nom, date/lieu de naissance, nationalité, n° sécu
  - Coordonnées : adresse, code postal, ville, pays
  - Contact d'urgence : nom, téléphone
  - Coordonnées bancaires : IBAN, BIC
  - Situation : statut marital, nb d'enfants à charge
  - Transport : mode, coût
  - Titres restaurant : nombre, valeur
  - Manager : select parmi les autres employés
  - Sortie : date de sortie, motif
- Ajouter bouton "Assistant de sortie" sur les employés actifs
- Ajouter bouton "Voir carrière" → redirige vers CareerHistoryPage filtré
- Ajouter bouton "Voir pénibilité" → redirige vers WorkHardshipPage filtré

### E.2 — Extension HRDashboardPage

**Fichier : `@/pages/HRDashboardPage.tsx`** (modifier)
- Ajouter widgets :
  - Pénibilité : nb employés exposés, niveau moyen
  - CPF : solde total, nb employés avec solde
  - Carrières : dernières promotions/transferts
  - Documents RH : nb documents, taux de distribution
  - Requêtes RH : nb en attente, temps moyen de traitement
  - Titres restaurant : total mensuel
  - Sorties : sorties prévues, soldes de tout compte en cours

### E.3 — Extension DSNPage

**Fichier : `@/pages/Phase4Pages.tsx`** (modifier, section DSNPage)
- Ajouter IntuiDSN : wizard visuel étape par étape
  - Étape 1 : Sélection de la période
  - Étape 2 : Vérification des données (anomalies, manquants)
  - Étape 3 : Génération du fichier
  - Étape 4 : Transmission
  - Étape 5 : Suivi du retour
- Ajouter contrôle des anomalies (validation des données avant transmission)
- Ajouter suivi des retours avec codes d'erreur Net-Entreprises
- Ajouter historique des transmissions

### E.4 — Extension LegalDeclarationsPage

**Fichier : `@/pages/LegalDeclarationsPage.tsx`** (modifier)
- Ajouter liens vers les nouveaux types de déclarations
- Ou rediriger vers `SocialDeclarationsPage` pour les déclarations spécifiques

### E.5 — Extension PayrollCalcPage

**Fichier : `@/pages/PayrollCalcPage.tsx`** (modifier)
- Ajouter mode "Calcul à l'envers" : input net souhaité → output brut
- Ajouter gestion détaillée des titres restaurant (basé sur le config meal_voucher_config)
- Ajouter gestion des frais de transport (forfait mobilité durable)
- Ajouter "Régularisation des données de type brut" sans impact sur les cotisations
- Ajouter "Connect Import" : intégration de données externes sans saisie manuelle (import CSV/Excel)

---

## Sprint F — i18n

> **Prérequis** : Tous les sprints précédents
> **Effort** : Faible
> **Fichiers créés** : 3 | **Fichiers modifiés** : 3

### F.1 — Extension du namespace `hr` (existant)

**Fichiers : `@/i18n/locales/{fr,en,ar}/hr.json`** (modifier)

Ajouter les clés pour :

```json
{
  "hardship": {
    "title": "Pénibilité du travail",
    "exposureType": "Type d'exposition",
    "exposureLevel": "Niveau d'exposition",
    "points": "Points C3P",
    "types": {
      "noise": "Bruit",
      "posture": "Posture",
      "chemicals": "Produits chimiques",
      "handling": "Manutention",
      "vibrations": "Vibrations",
      "temperature": "Températures extrêmes",
      "other": "Autres"
    },
    "levels": { "low": "Faible", "medium": "Moyen", "high": "Élevé" }
  },
  "career": {
    "title": "Suivi des carrières",
    "eventType": "Type d'événement",
    "events": {
      "hire": "Embauche",
      "promotion": "Promotion",
      "transfer": "Mobilité",
      "salary_change": "Changement de salaire",
      "departure": "Départ"
    },
    "timeline": "Timeline",
    "previousPosition": "Ancien poste",
    "newPosition": "Nouveau poste",
    "previousSalary": "Ancien salaire",
    "newSalary": "Nouveau salaire"
  },
  "cpf": {
    "title": "Compte Personnel de Formation",
    "balanceHours": "Solde (heures)",
    "balanceAmount": "Montant (€)",
    "history": "Historique des utilisations",
    "updateBalance": "Mettre à jour le solde",
    "alertExpiring": "CPF expirant",
    "alertUnused": "Solde important non utilisé"
  },
  "documents": {
    "title": "Documents RH",
    "deposit": "Déposer un document",
    "batchDistribution": "Distribution en lot",
    "batchControl": "Contrôle de lot",
    "distribute": "Distribuer",
    "acknowledged": "Accusé de réception",
    "eSigned": "Signé électroniquement",
    "requestSignature": "Envoyer pour signature",
    "statistics": "Statistiques",
    "totalDocuments": "Documents totaux",
    "distributedPayslips": "Bulletins distribués",
    "acknowledgmentRate": "Taux d'accusé de réception",
    "signatureRate": "Taux de signature",
    "types": {
      "payslip": "Bulletin de paie",
      "contract": "Contrat",
      "dpae": "DPAE",
      "dsn": "DSN",
      "certificate": "Certificat",
      "other": "Autre"
    }
  },
  "preparation": {
    "title": "Assistant de préparation de la paie",
    "step1": "Sélection de la période",
    "step2": "Éléments constants",
    "step3": "Éléments variables",
    "step4": "Calcul et prévisualisation",
    "step5": "Validation",
    "importTimesheets": "Importer depuis les timesheets",
    "importLeaves": "Importer depuis les congés",
    "importExpenses": "Importer depuis les notes de frais",
    "reverseCalc": "Calcul à l'envers",
    "targetNet": "Net souhaité",
    "calculatedGross": "Brut calculé",
    "anomalies": "Anomalies détectées",
    "generatePayslips": "Générer les bulletins"
  },
  "mealVouchers": {
    "title": "Titres restaurant",
    "config": "Paramétrage",
    "voucherValue": "Valeur du titre",
    "employerShare": "Part employeur (%)",
    "employeeShare": "Part salarié (%)",
    "eligibleDays": "Jours éligibles",
    "maxPerMonth": "Maximum par mois",
    "monthlyCalc": "Calcul mensuel",
    "workedDays": "Jours travaillés",
    "voucherCount": "Nombre de titres",
    "employerAmount": "Montant employeur",
    "employeeAmount": "Montant salarié",
    "exportOrder": "Export commande"
  },
  "exit": {
    "title": "Assistant de sortie du salarié",
    "exitDate": "Date de sortie",
    "exitReason": "Motif de sortie",
    "finalSettlement": "Solde de tout compte",
    "cpIndemnity": "Indemnité compensatrice de congés payés",
    "rttIndemnity": "Indemnité compensatrice de RTT",
    "bonusAmount": "Primes sur la période",
    "advanceDeduction": "Acomptes à déduire",
    "overtimeAmount": "Heures sup. non payées",
    "totalGross": "Total brut",
    "totalNet": "Total net",
    "documents": "Documents de sortie",
    "workCertificate": "Certificat de travail",
    "settlementReceipt": "Reçu pour solde de tout compte",
    "poleEmploiAttestation": "Attestation Pôle Emploi",
    "dsnExit": "DSN fin de contrat",
    "validate": "Valider la sortie"
  },
  "declarations": {
    "title": "Déclarations sociales",
    "dsn": "DSN",
    "dadsU": "DADS-U",
    "ducs": "DUCS URSSAF",
    "aed": "Attestation employeur",
    "dtsMsa": "DTS-MSA (agricole)",
    "cibtp": "CIBTP (BTP)",
    "congesPayesBtp": "Congés Payés BTP",
    "cice": "CICE",
    "refusCdi": "Refus CDI",
    "ct2025": "CT2025",
    "intuiDsn": "IntuiDSN",
    "generate": "Générer",
    "transmit": "Transmettre",
    "anomalyCheck": "Vérification des anomalies",
    "responseCode": "Code de retour",
    "responseMessage": "Message de retour",
    "ciceConfig": "Paramétrage CICE",
    "smicThreshold": "Seuil SMIC",
    "rate": "Taux",
    "eligibleSalaryCap": "Plafond d'éligibilité"
  },
  "demat": {
    "title": "Dématérialisation RH",
    "vault": "Coffre-fort électronique",
    "doubleArchiving": "Double archivage légal",
    "afnorCompliance": "Conformité AFNOR Z42-013 / NF Z42-025",
    "rgpdCompliance": "Conformité RGPD",
    "laborCodeCompliance": "Conformité Art. L3243-2 Code du travail",
    "pilotage": "Pilotage de l'activité documentaire",
    "distributionLogs": "Logs de distribution",
    "sendReminders": "Envoyer des relances"
  },
  "requests": {
    "title": "Requêtes RH",
    "newRequest": "Nouvelle demande",
    "requestType": "Type de demande",
    "types": {
      "documentCopy": "Copie de document",
      "certificate": "Certificat",
      "leaveInfo": "Information congés",
      "salaryChange": "Changement de salaire",
      "addressChange": "Changement d'adresse",
      "other": "Autre"
    },
    "assignTo": "Assigner à",
    "resolve": "Traiter",
    "response": "Réponse",
    "avgProcessingTime": "Temps moyen de traitement",
    "resolutionRate": "Taux de résolution"
  },
  "knowledgeBase": {
    "title": "Base de connaissances RH",
    "newArticle": "Nouvel article",
    "categories": {
      "payroll": "Paie",
      "leaves": "Congés",
      "contracts": "Contrats",
      "law": "Droit",
      "procedures": "Procédures",
      "other": "Autre"
    },
    "search": "Rechercher...",
    "published": "Publié",
    "draft": "Brouillon"
  }
}
```

### F.2 — Extension du namespace `payroll` (existant)

**Fichiers : `@/i18n/locales/{fr,en,ar}/payroll.json`** (modifier)

Ajouter les clés pour :
- `preparation` : assistant de préparation, étapes, import éléments
- `reverseCalc` : calcul à l'envers, net souhaité, brut calculé
- `mealVouchers` : titres restaurant, paramétrage, calcul mensuel
- `exit` : assistant de sortie, solde de tout compte, documents de sortie
- `slipTypes` : normal, acompte, rappel, sortie
- `regularization` : régularisation brut sans impact cotisations
- `connectImport` : import de données externes
- `csvExport` : passation comptable CSV, ordonnancement

---

## Ordre de mise en œuvre

| Sprint | Durée | Dépendances | Priorité |
|---|---|---|---|
| **A** — Pages manquantes (queries existantes) | 2-3j | Aucune | 🔴 Haute (rapide) |
| **B** — Paie avancée | 4-5j | A | 🔴 Haute |
| **C** — Déclarations spécifiques | 2-3j | B | 🟡 Moyenne |
| **D** — Dématérialisation RH | 3-4j | A | 🔴 Haute |
| **E** — Extensions pages existantes | 1-2j | A, B, C, D | 🟡 Moyenne |
| **F** — i18n | 1-2j | Tous | 🔴 Obligatoire |

**Total : 13-19 jours de développement**

---

## Liste complète des fichiers

### Nouvelles pages (8)
1. `@/pages/hr/WorkHardshipPage.tsx` — Pénibilité
2. `@/pages/hr/CareerHistoryPage.tsx` — Suivi des carrières
3. `@/pages/hr/CPFPage.tsx` — Compte Personnel de Formation
4. `@/pages/hr/EmployeeDocumentsPage.tsx` — Documents employés (coffre-fort)
5. `@/pages/hr/PayrollPreparationPage.tsx` — Assistant de préparation de la paie
6. `@/pages/hr/MealVouchersPage.tsx` — Titres restaurant
7. `@/pages/hr/EmployeeExitPage.tsx` — Assistant de sortie du salarié
8. `@/pages/hr/SocialDeclarationsPage.tsx` — Déclarations sociales (DADS-U, DUCS, AED, BTP, MSA, CICE)
9. `@/pages/hr/DocumentManagementPage.tsx` — Gestion documentaire RH (distribution, e-signature, pilotage)
10. `@/pages/hr/RhRequestsPage.tsx` — Requêtes RH (relation RH-salariés)
11. `@/pages/hr/RhKnowledgeBasePage.tsx` — Base de connaissances RH

### SQL (1)
12. `@/sql/23_rh_paie_avancee.sql`

### Fichiers modifiés (10+)
- `@/types/index.ts` — nouveaux types + extensions
- `@/lib/queries.ts` — nouvelles queries + CRUD manquants
- `@/App.tsx` — nouvelles routes
- `@/pages/EmployeesPage.tsx` — champs étendus + bouton sortie
- `@/pages/PayRunsPage.tsx` — lien assistant préparation
- `@/pages/PaySlipsPage.tsx` — type bulletin + distribution
- `@/pages/PayrollCalcPage.tsx` — calcul à l'envers + titres restaurant + régularisation
- `@/pages/HRDashboardPage.tsx` — nouveaux widgets
- `@/pages/LegalDeclarationsPage.tsx` — liens déclarations spécifiques
- `@/pages/Phase4Pages.tsx` — IntuiDSN (section DSNPage)
- `@/pages/PayrollArchivePage.tsx` — passation CSV + conformité archivage
- `@/i18n/locales/{fr,en,ar}/hr.json` — clés RH étendues
- `@/i18n/locales/{fr,en,ar}/payroll.json` — clés paie étendues

**Total : 11 nouvelles pages + 1 SQL + ~13 fichiers modifiés**
