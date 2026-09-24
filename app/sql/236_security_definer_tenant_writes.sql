-- ============================================================
-- 236_security_definer_tenant_writes.sql — ISO-01 : écrire chez le voisin
--
-- CONSTAT, rejoué sous le vrai rôle `authenticated` (sql/236_..._tests.sql,
-- 17 scénarios) : les déclencheurs `SECURITY DEFINER` écrivaient dans la société
-- de la ligne VISÉE, jamais dans celle du mouvement. `SECURITY DEFINER` contourne
-- la RLS : la société B était modifiable par la société A, qui ne la voit même
-- pas en lecture. Mesuré AVANT ce correctif :
--
--   T01 rouge — la sous-tâche de A rattachée à une tâche de B passe B en « done »
--   T04 rouge — l'avancement du projet de B passe de 0 à 50
--   T05 rouge — le jalon de B est déclaré atteint par une tâche de A
--   T11 rouge — l'avancement de la tâche de B passe à 100 par une action de A
--   T12 rouge — la connexion d'un utilisateur de A révoque l'auditeur expiré de B
--   T14 rouge — A remet en file les envois de webhook de B
--   T16 rouge — A purge les enregistrements d'idempotence de B
--   T02 rouge au registre — la RÉFÉRENCE inter-sociétés reste possible (ISO-02)
--
-- LA LISTE, MESURÉE ET NON RÉCITÉE. L'audit du 23/09 nommait treize fonctions
-- « et les quatre `*_lines_refresh_totals` ». Le relevé sur le schéma
-- (`pg_proc.prosrc` confronté aux tables portant `tenant_id`) en trouve **dix-huit** :
-- les six déclencheurs de projets, les deux de temps passé, les cinq
-- rafraîchissements de totaux (invoice, credit_note, purchase_invoice,
-- purchase_credit, quote), `refresh_draft_entry_totals` (appelée par les
-- déclencheurs d'équilibre des écritures), et les quatre fonctions d'entretien
-- appelées par l'application ou par pg_cron (`auto_revoke_expired_auditors`,
-- `cleanup_expired_idempotency`, `process_webhook_queue`,
-- `requeue_stale_webhook_deliveries`).
-- Deux noms de l'audit demandent une correction : `notify_assignee_on_assignment`
-- n'écrit pas dans une table cloisonnée (`project_notifications` ne porte pas
-- `tenant_id`), donc rien à filtrer. Et `trigger_revoke_expired_auditors`
-- **existe** : c'est un déclencheur de `tenant_users` qui délègue à
-- `auto_revoke_expired_auditors`. Le détecteur ne l'avait pas vu parce qu'il ne
-- nomme aucune table cloisonnée — un angle mort qu'il faut connaître : le filet
-- de la CI attrape les écritures DIRECTES, pas les délégations. Les scénarios
-- couvrent les deux, parce qu'ils mesurent l'effet et non le texte.
--
-- LE CORRECTIF, uniforme : la société de l'écriture est celle du MOUVEMENT
-- (`COALESCE(NEW.tenant_id, OLD.tenant_id)`), et elle entre dans le `WHERE` de
-- chaque `UPDATE`, dans les `SELECT` qui comptent ou qui somment, et dans les
-- jointures. Les agrégats de totaux portent le couple `(id, tenant_id)` de la
-- ligne modifiée : la somme ne mélange plus les sociétés.
-- Les fonctions d'entretien, elles, sont globales par nature (le cron n'a pas de
-- contexte) : elles reçoivent la même clause sous la forme
-- `(current_tenant_id() IS NULL OR tenant_id = current_tenant_id())` — un
-- utilisateur connecté n'agit que chez lui, le cron agit sur tout.
--
-- CE QUE CE CORRECTIF NE FAIT PAS. Il empêche l'ÉCRITURE chez le voisin, pas la
-- RÉFÉRENCE à une ligne du voisin : une facture de A peut toujours désigner un
-- client de B (ISO-02, 189 tables, clés étrangères composites — vague 237). Et
-- `service_role`, qui contourne la RLS par construction, reste à surveiller par
-- les gardes de fonction (227) et non par la RLS.
--
-- ANTI-DÉRIVE. `ci/check_tenant_guard.sql` gagne une seconde règle, lue sur
-- `pg_proc.prosrc` : toute fonction `SECURITY DEFINER` qui écrit dans une table
-- portant `tenant_id` doit nommer `tenant_id` (ou `current_tenant_id()`). Vingt
-- lignes de SQL, et cette classe de défaut n'aurait jamais existé. Le contrôle
-- est un filet, pas une démonstration : les tests 236 restent la preuve.
-- ============================================================

