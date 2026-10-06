-- ============================================================
-- 387_roles_operations_tests.sql — LOC1-07 (tranche POS)
--
--   T01  deux rôles de journaux AJOUTÉS au catalogue (JOURNAL_POS, JOURNAL_PRODUCTION) ;
--   T02  le pack PCG les mappe (`POS`, `OF`) ;
--   T03  société FR : resolve_journal → POS / OF ;
--   T04  le trigger de clôture POS demande ses rôles (plus aucun `707000`) ;
--   T05  rejouable.
--
-- Vu ROUGE avant la 387 : T01/T02 (rôles absents), T03 (ROLE_JOURNAL_NON_MAPPE),
-- T04 (`'707000'` en dur).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '387', false);
DELETE FROM _audit_results WHERE file = '387';

-- ─────────────────────────────────────────────────────────────
-- T01 / T02 — les rôles et leur mapping
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_cat int; v_pack int;
BEGIN
  SELECT count(*) INTO v_cat FROM journal_role_catalog
   WHERE role IN ('JOURNAL_POS','JOURNAL_PRODUCTION');
  SELECT count(*) INTO v_pack FROM pack_journal_roles
   WHERE pack_code = 'PCG' AND role IN ('JOURNAL_POS','JOURNAL_PRODUCTION');
  PERFORM _rec('T01', 'JOURNAL_POS et JOURNAL_PRODUCTION sont au catalogue',
    v_cat = 2, format('%s rôle(s) au catalogue (2 attendus)', v_cat));
  PERFORM _rec('T02', 'le pack PCG mappe JOURNAL_POS → POS et JOURNAL_PRODUCTION → OF',
    v_pack = 2, format('%s mapping(s) dans le pack PCG (2 attendus)', v_pack));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'JOURNAL_POS et JOURNAL_PRODUCTION sont au catalogue', false, SQLERRM);
  PERFORM _rec('T02', 'le pack PCG mappe JOURNAL_POS → POS et JOURNAL_PRODUCTION → OF', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T03 — la résolution pour une société FR
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE t uuid; jp text; jf text;
BEGIN
  t := _mk_tenant('ROPS1');
  UPDATE tenants SET legislation_pack_code = 'FR' WHERE id = t;
  -- les journaux standard (POS, OF…) : une caisse ne peut pas poster sans eux,
  -- la clé étrangère (tenant_id, journal_code) l'exige.
  PERFORM ensure_standard_journals(t);
  SELECT resolve_journal(t, 'JOURNAL_POS')        INTO jp;
  SELECT resolve_journal(t, 'JOURNAL_PRODUCTION') INTO jf;
  PERFORM _rec('T03', 'société FR : JOURNAL_POS → POS et JOURNAL_PRODUCTION → OF',
    jp = 'POS' AND jf = 'OF',
    format('JOURNAL_POS=%s ; JOURNAL_PRODUCTION=%s', COALESCE(jp,'NULL'), COALESCE(jf,'NULL')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'société FR : JOURNAL_POS → POS et JOURNAL_PRODUCTION → OF', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T04 — le trigger de clôture POS passe par les rôles
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_src text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'post_pos_session_on_close_multi';

  PERFORM _rec('T04', 'la clôture POS demande ses rôles (journal, ventes, TVA) — plus de 707000',
    v_src LIKE '%resolve_journal%' AND v_src LIKE '%resolve_account%' AND v_src NOT LIKE '%''707000''%',
    format('resolve_journal=%s ; resolve_account=%s ; 707000 en dur=%s',
           v_src LIKE '%resolve_journal%', v_src LIKE '%resolve_account%', v_src LIKE '%''707000''%'));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'la clôture POS demande ses rôles (journal, ventes, TVA) — plus de 707000', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T05 — rejouable
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_av int; v_ap int;
BEGIN
  SELECT count(*) INTO v_av FROM journal_role_catalog;
  INSERT INTO journal_role_catalog (role, journal_type, required_for)
    VALUES ('JOURNAL_POS', 'cash', ARRAY['pos'])
  ON CONFLICT (role) DO NOTHING;
  SELECT count(*) INTO v_ap FROM journal_role_catalog;
  PERFORM _rec('T05', 'rejouable : un second chargement n''ajoute aucun rôle',
    v_av = v_ap, format('%s → %s rôle(s)', v_av, v_ap));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T05', 'rejouable : un second chargement n''ajoute aucun rôle', false, SQLERRM);
END $$;

SELECT _audit_assert('387');