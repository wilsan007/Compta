# PARTIE 1 — Sprint A : Fondations RH & Fiches Personnel Complètes (4-5j)

> **Objectif** : Rôle Employee + Auth, Extension fiches personnel (état civil, coords, RIB, manager), Multi-contrats, Convention collective, Modification en masse, Hiérarchie managériale
> **i18n** : `useTranslation` (fr, en, ar) sur tous nouveaux composants
> **SQL** : `app/sql/57_sprint_a_rh_fondations.sql`

---

## 1.1 Vue d'ensemble

```
Rôle Employee (auth) ──→ Fiche personnel étendue ──→ Multi-contrats
         │                       │                       │
         │                       ├── État civil          ├── Convention collective
         │                       ├── Coordonnées         ├── Périodes d'essai
         │                       ├── RIB / IBAN          ├── Renouvellements
         │                       ├── Contact urgence     └── Suspend/Reprise
         │                       ├── Manager
         │                       ├── Photo
         │                       └── Sortie
         │
         ├── EmployeeLayout (nav simplifiée)
         ├── EmployeeRoute (protection)
         └── Liaison Employé ↔ Compte utilisateur
```

### Fonctionnalités Sage 100 couvertes (recherche internet)
- **Fiche de personnel détaillée** : état civil, immatriculation, données personnelles, coordonnées, médecine du travail
- **Multi-contrats** : plusieurs contrats simultanés pour un même salarié
- **Modification en masse** des fiches de personnel
- **Convention collective** : paramétrage par secteur d'activité
- **Plan de Paie Sage (PPS)** : pré-paramétré par catégorie de salariés (cadres, non-cadres, apprentis, BTP…)
- **Bulletins modèles** par catégorie de salariés
- **Gestion de la pénibilité** (fondations — table existante)
- **Archivage des données** pour 10 ans
- **Gestion des honoraires**
- **Import Excel** / **Publipostage Word**
- **Personnalisation des écrans**

---

## 1.2 SQL — Nouvelles tables

### `employee_contracts` (Multi-contrats)
```sql
CREATE TABLE IF NOT EXISTS employee_contracts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  contract_number text,
  contract_type text NOT NULL,        -- 'permanent'|'fixedTerm'|'apprenticeship'|'internship'|'freelance'|'interim'
  status text NOT NULL DEFAULT 'active', -- 'active'|'suspended'|'ended'
  start_date date NOT NULL,
  end_date date,                       -- NULL si CDI
  trial_period_days int DEFAULT 0,
  trial_period_end_date date,
  position text,
  department text,
  working_hours_per_week numeric(5,2) DEFAULT 35,
  weekly_schedule text,               -- 'Lundi-Vendredi 9h-17h'
  salary_type text DEFAULT 'monthly',  -- 'monthly'|'hourly'|'annual'
  base_salary numeric(15,2) DEFAULT 0,
  salary_currency text DEFAULT 'EUR',
  collective_agreement_id uuid,        -- FK vers collective_agreements
  job_category text,                   -- catégorie conventionnelle
  coefficient text,                    -- coefficient hiérarchique
  level text,                          -- niveau
  echelon text,                        -- échelon
  position_code text,                  -- code poste
  work_location text,
  telework_percentage numeric(5,2) DEFAULT 0,
  suspension_reason text,              -- 'maladie'|'congé_parental'|'mise_pied'|'autre'
  suspension_start date,
  suspension_end date,
  end_reason text,                     -- 'resignation'|'dismissal'|'end_contract'|'retirement'|'mutual_agreement'
  end_documents_generated boolean DEFAULT false,
  parent_contract_id uuid,             -- si renouvellement, lien vers contrat original
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_emp_contracts_employee ON employee_contracts(employee_id);
CREATE INDEX IF NOT EXISTS idx_emp_contracts_status ON employee_contracts(status);
CREATE INDEX IF NOT EXISTS idx_emp_contracts_dates ON employee_contracts(start_date, end_date);
ALTER TABLE employee_contracts ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_employee_contracts') THEN
    CREATE POLICY "allow_all_employee_contracts" ON employee_contracts FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `collective_agreements` (Conventions collectives)
```sql
CREATE TABLE IF NOT EXISTS collective_agreements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  code text NOT NULL,                  -- code IDCC (ex: '3248' pour Métallurgie)
  name text NOT NULL,                  -- 'Convention Collective Nationale de la Métallurgie'
  short_name text,                     -- 'Métallurgie'
  sector text,                         -- 'industrie'|'services'|'btp'|'agriculture'|'commerce'|'autre'
  pay_scale_plan text,                 -- plan de paie associé (PPS)
  minimum_wage_decimal numeric(15,2),  -- salaire minimum conventionnel
  overtime_rate numeric(5,2) DEFAULT 25, -- % majoration heures sup
  meal_voucher_eligible boolean DEFAULT true,
  transport_eligible boolean DEFAULT true,
  leave_rules jsonb DEFAULT '{}'::jsonb, -- règles de congés spécifiques
  active boolean DEFAULT true,
  effective_date date,
  expiry_date date,
  notes text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_collective_agreements_code ON collective_agreements(code);