-- ── 1. Les six déclencheurs de projets ────────────────────────────────────


CREATE OR REPLACE FUNCTION public.update_parent_status_on_subtasks_done()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_parent_id uuid;
  v_tenant uuid;
  v_total integer;
  v_done integer;
  v_parent_status varchar;
BEGIN
  v_parent_id := COALESCE(NEW.parent_id, OLD.parent_id);
  IF v_parent_id IS NULL THEN RETURN NEW; END IF;

  -- ISO-01 : la société du mouvement. Un parent d'une autre société n'est ni
  -- compté (les sous-tâches sont filtrées), ni lu, ni modifié.
  v_tenant := COALESCE(NEW.tenant_id, OLD.tenant_id);
  IF v_tenant IS NULL THEN RETURN NEW; END IF;

  SELECT
    COUNT(*),
    COUNT(*) FILTER (WHERE status IN ('done', 'cancelled') OR is_closed = true)
  INTO v_total, v_done
  FROM project_tasks
  WHERE parent_id = v_parent_id AND tenant_id = v_tenant;

  SELECT status INTO v_parent_status
  FROM project_tasks WHERE id = v_parent_id AND tenant_id = v_tenant;

  IF v_total > 0 AND v_done = v_total AND v_parent_status NOT IN ('done', 'cancelled') THEN
    UPDATE project_tasks
      SET status = 'done', is_closed = true, updated_at = now()
    WHERE id = v_parent_id AND tenant_id = v_tenant;
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_parent_status_on_subtask_started()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_parent_id uuid;
  v_tenant uuid;
  v_parent_status varchar;
BEGIN
  IF NEW.parent_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN RETURN NEW; END IF;
  IF NEW.status != 'in_progress' THEN RETURN NEW; END IF;

  v_parent_id := NEW.parent_id;
  v_tenant := NEW.tenant_id;
  IF v_tenant IS NULL THEN RETURN NEW; END IF;

  SELECT status INTO v_parent_status
  FROM project_tasks WHERE id = v_parent_id AND tenant_id = v_tenant;

  IF v_parent_status = 'todo' THEN
    UPDATE project_tasks
      SET status = 'in_progress', updated_at = now()
    WHERE id = v_parent_id AND tenant_id = v_tenant;
  END IF;

  RETURN NEW;
END;
$function$;


CREATE OR REPLACE FUNCTION public.recalc_parent_progress_on_subtask_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_parent_id uuid;
  v_tenant uuid;
  v_avg_progress integer;
  v_count integer;
  v_done_count integer;
  v_sub_effort numeric;
BEGIN
  v_parent_id := COALESCE(NEW.parent_id, OLD.parent_id);
  IF v_parent_id IS NULL THEN RETURN NEW; END IF;

  v_tenant := COALESCE(NEW.tenant_id, OLD.tenant_id);
  IF v_tenant IS NULL THEN RETURN NEW; END IF;

  SELECT
    COALESCE(AVG(progress), 0)::integer,
    COUNT(*),
    COUNT(*) FILTER (WHERE status IN ('done', 'cancelled') OR is_closed = true),
    COALESCE(SUM(effort_spent_h), 0)
  INTO v_avg_progress, v_count, v_done_count, v_sub_effort
  FROM project_tasks
  WHERE parent_id = v_parent_id AND tenant_id = v_tenant;

  UPDATE project_tasks
    SET progress = v_avg_progress,
        subtask_count = v_count,
        subtask_done_count = v_done_count,
        subtask_effective_hours = v_sub_effort,
        updated_at = now()
  WHERE id = v_parent_id AND tenant_id = v_tenant;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.recalc_project_progress_on_task_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_project_id uuid;
  v_tenant uuid;
  v_avg_progress integer;
  v_count integer;
BEGIN
  v_project_id := COALESCE(NEW.project_id, OLD.project_id);
  IF v_project_id IS NULL THEN RETURN NEW; END IF;

  v_tenant := COALESCE(NEW.tenant_id, OLD.tenant_id);
  IF v_tenant IS NULL THEN RETURN NEW; END IF;

  SELECT
    COALESCE(AVG(progress), 0)::integer,
    COUNT(*)
  INTO v_avg_progress, v_count
  FROM project_tasks
  WHERE project_id = v_project_id
    AND parent_id IS NULL
    AND tenant_id = v_tenant;

  UPDATE projects
    SET progress = v_avg_progress,
        updated_at = now()
  WHERE id = v_project_id AND tenant_id = v_tenant;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.recalc_task_progress_on_action_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_task_id uuid;
  v_tenant uuid;
  v_total_weight integer;
  v_done_weight integer;
  v_total_actions integer;
  v_done_actions integer;
  v_new_progress integer;
