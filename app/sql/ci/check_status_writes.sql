-- ============================================================
-- check_status_writes.sql
--
-- Détecte les ÉCRITURES impossibles : une fonction qui écrit dans une colonne
-- une valeur littérale que les contraintes CHECK de la table interdisent. La
-- ligne est refusée à l'exécution, sur toutes les données, toujours.
--
-- POURQUOI CE CONTRÔLE EXISTE (24/09/2026)
--   `release_stock_on_delivery` écrivait `status = 'fulfilled'` dans
--   `stock_reservations`, dont la contrainte n'admet que 'active', 'released',
--   'consumed' et 'cancelled'. Conséquence : **aucune commande confirmée ne
--   pouvait passer à « livrée »**. Le défaut a vécu jusqu'à ce qu'un scénario
--   chiffré (230) traverse le cycle de réservation.
--
--   `check_trigger_reachability`, lui, était vert : il décide des COMPARAISONS
--   littérales, pas des AFFECTATIONS. Une comparaison morte est une branche
--   qui ne s'exécute jamais ; une affectation morte est une transaction qui
--   échoue. La seconde est plus grave et n'était surveillée par rien.
--
-- PORTÉE
--   * toutes les fonctions PL/pgSQL du schéma public, pas seulement les triggers ;
--   * `UPDATE <table> SET <col> = '<littéral>'` ;
--   * `INSERT INTO <table> (<colonnes>) VALUES (<littéraux>)`, par position,
--     quand la liste de valeurs ne contient pas de parenthèse imbriquée.
--   Les INSERT non décidables sont comptés et affichés : l'angle mort se voit
--   au lieu de se taire.
--
-- SOLIDITÉ
--   Une écriture n'est déclarée impossible que si l'ensemble des valeurs
--   autorisées est connu pour cette (table, colonne). Le script s'auto-teste
--   sur une fixture volontairement fausse et échoue s'il n'a rien pu décider.
-- ============================================================

\set ON_ERROR_STOP on

-- ------------------------------------------------------------
-- 1. Valeurs autorisées par (table, colonne), lues dans les CHECK énumérantes.
--    Même lecture que check_trigger_reachability : les contraintes contenant
--    une négation sont ignorées, leur énumération ne décrit pas l'autorisé.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW pg_temp.w_allowed AS
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

-- Table visée par son nom, sans ambiguïté : une seule relation publique par nom.
CREATE OR REPLACE VIEW pg_temp.w_tbl AS
SELECT c.oid AS reloid, c.relname AS tbl
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
WHERE c.relkind IN ('r', 'p');

-- ------------------------------------------------------------
-- 2. Corpus : fonctions PL/pgSQL du schéma public, extensions exclues
--    (elles ne sont pas écrites ici — même règle que la 228 pour H09).
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW pg_temp.w_fn AS
SELECT p.oid AS fnoid, p.proname AS fn, pg_get_functiondef(p.oid) AS src
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
JOIN pg_language l ON l.oid = p.prolang AND l.lanname = 'plpgsql'
WHERE NOT EXISTS (
  SELECT 1 FROM pg_depend d
  WHERE d.objid = p.oid AND d.classid = 'pg_proc'::regclass AND d.deptype = 'e'
);

-- ------------------------------------------------------------
-- 3. Écritures par UPDATE … SET
--    Le segment SET est coupé au premier WHERE / RETURNING / ';' : sans cela,
--    un `WHERE status = 'active'` passerait pour une affectation.
--    Le littéral doit terminer son affectation (suivi d'une virgule ou de la
--    fin du segment) : `SET a = 'x' || b` n'est pas une écriture de 'x'.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW pg_temp.w_upd AS
WITH raw AS (
  -- `[^;]*` et non `(.*?)` : en ARE PostgreSQL, la gourmandise de l'expression
  -- entière est fixée par son PREMIER quantificateur (ici `\s+`, gourmand), et
  -- elle l'emporte sur la paresse de `*?`. Un `(.*?);` avalait donc jusqu'au
  -- DERNIER point-virgule de la fonction, absorbant tous les UPDATE suivants —
  -- c'est ainsi que la première version de ce contrôle est passée au vert sur
  -- le défaut même qui l'a motivé. La classe de caractères ne dépend d'aucune
  -- préférence de match.
  -- Limite connue : un ';' à l'intérieur d'un littéral coupe l'instruction trop
  -- tôt. Cela fait manquer une écriture, jamais inventer une fausse.
  SELECT f.fnoid, f.fn, lower(m[1]) AS tbl, m[2] AS stmt
  FROM pg_temp.w_fn f, regexp_matches(
         f.src,
         $re$\mUPDATE\s+(?:public\.)?([a-z_][a-z0-9_]*)\s+SET\s+([^;]*);$re$,
         'gi') m
), stmt AS (
  SELECT fnoid, fn, tbl,
         regexp_replace(
           regexp_replace(stmt, $re$\mWHERE\M.*$$re$, '', 'i'),
           $re$\mRETURNING\M.*$$re$, '', 'i') AS setseg
  FROM raw
)
SELECT DISTINCT stmt.fnoid, stmt.fn, stmt.tbl, lower(a[1]) AS col, a[2] AS val
FROM stmt, regexp_matches(
       stmt.setseg,
       $re$([a-z_][a-z0-9_]*)\s*=\s*'([^']*)'\s*(?:,|$)$re$,
       'gi') a;

