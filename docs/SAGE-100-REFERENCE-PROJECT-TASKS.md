# Odoo Project Management & Task Management — Référence Complète

> Source: odoo.com (documentation 19.0 + features page + forum technique)

## 1. Vue d'ensemble

Odoo Project = gestion de projet AI-native basée sur Kanban.

**Entités:** Projet (project.project), Tâche (project.task), Stage (project.task.type), Statut (5 fixes), Sous-tâche, Jalon (project.milestone), Dépendance, Tags (project.tags).

---

## 2. Modèle project.project

### Champs principaux
- `name` (Char, requis) — Nom du projet
- `active` (Boolean) — Actif/archivé
- `sequence` (Integer) — Ordre Kanban
- `color` (Integer) — Couleur carte
- `partner_id` (M2O→res.partner) — Client (billable)
- `user_id` (M2O→res.users) — Chef de projet
- `company_id` (M2O→res.company) — Société
- `date_start` (Date) — Début planifié
- `date` (Date) — Fin planifiée
- `tag_ids` (M2M→project.tags) — Tags
- `favorite_user_ids` (M2M→res.users) — Favoris

### Settings (onglet Settings)
- `allow_billable` (Boolean) — Projet facturable
- `allow_timesheets` (Boolean) — Timesheets activés
- `allow_subtasks` (Boolean) — Sous-tâches activées
- `allow_recurrent_tasks` (Boolean) — Tâches récurrentes
- `allow_milestones` (Boolean) — Jalons
- `allow_task_dependencies` (Boolean) — Dépendances

### Visibilité
- `privacy_visibility` (Selection): `followers` (privé), `employees` (tous internes), `portal` (public, défaut)

### Champs calculés (dashboard)
- `task_count` — Nombre total tâches
- `allocated_hours` — Heures allouées
- `total_hours_spent` — Total (timesheets + sous-tâches)
- `remaining_hours` — Restantes
- `progress` — % complétion

### Alias email
- `alias_id` (M2O→mail.alias) — Alias pour création auto
- `alias_name` (Char) — Partie avant @
- `alias_domain` (Char) — Domaine

---

## 3. Modèle project.task

### Champs principaux
- `name` (Char, required) — Titre
- `active` (Boolean) — Actif/archivé
- `description` (Html) — Rich text
- `priority` (Selection) — `0` normal, `1` haute (étoile jaune)
- `color` (Integer) — Couleur
- `sequence` (Integer) — Ordre Kanban
- `state` (Selection) — `in_progress`, `changes_requested`, `approved`, `canceled`, `done`
- `display_in_project` (Boolean) — Afficher dans projet
- `display_project_id` (M2O→project.project) — Projet affichage (sous-tâches cross-project)

### Relations
- `project_id` (M2O→project.project) — Projet (vide = privée)
- `stage_id` (M2O→project.task.type) — Stage Kanban
- `parent_id` (M2O→project.task) — Tâche parent
- `child_ids` (O2M→project.task) — Sous-tâches
- `user_ids` (M2M→res.users) — Assignés (multi)
- `partner_id` (M2O→res.partner) — Client (billable)
- `tag_ids` (M2M→project.tags) — Tags
- `milestone_id` (M2O→project.milestone) — Jalon
- `company_id` (M2O→res.company) — Société

### Dates
- `date_deadline` (Date) — Échéance
- `date_start` (Datetime) — Début planifié
- `date_end` (Datetime) — Fin planifiée
- `date_assign` (Datetime) — Assignation
- `date_last_stage_update` (Datetime) — Dernier changement stage

### Temps
- `planned_hours` (Float) — Heures allouées
- `remaining_hours` (Float, computed) — Restantes
- `effective_hours` (Float, computed) — Effectives (timesheets)
- `total_hours_spent` (Float, computed) — Total + sous-tâches
- `progress` (Float, computed) — % = effective/planned
- `overtime` (Float, computed) — Heures supp

### Sous-tâches (computed)
- `subtask_count` — Nombre total
- `subtask_done_count` — Terminées (done/canceled)

### Récurrence
- `recurring_task` (Boolean) — Récurrente
- `recurring_interval` (Integer) — Intervalle
- `recurring_rule_type` (Selection) — `daily`, `weekly`, `monthly`, `yearly`
- `recurring_count` (Integer, computed) — Nombre récurrences

### Dépendances
- `depend_ids` (M2M→project.task) — Blocked by (predecessors)
- `blocking_task_ids` (M2M→project.task) — Blocked Tasks (successors)

### Facturation
- `sale_line_id` (M2O→sale.order.line) — Sales Order Item
- `is_closed` (Boolean, computed) — Fermée

### Chatter (mail.thread)
- `message_ids` — Messages
- `message_partner_ids` — Followers
- `activity_ids` — Activités planifiées
- `email_from` — Email expéditeur

---

## 4. Stages (project.task.type)

- `name`, `sequence`, `project_ids` (M2M), `case_default` (partagé), `fold`
- `mail_template_id` — email auto au changement
- Légendes: `legend_priority`, `legend_blocked`, `legend_done`, `legend_normal`

Spécifiques au projet par défaut, partageables, pas de défaut à la création.

---

## 5. Milestone (project.milestone)

- `name` (required), `project_id`, `deadline`, `is_reached` (auto/manuel)
- `sale_line_id`, `sale_line_qty_percentage` — facturation jalon
- `task_ids` (O2M) — tâches liées
- Auto-reached quand tâches Done/Canceled. Gantt: diamant bleu/rouge.

---

## 6. Tags (project.tags)

- `name` (required), `color`

---

## 7. Vues

- **Kanban** (défaut) — colonnes=stages, drag&drop, édition directe
- **List** — batch actions, import/export
- **Calendar** — deadlines
- **Gantt** — timeline, dépendances, jalons, ressources
- **Graph/Pivot/Burndown** — analyse
- **My Tasks** — multi-projets, privé + pipeline perso
- **Large screen** — chatter droite

---

## 8. Tâches — Détail

### Champs: Title, Priority(star), Project, Assignees(multi), Tags, Customer(billable), Sales Order Item(billable), Allocated Time, Deadline

### 5 Statuts fixes
1. In Progress (défaut) 2. Changes Requested 3. Approved 4. Done (ferme) 5. Canceled (ferme)
- Changes Requested/Approved effacés au changement de stage. Done/Canceled rouvrables.

---

## 9. Sous-tâches

Multi-niveaux. Éditable depuis parent (Title, Priority, Status, Assignees). Smart button total+fermées. Allocated time parent=parent+sous-tâches. Timesheets parent inclut sous-tâches. Cross-project possible.

---

## 10. Récurrence

Repeat Every (daily/weekly/monthly/yearly). Nouvelle tâche au Done/Canceled. Copiés: Name, Description, Project, Assignees, Customer, Tags. Non copiés: Milestones, Timesheets, Chatter, Activities, Subtasks. Édition sur dernière → futures.

---

## 11. Dépendances

Onglet "Blocked by" (predecessors). Smart button "Blocked Tasks". Gantt: drag dot→successor. Successor=Waiting jusqu'à predecessor Approved/Canceled/Done. Reschedule auto.

---

## 12. Jalons

Settings→Milestones. Auto-reached quand tâches liées Done/Canceled. Manuel possible. Dashboard: checklist rouge/vert. Gantt: diamant bleu/rouge.

---

## 13. Dashboard projet

Smart buttons: Tasks(%), Timesheets, Planned, Documents, Burndown, Timesheets&Planning, Sales Orders, POs.
Sections: Milestones, Profitability (billable), Budgets.
Project Updates: Status (On Track/At Risk/Off Track/On Hold/Done), Progress%, Description pré-rempli.

---

## 14. Rentabilité

**Revenus:** Timesheets (policy), Materials, Invoices, Subscriptions, Down payments, Expenses refacturés.
**Coûts:** Timesheets (coût employé), PO, Materials (stock moves), Expenses, Vendor bills, MO, Other.
**3 colonnes:** To invoice/bill, Invoiced/billed, Total.

---

## 15. Templates

Convertir projet→template (archive original). Transfère stages, tâches, sous-tâches, configs. Création: New→template. Billable possible. Lien produit: Service + Create on Order + Template.

---

## 16. Communication

Chatter (log centralisé), Email integration (auto-attaché), Templates email/SMS par stage, Customer satisfaction survey, Visibility levels, VoIP, Chat users, Real-time collaboration (HTML editor), Customer portal.

---

## 17. Facturation

Policies: fixed price, milestones, time&material. Auto-invoice timesheets. Création projet depuis Sales Order et inversement.

---

## 18. Reporting

Project Updates, Budget management, Tasks Analysis, Burndown chart, Time tracking, Graph/Pivot/Dashboard personnalisé.

---

## 19. Intégrations

Timesheet, Sales, Field Service, Planning, Expenses, Helpdesk, Documents, Inventory, Manufacturing, Subscriptions, Purchase.

---

## 20. Visibilité & Permissions

- `followers` (privé) — followers + admin seulement
- `employees` — tous internes
- `portal` (défaut) — internes + portal users (tâches suivies seulement)
- Share Project: lien public (read) ou collaborateur (Read/Edit limited/Edit)
- URL sharing: accès tâche même sans accès projet (sauf privé = follower requis)

---

## 21. Text shortcuts (création Kanban)

Format: nom + heures + tags + assigné + priorité. Ex: `Task name 30h #tag @user !high`

---

## 22. Création auto de tâches

- **Email alias:** sender→Customer, subject→Title, body→Description, recipients→followers
- **Website form:** Action=Create a Task, Project=select

---

## 23. Champs accessibles Portal

**Readable:** id, active, description, priority, kanban_state_label, project_id, display_project_id, color, allow_subtasks, subtask_count, child_text, is_closed, email_from, create_date, write_date, company_id, display_name, user_ids, allow_milestones, milestone_id

**Writable:** name, partner_id, date_deadline, tag_ids, sequence, stage_id, kanban_state, child_ids, parent_id, priority

---

## 24. Équivalences Compta/Sage100

| Odoo | Compta équivalent | Notes |
|---|---|---|
| project.project | projects table | Multi-tenant (company_id) |
| project.task | project_tasks table | parent_id pour sous-tâches |
| project.task.type | project_stages table | sequence, fold |
| project.milestone | project_milestones table | is_reached auto |
| project.tags | project_tags table | M2M avec tasks |
| state (5 statuts) | task_status enum | in_progress/changes_requested/approved/done/canceled |
| depend_ids | project_task_dependencies table | M2M |
| recurring_task | champs récurrence | interval + rule_type |
| planned_hours/effective_hours | champs temps | timesheets liés |
| privacy_visibility | visibility enum | followers/employees/portal |
| allow_* settings | boolean flags sur projet | subtasks/recurring/milestones/dependencies/timesheets/billable |
| alias email | alias config | création auto par email |
| profitability | coûts/revenus projet | compte analytique |
| project updates | project_updates table | snapshot périodique |

---

## 25. Plan d'Implémentation — Fusion des Meilleures Options (Wadashaqayn + Odoo)

> Objectif: conserver le meilleur de chaque système pour Sage100/Compta.
> Source: comparaison détaillée Wadashaqayn-clean vs Odoo 19.0 (Gantt & Kanban).

### 25.1 Vue Kanban — Retenir

#### De Wadashaqayn (à implémenter en priorité)

| Fonctionnalité | Description | Priorité |
|---|---|---|
| **Drag & drop complet (DndKit)** | PointerSensor (distance 8px), DragOverlay ghost, drop sur colonne OU sur autre tâche | P0 |
| **Mode dual Tasks/Projects** | ToggleGroup pour basculer entre vue tâches et vue projets | P1 |
| **Édition inline (4 composants)** | EditableTaskTitle, EditableTaskAssignee, EditableTaskPriority, EditableTaskStatus | P0 |
| **Filtres avancés multi-critères** | Search, status, priority, assignee, project, dateFrom, dateTo + persistance localStorage | P0 |
| **Progress bar sur carte** | `<Progress value={task.progress}>` avec couleur projet | P0 |
| **Color coding par projet** | `projectColorMap` + `getTaskColor()` | P0 |
| **Avatar assigné** | Avatar + fallback 2 lettres + ring | P1 |
| **Badge priorité multi-niveaux** | `PRIORITY_COLORS` (low/medium/high/urgent) — plus riche qu'Odoo (2 niveaux) | P0 |
| **Badge projet sur carte** | Badge coloré avec nom projet | P1 |
| **Compteur colonne** | Badge avec `tasks.length` | P0 |
| **Export intégré** | ExportButton CSV/Excel depuis Kanban | P1 |
| **Version mobile dédiée** | MobileKanbanBoard avec tabs horizontales | P1 |
| **i18n complet** | Clés `taskManagement.kanban.*` (fr/en/ar) | P0 |

#### D'Odoo (à ajouter)

