# PARTIE 4 — Sprints F & G : Déclarations Sociales & Dématérialisation RH (6-7j)

> **Sprint F** (3-4j) : DSN (IntuiDSN wizard), DADS-U, DUCS, AED, DPAE, DTS-MSA, CIBTP, Congés Payés BTP, CICE, Refus CDI, CT2025, PASRAU, BDES, bilan social, indicateurs égalité F/H
> **Sprint G** (3j) : Gestion documentaire RH (coffre-fort, distribution bulletins, e-signature, pilotage), requêtes RH, base de connaissances, archivage légal 10 ans
> **i18n** : `useTranslation` (fr, en, ar)
> **SQL** : `app/sql/62_sprint_f_social_declarations.sql` + `app/sql/63_sprint_g_demat_rh.sql`

---

# SPRINT F : Déclarations Sociales & Reporting (3-4j)

## F.1 Vue d'ensemble

```
DSN (IntuiDSN wizard 5 étapes)
├── 1. Sélection période
├── 2. Vérification données (anomalies, manquants)
├── 3. Génération fichier
├── 4. Transmission (Net-Entreprises)
└── 5. Suivi du retour (accepté/rejeté + codes erreur)

Autres déclarations
├── DADS-U (XML)
├── DUCS URSSAF
├── AED (attestation employeur)
├── DPAE (déclaration préalable embauche)
├── DTS-MSA (secteur agricole)
├── CIBTP + Congés Payés BTP (secteur BTP)
├── CICE (paramétrage + calcul)
├── Refus CDI / CT2025
└── PASRAU (prélèvement à la source, régularisation annuelle)

Reporting
├── BDES (base de données économiques et sociales)
├── Bilan social
├── Indicateurs égalité femmes / hommes
└── Éditions légales pré-paramétrées
```

### Fonctionnalités Sage 100 couvertes (recherche internet)
- **DSN mensuelle et événementielle** (arrêts de travail, fins de contrat, reprise)
- **IntuiDSN** : navigation guidée étape par étape
- **Automatisation des régularisations DSN**
- **PASRAU** : prélèvement à la source, régularisation annuelle
- **DADS-U** à la norme N4DS
- **DUCS** URSSAF
- **AED** : attestation employeur
- **DPAE** : déclaration préalable à l'embauche
- **DTS-MSA** (secteur agricole)
- **CIBTP** + **Congés Payés BTP** (secteur BTP)
- **CICE** : paramétrage et calcul
- **Refus CDI** / **CT2025**
- **Gestion des honoraires**
- **BDES** : alimentation avec données paie + RH + comptabilité
- **Indicateurs égalité femmes / hommes** (livré en standard)
- **Éditions légales pré-paramétrées**
- **Sage DS** : service déclaratif intégré
- **Bilans NEORES** : affichage directement dans la Paie
- **Import des taux PAS, des taux AT et des taux bonus/malus**

---

## F.2 SQL — Nouvelles tables

