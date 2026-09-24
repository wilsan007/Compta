-- ============================================================
-- 238_policy_dedup.sql — ISO-03 / ISO-04 : la politique jumelle qui annule la garde
--
-- LE DÉFAUT, MESURÉ LE 24/09/2026 SUR BASE NEUVE (237 migrations). **495 couples
-- (table, commande) portent DEUX politiques permissives** sur 127 tables, soit
-- 1 001 politiques. Le motif est toujours le même : une politique générique
-- `tenant_select` / `tenant_insert` … posée par la migration 74, **et** une
-- politique par table `tenant_select_<table>` posée par la 84 et les suivantes.
-- Les tables de la vague 3 sont plus explicites encore : `machines` porte
-- `tenant_update` ET `tenant_update_machines`, la seconde avec
-- `can_perform('machines','update')` — 57 gardes de droits sont dans ce cas.
--
-- POURQUOI C'EST UNE FAILLE, ET PAS UNE REDONDANCE. Deux politiques permissives
-- sur une même (table, commande) sont **OU**-ées par PostgreSQL : la plus large
-- gagne. La garde `can_perform` de la politique par table n'est donc jamais
-- atteinte — un `viewer` peut créer, modifier et supprimer par appel direct à
-- PostgREST, quel que soit ce que l'écran affiche. C'était le constat `ISO-03`
-- (« 38 gardes `can_perform` annulées ») ; l'`ISO-04` y ajoutait 11 index en
-- double, dont deux contraintes d'unicité identiques sur `pay_slips`.
--
-- LA RÈGLE DU CHOIX, écrite une fois et appliquée aux 495 couples. On garde UNE
-- politique, choisie par ce qu'elle porte, dans cet ordre :
--   1. une garde `can_perform` — la plus étroite, et celle dont le retour rend
--      la 239 possible ;
--   2. une condition de rôle ou de module (`current_user_role`,
--      `current_module_role`, `has_module_access`, appartenance à
--      `tenant_users`, `current_tenant_user_id`) — c'est la politique écrite
--      pour la table, pas la politique générique ;
--   3. un nom qui se termine par celui de sa table (`…_<table>`) — le nom le
--      plus précis ;
--   4. à égalité, le nom le plus long, puis l'ordre alphabétique : déterministe,
--      et **aucun couple n'a besoin de cette règle** (mesuré : les 495 couples
--      sont tranchés par 1, 2 ou 3).
-- Les deux seuls couples où deux politiques de portée égale s'affrontent sont
-- inscrits **à la main**, avec leur raison, dans `t238_exceptions` — un choix de
-- sécurité ne doit pas dépendre d'un départ d'égalité.
--
-- CE QUE LA 238 NE FAIT PAS. Elle ne rend opposables que les tables qui portaient
-- DÉJÀ une garde (57 couples, 21 tables) : les autres gardent leur politique
-- par table sans `can_perform`, donc la société seule — c'est l'objet de la 239
-- (rôles opposables). Elle ne juge pas non plus deux politiques de même portée
-- sémantique : elle en retire une, sans décider laquelle des deux expressions
-- était « la bonne ».
-- ============================================================

-- ── 1. Les décisions, construites puis relues avant d'être appliquées ────────
-- Les tables qui portent au moins une politique AVANT le retrait : c'est la
-- référence du contrôle de fin, et elle doit être prise maintenant — une table
-- qui perdrait TOUTES ses politiques deviendrait illisible selon sa RLS.
CREATE TEMP TABLE t238_tables AS
SELECT DISTINCT c.relname AS table_name
FROM pg_policy p
JOIN pg_class c ON c.oid = p.polrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public';

