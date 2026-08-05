# Référence ClickUp — Gestion de Projet et Tâches

> Document de référence pour implémenter les fonctionnalités manquantes dans notre module.
> Sources: clickup.com (deep scraping), 6 articles, help.clickup.com, infosaone.com (Odoo)

---

## 1. HIÉRARCHIE CLICKUP

| Niveau | Description | Notre app |
|--------|-------------|-----------|
| Workspace | Racine organisation | Tenant |
| Space | Département/équipe | Module |
| Folder | Regroupement de listes | Projet |
| Subfolder | Sous-dossier (beta, 7 niveaux) | Sous-projet |
| List | Conteneur de tâches | Liste de tâches |
| Task | Unité de travail | Tâche |
| Subtask | Sous-tâche (7 niveaux) | Sous-tâche |
| Checklist | Étapes simples (pas statut/assignee) | TaskAction |

---

## 2. TÂCHES — Champs et Features

### Champs existants (✅)
- `title`, `description`, `status` (7 valeurs), `priority` (4 niveaux)
- `assignee` (single) + `assignees[]` (multi en DB, UI partielle)
- `start_date`, `due_date`, `effort_estimate_h`, `effort_spent_h`, `progress`
- `tags[]`, `color`, `display_order`, `task_level`, `budget`
- `acceptance_criteria`, `recurring_task` + interval + rule_type
- Subtasks (`parent_id`), Dependencies (4 types), Comments, Documents, Actions
- Milestones, Stages, Tags, Multi-assignees (DB)

### Champs MANQUANTS (❌)
- **Watchers/Observateurs** — notifiés sans être assignés
- **Custom Task Type** — Bug, Feature, Lead, etc.
- **Task Template** — modèle réutilisable
- **Sprint Points** — story points agile
- **Epics** — groupe de tâches liées
- **Custom Fields** — 15+ types (text, number, currency, date, dropdown, checkbox, progress, rating, url, email, phone, people, formula, relationship, attachment, AI field)

---

## 3. VUES — 15+ Vues ClickUp

### Vues existantes (✅)
1. **List/Table** → `DynamicTable` — tri/filtre/groupage
2. **Kanban Board** → `KanbanBoard` — drag-and-drop par statut
3. **Gantt** → `GanttChart` — dépendances, drag
4. **Calendar** → `CalendarView` — jour/semaine/mois
5. **Graph** → `GraphView` — pie/bar/line
6. **Pivot** → `PivotView` — tableau croisé (Odoo)
7. **Burndown** → `BurndownChart` — sprint
8. **My Tasks** → `MyTasksView` — tâches assignées
9. **Large Screen** → `LargeScreenView` — vue tableau élargie

### Vues MANQUANTES (❌)
10. **Timeline View** — timeline linéaire (roadmaps), différent du Gantt
11. **Workload View** — charge par membre (capacity, sur/sous-chargé)
12. **Activity View** — fil d'activité (qui a fait quoi)
13. **Mind Map** — carte mentale des tâches
14. **Form View** — formulaires de création de tâches
15. **Whiteboard** — tableau blanc collaboratif
16. **Doc View** — documents/wikis intégrés
17. **Dashboard View** — widgets multiples (50+ types)
18. **Map View** — carte géographique (niche)
19. **Chat View** — chat d'équipe
20. **Embed View** — contenu externe

---

## 4. COLLABORATION — Features

### Existant (✅)
- Commentaires (`TaskComment`)

### Manquant (❌)
- **Mentions @user** dans commentaires
- **Assigned Comments** — commentaire → action item
- **Watchers** — observateurs notifiés
- **Inbox** — centre de notifications
- **Reminders** — rappels personnels
- **Chat intégré** — temps réel
- **Clips** — enregistrement écran
- **Sync Ups** — meetings instantanés
- **Email intégré** — emails sur tâche
- **Collaboration Detection** — qui édite en temps réel

---

## 5. TEMPS ET RESSOURCES

### Existant (✅)
- `effort_estimate_h` (estimation), `effort_spent_h` (temps passé manuel)

### Manquant (❌)
- **Timer intégré** — start/stop avec notes, tags, billable
- **Timesheets** — feuille de temps hebdomadaire
- **Billable time** — marquer comme facturable
- **Approvals** — approbation timesheets
- **Teams Hub** — vue d'équipe
- **Recurring Tasks UI** — DB existe, pas d'interface

---

## 6. AUTOMATISATIONS (❌ TOUT MANQUANT)

