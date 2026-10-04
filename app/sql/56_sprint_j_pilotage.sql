-- Sprint J: Pilotage & Reporting
-- saved_filters table for list page filters

CREATE TABLE IF NOT EXISTS saved_filters (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  user_email text NOT NULL,
  page_name text NOT NULL,
  filter_name text NOT NULL,
  filter_criteria jsonb NOT NULL DEFAULT '{}',
  is_default boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sf_user_page ON saved_filters(user_email, page_name);
CREATE INDEX IF NOT EXISTS idx_sf_tenant ON saved_filters(tenant_id);

ALTER TABLE saved_filters ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_saved_filters') THEN
    DROP POLICY IF EXISTS "allow_all_saved_filters" ON saved_filters;
    CREATE POLICY "allow_all_saved_filters" ON saved_filters FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
