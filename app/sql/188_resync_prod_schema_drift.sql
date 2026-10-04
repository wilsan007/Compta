-- ============================================================
-- 188_resync_prod_schema_drift.sql
-- Resynchronise la production avec l'état voulu par le dépôt.
--
-- Constat (répétition du 21/09/2026 sur une copie de la prod, PG 17.6) :
-- 115 des 142 migrations marquées « success » dans sql_migrations_tracker ont été
-- modifiées dans le dépôt APRÈS leur exécution en prod. Le runner ne suit que
-- les noms de fichiers : leurs nouvelles versions n'ont jamais été rejouées.
-- La prod diverge donc du schéma que la CI teste (00_schema_dump + migrations) :
-- 14 colonnes et 3 tables absentes, 37 fonctions, 25 triggers et 42 politiques
-- absents ou différents. Sans ce fichier, les migrations 136-187 cassent en prod
-- calculate_payslip (employees.withholding_tax_rate absent) et les triggers de
-- libération de stock (quantity_reserved supprimée par la 136).
--
-- Généré depuis une base CI rejouée jusqu'à 187 (la 187 passe avant ce fichier : ses fonctions ne sont pas touchées), pour les seuls
-- objets en écart. Hors périmètre : mirror_servers / mirror_verification_details
-- (tenant_id en text en prod, conversion à décider à part).
-- ============================================================

-- 1. Colonnes
ALTER TABLE public.bank_transactions ADD COLUMN IF NOT EXISTS bank_account_id uuid;
ALTER TABLE public.bank_transactions ADD COLUMN IF NOT EXISTS label text;
ALTER TABLE public.bank_transactions ADD COLUMN IF NOT EXISTS match_type text;
ALTER TABLE public.bank_transactions ADD COLUMN IF NOT EXISTS matched_account_code text;
ALTER TABLE public.bank_transactions ADD COLUMN IF NOT EXISTS matched_invoice_id uuid;
ALTER TABLE public.customer_payments ADD COLUMN IF NOT EXISTS invoice_number text;
ALTER TABLE public.employees ADD COLUMN IF NOT EXISTS withholding_rate_source text;
ALTER TABLE public.employees ADD COLUMN IF NOT EXISTS withholding_tax_rate numeric;
ALTER TABLE public.pos_sessions ADD COLUMN IF NOT EXISTS session_number text;
ALTER TABLE public.sales_orders ADD COLUMN IF NOT EXISTS credit_warning boolean DEFAULT false;
ALTER TABLE public.supplier_payments ADD COLUMN IF NOT EXISTS invoice_number text;
ALTER TABLE public.vat_returns ADD COLUMN IF NOT EXISTS vat_collected numeric DEFAULT 0;
ALTER TABLE public.vat_returns ADD COLUMN IF NOT EXISTS vat_deductible numeric DEFAULT 0;
ALTER TABLE public.vat_returns ADD COLUMN IF NOT EXISTS vat_to_pay numeric DEFAULT 0;
-- 1b. Contraintes
DO $$ BEGIN
  ALTER TABLE public.employees ADD CONSTRAINT employees_withholding_rate_source_check CHECK ((withholding_rate_source = ANY (ARRAY['dgfip'::text, 'neutral'::text, 'manual'::text])));
EXCEPTION WHEN duplicate_object OR duplicate_table OR invalid_table_definition THEN NULL;
END $$;
-- 1c. Index