### Triggers
- Task created, status changed, priority changed, assignee added/removed
- Due date approaching, comment added, field changed, dependency completed

### Actions
- Assign/unassign, change status/priority, set custom field
- Send notification, create subtask, add comment, move to list
- Archive, send email, call webhook

---

## 7. DASHBOARDS — Widgets (50+)

### Existant (✅)
- Pie/Bar/Line charts (`GraphView`), Pivot (`PivotView`), Burndown

### Manquant (❌)
- Sprint Progress, Time Tracking, Workload, Battery
- Cumulative Flow, Velocity, Task/Project Progress
- Leaderboard, Calendar widget, Notepad, Embed
- **Dashboards interactifs** — update tasks depuis le dashboard

---

## 8. SPRINTS ET AGILE (❌ TOUT MANQUANT)

- Sprint View, Sprint Points, Sprint Reports, Backlog, Roadmap, Epics
- Notre app a: BurndownChart ✅, KanbanBoard ✅

---

## 9. MILESTONES ET GOALS

- **Milestones** ✅ — `ProjectMilestone` (DB + queries)
- **Goals** ❌ — Objectifs liés aux tâches, progression auto, hiérarchie

---

## 10. PORTFOLIOS (❌ MANQUANT)
- Vue agrégée multi-projets, drill-down, métriques

---

## 11. TEMPLATES (❌ MANQUANT)
- Templates de tasks, lists, dashboards, automations

---

## 12. COMPARAISON — Features Manquantes Priorisées

### PRIORITÉ HAUTE
| # | Feature | Complexité |
|---|---------|------------|
| 1 | Time Tracking (Timer) | Moyenne |
| 2 | Workload View | Moyenne |
| 3 | Activity View | Moyenne |
| 4 | Watchers/Observateurs | Faible |
| 5 | Task Templates | Moyenne |
| 6 | Timeline View | Haute |
| 7 | Form View | Moyenne |
| 8 | Inbox/Notifications | Haute |
| 9 | Recurring Tasks UI | Faible |
| 10 | Multi-Assignees UI | Faible |

### PRIORITÉ MOYENNE
| # | Feature | Complexité |
|---|---------|------------|
| 11 | Custom Fields | Haute |
| 12 | Automations | Haute |
| 13 | Dashboards (widgets) | Haute |
| 14 | Sprints | Haute |
| 15 | Goals | Moyenne |
| 16 | Portfolios | Moyenne |
| 17 | Mind Map | Haute |
| 18 | Mentions @user | Faible |
| 19 | Assigned Comments | Faible |
| 20 | Timesheets | Moyenne |
| 21 | Approvals | Moyenne |
| 22 | Billable Time | Faible |
| 23 | Custom Task Types | Faible |
| 24 | Epics | Moyenne |
| 25 | Sprint Points | Faible |
| 26 | Reminders | Faible |
| 27 | Doc View | Haute |

### PRIORITÉ BASSE
| # | Feature | Complexité |
|---|---------|------------|
| 28 | Whiteboard | Très haute |
| 29 | Chat View | Haute |
| 30 | Map View | Moyenne |
| 31 | Embed View | Faible |
| 32 | Clips | Très haute |
| 33 | Sync Ups | Haute |
| 34 | Collaboration Detection | Haute |
| 35 | Email intégré | Haute |
| 36 | AI Features | Très haute |
| 37 | Templates Library | Moyenne |
| 38 | Integrations (Slack, etc.) | Haute |
| 39 | Custom Statuses | Moyenne |

---

## 13. SCHÉMAS SQL RECOMMANDÉS

### Time Tracking
```sql
CREATE TABLE project_time_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  task_id uuid REFERENCES project_tasks(id) ON DELETE CASCADE,
  project_id uuid REFERENCES projects(id) ON DELETE SET NULL,
  employee_id uuid REFERENCES employees(id) ON DELETE SET NULL,
  start_time timestamptz NOT NULL,
  end_time timestamptz,
  duration_seconds integer DEFAULT 0,
  description text,
  is_billable boolean DEFAULT false,
  hourly_rate decimal(10,2) DEFAULT 0,
  tags text[] DEFAULT '{}',
  created_at timestamptz DEFAULT now()
);
```

### Watchers
```sql
CREATE TABLE project_task_watchers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  task_id uuid REFERENCES project_tasks(id) ON DELETE CASCADE,
  employee_id uuid REFERENCES employees(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  UNIQUE(task_id, employee_id)
);
```