| Fonctionnalité | Description | Priorité |
|---|---|---|
| **Stages personnalisables par projet** | Table `project_stages` (name, sequence, fold, project_ids, mail_template_id) — partageables entre projets | P0 |
| **Repli colonne (fold)** | Collapse/expand colonne Kanban | P2 |
| **Cover image sur carte** | Image de couverture optionnelle par tâche | P2 |
| **Text shortcuts** | Format: `nom 30h #tag @user !high` à la création | P2 |
| **Pipeline privé / My Tasks** | Vue transversale multi-projets + stages privés personnels | P2 |
| **Email alias création** | `alias_name@domain` → création auto (sender=customer, subject=title, body=description) | P3 |
| **Website form création** | Formulaire public → création tâche dans projet sélectionné | P3 |
| **Batch actions** | Sélection multiple → export, archive, delete, email, SMS | P2 |
| **5 statuts fixes** | In Progress, Changes Requested, Approved, Done, Canceled (vs 4 actuels) | P1 |
| **Multi-assignation** | `user_ids` (M2M) au lieu de `assignee_id` (M2O) | P1 |
| **Tags sur tâches** | `project_tags` (name, color) + M2M avec tasks | P1 |
| **Smart button sub-task count** | Compteur sous-tâches + sous-tâches fermées sur carte | P1 |

### 25.2 Vue Gantt — Retenir

#### De Wadashaqayn (à implémenter en priorité)

| Fonctionnalité | Description | Priorité |
|---|---|---|
| **Timeline calendrier avec axe temporel** | Graduations jour/semaine/mois/trimestre/année | P0 |
| **5 niveaux de zoom + buffer** | Day (40px), Week (120px), Month (200px), Quarter (240px), Year + `yearBuffer` ajustable (1-50) | P0 |
| **Drag & drop barres** | `onTaskMouseDown` pour déplacement horizontal (reschedule) | P0 |
| **Resize barres (handles gauche/droite)** | `resize-left` / `resize-right` avec cursor `ew-resize` | P0 |
| **Progress sur barre** | % affiché au centre (font-extrabold) + barre colorée (completedColor/remainingColor) | P0 |
| **Couleurs par projet** | `projectColor` + `darkenColor`/`lightenColor` pour progression | P0 |
| **Sous-tâches hiérarchiques** | `parent_id` → hauteur 70%, retrait 3rem, italique, `↳` prefix | P0 |
| **Organisation parent/enfant** | Parents d'abord, enfants indentés juste après | P0 |
| **Barres de projet** | `GanttProjectBar` + `ProjectProgressBar` (nom, couleur, progress, durée, nb tâches) | P0 |
| **Dépendances SVG (4 types)** | finish-to-start, start-to-start, finish-to-finish, start-to-finish — Odoo n'a que FS | P0 |
| **Suppression dépendance** | Hover ligne → bouton X pour supprimer | P1 |
| **Détection de surcharge** | `isOverloaded` → fond rouge clair + bordure rouge + icône AlertTriangle | P1 |
| **Scroll synchronisé** | Vertical (task list ↔ timeline) + horizontal (header ↔ timeline) | P0 |
| **Grille temporelle adaptative** | Lignes verticales + horizontales calculées selon hauteurs variables (sous-tâches) | P0 |
| **Version mobile dédiée** | MobileGanttChart | P1 |
| **Modal erreur dates** | Modal avec message + details + suggestion + bouton "Compris" | P1 |
| **i18n complet** | Clés `gantt.*` (fr/en/ar) | P0 |

#### D'Odoo (à ajouter)

| Fonctionnalité | Description | Priorité |
|---|---|---|
| **Jalons (milestones) sur Gantt** | Diamants bleu (atteint) / rouge (non atteint) sur timeline | P0 |
| **Auto-reached milestones** | Jalon automatiquement atteint quand toutes les tâches liées sont Done/Canceled | P1 |
| **Critical path** | Chaîne critique visuelle (tâches sur le chemin critique en surbrillance) | P2 |
| **Auto-scheduling** | Forward/backward scheduling — reschedule automatique des successeurs | P2 |
| **Lag & lead** | Décalage positif/négatif sur dépendances (`lag_days` — type déjà défini dans Wadashaqayn mais non utilisé) | P2 |
| **Constraints** | Manual, Auto, Must Start On, As Late As Possible | P3 |
| **Loop detection** | Détection de dépendances circulaires bloquée à la création | P2 |
| **Gestion de ressources** | Barres ressources + histogrammes de charge | P3 |
| **Calendriers de travail** | Calendriers par ressource (jours/heures travaillés) | P3 |
| **Congés employés** | Pris en compte dans le planning | P3 |
| **Timesheet ghost bars** | Superposition du temps réel passé sur la barre planifiée | P2 |
| **Deadline indicators** | Marqueurs visuels de deadline sur la timeline | P2 |
| **Inline rename sur barre** | Double-clic sur barre → renommer inline | P2 |
| **Right-click menu** | Menu contextuel sur barre (quick actions: edit, delete, add dependency, add subtask) | P2 |
| **Expand/collapse par branche** | Repli/groupe par projet ou par tâche parent | P2 |

### 25.3 Modèle de données — Fusion

#### Table `project_tasks` (à créer)

| Champ | Type | Source | Notes |
|---|---|---|---|
| `id` | UUID PK | — | |
| `title` | VARCHAR(255) NOT NULL | Wadashaqayn | |
| `description` | TEXT | Odoo | Rich text |
| `status` | ENUM | Fusion | `todo`, `doing`, `blocked`, `changes_requested`, `approved`, `done`, `canceled` (7 statuts = 4 Wadashaqayn + 3 Odoo) |
| `priority` | ENUM | Wadashaqayn | `low`, `medium`, `high`, `urgent` (4 niveaux vs 2 Odoo) |
| `project_id` | UUID FK → projects | Commun | |
| `parent_id` | UUID FK → project_tasks (self) | Commun | Sous-tâches multi-niveaux |
| `assignee_ids` | UUID[] FK → employees | Odoo | Multi-assignation (M2M) |
| `department_id` | UUID FK → departments | Wadashaqayn | |
| `partner_id` | UUID FK → partners | Odoo | Client (billable) |
| `milestone_id` | UUID FK → project_milestones | Odoo | |
| `tag_ids` | UUID[] FK → project_tags | Odoo | |
| `stage_id` | UUID FK → project_stages | Odoo | Stage Kanban personnalisable |
| `start_date` | TIMESTAMP | Wadashaqayn | |
| `due_date` | TIMESTAMP | Wadashaqayn | |
| `date_assign` | TIMESTAMP | Odoo | |
| `date_last_stage_update` | TIMESTAMP | Odoo | |
| `effort_estimate_h` | FLOAT | Wadashaqayn | Heures planifiées |
| `effort_spent_h` | FLOAT | Wadashaqayn | Heures effectives |
| `progress` | FLOAT | Wadashaqayn | % calculé ou manuel |
| `budget` | FLOAT | Wadashaqayn | |
| `color` | INTEGER | Odoo | Couleur carte |
| `display_order` | VARCHAR | Wadashaqayn | Ordre Kanban (lexicographic) |
| `task_level` | INTEGER | Wadashaqayn | Niveau hiérarchique |
| `acceptance_criteria` | TEXT | Wadashaqayn | |
| `recurring_task` | BOOLEAN | Odoo | Tâche récurrente |
| `recurring_interval` | INTEGER | Odoo | Intervalle |
| `recurring_rule_type` | ENUM | Odoo | `daily`, `weekly`, `monthly`, `yearly` |
| `sale_line_id` | UUID FK → sale_order_lines | Odoo | Facturation |
| `is_closed` | BOOLEAN (computed) | Odoo | |
| `tenant_id` | UUID FK → tenants | Wadashaqayn | Multi-tenant |
| `linked_action_id` | UUID | Wadashaqayn | |
| `created_at` | TIMESTAMP | Commun | |
| `updated_at` | TIMESTAMP | Commun | |

#### Table `project_task_dependencies` (à créer)

| Champ | Type | Source | Notes |
|---|---|---|---|
| `id` | UUID PK | — | |
| `task_id` | UUID FK → project_tasks | Wadashaqayn | Successeur |
| `depends_on_task_id` | UUID FK → project_tasks | Wadashaqayn | Prédécesseur |
| `dependency_type` | ENUM | Wadashaqayn | `finish-to-start`, `start-to-start`, `finish-to-finish`, `start-to-finish` (4 types vs 1 Odoo) |
| `lag_days` | INTEGER | Odoo | Décalage (positif/négatif) |
| `tenant_id` | UUID FK → tenants | Wadashaqayn | |
| `created_at` | TIMESTAMP | Commun | |

#### Table `project_stages` (à créer — d'Odoo)

| Champ | Type | Notes |
|---|---|---|
| `id` | UUID PK | |
| `name` | VARCHAR(100) NOT NULL | |
| `sequence` | INTEGER | Ordre d'affichage |
| `fold` | BOOLEAN | Repli colonne Kanban |
| `project_ids` | UUID[] FK → projects | Projets utilisant ce stage (vide = tous) |
| `case_default` | BOOLEAN | Stage partagé par défaut |
| `mail_template_id` | UUID FK → mail_templates | Email auto au changement |
| `legend_priority` | VARCHAR | Légende étoile |
| `legend_blocked` | VARCHAR | Légende bloqué |
| `legend_done` | VARCHAR | Légende terminé |
| `legend_normal` | VARCHAR | Légende normal |
| `tenant_id` | UUID FK → tenants | |

#### Table `project_milestones` (à créer — d'Odoo)

| Champ | Type | Notes |
|---|---|---|
| `id` | UUID PK | |
| `name` | VARCHAR(255) NOT NULL | |
| `project_id` | UUID FK → projects | |
| `deadline` | DATE | |
| `is_reached` | BOOLEAN | Auto quand tâches liées Done/Canceled |
| `is_reached_manually` | BOOLEAN | Override manuel |
| `sale_line_id` | UUID FK → sale_order_lines | Facturation jalon |
| `sale_line_qty_percentage` | FLOAT | % quantité facturée |
| `tenant_id` | UUID FK → tenants | |

#### Table `project_tags` (à créer — d'Odoo)

| Champ | Type | Notes |
|---|---|---|
| `id` | UUID PK | |
| `name` | VARCHAR(100) NOT NULL | |
| `color` | INTEGER | |
| `tenant_id` | UUID FK → tenants | |

#### Table `project_task_tags` (junction — d'Odoo)

| Champ | Type | Notes |
|---|---|---|
| `task_id` | UUID FK → project_tasks | |
| `tag_id` | UUID FK → project_tags | |

#### Table `project_task_assignees` (junction — multi-assignation Odoo)

| Champ | Type | Notes |
|---|---|---|
| `task_id` | UUID FK → project_tasks | |
| `employee_id` | UUID FK → employees | |

#### Extension table `projects` (ajouts)

| Champ | Type | Source | Notes |
|---|---|---|---|
| `allow_subtasks` | BOOLEAN | Odoo | |
| `allow_recurrent_tasks` | BOOLEAN | Odoo | |
| `allow_milestones` | BOOLEAN | Odoo | |
| `allow_task_dependencies` | BOOLEAN | Odoo | |
| `allow_timesheets` | BOOLEAN | Odoo | |
| `allow_billable` | BOOLEAN | Odoo | |
| `privacy_visibility` | ENUM | Odoo | `followers`, `employees`, `portal` |
| `manager_id` | UUID FK → employees | Odoo | Chef de projet |
| `tag_ids` | UUID[] | Odoo | |
| `color` | INTEGER | Odoo | |
| `alias_name` | VARCHAR | Odoo | Email alias |
| `allocated_hours` | FLOAT (computed) | Odoo | |
| `total_hours_spent` | FLOAT (computed) | Odoo | |
| `remaining_hours` | FLOAT (computed) | Odoo | |

### 25.4 Composants UI à implémenter

#### Kanban (priorité P0 → P2)

1. **`KanbanBoard`** — DndContext, 4 colonnes (extensible via stages), mode dual tasks/projects
2. **`KanbanColumn`** — SortableContext, compteur, fold/unfold
3. **`KanbanCard`** — Avatar, badges (priorité + projet + tags), progress bar, color coding, cover image optionnelle
4. **`EditableTaskTitle`** — Double-clic → input inline
5. **`EditableTaskAssignee`** — Multi-select avatars inline
6. **`EditableTaskPriority`** — Dropdown inline (4 niveaux)
7. **`EditableTaskStatus`** — Dropdown inline (7 statuts)
8. **`AdvancedFilters`** — Search, status, priority, assignee, project, tags, dates + localStorage
9. **`ExportButton`** — CSV/Excel
10. **`MobileKanbanBoard`** — Tabs horizontales, swipe
11. **`TextShortcutInput`** — Parser `nom 30h #tag @user !high`

#### Gantt (priorité P0 → P3)