### `social_declarations` (Toutes les déclarations sociales)
```sql
CREATE TABLE IF NOT EXISTS social_declarations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  number text NOT NULL,
  declaration_type text NOT NULL,       -- 'dsn'|'dads_u'|'ducs'|'aed'|'dpae'|'dts_msa'|'cibtp'|'conges_payes_btp'|'cice'|'refus_cdi'|'ct2025'|'pasrau'|'other'
  subtype text,                         -- 'monthly'|'event_stoppage'|'event_exit'|'event_hire'|'event_reprise'|'regularization'|'annual'
  period_month int,
  period_year int,
  period text,                          -- '2024-01'
  due_date date,
  status text DEFAULT 'draft' CHECK (status IN ('draft', 'generated', 'transmitted', 'accepted', 'rejected', 'regularized')),
  file_url text,                        -- fichier généré (XML, CSV, PDF)
  file_format text,                     -- 'xml'|'csv'|'pdf'|'edi'
  generated_at timestamptz,
  transmitted_at timestamptz,
  response_code text,
  response_message text,
  anomalies jsonb DEFAULT '[]',         -- anomalies détectées avant transmission
  amount decimal(15,2),                 -- montant déclaré (si applicable)
  employee_count int,
  details jsonb DEFAULT '{}',           -- détails spécifiques au type
  notes text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_social_declarations_type ON social_declarations(declaration_type);
CREATE INDEX IF NOT EXISTS idx_social_declarations_period ON social_declarations(period);
CREATE INDEX IF NOT EXISTS idx_social_declarations_status ON social_declarations(status);
ALTER TABLE social_declarations ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_social_declarations') THEN
    CREATE POLICY "allow_all_social_declarations" ON social_declarations FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `cice_config` (Paramétrage CICE)
```sql
CREATE TABLE IF NOT EXISTS cice_config (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  year int NOT NULL,
  smic_threshold decimal(15,2) DEFAULT 2.5,  -- multiple du SMIC
  rate decimal(5,2) DEFAULT 6,               -- taux CICE %
  eligible_salary_cap decimal(15,2),          -- plafond
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE cice_config ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_cice_config') THEN
    CREATE POLICY "allow_all_cice_config" ON cice_config FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `pas_rates` (Taux de prélèvement à la source par employé)
```sql
CREATE TABLE IF NOT EXISTS pas_rates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  rate decimal(5,4) NOT NULL DEFAULT 0,  -- taux PAS (ex: 0.0300 = 3%)
  effective_date date NOT NULL,
  expiry_date date,
  source text DEFAULT 'import',         -- 'import'|'manual'|'api'
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pas_rates_employee ON pas_rates(employee_id);
CREATE INDEX IF NOT EXISTS idx_pas_rates_dates ON pas_rates(effective_date, expiry_date);
ALTER TABLE pas_rates ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_pas_rates') THEN
    CREATE POLICY "allow_all_pas_rates" ON pas_rates FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `at_rates` (Taux accidents du travail par employé)
```sql
CREATE TABLE IF NOT EXISTS at_rates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  rate decimal(5,4) NOT NULL DEFAULT 0,
  bonus_malus_rate decimal(5,4) DEFAULT 0,
  effective_date date NOT NULL,
  expiry_date date,
  risk_category text,                   -- catégorie de risque
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_at_rates_employee ON at_rates(employee_id);
ALTER TABLE at_rates ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_at_rates') THEN
    CREATE POLICY "allow_all_at_rates" ON at_rates FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `bdes_indicators` (BDES — Base de données économiques et sociales)
```sql
CREATE TABLE IF NOT EXISTS bdes_indicators (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  year int NOT NULL,
  category text NOT NULL,               -- 'effectifs'|'remuneration'|'formation'|'conditions_travail'|'hygiene_securite'|'relations_sociales'|'egalite_f_h'
  indicator_name text NOT NULL,
  indicator_value decimal(15,2),
  indicator_unit text,                  -- 'count'|'percent'|'currency'|'hours'|'days'
  breakdown jsonb DEFAULT '{}',         -- décomposition par genre, âge, catégorie, etc.
  target_value decimal(15,2),
  previous_year_value decimal(15,2),
  notes text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_bdes_year ON bdes_indicators(year);
CREATE INDEX IF NOT EXISTS idx_bdes_category ON bdes_indicators(category);
ALTER TABLE bdes_indicators ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_bdes_indicators') THEN
    CREATE POLICY "allow_all_bdes_indicators" ON bdes_indicators FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `honorarium_records` (Gestion des honoraires)
```sql
CREATE TABLE IF NOT EXISTS honorarium_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id uuid REFERENCES employees(id) ON DELETE SET NULL,
  recipient_name text NOT NULL,
  recipient_type text,                  -- 'employee'|'external'|'intern'
  period text,
  amount decimal(15,2) NOT NULL DEFAULT 0,
  description text,
  accounting_entry_id uuid,
  status text DEFAULT 'pending' CHECK (status IN ('pending', 'paid', 'accounted')),
  created_at timestamptz DEFAULT now()
);
ALTER TABLE honorarium_records ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_honorarium_records') THEN
    CREATE POLICY "allow_all_honorarium_records" ON honorarium_records FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

---

## F.3 Types TypeScript

