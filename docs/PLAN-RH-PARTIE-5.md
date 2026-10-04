# PARTIE 5 — Sprints H, I & J : Espace Employés, Pilotage RH, PWA & i18n (7-9j)

> **Sprint H** (3j) : Dashboard employé, profil self-service, dashboard RH (widgets complets), pilotage RH (reportings, tableaux de bord)
> **Sprint I** (2-3j) : PWA mobile (congés, notes de frais, approbations), responsive design, offline mode
> **Sprint J** (2j) : i18n complet — namespace `employee` (fr/en/ar), extension `hr` + `payroll` + `nav`, audit i18n
> **i18n** : `useTranslation` (fr, en, ar) sur TOUS les nouveaux composants
> **SQL** : `app/sql/64_sprint_h_pilotage_rh.sql` (pas de SQL pour Sprint I/J — config uniquement)

---

# SPRINT H : Espace Employés Dashboard, Profil & Pilotage RH (3j)

## H.1 Vue d'ensemble

```
Espace Employés (self-service)
├── Dashboard employé
│   ├── Cartes : mes congés (CP/RTT/récup), demandes en attente, notes de frais, prochains entretiens
│   ├── Activité récente (timeline)
│   └── Planning congés (mini-calendrier)
├── Profil self-service
│   ├── Informations personnelles (modifiable selon droits)
│   ├── Informations professionnelles (lecture seule)
│   ├── Carrière (historique)
│   ├── Alertes (fin période essai, visite médicale, CPF)
│   └── Demander une modification
└── Layout employé (nav simplifiée, responsive)

Pilotage RH (admin/RH)
├── Dashboard RH (widgets complets)
│   ├── Effectifs (total, actifs, entrées/sorties)
│   ├── Masse salariale (évolution, par département)
│   ├── Absentéisme (taux, par type)
│   ├── Congés (soldes, en attente)
│   ├── Pénibilité (nb exposés, niveau moyen)
│   ├── CPF (solde total, nb employés avec solde)
│   ├── Carrières (dernières promotions/transferts)
│   ├── Documents RH (nb, taux distribution)
│   ├── Requêtes RH (nb en attente, temps moyen)
│   ├── Titres restaurant (total mensuel)
│   ├── Sorties (prévues, soldes de tout compte en cours)
│   ├── Arrêts de travail (en cours, IJSS)
│   └── Visites médicales (à planifier, en retard)
├── Reportings
│   ├── Évolution des effectifs (graphique)
│   ├── Analyse rémunérations (par catégorie, genre, ancienneté)
│   ├── Coûts par centre (analytique)
│   ├── Taux d'absentéisme (par département, par type)
│   └── Export Excel
└── Tableaux de bord pré-paramétrés
```

