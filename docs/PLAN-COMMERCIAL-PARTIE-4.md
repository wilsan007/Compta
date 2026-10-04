# PARTIE 4 — Sprints F & G : CRM Force de Vente + CRM Service Client (9-11j)

> **Sprint F** (5-6j) : Opportunités/pipeline, activités, campagnes marketing, secteurs, e-mailing, prévisions ventes, géolocalisation
> **Sprint G** (4-5j) : Tickets, base de connaissances, contrats de service, SLA, extranet clients
> **i18n** : `useTranslation` (fr, en, ar) — nouveau namespace `crm`
> **SQL** : `app/sql/52_sprint_f_crm_sales.sql` + `app/sql/53_sprint_g_crm_service.sql`

---

# SPRINT F : CRM Force de Vente (5-6j)

## F.1 SQL — Nouvelles tables

### `crm_opportunities` (opportunités/pipeline)
```sql
CREATE TABLE IF NOT EXISTS crm_opportunities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  number text NOT NULL,
  customer_id uuid REFERENCES customers(id) ON DELETE SET NULL,
  prospect_id uuid REFERENCES prospects(id) ON DELETE SET NULL,
  title text NOT NULL,
  description text,
  stage text NOT NULL DEFAULT 'new',   -- 'new'|'qualified'|'proposition'|'negotiation'|'won'|'lost'
  probability integer DEFAULT 0,       -- 0-100
  expected_amount numeric(15,2) DEFAULT 0,
  expected_close_date date,
  actual_amount numeric(15,2),
  actual_close_date date,
  sales_rep_id uuid REFERENCES sales_representatives(id) ON DELETE SET NULL,
  source text,                         -- 'web'|'referral'|'cold_call'|'trade_show'|'other'
  lost_reason text,
  tags text[],
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_opp_customer ON crm_opportunities(customer_id);
CREATE INDEX IF NOT EXISTS idx_opp_stage ON crm_opportunities(stage);
CREATE INDEX IF NOT EXISTS idx_opp_rep ON crm_opportunities(sales_rep_id);
ALTER TABLE crm_opportunities ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_crm_opportunities') THEN
    CREATE POLICY "allow_all_crm_opportunities" ON crm_opportunities FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `crm_activities` (activités/appels/visites/emails)
```sql
CREATE TABLE IF NOT EXISTS crm_activities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  opportunity_id uuid REFERENCES crm_opportunities(id) ON DELETE CASCADE,
  customer_id uuid REFERENCES customers(id) ON DELETE SET NULL,
  activity_type text NOT NULL,         -- 'call'|'meeting'|'email'|'task'|'visit'
  subject text NOT NULL,
  description text,
  scheduled_date timestamptz,
  completed_date timestamptz,
  duration_minutes integer,
  status text DEFAULT 'planned',       -- 'planned'|'done'|'cancelled'|'postponed'
  assigned_to text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_act_opp ON crm_activities(opportunity_id);
CREATE INDEX IF NOT EXISTS idx_act_customer ON crm_activities(customer_id);
CREATE INDEX IF NOT EXISTS idx_act_date ON crm_activities(scheduled_date);
ALTER TABLE crm_activities ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_crm_activities') THEN
    CREATE POLICY "allow_all_crm_activities" ON crm_activities FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `crm_campaigns` (campagnes marketing)