```typescript
export interface SocialDeclaration {
  id: string
  tenant_id: string | null
  number: string
  declaration_type: 'dsn' | 'dads_u' | 'ducs' | 'aed' | 'dpae' | 'dts_msa' | 'cibtp' | 'conges_payes_btp' | 'cice' | 'refus_cdi' | 'ct2025' | 'pasrau' | 'other'
  subtype: string | null
  period_month: number | null
  period_year: number | null
  period: string | null
  due_date: string | null
  status: 'draft' | 'generated' | 'transmitted' | 'accepted' | 'rejected' | 'regularized'
  file_url: string | null
  file_format: string | null
  generated_at: string | null
  transmitted_at: string | null
  response_code: string | null
  response_message: string | null
  anomalies: any[]
  amount: number | null
  employee_count: number | null
  details: Record<string, any>
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

export interface PasRate {
  id: string
  tenant_id: string | null
  employee_id: string
  rate: number
  effective_date: string
  expiry_date: string | null
  source: 'import' | 'manual' | 'api'
  created_at: string
}

export interface AtRate {
  id: string
  tenant_id: string | null
  employee_id: string
  rate: number
  bonus_malus_rate: number
  effective_date: string
  expiry_date: string | null
  risk_category: string | null
  created_at: string
}

export interface BdesIndicator {
  id: string
  tenant_id: string | null
  year: number
  category: string
  indicator_name: string
  indicator_value: number | null
  indicator_unit: string | null
  breakdown: Record<string, any>
  target_value: number | null
  previous_year_value: number | null
  notes: string | null
  created_at: string
}

export interface HonorariumRecord {
  id: string
  tenant_id: string | null
  employee_id: string | null
  recipient_name: string
  recipient_type: 'employee' | 'external' | 'intern'
  period: string | null
  amount: number
  description: string | null
  accounting_entry_id: string | null
  status: 'pending' | 'paid' | 'accounted'
  created_at: string
}
```

---

## F.4 Queries

```typescript
// ============ Social Declarations (CRUD) ============
export async function getSocialDeclarations(type?: string, period?: string, status?: string)
export async function createSocialDeclaration(data: Omit<SocialDeclaration, 'id' | 'created_at'>)
export async function updateSocialDeclaration(id: string, updates: Partial<SocialDeclaration>)

// ============ DSN (IntuiDSN wizard) ============
export async function checkDsnAnomalies(period: string)
// Vérifie les données avant transmission : données manquantes, incohérences
// Retourne une liste d'anomalies par employé
export async function generateDsnFile(period: string, subtype?: string)
// Génère le fichier DSN (XML/EDI) pour la période
export async function transmitDsn(declarationId: string)
// Transmet via Net-Entreprises (ou marqué comme transmis manuellement)
export async function getDsnHistory()
// Historique des transmissions DSN avec retours
export async function getDsnReturnCodes(declarationId: string)
// Codes de retour Net-Entreprises (accepté/rejeté + détails)

// ============ DSN événementielles ============
export async function generateDsnStoppage(workStoppageId: string)
// DSN signalement arrêt de travail
export async function generateDsnReprise(workStoppageId: string)
// DSN signalement de reprise
export async function generateDsnExit(exitProcessId: string)
// DSN fin de contrat (déjà dans Sprint E)
export async function generateDsnHire(employeeId: string, contractId: string)
// DSN signalement d'embauche / amorçage des données variables

// ============ DADS-U ============
export async function generateDadsU(period: string)
// Génération du fichier DADS-U (format XML N4DS)

// ============ DUCS ============
export async function generateDucs(period: string)
// Génération de la DUCS URSSAF

// ============ AED ============
export async function generateAed(employeeId: string)
// Attestation employeur (génération à la demande pour un employé)

// ============ DPAE ============
export async function generateDpae(employeeId: string, contractId: string)
// Déclaration préalable à l'embauche

// ============ DTS-MSA ============
export async function generateDtsMsa(period: string)
// DTS-MSA (secteur agricole)

// ============ BTP ============
export async function generateCibtp(period: string)
export async function generateCongesPayesBtp(period: string)

// ============ CICE ============
export async function getCiceConfig(year?: number)
export async function updateCiceConfig(id: string, updates: Partial<CiceConfig>)
export async function calculateCice(year: number)
// Calcule le CICE pour tous les employés éligibles (seuil SMIC, plafond)
export async function generateCiceFile(year: number)

// ============ Autres déclarations ============
export async function generateRefusCdi(period: string)
export async function generateCt2025(period: string)

// ============ PASRAU ============
export async function generatePasrau(year: number)
// Régularisation annuelle du prélèvement à la source

// ============ PAS & AT Rates ============
export async function getPasRates(employeeId?: string)
export async function importPasRates(file: File)
// Import des taux PAS depuis fichier (CSV/Excel)
export async function updatePasRate(id: string, updates: Partial<PasRate>)
export async function getAtRates(employeeId?: string)
export async function importAtRates(file: File)
// Import des taux AT et bonus/malus
export async function updateAtRate(id: string, updates: Partial<AtRate>)

// ============ BDES ============
export async function getBdesIndicators(year: number, category?: string)
export async function calculateBdesIndicators(year: number)
// Calcule automatiquement les indicateurs BDES depuis les données paie + RH
// - effectifs (évolution, répartition par genre/âge/catégorie)
// - rémunérations (masse salariale, évolution, écarts F/H)
// - formation (heures, budget, accès)
// - conditions de travail (temps de travail, absentéisme)
// - hygiène sécurité (accidents, maladies pro)
// - relations sociales (élections, délégués)
// - égalité F/H (indicateurs obligatoires)
export async function calculateEqualityIndicators(year: number)
// Calcul des indicateurs égalité femmes / hommes (obligation légale)
export async function generateBdesReport(year: number)
// Génère le rapport BDES complet

// ============ Bilan social ============
export async function generateSocialReport(year: number)
// Génère le bilan social annuel

// ============ Honoraires ============
export async function getHonorariumRecords(period?: string)
export async function createHonorariumRecord(data: Omit<HonorariumRecord, 'id' | 'created_at'>)
export async function updateHonorariumRecord(id: string, updates: Partial<HonorariumRecord>)
export async function generateHonorariumAccounting(id: string)
// Génère les écritures comptables pour les honoraires
```

