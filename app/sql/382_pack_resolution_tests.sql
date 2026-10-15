-- ============================================================
-- 382_pack_resolution_tests.sql — LOT 1-A : la résolution héritée
--
--   T01  pack_lineage remonte la chaîne secteur → pays → référentiel ;
--   T02  pack_effective_value : le plus spécifique gagne, sinon on remonte ;
--   T03  pack_account_role : le plus profond gagne (et retombe sur la racine) ;
--   T04  pack_holidays_of : l'UNION de la lignée (le pays ajoute) ;
--   T05  v_pack_effective résout un pack réel (FR → EUR, DJ → DJF) ;
--   T06  tenant_pack_code rend le pack de la société.
--
-- Vu ROUGE avant la 382 : la fonction pack_lineage n'existait pas — les six
-- scénarios échouaient à l'appel.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '382', false);
DELETE FROM _audit_results WHERE file = '382';

-- Fixture : trois packs en ligne (référentiel ZZREF → pays ZZ → secteur ZZ-SEC).
-- (idempotence : on détache d'abord les sociétés, puis on efface d'éventuels restes)
UPDATE tenants SET legislation_pack_code = NULL WHERE legislation_pack_code IN ('ZZ-SEC', 'ZZ', 'ZZREF');
DELETE FROM legislation_packs WHERE code IN ('ZZ-SEC', 'ZZ', 'ZZREF');
INSERT INTO legislation_packs
  (code, name, country_code, country_name, accounting_standard, currency, tenant_id, level, parent_code)
VALUES
  ('ZZREF',  'Référentiel ZZ', NULL, 'Référentiel ZZ', 'ZZ', 'ZZZ', '00000000-0000-0000-0000-000000000001', 'referential', NULL),
  ('ZZ',     'Pays ZZ',        'ZZ', 'Pays ZZ',        'ZZ', 'ZZZ', '00000000-0000-0000-0000-000000000001', 'country',     'ZZREF'),
  ('ZZ-SEC', 'Secteur ZZ',     'ZZ', 'Pays ZZ',        'ZZ', 'ZZZ', '00000000-0000-0000-0000-000000000001', 'sector',      'ZZ');

