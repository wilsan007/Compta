-- ============================================================
-- check_plpgsql.sql
-- LOT6-01 : valide toutes les fonctions PL/pgSQL avec plpgsql_check
-- Détecte : colonnes inexistantes, types incompatibles, triggers morts
--
-- Les fonctions trigger ne peuvent être vérifiées qu'avec la table qui
-- les porte (NEW/OLD) : elles sont contrôlées une fois par table.
-- Seuls les niveaux 'error' font échouer la CI ; les avertissements
-- (variables inutilisées…) sont listés sans bloquer.
-- ============================================================

CREATE TEMP TABLE plpgsql_check_report (
  function_name text,
  relation text,
  level text,
  message text,
  lineno int,
  statement text
);

DO $$
DECLARE
  r RECORD;
BEGIN
  -- Fonctions ordinaires
  FOR r IN
    SELECT p.oid, p.oid::regprocedure::text AS fn
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_language l ON l.oid = p.prolang AND l.lanname = 'plpgsql'
    WHERE n.nspname = 'public'
      AND p.prorettype <> 'trigger'::regtype
  LOOP
    INSERT INTO plpgsql_check_report
    SELECT r.fn, NULL, c.level, c.message, c.lineno, c.statement
    FROM plpgsql_check_function_tb(r.oid) c;
  END LOOP;

  -- Fonctions trigger, avec chaque table qui les utilise
  FOR r IN
    SELECT DISTINCT p.oid, p.oid::regprocedure::text AS fn, t.tgrelid, t.tgrelid::regclass::text AS rel,
           t.tgoldtable, t.tgnewtable
    FROM pg_trigger t
    JOIN pg_proc p ON p.oid = t.tgfoid
    JOIN pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_language l ON l.oid = p.prolang AND l.lanname = 'plpgsql'
    WHERE NOT t.tgisinternal AND n.nspname = 'public'
  LOOP
    INSERT INTO plpgsql_check_report
    SELECT r.fn, r.rel, c.level, c.message, c.lineno, c.statement
    FROM plpgsql_check_function_tb(r.oid, r.tgrelid, oldtable => r.tgoldtable, newtable => r.tgnewtable) c;
  END LOOP;
END;
$$;

-- Tables temporaires créées à l'exécution (CREATE TEMP TABLE _x) : invisibles pour l'analyse statique
DELETE FROM plpgsql_check_report r
WHERE r.level = 'error'
  AND r.message ~ '^relation "_[a-z0-9_]+" does not exist$'
  AND EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid = r.function_name::regprocedure
      AND p.prosrc ~* ('CREATE\s+TEMP(ORARY)?\s+TABLE\s+(IF\s+NOT\s+EXISTS\s+)?' || substring(r.message from '"(_[a-z0-9_]+)"'))
  );

SELECT function_name, relation, lineno, message
FROM plpgsql_check_report
WHERE level = 'error'
ORDER BY function_name, relation, lineno;

DO $$
DECLARE
  v_errors int;
  v_warnings int;
BEGIN
  SELECT count(*) FILTER (WHERE level = 'error'), count(*) FILTER (WHERE level <> 'error')
  INTO v_errors, v_warnings FROM plpgsql_check_report;
  IF v_errors > 0 THEN
    RAISE EXCEPTION 'plpgsql_check : % erreur(s), % avertissement(s)', v_errors, v_warnings;
  END IF;
  RAISE NOTICE 'plpgsql_check : 0 erreur, % avertissement(s)', v_warnings;
END;
$$;
