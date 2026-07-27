# PARTIE 2 — Sprints B & C : Congés, Absences, Temps & Paie Avancée (6-7j)

> **Sprint B** (3-4j) : Soldes congés, règles de congés, jours fériés, workflows de validation, planning, provisions de congés payés
> **Sprint C** (3j) : Assistant de préparation paie (5 étapes), éléments variables, titres restaurant, calcul à l'envers, acomptes, rappels, virement SEPA
> **i18n** : `useTranslation` (fr, en, ar)
> **SQL** : `app/sql/58_sprint_b_leaves_absences.sql` + `app/sql/59_sprint_c_payroll_advanced.sql`

---

# SPRINT B : Congés, Absences & Gestion des Temps (3-4j)

## B.1 Vue d'ensemble

```
Règles de congés ──→ Soldes (CP/RTT/Récup/Maladie) ──→ Demandes ──→ Validation manager
       │                    │                           │              │
       │                    ├── Report annuel            │              ├── Approuver
       │                    ├── Provisions CP            │              ├── Rejeter
       │                    └── Solde tout compte        │              └── Commentaire
       │                                                   │
       ├── Jours fériés (régionalisables)                  ├── Demi-journée
       ├── Workflows de validation                         ├── Justificatif (upload)
       ├── Effectif minimum (astreintes)                   └── Conflit détecté
       └── Planning partagé
```

### Fonctionnalités Sage 100 couvertes
- **Gestion des absences, maladies, congés et RTT**
- **Valorisation automatique** à partir des dates saisies
- **Prise en compte des règles de calcul spécifiques** : conditions, barèmes
- **Valorisation en jours ouvrés, ouvrables, calendaires** selon jours fériés, particularités locales
- **Alimentation automatique des variables de paie**
- **Gestion des provisions de congés payés**
- **Planning de congés** partagé en temps réel
- **Circuit de validation** paramétrable
- **Export des données de congés vers la paie**

---

## B.2 SQL — Nouvelles tables