-- ─────────────────────────────────────────────────────────────
-- T01 — la lignée
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_n int; v_0 text; v_1 text; v_2 text;
BEGIN
  SELECT count(*) INTO v_n FROM pack_lineage('ZZ-SEC');
  SELECT code INTO v_0 FROM pack_lineage('ZZ-SEC') WHERE depth = 0;
  SELECT code INTO v_1 FROM pack_lineage('ZZ-SEC') WHERE depth = 1;
  SELECT code INTO v_2 FROM pack_lineage('ZZ-SEC') WHERE depth = 2;
  PERFORM _rec('T01', 'pack_lineage remonte secteur → pays → référentiel (3 niveaux)',
    v_n = 3 AND v_0 = 'ZZ-SEC' AND v_1 = 'ZZ' AND v_2 = 'ZZREF',
    format('niveaux=%s ; [0]=%s [1]=%s [2]=%s', v_n, v_0, v_1, v_2));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'pack_lineage remonte secteur → pays → référentiel (3 niveaux)', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T02 — une valeur de format : le plus spécifique gagne
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_sec text; v_pays text;
BEGIN
  UPDATE legislation_packs SET locale = 'fr-FR' WHERE code = 'ZZREF';
  UPDATE legislation_packs SET locale = 'zz-ZZ' WHERE code = 'ZZ-SEC';

  SELECT pack_effective_value('ZZ-SEC', 'locale') INTO v_sec;   -- le plus profond
  SELECT pack_effective_value('ZZ',      'locale') INTO v_pays; -- retombe sur ZZREF

  PERFORM _rec('T02', 'pack_effective_value : le plus spécifique gagne, sinon on remonte la lignée',
    v_sec = 'zz-ZZ' AND v_pays = 'fr-FR',
    format('ZZ-SEC.local=%s (zz-ZZ attendu) ; ZZ.local=%s (fr-FR attendu)', v_sec, v_pays));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'pack_effective_value : le plus spécifique gagne, sinon on remonte la lignée', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T03 — un rôle de compte : le plus profond gagne
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_sec text; v_pays text;
BEGIN
  INSERT INTO pack_account_roles (pack_code, role, account_code) VALUES
    ('ZZREF', 'CLIENTS', '411000'), ('ZZ-SEC', 'CLIENTS', '411100')
  ON CONFLICT (pack_code, role) DO UPDATE SET account_code = EXCLUDED.account_code;

  SELECT pack_account_role('ZZ-SEC', 'CLIENTS') INTO v_sec;   -- le secteur gagne
  SELECT pack_account_role('ZZ',      'CLIENTS') INTO v_pays; -- retombe sur ZZREF

  PERFORM _rec('T03', 'pack_account_role : le plus profond gagne, sinon on remonte la lignée',
    v_sec = '411100' AND v_pays = '411000',
    format('ZZ-SEC=CLIENTS → %s (411100 attendu) ; ZZ=CLIENTS → %s (411000 attendu)', v_sec, v_pays));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'pack_account_role : le plus profond gagne, sinon on remonte la lignée', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T04 — les jours fériés : l'UNION de la lignée
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_n int;
BEGIN
  INSERT INTO pack_holidays (pack_code, holiday_date, label) VALUES
    ('ZZREF', DATE '2026-01-01', 'Jour de l''an'),
    ('ZZ',    DATE '2026-06-27', 'Indépendance')
  ON CONFLICT (pack_code, holiday_date) DO NOTHING;

  SELECT count(*) INTO v_n FROM pack_holidays_of('ZZ-SEC');
  PERFORM _rec('T04', 'pack_holidays_of : l''UNION de la lignée (le pays AJOUTE au référentiel)',
    v_n = 2, format('fériés de ZZ-SEC=%s (2 attendus : un du référentiel, un du pays)', v_n));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'pack_holidays_of : l''UNION de la lignée (le pays AJOUTE au référentiel)', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T05 — v_pack_effective résout un pack réel
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_fr text; v_dj text;
BEGIN
  SELECT currency INTO v_fr FROM v_pack_effective WHERE pack_code = 'FR';
  SELECT currency INTO v_dj FROM v_pack_effective WHERE pack_code = 'DJ';
  PERFORM _rec('T05', 'v_pack_effective résout un pack réel (FR → EUR, DJ → DJF)',
    v_fr = 'EUR' AND v_dj = 'DJF',
    format('FR devise=%s (EUR attendu) ; DJ devise=%s (DJF attendu)', v_fr, v_dj));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T05', 'v_pack_effective résout un pack réel (FR → EUR, DJ → DJF)', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T06 — tenant_pack_code
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE t uuid; v text;
BEGIN
  t := _mk_tenant('ZZRES');
  UPDATE tenants SET legislation_pack_code = 'ZZ' WHERE id = t;
  SELECT tenant_pack_code(t) INTO v;
  PERFORM _rec('T06', 'tenant_pack_code rend le pack de la société',
    v = 'ZZ', format('pack effectif=%s (ZZ attendu)', COALESCE(v, 'NULL')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T06', 'tenant_pack_code rend le pack de la société', false, SQLERRM);
END $$;

-- Nettoyage de la fixture : on DÉTACHE d'abord les sociétés qui pointaient un
-- pack de test (T06), puis on supprime la lignée (cascade sur rôles et fériés).
UPDATE tenants SET legislation_pack_code = NULL
 WHERE legislation_pack_code IN ('ZZ-SEC', 'ZZ', 'ZZREF');
DELETE FROM legislation_packs WHERE code IN ('ZZ-SEC', 'ZZ', 'ZZREF');

SELECT _audit_assert('382');
