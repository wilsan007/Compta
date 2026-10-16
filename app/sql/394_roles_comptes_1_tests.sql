-- ============================================================
-- 394_roles_comptes_1_tests.sql — LOC1-10 (comptes en dur, tranche 1)
--
--   T01  les 6 fonctions demandent leur COMPTE (plus aucun littéral chiffré) ;
--   T02  société FR : les rôles rendent EXACTEMENT les numéros d'avant ;
--   T03  treasury_for_payment : caisse ET banque, compte ET journal, par rôle ;
--   T04  rejouable : les 7 rôles de la tranche sont au catalogue, une seule fois.
--
-- Vu ROUGE avant la 394 : T01 (comptes en dur : 8 occurrences mesurées).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '394', false);
DELETE FROM _audit_results WHERE file = '394';

-- ─────────────────────────────────────────────────────────────
-- T01 — les 6 fonctions passent par le rôle
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(p.proname, ', ' ORDER BY p.proname) INTO v_bad
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN ('treasury_for_payment','letter_advance_invoice',
                      'sync_customer_third_party_account','sync_supplier_third_party_account',
                      'backfill_third_party_accounts','sync_commitments_on_purchase_order')
    AND (p.prosrc NOT LIKE '%resolve_account%'
         OR p.prosrc ~ '''[1-9][0-9]{2,5}''');

  PERFORM _rec('T01', 'les 6 fonctions de la tranche demandent leur compte, sans littéral chiffré',
    v_bad IS NULL, COALESCE('encore en dur : ' || v_bad, 'les 6 fonctions passent par le rôle'));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'les 6 fonctions de la tranche demandent leur compte, sans littéral chiffré', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T02 — société FR : les rôles rendent EXACTEMENT les numéros d'avant
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE t uuid; c text; b text; cl text; fo text; pr text; av text; am text;
BEGIN
  t := _mk_tenant('RCPT1');
  UPDATE tenants SET legislation_pack_code = 'FR' WHERE id = t;
  PERFORM ensure_standard_journals(t);
  c  := resolve_account(t, 'CAISSE');
  b  := resolve_account(t, 'BANQUE');
  cl := resolve_account(t, 'CLIENTS');
  fo := resolve_account(t, 'FOURNISSEURS');
  pr := resolve_account(t, 'PERSONNEL_REMUNERATIONS_DUES');
  av := resolve_account(t, 'CLIENTS_AVANCES_RECUES');
  am := resolve_account(t, 'ACHATS_MARCHANDISES');
  PERFORM _rec('T02',
    'société FR : CAISSE=530000, BANQUE=512000, CLIENTS=411000, FOURNISSEURS=401000, PERSONNEL=421000, AVANCES=419100, ACHATS_MARCHANDISES=607000',
    c = '530000' AND b = '512000' AND cl = '411000' AND fo = '401000'
      AND pr = '421000' AND av = '419100' AND am = '607000',
    format('CAISSE=%s BANQUE=%s CLIENTS=%s FOURNISSEURS=%s PERSONNEL=%s AVANCES=%s ACHATS=%s',
           c, b, cl, fo, pr, av, am));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02',
    'société FR : CAISSE=530000, BANQUE=512000, CLIENTS=411000, FOURNISSEURS=401000, PERSONNEL=421000, AVANCES=419100, ACHATS_MARCHANDISES=607000',
    false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T03 — treasury_for_payment : caisse et banque, compte ET journal
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE t uuid; a_c text; j_c text; a_b text; j_b text;
BEGIN
  t := _mk_tenant('RCPT2');
  UPDATE tenants SET legislation_pack_code = 'FR' WHERE id = t;
  PERFORM ensure_standard_journals(t);
  SELECT account_code, journal_code INTO a_c, j_c FROM treasury_for_payment(t, NULL, 'cash');
  SELECT account_code, journal_code INTO a_b, j_b FROM treasury_for_payment(t, NULL, 'bank');
  PERFORM _rec('T03', 'trésorerie : caisse = 530000 / CA, banque = 512000 / BQ (par les rôles)',
    a_c = '530000' AND j_c = 'CA' AND a_b = '512000' AND j_b = 'BQ',
    format('caisse=%s/%s ; banque=%s/%s', a_c, j_c, a_b, j_b));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'trésorerie : caisse = 530000 / CA, banque = 512000 / BQ (par les rôles)', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T04 — rejouable
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v int;
BEGIN
  SELECT count(*) INTO v FROM journal_role_catalog
   WHERE role IN ('JOURNAL_CAISSE','JOURNAL_BANQUE');
  PERFORM _rec('T04', 'rejouable : JOURNAL_CAISSE et JOURNAL_BANQUE sont au catalogue, une seule fois', v = 2,
    format('%s occurrence(s)', v));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'rejouable : JOURNAL_CAISSE et JOURNAL_BANQUE sont au catalogue, une seule fois', false, SQLERRM);
END $$;

SELECT _audit_assert('394');