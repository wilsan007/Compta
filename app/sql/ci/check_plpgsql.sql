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

-- Paramètre de type `record` nu (03/10/2026, banc 434/436 : `chain_banc_appeler(m record, …)`).
-- L'analyse statique ne connaît pas la forme d'un `record` reçu en argument et
-- rend « record "m" is not assigned yet » — alors que l'appelant le fournit.
-- On n'écarte QUE ce message, et QUE pour une fonction dont un argument est un `record`.
DELETE FROM plpgsql_check_report r
WHERE r.level = 'error'
  AND r.message ~ '^record "[a-z0-9_]+" is not assigned yet$'
  AND EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid::regprocedure::text = r.function_name
      AND 'record'::regtype = ANY (p.proargtypes::oid[]));

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
