# PARTIE 3 — Sprints D & E : Catalogue articles étendu + Stock avancé (5-6j)

> **Sprint D** (3j) : Gammes, conditionnements, articles liés, promotions/soldes
> **Sprint E** (2-3j) : Stock prévisionnel, alertes seuil, affectation utilisateurs par dépôt
> **i18n** : `useTranslation` (fr, en, ar)
> **SQL** : `app/sql/50_sprint_d_catalog_extended.sql` + `app/sql/51_sprint_e_stock_advanced.sql`

---

# SPRINT D : Catalogue articles étendu (3j)

## D.1 SQL — Nouvelles tables

### `product_grids` (gammes : tailles/couleurs)
```sql
CREATE TABLE IF NOT EXISTS product_grids (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  name text NOT NULL,
  axis text NOT NULL,              -- 'size'|'color'|'material'|'style'
  values jsonb NOT NULL DEFAULT '[]'::jsonb,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pg_product ON product_grids(product_id);
ALTER TABLE product_grids ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_product_grids') THEN
    CREATE POLICY "allow_all_product_grids" ON product_grids FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `product_grid_combinations` (matrix stock par variante)
```sql
CREATE TABLE IF NOT EXISTS product_grid_combinations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  combination jsonb NOT NULL,       -- {"Taille":"M","Couleur":"Bleu"}
  sku text,
  barcode text,
  price_override numeric(15,2),
  stock_quantity numeric(15,2) DEFAULT 0,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pgc_product ON product_grid_combinations(product_id);
ALTER TABLE product_grid_combinations ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_pgc') THEN
    CREATE POLICY "allow_all_pgc" ON product_grid_combinations FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `product_packagings` (conditionnements)
```sql
CREATE TABLE IF NOT EXISTS product_packagings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  name text NOT NULL,              -- "Carton de 12", "Palette de 144"
  quantity numeric(15,2) NOT NULL,
  unit text,                       -- 'box'|'pallet'|'pack'|'case'
  barcode text,
  weight numeric(10,3),
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pp_product ON product_packagings(product_id);
ALTER TABLE product_packagings ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_product_packagings') THEN
    CREATE POLICY "allow_all_product_packagings" ON product_packagings FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `product_links` (articles liés/complémentaires)
```sql
CREATE TABLE IF NOT EXISTS product_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  linked_product_id uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  link_type text NOT NULL,         -- 'accessory'|'complement'|'substitute'|'bundle'|'cross_sell'
  quantity numeric(15,2) DEFAULT 1,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pl_product ON product_links(product_id);
ALTER TABLE product_links ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_product_links') THEN
    CREATE POLICY "allow_all_product_links" ON product_links FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `promotions` (soldes/promotions)
```sql
CREATE TABLE IF NOT EXISTS promotions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text,
  promo_type text NOT NULL,        -- 'percentage'|'fixed_amount'|'buy_x_get_y'|'free_shipping'
  value numeric(15,2),
  product_id uuid REFERENCES products(id) ON DELETE CASCADE,
  category text,
  customer_id uuid REFERENCES customers(id) ON DELETE CASCADE,
  start_date date NOT NULL,
  end_date date NOT NULL,
  min_quantity numeric(15,2) DEFAULT 1,
  free_product_id uuid REFERENCES products(id) ON DELETE SET NULL,
  free_product_qty numeric(15,2) DEFAULT 1,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_promo_dates ON promotions(start_date, end_date);
ALTER TABLE promotions ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_promotions') THEN
    CREATE POLICY "allow_all_promotions" ON promotions FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

## D.2 Types TypeScript

```typescript
export interface ProductGrid {
  id: string
  product_id: string
  name: string
  axis: 'size'|'color'|'material'|'style'
  values: string[]
  active: boolean
}

export interface ProductGridCombination {
  id: string
  product_id: string
  combination: Record<string, string>
  sku: string | null
  barcode: string | null
  price_override: number | null
  stock_quantity: number
  active: boolean
}

export interface ProductPackaging {
  id: string
  product_id: string
  name: string
  quantity: number
  unit: 'box'|'pallet'|'pack'|'case'
  barcode: string | null
  weight: number | null
  active: boolean
}

