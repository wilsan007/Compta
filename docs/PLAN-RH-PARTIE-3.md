# PARTIE 3 — Sprints D & E : Gestion Administrative, Arrêts de Travail & Sortie du Salarié (5-6j)

> **Sprint D** (3j) : Arrêts de travail, IJSS, subrogation, garantie du net, suivi médical, pénibilité (C3P), CPF, carrières
> **Sprint E** (2-3j) : Assistant de sortie (6 étapes), solde de tout compte, documents de sortie, DSN fin de contrat, notes de frais (self-service + OCR), entretiens & objectifs
> **i18n** : `useTranslation` (fr, en, ar)
> **SQL** : `app/sql/60_sprint_d_admin_arrets.sql` + `app/sql/61_sprint_e_sortie_notes_entretiens.sql`

---

# SPRINT D : Gestion Administrative, Arrêts de Travail & Suivi RH (3j)

## D.1 Vue d'ensemble

```
Arrêts de travail ──→ IJSS (estimation + réelle) ──→ Subrogation ──→ Garantie du net
       │                    │                           │                    │
       │                    ├── Calcul brut/net         │                    ├── Maintien salaire
       │                    ├── BPIJ (import)            │                    └── Deduction IJSS
       │                    ├── Rapprochement            │
       │                    └── Régularisation           ├── PAS (prélèvement à la source)
       │                                                 └── DSN arrêt/reprise
       │
       ├── Types : maladie, AT, maternité, paternité, accident
       └── Valorisation : ouvrés / ouvrables / calendaires

Suivi médical ──→ Visites obligatoires ──→ Alertes
Pénibilité (C3P) ──→ Expositions par employé ──→ Points ──→ Déclaration
CPF ──→ Solde (heures/€) ──→ Historique utilisations ──→ Alertes
Carrières ──→ Timeline événements ──→ Promotions / Mobilité / Augmentations
```

### Fonctionnalités Sage 100 couvertes (recherche internet)
- **Gestion des arrêts de travail** : calculs automatiques des IJSS et nombres de jours maladie à indemniser selon la convention collective
- **Import des BPIJ** (bordereaux de paiement des indemnités journalières) et rapprochement avec les indemnités déjà versées
- **Subrogation** : maintien du salaire + perception des IJSS par l'employeur
- **Garantie du net** : verser au salarié un net équivalent à celui qu'il aurait perçu
- **Calcul IJSS brutes** à partir des IJSS nettes : `IJSS Brutes = IJSS Nettes / (1 - 0.067)`
- **PAS sur IJ subrogées** : prélèvement à la source sur les IJ (limite de 2 mois pour IJ maladie)
- **Valorisation automatique** à partir des dates saisies
- **Prise en compte des règles de calcul spécifiques** : conditions, barèmes
- **Valorisation en jours ouvrés, ouvrables, calendaires** selon jours fériés, particularités locales
- **Gestion de la pénibilité** (C3P)
- **Suivi du CPF** (Compte Personnel de Formation)
- **Gestion des provisions de congés payés** (déjà couvert au Sprint B)
- **Archivage des données** pour 10 ans
- **Éditions légales pré-paramétrées**
- **Gestion des honoraires**
- **Médecine du travail** : suivi des visites

---

## D.2 SQL — Nouvelles tables

### `work_stoppages` (Arrêts de travail)
```sql
CREATE TABLE IF NOT EXISTS work_stoppages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  stoppage_type text NOT NULL,          -- 'maladie'|'accident_travail'|'maladie_professionnelle'|'maternite'|'paternite'|'accident_vie_privee'
  start_date date NOT NULL,
  end_date date,                        -- NULL si en cours
  expected_end_date date,               -- date de fin prévue (prolongation éventuelle)
  reprise_date date,                    -- date de reprise effective
  reprise_type text,                    -- 'plein_temps'|'mi_temps_therapeutique'|'temps_partiel'
  days_count decimal(5,2),              -- nombre de jours d'arrêt (calculé)
  working_days_count decimal(5,2),      -- jours ouvrés d'arrêt
  subrogation boolean DEFAULT false,    -- subrogation employeur
  net_guarantee boolean DEFAULT false,  -- garantie du net
  ijss_net_amount decimal(15,2) DEFAULT 0,  -- montant IJSS net perçu
  ijss_brut_amount decimal(15,2) DEFAULT 0, -- montant IJSS brut calculé
  ijss_daily_rate decimal(15,2) DEFAULT 0,  -- taux journalier IJSS
  ijss_days_count int DEFAULT 0,             -- nombre de jours IJSS
  ijss_care_days int DEFAULT 0,              -- jours de carence (3 jours maladie)
  pas_days_count int DEFAULT 0,              -- jours soumis au PAS (limite 60j maladie)
  employer_maintenance_amount decimal(15,2) DEFAULT 0, -- montant maintenu par employeur
  employer_maintenance_rate decimal(5,2) DEFAULT 100,  -- % de maintien (selon convention)
  bpij_number text,                     -- n° bordereau BPIJ
  bpij_imported_at timestamptz,
  regularization_amount decimal(15,2) DEFAULT 0, -- régularisation écart estimé/réel
  regularization_type text,             -- 'positive'|'negative'
  medical_certificate_url text,         -- certificat médical uploadé
  notes text,
  status text DEFAULT 'active' CHECK (status IN ('active', 'closed', 'regularized')),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_work_stoppages_employee ON work_stoppages(employee_id);
CREATE INDEX IF NOT EXISTS idx_work_stoppages_dates ON work_stoppages(start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_work_stoppages_type ON work_stoppages(stoppage_type);
ALTER TABLE work_stoppages ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_work_stoppages') THEN
    CREATE POLICY "allow_all_work_stoppages" ON work_stoppages FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `ijss_history` (Historique des IJSS par arrêt)
```sql
CREATE TABLE IF NOT EXISTS ijss_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  work_stoppage_id uuid NOT NULL REFERENCES work_stoppages(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  period text NOT NULL,                 -- '2024-01'
  ijss_net_received decimal(15,2) DEFAULT 0,
  ijss_brut_calculated decimal(15,2) DEFAULT 0,
  days_paid int DEFAULT 0,
  pas_amount decimal(15,2) DEFAULT 0,   -- prélèvement à la source sur IJ
  pas_rate decimal(5,2) DEFAULT 0,
  integrated_in_payslip boolean DEFAULT false,
  payslip_id uuid,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ijss_history_stoppage ON ijss_history(work_stoppage_id);
CREATE INDEX IF NOT EXISTS idx_ijss_history_employee ON ijss_history(employee_id);
ALTER TABLE ijss_history ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_ijss_history') THEN
    CREATE POLICY "allow_all_ijss_history" ON ijss_history FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `work_hardship_records` (Pénibilité — C3P)
```sql
CREATE TABLE IF NOT EXISTS work_hardship_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  exposure_type text NOT NULL,          -- 'noise'|'posture'|'chemicals'|'handling'|'vibrations'|'temperature'|'night_work'|'shift_work'|'other'
  exposure_level text NOT NULL,         -- 'low'|'medium'|'high'
  exposure_start date,
  exposure_end date,
  duration_months int,                  -- durée d'exposition en mois
  points decimal(5,2) DEFAULT 0,        -- points C3P
  declaration_status text DEFAULT 'pending' CHECK (declaration_status IN ('pending', 'declared', 'rejected')),
  declared_at timestamptz,
  notes text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_hardship_employee ON work_hardship_records(employee_id);
CREATE INDEX IF NOT EXISTS idx_hardship_type ON work_hardship_records(exposure_type);
ALTER TABLE work_hardship_records ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_work_hardship_records') THEN
    CREATE POLICY "allow_all_work_hardship_records" ON work_hardship_records FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `cpf_accounts` (Compte Personnel de Formation)
```sql
CREATE TABLE IF NOT EXISTS cpf_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  balance_hours decimal(8,2) DEFAULT 0,
  balance_amount decimal(15,2) DEFAULT 0,
  last_sync_date timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(employee_id)
);
ALTER TABLE cpf_accounts ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_cpf_accounts') THEN
    CREATE POLICY "allow_all_cpf_accounts" ON cpf_accounts FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `cpf_transactions` (Historique des utilisations CPF)
