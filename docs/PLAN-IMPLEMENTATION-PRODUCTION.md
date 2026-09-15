# Plan d'Implémentation — Module Gestion de Production

> **Source** : https://www.activit.fr/nouvelles-fonctionnalites-sage-100-gestion-de-production/
> **Objectif** : Implémenter toutes les fonctionnalités décrites sur cette page dans notre app Compta.
> **Architecture actuelle** : React + Vite + Supabase + TypeScript. Voir les conventions ci-dessous.

---

## Conventions existantes à respecter (OBLIGATOIRE)

### Stack
- **Frontend** : React 18 + TypeScript + Vite, TailwindCSS (variables CSS `var(--color-*)`)
- **Backend** : Supabase (PostgreSQL + RLS)
- **UI** : Composants dans `@/components/ui.tsx` — `Card`, `Button`, `Input`, `Select`, `Table`, `TableRow`, `TableCell`, `EmptyState`, `PageHeader`, `Breadcrumb`, `SkeletonTable`, `Badge`, `SortableTable`, `StatCard`, `AnimatedCounter`
- **Icons** : `lucide-react`
- **Queries** : `@/lib/queries.ts` — pattern `getTenantId()` + `ti()` (insert tenant) + `tud()` (update/delete tenant)
- **Types** : `@/types/index.ts` — interfaces en snake_case
- **Routing** : `@/App.tsx` — `<Route path="..." element={<PageComponent />} />`
- **Navigation** : `@/components/Layout.tsx` — `navGroups` array avec `label`, `icon`, `path`, `subItems`
- **Tenant tables** : `@/lib/supabase.ts` — `TENANT_TABLES` Set — **toute nouvelle table doit être ajoutée ici**
- **Toast** : `useToast()` depuis `@/lib/toast`
- **Auth** : `useAuth()` depuis `@/lib/auth`

### Pattern pour une nouvelle table (exemple)
```sql
-- 1. SQL dans supabase-schema.sql
create table if not exists ma_table (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  champ1 text not null,
  ...
  created_at timestamptz default now()
);
-- 2. Index
create index if not exists idx_ma_table_champ1 on ma_table(champ1);
-- 3. RLS
alter table ma_table enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_ma_table') THEN
    CREATE POLICY "allow_all_ma_table" ON ma_table FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
```
```typescript
// 4. Type dans @/types/index.ts
export interface MaTable {
  id: string
  champ1: string
  created_at: string
}

// 5. Queries dans @/lib/queries.ts (à la fin du fichier)
export async function getMaTables() {
  const tid = await getTenantId()
  let q = supabase.from('ma_table').select('*').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as MaTable[]
}
export async function createMaTable(item: Omit<MaTable, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('ma_table').insert(ti(item, 'ma_table', tid)).select().single()
  if (error) throw error
  return data as MaTable
}
export async function updateMaTable(id: string, updates: Partial<MaTable>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('ma_table').update(updates), 'ma_table', tid).eq('id', id).select().single()
  if (error) throw error
  return data as MaTable
}
export async function deleteMaTable(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('ma_table').delete(), 'ma_table', tid).eq('id', id)
  if (error) throw error
}

// 6. Page dans @/pages/MaTablePage.tsx (suivre le pattern de BOMPage.tsx)
// 7. Route dans App.tsx
// 8. Nav dans Layout.tsx navGroups
// 9. Table name dans TENANT_TABLES (supabase.ts)
// 10. Route label dans routeLabels (ui.tsx)
```

---

## Récapitulatif : Ce qui existe déjà et ce qui manque

### Tables existantes à modifier
| Table | Fichier | Modifications nécessaires |
|---|---|---|
| `boms` | `supabase-schema.sql:1178` | Ajouter `bom_type`, `routing_id` |
| `bom_lines` | `supabase-schema.sql:1189` | Ajouter `warehouse_id`, `unit`, `scrap_percent` |
| `manufacturing_orders` | `supabase-schema.sql:1199` | Ajouter `origin`, `routing_id`, `parent_of_id`, `lot_number`, `expiry_date`, `label_count` |
| `products` | `supabase-schema.sql` (chercher) | Ajouter `is_amalgam`, `units_per_carton`, `st_unit`, `purchase_unit`, `st_multiple`, `shelf_life_days`, `exclude_from_mrp` |
| `stock_movements` | `supabase-schema.sql:1121` | Ajouter `'production'`, `'subcontracting'` au CHECK de `reference_type` |
| `warehouses` | `supabase-schema.sql:1092` | Ajouter `warehouse_type` (`main`, `subcontractor`, `supplier`) |
| `suppliers` | `supabase-schema.sql:88` | Ajouter `default_warehouse_id` |

### Nouvelles tables à créer : 18 tables
| # | Table | Module |
|---|---|---|
| 1 | `routings` | Gamme opératoire |
| 2 | `routing_operations` | Gamme opératoire |
| 3 | `machines` | Machine & Outillage |
| 4 | `work_centers` | Machine & Outillage |
| 5 | `toolings` | Machine & Outillage |
| 6 | `subcontracting_orders` | Sous-traitance |
| 7 | `subcontracting_shipments` | Sous-traitance |
| 8 | `subcontracting_shipment_lines` | Sous-traitance |
| 9 | `subcontracting_receipts` | Sous-traitance |
| 10 | `subcontracting_receipt_lines` | Sous-traitance |
| 11 | `of_labels` | OF : Étiquettes |
| 12 | `of_lots` | OF : Lots & péremption |
| 13 | `of_consumptions` | Consommation différée |
| 14 | `mrp_calculations` | CBN |
| 15 | `mrp_proposals` | CBN |
| 16 | `mrp_pending_documents` | CBN |
| 17 | `production_forecasts` | Prévisions |
| 18 | `production_forecast_lines` | Prévisions |

### Nouvelles pages React : 14 pages
| # | Page | Route | Module |
|---|---|---|---|
| 1 | `RoutingsPage.tsx` | `/production/routings` | Gamme |
| 2 | `MachinesPage.tsx` | `/production/machines` | Machine & Outillage |
| 3 | `ToolingsPage.tsx` | `/production/toolings` | Machine & Outillage |
| 4 | `SubcontractingOrdersPage.tsx` | `/production/subcontracting/orders` | Sous-traitance |
| 5 | `SubcontractingShipmentsPage.tsx` | `/production/subcontracting/shipments` | Sous-traitance |
| 6 | `SubcontractingReceiptsPage.tsx` | `/production/subcontracting/receipts` | Sous-traitance |
| 7 | `SubcontractingSupervisorPage.tsx` | `/production/subcontracting/supervisor` | Sous-traitance |
| 8 | `ManufacturingOrderDetailPage.tsx` | `/production/of/:id` | OF détail |
| 9 | `MRPCalculationsPage.tsx` | `/production/mrp` | CBN |
| 10 | `MRPProposalsPage.tsx` | `/production/mrp/proposals/:calcId` | CBN |
| 11 | `MRPPendingDocumentsPage.tsx` | `/production/mrp/pending` | CBN |
| 12 | `ProductionForecastsPage.tsx` | `/production/forecasts` | Prévisions |
| 13 | `ProductionPlanningPage.tsx` | `/production/planning` | Planification |
| 14 | `ProductionDashboardPage.tsx` | `/production` | Dashboard production |

### Nouveaux composants modaux : 12 modaux
| # | Composant | Utilisé par |
|---|---|---|
| 1 | `RoutingFormModal` | `RoutingsPage` |
| 2 | `RoutingOperationFormModal` | `RoutingsPage` (détail gamme) |
| 3 | `MachineFormModal` | `MachinesPage` |
| 4 | `ToolingFormModal` | `ToolingsPage` |
| 5 | `SubcontractingOrderFormModal` | `SubcontractingOrdersPage` |
| 6 | `SubcontractingShipmentFormModal` | `SubcontractingShipmentsPage` |
| 7 | `SubcontractingReceiptFormModal` | `SubcontractingReceiptsPage` |
| 8 | `OFDetailModal` / `OFDetailPage` | `ManufacturingOrdersPage` + page détail |
| 9 | `LabelFormModal` | `ManufacturingOrderDetailPage` |
| 10 | `LotFormModal` | `ManufacturingOrderDetailPage` |
| 11 | `MRPCalculationFormModal` | `MRPCalculationsPage` |
| 12 | `ArticleInterrogationModal` | Composant réutilisable global |

---

# SPRINT 1 : Gamme Opératoire + Machine & Outillage

> **Fonctionnalités Sage 100 couvertes** :
> - Gamme Opératoire : Import/Export au format Excel
> - Gamme : Renuméroter une opération
> - Machine et Outillage : Import/Export au format Excel
> - Outillage : Compteur de pièces

## 1.1 — Tables SQL

### Table `routings` (gammes opératoires)
```sql
create table if not exists routings (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  code text not null,
  name text not null,
  description text,
  product_id uuid references products(id) on delete set null,
  version int default 1,
  active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists idx_routings_code on routings(code);
create index if not exists idx_routings_product on routings(product_id);
alter table routings enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_routings') THEN
    CREATE POLICY "allow_all_routings" ON routings FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
```

### Table `routing_operations` (opérations d'une gamme)
```sql
create table if not exists routing_operations (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  routing_id uuid not null references routings(id) on delete cascade,
  sequence int not null default 10,
  name text not null,
  description text,
  work_center_id uuid references work_centers(id) on delete set null,
  machine_id uuid references machines(id) on delete set null,
  tooling_id uuid references toolings(id) on delete set null,
  setup_time_min int default 0,
  run_time_min int default 0,
  is_subcontracted boolean default false,
  supplier_id uuid references suppliers(id) on delete set null,
  st_unit text,
  st_quantity numeric(15,2) default 1,
  created_at timestamptz default now()
);
create index if not exists idx_routing_operations_routing on routing_operations(routing_id);
create index if not exists idx_routing_operations_sequence on routing_operations(sequence);
alter table routing_operations enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_routing_operations') THEN
    CREATE POLICY "allow_all_routing_operations" ON routing_operations FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
```