-- ------------------------------------------------------------
-- 4. Écritures par INSERT … VALUES, appariées par position.
--    Seules les listes de valeurs sans parenthèse imbriquée sont décidables :
--    `VALUES (a, now(), 'x')` est écarté et compté.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW pg_temp.w_ins_raw AS
SELECT f.fnoid, f.fn, lower(m[1]) AS tbl, m[2] AS collist, m[3] AS vallist
FROM pg_temp.w_fn f, regexp_matches(
       f.src,
       $re$\mINSERT\s+INTO\s+(?:public\.)?([a-z_][a-z0-9_]*)\s*\(([^()]*)\)\s*VALUES\s*\(([^()]*)\)$re$,
       'gi') m;

CREATE OR REPLACE VIEW pg_temp.w_ins AS
WITH cols AS (
  SELECT fnoid, fn, tbl, vallist,
         lower(btrim(c)) AS col,
         row_number() OVER (PARTITION BY fnoid, tbl, collist, vallist ORDER BY o) AS pos
  FROM pg_temp.w_ins_raw, unnest(string_to_array(collist, ',')) WITH ORDINALITY AS u(c, o)
), vals AS (
  SELECT fnoid, tbl, vallist, btrim(v) AS val,
         row_number() OVER (PARTITION BY fnoid, tbl, vallist ORDER BY o) AS pos
  FROM (SELECT DISTINCT fnoid, tbl, vallist FROM pg_temp.w_ins_raw) s,
       unnest(string_to_array(vallist, ',')) WITH ORDINALITY AS u(v, o)
)
SELECT DISTINCT c.fnoid, c.fn, c.tbl, c.col,
       btrim(v.val, '''') AS val
FROM cols c
JOIN vals v ON v.fnoid = c.fnoid AND v.tbl = c.tbl AND v.vallist = c.vallist AND v.pos = c.pos
WHERE v.val ~ $re$^'[^']*'$re$;

-- ------------------------------------------------------------
-- 5. Verdict : l'écriture est impossible si la colonne est énumérée sur cette
--    table et que la valeur n'y figure pas.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW pg_temp.w_verdict AS
WITH w AS (
  SELECT 'UPDATE' AS kind, fnoid, fn, tbl, col, val FROM pg_temp.w_upd
  UNION
  SELECT 'INSERT', fnoid, fn, tbl, col, val FROM pg_temp.w_ins
)
SELECT w.kind, w.fn, w.tbl, w.col, w.val,
       EXISTS (SELECT 1 FROM pg_temp.w_allowed a JOIN pg_temp.w_tbl t ON t.reloid = a.reloid
                WHERE t.tbl = w.tbl AND a.col = w.col) AS decidable,
       EXISTS (SELECT 1 FROM pg_temp.w_allowed a JOIN pg_temp.w_tbl t ON t.reloid = a.reloid
                WHERE t.tbl = w.tbl AND a.col = w.col)
       AND NOT EXISTS (SELECT 1 FROM pg_temp.w_allowed a JOIN pg_temp.w_tbl t ON t.reloid = a.reloid
                WHERE t.tbl = w.tbl AND a.col = w.col AND a.val = w.val) AS impossible
FROM w;

-- ------------------------------------------------------------
-- 6. Auto-test : deux écritures volontairement fausses doivent être vues,
--    deux écritures valides ne doivent pas l'être. Annulé ensuite.
-- ------------------------------------------------------------
BEGIN;

CREATE TABLE public.w_selftest (
  id int primary key,
  status text CHECK (status = ANY (ARRAY['active'::text, 'consumed'::text])),
  note text
);

-- L'ordre compte : l'écriture interdite vient APRÈS une écriture valide et
-- après un UPDATE sur une autre table. C'est la configuration réelle de
-- release_stock_on_delivery, et celle qu'une capture gourmande ne voit pas.
-- Une fixture qui mettrait l'écriture fautive en premier passerait au vert
-- avec un contrôle cassé.
CREATE FUNCTION public.w_selftest_fn() RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  UPDATE public.w_selftest SET status = 'consumed'  WHERE id = 2;   -- autorisé
  UPDATE public.w_selftest SET note = 'peu importe' WHERE status = 'active';  -- WHERE, pas SET
  UPDATE public.w_selftest SET status = 'fulfilled', note = 'x' WHERE id = 1;  -- interdit, en dernier
  INSERT INTO public.w_selftest (id, status) VALUES (4, 'active');    -- autorisé
  INSERT INTO public.w_selftest (id, status) VALUES (3, 'archived');  -- interdit, en dernier
END;
$fn$;

DO $$
DECLARE v_upd int; v_ins int; v_faux int; v_where int;
BEGIN
  SELECT count(*) INTO v_upd FROM pg_temp.w_verdict
   WHERE impossible AND fn = 'w_selftest_fn' AND kind = 'UPDATE' AND val = 'fulfilled';
  SELECT count(*) INTO v_ins FROM pg_temp.w_verdict
   WHERE impossible AND fn = 'w_selftest_fn' AND kind = 'INSERT' AND val = 'archived';
  SELECT count(*) INTO v_faux FROM pg_temp.w_verdict
   WHERE impossible AND fn = 'w_selftest_fn' AND val IN ('consumed', 'active');
  SELECT count(*) INTO v_where FROM pg_temp.w_verdict
   WHERE fn = 'w_selftest_fn' AND col = 'status' AND val = 'peu importe';

  IF v_upd <> 1 THEN
    RAISE EXCEPTION 'AUTO-TEST : l''affectation interdite par UPDATE n''est pas détectée (%)', v_upd;
  END IF;
  IF v_ins <> 1 THEN
    RAISE EXCEPTION 'AUTO-TEST : l''affectation interdite par INSERT n''est pas détectée (%)', v_ins;
  END IF;
  IF v_faux <> 0 THEN
    RAISE EXCEPTION 'AUTO-TEST : faux positif sur une écriture autorisée (%)', v_faux;
  END IF;
  IF v_where <> 0 THEN
    RAISE EXCEPTION 'AUTO-TEST : une condition WHERE a été prise pour une affectation (%)', v_where;
  END IF;
  RAISE NOTICE 'Auto-test : OK (UPDATE et INSERT interdits détectés, écritures valides et clause WHERE non signalées)';
END;
$$;

ROLLBACK;

-- ------------------------------------------------------------
-- 7. Contrôle réel
-- ------------------------------------------------------------
DO $$
DECLARE
  r RECORD;
  v_bad int; v_decid int; v_unknown int; v_fn int; v_pairs int; v_ins_skip int;
BEGIN
  SELECT count(*) FILTER (WHERE impossible),
         count(*) FILTER (WHERE decidable),
         count(*) FILTER (WHERE NOT decidable)
    INTO v_bad, v_decid, v_unknown FROM pg_temp.w_verdict;

  SELECT count(*) INTO v_fn FROM pg_temp.w_fn;
  SELECT count(*) INTO v_pairs FROM (SELECT DISTINCT reloid, col FROM pg_temp.w_allowed) s;

  -- INSERT écartés : parenthèse imbriquée dans la liste de valeurs
  SELECT count(*) INTO v_ins_skip
  FROM pg_temp.w_fn f, regexp_matches(f.src,
    $re$\mINSERT\s+INTO\s+(?:public\.)?[a-z_][a-z0-9_]*\s*\([^()]*\)\s*VALUES\s*\([^)]*\($re$, 'gi') m;

  FOR r IN SELECT * FROM pg_temp.w_verdict WHERE impossible ORDER BY fn, tbl, col, val
  LOOP
    RAISE WARNING 'ÉCRITURE IMPOSSIBLE (%) : % écrit ''%'' dans %.% — valeur interdite par la contrainte CHECK',
      r.kind, r.fn, r.val, r.tbl, r.col;
  END LOOP;

  RAISE NOTICE 'Périmètre : % fonctions PL/pgSQL, % couples (table, colonne) énumérés par des CHECK', v_fn, v_pairs;
  RAISE NOTICE 'Écritures littérales : % décidées, % indécidables, % INSERT écartés (valeurs imbriquées)',
    v_decid, v_unknown, v_ins_skip;

  IF v_bad > 0 THEN
    RAISE EXCEPTION '% écriture(s) portent une valeur que la contrainte CHECK de la table refuse : la transaction échoue à chaque fois', v_bad;
  END IF;

  IF v_decid = 0 THEN
    RAISE EXCEPTION 'Contrôle sans valeur : aucune écriture n''a pu être décidée. Le garde-fou ne prouve rien.';
  END IF;

  RAISE NOTICE 'Contrôle d''écriture de statut : OK — % écritures vérifiées, aucune impossible', v_decid;
END;
$$;