```sql
CREATE TABLE IF NOT EXISTS cpf_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  transaction_type text NOT NULL,       -- 'acquisition'|'usage'|'adjustment'|'expiry'
  hours decimal(8,2) DEFAULT 0,
  amount decimal(15,2) DEFAULT 0,
  training_label text,                  -- libellé de la formation
  training_start_date date,
  training_end_date date,
  training_provider text,
  notes text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_cpf_transactions_employee ON cpf_transactions(employee_id);
ALTER TABLE cpf_transactions ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_cpf_transactions') THEN
    CREATE POLICY "allow_all_cpf_transactions" ON cpf_transactions FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `career_history` (Suivi des carrières)
```sql
CREATE TABLE IF NOT EXISTS career_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  event_type text NOT NULL,             -- 'hire'|'promotion'|'transfer'|'salary_change'|'departure'|'title_change'
  event_date date NOT NULL,
  previous_position text,
  new_position text,
  previous_department text,
  new_department text,
  previous_salary decimal(15,2),
  new_salary decimal(15,2),
  previous_manager_id uuid,
  new_manager_id uuid,
  previous_collective_agreement_id uuid,
  new_collective_agreement_id uuid,
  reason text,
  documents jsonb DEFAULT '[]',         -- documents liés (contrat, avenant, etc.)
  notes text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_career_history_employee ON career_history(employee_id);
CREATE INDEX IF NOT EXISTS idx_career_history_date ON career_history(event_date);
ALTER TABLE career_history ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_career_history') THEN
    CREATE POLICY "allow_all_career_history" ON career_history FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `medical_exams` (Suivi médecine du travail)
```sql
CREATE TABLE IF NOT EXISTS medical_exams (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  exam_type text NOT NULL,              -- 'initial'|'periodic'|'reprise'|'post_hazard'|'pre_employment'
  scheduled_date date NOT NULL,
  completed_date date,
  result text,                          -- 'apt'|'apt_with_restrictions'|'unapt'|'pending'
  restrictions text,
  next_exam_date date,
  occupational_doctor text,
  notes text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_medical_exams_employee ON medical_exams(employee_id);
CREATE INDEX IF NOT EXISTS idx_medical_exams_date ON medical_exams(scheduled_date);
ALTER TABLE medical_exams ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_medical_exams') THEN
    CREATE POLICY "allow_all_medical_exams" ON medical_exams FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `expense_categories` (Catégories de dépenses pour notes de frais)
```sql
CREATE TABLE IF NOT EXISTS expense_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  code text NOT NULL,
  label text NOT NULL,
  account_code text,                    -- compte de charge comptable
  vat_rate decimal(5,2) DEFAULT 20,
  max_amount decimal(15,2),             -- plafond par ligne
  max_monthly decimal(15,2),            -- plafond mensuel
  requires_receipt boolean DEFAULT true,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE expense_categories ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_expense_categories') THEN
    CREATE POLICY "allow_all_expense_categories" ON expense_categories FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `expense_report_lines` (Lignes de notes de frais)
```sql
CREATE TABLE IF NOT EXISTS expense_report_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  expense_report_id uuid NOT NULL REFERENCES expense_reports(id) ON DELETE CASCADE,
  category_id uuid REFERENCES expense_categories(id) ON DELETE SET NULL,
  date date NOT NULL,
  description text NOT NULL,
  amount_ht decimal(15,2) DEFAULT 0,
  vat_rate decimal(5,2) DEFAULT 0,
  vat_amount decimal(15,2) DEFAULT 0,
  amount_ttc decimal(15,2) DEFAULT 0,
  receipt_url text,
  ocr_data jsonb,                       -- données extraites par OCR
  ocr_processed boolean DEFAULT false,
  ceiling_exceeded boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_expense_lines_report ON expense_report_lines(expense_report_id);
ALTER TABLE expense_report_lines ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_expense_report_lines') THEN
    CREATE POLICY "allow_all_expense_report_lines" ON expense_report_lines FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `interview_campaigns` (Campagnes d'entretiens)
```sql
CREATE TABLE IF NOT EXISTS interview_campaigns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  campaign_type text NOT NULL,          -- 'annual'|'mid_year'|'professional'|'exit'|'other'
  start_date date NOT NULL,
  end_date date,
  reminder_days int DEFAULT 7,          -- relance X jours avant la fin
  status text DEFAULT 'draft' CHECK (status IN ('draft', 'active', 'closed')),
  form_template jsonb,                  -- template de formulaire
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_interview_campaigns_status ON interview_campaigns(status);
ALTER TABLE interview_campaigns ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_interview_campaigns') THEN
    CREATE POLICY "allow_all_interview_campaigns" ON interview_campaigns FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `employee_objectives` (Objectifs individuels)