1. **`GanttChart`** — Container principal, scroll synchronisé, modal erreur
2. **`GanttHeader`** — 5 niveaux zoom (day/week/month/quarter/year) + buffer
3. **`GanttTimeline`** — Grille, barres, flèches, jalons
4. **`GanttTaskBar`** — Drag, resize, progress %, surcharge, couleurs
5. **`GanttProjectBar`** — Barre projet avec progress
6. **`GanttTaskList`** — Liste gauche avec hiérarchie parent/enfant
7. **`ProjectProgressBar`** — Nom, couleur, progress, durée, nb tâches
8. **`DependencyLines`** — SVG, 4 types (FS/SS/FF/SF), lag_days, suppression
9. **`MilestoneDiamond`** — Diamant bleu (atteint) / rouge (non atteint) sur timeline
10. **`CriticalPathHighlight`** — Surbrillance chaîne critique
11. **`ResourceLoadBars`** — Histogrammes de charge par ressource
12. **`MobileGanttChart`** — Version mobile simplifiée
13. **`GanttContextMenu`** — Right-click (edit, delete, add dependency, add subtask)

### 25.5 Ordre d'implémentation recommandé

#### Sprint 1 — Fondations (P0)
1. Créer tables SQL: `project_tasks`, `project_stages`, `project_task_dependencies`, `project_milestones`, `project_tags`, `project_task_tags`, `project_task_assignees`
2. Étendre table `projects` avec champs `allow_*` et `privacy_visibility`
3. Créer types TypeScript correspondants
4. Implémenter `KanbanBoard` avec DndKit + drag & drop + 4 colonnes
5. Implémenter `GanttChart` avec timeline + 5 zooms + drag/resize

#### Sprint 2 — Édition & Filtres (P0-P1)
6. Implémenter 4 composants édition inline Kanban
7. Implémenter `AdvancedFilters` multi-critères + localStorage
8. Implémenter `KanbanCard` avec progress bar, color coding, avatar, badges
9. Implémenter `DependencyLines` SVG avec 4 types
10. Implémenter sous-tâches hiérarchiques Gantt
11. Implémenter `GanttProjectBar` + `ProjectProgressBar`

#### Sprint 3 — Stages & Jalons (P0-P1)
12. Implémenter stages personnalisables (table `project_stages`)
13. Implémenter jalons sur Gantt (`MilestoneDiamond`)
14. Implémenter auto-reached milestones
15. Ajouter 5 statuts Odoo (changes_requested, approved) aux 4 Wadashaqayn
16. Implémenter multi-assignation (`project_task_assignees`)
17. Implémenter tags sur tâches

#### Sprint 4 — Avancé (P1-P2)
18. Implémenter mode dual Tasks/Projects Kanban
19. Implémenter détection de surcharge Gantt
20. Implémenter versions mobiles (Kanban + Gantt)
21. Implémenter Export CSV/Excel
22. Implémenter repli colonne (fold)
23. Implémenter text shortcuts
24. Implémenter lag & lead sur dépendances

#### Sprint 5 — Expert (P2-P3)
25. Implémenter critical path
26. Implémenter auto-scheduling (forward/backward)
27. Implémenter loop detection dépendances
28. Implémenter batch actions Kanban
29. Implémenter timesheet ghost bars
30. Implémenter constraints (Must Start On, ALAP)
31. Implémenter gestion de ressources + calendriers
32. Implémenter email alias + website form création

### 25.6 i18n — Clés de traduction à prévoir

Namespaces: `taskManagement` (Kanban), `gantt` (Gantt), `projects` (commun)

Langues: **fr** (défaut), **en**, **ar** (RTL)

Clés principales:
- `taskManagement.kanban.colTodo`, `colDoing`, `colBlocked`, `colDone`, `colChangesRequested`, `colApproved`, `colCanceled`
- `taskManagement.kanban.tasksToggle`, `projectsToggle`, `projectsSubtitle`
- `taskManagement.kanban.priorityLow`, `priorityMedium`, `priorityHigh`, `priorityUrgent`
- `taskManagement.filters.*` (search, status, priority, assignee, project, tags, dateFrom, dateTo, reset, results)
- `gantt.title`, `viewDay`, `viewWeek`, `viewMonth`, `viewQuarter`, `viewYear`, `displayYears`
- `gantt.noProject`, `details`, `solution`, `understood`
- `gantt.milestone.reached`, `milestone.notReached`, `milestone.add`, `milestone.deadline`
- `gantt.dependency.finishToStart`, `startToStart`, `finishToFinish`, `startToFinish`
- `gantt.criticalPath`, `autoSchedule`, `overloaded`, `lagDays`

---

## 26. Tableau Dynamique d'Exécution — Wadashaqayn (Référence Détaillée)

