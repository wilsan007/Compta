-- ============================================================
-- check_trigger_reachability.sql
--
-- Détecte les comparaisons mortes dans les triggers : un trigger (ou une
-- branche de sa fonction) qui compare une colonne à une valeur littérale que
-- les contraintes CHECK de la table interdisent ne peut jamais se déclencher.
-- C'est ainsi qu'avaient été trouvés les 6 triggers morts de LOT1-01
-- (invoices.status vs validation_status).
--
-- Portée (élargie le 18/09/2026 — la version précédente ne regardait que le
-- motif `NEW.status = '…'` et ne prouvait rien : elle passait au vert sur un
-- schéma de 394 triggers sans faire une seule assertion) :
--   * toutes les colonnes, pas seulement `status` ;
--   * les corps de fonctions et les clauses WHEN des triggers ;
--   * les formes `= 'x'`, `<> 'x'`, `IN (…)`, `NOT IN (…)`, `= ANY (ARRAY[…])`.
--
-- Solidité : une comparaison n'est déclarée morte que si elle est impossible
-- sur *toutes* les tables où la fonction est branchée et qui portent cette
-- colonne, et seulement si l'ensemble des valeurs autorisées est connu pour
-- chacune d'elles. Une fonction générique branchée sur 40 tables ne produit
-- donc pas de faux positif.
--
-- Le script s'auto-teste (fixture volontairement morte, jouée puis annulée)
-- et échoue s'il n'a pu décider d'aucune comparaison : un vert doit signifier
-- « vérifié », pas « rien trouvé à regarder ».
-- ============================================================

\set ON_ERROR_STOP on

-- ------------------------------------------------------------
-- 1. Valeurs autorisées par colonne, lues dans les contraintes CHECK
--    énumérantes (`col = ANY (ARRAY['a', 'b'])`, forme désérialisée de IN).
--    Les contraintes contenant une négation sont ignorées : leur énumération
--    ne décrit pas l'ensemble autorisé.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW pg_temp.b3_allowed AS
WITH ck AS (
  SELECT c.conrelid AS reloid, pg_get_constraintdef(c.oid) AS def
  FROM pg_constraint c
  JOIN pg_class cl ON cl.oid = c.conrelid
  JOIN pg_namespace n ON n.oid = cl.relnamespace AND n.nspname = 'public'
  WHERE c.contype = 'c'
    AND pg_get_constraintdef(c.oid) !~* $re$(<>|!=|\mNOT\M)$re$
), seg AS (
  SELECT ck.reloid, lower(m[1]) AS col, m[2] AS arr
  FROM ck, regexp_matches(
         ck.def,
         $re$([a-z_][a-z0-9_]*)\)?(?:::[a-z][a-z ]*)?\s*=\s*ANY\s*\(+\s*ARRAY\[([^\]]*)\]$re$,
         'g') m
)
SELECT DISTINCT seg.reloid, seg.col, lit[1] AS val
FROM seg, regexp_matches(seg.arr, $re$'([^']*)'$re$, 'g') lit;

-- ------------------------------------------------------------
-- 2. Triggers et fonctions de trigger du schéma public
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW pg_temp.b3_trg AS
SELECT DISTINCT
       t.tgrelid AS reloid,
       c.relname AS tbl,
       p.oid     AS fnoid,
       p.proname AS fn,
       pg_get_functiondef(p.oid) AS src
FROM pg_trigger t
JOIN pg_proc p      ON p.oid = t.tgfoid
JOIN pg_class c     ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
WHERE NOT t.tgisinternal;

-- ------------------------------------------------------------
-- 3. Comparaisons littérales trouvées dans les corps de fonctions
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW pg_temp.b3_cmp AS
WITH fns AS (SELECT DISTINCT fnoid, fn, src FROM pg_temp.b3_trg),
eq AS (
  SELECT fnoid, fn, lower(m[1]) AS col, m[2] AS val
  FROM fns, regexp_matches(
         src,
         $re$\m(?:NEW|OLD)\.([a-z_][a-z0-9_]*)\)?(?:::[a-z][a-z ]*)?\s*(?:=|<>|!=)\s*'([^']*)'$re$,
         'gi') m
),
inlist AS (
  SELECT fnoid, fn, lower(m[1]) AS col, m[2] AS arr
  FROM fns, regexp_matches(
         src,
         $re$\m(?:NEW|OLD)\.([a-z_][a-z0-9_]*)\)?(?:::[a-z][a-z ]*)?\s*(?:(?:NOT\s+)?IN\s*\(|(?:=|<>)\s*ANY\s*\(+\s*ARRAY\[)([^)\]]*)$re$,
         'gi') m
)
SELECT fnoid, fn, col, val FROM eq
UNION
SELECT i.fnoid, i.fn, i.col, lit[1]
FROM inlist i, regexp_matches(i.arr, $re$'([^']*)'$re$, 'g') lit;