BEGIN
  v_task_id := COALESCE(NEW.task_id, OLD.task_id);
  IF v_task_id IS NULL THEN RETURN NEW; END IF;

  v_tenant := COALESCE(NEW.tenant_id, OLD.tenant_id);
  IF v_tenant IS NULL THEN RETURN NEW; END IF;

  SELECT
    COALESCE(SUM(weight_percentage), 0),
    COALESCE(SUM(weight_percentage) FILTER (WHERE is_done = true), 0),
    COUNT(*),
    COUNT(*) FILTER (WHERE is_done = true)
  INTO v_total_weight, v_done_weight, v_total_actions, v_done_actions
  FROM task_actions
  WHERE task_id = v_task_id AND tenant_id = v_tenant;

  IF v_total_actions = 0 THEN
    v_new_progress := 0;
  ELSIF v_total_weight > 0 THEN
    v_new_progress := LEAST(100, ROUND((v_done_weight::numeric / v_total_weight) * 100));
  ELSE
    v_new_progress := ROUND((v_done_actions::numeric / v_total_actions) * 100);
  END IF;

  UPDATE project_tasks
    SET progress = v_new_progress,
        updated_at = now()
  WHERE id = v_task_id AND tenant_id = v_tenant;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.auto_reach_milestone_on_tasks_done()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_milestone_id uuid;
  v_tenant uuid;
  v_total integer;
  v_done integer;
BEGIN
  v_milestone_id := COALESCE(NEW.milestone_id, OLD.milestone_id);
  IF v_milestone_id IS NULL THEN RETURN NEW; END IF;

  v_tenant := COALESCE(NEW.tenant_id, OLD.tenant_id);
  IF v_tenant IS NULL THEN RETURN NEW; END IF;

  SELECT
    COUNT(*),
    COUNT(*) FILTER (WHERE status IN ('done', 'cancelled') OR is_closed = true)
  INTO v_total, v_done
  FROM project_tasks
  WHERE milestone_id = v_milestone_id AND tenant_id = v_tenant;

  IF v_total > 0 AND v_done = v_total THEN
    UPDATE project_milestones
      SET is_reached = true,
          is_reached_manually = false,
          updated_at = now()
    WHERE id = v_milestone_id AND tenant_id = v_tenant AND is_reached = false;
  ELSIF v_done < v_total THEN
    UPDATE project_milestones
      SET is_reached = false,
          updated_at = now()
    WHERE id = v_milestone_id AND tenant_id = v_tenant
      AND is_reached = true AND is_reached_manually = false;
  END IF;

  RETURN NEW;
END;
$function$;

-- ── 2. Les deux déclencheurs de temps passé ───────────────────────────────
-- T07 était déjà fermé en amont par `check_time_entry_tenant` (231) : le filtre
-- est ici la seconde barrière, celle qui tient même quand la ligne arrive par un
-- autre chemin (service_role, import, déclencheur).

CREATE OR REPLACE FUNCTION public.update_project_hours_on_time_entry()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_project_id uuid;
  v_tenant uuid;
  v_total_seconds integer;
  v_total_hours numeric;
  v_allocated numeric;
BEGIN
  v_tenant := COALESCE(NEW.tenant_id, OLD.tenant_id);
  IF v_tenant IS NULL THEN RETURN NEW; END IF;

  v_project_id := COALESCE(NEW.project_id, OLD.project_id);
  IF v_project_id IS NULL AND COALESCE(NEW.task_id, OLD.task_id) IS NOT NULL THEN
    SELECT project_id INTO v_project_id
    FROM project_tasks
    WHERE id = COALESCE(NEW.task_id, OLD.task_id)
      AND tenant_id = v_tenant;
  END IF;
  IF v_project_id IS NULL THEN RETURN NEW; END IF;

  SELECT COALESCE(SUM(duration_seconds), 0)
  INTO v_total_seconds
  FROM project_time_entries
  WHERE project_id = v_project_id AND tenant_id = v_tenant;

  v_total_hours := ROUND((v_total_seconds::numeric / 3600), 2);

  SELECT allocated_hours INTO v_allocated
  FROM projects WHERE id = v_project_id AND tenant_id = v_tenant;

  UPDATE projects
    SET total_hours_spent = v_total_hours,
        remaining_hours = GREATEST(COALESCE(v_allocated, 0) - v_total_hours, 0),
        updated_at = now()
  WHERE id = v_project_id AND tenant_id = v_tenant;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_task_time_on_time_entry()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_task_id uuid;
  v_tenant uuid;
  v_total_seconds integer;
  v_total_hours numeric;