### Table `work_centers` (centres de charge)
```sql
create table if not exists work_centers (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  code text not null,
  name text not null,
  capacity_hours_per_day numeric(5,1) default 8,
  cost_per_hour numeric(15,2) default 0,
  active boolean default true,
  created_at timestamptz default now()
);
create index if not exists idx_work_centers_code on work_centers(code);
alter table work_centers enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_work_centers') THEN
    CREATE POLICY "allow_all_work_centers" ON work_centers FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
```

### Table `machines`
```sql
create table if not exists machines (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  code text not null,
  name text not null,
  work_center_id uuid references work_centers(id) on delete set null,
  capacity_per_hour numeric(15,2) default 0,
  status text default 'active' check (status in ('active','maintenance','inactive')),
  purchase_date date,
  notes text,
  created_at timestamptz default now()
);
create index if not exists idx_machines_code on machines(code);
create index if not exists idx_machines_work_center on machines(work_center_id);
alter table machines enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_machines') THEN
    CREATE POLICY "allow_all_machines" ON machines FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
```

### Table `toolings` (outillages)
```sql
create table if not exists toolings (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  code text not null,
  name text not null,
  machine_id uuid references machines(id) on delete set null,
  max_pieces int default 0,
  initial_counter int default 0,
  current_counter int default 0,
  status text default 'active' check (status in ('active','worn','inactive')),
  notes text,
  created_at timestamptz default now()
);
create index if not exists idx_toolings_code on toolings(code);
create index if not exists idx_toolings_machine on toolings(machine_id);
alter table toolings enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_toolings') THEN
    CREATE POLICY "allow_all_toolings" ON toolings FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
```

## 1.2 — Types TypeScript (`@/types/index.ts`)

Ajouter à la fin du fichier, avant la section Sprint 7 :

```typescript
// ============ Sprint Production: Gamme & Machine ============

export interface Routing {
  id: string
  code: string
  name: string
  description: string | null
  product_id: string | null
  version: number
  active: boolean
  created_at: string
  updated_at: string
}

export interface RoutingOperation {
  id: string
  routing_id: string
  sequence: number
  name: string
  description: string | null
  work_center_id: string | null
  machine_id: string | null
  tooling_id: string | null
  setup_time_min: number
  run_time_min: number
  is_subcontracted: boolean
  supplier_id: string | null
  st_unit: string | null
  st_quantity: number
  created_at: string
}

export interface WorkCenter {
  id: string
  code: string
  name: string
  capacity_hours_per_day: number
  cost_per_hour: number
  active: boolean
  created_at: string
}

export interface Machine {
  id: string
  code: string
  name: string
  work_center_id: string | null
  capacity_per_hour: number
  status: 'active' | 'maintenance' | 'inactive'
  purchase_date: string | null
  notes: string | null
  created_at: string
}

export interface Tooling {
  id: string
  code: string
  name: string
  machine_id: string | null
  max_pieces: number
  initial_counter: number
  current_counter: number
  status: 'active' | 'worn' | 'inactive'
  notes: string | null
  created_at: string
}
```

## 1.3 — Queries (`@/lib/queries.ts`)

Ajouter à la fin du fichier :

```typescript
// ============ Sprint Production: Routings ============
export async function getRoutings() {
  const tid = await getTenantId()
  let q = supabase.from('routings').select('*, products(name, sku)').order('code')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createRouting(r: Omit<Routing, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('routings').insert(ti(r, 'routings', tid)).select().single()
  if (error) throw error
  return data as Routing
}

export async function updateRouting(id: string, updates: Partial<Routing>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('routings').update(updates), 'routings', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Routing
}

export async function deleteRouting(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('routings').delete(), 'routings', tid).eq('id', id)
  if (error) throw error
}

export async function getRoutingOperations(routingId: string) {
  const tid = await getTenantId()
  let q = supabase.from('routing_operations').select('*, work_centers(name), machines(name), toolings(name), suppliers(name)').eq('routing_id', routingId).order('sequence')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createRoutingOperation(op: Omit<RoutingOperation, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('routing_operations').insert(ti(op, 'routing_operations', tid)).select().single()
  if (error) throw error
  return data as RoutingOperation
}

export async function updateRoutingOperation(id: string, updates: Partial<RoutingOperation>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('routing_operations').update(updates), 'routing_operations', tid).eq('id', id).select().single()
  if (error) throw error
  return data as RoutingOperation
}

export async function deleteRoutingOperation(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('routing_operations').delete(), 'routing_operations', tid).eq('id', id)
  if (error) throw error
}

// Renuméroter une opération (Sage 100 : "Gamme : Renuméroter une opération")
export async function renumberRoutingOperation(id: string, newSequence: number) {
  return updateRoutingOperation(id, { sequence: newSequence })
}

// Renumérotation générale de 10 en 10
export async function renumberAllOperations(routingId: string) {
  const ops = await getRoutingOperations(routingId)
  for (let i = 0; i < ops.length; i++) {
    await updateRoutingOperation(ops[i].id, { sequence: (i + 1) * 10 })
  }
}

// ============ Sprint Production: Work Centers ============
export async function getWorkCenters() {
  const tid = await getTenantId()
  let q = supabase.from('work_centers').select('*').order('code')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as WorkCenter[]
}

export async function createWorkCenter(wc: Omit<WorkCenter, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('work_centers').insert(ti(wc, 'work_centers', tid)).select().single()
  if (error) throw error
  return data as WorkCenter
}

export async function deleteWorkCenter(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('work_centers').delete(), 'work_centers', tid).eq('id', id)
  if (error) throw error
}

// ============ Sprint Production: Machines ============
export async function getMachines() {
  const tid = await getTenantId()
  let q = supabase.from('machines').select('*, work_centers(name)').order('code')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createMachine(m: Omit<Machine, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('machines').insert(ti(m, 'machines', tid)).select().single()
  if (error) throw error
  return data as Machine
}

export async function updateMachine(id: string, updates: Partial<Machine>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('machines').update(updates), 'machines', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Machine
}

export async function deleteMachine(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('machines').delete(), 'machines', tid).eq('id', id)
  if (error) throw error
}

// ============ Sprint Production: Toolings ============
export async function getToolings() {
  const tid = await getTenantId()
  let q = supabase.from('toolings').select('*, machines(name)').order('code')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createTooling(t: Omit<Tooling, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('toolings').insert(ti(t, 'toolings', tid)).select().single()
  if (error) throw error
  return data as Tooling
}

export async function updateTooling(id: string, updates: Partial<Tooling>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('toolings').update(updates), 'toolings', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Tooling
}

export async function deleteTooling(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('toolings').delete(), 'toolings', tid).eq('id', id)
  if (error) throw error
}
```

## 1.4 — Pages React

### Page `RoutingsPage.tsx`
**Fichier** : `@/pages/RoutingsPage.tsx`
**Pattern** : Identique à `BOMPage.tsx` — liste avec expand/collapse pour voir les opérations.

**Structure** :
- `Breadcrumb` : Production / Gammes opératoires
- `PageHeader` : "Gammes opératoires" + bouton "Nouvelle gamme"
- `Table` : Code, Nom, Produit, Version, Actif, Actions (expand + delete)
- **Expand** : Table des opérations (Séquence, Nom, Centre de charge, Machine, Outillage, Temps prép, Temps exéc, S/T, Actions)
- **Modal `RoutingFormModal`** : Code, Nom, Produit (select), Description
- **Modal `RoutingOperationFormModal`** : Nom, Séquence, Centre de charge (select), Machine (select), Outillage (select), Temps prép (min), Temps exéc (min), Sous-traité (checkbox), Fournisseur (select si S/T), Unité S/T, Quantité S/T
- **Bouton "Renuméroter 10 par 10"** dans la zone expand (appelle `renumberAllOperations`)
- **Bouton "Renuméroter"** sur chaque ligne d'opération (ouvre un prompt pour saisir le nouveau numéro, appelle `renumberRoutingOperation`)
- **Bouton "Export Excel"** : exporte les gammes + opérations au format Excel (installer `xlsx` : `npm install xlsx`)
- **Bouton "Import Excel"** : importe un fichier Excel avec mapping des colonnes

### Page `MachinesPage.tsx`
**Fichier** : `@/pages/MachinesPage.tsx`
**Structure** :
- `Breadcrumb` : Production / Machines & Outillages
- `PageHeader` : "Machines" + bouton "Nouvelle machine" + bouton "Export Excel" + bouton "Import Excel"
- `Table` : Code, Nom, Centre de charge, Capacité/h, Statut, Actions
- **Modal `MachineFormModal`** : Code, Nom, Centre de charge (select), Capacité/h, Statut (select: active/maintenance/inactive), Date d'achat, Notes
- **Section "Centres de charge"** : sous-tableau avec CRUD inline (Code, Nom, Capacité h/jour, Coût/h, Supprimer)

### Page `ToolingsPage.tsx`
**Fichier** : `@/pages/ToolingsPage.tsx`
**Structure** :
- `Breadcrumb` : Production / Outillages
- `PageHeader` : "Outillages" + bouton "Nouvel outillage" + bouton "Export Excel" + bouton "Import Excel"
- `Table` : Code, Nom, Machine, Pièces max, Compteur initial, Compteur actuel, Usure (% = current_counter / max_pieces * 100), Statut, Actions
- **Modal `ToolingFormModal`** : Code, Nom, Machine (select), Pièces max, Compteur initial (Sage 100 : "Compteur d'origine"), Compteur actuel, Statut, Notes
- **Colonne "Usure"** : barre de progression colorée (vert < 70%, orange 70-90%, rouge > 90%)

## 1.5 — Import/Export Excel

