-- ============================================================
-- Phase 2 — Gestion Commerciale 100%
-- Tables: variants, serials, batches, locations, quality, picking,
--         representatives, prospects, substitutes, delivery_schedules,
--         recurring_invoice_templates, document_templates, product_barcode
-- ============================================================

-- 1. Product attributes (tailles/couleurs)
create table if not exists product_attributes (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  name text not null,
  type text not null default 'select' check (type in ('select','text','number','color')),
  options jsonb default '[]'::jsonb,
  created_at timestamptz default now()
);
create index if not exists idx_product_attributes_name on product_attributes(name);
alter table product_attributes enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_product_attributes') THEN
    CREATE POLICY "allow_all_product_attributes" ON product_attributes FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 2. Product variants
create table if not exists product_variants (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  product_id uuid not null references products(id) on delete cascade,
  sku text not null,
  attributes jsonb default '{}'::jsonb,
  price_override numeric(15,2),
  barcode text,
  active boolean default true,
  created_at timestamptz default now()
);
create index if not exists idx_product_variants_product on product_variants(product_id);
create index if not exists idx_product_variants_sku on product_variants(sku);
alter table product_variants enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_product_variants') THEN
    CREATE POLICY "allow_all_product_variants" ON product_variants FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 3. Product serial numbers
create table if not exists product_serial_numbers (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  product_id uuid not null references products(id) on delete cascade,
  serial_number text not null,
  status text default 'in_stock' check (status in ('in_stock','sold','returned','warranty')),
  warranty_expiry date,
  notes text,
  created_at timestamptz default now()
);
create index if not exists idx_product_serials_product on product_serial_numbers(product_id);
create index if not exists idx_product_serials_number on product_serial_numbers(serial_number);
alter table product_serial_numbers enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_product_serial_numbers') THEN
    CREATE POLICY "allow_all_product_serial_numbers" ON product_serial_numbers FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 4. Product batches / lots
create table if not exists product_batches (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  product_id uuid not null references products(id) on delete cascade,
  batch_number text not null,
  quantity numeric(15,2) not null default 0,
  expiry_date date,
  status text default 'active' check (status in ('active','expired','quarantine')),
  created_at timestamptz default now()
);
create index if not exists idx_product_batches_product on product_batches(product_id);
create index if not exists idx_product_batches_number on product_batches(batch_number);
alter table product_batches enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_product_batches') THEN
    CREATE POLICY "allow_all_product_batches" ON product_batches FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 5. Warehouse locations (emplacements)
create table if not exists warehouse_locations (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  warehouse_id uuid not null references warehouses(id) on delete cascade,
  zone text,
  aisle text,
  shelf text,
  code text not null,
  description text,
  created_at timestamptz default now()
);
create index if not exists idx_warehouse_locations_wh on warehouse_locations(warehouse_id);
create index if not exists idx_warehouse_locations_code on warehouse_locations(code);
alter table warehouse_locations enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_warehouse_locations') THEN
    CREATE POLICY "allow_all_warehouse_locations" ON warehouse_locations FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- Add location_id to stock_quantities
alter table stock_quantities add column if not exists location_id uuid references warehouse_locations(id) on delete set null;

-- 6. Quality checks
create table if not exists quality_checks (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  product_id uuid not null references products(id) on delete cascade,
  reference_type text default 'goods_receipt' check (reference_type in ('goods_receipt','delivery_note','production','manual')),
  reference_id uuid,
  status text default 'pending' check (status in ('pending','passed','failed','partial')),
  checked_by text,
  checked_at timestamptz,
  notes text,
  created_at timestamptz default now()
);
create index if not exists idx_quality_checks_product on quality_checks(product_id);
create index if not exists idx_quality_checks_status on quality_checks(status);
alter table quality_checks enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_quality_checks') THEN
    CREATE POLICY "allow_all_quality_checks" ON quality_checks FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 7. Pick lists
create table if not exists pick_lists (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  number text not null,
  reference_type text default 'sales_order' check (reference_type in ('sales_order','delivery_note','production')),
  reference_id uuid,
  warehouse_id uuid references warehouses(id) on delete set null,
  status text default 'draft' check (status in ('draft','in_progress','completed','cancelled')),
  picked_by text,
  picked_at timestamptz,
  created_at timestamptz default now()
);
create index if not exists idx_pick_lists_number on pick_lists(number);
create index if not exists idx_pick_lists_status on pick_lists(status);
alter table pick_lists enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_pick_lists') THEN
    CREATE POLICY "allow_all_pick_lists" ON pick_lists FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 8. Pick list lines
create table if not exists pick_list_lines (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  pick_list_id uuid not null references pick_lists(id) on delete cascade,
  product_id uuid not null references products(id) on delete cascade,
  location_id uuid references warehouse_locations(id) on delete set null,
  quantity_to_pick numeric(15,2) not null default 0,
  quantity_picked numeric(15,2) default 0,
  barcode text,
  created_at timestamptz default now()
);
create index if not exists idx_pick_list_lines_pick on pick_list_lines(pick_list_id);
alter table pick_list_lines enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_pick_list_lines') THEN
    CREATE POLICY "allow_all_pick_list_lines" ON pick_list_lines FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 9. Sales representatives
