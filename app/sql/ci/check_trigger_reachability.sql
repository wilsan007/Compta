-- ============================================================
-- check_trigger_reachability.sql
-- Détecte les triggers morts (conditions impossibles à cause des contraintes CHECK)
-- Trouve les 6 triggers morts de LOT1-01 (invoices.status vs validation_status)
-- ============================================================

DO $$
DECLARE
  r RECORD;
  v_errors int := 0;
BEGIN
  -- Chercher les triggers qui attendent des valeurs de status interdites par les contraintes
  FOR r IN
    WITH trg AS (
      SELECT c.relname AS tbl, p.proname AS fn, pg_get_functiondef(p.oid) AS src
      FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid JOIN pg_class c ON c.oid=t.tgrelid
      JOIN pg_namespace n ON n.oid=c.relnamespace AND n.nspname='public'
      WHERE NOT t.tgisinternal
    ), lits AS (
      SELECT DISTINCT tbl, fn, m[1] AS val
      FROM trg, regexp_matches(src, 'NEW\.status\s*(?:=|IN\s*\()\s*''([a-z_]+)''', 'g') m
    ), chk AS (
      SELECT conrelid::regclass::text AS tbl, pg_get_constraintdef(oid) AS def
      FROM pg_constraint WHERE contype='c' AND pg_get_constraintdef(oid) ILIKE '%(status%'
    )
    SELECT l.tbl, l.fn, l.val FROM lits l JOIN chk ON chk.tbl = l.tbl
    WHERE chk.def NOT ILIKE '%''' || l.val || '''%'
  LOOP
    RAISE WARNING 'TRIGGER MORT : %.% attend ''%'' — interdit par la contrainte', r.tbl, r.fn, r.val;
    v_errors := v_errors + 1;
  END LOOP;

  IF v_errors > 0 THEN
    RAISE EXCEPTION '% trigger(s) ne peuvent jamais se déclencher', v_errors;
  ELSE
    RAISE NOTICE 'Contrôle de trigger atteignable : OK — % triggers validés', v_errors;
  END IF;
END;
$$;