### `leave_balances` (Compteurs par employé et par type)
```sql
CREATE TABLE IF NOT EXISTS leave_balances (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  leave_type text NOT NULL,            -- 'annual'|'rtt'|'recovery'|'sick'|'unpaid'|'maternity'|'paternity'|'special'
  year int NOT NULL DEFAULT extract(year from current_date)::int,
  acquired decimal(5,2) DEFAULT 0,     -- jours acquis
  taken decimal(5,2) DEFAULT 0,        -- jours pris
  pending decimal(5,2) DEFAULT 0,      -- jours en attente de validation
  remaining decimal(5,2) DEFAULT 0,    -- jours restants (acquired + carry_over - taken - pending)
  carry_over decimal(5,2) DEFAULT 0,   -- report de l'année précédente
  provision decimal(15,2) DEFAULT 0,   -- provision financière (CP)
  provision_calculated_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(employee_id, leave_type, year)
);
CREATE INDEX IF NOT EXISTS idx_leave_balances_employee ON leave_balances(employee_id);
CREATE INDEX IF NOT EXISTS idx_leave_balances_year ON leave_balances(year);
ALTER TABLE leave_balances ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_leave_balances') THEN
    CREATE POLICY "allow_all_leave_balances" ON leave_balances FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `public_holidays` (Jours fériés régionalisables)
```sql
CREATE TABLE IF NOT EXISTS public_holidays (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  holiday_date date NOT NULL,
  region text DEFAULT 'national',      -- 'national'|'alsace-moselle'|'guadeloupe'|'martinique'|'guyane'|'reunion'|'mayotte'|'polynesie'|'nouvelle_caledonie'|'saint_pierre'|'wallis'|'custom'
  country text DEFAULT 'FR',
  is_working_day boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_public_holidays_date ON public_holidays(holiday_date);
CREATE INDEX IF NOT EXISTS idx_public_holidays_region ON public_holidays(region);
ALTER TABLE public_holidays ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_public_holidays') THEN
    CREATE POLICY "allow_all_public_holidays" ON public_holidays FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `leave_rules` (Paramétrage des règles de congés)
```sql
CREATE TABLE IF NOT EXISTS leave_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  leave_type text NOT NULL,
  label text NOT NULL,
  accrual_rate decimal(5,2) DEFAULT 2.08,  -- taux mensuel (2.08 = 25j/an)
  max_carry_over decimal(5,2) DEFAULT 0,
  carry_over_expiry_months int DEFAULT 3,  -- expiration du report
  requires_justification boolean DEFAULT false,
  requires_manager_approval boolean DEFAULT true,
  min_notice_days int DEFAULT 7,
  max_consecutive_days int DEFAULT 30,
  color text DEFAULT '#3b82f6',
  count_method text DEFAULT 'working_days', -- 'working_days'|'working_days_excl_saturday'|'calendar_days'
  affects_pay boolean DEFAULT false,
  deduction_rate decimal(5,2) DEFAULT 100,  -- % de déduction si sans solde
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE leave_rules ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_leave_rules') THEN
    CREATE POLICY "allow_all_leave_rules" ON leave_rules FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `approval_workflows` (Workflows de validation)
```sql
CREATE TABLE IF NOT EXISTS approval_workflows (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  entity_type text NOT NULL,          -- 'leave_request'|'expense_report'|'timesheet'
  steps jsonb DEFAULT '[]',           -- [{role: 'manager', order: 1}, {role: 'hr', order: 2}]
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE approval_workflows ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_approval_workflows') THEN
    CREATE POLICY "allow_all_approval_workflows" ON approval_workflows FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `leave_provisions` (Provisions de congés payés)
```sql
CREATE TABLE IF NOT EXISTS leave_provisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  period text NOT NULL,               -- '2024-12'
  cp_remaining_days decimal(5,2) DEFAULT 0,
  rtt_remaining_days decimal(5,2) DEFAULT 0,
  recovery_remaining_days decimal(5,2) DEFAULT 0,
  daily_rate decimal(15,2) DEFAULT 0, -- salaire journalier de référence
  cp_provision decimal(15,2) DEFAULT 0,
  rtt_provision decimal(15,2) DEFAULT 0,
  recovery_provision decimal(15,2) DEFAULT 0,
  total_provision decimal(15,2) DEFAULT 0,
  accounting_entry_id uuid,           -- lien vers écriture comptable de provision
  status text DEFAULT 'draft' CHECK (status IN ('draft', 'calculated', 'posted')),
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_leave_provisions_employee ON leave_provisions(employee_id);
CREATE INDEX IF NOT EXISTS idx_leave_provisions_period ON leave_provisions(period);
ALTER TABLE leave_provisions ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_leave_provisions') THEN
    CREATE POLICY "allow_all_leave_provisions" ON leave_provisions FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `staff_requirements` (Astreintes / effectif minimum)
```sql
CREATE TABLE IF NOT EXISTS staff_requirements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  department text NOT NULL,
  min_staff int NOT NULL DEFAULT 1,
  days_of_week text[] DEFAULT '{1,2,3,4,5}', -- jours concernés
  start_date date,
  end_date date,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE staff_requirements ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_staff_requirements') THEN
    CREATE POLICY "allow_all_staff_requirements" ON staff_requirements FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

---

## B.3 Types TypeScript

```typescript
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
  provision: number
  provision_calculated_at: string | null
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
  is_working_day: boolean
  created_at: string
}

export interface LeaveRule {
  id: string
  tenant_id: string | null
  leave_type: string
  label: string
  accrual_rate: number
  max_carry_over: number
  carry_over_expiry_months: number
  requires_justification: boolean
  requires_manager_approval: boolean
  min_notice_days: number
  max_consecutive_days: number
  color: string
  count_method: 'working_days' | 'working_days_excl_saturday' | 'calendar_days'
  affects_pay: boolean
  deduction_rate: number
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

export interface LeaveProvision {
  id: string
  tenant_id: string | null
  employee_id: string
  period: string
  cp_remaining_days: number
  rtt_remaining_days: number
  recovery_remaining_days: number
  daily_rate: number
  cp_provision: number
  rtt_provision: number
  recovery_provision: number
  total_provision: number
  accounting_entry_id: string | null
  status: 'draft' | 'calculated' | 'posted'
  created_at: string
}

export interface StaffRequirement {
  id: string
  tenant_id: string | null
  department: string
  min_staff: number
  days_of_week: string[]
  start_date: string | null
  end_date: string | null
  active: boolean
  created_at: string
}
```

---

## B.4 Queries

```typescript
// ============ Leave Balances ============
export async function getLeaveBalances(employeeId: string, year?: number)
export async function getMyLeaveBalances()  // pour l'employé connecté
export async function updateLeaveBalance(id: string, updates: Partial<LeaveBalance>)
export async function recalculateLeaveBalance(employeeId: string, leaveType: string, year: number)
// Logique : remaining = acquired + carry_over - taken - pending

export async function carryOverLeaveBalances(employeeId: string, fromYear: number, toYear: number)
// Report des soldes vers l'année suivante (respecte max_carry_over)

export async function initializeYearLeaveBalances(year: number)
// Initialise les soldes pour tous les employés actifs au 1er janvier

// ============ Leave Requests (extension) ============
export async function getMyLeaveRequests()
export async function createMyLeaveRequest(data)
// Crée + met à jour pending + vérifie conflit + vérifie prévenance + vérifie astreinte
export async function cancelMyLeaveRequest(id)
// Annule + décrémente pending
export async function getPendingLeaveRequests(managerId?: string)
export async function approveLeaveRequest(id: string, managerId: string, comment: string)
// Approuve → décrémente pending, incrémente taken, recalcule remaining
export async function rejectLeaveRequest(id: string, managerId: string, comment: string)
// Rejette → décrémente pending, recalcule remaining

// ============ Public Holidays ============
export async function getPublicHolidays(year?: number, region?: string)
export async function createPublicHoliday(data: Omit<PublicHoliday, 'id' | 'created_at'>)
export async function deletePublicHoliday(id: string)
export async function importPublicHolidays(year: number, country: string, region: string)
// Import automatique des jours fériés par pays/région

// ============ Leave Rules ============
export async function getLeaveRules(activeOnly?: boolean)
export async function createLeaveRule(data: Omit<LeaveRule, 'id' | 'created_at'>)
export async function updateLeaveRule(id: string, updates: Partial<LeaveRule>)
export async function deleteLeaveRule(id: string)

// ============ Approval Workflows ============
export async function getApprovalWorkflows(entityType?: string)
export async function createApprovalWorkflow(data: Omit<ApprovalWorkflow, 'id' | 'created_at'>)
export async function updateApprovalWorkflow(id: string, updates: Partial<ApprovalWorkflow>)

// ============ Leave Provisions ============
export async function getLeaveProvisions(period?: string)
export async function calculateLeaveProvisions(period: string)
// Pour chaque employé : provision = remaining_days × daily_rate
export async function postLeaveProvisions(period: string)
// Génère les écritures comptables de provision

// ============ Staff Requirements ============
export async function getStaffRequirements(department?: string)
export async function createStaffRequirement(data: Omit<StaffRequirement, 'id' | 'created_at'>)
export async function updateStaffRequirement(id: string, updates: Partial<StaffRequirement>)

// ============ Helpers ============
export function calculateWorkingDays(startDate: string, endDate: string, holidays: PublicHoliday[], method: string)
// Calcule le nombre de jours (ouvrés/ouvrables/calendaires) entre 2 dates
export async function checkLeaveConflict(employeeId: string, startDate: string, endDate: string)
// Vérifie si l'employé a déjà un congé approuvé sur cette période
export async function checkMinStaffRequired(department: string, startDate: string, endDate: string)
// Vérifie les astreintes (effectif minimum)
export async function exportLeaveDataToPayroll(period: string)
// Export des données de congés pour intégration en paie
```

---

## B.5 Pages

### `LeaveRulesPage.tsx` (nouveau — admin)
**Fichier** : `@/pages/settings/LeaveRulesPage.tsx`

**Structure :**
- **Onglet 1 : "Règles de congés"**
  - Table : Type, Libellé, Taux acquisition, Report max, Expiration report, Prévenance min, Durée max, Couleur, Méthode de calcul, Actif
  - CRUD complet
  - Types : annual, rtt, recovery, sick, unpaid, maternity, paternity, special
- **Onglet 2 : "Jours fériés"**
  - Table : Nom, Date, Région, Pays, Jour ouvré
  - CRUD + bouton "Importer automatiquement" (sélection pays + région + année)
- **Onglet 3 : "Workflows de validation"**
  - Table : Nom, Type d'entité, Étapes (JSON), Actif
  - CRUD + éditeur d'étapes (drag & drop des rôles)
- **Onglet 4 : "Astreintes"**
  - Table : Département, Effectif minimum, Jours, Période, Actif
  - CRUD
- `useTranslation('hr')`

### `LeaveBalancesPage.tsx` (nouveau — admin/RH)
**Fichier** : `@/pages/hr/LeaveBalancesPage.tsx`

**Structure :**
- **Sélecteur d'année** en haut
- **Table principale** : Employé, CP (acquis/pris/en attente/restant/report), RTT, Récup, Maladie, Sans solde, Actions
- **Bouton "Initialiser l'année"** : crée les soldes pour tous les employés actifs
- **Bouton "Report annuel"** : reporte les soldes vers l'année suivante
- **Modal d'édition** : modifier manuellement un solde (acquis, pris, report)
- **Onglet "Provisions CP"** :
  - Sélection de la période (mois)
  - Bouton "Calculer" : calcule les provisions pour tous les employés
  - Table : Employé, Jours CP restants, TJ, Provision CP, Provision RTT, Provision Récup, Total
  - Bouton "Comptabiliser" : génère les écritures comptables
- **Filtres** : département, employé, type de congé
- **Export Excel**
- `useTranslation('hr')`

### `LeavePlanningPage.tsx` (nouveau — admin/RH/manager)
**Fichier** : `@/pages/hr/LeavePlanningPage.tsx`

**Structure :**
- **Vue calendrier** (mois/semaine/jour) avec tous les congés de l'équipe
- **Code couleur** par type de congé (configuré dans leave_rules)
- **Jours fériés** affichés en fond
- **Filtres** : département, employé, type de congé
- **Légende** des couleurs
- **Clic sur un congé** : popup avec détails (employé, type, dates, statut, justificatif)
- **Vue par employé** : timeline individuelle
- **Export PDF** du planning
- `useTranslation('hr')`

### `ManagerLeaveApprovalsPage.tsx` (nouveau — manager)
**Fichier** : `@/pages/employee/ManagerLeaveApprovalsPage.tsx`

**Structure :**
- Liste des demandes en attente pour les employés sous la responsabilité du manager
- Pour chaque demande : nom employé, type, dates, jours, solde restant, justification, justificatif
- Boutons "Approuver" / "Rejeter" avec commentaire obligatoire
- Vue calendrier pour visualiser les chevauchements
- Alerte si effectif minimum non respecté
- Alerte si délai de prévenance non respecté
- Filtres : employé, type, période
- `useTranslation('hr')`

### Extension `LeaveRequestsPage.tsx` (modifier)
- Ajouter colonnes : justificatif (icône upload), demi-journée, commentaire manager, manager
- Ajouter action "Approuver/Rejeter" pour les managers
- Ajouter calcul automatique des jours ouvrés/ouvrables/calendaires
- Ajouter filtre par employé, par département
- Ajouter bouton "Export vers paie" (export des données pour intégration paie)
- Ajouter visualisation du solde restant pour chaque demande

---

# SPRINT C : Paie Avancée (3j)

## C.1 Vue d'ensemble

```
Assistant de préparation (5 étapes)
├── 1. Sélection période
├── 2. Report éléments constants (salaire de base)
├── 3. Éléments variables (heures sup, primes, absences, titres resto, transport)
│   ├── Import automatique timesheets
│   ├── Import automatique congés
│   ├── Import automatique notes de frais
│   └── Saisie manuelle
├── 4. Calcul & prévisualisation (contrôles, anomalies, écarts)
│   ├── Calcul normal (brut → net)
│   └── Calcul à l'envers (net → brut)
└── 5. Validation (génération bulletins)

Titres restaurant ──→ Calcul mensuel ──→ Export commande
Acomptes ──→ Génération ──→ Virement SEPA ──→ Contrôle ──→ Report automatique
Rappels de salaire ──→ Rétroactivité
Virement SEPA ──→ Ordres de paiement ──→ Export fichier
```

### Fonctionnalités Sage 100 couvertes
- **Assistant de préparation** à la réalisation des bulletins de salaire
- **Report automatique des éléments constants**
- **Gestion des titres restaurant**
- **Calcul des paies à l'envers** (net → brut)
- **Gestion des acomptes** : génération, virement, contrôle, report automatique
- **Rappels de salaire** (rétroactivité)
- **Bulletins complémentaires** et bulletins de rappel
- **Double stockage** des bulletins (clarifiés et détaillés)
- **Comptabilité analytique salarié**
- **Ordres de paiement** / **Virement SEPA**
- **Prélèvement à la source** (PAS)
- **Alimentation automatique des variables de paie**

---

## C.2 SQL — Nouvelles tables

### `meal_voucher_config` (Titres restaurant)
```sql
CREATE TABLE IF NOT EXISTS meal_voucher_config (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  voucher_value decimal(15,2) NOT NULL DEFAULT 3.50,
  employer_share decimal(5,2) DEFAULT 60,   -- % employeur
  employee_share decimal(5,2) DEFAULT 40,   -- % salarié
  eligible_days text[] DEFAULT '{1,2,3,4,5}', -- 1=lun...7=dim
  max_per_month int DEFAULT 20,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE meal_voucher_config ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_meal_voucher_config') THEN
    CREATE POLICY "allow_all_meal_voucher_config" ON meal_voucher_config FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `payroll_variable_elements` (Éléments variables de paie)
```sql
CREATE TABLE IF NOT EXISTS payroll_variable_elements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  pay_run_id uuid,
  period text NOT NULL,                -- '2024-01'
  element_type text NOT NULL,          -- 'overtime'|'bonus'|'commission'|'absence'|'meal_voucher'|'transport'|'other'
  description text,
  quantity decimal(15,3),              -- nb heures, nb jours, nb titres
  unit_price decimal(15,2),
  amount decimal(15,2) NOT NULL DEFAULT 0,
  source text,                         -- 'manual'|'timesheet'|'leave_request'|'expense_report'|'import'
  source_id uuid,
  integrated boolean DEFAULT false,    -- intégré dans le bulletin ?
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_variable_elements_employee ON payroll_variable_elements(employee_id);
CREATE INDEX IF NOT EXISTS idx_variable_elements_period ON payroll_variable_elements(period);
CREATE INDEX IF NOT EXISTS idx_variable_elements_payrun ON payroll_variable_elements(pay_run_id);
ALTER TABLE payroll_variable_elements ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_payroll_variable_elements') THEN
    CREATE POLICY "allow_all_payroll_variable_elements" ON payroll_variable_elements FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `sepa_payment_orders` (Ordres de paiement SEPA)
```sql
CREATE TABLE IF NOT EXISTS sepa_payment_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  pay_run_id uuid,
  number text NOT NULL,
  execution_date date NOT NULL,
  total_amount decimal(15,2) NOT NULL DEFAULT 0,
  currency text DEFAULT 'EUR',
  employee_count int DEFAULT 0,
  file_url text,                       -- fichier XML SEPA généré
  file_generated_at timestamptz,
  status text DEFAULT 'draft' CHECK (status IN ('draft', 'generated', 'transmitted', 'processed', 'rejected')),
  transmitted_at timestamptz,
  processed_at timestamptz,
  notes text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sepa_orders_payrun ON sepa_payment_orders(pay_run_id);
ALTER TABLE sepa_payment_orders ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_sepa_payment_orders') THEN
    CREATE POLICY "allow_all_sepa_payment_orders" ON sepa_payment_orders FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `pay_slip_clarified` (Double stockage — bulletins clarifiés)
```sql
CREATE TABLE IF NOT EXISTS pay_slip_clarified (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  pay_slip_id uuid NOT NULL REFERENCES pay_slips(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL,
  period text NOT NULL,
  gross_salary decimal(15,2) DEFAULT 0,
  social_charges_employee decimal(15,2) DEFAULT 0,
  social_charges_employer decimal(15,2) DEFAULT 0,
  income_tax decimal(15,2) DEFAULT 0,   -- prélèvement à la source
  net_before_tax decimal(15,2) DEFAULT 0,
  net_after_tax decimal(15,2) DEFAULT 0,
  total_deductions decimal(15,2) DEFAULT 0,
  lines jsonb DEFAULT '[]',             -- lignes clarifiées (regroupées par catégorie)
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_payslip_clarified_slip ON pay_slip_clarified(pay_slip_id);
ALTER TABLE pay_slip_clarified ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_pay_slip_clarified') THEN
    CREATE POLICY "allow_all_pay_slip_clarified" ON pay_slip_clarified FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

---

## C.3 Types TypeScript

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

export interface SepaPaymentOrder {
  id: string
  tenant_id: string | null
  pay_run_id: string | null
  number: string
  execution_date: string
  total_amount: number
  currency: string
  employee_count: number
  file_url: string | null
  file_generated_at: string | null
  status: 'draft' | 'generated' | 'transmitted' | 'processed' | 'rejected'
  transmitted_at: string | null
  processed_at: string | null
  notes: string | null
  created_at: string
}

export interface PaySlipClarified {
  id: string
  tenant_id: string | null
  pay_slip_id: string
  employee_id: string
  period: string
  gross_salary: number
  social_charges_employee: number
  social_charges_employer: number
  income_tax: number
  net_before_tax: number
  net_after_tax: number
  total_deductions: number
  lines: any[]
  created_at: string
}
```

---

## C.4 Queries

```typescript
// ============ Meal Vouchers ============
export async function getMealVoucherConfig()
export async function updateMealVoucherConfig(id: string, updates: Partial<MealVoucherConfig>)
export async function calculateMealVouchers(month: number, year: number)
// Pour chaque employé actif : nb jours travaillés × valeur du titre
export async function generateMealVoucherElements(payRunId: string, month: number, year: number)
// Crée des payroll_variable_elements de type 'meal_voucher'

// ============ Variable Elements ============
export async function getVariableElements(payRunId?: string, employeeId?: string, period?: string)
export async function createVariableElement(data: Omit<PayrollVariableElement, 'id' | 'created_at'>)
export async function updateVariableElement(id: string, updates: Partial<PayrollVariableElement>)
export async function deleteVariableElement(id: string)
export async function importTimesheetElements(payRunId: string, month: number, year: number)
// Récupère les timesheets approuvés et crée des éléments variables (heures sup)
export async function importLeaveElements(payRunId: string, month: number, year: number)
// Récupère les congés approuvés et crée des déductions
export async function importExpenseElements(payRunId: string, month: number, year: number)
// Récupère les notes de frais approuvées et crée des éléments

// ============ Reverse Calculation ============
export function calculateGrossFromNet(
  targetNet: number,
  components: PayrollComponent[],
  employeeProfile: Employee
): { grossSalary: number, breakdown: PayrollBreakdown[] }
// Logique : itération pour trouver le brut qui donne le net souhaité
// en tenant compte des tranches de cotisations, du barème IR, etc.

// ============ Acomptes (extension) ============
export async function generateAdvanceSepa(payRunId: string, executionDate: string)
// Génère un fichier SEPA pour les acomptes
export async function controlAdvances(payRunId: string)
// Contrôle des acomptes payés
export async function reportAdvances(payRunId: string)
// Report automatique des acomptes payés dans les bulletins

// ============ Rappels de salaire ============
export async function createPayRecall(data: {
  employee_id: string
  period: string
  recall_period: string
  amount: number
  reason: string
})
export async function generateRecallPaySlip(recallId: string)
// Génère un bulletin de rappel (slip_type = 'recall')

// ============ SEPA ============
export async function generateSepaFile(payRunId: string, executionDate: string)
// Génère le fichier XML SEPA pour les virements de salaire
export async function getSepaPaymentOrders()
export async function transmitSepaOrder(id: string)

// ============ Double stockage ============
export async function generateClarifiedPaySlip(paySlipId: string)
// Génère la version clarifiée du bulletin (regroupement par catégorie)

// ============ Comptabilité analytique salarié ============
export async function generatePayrollAnalyticEntries(payRunId: string)
// Génère les écritures analytiques par salarié (centre de coût = département)
```

---

## C.5 Pages

### `PayrollPreparationPage.tsx` (nouveau — assistant 5 étapes)
**Fichier** : `@/pages/hr/PayrollPreparationPage.tsx`

**Structure :**
- **Stepper visuel** en haut (5 étapes avec progression)
- **Étape 1 : Sélection de la période**
  - Mois/année (select)
  - Pay_run existant ou nouveau (radio)
  - Si nouveau : créer un pay_run
- **Étape 2 : Report des éléments constants**
  - Liste des employés actifs avec salaire de base, contrat, convention collective
  - Checkbox pour inclure/exclure un employé
  - Bouton "Tout inclure" / "Tout exclure"
  - Recherche par nom/département
- **Étape 3 : Saisie des éléments variables**
  - Pour chaque employé inclus : table des éléments variables
  - Bouton "Importer depuis les timesheets approuvés"
  - Bouton "Importer depuis les congés" (déduction jours non travaillés)
  - Bouton "Importer depuis les notes de frais approuvées"
  - Saisie manuelle : heures sup (taux majoré), primes, commissions, absences
  - Calcul automatique des titres restaurant (basé sur le config)
  - Calcul automatique des frais de transport (forfait mobilité durable)
  - Bouton "Calcul à l'envers" pour un employé (modal : input net → output brut)
- **Étape 4 : Calcul et prévisualisation**
  - Table récapitulative : Employé, Brut, Cotisations salariales, Cotisations patronales, PAS, Net avant impôt, Net après impôt
  - Alertes : anomalies (salaire à 0, écart > 20% vs mois précédent, etc.)
  - Bouton "Détail" par employé → vue détaillée du bulletin
  - Bouton "Régularisation brut" (sans impact sur les cotisations)
- **Étape 5 : Validation**
  - Bouton "Générer les bulletins" → crée les pay_slips + pay_slip_clarified
  - Marquage des éléments variables comme `integrated = true`
  - Bouton "Générer virement SEPA"
  - Bouton "Passation comptable"
- `useTranslation('payroll')`

### `MealVouchersPage.tsx` (nouveau)
**Fichier** : `@/pages/hr/MealVouchersPage.tsx`

**Structure :**
- **Onglet 1 : "Paramétrage"**
  - Configuration : valeur du titre, part employeur/salarié, jours éligibles, max/mois
- **Onglet 2 : "Calcul mensuel"**
  - Sélection du mois
  - Table : Employé, Jours travaillés, Nb titres, Valeur unitaire, Part employeur, Part salarié, Total
  - Calcul automatique basé sur les timesheets et le paramétrage
  - Bouton "Générer les éléments variables" → crée des payroll_variable_elements
- **Onglet 3 : "Export commande"**
  - Export CSV/Excel pour commande auprès du fournisseur (Edenred, Sodexo, etc.)
  - Format : Employé, Nombre de titres, Valeur unitaire, Total
- `useTranslation('payroll')`

### `SepaPaymentsPage.tsx` (nouveau)
**Fichier** : `@/pages/hr/SepaPaymentsPage.tsx`

**Structure :**
- **Table** : N° ordre, Pay run, Date d'exécution, Montant total, Nb employés, Statut, Actions
- **Bouton "Générer virement SEPA"** : sélectionner un pay_run + date d'exécution
- **Bouton "Télécharger fichier SEPA"** : télécharge le XML
- **Bouton "Transmettre"** : marque comme transmis
- **Détail** : liste des virements individuels (employé, IBAN, montant)
- **Filtres** : statut, période
- `useTranslation('payroll')`

### Extension `PayRunsPage.tsx` (modifier)
- Ajouter bouton "Assistant de préparation" → redirige vers PayrollPreparationPage
- Ajouter colonne "Type" pour distinguer les pay_runs normaux / sortie / rappel
- Ajouter bouton "Virement SEPA" sur les pay_runs validés
- Ajouter bouton "Passation comptable" (déjà existant mais étendre avec analytique)

### Extension `PaySlipsPage.tsx` (modifier)
- Ajouter colonne "Type" (normal, acompte, rappel, sortie, complément)
- Ajouter bouton "Bulletin de sortie" sur les employés inactifs
- Ajouter bouton "Bulletin de rappel"
- Ajouter bouton "Prévisualisation PDF" du bulletin (clarifié + détaillé)
- Ajouter colonne "Distribué" (✓/✗)
- Ajouter colonne "Clarifié" (✓/✗)

### Extension `PayrollCalcPage.tsx` (modifier)
- Ajouter mode "Calcul à l'envers" : input net souhaité → output brut
  - Modal : code rubrique, mode de calcul (autre/subrogation), net à payer
  - Affichage du brut calculé + détail des cotisations
- Ajouter gestion détaillée des titres restaurant (basé sur le config)
- Ajouter gestion des frais de transport (forfait mobilité durable)
- Ajouter "Régularisation des données de type brut" sans impact sur les cotisations
- Ajouter "Connect Import" : intégration de données externes (CSV/Excel)

### Extension `SalaryAdvancesPage.tsx` (modifier)
- Ajouter bouton "Générer virement SEPA" pour les acomptes
- Ajouter bouton "Contrôle des acomptes payés"
- Ajouter bouton "Report automatique" dans les bulletins

---

## C.6 i18n — Clés à ajouter

### Namespace `payroll` — nouvelles sections

| Section | Clés principales |
|---|---|
| `preparation.*` | title, step1, step2, step3, step4, step5, selectPeriod, constantElements, variableElements, preview, validation, includeEmployee, excludeEmployee, importTimesheets, importLeaves, importExpenses, reverseCalc, targetNet, calculatedGross, anomalies, generatePayslips, generateSepa, accountingTransfer, regularization, connectImport |
| `mealVouchers.*` | title, config, voucherValue, employerShare, employeeShare, eligibleDays, maxPerMonth, monthlyCalc, workedDays, voucherCount, employerAmount, employeeAmount, exportOrder, days (mon/tue/wed/thu/fri/sat/sun) |
| `sepa.*` | title, new, generate, executionDate, totalAmount, employeeCount, downloadFile, transmit, status, statuses (draft/generated/transmitted/processed/rejected), detail, individualTransfers |
| `slipTypes.*` | normal, advance, recall, exit, complement |
| `reverseCalc.*` | title, code, calcMode, targetNet, other, subrogation, calculatedGross, breakdown |
| `clarified.*` | title, grossSalary, socialChargesEmployee, socialChargesEmployer, incomeTax, netBeforeTax, netAfterTax, totalDeductions |
| `analytic.*` | title, employeeAnalytic, costCenter, generateEntries |
| `advances.*` (ajouts) | generateSepa, controlAdvances, reportAdvances |
| `recalls.*` (ajouts) | recallPeriod, generateRecallSlip, reason |

### Namespace `hr` — nouvelles sections (Sprint B)

| Section | Clés principales |
|---|---|
| `leaveBalances.*` | title, year, initialize, carryOver, acquired, taken, pending, remaining, carryOver, provision, calculateProvision, postProvision, dailyRate, cpProvision, rttProvision, recoveryProvision, totalProvision, exportExcel |
| `leaveRules.*` | title, leaveType, label, accrualRate, maxCarryOver, carryOverExpiry, requiresJustification, requiresManagerApproval, minNotice, maxConsecutive, color, countMethod, affectsPay, deductionRate, active, methods (working_days/working_days_excl_saturday/calendar_days) |
| `publicHolidays.*` | title, name, date, region, country, isWorkingDay, import, regions (national/alsace-moselle/guadeloupe/etc.) |
| `approvalWorkflows.*` | title, name, entityType, steps, active, entityTypes (leave_request/expense_report/timesheet) |
| `leavePlanning.*` | title, month, week, day, legend, exportPdf, byEmployee |
| `staffRequirements.*` | title, department, minStaff, daysOfWeek, startDate, endDate, active |
| `leaveRequests.*` (ajouts) | halfDay, justification, uploadJustification, balanceAvailable, daysRequested, minNoticeWarning, conflictWarning, staffRequiredWarning, managerComment, exportToPayroll, workingDays, calendarDays |

**3 langues** : fr, en, ar (RTL)

---

## C.7 Routes App.tsx

```tsx
{/* RH Admin — Sprint B */}
<Route path="/hr/leave-balances" element={<LeaveBalancesPage />} />
<Route path="/hr/leave-planning" element={<LeavePlanningPage />} />
<Route path="/settings/leave-rules" element={<LeaveRulesPage />} />

{/* RH Admin — Sprint C */}
<Route path="/hr/payroll-preparation" element={<PayrollPreparationPage />} />
<Route path="/hr/meal-vouchers" element={<MealVouchersPage />} />
<Route path="/hr/sepa-payments" element={<SepaPaymentsPage />} />

{/* Manager — Sprint B */}
<Route path="/employee/manager/approvals" element={<ManagerLeaveApprovalsPage />} />
```

---

## C.8 Navigation (`nav.json`)

Ajouter dans les 3 langues :
```json
{
  "leaveBalances": "Soldes de congés",
  "leavePlanning": "Planning congés",
  "leaveRules": "Règles de congés",
  "payrollPreparation": "Assistant de préparation",
  "mealVouchers": "Titres restaurant",
  "sepaPayments": "Virements SEPA",
  "managerApprovals": "Validations manager"
}
```

---

## C.9 Fichiers créés / modifiés

### Nouveaux fichiers (8)
1. `@/pages/settings/LeaveRulesPage.tsx` — Règles de congés + jours fériés + workflows + astreintes
2. `@/pages/hr/LeaveBalancesPage.tsx` — Soldes + provisions CP
3. `@/pages/hr/LeavePlanningPage.tsx` — Planning de congés
4. `@/pages/employee/ManagerLeaveApprovalsPage.tsx` — Validations manager
5. `@/pages/hr/PayrollPreparationPage.tsx` — Assistant 5 étapes
6. `@/pages/hr/MealVouchersPage.tsx` — Titres restaurant
7. `@/pages/hr/SepaPaymentsPage.tsx` — Virements SEPA
8. `@/sql/58_sprint_b_leaves_absences.sql` + `@/sql/59_sprint_c_payroll_advanced.sql`

### Fichiers modifiés (7)
- `@/types/index.ts` — nouveaux types
- `@/lib/queries.ts` — nouvelles queries
- `@/App.tsx` — nouvelles routes
- `@/pages/LeaveRequestsPage.tsx` — extensions
- `@/pages/PayRunsPage.tsx` — lien assistant + SEPA
- `@/pages/PaySlipsPage.tsx` — type bulletin + clarifié
- `@/pages/PayrollCalcPage.tsx` — calcul à l'envers + titres resto
- `@/pages/SalaryAdvancesPage.tsx` — SEPA + contrôle + report
- `@/i18n/locales/{fr,en,ar}/hr.json` — clés Sprint B
- `@/i18n/locales/{fr,en,ar}/payroll.json` — clés Sprint C
- `@/i18n/locales/{fr,en,ar}/nav.json` — nouvelles clés navigation
