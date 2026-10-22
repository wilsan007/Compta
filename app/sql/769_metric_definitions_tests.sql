-- Tests for migration 769: L19-reporting metric definitions historization

-- Test 1: v3 definition exists (replayable via IF NOT EXISTS)
SELECT 'v3 definition exists' AS test_name,
       COUNT(*) > 0 AS passes
FROM public.metric_definitions
WHERE code = 'pilotage.marge_pct'
  AND version = 3
  AND tenant_id IS NULL;

-- Test 2: History chain valid (v1, v2, v3 should have version_precedente chain)
SELECT 'history chain valid' AS test_name,
       COUNT(*) = 3 AS passes  -- exactly 3 historical entries
FROM public.metric_definition_history
WHERE code = 'pilotage.marge_pct';

-- Test 3: No duplicate history entries (unique constraint should prevent)
SELECT 'no duplicate history' AS test_name,
       COUNT(*) = 0 AS passes  -- no groups with count > 1
FROM (
    SELECT code, version, sql_definition, COUNT(*) AS cnt
    FROM public.metric_definition_history
    GROUP BY code, version, sql_definition
    HAVING COUNT(*) > 1
) sub;