# PARTIE 2 — Sprints B & C : Gestion clients avancée + Gestion achats avancée (6-7j)

> **Sprint B** (3j) : Vue 360° client, contrôle encours, multi-contacts, paramètres email
> **Sprint C** (3-4j) : Demandes d'achat, tarifs fournisseurs multi, cadencier, criticité réappro, traitement par lot
> **i18n** : `useTranslation` (fr, en, ar)
> **SQL** : `app/sql/48_sprint_b_customer_advanced.sql` + `app/sql/49_sprint_c_purchase_advanced.sql`

---

# SPRINT B : Gestion clients avancée (3j)

## B.1 SQL — Nouvelles tables

### `customer_contacts`
```sql
CREATE TABLE IF NOT EXISTS customer_contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  customer_id uuid NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  name text NOT NULL,
  role text,              -- 'billing'|'delivery'|'technical'|'sales'|'other'
  email text,
  phone text,
  mobile text,
  is_default boolean DEFAULT false,
  active boolean DEFAULT true,
  notes text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_cc_customer ON customer_contacts(customer_id);
ALTER TABLE customer_contacts ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_customer_contacts') THEN
    CREATE POLICY "allow_all_customer_contacts" ON customer_contacts FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `supplier_contacts` (identique, FK vers suppliers)
```sql
CREATE TABLE IF NOT EXISTS supplier_contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  supplier_id uuid NOT NULL REFERENCES suppliers(id) ON DELETE CASCADE,
  name text NOT NULL,
  role text,
  email text,
  phone text,
  mobile text,
  is_default boolean DEFAULT false,
  active boolean DEFAULT true,
  notes text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sc_supplier ON supplier_contacts(supplier_id);
ALTER TABLE supplier_contacts ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_supplier_contacts') THEN
    CREATE POLICY "allow_all_supplier_contacts" ON supplier_contacts FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

## B.2 SQL — Extensions

```sql
-- customers
ALTER TABLE customers ADD COLUMN IF NOT EXISTS bank_account_id uuid;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS price_list_id uuid;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS sales_rep_id uuid;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS email_settings jsonb DEFAULT '{}'::jsonb;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS credit_limit numeric(15,2) DEFAULT 0;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS credit_used numeric(15,2) DEFAULT 0;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS credit_blocked boolean DEFAULT false;

-- suppliers
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS bank_account_id uuid;
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS price_list_id uuid;
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS email_settings jsonb DEFAULT '{}'::jsonb;
```

## B.3 Types TypeScript

```typescript
export interface CustomerContact {
  id: string
  customer_id: string
  name: string
  role: 'billing'|'delivery'|'technical'|'sales'|'other' | null
  email: string | null
  phone: string | null
  mobile: string | null
  is_default: boolean
  active: boolean
  notes: string | null
  created_at: string
}

export interface SupplierContact {
  id: string
  supplier_id: string
  name: string
  role: 'billing'|'delivery'|'technical'|'sales'|'other' | null
  email: string | null
  phone: string | null
  mobile: string | null
  is_default: boolean
  active: boolean
  notes: string | null
  created_at: string
}
```

**Extensions** :
- `Customer` : `bank_account_id?`, `price_list_id?`, `sales_rep_id?`, `email_settings?`, `credit_used?`, `credit_blocked?`
- `Supplier` : `bank_account_id?`, `price_list_id?`, `email_settings?`

## B.4 Queries

| Fonction | Description |
|---|---|
| `getCustomerContacts(customerId)` | Liste des contacts client |
| `createCustomerContact(contact)` | Crée un contact |
| `updateCustomerContact(id, updates)` | Modifie un contact |
| `deleteCustomerContact(id)` | Supprime un contact |
| `getSupplierContacts(supplierId)` | Liste des contacts fournisseur |
| `createSupplierContact(contact)` | Crée un contact fournisseur |
| `updateSupplierContact(id, updates)` | Modifie |
| `deleteSupplierContact(id)` | Supprime |
| `getCustomer360(customerId)` | Retourne {infos, contacts, encours, factures, devis, commandes, BL, paiements, relances, stats} |
| `checkCustomerCredit(customerId)` | Retourne `{limit, used, available, blocked}` |