BEGIN
  v_task_id := COALESCE(NEW.task_id, OLD.task_id);
  IF v_task_id IS NULL THEN RETURN NEW; END IF;

  v_tenant := COALESCE(NEW.tenant_id, OLD.tenant_id);
  IF v_tenant IS NULL THEN RETURN NEW; END IF;

  SELECT COALESCE(SUM(duration_seconds), 0)
  INTO v_total_seconds
  FROM project_time_entries
  WHERE task_id = v_task_id AND tenant_id = v_tenant;

  v_total_hours := ROUND((v_total_seconds::numeric / 3600), 2);

  UPDATE project_tasks
    SET effort_spent_h = v_total_hours,
        updated_at = now()
  WHERE id = v_task_id AND tenant_id = v_tenant;

  RETURN NEW;
END;
$function$;


-- ── 3. Les cinq rafraîchissements de totaux ───────────────────────────────
-- Le couple `(id, tenant_id)` remplace l'identifiant seul : la somme des lignes
-- ne mélange plus les sociétés, et le `UPDATE` du document ne peut viser qu'une
-- ligne de la société de la ligne modifiée.

CREATE OR REPLACE FUNCTION public.invoice_lines_refresh_totals()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  UPDATE invoices i SET subtotal = s.ht, vat_total = s.tva, total = s.ht + s.tva
  FROM (SELECT x.id, x.tenant_id,
               COALESCE(sum(l.total), 0) ht, COALESCE(sum(l.vat_amount), 0) tva
        FROM (SELECT DISTINCT x.id, x.tenant_id FROM (VALUES
                (CASE WHEN TG_OP <> 'INSERT' THEN OLD.invoice_id END,
                 CASE WHEN TG_OP <> 'INSERT' THEN OLD.tenant_id END),
                (CASE WHEN TG_OP <> 'DELETE' THEN NEW.invoice_id END,
                 CASE WHEN TG_OP <> 'DELETE' THEN NEW.tenant_id END)
              ) AS x(id, tenant_id)
              WHERE x.id IS NOT NULL) x
        LEFT JOIN invoice_lines l ON l.invoice_id = x.id AND l.tenant_id = x.tenant_id
        GROUP BY x.id, x.tenant_id) s
  WHERE i.id = s.id AND i.tenant_id = s.tenant_id
    AND i.validation_status IS DISTINCT FROM 'validated'
    AND (i.subtotal, i.vat_total, i.total) IS DISTINCT FROM (s.ht, s.tva, s.ht + s.tva);
  RETURN NULL;
END $function$;

CREATE OR REPLACE FUNCTION public.credit_note_lines_refresh_totals()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  UPDATE credit_notes c SET subtotal = s.ht, vat_total = s.tva, total = s.ht + s.tva
  FROM (SELECT x.id, x.tenant_id,
               COALESCE(sum(l.total), 0) ht, COALESCE(sum(l.vat_amount), 0) tva
        FROM (SELECT DISTINCT x.id, x.tenant_id FROM (VALUES
                (CASE WHEN TG_OP <> 'INSERT' THEN OLD.credit_note_id END,
                 CASE WHEN TG_OP <> 'INSERT' THEN OLD.tenant_id END),
                (CASE WHEN TG_OP <> 'DELETE' THEN NEW.credit_note_id END,
                 CASE WHEN TG_OP <> 'DELETE' THEN NEW.tenant_id END)
              ) AS x(id, tenant_id)
              WHERE x.id IS NOT NULL) x
        LEFT JOIN credit_note_lines l ON l.credit_note_id = x.id AND l.tenant_id = x.tenant_id
        GROUP BY x.id, x.tenant_id) s
  WHERE c.id = s.id AND c.tenant_id = s.tenant_id
    AND c.status = 'draft'
    AND (c.subtotal, c.vat_total, c.total) IS DISTINCT FROM (s.ht, s.tva, s.ht + s.tva);
  RETURN NULL;
END $function$;


