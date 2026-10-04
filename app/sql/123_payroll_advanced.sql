-- ============================================================
-- 123_payroll_advanced.sql
-- PAY-07 : Heures supplémentaires conformes
-- PAY-08 : Conventions collectives
-- PAY-09 : Absences maladie, IJSS, subrogation
-- PAY-10 : Bulletin clarifié réglementaire
-- PAY-11 : Solde de tout compte complet
-- ============================================================

-- ============================================================
-- PAY-08 : Conventions collectives (IDCC)
-- ============================================================
CREATE TABLE IF NOT EXISTS collective_agreements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  idcc_code text NOT NULL,           -- Identifiant de la convention
  name text NOT NULL,
  application_date date NOT NULL DEFAULT CURRENT_DATE,
  is_active boolean DEFAULT true,
  metadata jsonb DEFAULT '{}',       -- Primes, minimas, classifications
  created_at timestamptz DEFAULT now()
);

ALTER TABLE collective_agreements ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS collective_agreements_tenant ON collective_agreements;
CREATE POLICY collective_agreements_tenant ON collective_agreements
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- Classifications par convention
CREATE TABLE IF NOT EXISTS collective_classifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  agreement_id uuid NOT NULL REFERENCES collective_agreements(id) ON DELETE CASCADE,
  category text,                     -- Catégorie
  level text,                        -- Niveau
  echelon text,                      -- Échelon
  coefficient int NOT NULL,          -- Coefficient hiérarchique
  minimum_monthly_salary numeric NOT NULL,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE collective_classifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS collective_classifications_tenant ON collective_classifications;
CREATE POLICY collective_classifications_tenant ON collective_classifications
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- Rattacher les salariés à une convention + classification
ALTER TABLE employees ADD COLUMN IF NOT EXISTS collective_agreement_id uuid REFERENCES collective_agreements(id);
ALTER TABLE employees ADD COLUMN IF NOT EXISTS classification_id uuid REFERENCES collective_classifications(id);
ALTER TABLE employees ADD COLUMN IF NOT EXISTS hire_date date;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS seniority_date date;

-- ============================================================
-- PAY-07 : Heures supplémentaires par palier
-- ============================================================
CREATE TABLE IF NOT EXISTS overtime_tiers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  from_hour int NOT NULL,            -- Heure de début (ex: 36, 44)
  to_hour int,                      -- Heure de fin (NULL = illimité)
  rate_multiplier numeric NOT NULL DEFAULT 1.25,
  is_conventional boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE overtime_tiers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS overtime_tiers_tenant ON overtime_tiers;