```sql
CREATE TABLE IF NOT EXISTS employee_objectives (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  campaign_id uuid REFERENCES interview_campaigns(id) ON DELETE SET NULL,
  title text NOT NULL,
  description text,
  target_value decimal(15,2),
  current_value decimal(15,2) DEFAULT 0,
  unit text,                            -- 'percent'|'count'|'currency'|'days'
  period text,                          -- '2024' ou '2024-Q1'
  frequency text DEFAULT 'annual',      -- 'annual'|'quarterly'|'monthly'
  status text DEFAULT 'active' CHECK (status IN ('active', 'achieved', 'missed', 'cancelled')),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_objectives_employee ON employee_objectives(employee_id);
CREATE INDEX IF NOT EXISTS idx_objectives_campaign ON employee_objectives(campaign_id);
ALTER TABLE employee_objectives ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_employee_objectives') THEN
    CREATE POLICY "allow_all_employee_objectives" ON employee_objectives FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

---

## D.3 Types TypeScript

```typescript
export interface WorkStoppage {
  id: string
  tenant_id: string | null
  employee_id: string
  stoppage_type: 'maladie' | 'accident_travail' | 'maladie_professionnelle' | 'maternite' | 'paternite' | 'accident_vie_privee'
  start_date: string
  end_date: string | null
  expected_end_date: string | null
  reprise_date: string | null
  reprise_type: 'plein_temps' | 'mi_temps_therapeutique' | 'temps_partiel' | null
  days_count: number | null
  working_days_count: number | null
  subrogation: boolean
  net_guarantee: boolean
  ijss_net_amount: number
  ijss_brut_amount: number
  ijss_daily_rate: number
  ijss_days_count: number
  ijss_care_days: number
  pas_days_count: number
  employer_maintenance_amount: number
  employer_maintenance_rate: number
  bpij_number: string | null
  bpij_imported_at: string | null
  regularization_amount: number
  regularization_type: 'positive' | 'negative' | null
  medical_certificate_url: string | null
  notes: string | null
  status: 'active' | 'closed' | 'regularized'
  created_at: string
  updated_at: string
}

export interface IjssHistory {
  id: string
  tenant_id: string | null
  work_stoppage_id: string
  employee_id: string
  period: string
  ijss_net_received: number
  ijss_brut_calculated: number
  days_paid: number
  pas_amount: number
  pas_rate: number
  integrated_in_payslip: boolean
  payslip_id: string | null
  created_at: string
}

export interface WorkHardshipRecord {
  id: string
  tenant_id: string | null
  employee_id: string
  exposure_type: string
  exposure_level: 'low' | 'medium' | 'high'
  exposure_start: string | null
  exposure_end: string | null
  duration_months: number | null
  points: number
  declaration_status: 'pending' | 'declared' | 'rejected'
  declared_at: string | null
  notes: string | null
  created_at: string
}

export interface CpfAccount {
  id: string
  tenant_id: string | null
  employee_id: string
  balance_hours: number
  balance_amount: number
  last_sync_date: string | null
  created_at: string
  updated_at: string
}

export interface CpfTransaction {
  id: string
  tenant_id: string | null
  employee_id: string
  transaction_type: 'acquisition' | 'usage' | 'adjustment' | 'expiry'
  hours: number
  amount: number
  training_label: string | null
  training_start_date: string | null
  training_end_date: string | null
  training_provider: string | null
  notes: string | null
  created_at: string
}

export interface CareerHistory {
  id: string
  tenant_id: string | null
  employee_id: string
  event_type: 'hire' | 'promotion' | 'transfer' | 'salary_change' | 'departure' | 'title_change'
  event_date: string
  previous_position: string | null
  new_position: string | null
  previous_department: string | null
  new_department: string | null
  previous_salary: number | null
  new_salary: number | null
  previous_manager_id: string | null
  new_manager_id: string | null
  previous_collective_agreement_id: string | null
  new_collective_agreement_id: string | null
  reason: string | null
  documents: any[]
  notes: string | null
  created_at: string
}

export interface MedicalExam {
  id: string
  tenant_id: string | null
  employee_id: string
  exam_type: 'initial' | 'periodic' | 'reprise' | 'post_hazard' | 'pre_employment'
  scheduled_date: string
  completed_date: string | null
  result: 'apt' | 'apt_with_restrictions' | 'unapt' | 'pending' | null
  restrictions: string | null
  next_exam_date: string | null
  occupational_doctor: string | null
  notes: string | null
  created_at: string
}

export interface ExpenseCategory {
  id: string
  tenant_id: string | null
  code: string
  label: string
  account_code: string | null
  vat_rate: number
  max_amount: number | null
  max_monthly: number | null
  requires_receipt: boolean
  active: boolean
  created_at: string
}

export interface ExpenseReportLine {
  id: string
  tenant_id: string | null
  expense_report_id: string
  category_id: string | null
  date: string
  description: string
  amount_ht: number
  vat_rate: number
  vat_amount: number
  amount_ttc: number
  receipt_url: string | null
  ocr_data: any
  ocr_processed: boolean
  ceiling_exceeded: boolean
  created_at: string
}

export interface InterviewCampaign {
  id: string
  tenant_id: string | null
  name: string
  campaign_type: 'annual' | 'mid_year' | 'professional' | 'exit' | 'other'
  start_date: string
  end_date: string | null
  reminder_days: number
  status: 'draft' | 'active' | 'closed'
  form_template: any
  created_at: string
}