-- ------------------------------------------------------------
-- 4. Comparaisons littérales trouvées dans les clauses WHEN
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW pg_temp.b3_when_cmp AS
WITH w AS (
  SELECT t.tgrelid AS reloid,
         c.relname AS tbl,
         t.tgname::text AS tgname,
         substring(pg_get_triggerdef(t.oid) from $re$\mWHEN \((.*)\) EXECUTE$re$) AS cond
  FROM pg_trigger t
  JOIN pg_class c     ON c.oid = t.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
  WHERE NOT t.tgisinternal AND t.tgqual IS NOT NULL
), eq AS (
  SELECT reloid, tbl, tgname, lower(m[1]) AS col, m[2] AS val
  FROM w, regexp_matches(
         cond,
         $re$\m(?:new|old)\.([a-z_][a-z0-9_]*)\)?(?:::[a-z][a-z ]*)?\s*(?:=|<>|!=)\s*'([^']*)'$re$,
         'gi') m
  WHERE cond IS NOT NULL
), inlist AS (
  SELECT reloid, tbl, tgname, lower(m[1]) AS col, m[2] AS arr
  FROM w, regexp_matches(
         cond,
         $re$\m(?:new|old)\.([a-z_][a-z0-9_]*)\)?(?:::[a-z][a-z ]*)?\s*(?:(?:NOT\s+)?IN\s*\(|(?:=|<>)\s*ANY\s*\(+\s*ARRAY\[)([^)\]]*)$re$,
         'gi') m
  WHERE cond IS NOT NULL
)
SELECT reloid, tbl, tgname, col, val FROM eq
UNION
SELECT i.reloid, i.tbl, i.tgname, i.col, lit[1]
FROM inlist i, regexp_matches(i.arr, $re$'([^']*)'$re$, 'g') lit;

-- ------------------------------------------------------------
-- 5. Verdict par comparaison
--    decidable : l'ensemble autorisé est connu partout où la colonne existe
--    dead      : décidable ET la valeur est interdite partout
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW pg_temp.b3_verdict AS
WITH scope AS (  -- corps de fonctions : toutes les tables où la fonction est branchée
  SELECT c.fn AS subject, c.col, c.val, t.tbl, 'fonction' AS kind,
         EXISTS (SELECT 1 FROM pg_temp.b3_allowed a
                  WHERE a.reloid = t.reloid AND a.col = c.col) AS has_set,
         EXISTS (SELECT 1 FROM pg_temp.b3_allowed a
                  WHERE a.reloid = t.reloid AND a.col = c.col AND a.val = c.val) AS allowed
  FROM pg_temp.b3_cmp c
  JOIN pg_temp.b3_trg t ON t.fnoid = c.fnoid
  WHERE EXISTS (SELECT 1 FROM pg_attribute att
                 WHERE att.attrelid = t.reloid AND att.attnum > 0
                   AND NOT att.attisdropped AND att.attname = c.col)
  UNION ALL       -- clauses WHEN : la table est connue sans ambiguïté
  SELECT w.tgname, w.col, w.val, w.tbl, 'WHEN',
         EXISTS (SELECT 1 FROM pg_temp.b3_allowed a
                  WHERE a.reloid = w.reloid AND a.col = w.col),
         EXISTS (SELECT 1 FROM pg_temp.b3_allowed a
                  WHERE a.reloid = w.reloid AND a.col = w.col AND a.val = w.val)
  FROM pg_temp.b3_when_cmp w
  WHERE EXISTS (SELECT 1 FROM pg_attribute att
                 WHERE att.attrelid = w.reloid AND att.attnum > 0
                   AND NOT att.attisdropped AND att.attname = w.col)
)
SELECT kind, subject, col, val,
       string_agg(DISTINCT tbl, ', ') AS tables,
       bool_and(has_set)                        AS decidable,
       bool_and(has_set) AND bool_and(NOT allowed) AS dead
FROM scope
GROUP BY kind, subject, col, val;

-- ------------------------------------------------------------
-- 6. Auto-test : une fixture volontairement morte doit être détectée,
--    et une fixture valide ne doit pas l'être. Annulé ensuite.
-- ------------------------------------------------------------
BEGIN;

