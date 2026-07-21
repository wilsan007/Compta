# Plan d'Implémentation — Espace Employés & RH Complet

> **Source** : SAGE-100-REFERENCE-COMPLETE.md (Sections 12, 13, 14)
> **Objectif** : Implémenter toutes les fonctionnalités RH manquantes de Sage 100
> **Conventions** : Voir PLAN-IMPLEMENTATION-PRODUCTION.md (section Conventions)

---

## Sommaire

1. [Sprint A — Rôle Employee & Authentification](#sprint-a--rôle-employee--authentification)
2. [Sprint B — Espace Employés : Congés & Absences (self-service)](#sprint-b--espace-employés-congés--absences)
3. [Sprint C — Espace Employés : Dossier Salarié](#sprint-c--espace-employés-dossier-salarié)
4. [Sprint D — Espace Employés : Notes de Frais (self-service)](#sprint-d--espace-employés-notes-de-frais)
5. [Sprint E — Espace Employés : Entretiens & Objectifs](#sprint-e--espace-employés-entretiens--objectifs)
6. [Sprint F — Dématérialisation RH](#sprint-f--dématérialisation-rh)
7. [Sprint G — Fonctionnalités Paie avancées](#sprint-g--fonctionnalités-paie-avancées)
8. [Sprint H — Déclarations sociales spécifiques](#sprint-h--déclarations-sociales-spécifiques)
9. [Sprint I — Application Mobile (PWA)](#sprint-i--application-mobile-pwa)
10. [Sprint J — i18n (fr, en, ar)](#sprint-j--i18n)

---

## Sprint A — Rôle Employee & Authentification

> **Prérequis** : Aucun
> **Effort** : Moyen
> **Fichiers modifiés** : 8

### A.1 — SQL : Extension du schéma

```sql
-- 1. Ajouter le rôle 'employee' dans tenant_users
-- (Pas de migration nécessaire, le type text accepte déjà toutes les valeurs)

-- 2. Lier un employé à un compte utilisateur
alter table employees add column if not exists auth_id uuid;
alter table employees add column if not exists tenant_user_id uuid references tenant_users(id) on delete set null;

-- 3. Table des soldes de congés (compteurs par employé et par type)
create table if not exists leave_balances (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  employee_id uuid not null references employees(id) on delete cascade,
  leave_type text not null, -- 'annual', 'rtt', 'recovery', 'sick', 'unpaid'
  year int not null default extract(year from current_date)::int,
  acquired decimal(5,2) default 0,   -- jours acquis
  taken decimal(5,2) default 0,      -- jours pris
  pending decimal(5,2) default 0,    -- jours en attente de validation
  remaining decimal(5,2) default 0,  -- jours restants (acquired - taken - pending)
  carry_over decimal(5,2) default 0, -- report de l'année précédente
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique(employee_id, leave_type, year)
);
create index if not exists idx_leave_balances_employee on leave_balances(employee_id);
create index if not exists idx_leave_balances_year on leave_balances(year);
alter table leave_balances enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_leave_balances') THEN
    CREATE POLICY "allow_all_leave_balances" ON leave_balances FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 4. Table des jours fériés (régionalisable)
create table if not exists public_holidays (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  name text not null,
  holiday_date date not null,
  region text default 'national', -- 'national', 'alsace-moselle', 'guadeloupe', etc.
  country text default 'FR',
  created_at timestamptz default now()
);
create index if not exists idx_public_holidays_date on public_holidays(holiday_date);
alter table public_holidays enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_public_holidays') THEN
    CREATE POLICY "allow_all_public_holidays" ON public_holidays FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 5. Table de paramétrage des règles de congés
create table if not exists leave_rules (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  leave_type text not null,
  label text not null,
  accrual_rate decimal(5,2) default 2.08,  -- taux d'acquisition mensuel (2.08 = 25 jours/an)
  max_carry_over decimal(5,2) default 0,    -- report maximum
  requires_justification boolean default false,
  requires_manager_approval boolean default true,
  min_notice_days int default 7,            -- délai minimum de prévenance
  max_consecutive_days int default 30,      -- durée max d'un congé
  color text default '#3b82f6',             -- couleur pour le planning
  active boolean default true,
  created_at timestamptz default now()
);
alter table leave_rules enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_leave_rules') THEN
    CREATE POLICY "allow_all_leave_rules" ON leave_rules FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 6. Table de paramétrage des workflows de validation
create table if not exists approval_workflows (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  name text not null,                 -- ex: "Validation congés standard"
  entity_type text not null,          -- 'leave_request', 'expense_report', 'timesheet'
  steps jsonb default '[]',           -- [{role: 'manager', order: 1}, {role: 'hr', order: 2}]
  active boolean default true,
  created_at timestamptz default now()
);
alter table approval_workflows enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_approval_workflows') THEN
    CREATE POLICY "allow_all_approval_workflows" ON approval_workflows FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 7. Étendre leave_requests
alter table leave_requests add column if not exists tenant_id uuid;
alter table leave_requests add column if not exists justification_url text;
alter table leave_requests add column if not exists manager_id uuid references employees(id) on delete set null;
alter table leave_requests add column if not exists manager_comment text;
alter table leave_requests add column if not exists half_day boolean default false;
alter table leave_requests add column if not exists requested_at timestamptz default now();

-- 8. Étendre expense_reports
alter table expense_reports add column if not exists manager_id uuid;
alter table expense_reports add column if not exists manager_comment text;
alter table expense_reports add column if not exists reimbursement_date date;

-- 9. Table des objectifs (entretiens)
create table if not exists employee_objectives (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  employee_id uuid not null references employees(id) on delete cascade,
  interview_id uuid references interviews(id) on delete set null,
  title text not null,
  description text,
  target_value decimal(15,2),
  current_value decimal(15,2) default 0,
  unit text,                     -- '%', '€', 'unités', etc.
  period_start date not null,
  period_end date not null,
  frequency text default 'annual', -- 'annual', 'semiannual', 'quarterly', 'monthly'
  status text default 'active' check (status in ('active', 'achieved', 'missed', 'cancelled')),
  progress_percentage decimal(5,2) default 0,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists idx_objectives_employee on employee_objectives(employee_id);
alter table employee_objectives enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_employee_objectives') THEN
    CREATE POLICY "allow_all_employee_objectives" ON employee_objectives FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 10. Étendre interviews
alter table interviews add column if not exists tenant_id uuid;
alter table interviews add column if not exists manager_id uuid;
alter table interviews add column if not exists employee_feedback text;
alter table interviews add column if not exists employee_rating int;
alter table interviews add column if not exists form_data jsonb;  -- réponses structurées
alter table interviews add column if not exists campaign_id uuid;

-- 11. Table des campagnes d'entretiens
create table if not exists interview_campaigns (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  name text not null,
  type text not null,               -- 'annual', 'professional', 'exit', 'mid_year'
  start_date date not null,
  end_date date not null,
  status text default 'draft' check (status in ('draft', 'active', 'closed')),
  reminder_days int default 7,      -- relance X jours avant la fin
  created_at timestamptz default now()
);
alter table interview_campaigns enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_interview_campaigns') THEN
    CREATE POLICY "allow_all_interview_campaigns" ON interview_campaigns FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 12. Table des documents RH (coffre-fort)
create table if not exists employee_documents (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  employee_id uuid not null references employees(id) on delete cascade,
  document_type text not null,       -- 'payslip', 'contract', 'certificate', 'other'
  title text not null,
  file_url text not null,            -- URL Supabase Storage
  file_size bigint,
  mime_type text,
  period text,                       -- ex: "2024-01" pour un bulletin de paie
  uploaded_by uuid,                  -- user id
  visible_to_employee boolean default true,
  requires_acknowledgment boolean default false,
  acknowledged_at timestamptz,
  e_signed boolean default false,
  created_at timestamptz default now()
);
create index if not exists idx_employee_documents_employee on employee_documents(employee_id);
create index if not exists idx_employee_documents_type on employee_documents(document_type);
alter table employee_documents enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_employee_documents') THEN
    CREATE POLICY "allow_all_employee_documents" ON employee_documents FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 13. Étendre employees avec données RH complètes
alter table employees add column if not exists tenant_id uuid;
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
alter table employees add column if not exists manager_id uuid references employees(id) on delete set null;
alter table employees add column if not exists photo_url text;
alter table employees add column if not exists exit_date date;
alter table employees add column if not exists exit_reason text;
```

### A.2 — Types TypeScript (`@/types/index.ts`)

```typescript
// ============ Espace Employés ============

export interface LeaveBalance {
  id: string
  tenant_id: string | null
  employee_id: string
  leave_type: string
  year: number
  acquired: number
  taken: number
  pending: number
  remaining: number
  carry_over: number
  created_at: string
  updated_at: string
}

export interface PublicHoliday {
  id: string
  tenant_id: string | null
  name: string
  holiday_date: string
  region: string
  country: string
  created_at: string
}

export interface LeaveRule {
  id: string
  tenant_id: string | null
  leave_type: string
  label: string
  accrual_rate: number
  max_carry_over: number
  requires_justification: boolean
  requires_manager_approval: boolean
  min_notice_days: number
  max_consecutive_days: number
  color: string
  active: boolean
  created_at: string
}

export interface ApprovalWorkflow {
  id: string
  tenant_id: string | null
  name: string
  entity_type: 'leave_request' | 'expense_report' | 'timesheet'
  steps: { role: string; order: number }[]
  active: boolean
  created_at: string
}

export interface EmployeeObjective {
  id: string
  tenant_id: string | null
  employee_id: string
  interview_id: string | null
  title: string
  description: string | null
  target_value: number | null
  current_value: number
  unit: string | null
  period_start: string
  period_end: string
  frequency: 'annual' | 'semiannual' | 'quarterly' | 'monthly'
  status: 'active' | 'achieved' | 'missed' | 'cancelled'
  progress_percentage: number
  created_at: string
  updated_at: string
}

export interface InterviewCampaign {
  id: string
  tenant_id: string | null
  name: string
  type: 'annual' | 'professional' | 'exit' | 'mid_year'
  start_date: string
  end_date: string
  status: 'draft' | 'active' | 'closed'
  reminder_days: number
  created_at: string
}

export interface EmployeeDocument {
  id: string
  tenant_id: string | null
  employee_id: string
  document_type: 'payslip' | 'contract' | 'certificate' | 'other'
  title: string
  file_url: string
  file_size: number | null
  mime_type: string | null
  period: string | null
  uploaded_by: string | null
  visible_to_employee: boolean
  requires_acknowledgment: boolean
  acknowledged_at: string | null
  e_signed: boolean
  created_at: string
}
```

Étendre les interfaces existantes :

```typescript
// Étendre Employee
export interface Employee {
  // ... champs existants ...
  tenant_id: string | null
  first_name: string | null
  last_name: string | null
  birth_date: string | null
  birth_place: string | null
  nationality: string | null
  social_security_number: string | null
  address: string | null
  postal_code: string | null
  city: string | null
  country: string
  emergency_contact_name: string | null
  emergency_contact_phone: string | null
  bank_iban: string | null
  bank_bic: string | null
  marital_status: string | null
  dependents_count: number
  transport_mode: string | null
  transport_cost: number
  meal_voucher_count: number
  meal_voucher_value: number
  manager_id: string | null
  photo_url: string | null
  exit_date: string | null
  exit_reason: string | null
  auth_id: string | null
  tenant_user_id: string | null
}

// Étendre LeaveRequest
export interface LeaveRequest {
  // ... champs existants ...
  tenant_id: string | null
  justification_url: string | null
  manager_id: string | null
  manager_comment: string | null
  half_day: boolean
  requested_at: string
}

// Étendre ExpenseReport
export interface ExpenseReport {
  // ... champs existants ...
  manager_id: string | null
  manager_comment: string | null
  reimbursement_date: string | null
}

// Étendre Interview
export interface Interview {
  // ... champs existants ...
  tenant_id: string | null
  manager_id: string | null
  employee_feedback: string | null
  employee_rating: number | null
  form_data: any
  campaign_id: string | null
}
```

### A.3 — Rôle `employee` dans l'auth

**Fichier : `@/lib/queries.ts`**
- Modifier le type `TenantUser['role']` : ajouter `'employee'`
- Modifier `ROLE_LABELS` : ajouter `employee: 'Employé'`
- Modifier `ROLE_DESCRIPTIONS` : ajouter `employee: 'Accès à son espace employé (congés, notes de frais, documents)'`

**Fichier : `@/lib/auth.tsx`**
- Ajouter le cas `employee` dans `canPerform` :
  ```typescript
  if (user.role === 'employee') {
    // L'employé ne peut accéder qu'à ses propres données
    const employeeTables = ['leave_requests', 'expense_reports', 'expense_report_lines',
      'employee_documents', 'employee_objectives', 'interviews', 'timesheets',
      'leave_balances', 'employees']
    if (action === 'select' && employeeTables.includes(table)) return true
    if (action === 'insert' && ['leave_requests', 'expense_reports', 'expense_report_lines'].includes(table)) return true
    if (action === 'update' && ['leave_requests', 'expense_reports', 'expense_report_lines', 'employees'].includes(table)) return true
    return false
  }
  ```

**Fichier : `@/lib/supabase.ts`**
- Ajouter dans `TENANT_TABLES` :
  ```
  'leave_balances', 'public_holidays', 'leave_rules', 'approval_workflows',
  'employee_objectives', 'interview_campaigns', 'employee_documents'
  ```

### A.4 — Liaison Employé ↔ Compte utilisateur

**Fichier : `@/lib/queries.ts`**
- Créer `linkEmployeeToUser(employeeId, authId, tenantUserId)` : met à jour `employees.auth_id` et `employees.tenant_user_id`
- Créer `getEmployeeByUserId(userId)` : récupère l'employé lié à l'utilisateur connecté
- Créer `getMyEmployeeProfile()` : récupère le profil de l'employé connecté

### A.5 — Route protégée Employee

**Fichier : `@/components/ProtectedRoute.tsx`**
- Ajouter un `EmployeeRoute` qui vérifie `user.role === 'employee'`
- Si l'utilisateur n'est pas employé, rediriger vers le dashboard principal

### A.6 — Layout Espace Employé

**Fichier : `@/components/EmployeeLayout.tsx`** (nouveau)
- Layout simplifié (pas de sidebar complète, juste une nav horizontale)
- Items : Tableau de bord, Mes congés, Mon dossier, Mes notes de frais, Mes entretiens, Mes documents
- Language switcher
- Avatar + nom de l'employé

### A.7 — Routes App.tsx

```tsx
{/* Espace Employés — portail self-service */}
<Route path="/employee" element={<EmployeeLayout />}>
  <Route index element={<EmployeeDashboardPage />} />
  <Route path="leaves" element={<EmployeeLeavesPage />} />
  <Route path="profile" element={<EmployeeProfilePage />} />
  <Route path="expenses" element={<EmployeeExpensesPage />} />
  <Route path="interviews" element={<EmployeeInterviewsPage />} />
  <Route path="documents" element={<EmployeeDocumentsPage />} />
</Route>
```

---

## Sprint B — Espace Employés : Congés & Absences

> **Prérequis** : Sprint A
> **Effort** : Important
> **Fichiers créés** : 4 | **Fichiers modifiés** : 3

### B.1 — Queries (`@/lib/queries.ts`)

```typescript
// ============ Leave Balances ============
export async function getLeaveBalances(employeeId: string, year?: number)
export async function getMyLeaveBalances()  // pour l'employé connecté
export async function updateLeaveBalance(id, updates)
export async function recalculateLeaveBalance(employeeId, leaveType, year)
// Logique : remaining = acquired + carry_over - taken - pending

// ============ Leave Requests (extension) ============
export async function getMyLeaveRequests()  // pour l'employé connecté
export async function createMyLeaveRequest(data)  // crée + met à jour pending
export async function cancelMyLeaveRequest(id)  // annule + décrémente pending
export async function getPendingLeaveRequests(managerId?)  // pour le manager
export async function approveLeaveRequest(id, managerId, comment)
// Logique : approuve → décrémente pending, incrémente taken, recalcule remaining
export async function rejectLeaveRequest(id, managerId, comment)
// Logique : rejette → décrémente pending, recalcule remaining

// ============ Public Holidays ============
export async function getPublicHolidays(year?, region?)
export async function createPublicHoliday(data)
export async function deletePublicHoliday(id)

// ============ Leave Rules ============
export async function getLeaveRules()
export async function createLeaveRule(data)
export async function updateLeaveRule(id, updates)
export async function deleteLeaveRule(id)

// ============ Approval Workflows ============
export async function getApprovalWorkflows(entityType?)
export async function createApprovalWorkflow(data)
export async function updateApprovalWorkflow(id, updates)

// ============ Helpers ============
export async function calculateWorkingDays(startDate, endDate, holidays[])
// Calcule le nombre de jours ouvrés/ouvrables entre 2 dates
export async function checkLeaveConflict(employeeId, startDate, endDate)
// Vérifie si l'employé a déjà un congé approuvé sur cette période
export async function checkMinStaffRequired(department, startDate, endDate)
// Vérifie les astreintes (effectif minimum)
```

### B.2 — Page : EmployeeDashboardPage

**Fichier : `@/pages/employee/EmployeeDashboardPage.tsx`** (nouveau)

**Structure :**
- **Carte "Mes congés"** : solde CP, RTT, récupération avec barres de progression
- **Carte "Demandes en attente"** : nombre de demandes en cours
- **Carte "Notes de frais"** : montant en attente de remboursement
- **Carte "Prochains entretiens"** : date du prochain entretien
- **Section "Activité récente"** : timeline des dernières actions (congé approuvé, document reçu, etc.)
- **Section "Planning congés"** : mini-calendrier du mois avec congés visualisés

### B.3 — Page : EmployeeLeavesPage

**Fichier : `@/pages/employee/EmployeeLeavesPage.tsx`** (nouveau)

**Structure :**
- **Onglet 1 : "Mes demandes"**
  - Table : Type, Date début, Date fin, Jours, Statut, Actions
  - Bouton "Nouvelle demande"
  - Modal de création :
    - Type de congé (select, depuis leave_rules actifs)
    - Date début (date picker)
    - Date fin (date picker)
    - Demi-journée (checkbox)
    - Justification (textarea)
    - Pièce jointe (upload, si `requires_justification`)
    - Affichage automatique du solde disponible
    - Alerte si délai de prévenance non respecté (`min_notice_days`)
    - Alerte si conflit avec congé existant
    - Alerte si effectif minimum non respecté (astreinte)
  - Bouton "Annuler" sur demande en attente
  - Filtres : statut, type, période

- **Onglet 2 : "Mon solde"**
  - Cartes par type de congé : acquis, pris, en attente, restant, report
  - Historique des mouvements (acquisition, prise, régularisation)
  - Export Excel

- **Onglet 3 : "Planning"**
  - Vue calendrier (mois/semaine) avec tous les congés de l'équipe
  - Code couleur par type de congé
  - Jours fériés affichés
  - Légende

### B.4 — Page : ManagerLeaveApprovalsPage

**Fichier : `@/pages/employee/ManagerLeaveApprovalsPage.tsx`** (nouveau)

**Structure :**
- Liste des demandes en attente pour les employés sous la responsabilité du manager
- Pour chaque demande : nom employé, type, dates, jours, solde restant, justification
- Boutons "Approuver" / "Rejeter" avec commentaire
- Vue calendrier pour visualiser les chevauchements
- Filtres : employé, type, période

### B.5 — Page : LeaveRulesPage (admin)

**Fichier : `@/pages/settings/LeaveRulesPage.tsx`** (nouveau)

**Structure :**
- Table des règles de congés : type, libellé, taux acquisition, report max, prévenance min, durée max, couleur, actif
- CRUD complet
- Section "Jours fériés" : table + CRUD + import automatique par région/pays
- Section "Workflows de validation" : configuration des étapes

### B.6 — Extension LeaveRequestsPage existante

**Fichier : `@/pages/LeaveRequestsPage.tsx`** (modifier)
- Ajouter colonnes : justificatif, demi-journée, commentaire manager
- Ajouter filtre par employé
- Ajouter action "Approuver/Rejeter" pour les managers
- Ajouter calcul automatique des jours ouvrés

---

## Sprint C — Espace Employés : Dossier Salarié

> **Prérequis** : Sprint A
> **Effort** : Moyen
> **Fichiers créés** : 1 | **Fichiers modifiés** : 2

### C.1 — Queries

```typescript
// ============ Employee Profile (self-service) ============
export async function getMyProfile()  // profil complet de l'employé connecté
export async function updateMyProfile(updates)  // champs modifiables selon droits
// Logique : seuls les champs autorisés par la config sont modifiables
// (address, phone, emergency_contact, photo — PAS salary, position, etc.)

export async function getEmployeeFieldsConfig()
// Récupère la config des champs visibles/modifiables par l'employé
// (table de paramétrage ou JSON statique)

// ============ Career History ============
export async function getCareerHistory(employeeId)
// Historique des changements de poste, promotion, augmentation

// ============ Alerts ============
export async function getEmployeeAlerts(employeeId)
// Alertes : fin de période d'essai, visite médicale, formation obligatoire, etc.
```

### C.2 — Page : EmployeeProfilePage

**Fichier : `@/pages/employee/EmployeeProfilePage.tsx`** (nouveau)

**Structure :**
- **Section "Informations personnelles"** (modifiable selon droits) :
  - Photo (upload)
  - Nom, prénom, date de naissance, lieu de naissance, nationalité
  - Numéro de sécurité sociale
  - Adresse, code postal, ville, pays
  - Téléphone, email
  - Contact d'urgence
  - Situation familiale, nombre d'enfants à charge
- **Section "Informations professionnelles"** (lecture seule) :
  - Poste, département, manager
  - Date d'embauche, type de contrat
  - Salaire (si visible)
  - Titres restaurant (nombre, valeur)
  - Frais de transport (mode, montant)
  - Coordonnées bancaires (modifiable selon droits)
- **Section "Carrière"** :
  - Historique des postes
  - Promotions
  - Changements de département
- **Section "Alertes"** :
  - Fin de période d'essai dans X jours
  - Visite médicale à planifier
  - Formation CPF disponible
- **Bouton "Demander une modification"** : si un champ n'est pas modifiable directement, l'employé peut soumettre une demande de modification qui sera validée par les RH

### C.3 — Extension EmployeesPage (admin)

**Fichier : `@/pages/EmployeesPage.tsx`** (modifier)
- Ajouter tous les nouveaux champs dans le formulaire de création/édition
- Ajouter section "Lier à un compte utilisateur" (select des tenant_users sans employé lié)
- Ajouter section "Manager" (select parmi les autres employés)
- Ajouter bouton "Assistant de sortie" (voir Sprint G)

---

## Sprint D — Espace Employés : Notes de Frais

> **Prérequis** : Sprint A
> **Effort** : Important
> **Fichiers créés** : 2 | **Fichiers modifiés** : 2

### D.1 — Queries

```typescript
// ============ Expense Reports (self-service) ============
export async function getMyExpenseReports()
export async function createMyExpenseReport(data)
export async function updateMyExpenseReport(id, updates)
export async function submitMyExpenseReport(id)  // statut: draft → submitted
export async function deleteMyExpenseReport(id)  // seulement si draft

export async function getPendingExpenseReports(managerId?)
export async function approveExpenseReport(id, managerId, comment)
export async function rejectExpenseReport(id, managerId, comment)
export async function markExpenseReimbursed(id, reimbursementDate)

// ============ Expense Report Lines ============
export async function getExpenseReportLines(reportId)
export async function addExpenseReportLine(reportId, line)
export async function updateExpenseReportLine(id, updates)
export async function deleteExpenseReportLine(id)

// ============ OCR (reconnaissance factures) ============
export async function uploadReceipt(file, lineId)
// Upload vers Supabase Storage + extraction OCR
// Utiliser Tesseract.js (client-side) ou API externe
export async function extractReceiptData(file)
// Retourne : { date, amount, vatRate, vendor, category? }

// ============ Expense Categories ============
export async function getExpenseCategories()
export async function createExpenseCategory(data)
// Catégories : transport, repas, hébergement, fournitures, télécom, divers...

// ============ Plafonds ============
export async function getExpenseLimits(categoryId)
// Plafonds de remboursement par catégorie

// ============ Comptabilisation ============
export async function generateExpenseAccountingEntries(reportId)
// Génère les écritures comptables vers Sage 100 Comptabilité
// (compte de charge, compte de TVA, compte de tiers)
```

### D.2 — Page : EmployeeExpensesPage

**Fichier : `@/pages/employee/EmployeeExpensesPage.tsx`** (nouveau)

**Structure :**
- **Table "Mes notes de frais"** : Numéro, Période, Montant total, TVA, Statut, Actions
- **Bouton "Nouvelle note de frais"**
- **Modal de création** :
  - Période (mois/année)
  - Notes
- **Détail de la note de frais** (page ou modal large) :
  - Table des lignes : Date, Description, Catégorie, Montant HT, TVA, TTC, Justificatif, Actions
  - Bouton "Ajouter une ligne"
  - **Upload justificatif** : drag & drop ou photo (sur mobile)
  - **OCR automatique** : extraction date, montant, TVA depuis le justificatif
  - **Alerte plafond** : si montant > plafond catégorie, afficher warning
  - Bouton "Soumettre" (draft → submitted)
  - Bouton "Supprimer" (si draft)
- **Filtres** : statut, période, catégorie

### D.3 — Page : ManagerExpenseApprovalsPage

**Fichier : `@/pages/employee/ManagerExpenseApprovalsPage.tsx`** (nouveau)

**Structure :**
- Liste des notes de frais en attente de validation
- Pour chaque note : employé, période, montant total, nombre de justificatifs
- Bouton "Voir détail" → affiche toutes les lignes + justificatifs
- Boutons "Approuver" / "Rejeter" avec commentaire
- Filtres : employé, période

### D.4 — Extension ExpenseReportsPage existante

**Fichier : `@/pages/Phase4Pages.tsx`** (modifier, section ExpenseReportsPage)
- Ajouter colonnes : manager, commentaire manager, date remboursement
- Ajouter action "Marquer remboursé"
- Ajouter action "Générer écritures comptables"
- Ajouter filtre par employé
- Ajouter vue détaillée avec lignes

### D.5 — Table des catégories de dépenses

```sql
create table if not exists expense_categories (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  code text not null,
  label text not null,
  account_code text,              -- compte de charge comptable
  vat_rate decimal(5,2) default 20,
  max_amount decimal(15,2),       -- plafond par ligne
  max_monthly decimal(15,2),      -- plafond mensuel
  active boolean default true,
  created_at timestamptz default now()
);
alter table expense_categories enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_expense_categories') THEN
    CREATE POLICY "allow_all_expense_categories" ON expense_categories FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
```

---

## Sprint E — Espace Employés : Entretiens & Objectifs

> **Prérequis** : Sprint A
> **Effort** : Moyen
> **Fichiers créés** : 2 | **Fichiers modifiés** : 1

### E.1 — Queries

```typescript
// ============ Interviews (self-service) ============
export async function getMyInterviews()
export async function getMyUpcomingInterview()
export async function submitInterviewFeedback(id, feedback, rating)
// L'employé soumet son feedback après l'entretien

// ============ Objectives ============
export async function getMyObjectives()
export async function createMyObjective(data)  // le manager crée, l'employé consulte
export async function updateObjectiveProgress(id, currentValue)
// L'employé met à jour sa progression
export async function getObjectivesByEmployee(employeeId)
export async function getObjectivesByCampaign(campaignId)

// ============ Campaigns ============
export async function getInterviewCampaigns()
export async function createInterviewCampaign(data)
export async function launchCampaign(id)  // draft → active, crée les entretiens pour chaque employé
export async function closeCampaign(id)   // active → closed
export async function sendCampaignReminders(campaignId)
// Relance les employés/managers qui n'ont pas complété leur entretien

// ============ Forms ============
export async function getInterviewFormTemplate(type)
// Retourne la structure du formulaire selon le type d'entretien
export async function saveInterviewFormData(interviewId, formData)
```

### E.2 — Page : EmployeeInterviewsPage

**Fichier : `@/pages/employee/EmployeeInterviewsPage.tsx`** (nouveau)

**Structure :**
- **Onglet 1 : "Mes entretiens"**
  - Table : Type, Date prévue, Date réalisée, Statut, Évaluation, Actions
  - Bouton "Voir détail" → affiche le formulaire d'entretien
  - Section "Mon feedback" : l'employé peut saisir son feedback et son rating
  - Section "Feedback manager" : visible après réalisation
- **Onglet 2 : "Mes objectifs"**
  - Table : Titre, Description, Cible, Progression, Période, Fréquence, Statut
  - Barre de progression visuelle pour chaque objectif
  - Bouton "Mettre à jour la progression" (modal avec slider ou input)
  - Filtres : statut, période

### E.3 — Page : InterviewCampaignsPage (admin/manager)

**Fichier : `@/pages/hr/InterviewCampaignsPage.tsx`** (nouveau)

**Structure :**
- Table des campagnes : Nom, Type, Période, Statut, Avancement (% complétés)
- Bouton "Nouvelle campagne"
- Modal de création : nom, type, dates, relance
- Bouton "Lancer" (crée les entretiens pour tous les employés actifs)
- Bouton "Relancer" (envoie notifications)
- Bouton "Clôturer"
- Vue détaillée : liste des entretiens de la campagne avec statut

### E.4 — Extension InterviewsPage existante

**Fichier : `@/pages/Phase4Pages.tsx`** (modifier, section InterviewsPage)
- Ajouter colonnes : manager, feedback employé, rating employé, campagne
- Ajouter vue détaillée avec form_data (réponses structurées)
- Ajouter action "Planifier" pour les managers

---

## Sprint F — Dématérialisation RH

> **Prérequis** : Sprint A
> **Effort** : Moyen
> **Fichiers créés** : 3 | **Fichiers modifiés** : 2

### F.1 — Queries

```typescript
// ============ Employee Documents ============
export async function getMyDocuments()  // documents visibles pour l'employé connecté
export async function getEmployeeDocuments(employeeId)  // pour RH/admin
export async function uploadEmployeeDocument(employeeId, file, metadata)
// Upload vers Supabase Storage + création enregistrement
export async function deleteEmployeeDocument(id)
export async function acknowledgeDocument(id)  // l'employé accuse réception
export async function distributePaySlips(payRunId)
// Distribue automatiquement les bulletins de paie dans les coffres-forts salariés
// Logique : pour chaque pay_slip du pay_run, créer un employee_document
// de type 'payslip', visible_to_employee=true

// ============ e-Signature ============
export async function requestESignature(documentId, employeeId)
// Envoie une demande de signature électronique
export async function signDocument(documentId)
// L'employé signe électroniquement (hash + timestamp)

// ============ Document Statistics ============
export async function getDocumentStats()
// Indicateurs : nb documents par type, nb distribués, nb accusés de réception, etc.
export async function getDistributionReport(payRunId)
// Rapport de distribution des bulletins : qui a reçu, qui a accusé réception

// ============ Bulk Operations ============
export async function bulkUploadDocuments(files, documentType, employeeIds?)
export async function controlBatchBeforeDiffusion(payRunId)
// Vérification avant envoi : cohérence des bulletins, nb destinataires, etc.
```

### F.2 — Page : EmployeeDocumentsPage

**Fichier : `@/pages/employee/EmployeeDocumentsPage.tsx`** (nouveau)

**Structure :**
- **Table "Mes documents"** : Type, Titre, Période, Date, Accusé réception, Actions
- **Filtres** : type (bulletin de paie, contrat, certificat, autre), période
- **Bouton "Télécharger"** : télécharge le document
- **Bouton "Accuser réception"** : si `requires_acknowledgment`
- **Bouton "Signer"** : si `e_signed` requis
- **Section "Coffre-fort"** : présentation visuelle, nombre de documents, dernière connexion

### F.3 — Page : DocumentManagementPage (admin/RH)

**Fichier : `@/pages/hr/DocumentManagementPage.tsx`** (nouveau)

**Structure :**
- **Onglet 1 : "Documents"**
  - Table : Employé, Type, Titre, Période, Visible employé, Accusé réception, Date, Actions
  - Bouton "Déposer un document" (upload + sélection employé)
  - Bouton "Distribution en lot" (sélection multiple de fichiers + type)
- **Onglet 2 : "Distribution bulletins"**
  - Sélection d'un pay_run
  - Bouton "Distribuer" → distribue tous les bulletins dans les coffres-forts
  - Table de suivi : Employé, Bulletin distribué, Accusé de réception, Date
  - Bouton "Contrôle de lot" avant diffusion
- **Onglet 3 : "Statistiques"**
  - Cartes : nb documents totaux, nb bulletins distribués, taux d'accusé de réception
  - Graphique : distribution par type, par mois
  - Table : documents non accusés (relance possible)

### F.4 — Page : ESignaturePage (admin/RH)

**Fichier : `@/pages/hr/ESignaturePage.tsx`** (nouveau)

**Structure :**
- Table des documents en attente de signature : Employé, Document, Date demande, Statut
- Bouton "Envoyer demande de signature" (sélection document + employé)
- Suivi des signatures en temps réel

### F.5 — Extension PaySlipsPage

**Fichier : `@/pages/PaySlipsPage.tsx`** (modifier)
- Ajouter bouton "Distribuer les bulletins" sur chaque pay_run
- Ajouter colonne "Distribué" (✓/✗) sur chaque bulletin
- Ajouter colonne "Accusé de réception"

---

## Sprint G — Fonctionnalités Paie avancées

> **Prérequis** : Sprint A
> **Effort** : Important
> **Fichiers créés** : 2 | **Fichiers modifiés** : 4

### G.1 — Calcul de paie à l'envers

**Fichier : `@/lib/payroll.ts`** (modifier)

```typescript
export function calculateGrossFromNet(
  targetNet: number,
  components: PayrollComponent[],
  employeeProfile: Employee
): { grossSalary: number, breakdown: PayrollBreakdown[] }
// Logique : itération pour trouver le brut qui donne le net souhaité
// en tenant compte des tranches de cotisations, du barème IR, etc.
```

### G.2 — Assistant de préparation de la paie

**Fichier : `@/pages/hr/PayrollPreparationPage.tsx`** (nouveau)

**Structure :**
- **Étape 1 : Sélection de la période**
  - Mois/année, pay_run existant ou nouveau
- **Étape 2 : Report des éléments constants**
  - Liste des employés actifs avec leur salaire de base
  - Checkbox pour inclure/exclure un employé
- **Étape 3 : Saisie des éléments variables**
  - Pour chaque employé : heures sup, primes, absences, acomptes
  - Import automatique depuis les timesheets approuvés
  - Import automatique depuis les notes de frais approuvées
  - Import automatique depuis les congés (déduction jours non travaillés)
  - Gestion des titres restaurant
- **Étape 4 : Calcul et prévisualisation**
  - Table récapitulative : brut, cotisations, net, employeur
  - Alertes : anomalies, écarts par rapport au mois précédent
- **Étape 5 : Validation**
  - Génération des bulletins
  - Bouton "Calcul à l'envers" pour un employé (brut → net souhaité)

### G.3 — Titres restaurant

**Fichier : `@/pages/hr/MealVouchersPage.tsx`** (nouveau)

**Structure :**
- Table des employés : nombre de titres, valeur unitaire, montant mensuel
- Paramétrage : valeur du titre, jours éligibles (lun-sam), plafond
- Calcul automatique : nb jours travaillés × valeur du titre
- Export pour commande (CSV/Excel)

### G.4 — Assistant de sortie du salarié

**Fichier : `@/pages/hr/EmployeeExitPage.tsx`** (nouveau)

**Structure :**
- **Étape 1 : Sélection de l'employé**
- **Étape 2 : Date et motif de sortie**
- **Étape 3 : Calcul du solde de tout compte**
  - Solde des congés payés (indemnité compensatrice)
  - Solde des RTT
  - Primes sur la période
  - Acomptes à déduire
  - Heures sup non payées
- **Étape 4 : Documents de sortie**
  - Certificat de travail
  - Reçu pour solde de tout compte
  - Attestation Pôle Emploi (France Travail)
- **Étape 5 : Déclarations**
  - DSN fin de contrat (génération automatique)
  - DPAE de fin (si applicable)
- **Étape 6 : Validation**
  - Mise à jour du statut employé → 'inactive'
  - Génération du bulletin de sortie
  - Archivage des documents dans le coffre-fort

### G.5 — Suivi du CPF

**Fichier : `@/pages/hr/CPFPage.tsx`** (nouveau)

**Structure :**
- Table des employés : solde CPF (heures), dernière mise à jour
- Historique des utilisations : employé, formation, heures consommées, date
- Import automatique depuis moncompteformation.gouv.fr (API si disponible)
- Alertes : CPF expirant, solde important non utilisé

### G.6 — Suivi de la pénibilité

**Fichier : `@/pages/hr/HardshipPage.tsx`** (nouveau)

**Structure :**
- Table des employés avec exposition : type d'exposition, niveau, durée
- Cartes de suivi par type (bruit, posture, produits chimiques, etc.)
- Calcul des points de pénibilité (C3P)
- Historique des expositions par employé
- Export pour déclaration

### G.7 — Suivi des carrières

**Fichier : `@/pages/hr/CareerHistoryPage.tsx`** (nouveau)

**Structure :**
- Table : Employé, Date, Événement (embauche, promotion, mobilité, augmentation), Ancien poste, Nouveau poste, Ancien salaire, Nouveau salaire
- Filtre par employé, par période, par type d'événement
- Vue timeline par employé
- CRUD complet

### G.8 — Extension PayRunsPage

**Fichier : `@/pages/PayRunsPage.tsx`** (modifier)
- Ajouter bouton "Assistant de préparation" qui redirige vers PayrollPreparationPage
- Ajouter bouton "Calcul à l'envers" sur un employé
- Ajouter colonne "Titres restaurant"
- Ajouter import automatique des éléments variables (timesheets, congés, notes de frais)

### G.9 — Extension PaySlipsPage

**Fichier : `@/pages/PaySlipsPage.tsx`** (modifier)
- Ajouter bouton "Bulletin de sortie" (génère un bulletin final)
- Ajouter colonne "Type" (normal, acompte, rappel, sortie)
- Ajouter prévisualisation PDF du bulletin

### G.10 — Extension PayrollCalcPage

**Fichier : `@/pages/PayrollCalcPage.tsx`** (modifier)
- Ajouter mode "Calcul à l'envers" : input net souhaité → output brut
- Ajouter gestion des titres restaurant dans le calcul
- Ajouter gestion des frais de transport (forfait mobilité durable)

---

## Sprint H — Déclarations sociales spécifiques

> **Prérequis** : Sprint A, Sprint G
> **Effort** : Faible
> **Fichiers créés** : 1 | **Fichiers modifiés** : 2

### H.1 — Queries

```typescript
// ============ Déclarations spécifiques ============
export async function generateDADSU(period)  // DADS-U
export async function generateDUCS(period)   // DUCS URSSAF
export async function generateAED(period)    // AED (attestation employeur)
export async function generateDTSMSA(period) // DTS-MSA (secteur agricole)
export async function generateCIBTP(period)  // CIBTP (BTP)
export async function generateCongesPayesBTP(period) // Congés Payés BTP
export async function configureCICE(params)  // CICE paramétrage
export async function generateRefusCDI(period) // Déclaration refus CDI
export async function generateCT2025(period)   // CT2025
```

### H.2 — Page : LegalDeclarationsPage (extension)

**Fichier : `@/pages/LegalDeclarationsPage.tsx`** (modifier)

**Structure :**
- **Onglet "DSN"** (existant + améliorations) :
  - Ajouter IntuiDSN : navigation guidée étape par étape
  - Vérification des anomalies avant transmission
  - Suivi des retours (accepté/rejeté) avec codes d'erreur
- **Onglet "DADS-U"** : génération + téléchargement
- **Onglet "DUCS"** : génération + téléchargement
- **Onglet "AED"** : attestation employeur (génération à la demande)
- **Onglet "BTP"** : CIBTP + Congés Payés BTP
- **Onglet "MSA"** : DTS-MSA (secteur agricole)
- **Onglet "CICE"** : paramétrage + calcul
- **Onglet "Autres"** : Refus CDI, CT2025

### H.3 — Extension DSNPage

**Fichier : `@/pages/Phase4Pages.tsx`** (modifier, section DSNPage)
- Ajouter IntuiDSN : wizard visuel pour la DSN
- Ajouter contrôle des anomalies (validation des données avant transmission)
- Ajouter suivi des retours avec codes d'erreur Net-Entreprises
- Ajouter historique des transmissions

---

## Sprint I — Application Mobile (PWA)

> **Prérequis** : Sprints A, B, C, D, E
> **Effort** : Moyen (PWA, pas d'app native)
> **Fichiers créés** : 3 | **Fichiers modifiés** : 3

### I.1 — Configuration PWA

**Fichier : `@/public/manifest.json`** (modifier)
- Ajouter les icônes pour l'espace employé
- Ajouter les shortcuts : "Mes congés", "Note de frais", "Mes documents"

**Fichier : `@/public/sw.js`** (modifier)
- Cache des pages employee pour accès hors connexion
- Sync en arrière-plan pour les notes de frais hors ligne

### I.2 — Composants mobiles

**Fichier : `@/components/employee/MobileLeaveRequest.tsx`** (nouveau)
- Interface simplifiée pour poser un congé depuis mobile
- Date picker natif
- Affichage du solde en temps réel

**Fichier : `@/components/employee/MobileExpenseCapture.tsx`** (nouveau)
- Capture photo du justificatif
- OCR côté client (Tesseract.js)
- Saisie rapide : catégorie, montant, date
- Mode hors connexion : stockage local + sync au retour

**Fichier : `@/components/employee/MobileApproval.tsx`** (nouveau)
- Interface manager pour valider congés et notes de frais depuis mobile
- Cards empilables (swipe left = rejeter, swipe right = approuver)

### I.3 — Responsive design

**Toutes les pages employee** : assurer le responsive avec TailwindCSS
- Navigation bottom bar sur mobile
- Cards empilables
- Tables scrollables horizontalement
- Modals en plein écran sur mobile

---

## Sprint J — i18n (fr, en, ar)

> **Prérequis** : Tous les sprints précédents
> **Effort** : Faible
> **Fichiers créés** : 3 | **Fichiers modifiés** : 3

### J.1 — Namespace `employee`

**Fichiers : `@/i18n/locales/{fr,en,ar}/employee.json`** (nouveaux)

Structure des clés :
```json
{
  "dashboard": {
    "title": "Tableau de bord",
    "welcome": "Bienvenue {{name}}",
    "myLeaves": "Mes congés",
    "pendingRequests": "Demandes en attente",
    "myExpenses": "Mes notes de frais",
    "upcomingInterviews": "Prochains entretiens",
    "recentActivity": "Activité récente",
    "leavePlanning": "Planning congés"
  },
  "leaves": {
    "title": "Mes congés",
    "myRequests": "Mes demandes",
    "myBalance": "Mon solde",
    "planning": "Planning",
    "newRequest": "Nouvelle demande",
    "leaveType": "Type de congé",
    "startDate": "Date de début",
    "endDate": "Date de fin",
    "halfDay": "Demi-journée",
    "justification": "Justification",
    "uploadJustification": "Télécharger un justificatif",
    "balanceAvailable": "Solde disponible",
    "daysRequested": "Jours demandés",
    "minNoticeWarning": "Délai de prévenance minimum : {{days}} jours",
    "conflictWarning": "Vous avez déjà un congé sur cette période",
    "staffRequiredWarning": "Effectif minimum non respecté sur cette période",
    "cancel": "Annuler la demande",
    "status": { "pending": "En attente", "approved": "Approuvé", "rejected": "Rejeté", "cancelled": "Annulé" },
    "types": { "annual": "Congés payés", "rtt": "RTT", "recovery": "Récupération", "sick": "Maladie", "unpaid": "Sans solde", "other": "Autre" },
    "acquired": "Acquis", "taken": "Pris", "pending": "En attente", "remaining": "Restant", "carryOver": "Report",
    "managerApprovals": "Validations manager",
    "approve": "Approuver", "reject": "Rejeter", "managerComment": "Commentaire"
  },
  "profile": {
    "title": "Mon dossier",
    "personalInfo": "Informations personnelles",
    "professionalInfo": "Informations professionnelles",
    "career": "Carrière",
    "alerts": "Alertes",
    "requestChange": "Demander une modification",
    "photo": "Photo",
    "birthDate": "Date de naissance",
    "birthPlace": "Lieu de naissance",
    "nationality": "Nationalité",
    "socialSecurity": "Numéro de sécurité sociale",
    "address": "Adresse",
    "postalCode": "Code postal",
    "city": "Ville",
    "country": "Pays",
    "emergencyContact": "Contact d'urgence",
    "maritalStatus": "Situation familiale",
    "dependents": "Personnes à charge",
    "bankDetails": "Coordonnées bancaires",
    "iban": "IBAN",
    "bic": "BIC",
    "transportMode": "Mode de transport",
    "transportCost": "Frais de transport",
    "mealVouchers": "Titres restaurant",
    "manager": "Manager",
    "hireDate": "Date d'embauche",
    "position": "Poste",
    "department": "Département"
  },
  "expenses": {
    "title": "Mes notes de frais",
    "newReport": "Nouvelle note de frais",
    "period": "Période",
    "totalAmount": "Montant total",
    "totalVat": "TVA totale",
    "submit": "Soumettre",
    "addLine": "Ajouter une ligne",
    "date": "Date",
    "description": "Description",
    "category": "Catégorie",
    "amountHT": "Montant HT",
    "vatRate": "Taux TVA",
    "vatAmount": "Montant TVA",
    "amountTTC": "Montant TTC",
    "receipt": "Justificatif",
    "uploadReceipt": "Télécharger le justificatif",
    "ocrProcessing": "Extraction automatique...",
    "ceilingExceeded": "Plafond dépassé pour cette catégorie",
    "status": { "draft": "Brouillon", "submitted": "Soumise", "approved": "Approuvée", "rejected": "Rejetée", "reimbursed": "Remboursée" },
    "managerApprovals": "Validations manager",
    "approve": "Approuver", "reject": "Rejeter",
    "markReimbursed": "Marquer remboursé",
    "generateAccounting": "Générer écritures comptables"
  },
  "interviews": {
    "title": "Mes entretiens",
    "myObjectives": "Mes objectifs",
    "type": "Type",
    "scheduledDate": "Date prévue",
    "conductedAt": "Date de réalisation",
    "myFeedback": "Mon feedback",
    "managerFeedback": "Feedback manager",
    "rating": "Évaluation",
    "submitFeedback": "Soumettre mon feedback",
    "objectives": { "title": "Objectifs", "target": "Cible", "progress": "Progression", "period": "Période", "frequency": "Fréquence", "updateProgress": "Mettre à jour", "status": { "active": "Actif", "achieved": "Atteint", "missed": "Manqué", "cancelled": "Annulé" } },
    "types": { "annual": "Annuel", "mid_year": "Mi-année", "professional": "Professionnel", "exit": "Fin de mission", "other": "Autre" },
    "campaigns": { "title": "Campagnes", "new": "Nouvelle campagne", "launch": "Lancer", "close": "Clôturer", "remind": "Relancer", "progress": "Avancement" }
  },
  "documents": {
    "title": "Mes documents",
    "coffreFort": "Coffre-fort",
    "type": "Type",
    "uploadDate": "Date",
    "download": "Télécharger",
    "acknowledge": "Accuser réception",
    "sign": "Signer",
    "types": { "payslip": "Bulletin de paie", "contract": "Contrat", "certificate": "Certificat", "other": "Autre" },
    "distribution": "Distribution bulletins",
    "distribute": "Distribuer",
    "batchControl": "Contrôle de lot",
    "statistics": "Statistiques",
    "totalDocuments": "Documents totaux",
    "distributedPayslips": "Bulletins distribués",
    "acknowledgmentRate": "Taux d'accusé de réception"
  },
  "payroll": {
    "preparation": "Préparation de la paie",
    "step": "Étape",
    "selectPeriod": "Sélection de la période",
    "constantElements": "Éléments constants",
    "variableElements": "Éléments variables",
    "preview": "Prévisualisation",
    "validation": "Validation",
    "reverseCalc": "Calcul à l'envers",
    "targetNet": "Net souhaité",
    "calculatedGross": "Brut calculé",
    "mealVouchers": "Titres restaurant",
    "employeeExit": "Sortie de salarié",
    "exitDate": "Date de sortie",
    "exitReason": "Motif de sortie",
    "finalSettlement": "Solde de tout compte",
    "exitDocuments": "Documents de sortie",
    "workCertificate": "Certificat de travail",
    "poleEmploiAttestation": "Attestation Pôle Emploi",
    "cpf": "Compte Personnel de Formation",
    "cpfBalance": "Solde CPF (heures)",
    "hardship": "Pénibilité",
    "career": "Suivi des carrières"
  },
  "nav": {
    "dashboard": "Tableau de bord",
    "leaves": "Mes congés",
    "profile": "Mon dossier",
    "expenses": "Mes notes de frais",
    "interviews": "Mes entretiens",
    "documents": "Mes documents"
  }
}
```

### J.2 — Namespace `hr` (extension)

**Fichiers : `@/i18n/locales/{fr,en,ar}/hr.json`** (modifier)

Ajouter les clés pour :
- `leaveRules` : règles de congés, jours fériés, workflows
- `documentManagement` : gestion documentaire, distribution, e-signature
- `payrollPreparation` : assistant de préparation
- `employeeExit` : assistant de sortie
- `cpf` : suivi CPF
- `hardship` : pénibilité
- `career` : carrières
- `mealVouchers` : titres restaurant
- `campaigns` : campagnes d'entretiens
- `expenseCategories` : catégories de dépenses
- `declarations` : DADS-U, DUCS, AED, BTP, MSA, CICE, IntuiDSN

---

## Ordre de mise en œuvre recommandé

| Sprint | Durée estimée | Dépendances | Priorité |
|---|---|---|---|
| **A** — Rôle Employee & Auth | 2-3 jours | Aucune | 🔴 Bloquant |
| **B** — Congés & Absences | 3-4 jours | A | 🔴 Haute |
| **D** — Notes de Frais | 3-4 jours | A | 🔴 Haute |
| **C** — Dossier Salarié | 2 jours | A | 🟡 Moyenne |
| **E** — Entretiens & Objectifs | 2-3 jours | A | 🟡 Moyenne |
| **F** — Dématérialisation RH | 3 jours | A | 🔴 Haute |
| **G** — Paie avancée | 4-5 jours | A | 🟡 Moyenne |
| **H** — Déclarations spécifiques | 1-2 jours | G | 🟢 Basse |
| **I** — PWA Mobile | 2-3 jours | B, C, D, E | 🟢 Basse |
| **J** — i18n | 1-2 jours | Tous | 🔴 Obligatoire |

**Total estimé : 20-28 jours de développement**

---

## Liste complète des nouveaux fichiers

### Pages Espace Employé (7)
1. `@/pages/employee/EmployeeDashboardPage.tsx`
2. `@/pages/employee/EmployeeLeavesPage.tsx`
3. `@/pages/employee/EmployeeProfilePage.tsx`
4. `@/pages/employee/EmployeeExpensesPage.tsx`
5. `@/pages/employee/EmployeeInterviewsPage.tsx`
6. `@/pages/employee/EmployeeDocumentsPage.tsx`
7. `@/pages/employee/ManagerLeaveApprovalsPage.tsx`
8. `@/pages/employee/ManagerExpenseApprovalsPage.tsx`

### Pages Admin/RH (10)
9. `@/pages/settings/LeaveRulesPage.tsx`
10. `@/pages/hr/PayrollPreparationPage.tsx`
11. `@/pages/hr/MealVouchersPage.tsx`
12. `@/pages/hr/EmployeeExitPage.tsx`
13. `@/pages/hr/CPFPage.tsx`
14. `@/pages/hr/HardshipPage.tsx`
15. `@/pages/hr/CareerHistoryPage.tsx`
16. `@/pages/hr/InterviewCampaignsPage.tsx`
17. `@/pages/hr/DocumentManagementPage.tsx`
18. `@/pages/hr/ESignaturePage.tsx`

### Composants (4)
19. `@/components/EmployeeLayout.tsx`
20. `@/components/employee/MobileLeaveRequest.tsx`
21. `@/components/employee/MobileExpenseCapture.tsx`
22. `@/components/employee/MobileApproval.tsx`

### Locale files (3)
23. `@/i18n/locales/fr/employee.json`
24. `@/i18n/locales/en/employee.json`
25. `@/i18n/locales/ar/employee.json`

### SQL (1)
26. `@/sql/23_espace_employe_rh.sql`

### Fichiers modifiés (15+)
- `@/types/index.ts` — nouveaux types + extensions
- `@/lib/queries.ts` — nouvelles queries + rôle employee
- `@/lib/auth.tsx` — gestion rôle employee
- `@/lib/supabase.ts` — TENANT_TABLES
- `@/lib/payroll.ts` — calcul à l'envers
- `@/App.tsx` — routes espace employé
- `@/components/ProtectedRoute.tsx` — EmployeeRoute
- `@/pages/EmployeesPage.tsx` — champs étendus
- `@/pages/LeaveRequestsPage.tsx` — extensions
- `@/pages/PayRunsPage.tsx` — assistant préparation
- `@/pages/PaySlipsPage.tsx` — distribution bulletins
- `@/pages/PayrollCalcPage.tsx` — calcul à l'envers
- `@/pages/LegalDeclarationsPage.tsx` — déclarations spécifiques
- `@/pages/Phase4Pages.tsx` — extensions DSN, ExpenseReports, Interviews
- `@/i18n/locales/{fr,en,ar}/hr.json` — clés RH étendues
- `@/public/manifest.json` — PWA
- `@/public/sw.js` — cache offline
- `@/components/Layout.tsx` — nav espace employé
- `@/components/ui.tsx` — routeLabels

**Total : ~26 nouveaux fichiers + ~19 fichiers modifiés**