export interface EmployeeObjective {
  id: string
  tenant_id: string | null
  employee_id: string
  campaign_id: string | null
  title: string
  description: string | null
  target_value: number | null
  current_value: number
  unit: 'percent' | 'count' | 'currency' | 'days' | null
  period: string | null
  frequency: 'annual' | 'quarterly' | 'monthly'
  status: 'active' | 'achieved' | 'missed' | 'cancelled'
  created_at: string
  updated_at: string
}
```

---

## D.4 Queries

```typescript
// ============ Work Stoppages (Arrêts de travail) ============
export async function getWorkStoppages(employeeId?: string, status?: string)
export async function createWorkStoppage(data: Omit<WorkStoppage, 'id' | 'created_at' | 'updated_at'>)
export async function updateWorkStoppage(id: string, updates: Partial<WorkStoppage>)
export async function closeWorkStoppage(id: string, repriseDate: string, repriseType: string)
export async function calculateIjssBrut(ijssNet: number): number
// Logique : IJSS Brutes = IJSS Nettes / (1 - 0.067)  [CSG 6.2% + CRDS 0.5%]
export async function calculateIjssEstimate(employeeId: string, startDate: string, endDate: string, stoppageType: string)
// Estimation des IJSS basée sur le salaire de référence
export async function importBpij(workStoppageId: string, bpijNumber: string, ijssNetReceived: number)
// Import du bordereau BPIJ + rapprochement avec les indemnités déjà versées
export async function regularizeIjss(workStoppageId: string, actualAmount: number)
// Régularisation de l'écart entre IJSS estimées et réelles

// ============ Subrogation & Garantie du net ============
export async function calculateNetGuarantee(employeeId: string, workStoppageId: string)
// Calcule le maintien du net sous déduction des IJSS
export async function calculatePasOnIjss(workStoppageId: string, period: string)
// Calcul du prélèvement à la source sur IJ subrogées (limite 60j maladie)

// ============ IJSS History ============
export async function getIjssHistory(workStoppageId: string)
export async function getIjssHistoryByEmployee(employeeId: string)
export async function integrateIjssInPayslip(ijssHistoryId: string, payslipId: string)

// ============ Work Hardship (Pénibilité) ============
export async function getWorkHardshipRecords(employeeId?: string)
export async function createWorkHardshipRecord(data: Omit<WorkHardshipRecord, 'id' | 'created_at'>)
export async function updateWorkHardshipRecord(id: string, updates: Partial<WorkHardshipRecord>)
export async function calculateC3pPoints(employeeId: string)
// Calcule les points C3P pour un employé (somme des expositions)
export async function declareWorkHardship(employeeId: string)
// Marque les records comme déclarés

// ============ CPF ============
export async function getCpfAccount(employeeId: string)
export async function updateCpfBalance(employeeId: string, hours: number, amount: number)
export async function getCpfTransactions(employeeId: string)
export async function createCpfTransaction(data: Omit<CpfTransaction, 'id' | 'created_at'>)
export async function syncCpfFromApi(employeeId: string)
// Synchronisation depuis moncompteformation.gouv.fr (si API disponible)
export async function getCpfAlerts()
// Alertes : CPF expirant, solde important non utilisé

// ============ Career History ============
export async function getCareerHistory(employeeId: string)
export async function createCareerEvent(data: Omit<CareerHistory, 'id' | 'created_at'>)
export async function updateCareerEvent(id: string, updates: Partial<CareerHistory>)
export async function deleteCareerEvent(id: string)

// ============ Medical Exams ============
export async function getMedicalExams(employeeId?: string)
export async function createMedicalExam(data: Omit<MedicalExam, 'id' | 'created_at'>)
export async function updateMedicalExam(id: string, updates: Partial<MedicalExam>)
export async function getUpcomingMedicalExams(months?: number)
// Examens à venir dans les X prochains mois
export async function getMedicalExamAlerts()
// Alertes : examen en retard, examen à planifier

// ============ Expense Categories ============
export async function getExpenseCategories(activeOnly?: boolean)
export async function createExpenseCategory(data: Omit<ExpenseCategory, 'id' | 'created_at'>)
export async function updateExpenseCategory(id: string, updates: Partial<ExpenseCategory>)

// ============ Expense Report Lines ============
export async function getExpenseReportLines(reportId: string)
export async function addExpenseReportLine(reportId: string, line: Omit<ExpenseReportLine, 'id' | 'created_at'>)
export async function updateExpenseReportLine(id: string, updates: Partial<ExpenseReportLine>)
export async function deleteExpenseReportLine(id: string)
export async function uploadReceipt(file: File, lineId: string)
// Upload vers Supabase Storage
export async function extractReceiptData(file: File)
// OCR côté client (Tesseract.js) → { date, amount, vatRate, vendor, category? }
export async function checkExpenseCeiling(lineId: string)
// Vérifie si le montant dépasse le plafond de la catégorie

// ============ Expense Reports (self-service) ============
export async function getMyExpenseReports()
export async function createMyExpenseReport(data: any)
export async function updateMyExpenseReport(id: string, updates: any)
export async function submitMyExpenseReport(id: string)  // draft → submitted
export async function deleteMyExpenseReport(id: string)  // seulement si draft
export async function getPendingExpenseReports(managerId?: string)
export async function approveExpenseReport(id: string, managerId: string, comment: string)
export async function rejectExpenseReport(id: string, managerId: string, comment: string)
export async function markExpenseReimbursed(id: string, reimbursementDate: string)
export async function generateExpenseAccountingEntries(reportId: string)
// Génère les écritures comptables (compte de charge, TVA, tiers)

// ============ Interview Campaigns ============
export async function getInterviewCampaigns(status?: string)
export async function createInterviewCampaign(data: Omit<InterviewCampaign, 'id' | 'created_at'>)
export async function launchCampaign(id: string)
// draft → active, crée les entretiens pour chaque employé actif
export async function closeCampaign(id: string)
export async function sendCampaignReminders(campaignId: string)

