-- ============================================================
-- Sprint D: Catalogue articles étendu
-- File: 50_sprint_d_catalog_extended.sql
-- ============================================================

-- ============ New tables ============

-- Product grids (gammes: tailles/couleurs)
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
    DROP POLICY IF EXISTS "allow_all_product_grids" ON product_grids;
    CREATE POLICY "allow_all_product_grids" ON product_grids FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- Product grid combinations (matrix stock par variante)
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
    DROP POLICY IF EXISTS "allow_all_pgc" ON product_grid_combinations;
    CREATE POLICY "allow_all_pgc" ON product_grid_combinations FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- Product packagings (conditionnements)
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
    DROP POLICY IF EXISTS "allow_all_product_packagings" ON product_packagings;
    CREATE POLICY "allow_all_product_packagings" ON product_packagings FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- Product links (articles liés/complémentaires)
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
    DROP POLICY IF EXISTS "allow_all_product_links" ON product_links;
    CREATE POLICY "allow_all_product_links" ON product_links FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- Promotions (soldes/promotions)
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
    DROP POLICY IF EXISTS "allow_all_promotions" ON promotions;
    CREATE POLICY "allow_all_promotions" ON promotions FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
