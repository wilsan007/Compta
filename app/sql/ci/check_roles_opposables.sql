-- ============================================================
-- check_roles_opposables.sql — PERM-01 : le rôle doit être opposable sur le
--                               périmètre déclaré
--
-- LE DÉFAUT QUE CE CONTRÔLE FERME. La matrice des droits (`hasPermission` côté
-- navigateur, `can_perform` côté base) n'est opposable que si la politique RLS
-- la porte. Mesuré le 24/09/2026 (`scenarios/M18_role_non_opposable.sql`) : un
-- `viewer` créait une facture et supprimait un client par appel direct — 7
-- politiques sur 2 296 regardaient le rôle. La 239 a posé la garde sur le
-- périmètre de la décision `D-6` ; ce contrôle la garde là.
--
-- LA RÈGLE. Toute table du périmètre doit porter `can_perform(...)` dans TOUTES
-- ses politiques d'écriture permissives (insert / update / delete). Une seule
-- politique sans garde suffirait à rouvrir la porte : le contrôle exige la garde
-- sur chacune, pas sur l'une d'elles. La liste est gelée **ici** et dans la
-- migration : une table qui entre au périmètre s'inscrit des deux côtés, une
-- table qui en sort s'en retire des deux côtés, dans le même commit.
--
-- CE QUE LE CONTRÔLE NE PROUVE PAS. Il lit le texte des politiques : il ne dit
-- pas qu'un `viewer` est réellement refusé — c'est le rôle des scénarios 239,
-- qui posent le JWT et mesurent l'effet. Il ne couvre pas non plus la lecture :
-- le choix assumé de la 239 est que la lecture reste cloisonnée par la société
-- seule (un `viewer` doit lire), et la suite 105 le prouve sur 340 tables.
--
-- L'ÉTAT DATÉ DU RESTE, ET POURQUOI IL EST PUBLIÉ. Les tables hors périmètre
-- gardent la garde de société : c'est mesuré et affiché à chaque exécution
-- (`% table(s) hors périmètre`). Le jour où une de ces tables devient sensible,
-- le chiffre baisse et la liste s'allonge — la décision `D-6` est une tranche,
-- pas une omission silencieuse.
-- ============================================================

\set ON_ERROR_STOP on

-- ------------------------------------------------------------
-- 1. Le périmètre, identique à celui de la 239
-- ------------------------------------------------------------
CREATE TEMP TABLE roles_perimetre (table_name text PRIMARY KEY);
INSERT INTO roles_perimetre (table_name) VALUES
  ('invoices'), ('invoice_lines'), ('credit_notes'), ('credit_note_lines'),
  ('quotes'), ('quote_lines'), ('sales_orders'), ('sales_order_lines'),
  ('delivery_notes'), ('delivery_note_lines'),
  ('purchase_invoices'), ('purchase_invoice_lines'), ('purchase_credit_notes'),
  ('purchase_credit_lines'), ('purchase_orders'), ('purchase_order_lines'),
  ('customers'), ('suppliers'), ('customer_payments'), ('supplier_payments'),
  ('payment_orders'), ('bank_accounts'), ('bank_transactions'),
  ('journal_entries'), ('journal_lines'), ('chart_accounts'),
  ('fiscal_years'), ('vat_returns'), ('company_settings'),
  ('employees'), ('pay_runs'), ('pay_slips'), ('timesheets'),
  ('leave_requests'), ('expense_reports'), ('expense_report_lines'),
  ('products'), ('stock_movements'), ('projects'), ('project_tasks'),
  ('project_time_entries');