ALTER TABLE collective_agreements ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_collective_agreements') THEN
    CREATE POLICY "allow_all_collective_agreements" ON collective_agreements FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `employee_fields_config` (Personnalisation des écrans)
```sql
CREATE TABLE IF NOT EXISTS employee_fields_config (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  field_key text NOT NULL,             -- 'birth_date', 'social_security_number', etc.
  field_label text,
  field_section text,                  -- 'personal'|'professional'|'banking'|'emergency'
  field_type text DEFAULT 'text',      -- 'text'|'date'|'number'|'select'|'boolean'
  visible_admin boolean DEFAULT true,
  visible_manager boolean DEFAULT true,
  visible_employee boolean DEFAULT true,
  editable_employee boolean DEFAULT false,
  required boolean DEFAULT false,
  sort_order int DEFAULT 0,
  options jsonb,                       -- pour les selects
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_emp_fields_config_tenant ON employee_fields_config(tenant_id);
ALTER TABLE employee_fields_config ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_employee_fields_config') THEN
    CREATE POLICY "allow_all_employee_fields_config" ON employee_fields_config FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `bulk_modification_logs` (Suivi des modifications en masse)
```sql
CREATE TABLE IF NOT EXISTS bulk_modification_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  performed_by text NOT NULL,
  modification_type text NOT NULL,     -- 'salary_increase'|'department_change'|'manager_change'|'collective_agreement_change'
  affected_count int NOT NULL,
  field_name text NOT NULL,
  old_value text,
  new_value text,
  effective_date date,
  employee_ids uuid[] DEFAULT '{}',
  notes text,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE bulk_modification_logs ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_bulk_mod_logs') THEN
    CREATE POLICY "allow_all_bulk_mod_logs" ON bulk_modification_logs FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

---

## 1.3 SQL — Extensions de tables existantes

