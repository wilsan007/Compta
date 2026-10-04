-- ============================================================
-- ci/audit_registry_selftest.sql — la preuve d'AUD-X01 (vague W0.1)
--
-- CE QU'IL FAUT PROUVER. `ci/expected_failures.sql` est consulté par
-- `_audit_assert` à la fin de chaque fichier de test. Tant que le registre était
-- indexé sur `test_id` SEUL (`_audit_expected (test_id text PRIMARY KEY)`),
-- inscrire `T01` blanchissait le `T01` de **treize** fichiers — 227→234 et
-- 240→244 — y compris ceux qui étaient verts. Un défaut qui réapparaît dans un
-- fichier homonyme passait donc inaperçu : le registre, au lieu de rendre les
-- défauts visibles, les cachait.
--
-- CE QUE CE FICHIER FAIT. Il monte deux fichiers homonymes de toutes pièces
-- dans `_audit_results`, inscrit UN SEUL des deux au registre, et exige le
-- comportement suivant — c'est la falsification, au sens de §4.7 : réinstaller
-- la version fautive de la règle doit faire échouer ce fichier.
--
--   Z1  le `T01` ROUGE du fichier non inscrit          → `_audit_assert` LÈVE
--   Z2  le `T01` VERT du fichier inscrit               → `_audit_assert` LÈVE
--       (un défaut corrigé mais encore au registre casse la CI)
--   Z3  un fichier sans aucun verdict                  → `_audit_assert` LÈVE
--   Z4  rouge inscrit + vert non inscrit, dans le même → les deux passent
--       fichier
--
-- Avec l'ancienne clé (test_id seul), Z1 ne lève PAS : le `T01` du fichier B
-- blanchit celui du fichier A. C'est la contre-épreuve : remettre
-- `PRIMARY KEY (test_id)` dans `ci/audit_helpers.sql` et ce fichier échoue.
--
-- Exécution (job `db-integration`, après les migrations) :
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f sql/ci/audit_registry_selftest.sql
-- ============================================================

\set ON_ERROR_STOP on
\ir audit_helpers.sql

CREATE TEMP TABLE selftest_audit_x01 (id text PRIMARY KEY, ok boolean, attendu text);

-- Deux fichiers homonymes, et le registre qui n'en couvre qu'un.
DELETE FROM _audit_results WHERE file IN ('TST-A', 'TST-B', 'TST-D', 'TST-E');
DELETE FROM _audit_expected WHERE file IN ('TST-A', 'TST-B', 'TST-D', 'TST-E');

INSERT INTO _audit_results (file, test_id, label, ok, detail) VALUES
  ('TST-A', 'T01', 'rouge dans un fichier NON inscrit',  false, 'fixture AUD-X01'),
  ('TST-B', 'T01', 'vert dans un fichier inscrit',       true,  'fixture AUD-X01'),
  ('TST-D', 'T01', 'vert dans un fichier non inscrit',   true,  'fixture AUD-X01'),
  ('TST-E', 'T01', 'rouge dans un fichier inscrit',      false, 'fixture AUD-X01');

INSERT INTO _audit_expected (file, test_id, reason) VALUES
  ('TST-B', 'T01', 'fixture AUD-X01 — le T01 du fichier B est inscrit'),
  ('TST-E', 'T01', 'fixture AUD-X01 — défaut ouvert, connu');

-- ------------------------------------------------------------
-- Les quatre exigences. Chacune enregistre son verdict : un auto-test qui
-- s'arrête au premier échec ne dit pas ce qui est cassé.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION _selftest_lance(p_file text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_msg text;
BEGIN
  BEGIN
    PERFORM _audit_assert(p_file);
    RETURN NULL;                       -- aucune exception : le fichier est passé
  EXCEPTION WHEN OTHERS THEN
    RETURN SQLERRM;
  END;
END $$;

DO $$
DECLARE
  v_msg text;
BEGIN
  -- Z1 — le T01 du fichier A est ROUGE et n'est PAS inscrit : le T01 de B, lui
  -- inscrit, ne doit pas le blanchir.
  v_msg := _selftest_lance('TST-A');
  INSERT INTO selftest_audit_x01 VALUES ('Z1', v_msg IS NOT NULL AND v_msg LIKE '%T01%',
    format('attendu : échec « hors registre » pour TST-A → %s', coalesce(v_msg, 'AUCUNE ERREUR')));

  -- Z2 — le T01 du fichier B est VERT et il est inscrit : la CI doit exiger le
  -- retrait de la ligne du registre.
  v_msg := _selftest_lance('TST-B');
  INSERT INTO selftest_audit_x01 VALUES ('Z2', v_msg IS NOT NULL AND v_msg LIKE '%retirer%',
    format('attendu : échec « encore au registre » pour TST-B → %s', coalesce(v_msg, 'AUCUNE ERREUR')));

  -- Z3 — un fichier sans verdict ne prouve rien.
  v_msg := _selftest_lance('TST-ZZZ');
  INSERT INTO selftest_audit_x01 VALUES ('Z3', v_msg IS NOT NULL AND v_msg LIKE '%aucun verdict%',
    format('attendu : échec « aucun verdict » pour un fichier vide → %s', coalesce(v_msg, 'AUCUNE ERREUR')));

  -- Z4 — dans le même fichier, un rouge INSCRIT et un vert NON inscrit passent
  -- tous les deux : le registre blanchit le rouge, et rien d'autre.
  v_msg := _selftest_lance('TST-E');
  INSERT INTO selftest_audit_x01 VALUES ('Z4a', v_msg IS NULL,
    format('attendu : TST-E passe (rouge inscrit) → %s', coalesce(v_msg, 'OK')));
  v_msg := _selftest_lance('TST-D');
  INSERT INTO selftest_audit_x01 VALUES ('Z4b', v_msg IS NULL,
    format('attendu : TST-D passe (vert non inscrit) → %s', coalesce(v_msg, 'OK')));
END $$;

SELECT format('%s %s — %s', CASE WHEN ok THEN '✅' ELSE '❌' END, id, attendu) AS verdict
FROM selftest_audit_x01 ORDER BY id;

DO $$
DECLARE v_ko text;
BEGIN
  SELECT string_agg(id || ' (' || attendu || ')', ', ' ORDER BY id) INTO v_ko
  FROM selftest_audit_x01 WHERE NOT ok;
  IF v_ko IS NOT NULL THEN
    RAISE EXCEPTION '[AUD-X01] l''auto-test du registre a échoué : % — la clé du registre n''est plus le couple (fichier, identifiant)', v_ko;
  END IF;
  RAISE NOTICE '[AUD-X01] registre conforme : la clé (file, test_id) blanchit un test et un seul.';
END $$;

-- Nettoyage : le harnais ne doit rien laisser derrière lui.
DELETE FROM _audit_results WHERE file LIKE 'TST-%';
DELETE FROM _audit_expected WHERE file LIKE 'TST-%';