## B.5 Nouvelle page — `Customer360Page.tsx`

**Fichier** : `app/src/pages/sales/Customer360Page.tsx`
**Route** : `/sales/customers/:id/360`

**Onglets** :
1. **Informations** : Coordonnées, TVA, conditions paiement, représentant, crédit
2. **Documents** : Tableau consolidé (devis, commandes, BL, factures, avoirs)
3. **Paiements** : Historique des règlements + solde
4. **Relances** : Historique + promesses
5. **Statistiques** : CA annuel, évolution, top produits, délai paiement moyen
6. **Contacts** : Multi-contacts (CRUD)

`useTranslation('sales')`

## B.6 Modifications de pages

### `CustomersPage.tsx`
- Bouton **"Vue 360°"** → navigation `/sales/customers/:id/360`
- Champs supplémentaires formulaire : `bank_account_id` (Select), `price_list_id` (Select), `sales_rep_id` (Select), `credit_limit` (Input), `credit_blocked` (Checkbox)
- Section **"Paramètres email"** : checkboxes (envoi auto factures, relances, format PDF, copie)
- Section **"Contacts"** : intégrer `PartnerContactsModal` (existant)
- Contrôle encours : si `credit_used > credit_limit` → badge rouge + bloquer création facture

### `SuppliersPage.tsx`
- Champs : `bank_account_id`, `price_list_id`, `email_settings`
- Section **"Contacts"** : gestion multi-contacts

## B.7 i18n

| Section | Clés |
|---|---|
| `customer360.*` | title, tabs (infos, documents, payments, reminders, stats, contacts), outstanding, creditLimit, creditUsed, creditAvailable, creditBlocked, annualRevenue, avgPaymentDelay, topProducts |
| `contacts.*` | title, add, name, role, roleBilling, roleDelivery, roleTechnical, roleSales, roleOther, email, phone, mobile, isDefault, active, notes |
| `emailSettings.*` | title, autoInvoice, autoReminder, formatPdf, copyEmail |
| `credit.*` | limit, used, available, blocked, checkCredit, creditExceeded |

## B.8 Routes

```tsx
<Route path="/sales/customers/:id/360" element={<Customer360Page />} />
```

---

# SPRINT C : Gestion achats avancée (3-4j)

## C.1 SQL — Nouvelles tables