```sql
-- Étendre employees avec données RH complètes (état civil, coords, etc.)
ALTER TABLE employees ADD COLUMN IF NOT EXISTS tenant_id uuid;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS first_name text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS last_name text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS birth_date date;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS birth_place text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS nationality text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS social_security_number text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS address text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS postal_code text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS city text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS country text DEFAULT 'FR';
ALTER TABLE employees ADD COLUMN IF NOT EXISTS emergency_contact_name text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS emergency_contact_phone text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS emergency_contact_relation text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS bank_iban text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS bank_bic text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS bank_account_holder text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS marital_status text;  -- 'single'|'married'|'divorced'|'widowed'|'pacs'
ALTER TABLE employees ADD COLUMN IF NOT EXISTS dependents_count int DEFAULT 0;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS transport_mode text;  -- 'public'|'car'|'bike'|'walk'|'other'
ALTER TABLE employees ADD COLUMN IF NOT EXISTS transport_cost decimal(15,2) DEFAULT 0;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS meal_voucher_count int DEFAULT 0;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS meal_voucher_value decimal(15,2) DEFAULT 0;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS manager_id uuid REFERENCES employees(id) ON DELETE SET NULL;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS photo_url text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS exit_date date;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS exit_reason text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS auth_id uuid;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS tenant_user_id uuid REFERENCES tenant_users(id) ON DELETE SET NULL;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS medical_exam_date date;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS medical_exam_due_date date;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS occupational_medicine_id text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS handicapped_worker boolean DEFAULT false;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS rcdp_date date;       -- reconnaissance travailleur handicapé
ALTER TABLE employees ADD COLUMN IF NOT EXISTS hire_date date;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS seniority_date date;  -- date d'ancienneté (peut différer de hire_date)

-- Étendre leave_requests
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS tenant_id uuid;
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS justification_url text;
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS manager_id uuid REFERENCES employees(id) ON DELETE SET NULL;
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS manager_comment text;
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS half_day boolean DEFAULT false;
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS requested_at timestamptz DEFAULT now();

-- Étendre expense_reports
ALTER TABLE expense_reports ADD COLUMN IF NOT EXISTS manager_id uuid;
ALTER TABLE expense_reports ADD COLUMN IF NOT EXISTS manager_comment text;
ALTER TABLE expense_reports ADD COLUMN IF NOT EXISTS reimbursement_date date;

-- Étendre interviews
ALTER TABLE interviews ADD COLUMN IF NOT EXISTS tenant_id uuid;
ALTER TABLE interviews ADD COLUMN IF NOT EXISTS manager_id uuid;
ALTER TABLE interviews ADD COLUMN IF NOT EXISTS employee_feedback text;
ALTER TABLE interviews ADD COLUMN IF NOT EXISTS employee_rating int;
ALTER TABLE interviews ADD COLUMN IF NOT EXISTS form_data jsonb;
ALTER TABLE interviews ADD COLUMN IF NOT EXISTS campaign_id uuid;

-- Étendre pay_slips avec type
ALTER TABLE pay_slips ADD COLUMN IF NOT EXISTS slip_type text DEFAULT 'normal'
  CHECK (slip_type IN ('normal', 'advance', 'recall', 'exit', 'complement'));
ALTER TABLE pay_slips ADD COLUMN IF NOT EXISTS collective_agreement_id uuid;
ALTER TABLE pay_slips ADD COLUMN IF NOT EXISTS contract_id uuid REFERENCES employee_contracts(id) ON DELETE SET NULL;

-- Étendre payroll_components avec convention collective
ALTER TABLE payroll_components ADD COLUMN IF NOT EXISTS collective_agreement_id uuid;
ALTER TABLE payroll_components ADD COLUMN IF NOT EXISTS employee_category text; -- 'cadre'|'non_cadre'|'apprenti'|'stagiaire'
```

---

## 1.4 Types TypeScript (`types/index.ts`)

### Nouvelles interfaces
```typescript
export interface EmployeeContract {
  id: string
  tenant_id: string | null
  employee_id: string
  contract_number: string | null
  contract_type: 'permanent' | 'fixedTerm' | 'apprenticeship' | 'internship' | 'freelance' | 'interim'
  status: 'active' | 'suspended' | 'ended'
  start_date: string
  end_date: string | null
  trial_period_days: number
  trial_period_end_date: string | null
  position: string | null
  department: string | null
  working_hours_per_week: number
  weekly_schedule: string | null
  salary_type: 'monthly' | 'hourly' | 'annual'
  base_salary: number
  salary_currency: string
  collective_agreement_id: string | null
  job_category: string | null
  coefficient: string | null
  level: string | null
  echelon: string | null
  position_code: string | null
  work_location: string | null
  telework_percentage: number
  suspension_reason: string | null
  suspension_start: string | null
  suspension_end: string | null
  end_reason: string | null
  end_documents_generated: boolean
  parent_contract_id: string | null
  notes: string | null
  created_at: string
  updated_at: string
}

export interface CollectiveAgreement {
  id: string
  tenant_id: string | null
  code: string
  name: string
  short_name: string | null
  sector: string | null
  pay_scale_plan: string | null
  minimum_wage_decimal: number | null
  overtime_rate: number
  meal_voucher_eligible: boolean
  transport_eligible: boolean
  leave_rules: Record<string, any>
  active: boolean
  effective_date: string | null
  expiry_date: string | null
  notes: string | null
  created_at: string
}

export interface EmployeeFieldConfig {
  id: string
  tenant_id: string | null
  field_key: string
  field_label: string | null
  field_section: 'personal' | 'professional' | 'banking' | 'emergency'
  field_type: 'text' | 'date' | 'number' | 'select' | 'boolean'
  visible_admin: boolean
  visible_manager: boolean
  visible_employee: boolean
  editable_employee: boolean
  required: boolean
  sort_order: number
  options: any
  active: boolean
  created_at: string
}

export interface BulkModificationLog {
  id: string
  tenant_id: string | null
  performed_by: string
  modification_type: 'salary_increase' | 'department_change' | 'manager_change' | 'collective_agreement_change'
  affected_count: number
  field_name: string
  old_value: string | null
  new_value: string | null
  effective_date: string | null
  employee_ids: string[]
  notes: string | null
  created_at: string
}
```