CREATE POLICY overtime_tiers_tenant ON overtime_tiers
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- Seed des paliers légaux français (sera créé par l'application pour chaque tenant)
-- Désactivé ici car current_tenant_id() retourne NULL sans contexte de session

-- Suivi du plafond d'exonération salariale (7500 €/an)
ALTER TABLE payroll_cumulative ADD COLUMN IF NOT EXISTS overtime_exemption_used numeric DEFAULT 0;

-- ============================================================
-- PAY-07 : Calcul des heures supplémentaires par palier
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_overtime_pay(
  p_employee_id uuid,
  p_overtime_hours numeric,
  p_base_hourly_rate numeric DEFAULT NULL
)
RETURNS TABLE(
  tier_from int,
  tier_to int,
  hours_in_tier numeric,
  rate_multiplier numeric,
  gross_amount numeric,
  exemption_amount numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_base_rate numeric;
  v_hours_remaining numeric := p_overtime_hours;
  v_tier record;
  v_hours_in_tier numeric;
  v_gross numeric;
  v_exemption numeric;
  v_year int := EXTRACT(YEAR FROM CURRENT_DATE);
  v_used numeric := 0;
BEGIN
  -- Taux horaire de base
  IF p_base_hourly_rate IS NOT NULL THEN
    v_base_rate := p_base_hourly_rate;
  ELSE
    SELECT COALESCE(base_salary, 0) / 151.67 INTO v_base_rate
    FROM employees WHERE id = p_employee_id AND tenant_id = v_tid;
  END IF;

  -- Plafond d'exonération restant
  SELECT COALESCE(overtime_exemption_used, 0) INTO v_used
  FROM payroll_cumulative
  WHERE employee_id = p_employee_id AND year = v_year AND tenant_id = v_tid;

  FOR v_tier IN
    SELECT from_hour, to_hour, rate_multiplier
    FROM overtime_tiers
    WHERE tenant_id = v_tid
    ORDER BY from_hour
  LOOP
    v_hours_in_tier := LEAST(v_hours_remaining, COALESCE(v_tier.to_hour - v_tier.from_hour + 1, v_hours_remaining));
    IF v_hours_in_tier <= 0 THEN
      EXIT;
    END IF;

    v_gross := v_hours_in_tier * v_base_rate * v_tier.rate_multiplier;
    v_exemption := LEAST(v_gross, GREATEST(7500 - v_used, 0));
    v_used := v_used + v_exemption;

    RETURN QUERY
      SELECT
        v_tier.from_hour,
        v_tier.to_hour,
        v_hours_in_tier,
        v_tier.rate_multiplier,
        v_gross,
        v_exemption;

    v_hours_remaining := v_hours_remaining - v_hours_in_tier;
    IF v_hours_remaining <= 0 THEN EXIT; END IF;
  END LOOP;
END;
$$;

-- ============================================================
-- PAY-09 : Arrêts de travail (maladie, AT/MP, maternité)
-- ============================================================
CREATE TABLE IF NOT EXISTS sick_leaves (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  leave_type text NOT NULL CHECK (leave_type IN ('sickness', 'work_accident', 'maternity', 'paternity', 'parental')),
  start_date date NOT NULL,
  end_date date NOT NULL,
  waiting_days int DEFAULT 3,       -- Délai de carence
  daily_ijss numeric DEFAULT 0,     -- Indemnités journalières de la sécurité sociale
  is_subrogated boolean DEFAULT false,  -- Subrogation : employeur perçoit les IJSS
  maintenance_rate numeric DEFAULT 0.9,  -- Taux de maintien de salaire
  medical_certificate_url text,
  status text DEFAULT 'active' CHECK (status IN ('active', 'closed', 'cancelled')),
  created_at timestamptz DEFAULT now()
);

ALTER TABLE sick_leaves ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS sick_leaves_tenant ON sick_leaves;
CREATE POLICY sick_leaves_tenant ON sick_leaves
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- ============================================================
-- PAY-09 : Calcul du maintien de salaire et retenue maladie
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_sick_leave_pay(
  p_sick_leave_id uuid
)
RETURNS TABLE(
  leave_days int,
  waiting_days int,
  retained_days int,
  daily_rate numeric,
  retention_amount numeric,
  maintenance_amount numeric,
  ijss_amount numeric,
  net_impact numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_sl record;
  v_tid uuid := current_tenant_id();
  v_emp record;
  v_daily_rate numeric;
  v_leave_days int;
  v_retained_days int;
  v_retention numeric;
  v_maintenance numeric;
  v_ijss numeric;
BEGIN
  SELECT * INTO v_sl FROM sick_leaves WHERE id = p_sick_leave_id AND tenant_id = v_tid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Arrêt introuvable'; END IF;

  SELECT * INTO v_emp FROM employees WHERE id = v_sl.employee_id AND tenant_id = v_tid;

  v_daily_rate := COALESCE(v_emp.base_salary, 0) / 30;  -- Méthode de mensualisation
  v_leave_days := v_sl.end_date - v_sl.start_date + 1;
  v_retained_days := GREATEST(v_leave_days - v_sl.waiting_days, 0);

  -- Retenue pour absence (jours non maintenus)
  v_retention := v_leave_days * v_daily_rate;

  -- Maintien de salaire après carence
  v_maintenance := v_retained_days * v_daily_rate * v_sl.maintenance_rate;

  -- IJSS (si subrogation)
  v_ijss := v_retained_days * v_sl.daily_ijss;

  RETURN QUERY
    SELECT
      v_leave_days,
      v_sl.waiting_days,
      v_retained_days,
      v_daily_rate,
      v_retention,
      v_maintenance,
      v_ijss,
      v_maintenance - v_ijss;  -- Impact net sur le bulletin
END;
$$;

-- ============================================================
-- PAY-10 : Bulletin clarifié — regroupement par risque
-- ============================================================
ALTER TABLE pay_slip_clarified ADD COLUMN IF NOT EXISTS risk_group text;
ALTER TABLE pay_slip_clarified ADD COLUMN IF NOT EXISTS exemption_amount numeric DEFAULT 0;
ALTER TABLE pay_slip_clarified ADD COLUMN IF NOT EXISTS net_social numeric;
ALTER TABLE pay_slip_clarified ADD COLUMN IF NOT EXISTS net_imposable numeric;
ALTER TABLE pay_slip_clarified ADD COLUMN IF NOT EXISTS net_before_tax numeric;
ALTER TABLE pay_slip_clarified ADD COLUMN IF NOT EXISTS net_paid numeric;

-- Vue regroupant les cotisations par risque (depuis le JSON lines)
CREATE OR REPLACE VIEW v_pay_slip_by_risk AS
SELECT
  psc.tenant_id,
  psc.pay_slip_id,
  line->>'risk_group' AS risk_group,
  SUM(COALESCE((line->>'amount')::numeric, 0)) AS total_amount,
  SUM(COALESCE((line->>'exemption_amount')::numeric, 0)) AS total_exemption
FROM pay_slip_clarified psc,
  jsonb_array_elements(COALESCE(psc.lines, '[]'::jsonb)) AS line
WHERE line->>'risk_group' IS NOT NULL
GROUP BY psc.tenant_id, psc.pay_slip_id, line->>'risk_group';

-- ============================================================
-- PAY-11 : Solde de tout compte — indemnité compensatrice de congés
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_compensated_leave_indemnity(
  p_employee_id uuid,
  p_end_date date
)
RETURNS TABLE(
  acquired_days numeric,
  taken_days numeric,
  remaining_days numeric,
  tenth_rule_amount numeric,
  maintenance_rule_amount numeric,
  retained_amount numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_emp record;
  v_acquired numeric := 0;
  v_taken numeric := 0;
  v_remaining numeric;
  v_tenth numeric;
  v_maint numeric;
  v_ref_salary numeric;
BEGIN
  SELECT * INTO v_emp FROM employees WHERE id = p_employee_id AND tenant_id = v_tid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Salarié introuvable'; END IF;

  -- Congés acquis (2,5 jours/mois) depuis l'embauche
  v_acquired := EXTRACT(MONTH FROM age(p_end_date, COALESCE(v_emp.seniority_date, v_emp.hire_date, p_end_date))) * 2.5;

  -- Congés pris (à partir des absences 'paid_leave')
  SELECT COALESCE(SUM(quantity), 0) INTO v_taken
  FROM employee_attendance
  WHERE employee_id = p_employee_id AND tenant_id = v_tid
    AND attendance_type = 'paid_leave'
    AND date <= p_end_date;

  v_remaining := GREATEST(v_acquired - v_taken, 0);

  -- Règle du dixième (10% du brut annuel / nombre de jours acquis)
  v_ref_salary := COALESCE(v_emp.base_salary, 0) * 12;
  v_tenth := (v_ref_salary * 0.10) / 30 * v_remaining;

  -- Règle du maintien (salaire journalier × jours restants)
  v_maint := (COALESCE(v_emp.base_salary, 0) / 30) * v_remaining;

  -- La plus favorable
  RETURN QUERY
    SELECT
      v_acquired,
      v_taken,
      v_remaining,
      v_tenth,
      v_maint,
      GREATEST(v_tenth, v_maint);
END;
$$;

-- ============================================================
-- PAY-11 : Indemnité compensatrice de préavis
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_notice_compensation(
  p_employee_id uuid,
  p_notice_days int DEFAULT 0,
  p_end_date date DEFAULT CURRENT_DATE
)
RETURNS TABLE(
  notice_days int,
  daily_rate numeric,
  compensation_amount numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_emp record;
  v_daily numeric;
BEGIN
  SELECT * INTO v_emp FROM employees WHERE id = p_employee_id AND tenant_id = v_tid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Salarié introuvable'; END IF;

  v_daily := COALESCE(v_emp.base_salary, 0) / 30;

  RETURN QUERY
    SELECT
      p_notice_days,
      v_daily,
      p_notice_days * v_daily;
END;
$$;
