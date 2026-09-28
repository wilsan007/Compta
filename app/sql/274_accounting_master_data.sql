-- ============================================================
-- 274_accounting_master_data.sql — vague X2 / C14 : données de base comptables
-- (audit fonctionnel exécuté du 28/09/2026 ; décisions D-C et D-6)
--
-- LES DÉFAUTS, mesurés par le chemin de l'écran :
--   W03 la fiche section envoie `section_type` (« section » ou « total ») ; la
--       colonne n'existait pas — toute création de section échouait (PGRST204).
--   M8  (masqué jusqu'ici) dès que l'écran a pu créer un compte de tiers et une
--       section, le balayage du lecteur (15_security, X1-M8) les a trouvés
--       MODIFIABLES par un lecteur : le balayage ne teste que les tables qui ont
--       une ligne, et aucune de ces deux tables n'en avait. Neuf tables de
--       données de base comptables n'ont que la garde de société : comptes de
--       tiers, RIB des tiers (le virement part vers l'IBAN écrit là), modèles de
--       règlement, relances, sections, plans et ventilations analytiques,
--       modèles de saisie.
--
-- LE CORRECTIF (D-C : une donnée n'existe que si une règle la lit)
--   1. `analytic_sections.section_type` : énumération `section` | `total`,
--      `section` par défaut (toutes les sections existantes le restent).
--   2. La règle qui la lit : une section « total » regroupe d'autres sections,
--      elle ne reçoit JAMAIS d'imputation — ni sur une ligne d'écriture
--      (`journal_lines.analytic_section_id`, y compris celle que pose la
--      propagation depuis une pièce), ni dans une ventilation
--      (`analytic_distribution_lines.section_id`). Sinon le total compterait
--      deux fois ce que ses sections portent déjà.
--
--   3. Les neuf tables passent sous `can_perform`, comme les 19 de la 271 :
--      même matrice, donc un lecteur n'y écrit plus ; un `manager` non plus
--      (il n'écrit que les pièces commerciales — décision D-6).
--
-- Suite : `274_accounting_master_data_tests.sql`.
-- ============================================================

ALTER TABLE public.analytic_sections
  ADD COLUMN IF NOT EXISTS section_type text NOT NULL DEFAULT 'section';

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'analytic_sections_section_type_check') THEN
    ALTER TABLE public.analytic_sections ADD CONSTRAINT analytic_sections_section_type_check
      CHECK (section_type IN ('section', 'total'));
  END IF;
END $$;

COMMENT ON COLUMN public.analytic_sections.section_type IS
  'X2/C14 (274) : section (imputable) ou total (regroupement, jamais imputé — lu par '
  'analytic_section_must_be_imputable sur journal_lines et analytic_distribution_lines).';

CREATE OR REPLACE FUNCTION public.analytic_section_must_be_imputable()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_section uuid := (to_jsonb(NEW) ->> CASE TG_TABLE_NAME WHEN 'journal_lines' THEN 'analytic_section_id' ELSE 'section_id' END)::uuid;
  v_code text;
BEGIN
  IF v_section IS NULL THEN
    RETURN NEW;
  END IF;
  SELECT code INTO v_code FROM analytic_sections
  WHERE tenant_id = NEW.tenant_id AND id = v_section AND section_type = 'total';
  IF FOUND THEN
    RAISE EXCEPTION 'La section analytique % est une section de total : elle regroupe d''autres sections et ne reçoit pas d''imputation', v_code
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.analytic_section_must_be_imputable() FROM PUBLIC, anon, authenticated;

-- nommé après `trigger_propagate_analytic` : la section posée par la propagation
-- est contrôlée aussi (les déclencheurs BEFORE s'exécutent par ordre de nom)
DROP TRIGGER IF EXISTS tz_journal_line_section_imputable ON public.journal_lines;
CREATE TRIGGER tz_journal_line_section_imputable
  BEFORE INSERT OR UPDATE OF analytic_section_id ON public.journal_lines
  FOR EACH ROW EXECUTE FUNCTION public.analytic_section_must_be_imputable();

DROP TRIGGER IF EXISTS tz_distribution_line_section_imputable ON public.analytic_distribution_lines;
CREATE TRIGGER tz_distribution_line_section_imputable
  BEFORE INSERT OR UPDATE OF section_id ON public.analytic_distribution_lines
  FOR EACH ROW EXECUTE FUNCTION public.analytic_section_must_be_imputable();

-- une section déjà imputée ne devient pas un total
CREATE OR REPLACE FUNCTION public.analytic_section_type_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF NEW.section_type = 'total' AND OLD.section_type IS DISTINCT FROM 'total' AND (
       EXISTS (SELECT 1 FROM journal_lines WHERE tenant_id = NEW.tenant_id AND analytic_section_id = NEW.id)
    OR EXISTS (SELECT 1 FROM analytic_distribution_lines WHERE tenant_id = NEW.tenant_id AND section_id = NEW.id)) THEN
    RAISE EXCEPTION 'La section % porte déjà des imputations : elle ne peut pas devenir une section de total', NEW.code
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.analytic_section_type_guard() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS tg_analytic_section_type_guard ON public.analytic_sections;
CREATE TRIGGER tg_analytic_section_type_guard
  BEFORE UPDATE OF section_type ON public.analytic_sections
  FOR EACH ROW EXECUTE FUNCTION public.analytic_section_type_guard();

-- ── 3. Données de base comptables sous le rôle (M8, masqué) ──────────────────
CREATE TEMP TABLE t274_tables (table_name text PRIMARY KEY, raison text);
INSERT INTO t274_tables VALUES
  ('third_party_accounts',        'comptabilité — compte auxiliaire, encours autorisé, conditions'),
  ('partner_bank_accounts',       'argent — l''IBAN vers lequel part un virement'),
  ('tier_ribs',                   'argent — RIB d''un compte de tiers'),
  ('payment_terms',               'comptabilité — l''échéance de toutes les pièces'),
  ('reminder_levels',             'argent — la politique de relance'),
  ('analytic_sections',           'comptabilité analytique'),
  ('analytic_plans',              'comptabilité analytique'),
  ('analytic_distribution_lines', 'comptabilité analytique — une ventilation'),
  ('entry_templates',             'comptabilité — modèle de saisie');

DO $$
DECLARE r record; v_action text; v_garde text; v_qual text; v_wc text; v_n int := 0;
BEGIN
  FOR r IN
    SELECT c.relname AS table_name, p.polname, p.polcmd,
           coalesce(pg_get_expr(p.polqual, p.polrelid), '') AS qual,
           coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') AS wc
    FROM pg_policy p
    JOIN pg_class c ON c.oid = p.polrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
    JOIN t274_tables t ON t.table_name = c.relname
    WHERE p.polpermissive AND p.polcmd IN ('a', 'w', 'd', '*')
    ORDER BY c.relname, p.polcmd
  LOOP
    IF r.qual LIKE '%can_perform%' OR r.wc LIKE '%can_perform%' THEN CONTINUE; END IF;

    IF r.polcmd = '*' THEN
      EXECUTE format('DROP POLICY %I ON public.%I', r.polname, r.table_name);
      EXECUTE format('CREATE POLICY %I ON public.%I FOR SELECT USING (%s)',
                     r.table_name || '_select', r.table_name, r.qual);
      EXECUTE format('CREATE POLICY %I ON public.%I FOR INSERT WITH CHECK ((%s) AND can_perform(%L, ''insert''))',
                     r.table_name || '_insert', r.table_name, coalesce(nullif(r.wc, ''), r.qual), r.table_name);
      EXECUTE format('CREATE POLICY %I ON public.%I FOR UPDATE USING ((%s) AND can_perform(%L, ''update'')) WITH CHECK ((%s) AND can_perform(%L, ''update''))',
                     r.table_name || '_update', r.table_name, r.qual, r.table_name, coalesce(nullif(r.wc, ''), r.qual), r.table_name);
      EXECUTE format('CREATE POLICY %I ON public.%I FOR DELETE USING ((%s) AND can_perform(%L, ''delete''))',
                     r.table_name || '_delete', r.table_name, r.qual, r.table_name);
      v_n := v_n + 4;
      CONTINUE;
    END IF;

    v_action := CASE r.polcmd WHEN 'a' THEN 'insert' WHEN 'w' THEN 'update' ELSE 'delete' END;
    v_garde := format('can_perform(%L, %L)', r.table_name, v_action);
    IF r.polcmd = 'a' THEN
      v_wc := CASE WHEN r.wc = '' THEN v_garde ELSE format('(%s) AND %s', r.wc, v_garde) END;
      EXECUTE format('ALTER POLICY %I ON public.%I WITH CHECK (%s)', r.polname, r.table_name, v_wc);
    ELSIF r.polcmd = 'd' THEN
      v_qual := CASE WHEN r.qual = '' THEN v_garde ELSE format('(%s) AND %s', r.qual, v_garde) END;
      EXECUTE format('ALTER POLICY %I ON public.%I USING (%s)', r.polname, r.table_name, v_qual);
    ELSE
      v_qual := CASE WHEN r.qual = '' THEN v_garde ELSE format('(%s) AND %s', r.qual, v_garde) END;
      v_wc := CASE WHEN r.wc = '' THEN v_garde ELSE format('(%s) AND %s', r.wc, v_garde) END;
      EXECUTE format('ALTER POLICY %I ON public.%I USING (%s) WITH CHECK (%s)', r.polname, r.table_name, v_qual, v_wc);
    END IF;
    v_n := v_n + 1;
  END LOOP;
  RAISE NOTICE '[X2/M8] % politique(s) d''écriture gardée(s) par can_perform sur % table(s)', v_n, (SELECT count(*) FROM t274_tables);
END $$;