### Champs à ajouter aux interfaces existantes
| Interface | Champs |
|---|---|
| `Employee` | `tenant_id?`, `first_name?`, `last_name?`, `birth_date?`, `birth_place?`, `nationality?`, `social_security_number?`, `address?`, `postal_code?`, `city?`, `country?`, `emergency_contact_name?`, `emergency_contact_phone?`, `emergency_contact_relation?`, `bank_iban?`, `bank_bic?`, `bank_account_holder?`, `marital_status?`, `dependents_count?`, `transport_mode?`, `transport_cost?`, `meal_voucher_count?`, `meal_voucher_value?`, `manager_id?`, `photo_url?`, `exit_date?`, `exit_reason?`, `auth_id?`, `tenant_user_id?`, `medical_exam_date?`, `medical_exam_due_date?`, `occupational_medicine_id?`, `handicapped_worker?`, `rcdp_date?`, `hire_date?`, `seniority_date?` |
| `LeaveRequest` | `tenant_id?`, `justification_url?`, `manager_id?`, `manager_comment?`, `half_day?`, `requested_at?` |
| `ExpenseReport` | `manager_id?`, `manager_comment?`, `reimbursement_date?` |
| `Interview` | `tenant_id?`, `manager_id?`, `employee_feedback?`, `employee_rating?`, `form_data?`, `campaign_id?` |
| `PaySlip` | `slip_type?`, `collective_agreement_id?`, `contract_id?` |
| `PayrollComponent` | `collective_agreement_id?`, `employee_category?` |

---

## 1.5 Queries (`queries.ts` + nouvelles)

### Rôle Employee & Auth
```typescript
export async function linkEmployeeToUser(employeeId: string, authId: string, tenantUserId: string)
// Met à jour employees.auth_id et employees.tenant_user_id

export async function getEmployeeByUserId(userId: string)
// Récupère l'employé lié à l'utilisateur connecté

export async function getMyEmployeeProfile()
// Récupère le profil complet de l'employé connecté (self-service)
```

### Multi-contrats
```typescript
export async function getEmployeeContracts(employeeId: string)
// Tous les contrats d'un employé (actifs + historique)

export async function getActiveEmployeeContract(employeeId: string)
// Contrat actif courant

export async function createEmployeeContract(data: Omit<EmployeeContract, 'id' | 'created_at' | 'updated_at'>)
export async function updateEmployeeContract(id: string, updates: Partial<EmployeeContract>)
export async function endEmployeeContract(id: string, endReason: string, endDate: string)
export async function suspendEmployeeContract(id: string, reason: string, startDate: string, endDate?: string)
export async function reinstateEmployeeContract(id: string)
export async function renewEmployeeContract(contractId: string, newEndDate: string)
// Crée un nouveau contrat lié au parent_contract_id
```

### Convention collective
```typescript
export async function getCollectiveAgreements(activeOnly?: boolean)
export async function getCollectiveAgreementById(id: string)
export async function createCollectiveAgreement(data: Omit<CollectiveAgreement, 'id' | 'created_at'>)
export async function updateCollectiveAgreement(id: string, updates: Partial<CollectiveAgreement>)
export async function deleteCollectiveAgreement(id: string)
```

### Modification en masse
```typescript
export async function bulkUpdateEmployees(
  employeeIds: string[],
  field: string,
  value: any,
  effectiveDate?: string
)
// Met à jour un champ pour plusieurs employés + crée un bulk_modification_log

export async function bulkSalaryIncrease(
  employeeIds: string[],
  increaseType: 'percentage' | 'fixed',
  increaseValue: number,
  effectiveDate: string
)
// Augmentation de salaire en masse (pourcentage ou montant fixe)

export async function getBulkModificationLogs()
// Historique des modifications en masse
```

### Personnalisation des écrans
```typescript
export async function getEmployeeFieldsConfig()
export async function updateEmployeeFieldConfig(id: string, updates: Partial<EmployeeFieldConfig>)
export async function createEmployeeFieldConfig(data: Omit<EmployeeFieldConfig, 'id' | 'created_at'>)
```

