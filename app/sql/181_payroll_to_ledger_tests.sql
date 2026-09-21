-- ============================================================
-- 181_payroll_to_ledger_tests.sql — AUD-A01, lot F du plan correctif
--
-- P01/P02 rejouent la charge utile exacte de misc.ts:generatePayrollJournal
-- (brut 3 000, net 2 340, charges 1 260). Quand AUD-F02 remplacera cette
-- fonction front par la RPC serveur post_payroll_journal, ces deux scénarios
-- seront réécrits sur la RPC — le défaut prouvé ici est celui du front.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '181', false);
DELETE FROM _audit_results WHERE file = '181';

DO $$ DECLARE t uuid := _mk_tenant('P01'); r jsonb; r2 jsonb; e uuid; BEGIN
  PERFORM _as_user();
  -- P01 — le bouton « Générer l'écriture de paie », charge utile réelle
  r := post_journal_entry(
    '{"number":"JE-PAY-PR1","date":"2026-03-31","description":"Écriture de paie PR1","journal_type":"purchase","status":"posted","total_debit":4260,"total_credit":3600}',
    '[{"account_code":"641000","account_name":"Rémunérations du personnel","debit":3000,"credit":0,"line_order":0},
      {"account_code":"645000","account_name":"Charges sociales","debit":1260,"credit":0,"line_order":1},
      {"account_code":"421000","account_name":"Personnel - Rémunérations dues","debit":0,"credit":2340,"line_order":2},
      {"account_code":"431000","account_name":"Sécurité sociale - Charges","debit":0,"credit":1260,"line_order":3}]');
  PERFORM _rec('P01', 'écriture de paie générée et validée', COALESCE((r->>'success')::boolean, false), r::text);

  -- P02 — les mêmes lignes, en brouillon puis validées : l'écriture est-elle équilibrée ?
  r2 := post_journal_entry('{"number":"JE-PAY-PR2","date":"2026-03-31","description":"Paie"}',
    '[{"account_code":"641000","debit":3000},{"account_code":"645000","debit":1260},
      {"account_code":"421000","credit":2340},{"account_code":"431000","credit":1260}]');
  e := (r2->>'entry_id')::uuid;
  BEGIN
    UPDATE journal_entries SET status = 'posted' WHERE id = e;
    PERFORM _rec('P02', 'écriture de paie équilibrée (cotisations salariales comprises)', true, 'ok');
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('P02', 'écriture de paie équilibrée (cotisations salariales comprises)', false,
      SQLERRM || ' | journal_code=' || COALESCE((SELECT journal_code FROM journal_entries WHERE id = e), 'NULL'));
  END;
END $$;

SELECT _audit_assert('181');