> Source: `wadashaqayn-clean/src/components/vues/table/` — 20+ composants
> Architecture: Panneau dual (colonnes fixes + colonnes d'actions dynamiques) avec scroll synchronisé

### 26.1 Vue d'ensemble

Le Tableau Dynamique est une vue d'exécution de type "spreadsheet" combinant:
- **Panneau gauche (60%)** : Colonnes fixes (informations tâche — 12 colonnes)
- **Panneau droit (40%)** : Colonnes d'actions dynamiques (actions pondérées avec preuves)
- **Scroll synchronisé** : Vertical entre les deux panneaux, horizontal dans chaque panneau
- **Mode dual** : Bascule entre vue **Tâches** et vue **Projets** via `ToggleGroup`
- **Layout responsive** : `ResizablePanelGroup` (redimensionnable) + version mobile dédiée

### 26.2 Architecture des composants (20+ fichiers)

```
table/
├── DynamicTable.tsx              (conteneur principal — 504 lignes)
├── TaskTableHeader.tsx           (barre d'outils)
├── TaskFixedColumns.tsx          (table colonnes fixes — 12 colonnes)
├── TaskTableBody.tsx             (corps table + lignes fantômes)
├── TaskRow.tsx                   (ligne individuelle — 305 lignes)
├── TaskActionColumns.tsx         (table actions dynamiques — 378 lignes)
├── TaskRowActions.tsx            (menu actions ligne: edit/duplicate/delete)
├── TaskDialogManager.tsx         (gestion dialogs: détails + sous-tâche)
├── SubTaskRow.tsx                (ligne sous-tâche alternative)
├── SubtaskCreationDialog.tsx     (dialog création sous-tâche — 599 lignes)
├── ActionCreationDialog.tsx      (dialog création action détaillée)
├── AssigneeSelect.tsx            (sélecteur assigné avec workload)
├── SimpleAssigneeDisplay.tsx     (affichage assigné compact)
├── DocumentCellColumn.tsx        (cellule documents inline)
├── CommentCellColumn.tsx         (cellule commentaires inline)
├── DocumentsColumn.tsx           (panneau documents latéral)
├── CommentsColumn.tsx            (panneau commentaires latéral)
├── LoadingState.tsx              (état chargement)
├── ErrorState.tsx                (état erreur)
└── cells/
    ├── EditableCell.tsx              (cellule éditable simple)
    ├── EditableCellWithDebounce.tsx  (cellule éditable avec debounce)
    ├── EditableTitleCell.tsx         (cellule titre avec statut sauvegarde)
    ├── EditableDateCell.tsx          (cellule date avec calendar popover)
    └── EditableSelectCell.tsx        (cellule select avec badges colorés)
```

### 26.3 Conteneur Principal — `DynamicTable.tsx`

#### Hooks utilisés
- `useTasks()` — CRUD tâches: `tasks`, `loading`, `error`, `duplicateTask`, `deleteTask`, `toggleAction`, `addActionColumn`, `addDetailedAction`, `createSubTask`, `createSubTaskWithActions`, `updateTaskAssignee`, `refetch`, `createTask`, `updateTask`
- `useProjects()` — Liste projets pour color coding et vue projets
- `useEmployees()` — Liste employés pour filtres
- `useIsMobile()` — Détection mobile pour bascule vers `MobileDynamicTable`
- `useTranslation()` — i18n (clés `taskManagement.*`)
- `useRoleBasedAccess()` — Permissions par rôle

#### État interne
- `selectedTaskId` — Tâche sélectionnée (pour colonnes d'actions contextuelles)
- `newActionTitle` — Input action rapide dans le header
- `displayMode` — `'tasks' | 'projects'` (bascule vue)
- `filters` — `TaskFilters` (search, status, priority, assignee, project, dateFrom, dateTo)
- `projectColorMap` — Map `project_id → color` via `assignProjectColors()`

#### Layout
- `ResizablePanelGroup` (horizontal) avec 2 panneaux:
  - `ResizablePanel` (defaultSize=60, min=40) → `TaskFixedColumns`
  - `ResizableHandle` (barre de redimensionnement)
  - `ResizablePanel` (defaultSize=40, min=30) → `TaskActionColumns`
- Scroll synchronisé via `syncScroll()` — `onScroll` sur chaque panneau met à jour `scrollTop` de l'autre

#### Mode Projets
- Quand `displayMode === 'projects'`, affiche `ProjectTableView` au lieu du tableau de tâches
- Vue par projet avec statistiques agrégées (nombre tâches, progression moyenne, heures totales)

#### Filtres avancés
- Composant `AdvancedFilters` avec:
  - Recherche textuelle (sur titre et assigné)
  - Filtre statut (multi-select: todo, doing, blocked, done)
  - Filtre priorité (multi-select: low, medium, high, urgent)
  - Filtre assigné (multi-select employés)
  - Filtre projet (multi-select projets)
  - Plage de dates (dateFrom, dateTo)
  - Persistance dans `localStorage`
  - Bouton reset

### 26.4 Barre d'Outils — `TaskTableHeader.tsx`

#### Éléments
- **Titre** : "Tableau Dynamique d'Exécution" avec icône `Target`
- **Bouton "Nouvelle Tâche"** : Déclenche `onCreateTask` (ouverture dialog création)
- **Bouton Export** : `ExportButton` CSV/Excel avec filtres appliqués
- **Indicateur tâche sélectionnée** : Texte "Tâche sélectionnée" quand `selectedTaskId` est défini
- **Input action rapide** : Placeholder "Action rapide...", validation sur Enter (appelle `onAddActionColumn`)
- **Bouton "+"** : Ajoute une action rapide à la tâche sélectionnée (désactivé si pas de tâche sélectionnée ou titre vide)
- **Bouton "Action Détaillée"** : Ouvre `ActionCreationDialog` (dialog avec titre, poids slider, échéance, notes)

#### Masqué sur mobile
- `if (isMobile) return null` — Le header est masqué sur mobile, les contrôles sont dans la version mobile

### 26.5 Table Colonnes Fixes — `TaskFixedColumns.tsx`

#### 12 colonnes fixes (ordre exact)

| # | Colonne | min-width | Type | Éditable | Composant |
|---|---|---|---|---|---|
| 1 | Tâche | 200px | Texte | Oui (inline) | `EditableTitleCell` |
| 2 | Projet | 150px | Badge coloré | Non (affichage) | `TableCell` + Badge |
| 3 | Responsable | 150px | Avatar + nom | Oui (popover) | `SimpleAssigneeDisplay` + `AssigneeSelect` |
| 4 | Début | 80px | Date | Oui (popover calendar) | `EditableDateCell` |
| 5 | Échéance | 80px | Date | Oui (popover calendar) | `EditableDateCell` |
| 6 | Priorité | 80px | Badge coloré | Oui (dropdown) | `EditableSelectCell` |
| 7 | Statut | 80px | Badge coloré | Oui (dropdown) | `EditableSelectCell` |
| 8 | Charge (h) | 80px | Nombre | Oui (input debounce) | `EditableCellWithDebounce` |
| 9 | Progression | 100px | Progress bar + % | Non (auto-calculé) | `Progress` + texte |
| 10 | Documents | 100px | Bouton + compteur | Oui (upload/download) | `DocumentCellColumn` |
| 11 | Commentaires | 100px | Bouton + compteur | Oui (dialog) | `CommentCellColumn` |
| 12 | Actions | 50px | Menu dropdown | Non | `TaskRowActions` |

#### Style du header
- `sticky top-0 z-20` — Header collant
- `bg-gradient-to-r from-primary to-violet-600` — Dégradé violet
- `text-white font-bold` — Texte blanc gras
- `h-16` — Hauteur 64px
- `shadow-md` — Ombre

#### Conteneur scroll
- `h-[600px] overflow-auto` — Hauteur fixe 600px avec scroll
- `ref={scrollRef}` pour synchronisation avec panneau actions

### 26.6 Corps du Tableau — `TaskTableBody.tsx`

#### Tri par `display_order`
- Tri lexicographique sur `display_order` (ex: "1", "1.1", "1.2", "2", "2.1")
- Parse les niveaux avec `split('.').map(n => parseInt(n))`
- Compare niveau par niveau avec fallback à 0

#### Lignes fantômes (Ghost rows)
- **5 lignes fantômes** générées à la fin du tableau
- ID: `ghost-task-0` à `ghost-task-4`
- Titre vide avec placeholder "+ Ajouter une nouvelle tâche..."
- Style: `border-dashed opacity-60`
- **Création inline** : Quand on tape un titre dans une ligne fantôme → `handleGhostTaskUpdate` → `onCreateTask()` avec titre, assigné, projet, priorité, statut, effort
- La nouvelle tâche remplace la ligne fantôme après re-render

#### Délégation
- Mappe chaque tâche (réelle + fantôme) vers `TaskRow` avec toutes les callbacks
- `isGhost` flag pour différencier le comportement (édition titre = création au lieu d'update)

### 26.7 Ligne Individuelle — `TaskRow.tsx` (305 lignes)

#### Structure
- `TableRow` avec hauteur variable: 64px (tâche normale) ou 51px (sous-tâche)
- `onClick` → sélection de la tâche (`onSelectTask`)
- `onDoubleClick` → édition (`onEdit`)
- Style conditionnel: `bg-primary/15` si sélectionnée, `border-dashed opacity-60` si fantôme

#### Permissions par tâche
- `useTaskEditPermissions({ task })` → `permissions.canEditTitle`, `permissions.canEdit`
- Les cellules éditables sont en `readOnly` si pas de permission

#### Colonne 1 — Tâche (`EditableTitleCell`)
- **Bouton +/-** : Si tâche parent → bouton `+` (créer sous-tâche), si sous-tâche → bouton `-` (supprimer)
- **Numéro d'ordre** : `display_order` affiché en gris (ex: "1", "1.1")
- **Indentation** : `paddingLeft: taskLevel * 20px` pour hiérarchie visuelle
- **Titre éditable** : Clic → input inline avec debounce 800ms
- **Statut sauvegarde** : `idle` → `editing` → `saving` (spinner bleu) → `saved` (check vert 2s) → `error` (✗ rouge 3s)
- **Raccourcis** : Enter = sauvegarder, Escape = annuler
- **Placeholder** : "+ Ajouter une nouvelle tâche..." pour les fantômes, "Nom de la tâche..." sinon
- **Style sous-tâche** : `text-xs italic text-foreground/70`

#### Colonne 2 — Projet
- Badge coloré avec `backgroundColor: color, color: '#fff', borderColor: color` si couleur projet
- Point animé `animate-pulse` devant le nom
- Badge "Aucun projet" en pointillé gris si pas de projet
- Effet hover: `scale-105 shadow-md`

#### Colonne 3 — Responsable
- `Popover` avec `SimpleAssigneeDisplay` comme trigger
- `AssigneeSelect` dans le popover avec:
  - Liste employés filtrés par `tenant_id` (sécurité stricte)
  - Avatar + nom pour chaque employé
  - Indicateur de surcharge `AlertTriangle` + `%` si `workloadInfo.isOverloaded`
  - Check vert si déjà assigné
  - Bouton "Inviter un collaborateur" (si permission `canManageTeam`)
  - `QuickInviteDialog` pour invitation rapide

#### Colonne 4-5 — Dates (`EditableDateCell`)
- Icône `Calendar` + date formatée (`formatDate`)
- Popover avec `Calendar` (mode single)
- Format de sortie: `yyyy-MM-dd`
- Style focus: `bg-blue-50 ring-2 ring-blue-500`
- ReadOnly: `cursor-not-allowed opacity-60`

#### Colonne 6 — Priorité (`EditableSelectCell`)
- `DropdownMenu` avec 4 options:
  - `low` → "Basse" (badge outline)
  - `medium` → "Moyenne" (badge outline)
  - `high` → "Haute" (badge outline)
  - `urgent` → "Urgente" (badge destructive)
- Badge coloré via `priorityColors[value]`
- Style focus: `ring-2 ring-blue-500`

#### Colonne 7 — Statut (`EditableSelectCell`)
- `DropdownMenu` avec 4 options:
  - `todo` → "À faire" (badge outline)
  - `doing` → "En cours" (badge outline)
  - `blocked` → "Bloquée" (badge destructive)
  - `done` → "Terminée" (badge outline)
- Badge coloré via `statusColors[value]`

#### Colonne 8 — Charge (`EditableCellWithDebounce`)
- Input number avec debounce 800ms
- Type: `number`, placeholder "0h"
- Sauvegarde: `parseFloat(value) || 0`
- Indicateur visuel: spinner bleu (saving), check vert (saved), ✗ rouge (error)
- Fond coloré temporaire: jaune (saving), vert (saved)

#### Colonne 9 — Progression
- `Progress` component avec `value={task.progress}`
- `indicatorColor={color}` (couleur projet)
- Texte `%` à côté
- Largeur: `w-16` (normal) ou `h-1 w-12` (sous-tâche)
- **Non éditable** — calculé automatiquement depuis les actions

#### Colonne 10 — Documents (`DocumentCellColumn`)
- Bouton `+` pour upload (input file caché)
- Upload vers Supabase Storage bucket `task-documents`
- Path: `{task.id}/{timestamp}.{ext}`
- Métadonnées en base: `task_id`, `project_id`, `file_name`, `file_path`, `file_size`, `mime_type`, `tenant_id`, `uploader_id`
- Compteur avec icône `FileText` + nombre
- Dialog avec liste documents (nom, date, bouton download)
- Désactivé pour demo/ghost tasks (`isDemoTask`)

#### Colonne 11 — Commentaires (`CommentCellColumn`)
- Bouton avec icône `MessageSquare` + compteur
- Dialog avec:
  - `ScrollArea` (hauteur 384px) listant les commentaires
  - Format: temps relatif (`formatDistanceToNow`) + contenu
  - `Textarea` pour nouveau commentaire
  - Bouton "Envoyer" avec icône `Send`
  - Insertion en base: `task_id`, `content`, `comment_type: 'general'`
  - Tri par `created_at` ascending

#### Colonne 12 — Actions (`TaskRowActions`)
- `DropdownMenu` avec 3 actions:
  - **Modifier** (icône `Edit`) → `onEdit(taskId)`
  - **Dupliquer** (icône `Copy`) → `onDuplicate(taskId)`
  - **Supprimer** (icône `Trash2`, classe `text-destructive`) → `onDelete(taskId)`

#### Dialog sous-tâche (Portal)
- Si tâche parent (pas sous-tâche) et clic sur bouton `+`
- `createPortal(<SubtaskCreationDialog />, document.body)` — rendu via Portal
- Évite les problèmes de z-index dans le tableau scrollable

### 26.8 Cellules Éditables (`cells/`)

#### `EditableCell.tsx` — Cellule simple
- Édition sur clic (input inline)
- Enter = sauvegarder, Escape = annuler
- Pas de debounce (sauvegarde immédiate sur blur)
- Props: `value`, `onChange`, `type` (text/number), `placeholder`, `readOnly`, `isSubtask`

#### `EditableCellWithDebounce.tsx` — Cellule avec debounce
- **Debounce 800ms** (configurable via `debounceMs`)
- États de sauvegarde: `idle` → `editing` → `saving` → `saved` → `error`
- `saving` : spinner `Loader2` bleu + fond jaune temporaire
- `saved` : check `Check` vert (2s) + fond vert temporaire
- `error` : ✗ rouge (3s) + message "Erreur de sauvegarde"
- Ring bleu `ring-2 ring-blue-500` en mode édition
- Cleanup du timer au démontage

#### `EditableTitleCell.tsx` — Cellule titre avancée
- Bouton `+` (créer sous-tâche) ou `-` (supprimer sous-tâche) selon `isSubtask`
- Numéro `display_order` affiché en gris
- Indentation hiérarchique: `paddingLeft: taskLevel * 20px`
- Debounce 800ms (configurable)
- États de sauvegarde identiques à `EditableCellWithDebounce`
- Style sous-tâche: `text-xs italic text-muted-foreground font-normal`
- Style parent: `text-foreground font-medium`
- `readOnly` : `cursor-not-allowed opacity-60` + tooltip "Modification non autorisée"

#### `EditableDateCell.tsx` — Cellule date
- `Popover` avec `Calendar` (mode single)
- Icône `Calendar` + date formatée (`formatDate`)
- Format sortie: `yyyy-MM-dd`
- Style focus: `bg-blue-50 ring-2 ring-blue-500`
- ReadOnly: `cursor-not-allowed opacity-60`, affiche `-` si pas de valeur

#### `EditableSelectCell.tsx` — Cellule select avec badges
- `DropdownMenu` avec options (value, label, variant, color)
- Badge coloré affichant la valeur sélectionnée
- `getColorClass` callback pour classes CSS conditionnelles
- Style focus: `ring-2 ring-blue-500`
- Sous-tâche: `px-2 py-0.5 text-xs`

### 26.9 Table Actions Dynamiques — `TaskActionColumns.tsx` (378 lignes)

#### Principe
- Colonnes d'actions **dynamiques** générées depuis les actions uniques de toutes les tâches
- Chaque action a un `title`, `weight_percentage`, `is_done`, `id`
- Les colonnes se réorganisent automatiquement pour mettre les actions de la tâche sélectionnée en premier

#### Récupération des actions uniques
- `getUniqueActions(tasks)` — extrait tous les titres d'actions uniques
- `reorderActionsForSelectedTask(actions, selectedTaskId)` — actions de la tâche sélectionnée en premier, autres après

#### Compteur de fichiers attachés
- Pour chaque action de chaque tâche, query Supabase `task_action_attachments` avec `count: 'exact', head: true`
- Filtrage par `tenant_id` + `task_action_id` + `task_id`
- Stockage dans `attachmentCounts` map: `{ `${taskId}-${actionId}`: count }`

#### Validation preuve requise
- `handleToggleActionWithValidation` : Vérifie qu'au moins 1 fichier est uploadé avant de permettre le toggle
- Si 0 fichier → `toast.error('Document requis', { description: 'Veuillez uploader au moins un document de preuve...' })`
- Checkbox désactivée si `!action.is_done && fileCount === 0` (opacité 50%, curseur not-allowed)

#### Rendu cellule action (`TaskActionRow`)
- **Checkbox** : `Checkbox` avec `checked={action.is_done}`
- **Pourcentage** : Texte `{action.weight_percentage}%` sous la checkbox
- **Bouton upload** : Bouton `+` avec compteur badge vert (si > 0 fichiers)
  - Tooltip: "X fichier(s) • Cliquez pour ajouter" ou "Ajouter un document de preuve (requis)"
  - Visible seulement si `canUploadAttachment` (permission)
- **Style sélection** : Si tâche sélectionnée + action existe → `bg-primary/5` + `scale-110`
- **Style sous-tâche** : `py-0 text-xs`, checkbox `scale-75`
- **Action absente** : Affiche `-` si la tâche n'a pas cette action

#### Permissions par tâche
- `useTaskEditPermissions({ task })` dans `TaskActionRow` (hook par tâche, pas dans la boucle)
- `canUploadAttachment = taskPermissions.canEdit`

#### Upload dialog
- `ActionAttachmentUpload` dialog avec `actionTemplateId`, `actionTitle`, `taskId`, `actionType: "task_action"`
- Callback `onUploadSuccess` → incrémente le compteur local

#### Lignes fantômes
- 5 lignes fantômes identiques à `TaskTableBody` (pour alignement vertical)
- Pas d'actions affichées (cellules vides)

#### Empty state
- Si aucune action: "Aucune colonne d'action" + "Sélectionnez une tâche et ajoutez une colonne d'action via le header"

#### Header actions
- `TableHead` par action avec:
  - Titre tronqué (3 lignes max, `WebkitLineClamp: 3`)
  - `max-w-[140px] min-w-[140px]` — largeur fixe
  - Ring jaune `ring-2 ring-yellow-400/50` si action de la tâche sélectionnée
  - Barre animée `animate-pulse` jaune sous l'action sélectionnée

### 26.10 Dialog Création Sous-tâche — `SubtaskCreationDialog.tsx` (599 lignes)

#### Champs du formulaire
- **Titre** (Input, max 100 chars, compteur) — défaut: "Sous-tâche de {parent.title}"
- **Date de début** (Popover Calendar, format `PPP` locale fr) — défaut: date début parent
- **Date d'échéance** (Popover Calendar) — défaut: date échéance parent
- **Charge estimée** (Input number, min 0.5, step 0.5) — défaut: 1h
- **Responsable** (Select, obligatoire) — défaut: assigné parent ou "Ahmed Waleh"
- **Liaison action parent** (Select optionnel) — si parent a des `task_actions`

#### Section Actions de la sous-tâche
- **Liste actions** avec titre, poids (%), échéance, notes, bouton supprimer
- **Formulaire ajout action** :
  - Titre (Input, max 40 chars, compteur)
  - Poids (Slider 1-100%, step 1)
  - Échéance (Popover Calendar, optionnel)
  - Notes (Textarea, optionnel)
- **Redistribution automatique** des poids:
  - `equalWeight = Math.floor(100 / count)`
  - `remainder = 100 - equalWeight * count` (ajouté à la première action)
  - Bouton "Redistribuer équitablement"
- **Validation** : Somme des poids doit être = 100% (indicateur visuel vert ✅ ou rouge ⚠️)

#### Validation soumission
- Titre non vide
- Responsable obligatoire (alert si "Non assigné")
- Si actions définies: somme poids = 100%

#### Submit
- Si actions + `onCreateSubtaskWithActions` → appelle cette fonction avec `subtaskData` + `actions`
- Sinon → `onCreateSubtask(parentId, linkedActionId, subtaskData)`

#### Reset
- Toutes les valeurs reviennent aux défauts (hérités du parent)

### 26.11 Dialog Création Action — `ActionCreationDialog.tsx`

#### Champs
- **Titre** (Input, max 40 chars, indicateur "0-20 = 1 ligne, 21-40 = 2 lignes")
- **Poids** (Slider 1-100%, step 1, défaut 20%)
- **Date d'échéance** (Popover Calendar, optionnel)
- **Notes** (Textarea, optionnel)

#### Trigger
- Bouton "Action Détaillée" dans le header
- Désactivé si pas de tâche sélectionnée

#### Submit
- Appelle `onCreateAction({ title, weight_percentage, due_date, notes })`
- Reset complet du formulaire

### 26.12 Sélecteur d'Assigné — `AssigneeSelect.tsx`

#### Sécurité multi-tenant
- Filtrage strict par `taskTenantId` — si pas de tenant_id, retourne liste vide (sécurité)
- Log warning si aucun employé trouvé pour le tenant

#### Affichage
- `Popover` avec liste employés filtrés
- Avatar + `full_name` pour chaque employé
- Indicateur de surcharge: `AlertTriangle` + `(workloadPercentage%)` en rouge
- Check vert si déjà assigné
- Compteur "X personnes"

#### Actions
- Sélection → `onChange(employee.user_id || employee.id)`
- Désassignation → bouton "Non assigné" → `onChange('')`
- Inviter collaborateur → `QuickInviteDialog` (si permission `canManageTeam`)

#### Hook de charge
- `useWorkloadAlert(taskId)` — calcule la charge de travail pour tous les employés
- Retourne map: `{ employeeId: { isOverloaded, workloadPercentage } }`

### 26.13 Documents et Commentaires

#### `DocumentCellColumn.tsx` (inline dans la cellule)
- Upload vers Supabase Storage `task-documents`
- Path: `{task.id}/{timestamp}.{ext}`
- Insertion en base avec `tenant_id`, `uploader_id` (user auth)
- Dialog liste avec download (création URL temporaire + click)
- Désactivé pour demo/ghost tasks

#### `CommentCellColumn.tsx` (inline dans la cellule)
- Query `task_comments` triés par `created_at` ascending
- Dialog avec `ScrollArea` (hauteur 384px)
- Format: temps relatif (`formatDistanceToNow` locale fr) + contenu
- Textarea + bouton Envoyer
- Insertion avec `comment_type: 'general'`

#### `DocumentsColumn.tsx` (panneau latéral — version alternative)
- Panneau latéral `w-64 border-l`
- Bouton Upload + liste documents avec download et delete
- Delete: supprime du Storage ET de la base

#### `CommentsColumn.tsx` (panneau latéral — version alternative)
- Panneau latéral `w-80 border-l`
- `ScrollArea` + liste commentaires avec `comment_type` badge
- Textarea + bouton Envoyer

### 26.14 Calcul Automatique de Progression

#### Principe
- La progression d'une tâche est **calculée automatiquement** depuis ses actions
- Formule: `progress = Σ(action.weight_percentage * action.is_done) / 100`
- Si une tâche a 3 actions (40%, 30%, 30%) et 2 sont done → `progress = (40 + 30) / 100 * 100 = 70%`
- Mise à jour optimiste: le toggle d'une action met à jour immédiatement la progression dans l'UI

#### Mise à jour optimiste (`handleToggleAction` dans `DynamicTable`)
1. Trouver la tâche et l'action dans l'état local
2. Inverser `is_done` immédiatement dans l'UI
3. Recalculer `progress` = somme pondérée des actions done
4. Appeler `toggleAction(taskId, actionId)` (API)
5. Si erreur → rollback (revert `is_done` et `progress`)

### 26.15 États (Loading / Error)

#### `LoadingState.tsx`
- `Card` avec `Loader2` (spinner 32px) + texte "Chargement des tâches..."

#### `ErrorState.tsx`
- `Card` avec texte rouge "Erreur lors du chargement des tâches" + détail en gris

### 26.16 Version Mobile — `MobileDynamicTable.tsx`

#### Structure
- Tabs par statut: "À faire", "En cours", "Bloqué", "Terminée"
- Cartes mobiles (`MobileTaskCard`) au lieu de lignes de tableau
- Bouton "Passer en vue desktop" pour basculer vers la version complète

#### Fonctionnalités
- Mêmes actions que la version desktop: duplication, suppression, toggle action, création sous-tâche
- Filtres simplifiés (search + statut)
- Pas de colonnes d'actions dynamiques (version simplifiée)

### 26.17 Modèle de Données Supabase

#### Tables utilisées

| Table | Champs principaux | Rôle |
|---|---|---|
| `project_tasks` | id, title, status, priority, project_id, parent_id, assignee, start_date, due_date, effort_estimate_h, progress, display_order, task_level, tenant_id | Tâches et sous-tâches |
| `task_actions` | id, task_id, title, weight_percentage, is_done, due_date, notes | Actions pondérées par tâche |
| `task_action_attachments` | id, task_action_id, task_id, tenant_id | Preuves/fichiers attachés à une action |
| `task_documents` | id, task_id, project_id, file_name, file_path, file_size, mime_type, tenant_id, uploader_id | Documents de tâche |
| `task_comments` | id, task_id, content, comment_type, author_id, created_at | Commentaires de tâche |
| `projects` | id, name, color, status, start_date, end_date | Projets |
| `employees` | id, full_name, avatar_url, tenant_id, user_id | Employés (filtrage tenant) |

#### Sécurité
- Toutes les queries filtrent par `tenant_id` (RLS Supabase)
- `AssigneeSelect` filtre strictement par `taskTenantId`
- Upload documents requiert authentification (`supabase.auth.getUser()`)
- `tenant_id` automatiquement rempli par trigger sur insert

### 26.18 Hooks et Utilitaires

| Hook/Util | Fichier | Rôle |
|---|---|---|
| `useTasks()` | `hooks/optimized.ts` | CRUD tâches + actions + sous-tâches, optimistic updates |
| `useProjects()` | `hooks/useProjects.ts` | Liste projets |
| `useEmployees()` | `hooks/useEmployees.ts` | Liste employés (filtrage tenant) |
| `useIsMobile()` | `hooks/use-mobile.ts` | Détection mobile |
| `useTranslation()` | `hooks/useTranslation.ts` | i18n |
| `useRoleBasedAccess()` | `hooks/useRoleBasedAccess.ts` | Permissions par rôle |
| `useTaskEditPermissions()` | `hooks/useTaskEditPermissions.ts` | Permissions d'édition par tâche |
| `useProjectEditPermissions()` | `hooks/useProjectEditPermissions.ts` | Permissions projet (canManageTeam) |
| `useWorkloadAlert()` | `hooks/useWorkloadAlert.ts` | Calcul charge employé |
| `getUniqueActions()` | `lib/taskHelpers.ts` | Extrait actions uniques |
| `priorityColors` | `lib/taskHelpers.ts` | Map priorité → classe CSS badge |
| `statusColors` | `lib/taskHelpers.ts` | Map statut → classe CSS badge |
| `formatDate()` | `lib/taskHelpers.ts` | Formatage date |
| `getTaskStatusLabel()` | `lib/taskHelpers.ts` | Label statut i18n |
| `getTaskPriorityLabel()` | `lib/taskHelpers.ts` | Label priorité i18n |
| `assignProjectColors()` | `lib/ganttColors.ts` | Map project_id → couleur |
| `getTaskColor()` | `lib/ganttColors.ts` | Couleur tâche depuis projectColorMap |

### 26.19 Fonctionnalités à Implémenter pour Compta/Sage100

#### P0 — Essentiel

| Fonctionnalité | Description | Composant source |
|---|---|---|
| **Tableau dual panneau** | Colonnes fixes + colonnes actions dynamiques avec scroll sync | `DynamicTable` + `ResizablePanelGroup` |
| **12 colonnes fixes** | Tâche, Projet, Responsable, Début, Échéance, Priorité, Statut, Charge, Progression, Documents, Commentaires, Actions | `TaskFixedColumns` |
| **Édition inline (5 types)** | Titre (debounce), Date (calendar), Select (badges), Number (debounce), Text (simple) | `cells/*` |
| **Lignes fantômes** | 5 lignes vides pour création rapide inline | `TaskTableBody` |
| **Actions dynamiques pondérées** | Colonnes d'actions avec checkbox + % + upload preuve | `TaskActionColumns` |
| **Calcul progression auto** | Progression = somme pondérée des actions done | `DynamicTable` |
| **Sous-tâches hiérarchiques** | parent_id, display_order, task_level, indentation visuelle | `TaskRow` + `EditableTitleCell` |
| **Dialog création sous-tâche** | Titre, dates, charge, responsable, liaison action, actions propres | `SubtaskCreationDialog` |
| **Dialog création action** | Titre, poids (slider), échéance, notes | `ActionCreationDialog` |
| **Upload documents** | Supabase Storage + métadonnées en base | `DocumentCellColumn` |
| **Commentaires** | Add/list/delete avec temps relatif | `CommentCellColumn` |
| **Sélecteur assigné sécurisé** | Filtrage tenant_id, workload alert, invitation | `AssigneeSelect` |
| **Permissions par tâche** | readOnly sur cellules si pas de permission | `useTaskEditPermissions` |
| **Filtres avancés** | Search, status, priority, assignee, project, dates + localStorage | `AdvancedFilters` |
| **Export CSV/Excel** | Avec filtres appliqués | `ExportButton` |
| **Mode dual Tasks/Projects** | ToggleGroup pour bascule | `DynamicTable` |
| **États loading/error** | Spinner + message erreur | `LoadingState` + `ErrorState` |
| **i18n complet** | Toutes les clés en fr/en/ar | `useTranslation` |

#### P1 — Important

| Fonctionnalité | Description | Composant source |
|---|---|---|
| **Version mobile** | Tabs par statut + cartes mobile | `MobileDynamicTable` |
| **Color coding projet** | Badge coloré par projet avec `projectColorMap` | `TaskRow` |
| **Avatar assigné** | Avatar + fallback 2 lettres | `SimpleAssigneeDisplay` |
| **Indicateur sauvegarde** | Spinner/check/erreur sur cellules éditables | `EditableCellWithDebounce` |
| **Réorganisation colonnes actions** | Actions de la tâche sélectionnée en premier | `TaskActionColumns` |
| **Preuve requise** | Checkbox désactivée si 0 fichier attaché | `TaskActionColumns` |
| **Workload alert** | AlertTriangle sur employé surchargé | `AssigneeSelect` |
| **Menu actions ligne** | Edit, Dupliquer, Supprimer (dropdown) | `TaskRowActions` |
| **Dialog détails tâche** | Vue détaillée sur double-clic | `TaskDialogManager` |
| **Panneaux latéraux** | Documents et commentaires en panneau latéral (alternative) | `DocumentsColumn` + `CommentsColumn` |

#### P2 — Améliorations

| Fonctionnalité | Description |
|---|---|
| **Redistribution poids auto** | Bouton "Redistribuer équitablement" dans dialog sous-tâche |
| **Validation somme poids = 100%** | Indicateur visuel vert/rouge |
| **Liaison action parent** | Sous-tâche liée à une action spécifique du parent |
| **Actions avec échéance + notes** | Actions avec date proprete et notes optionnelles |
| **Compteur fichiers par action** | Badge vert avec nombre de preuves |
| **Tooltip actions** | Tooltip avec titre complet (header tronqué) |
| **Style sélection** | Ring jaune sur action de tâche sélectionnée |
| **Scroll horizontal header sync** | Header scroll horizontalement avec le body |

### 26.20 i18n — Clés de Traduction à Prévoir

Namespace: `taskManagement` (tableau dynamique)

```
taskManagement.dynamicTable.title           → "Tableau Dynamique d'Exécution"
taskManagement.dynamicTable.newTask         → "Nouvelle Tâche"
taskManagement.dynamicTable.selectedTask    → "Tâche sélectionnée"
taskManagement.dynamicTable.quickAction     → "Action rapide..."
taskManagement.dynamicTable.detailedAction  → "Action Détaillée"
taskManagement.dynamicTable.noActionColumn  → "Aucune colonne d'action"
taskManagement.dynamicTable.addColumnHint   → "Sélectionnez une tâche et ajoutez une colonne d'action via le header"
taskManagement.dynamicTable.ghostPlaceholder → "+ Ajouter une nouvelle tâche..."
taskManagement.dynamicTable.taskPlaceholder → "Nom de la tâche..."
taskManagement.dynamicTable.loading         → "Chargement des tâches..."
taskManagement.dynamicTable.error           → "Erreur lors du chargement des tâches"
taskManagement.dynamicTable.export          → "Exporter"
taskManagement.dynamicTable.noProject       → "Aucun projet"
taskManagement.dynamicTable.unassigned      → "Non assigné"
taskManagement.dynamicTable.inviteCollaborator → "Inviter un collaborateur"
taskManagement.dynamicTable.proofRequired   → "Document requis"
taskManagement.dynamicTable.proofRequiredDesc → "Veuillez uploader au moins un document de preuve avant de marquer cette action comme terminée."
taskManagement.dynamicTable.filesAttached   → "fichier(s)"
taskManagement.dynamicTable.addProof        → "Ajouter un document de preuve (requis)"
taskManagement.dynamicTable.documents       → "Documents"
taskManagement.dynamicTable.comments        → "Commentaires"
taskManagement.dynamicTable.addComment      → "Ajouter un commentaire..."
taskManagement.dynamicTable.send            → "Envoyer"
taskManagement.dynamicTable.sending         → "Envoi..."
taskManagement.dynamicTable.noComment       → "Aucun commentaire"
taskManagement.dynamicTable.upload          → "Upload"
taskManagement.dynamicTable.uploading       → "Upload..."
taskManagement.dynamicTable.download        → "Télécharger"
taskManagement.dynamicTable.delete          → "Supprimer"
taskManagement.dynamicTable.edit            → "Modifier"
taskManagement.dynamicTable.duplicate       → "Dupliquer"
taskManagement.dynamicTable.createSubtask   → "Créer une Sous-tâche"
taskManagement.dynamicTable.subtaskOf       → "Sous-tâche de"
taskManagement.dynamicTable.parentTask      → "Tâche parent"
taskManagement.dynamicTable.inheritedAssignee → "Responsable hérité"
taskManagement.dynamicTable.linkAction      → "Lier à une action de la tâche parent (optionnel)"
taskManagement.dynamicTable.noLink          → "Aucune liaison"
taskManagement.dynamicTable.linkHint        → "Cette sous-tâche contribuera à l'accomplissement de l'action sélectionnée"
taskManagement.dynamicTable.addAction       → "Ajouter une action à cette sous-tâche"
taskManagement.dynamicTable.actionTitle     → "Nom de l'action"
taskManagement.dynamicTable.weight          → "Poids"
taskManagement.dynamicTable.dueDate         → "Échéance"
taskManagement.dynamicTable.notes           → "Notes"
taskManagement.dynamicTable.redistribute    → "Redistribuer équitablement"
taskManagement.dynamicTable.totalWeight     → "Total des poids"
taskManagement.dynamicTable.weightValid     → "Parfait ! Les actions totalisent 100%"
taskManagement.dynamicTable.weightInvalid   → "Doit être égal à 100% pour valider"
taskManagement.dynamicTable.estimatedEffort → "Charge estimée (heures)"
taskManagement.dynamicTable.responsible     → "Responsable"
taskManagement.dynamicTable.responsibleRequired → "Un responsable doit être assigné à la sous-tâche"
taskManagement.dynamicTable.createButton    → "Créer la Sous-tâche"
taskManagement.dynamicTable.createAction    → "Créer l'Action"
taskManagement.dynamicTable.cancel          → "Annuler"
taskManagement.dynamicTable.titleRequired   → "Le titre est obligatoire"
taskManagement.dynamicTable.selectDate      → "Sélectionner une date"
taskManagement.dynamicTable.noDate          → "-"
taskManagement.dynamicTable.saveError       → "Erreur de sauvegarde"
taskManagement.dynamicTable.editNotAllowed  → "Modification non autorisée"
taskManagement.dynamicTable.viewDesktop     → "Passer en vue desktop"
taskManagement.dynamicTable.colTodo         → "À faire"
taskManagement.dynamicTable.colDoing        → "En cours"
taskManagement.dynamicTable.colBlocked      → "Bloqué"
taskManagement.dynamicTable.colDone         → "Terminée"
taskManagement.dynamicTable.priorityLow     → "Basse"
taskManagement.dynamicTable.priorityMedium  → "Moyenne"
taskManagement.dynamicTable.priorityHigh    → "Haute"
taskManagement.dynamicTable.priorityUrgent  → "Urgente"
```

> **Note** : Toutes ces clés doivent être déclinées en **fr** (défaut), **en** et **ar** (RTL) dans les fichiers `app/src/i18n/locales/{fr,en,ar}/taskManagement.json`.

---

## 27. Plan d'Implémentation — Module Gestion de Projets & Tâches (Tableau Dynamique + Kanban + Gantt)

> **Objectif** : Implémenter le module complet de gestion de projets et tâches (tableau dynamique, kanban, gantt) dans Compta/Sage100 en adaptant les composants Wadashaqayn au design system existant.
> **Principe directeur** : **Harmonisation totale** — utiliser le design system existant de Compta (CSS variables, composants `ui.tsx`, classes Tailwind v4), pas importer shadcn/ui de Wadashaqayn.

### 27.1 État Actuel du Projet Compta

#### Design System existant
- **CSS Variables** : `--color-primary: #0066cc`, `--color-success`, `--color-warning`, `--color-danger`, `--color-neutral-50` à `--color-neutral-900`, `--color-surface`, `--color-background`, `--color-text`, `--color-text-secondary`, `--color-border`
- **Composants UI** (`@/components/ui`) : `Card`, `StatCard`, `Badge` (5 variants), `Button` (4 variants, 3 sizes), `Input`, `Select`, `Table`, `SortableTable`, `TableRow`, `TableCell`, `EmptyState`, `PageHeader`, `Breadcrumb`, `Skeleton`, `SkeletonCard`, `SkeletonTable`
- **Classes CSS** : `.card`, `.btn`, `.btn-primary`, `.btn-secondary`, `.btn-danger`, `.btn-ghost`, `.input`, `.badge`, `.badge-*`, `.table-container`, `.app-table`
- **Typographie** : Inter (sans), ui-monospace (mono), Noto Sans Arabic (ar)
- **Border radius** : `--radius-sm: 4px`, `--radius-md: 8px`, `--radius-lg: 12px`
- **Shadows** : `--shadow-sm`, `--shadow-md`, `--shadow-lg`

#### Modules existants
- **ProjectsPage** (`/accounting/projects`) : Table simple (name, customer, budget, actual_cost, profitability, status, delete) — **à remplacer** par le module complet
- **PlanningPage** (`/production/planning`) : Gantt simplifié en barres CSS pour ordres de fabrication — **à conserver**, le nouveau Gantt sera dans le module projets
- **OpportunitiesPage** (`/crm/opportunities`) : Kanban basique pour opportunités CRM — **à conserver**, le nouveau Kanban sera dans le module projets

#### Dépendances installées
- React 19, react-router-dom v7, react-i18next, @supabase/supabase-js, date-fns, lucide-react, recharts, xlsx, tailwindcss v4
- **Manquantes** : `@dnd-kit/core`, `@dnd-kit/sortable`, `@dnd-kit/utilities` (pour Kanban drag-and-drop)

#### i18n
- 21 namespaces existants (accounting, common, nav, sales, etc.)
- **Nouveau namespace requis** : `taskManagement` (fr/en/ar)

### 27.2 Architecture Cible — Harmonisation

#### Structure des fichiers à créer

```
app/src/
├── components/
│   └── project-management/           ← Nouveau dossier module
│       ├── ProjectManagementHub.tsx       (page hub avec bascule vues)
│       ├── DynamicTable.tsx               (tableau dynamique dual panneau)
│       ├── TaskTableHeader.tsx            (barre d'outils)
│       ├── TaskFixedColumns.tsx           (12 colonnes fixes)
│       ├── TaskTableBody.tsx              (corps + lignes fantômes)
│       ├── TaskRow.tsx                    (ligne individuelle)
│       ├── TaskActionColumns.tsx          (colonnes actions dynamiques)
│       ├── TaskRowActions.tsx             (menu actions ligne)
│       ├── KanbanBoard.tsx                (kanban avec drag-and-drop)
│       ├── KanbanColumn.tsx               (colonne kanban)
│       ├── KanbanCard.tsx                 (carte kanban)
│       ├── GanttChart.tsx                 (gantt principal)
│       ├── GanttHeader.tsx                (contrôles gantt)
│       ├── GanttTimeline.tsx              (timeline gantt)
│       ├── GanttTaskBar.tsx               (barre tâche gantt)
│       ├── GanttTaskList.tsx              (liste tâches gantt)
│       ├── SubtaskCreationDialog.tsx      (dialog sous-tâche)
│       ├── ActionCreationDialog.tsx       (dialog action)
│       ├── TaskDetailsDialog.tsx          (dialog détails tâche)
│       ├── AssigneeSelect.tsx             (sélecteur assigné)
│       ├── DocumentCellColumn.tsx         (cellule documents)
│       ├── CommentCellColumn.tsx          (cellule commentaires)
│       ├── LoadingState.tsx               (état chargement)
│       ├── ErrorState.tsx                 (état erreur)
│       └── cells/
│           ├── EditableCell.tsx
│           ├── EditableCellWithDebounce.tsx
│           ├── EditableTitleCell.tsx
│           ├── EditableDateCell.tsx
│           └── EditableSelectCell.tsx
├── hooks/
│   ├── useTasks.ts                        (CRUD tâches + actions)
│   ├── useProjects.ts                     (CRUD projets étendu)
│   ├── useTaskFilters.ts                  (filtres avancés + localStorage)
│   ├── useGanttDrag.ts                    (drag gantt)
│   ├── useTaskEditPermissions.ts          (permissions)
│   └── useWorkloadAlert.ts                (charge employés)
├── lib/
│   ├── queries/
│   │   └── projectManagement.ts           (queries Supabase)
│   ├── ganttHelpers.ts                    (types + utils gantt)
│   └── ganttColors.ts                     (palette couleurs projets)
├── types/
│   └── projectManagement.ts               (types TypeScript)
├── pages/
│   └── ProjectManagementPage.tsx          (page wrapper pour routing)
├── i18n/locales/{fr,en,ar}/
│   └── taskManagement.json                (60+ clés i18n)
└── sql/
    └── 30_project_management.sql          (migration SQL)
```

#### Règles d'harmonisation avec le design existant

| Aspect | Wadashaqayn (source) | Compta (cible) |
|---|---|---|
| **Composants UI** | shadcn/ui (`@/components/ui/*`) | Composants existants (`@/components/ui.tsx`) |
| **Card** | `<Card>` shadcn | `<Card>` de `ui.tsx` avec `.card` class |
| **Button** | `<Button>` shadcn (variants) | `<Button>` de `ui.tsx` (4 variants, 3 sizes) |
| **Badge** | `<Badge>` shadcn | `<Badge>` de `ui.tsx` (5 variants) |
| **Input** | `<Input>` shadcn | `<Input>` de `ui.tsx` avec `.input` class |
| **Select** | `<Select>` shadcn | `<Select>` de `ui.tsx` |
| **Table** | `<Table>`, `<TableRow>`, `<TableCell>` shadcn | `<Table>`, `<TableRow>`, `<TableCell>` de `ui.tsx` |
| **Dialog/Modal** | `ResponsiveModal` shadcn | `fixed inset-0 bg-black/50` pattern existant (comme `ProjectForm`) |
| **Popover** | shadcn `Popover` | **À créer** : composant `Popover` simple avec `useState` + `useRef` + click outside |
| **DropdownMenu** | shadcn `DropdownMenu` | **À créer** : composant `DropdownMenu` simple |
| **Checkbox** | shadcn `Checkbox` | `<input type="checkbox">` styled avec CSS variables |
| **Progress** | shadcn `Progress` | `<div>` avec width % + couleur CSS variable |
| **ScrollArea** | shadcn `ScrollArea` | `<div className="overflow-y-auto">` |
| **Avatar** | shadcn `Avatar` | `<div>` avec initiales + couleur background |
| **Toast** | `useToast` shadcn | `useToast` de `@/lib/toast` (existant) |
| **Colors** | `bg-primary`, `text-destructive` (shadcn) | `bg-[var(--color-primary)]`, `text-[var(--color-danger)]` |
| **Spacing** | shadcn spacing tokens | Tailwind spacing (p-4, gap-2, etc.) |
| **Border radius** | shadcn `rounded-lg` | `rounded-[var(--radius-md)]` ou Tailwind `rounded-md` |
| **Shadow** | shadcn `shadow-md` | `shadow-[var(--shadow-md)]` ou `.card` class |
| **i18n** | `useTranslation` custom | `useTranslation` de `react-i18next` (existant) |
| **Icons** | `@/lib/icons` (re-exports) | `lucide-react` direct (existant) |
| **Dates** | `date-fns` + locale fr | `date-fns` + `useLocale` hook (existant) |
| **Resizable panels** | `ResizablePanelGroup` shadcn | **À créer** : simple flex avec drag handle |
| **Drag-and-drop** | `@dnd-kit/core` | **À installer** : `@dnd-kit/core` + `@dnd-kit/sortable` |

### 27.3 Sprints d'Implémentation

#### Sprint 1 — Fondation SQL + Types + Dependencies (3-4h)

| Tâche | Détail | Fichier |
|---|---|---|
| **1.1** Installer dépendances | `npm install @dnd-kit/core @dnd-kit/sortable @dnd-kit/utilities` | `package.json` |
| **1.2** Migration SQL — Tables | Créer `project_tasks`, `task_actions`, `task_action_attachments`, `task_documents`, `task_comments` avec RLS + indexes | `app/sql/30_project_management.sql` |
| **1.3** Migration SQL — Projects | Étendre table `projects` existante : ajouter `color`, `display_order`, `progress` | `app/sql/30_project_management.sql` |
| **1.4** Types TypeScript | `ProjectTask`, `TaskAction`, `TaskActionAttachment`, `TaskDocument`, `TaskComment`, `ProjectExtended`, `TaskFilters`, `ViewMode`, `GanttTask` | `app/src/types/projectManagement.ts` |
| **1.5** Queries Supabase | `getTasks`, `createTask`, `updateTask`, `deleteTask`, `duplicateTask`, `toggleAction`, `addActionColumn`, `addDetailedAction`, `createSubTask`, `getTaskDocuments`, `uploadTaskDocument`, `getTaskComments`, `addTaskComment`, `getTaskActionAttachments` | `app/src/lib/queries/projectManagement.ts` |
| **1.6** Hook useTasks | CRUD complet avec optimistic updates | `app/src/hooks/useTasks.ts` |
| **1.7** Hook useProjects | Étendre avec `color`, `progress`, `display_order` | `app/src/hooks/useProjects.ts` |

**Détail migration SQL :**

```sql
-- 30_project_management.sql

-- Étendre projects existant
ALTER TABLE projects ADD COLUMN IF NOT EXISTS color VARCHAR(7) DEFAULT '#0066cc';
ALTER TABLE projects ADD COLUMN IF NOT EXISTS display_order VARCHAR(50) DEFAULT '0';
ALTER TABLE projects ADD COLUMN IF NOT EXISTS progress INTEGER DEFAULT 0;

-- Table: project_tasks
CREATE TABLE IF NOT EXISTS project_tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  project_id UUID REFERENCES projects(id) ON DELETE SET NULL,
  parent_id UUID REFERENCES project_tasks(id) ON DELETE CASCADE,
  title VARCHAR(200) NOT NULL,
  description TEXT,
  status VARCHAR(20) NOT NULL DEFAULT 'todo',
  priority VARCHAR(20) NOT NULL DEFAULT 'medium',
  assignee VARCHAR(200),
  start_date DATE,
  due_date DATE,
  effort_estimate_h DECIMAL(5,1) DEFAULT 0,
  progress INTEGER DEFAULT 0,
  display_order VARCHAR(50) NOT NULL DEFAULT '0',
  task_level INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Table: task_actions
CREATE TABLE IF NOT EXISTS task_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  task_id UUID NOT NULL REFERENCES project_tasks(id) ON DELETE CASCADE,
  title VARCHAR(100) NOT NULL,
  weight_percentage INTEGER DEFAULT 0,
  is_done BOOLEAN DEFAULT FALSE,
  due_date DATE,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Table: task_action_attachments
CREATE TABLE IF NOT EXISTS task_action_attachments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  task_action_id UUID NOT NULL REFERENCES task_actions(id) ON DELETE CASCADE,
  task_id UUID NOT NULL REFERENCES project_tasks(id) ON DELETE CASCADE,
  file_name VARCHAR(255) NOT NULL,
  file_path VARCHAR(500) NOT NULL,
  file_size BIGINT,
  mime_type VARCHAR(100),
  uploader_id UUID,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Table: task_documents
CREATE TABLE IF NOT EXISTS task_documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  task_id UUID NOT NULL REFERENCES project_tasks(id) ON DELETE CASCADE,
  project_id UUID REFERENCES projects(id) ON DELETE SET NULL,
  file_name VARCHAR(255) NOT NULL,
  file_path VARCHAR(500) NOT NULL,
  file_size BIGINT,
  mime_type VARCHAR(100),
  uploader_id UUID,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Table: task_comments
CREATE TABLE IF NOT EXISTS task_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  task_id UUID NOT NULL REFERENCES project_tasks(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  comment_type VARCHAR(20) DEFAULT 'general',
  author_id UUID,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_project_tasks_tenant ON project_tasks(tenant_id);
CREATE INDEX idx_project_tasks_project ON project_tasks(project_id);
CREATE INDEX idx_project_tasks_parent ON project_tasks(parent_id);
CREATE INDEX idx_project_tasks_display_order ON project_tasks(display_order);
CREATE INDEX idx_task_actions_task ON task_actions(task_id);
CREATE INDEX idx_task_action_attachments_action ON task_action_attachments(task_action_id);
CREATE INDEX idx_task_documents_task ON task_documents(task_id);
CREATE INDEX idx_task_comments_task ON task_comments(task_id);

-- RLS Policies
ALTER TABLE project_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_action_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_comments ENABLE ROW LEVEL SECURITY;

-- Policies (same pattern as existing tables)
CREATE POLICY project_tasks_select ON project_tasks FOR SELECT USING (tenant_id = get_current_tenant_id());
CREATE POLICY project_tasks_insert ON project_tasks FOR INSERT WITH CHECK (tenant_id = get_current_tenant_id());
CREATE POLICY project_tasks_update ON project_tasks FOR UPDATE USING (tenant_id = get_current_tenant_id());
CREATE POLICY project_tasks_delete ON project_tasks FOR DELETE USING (tenant_id = get_current_tenant_id());
-- (répéter pour task_actions, task_action_attachments, task_documents, task_comments)

-- Trigger updated_at
CREATE TRIGGER project_tasks_updated_at BEFORE UPDATE ON project_tasks FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
```

#### Sprint 2 — Composants UI Réutilisables (2-3h)

| Tâche | Détail | Fichier |
|---|---|---|
| **2.1** Popover | Composant simple avec `useState` + click outside via `useRef` | `app/src/components/project-management/Popover.tsx` |
| **2.2** DropdownMenu | Composant simple avec items + icons | `app/src/components/project-management/DropdownMenu.tsx` |
| **2.3** Modal/Dialog** | Réutiliser pattern existant `fixed inset-0 bg-black/50` (comme `ProjectForm`) | Pattern inline dans chaque dialog |
| **2.4** ResizablePanel | Simple flex avec drag handle (2 panneaux redimensionnables) | `app/src/components/project-management/ResizablePanel.tsx` |
| **2.5** Progress bar** | `<div>` avec width % + `bg-[var(--color-primary)]` | Inline dans `TaskRow` |
| **2.6** Avatar** | `<div>` avec initiales + `bg-[var(--color-primary)] text-white` | Inline dans `AssigneeSelect` |

#### Sprint 3 — Cellules Éditables + Hooks (3-4h)

| Tâche | Détail | Fichier |
|---|---|---|
| **3.1** EditableCell | Cellule éditable simple (text/number) avec `useTranslation` | `cells/EditableCell.tsx` |
| **3.2** EditableCellWithDebounce | Cellule avec debounce 800ms + indicateurs visuels (spinner/check/erreur) | `cells/EditableCellWithDebounce.tsx` |
| **3.3** EditableTitleCell | Cellule titre avec bouton +/-, `display_order`, indentation, debounce | `cells/EditableTitleCell.tsx` |
| **3.4** EditableDateCell | Cellule date avec Popover + Calendar (date-fns) | `cells/EditableDateCell.tsx` |
| **3.5** EditableSelectCell | Cellule select avec DropdownMenu + Badge coloré | `cells/EditableSelectCell.tsx` |
| **3.6** useTaskFilters | Filtres avancés (search, status, priority, assignee, project, dates) + localStorage | `hooks/useTaskFilters.ts` |
| **3.7** useTaskEditPermissions | Permissions par rôle (admin, manager, employee) | `hooks/useTaskEditPermissions.ts` |
| **3.8** useWorkloadAlert | Calcul charge employé (count tasks + effort) | `hooks/useWorkloadAlert.ts` |
| **3.9** ganttHelpers | Types `ViewMode`, `GanttTask`, `ViewConfig`, fonctions calcul position/largeur | `lib/ganttHelpers.ts` |
| **3.10** ganttColors | Palette 45 couleurs + `assignProjectColors()` + `getTaskColor()` | `lib/ganttColors.ts` |

#### Sprint 4 — Tableau Dynamique (4-5h)

| Tâche | Détail | Fichier |
|---|---|---|
| **4.1** DynamicTable | Conteneur principal avec `useTasks`, `useProjects`, `useTaskFilters`, layout dual panneau (ResizablePanel), scroll sync, mode tasks/projects | `DynamicTable.tsx` |
| **4.2** TaskTableHeader | Barre d'outils : nouvelle tâche, action rapide, action détaillée, export CSV (xlsx) | `TaskTableHeader.tsx` |
| **4.3** TaskFixedColumns | 12 colonnes fixes avec header sticky + gradient `from-[var(--color-primary)] to-[var(--color-primary-dark)]` | `TaskFixedColumns.tsx` |
| **4.4** TaskTableBody | Tri par `display_order`, 5 lignes fantômes, délégation vers `TaskRow` | `TaskTableBody.tsx` |
| **4.5** TaskRow | Ligne individuelle avec 12 colonnes, permissions, édition inline, badges, avatar, documents, commentaires, actions | `TaskRow.tsx` |
| **4.6** TaskActionColumns | Colonnes actions dynamiques, checkbox + %, upload preuve, réorganisation contextuelle | `TaskActionColumns.tsx` |
| **4.7** TaskRowActions | Menu dropdown : Modifier, Dupliquer, Supprimer | `TaskRowActions.tsx` |
| **4.8** AssigneeSelect | Popover avec liste employés filtrés par tenant, workload alert | `AssigneeSelect.tsx` |
| **4.9** DocumentCellColumn | Upload Supabase Storage + dialog liste + download | `DocumentCellColumn.tsx` |
| **4.10** CommentCellColumn | Dialog commentaires avec ScrollArea + Textarea | `CommentCellColumn.tsx` |
| **4.11** SubtaskCreationDialog | Formulaire complet avec redistribution poids auto | `SubtaskCreationDialog.tsx` |
| **4.12** ActionCreationDialog | Slider poids + échéance + notes | `ActionCreationDialog.tsx` |
| **4.13** LoadingState + ErrorState | États chargement/erreur avec composants existants | `LoadingState.tsx` + `ErrorState.tsx` |

#### Sprint 5 — Kanban Board (2-3h)

| Tâche | Détail | Fichier |
|---|---|---|
| **5.1** KanbanBoard | Board avec `@dnd-kit/core`, 4 colonnes (todo, doing, blocked, done), mode tasks/projects, filtres | `KanbanBoard.tsx` |
| **5.2** KanbanColumn | Colonne avec header coloré, compteur, liste cartes scrollable, drop zone | `KanbanColumn.tsx` |
| **5.3** KanbanCard | Carte avec titre, badges (projet, priorité), avatar, barre progression, due date | `KanbanCard.tsx` |

#### Sprint 6 — Gantt Chart (3-4h)

| Tâche | Détail | Fichier |
|---|---|---|
| **6.1** GanttChart | Conteneur avec `useGanttDrag`, view modes (day/week/month/quarter/year), scroll sync, mode tasks/projects | `GanttChart.tsx` |
| **6.2** GanttHeader | Contrôles : toggle view mode, année buffer, bascule tasks/projects | `GanttHeader.tsx` |
| **6.3** GanttTimeline | Timeline avec grille, barres tâches/projets, lignes de dépendances SVG | `GanttTimeline.tsx` |
| **6.4** GanttTaskBar | Barre tâche avec drag + resize, progression, couleur projet | `GanttTaskBar.tsx` |
| **6.5** GanttTaskList | Liste tâches/projets à gauche avec regroupement par projet + hiérarchie | `GanttTaskList.tsx` |
| **6.6** useGanttDrag | Hook drag + resize avec optimistic updates + rollback | `hooks/useGanttDrag.ts` |

#### Sprint 7 — Page Hub + Routing + Navigation + i18n (2-3h)

| Tâche | Détail | Fichier |
|---|---|---|
| **7.1** ProjectManagementHub | Page hub avec bascule 3 vues (Tableau/Kanban/Gantt) via `ToggleGroup` ou boutons, filtres partagés | `ProjectManagementHub.tsx` |
| **7.2** ProjectManagementPage | Wrapper pour routing | `pages/ProjectManagementPage.tsx` |
| **7.3** Routes App.tsx | Ajouter routes `/projects`, `/projects/table`, `/projects/kanban`, `/projects/gantt` | `App.tsx` |
| **7.4** Sidebar navigation | Ajouter module "Gestion de Projets" avec icône `FolderKanban` | `Sidebar.tsx` |
| **7.5** i18n taskManagement.json | 60+ clés en fr/en/ar (voir section 26.20) | `i18n/locales/{fr,en,ar}/taskManagement.json` |
| **7.6** i18n nav.json | Ajouter clés navigation pour le module projets | `i18n/locales/{fr,en,ar}/nav.json` |
| **7.7** Remplacer ProjectsPage | L'ancienne `ProjectsPage` redirige vers `/projects` ou est intégrée au hub | `ProjectsPage.tsx` |

#### Sprint 8 — Intégration Cross-Module + Harmonisation (2-3h)

| Tâche | Détail | Fichier |
|---|---|---|
| **8.1** Lien Projects → Compta | Associer projets à clients (table `customers`), budgets, coûts réels | `projectManagement.ts` |
| **8.2** Lien Tasks → Employés | Utiliser table `employees` existante pour assignation | `AssigneeSelect.tsx` |
| **8.3** Lien Tasks → Production | Option : lier une tâche à un ordre de fabrication (MO) | Types + queries |
| **8.4** Export CSV/Excel | Utiliser `xlsx` déjà installé pour export tâches filtrées | `TaskTableHeader.tsx` |
| **8.5** Responsive mobile | Détection mobile avec `window.innerWidth` + versions simplifiées (tabs par statut) | `DynamicTable.tsx` |
| **8.6** Dark mode ready** | Utiliser CSS variables (déjà définies) pour support dark mode futur | Tous composants |
| **8.7** Accessibility** | ARIA labels, keyboard navigation (Enter/Escape/Tab), focus visible | Tous composants |

#### Sprint 9 — Tests + Validation (2h)

| Tâche | Détail |
|---|---|
| **9.1** Tests unitaires | `useTasks` hook, `ganttHelpers` functions, `getUniqueActions` |
| **9.2** Test E2E | Créer tâche, éditer inline, toggle action, drag kanban, drag gantt |
| **9.3** `tsc --noEmit` | Validation TypeScript sans erreurs |
| **9.4** `npm run dev` | Démarrage dev server sans erreurs |
| **9.5** Browser preview | Test visuel des 3 vues + interactions |
| **9.6** Test i18n | Vérifier fr/en/ar sur toutes les pages |
| **9.7** Test RLS | Vérifier isolation tenant sur toutes les queries |

### 27.4 Modèle de Données — Schéma Complet

```
┌─────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  projects   │────<│  project_tasks   │────<│  task_actions    │
│ (étendu)    │     │  (tâches)        │     │  (actions)       │
├─────────────┤     ├──────────────────┤     ├──────────────────┤
│ id          │     │ id               │     │ id               │
│ name        │     │ project_id ──────┘     │ task_id ─────────┘
│ description │     │ parent_id (self-ref)   │ title             │
│ customer_id │     │ title                  │ weight_percentage │
│ status      │     │ status                 │ is_done           │
│ budget      │     │ priority               │ due_date          │
│ actual_cost │     │ assignee               │ notes             │
│ start_date  │     │ start_date             └──────────────────┘
│ end_date    │     │ due_date                         │
│ color (NEW) │     │ effort_estimate_h                │
│ progress(N) │     │ progress (auto-calc)             │
│ display_ord │     │ display_order                    │
│ tenant_id   │     │ task_level                       │
└─────────────┘     │ tenant_id                        │
                    └──────────────────┘               │
                              │                        │
                    ┌─────────┴──────────┐    ┌────────┴───────────────┐
                    │ task_documents     │    │ task_action_attachments│
                    │ (docs tâche)       │    │ (preuves action)       │
                    ├────────────────────┤    ├────────────────────────┤
                    │ id                 │    │ id                     │
                    │ task_id            │    │ task_action_id         │
                    │ project_id         │    │ task_id                │
                    │ file_name          │    │ file_name              │
                    │ file_path          │    │ file_path              │
                    │ file_size          │    │ file_size              │
                    │ mime_type          │    │ mime_type              │
                    │ tenant_id          │    │ tenant_id              │
                    │ uploader_id        │    │ uploader_id            │
                    └────────────────────┘    └────────────────────────┘
                    ┌────────────────────┐
                    │ task_comments      │
                    │ (commentaires)     │
                    ├────────────────────┤
                    │ id                 │
                    │ task_id            │
                    │ content            │
                    │ comment_type       │
                    │ author_id          │
                    │ tenant_id          │
                    └────────────────────┘
```

### 27.5 Harmonisation Cross-Module

#### Interactions entre modules

```
┌─────────────────────────────────────────────────────────────────────┐
│                     MODULE GESTION DE PROJETS                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                          │
│  │ Tableau  │  │ Kanban   │  │ Gantt    │  ← 3 vues partagées     │
│  │ Dynamique│  │ Board    │  │ Chart    │    (mêmes données)       │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘                          │
│       └──────────────┴──────────────┘                               │
│                     │                                               │
├─────────────────────┼───────────────────────────────────────────────┤
│                     │                                               │
│  ┌──────────────────▼──────────────────┐                            │
│  │ project_tasks + task_actions        │                            │
│  └──────────────────┬──────────────────┘                            │
│                     │                                               │
├─────────────────────┼───────────────────────────────────────────────┤
│                     │                                               │
│  ┌──────────────────▼──────────────────┐                            │
│  │ projects (étendu)                   │                            │
│  └────┬──────────────┬──────────────────┘                            │
│       │              │                                               │
│  ┌────▼─────┐  ┌─────▼──────┐  ┌──────────────┐  ┌──────────────┐  │
│  │customers │  │ employees  │  │ production   │  │ accounting   │  │
│  │(CRM)     │  │(RH)        │  │(MO/Planning) │  │(budgets/     │  │
│  │          │  │            │  │              │  │ coûts)       │  │
│  └──────────┘  └────────────┘  └──────────────┘  └──────────────┘  │
│                                                                     │
│  Assigné → employé RH                                               │
│  Projet → client CRM + budget compta                                │
│  Tâche → option: lien OF production                                 │
│  Export → CSV/Excel (xlsx)                                          │
└─────────────────────────────────────────────────────────────────────┘
```

#### Points d'intégration

| Module | Intégration | Implémentation |
|---|---|---|
| **CRM (Customers)** | Projet lié à un client | `projects.customer_id` → `customers.id` (déjà existant) |
| **RH (Employees)** | Assigné = employé | `project_tasks.assignee` → `employees.id` ou `employees.full_name` |
| **Compta (Budgets)** | Budget vs coût réel | `projects.budget` + `projects.actual_cost` (déjà existant) |
| **Production (MO)** | Tâche liée à un OF | `project_tasks.manufacturing_order_id` (optionnel, à ajouter) |
| **Production (Planning)** | Gantt production séparé | Conserver `PlanningPage` existant, le nouveau Gantt est dans projets |
| **Sidebar** | Nouveau module dans la navigation | Section "Gestion de Projets" avec sous-menu Tableau/Kanban/Gantt |
| **Export** | Export tâches filtrées | Utiliser `xlsx` déjà installé |
| **Toast** | Notifications | Utiliser `useToast` de `@/lib/toast` (existant) |
| **i18n** | 3 langues | Nouveau namespace `taskManagement` + clés `nav` |

### 27.6 Design Harmonisé — Spécifications

#### Page Hub (`ProjectManagementHub`)

```
┌─────────────────────────────────────────────────────────────────────┐
│  [Breadcrumb] Gestion de Projets                                    │
│                                                                     │
│  Gestion de Projets                              [Tableau] [Kanban] │
│  Suivez et gérez vos projets et tâches          [Gantt]  [+ Nouv.]  │
│                                                                     │
│  [Recherche...]  [Statut▼]  [Priorité▼]  [Assigné▼]  [Projet▼]     │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    VUE ACTIVE                               │   │
│  │              (Tableau / Kanban / Gantt)                     │   │
│  │                                                             │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

#### Palette de couleurs par statut (harmonisée avec CSS variables)

| Statut | Couleur | CSS |
|---|---|---|
| `todo` (À faire) | Neutre | `badge-neutral` |
| `doing` (En cours) | Warning | `badge-warning` |
| `blocked` (Bloqué) | Danger | `badge-danger` |
| `done` (Terminé) | Success | `badge-success` |

#### Palette par priorité

| Priorité | Couleur | CSS |
|---|---|---|
| `low` (Basse) | Neutre | `badge-neutral` |
| `medium` (Moyenne) | Primary | `badge-primary` |
| `high` (Haute) | Warning | `badge-warning` |
| `urgent` (Urgente) | Danger | `badge-danger` |

#### Header du tableau (gradient harmonisé)

```css
/* Au lieu de from-primary to-violet-600 (Wadashaqayn) */
background: linear-gradient(to right, var(--color-primary), var(--color-primary-dark));
color: white;
```

#### Cellules éditables — indicateurs de sauvegarde

| État | Visuel | CSS |
|---|---|---|
| `saving` | Spinner `Loader2` bleu | `text-[var(--color-primary)] animate-spin` |
| `saved` | Check `Check` vert | `text-[var(--color-success)]` |
| `error` | ✗ rouge | `text-[var(--color-danger)]` |
| `editing` | Ring bleu | `ring-2 ring-[var(--color-primary)]` |

### 27.7 Checklist de Qualité

#### Avant chaque sprint
- [ ] `tsc --noEmit` passe sans erreur
- [ ] Tous les nouveaux composants utilisent `useTranslation`
- [ ] Toutes les queries filtrent par `tenant_id`
- [ ] Aucune chaîne hardcodée en français (utiliser `t('key')`)
- [ ] Composants UI utilisent les CSS variables existantes

#### Avant merge final
- [ ] 3 vues fonctionnelles (Tableau, Kanban, Gantt)
- [ ] Édition inline sur toutes les cellules
- [ ] Lignes fantômes pour création rapide
- [ ] Actions dynamiques avec preuves
- [ ] Calcul progression automatique
- [ ] Sous-tâches hiérarchiques
- [ ] Drag-and-drop Kanban fonctionnel
- [ ] Drag-and-drop Gantt fonctionnel
- [ ] Filtres avancés avec persistance
- [ ] Export CSV/Excel
- [ ] Upload documents
- [ ] Commentaires
- [ ] Permissions par rôle
- [ ] i18n fr/en/ar complet
- [ ] Responsive mobile
- [ ] États loading/error
- [ ] Navigation Sidebar mise à jour
- [ ] Routes App.tsx configurées

### 27.8 Estimation Totale

| Sprint | Durée | Tâches |
|---|---|---|
| Sprint 1 — SQL + Types + Dependencies | 3-4h | 7 |
| Sprint 2 — Composants UI réutilisables | 2-3h | 6 |
| Sprint 3 — Cellules + Hooks | 3-4h | 10 |
| Sprint 4 — Tableau Dynamique | 4-5h | 13 |
| Sprint 5 — Kanban Board | 2-3h | 3 |
| Sprint 6 — Gantt Chart | 3-4h | 6 |
| Sprint 7 — Hub + Routing + i18n | 2-3h | 7 |
| Sprint 8 — Intégration + Harmonisation | 2-3h | 7 |
| Sprint 9 — Tests + Validation | 2h | 7 |
| **Total** | **23-31h** | **66** |

### 27.9 Ordre d'Exécution (Multi-Agent)

> Utilisable avec le protocole `/multi-agent-impliment`

| Agent | Sprint 1 | Sprint 2-3 | Sprint 4 | Sprint 5-6 | Sprint 7-8 |
|---|---|---|---|---|---|
| **SQL** | Migration SQL complète | — | — | — | — |
| **Types** | Types TypeScript | — | — | — | — |
| **Lib/Logic** | Queries + hooks | ganttHelpers + ganttColors + hooks | — | useGanttDrag | Export CSV |
| **UI/Pages** | — | Composants UI + cellules | Tableau dynamique (13 composants) | Kanban + Gantt (9 composants) | Hub + Page + Sidebar |
| **i18n/Routes** | — | — | — | — | taskManagement.json + nav.json + App.tsx |

**Agents de validation (après Sprint 4, puis après Sprint 8) :**
- **Agent QA-UI** : Structure, onglets, tables, boutons, skeleton, empty state, badges, useTranslation
- **Agent Logique Métier** : Queries, optimistic updates, calcul progression, filtres
- **Agent SQL/Intégration** : RLS, types, routes, clés i18n, tenant isolation