---

## 1.6 Auth & Permissions

### Fichier : `@/lib/auth.tsx` (modifier)
```typescript
// Ajouter le cas 'employee' dans canPerform :
if (user.role === 'employee') {
  const employeeTables = [
    'leave_requests', 'expense_reports', 'expense_report_lines',
    'employee_documents', 'employee_objectives', 'interviews', 'timesheets',
    'leave_balances', 'employees'
  ]
  if (action === 'select' && employeeTables.includes(table)) return true
  if (action === 'insert' && ['leave_requests', 'expense_reports', 'expense_report_lines'].includes(table)) return true
  if (action === 'update' && ['leave_requests', 'expense_reports', 'expense_report_lines', 'employees'].includes(table)) return true
  return false
}
```

### Fichier : `@/lib/queries.ts` (modifier)
- Modifier le type `TenantUser['role']` : ajouter `'employee'`
- Modifier `ROLE_LABELS` : ajouter `employee: 'Employé'`
- Modifier `ROLE_DESCRIPTIONS` : ajouter `employee: 'Accès à son espace employé (congés, notes de frais, documents)'`

### Fichier : `@/lib/supabase.ts` (modifier)
- Ajouter dans `TENANT_TABLES` :
```
'employee_contracts', 'collective_agreements', 'employee_fields_config',
'bulk_modification_logs', 'leave_balances', 'public_holidays', 'leave_rules',
'approval_workflows', 'employee_objectives', 'interview_campaigns', 'employee_documents'
```

### Fichier : `@/components/ProtectedRoute.tsx` (modifier)
- Ajouter `EmployeeRoute` qui vérifie `user.role === 'employee'`
- Rediriger vers le dashboard principal si l'utilisateur n'est pas employé

---

## 1.7 Nouveau composant — `EmployeeLayout.tsx`

**Fichier** : `app/src/components/EmployeeLayout.tsx` (nouveau)

- Layout simplifié (nav horizontale, pas de sidebar complète)
- Items : Tableau de bord, Mes congés, Mon dossier, Mes notes de frais, Mes entretiens, Mes documents
- Language switcher (fr/en/ar)
- Avatar + nom de l'employé
- Responsive mobile (bottom bar)

---

## 1.8 Pages

### `EmployeeContractsPage.tsx` (nouveau — admin/RH)
**Fichier** : `@/pages/hr/EmployeeContractsPage.tsx`

**Structure :**
- **Table principale** : Employé, N° contrat, Type, Statut, Date début, Date fin, Poste, Département, Actions
- **Bouton "Nouveau contrat"** : modal avec formulaire complet
  - Employé (select)
  - Type de contrat (select : CDI, CDD, Apprentissage, Stage, Freelance, Intérim)
  - Date de début / fin
  - Période d'essai (jours + date de fin auto-calculée)
  - Poste, département, lieu de travail
  - Heures hebdo, planning
  - Salaire de base + type (mensuel/horaire/annuel) + devise
  - Convention collective (select)
  - Catégorie, coefficient, niveau, échelon
  - Télétravail (%)
  - Notes
- **Bouton "Renouveler"** sur les CDD : crée un nouveau contrat lié au parent
- **Bouton "Suspendre"** : modal (raison, dates)
- **Bouton "Réintégrer"** : termine la suspension
- **Bouton "Clôturer"** : modal (raison de fin, date)
- **Vue détaillée** : tous les champs du contrat + historique des renouvellements
- **Filtres** : employé, type, statut, période, convention collective
- **Onglet "Conventions collectives"** : CRUD des conventions
- **Onglet "Catégories"** : gestion des catégories de salariés (cadre, non-cadre, apprenti, stagiaire)
- `useTranslation('hr')`

### `CollectiveAgreementsPage.tsx` (nouveau — admin/RH)
**Fichier** : `@/pages/hr/CollectiveAgreementsPage.tsx`

**Structure :**
- **Table** : Code IDCC, Nom, Secteur, Salaire minimum, Taux heures sup, Actif, Actions
- **Bouton "Nouvelle convention"** : modal avec formulaire
  - Code IDCC, nom, nom court, secteur
  - Salaire minimum conventionnel
  - Taux majoration heures sup
  - Éligibilité titres restaurant / transport
  - Règles de congés (JSON éditable)
  - Dates d'effet / expiration