### `purchase_requests` + `purchase_request_lines`
```sql
CREATE TABLE IF NOT EXISTS purchase_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  number text NOT NULL,
  requester text,
  department text,
  status text DEFAULT 'draft',       -- 'draft'|'submitted'|'approved'|'rejected'|'converted'
  priority text DEFAULT 'normal',    -- 'low'|'normal'|'high'|'urgent'
  expected_date date,
  notes text,
  approved_by text,
  approved_at timestamptz,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pr_number ON purchase_requests(number);
ALTER TABLE purchase_requests ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_purchase_requests') THEN
    CREATE POLICY "allow_all_purchase_requests" ON purchase_requests FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS purchase_request_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  purchase_request_id uuid NOT NULL REFERENCES purchase_requests(id) ON DELETE CASCADE,
  product_id uuid REFERENCES products(id) ON DELETE SET NULL,
  description text NOT NULL,
  quantity numeric(15,2) NOT NULL DEFAULT 1,
  unit text,
  estimated_price numeric(15,2),
  preferred_supplier_id uuid REFERENCES suppliers(id) ON DELETE SET NULL,
  notes text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_prl_request ON purchase_request_lines(purchase_request_id);
ALTER TABLE purchase_request_lines ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_purchase_request_lines') THEN
    CREATE POLICY "allow_all_purchase_request_lines" ON purchase_request_lines FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `supplier_price_lists` + `supplier_price_list_lines`
```sql
CREATE TABLE IF NOT EXISTS supplier_price_lists (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  supplier_id uuid NOT NULL REFERENCES suppliers(id) ON DELETE CASCADE,
  name text NOT NULL,
  valid_from date NOT NULL DEFAULT CURRENT_DATE,
  valid_to date,
  currency_code text DEFAULT 'EUR',
  min_quantity numeric(15,2) DEFAULT 1,
  discount_percent numeric(5,2) DEFAULT 0,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_spl_supplier ON supplier_price_lists(supplier_id);
ALTER TABLE supplier_price_lists ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_supplier_price_lists') THEN
    CREATE POLICY "allow_all_supplier_price_lists" ON supplier_price_lists FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS supplier_price_list_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  price_list_id uuid NOT NULL REFERENCES supplier_price_lists(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  supplier_ref text,
  unit_price numeric(15,2) NOT NULL,
  min_quantity numeric(15,2) DEFAULT 1,
  discount_percent numeric(5,2) DEFAULT 0,
  lead_time_days integer,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_spll_pl ON supplier_price_list_lines(price_list_id);
CREATE INDEX IF NOT EXISTS idx_spll_product ON supplier_price_list_lines(product_id);
ALTER TABLE supplier_price_list_lines ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_supplier_price_list_lines') THEN
    CREATE POLICY "allow_all_supplier_price_list_lines" ON supplier_price_list_lines FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `supplier_delivery_schedules`
```sql
CREATE TABLE IF NOT EXISTS supplier_delivery_schedules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  supplier_id uuid NOT NULL REFERENCES suppliers(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  warehouse_id uuid REFERENCES warehouses(id) ON DELETE SET NULL,
  frequency text NOT NULL,          -- 'weekly'|'biweekly'|'monthly'
  monday_qty numeric(15,2) DEFAULT 0,
  tuesday_qty numeric(15,2) DEFAULT 0,
  wednesday_qty numeric(15,2) DEFAULT 0,
  thursday_qty numeric(15,2) DEFAULT 0,
  friday_qty numeric(15,2) DEFAULT 0,
  saturday_qty numeric(15,2) DEFAULT 0,
  sunday_qty numeric(15,2) DEFAULT 0,
  start_date date NOT NULL DEFAULT CURRENT_DATE,
  end_date date,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sds_supplier ON supplier_delivery_schedules(supplier_id);
ALTER TABLE supplier_delivery_schedules ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_supplier_delivery_schedules') THEN
    CREATE POLICY "allow_all_supplier_delivery_schedules" ON supplier_delivery_schedules FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

## C.2 Types TypeScript

```typescript
export interface PurchaseRequest {
  id: string
  number: string
  requester: string | null
  department: string | null
  status: 'draft'|'submitted'|'approved'|'rejected'|'converted'
  priority: 'low'|'normal'|'high'|'urgent'
  expected_date: string | null
  notes: string | null
  approved_by: string | null
  approved_at: string | null
  created_at: string
  purchase_request_lines?: PurchaseRequestLine[]
}

export interface PurchaseRequestLine {
  id: string
  purchase_request_id: string
  product_id: string | null
  description: string
  quantity: number
  unit: string | null
  estimated_price: number | null
  preferred_supplier_id: string | null
  notes: string | null
}

export interface SupplierPriceList {
  id: string
  supplier_id: string
  name: string
  valid_from: string
  valid_to: string | null
  currency_code: string
  min_quantity: number
  discount_percent: number
  active: boolean
  supplier_price_list_lines?: SupplierPriceListLine[]
}

export interface SupplierPriceListLine {
  id: string
  price_list_id: string
  product_id: string
  supplier_ref: string | null
  unit_price: number
  min_quantity: number
  discount_percent: number
  lead_time_days: number | null
}

export interface SupplierDeliverySchedule {
  id: string
  supplier_id: string
  product_id: string
  warehouse_id: string | null
  frequency: 'weekly'|'biweekly'|'monthly'
  monday_qty: number
  tuesday_qty: number
  wednesday_qty: number
  thursday_qty: number
  friday_qty: number
  saturday_qty: number
  sunday_qty: number
  start_date: string
  end_date: string | null
  active: boolean
}
```

## C.3 Queries

| Fonction | Description |
|---|---|
| `getPurchaseRequests(status?)` | Liste des demandes d'achat |
| `createPurchaseRequest(pr)` | Crée demande + lignes |
| `updatePurchaseRequestStatus(id, status)` | Workflow approbation |
| `convertPurchaseRequestToOrder(prId, supplierId)` | Convertit en commande fournisseur |
| `getSupplierPriceLists(supplierId?)` | Liste grilles tarifaires |
| `createSupplierPriceList(list)` | Crée une grille |
| `getBestSupplierPrice(productId, qty)` | Compare prix, retourne meilleur fournisseur |
| `getSupplierDeliverySchedules(supplierId?)` | Liste cadenciers |
| `createSupplierDeliverySchedule(schedule)` | Crée un cadencier |
| `generatePurchaseFromSchedule(date)` | Génère commandes depuis cadencier |

## C.4 Nouvelles pages

### `PurchaseRequestsPage.tsx`
**Fichier** : `app/src/pages/purchases/PurchaseRequestsPage.tsx`
**Route** : `/purchases/requests`
- Liste + filtres (statut, priorité, demandeur)
- Formulaire : en-tête + lignes (produit, quantité, prix estimé, fournisseur préféré)
- Workflow : Draft → Submitted → Approved → Converted (ou Rejected)
- Bouton "Convertir en commande" sur demande approuvée
- `useTranslation('purchases')`

### `SupplierPriceListsPage.tsx`
**Fichier** : `app/src/pages/purchases/SupplierPriceListsPage.tsx`
**Route** : `/purchases/supplier-prices`
- Liste grilles par fournisseur
- Formulaire : fournisseur, nom, validité, devise, remise
- Détail : lignes (produit, réf fournisseur, prix, qté min, remise, délai)
- **Comparateur** : sélectionner produit → tableau comparatif tous fournisseurs
- Import CSV
- `useTranslation('purchases')`

### `SupplierDeliverySchedulePage.tsx`
**Fichier** : `app/src/pages/purchases/SupplierDeliverySchedulePage.tsx`
**Route** : `/purchases/delivery-schedule`
- Liste cadenciers par fournisseur/produit
- Formulaire : fournisseur, produit, dépôt, fréquence, quantités par jour
- Vue calendrier : quantités à commander par jour
- Bouton "Générer les commandes" pour une date
- `useTranslation('purchases')`

## C.5 Modifications de pages

### `ReorderPage.tsx`
- Colonne **"Criticité"** : badge (low/normal/high/critical)
- Filtre par criticité
- **Traitement par lot** : checkbox multi-produits → "Créer commandes pour la sélection"
- **Substitution auto** : si rupture → proposer substitut (table `product_substitutes`)
- **Meilleur tarif** : afficher meilleur prix fournisseur (`getBestSupplierPrice`)

### `ProductsPage.tsx`
- Champs formulaire : `barcode`, `weight`, `photo_url`, `supplier_ref`, `criticality_level` (Select), `cost_price` (Input)
- Colonnes : code-barres, criticité (badge), prix de revient

## C.6 i18n

**Namespace `purchases`** (nouveau, fr/en/ar) :
| Section | Clés |
|---|---|
| `purchaseRequests.*` | title, new, number, requester, department, status, priority, expectedDate, approve, reject, convert, converted, lines, product, quantity, unit, estimatedPrice, preferredSupplier |
| `supplierPrices.*` | title, new, supplier, validFrom, validTo, currency, minQuantity, discount, compare, bestPrice, import, leadTime, supplierRef |
| `deliverySchedule.*` | title, new, supplier, product, warehouse, frequency, weekly, biweekly, monthly, monday-sunday, generateOrders |

**Ajouts `stock.json`** (fr/en/ar) :
- `reorder.criticality`, `reorder.criticalityLow/Normal/High/Critical`
- `reorder.batchCreate`, `reorder.substitutionAvailable`, `reorder.bestPrice`

## C.7 Routes

```tsx
<Route path="/purchases/requests" element={<PurchaseRequestsPage />} />
<Route path="/purchases/supplier-prices" element={<SupplierPriceListsPage />} />
<Route path="/purchases/delivery-schedule" element={<SupplierDeliverySchedulePage />} />
```
