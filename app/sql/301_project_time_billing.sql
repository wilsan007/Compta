-- ============================================================
-- 269_project_time_billing.sql — W8 : les heures facturables atteignent une facture
--
-- LE DÉFAUT (231 M-17-01, inscrit au registre `ci/expected_failures.sql`).
-- La fonction s'appelait `create_billable_line_on_timesheet_stop` et son corps
-- **créait une notification**, rien d'autre. Trois heures facturables à 80
-- produisaient une notification, zéro facture, zéro ligne de facture. Mesuré sur
-- base neuve le 28/09/2026, avant ce fichier : `lignes de facture=0`.
--
-- Un second chemin manquait, du même défaut : le déclencheur ne se branchait que
-- sur `UPDATE OF end_time`, donc la **saisie directe** du formulaire « temps
-- manuel » (INSERT avec `end_time` du premier coup) n'atteignait rien non plus.
-- Mesuré : `lignes=0 montant=0` (scénario T07).
--
-- CE QUE LA MIGRATION POSE.
--   1. `invoices.project_id` — la facture dit quel projet elle facture, et
--      **un seul brouillon** peut exister par projet et par société (index
--      unique partiel) : les heures s'y accumulent au lieu de créer une facture
--      par arrêt de chronomètre.
--   2. `invoice_lines.time_entry_id` — la ligne dit quelle feuille de temps elle
--      refacture, avec unicité `(société, temps)` : un temps arrêté deux fois
--      n'est **jamais** facturé deux fois (T08).
--   3. Le déclencheur se branche sur `INSERT OR UPDATE OF end_time`, reste dans
--      la société du temps (231) et dans sa devise, et **crée la ligne**.
--
-- CE QUI N'EST PAS FAIT, ET POURQUOI C'EST BIEN AINSI.
--   • Le brouillon n'est **pas** validé automatiquement : une facture de temps
--     est un acte commercial (prix, TVA, remises, regroupement), et T06 exige
--     qu'aucune écriture comptable ne naisse d'un temps passé.
--   • La ligne porte le **prix de la feuille de temps** (`hourly_rate`) et le
--     **taux de TVA par défaut** de la législation de la société — les mêmes
--     règles que les écrans de vente (`tax_rates.is_default`, `category =
--     'standard'`). Il n'y a ni position fiscale du client ni régénération d'une
--     ligne déjà posée : ce sont des chaînages (L14/L20), pas ce défaut.
--   • Supprimer une feuille de temps emporte sa ligne tant qu'elle est en
--     brouillon (CASCADE) ; si l'heure est déjà sur une facture **validée**,
--     `invoice_line_compute` refuse la suppression — on n'efface pas une pièce.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. La référence d'unicité des temps, puis les deux colonnes de rattachement
-- ─────────────────────────────────────────────────────────────
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'project_time_entries_tenant_id_id_key'
                   AND conrelid = 'public.project_time_entries'::regclass) THEN
    ALTER TABLE public.project_time_entries
      ADD CONSTRAINT project_time_entries_tenant_id_id_key UNIQUE (tenant_id, id);
  END IF;
END $$;

ALTER TABLE public.invoices ADD COLUMN IF NOT EXISTS project_id uuid;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'invoices_project_fk'
                   AND conrelid = 'public.invoices'::regclass) THEN
    ALTER TABLE public.invoices ADD CONSTRAINT invoices_project_fk
      FOREIGN KEY (tenant_id, project_id) REFERENCES public.projects (tenant_id, id)
      ON DELETE SET NULL (project_id);
  END IF;
END $$;

-- Un seul brouillon par projet et par société : les heures du projet s'y
-- accumulent. Une facture validée sort de l'index (validation_status), un
-- nouveau brouillon peut donc naître pour la période suivante.
CREATE UNIQUE INDEX IF NOT EXISTS uniq_invoice_draft_project
  ON public.invoices (tenant_id, project_id)
  WHERE project_id IS NOT NULL AND status = 'draft' AND validation_status = 'draft';