-- 2. Tables absentes (migration 93 jamais réellement appliquée)
CREATE TABLE IF NOT EXISTS public.email_templates (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    template_key text NOT NULL,
    subject text NOT NULL,
    body_html text NOT NULL,
    body_text text,
    variables jsonb DEFAULT '[]'::jsonb NOT NULL,
    locale text DEFAULT 'fr'::text NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.email_templates FORCE ROW LEVEL SECURITY;

ALTER TABLE public.email_templates OWNER TO postgres;

CREATE TABLE IF NOT EXISTS public.notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    user_id uuid,
    category text NOT NULL,
    severity text DEFAULT 'info'::text NOT NULL,
    title text NOT NULL,
    message text NOT NULL,
    link text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    read_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.notifications FORCE ROW LEVEL SECURITY;

ALTER TABLE public.notifications OWNER TO postgres;

CREATE TABLE IF NOT EXISTS public.user_totp (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    secret_enc text NOT NULL,
    backup_codes jsonb DEFAULT '[]'::jsonb NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    enabled_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.user_totp FORCE ROW LEVEL SECURITY;

ALTER TABLE public.user_totp OWNER TO postgres;

DO $$ BEGIN
  ALTER TABLE ONLY public.email_templates
    ADD CONSTRAINT email_templates_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object OR duplicate_table OR invalid_table_definition THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object OR duplicate_table OR invalid_table_definition THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY public.user_totp
    ADD CONSTRAINT user_totp_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object OR duplicate_table OR invalid_table_definition THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_email_templates_tenant ON public.email_templates USING btree (tenant_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_email_templates_tenant_key_locale ON public.email_templates USING btree (tenant_id, template_key, locale);

CREATE INDEX IF NOT EXISTS idx_notifications_tenant_date ON public.notifications USING btree (tenant_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notifications_tenant_unread ON public.notifications USING btree (tenant_id, user_id, read_at) WHERE (read_at IS NULL);

CREATE INDEX IF NOT EXISTS idx_notifications_user ON public.notifications USING btree (user_id, read_at);

CREATE INDEX IF NOT EXISTS idx_user_totp_tenant ON public.user_totp USING btree (tenant_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_user_totp_user_tenant ON public.user_totp USING btree (user_id, tenant_id);

DO $$ BEGIN
  ALTER TABLE ONLY public.email_templates
    ADD CONSTRAINT email_templates_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR duplicate_table OR invalid_table_definition THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR duplicate_table OR invalid_table_definition THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY public.user_totp
    ADD CONSTRAINT user_totp_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR duplicate_table OR invalid_table_definition THEN NULL;
END $$;

ALTER TABLE public.email_templates ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tenant_delete_email_templates ON public.email_templates;
CREATE POLICY tenant_delete_email_templates ON public.email_templates FOR DELETE USING ((tenant_id = public.current_tenant_id()));

DROP POLICY IF EXISTS tenant_delete_notifications ON public.notifications;
CREATE POLICY tenant_delete_notifications ON public.notifications FOR DELETE USING ((tenant_id = public.current_tenant_id()));

DROP POLICY IF EXISTS tenant_delete_user_totp ON public.user_totp;
CREATE POLICY tenant_delete_user_totp ON public.user_totp FOR DELETE USING ((tenant_id = public.current_tenant_id()));

DROP POLICY IF EXISTS tenant_insert_email_templates ON public.email_templates;
CREATE POLICY tenant_insert_email_templates ON public.email_templates FOR INSERT WITH CHECK ((tenant_id = public.current_tenant_id()));

DROP POLICY IF EXISTS tenant_insert_notifications ON public.notifications;
CREATE POLICY tenant_insert_notifications ON public.notifications FOR INSERT WITH CHECK ((tenant_id = public.current_tenant_id()));

DROP POLICY IF EXISTS tenant_insert_user_totp ON public.user_totp;
CREATE POLICY tenant_insert_user_totp ON public.user_totp FOR INSERT WITH CHECK ((tenant_id = public.current_tenant_id()));

DROP POLICY IF EXISTS tenant_select_email_templates ON public.email_templates;
CREATE POLICY tenant_select_email_templates ON public.email_templates FOR SELECT USING ((tenant_id = public.current_tenant_id()));

DROP POLICY IF EXISTS tenant_select_notifications ON public.notifications;
CREATE POLICY tenant_select_notifications ON public.notifications FOR SELECT USING ((tenant_id = public.current_tenant_id()));

DROP POLICY IF EXISTS tenant_select_user_totp ON public.user_totp;
CREATE POLICY tenant_select_user_totp ON public.user_totp FOR SELECT USING ((tenant_id = public.current_tenant_id()));

DROP POLICY IF EXISTS tenant_update_email_templates ON public.email_templates;
CREATE POLICY tenant_update_email_templates ON public.email_templates FOR UPDATE USING ((tenant_id = public.current_tenant_id())) WITH CHECK ((tenant_id = public.current_tenant_id()));

DROP POLICY IF EXISTS tenant_update_notifications ON public.notifications;
CREATE POLICY tenant_update_notifications ON public.notifications FOR UPDATE USING ((tenant_id = public.current_tenant_id())) WITH CHECK ((tenant_id = public.current_tenant_id()));

DROP POLICY IF EXISTS tenant_update_user_totp ON public.user_totp;
CREATE POLICY tenant_update_user_totp ON public.user_totp FOR UPDATE USING ((tenant_id = public.current_tenant_id())) WITH CHECK ((tenant_id = public.current_tenant_id()));

ALTER TABLE public.user_totp ENABLE ROW LEVEL SECURITY;

GRANT ALL ON TABLE public.email_templates TO anon;

GRANT ALL ON TABLE public.email_templates TO authenticated;

GRANT ALL ON TABLE public.email_templates TO service_role;

GRANT ALL ON TABLE public.notifications TO anon;

GRANT ALL ON TABLE public.notifications TO authenticated;

GRANT ALL ON TABLE public.notifications TO service_role;

GRANT ALL ON TABLE public.user_totp TO anon;

GRANT ALL ON TABLE public.user_totp TO authenticated;

GRANT ALL ON TABLE public.user_totp TO service_role;

-- 3. Fonctions
CREATE OR REPLACE FUNCTION public.assign_pos_ticket_number_and_hash()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_last_number int := 0;
  v_last_hash text;
  v_hash_input text;
  v_grand_daily numeric := 0;
  v_grand_monthly numeric := 0;
  v_grand_yearly numeric := 0;
  v_grand_lifetime numeric := 0;
BEGIN
  -- Numéro séquentiel par terminal
  SELECT COALESCE(MAX(sequential_number), 0) INTO v_last_number
  FROM pos_tickets
  WHERE tenant_id = NEW.tenant_id AND terminal_id = NEW.terminal_id;

  NEW.sequential_number := v_last_number + 1;

  -- Récupérer le hash précédent
  SELECT ticket_hash INTO v_last_hash
  FROM pos_tickets
  WHERE tenant_id = NEW.tenant_id AND terminal_id = NEW.terminal_id
  ORDER BY sequential_number DESC
  LIMIT 1;

  NEW.previous_hash := v_last_hash;

  -- Calculer le hash : SHA256(données + hash précédent)
  v_hash_input := NEW.tenant_id || '|' || NEW.terminal_id || '|' ||
    NEW.sequential_number || '|' || NEW.total || '|' ||
    COALESCE(v_last_hash, '') || '|' || NEW.created_at;

  NEW.ticket_hash := encode(digest(v_hash_input, 'sha256'), 'hex');

  -- Cumuls perpétuels (jamais remis à zéro)
  SELECT COALESCE(SUM(total), 0) INTO v_grand_daily
  FROM pos_tickets
  WHERE tenant_id = NEW.tenant_id AND terminal_id = NEW.terminal_id
    AND DATE(created_at) = DATE(NEW.created_at);

  SELECT COALESCE(SUM(total), 0) INTO v_grand_monthly
  FROM pos_tickets
  WHERE tenant_id = NEW.tenant_id AND terminal_id = NEW.terminal_id
    AND DATE_TRUNC('month', created_at) = DATE_TRUNC('month', NEW.created_at);

  SELECT COALESCE(SUM(total), 0) INTO v_grand_yearly
  FROM pos_tickets
  WHERE tenant_id = NEW.tenant_id AND terminal_id = NEW.terminal_id
    AND DATE_TRUNC('year', created_at) = DATE_TRUNC('year', NEW.created_at);

  SELECT COALESCE(SUM(total), 0) INTO v_grand_lifetime
  FROM pos_tickets
  WHERE tenant_id = NEW.tenant_id AND terminal_id = NEW.terminal_id;

  NEW.grand_total_daily := v_grand_daily + NEW.total;
  NEW.grand_total_monthly := v_grand_monthly + NEW.total;
  NEW.grand_total_yearly := v_grand_yearly + NEW.total;
  NEW.grand_total_lifetime := v_grand_lifetime + NEW.total;

  -- Journaliser dans nf525_event_log via la fonction certifiée avec hash-chaining
  PERFORM log_nf525_event(
    'pos_ticket_created',
    'pos_ticket',
    NEW.id,
    jsonb_build_object(
      'terminal_id', NEW.terminal_id,
      'sequential_number', NEW.sequential_number,
      'total', NEW.total,
      'hash', NEW.ticket_hash,
      'previous_hash', NEW.previous_hash
    ),
    NULL,
    to_char(now(), 'YYYY-MM')
  );

  RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.auto_close_task_on_progress_100()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  -- Se déclenche quand le progress passe à 100
  IF NEW.progress = 100 AND (OLD.progress IS DISTINCT FROM 100 OR TG_OP = 'INSERT') THEN
    IF NEW.status NOT IN ('done', 'cancelled') THEN
      NEW.status := 'done';
      NEW.is_closed := true;
    END IF;
  ELSIF NEW.progress < 100 AND NEW.is_closed = true AND NEW.status = 'done' THEN
    -- Rouvrir si le progress redescend
    NEW.is_closed := false;
    NEW.status := 'in_progress';
  END IF;

  RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.auto_reach_milestone_on_tasks_done()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_milestone_id uuid;
  v_total integer;
  v_done integer;
BEGIN
  -- Déterminer le jalon concerné
  v_milestone_id := COALESCE(NEW.milestone_id, OLD.milestone_id);
  IF v_milestone_id IS NULL THEN RETURN NEW; END IF;

  -- Compter les tâches liées à ce jalon
  SELECT
    COUNT(*),
    COUNT(*) FILTER (WHERE status IN ('done', 'cancelled') OR is_closed = true)
  INTO v_total, v_done
  FROM project_tasks
  WHERE milestone_id = v_milestone_id;

  -- Si toutes les tâches du jalon sont terminées
  IF v_total > 0 AND v_done = v_total THEN
    UPDATE project_milestones
      SET is_reached = true,
          is_reached_manually = false,
          updated_at = now()
    WHERE id = v_milestone_id AND is_reached = false;
  ELSIF v_done < v_total THEN
    -- Rouvrir le jalon si une tâche revient en arrière
    UPDATE project_milestones
      SET is_reached = false,
          updated_at = now()
    WHERE id = v_milestone_id AND is_reached = true AND is_reached_manually = false;
  END IF;

  RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.can_perform(p_table text, p_action text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
  SELECT CASE
    WHEN current_user_role() = 'admin' THEN true
    WHEN current_user_role() = 'accountant' AND p_action IN ('select', 'insert', 'update') THEN true
    WHEN current_user_role() = 'accountant' AND p_action = 'delete' AND p_table IN ('journal_entries', 'journal_lines', 'invoice_lines', 'quote_lines', 'credit_note_lines') THEN true
    WHEN current_user_role() = 'manager' AND p_action = 'select' THEN true
    WHEN current_user_role() = 'manager' AND p_action IN ('insert', 'update') AND p_table IN ('invoices', 'invoice_lines', 'quotes', 'quote_lines', 'credit_notes', 'credit_note_lines', 'customers', 'products', 'delivery_notes', 'delivery_note_lines', 'sales_orders', 'sales_order_lines', 'purchase_orders', 'purchase_order_lines') THEN true
    WHEN current_user_role() = 'viewer' AND p_action = 'select' THEN true
    WHEN current_user_role() = 'auditor' AND p_action = 'select' THEN true
    WHEN current_user_role() = 'custom' THEN
      COALESCE(
        (current_user_permissions() -> p_table ->> p_action)::boolean,
        false
      )
    ELSE false
  END
$function$
;
CREATE OR REPLACE FUNCTION public.check_customer_credit_limit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_limit numeric;
  v_outstanding numeric;
  v_policy text;
BEGIN
  -- Ne vérifier que lors du passage à 'confirmed'
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status <> 'confirmed' THEN
    RETURN NEW;
  END IF;

  -- Récupérer la limite et la politique
  SELECT COALESCE(credit_limit, 0), COALESCE(credit_policy, 'blocking')
  INTO v_limit, v_policy
  FROM customers
  WHERE id = NEW.customer_id AND tenant_id = NEW.tenant_id;

  -- 0 = pas de plafond
  IF v_limit <= 0 THEN
    RETURN NEW;
  END IF;

  -- Encours = factures non soldées + commandes confirmées non facturées
  SELECT COALESCE(SUM(amount_due), 0)
  INTO v_outstanding
  FROM invoices
  WHERE customer_id = NEW.customer_id
    AND tenant_id = NEW.tenant_id
    AND payment_state IN ('not_paid', 'partial');

  -- Ajouter les commandes confirmées non facturées
  v_outstanding := v_outstanding + COALESCE((
    SELECT SUM(total)
    FROM sales_orders
    WHERE customer_id = NEW.customer_id
      AND tenant_id = NEW.tenant_id
      AND status = 'confirmed'
      AND id <> NEW.id
  ), 0);

  -- Vérifier le dépassement
  IF v_outstanding + NEW.total > v_limit THEN
    IF v_policy = 'blocking' THEN
      RAISE EXCEPTION
        'Encours dépassé : % + % > limite % — validation requise',
        v_outstanding, NEW.total, v_limit;
    ELSIF v_policy = 'warning' THEN
      -- Marquer la commande avec un avertissement mais ne pas bloquer
      NEW.credit_warning := true;
    END IF;
  END IF;

  -- Mettre à jour l'encours utilisé
  UPDATE customers
  SET credit_used = v_outstanding + NEW.total,
    updated_at = now()
  WHERE id = NEW.customer_id AND tenant_id = NEW.tenant_id;

  RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.check_journal_entry_balance()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_total_debit numeric;
  v_total_credit numeric;
  v_entry_id uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_entry_id := OLD.journal_id;
  ELSE
    v_entry_id := NEW.journal_id;
  END IF;

  SELECT COALESCE(SUM(debit), 0), COALESCE(SUM(credit), 0)
  INTO v_total_debit, v_total_credit
  FROM journal_lines
  WHERE journal_id = v_entry_id;

  -- Tolérance de 0.01 pour les arrondis
  IF ABS(v_total_debit - v_total_credit) > 0.01 THEN
    RAISE EXCEPTION 'Écriture déséquilibrée: débit=%, crédit=% (écart=%)',
      v_total_debit, v_total_credit, ABS(v_total_debit - v_total_credit);
  END IF;

  -- Au moins une ligne avec un montant > 0
  IF v_total_debit = 0 AND v_total_credit = 0 THEN
    RAISE EXCEPTION 'Écriture vide: aucun montant sur les lignes';
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.check_task_dependencies_before_start()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_dep RECORD;
  v_blocked boolean := false;
  v_blocked_names text;
BEGIN
  -- Se déclenche quand une tâche passe à 'in_progress'
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'in_progress' THEN
    -- Vérifier les dépendances finish-to-start
    v_blocked_names := '';
    FOR v_dep IN
      SELECT pt.title, pt.status, ptd.dependency_type
      FROM project_task_dependencies ptd
      JOIN project_tasks pt ON pt.id = ptd.depends_on_task_id
      WHERE ptd.task_id = NEW.id
        AND ptd.tenant_id = NEW.tenant_id
        AND ptd.dependency_type = 'finish-to-start'
        AND pt.status NOT IN ('done', 'cancelled')
    LOOP
      v_blocked := true;
      v_blocked_names := v_blocked_names || '- ' || v_dep.title || ' (statut: ' || v_dep.status || ')' || E'\n';
    END LOOP;

    IF v_blocked THEN
      -- Créer une notification d'alerte pour l'assigné
      IF NEW.assignee_id IS NOT NULL THEN
        INSERT INTO project_notifications (
          tenant_id, recipient_id, task_id, project_id,
          notification_type, title, message, action_url
        ) VALUES (
          NEW.tenant_id, NEW.assignee_id, NEW.id, NEW.project_id,
          'dependency_blocked',
          'Dépendances non terminées',
          'La tâche ''' || NEW.title || ''' a des dépendances non terminées :' || E'\n' || v_blocked_names,
          '/projects/tasks/' || NEW.id
        );
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.create_billable_line_on_timesheet_stop()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_project RECORD;
  v_customer_id uuid;
  v_hours numeric;
  v_amount numeric;
BEGIN
  -- Se déclenche quand end_time passe de NULL à une valeur, et is_billable = true
  IF NEW.is_billable = false THEN RETURN NEW; END IF;
  IF NEW.end_time IS NULL THEN RETURN NEW; END IF;
  IF OLD.end_time IS NOT NULL THEN RETURN NEW; END IF;

  -- Récupérer le projet et son client
  SELECT * INTO v_project
  FROM projects
  WHERE id = COALESCE(NEW.project_id, (
    SELECT project_id FROM project_tasks WHERE id = NEW.task_id
  ));

  IF NOT FOUND OR v_project.customer_id IS NULL THEN RETURN NEW; END IF;
  IF v_project.allow_billable = false THEN RETURN NEW; END IF;

  v_customer_id := v_project.customer_id;
  v_hours := ROUND(NEW.duration_seconds::numeric / 3600, 2);
  v_amount := v_hours * COALESCE(NEW.hourly_rate, 0);

  -- Créer une ligne de devis/facturation en attente
  -- On utilise la table quotes si elle existe, sinon on crée une notification
  -- pour informer qu'il y a des heures à facturer
  INSERT INTO project_notifications (
    tenant_id, recipient_id, task_id, project_id,
    notification_type, title, message, action_url
  ) SELECT
    NEW.tenant_id,
    p.manager_id,
    NEW.task_id,
    v_project.id,
    'billable_hours',
    'Heures facturables à facturer',
    v_hours::text || 'h facturables (' || v_amount::text || '€) sur le projet ''' || v_project.name || '''',
    '/projects/' || v_project.id
  FROM projects p
  WHERE p.id = v_project.id AND p.manager_id IS NOT NULL;

  RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.create_journal_on_customer_payment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_entry_id uuid;
  v_number text;
  v_collectif text := '411000';
  v_tiers text;
  v_third_party uuid;
BEGIN
  -- ACC-01 : récupérer les infos du client directement ou via la facture
  IF NEW.customer_id IS NOT NULL THEN
    SELECT account_collectif, account_tiers, id
    INTO v_collectif, v_tiers, v_third_party
    FROM customers
    WHERE id = NEW.customer_id AND tenant_id = NEW.tenant_id;
  ELSIF NEW.invoice_id IS NOT NULL THEN
    SELECT c.account_collectif, c.account_tiers, c.id
    INTO v_collectif, v_tiers, v_third_party
    FROM customers c
    JOIN invoices i ON i.customer_id = c.id AND i.tenant_id = c.tenant_id
    WHERE i.id = NEW.invoice_id AND i.tenant_id = NEW.tenant_id;
  END IF;

  v_number := 'JE-CP-' || NEW.number;
  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, piece_number)
  VALUES (NEW.tenant_id, v_number, NEW.payment_date, 'BQ', 'draft', 'Encaissement ' || NEW.number, v_number)
  RETURNING id INTO v_entry_id;

  INSERT INTO journal_lines (
    tenant_id, journal_id, account_code, account_general,
    account_tiers, third_party_id,
    debit, credit, description, line_order
  ) VALUES
    (New.tenant_id, v_entry_id, '512000', '512000',
     NULL, NULL,
     NEW.amount, 0, 'Banque ' || NEW.number, 0),
    (New.tenant_id, v_entry_id, v_collectif, v_collectif,
     v_tiers, v_third_party,
     0, NEW.amount, 'Client ' || NEW.number, 1);

  -- Bascule en 'posted' APRÈS les lignes (SOC-01)
  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;
  UPDATE customer_payments SET transferred_entry_id = v_entry_id WHERE id = NEW.id AND tenant_id = NEW.tenant_id;
  RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.create_journal_on_supplier_payment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_entry_id uuid;
  v_number text;
  v_collectif text := '401000';
  v_tiers text;
  v_third_party uuid;
BEGIN
  -- ACC-01 : récupérer les infos du fournisseur directement ou via la facture d'achat
  IF NEW.supplier_id IS NOT NULL THEN
    SELECT account_collectif, account_tiers, id
    INTO v_collectif, v_tiers, v_third_party
    FROM suppliers
    WHERE id = NEW.supplier_id AND tenant_id = NEW.tenant_id;
  ELSIF NEW.purchase_invoice_id IS NOT NULL THEN
    SELECT s.account_collectif, s.account_tiers, s.id
    INTO v_collectif, v_tiers, v_third_party
    FROM suppliers s
    JOIN purchase_invoices pi ON pi.supplier_id = s.id AND pi.tenant_id = s.tenant_id
    WHERE pi.id = NEW.purchase_invoice_id AND pi.tenant_id = NEW.tenant_id;
  END IF;

  v_number := 'JE-SP-' || NEW.number;
  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, piece_number)
  VALUES (NEW.tenant_id, v_number, NEW.payment_date, 'BQ', 'draft', 'Décaissement ' || NEW.number, v_number)
  RETURNING id INTO v_entry_id;

  INSERT INTO journal_lines (
    tenant_id, journal_id, account_code, account_general,
    account_tiers, third_party_id,
    debit, credit, description, line_order
  ) VALUES
    (New.tenant_id, v_entry_id, v_collectif, v_collectif,
     v_tiers, v_third_party,
     NEW.amount, 0, 'Fournisseur ' || NEW.number, 0),
    (New.tenant_id, v_entry_id, '512000', '512000',
     NULL, NULL,
     0, NEW.amount, 'Banque ' || NEW.number, 1);

  -- Bascule en 'posted' APRÈS les lignes (SOC-01)
  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;
  UPDATE supplier_payments SET transferred_entry_id = v_entry_id WHERE id = NEW.id AND tenant_id = NEW.tenant_id;
  RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.create_notification(p_category text, p_title text, p_message text, p_user_id uuid DEFAULT NULL::uuid, p_severity text DEFAULT 'info'::text, p_link text DEFAULT NULL::text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_id uuid;
  v_tenant uuid := current_tenant_id();
BEGIN
  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  INSERT INTO notifications (tenant_id, user_id, category, severity, title, message, link, metadata)
  VALUES (v_tenant, p_user_id, p_category, p_severity, p_title, p_message, p_link, p_metadata)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.current_tenant_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
  SELECT c.tid
  FROM (
    -- prio 1 : en-tête x-tenant-id (transmis par PostgREST)
    SELECT 1 AS prio,
           NULLIF(
             current_setting('request.headers', true)::json->>'x-tenant-id',
             ''
           )::uuid AS tid
    UNION ALL
    -- prio 2 : GUC de session (set_config via set_active_tenant)
    SELECT 2 AS prio,
           NULLIF(current_setting('app.active_tenant_id', true), '')::uuid AS tid
  ) c
  WHERE c.tid IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM tenant_users
      WHERE auth_id = auth.uid()
        AND status = 'active'
        AND tenant_id = c.tid
    )
  ORDER BY c.prio
  LIMIT 1
$function$
;
CREATE OR REPLACE FUNCTION public.escalate_overdue_tasks()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_task RECORD;
  v_manager_id uuid;
BEGIN
  -- Trouver les tâches en retard de plus de 3 jours
  FOR v_task IN
    SELECT t.*, p.manager_id as project_manager_id
    FROM project_tasks t
    LEFT JOIN projects p ON p.id = t.project_id
    WHERE t.due_date < CURRENT_DATE - 3
      AND t.status NOT IN ('done', 'cancelled')
      AND t.is_closed = false
  LOOP
    v_manager_id := COALESCE(v_task.project_manager_id, v_task.assignee_id);
    IF v_manager_id IS NULL THEN CONTINUE; END IF;

    -- Vérifier qu'une notification d'escalade n'a pas déjà été envoyée
    IF NOT EXISTS (
      SELECT 1 FROM project_notifications
      WHERE task_id = v_task.id
        AND notification_type = 'task_escalated'
        AND created_at >= CURRENT_DATE - 3
    ) THEN
      INSERT INTO project_notifications (
        tenant_id, recipient_id, task_id, project_id,
        notification_type, title, message, action_url
      ) VALUES (
        v_task.tenant_id, v_manager_id, v_task.id, v_task.project_id,
        'task_escalated',
        'ESCALADE : Tâche en retard de plus de 3 jours',
        'La tâche ''' || v_task.title || ''' est en retard de ' ||
        (CURRENT_DATE - v_task.due_date)::text || ' jours et nécessite une attention immédiate.',
        '/projects/tasks/' || v_task.id
      );
    END IF;
  END LOOP;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.explode_bom_recursive(p_tenant_id uuid, p_bom_id uuid, p_quantity numeric, p_max_level integer DEFAULT 15)
 RETURNS TABLE(product_id uuid, gross_need numeric, low_level_code integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH RECURSIVE explosion AS (
    -- Niveau 0 : les composants directs de la nomenclature
    SELECT
      bl.product_id,
      bl.quantity * p_quantity * (1 + COALESCE(bl.scrap_rate, 0)) AS qty,
      0 AS level
    FROM bom_lines bl
    WHERE bl.bom_id = p_bom_id AND bl.tenant_id = p_tenant_id

    UNION ALL

    -- Niveau n+1 : éclater les composants qui ont eux-mêmes une nomenclature
    SELECT
      bl.product_id,
      e.qty * (bl.quantity / COALESCE(NULLIF(b.quantity, 0), 1)) * (1 + COALESCE(bl.scrap_rate, 0)),
      e.level + 1
    FROM explosion e
    JOIN boms b ON b.product_id = e.product_id AND b.tenant_id = p_tenant_id AND b.active = true
    JOIN bom_lines bl ON bl.bom_id = b.id AND bl.tenant_id = p_tenant_id
    WHERE e.level < p_max_level
  )
  SELECT explosion.product_id, sum(explosion.qty) AS gross_need, max(explosion.level) AS low_level_code
  FROM explosion
  GROUP BY explosion.product_id
  ORDER BY low_level_code;
$function$
;
CREATE OR REPLACE FUNCTION public.fec_export(p_tenant_id uuid, p_start_date date, p_end_date date, p_offset integer DEFAULT 0, p_limit integer DEFAULT 1000)
 RETURNS TABLE(journal_code text, entry_number text, entry_date date, account_code text, account_label text, description text, debit numeric, credit numeric, piece_number text)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    je.journal_code::text,
    je.number::text,
    je.date,
    jl.account_code::text,
    COALESCE(ja.name, '')::text,
    COALESCE(jl.description, '')::text,
    jl.debit,
    jl.credit,
    COALESCE(je.piece_number, je.number)::text
  FROM journal_entries je
  JOIN journal_lines jl ON jl.journal_id = je.id AND jl.tenant_id = je.tenant_id
  LEFT JOIN chart_accounts ja ON ja.code = jl.account_code AND ja.tenant_id = je.tenant_id
  WHERE je.tenant_id = p_tenant_id
    AND je.status = 'posted'
    AND je.date >= p_start_date
    AND je.date <= p_end_date
  ORDER BY je.date, je.journal_code, je.number, jl.line_order
  OFFSET p_offset
  LIMIT p_limit;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.fec_export(p_start_date date, p_end_date date, p_offset integer DEFAULT 0, p_limit integer DEFAULT 1000)
 RETURNS TABLE(journal_code text, entry_number text, entry_date date, account_code text, account_label text, description text, debit numeric, credit numeric, piece_number text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_tid uuid := current_tenant_id();
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  RETURN QUERY
  SELECT
    je.journal_code::text,
    je.number::text,
    je.date,
    jl.account_code::text,
    COALESCE(ja.name, '')::text,
    COALESCE(jl.description, '')::text,
    jl.debit,
    jl.credit,
    COALESCE(je.piece_number, je.number)::text
  FROM journal_entries je
  JOIN journal_lines jl ON jl.journal_id = je.id AND jl.tenant_id = je.tenant_id
  LEFT JOIN chart_accounts ja ON ja.code = jl.account_code AND ja.tenant_id = je.tenant_id
  WHERE je.tenant_id = v_tid
    AND je.status = 'posted'
    AND je.date >= p_start_date
    AND je.date <= p_end_date
  ORDER BY je.date, je.journal_code, je.number, jl.line_order
  OFFSET p_offset
  LIMIT p_limit;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.generate_recurring_entry(p_entry_id uuid, p_tenant_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_tid uuid := COALESCE(p_tenant_id, current_tenant_id());
  v_source journal_entries%ROWTYPE;
  v_source_lines journal_lines[] := ARRAY[]::journal_lines[];
  v_new_id uuid;
  v_line journal_lines%ROWTYPE;
  v_new_date date;
  v_number text;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- Charger l'écriture source
  SELECT * INTO v_source FROM journal_entries WHERE id = p_entry_id AND tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Écriture source % non trouvée', p_entry_id;
  END IF;

  -- Calculer la nouvelle date (un mois plus tard)
  v_new_date := (v_source.date + INTERVAL '1 month')::date;

  -- Générer un nouveau numéro
  v_number := get_next_piece_number(v_source.journal_code);

  -- Créer la nouvelle écriture
  INSERT INTO journal_entries (
    tenant_id, number, date, journal_code, status,
    description, invoice_ref
  ) VALUES (
    v_tid, v_number, v_new_date, v_source.journal_code,
    'draft',
    '[Récurrent] ' || COALESCE(v_source.description, ''),
    v_source.invoice_ref
  )
  RETURNING id INTO v_new_id;

  -- Copier les lignes
  FOR v_line IN
    SELECT * FROM journal_lines WHERE journal_id = p_entry_id AND tenant_id = v_tid
  LOOP
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order
    ) VALUES (
      v_tid, v_new_id, v_line.account_code, v_line.account_general,
      v_line.debit, v_line.credit, v_line.description, v_line.line_order
    );
  END LOOP;

  RETURN jsonb_build_object('success', true, 'new_entry_id', v_new_id, 'number', v_number);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$function$
;
CREATE OR REPLACE FUNCTION public.get_journal_entry_count(p_tenant_id uuid, p_start_date date DEFAULT NULL::date, p_end_date date DEFAULT NULL::date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_count integer;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM journal_entries je
  WHERE je.tenant_id = p_tenant_id
    AND je.status IN ('posted', 'draft')
    AND (p_start_date IS NULL OR je.date >= p_start_date)
    AND (p_end_date IS NULL OR je.date <= p_end_date);
  RETURN v_count;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.get_journal_entry_count(p_start_date date DEFAULT NULL::date, p_end_date date DEFAULT NULL::date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_count integer;
  v_tid uuid := current_tenant_id();
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM journal_entries je
  WHERE je.tenant_id = v_tid
    AND je.status IN ('posted', 'draft')
    AND (p_start_date IS NULL OR je.date >= p_start_date)
    AND (p_end_date IS NULL OR je.date <= p_end_date);
  RETURN v_count;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.get_unread_notification_count(p_user_id uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_count integer;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM notifications
  WHERE read_at IS NULL
    AND tenant_id = current_tenant_id()
    AND (p_user_id IS NULL OR user_id = p_user_id OR user_id IS NULL);

  RETURN v_count;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.mark_all_notifications_read(p_user_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  UPDATE notifications
  SET read_at = now()
  WHERE read_at IS NULL
    AND tenant_id = current_tenant_id()
    AND (p_user_id IS NULL OR user_id = p_user_id OR user_id IS NULL);
END;
$function$
;
CREATE OR REPLACE FUNCTION public.mark_notification_read(p_notification_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  UPDATE notifications
  SET read_at = now()
  WHERE id = p_notification_id
    AND tenant_id = current_tenant_id();
END;
$function$
;
CREATE OR REPLACE FUNCTION public.notify_assignee_on_assignment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  -- Se déclenche quand assignee_id change (et n'est pas NULL)
  IF NEW.assignee_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.assignee_id IS NOT DISTINCT FROM OLD.assignee_id THEN RETURN NEW; END IF;

  INSERT INTO project_notifications (
    tenant_id, recipient_id, task_id, project_id,
    notification_type, title, message, action_url
  ) VALUES (
    NEW.tenant_id, NEW.assignee_id, NEW.id, NEW.project_id,
    'task_assigned',
    'Tâche assignée : ' || NEW.title,
    'Vous avez été assigné(e) à la tâche ''' || NEW.title || '''',
    '/projects/tasks/' || NEW.id
  );

  RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.notify_bank_reconciliation_needed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_curr text;
BEGIN
  v_curr := COALESCE(NEW.original_currency, 'EUR');

  IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND NEW.reconciled = false AND OLD.reconciled = true) THEN
    PERFORM create_notification(
      'banking',
      'Transaction bancaire à rapprocher',
      'Une nouvelle transaction bancaire de ' || NEW.amount || ' ' || v_curr || ' nécessite un rapprochement.',
      NULL, 'info',
      '/bank-reconciliation'
    );
  END IF;
  RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.notify_invoice_overdue()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.status = 'sent' AND NEW.due_date < now() AND OLD.due_date >= now() THEN
    PERFORM create_notification(
      'sales',
      'Facture en retard de paiement',
      'La facture ' || NEW.number || ' est maintenant en retard de paiement (échéance: ' || NEW.due_date::date || ')',
      NULL, 'warning',
      '/invoices/' || NEW.id
    );
  END IF;
  RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.notify_overdue_tasks()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_task RECORD;
BEGIN
  -- Trouver toutes les tâches en retard (due_date < today, non terminées)
  FOR v_task IN
    SELECT * FROM project_tasks
    WHERE due_date < CURRENT_DATE
      AND status NOT IN ('done', 'cancelled')
      AND is_closed = false
      AND assignee_id IS NOT NULL
  LOOP
    -- Vérifier qu'une notification n'a pas déjà été envoyée aujourd'hui
    IF NOT EXISTS (
      SELECT 1 FROM project_notifications
      WHERE task_id = v_task.id
        AND notification_type = 'task_overdue'
        AND created_at >= CURRENT_DATE
    ) THEN
      INSERT INTO project_notifications (
        tenant_id, recipient_id, task_id, project_id,
        notification_type, title, message, action_url
      ) VALUES (
        v_task.tenant_id, v_task.assignee_id, v_task.id, v_task.project_id,
        'task_overdue',
        'Tâche en retard : ' || v_task.title,
        'La tâche ''' || v_task.title || ''' était due le ' || to_char(v_task.due_date, 'DD/MM/YYYY'),
        '/projects/tasks/' || v_task.id
      );
    END IF;
  END LOOP;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.notify_payslip_ready()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.status = 'draft' AND (OLD.status IS NULL OR OLD.status <> 'draft') THEN
    PERFORM create_notification(
      'hr',
      'Bulletin de paie disponible',
      'Votre bulletin de paie de ' || to_char(NEW.period_start, 'MM/YYYY') || ' est disponible.',
      NEW.employee_id, 'info',
      '/pay-slips/' || NEW.id
    );
  END IF;
  RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.notify_watchers_on_comment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_watcher RECORD;
  v_task RECORD;
BEGIN
  -- Récupérer les infos de la tâche
  SELECT * INTO v_task
  FROM project_tasks
  WHERE id = NEW.task_id;

  IF NOT FOUND THEN RETURN NEW; END IF;

  -- Notifier tous les watchers
  FOR v_watcher IN
    SELECT employee_id FROM project_task_watchers
    WHERE task_id = NEW.task_id AND tenant_id = NEW.tenant_id
  LOOP
    INSERT INTO project_notifications (
      tenant_id, recipient_id, task_id, project_id,
      notification_type, title, message, action_url
    ) VALUES (
      NEW.tenant_id, v_watcher.employee_id, NEW.task_id, v_task.project_id,
      'comment_added',
      'Nouveau commentaire sur : ' || v_task.title,
      LEFT(NEW.content, 200),
      '/projects/tasks/' || NEW.task_id
    );
  END LOOP;

  RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.notify_watchers_on_status_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_watcher RECORD;
BEGIN
  -- Se déclenche quand le statut change
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN RETURN NEW; END IF;

  -- Notifier tous les watchers de la tâche
  FOR v_watcher IN
    SELECT employee_id FROM project_task_watchers
    WHERE task_id = NEW.id AND tenant_id = NEW.tenant_id
  LOOP
    -- Ne pas notifier l'assigné (il a déjà la notification d'assignation)
    IF v_watcher.employee_id IS DISTINCT FROM NEW.assignee_id THEN
      INSERT INTO project_notifications (
        tenant_id, recipient_id, task_id, project_id,
        notification_type, title, message, action_url
      ) VALUES (
        NEW.tenant_id, v_watcher.employee_id, NEW.id, NEW.project_id,
        'status_changed',
        'Statut modifié : ' || NEW.title,
        'Le statut de ''' || NEW.title || ''' est passé de ''' || COALESCE(OLD.status, 'aucun') || ''' à ''' || NEW.status || '''',
        '/projects/tasks/' || NEW.id
      );
    END IF;
  END LOOP;

  RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.prevent_posted_entry_modification()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- Une écriture validée (posted) ne peut être ni modifiée ni supprimée
  -- L'annulation passe par generateExtourne (création d'une écriture inverse)
  IF (TG_OP = 'DELETE') THEN
    IF OLD.status = 'posted' THEN
      RAISE EXCEPTION 'Écriture % est validée (posted) — immuable. Utiliser l''extourne pour annuler.', OLD.id;
    END IF;
    RETURN OLD;
  END IF;
  -- TG_OP = 'UPDATE'
  IF OLD.status = 'posted' THEN
    RAISE EXCEPTION 'Écriture % est validée (posted) — immuable. Utiliser l''extourne pour annuler.', OLD.id;
  END IF;
  RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.recalc_project_progress_on_task_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_project_id uuid;
  v_avg_progress integer;
  v_count integer;
BEGIN
  -- Déterminer le projet concerné
  v_project_id := COALESCE(NEW.project_id, OLD.project_id);
  IF v_project_id IS NULL THEN RETURN NEW; END IF;

  -- Calculer la moyenne du progress des tâches de premier niveau du projet
  SELECT
    COALESCE(AVG(progress), 0)::integer,
    COUNT(*)
  INTO v_avg_progress, v_count
  FROM project_tasks
  WHERE project_id = v_project_id
    AND parent_id IS NULL;

  -- Mettre à jour le projet
  UPDATE projects
    SET progress = v_avg_progress,
        updated_at = now()
  WHERE id = v_project_id;

  RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.recalc_task_progress_on_action_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_task_id uuid;
  v_total_weight integer;
  v_done_weight integer;
  v_total_actions integer;
  v_done_actions integer;
  v_new_progress integer;
BEGIN
  v_task_id := COALESCE(NEW.task_id, OLD.task_id);
  IF v_task_id IS NULL THEN RETURN NEW; END IF;

  -- Calculer le progress basé sur les actions pondérées
  SELECT
    COALESCE(SUM(weight_percentage), 0),
    COALESCE(SUM(weight_percentage) FILTER (WHERE is_done = true), 0),
    COUNT(*),
    COUNT(*) FILTER (WHERE is_done = true)
  INTO v_total_weight, v_done_weight, v_total_actions, v_done_actions
  FROM task_actions
  WHERE task_id = v_task_id;

  IF v_total_actions = 0 THEN
    v_new_progress := 0;
  ELSIF v_total_weight > 0 THEN
    v_new_progress := LEAST(100, ROUND((v_done_weight::numeric / v_total_weight) * 100));
  ELSE
    -- Sans pondération : ratio simple
    v_new_progress := ROUND((v_done_actions::numeric / v_total_actions) * 100);
  END IF;

  -- Mettre à jour la tâche (le trigger auto_close_on_progress gèrera le statut)
  UPDATE project_tasks
    SET progress = v_new_progress,
        updated_at = now()
  WHERE id = v_task_id;

  RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.release_stock_on_delivery()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_reservation RECORD;
BEGIN
  IF NEW.status = 'delivered' AND OLD.status IS DISTINCT FROM 'delivered' THEN
    FOR v_reservation IN
      SELECT * FROM stock_reservations
      WHERE reference_id = NEW.id AND tenant_id = NEW.tenant_id AND status = 'active'
    LOOP
      -- STK-02b : Libérer la quantité réservée pour le bon dépôt
      UPDATE stock_quantities
      SET reserved_quantity = GREATEST(0, reserved_quantity - v_reservation.quantity),
        updated_at = now()
      WHERE tenant_id = NEW.tenant_id
        AND product_id = v_reservation.product_id
        AND (v_reservation.warehouse_id IS NULL OR warehouse_id = v_reservation.warehouse_id);

      UPDATE stock_reservations
      SET status = 'fulfilled', updated_at = now()
      WHERE id = v_reservation.id;
    END LOOP;
  END IF;
  RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.release_stock_on_sales_order_cancel()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_reservation record;
BEGIN
  IF NEW.status = 'cancelled' AND OLD.status = 'confirmed' THEN
    FOR v_reservation IN
      SELECT * FROM stock_reservations
      WHERE reference_id = NEW.id AND tenant_id = NEW.tenant_id AND status = 'active'
    LOOP
      -- STK-02c : Libérer uniquement pour le dépôt de la réservation
      UPDATE stock_quantities
      SET reserved_quantity = GREATEST(0, reserved_quantity - v_reservation.quantity),
        updated_at = now()
      WHERE tenant_id = NEW.tenant_id
        AND product_id = v_reservation.product_id
        AND (v_reservation.warehouse_id IS NULL OR warehouse_id = v_reservation.warehouse_id);

      UPDATE stock_reservations
      SET status = 'released', updated_at = now()
      WHERE id = v_reservation.id;
    END LOOP;
  END IF;
  RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.update_project_hours_on_time_entry()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_project_id uuid;
  v_total_seconds integer;
  v_total_hours numeric;
  v_allocated numeric;
BEGIN
  -- Déterminer le projet (soit via l'entrée, soit via la tâche)
  v_project_id := COALESCE(NEW.project_id, OLD.project_id);
  IF v_project_id IS NULL AND COALESCE(NEW.task_id, OLD.task_id) IS NOT NULL THEN
    SELECT project_id INTO v_project_id
    FROM project_tasks
    WHERE id = COALESCE(NEW.task_id, OLD.task_id);
  END IF;
  IF v_project_id IS NULL THEN RETURN NEW; END IF;

  -- Sommer les durées de toutes les feuilles de temps de ce projet
  SELECT COALESCE(SUM(duration_seconds), 0)
  INTO v_total_seconds
  FROM project_time_entries
  WHERE project_id = v_project_id;

  v_total_hours := ROUND((v_total_seconds::numeric / 3600), 2);

  -- Récupérer les heures allouées
  SELECT allocated_hours INTO v_allocated
  FROM projects WHERE id = v_project_id;

  -- Mettre à jour le projet
  UPDATE projects
    SET total_hours_spent = v_total_hours,
        remaining_hours = GREATEST(COALESCE(v_allocated, 0) - v_total_hours, 0),
        updated_at = now()
  WHERE id = v_project_id;

  RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.update_task_time_on_time_entry()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_task_id uuid;
  v_total_seconds integer;
  v_total_hours numeric;
BEGIN
  v_task_id := COALESCE(NEW.task_id, OLD.task_id);
  IF v_task_id IS NULL THEN RETURN NEW; END IF;

  -- Sommer les durées de toutes les feuilles de temps de cette tâche
  SELECT COALESCE(SUM(duration_seconds), 0)
  INTO v_total_seconds
  FROM project_time_entries
  WHERE task_id = v_task_id;

  v_total_hours := ROUND((v_total_seconds::numeric / 3600), 2);

  -- Mettre à jour la tâche
  UPDATE project_tasks
    SET effort_spent_h = v_total_hours,
        updated_at = now()
  WHERE id = v_task_id;

  RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.validate_stock_movement_type()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.movement_type NOT IN ('in', 'out', 'transfer', 'adjustment', 'initial') THEN
    RAISE EXCEPTION 'Type de mouvement de stock invalide : % — valeurs admises : in, out, transfer, adjustment, initial', NEW.movement_type;
  END IF;
  RETURN NEW;
END;
$function$
;
-- 4. Triggers
DROP TRIGGER IF EXISTS bank_accounts_updated_at ON public.bank_accounts;
CREATE TRIGGER bank_accounts_updated_at BEFORE UPDATE ON public.bank_accounts FOR EACH STATEMENT EXECUTE FUNCTION public.update_updated_at();
DROP TRIGGER IF EXISTS company_settings_updated_at ON public.company_settings;
CREATE TRIGGER company_settings_updated_at BEFORE UPDATE ON public.company_settings FOR EACH STATEMENT EXECUTE FUNCTION public.update_updated_at();
DROP TRIGGER IF EXISTS customers_updated_at ON public.customers;
CREATE TRIGGER customers_updated_at BEFORE UPDATE ON public.customers FOR EACH STATEMENT EXECUTE FUNCTION public.update_updated_at();
DROP TRIGGER IF EXISTS invoices_updated_at ON public.invoices;
CREATE TRIGGER invoices_updated_at BEFORE UPDATE ON public.invoices FOR EACH STATEMENT EXECUTE FUNCTION public.update_updated_at();
DROP TRIGGER IF EXISTS journal_entries_updated_at ON public.journal_entries;
CREATE TRIGGER journal_entries_updated_at BEFORE UPDATE ON public.journal_entries FOR EACH STATEMENT EXECUTE FUNCTION public.update_updated_at();
DROP TRIGGER IF EXISTS prevent_posted_line_modification ON public.journal_lines;
CREATE TRIGGER prevent_posted_line_modification BEFORE INSERT OR DELETE OR UPDATE ON public.journal_lines FOR EACH ROW EXECUTE FUNCTION public.prevent_posted_line_modification();
DROP TRIGGER IF EXISTS products_updated_at ON public.products;
CREATE TRIGGER products_updated_at BEFORE UPDATE ON public.products FOR EACH STATEMENT EXECUTE FUNCTION public.update_updated_at();
DROP TRIGGER IF EXISTS projects_updated_at ON public.projects;
CREATE TRIGGER projects_updated_at BEFORE UPDATE ON public.projects FOR EACH STATEMENT EXECUTE FUNCTION public.update_updated_at();
DROP TRIGGER IF EXISTS purchase_invoices_updated_at ON public.purchase_invoices;
CREATE TRIGGER purchase_invoices_updated_at BEFORE UPDATE ON public.purchase_invoices FOR EACH STATEMENT EXECUTE FUNCTION public.update_updated_at();
DROP TRIGGER IF EXISTS revoke_expired_auditors ON public.tenant_users;
CREATE TRIGGER revoke_expired_auditors AFTER INSERT OR UPDATE ON public.tenant_users FOR EACH STATEMENT EXECUTE FUNCTION public.trigger_revoke_expired_auditors();
DROP TRIGGER IF EXISTS set_tenant_id_analytic_distribution_lines ON public.analytic_distribution_lines;
CREATE TRIGGER set_tenant_id_analytic_distribution_lines BEFORE INSERT ON public.analytic_distribution_lines FOR EACH STATEMENT EXECUTE FUNCTION public.set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_bank_connections ON public.bank_connections;
CREATE TRIGGER set_tenant_id_bank_connections BEFORE INSERT ON public.bank_connections FOR EACH STATEMENT EXECUTE FUNCTION public.set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_employee_activity_logs ON public.employee_activity_logs;
CREATE TRIGGER set_tenant_id_employee_activity_logs BEFORE INSERT ON public.employee_activity_logs FOR EACH ROW EXECUTE FUNCTION public.set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_of_document_access ON public.of_document_access;
CREATE TRIGGER set_tenant_id_of_document_access BEFORE INSERT ON public.of_document_access FOR EACH STATEMENT EXECUTE FUNCTION public.set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_product_equivalences ON public.product_equivalences;
CREATE TRIGGER set_tenant_id_product_equivalences BEFORE INSERT ON public.product_equivalences FOR EACH STATEMENT EXECUTE FUNCTION public.set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_public_holidays ON public.public_holidays;
CREATE TRIGGER set_tenant_id_public_holidays BEFORE INSERT ON public.public_holidays FOR EACH STATEMENT EXECUTE FUNCTION public.set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_rh_dashboard_configs ON public.rh_dashboard_configs;
CREATE TRIGGER set_tenant_id_rh_dashboard_configs BEFORE INSERT ON public.rh_dashboard_configs FOR EACH ROW EXECUTE FUNCTION public.set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_rh_reports ON public.rh_reports;
CREATE TRIGGER set_tenant_id_rh_reports BEFORE INSERT ON public.rh_reports FOR EACH ROW EXECUTE FUNCTION public.set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_users ON public.users;
CREATE TRIGGER set_tenant_id_users BEFORE INSERT ON public.users FOR EACH STATEMENT EXECUTE FUNCTION public.set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_workflows ON public.workflows;
CREATE TRIGGER set_tenant_id_workflows BEFORE INSERT ON public.workflows FOR EACH STATEMENT EXECUTE FUNCTION public.set_tenant_id();
DROP TRIGGER IF EXISTS suppliers_updated_at ON public.suppliers;
CREATE TRIGGER suppliers_updated_at BEFORE UPDATE ON public.suppliers FOR EACH STATEMENT EXECUTE FUNCTION public.update_updated_at();
DROP TRIGGER IF EXISTS trigger_bank_recon_needed ON public.bank_transactions;
CREATE TRIGGER trigger_bank_recon_needed AFTER INSERT OR UPDATE ON public.bank_transactions FOR EACH ROW WHEN ((new.reconciled = false)) EXECUTE FUNCTION public.notify_bank_reconciliation_needed();
DROP TRIGGER IF EXISTS trigger_invoice_overdue ON public.invoices;
CREATE TRIGGER trigger_invoice_overdue AFTER UPDATE ON public.invoices FOR EACH ROW EXECUTE FUNCTION public.notify_invoice_overdue();
DROP TRIGGER IF EXISTS trigger_payslip_ready ON public.pay_slips;
CREATE TRIGGER trigger_payslip_ready AFTER INSERT OR UPDATE ON public.pay_slips FOR EACH ROW EXECUTE FUNCTION public.notify_payslip_ready();
DROP TRIGGER IF EXISTS users_updated_at ON public.users;
CREATE TRIGGER users_updated_at BEFORE UPDATE ON public.users FOR EACH STATEMENT EXECUTE FUNCTION public.update_updated_at();
-- 5. Politiques
DROP POLICY IF EXISTS tenant_delete_crm_campaign_recipients ON public.crm_campaign_recipients;
CREATE POLICY tenant_delete_crm_campaign_recipients ON public.crm_campaign_recipients AS PERMISSIVE FOR DELETE TO public USING ((EXISTS ( SELECT 1
   FROM public.crm_campaigns p
  WHERE ((p.id = crm_campaign_recipients.campaign_id) AND (p.tenant_id = public.current_tenant_id())))));
DROP POLICY IF EXISTS tenant_delete_distribution_grill_lines ON public.distribution_grill_lines;
CREATE POLICY tenant_delete_distribution_grill_lines ON public.distribution_grill_lines AS PERMISSIVE FOR DELETE TO public USING ((EXISTS ( SELECT 1
   FROM public.distribution_grills p
  WHERE ((p.id = distribution_grill_lines.grill_id) AND (p.tenant_id = public.current_tenant_id())))));
DROP POLICY IF EXISTS tenant_delete_employee_activity_logs ON public.employee_activity_logs;
CREATE POLICY tenant_delete_employee_activity_logs ON public.employee_activity_logs AS PERMISSIVE FOR DELETE TO public USING ((tenant_id = public.current_tenant_id()));
DROP POLICY IF EXISTS tenant_delete_invoice_lines ON public.invoice_lines;
CREATE POLICY tenant_delete_invoice_lines ON public.invoice_lines AS PERMISSIVE FOR DELETE TO public USING ((EXISTS ( SELECT 1
   FROM public.invoices p
  WHERE ((p.id = invoice_lines.invoice_id) AND (p.tenant_id = public.current_tenant_id())))));
DROP POLICY IF EXISTS tenant_delete_notification_email_queue ON public.notification_email_queue;
CREATE POLICY tenant_delete_notification_email_queue ON public.notification_email_queue AS PERMISSIVE FOR DELETE TO public USING ((tenant_id = public.current_tenant_id()));
DROP POLICY IF EXISTS tenant_delete_notification_preferences ON public.notification_preferences;
CREATE POLICY tenant_delete_notification_preferences ON public.notification_preferences AS PERMISSIVE FOR DELETE TO public USING ((tenant_id = public.current_tenant_id()));
DROP POLICY IF EXISTS tenant_delete_pick_list_lines ON public.pick_list_lines;
CREATE POLICY tenant_delete_pick_list_lines ON public.pick_list_lines AS PERMISSIVE FOR DELETE TO public USING ((EXISTS ( SELECT 1
   FROM public.pick_lists p
  WHERE ((p.id = pick_list_lines.pick_list_id) AND (p.tenant_id = public.current_tenant_id())))));
DROP POLICY IF EXISTS tenant_delete_purchase_request_lines ON public.purchase_request_lines;
CREATE POLICY tenant_delete_purchase_request_lines ON public.purchase_request_lines AS PERMISSIVE FOR DELETE TO public USING ((EXISTS ( SELECT 1
   FROM public.purchase_requests p
  WHERE ((p.id = purchase_request_lines.purchase_request_id) AND (p.tenant_id = public.current_tenant_id())))));
DROP POLICY IF EXISTS tenant_delete_rh_dashboard_configs ON public.rh_dashboard_configs;
CREATE POLICY tenant_delete_rh_dashboard_configs ON public.rh_dashboard_configs AS PERMISSIVE FOR DELETE TO public USING ((tenant_id = public.current_tenant_id()));
DROP POLICY IF EXISTS tenant_delete_rh_reports ON public.rh_reports;
CREATE POLICY tenant_delete_rh_reports ON public.rh_reports AS PERMISSIVE FOR DELETE TO public USING ((tenant_id = public.current_tenant_id()));
DROP POLICY IF EXISTS tenant_delete_service_ticket_messages ON public.service_ticket_messages;
CREATE POLICY tenant_delete_service_ticket_messages ON public.service_ticket_messages AS PERMISSIVE FOR DELETE TO public USING ((EXISTS ( SELECT 1
   FROM public.service_tickets p
  WHERE ((p.id = service_ticket_messages.ticket_id) AND (p.tenant_id = public.current_tenant_id())))));
DROP POLICY IF EXISTS tenant_insert_crm_campaign_recipients ON public.crm_campaign_recipients;
CREATE POLICY tenant_insert_crm_campaign_recipients ON public.crm_campaign_recipients AS PERMISSIVE FOR INSERT TO public WITH CHECK ((EXISTS ( SELECT 1
   FROM public.crm_campaigns p
  WHERE ((p.id = crm_campaign_recipients.campaign_id) AND (p.tenant_id = public.current_tenant_id())))));
DROP POLICY IF EXISTS tenant_insert_distribution_grill_lines ON public.distribution_grill_lines;
CREATE POLICY tenant_insert_distribution_grill_lines ON public.distribution_grill_lines AS PERMISSIVE FOR INSERT TO public WITH CHECK ((EXISTS ( SELECT 1
   FROM public.distribution_grills p
  WHERE ((p.id = distribution_grill_lines.grill_id) AND (p.tenant_id = public.current_tenant_id())))));
DROP POLICY IF EXISTS tenant_insert_employee_activity_logs ON public.employee_activity_logs;
CREATE POLICY tenant_insert_employee_activity_logs ON public.employee_activity_logs AS PERMISSIVE FOR INSERT TO public WITH CHECK ((tenant_id = public.current_tenant_id()));
DROP POLICY IF EXISTS tenant_insert_invoice_lines ON public.invoice_lines;
CREATE POLICY tenant_insert_invoice_lines ON public.invoice_lines AS PERMISSIVE FOR INSERT TO public WITH CHECK ((EXISTS ( SELECT 1
   FROM public.invoices p
  WHERE ((p.id = invoice_lines.invoice_id) AND (p.tenant_id = public.current_tenant_id())))));
DROP POLICY IF EXISTS tenant_insert_notification_email_queue ON public.notification_email_queue;
CREATE POLICY tenant_insert_notification_email_queue ON public.notification_email_queue AS PERMISSIVE FOR INSERT TO public WITH CHECK ((tenant_id = public.current_tenant_id()));
DROP POLICY IF EXISTS tenant_insert_notification_preferences ON public.notification_preferences;
CREATE POLICY tenant_insert_notification_preferences ON public.notification_preferences AS PERMISSIVE FOR INSERT TO public WITH CHECK ((tenant_id = public.current_tenant_id()));
DROP POLICY IF EXISTS tenant_insert_pick_list_lines ON public.pick_list_lines;
CREATE POLICY tenant_insert_pick_list_lines ON public.pick_list_lines AS PERMISSIVE FOR INSERT TO public WITH CHECK ((EXISTS ( SELECT 1
   FROM public.pick_lists p
  WHERE ((p.id = pick_list_lines.pick_list_id) AND (p.tenant_id = public.current_tenant_id())))));
DROP POLICY IF EXISTS tenant_insert_purchase_request_lines ON public.purchase_request_lines;
CREATE POLICY tenant_insert_purchase_request_lines ON public.purchase_request_lines AS PERMISSIVE FOR INSERT TO public WITH CHECK ((EXISTS ( SELECT 1
   FROM public.purchase_requests p
  WHERE ((p.id = purchase_request_lines.purchase_request_id) AND (p.tenant_id = public.current_tenant_id())))));
DROP POLICY IF EXISTS tenant_insert_rh_dashboard_configs ON public.rh_dashboard_configs;
CREATE POLICY tenant_insert_rh_dashboard_configs ON public.rh_dashboard_configs AS PERMISSIVE FOR INSERT TO public WITH CHECK ((tenant_id = public.current_tenant_id()));
DROP POLICY IF EXISTS tenant_insert_rh_reports ON public.rh_reports;
CREATE POLICY tenant_insert_rh_reports ON public.rh_reports AS PERMISSIVE FOR INSERT TO public WITH CHECK ((tenant_id = public.current_tenant_id()));
DROP POLICY IF EXISTS tenant_insert_service_ticket_messages ON public.service_ticket_messages;
CREATE POLICY tenant_insert_service_ticket_messages ON public.service_ticket_messages AS PERMISSIVE FOR INSERT TO public WITH CHECK ((EXISTS ( SELECT 1
   FROM public.service_tickets p
  WHERE ((p.id = service_ticket_messages.ticket_id) AND (p.tenant_id = public.current_tenant_id())))));
DROP POLICY IF EXISTS tenant_select_crm_campaign_recipients ON public.crm_campaign_recipients;
CREATE POLICY tenant_select_crm_campaign_recipients ON public.crm_campaign_recipients AS PERMISSIVE FOR SELECT TO public USING ((EXISTS ( SELECT 1
   FROM public.crm_campaigns p
  WHERE ((p.id = crm_campaign_recipients.campaign_id) AND (p.tenant_id = public.current_tenant_id())))));
DROP POLICY IF EXISTS tenant_select_distribution_grill_lines ON public.distribution_grill_lines;
CREATE POLICY tenant_select_distribution_grill_lines ON public.distribution_grill_lines AS PERMISSIVE FOR SELECT TO public USING ((EXISTS ( SELECT 1
   FROM public.distribution_grills p
  WHERE ((p.id = distribution_grill_lines.grill_id) AND (p.tenant_id = public.current_tenant_id())))));
DROP POLICY IF EXISTS tenant_select_invoice_lines ON public.invoice_lines;
CREATE POLICY tenant_select_invoice_lines ON public.invoice_lines AS PERMISSIVE FOR SELECT TO public USING ((EXISTS ( SELECT 1
   FROM public.invoices p
  WHERE ((p.id = invoice_lines.invoice_id) AND (p.tenant_id = public.current_tenant_id())))));
DROP POLICY IF EXISTS tenant_select_notification_email_queue ON public.notification_email_queue;
CREATE POLICY tenant_select_notification_email_queue ON public.notification_email_queue AS PERMISSIVE FOR SELECT TO public USING (((tenant_id = public.current_tenant_id()) OR (tenant_id IS NULL)));
DROP POLICY IF EXISTS tenant_select_notification_preferences ON public.notification_preferences;
CREATE POLICY tenant_select_notification_preferences ON public.notification_preferences AS PERMISSIVE FOR SELECT TO public USING (((tenant_id = public.current_tenant_id()) OR (tenant_id IS NULL)));
DROP POLICY IF EXISTS tenant_select_pick_list_lines ON public.pick_list_lines;
CREATE POLICY tenant_select_pick_list_lines ON public.pick_list_lines AS PERMISSIVE FOR SELECT TO public USING ((EXISTS ( SELECT 1
   FROM public.pick_lists p
  WHERE ((p.id = pick_list_lines.pick_list_id) AND (p.tenant_id = public.current_tenant_id())))));
DROP POLICY IF EXISTS tenant_select_purchase_request_lines ON public.purchase_request_lines;
CREATE POLICY tenant_select_purchase_request_lines ON public.purchase_request_lines AS PERMISSIVE FOR SELECT TO public USING ((EXISTS ( SELECT 1
   FROM public.purchase_requests p
  WHERE ((p.id = purchase_request_lines.purchase_request_id) AND (p.tenant_id = public.current_tenant_id())))));
DROP POLICY IF EXISTS tenant_select_service_ticket_messages ON public.service_ticket_messages;
CREATE POLICY tenant_select_service_ticket_messages ON public.service_ticket_messages AS PERMISSIVE FOR SELECT TO public USING ((EXISTS ( SELECT 1
   FROM public.service_tickets p
  WHERE ((p.id = service_ticket_messages.ticket_id) AND (p.tenant_id = public.current_tenant_id())))));
DROP POLICY IF EXISTS tenant_select_users ON public.users;
CREATE POLICY tenant_select_users ON public.users AS PERMISSIVE FOR SELECT TO public USING (((tenant_id = public.current_tenant_id()) OR (tenant_id IS NULL)));
DROP POLICY IF EXISTS tenant_update_crm_campaign_recipients ON public.crm_campaign_recipients;
CREATE POLICY tenant_update_crm_campaign_recipients ON public.crm_campaign_recipients AS PERMISSIVE FOR UPDATE TO public USING ((EXISTS ( SELECT 1
   FROM public.crm_campaigns p
  WHERE ((p.id = crm_campaign_recipients.campaign_id) AND (p.tenant_id = public.current_tenant_id()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.crm_campaigns p
  WHERE ((p.id = crm_campaign_recipients.campaign_id) AND (p.tenant_id = public.current_tenant_id())))));
DROP POLICY IF EXISTS tenant_update_distribution_grill_lines ON public.distribution_grill_lines;
CREATE POLICY tenant_update_distribution_grill_lines ON public.distribution_grill_lines AS PERMISSIVE FOR UPDATE TO public USING ((EXISTS ( SELECT 1
   FROM public.distribution_grills p
  WHERE ((p.id = distribution_grill_lines.grill_id) AND (p.tenant_id = public.current_tenant_id()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.distribution_grills p
  WHERE ((p.id = distribution_grill_lines.grill_id) AND (p.tenant_id = public.current_tenant_id())))));
DROP POLICY IF EXISTS tenant_update_employee_activity_logs ON public.employee_activity_logs;
CREATE POLICY tenant_update_employee_activity_logs ON public.employee_activity_logs AS PERMISSIVE FOR UPDATE TO public USING ((tenant_id = public.current_tenant_id())) WITH CHECK ((tenant_id = public.current_tenant_id()));
DROP POLICY IF EXISTS tenant_update_invoice_lines ON public.invoice_lines;
CREATE POLICY tenant_update_invoice_lines ON public.invoice_lines AS PERMISSIVE FOR UPDATE TO public USING ((EXISTS ( SELECT 1
   FROM public.invoices p
  WHERE ((p.id = invoice_lines.invoice_id) AND (p.tenant_id = public.current_tenant_id()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.invoices p
  WHERE ((p.id = invoice_lines.invoice_id) AND (p.tenant_id = public.current_tenant_id())))));
DROP POLICY IF EXISTS tenant_update_notification_email_queue ON public.notification_email_queue;
CREATE POLICY tenant_update_notification_email_queue ON public.notification_email_queue AS PERMISSIVE FOR UPDATE TO public USING ((tenant_id = public.current_tenant_id())) WITH CHECK ((tenant_id = public.current_tenant_id()));
DROP POLICY IF EXISTS tenant_update_notification_preferences ON public.notification_preferences;
CREATE POLICY tenant_update_notification_preferences ON public.notification_preferences AS PERMISSIVE FOR UPDATE TO public USING ((tenant_id = public.current_tenant_id())) WITH CHECK ((tenant_id = public.current_tenant_id()));
DROP POLICY IF EXISTS tenant_update_pick_list_lines ON public.pick_list_lines;
CREATE POLICY tenant_update_pick_list_lines ON public.pick_list_lines AS PERMISSIVE FOR UPDATE TO public USING ((EXISTS ( SELECT 1
   FROM public.pick_lists p
  WHERE ((p.id = pick_list_lines.pick_list_id) AND (p.tenant_id = public.current_tenant_id()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.pick_lists p
  WHERE ((p.id = pick_list_lines.pick_list_id) AND (p.tenant_id = public.current_tenant_id())))));
DROP POLICY IF EXISTS tenant_update_purchase_request_lines ON public.purchase_request_lines;
CREATE POLICY tenant_update_purchase_request_lines ON public.purchase_request_lines AS PERMISSIVE FOR UPDATE TO public USING ((EXISTS ( SELECT 1
   FROM public.purchase_requests p
  WHERE ((p.id = purchase_request_lines.purchase_request_id) AND (p.tenant_id = public.current_tenant_id()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.purchase_requests p
  WHERE ((p.id = purchase_request_lines.purchase_request_id) AND (p.tenant_id = public.current_tenant_id())))));
DROP POLICY IF EXISTS tenant_update_rh_dashboard_configs ON public.rh_dashboard_configs;
CREATE POLICY tenant_update_rh_dashboard_configs ON public.rh_dashboard_configs AS PERMISSIVE FOR UPDATE TO public USING ((tenant_id = public.current_tenant_id())) WITH CHECK ((tenant_id = public.current_tenant_id()));
DROP POLICY IF EXISTS tenant_update_rh_reports ON public.rh_reports;
CREATE POLICY tenant_update_rh_reports ON public.rh_reports AS PERMISSIVE FOR UPDATE TO public USING ((tenant_id = public.current_tenant_id())) WITH CHECK ((tenant_id = public.current_tenant_id()));
DROP POLICY IF EXISTS tenant_update_service_ticket_messages ON public.service_ticket_messages;
CREATE POLICY tenant_update_service_ticket_messages ON public.service_ticket_messages AS PERMISSIVE FOR UPDATE TO public USING ((EXISTS ( SELECT 1
   FROM public.service_tickets p
  WHERE ((p.id = service_ticket_messages.ticket_id) AND (p.tenant_id = public.current_tenant_id()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.service_tickets p
  WHERE ((p.id = service_ticket_messages.ticket_id) AND (p.tenant_id = public.current_tenant_id())))));

-- 6. pgcrypto est dans le schéma « extensions » sur Supabase (la CI l'installe dans
--    public, ce qui masquait le défaut) : toute fonction à search_path figé qui appelle
--    digest()/gen_random_bytes()... échoue. Cas avéré : log_nf525_event, appelé par le
--    trigger nf525_entry_post à chaque changement de statut d'écriture.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    WHERE p.pronamespace = 'public'::regnamespace
      AND p.prosrc ~ '\m(digest|hmac|gen_random_bytes|gen_random_uuid_v7|crypt|gen_salt|pgp_[a-z_]+|armor|dearmor)\s*\('
      AND EXISTS (SELECT 1 FROM unnest(p.proconfig) c
                  WHERE c LIKE 'search_path=%' AND c NOT LIKE '%extensions%')
  LOOP
    EXECUTE format('ALTER FUNCTION %s SET search_path = public, extensions, pg_temp', r.sig);
  END LOOP;
END $$;