```sql
CREATE TABLE IF NOT EXISTS crm_campaigns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text,
  campaign_type text NOT NULL,         -- 'email'|'sms'|'social'|'event'|'print'
  status text DEFAULT 'draft',         -- 'draft'|'scheduled'|'running'|'completed'|'cancelled'
  start_date date,
  end_date date,
  budget numeric(15,2) DEFAULT 0,
  actual_cost numeric(15,2) DEFAULT 0,
  target_audience text,                -- 'all'|'segment'|'specific'
  segment_criteria jsonb,              -- filtres en JSON
  sent_count integer DEFAULT 0,
  open_count integer DEFAULT 0,
  click_count integer DEFAULT 0,
  response_count integer DEFAULT 0,
  conversion_count integer DEFAULT 0,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_camp_status ON crm_campaigns(status);
ALTER TABLE crm_campaigns ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_crm_campaigns') THEN
    CREATE POLICY "allow_all_crm_campaigns" ON crm_campaigns FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `crm_campaign_recipients`
```sql
CREATE TABLE IF NOT EXISTS crm_campaign_recipients (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  campaign_id uuid NOT NULL REFERENCES crm_campaigns(id) ON DELETE CASCADE,
  customer_id uuid REFERENCES customers(id) ON DELETE SET NULL,
  prospect_id uuid REFERENCES prospects(id) ON DELETE SET NULL,
  email text,
  phone text,
  sent boolean DEFAULT false,
  sent_at timestamptz,
  opened boolean DEFAULT false,
  opened_at timestamptz,
  clicked boolean DEFAULT false,
  responded boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_cr_camp ON crm_campaign_recipients(campaign_id);
ALTER TABLE crm_campaign_recipients ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_crm_campaign_recipients') THEN
    CREATE POLICY "allow_all_crm_campaign_recipients" ON crm_campaign_recipients FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `crm_territories` (secteurs)
```sql
CREATE TABLE IF NOT EXISTS crm_territories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  code text,
  parent_id uuid REFERENCES crm_territories(id) ON DELETE SET NULL,
  sales_rep_id uuid REFERENCES sales_representatives(id) ON DELETE SET NULL,
  regions text[],                      -- codes postaux ou régions
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_terr_parent ON crm_territories(parent_id);
ALTER TABLE crm_territories ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_crm_territories') THEN
    CREATE POLICY "allow_all_crm_territories" ON crm_territories FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `crm_forecasts` (prévisions ventes)
```sql
CREATE TABLE IF NOT EXISTS crm_forecasts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  period text NOT NULL,                -- '2024-Q1', '2024-03', '2024'
  sales_rep_id uuid REFERENCES sales_representatives(id) ON DELETE SET NULL,
  target_amount numeric(15,2) DEFAULT 0,
  committed_amount numeric(15,2) DEFAULT 0,
  best_case_amount numeric(15,2) DEFAULT 0,
  pipeline_amount numeric(15,2) DEFAULT 0,
  closed_amount numeric(15,2) DEFAULT 0,
  notes text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_fc_period ON crm_forecasts(period);
ALTER TABLE crm_forecasts ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_crm_forecasts') THEN
    CREATE POLICY "allow_all_crm_forecasts" ON crm_forecasts FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

## F.2 Types TypeScript

```typescript
export interface CrmOpportunity {
  id: string
  number: string
  customer_id: string | null
  prospect_id: string | null
  title: string
  description: string | null
  stage: 'new'|'qualified'|'proposition'|'negotiation'|'won'|'lost'
  probability: number
  expected_amount: number
  expected_close_date: string | null
  actual_amount: number | null
  actual_close_date: string | null
  sales_rep_id: string | null
  source: string | null
  lost_reason: string | null
  tags: string[] | null
  created_at: string
  updated_at: string
}

export interface CrmActivity {
  id: string
  opportunity_id: string | null
  customer_id: string | null
  activity_type: 'call'|'meeting'|'email'|'task'|'visit'
  subject: string
  description: string | null
  scheduled_date: string | null
  completed_date: string | null
  duration_minutes: number | null
  status: 'planned'|'done'|'cancelled'|'postponed'
  assigned_to: string | null
  created_at: string
}

export interface CrmCampaign {
  id: string
  name: string
  description: string | null
  campaign_type: 'email'|'sms'|'social'|'event'|'print'
  status: 'draft'|'scheduled'|'running'|'completed'|'cancelled'
  start_date: string | null
  end_date: string | null
  budget: number
  actual_cost: number
  target_audience: string | null
  segment_criteria: Record<string, any> | null
  sent_count: number
  open_count: number
  click_count: number
  response_count: number
  conversion_count: number
  created_at: string
}

export interface CrmTerritory {
  id: string
  name: string
  code: string | null
  parent_id: string | null
  sales_rep_id: string | null
  regions: string[] | null
  active: boolean
}

export interface CrmForecast {
  id: string
  period: string
  sales_rep_id: string | null
  target_amount: number
  committed_amount: number
  best_case_amount: number
  pipeline_amount: number
  closed_amount: number
  notes: string | null
}
```

## F.3 Queries

| Fonction | Description |
|---|---|
| `getOpportunities(stage?)` | Liste des opportunités (filtre par stage) |
| `createOpportunity(opp)` | Crée une opportunité |
| `updateOpportunityStage(id, stage)` | Change le stage (pipeline kanban) |
| `getOpportunityById(id)` | Détail + activités + lignes |
| `getActivities(opportunityId?)` | Liste des activités |
| `createActivity(activity)` | Crée une activité |
| `completeActivity(id)` | Marque comme terminée |
| `getCampaigns(status?)` | Liste des campagnes |
| `createCampaign(camp)` | Crée une campagne |
| `launchCampaign(id)` | Démarre l'envoi (e-mailing) |
| `getCampaignStats(id)` | Retourne statistiques (taux ouverture, clic, conversion) |
| `getTerritories()` | Liste des secteurs |
| `createTerritory(terr)` | Crée un secteur |
| `assignTerritoryRep(id, repId)` | Affecte un représentant |
| `getForecasts(period?)` | Prévisions par période |
| `createForecast(fc)` | Crée une prévision |
| `getSalesPipeline()` | Agrège le pipeline par stage pour le kanban |

## F.4 Nouvelles pages

### `OpportunitiesPage.tsx` (Pipeline Kanban)
**Fichier** : `app/src/pages/crm/OpportunitiesPage.tsx`
**Route** : `/crm/opportunities`

- **Vue Kanban** : colonnes par stage (New, Qualified, Proposition, Negotiation, Won, Lost)
- Drag & drop entre colonnes → `updateOpportunityStage`
- Carte opportunité : titre, client, montant attendu, probabilité, date clôture
- Bouton "Nouvelle opportunité" → formulaire
- **Vue liste** alternative (tableau avec filtres)
- Filtres : représentant, période, source
- `useTranslation('crm')`

### `ActivitiesPage.tsx`
**Fichier** : `app/src/pages/crm/ActivitiesPage.tsx`
**Route** : `/crm/activities`

- **Vue calendrier** : activités planifiées par jour
- **Vue liste** : filtres par type, statut, date, assigné à
- Bouton "Nouvelle activité" → formulaire (type, sujet, date, durée, assigné)
- Bouton "Terminer" sur chaque activité
- `useTranslation('crm')`

### `CampaignsPage.tsx`
**Fichier** : `app/src/pages/crm/CampaignsPage.tsx`
**Route** : `/crm/campaigns`

- Liste des campagnes avec statut (draft, scheduled, running, completed)
- Bouton "Nouvelle campagne" → formulaire :
  - Nom, type (email/sms/social/event/print)
  - Audience cible (tous, segment, spécifiques)
  - Critères de segment (jsonb dynamique)
  - Budget, dates
- **Tableau de bord campagne** : taux ouverture, clic, réponse, conversion
- Bouton "Lancer" → `launchCampaign(id)`
- `useTranslation('crm')`

### `TerritoriesPage.tsx`
**Fichier** : `app/src/pages/crm/TerritoriesPage.tsx`
**Route** : `/crm/territories`

- Liste hiérarchique des secteurs (arbre parent/enfant)
- Création : nom, code, parent, représentant, régions
- **Vue carte** : géolocalisation des clients par secteur (optionnel, Leaflet/Mapbox)
- `useTranslation('crm')`

### `SalesForecastPage.tsx`
**Fichier** : `app/src/pages/crm/SalesForecastPage.tsx`
**Route** : `/crm/forecasts`

- Sélection période (mois/trimestre/année)
- Tableau par représentant : cible, engagé, meilleur cas, pipeline, réalisé
- Graphique : cible vs réalisé
- Bouton "Nouvelle prévision"
- `useTranslation('crm')`

## F.5 i18n — Nouveau namespace `crm`

**Fichiers** : `app/src/i18n/locales/{fr,en,ar}/crm.json`

| Section | Clés |
|---|---|
| `opportunities.*` | title, new, number, customer, prospect, title_field, description, stage, stageNew, stageQualified, stageProposition, stageNegotiation, stageWon, stageLost, probability, expectedAmount, expectedCloseDate, actualAmount, actualCloseDate, salesRep, source, lostReason, tags, kanbanView, listView |
| `activities.*` | title, new, type, call, meeting, email, task, visit, subject, description, scheduledDate, completedDate, duration, status, planned, done, cancelled, postponed, assignedTo, calendarView, complete |
| `campaigns.*` | title, new, name, type, email, sms, social, event, print, status, draft, scheduled, running, completed, cancelled, startDate, endDate, budget, actualCost, targetAudience, all, segment, specific, launch, stats, openRate, clickRate, responseRate, conversionRate, sentCount |
| `territories.*` | title, new, name, code, parent, salesRep, regions, active, mapView |
| `forecasts.*` | title, new, period, target, committed, bestCase, pipeline, closed, notes, targetVsActual |

## F.6 Routes

```tsx
<Route path="/crm/opportunities" element={<OpportunitiesPage />} />
<Route path="/crm/activities" element={<ActivitiesPage />} />
<Route path="/crm/campaigns" element={<CampaignsPage />} />
<Route path="/crm/territories" element={<TerritoriesPage />} />
<Route path="/crm/forecasts" element={<SalesForecastPage />} />
```

---

# SPRINT G : CRM Service Client (4-5j)

## G.1 SQL — Nouvelles tables

### `service_tickets` (tickets support)
```sql
CREATE TABLE IF NOT EXISTS service_tickets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  number text NOT NULL,
  customer_id uuid NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  contact_id uuid REFERENCES customer_contacts(id) ON DELETE SET NULL,
  subject text NOT NULL,
  description text,
  category text,                       -- 'technical'|'billing'|'delivery'|'product'|'other'
  priority text DEFAULT 'normal',      -- 'low'|'normal'|'high'|'urgent'
  status text DEFAULT 'open',          -- 'open'|'in_progress'|'waiting_customer'|'resolved'|'closed'
  assigned_to text,
  sla_due_date timestamptz,
  first_response_at timestamptz,
  resolved_at timestamptz,
  closed_at timestamptz,
  satisfaction_rating integer,         -- 1-5
  satisfaction_comment text,
  tags text[],
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tk_customer ON service_tickets(customer_id);
CREATE INDEX IF NOT EXISTS idx_tk_status ON service_tickets(status);
CREATE INDEX IF NOT EXISTS idx_tk_assigned ON service_tickets(assigned_to);
ALTER TABLE service_tickets ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_service_tickets') THEN
    CREATE POLICY "allow_all_service_tickets" ON service_tickets FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `service_ticket_messages` (messages du ticket)
```sql
CREATE TABLE IF NOT EXISTS service_ticket_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  ticket_id uuid NOT NULL REFERENCES service_tickets(id) ON DELETE CASCADE,
  author text NOT NULL,                -- nom de l'auteur
  author_type text NOT NULL,           -- 'agent'|'customer'|'system'
  message text NOT NULL,
  attachments jsonb,                   -- [{filename, url, size}]
  is_internal boolean DEFAULT false,   -- note interne (non visible client)
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tm_ticket ON service_ticket_messages(ticket_id);
ALTER TABLE service_ticket_messages ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_service_ticket_messages') THEN
    CREATE POLICY "allow_all_service_ticket_messages" ON service_ticket_messages FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `service_contracts` (contrats de service)
```sql
CREATE TABLE IF NOT EXISTS service_contracts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  number text NOT NULL,
  customer_id uuid NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  name text NOT NULL,
  contract_type text,                  -- 'support'|'maintenance'|'warranty'|'sla'
  start_date date NOT NULL,
  end_date date,
  status text DEFAULT 'active',        -- 'active'|'expired'|'terminated'|'draft'
  sla_response_hours integer,          -- temps de réponse SLA en heures
  sla_resolution_hours integer,        -- temps de résolution SLA en heures
  coverage text,                       -- 'business_hours'|'24_7'
  max_tickets integer,                 -- nombre max de tickets (null = illimité)
  used_tickets integer DEFAULT 0,
  amount numeric(15,2),
  notes text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sc_customer ON service_contracts(customer_id);
ALTER TABLE service_contracts ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_service_contracts') THEN
    CREATE POLICY "allow_all_service_contracts" ON service_contracts FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `knowledge_base_articles` (base de connaissances)
```sql
CREATE TABLE IF NOT EXISTS knowledge_base_articles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  title text NOT NULL,
  category text,                       -- 'faq'|'guide'|'troubleshooting'|'policy'
  content text NOT NULL,               -- markdown
  tags text[],
  author text,
  status text DEFAULT 'draft',         -- 'draft'|'published'|'archived'
  views integer DEFAULT 0,
  helpful_count integer DEFAULT 0,
  not_helpful_count integer DEFAULT 0,
  is_public boolean DEFAULT false,     -- visible côté extranet client
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_kb_category ON knowledge_base_articles(category);
CREATE INDEX IF NOT EXISTS idx_kb_status ON knowledge_base_articles(status);
ALTER TABLE knowledge_base_articles ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_kb_articles') THEN
    CREATE POLICY "allow_all_kb_articles" ON knowledge_base_articles FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

## G.2 Types TypeScript

```typescript
export interface ServiceTicket {
  id: string
  number: string
  customer_id: string
  contact_id: string | null
  subject: string
  description: string | null
  category: 'technical'|'billing'|'delivery'|'product'|'other' | null
  priority: 'low'|'normal'|'high'|'urgent'
  status: 'open'|'in_progress'|'waiting_customer'|'resolved'|'closed'
  assigned_to: string | null
  sla_due_date: string | null
  first_response_at: string | null
  resolved_at: string | null
  closed_at: string | null
  satisfaction_rating: number | null
  satisfaction_comment: string | null
  tags: string[] | null
  created_at: string
  updated_at: string
}

export interface ServiceTicketMessage {
  id: string
  ticket_id: string
  author: string
  author_type: 'agent'|'customer'|'system'
  message: string
  attachments: { filename: string; url: string; size: number }[] | null
  is_internal: boolean
  created_at: string
}

export interface ServiceContract {
  id: string
  number: string
  customer_id: string
  name: string
  contract_type: 'support'|'maintenance'|'warranty'|'sla' | null
  start_date: string
  end_date: string | null
  status: 'active'|'expired'|'terminated'|'draft'
  sla_response_hours: number | null
  sla_resolution_hours: number | null
  coverage: 'business_hours'|'24_7' | null
  max_tickets: number | null
  used_tickets: number
  amount: number | null
  notes: string | null
}

export interface KnowledgeBaseArticle {
  id: string
  title: string
  category: 'faq'|'guide'|'troubleshooting'|'policy' | null
  content: string
  tags: string[] | null
  author: string | null
  status: 'draft'|'published'|'archived'
  views: number
  helpful_count: number
  not_helpful_count: number
  is_public: boolean
  created_at: string
  updated_at: string
}
```

## G.3 Queries

| Fonction | Description |
|---|---|
| `getTickets(status?, priority?)` | Liste des tickets |
| `createTicket(ticket)` | Crée un ticket |
| `updateTicketStatus(id, status)` | Change le statut |
| `assignTicket(id, agent)` | Assigne à un agent |
| `getTicketMessages(ticketId)` | Messages d'un ticket |
| `addTicketMessage(msg)` | Ajoute un message |
| `checkSlaCompliance(ticketId)` | Vérifie le respect du SLA |
| `getServiceContracts(customerId?)` | Liste des contrats |
| `createServiceContract(contract)` | Crée un contrat |
| `getKbArticles(category?, status?)` | Articles base de connaissances |
| `createKbArticle(article)` | Crée un article |
| `updateKbArticle(id, updates)` | Modifie |
| `incrementKbViews(id)` | Incrémente le compteur de vues |
| `rateKbArticle(id, helpful)` | Vote utile/pas utile |

## G.4 Nouvelles pages

### `TicketsPage.tsx`
**Fichier** : `app/src/pages/crm/TicketsPage.tsx`
**Route** : `/crm/tickets`

- Liste des tickets avec filtres (statut, priorité, catégorie, assigné)
- **Vue Kanban** par statut (open, in_progress, waiting_customer, resolved, closed)
- Bouton "Nouveau ticket" → formulaire (client, contact, sujet, catégorie, priorité)
- **Détail ticket** : fil de discussion (messages), pièces jointes, SLA countdown
- Bouton "Répondre" + option "Note interne"
- Évaluation satisfaction à la clôture (1-5 étoiles)
- `useTranslation('crm')`

### `ServiceContractsPage.tsx`
**Fichier** : `app/src/pages/crm/ServiceContractsPage.tsx`
**Route** : `/crm/contracts`

- Liste des contrats par client
- Formulaire : client, type, dates, SLA (response/resolution), couverture, max tickets, montant
- Badge statut (active/expired/terminated)
- Compteur tickets utilisés / max
- `useTranslation('crm')`

### `KnowledgeBasePage.tsx`
**Fichier** : `app/src/pages/crm/KnowledgeBasePage.tsx`
**Route** : `/crm/knowledge-base`

- Liste des articles avec filtres (catégorie, statut, tags)
- **Recherche full-text** dans le contenu
- Formulaire création/édition : titre, catégorie, contenu (markdown editor), tags, is_public
- Bouton "Utile" / "Pas utile" sur chaque article
- Compteur de vues
- `useTranslation('crm')`

### `CustomerPortalPage.tsx` (extranet clients)
**Fichier** : `app/src/pages/crm/CustomerPortalPage.tsx`
**Route** : `/portal`

- Page publique (accessible sans login admin, auth client)
- **Onglet 1 — Mes tickets** : création + suivi de tickets
- **Onglet 2 — Base de connaissances** : articles publics uniquement
- **Onglet 3 — Mes contrats** : contrats actifs du client connecté
- `useTranslation('crm')`

## G.5 i18n — Ajouts au namespace `crm`

| Section | Clés |
|---|---|
| `tickets.*` | title, new, number, customer, contact, subject, description, category, technical, billing, delivery, product, other, priority, low, normal, high, urgent, status, open, inProgress, waitingCustomer, resolved, closed, assignedTo, slaDueDate, firstResponse, resolvedAt, satisfaction, rating, comment, kanbanView, listView, reply, internalNote, attachments |
| `ticketMessages.*` | author, authorType, agent, customer, system, message, isInternal, send |
| `contracts.*` | title, new, number, customer, name, type, support, maintenance, warranty, sla, startDate, endDate, status, active, expired, terminated, draft, slaResponse, slaResolution, coverage, businessHours, 24_7, maxTickets, usedTickets, amount |
| `knowledgeBase.*` | title, new, edit, category, faq, guide, troubleshooting, policy, content, tags, author, status, draft, published, archived, views, helpful, notHelpful, isPublic, search |
| `portal.*` | title, myTickets, knowledgeBase, myContracts, createTicket, ticketStatus |

## G.6 Routes

```tsx
<Route path="/crm/tickets" element={<TicketsPage />} />
<Route path="/crm/contracts" element={<ServiceContractsPage />} />
<Route path="/crm/knowledge-base" element={<KnowledgeBasePage />} />
<Route path="/portal" element={<CustomerPortalPage />} />
```