### Custom Fields
```sql
CREATE TABLE project_custom_fields (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  project_id uuid REFERENCES projects(id) ON DELETE CASCADE,
  name text NOT NULL,
  field_type text NOT NULL, -- text,number,currency,date,dropdown,checkbox,progress,rating,url,email,phone,people
  options jsonb DEFAULT '{}',
  default_value jsonb,
  is_required boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE project_custom_field_values (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  task_id uuid REFERENCES project_tasks(id) ON DELETE CASCADE,
  field_id uuid REFERENCES project_custom_fields(id) ON DELETE CASCADE,
  value jsonb,
  created_at timestamptz DEFAULT now(),
  UNIQUE(task_id, field_id)
);
```

### Automations
```sql
CREATE TABLE project_automations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  project_id uuid REFERENCES projects(id) ON DELETE CASCADE,
  name text NOT NULL,
  trigger_type text NOT NULL,
  trigger_conditions jsonb DEFAULT '{}',
  action_type text NOT NULL,
  action_config jsonb DEFAULT '{}',
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
```

### Activity Log
```sql
CREATE TABLE project_activity_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  task_id uuid REFERENCES project_tasks(id) ON DELETE CASCADE,
  project_id uuid REFERENCES projects(id) ON DELETE SET NULL,
  user_id uuid,
  action_type text NOT NULL, -- created,updated,status_changed,assigned,commented,uploaded,completed,archived
  old_value jsonb,
  new_value jsonb,
  created_at timestamptz DEFAULT now()
);
```

### Task Templates
```sql
CREATE TABLE project_task_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  name text NOT NULL,
  description text,
  default_status text DEFAULT 'todo',
  default_priority text DEFAULT 'medium',
  default_assignee uuid,
  default_tags text[] DEFAULT '{}',
  default_custom_fields jsonb DEFAULT '{}',
  checklist_template jsonb DEFAULT '[]',
  subtasks_template jsonb DEFAULT '[]',
  created_at timestamptz DEFAULT now()
);
```

### Sprints
```sql
CREATE TABLE project_sprints (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  project_id uuid REFERENCES projects(id) ON DELETE CASCADE,
  name text NOT NULL,
  start_date date NOT NULL,
  end_date date NOT NULL,
  status text DEFAULT 'planned', -- planned,active,completed,cancelled
  goal text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE project_sprint_tasks (
  sprint_id uuid REFERENCES project_sprints(id) ON DELETE CASCADE,
  task_id uuid REFERENCES project_tasks(id) ON DELETE CASCADE,
  story_points integer DEFAULT 0,
  PRIMARY KEY (sprint_id, task_id)
);
```

### Goals
```sql
CREATE TABLE project_goals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  title text NOT NULL,
  description text,
  parent_goal_id uuid REFERENCES project_goals(id) ON DELETE SET NULL,
  target_value decimal DEFAULT 100,
  current_value decimal DEFAULT 0,
  unit text DEFAULT 'percentage', -- tasks,hours,percentage,currency
  due_date date,
  owner_id uuid,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE project_goal_tasks (
  goal_id uuid REFERENCES project_goals(id) ON DELETE CASCADE,
  task_id uuid REFERENCES project_tasks(id) ON DELETE CASCADE,
  weight decimal DEFAULT 1,
  PRIMARY KEY (goal_id, task_id)
);
```

---

## 14. ÉCRAN CLICKUP — Task Detail (modal)