export interface ProductLink {
  id: string
  product_id: string
  linked_product_id: string
  link_type: 'accessory'|'complement'|'substitute'|'bundle'|'cross_sell'
  quantity: number
}

export interface Promotion {
  id: string
  name: string
  description: string | null
  promo_type: 'percentage'|'fixed_amount'|'buy_x_get_y'|'free_shipping'
  value: number | null
  product_id: string | null
  category: string | null
  customer_id: string | null
  start_date: string
  end_date: string
  min_quantity: number
  free_product_id: string | null
  free_product_qty: number
  active: boolean
}
```

## D.3 Queries

| Fonction | Description |
|---|---|
| `getProductGrids(productId)` | Gammes d'un produit |
| `createProductGrid(grid)` | Crée une gamme |
| `getProductGridCombinations(productId)` | Combinaisons (matrix stock) |
| `createProductGridCombination(combo)` | Crée une combinaison |
| `generateAllCombinations(productId)` | Génère toutes les combinaisons automatiquement |
| `getProductPackagings(productId)` | Conditionnements |
| `createProductPackaging(packaging)` | Crée un conditionnement |
| `getProductLinks(productId)` | Articles liés |
| `createProductLink(link)` | Crée un lien |
| `getPromotions(activeOnly?)` | Liste des promotions |
| `createPromotion(promo)` | Crée une promotion |
| `updatePromotion(id, updates)` | Modifie |
| `deletePromotion(id)` | Supprime |
| `applyPromotion(productId, customerId, quantity)` | Calcule la promotion applicable |

## D.4 Nouvelles pages

### `PromotionsPage.tsx`
**Fichier** : `app/src/pages/sales/PromotionsPage.tsx`
**Route** : `/sales/promotions`
- Liste + filtres (actives, expirées, par type)
- Formulaire : nom, type (percentage/fixed_amount/buy_x_get_y/free_shipping), valeur, produit/catégorie, client, dates, quantité min
- Badge Active/Expirée/À venir
- `useTranslation('sales')`

### `ProductGridsPage.tsx`
**Fichier** : `app/src/pages/stock/ProductGridsPage.tsx`
**Route** : `/stock/product-grids`
- Sélection produit → affichage gammes
- Création gamme : nom, axe, valeurs (tags input)
- **Vue matricielle** : tableau croisé Taille × Couleur avec stock
- Bouton "Générer les combinaisons"
- `useTranslation('stock')`

## D.5 Modifications de pages

### `ProductsPage.tsx`
Nouveaux onglets dans la fiche produit :
- **Gammes** : gestion axes + combinaisons
- **Conditionnements** : CRUD packagings
- **Articles liés** : CRUD liens (accessoire, complément, substitut, bundle, cross-sell)
- **Tarifs fournisseurs** : affichage depuis `supplier_price_list_lines`
- **Stock prévisionnel** : affichage `getStockForecast(productId)`

## D.6 i18n

**`sales.json`** (fr/en/ar) :
- `promotions.*` : title, new, name, description, type, percentage, fixedAmount, buyXGetY, freeShipping, value, product, category, customer, startDate, endDate, minQuantity, freeProduct, freeQuantity, active, expired, upcoming

**`stock.json`** (fr/en/ar) :
- `grids.*` : title, new, product, axis, size, color, material, style, values, combinations, generateCombinations, matrix, sku, barcode, priceOverride, stock
- `packagings.*` : title, new, name, quantity, unit, box, pallet, pack, case, weight
- `productLinks.*` : title, new, linkedProduct, type, accessory, complement, substitute, bundle, crossSell

## D.7 Routes

```tsx
<Route path="/sales/promotions" element={<PromotionsPage />} />
<Route path="/stock/product-grids" element={<ProductGridsPage />} />
```

---

# SPRINT E : Stock avancé (2-3j)

## E.1 SQL — Nouvelles tables et extensions

### Étendre `stock_quantities`
```sql
ALTER TABLE stock_quantities ADD COLUMN IF NOT EXISTS reserved_quantity numeric(15,2) DEFAULT 0;
ALTER TABLE stock_quantities ADD COLUMN IF NOT EXISTS incoming_quantity numeric(15,2) DEFAULT 0;
```

### `warehouse_users` (affectation utilisateurs par dépôt)
```sql
CREATE TABLE IF NOT EXISTS warehouse_users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  warehouse_id uuid NOT NULL REFERENCES warehouses(id) ON DELETE CASCADE,
  user_email text NOT NULL,
  role text DEFAULT 'operator',    -- 'manager'|'operator'|'viewer'
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_wu_warehouse ON warehouse_users(warehouse_id);
CREATE INDEX IF NOT EXISTS idx_wu_user ON warehouse_users(user_email);
ALTER TABLE warehouse_users ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_warehouse_users') THEN
    CREATE POLICY "allow_all_warehouse_users" ON warehouse_users FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