// ============ Objectives ============
export async function getMyObjectives()
export async function getObjectivesByEmployee(employeeId: string)
export async function getObjectivesByCampaign(campaignId: string)
export async function createObjective(data: Omit<EmployeeObjective, 'id' | 'created_at' | 'updated_at'>)
export async function updateObjectiveProgress(id: string, currentValue: number)

// ============ Interviews (self-service) ============
export async function getMyInterviews()
export async function getMyUpcomingInterview()
export async function submitInterviewFeedback(id: string, feedback: string, rating: number)
export async function getInterviewFormTemplate(type: string)
export async function saveInterviewFormData(interviewId: string, formData: any)
```

---

## D.5 Pages

### `WorkStoppagesPage.tsx` (nouveau — admin/RH)
**Fichier** : `@/pages/hr/WorkStoppagesPage.tsx`

**Structure :**
- **Onglet 1 : "Arrêts en cours"**
  - Table : Employé, Type, Date début, Date fin prévue, Jours, Subrogation, Garantie net, IJSS net, Maintien employeur, Statut, Actions
  - Bouton "Nouvel arrêt" : modal avec formulaire
    - Employé (select)
    - Type d'arrêt (select : maladie, AT, MP, maternité, paternité, accident vie privée)
    - Date de début / fin prévue
    - Subrogation (checkbox)
    - Garantie du net (checkbox)
    - Upload certificat médical
    - Notes
  - Calcul automatique : jours d'arrêt, jours ouvrés, IJSS estimées
  - Bouton "Détail" : vue complète avec historique IJSS
  - Bouton "Clôturer" : modal (date de reprise, type de reprise)
- **Onglet 2 : "IJSS & Subrogation"**
  - Table : Employé, Arrêt, Période, IJSS nettes reçues, IJSS brutes calculées, Jours, PAS, Intégré bulletin
  - Bouton "Importer BPIJ" : modal (n° bordereau, montant, arrêt concerné)
  - Bouton "Régulariser" : si écart entre estimé et réel
  - Bouton "Intégrer au bulletin" : lie l'IJSS à un pay_slip
- **Onglet 3 : "Historique"**
  - Table de tous les arrêts clôturés
  - Filtres : employé, type, période
- `useTranslation('hr')`

### `HardshipPage.tsx` (nouveau — admin/RH)
**Fichier** : `@/pages/hr/HardshipPage.tsx`

**Structure :**
- **Table principale** : Employé, Type d'exposition, Niveau, Début, Fin, Durée (mois), Points C3P, Statut déclaration, Actions
- **Cartes de suivi par type** : bruit, posture, produits chimiques, manutention, vibrations, températures extrêmes, travail de nuit, travail en équipes
- **Bouton "Nouvelle exposition"** : modal (employé, type, niveau, dates)
- **Bouton "Calculer points C3P"** : calcule les points pour un employé
- **Bouton "Déclarer"** : marque les records comme déclarés
- **Vue par employé** : historique des expositions + total points
- **Export** pour déclaration C3P
- `useTranslation('hr')`

### `CPFPage.tsx` (nouveau — admin/RH)
**Fichier** : `@/pages/hr/CPFPage.tsx`

**Structure :**
- **Table des employés** : Employé, Solde CPF (heures), Montant (€), Dernière synchro, Actions
- **Bouton "Synchroniser"** : import depuis moncompteformation.gouv.fr
- **Onglet "Historique"** : Employé, Type (acquisition/usage/adjustment/expiry), Heures, Montant, Formation, Dates, Fournisseur
- **Bouton "Nouvelle transaction"** : modal (employé, type, heures, montant, formation, dates)
- **Section "Alertes"** :
  - CPF expirant (heures qui expirent dans les 6 mois)
  - Solde important non utilisé (> 100h)
- `useTranslation('hr')`

### `CareerHistoryPage.tsx` (nouveau — admin/RH)
**Fichier** : `@/pages/hr/CareerHistoryPage.tsx`

**Structure :**
- **Table principale** : Employé, Date, Événement, Ancien poste, Nouveau poste, Ancien salaire, Nouveau salaire, Motif, Actions
- **Bouton "Nouvel événement"** : modal (employé, type, date, anciennes/nouvelles valeurs)
- **Vue timeline par employé** : chronologie visuelle des événements de carrière
- **Filtres** : employé, type d'événement, période
- **CRUD complet**
- `useTranslation('hr')`

### `MedicalExamsPage.tsx` (nouveau — admin/RH)
**Fichier** : `@/pages/hr/MedicalExamsPage.tsx`

**Structure :**
- **Table** : Employé, Type d'examen, Date prévue, Date réalisée, Résultat, Restrictions, Prochain examen, Médecin, Actions
- **Bouton "Planifier"** : modal (employé, type, date, médecin)
- **Bouton "Résultat"** : modal (apt / apt avec restrictions / inapt, restrictions, prochain examen)
- **Section "Alertes"** :
  - Examens en retard (date prévue dépassée)
  - Examens à planifier (visite périodique annuelle)
  - Visites de reprise à planifier (après arrêt > 30 jours)
- **Filtres** : employé, type, période, résultat
- `useTranslation('hr')`

### `ExpenseCategoriesPage.tsx` (nouveau — admin/RH)
**Fichier** : `@/pages/settings/ExpenseCategoriesPage.tsx`

**Structure :**
- **Table** : Code, Libellé, Compte comptable, Taux TVA, Plafond/ligne, Plafond mensuel, Justificatif requis, Actif
- **CRUD complet**
- **Catégories pré-définies** : transport, repas, hébergement, fournitures, télécom, divers
- `useTranslation('hr')`

---

# SPRINT E : Sortie du Salarié, Notes de Frais & Entretiens (2-3j)

## E.1 Vue d'ensemble

```
Assistant de sortie (6 étapes)
├── 1. Sélection employé
├── 2. Date & motif de sortie
├── 3. Calcul solde de tout compte
│   ├── Indemnité compensatrice CP
│   ├── Indemnité compensatrice RTT
│   ├── Primes sur la période
│   ├── Acomptes à déduire
│   ├── Heures sup non payées
│   └── Total brut / net
├── 4. Documents de sortie
│   ├── Certificat de travail
│   ├── Reçu pour solde de tout compte
│   ├── Attestation Pôle Emploi (France Travail)
│   └── DSN fin de contrat
├── 5. Déclarations
│   └── DSN fin de contrat + DPAE de fin
└── 6. Validation
    ├── Statut employé → inactive
    ├── Génération bulletin de sortie
    └── Archivage documents