```
┌─ Breadcrumbs: Space > Folder > List ───────────┐
│ [Status Badge] [Priority Flag] [Assignees]      │
│                                                  │
│ Task Title (click to edit)                       │
│ ─────────────────────────────────────           │
│ Description (rich text, markdown, @mentions)     │
│                                                  │
│ ┌─ Custom Fields ──────────────────────────┐    │
│ │ [Budget: $5,000] [Phase: Design] [+Add]   │    │
│ └───────────────────────────────────────────┘    │
│                                                  │
│ ┌─ Subtasks (3) ───────────────────────────┐    │
│ │ [○] Subtask 1 [John] [Dec 5]              │    │
│ │ [●] Subtask 2 [Mary] [Dec 7]              │    │
│ │ [○] Subtask 3 [—] [—]                     │    │
│ │ [+ Add Subtask]                           │    │
│ └───────────────────────────────────────────┘    │
│                                                  │
│ ┌─ Dependencies ───────────────────────────┐    │
│ │ ⬅ Waiting on: "API Design"                │    │
│ │ ➡ Blocking: "Frontend Build"              │    │
│ │ [+ Add Dependency]                        │    │
│ └───────────────────────────────────────────┘    │
│                                                  │
│ ┌─ Checklist ──────────────────────────────┐    │
│ │ ☑ Research competitors                    │    │
│ │ ☐ Design wireframes                       │    │
│ │ ☐ Get approval                            │    │
│ │ [+ Add Item]                              │    │
│ └───────────────────────────────────────────┘    │
│                                                  │
│ ┌─ Comments (5) ───────────────────────────┐    │
│ │ @John: "Looks good, but..."               │    │
│ │ @Mary: "Updated the design"               │    │
│ │ [Write a comment...] [Send]               │    │
│ └───────────────────────────────────────────┘    │
│                                                  │
│ ┌─ Attachments ────────────────────────────┐    │
│ │ 📎 file.pdf (2.3 MB)                      │    │
│ │ 📎 screenshot.png                         │    │
│ └───────────────────────────────────────────┘    │
│                                                  │
│ ┌─ Activity ───────────────────────────────┐    │
│ │ John changed status to "In Progress"      │    │
│ │ Mary added a comment                      │    │
│ │ John set due date to Dec 15               │    │
│ └───────────────────────────────────────────┘    │
└──────────────────────────────────────────────────┘
```

---

## 15. FICHIERS DE NOTRE MODULE EXISTANT

| Fichier | Rôle |
|---------|------|
| `app/src/pages/ProjectManagementPage.tsx` | Page principale avec 9 vues |
| `app/src/types/projectManagement.ts` | Types (267 lignes) |
| `app/src/lib/queries/projectManagement.ts` | Queries CRUD (542 lignes) |
| `app/src/hooks/useTasks.ts` | Hook tâches avec filtres |
| `app/src/hooks/useTaskFilters.ts` | Hook filtres avec localStorage |
| `app/src/components/project-management/DynamicTable.tsx` | Vue table |
| `app/src/components/project-management/KanbanBoard.tsx` | Vue kanban |
| `app/src/components/project-management/GanttChart.tsx` | Vue gantt |
| `app/src/components/project-management/CalendarView.tsx` | Vue calendrier |
| `app/src/components/project-management/GraphView.tsx` | Vue graphiques |
| `app/src/components/project-management/PivotView.tsx` | Vue pivot |
| `app/src/components/project-management/BurndownChart.tsx` | Burndown |
| `app/src/components/project-management/MyTasksView.tsx` | Mes tâches |
| `app/src/components/project-management/LargeScreenView.tsx` | Vue élargie |
| `app/src/components/project-management/TaskRow.tsx` | Ligne tâche |
| `app/src/components/project-management/TaskChatter.tsx` | Commentaires |
| `app/src/components/project-management/TaskActionColumns.tsx` | Actions/checklist |
| `app/src/components/project-management/DocumentCellColumn.tsx` | Documents |
| `app/sql/65_project_management.sql` | Schéma SQL |

---

## 16. PLAN D'IMPLÉMENTATION RECOMMANDÉ

### Sprint 1: Core PM (10 features haute priorité)
1. Time Tracking (Timer) — SQL + UI + hook
2. Watchers — SQL + UI badge
3. Multi-Assignees UI — finaliser UI
4. Recurring Tasks UI — modal configuration
5. Activity View — SQL trigger + page
6. Workload View — page + calcul capacity
7. Task Templates — SQL + modal + library
8. Timeline View — page (différent du Gantt)
9. Form View — SQL + page + partage lien
10. Inbox/Notifications — SQL + page

### Sprint 2: Advanced (10 features moyenne priorité)
11. Custom Fields — SQL + UI + types
12. Automations — SQL + builder UI
13. Dashboards widgets — multiple widgets
14. Sprints — SQL + Sprint View + points
15. Goals — SQL + page + progression
16. Portfolios — page multi-projets
17. Mentions @user — parse commentaires
18. Assigned Comments — action items
19. Timesheets — page hebdomadaire
20. Epics — groupement de tâches

### Sprint 3: Nice to have
21-40. Voir liste priorité basse

---

*Document généré le 27 juillet 2026 — Sources: clickup.com, help.clickup.com, lane-digital.ch, journaldunet.com, dtechsystems.co, 0hands.com, platinumpartner.com.au, infosaone.com*