CREATE OR REPLACE FUNCTION public.purchase_invoice_lines_refresh_totals()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  UPDATE purchase_invoices i SET subtotal = s.ht, vat_total = s.tva, total = s.ht + s.tva
  FROM (SELECT x.id, x.tenant_id,
               COALESCE(sum(l.total), 0) ht, COALESCE(sum(l.vat_amount), 0) tva
        FROM (SELECT DISTINCT x.id, x.tenant_id FROM (VALUES
                (CASE WHEN TG_OP <> 'INSERT' THEN OLD.purchase_invoice_id END,
                 CASE WHEN TG_OP <> 'INSERT' THEN OLD.tenant_id END),
                (CASE WHEN TG_OP <> 'DELETE' THEN NEW.purchase_invoice_id END,
                 CASE WHEN TG_OP <> 'DELETE' THEN NEW.tenant_id END)
              ) AS x(id, tenant_id)
              WHERE x.id IS NOT NULL) x
        LEFT JOIN purchase_invoice_lines l ON l.purchase_invoice_id = x.id AND l.tenant_id = x.tenant_id
        GROUP BY x.id, x.tenant_id) s
  WHERE i.id = s.id AND i.tenant_id = s.tenant_id
    AND i.approval_status IS DISTINCT FROM 'approved'
    AND (i.subtotal, i.vat_total, i.total) IS DISTINCT FROM (s.ht, s.tva, s.ht + s.tva);
  RETURN NULL;
END $function$;

CREATE OR REPLACE FUNCTION public.purchase_credit_lines_refresh_totals()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  UPDATE purchase_credit_notes c SET subtotal = s.ht, vat_total = s.tva, total = s.ht + s.tva
  FROM (SELECT x.id, x.tenant_id,
               COALESCE(sum(l.total), 0) ht, COALESCE(sum(l.vat_amount), 0) tva
        FROM (SELECT DISTINCT x.id, x.tenant_id FROM (VALUES
                (CASE WHEN TG_OP <> 'INSERT' THEN OLD.purchase_credit_id END,
                 CASE WHEN TG_OP <> 'INSERT' THEN OLD.tenant_id END),
                (CASE WHEN TG_OP <> 'DELETE' THEN NEW.purchase_credit_id END,
                 CASE WHEN TG_OP <> 'DELETE' THEN NEW.tenant_id END)
              ) AS x(id, tenant_id)
              WHERE x.id IS NOT NULL) x
        LEFT JOIN purchase_credit_lines l ON l.purchase_credit_id = x.id AND l.tenant_id = x.tenant_id
        GROUP BY x.id, x.tenant_id) s
  WHERE c.id = s.id AND c.tenant_id = s.tenant_id
    AND c.status = 'draft'
    AND (c.subtotal, c.vat_total, c.total) IS DISTINCT FROM (s.ht, s.tva, s.ht + s.tva);
  RETURN NULL;
END $function$;

CREATE OR REPLACE FUNCTION public.quote_lines_refresh_totals()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  UPDATE quotes q SET subtotal = s.ht, vat_total = s.tva, total = s.ht + s.tva
  FROM (SELECT x.id, x.tenant_id,
               COALESCE(sum(l.total), 0) ht, COALESCE(sum(l.vat_total), 0) tva
        FROM (SELECT DISTINCT x.id, x.tenant_id FROM (VALUES
                (CASE WHEN TG_OP <> 'INSERT' THEN OLD.quote_id END,
                 CASE WHEN TG_OP <> 'INSERT' THEN OLD.tenant_id END),
                (CASE WHEN TG_OP <> 'DELETE' THEN NEW.quote_id END,
                 CASE WHEN TG_OP <> 'DELETE' THEN NEW.tenant_id END)
              ) AS x(id, tenant_id)
              WHERE x.id IS NOT NULL) x
        LEFT JOIN quote_lines l ON l.quote_id = x.id AND l.tenant_id = x.tenant_id
        GROUP BY x.id, x.tenant_id) s
  WHERE q.id = s.id AND q.tenant_id = s.tenant_id
    AND (q.subtotal, q.vat_total, q.total) IS DISTINCT FROM (s.ht, s.tva, s.ht + s.tva);
  RETURN NULL;
END $function$;


-- ── 4. Le recalcul des totaux d'écriture brouillon ────────────────────────
-- Appelée par les déclencheurs d'équilibre (`check_journal_entry_balance_*`).
-- Le contexte d'un utilisateur connecté borne le recalcul à sa société ; le cron
-- et `service_role`, qui n'en ont pas, gardent le comportement global.