Notes de frais (self-service)
├── Employé : création + lignes + OCR + soumission
├── Manager : validation / rejet
└── RH : remboursement + comptabilisation

Entretiens & Objectifs
├── Campagnes (création, lancement, clôture, relances)
├── Entretiens (formulaire, feedback employé + manager, rating)
└── Objectifs (création, suivi progression, statut)
```

### Fonctionnalités Sage 100 couvertées
- **Assistant de sortie du salarié**
- **Documents liés au solde de tout compte**
- **DSN fin de contrat** (événementielle)
- **Attestation Pôle Emploi** (France Travail)
- **Certificat de travail**
- **Notes de frais** : scan des justificatifs, extraction automatique, validation, comptabilisation
- **Entretiens individuels** : formulaires personnalisables, campagnes, suivi des objectifs
- **Gestion des honoraires** (extension)

---

## E.2 SQL — Nouvelles tables

### `employee_exit_processes` (Suivi des sorties)
```sql
CREATE TABLE IF NOT EXISTS employee_exit_processes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  exit_date date NOT NULL,
  exit_reason text NOT NULL,           -- 'resignation'|'dismissal'|'end_cdd'|'retirement'|'mutual_agreement'|'probation_fail'
  step int DEFAULT 1,                  -- étape actuelle (1-6)
  status text DEFAULT 'in_progress' CHECK (status IN ('in_progress', 'completed', 'cancelled')),
  
  -- Solde de tout compte
  cp_indemnity decimal(15,2) DEFAULT 0,
  rtt_indemnity decimal(15,2) DEFAULT 0,
  recovery_indemnity decimal(15,2) DEFAULT 0,
  bonus_amount decimal(15,2) DEFAULT 0,
  advance_deduction decimal(15,2) DEFAULT 0,
  overtime_amount decimal(15,2) DEFAULT 0,
  total_gross decimal(15,2) DEFAULT 0,
  total_net decimal(15,2) DEFAULT 0,
  
  -- Documents
  work_certificate_url text,
  settlement_receipt_url text,
  pole_emploi_attestation_url text,
  dsn_exit_url text,
  documents_generated boolean DEFAULT false,
  
  -- DSN
  dsn_exit_generated boolean DEFAULT false,
  dsn_exit_transmitted boolean DEFAULT false,
  
  -- Bulletin de sortie
  exit_payslip_id uuid,
  
  notes text,
  created_at timestamptz DEFAULT now(),
  completed_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_exit_processes_employee ON employee_exit_processes(employee_id);
CREATE INDEX IF NOT EXISTS idx_exit_processes_status ON employee_exit_processes(status);
ALTER TABLE employee_exit_processes ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_employee_exit_processes') THEN
    CREATE POLICY "allow_all_employee_exit_processes" ON employee_exit_processes FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

---

## E.3 Types TypeScript

```typescript
export interface EmployeeExitProcess {
  id: string
  tenant_id: string | null
  employee_id: string
  exit_date: string
  exit_reason: 'resignation' | 'dismissal' | 'end_cdd' | 'retirement' | 'mutual_agreement' | 'probation_fail'
  step: number
  status: 'in_progress' | 'completed' | 'cancelled'
  cp_indemnity: number
  rtt_indemnity: number
  recovery_indemnity: number
  bonus_amount: number
  advance_deduction: number
  overtime_amount: number
  total_gross: number
  total_net: number
  work_certificate_url: string | null
  settlement_receipt_url: string | null
  pole_emploi_attestation_url: string | null
  dsn_exit_url: string | null
  documents_generated: boolean
  dsn_exit_generated: boolean
  dsn_exit_transmitted: boolean
  exit_payslip_id: string | null
  notes: string | null
  created_at: string
  completed_at: string | null
}
```

---

## E.4 Queries

```typescript
// ============ Employee Exit ============
export async function createExitProcess(employeeId: string, exitDate: string, exitReason: string)
export async function getExitProcess(id: string)
export async function getExitProcesses(status?: string)
export async function calculateFinalSettlement(exitProcessId: string)
// Calcule le solde de tout compte :
// - indemnité compensatrice CP = remaining_days × daily_rate
// - indemnité compensatrice RTT = remaining_days × daily_rate
// - primes sur la période (prorata)
// - acomptes à déduire
// - heures sup non payées
export async function generateExitDocuments(exitProcessId: string)
// Génère : certificat de travail, reçu pour solde de tout compte, attestation Pôle Emploi
export async function generateDsnExit(exitProcessId: string)
// Génère la DSN fin de contrat
export async function transmitDsnExit(exitProcessId: string)
export async function generateExitPayslip(exitProcessId: string)
// Génère le bulletin de sortie (slip_type = 'exit')
export async function completeExitProcess(exitProcessId: string)
// Met à jour employee.status = 'inactive', employee.exit_date
// Archive les documents dans le coffre-fort

// ============ Expense Reports (self-service) ============
// (Voir D.4 — queries déjà définies)

// ============ Interview Campaigns ============
// (Voir D.4 — queries déjà définies)
```

---

## E.5 Pages

### `EmployeeExitPage.tsx` (nouveau — assistant 6 étapes)
**Fichier** : `@/pages/hr/EmployeeExitPage.tsx`

**Structure :**
- **Stepper visuel** (6 étapes)
- **Étape 1 : Sélection de l'employé**
  - Select avec recherche
  - Affichage : nom, poste, département, date d'embauche, type de contrat, manager
