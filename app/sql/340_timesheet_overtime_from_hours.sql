-- ════════════════════════════════════════════════════════════════════════════
-- 340 — Partie 2, tâche 2.2 (C3, rh-008) : les heures supplémentaires d'une
--       feuille de temps saisie en HEURES
-- ════════════════════════════════════════════════════════════════════════════
--
-- LE DÉFAUT, MESURÉ. L'écran des feuilles de temps enregistre `hours` (12, par
-- exemple) et rien d'autre : ni heure d'arrivée, ni heure de départ. Le
-- déclencheur `calculate_lateness_on_timesheet` ne calculait `overtime_minutes`
-- QUE dans la branche « heure de départ renseignée ». Résultat (suite 340,
-- avant) : 12 h approuvées → `overtime_minutes = 0`, aucun élément de paie
-- « heures sup » ; et `approved_by` restait vide.
--
-- CE QUE FAIT CE FICHIER. Il reprend le corps du déclencheur À L'IDENTIQUE
-- (relevé par pg_get_functiondef sur une base neuve à 316 migrations) et lui
-- ajoute deux blocs, marqués « 340 » :
--   1. sans heure de départ : heures sup = heures saisies − horaire prévu du
--      jour (horaire hebdomadaire du salarié / 5 ; 35 h par défaut) ;
--   2. à l'approbation : `approved_by = auth.uid()` et `approved_at = now()`.
-- Le reste de la chaîne ne change pas : `sync_timesheet_to_payroll` (260) lit
-- `overtime_minutes` et pose l'élément de paie au taux majoré de la société —
-- UN seul moteur, celui de la W5.
--
-- CE QU'IL NE FAIT PAS. Les tranches (25 % / 50 %) et l'exonération restent la
-- tâche 2.3. Le seuil est JOURNALIER (horaire / 5) : le décompte légal à la
-- semaine relève de la même tâche. La signature des congés (`leave_requests`)
-- n'est pas touchée : l'écran envoie déjà l'approbateur.
-- ════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.calculate_lateness_on_timesheet()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_scheduled_start timestamptz;
  v_scheduled_end timestamptz;
  v_arrival timestamptz;
  v_departure timestamptz;
  v_diff_min integer;
  v_default_start time;
  v_default_end time;
  v_hebdo numeric;        -- 340 : horaire hebdomadaire du salarié
  v_prevu_jour numeric;   -- 340 : heures prévues pour la journée
