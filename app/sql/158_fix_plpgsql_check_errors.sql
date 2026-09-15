-- ============================================================
-- 158_fix_plpgsql_check_errors.sql
--
-- Erreurs trouvées par plpgsql_check après rejeu réel des 157 migrations
-- sur PostgreSQL 16 (15/09/2026). Chaque fonction est reprise depuis sa
-- définition effective en base, corrigée sur les seules colonnes fautives.
-- ============================================================

-- ------------------------------------------------------------
-- LOT2-09 : règles de rapprochement — colonnes match_pattern / counterpart_account
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.apply_bank_reconciliation_rules()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_rule record;
BEGIN
  IF NEW.matched = true THEN RETURN NEW; END IF;

  FOR v_rule IN
    SELECT *
    FROM bank_reconciliation_rules
    WHERE tenant_id = NEW.tenant_id
      AND active = true
    ORDER BY priority DESC
  LOOP
    -- Vérifier si le libellé correspond au pattern
    IF v_rule.match_pattern IS NOT NULL AND NEW.description ILIKE v_rule.match_pattern THEN
      -- Appliquer la règle : assigner le compte et marquer comme rapproché
      NEW.matched_account_code := v_rule.counterpart_account;
      NEW.matched := true;
      NEW.match_type := 'rule';

      -- Créer l'écriture comptable correspondante
      -- (la création complète se fait via le trigger de rapprochement)
      EXIT;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$function$;

-- ------------------------------------------------------------
-- LOT2-08 : rapprochement par score — invoices n'a pas de payment_reference
-- (toute insertion de mouvement bancaire échouait)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.auto_reconcile_by_score()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_invoice record;
  v_score int;
  v_best_score int := 0;
  v_best_invoice_id uuid;
  v_best_customer_id uuid;
  v_best_amount numeric;
  v_tx_label text;
BEGIN
  -- Ne rapprocher que les mouvements non déjà rapprochés
  IF NEW.matched = true THEN RETURN NEW; END IF;

  v_tx_label := NEW.description;

  -- Chercher la meilleure facture par score multi-critères
  FOR v_invoice IN
    SELECT i.*,
      (CASE WHEN ABS(i.amount_due - NEW.amount) < 0.01              THEN 50 ELSE 0 END
     + CASE WHEN v_tx_label ILIKE '%' || i.number || '%'            THEN 40 ELSE 0 END
     + CASE WHEN NULLIF(NEW.reference, '') IS NOT NULL
            AND NEW.reference = i.number                            THEN 40 ELSE 0 END
     + CASE WHEN v_tx_label ILIKE '%' || c.name || '%'              THEN 20 ELSE 0 END
     + CASE WHEN i.due_date BETWEEN NEW.date - 30 AND NEW.date + 30 THEN 10 ELSE 0 END
      ) AS score
    FROM invoices i
    LEFT JOIN customers c ON c.id = i.customer_id AND c.tenant_id = i.tenant_id
    WHERE i.tenant_id = NEW.tenant_id
      AND i.payment_state IN ('not_paid', 'partial')
      AND ABS(i.amount_due) > 0
    ORDER BY score DESC
    LIMIT 5
  LOOP
    v_score := v_invoice.score;

    -- Au-dessus du seuil : rapprochement automatique
    IF v_score >= 70 AND v_score > v_best_score THEN
      v_best_score := v_score;
      v_best_invoice_id := v_invoice.id;
      v_best_customer_id := v_invoice.customer_id;
      v_best_amount := v_invoice.amount_due;
    END IF;

    -- Entre 40 et 70 : créer une suggestion
    IF v_score >= 40 AND v_score < 70 THEN
      INSERT INTO bank_reconciliation_suggestions (
        tenant_id, bank_transaction_id, invoice_id, customer_id,
        score, match_type, matched_amount, status
      ) VALUES (
        NEW.tenant_id, NEW.id, v_invoice.id, v_invoice.customer_id,
        v_score, 'suggestion', v_invoice.amount_due, 'pending'
      );
    END IF;
  END LOOP;

  -- Si une facture a un score >= 70, rapprocher automatiquement
  IF v_best_invoice_id IS NOT NULL THEN
    -- Mettre à jour la transaction dans la table
    UPDATE bank_transactions
    SET matched = true,
        invoice_id = v_best_invoice_id,
        matched_invoice_id = v_best_invoice_id
    WHERE id = NEW.id;

    -- Mettre à jour la facture
    UPDATE invoices
    SET payment_state = CASE
      WHEN amount_due <= ABS(NEW.amount) THEN 'paid'
      ELSE 'partial'
    END,
    amount_paid = COALESCE(amount_paid, 0) + ABS(NEW.amount),
    updated_at = now()
    WHERE id = v_best_invoice_id AND tenant_id = NEW.tenant_id;

    -- Créer l'écriture de règlement
    INSERT INTO bank_reconciliation_suggestions (
      tenant_id, bank_transaction_id, invoice_id, customer_id,
      score, match_type, matched_amount, status
    ) VALUES (
      NEW.tenant_id, NEW.id, v_best_invoice_id, v_best_customer_id,
      v_best_score, 'auto', v_best_amount, 'accepted'
    );
  END IF;

  RETURN NEW;
END;
$function$;

