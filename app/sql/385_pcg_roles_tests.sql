-- ============================================================
-- 385_pcg_roles_tests.sql — les rôles du pack PCG (le PCG en données)
--
--   T01  le référentiel PCG porte 65 rôles de comptes (67 moins les 2 « par
--        catégorie » : IMMOBILISATIONS, AMORTISSEMENTS) ;
--   T02  il porte 7 rôles de journaux (JOURNAL_PAIE volontairement absent) ;
--   T03  RECETTE LOC1-05 : société FR → resolve_account(…,'CLIENTS') = 411000 ;
--   T04  un pays hérite des rôles de son référentiel (FR → PCG) ;
--   T05  les deux rôles « par catégorie » ne sont PAS dans le pack (ctx oblige) ;
--   T06  rejouable : un second chargement n'ajoute rien.
--
-- Vu ROUGE avant la 385 : T01..T05 (aucun rôle mappé → ROLE_NON_MAPPE). T06 sans objet.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '385', false);
DELETE FROM _audit_results WHERE file = '385';

-- ─────────────────────────────────────────────────────────────
-- T01 / T02 — le compte des rôles du référentiel PCG
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_cpt int; v_jrn int;
BEGIN
  SELECT count(*) INTO v_cpt FROM pack_account_roles WHERE pack_code = 'PCG';
  SELECT count(*) INTO v_jrn FROM pack_journal_roles WHERE pack_code = 'PCG';
  PERFORM _rec('T01', 'le référentiel PCG porte 65 rôles de comptes (67 moins IMMOBILISATIONS et AMORTISSEMENTS)',
    v_cpt = 65, format('%s rôle(s) de comptes (65 attendus)', v_cpt));
  PERFORM _rec('T02', 'le référentiel PCG porte 7 rôles de journaux (JOURNAL_PAIE absent)',
    v_jrn = 7, format('%s rôle(s) de journaux (7 attendus)', v_jrn));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'le référentiel PCG porte 65 rôles de comptes (67 moins IMMOBILISATIONS et AMORTISSEMENTS)', false, SQLERRM);
  PERFORM _rec('T02', 'le référentiel PCG porte 7 rôles de journaux (JOURNAL_PAIE absent)', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T03 — RECETTE LOC1-05 : société FR → CLIENTS = 411000
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE t uuid; v text;
BEGIN
  t := _mk_tenant('PCGR1');
  UPDATE tenants SET legislation_pack_code = 'FR' WHERE id = t;
  SELECT resolve_account(t, 'CLIENTS') INTO v;
  PERFORM _rec('T03', 'société FR : resolve_account(…,''CLIENTS'') = 411000',
    v = '411000', format('compte=%s (411000 attendu)', COALESCE(v, 'NULL')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'société FR : resolve_account(…,''CLIENTS'') = 411000', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T04 — un pays hérite des rôles de son référentiel
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v text;
BEGIN
  SELECT pack_account_role('FR', 'CLIENTS') INTO v;     -- FR → PCG
  PERFORM _rec('T04', 'un pays hérite des rôles de son référentiel (FR → PCG → 411000)',
    v = '411000', format('pack_account_role(FR, CLIENTS)=%s (411000 attendu)', COALESCE(v, 'NULL')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'un pays hérite des rôles de son référentiel (FR → PCG → 411000)', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T05 — les deux rôles « par catégorie » ne sont PAS dans le pack
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE a text; b text;
BEGIN
  SELECT pack_account_role('FR', 'IMMOBILISATIONS') INTO a;
  SELECT pack_account_role('FR', 'AMORTISSEMENTS')  INTO b;
  PERFORM _rec('T05', 'IMMOBILISATIONS et AMORTISSEMENTS ne sont PAS mappés par le pack (ils se résolvent par catégorie)',
    a IS NULL AND b IS NULL, format('IMMOBILISATIONS=%s ; AMORTISSEMENTS=%s (NULL attendus)',
      COALESCE(a, 'NULL'), COALESCE(b, 'NULL')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T05', 'IMMOBILISATIONS et AMORTISSEMENTS ne sont PAS mappés par le pack (ils se résolvent par catégorie)', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T06 — rejouable
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_av int; v_ap int;
BEGIN
  SELECT count(*) INTO v_av FROM pack_account_roles WHERE pack_code = 'PCG';
  INSERT INTO pack_account_roles (pack_code, role, account_code)
    VALUES ('PCG', 'CLIENTS', '411000')
  ON CONFLICT (pack_code, role) DO NOTHING;
  SELECT count(*) INTO v_ap FROM pack_account_roles WHERE pack_code = 'PCG';
  PERFORM _rec('T06', 'rejouable : un second chargement n''ajoute aucun rôle',
    v_av = v_ap AND v_ap = 65, format('%s → %s rôle(s)', v_av, v_ap));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T06', 'rejouable : un second chargement n''ajoute aucun rôle', false, SQLERRM);
END $$;

SELECT _audit_assert('385');