-- ============================================================
-- Sprint F: CRM Force de Vente
-- File: 52_sprint_f_crm_sales.sql
-- ============================================================

-- CRM Opportunities (pipeline)
CREATE TABLE IF NOT EXISTS crm_opportunities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  number text NOT NULL,
  customer_id uuid REFERENCES customers(id) ON DELETE SET NULL,
  prospect_id uuid REFERENCES prospects(id) ON DELETE SET NULL,
  title text NOT NULL,
  description text,
  stage text NOT NULL DEFAULT 'new',
  probability integer DEFAULT 0,
  expected_amount numeric(15,2) DEFAULT 0,
  expected_close_date date,
  actual_amount numeric(15,2),
  actual_close_date date,
  sales_rep_id uuid REFERENCES sales_representatives(id) ON DELETE SET NULL,
  source text,
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

-- CRM Activities
CREATE TABLE IF NOT EXISTS crm_activities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  opportunity_id uuid REFERENCES crm_opportunities(id) ON DELETE CASCADE,
  customer_id uuid REFERENCES customers(id) ON DELETE SET NULL,
  activity_type text NOT NULL,
  subject text NOT NULL,
  description text,
  scheduled_date timestamptz,
  completed_date timestamptz,
  duration_minutes integer,
  status text DEFAULT 'planned',
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

-- CRM Campaigns
CREATE TABLE IF NOT EXISTS crm_campaigns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text,
  campaign_type text NOT NULL,
  status text DEFAULT 'draft',
  start_date date,
  end_date date,
  budget numeric(15,2) DEFAULT 0,
  actual_cost numeric(15,2) DEFAULT 0,
  target_audience text,
  segment_criteria jsonb,
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

-- CRM Campaign Recipients
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

-- CRM Territories
CREATE TABLE IF NOT EXISTS crm_territories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  code text,
  parent_id uuid REFERENCES crm_territories(id) ON DELETE SET NULL,
  sales_rep_id uuid REFERENCES sales_representatives(id) ON DELETE SET NULL,
  regions text[],
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

-- CRM Forecasts
CREATE TABLE IF NOT EXISTS crm_forecasts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  period text NOT NULL,
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
