-- ============================================================
-- 271_viewer_writes_and_approval.sql — vague X1 : ce qu'un lecteur ne doit pas
-- pouvoir faire (audit fonctionnel exécuté du 28/09/2026 : C3, M8, M9, M12, H10)
--
-- LES DÉFAUTS, mesurés par le chemin de l'écran (PostgREST + JWT du lecteur) :
--   C3  `document_number_sequences` : un lecteur remettait le compteur à 2 ;
--       chaque validation de facture échouait ensuite sur un doublon. Les
--       tables qu'alimentent SEULES des fonctions (numérotation, quantités en
--       stock, couches de valorisation, séquences de pièces) étaient
--       écrivables par tout utilisateur connecté.
--   M8  le lecteur modifiait 16 tables hors du périmètre de la 239, créait des
--       écritures par `post_journal_entry` et relançait `calculate_payslip`
--       (deux fonctions SECURITY DEFINER : la RLS ne les arrête pas).
--   M9  l'auteur d'une facture d'achat l'approuvait lui-même, même avec
--       `enforce_segregation` ; `approved_by` n'était jamais écrit — et la
--       table n'avait pas de colonne d'auteur.
--   M12 deux politiques héritées : `analytic_distribution_lines` (tenant NULL
--       ou GUC `app.tenant_id` que personne ne pose) et `project_docs`
--       (`tenant_id = (SELECT id FROM tenants LIMIT 1)` : la première société
--       de la table, pas celle de l'utilisateur).
--
-- LES CORRECTIFS
--   1. Tables alimentées par fonction : plus aucun droit d'écriture pour
--      `authenticated` ; leurs fonctions sont toutes SECURITY DEFINER
--      (vérifié le 28/09 : 4 fonctions de numérotation, 30 de stock, 4 de
--      valorisation, 1 de séquence). Leurs politiques d'écriture tombent avec.
--   2. Le périmètre de la 239 s'étend à 19 tables (§2) : même garde
--      `can_perform` ajoutée à la politique existante. Même matrice, donc même
--      conséquence : un `manager` n'écrit pas ces tables (caisse, production,
--      réceptions, opportunités CRM) — il ne les écrivait qu'en l'absence de garde.
--      Un rôle « caissier » ou « magasinier » est une décision (D-6), pas un
--      correctif.
--   3. `post_journal_entry` et `calculate_payslip` vérifient le droit avant
--      d'écrire. Le corps de ces deux fonctions est celui de leur dernière
--      migration : la garde est INSÉRÉE après le contrôle de société, par
--      remplacement d'une ancre exacte — la migration échoue si l'ancre a
--      changé, plutôt que de réécrire 300 lignes de mémoire.
--   4. Achats : `created_by` (posé par la base, jamais par le client),
--      `approved_by` posé à l'approbation, et la séparation des tâches
--      appliquée quand la société l'a demandée.
--   5. Les deux politiques héritées disparaissent ; `project_docs` est
--      cloisonnée par `current_tenant_id()`.
--
-- Tests : 271_viewer_writes_and_approval_tests.sql (T01–T10, 8 rouges avant).
-- ============================================================

BEGIN;

-- ── 1. Tables alimentées par fonction (C3) ───────────────────
REVOKE INSERT, UPDATE, DELETE ON document_number_sequences, stock_quantities,
  stock_valuation_layers, journal_posting_sequences FROM authenticated, anon;

DROP POLICY IF EXISTS document_number_sequences_tenant ON document_number_sequences;
DROP POLICY IF EXISTS document_number_sequences_select ON document_number_sequences;
CREATE POLICY document_number_sequences_select ON document_number_sequences
  FOR SELECT USING (tenant_id = current_tenant_id());

DROP POLICY IF EXISTS tenant_insert_stock_quantities ON stock_quantities;
DROP POLICY IF EXISTS tenant_update_stock_quantities ON stock_quantities;
DROP POLICY IF EXISTS tenant_delete_stock_quantities ON stock_quantities;

DROP POLICY IF EXISTS svl_tenant_all ON stock_valuation_layers;