-- ------------------------------------------------------------
-- 2. Le détecteur
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW pg_temp.w_ecritures AS
SELECT c.relname AS table_name, p.polname, p.polcmd,
       (coalesce(pg_get_expr(p.polqual, p.polrelid), '') LIKE '%can_perform%'
        OR coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') LIKE '%can_perform%') AS gardee
FROM pg_policy p
JOIN pg_class c ON c.oid = p.polrelid
JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
WHERE n.nspname = 'public' AND p.polpermissive AND p.polcmd IN ('a', 'w', 'd');

-- ------------------------------------------------------------
-- 3. L'auto-test : deux politiques sur une table témoin, une gardée, une nue.
--    Le détecteur doit les distinguer — sans quoi il annoncerait « tout est
--    gardé » sur une base où rien ne l'est.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS public.perm_selftest;
CREATE TABLE public.perm_selftest (id uuid PRIMARY KEY, tenant_id uuid NOT NULL);
CREATE POLICY perm_selftest_gardee ON public.perm_selftest
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id() AND can_perform('perm_selftest', 'insert'));
CREATE POLICY perm_selftest_nue ON public.perm_selftest
  FOR DELETE USING (tenant_id = current_tenant_id());

DO $$
DECLARE v_gardee boolean; v_nue boolean;
BEGIN
  SELECT gardee INTO v_gardee FROM pg_temp.w_ecritures
  WHERE table_name = 'perm_selftest' AND polname = 'perm_selftest_gardee';
  SELECT gardee INTO v_nue FROM pg_temp.w_ecritures
  WHERE table_name = 'perm_selftest' AND polname = 'perm_selftest_nue';
  IF v_gardee IS DISTINCT FROM true OR v_nue IS DISTINCT FROM false THEN
    RAISE EXCEPTION '[PERM-01] le détecteur est aveugle : gardée=%, nue=%', v_gardee, v_nue;
  END IF;
END $$;

DROP TABLE public.perm_selftest;

-- ------------------------------------------------------------
-- 4. Le verdict
-- ------------------------------------------------------------
DO $$
DECLARE
  v_sans_garde text;
  v_absentes text;
  v_hors int;
  v_gardees int;
BEGIN
  SELECT string_agg(t.table_name || ' (' || coalesce(x.nues, 'aucune politique d''écriture') || ')',
                    ', ' ORDER BY t.table_name)
    INTO v_sans_garde
  FROM roles_perimetre t
  LEFT JOIN (
    SELECT table_name, string_agg(polname, ' + ' ORDER BY polname) AS nues
    FROM pg_temp.w_ecritures WHERE NOT gardee GROUP BY table_name
  ) x ON x.table_name = t.table_name
  WHERE x.nues IS NOT NULL
     OR NOT EXISTS (SELECT 1 FROM pg_temp.w_ecritures w WHERE w.table_name = t.table_name);

  SELECT string_agg(t.table_name, ', ' ORDER BY t.table_name) INTO v_absentes
  FROM roles_perimetre t
  WHERE NOT EXISTS (SELECT 1 FROM pg_class c
                    JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
                    WHERE c.relname = t.table_name AND c.relkind = 'r');

  SELECT count(DISTINCT table_name) INTO v_gardees FROM pg_temp.w_ecritures WHERE gardee;

  SELECT count(DISTINCT table_name) INTO v_hors
  FROM pg_temp.w_ecritures
  WHERE table_name NOT IN (SELECT table_name FROM roles_perimetre);

  RAISE NOTICE '[PERM-01] % table(s) écrivent avec un rôle opposable ; % autre(s) restent sous la garde de société seule (état daté de la décision D-6).',
    v_gardees, v_hors;

  IF v_absentes IS NOT NULL THEN
    RAISE EXCEPTION '[PERM-01] table(s) du périmètre absentes du schéma — retirer la ligne du périmètre dans le même commit : %', v_absentes;
  END IF;

  IF v_sans_garde IS NOT NULL THEN
    RAISE EXCEPTION E'[PERM-01] table(s) du périmètre sans garde `can_perform` sur toutes leurs politiques d''écriture :\n  %\n'
      '  Ajoutez la garde (migration 239 et ce fichier), ou retirez la table du périmètre avec sa raison.',
      v_sans_garde;
  END IF;

  RAISE NOTICE '[PERM-01] toutes les politiques d''écriture du périmètre portent la matrice des rôles.';
END $$;