-- ------------------------------------------------------------
-- LOT3 : calculate_depreciation — la colonne s'appelle amount
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.calculate_depreciation(p_asset_id uuid, p_period text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_asset fixed_assets%ROWTYPE;
  v_annual_depreciation numeric;
  v_monthly_depreciation numeric;
  v_period_start date;
  v_accumulated numeric := 0;
BEGIN
  SELECT * INTO v_asset FROM fixed_assets WHERE id = p_asset_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN RAISE EXCEPTION 'Actif non trouvé'; END IF;

  v_period_start := (p_period || '-01')::date;
  v_annual_depreciation := COALESCE(v_asset.purchase_value, 0) / NULLIF(COALESCE(v_asset.useful_life_years, 1), 0);
  v_monthly_depreciation := v_annual_depreciation / 12;

  SELECT COALESCE(SUM(amount), 0) INTO v_accumulated
  FROM asset_depreciations WHERE asset_id = p_asset_id AND tenant_id = current_tenant_id();

  RETURN jsonb_build_object(
    'asset_id', p_asset_id,
    'period', p_period,
    'monthly_depreciation', v_monthly_depreciation,
    'annual_depreciation', v_annual_depreciation,
    'accumulated_depreciation', v_accumulated + v_monthly_depreciation,
    'net_book_value', COALESCE(v_asset.purchase_value, 0) - v_accumulated - v_monthly_depreciation
  );
END;
$function$;

-- ------------------------------------------------------------
-- LOT3 : calculate_overtime_pay — rate_multiplier ambigu avec le paramètre de sortie
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.calculate_overtime_pay(p_employee_id uuid, p_overtime_hours numeric, p_base_hourly_rate numeric DEFAULT NULL::numeric)
 RETURNS TABLE(tier_from integer, tier_to integer, hours_in_tier numeric, rate_multiplier numeric, gross_amount numeric, exemption_amount numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
  IF p_base_hourly_rate IS NOT NULL THEN
    v_base_rate := p_base_hourly_rate;
  ELSE
    SELECT COALESCE(COALESCE(base_salary, salary), 0) / 151.67 INTO v_base_rate
    FROM employees WHERE id = p_employee_id AND tenant_id = v_tid;
  END IF;

  SELECT COALESCE(overtime_exemption_used, 0) INTO v_used
  FROM payroll_cumulative
  WHERE employee_id = p_employee_id AND year = v_year AND tenant_id = v_tid;

  FOR v_tier IN
    SELECT ot.from_hour, ot.to_hour, ot.rate_multiplier
    FROM overtime_tiers ot
    WHERE ot.tenant_id = v_tid
    ORDER BY ot.from_hour
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
$function$;

-- ------------------------------------------------------------
-- LOT3 : calculate_project_profitability — temps saisi en secondes, taux horaire par saisie ;
-- les notes de frais ne sont pas rattachées aux projets
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.calculate_project_profitability(p_project_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_tid uuid := current_tenant_id();
  v_proj RECORD;
  v_invoiced numeric := 0;
  v_cost numeric := 0;
  v_budget numeric := 0;
  v_margin numeric := 0;
  v_margin_pct numeric := 0;
  v_progress_pct numeric := 0;
  v_eac numeric := 0;  -- Estimate At Completion
  v_etc numeric := 0;  -- Estimate To Complete
  v_cpi numeric := 0;  -- Cost Performance Index
  v_hours_logged numeric := 0;
  v_time_cost numeric := 0;
  v_task_count integer := 0;
  v_completed_tasks integer := 0;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  SELECT * INTO v_proj FROM projects WHERE id = p_project_id AND tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Projet non trouvé: %', p_project_id;
  END IF;

  -- CA facturé sur le projet
  SELECT COALESCE(sum(i.total), 0) INTO v_invoiced
  FROM invoices i
  WHERE i.tenant_id = v_tid AND i.project_id = p_project_id
    AND i.status NOT IN ('cancelled', 'draft');

  -- Coûts (temps + dépenses)
  SELECT COALESCE(sum(COALESCE(te.duration_seconds, 0) / 3600.0), 0),
         COALESCE(sum(COALESCE(te.duration_seconds, 0) / 3600.0
                      * COALESCE(te.hourly_rate, COALESCE(e.salary, 0) / 151.67)), 0)
  INTO v_hours_logged, v_time_cost
  FROM project_time_entries te
  LEFT JOIN employees e ON e.id = te.employee_id AND e.tenant_id = v_tid
  WHERE te.tenant_id = v_tid AND te.project_id = p_project_id;

  v_cost := v_time_cost;

  -- Budget
  v_budget := COALESCE(v_proj.budget, 0);

  -- Marges
  v_margin := v_invoiced - v_cost;
  v_margin_pct := CASE WHEN v_invoiced > 0 THEN (v_margin / v_invoiced) * 100 ELSE 0 END;

  -- Avancement (basé sur tâches)
  SELECT count(*), count(*) FILTER (WHERE status = 'done' OR status = 'completed')
  INTO v_task_count, v_completed_tasks
  FROM project_tasks
  WHERE tenant_id = v_tid AND project_id = p_project_id;

  v_progress_pct := CASE WHEN v_task_count > 0 THEN (v_completed_tasks::numeric / v_task_count) * 100 ELSE 0 END;

  -- EAC / ETC / CPI (Earned Value Management)
  IF v_progress_pct > 0 AND v_cost > 0 THEN
    v_cpi := (v_budget * v_progress_pct / 100) / v_cost;
    v_eac := CASE WHEN v_cpi > 0 THEN v_budget / v_cpi ELSE v_cost END;
    v_etc := v_eac - v_cost;
  ELSE
    v_eac := v_cost;
    v_etc := v_budget - v_cost;
  END IF;

  RETURN jsonb_build_object(
    'project_id', p_project_id,
    'project_name', v_proj.name,
    'status', v_proj.status,
    'budget', round(v_budget, 2),
    'invoiced', round(v_invoiced, 2),
    'cost', round(v_cost, 2),
    'hours_logged', round(v_hours_logged, 2),
    'margin', round(v_margin, 2),
    'margin_pct', round(v_margin_pct, 2),
    'progress_pct', round(v_progress_pct, 2),
    'task_count', v_task_count,
    'completed_tasks', v_completed_tasks,
    'eac', round(v_eac, 2),
    'etc', round(v_etc, 2),
    'cpi', round(v_cpi, 2),
    'health', CASE
      WHEN v_margin_pct > 20 THEN 'healthy'
      WHEN v_margin_pct > 0 THEN 'warning'
      ELSE 'critical'
    END
  );
END;
$function$;

-- ------------------------------------------------------------
-- P0 onboarding : create_tenant_for_current_user — enabled_modules est jsonb
-- (la création de société échouait toujours avec success=false)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_tenant_for_current_user(p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_tenant uuid;
  v_auth_id uuid := auth.uid();
  v_email text;
  v_user_name text;
  v_enabled_modules jsonb;
  v_claims jsonb;
BEGIN
  IF v_auth_id IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;

  -- Métadonnées JWT via request.jwt.claims (compatible Supabase ET local)
  BEGIN
    v_claims := COALESCE(current_setting('request.jwt.claims', true)::jsonb, '{}'::jsonb);
  EXCEPTION WHEN OTHERS THEN
    v_claims := '{}'::jsonb;
  END;

  v_email := COALESCE(
    v_claims ->> 'email',
    v_claims -> 'user_metadata' ->> 'email'
  );

  v_user_name := COALESCE(
    v_claims -> 'user_metadata' ->> 'name',
    v_claims -> 'user_metadata' ->> 'full_name',
    v_email
  );

  v_enabled_modules := COALESCE(
    p_data -> 'enabled_modules',
    '["home","accounting","commercial","treasury","stock","production","hr","dashboards","reporting","system"]'::jsonb
  );

  INSERT INTO tenants (
    name, legal_name, siren, vat_number,
    address, city, postal_code, country, currency,
    email, phone, legislation_pack_code, country_code,
    enabled_modules, status, plan, trial_ends_at
  ) VALUES (
    p_data ->> 'name',
    COALESCE(p_data ->> 'legal_name', p_data ->> 'name'),
    p_data ->> 'siren',
    p_data ->> 'vat_number',
    p_data ->> 'address',
    p_data ->> 'city',
    p_data ->> 'postal_code',
    COALESCE(p_data ->> 'country', 'France'),
    COALESCE(p_data ->> 'currency', 'EUR'),
    COALESCE(p_data ->> 'email', v_email),
    p_data ->> 'phone',
    p_data ->> 'legislation_pack_code',
    p_data ->> 'legislation_pack_code',
    v_enabled_modules,
    'active',
    'trial',
    (NOW() + INTERVAL '30 days')::timestamptz
  )
  RETURNING id INTO v_tenant;

  INSERT INTO tenant_users (
    tenant_id, auth_id, email, name, role, permissions, status, accepted_at
  ) VALUES (
    v_tenant,
    v_auth_id,
    v_email,
    v_user_name,
    'admin',
    '{}'::jsonb,
    'active',
    NOW()
  );

  BEGIN
    INSERT INTO employees (
      tenant_id, name, email, position, department, hire_date, status
    ) VALUES (
      v_tenant,
      v_user_name,
      v_email,
      'Admin',
      'Direction',
      CURRENT_DATE,
      'active'
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Employee creation skipped: %', SQLERRM;
  END;

  BEGIN
    PERFORM bootstrap_tenant(v_tenant);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'bootstrap_tenant skipped: %', SQLERRM;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'tenant_id', v_tenant
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$function$;

-- ------------------------------------------------------------
-- LOT3 : import_employee_with_cumuls — aucun index unique (tenant_id, email) :
-- recherche puis mise à jour ou insertion
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.import_employee_with_cumuls(p_employee json, p_cumuls json DEFAULT NULL::json)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_trgm', 'pg_temp'
AS $function$
DECLARE
  v_tid uuid := current_tenant_id();
  v_emp_id uuid;
  v_cumul record;
  v_full_name text;
  v_sal numeric;
  v_year int;
  v_month int;
  v_gross numeric;
  v_tax numeric;
  v_social numeric;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  v_full_name := TRIM(COALESCE(p_employee->>'name', COALESCE(p_employee->>'first_name', '') || ' ' || COALESCE(p_employee->>'last_name', '')));
  v_sal := COALESCE((p_employee->>'base_salary')::numeric, (p_employee->>'salary')::numeric, 0);

  -- Créer ou mettre à jour l'employé (rapprochement sur l'e-mail dans le tenant)
  IF NULLIF(p_employee->>'email', '') IS NOT NULL THEN
    SELECT id INTO v_emp_id FROM employees
    WHERE tenant_id = v_tid AND lower(email) = lower(p_employee->>'email')
    ORDER BY created_at
    LIMIT 1;
  END IF;

  IF v_emp_id IS NOT NULL THEN
    UPDATE employees SET
      name = v_full_name,
      first_name = p_employee->>'first_name',
      last_name = p_employee->>'last_name',
      phone = p_employee->>'phone',
      position = p_employee->>'position',
      department = p_employee->>'department',
      salary = v_sal,
      base_salary = v_sal,
      updated_at = now()
    WHERE id = v_emp_id;
  ELSE
    INSERT INTO employees (
      tenant_id, name, first_name, last_name, email, phone, hire_date,
      contract_type, position, department, salary, base_salary, status
    ) VALUES (
      v_tid,
      v_full_name,
      p_employee->>'first_name',
      p_employee->>'last_name',
      p_employee->>'email',
      p_employee->>'phone',
      COALESCE((p_employee->>'hire_date')::date, CURRENT_DATE),
      COALESCE(p_employee->>'contract_type', 'cdi'),
      p_employee->>'position',
      p_employee->>'department',
      v_sal,
      v_sal,
      'active'
    )
    RETURNING id INTO v_emp_id;
  END IF;

  -- Insérer les cumuls si fournis (mapping des colonnes corrigé)
  IF p_cumuls IS NOT NULL THEN
    FOR v_cumul IN
      SELECT
        (elem->>'year')::int AS year,
        COALESCE((elem->>'month')::int, 0) AS month,
        COALESCE((elem->>'cumulative_gross')::numeric, (elem->>'gross')::numeric, 0) AS gross,
        COALESCE((elem->>'cumulative_tax')::numeric, (elem->>'withholding_tax')::numeric, (elem->>'tax')::numeric, 0) AS tax,
        COALESCE((elem->>'cumulative_social')::numeric, (elem->>'employee_contributions')::numeric, (elem->>'social')::numeric, 0) AS social
      FROM json_array_elements(p_cumuls) AS elem
    LOOP
      INSERT INTO payroll_cumulative (
        tenant_id, employee_id, year, month,
        gross, withholding_tax, employee_contributions
      ) VALUES (
        v_tid, v_emp_id, v_cumul.year, v_cumul.month,
        v_cumul.gross, v_cumul.tax, v_cumul.social
      )
      ON CONFLICT (tenant_id, employee_id, year, month)
      DO UPDATE SET
        gross = EXCLUDED.gross,
        withholding_tax = EXCLUDED.withholding_tax,
        employee_contributions = EXCLUDED.employee_contributions;
    END LOOP;
  END IF;

  RETURN jsonb_build_object('success', true, 'employee_id', v_emp_id);
END;
$function$;

-- ------------------------------------------------------------
-- LOT3 : import_initial_stock — product_id ambigu, contrainte unique (product_id, warehouse_id)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.import_initial_stock(p_stock_data json, p_batch_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(product_id uuid, product_name text, warehouse_id uuid, quantity numeric, unit_cost numeric, status text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_trgm', 'pg_temp'
AS $function$
#variable_conflict use_column
DECLARE
  v_tid uuid := current_tenant_id();
  v_row json;
  v_product_id uuid;
  v_warehouse_id uuid;
  v_qty numeric;
  v_cost numeric;
BEGIN
  FOR v_row IN SELECT * FROM json_array_elements(p_stock_data)
  LOOP
    v_product_id := (v_row->>'product_id')::uuid;
    v_warehouse_id := (v_row->>'warehouse_id')::uuid;
    v_qty := (v_row->>'quantity')::numeric;
    v_cost := COALESCE((v_row->>'unit_cost')::numeric, 0);

    INSERT INTO stock_movements (
      tenant_id, product_id, warehouse_id, movement_type,
      quantity, unit_cost, reference, reference_type,
      movement_date, created_at
    ) VALUES (
      v_tid, v_product_id, v_warehouse_id, 'initial',
      v_qty, v_cost, 'STOCK-INIT', 'manual',
      now(), now()
    );

    INSERT INTO stock_quantities (
      tenant_id, product_id, warehouse_id,
      quantity, unit_cost, min_quantity, max_quantity, reorder_point
    ) VALUES (
      v_tid, v_product_id, COALESCE(v_warehouse_id, (SELECT id FROM warehouses WHERE tenant_id = v_tid LIMIT 1)),
      v_qty, v_cost, 0, 0, 0
    )
    ON CONFLICT (product_id, warehouse_id)
    DO UPDATE SET quantity = EXCLUDED.quantity, unit_cost = EXCLUDED.unit_cost, updated_at = now();
  END LOOP;

  RETURN QUERY
    SELECT
      (elem->>'product_id')::uuid AS product_id,
      COALESCE(elem->>'product_name', '')::text AS product_name,
      (elem->>'warehouse_id')::uuid AS warehouse_id,
      (elem->>'quantity')::numeric AS quantity,
      COALESCE((elem->>'unit_cost')::numeric, 0) AS unit_cost,
      'imported'::text AS status
    FROM json_array_elements(p_stock_data) AS elem;
END;
$function$;

-- ------------------------------------------------------------
-- LOT4-08 : next_lettrage_code — company_settings n'a pas d'unicité sur tenant_id
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.next_lettrage_code()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_seq bigint;
  v_tid uuid := current_tenant_id();
  v_letter text;
  v_num int;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- Incrémenter atomiquement la séquence
  UPDATE company_settings
  SET next_lettrage_seq = next_lettrage_seq + 1
  WHERE tenant_id = v_tid
  RETURNING next_lettrage_seq - 1 INTO v_seq;

  -- Si company_settings n'existe pas pour ce tenant, v_seq est NULL
  IF v_seq IS NULL THEN
    -- Créer la ligne si elle n'existe pas
    PERFORM pg_advisory_xact_lock(hashtext('lettrage:' || v_tid::text));
    UPDATE company_settings
    SET next_lettrage_seq = next_lettrage_seq + 1
    WHERE tenant_id = v_tid
    RETURNING next_lettrage_seq - 1 INTO v_seq;
    IF v_seq IS NULL THEN
      INSERT INTO company_settings (tenant_id, name, next_lettrage_seq)
      SELECT v_tid, COALESCE(t.name, 'Société'), 2 FROM tenants t WHERE t.id = v_tid;
      v_seq := 1;
    END IF;
  END IF;

  -- A001..Z999 (26 * 999 = 25 974 codes)
  IF v_seq < 26 * 999 THEN
    v_letter := chr(65 + (v_seq / 999)::int);
    v_num := (v_seq % 999)::int + 1;
    RETURN v_letter || lpad(v_num::text, 3, '0');
  -- AA01..ZZ99 (26 * 26 * 99 = 67 176 codes)
  ELSIF v_seq < 26 * 999 + 26 * 26 * 99 THEN
    v_seq := v_seq - 26 * 999;
    v_letter := chr(65 + (v_seq / (26 * 99))::int) || chr(65 + ((v_seq / 99)::int % 26));
    v_num := (v_seq % 99)::int + 1;
    RETURN v_letter || lpad(v_num::text, 2, '0');
  ELSE
    RAISE EXCEPTION 'Numérotation de lettrage épuisée';
  END IF;
END;
$function$;

-- ------------------------------------------------------------
-- LOT2-06 : propagate_analytic_section — les lignes de factures ne portent aucune section
-- analytique et supplier_invoices n'existe pas : rien à propager, la fonction ne lit plus
-- que des colonnes existantes
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.propagate_analytic_section()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  -- La section analytique est posée par la saisie (journal_lines.analytic_section_id)
  -- ou par analytic_distribution ; aucune ligne de document ne la porte à ce jour.
  RETURN NEW;
END;
$function$;

-- ------------------------------------------------------------
-- LOT4-06 / LOT2-16 : réservation — sales_order_lines n'a pas de dépôt :
-- on réserve sur le dépôt qui a le plus de disponible, une seule fois
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reserve_stock_on_sales_order_confirm()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_line RECORD;
  v_warehouse_id UUID;
  v_tid UUID := NEW.tenant_id;
BEGIN
  IF NEW.status = 'confirmed' AND OLD.status IS DISTINCT FROM 'confirmed' THEN
    FOR v_line IN SELECT * FROM sales_order_lines WHERE sales_order_id = NEW.id AND tenant_id = v_tid AND quantity > 0 LOOP
      -- STK-02 : la ligne de commande ne porte pas de dépôt : choisir celui qui a le plus de disponible
      SELECT sq.warehouse_id INTO v_warehouse_id
      FROM stock_quantities sq
      WHERE sq.tenant_id = v_tid AND sq.product_id = v_line.product_id
      ORDER BY (COALESCE(sq.quantity, 0) - COALESCE(sq.reserved_quantity, 0)) DESC, sq.warehouse_id
      LIMIT 1;

      -- Créer la réservation avec warehouse_id
      INSERT INTO stock_reservations (
        tenant_id, product_id, warehouse_id, quantity,
        reserved_by, reference_id, reference_type, status
      ) VALUES (
        v_tid, v_line.product_id, v_warehouse_id, v_line.quantity,
        'sales_order', NEW.id, 'sales_order', 'active'
      );

      -- STK-02 : Mettre à jour la quantité réservée uniquement pour le dépôt concerné
      UPDATE stock_quantities
      SET reserved_quantity = reserved_quantity + v_line.quantity,
        updated_at = now()
      WHERE tenant_id = v_tid
        AND product_id = v_line.product_id
        AND warehouse_id = v_warehouse_id;
    END LOOP;
  END IF;

  RETURN NEW;
END;
$function$;

-- ------------------------------------------------------------
-- LOT3 : resolve_price — customers n'a pas de catégorie tarifaire
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resolve_price(p_product_id uuid, p_customer_id uuid, p_quantity numeric DEFAULT 1, p_date date DEFAULT CURRENT_DATE)
 RETURNS TABLE(unit_price numeric, discount_percent numeric, price_list_id uuid, price_list_name text, source text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_tid uuid := current_tenant_id();
  v_customer_pl uuid;
  v_customer_cat uuid;
  v_line record;
  v_base_price numeric;
BEGIN
  -- Rattachements du client
  SELECT c.price_list_id INTO v_customer_pl
  FROM customers c WHERE c.id = p_customer_id AND c.tenant_id = v_tid;

  -- Pas de catégorie tarifaire sur customers : v_customer_cat reste NULL

  -- Chercher la ligne de tarif la plus spécifique
  SELECT pll.unit_price, pll.discount_percent, pll.min_quantity,
         pl.id, pl.name, pl.base_price_list_id, pl.discount_percent AS pl_discount
  INTO v_line
  FROM price_list_lines pll
  JOIN price_lists pl ON pl.id = pll.price_list_id AND pl.tenant_id = pll.tenant_id
  WHERE pll.tenant_id = v_tid
    AND pll.product_id = p_product_id
    AND pl.type = 'sales'
    AND pl.active = true
    AND pll.min_quantity <= p_quantity
    AND COALESCE(pl.valid_from, p_date) <= p_date
    AND COALESCE(pl.valid_to, '9999-12-31'::date) >= p_date
    AND (
      -- 1. Tarif nominatif du client
      pl.id IN (SELECT plc.price_list_id FROM price_list_customers plc
                WHERE plc.customer_id = p_customer_id AND plc.tenant_id = v_tid)
      -- 2. Tarif directement rattaché au client
      OR pl.id = v_customer_pl
      -- 3. Tarif de sa catégorie
      OR (v_customer_cat IS NOT NULL AND pl.customer_category_id = v_customer_cat)
      -- 4. Tarif par défaut
      OR pl.is_default = true
    )
  ORDER BY
    -- Nominatif > rattaché > catégorie > défaut
    CASE
      WHEN pl.id IN (SELECT plc.price_list_id FROM price_list_customers plc
                     WHERE plc.customer_id = p_customer_id AND plc.tenant_id = v_tid) THEN 0
      WHEN pl.id = v_customer_pl THEN 1
      WHEN v_customer_cat IS NOT NULL AND pl.customer_category_id = v_customer_cat THEN 2
      ELSE 3
    END,
    pl.priority DESC NULLS LAST,
    pll.min_quantity DESC
  LIMIT 1;

  IF v_line.id IS NULL THEN
    RETURN;
  END IF;

  -- Tarif dérivé d'un autre tarif (% de remise sur tarif de base)
  IF v_line.base_price_list_id IS NOT NULL THEN
    SELECT pll2.unit_price INTO v_base_price
    FROM price_list_lines pll2
    WHERE pll2.tenant_id = v_tid
      AND pll2.price_list_id = v_line.base_price_list_id
      AND pll2.product_id = p_product_id
      AND pll2.min_quantity <= p_quantity
    ORDER BY pll2.min_quantity DESC
    LIMIT 1;

    IF v_base_price IS NOT NULL THEN
      RETURN QUERY
      SELECT
        v_base_price * (1 - COALESCE(v_line.pl_discount, 0) / 100),
        COALESCE(v_line.discount_percent, 0),
        v_line.id,
        v_line.name,
        'price_list:' || v_line.name;
      RETURN;
    END IF;
  END IF;

  RETURN QUERY
  SELECT
    v_line.unit_price,
    COALESCE(v_line.discount_percent, 0),
    v_line.id,
    v_line.name,
    'price_list:' || v_line.name;
END;
$function$;

-- ------------------------------------------------------------
-- P0 : récursion infinie sur tenant_users (migration 90)
-- Le trigger FOR EACH STATEMENT appelle auto_revoke_expired_auditors(), qui
-- fait un UPDATE tenant_users, qui redéclenche le trigger — même sans ligne
-- modifiée. Toute création ou modification d'utilisateur de tenant levait
-- « stack depth limit exceeded ».
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trigger_revoke_expired_auditors()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- Ne pas se redéclencher depuis l'UPDATE de auto_revoke_expired_auditors()
  IF pg_trigger_depth() > 1 THEN
    RETURN NULL;
  END IF;
  PERFORM auto_revoke_expired_auditors();
  RETURN NULL;
END;
$function$;

-- ------------------------------------------------------------
-- Double décrément du solde client
-- create_journal_on_customer_payment met à jour customer_payments (écriture liée) :
-- l'UPDATE redéclenchait update_invoice_on_customer_payment, qui retirait une
-- seconde fois le montant du solde client (1000 - 120 → 760 au lieu de 880).
-- La facture était recalculée depuis la somme des paiements (idempotent) ;
-- le solde client est désormais ajusté du seul écart entre OLD et NEW.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_invoice_on_customer_payment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_invoice RECORD;
  v_total_paid numeric;
  v_invoice_total numeric;
  v_old_counted numeric := 0;
  v_new_counted numeric := 0;
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.status IN ('recorded', 'validated') THEN
    v_old_counted := COALESCE(OLD.amount, 0);
  END IF;
  IF NEW.status IN ('recorded', 'validated') THEN
    v_new_counted := COALESCE(NEW.amount, 0);
  END IF;

  -- Facture liée : recalcul complet depuis les paiements enregistrés
  IF NEW.invoice_id IS NOT NULL THEN
    SELECT * INTO v_invoice FROM invoices WHERE id = NEW.invoice_id AND tenant_id = NEW.tenant_id;
    IF FOUND THEN
      SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
      FROM customer_payments
      WHERE invoice_id = NEW.invoice_id
        AND tenant_id = NEW.tenant_id
        AND status IN ('recorded', 'validated');

      v_invoice_total := COALESCE(v_invoice.total, 0);

      UPDATE invoices
        SET amount_paid = v_total_paid,
            amount_due = GREATEST(v_invoice_total - v_total_paid, 0),
            payment_state = CASE
              WHEN v_total_paid >= v_invoice_total AND v_invoice_total > 0 THEN 'paid'
              WHEN v_total_paid > 0 THEN 'partial'
              ELSE 'not_paid'
            END,
            status = CASE
              WHEN v_total_paid >= v_invoice_total AND v_invoice_total > 0 THEN 'paid'
              ELSE status
            END,
            updated_at = NOW()
      WHERE id = NEW.invoice_id AND tenant_id = NEW.tenant_id
        AND (amount_paid IS DISTINCT FROM v_total_paid
             OR amount_due IS DISTINCT FROM GREATEST(v_invoice_total - v_total_paid, 0));
    END IF;
  END IF;

  -- Solde client : n'appliquer que la variation réelle du montant compté
  IF TG_OP = 'UPDATE' AND OLD.customer_id IS DISTINCT FROM NEW.customer_id THEN
    IF OLD.customer_id IS NOT NULL AND v_old_counted <> 0 THEN
      UPDATE customers
        SET balance = COALESCE(balance, 0) + v_old_counted,
            credit_used = COALESCE(credit_used, 0) + v_old_counted,
            updated_at = NOW()
      WHERE id = OLD.customer_id AND tenant_id = OLD.tenant_id;
    END IF;
    v_old_counted := 0;
  END IF;

  IF NEW.customer_id IS NOT NULL AND v_new_counted - v_old_counted <> 0 THEN
    UPDATE customers
      SET balance = GREATEST(COALESCE(balance, 0) - (v_new_counted - v_old_counted), 0),
          credit_used = GREATEST(COALESCE(credit_used, 0) - (v_new_counted - v_old_counted), 0),
          updated_at = NOW()
    WHERE id = NEW.customer_id AND tenant_id = NEW.tenant_id;
  END IF;

  RETURN NEW;
END;
$function$;

-- ------------------------------------------------------------
-- LOT2-05 / LOT7-05 : contrôle d'équilibre
-- Les triggers FOR EACH STATEMENT de la 156 contrôlaient l'équilibre après
-- CHAQUE instruction INSERT de ligne : une écriture saisie ligne par ligne
-- (saisie, triggers de comptabilisation) était refusée dès la première ligne.
-- Règle retenue : le brouillard peut être déséquilibré ; l'équilibre est
-- exigé pour toute écriture non brouillard et au passage en 'posted'.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assert_journal_entries_balanced(p_entry_ids uuid[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT je.id, je.status,
           COALESCE(SUM(jl.debit), 0) AS total_debit,
           COALESCE(SUM(jl.credit), 0) AS total_credit
    FROM journal_entries je
    LEFT JOIN journal_lines jl ON jl.journal_id = je.id
    WHERE je.id = ANY (p_entry_ids)
    GROUP BY je.id, je.status
  LOOP
    IF r.status IS DISTINCT FROM 'draft' AND ABS(r.total_debit - r.total_credit) > 0.01 THEN
      RAISE EXCEPTION 'Écriture % non équilibrée : débit % ≠ crédit %', r.id, r.total_debit, r.total_credit;
    END IF;
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.check_journal_entry_balance_ins()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  PERFORM assert_journal_entries_balanced(ARRAY(SELECT DISTINCT journal_id FROM new_table));
  RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.check_journal_entry_balance_upd()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  PERFORM assert_journal_entries_balanced(ARRAY(
    SELECT journal_id FROM new_table UNION SELECT journal_id FROM old_table));
  RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.check_journal_entry_balance_del()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  PERFORM assert_journal_entries_balanced(ARRAY(SELECT DISTINCT journal_id FROM old_table));
  RETURN NULL;
END;
$function$;

-- Validation d'une écriture : refus si déséquilibrée ou vide
CREATE OR REPLACE FUNCTION public.check_journal_entry_balance_on_post()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_debit numeric;
  v_credit numeric;
BEGIN
  SELECT COALESCE(SUM(debit), 0), COALESCE(SUM(credit), 0)
  INTO v_debit, v_credit
  FROM journal_lines WHERE journal_id = NEW.id;

  IF v_debit = 0 AND v_credit = 0 THEN
    RAISE EXCEPTION 'Écriture % sans ligne : validation impossible', NEW.id;
  END IF;
  IF ABS(v_debit - v_credit) > 0.01 THEN
    RAISE EXCEPTION 'Écriture % non équilibrée : débit % ≠ crédit %', NEW.id, v_debit, v_credit;
  END IF;

  NEW.total_debit := v_debit;
  NEW.total_credit := v_credit;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS check_journal_entry_balance_on_post ON journal_entries;
CREATE TRIGGER check_journal_entry_balance_on_post
  BEFORE UPDATE OF status ON journal_entries
  FOR EACH ROW
  WHEN (NEW.status = 'posted' AND OLD.status IS DISTINCT FROM 'posted')
  EXECUTE FUNCTION check_journal_entry_balance_on_post();

-- ------------------------------------------------------------
-- Écriture de fin d'OF : les lignes 641 / 613 débitaient la main-d'œuvre et les
-- frais généraux sans contrepartie (écriture déséquilibrée dès que MO + FG ≠ 0)
-- et doublaient des charges déjà constatées. Elles sont retirées ; le coût complet
-- reste porté par 355 / 713550. Pas d'écriture si le coût est nul.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_stock_on_manufacturing_complete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_entry_id uuid;
  v_number text;
  v_existing uuid;
  v_cost jsonb;
  v_unit_cost numeric;
  v_cost_material numeric;
  v_cost_labor numeric;
  v_cost_overhead numeric;
  v_cost_total numeric;
  v_ordre int := 0;
  v_component RECORD;
  v_component_cost numeric;
BEGIN
  -- Ne traiter que la transition vers 'completed'
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'completed' THEN

    -- Calculer le coût de production
    v_cost := calculate_manufacturing_cost(NEW.id, NEW.tenant_id);
    IF (v_cost->>'success')::boolean THEN
      v_cost_material := (v_cost->>'cost_material')::numeric;
      v_cost_labor := (v_cost->>'cost_labor')::numeric;
      v_cost_overhead := (v_cost->>'cost_overhead')::numeric;
      v_cost_total := (v_cost->>'cost_total')::numeric;
      v_unit_cost := (v_cost->>'unit_cost')::numeric;
    ELSE
      v_unit_cost := 0;
      v_cost_total := 0;
    END IF;

    -- Mouvement d'entrée du produit fini AVEC unit_cost
    INSERT INTO stock_movements (
      tenant_id, product_id, warehouse_id, movement_type,
      quantity, unit_cost, reference, movement_date, reference_type
    ) VALUES (
      NEW.tenant_id, NEW.product_id, NEW.warehouse_id, 'in',
      NEW.quantity, v_unit_cost, NEW.number, CURRENT_DATE, 'production'
    );

    -- Sortie des composants du stock avec leur CUMP courant
    FOR v_component IN
      SELECT bl.product_id, bl.quantity * NEW.quantity AS qty,
             COALESCE(NULLIF(sq.unit_cost, 0), NULLIF(p.cost_price, 0), bl.unit_cost, 0) AS comp_cost
      FROM bom_lines bl
      JOIN products p ON p.id = bl.product_id AND p.tenant_id = NEW.tenant_id
      LEFT JOIN stock_quantities sq
        ON sq.product_id = bl.product_id
       AND sq.warehouse_id = NEW.warehouse_id
       AND sq.tenant_id = NEW.tenant_id
      WHERE bl.bom_id = NEW.bom_id AND bl.tenant_id = NEW.tenant_id
    LOOP
      v_component_cost := v_component.qty * v_component.comp_cost;

      INSERT INTO stock_movements (
        tenant_id, product_id, warehouse_id, movement_type,
        quantity, unit_cost, reference, movement_date, reference_type
      ) VALUES (
        NEW.tenant_id, v_component.product_id, NEW.warehouse_id, 'out',
        v_component.qty, v_component.comp_cost, NEW.number, CURRENT_DATE, 'production'
      );
    END LOOP;

    -- Écriture comptable de production
    v_number := 'JE-OF-' || NEW.number;
    SELECT id INTO v_existing FROM journal_entries
      WHERE tenant_id = NEW.tenant_id AND reference = v_number LIMIT 1;

    IF v_existing IS NULL AND COALESCE(v_cost_total, 0) > 0 THEN
      INSERT INTO journal_entries (
        tenant_id, number, date, journal_code, status,
        description, reference
      ) VALUES (
        NEW.tenant_id, v_number, CURRENT_DATE, 'OF', 'draft',
        'Production OF ' || NEW.number, v_number
      )
      RETURNING id INTO v_entry_id;

      -- Sortie des matières (débit 601, crédit 31x)
      IF v_cost_material > 0 THEN
        INSERT INTO journal_lines (
          tenant_id, journal_id, account_code, account_general,
          debit, credit, description, line_order
        ) VALUES (
          NEW.tenant_id, v_entry_id, '601000', '601000',
          v_cost_material, 0, 'Consommation matières — ' || NEW.number, v_ordre
        );
        v_ordre := v_ordre + 1;

        INSERT INTO journal_lines (
          tenant_id, journal_id, account_code, account_general,
          debit, credit, description, line_order
        ) VALUES (
          NEW.tenant_id, v_entry_id, '310000', '310000',
          0, v_cost_material, 'Sortie stock matières — ' || NEW.number, v_ordre
        );
        v_ordre := v_ordre + 1;
      END IF;

      -- Main-d'œuvre et frais généraux : déjà constatés en charges (paie, factures) ;
      -- ils sont absorbés dans la valeur du produit fini via 355 / 713, sans nouvelle charge.

      -- Entrée du produit fini (débit 355, crédit 71355 production stockée)
      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        debit, credit, description, line_order
      ) VALUES (
        NEW.tenant_id, v_entry_id, '355000', '355000',
        v_cost_total, 0, 'Entrée produit fini — ' || NEW.number, v_ordre
      );
      v_ordre := v_ordre + 1;

      INSERT INTO journal_lines (
        tenant_id, journal_id, account_code, account_general,
        debit, credit, description, line_order
      ) VALUES (
        NEW.tenant_id, v_entry_id, '713550', '713550',
        0, v_cost_total, 'Production stockée — ' || NEW.number, v_ordre
      );

      -- Bascule en 'posted' APRÈS les lignes (SOC-01)
      UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;
    END IF;

    -- Mettre à jour les quantités produites
    UPDATE manufacturing_orders
    SET qty_produced = NEW.quantity
    WHERE id = NEW.id AND tenant_id = NEW.tenant_id;
  END IF;

  RETURN NEW;
END;
$function$;

-- ------------------------------------------------------------
-- SOC-01 (régression) : create_journal_on_stock_movement (migration 101) créait
-- l'en-tête en 'posted' avant les lignes ; prevent_posted_line_modification
-- refusait alors toute ligne : AUCUN mouvement de stock valorisé ne passait
-- (réceptions, livraisons, inventaires). Motif draft → lignes → posted rétabli.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_journal_on_stock_movement()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_entry_id uuid;
  v_number text;
  v_amount numeric;
  v_product RECORD;
  v_stock_account text := '310000';
  v_variation_account text := '603000';
  v_existing uuid;
BEGIN
  -- Ne générer une écriture que si unit_cost est renseigné et > 0
  IF NEW.unit_cost IS NULL OR NEW.unit_cost <= 0 THEN
    RETURN NEW;
  END IF;

  -- Ne pas générer pour les transferts internes
  IF NEW.movement_type NOT IN ('in', 'out', 'adjustment') THEN
    RETURN NEW;
  END IF;

  v_amount := NEW.quantity * NEW.unit_cost;
  IF v_amount = 0 THEN RETURN NEW; END IF;

  -- Récupérer le produit pour d'éventuels comptes spécifiques
  SELECT * INTO v_product FROM products WHERE id = NEW.product_id AND tenant_id = NEW.tenant_id;

  -- Éviter les doublons : vérifier qu'une écriture n'existe pas déjà pour ce mouvement
  SELECT id INTO v_existing
  FROM journal_entries
  WHERE tenant_id = NEW.tenant_id
    AND piece_number = 'STK-' || NEW.id::text
  LIMIT 1;

  IF v_existing IS NOT NULL THEN RETURN NEW; END IF;

  v_number := 'JE-STK-' || to_char(NOW(), 'YYYYMMDDHH24MISS') || '-' || substr(NEW.id::text, 1, 8);

  -- Insérer l'entête
  INSERT INTO journal_entries (
    tenant_id, number, date, journal_code, status,
    description, piece_number, reference
  ) VALUES (
    NEW.tenant_id, v_number, COALESCE(NEW.movement_date, NEW.date, CURRENT_DATE),
    'ST', 'draft',
    'Mouvement de stock ' || COALESCE(NEW.reference, NEW.id::text),
    'STK-' || NEW.id::text,
    NEW.reference
  )
  RETURNING id INTO v_entry_id;

  -- Insérer les lignes selon le type de mouvement
  IF NEW.movement_type = 'in' THEN
    -- Entrée en stock : Débit 310 (stock) / Crédit 603 (variation)
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order, product_id, quantity
    ) VALUES
      (NEW.tenant_id, v_entry_id, v_stock_account, v_stock_account,
       v_amount, 0, 'Entrée en stock - ' || COALESCE(v_product.name, 'Produit'), 0,
       NEW.product_id, NEW.quantity),
      (NEW.tenant_id, v_entry_id, v_variation_account, v_variation_account,
       0, v_amount, 'Variation de stock (entrée) - ' || COALESCE(v_product.name, 'Produit'), 1,
       NEW.product_id, NEW.quantity);

  ELSIF NEW.movement_type = 'out' THEN
    -- Sortie de stock : Débit 603 (variation) / Crédit 310 (stock)
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order, product_id, quantity
    ) VALUES
      (NEW.tenant_id, v_entry_id, v_variation_account, v_variation_account,
       v_amount, 0, 'Variation de stock (sortie) - ' || COALESCE(v_product.name, 'Produit'), 0,
       NEW.product_id, NEW.quantity),
      (NEW.tenant_id, v_entry_id, v_stock_account, v_stock_account,
       0, v_amount, 'Sortie de stock - ' || COALESCE(v_product.name, 'Produit'), 1,
       NEW.product_id, NEW.quantity);

  ELSIF NEW.movement_type = 'adjustment' THEN
    -- Ajustement : Débit ou Crédit selon le sens de la variation
    -- Si quantity augmente → Débit 310 / Crédit 603
    -- Si quantity diminue → Débit 603 / Crédit 310
    -- (Pour un ajustement, on suppose que unit_cost représente la valeur unitaire)
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order, product_id, quantity
    ) VALUES
      (NEW.tenant_id, v_entry_id, v_stock_account, v_stock_account,
       v_amount, 0, 'Ajustement de stock (entrée) - ' || COALESCE(v_product.name, 'Produit'), 0,
       NEW.product_id, NEW.quantity),
      (NEW.tenant_id, v_entry_id, v_variation_account, v_variation_account,
       0, v_amount, 'Variation de stock (ajustement) - ' || COALESCE(v_product.name, 'Produit'), 1,
       NEW.product_id, NEW.quantity);
  END IF;

  -- Bascule en 'posted' APRÈS les lignes (SOC-01)
  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id;

  RETURN NEW;
END;
$function$;

-- ------------------------------------------------------------
-- Coût matière d'OF : un coût à 0 en stock ou sur la fiche article masquait le
-- coût standard de la nomenclature (bom_lines.unit_cost) → produit fini à 0.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.calculate_manufacturing_cost(p_mo_id uuid, p_tenant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_cost_material numeric := 0;
  v_cost_labor numeric := 0;
  v_cost_overhead numeric := 0;
  v_unit_cost numeric;
  v_quantity numeric;
  v_bom_id uuid;
  v_routing_id uuid;
  v_warehouse_id uuid;
  v_overhead_rate numeric := 0;
BEGIN
  SELECT mo.quantity, mo.bom_id, mo.routing_id, mo.warehouse_id
  INTO v_quantity, v_bom_id, v_routing_id, v_warehouse_id
  FROM manufacturing_orders mo
  WHERE mo.id = p_mo_id AND mo.tenant_id = p_tenant_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'OF introuvable');
  END IF;

  SELECT COALESCE(sum(bl.quantity * v_quantity
                    * COALESCE(NULLIF(sq.unit_cost, 0), NULLIF(p.cost_price, 0), bl.unit_cost, 0)), 0)
  INTO v_cost_material
  FROM bom_lines bl
  JOIN products p ON p.id = bl.product_id AND p.tenant_id = p_tenant_id
  LEFT JOIN stock_quantities sq
    ON sq.product_id = bl.product_id
   AND sq.warehouse_id = v_warehouse_id
   AND sq.tenant_id = p_tenant_id
  WHERE bl.bom_id = v_bom_id AND bl.tenant_id = p_tenant_id;

  -- Temps en minutes → heures
  SELECT COALESCE(sum((COALESCE(ro.setup_time_min, 0) + COALESCE(ro.run_time_min, 0) * v_quantity) / 60.0
                    * COALESCE(wc.cost_per_hour, 0)), 0)
  INTO v_cost_labor
  FROM routing_operations ro
  JOIN work_centers wc ON wc.id = ro.work_center_id AND wc.tenant_id = p_tenant_id
  WHERE ro.routing_id = v_routing_id AND ro.tenant_id = p_tenant_id;

  SELECT COALESCE(overhead_rate, 0) INTO v_overhead_rate
  FROM company_settings WHERE tenant_id = p_tenant_id LIMIT 1;

  v_cost_overhead := v_cost_labor * v_overhead_rate;
  v_unit_cost := (v_cost_material + v_cost_labor + v_cost_overhead)
                / NULLIF(v_quantity, 0);

  UPDATE manufacturing_orders
  SET cost_material = v_cost_material,
      cost_labor = v_cost_labor,
      cost_overhead = v_cost_overhead,
      cost_total = v_cost_material + v_cost_labor + v_cost_overhead,
      unit_cost = COALESCE(v_unit_cost, 0)
  WHERE id = p_mo_id AND tenant_id = p_tenant_id;

  RETURN jsonb_build_object(
    'success', true,
    'cost_material', v_cost_material,
    'cost_labor', v_cost_labor,
    'cost_overhead', v_cost_overhead,
    'cost_total', v_cost_material + v_cost_labor + v_cost_overhead,
    'unit_cost', COALESCE(v_unit_cost, 0)
  );
END;
$function$;