-- ── 2. Le périmètre opposable s'étend (M8) ───────────────────
CREATE TEMP TABLE t271_tables (table_name text PRIMARY KEY, raison text);
INSERT INTO t271_tables VALUES
  ('fiscal_periods',          'comptabilité — une période se clôt et se rouvre'),
  ('journals',                'comptabilité — le journal porte la numérotation des pièces'),
  ('bank_statement_imports',  'argent — un relevé importé crée des opérations'),
  ('warehouses',              'stock'),
  ('goods_receipts',          'stock — une réception fait entrer la marchandise'),
  ('goods_receipt_lines',     'stock'),
  ('boms',                    'production — la nomenclature fixe les consommations'),
  ('bom_lines',               'production'),
  ('manufacturing_orders',    'production — un OF terminé écrit du stock et une écriture'),
  ('pos_terminals',           'caisse'),
  ('pos_sessions',            'caisse — ouvrir une session engage le fond de caisse'),
  ('pos_tickets',             'caisse — une vente'),
  ('pos_ticket_lines',        'caisse'),
  ('pos_payments',            'caisse — un encaissement'),
  -- trouvées par le balayage du lecteur PAR L'API (src/__screen__/15_security.screen.ts)
  ('tax_rates',               'comptabilité — un taux de TVA calcule toutes les pièces'),
  ('payroll_cumulative',      'personnes — cumuls de paie (plafonds, réduction générale)'),
  ('pay_slip_clarified',      'personnes — bulletin clarifié'),
  ('document_transformations','argent — devis → commande → facture'),
  ('crm_opportunities',       'commercial — une opportunité engage un montant prévisionnel');

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
    JOIN t271_tables t ON t.table_name = c.relname
    WHERE p.polpermissive AND p.polcmd IN ('a', 'w', 'd', '*')
    ORDER BY c.relname, p.polcmd
  LOOP
    IF r.qual LIKE '%can_perform%' OR r.wc LIKE '%can_perform%' THEN CONTINUE; END IF;

    IF r.polcmd = '*' THEN
      -- Politique ALL (pos_payments) : scindée en lecture + trois écritures gardées.
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
  RAISE NOTICE '[X1/M8] % politique(s) d''écriture gardée(s) par can_perform sur % table(s)', v_n, (SELECT count(*) FROM t271_tables);

  -- Chaque table du périmètre a désormais une garde par commande d'écriture
  IF EXISTS (
    SELECT 1 FROM t271_tables t, (VALUES ('a'), ('w'), ('d')) AS cmd(c)
    WHERE NOT EXISTS (
      SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
      WHERE c.relname = t.table_name AND p.polcmd::text = cmd.c
        AND (coalesce(pg_get_expr(p.polqual, p.polrelid), '') || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), ''))
            LIKE '%can_perform%')) THEN
    RAISE EXCEPTION '[X1/M8] une table du périmètre n''a pas de politique gardée pour chaque écriture';
  END IF;
END $$;