**Logique** (Sage 100 : "Import/Export au format Excel") :
1. **Export** : Récupérer toutes les données via les queries existantes, créer un workbook `xlsx`, télécharger le fichier
2. **Import** : FileReader → `xlsx.read()` → parcourir les lignes → pour chaque ligne : si `id` existe → `update`, sinon → `create`
3. L'utilisateur peut exporter le format vide (sans données) en sélectionnant les champs

**Code utilitaire** à créer dans `@/lib/excel-utils.ts` :
```typescript
import * as XLSX from 'xlsx'

export function exportToExcel(data: any[], filename: string, sheetName = 'Sheet1') {
  const ws = XLSX.utils.json_to_sheet(data)
  const wb = XLSX.utils.book_new()
  XLSX.utils.book_append_sheet(wb, ws, sheetName)
  XLSX.writeFile(wb, filename)
}

export async function importFromExcel(file: File): Promise<any[]> {
  const buf = await file.arrayBuffer()
  const wb = XLSX.read(buf)
  const ws = wb.Sheets[wb.SheetNames[0]]
  return XLSX.utils.sheet_to_json(ws)
}
```

## 1.6 — Modifications tables existantes

```sql
-- Ajouter routing_id sur boms et manufacturing_orders
alter table boms add column if not exists routing_id uuid references routings(id) on delete set null;
alter table manufacturing_orders add column if not exists routing_id uuid references routings(id) on delete set null;
```

## 1.7 — Navigation & Routes

**`Layout.tsx`** — Ajouter un nouveau groupe dans `navGroups` :
```typescript
{
  label: 'Production',
  items: [
    {
      label: 'Gestion production',
      icon: Factory,  // importer de lucide-react
      path: '/production',
      subItems: [
        { label: 'Tableau de bord', path: '/production' },
        { label: 'Gammes opératoires', path: '/production/routings' },
        { label: 'Machines', path: '/production/machines' },
        { label: 'Outillages', path: '/production/toolings' },
        { label: 'Sous-traitance', path: '/production/subcontracting/orders' },
        { label: 'Expéditions S/T', path: '/production/subcontracting/shipments' },
        { label: 'Réceptions S/T', path: '/production/subcontracting/receipts' },
        { label: 'Superviseur S/T', path: '/production/subcontracting/supervisor' },
        { label: 'Ordres de fabrication', path: '/production/manufacturing' },
        { label: 'CBN (MRP)', path: '/production/mrp' },
        { label: 'Documents en attente', path: '/production/mrp/pending' },
        { label: 'Prévisions', path: '/production/forecasts' },
        { label: 'Planification', path: '/production/planning' },
      ],
    },
  ],
},
```

**`App.tsx`** — Ajouter les routes (voir section Routes complètes ci-dessous).

**`supabase.ts`** — Ajouter dans `TENANT_TABLES` :
```typescript
'routings', 'routing_operations', 'work_centers', 'machines', 'toolings',
```

**`ui.tsx`** — Ajouter dans `routeLabels` :
```typescript
'production': 'Production',
'routings': 'Gammes opératoires',
'machines': 'Machines',
'toolings': 'Outillages',
'subcontracting': 'Sous-traitance',
'supervisor': 'Superviseur',
'mrp': 'CBN',
'forecasts': 'Prévisions',
'planning': 'Planification',
```

---

# SPRINT 2 : Sous-Traitance

> **Fonctionnalités Sage 100 couvertes** :
> - S/T : Commande (refonte écran passation commandes, mode liste/grille, filtres, décimales)
> - S/T : Gestion des décimales dans les opérations
> - S/T : Expédition (historique, bordereau, ajout d'articles, multiple d'expédition)
> - S/T : Réception (entrées stock, consommation composants, retour matières, lot/série, bordereau, réceptions multiples, historisation)
> - S/T : Superviseur (pilotage, fournisseurs à relancer, calendrier livraisons)
> - CBN : Sous-traitance et dépôt fournisseur

## 2.1 — Tables SQL

### Table `subcontracting_orders` (commandes de sous-traitance)
```sql
create table if not exists subcontracting_orders (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  number text not null unique,
  supplier_id uuid not null references suppliers(id) on delete restrict,
  manufacturing_order_id uuid references manufacturing_orders(id) on delete set null,
  routing_operation_id uuid references routing_operations(id) on delete set null,
  order_date date not null default current_date,
  expected_date date,
  status text not null default 'draft' check (status in ('draft','sent','in_progress','received','cancelled')),
  st_unit text not null default 'unit',
  st_quantity numeric(15,2) not null default 1,
  unit_price numeric(15,2) default 0,
  total_price numeric(15,2) default 0,
  warehouse_id uuid references warehouses(id) on delete set null,
  notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists idx_st_orders_supplier on subcontracting_orders(supplier_id);
create index if not exists idx_st_orders_status on subcontracting_orders(status);
create index if not exists idx_st_orders_mo on subcontracting_orders(manufacturing_order_id);
alter table subcontracting_orders enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_subcontracting_orders') THEN
    CREATE POLICY "allow_all_subcontracting_orders" ON subcontracting_orders FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
```

### Table `subcontracting_shipments` (expéditions S/T)
```sql
create table if not exists subcontracting_shipments (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  number text not null unique,
  subcontracting_order_id uuid not null references subcontracting_orders(id) on delete cascade,
  shipment_date date not null default current_date,
  status text not null default 'pending' check (status in ('pending','shipped','cancelled')),
  shipment_multiple numeric(15,2) default 1,
  notes text,
  created_at timestamptz default now()
);
create index if not exists idx_st_shipments_order on subcontracting_shipments(subcontracting_order_id);
alter table subcontracting_shipments enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_subcontracting_shipments') THEN
    CREATE POLICY "allow_all_subcontracting_shipments" ON subcontracting_shipments FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
```

### Table `subcontracting_shipment_lines` (lignes d'expédition)
```sql
create table if not exists subcontracting_shipment_lines (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  shipment_id uuid not null references subcontracting_shipments(id) on delete cascade,
  product_id uuid not null references products(id) on delete cascade,
  description text,
  quantity numeric(15,2) not null default 1,
  unit text default 'unit',
  is_from_bom boolean default true,
  created_at timestamptz default now()
);
create index if not exists idx_st_shipment_lines_shipment on subcontracting_shipment_lines(shipment_id);
alter table subcontracting_shipment_lines enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_subcontracting_shipment_lines') THEN
    CREATE POLICY "allow_all_subcontracting_shipment_lines" ON subcontracting_shipment_lines FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
```

### Table `subcontracting_receipts` (réceptions S/T)
```sql
create table if not exists subcontracting_receipts (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  number text not null unique,
  subcontracting_order_id uuid not null references subcontracting_orders(id) on delete cascade,
  receipt_date date not null default current_date,
  status text not null default 'pending' check (status in ('pending','received','partial','cancelled')),
  warehouse_id uuid references warehouses(id) on delete set null,
  notes text,
  created_at timestamptz default now()
);
create index if not exists idx_st_receipts_order on subcontracting_receipts(subcontracting_order_id);
create index if not exists idx_st_receipts_status on subcontracting_receipts(status);
alter table subcontracting_receipts enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_subcontracting_receipts') THEN
    CREATE POLICY "allow_all_subcontracting_receipts" ON subcontracting_receipts FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
```

### Table `subcontracting_receipt_lines` (lignes de réception)
```sql
create table if not exists subcontracting_receipt_lines (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  receipt_id uuid not null references subcontracting_receipts(id) on delete cascade,
  product_id uuid not null references products(id) on delete cascade,
  description text,
  quantity_received numeric(15,2) not null default 0,
  quantity_consumed numeric(15,2) default 0,
  quantity_returned numeric(15,2) default 0,
  unit text default 'unit',
  lot_number text,
  serial_numbers text,
  is_rejected boolean default false,
  rejected_serials text,
  movement_type text default 'in' check (movement_type in ('in','out')),
  created_at timestamptz default now()
);
create index if not exists idx_st_receipt_lines_receipt on subcontracting_receipt_lines(receipt_id);
alter table subcontracting_receipt_lines enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_subcontracting_receipt_lines') THEN
    CREATE POLICY "allow_all_subcontracting_receipt_lines" ON subcontracting_receipt_lines FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
```

### Modification `warehouses` (dépôt fournisseur)
```sql
alter table warehouses add column if not exists warehouse_type text default 'main' check (warehouse_type in ('main','subcontractor','supplier'));
alter table suppliers add column if not exists default_warehouse_id uuid references warehouses(id) on delete set null;
```

### Modification `stock_movements` (nouveaux types de référence)
```sql
-- Ajouter 'production' et 'subcontracting' aux types de référence autorisés
ALTER TABLE stock_movements DROP CONSTRAINT IF EXISTS stock_movements_reference_type_check;
ALTER TABLE stock_movements ADD CONSTRAINT stock_movements_reference_type_check
  CHECK (reference_type IN ('delivery_note','goods_receipt','inventory','transfer','manual','production','subcontracting'));
```

## 2.2 — Types TypeScript

```typescript
export interface SubcontractingOrder {
  id: string
  number: string
  supplier_id: string
  manufacturing_order_id: string | null
  routing_operation_id: string | null
  order_date: string
  expected_date: string | null
  status: 'draft' | 'sent' | 'in_progress' | 'received' | 'cancelled'
  st_unit: string
  st_quantity: number
  unit_price: number
  total_price: number
  warehouse_id: string | null
  notes: string | null
  created_at: string
  updated_at: string
}

export interface SubcontractingShipment {
  id: string
  number: string
  subcontracting_order_id: string
  shipment_date: string
  status: 'pending' | 'shipped' | 'cancelled'
  shipment_multiple: number
  notes: string | null
  created_at: string
}

export interface SubcontractingShipmentLine {
  id: string
  shipment_id: string
  product_id: string
  description: string | null
  quantity: number
  unit: string
  is_from_bom: boolean
  created_at: string
}

export interface SubcontractingReceipt {
  id: string
  number: string
  subcontracting_order_id: string
  receipt_date: string
  status: 'pending' | 'received' | 'partial' | 'cancelled'
  warehouse_id: string | null
  notes: string | null
  created_at: string
}

export interface SubcontractingReceiptLine {
  id: string
  receipt_id: string
  product_id: string
  description: string | null
  quantity_received: number
  quantity_consumed: number
  quantity_returned: number
  unit: string
  lot_number: string | null
  serial_numbers: string | null
  is_rejected: boolean
  rejected_serials: string | null
  movement_type: 'in' | 'out'
  created_at: string
}
```

