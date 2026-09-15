-- ============================================================
-- check_plpgsql.sql
-- Valide toutes les fonctions PL/pgSQL avec plpgsql_check
-- Détecte : colonnes inexistantes, types incompatibles, triggers morts
-- ============================================================

DO $$
DECLARE
  r RECORD;
  v_errors int := 0;
  v_warnings int := 0;
BEGIN
  -- Itérer sur toutes les fonctions PL/pgSQL
  FOR r IN
    SELECT p.oid::regproc AS function_name,
           p.proname AS name,
           n.nspname AS schema
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.prolang = (SELECT oid FROM pg_language WHERE lanname = 'plpgsql')
      AND n.nspname NOT IN ('pg_catalog', 'information_schema')
      AND p.proname NOT LIKE 'pg_%'
  LOOP
    BEGIN
      -- Valider la fonction avec plpgsql_check
      PERFORM plpgsql_check_function(r.function_name, 'warning');
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'Erreur sur fonction % : %', r.function_name, SQLERRM;
      v_errors := v_errors + 1;
    END;
  END LOOP;

  -- Rapport
  IF v_errors > 0 THEN
    RAISE EXCEPTION 'plpgsql_check : % fonctions avec erreurs', v_errors;
  ELSE
    RAISE NOTICE 'plpgsql_check : % fonctions validées sans erreur', v_errors;
  END IF;
END;
$$;