-- ── 3. Les deux RPC SECURITY DEFINER vérifient le droit (M8, H10) ─────────
DO $$
DECLARE
  v_ancre constant text := E'  IF v_tid IS NULL THEN\n    RAISE EXCEPTION ''Aucun tenant actif'';\n  END IF;\n';
  v_def text; v_pos int; r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('post_journal_entry(jsonb,jsonb)',
     E'\n  -- X1-271 : la fonction écrit en SECURITY DEFINER, la RLS ne l''arrête pas : le droit se vérifie ici.\n'
     '  IF NOT (can_perform(''journal_entries'', ''insert'') OR has_permission(''journal_entry.create'')) THEN\n'
     '    RAISE EXCEPTION ''Permission refusée : saisie d''''écriture (journal_entries.insert)'' USING ERRCODE = ''insufficient_privilege'';\n'
     '  END IF;\n'),
    ('calculate_payslip(uuid,text,uuid)',
     E'\n  -- X1-271 (H10) : calculer un bulletin l''écrit ; un lecteur ne le relance pas.\n'
     '  IF NOT can_perform(''pay_slips'', ''update'') THEN\n'
     '    RAISE EXCEPTION ''Permission refusée : calcul des bulletins (pay_slips.update)'' USING ERRCODE = ''insufficient_privilege'';\n'
     '  END IF;\n')
  ) AS x(sig, garde) LOOP
    v_def := pg_get_functiondef(r.sig::regprocedure);
    IF position('X1-271' IN v_def) > 0 THEN CONTINUE; END IF;
    v_pos := position(v_ancre IN v_def);
    IF v_pos = 0 THEN
      RAISE EXCEPTION '[X1] ancre « Aucun tenant actif » introuvable dans % : le corps a changé, reprendre la garde à la main', r.sig;
    END IF;
    v_def := overlay(v_def PLACING v_ancre || r.garde FROM v_pos FOR length(v_ancre));
    EXECUTE v_def;
  END LOOP;
END $$;

-- ── 4. Approbation des achats : auteur, approbateur, séparation (M9) ───────
ALTER TABLE purchase_invoices ADD COLUMN IF NOT EXISTS created_by uuid;
COMMENT ON COLUMN purchase_invoices.created_by IS
  'Auteur de la saisie : posé par la base (auth.uid()) à l''insertion, jamais par le client. Lu par la séparation des tâches à l''approbation.';

CREATE OR REPLACE FUNCTION purchase_invoice_authorship()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_uid uuid := auth.uid(); v_enforce boolean := false;
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- Un appel de serveur (sans jeton) garde ce qu'il déclare ; un utilisateur ne choisit pas son auteur.
    NEW.created_by := COALESCE(v_uid, NEW.created_by);
    NEW.approved_by := NULL;
    RETURN NEW;
  END IF;

  NEW.created_by := OLD.created_by;
  IF NEW.approval_status = 'approved' AND OLD.approval_status IS DISTINCT FROM 'approved' THEN
    NEW.approved_by := COALESCE(v_uid, NEW.approved_by);
    SELECT COALESCE(enforce_segregation, false) INTO v_enforce
    FROM company_settings WHERE tenant_id = NEW.tenant_id;
    IF v_enforce AND NEW.approved_by IS NOT NULL AND NEW.approved_by = NEW.created_by THEN
      RAISE EXCEPTION 'Séparation des tâches : vous avez saisi cette facture d''achat, son approbation revient à une autre personne'
        USING ERRCODE = 'check_violation';
    END IF;
  ELSIF OLD.approval_status = 'approved' THEN
    NEW.approved_by := OLD.approved_by;
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION purchase_invoice_authorship() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS tg_purchase_invoice_authorship ON purchase_invoices;
-- Nom choisi pour passer AVANT tg_purchase_invoice_guard (ordre alphabétique des BEFORE).
CREATE TRIGGER tg_purchase_invoice_authorship
  BEFORE INSERT OR UPDATE ON purchase_invoices
  FOR EACH ROW EXECUTE FUNCTION purchase_invoice_authorship();

-- ── 5. Politiques héritées (M12) ─────────────────────────────
-- tenant_id est NOT NULL sur analytic_distribution_lines : aucune ligne
-- « sans société » n'existe ; les quatre politiques tenant_* restent.
DROP POLICY IF EXISTS tenant_isolated_analytic_dist_lines ON analytic_distribution_lines;

DROP POLICY IF EXISTS project_docs_tenant_select ON project_docs;
DROP POLICY IF EXISTS project_docs_tenant_insert ON project_docs;
DROP POLICY IF EXISTS project_docs_tenant_update ON project_docs;
DROP POLICY IF EXISTS project_docs_tenant_delete ON project_docs;
CREATE POLICY project_docs_tenant_select ON project_docs FOR SELECT USING (tenant_id = current_tenant_id());
CREATE POLICY project_docs_tenant_insert ON project_docs FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY project_docs_tenant_update ON project_docs FOR UPDATE
  USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY project_docs_tenant_delete ON project_docs FOR DELETE USING (tenant_id = current_tenant_id());

COMMIT;