CREATE TEMP TABLE t238_candidats AS
WITH d AS (
  SELECT p.polrelid, p.polcmd
  FROM pg_policy p
  JOIN pg_class c ON c.oid = p.polrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND p.polpermissive
  GROUP BY 1, 2 HAVING count(*) > 1
)
SELECT p.polname,
       c.relname AS table_name,
       p.polcmd,
       coalesce(pg_get_expr(p.polqual, p.polrelid), '') AS qual,
       coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') AS with_check,
       (coalesce(pg_get_expr(p.polqual, p.polrelid), '') LIKE '%can_perform%'
        OR coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') LIKE '%can_perform%') AS gardee,
       (coalesce(pg_get_expr(p.polqual, p.polrelid), '') || ' ' ||
        coalesce(pg_get_expr(p.polwithcheck, p.polrelid), ''))
         ~ '(current_user_role|current_module_role|has_module_access|tenant_users|current_tenant_user_id)' AS ciblee,
       (p.polname LIKE '%\_' || c.relname) AS nomme_table,
       length(p.polname) AS longueur
FROM pg_policy p
JOIN pg_class c ON c.oid = p.polrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN d ON d.polrelid = p.polrelid AND d.polcmd = p.polcmd
WHERE n.nspname = 'public' AND p.polpermissive;

-- Les deux couples où la règle ne tranche pas honnêtement. `banks` et
-- `chart_account_templates` sont des référentiels GLOBAUX : leurs deux
-- politiques de lecture autorisent soit « toute session ouverte »
-- (`global_select_*`), soit « tout le monde, même sans jeton »
-- (`…_select_*` avec `USING (true)`). Garder la seconde élargirait la lecture à
-- `anon` — l'inverse du but de la vague. Le choix est donc écrit ici, pas
-- déduit d'un départ d'égalité.
CREATE TEMP TABLE t238_exceptions (table_name text, cmd text, garder text, raison text);
INSERT INTO t238_exceptions VALUES
  ('banks', 'r', 'global_select_banks',
   'Référentiel bancaire global, sans tenant_id : `global_select_banks` exige une session (`auth.uid() IS NOT NULL`), `tenant_select_banks` laisse `USING (true)`, donc lisible sans jeton. On garde la plus étroite.'),
  ('chart_account_templates', 'r', 'global_select_chart_account_templates',
   'Modèles de plan comptable, référentiel global : même arbitrage que `banks` — la politique qui exige une session est conservée.');

-- ── 2. Le classement, puis le retrait ───────────────────────────────────────
CREATE TEMP TABLE t238_decisions AS
SELECT c.table_name, c.polcmd, c.polname, c.gardee, c.ciblee, c.nomme_table,
  row_number() OVER (
    PARTITION BY c.table_name, c.polcmd
    ORDER BY (c.polname = e.garder) DESC,                       -- la décision écrite à la main d'abord
             (coalesce(c.gardee, false)::int * 8
              + coalesce(c.ciblee, false)::int * 4
              + coalesce(c.nomme_table, false)::int * 2) DESC,   -- puis la règle, dans l'ordre des critères
             c.longueur DESC, c.polname ASC                       -- à égalité : déterministe, jamais atteint
  ) AS rang,
  e.raison
FROM t238_candidats c
LEFT JOIN t238_exceptions e ON e.table_name = c.table_name AND e.cmd = c.polcmd AND e.garder = c.polname;

DO $$
DECLARE
  v_couples int; v_politiques int; v_retirees int; v_sans_regle int; v_perimee text;
BEGIN
  SELECT count(DISTINCT (table_name, polcmd)), count(*) INTO v_couples, v_politiques FROM t238_decisions;

  -- Un classement qui ne saurait pas trancher ne doit pas retirer au hasard.
  SELECT count(*) INTO v_sans_regle FROM (
    SELECT table_name, polcmd,
           count(*) FILTER (WHERE coalesce(gardee, false) OR coalesce(ciblee, false) OR coalesce(nomme_table, false)) AS tranchants
    FROM t238_candidats GROUP BY 1, 2 HAVING count(*) > 1
  ) x WHERE x.tranchants = 0;
  IF v_sans_regle > 0 THEN
    RAISE EXCEPTION '[ISO-03] % couple(s) où aucune politique ne porte ni garde, ni rôle, ni nom de table — la règle ne peut pas trancher sans risquer de garder la plus large. Inscrivez-les dans t238_exceptions.', v_sans_regle;
  END IF;

  IF v_couples < 400 THEN
    RAISE EXCEPTION '[ISO-03] le relevé ne trouve que % couple(s) doublé(s) : le détecteur est cassé, ou le schéma n''est pas chargé', v_couples;
  END IF;

  -- Les deux exceptions doivent exister et désigner une politique réelle.
  SELECT string_agg(e.table_name || '(' || e.cmd || ')', ', ' ORDER BY e.table_name)
    INTO v_perimee
  FROM t238_exceptions e
  WHERE NOT EXISTS (SELECT 1 FROM t238_candidats c
                    WHERE c.table_name = e.table_name AND c.polcmd = e.cmd AND c.polname = e.garder);
  IF v_perimee IS NOT NULL THEN
    RAISE EXCEPTION '[ISO-03] exception périmée : la politique à garder n''existe plus pour %', v_perimee;
  END IF;

  SELECT count(*) INTO v_retirees FROM t238_decisions WHERE rang > 1;

  RAISE NOTICE '[ISO-03] % couple(s) (table, commande), % politique(s) permissive(s) : % retirée(s), 1 conservée par couple.',
    v_couples, v_politiques, v_retirees;
END $$;

-- Le retrait, nommément, une politique à la fois.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT d.table_name, d.polname
    FROM t238_decisions d
    WHERE d.rang > 1
    ORDER BY d.table_name, d.polcmd, d.polname
  LOOP
    EXECUTE format('DROP POLICY %I ON public.%I', r.polname, r.table_name);
  END LOOP;
END $$;



-- ── 3. Les index en double (ISO-04) ─────────────────────────────────────────
-- Même méthode : on garde celui dont le nom dit ce qu'il indexe, on retire
-- l'abrégé. Mesuré sur base neuve : 12 couples (la mesure du 24/09 en comptait
-- 11 ; le douzième est `purchase_orders`, deux index de MÊMES colonnes dont l'un
-- trie `order_date DESC` — un arbre binaire se parcourt dans les deux sens, la
-- copie n'apporte rien).
-- `pay_slips` est le seul cas particulier : ce ne sont pas des index libres mais
-- DEUX contraintes d'unicité identiques sur `(tenant_id, number)`. Une seule
-- suffit ; on garde celle que la migration 76 a créée nommément
-- (`uniq_pay_slip_number_tenant`), et l'on retire celle que Supabase a
-- auto-nommée à la création de la table — aucun code ne la référence (vérifié).
DROP INDEX IF EXISTS public.idx_bank_recon_rules_tenant;          -- doublon de idx_bank_reconciliation_rules_tenant
DROP INDEX IF EXISTS public.idx_bank_stmt_imports_tenant;         -- doublon de idx_bank_statement_imports_tenant
DROP INDEX IF EXISTS public.idx_currency_reval_tenant;            -- doublon de idx_currency_revaluations_tenant
DROP INDEX IF EXISTS public.idx_customers_name;                   -- mêmes colonnes que idx_customers_tenant_name (le nom trompait)
DROP INDEX IF EXISTS public.idx_emp_docs_employee;                -- doublon de idx_employee_documents_employee
DROP INDEX IF EXISTS public.idx_mirror_verification_tenant;       -- doublon de idx_mirror_verification_details_tenant
DROP INDEX IF EXISTS public.idx_purchase_orders_status;           -- mêmes colonnes que idx_purchase_orders_tenant_status
DROP INDEX IF EXISTS public.idx_regularization_tenant;            -- doublon de idx_regularization_entries_tenant
DROP INDEX IF EXISTS public.idx_stock_movements_product;          -- doublon de idx_stock_movements_product_id
DROP INDEX IF EXISTS public.idx_tier_ribs_tp;                     -- doublon de idx_tier_ribs_third_party_account_id
DROP INDEX IF EXISTS public.idx_tvs_tenant;                       -- doublon de idx_tvs_declarations_tenant
ALTER TABLE public.pay_slips DROP CONSTRAINT IF EXISTS pay_slips_tenant_number_key;


-- ── 4. La preuve, dans la migration elle-même ───────────────────────────────
DO $$
DECLARE
  v_doubles int; v_examinees int; v_index int; v_orphelines text; v_gardees int;
BEGIN
  SELECT count(*) INTO v_doubles
  FROM (SELECT p.polrelid, p.polcmd
        FROM pg_policy p
        JOIN pg_class c ON c.oid = p.polrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND p.polpermissive
        GROUP BY 1, 2 HAVING count(*) > 1) x;

  SELECT count(*) INTO v_examinees
  FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND p.polpermissive;

  -- Une table qui portait des politiques et n'en a plus AUCUNE serait devenue
  -- illisible — ou pire, lisible par qui ne devrait pas : c'est le risque d'un
  -- retrait mal ciblé. On compare à l'état mesuré en début de migration.
  SELECT string_agg(t.table_name, ', ' ORDER BY t.table_name) INTO v_orphelines
  FROM t238_tables t
  WHERE NOT EXISTS (SELECT 1 FROM pg_policy p
                    JOIN pg_class c ON c.oid = p.polrelid
                    WHERE c.relname = t.table_name);

  SELECT count(*) INTO v_index
  FROM (SELECT i.indrelid, i.indkey::text, i.indisunique, i.indexprs::text, i.indpred::text
        FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
        GROUP BY 1, 2, 3, 4, 5 HAVING count(*) > 1) x;

  SELECT count(*) INTO v_gardees
  FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND (coalesce(pg_get_expr(p.polqual, p.polrelid), '') LIKE '%can_perform%'
      OR coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') LIKE '%can_perform%');

  RAISE NOTICE '[ISO-03] après dédoublonnage : % politique(s) permissive(s), dont % portant une garde ; % couple(s) doublé(s) restant(s).',
    v_examinees, v_gardees, v_doubles;
  RAISE NOTICE '[ISO-04] index en double restants : %', v_index;

  IF v_doubles > 0 THEN
    RAISE EXCEPTION '[ISO-03] % couple(s) (table, commande) portent encore plusieurs politiques permissives : la plus large annule la plus étroite.', v_doubles;
  END IF;
  IF v_index > 0 THEN
    RAISE EXCEPTION '[ISO-04] % index en double subsistent.', v_index;
  END IF;
  IF v_orphelines IS NOT NULL THEN
    RAISE EXCEPTION '[ISO-03] table(s) cloisonnée(s) sans AUCUNE politique après le retrait : %', v_orphelines;
  END IF;
  IF v_gardees < 40 THEN
    RAISE EXCEPTION '[ISO-03] % garde(s) `can_perform` trouvée(s) — le relevé des politiques gardées est cassé (57 attendues)', v_gardees;
  END IF;

  RAISE NOTICE '[ISO-03/ISO-04] une seule politique permissive par (table, commande), aucun index en double.';
END $$;