ALTER TABLE public.invoice_lines ADD COLUMN IF NOT EXISTS time_entry_id uuid;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'invoice_lines_time_entry_fk'
                   AND conrelid = 'public.invoice_lines'::regclass) THEN
    ALTER TABLE public.invoice_lines ADD CONSTRAINT invoice_lines_time_entry_fk
      FOREIGN KEY (tenant_id, time_entry_id) REFERENCES public.project_time_entries (tenant_id, id)
      ON DELETE CASCADE;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uniq_invoice_line_time_entry
  ON public.invoice_lines (tenant_id, time_entry_id)
  WHERE time_entry_id IS NOT NULL;

COMMENT ON COLUMN public.invoices.project_id IS
  'Projet refacturé par cette facture. Un seul brouillon par (société, projet) : uniq_invoice_draft_project. 301 (W8).';
COMMENT ON COLUMN public.invoice_lines.time_entry_id IS
  'Feuille de temps refacturée par cette ligne. Unique par société : un temps ne se facture qu''une fois. 301 (W8).';

-- ─────────────────────────────────────────────────────────────
-- 2. Le déclencheur remplit enfin sa promesse : la ligne facturable existe
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_billable_line_on_timesheet_stop()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_project RECORD;
  v_client text;
  v_hours numeric;
  v_rate numeric;
  v_amount numeric;
  v_currency text;
  v_pack text;
  v_vat_rate numeric;
  v_invoice uuid;
  v_line integer;