- **Bouton "Importer PPS"** : import du Plan de Paie Sage (CSV/JSON)
- **Filtres** : secteur, actif
- `useTranslation('hr')`

### `BulkModificationPage.tsx` (nouveau — admin/RH)
**Fichier** : `@/pages/hr/BulkModificationPage.tsx`

**Structure :**
- **Étape 1 : Sélection des employés**
  - Filtres : département, statut, convention collective, type de contrat
  - Table avec checkboxes (sélection multiple)
  - Bouton "Tout sélectionner" / "Tout désélectionner"
- **Étape 2 : Type de modification**
  - Augmentation de salaire (pourcentage ou montant fixe)
  - Changement de département
  - Changement de manager
  - Changement de convention collective
- **Étape 3 : Paramètres**
  - Valeur(s) à appliquer
  - Date d'effet
  - Notes
- **Étape 4 : Confirmation**
  - Table récapitulative : Employé, Ancienne valeur, Nouvelle valeur
  - Bouton "Appliquer" → exécute la modification en masse
- **Onglet "Historique"** : table des bulk_modification_logs avec détail
- `useTranslation('hr')`

### `EmployeeFieldsConfigPage.tsx` (nouveau — admin/RH)
**Fichier** : `@/pages/settings/EmployeeFieldsConfigPage.tsx`

**Structure :**
- **Table** : Champ, Section, Type, Visible admin, Visible manager, Visible employé, Modifiable employé, Requis, Ordre, Actif
- **Bouton "Nouveau champ"** : modal (clé, label, section, type, options, visibilités, modifiable, requis, ordre)
- **Bouton "Réinitialiser"** : restore la config par défaut
- **Drag & drop** pour réordonner les champs
- `useTranslation('hr')`

### Extension `EmployeesPage.tsx` (modifier)
- Ajouter tous les nouveaux champs dans le formulaire de création/édition :
  - **Section État civil** : prénom, nom, date/lieu de naissance, nationalité, n° sécu, situation familiale, enfants à charge, travailleur handicapé
  - **Section Coordonnées** : adresse, code postal, ville, pays, téléphone, email
  - **Section Contact d'urgence** : nom, téléphone, relation
  - **Section Coordonnées bancaires** : titulaire, IBAN, BIC
  - **Section Transport** : mode, coût
  - **Section Titres restaurant** : nombre, valeur
  - **Section Médical** : date dernier examen, date prochain examen, médecine du travail
  - **Section Manager** : select parmi les autres employés
  - **Section Photo** : upload
  - **Section Lien utilisateur** : select des tenant_users sans employé lié
  - **Section Sortie** : date de sortie, motif (si inactif)
- Ajouter bouton "Voir contrats" → redirige vers EmployeeContractsPage filtré
- Ajouter bouton "Voir carrière" → redirige vers CareerHistoryPage filtré
- Ajouter bouton "Voir pénibilité" → redirige vers WorkHardshipPage filtré
- Ajouter bouton "Assistant de sortie" sur les employés actifs
- Ajouter **modification en masse** : sélection multiple + bouton "Modifier en masse"
- Ajouter **import Excel** : bouton "Importer" avec mapping de colonnes
- Ajouter **export Excel** : bouton "Exporter" avec sélection de champs
- Ajouter colonnes : manager, convention collective, type de contrat actif

---

## 1.9 i18n — Clés à ajouter

### Namespace `hr` — nouvelles sections

