-- ============================================================
-- 347_chart_account_balances_from_ledger_tests.sql — tâche 2.10 (F1)
--
--   T01  un à-nouveau de 10 000 € : 512000 solde 10 000, 890000 solde −10 000
--        (les colonnes de chart_accounts, elles, disent 0)
--   T02  une écriture en BROUILLON n'entre pas dans les soldes
--   T03  cloisonnement : la société voisine ne voit rien de ces soldes
-- ============================================================
\ir ci/audit_helpers.sql
\ir ci/ledger_fixture.sql
SELECT set_config('audit.file', '347', false);
DELETE FROM _audit_results WHERE file = '347';

DO $$
DECLARE
  t2 uuid := _mk_tenant('P2F1T03', false);   -- la voisine, créée d'abord
  t uuid := _mk_tenant('P2F1T01', false);    -- le contexte de session est celui de `t`
  a2 uuid;
  s512 numeric; s890 numeric; col512 numeric; s606 numeric; n_voisin int;
BEGIN
  PERFORM _ledger_fixture(t, ARRAY['512000', '890000', '606000', '401000']);

  -- un à-nouveau VALIDÉ : 512000 / 890000, 10 000 €
  PERFORM _entry(t, 'AN-F1-1', DATE '2026-01-01',
    '[{"a":"512000","d":10000,"c":0},{"a":"890000","d":0,"c":10000}]'::jsonb, true);
  -- une écriture laissée en BROUILLON : 606000 / 401000, 500 €
  PERFORM _entry(t, 'OD-F1-2', DATE '2026-02-01',
    '[{"a":"606000","d":500,"c":0},{"a":"401000","d":0,"c":500}]'::jsonb, false);

  PERFORM _as_user();
  SELECT b.balance INTO s512 FROM chart_account_balances() b WHERE b.code = '512000';
  SELECT b.balance INTO s890 FROM chart_account_balances() b WHERE b.code = '890000';
  SELECT b.balance INTO s606 FROM chart_account_balances() b WHERE b.code = '606000';
  EXECUTE 'RESET ROLE';
  SELECT COALESCE(balance, 0) INTO col512 FROM chart_accounts WHERE tenant_id = t AND code = '512000';

  PERFORM _rec('T01', 'un à-nouveau de 10 000 € : 512000 solde 10 000 et 890000 solde −10 000, lus au grand livre',
    s512 = 10000 AND s890 = -10000,
    format('512000=%s 890000=%s | colonne chart_accounts.balance=%s', s512, s890, col512));
  PERFORM _rec('T02', 'une écriture en brouillon n''entre pas dans les soldes (606000 absent)',
    s606 IS NULL, format('606000=%s', COALESCE(s606::text, 'absent')));

  -- la voisine : on prend son utilisateur, et elle ne voit aucun de ces soldes
  SELECT auth_id INTO a2 FROM tenant_users WHERE tenant_id = t2 LIMIT 1;
  PERFORM set_config('request.jwt.claim.sub', a2::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', a2, 'role', 'authenticated')::text, true);
  PERFORM _as_user();
  SELECT count(*) INTO n_voisin FROM chart_account_balances();
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T03', 'cloisonnement : la société voisine ne lit aucun de ces soldes',
    n_voisin = 0, format('lignes vues par la voisine=%s', n_voisin));
EXCEPTION WHEN OTHERS THEN
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T01', 'T01 à T03 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

SELECT _audit_assert('347');
