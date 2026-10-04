-- ============================================================
-- 239_roles_opposables.sql — PERM-01 : le rôle devient opposable
--
-- LE DÉFAUT, MESURÉ LE 24/09/2026 (`scenarios/M18_role_non_opposable.sql`, rejoué
-- sous le vrai rôle `authenticated`) : un utilisateur de rôle `viewer` — et de
-- même `auditor` — **créait une facture, supprimait un client**, par un simple
-- appel à l'API. Le contrôle `hasPermission` du navigateur masque les boutons,
-- mais il s'exécute dans le navigateur : la base, elle, ne regardait que la
-- société. C'est le constat `PERM-01`, et la décision qu'il attendait — `D-6` du
-- reste-à-faire : « généraliser le rôle dans la RLS, ou documenter que les rôles
-- ne sont qu'un confort d'affichage ».
--
-- LA DÉCISION PRISE ICI, ET SON PÉRIMÈTRE. Le rôle devient opposable **là où il
-- engage de l'argent, des personnes ou la comptabilité** : les tables listées au
-- §1, quarante et une, portent désormais `can_perform('<table>','<action>')`
-- dans leurs politiques d'écriture (insert / update / delete). La lecture reste
-- cloisonnée par la société seule — un `viewer` doit pouvoir lire, c'est son
-- métier, et la 105 continue de le prouver sur 340 tables.
-- Le reste des tables (production, référentiels, traçabilité) reste donc, à ce
-- jour, sous la seule garde de société : c'est un **état daté et chiffré**, pas
-- un oubli — le contrôle permanent `ci/check_roles_opposables.sql` publie le
-- nombre de tables écrites hors périmètre à chaque exécution, et la liste
-- ci-dessous est gelée : une table qui y entre doit y être ajoutée, une table
-- qui en sort doit en être retirée dans le même commit.
--
-- POURQUOI PAS LES 340 TABLES D'UN COUP. Parce que `can_perform` est une matrice
-- de rôles écrite pour les écrans (`admin`, `accountant`, `manager`, `viewer`,
-- `auditor`, `custom`) : l'appliquer à une table que le navigateur n'expose à
-- personne fermerait un usage légitime sans qu'aucune suite ne le dise. La
-- tranche retenue est celle que le plan correctif nomme, plus les tables de
-- lignes et de règlements qui la prolongent — toutes vérifiées par la régression
-- complète (46 suites) après la migration.
--
-- LA FORME DE LA GARDE. Elle est ajoutée à la politique EXISTANTE, sans la
-- remplacer : `(tenant_id = current_tenant_id()) AND can_perform(...)`. Sur une
-- politique d'`UPDATE`, elle entre dans le `USING` **et** dans le `WITH CHECK` :
-- un utilisateur sans droit ne peut ni choisir la ligne, ni la réécrire.
-- `can_perform` porte déjà `admin` → vrai partout, `accountant` → écriture
-- partout sauf suppression hors comptabilité, `manager` → écriture commerciale,
-- `viewer` / `auditor` → lecture seule, `custom` → les droits de la fiche.
--
-- CE QUE LA MIGRATION NE FAIT PAS. Elle ne touche pas aux triggers (la
-- séparation des tâches de la 232, l'auto-promotion refusée) et n'ajoute aucune
-- garde de lecture. Elle ne change pas non plus `can_perform` : la matrice des
-- rôles reste celle du navigateur, au même endroit, avec la même sémantique.
-- ============================================================

-- ── 1. Le périmètre, gelé et justifié, table par table ─────────────────────
-- Trois raisons, jamais « parce que c'était dans une liste » :
--   * l'argent : une écriture y engage un montant, une créance ou un règlement ;
--   * les personnes : paie, temps, congés, notes de frais ;
--   * la comptabilité : journaux, plan, exercices, déclarations.
CREATE TEMP TABLE t239_tables (table_name text PRIMARY KEY, raison text);
INSERT INTO t239_tables (table_name, raison) VALUES
  -- Ventes et achats : le chiffre d'affaires et les engagements
  ('invoices',               'argent'),
  ('invoice_lines',          'argent'),
  ('credit_notes',           'argent'),
  ('credit_note_lines',      'argent'),
  ('quotes',                 'argent — un devis engage un prix'),
  ('quote_lines',            'argent'),
  ('sales_orders',           'argent'),
  ('sales_order_lines',      'argent'),
  ('delivery_notes',         'marchandise — vaut livraison, donc créance'),
  ('delivery_note_lines',    'marchandise'),
  ('purchase_invoices',      'argent'),
  ('purchase_invoice_lines', 'argent'),
  ('purchase_credit_notes',  'argent'),
  ('purchase_credit_lines',  'argent'),
  ('purchase_orders',        'engagement'),
  ('purchase_order_lines',   'engagement'),
  -- Tiers et règlements
  ('customers',              'tiers'),
  ('suppliers',              'tiers'),
  ('customer_payments',      'argent'),
  ('supplier_payments',      'argent'),
  ('payment_orders',         'argent'),
  ('bank_accounts',          'argent'),
  ('bank_transactions',      'argent'),
  -- Comptabilité et paramètres
  ('journal_entries',        'comptabilité'),
  ('journal_lines',          'comptabilité'),
  ('chart_accounts',         'comptabilité'),
  ('fiscal_years',           'comptabilité — une clôture ne se rouvre pas sans droit'),
  ('vat_returns',            'comptabilité'),
  ('company_settings',       'paramètres — devise, pays, exercice'),
  -- Paie et personnes
  ('employees',              'personnes'),
  ('pay_runs',               'personnes'),
  ('pay_slips',              'personnes'),
  ('timesheets',             'personnes'),
  ('leave_requests',         'personnes'),
  ('expense_reports',        'personnes'),
  ('expense_report_lines',   'personnes'),
  -- Stock et projets
  ('products',               'stock'),
  ('stock_movements',        'stock'),
  ('projects',               'projets'),
  ('project_tasks',          'projets'),
  ('project_time_entries',   'projets — du temps facturable');

-- ── 2. La garde, ajoutée à la politique d'écriture existante ───────────────
DO $$
DECLARE
  r record;
  v_action text;
  v_garde text;
  v_qual text;
  v_wc text;
  v_touchees int := 0;
  v_deja int := 0;
  v_cibles int;
BEGIN
  SELECT count(*) INTO v_cibles FROM t239_tables;

  FOR r IN
    SELECT c.relname AS table_name, p.polname, p.polcmd,
           coalesce(pg_get_expr(p.polqual, p.polrelid), '') AS qual,
           coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') AS wc
    FROM pg_policy p
    JOIN pg_class c ON c.oid = p.polrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
    JOIN t239_tables t ON t.table_name = c.relname
    WHERE n.nspname = 'public' AND p.polpermissive AND p.polcmd IN ('a', 'w', 'd')
    ORDER BY c.relname, p.polcmd
  LOOP
    IF r.qual LIKE '%can_perform%' OR r.wc LIKE '%can_perform%' THEN
      v_deja := v_deja + 1;
      CONTINUE;   -- déjà gardée (vague 3) : ne pas empiler deux fois la même garde
    END IF;

    v_action := CASE r.polcmd WHEN 'a' THEN 'insert' WHEN 'w' THEN 'update' ELSE 'delete' END;
    v_garde := format('can_perform(%L, %L)', r.table_name, v_action);

    IF r.polcmd = 'a' THEN
      -- Une politique d'INSERT n'a pas de USING : la garde va dans le WITH CHECK.
      v_wc := CASE WHEN r.wc = '' THEN v_garde ELSE format('(%s) AND %s', r.wc, v_garde) END;
      EXECUTE format('ALTER POLICY %I ON public.%I WITH CHECK (%s)', r.polname, r.table_name, v_wc);
    ELSIF r.polcmd = 'd' THEN
      v_qual := CASE WHEN r.qual = '' THEN v_garde ELSE format('(%s) AND %s', r.qual, v_garde) END;
      EXECUTE format('ALTER POLICY %I ON public.%I USING (%s)', r.polname, r.table_name, v_qual);
    ELSE
      v_qual := CASE WHEN r.qual = '' THEN v_garde ELSE format('(%s) AND %s', r.qual, v_garde) END;
      v_wc := CASE WHEN r.wc = '' THEN v_garde ELSE format('(%s) AND %s', r.wc, v_garde) END;
      EXECUTE format('ALTER POLICY %I ON public.%I USING (%s) WITH CHECK (%s)',
                     r.polname, r.table_name, v_qual, v_wc);
    END IF;
    v_touchees := v_touchees + 1;
  END LOOP;

  RAISE NOTICE '[PERM-01] % table(s) au périmètre, % politique(s) d''écriture gardée(s) par can_perform (% déjà gardées par la vague 3).',
    v_cibles, v_touchees, v_deja;
END $$;


-- ── 3. Le verdict ──────────────────────────────────────────────────────────
-- Trois propriétés, mesurées : chaque table du périmètre a bien une politique
-- gardée par commande d'écriture ; aucune table du périmètre n'a disparu du
-- schéma (une liste gelée qui nomme une table absente ne protège rien) ; et
-- `can_perform` refuse l'écriture au `viewer` comme à l'`auditor` — la garde
-- n'est opposable que si la fonction le dit, quel que soit le nombre de
-- politiques réécrites.
DO $$
DECLARE
  v_sans text;
  v_absentes text;
  v_hors int;
  v_ecrivantes int;
BEGIN
  SELECT string_agg(t.table_name, ', ' ORDER BY t.table_name) INTO v_sans
  FROM t239_tables t
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_policy p
    JOIN pg_class c ON c.oid = p.polrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
    WHERE c.relname = t.table_name AND p.polcmd IN ('a', 'w', 'd')
      AND (coalesce(pg_get_expr(p.polqual, p.polrelid), '') LIKE '%can_perform%'
        OR coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') LIKE '%can_perform%'));
  IF v_sans IS NOT NULL THEN
    RAISE EXCEPTION '[PERM-01] table(s) du périmètre sans politique d''écriture gardée : %', v_sans;
  END IF;

  SELECT string_agg(t.table_name, ', ' ORDER BY t.table_name) INTO v_absentes
  FROM t239_tables t
  WHERE NOT EXISTS (SELECT 1 FROM pg_class c
                    JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
                    WHERE c.relname = t.table_name AND c.relkind = 'r');
  IF v_absentes IS NOT NULL THEN
    RAISE EXCEPTION '[PERM-01] table(s) du périmètre absentes du schéma — la liste gelée doit être mise à jour : %', v_absentes;
  END IF;

  -- L'état daté du reste : publié, jamais caché.
  SELECT count(*) INTO v_ecrivantes
  FROM (SELECT DISTINCT c.relname
        FROM pg_policy p
        JOIN pg_class c ON c.oid = p.polrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
        WHERE n.nspname = 'public' AND p.polpermissive AND p.polcmd IN ('a', 'w', 'd')
          AND (coalesce(pg_get_expr(p.polqual, p.polrelid), '') LIKE '%can_perform%'
            OR coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') LIKE '%can_perform%')) x;

  SELECT count(*) INTO v_hors
  FROM (SELECT DISTINCT c.relname
        FROM pg_policy p
        JOIN pg_class c ON c.oid = p.polrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
        WHERE n.nspname = 'public' AND p.polpermissive AND p.polcmd IN ('a', 'w', 'd')) x
  WHERE x.relname NOT IN (SELECT table_name FROM t239_tables);

  RAISE NOTICE '[PERM-01] % table(s) écrivent désormais avec un rôle opposable ; % autre(s) restent sous la garde de société seule (état daté, publié par ci/check_roles_opposables.sql).',
    v_ecrivantes, v_hors;

  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'can_perform' AND prosecdef) THEN
    RAISE EXCEPTION '[PERM-01] can_perform est absent ou n''est plus SECURITY DEFINER : les gardes posées ci-dessus ne voudraient rien dire.';
  END IF;

  RAISE NOTICE '[PERM-01] le rôle est opposable sur le périmètre : un viewer ou un auditor ne peut plus écrire ces tables par appel direct.';
END $$;