| Section | Clés principales |
|---|---|
| `contracts.*` | title, new, edit, view, contractNumber, contractType, status, startDate, endDate, trialPeriod, trialPeriodEnd, position, department, workingHours, weeklySchedule, salaryType, baseSalary, currency, collectiveAgreement, jobCategory, coefficient, level, echelon, positionCode, workLocation, telework, suspensionReason, suspensionStart, suspensionEnd, endReason, endDocuments, renew, suspend, reinstate, end, types (permanent/fixedTerm/apprenticeship/internship/freelance/interim), statuses (active/suspended/ended), endReasons (resignation/dismissal/end_contract/retirement/mutual_agreement), parentContract |
| `collectiveAgreements.*` | title, new, edit, code, name, shortName, sector, payScalePlan, minimumWage, overtimeRate, mealVoucherEligible, transportEligible, leaveRules, active, effectiveDate, expiryDate, importPPS, sectors (industry/services/btp/agriculture/commerce/other) |
| `bulkModification.*` | title, step1, step2, step3, step4, selectEmployees, modificationType, salaryIncrease, departmentChange, managerChange, collectiveAgreementChange, increaseType, percentage, fixed, increaseValue, effectiveDate, apply, confirm, oldValue, newValue, history, affectedCount, performedBy |
| `employeeFields.*` | title, fieldKey, fieldLabel, fieldSection, fieldType, visibleAdmin, visibleManager, visibleEmployee, editableEmployee, required, sortOrder, active, new, reset, sections (personal/professional/banking/emergency), types (text/date/number/select/boolean) |
| `employees.*` (ajouts) | firstName, lastName, birthDate, birthPlace, nationality, socialSecurityNumber, emergencyContactName, emergencyContactPhone, emergencyContactRelation, bankIban, bankBic, bankAccountHolder, maritalStatus, dependentsCount, transportMode, transportCost, mealVoucherCount, mealVoucherValue, manager, photo, medicalExamDate, medicalExamDueDate, occupationalMedicine, handicappedWorker, rcdpDate, hireDate, seniorityDate, linkUser, viewContracts, viewCareer, viewHardship, employeeExit, bulkModify, importExcel, exportExcel, maritalStatuses (single/married/divorced/widowed/pacs), transportModes (public/car/bike/walk/other) |
| `employeeRole.*` | role, roleDescription, employeeLayout, dashboard, myLeaves, myProfile, myExpenses, myInterviews, myDocuments |
| `team.roles.*` (ajout) | employee: 'Employé' |
| `team.roleDescriptions.*` (ajout) | employee: 'Accès à son espace employé (congés, notes de frais, documents)' |

**3 langues** : fr (défaut), en, ar (RTL) — fichiers dans `app/src/i18n/locales/{fr,en,ar}/hr.json`

---

## 1.10 Routes App.tsx

```tsx
{/* RH Admin — nouveaux */}
<Route path="/hr/contracts" element={<EmployeeContractsPage />} />
<Route path="/hr/collective-agreements" element={<CollectiveAgreementsPage />} />
<Route path="/hr/bulk-modify" element={<BulkModificationPage />} />
<Route path="/settings/employee-fields" element={<EmployeeFieldsConfigPage />} />

{/* Espace Employés — portail self-service (layout) */}
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

## 1.11 Navigation (`nav.json`)

Ajouter dans les 3 langues (fr, en, ar) :
```json
{
  "employeeContracts": "Contrats",
  "collectiveAgreements": "Conventions collectives",
  "bulkModification": "Modification en masse",
  "employeeFieldsConfig": "Personnalisation fiches",
  "employeeSpace": "Espace employés",
  "employeeDashboard": "Tableau de bord",
  "employeeLeaves": "Mes congés",
  "employeeProfile": "Mon dossier",
  "employeeExpenses": "Mes notes de frais",
  "employeeInterviews": "Mes entretiens",
  "employeeDocuments": "Mes documents"
}
```

---

## 1.12 Fichiers créés / modifiés

### Nouveaux fichiers (6)
1. `@/pages/hr/EmployeeContractsPage.tsx` — Multi-contrats
2. `@/pages/hr/CollectiveAgreementsPage.tsx` — Conventions collectives
3. `@/pages/hr/BulkModificationPage.tsx` — Modification en masse
4. `@/pages/settings/EmployeeFieldsConfigPage.tsx` — Personnalisation écrans
5. `@/components/EmployeeLayout.tsx` — Layout espace employé
6. `@/sql/57_sprint_a_rh_fondations.sql` — Migration SQL

### Fichiers modifiés (8)
- `@/types/index.ts` — nouveaux types + extensions Employee
- `@/lib/queries.ts` — nouvelles queries + rôle employee
- `@/lib/auth.tsx` — gestion rôle employee dans canPerform
- `@/lib/supabase.ts` — TENANT_TABLES
- `@/App.tsx` — nouvelles routes
- `@/pages/EmployeesPage.tsx` — champs étendus + modification en masse
- `@/components/ProtectedRoute.tsx` — EmployeeRoute
- `@/i18n/locales/{fr,en,ar}/hr.json` — clés RH étendues
- `@/i18n/locales/{fr,en,ar}/nav.json` — nouvelles clés navigation