create table if not exists sales_representatives (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  name text not null,
  email text,
  phone text,
  commission_rate numeric(5,2) default 0,
  territory text,
  active boolean default true,
  created_at timestamptz default now()
);
create index if not exists idx_sales_reps_name on sales_representatives(name);
alter table sales_representatives enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_sales_representatives') THEN
    CREATE POLICY "allow_all_sales_representatives" ON sales_representatives FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 10. Prospects (séparés des clients)
create table if not exists prospects (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  name text not null,
  email text,
  phone text,
  address text,
  city text,
  postal_code text,
  country text,
  contact_name text,
  source text,
  status text default 'new' check (status in ('new','contacted','qualified','converted','lost')),
  assigned_rep_id uuid references sales_representatives(id) on delete set null,
  notes text,
  converted_customer_id uuid references customers(id) on delete set null,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists idx_prospects_name on prospects(name);
create index if not exists idx_prospects_status on prospects(status);
alter table prospects enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_prospects') THEN
    CREATE POLICY "allow_all_prospects" ON prospects FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 11. Product substitutes
create table if not exists product_substitutes (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  product_id uuid not null references products(id) on delete cascade,
  substitute_id uuid not null references products(id) on delete cascade,
  priority int default 1,
  created_at timestamptz default now()
);
create index if not exists idx_product_substitutes_product on product_substitutes(product_id);
alter table product_substitutes enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_product_substitutes') THEN
    CREATE POLICY "allow_all_product_substitutes" ON product_substitutes FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 12. Delivery schedules (cadencier)
create table if not exists delivery_schedules (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  customer_id uuid references customers(id) on delete set null,
  product_id uuid not null references products(id) on delete cascade,
  frequency text default 'weekly' check (frequency in ('daily','weekly','monthly')),
  quantity numeric(15,2) not null default 0,
  start_date date not null default current_date,
  end_date date,
  active boolean default true,
  created_at timestamptz default now()
);
create index if not exists idx_delivery_schedules_customer on delivery_schedules(customer_id);
create index if not exists idx_delivery_schedules_product on delivery_schedules(product_id);
alter table delivery_schedules enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_delivery_schedules') THEN
    CREATE POLICY "allow_all_delivery_schedules" ON delivery_schedules FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 13. Recurring invoice templates
create table if not exists recurring_invoice_templates (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  name text not null,
  customer_id uuid references customers(id) on delete set null,
  frequency text default 'monthly' check (frequency in ('weekly','monthly','quarterly','yearly')),
  next_date date not null default current_date,
  lines jsonb default '[]'::jsonb,
  active boolean default true,
  created_at timestamptz default now()
);
create index if not exists idx_recurring_inv_templates_customer on recurring_invoice_templates(customer_id);
alter table recurring_invoice_templates enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_recurring_invoice_templates') THEN
    CREATE POLICY "allow_all_recurring_invoice_templates" ON recurring_invoice_templates FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 14. Document templates (personnalisation)
create table if not exists document_templates (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid,
  name text not null,
  document_type text not null check (document_type in ('invoice','quote','delivery_note','credit_note','purchase_order','statement')),
  logo_url text,
  primary_color text default '#2563eb',
  secondary_color text default '#64748b',
  template_config jsonb default '{}'::jsonb,
  is_default boolean default false,
  created_at timestamptz default now()
);
create index if not exists idx_document_templates_type on document_templates(document_type);
alter table document_templates enable row level security;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_document_templates') THEN
    CREATE POLICY "allow_all_document_templates" ON document_templates FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 15. Add barcode to products
alter table products add column if not exists barcode text;

-- 16. Add validation_status to invoices/quotes/orders/delivery_notes
alter table invoices add column if not exists validation_status text default 'draft' check (validation_status in ('draft','validated','transformed'));
alter table quotes add column if not exists validation_status text default 'draft' check (validation_status in ('draft','validated','transformed'));
alter table sales_orders add column if not exists validation_status text default 'draft' check (validation_status in ('draft','validated','transformed'));
alter table delivery_notes add column if not exists validation_status text default 'draft' check (validation_status in ('draft','validated','transformed'));

-- 17. Add sector_code and geographic_zone to customers/suppliers
alter table customers add column if not exists sector_code text;
alter table customers add column if not exists geographic_zone text;
alter table suppliers add column if not exists sector_code text;
alter table suppliers add column if not exists geographic_zone text;

-- 18. Add delivered_quantity to delivery_note_lines and sales_order_lines
alter table delivery_note_lines add column if not exists ordered_quantity numeric(15,2) default 0;
alter table sales_order_lines add column if not exists delivered_quantity numeric(15,2) default 0;