## 2.3 — Queries

Même pattern que Sprint 1. Fonctions à créer :
- `getSubcontractingOrders()`, `createSubcontractingOrder()`, `updateSubcontractingOrder()`, `deleteSubcontractingOrder()`
- `getSubcontractingShipments()`, `createSubcontractingShipment()`, `deleteSubcontractingShipment()`
- `getSubcontractingShipmentLines()`, `createSubcontractingShipmentLine()`, `deleteSubcontractingShipmentLine()`
- `getSubcontractingReceipts()`, `createSubcontractingReceipt()`, `updateSubcontractingReceipt()`, `deleteSubcontractingReceipt()`
- `getSubcontractingReceiptLines()`, `createSubcontractingReceiptLine()`, `deleteSubcontractingReceiptLine()`

**Logique spéciale réception** (Sage 100 : "Réception") :
```typescript
// Quand on valide une réception S/T, il faut :
// 1. Créer un stock_movement 'in' pour le produit fabriqué (entrée en stock)
// 2. Créer un stock_movement 'out' pour chaque composant consommé
// 3. Créer un stock_movement 'in' pour les retours de matières
// 4. Mettre à jour stock_quantities (incrémenter/décrémenter)
// 5. Mettre à jour le statut de l'OF lié
export async function validateSubcontractingReceipt(receiptId: string) {
  const tid = await getTenantId()
  const lines = await getSubcontractingReceiptLines(receiptId)
  const receipt = await getSubcontractingReceipt(receiptId) // à créer

  for (const line of lines) {
    if (line.movement_type === 'in' && line.quantity_received > 0) {
      // Entrée en stock du produit fabriqué
      await createStockMovement({
        product_id: line.product_id,
        warehouse_id: receipt.warehouse_id,
        movement_type: 'in',
        quantity: line.quantity_received,
        reference: receipt.number,
        reference_type: 'subcontracting',
        reference_id: receiptId,
        movement_date: receipt.receipt_date,
        notes: `Réception S/T ${receipt.number}`,
      })
    }
    if (line.quantity_consumed > 0) {
      // Sortie des composants consommés
      await createStockMovement({
        product_id: line.product_id,
        warehouse_id: receipt.warehouse_id,
        movement_type: 'out',
        quantity: line.quantity_consumed,
        reference: receipt.number,
        reference_type: 'subcontracting',
        reference_id: receiptId,
        movement_date: receipt.receipt_date,
        notes: `Consommation S/T ${receipt.number}`,
      })
    }
    if (line.quantity_returned > 0) {
      // Retour de matières du sous-traitant
      await createStockMovement({
        product_id: line.product_id,
        warehouse_id: receipt.warehouse_id,
        movement_type: 'in',
        quantity: line.quantity_returned,
        reference: receipt.number,
        reference_type: 'subcontracting',
        reference_id: receiptId,
        movement_date: receipt.receipt_date,
        notes: `Retour matières S/T ${receipt.number}`,
      })
    }
  }

  // Mettre à jour le statut de la réception
  await updateSubcontractingReceipt(receiptId, { status: 'received' })
}
```

## 2.4 — Pages React

### Page `SubcontractingOrdersPage.tsx`
**Logique Sage 100** : "Refonte de l'écran de passation des commandes de S/T à l'opération. Mode liste (multilignes) et mode grille avec filtres et personnalisation des colonnes. Prise en charge des quantités en décimales."