- **Étape 2 : Date et motif de sortie**
  - Date de sortie (date picker)
  - Motif (select : démission, licenciement, fin de CDD, retraite, rupture conventionnelle, fin période d'essai)
  - Notes
- **Étape 3 : Calcul du solde de tout compte**
  - Table récapitulative :
    - Indemnité compensatrice de congés payés (CP restants × TJ)
    - Indemnité compensatrice de RTT (RTT restants × TJ)
    - Indemnité compensatrice de récupération
    - Primes sur la période (prorata)
    - Acomptes à déduire
    - Heures sup non payées
  - Total brut / Total net
  - Bouton "Recalculer"
- **Étape 4 : Documents de sortie**
  - Bouton "Générer certificat de travail" → PDF
  - Bouton "Générer reçu pour solde de tout compte" → PDF
  - Bouton "Générer attestation Pôle Emploi" → PDF
  - Téléchargement individuel ou en lot
- **Étape 5 : Déclarations**
  - Bouton "Générer DSN fin de contrat"
  - Bouton "Transmettre DSN"
  - Statut de la transmission
- **Étape 6 : Validation**
  - Récapitulatif complet
  - Bouton "Valider la sortie" :
    - Met à jour statut employé → 'inactive'
    - Génère le bulletin de sortie
    - Archive les documents dans le coffre-fort
    - Marque le processus comme terminé
- `useTranslation('hr')`

### `EmployeeExpensesPage.tsx` (nouveau — self-service employé)
**Fichier** : `@/pages/employee/EmployeeExpensesPage.tsx`

**Structure :**
- **Table "Mes notes de frais"** : Numéro, Période, Montant total, TVA, Statut, Actions
- **Bouton "Nouvelle note de frais"** : modal (période, notes)
- **Détail de la note de frais** (page ou modal large) :
  - Table des lignes : Date, Description, Catégorie, Montant HT, TVA, TTC, Justificatif, Actions
  - Bouton "Ajouter une ligne"
  - **Upload justificatif** : drag & drop ou photo (sur mobile)
  - **OCR automatique** : extraction date, montant, TVA depuis le justificatif
  - **Alerte plafond** : si montant > plafond catégorie, afficher warning
  - Bouton "Soumettre" (draft → submitted)
  - Bouton "Supprimer" (si draft)
- **Filtres** : statut, période, catégorie
- `useTranslation('employee')`

### `ManagerExpenseApprovalsPage.tsx` (nouveau — manager)
**Fichier** : `@/pages/employee/ManagerExpenseApprovalsPage.tsx`

**Structure :**
- Liste des notes de frais en attente de validation
- Pour chaque note : employé, période, montant total, nombre de justificatifs
- Bouton "Voir détail" → affiche toutes les lignes + justificatifs
- Boutons "Approuver" / "Rejeter" avec commentaire
- Filtres : employé, période
- `useTranslation('employee')`

### `EmployeeInterviewsPage.tsx` (nouveau — self-service employé)
**Fichier** : `@/pages/employee/EmployeeInterviewsPage.tsx`

**Structure :**
- **Onglet 1 : "Mes entretiens"**
  - Table : Type, Date prévue, Date réalisée, Statut, Évaluation, Actions
  - Bouton "Voir détail" → affiche le formulaire d'entretien
  - Section "Mon feedback" : l'employé saisit son feedback et son rating
  - Section "Feedback manager" : visible après réalisation
- **Onglet 2 : "Mes objectifs"**
  - Table : Titre, Description, Cible, Progression, Période, Fréquence, Statut
  - Barre de progression visuelle pour chaque objectif
  - Bouton "Mettre à jour la progression" (modal avec slider ou input)
  - Filtres : statut, période
- `useTranslation('employee')`

### `InterviewCampaignsPage.tsx` (nouveau — admin/manager)
**Fichier** : `@/pages/hr/InterviewCampaignsPage.tsx`

**Structure :**
- Table des campagnes : Nom, Type, Période, Statut, Avancement (% complétés)
- Bouton "Nouvelle campagne" : modal (nom, type, dates, relance, template formulaire)
- Bouton "Lancer" (crée les entretiens pour tous les employés actifs)
- Bouton "Relancer" (envoie notifications)
- Bouton "Clôturer"
- Vue détaillée : liste des entretiens de la campagne avec statut
- `useTranslation('hr')`

### Extension `ExpenseReportsPage.tsx` (modifier)
- Ajouter colonnes : manager, commentaire manager, date remboursement
- Ajouter action "Marquer remboursé"
- Ajouter action "Générer écritures comptables"
- Ajouter filtre par employé
- Ajouter vue détaillée avec lignes + justificatifs

### Extension `InterviewsPage.tsx` (modifier)
- Ajouter colonnes : manager, feedback employé, rating employé, campagne
- Ajouter vue détaillée avec form_data (réponses structurées)
- Ajouter action "Planifier" pour les managers

### Extension `EmployeesPage.tsx` (modifier — Sprint E)
- Ajouter bouton "Assistant de sortie" sur les employés actifs
- Redirige vers EmployeeExitPage avec l'employé pré-sélectionné

---

## E.6 i18n — Clés à ajouter

### Namespace `hr` — nouvelles sections

| Section | Clés principales |
|---|---|
| `workStoppages.*` | title, new, employee, stoppageType, startDate, endDate, expectedEnd, repriseDate, repriseType, daysCount, workingDays, subrogation, netGuarantee, ijssNet, ijssBrut, ijssDailyRate, ijssDays, careDays, pasDays, employerMaintenance, maintenanceRate, bpijNumber, importBpij, regularize, regularizationAmount, regularizationType, medicalCertificate, uploadCertificate, types (maladie/accident_travail/maladie_professionnelle/maternite/paternite/accident_vie_privee), statuses (active/closed/regularized), repriseTypes (plein_temps/mi_temps_therapeutique/temps_partiel) |
| `ijss.*` | title, history, period, netReceived, brutCalculated, daysPaid, pasAmount, pasRate, integratedInPayslip, integrate, calculateIjssBrut, formula |
| `hardship.*` | title, exposureType, exposureLevel, exposureStart, exposureEnd, durationMonths, points, declarationStatus, calculatePoints, declare, types (noise/posture/chemicals/handling/vibrations/temperature/night_work/shift_work/other), levels (low/medium/high), statuses (pending/declared/rejected), exportC3p |
| `cpf.*` | title, balanceHours, balanceAmount, lastSync, sync, history, transactionType, hours, amount, trainingLabel, trainingDates, trainingProvider, newTransaction, alertExpiring, alertUnused, types (acquisition/usage/adjustment/expiry) |
| `career.*` | title, eventType, eventDate, previousPosition, newPosition, previousDepartment, newDepartment, previousSalary, newSalary, previousManager, newManager, reason, timeline, events (hire/promotion/transfer/salary_change/departure/title_change) |
| `medical.*` | title, examType, scheduledDate, completedDate, result, restrictions, nextExam, occupationalDoctor, plan, addResult, alerts, overdue, toPlan, repriseVisit, types (initial/periodic/reprise/post_hazard/pre_employment), results (apt/apt_with_restrictions/unapt/pending) |
| `exit.*` | title, step1, step2, step3, step4, step5, step6, selectEmployee, exitDate, exitReason, finalSettlement, cpIndemnity, rttIndemnity, recoveryIndemnity, bonusAmount, advanceDeduction, overtimeAmount, totalGross, totalNet, documents, workCertificate, settlementReceipt, poleEmploiAttestation, dsnExit, generateDsnExit, transmitDsnExit, generateExitPayslip, validate, complete, reasons (resignation/dismissal/end_cdd/retirement/mutual_agreement/probation_fail) |
| `expenseCategories.*` | title, code, label, accountCode, vatRate, maxAmount, maxMonthly, requiresReceipt, active |
| `expenseLines.*` | date, description, category, amountHt, vatRate, vatAmount, amountTtc, receipt, uploadReceipt, ocrProcessing, ceilingExceeded, addLine |
| `campaigns.*` | title, new, name, campaignType, startDate, endDate, reminderDays, launch, close, remind, progress, formTemplate, types (annual/mid_year/professional/exit/other), statuses (draft/active/closed) |
| `objectives.*` | title, target, progress, period, frequency, updateProgress, status, unit, units (percent/count/currency/days), statuses (active/achieved/missed/cancelled) |
| `interviews.*` (ajouts) | myFeedback, managerFeedback, rating, submitFeedback, formTemplate, formData |

### Namespace `employee` (nouveau — Sprint E)

| Section | Clés principales |
|---|---|
| `expenses.*` | title, newReport, period, totalAmount, totalVat, submit, addLine, date, description, category, amountHt, vatRate, vatAmount, amountTtc, receipt, uploadReceipt, ocrProcessing, ceilingExceeded, status (draft/submitted/approved/rejected/reimbursed), managerApprovals, approve, reject, markReimbursed, generateAccounting |
| `interviews.*` | title, myObjectives, type, scheduledDate, conductedAt, myFeedback, managerFeedback, rating, submitFeedback, objectives (title/target/progress/period/frequency/updateProgress/status), types (annual/mid_year/professional/exit/other), campaigns (title/new/launch/close/remind/progress) |

**3 langues** : fr, en, ar (RTL)

---

## E.7 Routes App.tsx

```tsx
{/* RH Admin — Sprint D */}
<Route path="/hr/work-stoppages" element={<WorkStoppagesPage />} />
<Route path="/hr/hardship" element={<HardshipPage />} />
<Route path="/hr/cpf" element={<CPFPage />} />
<Route path="/hr/career" element={<CareerHistoryPage />} />
<Route path="/hr/medical" element={<MedicalExamsPage />} />

{/* RH Admin — Sprint E */}
<Route path="/hr/employee-exit" element={<EmployeeExitPage />} />
<Route path="/hr/interview-campaigns" element={<InterviewCampaignsPage />} />
<Route path="/settings/expense-categories" element={<ExpenseCategoriesPage />} />

{/* Espace Employés — Sprint E */}
<Route path="/employee/expenses" element={<EmployeeExpensesPage />} />
<Route path="/employee/interviews" element={<EmployeeInterviewsPage />} />
<Route path="/employee/manager/expense-approvals" element={<ManagerExpenseApprovalsPage />} />
```

---

## E.8 Navigation (`nav.json`)

Ajouter dans les 3 langues :
```json
{
  "workStoppages": "Arrêts de travail",
  "hardship": "Pénibilité",
  "cpf": "CPF",
  "career": "Carrières",
  "medical": "Médecine du travail",
  "employeeExit": "Sortie salarié",
  "interviewCampaigns": "Campagnes d'entretiens",
  "expenseCategories": "Catégories de dépenses"
}
```

---

## E.9 Fichiers créés / modifiés

### Nouveaux fichiers (12)
1. `@/pages/hr/WorkStoppagesPage.tsx` — Arrêts de travail + IJSS + subrogation
2. `@/pages/hr/HardshipPage.tsx` — Pénibilité C3P
3. `@/pages/hr/CPFPage.tsx` — Compte Personnel de Formation
4. `@/pages/hr/CareerHistoryPage.tsx` — Suivi des carrières
5. `@/pages/hr/MedicalExamsPage.tsx` — Médecine du travail
6. `@/pages/hr/EmployeeExitPage.tsx` — Assistant de sortie (6 étapes)
7. `@/pages/hr/InterviewCampaignsPage.tsx` — Campagnes d'entretiens
8. `@/pages/settings/ExpenseCategoriesPage.tsx` — Catégories de dépenses
9. `@/pages/employee/EmployeeExpensesPage.tsx` — Notes de frais self-service
10. `@/pages/employee/EmployeeInterviewsPage.tsx` — Entretiens & objectifs
11. `@/pages/employee/ManagerExpenseApprovalsPage.tsx` — Validations notes de frais
12. `@/sql/60_sprint_d_admin_arrets.sql` + `@/sql/61_sprint_e_sortie_notes_entretiens.sql`

### Fichiers modifiés (8)
- `@/types/index.ts` — nouveaux types
- `@/lib/queries.ts` — nouvelles queries
- `@/App.tsx` — nouvelles routes
- `@/pages/EmployeesPage.tsx` — bouton "Assistant de sortie"
- `@/pages/ExpenseReportsPage.tsx` — extensions
- `@/pages/InterviewsPage.tsx` — extensions
- `@/i18n/locales/{fr,en,ar}/hr.json` — clés Sprint D+E
- `@/i18n/locales/{fr,en,ar}/nav.json` — nouvelles clés navigation