### Fonctionnalités Sage 100 couvertes (recherche internet)
- **Sage Espace Employés** : portail collaboratif self-service
  - Gestion des congés et absences (de la demande à l'envoi en paie)
  - Dossier salarié centralisé
  - Planning de congés partagé en temps réel
  - Entretiens et objectifs
  - Notes de frais
  - Coffre-fort documents
  - Export en un clic des données vers la paie
- **Pilotage et reporting RH** :
  - Tableaux de bord temps réel
  - Masse salariale, analyse rémunérations
  - Suivi effectifs, coûts par centre
  - Évolution des effectifs
  - Taux d'absentéisme
  - Indicateurs égalité F/H
  - BDES / Bilan social
  - Construction d'états depuis Excel
- **Personnalisation des écrans**
- **Modification en masse** des fiches de personnel
- **Import Excel** / **Publipostage Word**

---

## H.2 SQL — Nouvelles tables

### `rh_dashboard_configs` (Configuration des tableaux de bord)
```sql
CREATE TABLE IF NOT EXISTS rh_dashboard_configs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  user_email text NOT NULL,
  dashboard_type text NOT NULL,         -- 'hr_admin'|'manager'|'employee'
  widgets jsonb DEFAULT '[]',           -- [{widget: 'effectifs', position: 1, size: 'large'}, ...]
  filters jsonb DEFAULT '{}',           -- filtres par défaut
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(user_email, dashboard_type)
);
ALTER TABLE rh_dashboard_configs ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_rh_dashboard_configs') THEN
    CREATE POLICY "allow_all_rh_dashboard_configs" ON rh_dashboard_configs FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `rh_reports` (Reportings sauvegardés)
```sql
CREATE TABLE IF NOT EXISTS rh_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  report_type text NOT NULL,            -- 'effectifs'|'remuneration'|'absenteeism'|'turnover'|'training'|'costs'|'custom'
  parameters jsonb DEFAULT '{}',        -- filtres, groupBy, période, etc.
  chart_type text,                      -- 'bar'|'line'|'pie'|'table'|'mixed'
  data jsonb,                           -- données calculées (cache)
  data_calculated_at timestamptz,
  created_by text,
  shared boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_rh_reports_type ON rh_reports(report_type);
ALTER TABLE rh_reports ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_rh_reports') THEN
    CREATE POLICY "allow_all_rh_reports" ON rh_reports FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `employee_activity_logs` (Timeline d'activité employé)
```sql
CREATE TABLE IF NOT EXISTS employee_activity_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  activity_type text NOT NULL,          -- 'leave_request'|'leave_approved'|'leave_rejected'|'expense_submitted'|'expense_approved'|'document_received'|'document_signed'|'interview_scheduled'|'objective_updated'|'contract_change'|'salary_change'
  description text,
  metadata jsonb DEFAULT '{}',
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_activity_logs_employee ON employee_activity_logs(employee_id);
CREATE INDEX IF NOT EXISTS idx_activity_logs_date ON employee_activity_logs(created_at);
ALTER TABLE employee_activity_logs ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_employee_activity_logs') THEN
    CREATE POLICY "allow_all_employee_activity_logs" ON employee_activity_logs FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

---

## H.3 Types TypeScript

```typescript
export interface RhDashboardConfig {
  id: string
  tenant_id: string | null
  user_email: string
  dashboard_type: 'hr_admin' | 'manager' | 'employee'
  widgets: { widget: string; position: number; size: 'small' | 'medium' | 'large' }[]
  filters: Record<string, any>
  created_at: string
  updated_at: string
}

export interface RhReport {
  id: string
  tenant_id: string | null
  name: string
  report_type: 'effectifs' | 'remuneration' | 'absenteeism' | 'turnover' | 'training' | 'costs' | 'custom'
  parameters: Record<string, any>
  chart_type: string | null
  data: any
  data_calculated_at: string | null
  created_by: string | null
  shared: boolean
  created_at: string
}

export interface EmployeeActivityLog {
  id: string
  tenant_id: string | null
  employee_id: string
  activity_type: string
  description: string | null
  metadata: Record<string, any>
  created_at: string
}
```

---

## H.4 Queries

```typescript
// ============ Employee Dashboard ============
export async function getEmployeeDashboardData()
// Récupère toutes les données pour le dashboard employé :
// - soldes de congés (CP, RTT, récupération)
// - demandes en attente
// - montant notes de frais en attente
// - prochain entretien
// - activité récente (10 dernières actions)
// - planning congés du mois

// ============ Employee Profile (self-service) ============
export async function getMyProfile()
// Profil complet de l'employé connecté
export async function updateMyProfile(updates: any)
// Champs modifiables selon droits (address, phone, emergency_contact, photo)
export async function getEmployeeFieldsConfig()
// Config des champs visibles/modifiables
export async function requestProfileChange(field: string, newValue: string, reason: string)
// Soumet une demande de modification pour validation RH

// ============ Employee Alerts ============
export async function getEmployeeAlerts(employeeId: string)
// Alertes : fin de période d'essai dans X jours, visite médicale à planifier,
// formation CPF disponible, CPF expirant, convention collective modifiée

// ============ Employee Activity ============
export async function getMyActivity(limit?: number)
// Timeline des dernières actions de l'employé connecté
export async function logEmployeeActivity(employeeId: string, type: string, description: string, metadata?: any)
// Enregistre une activité (appelé automatiquement par les autres queries)

// ============ RH Dashboard ============
export async function getRhDashboardData()
// Récupère toutes les données pour le dashboard RH :
// - effectifs (total, actifs, entrées du mois, sorties du mois)
// - masse salariale (mois courant, évolution 6 mois)
// - absentéisme (taux, par type)
// - congés (nb en attente, nb approuvés ce mois)
// - pénibilité (nb exposés, niveau moyen)
// - CPF (solde total, nb employés avec solde)
// - carrières (dernières promotions/transferts)
// - documents RH (nb, taux distribution, taux accusé)
// - requêtes RH (nb en attente, temps moyen)
// - titres restaurant (total mensuel)
// - sorties (prévues, soldes de tout compte en cours)
// - arrêts de travail (en cours, IJSS)
// - visites médicales (à planifier, en retard)

// ============ RH Reports ============
export async function getRhReports(type?: string)
export async function createRhReport(data: Omit<RhReport, 'id' | 'created_at'>)
export async function calculateReportData(reportId: string)
// Calcule les données du rapport selon les paramètres
export async function exportReportExcel(reportId: string)
// Export Excel du rapport

// ============ RH Statistics ============
export async function getEffectifEvolution(months: number)
// Évolution des effectifs sur X mois (entrées, sorties, net)
export async function getSalaryAnalysis(groupBy: 'department' | 'category' | 'gender' | 'age_range')
// Analyse des rémunérations par dimension
export async function getAbsenceStats(groupBy: 'department' | 'type' | 'month')
// Statistiques d'absentéisme
export async function getTurnoverRate(period: string)
// Taux de rotation (turnover)
export async function getTrainingStats(year: number)
// Statistiques de formation
export async function getCostByCenter(period: string)
// Coûts par centre de coût (analytique)

// ============ Dashboard Config ============
export async function getDashboardConfig(dashboardType: string)
export async function updateDashboardConfig(id: string, updates: Partial<RhDashboardConfig>)
```

---

## H.5 Pages

### `EmployeeDashboardPage.tsx` (nouveau — self-service)
**Fichier** : `@/pages/employee/EmployeeDashboardPage.tsx`

**Structure :**
- **Carte "Mes congés"** : solde CP, RTT, récupération avec barres de progression visuelles
  - Acquis, Pris, En attente, Restant pour chaque type
  - Code couleur par type de congé
- **Carte "Demandes en attente"** : nombre de demandes de congé en cours
  - Lien rapide "Voir mes demandes"
- **Carte "Notes de frais"** : montant total en attente de remboursement
  - Lien rapide "Voir mes notes de frais"
- **Carte "Prochains entretiens"** : date du prochain entretien, type
  - Lien rapide "Voir mes entretiens"
- **Section "Activité récente"** : timeline des dernières actions
  - Congé approuvé, document reçu, note de frais soumise, etc.
  - Icône + description + date pour chaque activité
- **Section "Planning congés"** : mini-calendrier du mois courant
  - Congés visualisés (couleur par type)
  - Jours fériés affichés
  - Navigation mois précédent/suivant
- **Bouton "Nouvelle demande de congé"** (raccourci)
- **Bouton "Nouvelle note de frais"** (raccourci)
- `useTranslation('employee')`

### `EmployeeProfilePage.tsx` (nouveau — self-service)
**Fichier** : `@/pages/employee/EmployeeProfilePage.tsx`

**Structure :**
- **Section "Informations personnelles"** (modifiable selon droits) :
  - Photo (upload, avec prévisualisation)
  - Nom, prénom (lecture seule)
  - Date de naissance, lieu de naissance (lecture seule)
  - Nationalité (lecture seule)
  - Numéro de sécurité sociale (lecture seule)
  - Adresse, code postal, ville, pays (modifiable selon config)
  - Téléphone, email (modifiable selon config)
  - Contact d'urgence : nom, téléphone, relation (modifiable)
  - Situation familiale, nombre d'enfants à charge (lecture seule)
  - Bouton "Enregistrer" pour les champs modifiables
- **Section "Informations professionnelles"** (lecture seule) :
  - Poste, département, manager
  - Date d'embauche, type de contrat, date de fin (si CDD)
  - Salaire (si visible selon config)
  - Titres restaurant (nombre, valeur)
  - Frais de transport (mode, montant)
  - Coordonnées bancaires (IBAN, BIC — modifiable selon config)
  - Convention collective
  - Médecine du travail (prochain examen)
- **Section "Carrière"** :
  - Timeline visuelle des événements de carrière
  - Embauche, promotions, mobilités, changements de salaire
  - Ancien poste → Nouveau poste, dates
- **Section "Alertes"** :
  - Fin de période d'essai dans X jours (badge warning)
  - Visite médicale à planifier (badge info)
  - Formation CPF disponible (badge success)
  - CPF expirant (badge warning)
- **Bouton "Demander une modification"** :
  - Modal : champ concerné, nouvelle valeur, motif
  - Soumet une demande qui sera validée par les RH
- `useTranslation('employee')`

### `EmployeeLeavesPage.tsx` (nouveau — self-service)
**Fichier** : `@/pages/employee/EmployeeLeavesPage.tsx`

**Structure :**
- **Onglet 1 : "Mes demandes"**
  - Table : Type, Date début, Date fin, Jours, Statut, Actions
  - Bouton "Nouvelle demande" → modal de création :
    - Type de congé (select, depuis leave_rules actifs)
    - Date début (date picker)
    - Date fin (date picker)
    - Demi-journée (checkbox)
    - Justification (textarea, si `requires_justification`)
    - Pièce jointe (upload, si justificatif requis)
    - Affichage automatique du solde disponible pour le type
    - Alerte si délai de prévenance non respecté (`min_notice_days`)
    - Alerte si conflit avec congé existant
    - Alerte si effectif minimum non respecté (astreinte)
  - Bouton "Annuler" sur demande en attente
  - Filtres : statut, type, période
- **Onglet 2 : "Mon solde"**
  - Cartes par type de congé : acquis, pris, en attente, restant, report
  - Barres de progression visuelles
  - Historique des mouvements (acquisition, prise, régularisation)
  - Export Excel
- **Onglet 3 : "Planning"**
  - Vue calendrier (mois/semaine) avec tous les congés de l'équipe
  - Code couleur par type de congé
  - Jours fériés affichés
  - Légende
- `useTranslation('employee')`

### Extension `HRDashboardPage.tsx` (modifier — widgets complets)
**Fichier** : `@/pages/HRDashboardPage.tsx`

**Widgets à ajouter :**
- **Effectifs** : total, actifs, entrées du mois, sorties du mois (cartes avec chiffres)
- **Masse salariale** : montant du mois, évolution 6 mois (mini graphique)
- **Absentéisme** : taux du mois, par type (maladie, CP, RTT, autre)
- **Congés** : nb demandes en attente, nb approuvés ce mois
- **Pénibilité** : nb employés exposés, niveau moyen (badges par type)
- **CPF** : solde total (heures), nb employés avec solde, alertes
- **Carrières** : dernières promotions/transferts (table récente)
- **Documents RH** : nb documents, taux distribution, taux accusé (graphique)
- **Requêtes RH** : nb en attente, temps moyen de traitement, taux de résolution
- **Titres restaurant** : total mensuel, nb employés éligibles
- **Sorties** : sorties prévues, soldes de tout compte en cours
- **Arrêts de travail** : nb en cours, IJSS en attente d'intégration
- **Visites médicales** : à planifier, en retard
- **Personnalisation** : drag & drop des widgets, sauvegarde de la configuration
- `useTranslation('hr')`

### `RhReportsPage.tsx` (nouveau — admin/RH)
**Fichier** : `@/pages/hr/RhReportsPage.tsx`

**Structure :**
- **Onglet 1 : "Rapports pré-paramétrés"**
  - Cartes pour chaque type de rapport :
    - **Évolution des effectifs** : graphique ligne (entrées/sorties/net sur 12 mois)
    - **Analyse rémunérations** : table groupée par département/catégorie/genre/âge
    - **Taux d'absentéisme** : graphique barres par département/type/mois
    - **Taux de rotation** : turnover par période
    - **Statistiques formation** : heures, budget, accès par employé
    - **Coûts par centre** : analytique par centre de coût
  - Bouton "Générer" sur chaque rapport
  - Bouton "Export Excel"
  - Filtres : période, département, catégorie
- **Onglet 2 : "Rapports sauvegardés"**
  - Table des rapports créés par les utilisateurs
  - Bouton "Exécuter" (recalcule les données)
  - Bouton "Partager" (rend visible à toute l'équipe RH)
  - Bouton "Supprimer"
- **Onglet 3 : "Créer un rapport"**
  - Sélection du type de données (effectifs, salaires, absences, etc.)
  - Filtres (période, département, catégorie, genre)
  - GroupBy (département, catégorie, genre, âge, mois)
  - Type de graphique (barres, ligne, camembert, table)
  - Bouton "Prévisualiser"
  - Bouton "Sauvegarder"
- `useTranslation('hr')`

---

# SPRINT I : PWA Mobile & Responsive (2-3j)

## I.1 Vue d'ensemble

```
PWA (Progressive Web App)
├── Manifest.json (icônes, shortcuts)
├── Service Worker (cache offline, sync arrière-plan)
├── Composants mobiles
│   ├── MobileLeaveRequest (congés simplifié)
│   ├── MobileExpenseCapture (photo + OCR)
│   └── MobileApproval (swipe approve/reject)
└── Responsive design (toutes pages employee)
    ├── Navigation bottom bar (mobile)
    ├── Cards empilables
    ├── Tables scrollables horizontalement
    └── Modals plein écran (mobile)
```

### Fonctionnalités Sage 100 couvertes
- **Sage Espace Employés** : application mobile disponible sur Apple Store et Google Play
  - Visualiser le planning et le solde des congés
  - Consulter les soldes de congés
  - Saisir une absence ou un congé
  - Valider les demandes de congés (manager)
  - Accessible PC, MAC, Tablette, Smartphone
- **Notes de frais mobile** : scan des justificatifs en quelques secondes
- **Notifications push** : rappels, demandes en attente

---

## I.2 Configuration PWA

### `public/manifest.json` (modifier)
```json
{
  "name": "Compta - Espace Employés",
  "short_name": "Espace RH",
  "description": "Portail employé : congés, notes de frais, documents",
  "icons": [
    { "src": "/icons/employee-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/icons/employee-512.png", "sizes": "512x512", "type": "image/png" }
  ],
  "shortcuts": [
    { "name": "Mes congés", "url": "/employee/leaves", "icons": [{ "src": "/icons/leave-96.png", "sizes": "96x96" }] },
    { "name": "Note de frais", "url": "/employee/expenses", "icons": [{ "src": "/icons/expense-96.png", "sizes": "96x96" }] },
    { "name": "Mes documents", "url": "/employee/documents", "icons": [{ "src": "/icons/docs-96.png", "sizes": "96x96" }] }
  ],
  "start_url": "/employee",
  "display": "standalone",
  "orientation": "portrait",
  "theme_color": "#3b82f6",
  "background_color": "#ffffff"
}
```

### `public/sw.js` (modifier — Service Worker)
- Cache des pages employee pour accès hors connexion
- Stratégie : Cache First pour les pages statiques, Network First pour les données API
- Sync en arrière-plan pour les notes de frais hors ligne
- Notification push pour les approbations

---

## I.3 Composants mobiles

### `MobileLeaveRequest.tsx` (nouveau)
**Fichier** : `@/components/employee/MobileLeaveRequest.tsx`

**Structure :**
- Interface simplifiée pour poser un congé depuis mobile
- Date picker natif (input type="date")
- Sélection du type de congé (boutons larges, pas de select)
- Affichage du solde en temps réel (grand texte)
- Alerte visuelle si solde insuffisant
- Alerte si prévenance non respectée
- Bouton "Confirmer" en bas (sticky)
- Animation de confirmation (checkmark)
- `useTranslation('employee')`

### `MobileExpenseCapture.tsx` (nouveau)
**Fichier** : `@/components/employee/MobileExpenseCapture.tsx`

**Structure :**
- Capture photo du justificatif (input type="file" accept="image/*" capture="environment")
- Prévisualisation de la photo
- **OCR côté client** (Tesseract.js) : extraction automatique
  - Date (regex)
  - Montant total (regex)
  - Taux TVA (détection)
  - Fournisseur (heuristique)
- Saisie rapide : catégorie (boutons larges), description, montant
- Mode hors connexion : stockage local (localStorage/IndexedDB) + sync au retour
- Indicateur de sync (en attente / synchronisé)
- `useTranslation('employee')`

### `MobileApproval.tsx` (nouveau — manager)
**Fichier** : `@/components/employee/MobileApproval.tsx`

**Structure :**
- Interface manager pour valider congés et notes de frais depuis mobile
- **Cards empilables** (style Tinder) :
  - Card de demande : employé, type, dates, montant, détails
  - Swipe left = rejeter, swipe right = approuver
  - Boutons "Approuver" / "Rejeter" en bas (alternative au swipe)
- Commentaire obligatoire pour le rejet (modal)
- Compteur de demandes en attente (badge)
- Animation de transition entre cards
- `useTranslation('employee')`

---

## I.4 Responsive design

### Toutes les pages employee — adaptations responsive avec TailwindCSS :

| Élément | Desktop | Mobile |
|---|---|---|
| Navigation | Sidebar gauche | Bottom bar (fixed) |
| Tables | Table complète | Scroll horizontal + cards |
| Modals | Centered, max-width | Plein écran |
| Formulaires | 2-3 colonnes | 1 colonne |
| Cartes dashboard | Grid 4 colonnes | Grid 1-2 colonnes |
| Calendrier | Vue mois complète | Vue semaine + navigation |
| Boutons | Texte + icône | Icône seule (FAB) |

### Breakpoints TailwindCSS utilisés :
- `sm:` (640px) — téléphones en paysage
- `md:` (768px) — tablettes
- `lg:` (1024px) — desktop
- `xl:` (1280px) — grand desktop

---

# SPRINT J : i18n Complet — fr, en, ar (RTL) (2j)

## J.1 Vue d'ensemble

```
i18n complet RH & Paie
├── Namespace 'employee' (nouveau)
│   ├── dashboard (titre, cartes, activité, planning)
│   ├── leaves (demandes, solde, planning, types, statuts)
│   ├── profile (personnel, professionnel, carrière, alertes)
│   ├── expenses (notes de frais, lignes, OCR, statuts)
│   ├── interviews (entretiens, objectifs, campagnes)
│   ├── documents (coffre-fort, types, distribution)
│   └── nav (navigation espace employé)
├── Namespace 'hr' (extension massive)
│   ├── contracts, collectiveAgreements, bulkModification, employeeFields
│   ├── leaveBalances, leaveRules, publicHolidays, approvalWorkflows, leavePlanning, staffRequirements
│   ├── workStoppages, ijss, hardship, cpf, career, medical
│   ├── exit, expenseCategories, expenseLines, campaigns, objectives
│   ├── declarations, bdes, honorarium
│   ├── demat, requests, knowledgeBase
│   └── dashboard, reports
├── Namespace 'payroll' (extension)
│   ├── preparation, mealVouchers, sepa, slipTypes, reverseCalc
│   ├── clarified, analytic, advances, recalls
│   └── regularizations, connectImport, csvExport
└── Namespace 'nav' (extension)
    └── Toutes les nouvelles clés de navigation
```

---

## J.2 Namespace `employee` (nouveau — 3 langues)

**Fichiers** : `@/i18n/locales/{fr,en,ar}/employee.json` (nouveaux)

### Structure complète des clés

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
    "leavePlanning": "Planning congés",
    "newLeaveRequest": "Nouvelle demande de congé",
    "newExpenseReport": "Nouvelle note de frais",
    "acquired": "Acquis",
    "taken": "Pris",
    "pending": "En attente",
    "remaining": "Restant"
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
    "status": {
      "pending": "En attente",
      "approved": "Approuvé",
      "rejected": "Rejeté",
      "cancelled": "Annulé"
    },
    "types": {
      "annual": "Congés payés",
      "rtt": "RTT",
      "recovery": "Récupération",
      "sick": "Maladie",
      "unpaid": "Sans solde",
      "maternity": "Maternité",
      "paternity": "Paternité",
      "special": "Congé spécial",
      "other": "Autre"
    },
    "acquired": "Acquis",
    "taken": "Pris",
    "pending": "En attente",
    "remaining": "Restant",
    "carryOver": "Report",
    "managerApprovals": "Validations manager",
    "approve": "Approuver",
    "reject": "Rejeter",
    "managerComment": "Commentaire",
    "exportExcel": "Export Excel"
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
    "emergencyPhone": "Téléphone d'urgence",
    "emergencyRelation": "Relation",
    "maritalStatus": "Situation familiale",
    "dependents": "Personnes à charge",
    "bankDetails": "Coordonnées bancaires",
    "iban": "IBAN",
    "bic": "BIC",
    "bankAccountHolder": "Titulaire du compte",
    "transportMode": "Mode de transport",
    "transportCost": "Frais de transport",
    "mealVouchers": "Titres restaurant",
    "manager": "Manager",
    "hireDate": "Date d'embauche",
    "position": "Poste",
    "department": "Département",
    "contractType": "Type de contrat",
    "contractEndDate": "Fin de contrat",
    "collectiveAgreement": "Convention collective",
    "medicalExam": "Prochain examen médical",
    "save": "Enregistrer",
    "changeField": "Champ à modifier",
    "newValue": "Nouvelle valeur",
    "reason": "Motif",
    "trialPeriodWarning": "Fin de période d'essai dans {{days}} jours",
    "medicalExamWarning": "Visite médicale à planifier",
    "cpfAvailable": "Formation CPF disponible",
    "cpfExpiring": "CPF expirant bientôt"
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
    "amountHt": "Montant HT",
    "vatRate": "Taux TVA",
    "vatAmount": "Montant TVA",
    "amountTtc": "Montant TTC",
    "receipt": "Justificatif",
    "uploadReceipt": "Télécharger le justificatif",
    "capturePhoto": "Prendre une photo",
    "ocrProcessing": "Extraction automatique...",
    "ocrSuccess": "Données extraites avec succès",
    "ocrFailed": "Extraction échouée, saisie manuelle requise",
    "ceilingExceeded": "Plafond dépassé pour cette catégorie",
    "status": {
      "draft": "Brouillon",
      "submitted": "Soumise",
      "approved": "Approuvée",
      "rejected": "Rejetée",
      "reimbursed": "Remboursée"
    },
    "managerApprovals": "Validations manager",
    "approve": "Approuver",
    "reject": "Rejeter",
    "managerComment": "Commentaire",
    "markReimbursed": "Marquer remboursé",
    "generateAccounting": "Générer écritures comptables",
    "pendingReimbursement": "En attente de remboursement",
    "offlineMode": "Hors ligne — synchronisation au retour",
    "synced": "Synchronisé"
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
    "objectives": {
      "title": "Objectifs",
      "target": "Cible",
      "progress": "Progression",
      "period": "Période",
      "frequency": "Fréquence",
      "updateProgress": "Mettre à jour",
      "status": {
        "active": "Actif",
        "achieved": "Atteint",
        "missed": "Manqué",
        "cancelled": "Annulé"
      }
    },
    "types": {
      "annual": "Annuel",
      "mid_year": "Mi-année",
      "professional": "Professionnel",
      "exit": "Fin de mission",
      "other": "Autre"
    },
    "campaigns": {
      "title": "Campagnes",
      "new": "Nouvelle campagne",
      "launch": "Lancer",
      "close": "Clôturer",
      "remind": "Relancer",
      "progress": "Avancement"
    }
  },
  "documents": {
    "title": "Mes documents",
    "coffreFort": "Coffre-fort",
    "type": "Type",
    "uploadDate": "Date",
    "download": "Télécharger",
    "acknowledge": "Accuser réception",
    "sign": "Signer",
    "types": {
      "payslip": "Bulletin de paie",
      "contract": "Contrat",
      "dpae": "DPAE",
      "dsn": "DSN",
      "certificate": "Certificat",
      "work_certificate": "Certificat de travail",
      "settlement_receipt": "Reçu pour solde de tout compte",
      "pole_emploi_attestation": "Attestation Pôle Emploi",
      "medical_cert": "Certificat médical",
      "other": "Autre"
    },
    "distribution": "Distribution bulletins",
    "distribute": "Distribuer",
    "batchControl": "Contrôle de lot",
    "statistics": "Statistiques",
    "totalDocuments": "Documents totaux",
    "distributedPayslips": "Bulletins distribués",
    "acknowledgmentRate": "Taux d'accusé de réception",
    "lastConnection": "Dernière connexion"
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
  },
  "approvals": {
    "title": "Validations",
    "leaveApprovals": "Demandes de congé",
    "expenseApprovals": "Notes de frais",
    "pending": "En attente",
    "approved": "Approuvé",
    "rejected": "Rejeté",
    "swipeApprove": "Glisser à droite pour approuver",
    "swipeReject": "Glisser à gauche pour rejeter",
    "commentRequired": "Commentaire obligatoire pour le rejet"
  },
  "common": {
    "loading": "Chargement...",
    "noData": "Aucune donnée",
    "error": "Une erreur est survenue",
    "save": "Enregistrer",
    "cancel": "Annuler",
    "confirm": "Confirmer",
    "delete": "Supprimer",
    "edit": "Modifier",
    "close": "Fermer",
    "yes": "Oui",
    "no": "Non"
  }
}
```

**Note** : Les versions `en` et `ar` suivent la même structure avec les traductions respectives. La version `ar` utilise le RTL (right-to-left) configuré dans i18n.

---

## J.3 Namespace `hr` — clés finales (synthèse)

Toutes les clés des Sprints A à H (déjà détaillées dans les Parties 1-4) doivent être présentes dans `hr.json` pour les 3 langues :

| Section | Sprint | Nb clés estimé |
|---|---|---|
| `contracts.*` | A | ~40 |
| `collectiveAgreements.*` | A | ~20 |
| `bulkModification.*` | A | ~20 |
| `employeeFields.*` | A | ~15 |
| `employees.*` (ajouts) | A | ~30 |
| `employeeRole.*` | A | ~10 |
| `leaveBalances.*` | B | ~20 |
| `leaveRules.*` | B | ~20 |
| `publicHolidays.*` | B | ~15 |
| `approvalWorkflows.*` | B | ~10 |
| `leavePlanning.*` | B | ~10 |
| `staffRequirements.*` | B | ~10 |
| `leaveRequests.*` (ajouts) | B | ~15 |
| `workStoppages.*` | D | ~35 |
| `ijss.*` | D | ~15 |
| `hardship.*` | D | ~20 |
| `cpf.*` | D | ~20 |
| `career.*` | D | ~15 |
| `medical.*` | D | ~20 |
| `exit.*` | E | ~30 |
| `expenseCategories.*` | E | ~10 |
| `expenseLines.*` | E | ~15 |
| `campaigns.*` | E | ~15 |
| `objectives.*` | E | ~15 |
| `interviews.*` (ajouts) | E | ~10 |
| `declarations.*` | F | ~40 |
| `bdes.*` | F | ~15 |
| `honorarium.*` | F | ~10 |
| `demat.*` | G | ~25 |
| `requests.*` | G | ~15 |
| `knowledgeBase.*` | G | ~10 |
| `dashboard.*` | H | ~30 |
| `reports.*` | H | ~20 |
| **Total estimé** | | **~650 clés** |

---

## J.4 Namespace `payroll` — clés finales (synthèse)

| Section | Sprint | Nb clés estimé |
|---|---|---|
| `preparation.*` | C | ~25 |
| `mealVouchers.*` | C | ~20 |
| `sepa.*` | C | ~15 |
| `slipTypes.*` | C | ~5 |
| `reverseCalc.*` | C | ~10 |
| `clarified.*` | C | ~10 |
| `analytic.*` | C | ~5 |
| `advances.*` (ajouts) | C | ~5 |
| `recalls.*` (ajouts) | C | ~5 |
| `regularization.*` | C | ~5 |
| `connectImport.*` | C | ~5 |
| `csvExport.*` | C | ~5 |
| **Total estimé** | | **~120 clés** |

---

## J.5 Namespace `nav` — clés finales (synthèse)

Toutes les nouvelles clés de navigation (déjà détaillées dans les Parties 1-4) :

| Clé | Sprint |
|---|---|
| `employeeContracts`, `collectiveAgreements`, `bulkModification`, `employeeFieldsConfig` | A |
| `employeeSpace`, `employeeDashboard`, `employeeLeaves`, `employeeProfile`, `employeeExpenses`, `employeeInterviews`, `employeeDocuments` | A |
| `leaveBalances`, `leavePlanning`, `leaveRules`, `payrollPreparation`, `mealVouchers`, `sepaPayments`, `managerApprovals` | B+C |
| `workStoppages`, `hardship`, `cpf`, `career`, `medical`, `employeeExit`, `interviewCampaigns`, `expenseCategories` | D+E |
| `socialDeclarations`, `bdes`, `documentManagement`, `rhRequests`, `knowledgeBase` | F+G |
| `rhReports` | H |
| **Total** | **~30 clés** |

---

## J.6 Configuration i18n (`index.ts`)

### Enregistrement du namespace `employee`

**Fichier** : `@/i18n/index.ts` (modifier)

```typescript
// Ajouter les imports
import frEmployee from './locales/fr/employee.json'
import enEmployee from './locales/en/employee.json'
import arEmployee from './locales/ar/employee.json'

// Ajouter dans les namespaces
'common', 'nav', 'auth', 'sales', 'purchases', 'accounting',
'banking', 'treasury', 'stock', 'production', 'hr', 'payroll', 'assets',
'reports', 'settings', 'errors', 'features', 'crm', 'pos', 'demat',
'employee',  // <-- nouveau

// Ajouter dans les resources
// fr:
employee: frEmployee,
// en:
employee: enEmployee,
// ar:
employee: arEmployee,
```

---

## J.7 Audit i18n complet

### Checklist d'audit (à exécuter après implémentation)

- [ ] **Namespace `employee`** : créé dans fr/en/ar avec toutes les clés
- [ ] **Namespace `hr`** : étendu dans fr/en/ar avec toutes les clés des Sprints A-H
- [ ] **Namespace `payroll`** : étendu dans fr/en/ar avec toutes les clés du Sprint C
- [ ] **Namespace `nav`** : étendu dans fr/en/ar avec toutes les nouvelles clés
- [ ] **`i18n/index.ts`** : namespace `employee` enregistré pour les 3 langues
- [ ] **Toutes les nouvelles pages** utilisent `useTranslation` avec le bon namespace
- [ ] **Aucune chaîne hardcodée** dans les nouvelles pages (vérification grep)
- [ ] **RTL** : le namespace `ar` est correct et le RTL s'applique automatiquement
- [ ] **Clés orphelines** : aucune clé i18n non utilisée dans le code
- [ ] **Clés manquantes** : aucune clé utilisée dans le code mais absente des JSON
- [ ] **Cohérence** : les mêmes clés existent dans fr, en et ar

### Commandes d'audit
```bash
# Vérifier qu'aucune chaîne française est hardcodée dans les nouvelles pages
grep -r "['\"][A-ZÀ-Ý][a-zà-ÿ]" app/src/pages/hr/ app/src/pages/employee/ --include="*.tsx" | grep -v "useTranslation\|import\|//\|t('" | head -50

# Vérifier que tous les fichiers employee.json existent
ls -la app/src/i18n/locales/{fr,en,ar}/employee.json

# Vérifier la structure des namespaces
node -e "const fr = require('./app/src/i18n/locales/fr/employee.json'); console.log(Object.keys(fr))"

# tsc --noEmit
cd app && npx tsc --noEmit --pretty
```

---

## J.8 Routes App.tsx — synthèse complète

```tsx
{/* ============ RH Admin ============ */}
<Route path="/hr/contracts" element={<EmployeeContractsPage />} />
<Route path="/hr/collective-agreements" element={<CollectiveAgreementsPage />} />
<Route path="/hr/bulk-modify" element={<BulkModificationPage />} />
<Route path="/hr/leave-balances" element={<LeaveBalancesPage />} />
<Route path="/hr/leave-planning" element={<LeavePlanningPage />} />
<Route path="/hr/payroll-preparation" element={<PayrollPreparationPage />} />
<Route path="/hr/meal-vouchers" element={<MealVouchersPage />} />
<Route path="/hr/sepa-payments" element={<SepaPaymentsPage />} />
<Route path="/hr/work-stoppages" element={<WorkStoppagesPage />} />
<Route path="/hr/hardship" element={<HardshipPage />} />
<Route path="/hr/cpf" element={<CPFPage />} />
<Route path="/hr/career" element={<CareerHistoryPage />} />
<Route path="/hr/medical" element={<MedicalExamsPage />} />
<Route path="/hr/employee-exit" element={<EmployeeExitPage />} />
<Route path="/hr/interview-campaigns" element={<InterviewCampaignsPage />} />
<Route path="/hr/social-declarations" element={<SocialDeclarationsPage />} />
<Route path="/hr/bdes" element={<BdesPage />} />
<Route path="/hr/documents" element={<DocumentManagementPage />} />
<Route path="/hr/rh-requests" element={<RhRequestsPage />} />
<Route path="/hr/knowledge-base" element={<RhKnowledgeBasePage />} />
<Route path="/hr/reports" element={<RhReportsPage />} />

{/* ============ Settings ============ */}
<Route path="/settings/leave-rules" element={<LeaveRulesPage />} />
<Route path="/settings/employee-fields" element={<EmployeeFieldsConfigPage />} />
<Route path="/settings/expense-categories" element={<ExpenseCategoriesPage />} />

{/* ============ Espace Employés ============ */}
<Route path="/employee" element={<EmployeeLayout />}>
  <Route index element={<EmployeeDashboardPage />} />
  <Route path="leaves" element={<EmployeeLeavesPage />} />
  <Route path="profile" element={<EmployeeProfilePage />} />
  <Route path="expenses" element={<EmployeeExpensesPage />} />
  <Route path="interviews" element={<EmployeeInterviewsPage />} />
  <Route path="documents" element={<EmployeeDocumentsPage />} />
  <Route path="manager/approvals" element={<ManagerLeaveApprovalsPage />} />
  <Route path="manager/expense-approvals" element={<ManagerExpenseApprovalsPage />} />
</Route>
```

---

## J.9 Fichiers créés / modifiés (Sprint H+I+J)

### Nouveaux fichiers (10)
1. `@/pages/employee/EmployeeDashboardPage.tsx` — Dashboard employé
2. `@/pages/employee/EmployeeProfilePage.tsx` — Profil self-service
3. `@/pages/employee/EmployeeLeavesPage.tsx` — Congés self-service
4. `@/pages/hr/RhReportsPage.tsx` — Reportings RH
5. `@/components/employee/MobileLeaveRequest.tsx` — Composant mobile congés
6. `@/components/employee/MobileExpenseCapture.tsx` — Composant mobile notes de frais
7. `@/components/employee/MobileApproval.tsx` — Composant mobile approbations
8. `@/i18n/locales/fr/employee.json` — Namespace employee (fr)
9. `@/i18n/locales/en/employee.json` — Namespace employee (en)
10. `@/i18n/locales/ar/employee.json` — Namespace employee (ar)
11. `@/sql/64_sprint_h_pilotage_rh.sql` — Migration SQL

### Fichiers modifiés (10)
- `@/types/index.ts` — nouveaux types (RhDashboardConfig, RhReport, EmployeeActivityLog)
- `@/lib/queries.ts` — nouvelles queries (dashboard, reports, stats, activity)
- `@/App.tsx` — nouvelles routes
- `@/pages/HRDashboardPage.tsx` — widgets complets
- `@/i18n/index.ts` — enregistrement namespace `employee`
- `@/i18n/locales/{fr,en,ar}/hr.json` — extension massive (~650 clés)
- `@/i18n/locales/{fr,en,ar}/payroll.json` — extension (~120 clés)
- `@/i18n/locales/{fr,en,ar}/nav.json` — nouvelles clés (~30 clés)
- `@/public/manifest.json` — PWA config
- `@/public/sw.js` — Service Worker (cache offline, sync)

---

# SYNTHÈSE GLOBALE — PLAN RH & PAIE (5 parties)

## Ordre de mise en œuvre recommandé

| Partie | Sprint | Durée | Dépendances | Priorité |
|---|---|---|---|---|
| **PARTIE 1** | A — Fondations RH | 4-5j | Aucune | 🔴 Bloquant |
| **PARTIE 2** | B — Congés & Absences | 3-4j | A | 🔴 Haute |
| | C — Paie Avancée | 3j | A | 🔴 Haute |
| **PARTIE 3** | D — Admin & Arrêts | 3j | A | 🔴 Haute |
| | E — Sortie & Entretiens | 2-3j | A | 🟡 Moyenne |
| **PARTIE 4** | F — Déclarations Sociales | 3-4j | D | 🟡 Moyenne |
| | G — Dématérialisation | 3j | A | 🔴 Haute |
| **PARTIE 5** | H — Dashboard & Pilotage | 3j | A-G | 🟡 Moyenne |
| | I — PWA Mobile | 2-3j | H | 🟢 Basse |
| | J — i18n | 2j | Tous | 🔴 Obligatoire |

**Total estimé : 28-35 jours de développement**

---

## Liste complète des nouveaux fichiers

### Pages Espace Employé (8)
1. `@/pages/employee/EmployeeDashboardPage.tsx`
2. `@/pages/employee/EmployeeLeavesPage.tsx`
3. `@/pages/employee/EmployeeProfilePage.tsx`
4. `@/pages/employee/EmployeeExpensesPage.tsx`
5. `@/pages/employee/EmployeeInterviewsPage.tsx`
6. `@/pages/employee/EmployeeDocumentsPage.tsx`
7. `@/pages/employee/ManagerLeaveApprovalsPage.tsx`
8. `@/pages/employee/ManagerExpenseApprovalsPage.tsx`

### Pages Admin/RH (19)
9. `@/pages/hr/EmployeeContractsPage.tsx`
10. `@/pages/hr/CollectiveAgreementsPage.tsx`
11. `@/pages/hr/BulkModificationPage.tsx`
12. `@/pages/hr/LeaveBalancesPage.tsx`
13. `@/pages/hr/LeavePlanningPage.tsx`
14. `@/pages/hr/PayrollPreparationPage.tsx`
15. `@/pages/hr/MealVouchersPage.tsx`
16. `@/pages/hr/SepaPaymentsPage.tsx`
17. `@/pages/hr/WorkStoppagesPage.tsx`
18. `@/pages/hr/HardshipPage.tsx`
19. `@/pages/hr/CPFPage.tsx`
20. `@/pages/hr/CareerHistoryPage.tsx`
21. `@/pages/hr/MedicalExamsPage.tsx`
22. `@/pages/hr/EmployeeExitPage.tsx`
23. `@/pages/hr/InterviewCampaignsPage.tsx`
24. `@/pages/hr/SocialDeclarationsPage.tsx`
25. `@/pages/hr/BdesPage.tsx`
26. `@/pages/hr/DocumentManagementPage.tsx`
27. `@/pages/hr/RhRequestsPage.tsx`
28. `@/pages/hr/RhKnowledgeBasePage.tsx`
29. `@/pages/hr/RhReportsPage.tsx`

### Pages Settings (3)
30. `@/pages/settings/LeaveRulesPage.tsx`
31. `@/pages/settings/EmployeeFieldsConfigPage.tsx`
32. `@/pages/settings/ExpenseCategoriesPage.tsx`

### Composants (4)
33. `@/components/EmployeeLayout.tsx`
34. `@/components/employee/MobileLeaveRequest.tsx`
35. `@/components/employee/MobileExpenseCapture.tsx`
36. `@/components/employee/MobileApproval.tsx`

### Locale files (3)
37. `@/i18n/locales/fr/employee.json`
38. `@/i18n/locales/en/employee.json`
39. `@/i18n/locales/ar/employee.json`

### SQL (8)
40. `@/sql/57_sprint_a_rh_fondations.sql`
41. `@/sql/58_sprint_b_leaves_absences.sql`
42. `@/sql/59_sprint_c_payroll_advanced.sql`
43. `@/sql/60_sprint_d_admin_arrets.sql`
44. `@/sql/61_sprint_e_sortie_notes_entretiens.sql`
45. `@/sql/62_sprint_f_social_declarations.sql`
46. `@/sql/63_sprint_g_demat_rh.sql`
47. `@/sql/64_sprint_h_pilotage_rh.sql`

### Fichiers modifiés (~25)
- `@/types/index.ts` — ~30 nouveaux types/interfaces + extensions
- `@/lib/queries.ts` — ~150 nouvelles queries
- `@/lib/auth.tsx` — rôle employee
- `@/lib/supabase.ts` — TENANT_TABLES (~20 nouvelles tables)
- `@/lib/payroll.ts` — calcul à l'envers
- `@/App.tsx` — ~30 nouvelles routes
- `@/components/ProtectedRoute.tsx` — EmployeeRoute
- `@/components/Layout.tsx` — nav espace employé
- `@/pages/EmployeesPage.tsx` — champs étendus + masse + sortie
- `@/pages/LeaveRequestsPage.tsx` — extensions
- `@/pages/PayRunsPage.tsx` — assistant + SEPA
- `@/pages/PaySlipsPage.tsx` — type + distribution + clarifié
- `@/pages/PayrollCalcPage.tsx` — calcul à l'envers + titres resto
- `@/pages/SalaryAdvancesPage.tsx` — SEPA + contrôle + report
- `@/pages/ExpenseReportsPage.tsx` — extensions
- `@/pages/InterviewsPage.tsx` — extensions
- `@/pages/HRDashboardPage.tsx` — widgets complets
- `@/pages/LegalDeclarationsPage.tsx` — liens déclarations
- `@/pages/PayrollArchivePage.tsx` — passation CSV + conformité
- `@/pages/Phase4Pages.tsx` — IntuiDSN (section DSNPage)
- `@/i18n/index.ts` — namespace employee
- `@/i18n/locales/{fr,en,ar}/hr.json` — ~650 clés
- `@/i18n/locales/{fr,en,ar}/payroll.json` — ~120 clés
- `@/i18n/locales/{fr,en,ar}/nav.json` — ~30 clés
- `@/public/manifest.json` — PWA
- `@/public/sw.js` — cache offline

**Total : ~47 nouveaux fichiers + ~25 fichiers modifiés = ~72 fichiers**

---

## Nouvelles tables SQL (synthèse)

| # | Table | Sprint | Description |
|---|---|---|---|
| 1 | `employee_contracts` | A | Multi-contrats par employé |
| 2 | `collective_agreements` | A | Conventions collectives |
| 3 | `employee_fields_config` | A | Personnalisation des écrans |
| 4 | `bulk_modification_logs` | A | Suivi modifications en masse |
| 5 | `leave_balances` | B | Compteurs CP/RTT/récup |
| 6 | `public_holidays` | B | Jours fériés régionalisables |
| 7 | `leave_rules` | B | Règles de congés paramétrables |
| 8 | `approval_workflows` | B | Workflows de validation |
| 9 | `leave_provisions` | B | Provisions de congés payés |
| 10 | `staff_requirements` | B | Astreintes / effectif minimum |
| 11 | `meal_voucher_config` | C | Titres restaurant config |
| 12 | `payroll_variable_elements` | C | Éléments variables de paie |
| 13 | `sepa_payment_orders` | C | Ordres de paiement SEPA |
| 14 | `pay_slip_clarified` | C | Double stockage bulletins |
| 15 | `work_stoppages` | D | Arrêts de travail + IJSS |
| 16 | `ijss_history` | D | Historique IJSS par arrêt |
| 17 | `work_hardship_records` | D | Pénibilité C3P |
| 18 | `cpf_accounts` | D | Compte CPF par employé |
| 19 | `cpf_transactions` | D | Historique utilisations CPF |
| 20 | `career_history` | D | Suivi des carrières |
| 21 | `medical_exams` | D | Médecine du travail |
| 22 | `expense_categories` | D | Catégories de dépenses |
| 23 | `expense_report_lines` | D | Lignes de notes de frais |
| 24 | `interview_campaigns` | D | Campagnes d'entretiens |
| 25 | `employee_objectives` | D | Objectifs individuels |
| 26 | `employee_exit_processes` | E | Suivi des sorties |
| 27 | `social_declarations` | F | Toutes déclarations sociales |
| 28 | `cice_config` | F | Paramétrage CICE |
| 29 | `pas_rates` | F | Taux prélèvement à la source |
| 30 | `at_rates` | F | Taux accidents du travail |
| 31 | `bdes_indicators` | F | BDES / bilan social |
| 32 | `honorarium_records` | F | Gestion des honoraires |
| 33 | `employee_documents` | G | Coffre-fort électronique |
| 34 | `document_distribution_logs` | G | Pilotage distribution |
| 35 | `rh_requests` | G | Requêtes RH |
| 36 | `rh_knowledge_base` | G | Base de connaissances RH |
| 37 | `rh_dashboard_configs` | H | Config tableaux de bord |
| 38 | `rh_reports` | H | Reportings sauvegardés |
| 39 | `employee_activity_logs` | H | Timeline d'activité |

**Total : 39 nouvelles tables SQL**
