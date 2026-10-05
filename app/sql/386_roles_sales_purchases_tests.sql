-- ============================================================
-- 386_roles_sales_purchases_tests.sql — LOC1-06
--
--   T01  les 4 triggers DEMANDENT un rôle (resolve_account / resolve_journal) ;
--   T02  aucun littéral de compte collectif/vente/achat ne subsiste en défaut ;
--   T03  PONT : une société SANS pack retombe sur le pack PAR DÉFAUT (FR) ;
--   T04  société FR : resolve_account('CLIENTS') = 411000 (ancre) ;
--   T05  resolve_journal sans pack → VT.
--
-- La recette du cahier (« écritures identiques ligne à ligne ») est tenue par
-- `102_trigger_tests.sql`, rejoué vert : 17/17, inchangé. Ici on prouve la
-- NEUTRALITÉ : plus de numéro en dur, tout passe par les rôles.
--
-- Vu ROUGE avant la 386 : T01/T02 (littéraux en dur), T03 (pas de pont → ROLE_NON_MAPPE).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '386', false);
DELETE FROM _audit_results WHERE file = '386';

-- ─────────────────────────────────────────────────────────────
-- T01 — les 4 fonctions demandent un rôle
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_manque text;
BEGIN
  SELECT string_agg(f.proname, ', ' ORDER BY f.proname) INTO v_manque
  FROM pg_proc f JOIN pg_namespace n ON n.oid = f.pronamespace
  WHERE n.nspname = 'public'
    AND f.proname IN ('create_journal_on_invoice_validate','create_journal_on_purchase_invoice_validate',
                      'create_journal_on_customer_payment','create_journal_on_supplier_payment')
    AND pg_get_functiondef(f.oid) NOT LIKE '%resolve_account%'
    AND pg_get_functiondef(f.oid) NOT LIKE '%resolve_journal%';

  PERFORM _rec('T01', 'les 4 triggers de ventes/achats/règlements passent par les RÔLES',
    v_manque IS NULL, COALESCE('sans rôle : ' || v_manque, 'les 4 fonctions demandent un rôle'));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'les 4 triggers de ventes/achats/règlements passent par les RÔLES', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T02 — plus de littéral de compte en défaut
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_restant text;
BEGIN
  SELECT string_agg(DISTINCT f.proname || ' → ' || lit.l, ', ') INTO v_restant
  FROM pg_proc f
  JOIN pg_namespace n ON n.oid = f.pronamespace
  CROSS JOIN (VALUES ('411000'), ('707000'), ('706000'), ('401000'), ('607000'),
                     ('419100'), ('409100'), ('445710'), ('445660')) AS lit(l)
  WHERE n.nspname = 'public'
    AND f.proname IN ('create_journal_on_invoice_validate','create_journal_on_purchase_invoice_validate',
                      'create_journal_on_customer_payment','create_journal_on_supplier_payment')
    AND pg_get_functiondef(f.oid) LIKE '%''' || lit.l || '''%';

  PERFORM _rec('T02', 'aucun numéro de compte collectif/vente/achat/TVA ne subsiste en dur',
    v_restant IS NULL, COALESCE('restes : ' || v_restant, 'plus un seul numéro en dur'));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'aucun numéro de compte collectif/vente/achat/TVA ne subsiste en dur', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T03 — le pont : société SANS pack → pack par défaut (FR)
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE t uuid; v text;
BEGIN
  t := _mk_tenant('RSP1');   -- _mk_tenant ne pose AUCUN pack
  SELECT resolve_account(t, 'CLIENTS') INTO v;
  PERFORM _rec('T03', 'une société SANS pack retombe sur le pack PAR DÉFAUT (FR)',
    v = '411000', format('compte=%s (411000 attendu)', COALESCE(v, 'NULL')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'une société SANS pack retombe sur le pack PAR DÉFAUT (FR)', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T04 / T05 — les ancres FR
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE t uuid; v text; j text;
BEGIN
  t := _mk_tenant('RSP2');
  UPDATE tenants SET legislation_pack_code = 'FR' WHERE id = t;
  SELECT resolve_account(t, 'CLIENTS') INTO v;
  SELECT resolve_journal(t, 'JOURNAL_VENTES') INTO j;
  PERFORM _rec('T04', 'société FR : resolve_account(''CLIENTS'') = 411000', v = '411000',
    format('compte=%s', COALESCE(v, 'NULL')));
  PERFORM _rec('T05', 'société FR : resolve_journal(''JOURNAL_VENTES'') = VT', j = 'VT',
    format('journal=%s', COALESCE(j, 'NULL')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'société FR : resolve_account(''CLIENTS'') = 411000', false, SQLERRM);
  PERFORM _rec('T05', 'société FR : resolve_journal(''JOURNAL_VENTES'') = VT', false, SQLERRM);
END $$;

SELECT _audit_assert('386');