CREATE OR REPLACE FUNCTION public.refresh_draft_entry_totals(p_entry_ids uuid[])
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  UPDATE journal_entries je
  SET total_debit = s.d, total_credit = s.c
  FROM (
    SELECT e.id, COALESCE(sum(jl.debit), 0) AS d, COALESCE(sum(jl.credit), 0) AS c
    FROM unnest(p_entry_ids) AS e(id)
    LEFT JOIN journal_lines jl ON jl.journal_id = e.id
    GROUP BY e.id
  ) s
  WHERE je.id = s.id AND je.status = 'draft'
    AND (current_tenant_id() IS NULL OR je.tenant_id = current_tenant_id())
    AND (je.total_debit IS DISTINCT FROM s.d OR je.total_credit IS DISTINCT FROM s.c);
$function$;

-- ── 5. Les quatre fonctions d'entretien ───────────────────────────────────
-- Elles balaient toutes les sociétés : c'est leur raison d'être (pg_cron n'a
-- aucun contexte). La clause les rend inoffensives pour un appelant connecté,
-- qui n'agit plus que chez lui — `auto_revoke_expired_auditors` est appelée à
-- chaque connexion par `src/lib/auth.tsx`, et `cleanup_expired_idempotency` et
-- `requeue_stale_webhook_deliveries` sont exécutables par `authenticated`.

CREATE OR REPLACE FUNCTION public.auto_revoke_expired_auditors()
 RETURNS integer
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH expired AS (
    UPDATE tenant_users
    SET status = 'revoked',
        updated_at = now()
    WHERE role = 'auditor'
      AND status = 'active'
      AND valid_until IS NOT NULL
      AND valid_until < CURRENT_DATE
      AND (current_tenant_id() IS NULL OR tenant_id = current_tenant_id())
    RETURNING id
  )
  SELECT count(*)::integer FROM expired;
$function$;

CREATE OR REPLACE FUNCTION public.cleanup_expired_idempotency()
 RETURNS integer
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH deleted AS (
    DELETE FROM idempotency_records
    WHERE expires_at < now()
      AND (current_tenant_id() IS NULL OR tenant_id = current_tenant_id())
    RETURNING 1
  )
  SELECT COUNT(*) FROM deleted;
$function$;

CREATE OR REPLACE FUNCTION public.requeue_stale_webhook_deliveries(p_older_than interval DEFAULT '00:10:00'::interval)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_n int;
BEGIN
  UPDATE webhook_delivery_queue
  SET status = 'retry', next_attempt_at = now(),
      last_error = COALESCE(last_error, 'Envoi abandonné : traitement interrompu, remis en file')
  WHERE status = 'sending'
    AND delivered_at IS NULL
    AND COALESCE(last_attempt_at, created_at) < now() - p_older_than
    AND (current_tenant_id() IS NULL OR tenant_id = current_tenant_id());
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$function$;

CREATE OR REPLACE FUNCTION public.process_webhook_queue(p_batch_size integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_requeued int;
  v_blocked int := 0;
  v_due int;
  v_tenant uuid := current_tenant_id();
BEGIN
  v_requeued := requeue_stale_webhook_deliveries();

  -- URL devenues interdites depuis leur mise en file (garde SSRF, 167)
  UPDATE webhook_delivery_queue
  SET status = 'blocked', last_error = 'URL bloquée (protection SSRF)'
  WHERE status IN ('pending', 'retry') AND delivered_at IS NULL
    AND (url IS NULL OR NOT is_allowed_webhook_url(url))
    AND (v_tenant IS NULL OR tenant_id = v_tenant);
  GET DIAGNOSTICS v_blocked = ROW_COUNT;

  SELECT count(*) INTO v_due FROM webhook_delivery_queue
  WHERE status IN ('pending', 'retry') AND delivered_at IS NULL
    AND (next_attempt_at IS NULL OR next_attempt_at <= now())
    AND (v_tenant IS NULL OR tenant_id = v_tenant);

  -- L'envoi HTTP appartient à la fonction Edge outgoing-webhooks?process=1,
  -- qui prend son lot par claim_webhook_batch(). Cette fonction-ci ne compte
  -- plus de tentative : une tentative, c'est un envoi réellement fait.
  RETURN jsonb_build_object(
    'requeued', v_requeued,
    'blocked', v_blocked,
    'due', v_due,
    'processed_at', now()
  );
END;
$function$;