CREATE TABLE public.b3_selftest (
  id int primary key,
  status text CHECK (status = ANY (ARRAY['draft'::text, 'posted'::text]))
);

CREATE FUNCTION public.b3_selftest_fn() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
  IF NEW.status = 'archived' THEN   -- interdit par la contrainte : mort
    RAISE NOTICE 'jamais';
  END IF;
  IF NEW.status = 'posted' THEN     -- autorisé : vivant
    RAISE NOTICE 'possible';
  END IF;
  IF NEW.status NOT IN ('draft', 'obsolete') THEN  -- 'obsolete' interdit : mort
    RAISE NOTICE 'garde inutile';
  END IF;
  RETURN NEW;
END;
$fn$;

CREATE TRIGGER b3_selftest_body
  BEFORE INSERT ON public.b3_selftest
  FOR EACH ROW EXECUTE FUNCTION public.b3_selftest_fn();

CREATE TRIGGER b3_selftest_when
  BEFORE UPDATE ON public.b3_selftest
  FOR EACH ROW WHEN (NEW.status = 'void')   -- interdit par la contrainte : mort
  EXECUTE FUNCTION public.b3_selftest_fn();

DO $$
DECLARE
  v_body int; v_when int; v_alive int;
BEGIN
  SELECT count(*) INTO v_body  FROM pg_temp.b3_verdict
   WHERE dead AND subject = 'b3_selftest_fn' AND val IN ('archived', 'obsolete');
  SELECT count(*) INTO v_when  FROM pg_temp.b3_verdict
   WHERE dead AND subject = 'b3_selftest_when' AND val = 'void';
  SELECT count(*) INTO v_alive FROM pg_temp.b3_verdict
   WHERE dead AND val = 'posted';

  IF v_body <> 2 THEN
    RAISE EXCEPTION 'AUTO-TEST : les comparaisons impossibles du corps de fonction ne sont pas toutes détectées (% sur 2)', v_body;
  END IF;
  IF v_when <> 1 THEN
    RAISE EXCEPTION 'AUTO-TEST : la clause WHEN morte n''est pas détectée (%)', v_when;
  END IF;
  IF v_alive <> 0 THEN
    RAISE EXCEPTION 'AUTO-TEST : faux positif sur une comparaison valide (%)', v_alive;
  END IF;
  RAISE NOTICE 'Auto-test : OK (= et NOT IN impossibles détectés, WHEN impossible détecté, comparaison valide non signalée)';
END;
$$;

ROLLBACK;

-- ------------------------------------------------------------
-- 7. Contrôle réel
-- ------------------------------------------------------------
DO $$
DECLARE
  r RECORD;
  v_dead int; v_decidable int; v_unknown int; v_triggers int; v_pairs int;
BEGIN
  SELECT count(*) FILTER (WHERE dead),
         count(*) FILTER (WHERE decidable),
         count(*) FILTER (WHERE NOT decidable)
    INTO v_dead, v_decidable, v_unknown
    FROM pg_temp.b3_verdict;

  SELECT count(*) INTO v_triggers FROM pg_trigger t
   JOIN pg_class c ON c.oid = t.tgrelid
   JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
   WHERE NOT t.tgisinternal;

  SELECT count(*) INTO v_pairs FROM (
    SELECT DISTINCT reloid, col FROM pg_temp.b3_allowed) s;

  FOR r IN SELECT * FROM pg_temp.b3_verdict WHERE dead ORDER BY kind, subject, col, val
  LOOP
    RAISE WARNING 'COMPARAISON IMPOSSIBLE (%) : % compare %.% à ''%'' — valeur interdite par la contrainte CHECK',
      r.kind, r.subject, r.tables, r.col, r.val;
  END LOOP;

  RAISE NOTICE 'Périmètre : % triggers, % couples (table, colonne) énumérés par des CHECK', v_triggers, v_pairs;
  RAISE NOTICE 'Comparaisons littérales : % décidées, % indécidables (aucune énumération connue)', v_decidable, v_unknown;

  IF v_dead > 0 THEN
    RAISE EXCEPTION '% comparaison(s) de trigger portent sur une valeur que la table ne peut jamais contenir', v_dead;
  END IF;

  IF v_decidable = 0 THEN
    RAISE EXCEPTION 'Contrôle sans valeur : aucune comparaison n''a pu être décidée. Le garde-fou ne prouve rien — vérifier les motifs de détection.';
  END IF;

  RAISE NOTICE 'Contrôle de trigger atteignable : OK — % comparaisons vérifiées, aucune impossible', v_decidable;
END;
$$;