BEGIN
  -- Récupérer les horaires par défaut de l'employé si non spécifiés
  IF NEW.scheduled_start IS NULL OR NEW.scheduled_end IS NULL THEN
    SELECT default_start_time, default_end_time
    INTO v_default_start, v_default_end
    FROM employees
    WHERE id = NEW.employee_id AND tenant_id = NEW.tenant_id;

    IF NEW.scheduled_start IS NULL THEN
      NEW.scheduled_start := COALESCE(v_default_start, '09:00'::time);
    END IF;
    IF NEW.scheduled_end IS NULL THEN
      NEW.scheduled_end := COALESCE(v_default_end, '17:00'::time);
    END IF;
  END IF;

  -- Calculer le retard si l'heure d'arrivée est renseignée
  IF NEW.arrival_time IS NOT NULL THEN
    v_scheduled_start := (NEW.date::date + NEW.scheduled_start)::timestamptz;
    v_arrival := NEW.arrival_time;

    IF v_arrival > v_scheduled_start THEN
      v_diff_min := EXTRACT(EPOCH FROM (v_arrival - v_scheduled_start))::integer / 60;
      NEW.late_minutes := GREATEST(v_diff_min, 0);
    ELSE
      NEW.late_minutes := 0;
    END IF;
  END IF;

  -- Calculer le départ anticipé et les heures supplémentaires
  IF NEW.departure_time IS NOT NULL THEN
    v_scheduled_end := (NEW.date::date + NEW.scheduled_end)::timestamptz;
    v_departure := NEW.departure_time;

    IF v_departure < v_scheduled_end THEN
      v_diff_min := EXTRACT(EPOCH FROM (v_scheduled_end - v_departure))::integer / 60;
      NEW.early_leave_minutes := GREATEST(v_diff_min, 0);
    ELSE
      NEW.early_leave_minutes := 0;
    END IF;

    IF v_departure > v_scheduled_end THEN
      v_diff_min := EXTRACT(EPOCH FROM (v_departure - v_scheduled_end))::integer / 60;
      NEW.overtime_minutes := GREATEST(v_diff_min, 0);
    ELSE
      NEW.overtime_minutes := 0;
    END IF;
  END IF;

  -- 340 (C3, rh-008) — La feuille de temps de l'écran ne porte que des HEURES :
  -- sans heure de départ, la branche ci-dessus ne s'exécute jamais et les heures
  -- supplémentaires restaient à 0. Le seuil est alors l'horaire prévu de la
  -- journée : l'horaire hebdomadaire du salarié réparti sur cinq jours (35 h → 7 h).
  -- Un pointage d'absence ne produit pas d'heures supplémentaires.
  --
  -- Une valeur FOURNIE est respectée (« 9 h dont 1 h sup », suite 243 T05) : on
  -- ne calcule qu'à la création sans valeur, ou quand ce qui fonde le calcul
  -- change (heures, salarié, absence, retrait de l'heure de départ) sans que
  -- `overtime_minutes` soit lui-même modifié. Une simple approbation ne recalcule rien.
  IF NEW.departure_time IS NULL AND (
       (TG_OP = 'INSERT' AND COALESCE(NEW.overtime_minutes, 0) = 0)
    OR (TG_OP = 'UPDATE'
        AND NEW.overtime_minutes IS NOT DISTINCT FROM OLD.overtime_minutes
        AND (NEW.hours IS DISTINCT FROM OLD.hours
          OR NEW.employee_id IS DISTINCT FROM OLD.employee_id
          OR NEW.absence_type IS DISTINCT FROM OLD.absence_type
          OR NEW.departure_time IS DISTINCT FROM OLD.departure_time))
     ) THEN
    -- `absence_type` vaut 'none' par défaut : c'est cette valeur, et non NULL,
    -- qui dit « jour travaillé ».
    IF COALESCE(NEW.absence_type, 'none') <> 'none' OR NEW.hours IS NULL THEN
      NEW.overtime_minutes := 0;
    ELSE
      SELECT e.weekly_hours INTO v_hebdo
      FROM employees e
      WHERE e.id = NEW.employee_id AND e.tenant_id = NEW.tenant_id;
      v_prevu_jour := COALESCE(NULLIF(v_hebdo, 0), 35) / 5.0;
      NEW.overtime_minutes := GREATEST(round((NEW.hours - v_prevu_jour) * 60)::integer, 0);
    END IF;
  END IF;

  -- 340 — L'approbation est signée par la BASE : l'écran n'envoie ni l'auteur ni
  -- la date. Une valeur déjà fournie (import, reprise) est respectée.
  IF TG_OP = 'UPDATE' AND NEW.status = 'approved' AND OLD.status IS DISTINCT FROM 'approved' THEN
    NEW.approved_by := COALESCE(NEW.approved_by, auth.uid());
    NEW.approved_at := COALESCE(NEW.approved_at, now());
  END IF;

  -- Calculer les heures travaillées
  IF NEW.arrival_time IS NOT NULL AND NEW.departure_time IS NOT NULL THEN
    NEW.hours := EXTRACT(EPOCH FROM (NEW.departure_time - NEW.arrival_time))::integer / 3600.0;
  END IF;

  RETURN NEW;
END;
$function$;

-- ── Le déclencheur doit AUSSI se réveiller sur ce que l'écran modifie ──────
-- Mesuré : il ne réagissait, en UPDATE, qu'aux quatre colonnes horaires
-- (`arrival_time`, `departure_time`, `scheduled_start`, `scheduled_end`).
-- Corriger les heures d'une feuille (7 → 10) ne recalculait donc rien, et
-- l'approbation (colonne `status`) ne passait jamais par lui.
DROP TRIGGER IF EXISTS calculate_lateness ON public.timesheets;
CREATE TRIGGER calculate_lateness
  BEFORE INSERT OR UPDATE OF arrival_time, departure_time, scheduled_start, scheduled_end,
                             hours, absence_type, employee_id, status
  ON public.timesheets
  FOR EACH ROW EXECUTE FUNCTION calculate_lateness_on_timesheet();
