-- ============================================================
-- 349_fiscal_period_labels_accents_tests.sql — tâche 2.12 (F5)
--
--   T01  une société créée par `bootstrap_tenant` a ses douze périodes, dont
--        « Février », « Août » et « Décembre » — aucune sans accent
--   T02  plus aucune période sans accent dans la base
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '349', false);
DELETE FROM _audit_results WHERE file = '349';

DO $$
DECLARE
  t uuid := _mk_tenant('P2F5T01', false);
  v_labels text; n_ok int; n_ko int; n_total_ko int;
BEGIN
  DELETE FROM fiscal_periods WHERE tenant_id = t;
  DELETE FROM fiscal_years WHERE tenant_id = t;
  PERFORM bootstrap_tenant(t);
  SELECT string_agg(period_label, ' | ' ORDER BY period_number),
         count(*) FILTER (WHERE period_label ~ '(Février|Août|Décembre)'),
         count(*) FILTER (WHERE period_label ~ '(Fevrier|Aout|Decembre)')
    INTO v_labels, n_ok, n_ko
    FROM fiscal_periods WHERE tenant_id = t;
  PERFORM _rec('T01', 'une société neuve a ses périodes avec leurs accents : Février, Août, Décembre',
    n_ok = 3 AND n_ko = 0, format('avec accent=%s sans accent=%s — %s', n_ok, n_ko, left(COALESCE(v_labels, '(aucune période)'), 160)));

  SELECT count(*) INTO n_total_ko FROM fiscal_periods WHERE period_label ~ '(Fevrier|Aout|Decembre)';
  PERFORM _rec('T02', 'plus aucune période sans accent dans la base',
    n_total_ko = 0, format('périodes sans accent=%s', n_total_ko));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'T01/T02 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

SELECT _audit_assert('349');