---

## F.5 Pages

### `SocialDeclarationsPage.tsx` (nouveau — multi-onglets)
**Fichier** : `@/pages/hr/SocialDeclarationsPage.tsx`

**Structure :**
- **Onglet "DSN"** (existant + améliorations) :
  - **IntuiDSN** : wizard visuel étape par étape
    - Étape 1 : Sélection de la période (mois/année)
    - Étape 2 : Vérification des données (anomalies affichées en tableau, correction possible)
    - Étape 3 : Génération du fichier (progress bar)
    - Étape 4 : Transmission (bouton "Transmettre via Net-Entreprises")
    - Étape 5 : Suivi du retour (accepté/rejeté + codes d'erreur + message)
  - Historique des transmissions DSN (table avec statut, date, retour)
  - Bouton "DSN événementielle" : sous-menu (arrêt, reprise, fin de contrat, embauche)
- **Onglet "DADS-U"** :
  - Sélection de la période (année)
  - Bouton "Générer" → fichier XML N4DS
  - Téléchargement
  - Historique
- **Onglet "DUCS"** :
  - Sélection de la période (mois/année)
  - Bouton "Générer" → DUCS URSSAF
  - Téléchargement
- **Onglet "AED"** :
  - Sélection de l'employé
  - Bouton "Générer" → attestation employeur PDF
  - Téléchargement
- **Onglet "DPAE"** :
  - Sélection de l'employé + contrat
  - Bouton "Générer" → DPAE
  - Historique des DPAE
- **Onglet "BTP"** :
  - CIBTP : sélection période + génération + téléchargement
  - Congés Payés BTP : sélection période + génération + téléchargement
- **Onglet "MSA"** :
  - DTS-MSA : sélection période + génération + téléchargement (secteur agricole)
- **Onglet "CICE"** :
  - Paramétrage (table cice_config) : année, seuil SMIC, taux, plafond
  - Bouton "Calculer" pour l'année → table des employés éligibles avec montant
  - Bouton "Générer fichier"
- **Onglet "PASRAU"** :
  - Sélection de l'année
  - Bouton "Générer" → régularisation annuelle PAS
- **Onglet "Autres"** :
  - Refus CDI : génération + téléchargement
  - CT2025 : génération + téléchargement
  - Gestion des honoraires : table + CRUD + comptabilisation
- **Onglet "Taux"** :
  - PAS : import des taux (CSV/Excel) + table par employé + édition manuelle
  - AT : import des taux AT + bonus/malus + table par employé
- `useTranslation('hr')`

### `BdesPage.tsx` (nouveau — admin/RH)
**Fichier** : `@/pages/hr/BdesPage.tsx`

**Structure :**
- **Sélecteur d'année** en haut
- **Bouton "Calculer les indicateurs"** : calcule automatiquement depuis les données paie + RH
- **Onglets par catégorie** :
  - **Effectifs** : évolution, répartition par genre/âge/catégorie/contrat
  - **Rémunérations** : masse salariale, évolution, écarts F/H, grilles de salaires
  - **Formation** : heures de formation, budget, taux d'accès
  - **Conditions de travail** : temps de travail, aménagement, absentéisme
  - **Hygiène & sécurité** : accidents du travail, maladies professionnelles, jours perdus
  - **Relations sociales** : élections CSE, délégués, accords d'entreprise
  - **Égalité F/H** : indicateurs obligatoires (écart rémunération, écart augmentations, % augmentées, % promotions, retour congé maternité, parité top 10)
- **Table par catégorie** : Indicateur, Valeur, Année précédente, Cible, Détail
- **Bouton "Générer rapport BDES"** : export PDF complet
- **Bouton "Générer bilan social"** : export PDF du bilan social annuel
- `useTranslation('hr')`

### Extension `DSNPage.tsx` (modifier — dans Phase4Pages.tsx)
- Remplacer par redirection vers `SocialDeclarationsPage` onglet DSN
- Ou intégrer IntuiDSN directement si page séparée préférée

### Extension `LegalDeclarationsPage.tsx` (modifier)
- Ajouter liens vers les nouveaux types de déclarations
- Ou rediriger vers `SocialDeclarationsPage`

### Extension `PayrollArchivePage.tsx` (modifier)
- Ajouter bouton "Passation comptable CSV" : export des écritures de paie au format CSV avec ordonnancement
- Ajouter bouton "Régularisation brut" : régularisation des données de type brut sans impact sur les cotisations
- Ajouter conformité archivage : mention AFNOR Z42-013, NF Z42-025, RGPD, Art. L3243-2 Code du travail

---

# SPRINT G : Dématérialisation RH (3j)

## G.1 Vue d'ensemble

```
Gestion documentaire RH
├── Coffre-fort électronique (par employé)
│   ├── Upload documents (bulletins, contrats, DPAE, certificats)
│   ├── Distribution en lot (bulletins de paie)
│   ├── Accusé de réception
│   ├── e-Signature (hash + timestamp)
│   └── Pilotage (statistiques, graphiques)
├── Requêtes RH (relation RH-salariés)
│   ├── Types : copie document, certificat, info congés, changement salaire/adresse
│   ├── Attribution automatique
│   └── Suivi temps de traitement
├── Base de connaissances RH
│   ├── Articles par catégorie (paie, congés, contrats, droit, procédures)
│   ├── Recherche full-text
│   └── Compteur de vues
└── Archivage légal 10 ans
    ├── Conformité AFNOR Z42-013 / NF Z42-025
    ├── Conformité RGPD
    └── Conformité Art. L3243-2 Code du travail
```

### Fonctionnalités Sage 100 couvertes
- **Dématérialisation des bulletins de paie** et documents RH
- **Coffre-fort électronique** sécurisé
- **Distribution en lot** des bulletins de paie
- **Accusé de réception** électronique
- **e-Signature** (horodatage, hash)
- **Archivage légal** 10 ans (50 ans pour bulletins de paie dans coffre-fort)
- **Pilotage de l'activité documentaire**
- **Base de connaissances RH** (IntuiSage)
- **Portail Sage Espace Employés** (dématérialisation des processus RH)

---

## G.2 SQL — Nouvelles tables

### `employee_documents` (Coffre-fort électronique)
```sql
CREATE TABLE IF NOT EXISTS employee_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  document_type text NOT NULL,          -- 'payslip'|'contract'|'dpae'|'dsn'|'certificate'|'work_certificate'|'settlement_receipt'|'pole_emploi_attestation'|'medical_cert'|'other'
  title text NOT NULL,
  file_url text NOT NULL,
  file_size bigint,
  mime_type text,
  period text,                          -- '2024-01' pour bulletin
  uploaded_by text,                     -- email de l'utilisateur qui a uploadé
  visible_to_employee boolean DEFAULT true,
  requires_acknowledgment boolean DEFAULT false,
  acknowledged boolean DEFAULT false,
  acknowledged_at timestamptz,
  e_signed boolean DEFAULT false,
  e_signed_at timestamptz,
  e_signature_hash text,
  archived boolean DEFAULT false,
  archive_date date,
  retention_years int DEFAULT 10,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_emp_docs_employee ON employee_documents(employee_id);
CREATE INDEX IF NOT EXISTS idx_emp_docs_type ON employee_documents(document_type);
CREATE INDEX IF NOT EXISTS idx_emp_docs_period ON employee_documents(period);
ALTER TABLE employee_documents ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_employee_documents') THEN
    CREATE POLICY "allow_all_employee_documents" ON employee_documents FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `document_distribution_logs` (Pilotage de la distribution)
```sql
CREATE TABLE IF NOT EXISTS document_distribution_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  batch_id uuid,                       -- identifiant de lot
  employee_document_id uuid REFERENCES employee_documents(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  document_type text,
  period text,
  distributed_at timestamptz,
  acknowledged_at timestamptz,
  status text DEFAULT 'distributed' CHECK (status IN ('distributed', 'acknowledged', 'bounced', 'failed')),
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_dist_logs_batch ON document_distribution_logs(batch_id);
CREATE INDEX IF NOT EXISTS idx_dist_logs_employee ON document_distribution_logs(employee_id);
ALTER TABLE document_distribution_logs ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_document_distribution_logs') THEN
    CREATE POLICY "allow_all_document_distribution_logs" ON document_distribution_logs FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `rh_requests` (Requêtes RH — relation RH-salariés)
```sql
CREATE TABLE IF NOT EXISTS rh_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  request_type text NOT NULL,          -- 'document_copy'|'certificate'|'leave_info'|'salary_change'|'address_change'|'other'
  subject text NOT NULL,
  description text,
  status text DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'resolved', 'rejected')),
  assigned_to text,                    -- user RH assigné
  response text,
  resolved_at timestamptz,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_rh_requests_status ON rh_requests(status);
CREATE INDEX IF NOT EXISTS idx_rh_requests_employee ON rh_requests(employee_id);
ALTER TABLE rh_requests ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_rh_requests') THEN
    CREATE POLICY "allow_all_rh_requests" ON rh_requests FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `rh_knowledge_base` (Base de connaissances RH)
```sql
CREATE TABLE IF NOT EXISTS rh_knowledge_base (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  title text NOT NULL,
  content text NOT NULL,
  category text,                       -- 'paie'|'conges'|'contrats'|'droit'|'procedure'|'other'
  tags text[],
  author_id text,
  published boolean DEFAULT false,
  views int DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_rh_kb_category ON rh_knowledge_base(category);
ALTER TABLE rh_knowledge_base ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_rh_knowledge_base') THEN
    CREATE POLICY "allow_all_rh_knowledge_base" ON rh_knowledge_base FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

---

## G.3 Types TypeScript

```typescript
export interface EmployeeDocument {
  id: string
  tenant_id: string | null
  employee_id: string
  document_type: 'payslip' | 'contract' | 'dpae' | 'dsn' | 'certificate' | 'work_certificate' | 'settlement_receipt' | 'pole_emploi_attestation' | 'medical_cert' | 'other'
  title: string
  file_url: string
  file_size: number | null
  mime_type: string | null
  period: string | null
  uploaded_by: string | null
  visible_to_employee: boolean
  requires_acknowledgment: boolean
  acknowledged: boolean
  acknowledged_at: string | null
  e_signed: boolean
  e_signed_at: string | null
  e_signature_hash: string | null
  archived: boolean
  archive_date: string | null
  retention_years: number
  created_at: string
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
```

---

## G.4 Queries

```typescript
// ============ Employee Documents ============
export async function getEmployeeDocuments(employeeId: string)
export async function getMyDocuments()
export async function uploadEmployeeDocument(employeeId: string, file: File, metadata: any)
export async function deleteEmployeeDocument(id: string)
export async function acknowledgeDocument(id: string)
export async function bulkUploadDocuments(files: File[], documentType: string, employeeIds?: string[])

// ============ Distribution ============
export async function distributePaySlips(payRunId: string)
// Pour chaque pay_slip du pay_run : créer employee_document + distribution_log
export async function controlBatchBeforeDiffusion(payRunId: string)
// Vérification : cohérence des bulletins, nb destinataires, doublons
export async function getDistributionLogs(batchId?: string)
export async function sendDistributionReminders(batchId: string)
// Relance les employés qui n'ont pas accusé réception

// ============ e-Signature ============
export async function requestESignature(documentId: string, employeeId: string)
export async function signDocument(documentId: string)
// Génère un hash du document + timestamp

// ============ Document Stats ============
export async function getDocumentStats()
// nb par type, nb distribués, nb accusés, nb signés, taux

// ============ RH Requests ============
export async function getRhRequests(status?: string, type?: string)
export async function createRhRequest(data: Omit<RhRequest, 'id' | 'created_at'>)
export async function updateRhRequest(id: string, updates: Partial<RhRequest>)
export async function assignRhRequest(id: string, assignedTo: string)
export async function resolveRhRequest(id: string, response: string)

// ============ Knowledge Base ============
export async function getRhKnowledgeBase(category?: string, search?: string)
export async function createRhKnowledgeBaseArticle(data: Omit<RhKnowledgeBaseArticle, 'id' | 'created_at' | 'updated_at'>)
export async function updateRhKnowledgeBaseArticle(id: string, updates: Partial<RhKnowledgeBaseArticle>)
export async function deleteRhKnowledgeBaseArticle(id: string)
export async function incrementArticleViews(id: string)
```

---

## G.5 Pages

### `DocumentManagementPage.tsx` (nouveau — admin/RH)
**Fichier** : `@/pages/hr/DocumentManagementPage.tsx`

**Structure :**
- **Onglet 1 : "Documents"**
  - Table : Employé, Type, Titre, Période, Visible employé, Accusé réception, Signé, Taille, Date, Actions
  - Bouton "Déposer un document" (upload + sélection employé + type + période)
  - Bouton "Dépôt manuel hors bulletin" (avec ou sans annexes)
  - Bouton "Synchroniser bulletins d'un mois précédent" (dépôt rétroactif)
  - Bouton "Upload en lot" (sélection multiple de fichiers + type)
  - Filtres : employé, type, période, visible, signé
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
  - Indicateurs en temps réel
- **Onglet 4 : "e-Signature"**
  - Table des documents en attente de signature : Employé, Document, Date demande, Statut
  - Bouton "Envoyer demande de signature" (sélection document + employé)
  - Suivi des signatures en temps réel (hash + timestamp)
- `useTranslation('hr')`

### `RhRequestsPage.tsx` (nouveau — admin/RH)
**Fichier** : `@/pages/hr/RhRequestsPage.tsx`

**Structure :**
- **Table** : Employé, Type de demande, Sujet, Statut, Assigné à, Date, Actions
- **Types** : copie de document, certificat, information congés, changement salaire, changement adresse, autre
- **Bouton "Nouvelle demande"** : modal (employé, type, sujet, description)
- **Bouton "Assigner"** : assigner à un gestionnaire RH
- **Bouton "Traiter"** : modal avec réponse + changement de statut
- **Règles d'attribution automatique** : selon le type de demande
- **Filtres** : statut, type, employé, période
- **Statistiques** : nb requêtes en attente, temps moyen de traitement, taux de résolution
- `useTranslation('hr')`

### `RhKnowledgeBasePage.tsx` (nouveau — admin/RH)
**Fichier** : `@/pages/hr/RhKnowledgeBasePage.tsx`

**Structure :**
- **Vue articles** : cards avec titre, catégorie, vues, extrait
- **Recherche full-text** : barre de recherche
- **Filtres** : catégorie (paie, congés, contrats, droit, procédures), tags
- **CRUD complet** : création/édition d'articles avec éditeur de texte riche
- **Publication** : brouillon → publié
- **Système de vues** : compteur automatique
- `useTranslation('hr')`

### `EmployeeDocumentsPage.tsx` (nouveau — self-service employé)
**Fichier** : `@/pages/employee/EmployeeDocumentsPage.tsx`

**Structure :**
- **Table "Mes documents"** : Type, Titre, Période, Date, Accusé réception, Actions
- **Filtres** : type (bulletin de paie, contrat, certificat, autre), période
- **Bouton "Télécharger"** : télécharge le document
- **Bouton "Accuser réception"** : si `requires_acknowledgment`
- **Bouton "Signer"** : si `e_signed` requis
- **Section "Coffre-fort"** : présentation visuelle, nombre de documents, dernière connexion
- `useTranslation('employee')`

### Extension `PaySlipsPage.tsx` (modifier)
- Ajouter bouton "Distribuer les bulletins" sur chaque pay_run
- Ajouter colonne "Distribué" (✓/✗) sur chaque bulletin
- Ajouter colonne "Accusé de réception"

### Extension `PayrollArchivePage.tsx` (modifier)
- Ajouter mention du double archivage (employeur + salarié)
- Ajouter conformité aux normes AFNOR Z42-013 et NF Z42-025
- Ajouter conformité RGPD
- Ajouter conformité Art. L3243-2 du Code du travail
- Ajouter bouton "Passation comptable CSV"
- Ajouter bouton "Régularisation brut"

---

## G.6 i18n — Clés à ajouter

### Namespace `hr` — nouvelles sections

| Section | Clés principales |
|---|---|
| `declarations.*` | title, dsn, dadsU, ducs, aed, dpae, dtsMsa, cibtp, congesPayesBtp, cice, refusCdi, ct2025, pasrau, intuiDsn, generate, transmit, anomalyCheck, responseCode, responseMessage, ciceConfig, smicThreshold, rate, eligibleSalaryCap, calculateCice, generateFile, importPas, importAt, pasRates, atRates, bonusMalus, subtypes (monthly/event_stoppage/event_exit/event_hire/event_reprise/regularization/annual), statuses (draft/generated/transmitted/accepted/rejected/regularized) |
| `bdes.*` | title, year, calculate, categories (effectifs/remuneration/formation/conditions_travail/hygiene_securite/relations_sociales/egalite_f_h), indicatorName, indicatorValue, previousYear, target, breakdown, generateReport, generateSocialReport, equalityIndicators |
| `honorarium.*` | title, recipientName, recipientType, period, amount, description, status, generateAccounting, types (employee/external/intern), statuses (pending/paid/accounted) |
| `demat.*` | title, vault, doubleArchiving, afnorCompliance, rgpdCompliance, laborCodeCompliance, pilotage, distributionLogs, sendReminders, batchControl, distribute, acknowledged, eSigned, requestSignature, statistics, totalDocuments, distributedPayslips, acknowledgmentRate, signatureRate, types (payslip/contract/dpae/dsn/certificate/work_certificate/settlement_receipt/pole_emploi_attestation/medical_cert/other) |
| `requests.*` | title, newRequest, requestType, types (documentCopy/certificate/leaveInfo/salaryChange/addressChange/other), assignTo, resolve, response, avgProcessingTime, resolutionRate, statuses (pending/in_progress/resolved/rejected) |
| `knowledgeBase.*` | title, newArticle, categories (payroll/leaves/contracts/law/procedures/other), search, published, draft, views, tags, content |

### Namespace `employee` (ajouts)

| Section | Clés principales |
|---|---|
| `documents.*` | title, coffreFort, type, uploadDate, download, acknowledge, sign, types (payslip/contract/certificate/other), distribution, distribute, batchControl, statistics, totalDocuments, distributedPayslips, acknowledgmentRate |

**3 langues** : fr, en, ar (RTL)

---

## G.7 Routes App.tsx

```tsx
{/* RH Admin — Sprint F */}
<Route path="/hr/social-declarations" element={<SocialDeclarationsPage />} />
<Route path="/hr/bdes" element={<BdesPage />} />

{/* RH Admin — Sprint G */}
<Route path="/hr/documents" element={<DocumentManagementPage />} />
<Route path="/hr/rh-requests" element={<RhRequestsPage />} />
<Route path="/hr/knowledge-base" element={<RhKnowledgeBasePage />} />

{/* Espace Employés — Sprint G */}
<Route path="/employee/documents" element={<EmployeeDocumentsPage />} />
```

---

## G.8 Navigation (`nav.json`)

Ajouter dans les 3 langues :
```json
{
  "socialDeclarations": "Déclarations sociales",
  "bdes": "BDES & Bilan social",
  "documentManagement": "Gestion documentaire",
  "rhRequests": "Requêtes RH",
  "knowledgeBase": "Base de connaissances"
}
```

---

## G.9 Fichiers créés / modifiés

### Nouveaux fichiers (6)
1. `@/pages/hr/SocialDeclarationsPage.tsx` — Toutes déclarations sociales (multi-onglets)
2. `@/pages/hr/BdesPage.tsx` — BDES, bilan social, indicateurs égalité F/H
3. `@/pages/hr/DocumentManagementPage.tsx` — Gestion documentaire (distribution, e-signature, pilotage)
4. `@/pages/hr/RhRequestsPage.tsx` — Requêtes RH
5. `@/pages/hr/RhKnowledgeBasePage.tsx` — Base de connaissances RH
6. `@/pages/employee/EmployeeDocumentsPage.tsx` — Coffre-fort employé
7. `@/sql/62_sprint_f_social_declarations.sql` + `@/sql/63_sprint_g_demat_rh.sql`

### Fichiers modifiés (6)
- `@/types/index.ts` — nouveaux types
- `@/lib/queries.ts` — nouvelles queries
- `@/App.tsx` — nouvelles routes
- `@/pages/PaySlipsPage.tsx` — distribution + accusé réception
- `@/pages/PayrollArchivePage.tsx` — passation CSV + conformité archivage
- `@/pages/LegalDeclarationsPage.tsx` — liens vers nouvelles déclarations
- `@/i18n/locales/{fr,en,ar}/hr.json` — clés Sprint F+G
- `@/i18n/locales/{fr,en,ar}/nav.json` — nouvelles clés navigation