### `stock_alerts` (alertes de seuil)
```sql
CREATE TABLE IF NOT EXISTS stock_alerts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  warehouse_id uuid REFERENCES warehouses(id) ON DELETE SET NULL,
  alert_type text NOT NULL,        -- 'low_stock'|'out_of_stock'|'overstock'|'expiry'
  threshold numeric(15,2),
  current_value numeric(15,2),
  status text DEFAULT 'active',    -- 'active'|'acknowledged'|'resolved'
  triggered_at timestamptz DEFAULT now(),
  resolved_at timestamptz,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sa_product ON stock_alerts(product_id);
CREATE INDEX IF NOT EXISTS idx_sa_status ON stock_alerts(status);
ALTER TABLE stock_alerts ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_stock_alerts') THEN
    CREATE POLICY "allow_all_stock_alerts" ON stock_alerts FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
```

## E.2 Types TypeScript

```typescript
export interface WarehouseUser {
  id: string
  warehouse_id: string
  user_email: string
  role: 'manager'|'operator'|'viewer'
  active: boolean
  created_at: string
}

export interface StockAlert {
  id: string
  product_id: string
  warehouse_id: string | null
  alert_type: 'low_stock'|'out_of_stock'|'overstock'|'expiry'
  threshold: number | null
  current_value: number | null
  status: 'active'|'acknowledged'|'resolved'
  triggered_at: string
  resolved_at: string | null
}
```

## E.3 Queries

| Fonction | Description |
|---|---|
| `getWarehouseUsers(warehouseId)` | Liste utilisateurs affectés à un dépôt |
| `assignWarehouseUser(wu)` | Affecte un utilisateur |
| `removeWarehouseUser(id)` | Retire l'affectation |
| `getStockAlerts(status?)` | Liste des alertes |
| `acknowledgeStockAlert(id)` | Marquer comme acquittée |
| `resolveStockAlert(id)` | Marquer comme résolue |
| `checkStockThresholds()` | Parcourt le stock et génère les alertes (fonction batch) |
| `getStockForecastDetailed(productId)` | Retourne `{current, reserved, incoming, outgoing, forecast}` par dépôt |

## E.4 Nouvelle page — `StockAlertsPage.tsx`

**Fichier** : `app/src/pages/stock/StockAlertsPage.tsx`
**Route** : `/stock/alerts`

- Liste des alertes avec filtres (type, statut, dépôt, produit)
- Badge couleur par type (rouge = rupture, orange = stock bas, bleu = surstock)
- Boutons : "Acquitter", "Résoudre"
- Bouton "Vérifier les seuils" → déclenche `checkStockThresholds()`
- `useTranslation('stock')`

## E.5 Modifications de pages

### `WarehousesPage.tsx` (si existe) ou `SettingsPage`
- Section **"Utilisateurs affectés"** par dépôt : CRUD `warehouse_users`

### `StockQuantitiesPage.tsx`
- Colonnes supplémentaires : **Réservé**, **Entrant prévu**, **Stock prévisionnel**
- Badge alerte si stock ≤ seuil
- Lien vers `StockAlertsPage`

## E.6 i18n

**`stock.json`** (fr/en/ar) :
- `alerts.*` : title, type, lowStock, outOfStock, overstock, expiry, threshold, currentValue, status, active, acknowledged, resolved, acknowledge, resolve, checkThresholds
- `forecast.*` : title, current, reserved, incoming, outgoing, forecast, byWarehouse
- `warehouseUsers.*` : title, assign, userEmail, role, manager, operator, viewer, active

## E.7 Routes

```tsx
<Route path="/stock/alerts" element={<StockAlertsPage />} />
```
