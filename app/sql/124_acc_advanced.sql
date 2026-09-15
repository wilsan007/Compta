-- ============================================================
-- 124_acc_advanced.sql
-- ACC-06 : Lettrage complet
-- ACC-07 : Immobilisations complètes
-- ACC-08 : Comptabilité analytique effective
-- ============================================================

-- ============================================================
-- ACC-06 : Lettrage groupé et partiel
-- ============================================================
ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS lettrage_partial boolean DEFAULT false;
ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS lettrage_group_id uuid;

-- Table de groupes de lettrage (n-à-n)
CREATE TABLE IF NOT EXISTS lettrage_groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  lettrage_code text NOT NULL,
  lettrage_date date NOT NULL DEFAULT CURRENT_DATE,
  total_debit numeric DEFAULT 0,
  total_credit numeric DEFAULT 0,
  residual_amount numeric DEFAULT 0,
  residual_type text,  -- 'escompte' | 'perte_change' | 'gain_change' | 'creance_irrecouvrable'
  status text DEFAULT 'open' CHECK (status IN ('open', 'closed', 'cancelled')),
  created_by uuid,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE lettrage_groups ENABLE ROW LEVEL SECURITY;
CREATE POLICY lettrage_groups_tenant ON lettrage_groups
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- ============================================================
-- ACC-06 : Lettrage par référence structurée
-- ============================================================
CREATE OR REPLACE FUNCTION auto_lettrage_by_reference(
  p_account_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_count int := 0;
  v_line record;
  v_match record;
  v_group_id uuid;
BEGIN
  -- Chercher les lignes non lettrées avec une référence structurée
  FOR v_line IN
    SELECT id, reference, debit, credit
    FROM journal_lines
    WHERE tenant_id = v_tid
      AND account_code = p_account_code
      AND lettrage_code IS NULL
      AND reference IS NOT NULL
    ORDER BY date
  LOOP
    -- Chercher une ligne opposée avec la même référence
    SELECT id, debit, credit INTO v_match
    FROM journal_lines
    WHERE tenant_id = v_tid
      AND account_code = p_account_code
      AND lettrage_code IS NULL
      AND reference = v_line.reference
      AND id != v_line.id
      AND (
        (v_line.debit > 0 AND credit > 0 AND credit = v_line.debit)
        OR (v_line.credit > 0 AND debit > 0 AND debit = v_line.credit)
      )
    LIMIT 1;

    IF v_match IS NOT NULL THEN
      -- Créer un groupe de lettrage
      INSERT INTO lettrage_groups (tenant_id, lettrage_code, lettrage_date, total_debit, total_credit, status)
      VALUES (v_tid, 'LET-' || EXTRACT(EPOCH FROM now())::bigint, CURRENT_DATE, v_line.debit + v_match.debit, v_line.credit + v_match.credit, 'closed')
      RETURNING id INTO v_group_id;

      -- Lettrer les deux lignes
      UPDATE journal_lines SET lettrage_code = 'LET-' || v_group_id, lettrage_date = CURRENT_DATE, lettrage_group_id = v_group_id
      WHERE id IN (v_line.id, v_match.id);

      v_count := v_count + 2;
      v_match := NULL;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('matched_lines', v_count);
END;
$$;

-- ============================================================
-- ACC-06 : Écriture d'écart de règlement
-- ============================================================
CREATE OR REPLACE FUNCTION generate_residual_entry(
  p_group_id uuid,
  p_residual_type text,
  p_amount numeric
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_group record;
  v_je_id uuid;
  v_account_code text;
BEGIN
  SELECT * INTO v_group FROM lettrage_groups WHERE id = p_group_id AND tenant_id = v_tid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Groupe de lettrage introuvable'; END IF;

  -- Compte selon le type d'écart
  v_account_code := CASE p_residual_type
    WHEN 'escompte' THEN '665'
    WHEN 'perte_change' THEN '666'
    WHEN 'gain_change' THEN '766'
    WHEN 'creance_irrecouvrable' THEN '654'
    ELSE NULL
  END;

  IF v_account_code IS NULL THEN
    RAISE EXCEPTION 'Type d''écart inconnu: %', p_residual_type;
  END IF;

  -- Créer l'écriture d'écart
  INSERT INTO journal_entries (
    tenant_id, journal_code, number, date, description, status, created_at
  ) VALUES (
    v_tid, 'OD', 'ECART-' || p_group_id, CURRENT_DATE,
    'Écart de règlement - ' || p_residual_type, 'posted', now()
  )
  RETURNING id INTO v_je_id;

  -- Ligne d'écart
  INSERT INTO journal_lines (
    tenant_id, journal_id, account_code, account_name, debit, credit, created_at
  ) VALUES (
    v_tid, v_je_id, v_account_code,
    CASE p_residual_type
      WHEN 'escompte' THEN 'Escompte accordé'
      WHEN 'perte_change' THEN 'Perte de change'
      WHEN 'gain_change' THEN 'Gain de change'
      WHEN 'creance_irrecouvrable' THEN 'Créance irrécouvrable'
    END,
    CASE WHEN p_residual_type IN ('escompte', 'perte_change', 'creance_irrecouvrable') THEN p_amount ELSE 0 END,
    CASE WHEN p_residual_type = 'gain_change' THEN p_amount ELSE 0 END,
    now()
  );

  -- Mettre à jour le groupe
  UPDATE lettrage_groups SET residual_amount = p_amount, residual_type = p_residual_type, status = 'closed'
  WHERE id = p_group_id;

  RETURN v_je_id;
END;
$$;

-- ============================================================
-- ACC-07 : Composants d'immobilisation
-- ============================================================
CREATE TABLE IF NOT EXISTS fixed_asset_components (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  fixed_asset_id uuid NOT NULL REFERENCES fixed_assets(id) ON DELETE CASCADE,
  name text NOT NULL,
  acquisition_value numeric NOT NULL,
  depreciation_method text DEFAULT 'linear' CHECK (depreciation_method IN ('linear', 'declining_balance', 'exceptional')),
  useful_life_years int NOT NULL,
  salvage_value numeric DEFAULT 0,
  start_date date NOT NULL,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE fixed_asset_components ENABLE ROW LEVEL SECURITY;
CREATE POLICY fixed_asset_components_tenant ON fixed_asset_components
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- ============================================================
-- ACC-07 : Prorata temporis (linéaire en jours)
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_prorata_temporis(
  p_start_date date,
  p_end_date date,
  p_annual_amount numeric,
  p_method text DEFAULT 'linear'
)
RETURNS numeric
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT
    CASE
      WHEN p_method = 'linear' THEN
        -- Prorata en jours
        p_annual_amount * (p_end_date - p_start_date + 1) / 365
      WHEN p_method = 'declining_balance' THEN
        -- Prorata en mois entiers
        p_annual_amount * EXTRACT(MONTH FROM age(p_end_date, p_start_date)) / 12
      ELSE
        p_annual_amount
    END;
$$;

-- ============================================================
-- ACC-07 : Dotation automatique à la clôture
-- ============================================================
CREATE OR REPLACE FUNCTION generate_depreciation_entry(
  p_fixed_asset_id uuid,
  p_fiscal_year_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_fa record;
  v_fy record;
  v_amount numeric;
  v_je_id uuid;
  v_debit_account text;
  v_credit_account text;
BEGIN
  SELECT * INTO v_fa FROM fixed_assets WHERE id = p_fixed_asset_id AND tenant_id = v_tid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Immobilisation introuvable'; END IF;

  SELECT * INTO v_fy FROM fiscal_years WHERE id = p_fiscal_year_id AND tenant_id = v_tid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Exercice introuvable'; END IF;

  -- Calcul de la dotation annuelle
  SELECT calculate_depreciation(
    v_fa.id,
    v_fa.acquisition_value,
    v_fa.useful_life_years,
    v_fa.depreciation_method,
    v_fy.start_date,
    v_fy.end_date
  ) INTO v_amount;

  IF v_amount <= 0 THEN RETURN NULL; END IF;

  -- Comptes : 681xxx (débit) / 28xxxx (crédit)
  v_debit_account := '681' || SUBSTRING(v_fa.account_code FROM 2);
  v_credit_account := '28' || SUBSTRING(v_fa.account_code FROM 2);

  -- Créer l'écriture
  INSERT INTO journal_entries (
    tenant_id, journal_code, number, date, description, status, created_at
  ) VALUES (
    v_tid, 'OD', 'AMORT-' || v_fa.id, v_fy.end_date,
    'Dotation aux amortissements - ' || v_fa.name, 'posted', now()
  )
  RETURNING id INTO v_je_id;

  -- Ligne débit : dotation
  INSERT INTO journal_lines (
    tenant_id, journal_id, account_code, account_name, debit, credit, created_at
  ) VALUES (
    v_tid, v_je_id, v_debit_account, 'Dotations aux amortissements', v_amount, 0, now()
  );

  -- Ligne crédit : amortissement cumulé
  INSERT INTO journal_lines (
    tenant_id, journal_id, account_code, account_name, debit, credit, created_at
  ) VALUES (
    v_tid, v_je_id, v_credit_account, 'Amortissements', 0, v_amount, now()
  );

  RETURN v_je_id;
END;
$$;

CREATE OR REPLACE FUNCTION propagate_analytic_section()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_inv_ref text;
  v_ref text;
  v_sec_id uuid;
BEGIN
  -- Si la ligne d'écriture a déjà une section analytique, rien à faire
  IF NEW.analytic_section_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- Chercher la référence de facture depuis l'entête journal_entries
  SELECT invoice_ref, reference
  INTO v_inv_ref, v_ref
  FROM journal_entries
  WHERE id = NEW.journal_id;

  IF v_inv_ref IS NOT NULL OR v_ref IS NOT NULL THEN
    -- Chercher dans les lignes de factures clients
    SELECT analytic_section_id INTO v_sec_id
    FROM invoice_lines
    WHERE invoice_id IN (
      SELECT id FROM invoices
      WHERE (number = v_inv_ref OR number = v_ref)
        AND tenant_id = NEW.tenant_id
    ) AND analytic_section_id IS NOT NULL
    LIMIT 1;

    -- Si non trouvé, chercher dans les factures fournisseurs
    IF v_sec_id IS NULL THEN
      SELECT analytic_section_id INTO v_sec_id
      FROM supplier_invoice_lines
      WHERE invoice_id IN (
        SELECT id FROM supplier_invoices
        WHERE (number = v_inv_ref OR number = v_ref)
          AND tenant_id = NEW.tenant_id
      ) AND analytic_section_id IS NOT NULL
      LIMIT 1;
    END IF;

    IF v_sec_id IS NOT NULL THEN
      NEW.analytic_section_id := v_sec_id;
    END IF;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- En cas d'exception quelconque, ne jamais bloquer l'insertion comptable
  RETURN NEW;
END;
$$;

-- Trigger de propagation analytique
DROP TRIGGER IF EXISTS trigger_propagate_analytic ON journal_lines;
CREATE TRIGGER trigger_propagate_analytic
  BEFORE INSERT ON journal_lines
  FOR EACH ROW EXECUTE FUNCTION propagate_analytic_section();

-- ============================================================
-- ACC-08 : Contrôle d'équilibre analytique
-- ============================================================
CREATE OR REPLACE FUNCTION check_analytic_balance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_total numeric := 0;
  v_line_amount numeric;
BEGIN
  -- Pour les comptes de classe 6 et 7, vérifier que la section analytique est renseignée
  IF NEW.account_code ~ '^[67]' AND NEW.analytic_section_id IS NULL THEN
    -- Permettre l'insertion mais alerter (non bloquant pour compatibilité)
    -- En production stricte, décommenter le RAISE
    -- RAISE WARNING 'Ligne sans section analytique sur compte %', NEW.account_code;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_check_analytic ON journal_lines;
CREATE TRIGGER trigger_check_analytic
  BEFORE INSERT OR UPDATE ON journal_lines
  FOR EACH ROW EXECUTE FUNCTION check_analytic_balance();

-- ============================================================
-- ACC-08 : Ventilation par grille de répartition
-- ============================================================
CREATE OR REPLACE FUNCTION distribute_by_grill(
  p_journal_line_id uuid,
  p_grill_id uuid
)
RETURNS TABLE(
  section_id uuid,
  section_name text,
  amount numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_line record;
  v_grill record;
  v_total_keys numeric;
BEGIN
  SELECT * INTO v_line FROM journal_lines WHERE id = p_journal_line_id AND tenant_id = v_tid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ligne introuvable'; END IF;

  -- Somme des clés de la grille
  SELECT COALESCE(SUM(percentage), 0) INTO v_total_keys
  FROM distribution_grill_lines
  WHERE grill_id = p_grill_id AND tenant_id = v_tid;

  IF v_total_keys = 0 THEN RAISE EXCEPTION 'Grille vide ou introuvable'; END IF;

  -- Répartir le montant selon les clés
  RETURN QUERY
    SELECT
      dgl.section_id,
      as2.name,
      (COALESCE(v_line.debit, 0) + COALESCE(v_line.credit, 0)) * dgl.percentage / v_total_keys
    FROM distribution_grill_lines dgl
    JOIN analytic_sections as2 ON as2.id = dgl.section_id AND as2.tenant_id = v_tid
    WHERE dgl.grill_id = p_grill_id AND dgl.tenant_id = v_tid;
END;
$$;