**Structure** :
- `Breadcrumb` : Production / Sous-traitance / Commandes
- `PageHeader` : "Commandes de sous-traitance" + bouton "Nouvelle commande S/T"
- **Toggle Liste/Grille** : bouton pour basculer entre mode `Table` et mode `SortableTable` (grille filtrable)
- `Table` : N°, Fournisseur, OF lié, Opération, Date, Date prévue, Unité S/T, Qté S/T, Prix total, Statut, Actions
- **Filtres** : Select fournisseur, Select statut, Input date début, Input date fin
- **Modal `SubcontractingOrderFormModal`** :
  - Fournisseur (select, requis)
  - OF lié (select parmi les `manufacturing_orders` non terminés)
  - Opération (select parmi les `routing_operations` de la gamme de l'OF sélectionné, filtré par `is_subcontracted = true`)
  - Date commande, Date prévue
  - **Unité de sous-traitance** (text, ex: "Kg" — Sage 100 : "définir une unité de S/T qui n'est pas l'unité de production")
  - **Quantité S/T** (decimal, ex: 50.5 — Sage 100 : "gestion des décimales")
  - Prix unitaire, Prix total (auto-calculé = qté × prix)
  - Dépôt (select — Sage 100 : "dépôt de rattachement du fournisseur")
  - Notes

### Page `SubcontractingShipmentsPage.tsx`
**Logique Sage 100** : "Historique des expéditions, bordereau d'expédition, ajout d'articles non prévus dans la nomenclature de l'OF, multiple d'expédition."

**Structure** :
- `Breadcrumb` : Production / Sous-traitance / Expéditions
- `PageHeader` : "Expéditions sous-traitance" + bouton "Nouvelle expédition"
- `Table` : N°, Commande S/T, Fournisseur, Date, Multiple, Statut, Actions (voir détail, imprimer bordereau)
- **Modal `SubcontractingShipmentFormModal`** :
  - Commande S/T (select)
  - Date d'expédition
  - **Multiple d'expédition** (decimal — Sage 100 : "expédier par 1000 pour envoyer des boîtes complètes")
  - Table des lignes : articles de la BOM de l'OF (pré-rempli) + bouton "Ajouter article" (Sage 100 : "ajouter des articles non prévus dans la nomenclature")
  - Pour chaque ligne : Produit (select), Description, Quantité, Unité, `is_from_bom` (checkbox)
- **Bouton "Imprimer bordereau"** : génère un PDF du bordereau d'expédition (utiliser `window.print()` avec un template HTML stylé, ou installer `jspdf`)
- **Historique** : sur la commande S/T, afficher toutes les expéditions liées

### Page `SubcontractingReceiptsPage.tsx`
**Logique Sage 100** : "Réceptionner le produit fabriqué + entrée en stock. Gestion OF multi-références (amalgame + sous-produits). Ajout d'articles en entrée/sortie non prévus. Consommation des composants. Retour de matières. Gestion lot/série avec N° de série rebutés. Transformation commande en bon de livraison. Bordereau de réception. Réceptions multiples. Historisation."

**Structure** :
- `Breadcrumb` : Production / Sous-traitance / Réceptions
- `PageHeader` : "Réceptions sous-traitance" + bouton "Nouvelle réception"
- `Table` : N°, Commande S/T, Fournisseur, Date, Dépôt, Statut, Actions (voir détail, valider, imprimer bordereau)
- **Modal `SubcontractingReceiptFormModal`** :
  - Commande S/T (select)
  - Date de réception
  - Dépôt (select)
  - **Table des lignes** (pré-remplie avec les produits de l'OF) :
    - Produit, Description
    - **Qté reçue** (decimal)
    - **Qté consommée** (decimal — Sage 100 : "consommation des composants")
    - **Qté retournée** (decimal — Sage 100 : "retour de matières lorsque le sous-traitant renvoie le surplus")
    - Unité
    - **N° de lot** (text — Sage 100 : "gestion lot/série")
    - **N° de série** (text)
    - **Rebuté** (checkbox — Sage 100 : "identification des N° de série rebutés")
    - **N° série rebutés** (text, visible si rebuté = true)
    - **Type mouvement** (select: entrée/sortie — Sage 100 : "ajout d'articles en entrée ou sortie")
  - Bouton "Ajouter article" (Sage 100 : "ajouter des articles non prévus dans l'OF")
  - Bouton "Valider la réception" → appelle `validateSubcontractingReceipt()` qui crée les `stock_movements` et met à jour `stock_quantities`
  - Bouton "Imprimer bordereau" → génère un PDF

### Page `SubcontractingSupervisorPage.tsx`
**Logique Sage 100** : "Piloter l'activité de sous-traitance. Aperçu des commandes et OF en cours, fournisseurs à relancer, suivi de l'avancement, calendrier des livraisons prévisionnelles. Modifier directement les dates de livraisons dans les commandes."

**Structure** :
- `Breadcrumb` : Production / Sous-traitance / Superviseur
- `PageHeader` : "Superviseur sous-traitance"
- **StatCard x 4** :
  - Commandes en cours (count, status in 'sent','in_progress')
  - OF en sous-traitance (count, MO liées à des ST orders non reçues)
  - Fournisseurs à relancer (count, expected_date < today et status != 'received')
  - Réceptions ce mois (count)
- **Table "Commandes en cours"** : N°, Fournisseur, OF, Date prévue, Statut, Avancement (% = réceptions / total), Actions (modifier date de livraison inline)
- **Table "Fournisseurs à relancer"** : Fournisseur, Nb commandes en retard, Date la plus ancienne, Bouton "Relancer" (envoie email via Supabase function)
- **Calendrier des livraisons prévisionnelles** : composant calendrier simple (peut utiliser `react-calendar` ou un tableau par semaine) affichant les `expected_date` des commandes S/T

---

# SPRINT 3 : Amalgame (OF Multi-références)

> **Fonctionnalités Sage 100 couvertes** :
> - Amalgam : Gestion des OF multi-références NOUVEAU !
> - Amalgam : Création des ordres de fabrication
> - Amalgam : Propositions du CBN

## 3.1 — Modifications SQL

```sql
-- Ajouter bom_type sur boms (standard vs amalgam/inversé)
ALTER TABLE boms ADD COLUMN IF NOT EXISTS bom_type text default 'standard' check (bom_type in ('standard','amalgam'));

-- Pour les amalgams, bom_lines représente les PRODUITS FINIS (pas les composants)
-- Un amalgame = 1 matière première → plusieurs produits finis
-- Pas besoin de nouvelle table, on réutilise bom_lines avec bom_type='amalgam'
```

### Modification `products`
```sql
ALTER TABLE products ADD COLUMN IF NOT EXISTS is_amalgam boolean default false;
ALTER TABLE products ADD COLUMN IF NOT EXISTS units_per_carton int;
ALTER TABLE products ADD COLUMN IF NOT EXISTS st_unit text;
ALTER TABLE products ADD COLUMN IF NOT EXISTS purchase_unit text;
ALTER TABLE products ADD COLUMN IF NOT EXISTS st_multiple numeric(15,2) default 1;
ALTER TABLE products ADD COLUMN IF NOT EXISTS shelf_life_days int;
ALTER TABLE products ADD COLUMN IF NOT EXISTS exclude_from_mrp boolean default false;
```

## 3.2 — Types TypeScript

```typescript
// Étendre BOM
export interface BOM {
  id: string
  code: string
  name: string
  product_id: string | null
  quantity: number
  unit: string
  active: boolean
  bom_type: 'standard' | 'amalgam'  // NOUVEAU
  routing_id: string | null           // NOUVEAU (Sprint 1)
  created_at: string
}

// Étendre Product
export interface Product {
  // ... champs existants ...
  is_amalgam: boolean
  units_per_carton: number | null
  st_unit: string | null
  purchase_unit: string | null
  st_multiple: number
  shelf_life_days: number | null
  exclude_from_mrp: boolean
}
```

## 3.3 — Modification `BOMPage.tsx`

**Logique Sage 100** : "Pour un article fabriqué typé amalgame, définir une liste de produits finis. Secteurs : plasturgie (moules multi-empreintes), découpe (plans de découpe), recyclage (désassemblage)."

**Modifications** :
1. Ajouter un `Select` "Type de nomenclature" dans `BOMFormModal` : Standard | Amalgame
2. Si `bom_type = 'amalgam'` :
   - Le label "Produit fini" devient "Matière première"
   - Le label "Composant" dans `BOMLineFormModal` devient "Produit fini"
   - Les lignes représentent les produits finis obtenus, pas les composants consommés
3. Dans la table principale, ajouter une colonne "Type" avec un `Badge` (Standard / Amalgam)
4. Filtrer par type (Select dans la PageHeader)

## 3.4 — Modification `ManufacturingOrdersPage.tsx`

**Logique Sage 100** : "Lors de la création d'un OF de type amalgame, l'interface propose le contenu de la combinaison qui peut être modifiée (ex: boucher une empreinte sur le moule). Le contenu peut être imprimé sur le bon de travail."

**Modifications dans `OFForm`** :
1. Quand l'utilisateur sélectionne une BOM de type `amalgam` :
   - Afficher automatiquement la liste des produits finis de l'amalgam (via `getBOMLines(bomId)`)
   - Pour chaque produit fini : afficher Quantité (modifiable — Sage 100 : "décision de boucher une empreinte")
   - Checkbox "Inclure" (pour exclure une référence de l'OF)
2. Bouton "Imprimer bon de travail" → génère un PDF avec le contenu de l'OF

---

# SPRINT 4 : Ordre de Fabrication — Enhancements

> **Fonctionnalités Sage 100 couvertes** :
> - OF : Création des étiquettes (onglet "Suivi Quantité")
> - OF : Traçabilité (origine : manuel, CBN, sous-niveau)
> - OF : Procédure de post-traitement
> - OF : Lot et date de péremption personnalisée
> - OF : Dossier de fabrication (droits d'accès)
> - Consommation différée : Saisie sur OF terminé
> - OF à la commande : Recopie du texte complémentaire

## 4.1 — Tables SQL

### Table `of_labels` (étiquettes cartons)
```sql
create table if not exists of_labels (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  manufacturing_order_id uuid not null references manufacturing_orders(id) on delete cascade,
  label_number text not null unique,
  product_id uuid references products(id) on delete set null,
  planned_quantity numeric(15,2) default 0,
  actual_quantity numeric(15,2) default 0,
  is_complete boolean default false,
  is_declared boolean default false,
  created_at timestamptz default now()
);
create index if not exists idx_of_labels_mo on of_labels(manufacturing_order_id);
alter table of_labels enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_of_labels') THEN
    CREATE POLICY "allow_all_of_labels" ON of_labels FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
```

### Table `of_lots` (lots d'OF avec péremption)
```sql
create table if not exists of_lots (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  manufacturing_order_id uuid not null references manufacturing_orders(id) on delete cascade,
  lot_number text not null,
  product_id uuid references products(id) on delete set null,
  quantity numeric(15,2) default 0,
  production_date date,
  expiry_date date,
  custom_expiry_date date,
  expiry_type text check (expiry_type in ('dlUO','DDM','DLC')),
  created_at timestamptz default now()
);
create index if not exists idx_of_lots_mo on of_lots(manufacturing_order_id);
alter table of_lots enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_of_lots') THEN
    CREATE POLICY "allow_all_of_lots" ON of_lots FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
```

### Table `of_consumptions` (consommation différée)
```sql
create table if not exists of_consumptions (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  manufacturing_order_id uuid not null references manufacturing_orders(id) on delete cascade,
  product_id uuid not null references products(id) on delete cascade,
  quantity numeric(15,2) not null default 0,
  unit text default 'unit',
  consumption_date date not null default current_date,
  is_deferred boolean default false,
  notes text,
  created_at timestamptz default now()
);
create index if not exists idx_of_consumptions_mo on of_consumptions(manufacturing_order_id);
alter table of_consumptions enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_of_consumptions') THEN
    CREATE POLICY "allow_all_of_consumptions" ON of_consumptions FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
```

### Modification `manufacturing_orders`
```sql
ALTER TABLE manufacturing_orders ADD COLUMN IF NOT EXISTS origin text default 'manual' check (origin in ('manual','mrp','sub_level'));
ALTER TABLE manufacturing_orders ADD COLUMN IF NOT EXISTS parent_mo_id uuid references manufacturing_orders(id) on delete set null;
ALTER TABLE manufacturing_orders ADD COLUMN IF NOT EXISTS lot_number text;
ALTER TABLE manufacturing_orders ADD COLUMN IF NOT EXISTS expiry_date date;
ALTER TABLE manufacturing_orders ADD COLUMN IF NOT EXISTS custom_expiry_date date;
ALTER TABLE manufacturing_orders ADD COLUMN IF NOT EXISTS expiry_type text check (expiry_type in ('DLUO','DDM','DLC'));
ALTER TABLE manufacturing_orders ADD COLUMN IF NOT EXISTS label_enabled boolean default false;
ALTER TABLE manufacturing_orders ADD COLUMN IF NOT EXISTS sales_order_id uuid references sales_orders(id) on delete set null;
ALTER TABLE manufacturing_orders ADD COLUMN IF NOT EXISTS additional_text text;
```

## 4.2 — Types TypeScript

```typescript
export interface OFLabel {
  id: string
  manufacturing_order_id: string
  label_number: string
  product_id: string | null
  planned_quantity: number
  actual_quantity: number
  is_complete: boolean
  is_declared: boolean
  created_at: string
}

export interface OFLot {
  id: string
  manufacturing_order_id: string
  lot_number: string
  product_id: string | null
  quantity: number
  production_date: string | null
  expiry_date: string | null
  custom_expiry_date: string | null
  expiry_type: 'DLUO' | 'DDM' | 'DLC' | null
  created_at: string
}

export interface OFConsumption {
  id: string
  manufacturing_order_id: string
  product_id: string
  quantity: number
  unit: string
  consumption_date: string
  is_deferred: boolean
  notes: string | null
  created_at: string
}

// Étendre ManufacturingOrder
export interface ManufacturingOrder {
  id: string
  number: string
  bom_id: string | null
  product_id: string | null
  quantity: number
  status: 'planned' | 'in_progress' | 'completed' | 'cancelled'
  start_date: string | null
  end_date: string | null
  warehouse_id: string | null
  notes: string | null
  origin: 'manual' | 'mrp' | 'sub_level'  // NOUVEAU
  parent_mo_id: string | null               // NOUVEAU
  routing_id: string | null                 // NOUVEAU (Sprint 1)
  lot_number: string | null                 // NOUVEAU
  expiry_date: string | null                // NOUVEAU
  custom_expiry_date: string | null         // NOUVEAU
  expiry_type: 'DLUO' | 'DDM' | 'DLC' | null // NOUVEAU
  label_enabled: boolean                     // NOUVEAU
  sales_order_id: string | null             // NOUVEAU
  additional_text: string | null            // NOUVEAU
  created_at: string
}
```

## 4.3 — Page `ManufacturingOrderDetailPage.tsx`

**Nouvelle page** avec onglets (Sage 100 : "onglet Suivi Quantité").

**Route** : `/production/of/:id`

**Structure** :
- `Breadcrumb` : Production / Ordres de fabrication / {number}
- `PageHeader` : "OF {number}" + badges statut + boutons d'action
- **Onglets** (tabs) :
  1. **Informations** : BOM, quantité, dates, dépôt, gamme, origine (Sage 100 : "Traçabilité — provenance de l'OF")
  2. **Suivi Quantité** (Sage 100 : "onglet Suivi Quantité") :
     - Table des étiquettes cartons (`of_labels`) avec : N° étiquette, Produit, Qté prévue, Qté réelle, Complète, Déclarée, Actions
     - Bouton "Générer étiquettes" (crée N étiquettes basées sur `units_per_carton` du produit)
     - Bouton "Déclarer carton" (marque `is_declared = true` et crée un `stock_movement 'in'`)
  3. **Lots & Péremption** :
     - Table des lots (`of_lots`) : N° lot, Produit, Quantité, Date production, Date péremption, Type (DLUO/DDM/DLC)
     - Bouton "Ajouter lot" → `LotFormModal`
     - **Date de péremption personnalisée** (Sage 100 : "DLC, DDM, DLUO personnalisée") : si `custom_expiry_date` est renseignée, elle remplace le calcul automatique
  4. **Consommation** :
     - Table des consommations (`of_consumptions`)
     - **Case à cocher "Autoriser saisie sur OF terminé"** (Sage 100 : "Consommation différée : saisie sur OF terminé") — si l'OF est `completed` et cette case est cochée, permettre l'ajout de consommations
     - Bouton "Ajouter consommation" → sélection produit + quantité
  5. **Sous-niveaux** :
     - Si la BOM a des sous-nomenclatures, afficher les sous-OF créés (`parent_mo_id = this.id`)
     - Bouton "Créer sous-OF" pour un sous-niveau de nomenclature

## 4.4 — Modification `ManufacturingOrdersPage.tsx`

Ajouter :
- Colonne "Origine" avec badge (Manuel / CBN / Sous-niveau)
- Lien cliquable sur le N° d'OF → navigue vers `/production/of/:id`
- Dans `OFForm` : champ "Texte complémentaire" (Sage 100 : "Recopie du texte complémentaire dans le commentaire de l'OF")

---

# SPRINT 5 : CBN (Calcul des Besoins Nets / MRP)

> **Fonctionnalités Sage 100 couvertes** :
> - CBN : Transfert de dépôts à dépôts
> - CBN : Délai théorique sur une commande
> - CBN : Documents en attente
> - CBN : Analyse dernier calcul
> - CBN : Prise en compte de l'ordonnancement
> - CBN : Sous-traitance et dépôt fournisseur
> - CBN : Superviseur Achats / Ventes (Collaborateur)
> - CBN : Exclusion du stock (Emplacement et statut de lot)
> - Amalgam : Propositions du CBN

## 5.1 — Tables SQL

### Table `mrp_calculations` (historique des calculs)
```sql
create table if not exists mrp_calculations (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  number text not null unique,
  calculation_date date not null default current_date,
  horizon_start date not null,
  horizon_end date not null,
  status text default 'completed' check (status in ('draft','running','completed','cancelled')),
  parameters jsonb,
  summary jsonb,
  created_at timestamptz default now()
);
create index if not exists idx_mrp_calculations_date on mrp_calculations(calculation_date);
alter table mrp_calculations enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_mrp_calculations') THEN
    CREATE POLICY "allow_all_mrp_calculations" ON mrp_calculations FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
```

### Table `mrp_proposals` (propositions du CBN)
```sql
create table if not exists mrp_proposals (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  calculation_id uuid not null references mrp_calculations(id) on delete cascade,
  product_id uuid not null references products(id) on delete cascade,
  proposal_type text not null check (proposal_type in ('purchase','manufacture','transfer','subcontract')),
  quantity numeric(15,2) not null default 0,
  needed_date date not null,
  warehouse_id uuid references warehouses(id) on delete set null,
  source_warehouse_id uuid references warehouses(id) on delete set null,
  supplier_id uuid references suppliers(id) on delete set null,
  bom_id uuid references boms(id) on delete set null,
  status text default 'proposed' check (status in ('proposed','accepted','rejected','converted')),
  notes text,
  created_at timestamptz default now()
);
create index if not exists idx_mrp_proposals_calc on mrp_proposals(calculation_id);
create index if not exists idx_mrp_proposals_product on mrp_proposals(product_id);
create index if not exists idx_mrp_proposals_type on mrp_proposals(proposal_type);
create index if not exists idx_mrp_proposals_status on mrp_proposals(status);
alter table mrp_proposals enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_mrp_proposals') THEN
    CREATE POLICY "allow_all_mrp_proposals" ON mrp_proposals FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
```

### Table `mrp_pending_documents` (documents en attente)
```sql
create table if not exists mrp_pending_documents (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  document_type text not null check (document_type in ('purchase_order','manufacturing_order','transfer_order','subcontracting_order')),
  document_id uuid,
  document_number text,
  product_id uuid references products(id) on delete set null,
  quantity numeric(15,2) default 0,
  warehouse_id uuid references warehouses(id) on delete set null,
  status text default 'pending' check (status in ('pending','validated','cancelled')),
  created_date date not null default current_date,
  validated_date date,
  notes text,
  created_at timestamptz default now()
);
create index if not exists idx_mrp_pending_type on mrp_pending_documents(document_type);
create index if not exists idx_mrp_pending_status on mrp_pending_documents(status);
alter table mrp_pending_documents enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_mrp_pending_documents') THEN
    CREATE POLICY "allow_all_mrp_pending_documents" ON mrp_pending_documents FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
```

## 5.2 — Types TypeScript

```typescript
export interface MRPCalculation {
  id: string
  number: string
  calculation_date: string
  horizon_start: string
  horizon_end: string
  status: 'draft' | 'running' | 'completed' | 'cancelled'
  parameters: any
  summary: any
  created_at: string
}

export interface MRPProposal {
  id: string
  calculation_id: string
  product_id: string
  proposal_type: 'purchase' | 'manufacture' | 'transfer' | 'subcontract'
  quantity: number
  needed_date: string
  warehouse_id: string | null
  source_warehouse_id: string | null
  supplier_id: string | null
  bom_id: string | null
  status: 'proposed' | 'accepted' | 'rejected' | 'converted'
  notes: string | null
  created_at: string
}

export interface MRPPendingDocument {
  id: string
  document_type: 'purchase_order' | 'manufacturing_order' | 'transfer_order' | 'subcontracting_order'
  document_id: string | null
  document_number: string | null
  product_id: string | null
  quantity: number
  warehouse_id: string | null
  status: 'pending' | 'validated' | 'cancelled'
  created_date: string
  validated_date: string | null
  notes: string | null
  created_at: string
}
```

## 5.3 — Logique MRP (algorithme du CBN)

**Le CBN (Calcul des Besoins Nets) est le cœur de la gestion de production.**

### Algorithme (à implémenter dans `@/lib/mrp.ts`) :

```
Pour chaque produit ayant un besoin (ventes prévues, OF en cours, commandes clients) :
  1. Calculer le BESOIN BRUT par période :
     - Besoins externes : commandes clients confirmées + prévisions de production
     - Besoins internes : OF en cours (explosion des nomenclatures)
     - Pour les amalgams : besoins sur les références composant l'amalgame (Sage 100 : "Propositions du CBN pour amalgam")

  2. Calculer le STOCK DISPONIBLE :
     - Stock physique (stock_quantities)
     - MOINS stock réservé (reserved_quantity)
     - MOINS stock en emplacement de contrôle (Sage 100 : "Exclusion du stock — emplacement et statut de lot")
     - MOINS stock exclu (products.exclude_from_mrp)
     - PLUS réceptions attendues (commandes fournisseurs confirmées)
     - PLUS réceptions S/T attendues (sous-traitance en cours)

  3. Calculer le BESOIN NET = Besoin brut - Stock disponible
     Si Besoin Net ≤ 0 → pas de proposition

  4. Pour chaque besoin net positif, générer une PROPOSITION :
     - Si le produit a une BOM → proposition 'manufacture' (créer un OF)
       - Si la BOM est de type 'amalgam' → proposition 'manufacture' avec interface de guidage (Sage 100 : "propose une interface pour guider l'utilisateur")
     - Si le produit a une opération de sous-traitance → proposition 'subcontract'
     - Si le produit n'a pas de BOM → proposition 'purchase' (acheter)
     - Si le stock est disponible dans un autre dépôt → proposition 'transfer' (Sage 100 : "Transfert de dépôts à dépôts")

  5. Calculer les DATES :
     - Date de besoin = date de la commande client ou date de fin d'OF parent
     - Si ordonnancement actif (Sage 100 : "Prise en compte de l'ordonnancement") :
       Date de besoin du composant = date de début de l'opération qui l'utilise (pas le début de l'OF)
     - Date de proposition = date de besoin - délai d'approvisionnement (produit.lead_time_days ou supplier lead time)

  6. Calculer le DÉLAI THÉORIQUE (Sage 100 : "Délai théorique sur une commande") :
     - Pour une commande entière : somme des délais de tous les composants critiques
     - Prendre en compte le stock réservé et le dépôt renseigné sur les lignes de nomenclature
```

### Code `@/lib/mrp.ts` :
```typescript
import { supabase } from '@/lib/supabase'
import { getTenantId } from '@/lib/queries'

export async function runMRPCalculation(params: {
  horizonStart: string
  horizonEnd: string
  warehouseId?: string
  considerGantt: boolean
  excludeControlLocations: boolean
  excludeLotStatus: boolean
}): Promise<string> {
  const tid = await getTenantId()

  // 1. Récupérer tous les besoins (commandes clients + prévisions + OF en cours)
  // 2. Récupérer le stock disponible
  // 3. Calculer les besoins nets
  // 4. Générer les propositions
  // 5. Sauvegarder dans mrp_calculations + mrp_proposals

  // Détail de l'implémentation :
  // - Query sales_orders où status = 'confirmed', expected_date entre horizon
  // - Query manufacturing_orders où status in ('planned','in_progress')
  // - Pour chaque OF, exploser la BOM → besoins composants
  // - Query stock_quantities par warehouse
  // - Pour chaque besoin net > 0, créer une mrp_proposal

  // Retourner l'ID du calcul
  return calculationId
}
```

## 5.4 — Pages React

### Page `MRPCalculationsPage.tsx`
**Structure** :
- `Breadcrumb` : Production / CBN
- `PageHeader` : "Calcul des Besoins Nets" + bouton "Nouveau calcul"
- **StatCard x 3** : Dernier calcul (date), Propositions en attente (count), Documents en attente (count)
- `Table` : Historique des calculs (N°, Date, Horizon, Statut, Nb propositions, Actions)
- **Modal `MRPCalculationFormModal`** :
  - Date début horizon, Date fin horizon
  - Dépôt (select, optionnel)
  - **Checkbox "Prise en compte ordonnancement"** (Sage 100 : "Prise en compte de l'ordonnancement")
  - **Checkbox "Exclure stock en emplacement de contrôle"** (Sage 100 : "Exclusion du stock")
  - **Checkbox "Exclure stock par statut de lot"** (Sage 100)
  - Bouton "Lancer le calcul" → appelle `runMRPCalculation()`

### Page `MRPProposalsPage.tsx`
**Route** : `/production/mrp/proposals/:calcId`
**Logique Sage 100** : "Le CBN ne propose pas la meilleure combinaison mais propose une interface pour guider l'utilisateur. Permet de traiter en simultané plusieurs besoins de références différentes issus du même amalgame."

**Structure** :
- `Breadcrumb` : Production / CBN / Propositions
- `PageHeader` : "Propositions du CBN" + bouton "Tout valider" + bouton "Analyse dernier calcul"
- **Filtres** : Type (purchase/manufacture/transfer/subcontract), Statut, Produit
- `SortableTable` : Produit, Type, Quantité, Date besoin, Dépôt, Fournisseur/BOM, Statut, Actions
- **Actions par ligne** :
  - "Accepter" → status = 'accepted'
  - "Rejeter" → status = 'rejected'
  - "Convertir" → crée le document réel (purchase_order, manufacturing_order, etc.) et met status = 'converted'
- **Section "Amalgam"** (Sage 100 : "Propositions du CBN pour amalgam") :
  - Si des propositions concernent des produits d'un amalgame, les regrouper et afficher une interface de guidage
  - Permettre de traiter simultanément plusieurs besoins de références différentes du même amalgame
- **Bouton "Analyse dernier calcul"** (Sage 100 : "Analyse dernier calcul") :
  - Affiche un récapitulatif détaillé : besoins bruts, stock disponible, besoins nets, propositions par type
  - Liens vers l'interrogation article (Sage 100 : "lien permettant d'afficher la fenêtre d'interrogation article")
- **Bouton "Délai théorique"** (Sage 100 : "Délai théorique accessible depuis les propositions du CBN") :
  - Calcule et affiche le délai théorique pour la commande liée

### Page `MRPPendingDocumentsPage.tsx`
**Logique Sage 100** : "Documents en attente : consulter des informations synthétiques sur l'article. Afficher les tarifs fournisseurs. Fenêtre d'interrogation article général."

**Structure** :
- `Breadcrumb` : Production / CBN / Documents en attente
- `PageHeader` : "Documents en attente"
- `Table` : Type document, N°, Produit, Quantité, Dépôt, Date création, Statut, Actions
- **Actions** :
  - "Valider" → crée le document réel et met status = 'validated'
  - "Voir article" → ouvre `ArticleInterrogationModal` (Sage 100 : "fenêtre d'interrogation article général")
  - "Voir tarifs fournisseurs" → affiche les tarifs fournisseurs du produit (depuis `price_list_lines` où type='purchase')

---

# SPRINT 6 : Prévisions de Production

> **Fonctionnalités Sage 100 couvertes** :
> - Génération des prévisions : Import des factures (avec exclusion auto)
> - Prévision : Taux de fiabilité
> - Prévision : Gestion des décimales

## 6.1 — Tables SQL

```sql
create table if not exists production_forecasts (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  number text not null unique,
  name text not null,
  period_start date not null,
  period_end date not null,
  generation_method text default 'invoice_history' check (generation_method in ('manual','invoice_history')),
  exclusion_rule text,
  status text default 'draft' check (status in ('draft','validated','archived')),
  created_at timestamptz default now()
);
create index if not exists idx_production_forecasts_period on production_forecasts(period_start, period_end);
alter table production_forecasts enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_production_forecasts') THEN
    CREATE POLICY "allow_all_production_forecasts" ON production_forecasts FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

create table if not exists production_forecast_lines (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  forecast_id uuid not null references production_forecasts(id) on delete cascade,
  product_id uuid not null references products(id) on delete cascade,
  period_date date not null,
  forecast_quantity numeric(15,2) not null default 0,
  reliability_rate numeric(5,2) default 100,
  adjusted_quantity numeric(15,2) default 0,
  created_at timestamptz default now()
);
create index if not exists idx_forecast_lines_forecast on production_forecast_lines(forecast_id);
create index if not exists idx_forecast_lines_product on production_forecast_lines(product_id);
alter table production_forecast_lines enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_production_forecast_lines') THEN
    CREATE POLICY "allow_all_production_forecast_lines" ON production_forecast_lines FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
```

## 6.2 — Page `ProductionForecastsPage.tsx`

**Logique Sage 100** : "Génération basée sur l'historique des factures. Paramètre d'exclusion automatique (exclure factures d'un salon, lignes avec info libre particulière). Taux de fiabilité par article pour réévaluer à la hausse/baisse. Gestion des décimales."

**Structure** :
- `Breadcrumb` : Production / Prévisions
- `PageHeader` : "Prévisions de production" + bouton "Nouvelle prévision"
- `Table` : N°, Nom, Période, Méthode, Statut, Actions
- **Modal de génération** :
  - Nom, Date début, Date fin
  - Méthode : "Historique factures" (Sage 100 : "Import des factures")
  - **Champ d'exclusion** (Sage 100 : "clause d'exclusion automatique") : champ texte + select (champ facture, valeur recherchée)
    - Exemples : exclure si `description` contient "salon", si `info_libre_1` = "événement"
  - Bouton "Générer" → query `invoices` + `invoice_lines` sur la période, agrège par produit, crée les `production_forecast_lines`
- **Détail prévision** (expand) :
  - `Table` : Produit, Période, Quantité prévue, **Taux de fiabilité** (%), **Quantité ajustée** (= prévue × fiabilité / 100), Actions
  - **Taux de fiabilité modifiable** (Sage 100 : "taux de fiabilité au niveau de chaque article") — input numeric, recalcule auto `adjusted_quantity`
  - **Quantité décimale** supportée (Sage 100 : "Gestion des décimales")

---

# SPRINT 7 : Planification & Ordonnancement

> **Fonctionnalités Sage 100 couvertes** :
> - Planification : Disponibilité Matière
> - CBN : Prise en compte de l'ordonnancement (planning Gantt)

## 7.1 — Page `ProductionPlanningPage.tsx`

**Logique Sage 100** : "Affichage de la disponibilité matière avec lien vers l'interrogation article. Planning de Gantt comme repère pour la date de besoin des composants."

**Structure** :
- `Breadcrumb` : Production / Planification
- `PageHeader` : "Planification"
- **Vue Gantt simplifiée** : tableau par semaine avec les OF en cours (date début → fin)
  - Chaque OF = une barre horizontale
  - Couleur par statut (planifié=bleu, en cours=orange, terminé=vert)
  - Pas besoin de lib complexe — un tableau HTML avec des divs positionnés en absolu par date
- **Table "Disponibilité Matière"** (Sage 100 : "Disponibilité Matière") :
  - Pour chaque OF en cours, lister les composants de la BOM
  - Colonnes : Produit, Besoin, Stock disponible, Écart, Date besoin, Statut (OK/Pénurie)
  - **Lien sur le produit** → ouvre `ArticleInterrogationModal` (Sage 100 : "lien permettant d'appeler la fenêtre d'interrogation article")
- **Option ordonnancement** (Sage 100 : "Prise en compte de l'ordonnancement") :
  - Si activé, la date de besoin d'un composant = date de début de l'opération qui l'utilise (basé sur `routing_operations.run_time_min`)
  - Au lieu du début planifié de l'OF

---

# SPRINT 8 : Composant Article Interrogation + Deviseur

> **Fonctionnalités Sage 100 couvertes** :
> - Article : Interrogation (stock détaillé, tarifs fournisseurs, accessible depuis多个 écrans)
> - Article : Refresh Gamme/Nomenclature sans quitter la fiche
> - Deviseur : Visualisation du stock (colonne "Qté Stock" + tooltip)
> - Deviseur : Récupération du N° d'affaire
> - CBN : Superviseur Achats / Ventes (Collaborateur)

## 8.1 — Composant `ArticleInterrogationModal.tsx`

**Fichier** : `@/components/ArticleInterrogationModal.tsx`

**Logique Sage 100** : "Fenêtre d'interrogation article : stock détaillé par dépôts, documents, tarifs fournisseurs. Disponible depuis : Deviseur, CBN, Nomenclatures, Planification."

**Props** :
```typescript
interface ArticleInterrogationModalProps {
  productId: string
  open: boolean
  onClose: () => void
}
```

**Structure** :
- Modal plein écran (ou large, 800px)
- **Onglet 1 : Stock** :
  - `Table` : Dépôt, Quantité, Quantité réservée, Quantité disponible, Coût unitaire, Valeur
  - Query : `stock_quantities` + `warehouses` pour le `product_id`
- **Onglet 2 : Tarifs fournisseurs** :
  - `Table` : Fournisseur, Prix unitaire, Devise, Quantité min, Remise %
  - Query : `price_list_lines` + `price_lists` (type='purchase') + `suppliers`
- **Onglet 3 : Documents liés** :
  - `Table` : Type doc, N°, Date, Quantité, Statut
  - Query : `invoices` + `purchase_orders` + `manufacturing_orders` + `sales_orders` qui contiennent ce produit
- **Onglet 4 : Nomenclatures** :
  - BOMs où ce produit est le produit fini
  - BOMs où ce produit est un composant (bom_lines)
  - **Bouton "Refresh"** (Sage 100 : "Refresh Gamme/Nomenclature sans quitter la fiche") — recharge les données sans fermer le modal

## 8.2 — Modification `QuotesPage.tsx` (Deviseur)

**Logique Sage 100** : "Dans les lignes de Devis et les lignes de nomenclatures, ajouter la colonne 'Qté Stock'. Le survol de la valeur du stock affiche la fenêtre d'interrogation de l'article."

**Modifications** :
1. Ajouter une colonne "Qté Stock" dans la table des lignes de devis
2. Pour chaque ligne, query `stock_quantities` pour afficher le stock total
3. **Tooltip au survol** : ouvrir `ArticleInterrogationModal` au clic sur la valeur stock
4. **Récupération N° d'affaire** (Sage 100 : "Récupération du N° d'affaire lorsque le devis est validé en commande") :
   - Quand un devis est converti en commande (`sales_order`), copier un champ `project_number` dans le commentaire de l'OF si créé à partir de cette commande

## 8.3 — Modification `BOMPage.tsx`

Ajouter un lien sur chaque produit (produit fini et composants) qui ouvre `ArticleInterrogationModal`.

## 8.4 — Superviseur Achats/Ventes (Collaborateur)

**Logique Sage 100** : "Afficher en colonne le représentant dans les documents de vente et l'acheteur dans les documents d'achats."

**Modifications** :
- `SalesOrdersPage.tsx` : ajouter colonne "Représentant" (user qui a créé la commande)
- `PurchaseOrdersPage.tsx` : ajouter colonne "Acheteur" (user qui a créé la commande)

---

# SPRINT 9 : Fonctionnalités Complémentaires

> **Fonctionnalités Sage 100 couvertes** :
> - Cas d'emploi : Affichage des équivalences
> - Workflow : Affichage en vue grille
> - Périodique : Information de dernière exécution
> - Historisation des Log In/Out (déjà présent via `audit_log`)
> - OF – Dossier de fabrication : Gestion des droits d'accès aux éditions

## 9.1 — Cas d'emploi : Équivalences

Ajouter une table `product_equivalences` :
```sql
create table if not exists product_equivalences (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  product_id uuid not null references products(id) on delete cascade,
  equivalent_product_id uuid not null references products(id) on delete cascade,
  conversion_ratio numeric(15,4) default 1,
  created_at timestamptz default now()
);
```
Afficher dans `ProductsPage.tsx` un onglet "Équivalences" qui liste les produits équivalents.

## 9.2 — Workflow : Vue grille

Si des workflows existent (tâches automatisées), ajouter un toggle liste/grille. Si aucun workflow n'existe encore, créer une table `workflows` basique et une page `WorkflowsPage.tsx`.

## 9.3 — Périodique : Dernière exécution

Pour les tâches périodiques (calcul MRP, génération prévisions), afficher la date de dernière exécution dans un tableau de bord.

## 9.4 — Dossier de fabrication : Droits d'accès

Ajouter une table `of_document_access` :
```sql
create table if not exists of_document_access (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  user_id uuid not null references users(id) on delete cascade,
  document_type text not null,
  can_view boolean default true,
  can_print boolean default false,
  can_export boolean default false,
  created_at timestamptz default now()
);
```
Vérifier les droits avant d'afficher les boutons "Imprimer" et "Export" dans `ManufacturingOrderDetailPage`.

---

# SPRINT 10 : Dashboard Production

## 10.1 — Page `ProductionDashboardPage.tsx`

**Route** : `/production`

**Structure** :
- `Breadcrumb` : Production
- `PageHeader` : "Tableau de bord production"
- **StatCard x 6** :
  - OF en cours (count, status='in_progress')
  - OF planifiés (count, status='planned')
  - OF terminés ce mois (count, status='completed', end_date ce mois)
  - Commandes S/T en cours (count)
  - Propositions CBN en attente (count)
  - Retards de production (count, end_date < today et status != 'completed')
- **Graphique** : OF par statut (camembert ou barres)
- **Table "OF en cours"** : top 10 des OF en cours avec progression
- **Table "Alertes"** : OF en retard, composants en pénurie, S/T à relancer

---

# Récapitulatif complet des modifications par fichier

## Fichiers à modifier

| Fichier | Modifications |
|---|---|
| `app/supabase-schema.sql` | Ajouter 18 nouvelles tables + ALTER sur 6 tables existantes |
| `app/src/types/index.ts` | Ajouter ~20 nouvelles interfaces + étendre BOM, ManufacturingOrder, Product |
| `app/src/lib/queries.ts` | Ajouter ~60 nouvelles fonctions CRUD |
| `app/src/lib/supabase.ts` | Ajouter 18 noms de tables dans `TENANT_TABLES` |
| `app/src/components/Layout.tsx` | Ajouter groupe "Production" dans `navGroups` |
| `app/src/components/ui.tsx` | Ajouter labels de routes dans `routeLabels` |
| `app/src/App.tsx` | Ajouter ~14 nouvelles routes |
| `app/src/pages/BOMPage.tsx` | Ajouter `bom_type` (standard/amalgam), lien interrogation article |
| `app/src/pages/ManufacturingOrdersPage.tsx` | Ajouter colonne origine, lien détail OF, champ texte complémentaire, support amalgam |
| `app/src/pages/QuotesPage.tsx` | Ajouter colonne "Qté Stock" + tooltip interrogation article |
| `app/src/pages/ProductsPage.tsx` | Ajouter onglet équivalences, champs is_amalgam, units_per_carton, etc. |
| `app/src/pages/SalesOrdersPage.tsx` | Ajouter colonne "Représentant" |
| `app/src/pages/PurchaseOrdersPage.tsx` | Ajouter colonne "Acheteur" |

## Nouveaux fichiers à créer

| Fichier | Description |
|---|---|
| `app/src/lib/mrp.ts` | Algorithme CBN (Calcul des Besoins Nets) |
| `app/src/lib/excel-utils.ts` | Utilitaires Import/Export Excel |
| `app/src/components/ArticleInterrogationModal.tsx` | Modal réutilisable d'interrogation article |
| `app/src/pages/RoutingsPage.tsx` | Gammes opératoires |
| `app/src/pages/MachinesPage.tsx` | Machines & centres de charge |
| `app/src/pages/ToolingsPage.tsx` | Outillages |
| `app/src/pages/SubcontractingOrdersPage.tsx` | Commandes sous-traitance |
| `app/src/pages/SubcontractingShipmentsPage.tsx` | Expéditions sous-traitance |
| `app/src/pages/SubcontractingReceiptsPage.tsx` | Réceptions sous-traitance |
| `app/src/pages/SubcontractingSupervisorPage.tsx` | Superviseur sous-traitance |
| `app/src/pages/ManufacturingOrderDetailPage.tsx` | Détail OF avec onglets |
| `app/src/pages/MRPCalculationsPage.tsx` | CBN — calculs |
| `app/src/pages/MRPProposalsPage.tsx` | CBN — propositions |
| `app/src/pages/MRPPendingDocumentsPage.tsx` | CBN — documents en attente |
| `app/src/pages/ProductionForecastsPage.tsx` | Prévisions de production |
| `app/src/pages/ProductionPlanningPage.tsx` | Planification & ordonnancement |
| `app/src/pages/ProductionDashboardPage.tsx` | Dashboard production |

## Dépendances npm à installer

```bash
npm install xlsx    # Import/Export Excel
```

## Routes complètes à ajouter dans `App.tsx`

```typescript
{/* Production */}
<Route path="/production" element={<ProductionDashboardPage />} />
<Route path="/production/routings" element={<RoutingsPage />} />
<Route path="/production/machines" element={<MachinesPage />} />
<Route path="/production/toolings" element={<ToolingsPage />} />
<Route path="/production/subcontracting/orders" element={<SubcontractingOrdersPage />} />
<Route path="/production/subcontracting/shipments" element={<SubcontractingShipmentsPage />} />
<Route path="/production/subcontracting/receipts" element={<SubcontractingReceiptsPage />} />
<Route path="/production/subcontracting/supervisor" element={<SubcontractingSupervisorPage />} />
<Route path="/production/manufacturing" element={<ManufacturingOrdersPage />} />
<Route path="/production/of/:id" element={<ManufacturingOrderDetailPage />} />
<Route path="/production/mrp" element={<MRPCalculationsPage />} />
<Route path="/production/mrp/proposals/:calcId" element={<MRPProposalsPage />} />
<Route path="/production/mrp/pending" element={<MRPPendingDocumentsPage />} />
<Route path="/production/forecasts" element={<ProductionForecastsPage />} />
<Route path="/production/planning" element={<ProductionPlanningPage />} />
```

## Ordre d'implémentation recommandé

1. **Sprint 1** : Gamme + Machine + Outillage (fondation pour les OF)
2. **Sprint 4** : OF Enhancements (étend l'existant)
3. **Sprint 3** : Amalgam (étend BOM + OF)
4. **Sprint 2** : Sous-traitance (dépend des gammes pour les opérations S/T)
5. **Sprint 5** : CBN/MRP (dépend de tout ce qui précède)
6. **Sprint 6** : Prévisions (alimente le CBN)
7. **Sprint 7** : Planification (utilise les données du CBN)
8. **Sprint 8** : Article Interrogation + Deviseur (transversal)
9. **Sprint 9** : Complémentaires
10. **Sprint 10** : Dashboard (synthèse de tout)
