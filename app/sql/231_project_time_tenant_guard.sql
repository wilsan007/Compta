-- ============================================================
-- 231_project_time_tenant_guard.sql — le temps passé sortait de sa société
--
-- M-17 du reste-à-faire : « CRM, projets, temps passés, tâches — refacturation
-- des temps → facture ; aucune écriture directe ». Mesuré sur base neuve à la
-- 230, deux défauts, dont un de sécurité.
--
-- 1. FUITE ENTRE SOCIÉTÉS (famille de la 227 et de H02)
--    Un utilisateur de la société B enregistre un temps dont `project_id` est
--    le projet de la société A. Rien ne l'en empêche : la politique RLS de
--    `project_time_entries` vérifie son `tenant_id` (B, correct) et ne regarde
--    pas à qui appartient le projet visé. Puis le déclencheur
--    `create_billable_line_on_timesheet_stop`, SECURITY DEFINER, lit
--        SELECT * FROM projects WHERE id = NEW.project_id
--    sans filtre de société, et recopie le NOM DU PROJET DE A dans une
--    notification rangée chez B, avec l'identifiant du chef de projet de A en
--    destinataire — une clé étrangère qui traverse les deux sociétés.
--    Mesuré : notification créée chez B, portant « Projet confidentiel A ».
--
-- 2. DEVISE CODÉE EN DUR
--    Le message est bâti avec « € » littéral, quelle que soit la devise de la
--    société (cahier de localisation, LOC1). À Djibouti il affiche des francs
--    libellés en euros.
--
-- Hors périmètre, inscrit au registre (M-17-01) : la fonction s'appelle
-- `create_billable_line` et ne crée aucune ligne facturable. Trois heures
-- facturables à 80 produisent une notification, zéro facture, zéro ligne de
-- facture. C'est un manque de fonction, pas un défaut de code : le scénario
-- T02 le tient rouge jusqu'à ce qu'il soit comblé.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Un temps ne peut viser qu'un projet et une tâche de sa propre société
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION check_time_entry_tenant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_owner uuid;
BEGIN
  IF NEW.project_id IS NOT NULL THEN
    SELECT tenant_id INTO v_owner FROM projects WHERE id = NEW.project_id;
    IF v_owner IS NULL OR v_owner <> NEW.tenant_id THEN
      RAISE EXCEPTION 'Projet % hors de la société du temps saisi', NEW.project_id
        USING ERRCODE = '42501';
    END IF;
  END IF;

  IF NEW.task_id IS NOT NULL THEN
    SELECT tenant_id INTO v_owner FROM project_tasks WHERE id = NEW.task_id;
    IF v_owner IS NULL OR v_owner <> NEW.tenant_id THEN
      RAISE EXCEPTION 'Tâche % hors de la société du temps saisi', NEW.task_id
        USING ERRCODE = '42501';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- La 228 révoque EXECUTE sur TOUTES les fonctions de `public`, mais elle est
-- passée avant celle-ci : une fonction créée après elle retrouve le droit
-- PUBLIC par défaut. `ci/check_anon_grants.sql` (H09) l'a signalée. Même
-- révocation explicite que la 232 pour ses fonctions de déclencheur.
REVOKE EXECUTE ON FUNCTION check_time_entry_tenant() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS check_time_entry_tenant ON project_time_entries;
CREATE TRIGGER check_time_entry_tenant
  BEFORE INSERT OR UPDATE OF project_id, task_id, tenant_id ON project_time_entries
  FOR EACH ROW EXECUTE FUNCTION check_time_entry_tenant();

-- ------------------------------------------------------------
-- 2. Le déclencheur de facturation reste dans sa société, et dans sa devise
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION create_billable_line_on_timesheet_stop()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_project RECORD;
  v_hours numeric;
  v_amount numeric;
  v_currency text;
BEGIN
  IF NEW.is_billable = false THEN RETURN NEW; END IF;
  IF NEW.end_time IS NULL THEN RETURN NEW; END IF;
  IF OLD.end_time IS NOT NULL THEN RETURN NEW; END IF;

  -- 231 : le filtre de société manquait — la ligne lue pouvait appartenir à
  -- une autre société, et son nom partait dans une notification d'ici.
  SELECT * INTO v_project
  FROM projects
  WHERE tenant_id = NEW.tenant_id
    AND id = COALESCE(NEW.project_id, (
      SELECT project_id FROM project_tasks
      WHERE id = NEW.task_id AND tenant_id = NEW.tenant_id
    ));

  IF NOT FOUND OR v_project.customer_id IS NULL THEN RETURN NEW; END IF;
  IF v_project.allow_billable = false THEN RETURN NEW; END IF;

  v_hours := ROUND(NEW.duration_seconds::numeric / 3600, 2);
  v_amount := v_hours * COALESCE(NEW.hourly_rate, 0);

  -- 231 : devise de la société, plus « € » codé en dur (LOC1)
  SELECT COALESCE(NULLIF(currency, ''), 'EUR') INTO v_currency
  FROM company_settings WHERE tenant_id = NEW.tenant_id LIMIT 1;
  v_currency := COALESCE(v_currency, 'EUR');

  -- M-17-01 : ce n'est toujours qu'une notification. Aucune ligne facturable
  -- n'est créée — voir l'en-tête et le registre des défauts ouverts.
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
    v_hours::text || 'h facturables (' || v_amount::text || ' ' || v_currency || ') sur le projet ''' || v_project.name || '''',
    '/projects/' || v_project.id
  FROM projects p
  WHERE p.id = v_project.id AND p.tenant_id = NEW.tenant_id AND p.manager_id IS NOT NULL;

  RETURN NEW;
END;
$$;