BEGIN
  IF NEW.is_billable IS DISTINCT FROM true THEN RETURN NEW; END IF;
  IF NEW.end_time IS NULL THEN RETURN NEW; END IF;
  -- Le chronomètre s'arrête une fois : NULL → date. Une modification ultérieure
  -- d'une feuille déjà arrêtée ne rejoue pas la facturation.
  IF TG_OP = 'UPDATE' THEN
    IF OLD.end_time IS NOT NULL THEN RETURN NEW; END IF;
  END IF;

  -- 231 : le filtre de société manquait — la ligne lue pouvait appartenir à
  -- une autre société, et son nom partait dans une notification d'ici.
  SELECT * INTO v_project
  FROM public.projects
  WHERE tenant_id = NEW.tenant_id
    AND id = COALESCE(NEW.project_id, (
      SELECT project_id FROM public.project_tasks
      WHERE id = NEW.task_id AND tenant_id = NEW.tenant_id
    ));

  IF NOT FOUND OR v_project.customer_id IS NULL THEN RETURN NEW; END IF;
  IF v_project.allow_billable IS DISTINCT FROM true THEN RETURN NEW; END IF;

  v_hours := ROUND(COALESCE(NEW.duration_seconds, 0)::numeric / 3600, 2);
  -- Un arrêt instantané ne produit ni tarif ni ligne : rien à facturer.
  IF v_hours <= 0 THEN RETURN NEW; END IF;

  v_rate := COALESCE(NEW.hourly_rate, 0);
  v_amount := ROUND(v_hours * v_rate, 2);

  -- Devise et taux de TVA par défaut : les mêmes règles que les écrans de vente
  -- (legislation.tsx lit `tax_rates.is_default` puis `category = 'standard'`).
  SELECT COALESCE(NULLIF(currency, ''), 'EUR'), legislation_pack_code
    INTO v_currency, v_pack
  FROM public.company_settings WHERE tenant_id = NEW.tenant_id LIMIT 1;
  v_currency := COALESCE(v_currency, 'EUR');
  v_pack := COALESCE(v_pack,
    (SELECT code FROM public.legislation_packs WHERE is_default ORDER BY code LIMIT 1));

  SELECT t.rate INTO v_vat_rate
  FROM public.tax_rates t
  WHERE (t.tenant_id = NEW.tenant_id
         OR (t.tenant_id IS NULL AND (v_pack IS NULL OR t.pack_code = v_pack)))
    AND COALESCE(t.type_tax_use, 'none') IN ('sale', 'none')
    AND t.effective_from <= CURRENT_DATE
    AND (t.effective_to IS NULL OR t.effective_to >= CURRENT_DATE)
  ORDER BY (t.tenant_id IS NOT NULL) DESC, t.is_default DESC,
           (t.category = 'standard') DESC, t.rate DESC
  LIMIT 1;
  v_vat_rate := COALESCE(v_vat_rate, 0);


  -- Le chef de projet est prévenu (notification de la 231, conservée).
  INSERT INTO public.project_notifications (
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
  FROM public.projects p
  WHERE p.id = v_project.id AND p.tenant_id = NEW.tenant_id AND p.manager_id IS NOT NULL;

  -- ── La ligne facturable, dans le brouillon du projet ────────────────────
  -- Déjà facturé ? L'index unique (tenant_id, time_entry_id) le garantit, le
  -- test évite simplement de créer un brouillon pour rien.
  IF (SELECT count(*) FROM public.invoice_lines
      WHERE tenant_id = NEW.tenant_id AND time_entry_id = NEW.id) = 0 THEN

    SELECT id INTO v_invoice
    FROM public.invoices
    WHERE tenant_id = NEW.tenant_id
      AND project_id = v_project.id
      AND status = 'draft'
      AND validation_status = 'draft'
    LIMIT 1;

    IF v_invoice IS NULL THEN
      SELECT name INTO v_client FROM public.customers
      WHERE id = v_project.customer_id AND tenant_id = NEW.tenant_id;
      BEGIN
        INSERT INTO public.invoices (
          tenant_id, number, customer_id, customer_name, date, due_date,
          status, currency_code, project_id, notes
        ) VALUES (
          NEW.tenant_id, 'BROUILLON-TEMPS', v_project.customer_id,
          COALESCE(v_client, 'Client'), CURRENT_DATE, CURRENT_DATE + 30,
          'draft', v_currency, v_project.id,
          'Temps facturables du projet ' || v_project.name
        ) RETURNING id INTO v_invoice;
      EXCEPTION WHEN unique_violation THEN
        -- Deux arrêts simultanés : l'index a tranché, on rejoint son brouillon.
        SELECT id INTO v_invoice FROM public.invoices
        WHERE tenant_id = NEW.tenant_id AND project_id = v_project.id
          AND status = 'draft' AND validation_status = 'draft'
        LIMIT 1;
      END;
    END IF;

    SELECT COALESCE(MAX(line_order), 0) + 1 INTO v_line
    FROM public.invoice_lines
    WHERE tenant_id = NEW.tenant_id AND invoice_id = v_invoice;

    INSERT INTO public.invoice_lines (
      tenant_id, invoice_id, description, quantity, unit_price, vat_rate, line_order, time_entry_id
    ) VALUES (
      NEW.tenant_id, v_invoice,
      COALESCE(NULLIF(btrim(NEW.description), ''), 'Temps facturable — ' || v_project.name),
      v_hours, v_rate, v_vat_rate, v_line, NEW.id
    );
  END IF;

  RETURN NEW;
END;
$function$;

-- La 228 révoque EXECUTE sur toutes les fonctions de `public`, mais cette
-- réécriture n'ajoute aucun droit : le REVOKE est réaffirmé pour le contrôle
-- `ci/check_anon_grants.sql` (même geste que la 231, 232, 250).
REVOKE EXECUTE ON FUNCTION public.create_billable_line_on_timesheet_stop() FROM PUBLIC, anon;

-- Le déclencheur se branche aussi sur l'INSERT : la saisie directe d'un temps
-- déjà terminé (« temps manuel ») ne passe par aucun `UPDATE OF end_time`.
DROP TRIGGER IF EXISTS create_billable_line ON public.project_time_entries;
CREATE TRIGGER create_billable_line
  AFTER INSERT OR UPDATE OF end_time
  ON public.project_time_entries
  FOR EACH ROW
  EXECUTE FUNCTION public.create_billable_line_on_timesheet_stop();

